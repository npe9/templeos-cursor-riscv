// NinePVirtioPci.HC — virtio-pci 9p transport (ECAM + modern queue SendRecv).
// Dig-down: NinePVirtioPciInit; NinePVirtioPciSendRecv; Virtio9pConnect (MMIO→PCI).
#ifndef NINEP_VIRTIO_PCI_HC
#define NINEP_VIRTIO_PCI_HC
#include "../NineP/NineP.HH"
#include "../NineP/NinePCodec.HC"
#include "VirtioPci.HC"
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
// Away from mmio 9p (0x300000) and pci blk (0x400000).
#define V9P_PCI_VQ   (CONFIG_VIRTIO_DRV_RAM_BASE+0x500000)
#define V9P_PCI_REQ  (CONFIG_VIRTIO_DRV_RAM_BASE+0x510000)
#define V9P_PCI_RSP  (CONFIG_VIRTIO_DRV_RAM_BASE+0x520000)
#define V9P_PCI_META (CONFIG_VIRTIO_DRV_RAM_BASE+0x530000)
#define V9P_PCI_QSZ  8
#define VDESC_F_NEXT 1
#define VDESC_F_WRITE 2
class CV9pPciDesc
{
  U64 addr;
  U32 len;
  U16 flags;
  U16 next;
};
I64 ninep_pci_bdf;
U8 *ninep_pci_common;
U8 *ninep_pci_notify;
U8 *ninep_pci_devcfg;
U32 ninep_pci_notify_mult;
U16 ninep_pci_qsz;
U16 ninep_pci_q_notify_off;
U32 ninep_pci_avail_off;
U32 ninep_pci_used_off;
U16 ninep_pci_avail_idx;
CV9pPciDesc ninep_pci_desc_tmp[2];
U8 *NinePVirtioPciReq()
{
  return V9P_PCI_REQ;
}

U8 *NinePVirtioPciRsp()
{
  return V9P_PCI_RSP;
}

I64 NinePVirtioPciInit()
{
  U64 bars[6];
  U8 st;
  U16 qsz;
  I64 avail_off, used_off;
  ninep_pci_bdf = -1;
  ninep_pci_common = 0;
  ninep_pci_notify = 0;
  ninep_pci_devcfg = 0;
  ninep_pci_avail_idx = 0;
  if (!RVVirtioPciEnabled())
    return -1;
  ninep_pci_bdf = VirtioPciFind9p();
  if (ninep_pci_bdf < 0)
    return -1;
  VirtioPciEnableBm(ninep_pci_bdf);
  VirtioPciAssignBar4(ninep_pci_bdf);
  VirtioPciFillBars(ninep_pci_bdf, bars);
  if (VirtioPciParseCaps(ninep_pci_bdf, bars, &ninep_pci_common, &ninep_pci_notify, &ninep_pci_notify_mult, &ninep_pci_devcfg))
    return -2;
  OutU8(ninep_pci_common + VPCI_COMMON_STATUS, 0);
  OutU8(ninep_pci_common + VPCI_COMMON_STATUS, VPCI_S_ACK);
  OutU8(ninep_pci_common + VPCI_COMMON_STATUS, VPCI_S_ACK | VPCI_S_DRIVER);
  OutU32(ninep_pci_common + VPCI_COMMON_GFSELECT, 0);
  OutU32(ninep_pci_common + VPCI_COMMON_GF, 0);
  OutU32(ninep_pci_common + VPCI_COMMON_GFSELECT, 1);
  OutU32(ninep_pci_common + VPCI_COMMON_GF, 1);
  VirtioPciMsixDisable(ninep_pci_bdf);
  VirtioPciSetNoMsix(ninep_pci_common);
  st = VPCI_S_ACK | VPCI_S_DRIVER | VPCI_S_FEATURES_OK;
  OutU8(ninep_pci_common + VPCI_COMMON_STATUS, st);
  st = InU8(ninep_pci_common + VPCI_COMMON_STATUS);
  if (!(st & VPCI_S_FEATURES_OK) || (st & VPCI_S_FAILED))
    return -3;
  OutU16(ninep_pci_common + VPCI_COMMON_Q_SELECT, 0);
  qsz = InU16(ninep_pci_common + VPCI_COMMON_Q_SIZE);
  if (qsz < 2)
    return -4;
  if (qsz > V9P_PCI_QSZ)
    qsz = V9P_PCI_QSZ;
  OutU16(ninep_pci_common + VPCI_COMMON_Q_SIZE, qsz);
  avail_off = (qsz * 16 + 1) & ~1;
  used_off = (avail_off + 6 + 2 * qsz + 3) & ~3;
  MemSet(V9P_PCI_VQ, 0, 16384);
  MemSet(V9P_PCI_REQ, 0, 8192);
  MemSet(V9P_PCI_RSP, 0, 8192);
  OutU32(ninep_pci_common + VPCI_COMMON_Q_DESC, V9P_PCI_VQ);
  OutU32(ninep_pci_common + VPCI_COMMON_Q_DESC + 4, 0);
  OutU32(ninep_pci_common + VPCI_COMMON_Q_AVAIL, V9P_PCI_VQ + avail_off);
  OutU32(ninep_pci_common + VPCI_COMMON_Q_AVAIL + 4, 0);
  OutU32(ninep_pci_common + VPCI_COMMON_Q_USED, V9P_PCI_VQ + used_off);
  OutU32(ninep_pci_common + VPCI_COMMON_Q_USED + 4, 0);
  VirtioPciQueueNoMsix(ninep_pci_common);
  OutU16(ninep_pci_common + VPCI_COMMON_Q_ENABLE, 1);
  ninep_pci_q_notify_off = InU16(ninep_pci_common + VPCI_COMMON_Q_NOTIFY);
  ninep_pci_qsz = qsz;
  ninep_pci_avail_off = avail_off;
  ninep_pci_used_off = used_off;
  st = st | VPCI_S_DRIVER_OK;
  OutU8(ninep_pci_common + VPCI_COMMON_STATUS, st);
  if (InU8(ninep_pci_common + VPCI_COMMON_STATUS) & VPCI_S_FAILED)
    return -5;
  *(U64 *)(V9P_PCI_META + 0) = ninep_pci_common;
  *(U64 *)(V9P_PCI_META + 8) = ninep_pci_notify;
  *(U32 *)(V9P_PCI_META + 16) = ninep_pci_notify_mult;
  *(U16 *)(V9P_PCI_META + 20) = ninep_pci_q_notify_off;
  *(U16 *)(V9P_PCI_META + 22) = ninep_pci_qsz;
  *(U32 *)(V9P_PCI_META + 24) = ninep_pci_avail_off;
  *(U32 *)(V9P_PCI_META + 28) = ninep_pci_used_off;
  return 0;
}

I64 NinePVirtioPciPresent()
{
  return ninep_pci_bdf >= 0 && ninep_pci_common != 0;
}

I64 NinePVirtioPciSendRecv(I64 req_len)
{
  U8 *notify, *avail, *used;
  U32 nmult, avail_off, used_off;
  U16 qsz, q_notify_off, old_idx, aidx;
  I64 spin, pad;
  if (!NinePVirtioPciPresent() || req_len <= 0 || req_len > 8192)
    return -1;
  pad = req_len;
  if (pad & 3)
    pad = pad + 4 - (pad & 3);
  notify = ninep_pci_notify;
  nmult = ninep_pci_notify_mult;
  q_notify_off = ninep_pci_q_notify_off;
  qsz = ninep_pci_qsz;
  avail_off = ninep_pci_avail_off;
  used_off = ninep_pci_used_off;
  MemSet(V9P_PCI_RSP, 0, 4096);
  ninep_pci_desc_tmp[0].addr = V9P_PCI_REQ;
  ninep_pci_desc_tmp[0].len = pad;
  ninep_pci_desc_tmp[0].flags = VDESC_F_NEXT;
  ninep_pci_desc_tmp[0].next = 1;
  ninep_pci_desc_tmp[1].addr = V9P_PCI_RSP;
  ninep_pci_desc_tmp[1].len = 4096;
  ninep_pci_desc_tmp[1].flags = VDESC_F_WRITE;
  ninep_pci_desc_tmp[1].next = 0;
  MemCpy(V9P_PCI_VQ, ninep_pci_desc_tmp, 32);
  avail = V9P_PCI_VQ + avail_off;
  used = V9P_PCI_VQ + used_off;
  old_idx = InU16(used + 2);
  aidx = ninep_pci_avail_idx;
  OutU16(avail, 0);
  OutU16(avail + 4 + 2 * (aidx % qsz), 0);
  OutU16(avail + 2, aidx + 1);
  ninep_pci_avail_idx = aidx + 1;
  InU8(ninep_pci_common + VPCI_COMMON_STATUS);
  OutU16(notify + q_notify_off *nmult, 0);
  for (spin = 0; spin < 200000000; spin++)
    if (InU16(used + 2) != old_idx)
      break;
  if (InU16(used + 2) == old_idx)
    return -2;
  return NinePGetU32(V9P_PCI_RSP, 0);
}

I64 NinePVirtioPciMountTag(U8 *buf, I64 cap)
{
  U16 n, i;
  if (!NinePVirtioPciPresent() || !ninep_pci_devcfg || !buf || cap <= 0)
    return -1;
  n = InU16(ninep_pci_devcfg);
  if (n <= 0 || n >= cap)
    return -2;
  for (i = 0; i < n; i++)
    buf[i] = *(U8 *)(ninep_pci_devcfg + 2 + i);
  buf[n] = 0;
  return n;
}
#endif
