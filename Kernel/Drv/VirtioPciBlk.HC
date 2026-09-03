// VirtioPciBlk.HC — modern virtio-pci blk client (QEMU virt + virtio-blk-pci).
// LBA read/write via ECAM + common/notify caps. Dig-down: VirtioPciBlkReadLba;
// BlkDev MMIO→PCI: VirtioBlkInit falls back here when no mmio slot.
#ifndef RV_DRV_VIRTIO_PCI_BLK_HC
#define RV_DRV_VIRTIO_PCI_BLK_HC
#include "VirtioPci.HC"
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
// PCI blk scratch away from mmio blk/net/input/9p arenas.
#define VPCI_BLK_VQ     (CONFIG_VIRTIO_DRV_RAM_BASE+0x400000)
#define VPCI_BLK_HDR    (CONFIG_VIRTIO_DRV_RAM_BASE+0x404000)
#define VPCI_BLK_STAT   (CONFIG_VIRTIO_DRV_RAM_BASE+0x404100)
#define VPCI_BLK_QSZ    8
#define VDESC_F_NEXT    1
#define VDESC_F_WRITE   2
#define VBLK_T_IN       0
#define VBLK_T_OUT      1
I64 virtio_pci_blk_bdf;
I64 virtio_pci_blk_fail;
U8 *virtio_pci_blk_common;
U8 *virtio_pci_blk_notify;
U8 *virtio_pci_blk_devcfg;
U8 *virtio_pci_blk_isr;
U32 virtio_pci_blk_notify_mult;
U16 virtio_pci_blk_qsz;
U16 virtio_pci_blk_q_notify_off;
U32 virtio_pci_blk_avail_off;
U32 virtio_pci_blk_used_off;
U16 virtio_pci_blk_avail_idx;
I64 VirtioPciBlkPresent()
{
  return virtio_pci_blk_bdf >= 0 && virtio_pci_blk_common != 0;
}

I64 VirtioPciBlkInit()
{
  I64 bdf;
  U64 bars[6];
  U8 *common, *notify, *devcfg, *isr;
  U32 nmult;
  U8 st;
  U16 qsz;
  I64 avail_off, used_off;
  virtio_pci_blk_fail = 0;
  virtio_pci_blk_bdf = -1;
  virtio_pci_blk_common = 0;
  virtio_pci_blk_notify = 0;
  virtio_pci_blk_devcfg = 0;
  virtio_pci_blk_isr = 0;
  virtio_pci_blk_avail_idx = 0;
  if (!RVVirtioPciEnabled()) {
    virtio_pci_blk_fail = 1;
    return -1;
  }
  bdf = VirtioPciFindBlk();
  if (bdf < 0) {
    virtio_pci_blk_fail = 2;
    return -1;
  }
  VirtioPciEnableBm(bdf);
  VirtioPciAssignBar4(bdf);
  VirtioPciFillBars(bdf, bars);
  if (VirtioPciParseCapsEx(bdf, bars, &common, &notify, &nmult, &devcfg, &isr)) {
    virtio_pci_blk_fail = 3;
    return -1;
  }
  OutU8(common + VPCI_COMMON_STATUS, 0);
  OutU8(common + VPCI_COMMON_STATUS, VPCI_S_ACK);
  OutU8(common + VPCI_COMMON_STATUS, VPCI_S_ACK | VPCI_S_DRIVER);
  OutU32(common + VPCI_COMMON_GFSELECT, 0);
  OutU32(common + VPCI_COMMON_GF, 0);
  OutU32(common + VPCI_COMMON_GFSELECT, 1);
  OutU32(common + VPCI_COMMON_GF, 1);
  VirtioPciMsixDisable(bdf);
  VirtioPciSetNoMsix(common);
  VirtioPciEnableIntx(bdf);
  st = VPCI_S_ACK | VPCI_S_DRIVER | VPCI_S_FEATURES_OK;
  OutU8(common + VPCI_COMMON_STATUS, st);
  st = InU8(common + VPCI_COMMON_STATUS);
  if (!(st & VPCI_S_FEATURES_OK) || (st & VPCI_S_FAILED)) {
    virtio_pci_blk_fail = 4;
    return -1;
  }
  OutU16(common + VPCI_COMMON_Q_SELECT, 0);
  qsz = InU16(common + VPCI_COMMON_Q_SIZE);
  if (qsz < 3) {
    virtio_pci_blk_fail = 5;
    return -1;
  }
  if (qsz > VPCI_BLK_QSZ)
    qsz = VPCI_BLK_QSZ;
  OutU16(common + VPCI_COMMON_Q_SIZE, qsz);
  avail_off = (qsz * 16 + 1) & ~1;
  used_off = (avail_off + 6 + 2 * qsz + 3) & ~3;
  MemSet(VPCI_BLK_VQ, 0, 16384);
  MemSet(VPCI_BLK_HDR, 0, 64);
  MemSet(VPCI_BLK_STAT, 0, 64);
  OutU32(common + VPCI_COMMON_Q_DESC, VPCI_BLK_VQ);
  OutU32(common + VPCI_COMMON_Q_DESC + 4, 0);
  OutU32(common + VPCI_COMMON_Q_AVAIL, VPCI_BLK_VQ + avail_off);
  OutU32(common + VPCI_COMMON_Q_AVAIL + 4, 0);
  OutU32(common + VPCI_COMMON_Q_USED, VPCI_BLK_VQ + used_off);
  OutU32(common + VPCI_COMMON_Q_USED + 4, 0);
  VirtioPciQueueNoMsix(common);
  OutU16(common + VPCI_COMMON_Q_ENABLE, 1);
  virtio_pci_blk_q_notify_off = InU16(common + VPCI_COMMON_Q_NOTIFY);
  virtio_pci_blk_qsz = qsz;
  virtio_pci_blk_avail_off = avail_off;
  virtio_pci_blk_used_off = used_off;
  virtio_pci_blk_notify_mult = nmult;
  st = st | VPCI_S_DRIVER_OK;
  OutU8(common + VPCI_COMMON_STATUS, st);
  if (InU8(common + VPCI_COMMON_STATUS) & VPCI_S_FAILED) {
    virtio_pci_blk_fail = 7;
    return -1;
  }
  virtio_pci_blk_bdf = bdf;
  virtio_pci_blk_common = common;
  virtio_pci_blk_notify = notify;
  virtio_pci_blk_devcfg = devcfg;
  virtio_pci_blk_isr = isr;
  return 0;
}

I64 VirtioPciBlkReq(I64 type, I64 lba, U8 *buf)
{
  U8 *notify, *avail, *used, *p;
  U16 qsz, old_idx, aidx;
  I64 spin;
  if (!VirtioPciBlkPresent())
    if (VirtioPciBlkInit())
      return -1;
  // Raw hdr (avoid class layout quirks).
  *(U32 *)VPCI_BLK_HDR = type;
  *(U32 *)(VPCI_BLK_HDR + 4) = 0;
  *(U64 *)(VPCI_BLK_HDR + 8) = lba;
  *(U8 *)VPCI_BLK_STAT = 0xFF;
  if (type == VBLK_T_IN)
    MemSet(buf, 0, 512);
  p = VPCI_BLK_VQ;
  *(U64 *)p = VPCI_BLK_HDR;
  *(U32 *)(p + 8) = 16;
  *(U16 *)(p + 12) = VDESC_F_NEXT;
  *(U16 *)(p + 14) = 1;
  p = VPCI_BLK_VQ + 16;
  *(U64 *)p = buf;
  *(U32 *)(p + 8) = 512;
  if (type == VBLK_T_IN)
    *(U16 *)(p + 12) = VDESC_F_WRITE | VDESC_F_NEXT;
  else
    *(U16 *)(p + 12) = VDESC_F_NEXT;
  *(U16 *)(p + 14) = 2;
  p = VPCI_BLK_VQ + 32;
  *(U64 *)p = VPCI_BLK_STAT;
  *(U32 *)(p + 8) = 1;
  *(U16 *)(p + 12) = VDESC_F_WRITE;
  *(U16 *)(p + 14) = 0;
  qsz = virtio_pci_blk_qsz;
  avail = VPCI_BLK_VQ + virtio_pci_blk_avail_off;
  used = VPCI_BLK_VQ + virtio_pci_blk_used_off;
  notify = virtio_pci_blk_notify;
  old_idx = InU16(used + 2);
  aidx = virtio_pci_blk_avail_idx;
  OutU16(avail, 0);
  OutU16(avail + 4 + 2 * (aidx % qsz), 0);
  OutU16(avail + 2, aidx + 1);
  virtio_pci_blk_avail_idx = aidx + 1;
  // Fence before notify (same as NinePVirtioPci).
  InU8(virtio_pci_blk_common + VPCI_COMMON_STATUS);
  OutU16(notify + virtio_pci_blk_q_notify_off *virtio_pci_blk_notify_mult, 0);
  for (spin = 0; spin < 20000000; spin++)
    if (InU16(used + 2) != old_idx)
      break;
  if (InU16(used + 2) == old_idx) {
    virtio_pci_blk_fail = 8;
    return -1;
  }
  if (*(U8 *)VPCI_BLK_STAT) {
    virtio_pci_blk_fail = 9;
    return -1;
  }
  return 0;
}

I64 VirtioPciBlkReadLba(U8 *buf, I64 lba)
{
  return VirtioPciBlkReq(VBLK_T_IN, lba, buf);
}

I64 VirtioPciBlkWriteLba(U8 *buf, I64 lba)
{
  return VirtioPciBlkReq(VBLK_T_OUT, lba, buf);
}

I64 VirtioPciBlkCapacity()
{
  U32 lo, hi;
  if (!VirtioPciBlkPresent())
    if (VirtioPciBlkInit())
      return 0;
  if (!virtio_pci_blk_devcfg)
    return 0;
  lo = InU32(virtio_pci_blk_devcfg);
  hi = InU32(virtio_pci_blk_devcfg + 4);
  return lo | (hi << 32);
}

I64 VirtioPciBlkReadSector0(U8 *buf)
{
  return VirtioPciBlkReadLba(buf, 0);
}

I64 VirtioPciBlkIrqNum()
{
  if (!VirtioPciBlkPresent())
    return -1;
  return VirtioPciIrqNum(virtio_pci_blk_bdf);
}

U0 VirtioPciBlkIrqAck()
{
  VirtioPciIsrAck(virtio_pci_blk_isr);
}

I64 VirtioPciBlkIrqInit()
{
  I64 irq;
  irq = VirtioPciBlkIrqNum();
  if (irq < 0)
    return -1;
  VirtioPciBlkIrqAck();
  if (virtio_pci_blk_isr)
    RVVirtioPciIsrReg(virtio_pci_blk_isr);
  RVPlicEnable(irq, 1);
  RVPlicSetThreshold(0);
  RvSetMEIE();
  return irq;
}

I64 VirtioPciBlkIrqService()
{
  //Sync poll path: ACK ISR so INTx can re-assert; no async request queue yet.
  if (!VirtioPciBlkPresent())
    return 0;
  return VirtioPciIsrAck(virtio_pci_blk_isr);
}
#endif
