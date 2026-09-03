// VirtioBalloon.HC — legacy virtio-mmio balloon (DeviceID 5).
// Inflate/deflate PFN lists. Dig-down: Man("VirtioBalloon"); VirtioBalloonInit;
#ifndef RV_DRV_VIRTIO_BALLOON_HC
#define RV_DRV_VIRTIO_BALLOON_HC
#define VBAL_MAGIC        0x74726976
#define VBAL_ID_BALLOON   5
#define VMR_MAGIC         0x00
#define VMR_DEVICE_ID     0x08
#define VMR_DRIVER_FEAT   0x20
#define VMR_DRIVER_FEATSEL 0x24
#define VMR_GUEST_PGSZ    0x28
#define VMR_QUEUE_SEL     0x30
#define VMR_QUEUE_NUM     0x38
#define VMR_QUEUE_ALIGN   0x3c
#define VMR_QUEUE_PFN     0x40
#define VMR_QUEUE_NOTIFY  0x50
#define VMR_INTERRUPT_STATUS 0x60
#define VMR_INTERRUPT_ACK 0x64
#define VMR_STATUS        0x70
#define VSTAT_ACK         1
#define VSTAT_DRIVER      2
#define VSTAT_DRIVER_OK   4
#define VBAL_QSZ          8
#define VDESC_F_WRITE     2
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
#ifndef CONFIG_VIRTIO_MMIO_IRQ_BASE
#define CONFIG_VIRTIO_MMIO_IRQ_BASE 0x10000000
#endif
// Driver RAM: balloon @ +0x800000.
#define VBAL_INF_VQ       (CONFIG_VIRTIO_DRV_RAM_BASE+0x800000)
#define VBAL_DEF_VQ       (CONFIG_VIRTIO_DRV_RAM_BASE+0x802000)
#define VBAL_PFN_LIST     (CONFIG_VIRTIO_DRV_RAM_BASE+0x804000)
#define VBAL_PAGE_POOL    (CONFIG_VIRTIO_DRV_RAM_BASE+0x810000)
#define VBAL_POOL_PAGES   4
class CVbalDesc
{
  U64 addr;
  U32 len;
  U16 flags;
  U16 next;
};

class CVbalAvail
{
  U16 flags;
  U16 idx;
  U16 ring[VBAL_QSZ];
  U16 used_ev;
};

class CVbalUsedElem
{
  U32 id;
  U32 len;
};

class CVbalUsed
{
  U16 flags;
  U16 idx;
  CVbalUsedElem ring[VBAL_QSZ];
  U16 avail_ev;
};
I64 virtio_balloon_base;
I64 virtio_balloon_inflated;
I64 VirtioBalloonFind()
{
  I64 base, stride, count, i, slot;
  U8 *r;
  if (!RVVirtioMmioEnabled())
    return 0;
  base = RVVirtioMmioBase();
  stride = RVVirtioMmioStride();
  count = RVVirtioMmioCount();
  if (!base || !stride || count <= 0)
    return 0;
  for (i = 0; i < count; i++) {
    slot = base + i *stride;
    r = slot;
    if (InU32(r + VMR_MAGIC) == VBAL_MAGIC && InU32(r + VMR_DEVICE_ID) == VBAL_ID_BALLOON)
      return slot;
  }
  return 0;
}

U0 VirtioBalloonSetupQueue(U8 *r, I64 qsel, I64 pfn)
{
  OutU32(r + VMR_QUEUE_SEL, qsel);
  OutU32(r + VMR_QUEUE_NUM, VBAL_QSZ);
  OutU32(r + VMR_QUEUE_ALIGN, 4096);
  OutU32(r + VMR_QUEUE_PFN, pfn >> 12);
}

I64 VirtioBalloonInit()
{
  U8 *r;
  virtio_balloon_base = VirtioBalloonFind();
  if (!virtio_balloon_base)
    return -1;
  r = virtio_balloon_base;
  MemSet(VBAL_INF_VQ, 0, 8192);
  MemSet(VBAL_DEF_VQ, 0, 8192);
  MemSet(VBAL_PFN_LIST, 0, 64);
  MemSet(VBAL_PAGE_POOL, 0, VBAL_POOL_PAGES * 4096);
  OutU32(r + VMR_STATUS, 0);
  OutU32(r + VMR_STATUS, VSTAT_ACK);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER);
  OutU32(r + VMR_DRIVER_FEATSEL, 0);
  OutU32(r + VMR_DRIVER_FEAT, 0);
  OutU32(r + VMR_GUEST_PGSZ, 4096);
  VirtioBalloonSetupQueue(r, 0, VBAL_INF_VQ);
  VirtioBalloonSetupQueue(r, 1, VBAL_DEF_VQ);
  virtio_balloon_inflated = 0;
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER | VSTAT_DRIVER_OK);
  return 0;
}

I64 VirtioBalloonIrqNum()
{
  if (!virtio_balloon_base)
    return -1;
  return (virtio_balloon_base - CONFIG_VIRTIO_MMIO_IRQ_BASE) >> 12;
}

U0 VirtioBalloonIrqAck()
{
  U8 *r = virtio_balloon_base;
  U32 st;
  if (!r)
    return;
  st = InU32(r + VMR_INTERRUPT_STATUS);
  if (st)
    OutU32(r + VMR_INTERRUPT_ACK, st);
}

I64 VirtioBalloonIrqInit()
{
  I64 irq;
  irq = VirtioBalloonIrqNum();
  if (irq < 0)
    return -1;
  VirtioBalloonIrqAck();
  RVPlicEnable(irq, 1);
  RVPlicSetThreshold(0);
  RvSetMEIE();
  return irq;
}

I64 VirtioBalloonKick(I64 qsel, I64 vq, I64 npages)
{
  U8 *r = virtio_balloon_base;
  CVbalDesc *desc;
  CVbalAvail *avail;
  CVbalUsed *used;
  U32 *pfns = VBAL_PFN_LIST;
  U16 uidx0;
  I64 i, spin;
  if (!r || npages <= 0 || npages > VBAL_POOL_PAGES)
    return -1;
  for (i = 0; i < npages; i++)
    pfns[i] = (VBAL_PAGE_POOL + i * 4096) >> 12;
  desc = vq;
  avail = vq + 128;
  used = vq + 4096;
  desc[0].addr = VBAL_PFN_LIST;
  desc[0].len = npages * 4;
  desc[0].flags = 0;
  desc[0].next = 0;
  uidx0 = used->idx;
  avail->ring[avail->idx % VBAL_QSZ] = 0;
  avail->idx = avail->idx + 1;
  OutU32(r + VMR_QUEUE_SEL, qsel);
  OutU32(r + VMR_QUEUE_NOTIFY, qsel);
  for (spin = 0; spin < 20000000; spin++)
    if (used->idx != uidx0)
      break;
  if (used->idx == uidx0)
    return -1;
  VirtioBalloonIrqAck();
  return 0;
}

I64 VirtioBalloonInflate(I64 npages)
{
  if (VirtioBalloonKick(0, VBAL_INF_VQ, npages))
    return -1;
  virtio_balloon_inflated += npages;
  return 0;
}

I64 VirtioBalloonDeflate(I64 npages)
{
  if (VirtioBalloonKick(1, VBAL_DEF_VQ, npages))
    return -1;
  if (virtio_balloon_inflated >= npages)
    virtio_balloon_inflated -= npages;
  else
    virtio_balloon_inflated = 0;
  return 0;
}

I64 VirtioBalloonNumPages()
{
  //Config space actual pages (legacy offset 0x100): num_pages / actual.
  U8 *r = virtio_balloon_base;
  if (!r)
    return 0;
  return InU32(r + 0x104);
}

I64 VirtioBalloonSelfTest()
{
  if (VirtioBalloonInit())
    return -1;
  if (VirtioBalloonInflate(1))
    return -1;
  if (VirtioBalloonDeflate(1))
    return -1;
  return 0;
}
#endif
