// NinePVirtioMmio.HC — 9P transport over legacy virtio-mmio (DeviceID 9, single virtqueue).
#ifndef NINEP_VIRTIO_MMIO_HC
#define NINEP_VIRTIO_MMIO_HC
#include "../NineP/NineP.HH"
#include "../NineP/NinePCodec.HC"
#define V9P_MMIO_MAGIC    0x74726976
#define V9P_MMIO_ID       9
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
#define VMR_STATUS        0x70
#define VSTAT_ACK         1
#define VSTAT_DRIVER      2
#define VSTAT_DRIVER_OK   4
#define V9P_QSZ           8
#define VDESC_F_NEXT      1
#define VDESC_F_WRITE     2
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
#define V9P_VQ            (CONFIG_VIRTIO_DRV_RAM_BASE+0x300000)
#define V9P_REQ_MSG       (CONFIG_VIRTIO_DRV_RAM_BASE+0x302000)
#define V9P_RSP_MSG       (CONFIG_VIRTIO_DRV_RAM_BASE+0x304000)
class CV9pMmioDesc
{
  U64 addr;
  U32 len;
  U16 flags;
  U16 next;
};

class CV9pMmioAvail
{
  U16 flags;
  U16 idx;
  U16 ring[V9P_QSZ];
  U16 used_ev;
};

class CV9pMmioUsedElem
{
  U32 id;
  U32 len;
};

class CV9pMmioUsed
{
  U16 flags;
  U16 idx;
  CV9pMmioUsedElem ring[V9P_QSZ];
  U16 avail_ev;
};
I64 ninep_mmio_base;
U16 ninep_mmio_avail_idx;
CV9pMmioDesc ninep_mmio_desc_tmp[2];
CV9pMmioAvail ninep_mmio_avail_tmp;
U8 *NinePVirtioMmioReq()
{
  return V9P_REQ_MSG;
}

U8 *NinePVirtioMmioRsp()
{
  return V9P_RSP_MSG;
}

I64 NinePVirtioMmioFind()
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
    if (InU32(r + VMR_MAGIC) == V9P_MMIO_MAGIC && InU32(r + VMR_DEVICE_ID) == V9P_MMIO_ID)
      return slot;
  }
  return 0;
}

U0 NinePVirtioMmioSetupQueue(U8 *r, I64 pfn)
{
  OutU32(r + VMR_QUEUE_SEL, 0);
  OutU32(r + VMR_QUEUE_NUM, V9P_QSZ);
  OutU32(r + VMR_QUEUE_ALIGN, 4096);
  OutU32(r + VMR_QUEUE_PFN, pfn >> 12);
}

I64 NinePVirtioMmioInit()
{
  U8 *r;
  ninep_mmio_base = NinePVirtioMmioFind();
  if (!ninep_mmio_base)
    return -1;
  r = ninep_mmio_base;
  ninep_mmio_avail_idx = 0;
  MemSet(V9P_VQ, 0, 8192);
  MemSet(V9P_REQ_MSG, 0, P9_MSIZE_DEFAULT);
  MemSet(V9P_RSP_MSG, 0, P9_MSIZE_DEFAULT);
  OutU32(r + VMR_STATUS, 0);
  OutU32(r + VMR_STATUS, VSTAT_ACK);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER);
  OutU32(r + VMR_DRIVER_FEATSEL, 0);
  OutU32(r + VMR_DRIVER_FEAT, 0);
  OutU32(r + VMR_GUEST_PGSZ, 4096);
  NinePVirtioMmioSetupQueue(r, V9P_VQ);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER | VSTAT_DRIVER_OK);
  return 0;
}

I64 NinePVirtioMmioSendRecv(I64 req_len)
{
  U8 *r;
  U16 uidx0, aidx;
  I64 spin, pad;
  if (!ninep_mmio_base || req_len <= 0 || req_len > P9_MSIZE_DEFAULT)
    return -1;
  pad = req_len;
  if (pad & 3)
    pad = pad + 4 - (pad & 3);
  r = ninep_mmio_base;
  MemSet(V9P_RSP_MSG, 0, 4096);
  ninep_mmio_desc_tmp[0].addr = V9P_REQ_MSG;
  ninep_mmio_desc_tmp[0].len = pad;
  ninep_mmio_desc_tmp[0].flags = VDESC_F_NEXT;
  ninep_mmio_desc_tmp[0].next = 1;
  ninep_mmio_desc_tmp[1].addr = V9P_RSP_MSG;
  ninep_mmio_desc_tmp[1].len = 4096;
  ninep_mmio_desc_tmp[1].flags = VDESC_F_WRITE;
  ninep_mmio_desc_tmp[1].next = 0;
  MemCpy(V9P_VQ, ninep_mmio_desc_tmp, 32);
  aidx = ninep_mmio_avail_idx;
  ninep_mmio_avail_tmp.flags = 0;
  ninep_mmio_avail_tmp.idx = aidx + 1;
  ninep_mmio_avail_tmp.ring[aidx % V9P_QSZ] = 0;
  ninep_mmio_avail_tmp.used_ev = 0;
  MemCpy(V9P_VQ + 128, &ninep_mmio_avail_tmp, 20);
  ninep_mmio_avail_idx = aidx + 1;
  // Ensure avail is visible before sampling used / notifying.
  uidx0 = InU16(V9P_VQ + 4098);
  InU32(r + VMR_STATUS);
  OutU32(r + VMR_QUEUE_NOTIFY, 0);
  for (spin = 0; spin < 200000000; spin++)
    if (InU16(V9P_VQ + 4098) != uidx0)
      break;
  if (InU16(V9P_VQ + 4098) == uidx0)
    return -2;
  return NinePGetU32(V9P_RSP_MSG, 0);
}

I64 NinePVirtioMmioMountTag(U8 *buf, I64 cap)
{
  U8 *r;
  U16 n, i;
  if (!ninep_mmio_base || !buf || cap <= 0)
    return -1;
  r = ninep_mmio_base;
  n = InU32(r + 0x100) & 0xFFFF;
  if (n <= 0 || n >= cap)
    return -2;
  for (i = 0; i < n; i++)
    buf[i] = *(U8 *)(r + 0x102 + i);
  buf[n] = 0;
  return n;
}
#endif
