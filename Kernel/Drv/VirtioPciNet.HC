// VirtioPciNet.HC — modern virtio-pci net (QEMU virt + virtio-net-pci).
// TX/RX split queues via ECAM common/notify caps. Dig-down: VirtioPciNetInit;
// Descriptors published with raw 16-byte stores (avoid class-layout quirks).
#ifndef RV_DRV_VIRTIO_PCI_NET_HC
#define RV_DRV_VIRTIO_PCI_NET_HC
#include "VirtioPci.HC"
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
// Away from mmio net (0x100000), pci blk (0x400000), pci 9p (0x500000).
#define VPCI_NET_RX_VQ  (CONFIG_VIRTIO_DRV_RAM_BASE+0x600000)
#define VPCI_NET_TX_VQ  (CONFIG_VIRTIO_DRV_RAM_BASE+0x610000)
#define VPCI_NET_TX_PKT (CONFIG_VIRTIO_DRV_RAM_BASE+0x620000)
#define VPCI_NET_RX_BUF (CONFIG_VIRTIO_DRV_RAM_BASE+0x621000)
#define VPCI_NET_META   (CONFIG_VIRTIO_DRV_RAM_BASE+0x640000)
#define VPCI_NET_QSZ    8
#define VPCI_NET_BUF_STRIDE 1536
#define VDESC_F_NEXT    1
#define VDESC_F_WRITE   2
I64 virtio_pci_net_bdf;
U8 *virtio_pci_net_common;
U8 *virtio_pci_net_notify;
U8 *virtio_pci_net_isr;
U32 virtio_pci_net_notify_mult;
U16 virtio_pci_net_qsz;
U16 virtio_pci_net_rx_notify_off;
U16 virtio_pci_net_tx_notify_off;
U32 virtio_pci_net_avail_off;
U32 virtio_pci_net_used_off;
I64 virtio_pci_net_rx_last;
I64 virtio_pci_net_rx_pkts;
U0 (*virtio_pci_net_rx_cb)(U8 *pkt, I64 len);
U0 VirtioPciNetPutDesc(I64 vq, I64 idx, U64 addr, U32 len, U16 flags, U16 next)
{
  U8 *p = vq + idx * 16;
  *(U64 *)p = addr;
  *(U32 *)(p + 8) = len;
  *(U16 *)(p + 12) = flags;
  *(U16 *)(p + 14) = next;
}

I64 VirtioPciNetSetupQueue(U8 *common, I64 qsel, I64 vq_base, U16 *out_notify_off)
{
  U16 qsz;
  I64 avail_off, used_off;
  OutU16(common + VPCI_COMMON_Q_SELECT, qsel);
  qsz = InU16(common + VPCI_COMMON_Q_SIZE);
  if (qsz < 2)
    return -1;
  if (qsz > VPCI_NET_QSZ)
    qsz = VPCI_NET_QSZ;
  OutU16(common + VPCI_COMMON_Q_SIZE, qsz);
  avail_off = (qsz * 16 + 1) & ~1;
  used_off = (avail_off + 6 + 2 * qsz + 3) & ~3;
  MemSet(vq_base, 0, 16384);
  OutU32(common + VPCI_COMMON_Q_DESC, vq_base);
  OutU32(common + VPCI_COMMON_Q_DESC + 4, 0);
  OutU32(common + VPCI_COMMON_Q_AVAIL, vq_base + avail_off);
  OutU32(common + VPCI_COMMON_Q_AVAIL + 4, 0);
  OutU32(common + VPCI_COMMON_Q_USED, vq_base + used_off);
  OutU32(common + VPCI_COMMON_Q_USED + 4, 0);
  VirtioPciQueueNoMsix(common);
  OutU16(common + VPCI_COMMON_Q_ENABLE, 1);
  *out_notify_off = InU16(common + VPCI_COMMON_Q_NOTIFY);
  virtio_pci_net_qsz = qsz;
  virtio_pci_net_avail_off = avail_off;
  virtio_pci_net_used_off = used_off;
  return 0;
}

I64 VirtioPciNetInit()
{
  I64 bdf, i;
  U64 bars[6];
  U8 *common, *notify, *devcfg, *isr, *avail;
  U32 nmult;
  U8 st;
  U16 rx_off, tx_off;
  virtio_pci_net_bdf = -1;
  virtio_pci_net_common = 0;
  virtio_pci_net_notify = 0;
  virtio_pci_net_isr = 0;
  virtio_pci_net_rx_cb = 0;
  virtio_pci_net_rx_last = 0;
  virtio_pci_net_rx_pkts = 0;
  if (!RVVirtioPciEnabled())
    return -1;
  bdf = VirtioPciFindNet();
  if (bdf < 0)
    return -1;
  VirtioPciEnableBm(bdf);
  VirtioPciAssignBar4(bdf);
  VirtioPciFillBars(bdf, bars);
  if (VirtioPciParseCapsEx(bdf, bars, &common, &notify, &nmult, &devcfg, &isr))
    return -2;
  OutU8(common + VPCI_COMMON_STATUS, 0);
  OutU8(common + VPCI_COMMON_STATUS, VPCI_S_ACK);
  OutU8(common + VPCI_COMMON_STATUS, VPCI_S_ACK | VPCI_S_DRIVER);
  OutU32(common + VPCI_COMMON_GFSELECT, 0);
  OutU32(common + VPCI_COMMON_GF, 0);
  OutU32(common + VPCI_COMMON_GFSELECT, 1);
  OutU32(common + VPCI_COMMON_GF, 1);
  // virt PLIC: MSI-X does not deliver; use INTx + ISR ACK.
  VirtioPciMsixDisable(bdf);
  VirtioPciSetNoMsix(common);
  VirtioPciEnableIntx(bdf);
  st = VPCI_S_ACK | VPCI_S_DRIVER | VPCI_S_FEATURES_OK;
  OutU8(common + VPCI_COMMON_STATUS, st);
  st = InU8(common + VPCI_COMMON_STATUS);
  if (!(st & VPCI_S_FEATURES_OK) || (st & VPCI_S_FAILED))
    return -3;
  MemSet(VPCI_NET_TX_PKT, 0, VPCI_NET_BUF_STRIDE);
  MemSet(VPCI_NET_RX_BUF, 0, VPCI_NET_QSZ *VPCI_NET_BUF_STRIDE);
  if (VirtioPciNetSetupQueue(common, 0, VPCI_NET_RX_VQ, &rx_off))
    return -4;
  if (VirtioPciNetSetupQueue(common, 1, VPCI_NET_TX_VQ, &tx_off))
    return -5;
  avail = VPCI_NET_RX_VQ + virtio_pci_net_avail_off;
  for (i = 0; i < virtio_pci_net_qsz; i++) {
    VirtioPciNetPutDesc(VPCI_NET_RX_VQ, i, VPCI_NET_RX_BUF + i *VPCI_NET_BUF_STRIDE, VPCI_NET_BUF_STRIDE, VDESC_F_WRITE, 0);
    OutU16(avail + 4 + 2 * i, i);
  }
  OutU16(avail, 0);
  OutU16(avail + 2, virtio_pci_net_qsz);
  st = st | VPCI_S_DRIVER_OK;
  OutU8(common + VPCI_COMMON_STATUS, st);
  if (InU8(common + VPCI_COMMON_STATUS) & VPCI_S_FAILED)
    return -6;
  virtio_pci_net_bdf = bdf;
  virtio_pci_net_common = common;
  virtio_pci_net_notify = notify;
  virtio_pci_net_isr = isr;
  virtio_pci_net_notify_mult = nmult;
  virtio_pci_net_rx_notify_off = rx_off;
  virtio_pci_net_tx_notify_off = tx_off;
  OutU16(notify + rx_off *nmult, 0);
  return 0;
}

I64 VirtioPciNetPresent()
{
  return virtio_pci_net_bdf >= 0 && virtio_pci_net_common != 0;
}

U0 VirtioPciNetSetRxCb(U0 (*fp)(U8 *pkt, I64 len))
{
  virtio_pci_net_rx_cb = fp;
}

I64 VirtioPciNetTx(U8 *pkt, I64 len)
{
  U8 *notify, *avail, *used, *dst;
  U16 old_idx, aidx;
  I64 spin, i;
  if (!VirtioPciNetPresent() || !pkt || len <= 0 || len > 1514)
    return -1;
  // One TX buffer: [virtio_net_hdr (10) | eth frame] — matches RX layout.
  MemSet(VPCI_NET_TX_PKT, 0, 10);
  dst = VPCI_NET_TX_PKT + 10;
  for (i = 0; i < len; i++)
    dst[i] = pkt[i];
  VirtioPciNetPutDesc(VPCI_NET_TX_VQ, 0, VPCI_NET_TX_PKT, 10 + len, 0, 0);
  avail = VPCI_NET_TX_VQ + virtio_pci_net_avail_off;
  used = VPCI_NET_TX_VQ + virtio_pci_net_used_off;
  notify = virtio_pci_net_notify;
  old_idx = InU16(used + 2);
  aidx = InU16(avail + 2);
  OutU16(avail, 0);
  OutU16(avail + 4 + 2 * (aidx % virtio_pci_net_qsz), 0);
  OutU16(avail + 2, aidx + 1);
  OutU16(notify + virtio_pci_net_tx_notify_off *virtio_pci_net_notify_mult, 1);
  for (spin = 0; spin < 200000000; spin++)
    if (InU16(used + 2) != old_idx)
      break;
  if (InU16(used + 2) == old_idx)
    return -2;
  return 0;
}

I64 VirtioPciNetRxPending()
{
  U8 *used;
  if (!VirtioPciNetPresent())
    return 0;
  used = VPCI_NET_RX_VQ + virtio_pci_net_used_off;
  return (U16)(InU16(used + 2) - (U16)virtio_pci_net_rx_last);
}

I64 VirtioPciNetRx(U8 *pkt, I64 cap)
{
  U8 *used, *avail, *buf;
  U32 id, n;
  I64 i, plen;
  if (!VirtioPciNetPresent() || !pkt || cap <= 0)
    return -1;
  used = VPCI_NET_RX_VQ + virtio_pci_net_used_off;
  avail = VPCI_NET_RX_VQ + virtio_pci_net_avail_off;
  if ((U16)InU16(used + 2) == (U16)virtio_pci_net_rx_last)
    return 0;
  id = InU32(used + 4 + 8 * ((U16)virtio_pci_net_rx_last % virtio_pci_net_qsz));
  n = InU32(used + 8 + 8 * ((U16)virtio_pci_net_rx_last % virtio_pci_net_qsz));
  virtio_pci_net_rx_last = (U16)(virtio_pci_net_rx_last + 1);
  if (id >= virtio_pci_net_qsz)
    return -3;
  if (n < 10)
    return -2;
  plen = n - 10;
  if (plen > cap)
    plen = cap;
  buf = VPCI_NET_RX_BUF + id *VPCI_NET_BUF_STRIDE + 10;
  for (i = 0; i < plen; i++)
    pkt[i] = buf[i];
  OutU16(avail + 4 + 2 * (InU16(avail + 2) % virtio_pci_net_qsz), id);
  OutU16(avail + 2, InU16(avail + 2) + 1);
  OutU16(virtio_pci_net_notify + virtio_pci_net_rx_notify_off *virtio_pci_net_notify_mult, 0);
  virtio_pci_net_rx_pkts++;
  return plen;
}

I64 VirtioPciNetRxDrain(I64 max)
{
  U8 pkt[1514];
  I64 n = 0, plen;
  if (max <= 0)
    max = VPCI_NET_QSZ;
  while (n < max) {
    if (!VirtioPciNetRxPending())
      break;
    plen = VirtioPciNetRx(pkt, 1514);
    if (plen < 0)
      continue;
    if (plen == 0)
      break;
    if (virtio_pci_net_rx_cb)
      (*virtio_pci_net_rx_cb)(pkt, plen);
    n++;
  }
  return n;
}

I64 VirtioPciNetTxProbe()
{
  U8 pkt[64];
  I64 i;
  for (i = 0; i < 6; i++)
    pkt[i] = 0xFF;
  pkt[6] = 0x02;
  pkt[7] = 0x00;
  pkt[8] = 0x00;
  pkt[9] = 0x00;
  pkt[10] = 0x00;
  pkt[11] = 0x01;
  pkt[12] = 0x88;
  pkt[13] = 0xB5;
  for (i = 14; i < 60; i++)
    pkt[i] = i;
  return VirtioPciNetTx(pkt, 60);
}

I64 VirtioPciNetRxSelfTest()
{
  U8 *used, *buf;
  I64 i, id;
  if (!VirtioPciNetPresent())
    return -1;
  id = 0;
  buf = VPCI_NET_RX_BUF + id *VPCI_NET_BUF_STRIDE;
  for (i = 0; i < 10; i++)
    buf[i] = 0;
  for (i = 0; i < 6; i++)
    buf[10 + i] = 0xFF;
  buf[16] = 0x02;
  buf[17] = 0x00;
  buf[18] = 0x00;
  buf[19] = 0x00;
  buf[20] = 0x00;
  buf[21] = 0x02;
  buf[22] = 0x88;
  buf[23] = 0xB5;
  for (i = 24; i < 70; i++)
    buf[i] = i;
  used = VPCI_NET_RX_VQ + virtio_pci_net_used_off;
  OutU32(used + 4 + 8 * (InU16(used + 2) % virtio_pci_net_qsz), id);
  OutU32(used + 8 + 8 * (InU16(used + 2) % virtio_pci_net_qsz), 10 + 60);
  OutU16(used + 2, InU16(used + 2) + 1);
  return VirtioPciNetRxDrain(1);
}

I64 VirtioPciNetIrqNum()
{
  if (!VirtioPciNetPresent())
    return -1;
  return VirtioPciIrqNum(virtio_pci_net_bdf);
}

U0 VirtioPciNetIrqAck()
{
  VirtioPciIsrAck(virtio_pci_net_isr);
}

I64 VirtioPciNetIrqInit()
{
  I64 irq;
  irq = VirtioPciNetIrqNum();
  if (irq < 0)
    return -1;
  VirtioPciNetIrqAck();
  if (virtio_pci_net_isr)
    RVVirtioPciIsrReg(virtio_pci_net_isr);
  RVPlicEnable(irq, 1);
  RVPlicSetThreshold(0);
  RvSetMEIE();
  return irq;
}

I64 VirtioPciNetIrqService()
{
  I64 n, st;
  if (!VirtioPciNetPresent())
    return 0;
  st = VirtioPciIsrAck(virtio_pci_net_isr);
  n = 0;
  if (st & 1)
    n = VirtioPciNetRxDrain(VPCI_NET_QSZ);
  return n;
}
#endif
