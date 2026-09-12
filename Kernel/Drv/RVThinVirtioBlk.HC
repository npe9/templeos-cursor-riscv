// RVThinVirtioBlk.HC — G9 legacy chicken-egg: legacy virtio-mmio blk only.
// Used when RV_THIN_EMBED_BIN is unset. Default thin smoke embeds Kernel.BIN
// @0x81000000 and skips this file; SoftCall re-Inits + owns first RedSea mount.
#ifndef RV_THIN_VIRTIO_BLK_HC
#define RV_THIN_VIRTIO_BLK_HC
#ifndef CONFIG_VIRTIO_MMIO_BASE
#define CONFIG_VIRTIO_MMIO_BASE 0x10001000
#endif
#ifndef CONFIG_VIRTIO_MMIO_STRIDE
#define CONFIG_VIRTIO_MMIO_STRIDE 0x1000
#endif
#ifndef CONFIG_VIRTIO_MMIO_COUNT
#define CONFIG_VIRTIO_MMIO_COUNT 8
#endif
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
#define VIRTIO_MMIO_LO    CONFIG_VIRTIO_MMIO_BASE
#define VIRTIO_MMIO_HI    (CONFIG_VIRTIO_MMIO_BASE+(CONFIG_VIRTIO_MMIO_COUNT-1)*CONFIG_VIRTIO_MMIO_STRIDE)
#define VIRTIO_MAGIC      0x74726976
#define VIRTIO_ID_BLOCK   2
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
#define VBLK_QSZ          8
#define VDESC_F_NEXT      1
#define VDESC_F_WRITE     2
#define VBLK_T_IN         0
#define VBLK_T_OUT        1
#define VBLK_VQ           CONFIG_VIRTIO_DRV_RAM_BASE
#define VBLK_HDR          (CONFIG_VIRTIO_DRV_RAM_BASE+0x20000)
#define VBLK_STAT         (CONFIG_VIRTIO_DRV_RAM_BASE+0x21000)
#define VBLK_KIND_NONE  0
#define VBLK_KIND_MMIO  1
class CVioDesc
{
  U64 addr;
  U32 len;
  U16 flags;
  U16 next;
};

class CVioAvail
{
  U16 flags;
  U16 idx;
  U16 ring[VBLK_QSZ];
  U16 used_ev;
};

class CVioUsedElem
{
  U32 id;
  U32 len;
};

class CVioUsed
{
  U16 flags;
  U16 idx;
  CVioUsedElem ring[VBLK_QSZ];
  U16 avail_ev;
};

class CVioBlkReq
{
  U32 type;
  U32 rsvd;
  U64 sector;
};
I64 virtio_blk_base;
I64 virtio_blk_kind;
I64 VirtioBlkFind()
{
  I64 slot;
  if (!RVVirtioMmioEnabled())
    return 0;
  for (slot = VIRTIO_MMIO_LO; slot <= VIRTIO_MMIO_HI; slot += CONFIG_VIRTIO_MMIO_STRIDE) {
    U8 *r = slot;
    if (InU32(r + VMR_MAGIC) == VIRTIO_MAGIC && InU32(r + VMR_DEVICE_ID) == VIRTIO_ID_BLOCK)
      return slot;
  }
  return 0;
}
// MMIO-only bring-up. Returns 0 on success, -1 if no virtio-blk-mmio.
I64 VirtioBlkInit()
{
  U8 *r;
  virtio_blk_kind = VBLK_KIND_NONE;
  virtio_blk_base = VirtioBlkFind();
  if (!virtio_blk_base)
    return -1;
  r = virtio_blk_base;
  MemSet(VBLK_VQ, 0, 8192);
  OutU32(r + VMR_STATUS, 0);
  OutU32(r + VMR_STATUS, VSTAT_ACK);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER);
  OutU32(r + VMR_DRIVER_FEATSEL, 0);
  OutU32(r + VMR_DRIVER_FEAT, 0);
  OutU32(r + VMR_GUEST_PGSZ, 4096);
  OutU32(r + VMR_QUEUE_SEL, 0);
  OutU32(r + VMR_QUEUE_NUM, VBLK_QSZ);
  OutU32(r + VMR_QUEUE_ALIGN, 4096);
  OutU32(r + VMR_QUEUE_PFN, VBLK_VQ >> 12);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER | VSTAT_DRIVER_OK);
  virtio_blk_kind = VBLK_KIND_MMIO;
  return 0;
}

I64 VirtioBlkReq(I64 type, I64 sector, U8 *buf)
{
  U8 *r = virtio_blk_base;
  CVioDesc *desc = VBLK_VQ;
  CVioAvail *avail = VBLK_VQ + 128;
  CVioUsed *used = VBLK_VQ + 4096;
  CVioBlkReq *hdr = VBLK_HDR;
  U8 *statp = VBLK_STAT;
  U16 uidx0;
  I64 spin;
  if (!virtio_blk_base)
    return -1;
  hdr->type = type;
  hdr->rsvd = 0;
  hdr->sector = sector;
  *statp = 0xFF;
  desc[0].addr = VBLK_HDR;
  desc[0].len = 16;
  desc[0].flags = VDESC_F_NEXT;
  desc[0].next = 1;
  desc[1].addr = buf;
  desc[1].len = 512;
  if (type == VBLK_T_IN)
    desc[1].flags = VDESC_F_NEXT | VDESC_F_WRITE;
  else
    desc[1].flags = VDESC_F_NEXT;
  desc[1].next = 2;
  desc[2].addr = VBLK_STAT;
  desc[2].len = 1;
  desc[2].flags = VDESC_F_WRITE;
  desc[2].next = 0;
  uidx0 = used->idx;
  avail->ring[0] = 0;
  avail->idx = avail->idx + 1;
  OutU32(r + VMR_QUEUE_NOTIFY, 0);
  for (spin = 0; spin < 200000000; spin++)
    if (used->idx != uidx0)
      break;
  return *statp;
}

I64 VirtioBlkRead(I64 sector, U8 *buf)
{
  return VirtioBlkReq(VBLK_T_IN, sector, buf);
}

I64 VirtioBlkWrite(I64 sector, U8 *buf)
{
  return VirtioBlkReq(VBLK_T_OUT, sector, buf);
}

I64 VirtioBlkCapacity()
{
  U8 *r = virtio_blk_base;
  U64 lo, hi;
  if (!virtio_blk_base)
    return 0;
  lo = InU32(r + 0x100);
  hi = InU32(r + 0x104);
  return lo | (hi << 32);
}
#endif
