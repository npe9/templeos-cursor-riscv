// VirtioNet.HC — virtio-mmio net (DeviceID 1) with virtio-pci fallback.
// TX/RX via split virtqueues. Dig-down: Man("VirtioNet"); VirtioNetInit;
// RX: poll VirtioNetRx / VirtioNetRxDrain(+optional cb); IRQ: VirtioNetIrqInit
// + VirtioNetIrqService (ACK + drain). Full trap-vector RX still deferred.
// PCI path: VirtioPciNet when no mmio slot (virtio-net-pci).
#ifndef RV_DRV_VIRTIO_NET_HC
#define RV_DRV_VIRTIO_NET_HC
#include "VirtioPciNet.HC"
#define VNET_MAGIC        0x74726976
#define VNET_ID_NET       1
#define VNET_KIND_NONE    0
#define VNET_KIND_MMIO    1
#define VNET_KIND_PCI     2
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
#define VNET_QSZ          8
// Fixed driver RAM (needs DRAM covering CONFIG_VIRTIO_DRV_RAM_BASE; virt -m >=256M).
#ifndef CONFIG_VIRTIO_DRV_RAM_BASE
#define CONFIG_VIRTIO_DRV_RAM_BASE 0x88000000
#endif
#ifndef CONFIG_VIRTIO_MMIO_IRQ_BASE
#define CONFIG_VIRTIO_MMIO_IRQ_BASE 0x10000000
#endif
#define VNET_RX_VQ        (CONFIG_VIRTIO_DRV_RAM_BASE+0x100000)
#define VNET_TX_VQ        (CONFIG_VIRTIO_DRV_RAM_BASE+0x102000)
#define VNET_TX_HDR       (CONFIG_VIRTIO_DRV_RAM_BASE+0x104000)
#define VNET_RX_BUF       (CONFIG_VIRTIO_DRV_RAM_BASE+0x105000)
#define VNET_TX_BUF       (CONFIG_VIRTIO_DRV_RAM_BASE+0x108000)
#define VNET_BUF_STRIDE   1536
class CVnetDesc
{
  U64 addr;
  U32 len;
  U16 flags;
  U16 next;
};

class CVnetAvail
{
  U16 flags;
  U16 idx;
  U16 ring[VNET_QSZ];
  U16 used_ev;
};

class CVnetUsedElem
{
  U32 id;
  U32 len;
};

class CVnetUsed
{
  U16 flags;
  U16 idx;
  CVnetUsedElem ring[VNET_QSZ];
  U16 avail_ev;
};

class CVnetHdr
{
  U8 flags;
  U8 gso_type;
  U16 hdr_len;
  U16 gso_size;
  U16 csum_start;
  U16 csum_offset;
};
I64 virtio_net_base;
I64 virtio_net_kind;
I64 virtio_net_rx_last;
I64 virtio_net_rx_pkts;
U0 (*virtio_net_rx_cb)(U8 *pkt, I64 len);
I64 VirtioNetFind()
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
    if (InU32(r + VMR_MAGIC) == VNET_MAGIC && InU32(r + VMR_DEVICE_ID) == VNET_ID_NET)
      return slot;
  }
  return 0;
}

U0 VirtioNetSetupQueue(U8 *r, I64 qsel, I64 pfn)
{
  OutU32(r + VMR_QUEUE_SEL, qsel);
  OutU32(r + VMR_QUEUE_NUM, VNET_QSZ);
  OutU32(r + VMR_QUEUE_ALIGN, 4096);
  OutU32(r + VMR_QUEUE_PFN, pfn >> 12);
}

I64 VirtioNetInit()
{
  U8 *r;
  CVnetDesc *desc;
  CVnetAvail *avail;
  I64 i;
  virtio_net_kind = VNET_KIND_NONE;
  virtio_net_base = VirtioNetFind();
  if (!virtio_net_base) {
    if (VirtioPciNetInit())
      return -1;
    virtio_net_kind = VNET_KIND_PCI;
    return 0;
  }
  r = virtio_net_base;
  MemSet(VNET_RX_VQ, 0, 8192);
  MemSet(VNET_TX_VQ, 0, 8192);
  MemSet(VNET_TX_HDR, 0, 64);
  MemSet(VNET_RX_BUF, 0, VNET_QSZ *VNET_BUF_STRIDE);
  MemSet(VNET_TX_BUF, 0, VNET_BUF_STRIDE);
  OutU32(r + VMR_STATUS, 0);
  OutU32(r + VMR_STATUS, VSTAT_ACK);
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER);
  OutU32(r + VMR_DRIVER_FEATSEL, 0);
  OutU32(r + VMR_DRIVER_FEAT, 0);
  OutU32(r + VMR_GUEST_PGSZ, 4096);
  VirtioNetSetupQueue(r, 0, VNET_RX_VQ);
  VirtioNetSetupQueue(r, 1, VNET_TX_VQ);
  // One RX buffer per descriptor: [virtio_net_hdr | eth frame]
  desc = VNET_RX_VQ;
  avail = VNET_RX_VQ + 128;
  for (i = 0; i < VNET_QSZ; i++) {
    desc[i].addr = VNET_RX_BUF + i *VNET_BUF_STRIDE;
    desc[i].len = VNET_BUF_STRIDE;
    desc[i].flags = VDESC_F_WRITE;
    desc[i].next = 0;
    avail->ring[i] = i;
  }
  avail->idx = VNET_QSZ;
  virtio_net_rx_last = 0;
  virtio_net_rx_pkts = 0;
  OutU32(r + VMR_STATUS, VSTAT_ACK | VSTAT_DRIVER | VSTAT_DRIVER_OK);
  // Kick RX so the device sees posted buffers (needed before any RX/ARP).
  OutU32(r + VMR_QUEUE_NOTIFY, 0);
  virtio_net_kind = VNET_KIND_MMIO;
  return 0;
}

U0 VirtioNetSetRxCb(U0 (*fp)(U8 *pkt, I64 len))
{
  virtio_net_rx_cb = fp;
  if (virtio_net_kind == VNET_KIND_PCI)
    VirtioPciNetSetRxCb(fp);
}

I64 VirtioNetIrqNum()
{
  if (virtio_net_kind == VNET_KIND_PCI)
    return VirtioPciNetIrqNum();
  // QEMU virt: MMIO slot → PLIC IRQ via CONFIG_VIRTIO_MMIO_IRQ_BASE.
  if (virtio_net_kind != VNET_KIND_MMIO || !virtio_net_base)
    return -1;
  return (virtio_net_base - CONFIG_VIRTIO_MMIO_IRQ_BASE) >> 12;
}

U0 VirtioNetIrqAck()
{
  U8 *r = virtio_net_base;
  U32 st;
  if (virtio_net_kind == VNET_KIND_PCI) {
    VirtioPciNetIrqAck();
    return;
  }
  if (virtio_net_kind != VNET_KIND_MMIO || !r)
    return;
  st = InU32(r + VMR_INTERRUPT_STATUS);
  if (st)
    OutU32(r + VMR_INTERRUPT_ACK, st);
}
// Enable PLIC for this device. ACK first so an already-asserted line does not
// pend the moment enable is written. Caller still needs RVTrapInit + mie.MEIE
// for delivery; VirtioNetIrqService drains+ACKs from a trap or a poll loop.
I64 VirtioNetIrqInit()
{
  I64 irq;
  if (virtio_net_kind == VNET_KIND_PCI)
    return VirtioPciNetIrqInit();
  irq = VirtioNetIrqNum();
  if (irq < 0)
    return -1;
  VirtioNetIrqAck();
  RVPlicEnable(irq, 1);
  RVPlicSetThreshold(0);
  RvSetMEIE();
  return irq;
}

I64 VirtioNetTx(U8 *pkt, I64 len)
{
  U8 *r = virtio_net_base;
  CVnetDesc *desc = VNET_TX_VQ;
  CVnetAvail *avail = VNET_TX_VQ + 128;
  CVnetUsed *used = VNET_TX_VQ + 4096;
  CVnetHdr *hdr = VNET_TX_HDR;
  U16 uidx0;
  I64 spin, i;
  if (virtio_net_kind == VNET_KIND_PCI)
    return VirtioPciNetTx(pkt, len);
  if (!virtio_net_base || !pkt || len <= 0 || len > 1514)
    return -1;
  hdr->flags = 0;
  hdr->gso_type = 0;
  hdr->hdr_len = 0;
  hdr->gso_size = 0;
  hdr->csum_start = 0;
  hdr->csum_offset = 0;
  for (i = 0; i < len; i++)
    *(U8 *)(VNET_TX_BUF + i) = pkt[i];
  desc[0].addr = VNET_TX_HDR;
  desc[0].len = 10;
  desc[0].flags = VDESC_F_NEXT;
  desc[0].next = 1;
  desc[1].addr = VNET_TX_BUF;
  desc[1].len = len;
  desc[1].flags = 0;
  desc[1].next = 0;
  uidx0 = used->idx;
  avail->ring[avail->idx % VNET_QSZ] = 0;
  avail->idx = avail->idx + 1;
  OutU32(r + VMR_QUEUE_NOTIFY, 1);
  for (spin = 0; spin < 200000000; spin++)
    if (used->idx != uidx0)
      break;
  if (used->idx == uidx0)
    return -2;
  VirtioNetIrqAck();
  return 0;
}

I64 VirtioNetRxPending()
{
  CVnetUsed *used = VNET_RX_VQ + 4096;
  if (virtio_net_kind == VNET_KIND_PCI)
    return VirtioPciNetRxPending();
  if (!virtio_net_base)
    return 0;
  // used->idx is U16; compare modulo 65536 so wrap does not stall forever.
  return (U16)(used->idx - (U16)virtio_net_rx_last);
}

I64 VirtioNetRx(U8 *pkt, I64 cap)
{
  U8 *r = virtio_net_base;
  CVnetUsed *used = VNET_RX_VQ + 4096;
  CVnetAvail *avail = VNET_RX_VQ + 128;
  U32 id, n;
  I64 i, plen;
  U8 *buf;
  if (virtio_net_kind == VNET_KIND_PCI)
    return VirtioPciNetRx(pkt, cap);
  if (!virtio_net_base || !pkt || cap <= 0)
    return -1;
  if ((U16)used->idx == (U16)virtio_net_rx_last)
    return 0;
  id = used->ring[(U16)virtio_net_rx_last % VNET_QSZ].id;
  n = used->ring[(U16)virtio_net_rx_last % VNET_QSZ].len;
  virtio_net_rx_last = (U16)(virtio_net_rx_last + 1);
  if (id >= VNET_QSZ)
    return -3;
  if (n < 10)
    return -2;
  plen = n - 10;
  if (plen > cap)
    plen = cap;
  buf = VNET_RX_BUF + id *VNET_BUF_STRIDE + 10;
  for (i = 0; i < plen; i++)
    pkt[i] = buf[i];
  avail->ring[avail->idx % VNET_QSZ] = id;
  avail->idx = avail->idx + 1;
  OutU32(r + VMR_QUEUE_NOTIFY, 0);
  virtio_net_rx_pkts++;
  return plen;
}
// Drain up to max frames; invoke virtio_net_rx_cb(pkt,len) when set. Returns
// frames consumed (skips short/bad descriptors without counting them as ok).
I64 VirtioNetRxDrain(I64 max)
{
  U8 pkt[1514];
  I64 n = 0, plen;
  if (virtio_net_kind == VNET_KIND_PCI)
    return VirtioPciNetRxDrain(max);
  if (max <= 0)
    max = VNET_QSZ;
  while (n < max) {
    if (!VirtioNetRxPending())
      break;
    plen = VirtioNetRx(pkt, 1514);
    if (plen < 0)
      continue;
    if (plen == 0)
      break;
    if (virtio_net_rx_cb)
      (*virtio_net_rx_cb)(pkt, plen);
    n++;
  }
  VirtioNetIrqAck();
  return n;
}
// Poll InterruptStatus → drain RX → ACK. Safe from a trap after PLIC claim of
// VirtioNetIrqNum(), or from a timer/idle poll without MEIE.
I64 VirtioNetIrqService()
{
  U8 *r = virtio_net_base;
  U32 st;
  I64 n;
  if (virtio_net_kind == VNET_KIND_PCI)
    return VirtioPciNetIrqService();
  if (!r)
    return -1;
  st = InU32(r + VMR_INTERRUPT_STATUS);
  n = VirtioNetRxDrain(VNET_QSZ);
  if (st)
    OutU32(r + VMR_INTERRUPT_ACK, st);
  return n;
}

I64 VirtioNetTxProbe()
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
  return VirtioNetTx(pkt, 60);
}
// ARP who-has 10.0.2.2 (QEMU user-net gateway) from 10.0.2.15 / 02:00:00:00:00:01.
// Best-effort live RX; SLIRP may not reply in harness — prefer VirtioNetRxSelfTest
// for a deterministic drain/cb gate. Returns frames drained, or <0 on TX failure.
I64 VirtioNetArpProbe()
{
  U8 pkt[64];
  I64 i, spin, n, got;
  for (i = 0; i < 6; i++)
    pkt[i] = 0xFF;
  pkt[6] = 0x02;
  pkt[7] = 0x00;
  pkt[8] = 0x00;
  pkt[9] = 0x00;
  pkt[10] = 0x00;
  pkt[11] = 0x01;
  pkt[12] = 0x08;
  pkt[13] = 0x06;
  pkt[14] = 0x00;
  pkt[15] = 0x01;
  pkt[16] = 0x08;
  pkt[17] = 0x00;
  pkt[18] = 6;
  pkt[19] = 4;
  pkt[20] = 0x00;
  pkt[21] = 0x01;
  pkt[22] = 0x02;
  pkt[23] = 0x00;
  pkt[24] = 0x00;
  pkt[25] = 0x00;
  pkt[26] = 0x00;
  pkt[27] = 0x01;
  pkt[28] = 10;
  pkt[29] = 0;
  pkt[30] = 2;
  pkt[31] = 15;
  for (i = 32; i < 38; i++)
    pkt[i] = 0;
  pkt[38] = 10;
  pkt[39] = 0;
  pkt[40] = 2;
  pkt[41] = 2;
  for (i = 42; i < 60; i++)
    pkt[i] = 0;
  if (VirtioNetTx(pkt, 60))
    return -1;
  got = 0;
  for (spin = 0; spin < 2000000; spin++) {
    n = VirtioNetRxDrain(VNET_QSZ);
    if (n > 0) {
      got = got + n;
      break;
    }
  }
  return got;
}
// Deterministic RX drain/cb check: plant one used-ring eth frame (as the device
// would) and drain it. Does not depend on host netdev / SLIRP.
I64 VirtioNetRxSelfTest()
{
  CVnetUsed *used = VNET_RX_VQ + 4096;
  U8 *buf;
  I64 i, id;
  if (virtio_net_kind == VNET_KIND_PCI)
    return VirtioPciNetRxSelfTest();
  if (!virtio_net_base)
    return -1;
  id = 0;
  buf = VNET_RX_BUF + id *VNET_BUF_STRIDE;
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
  used->ring[used->idx % VNET_QSZ].id = id;
  used->ring[used->idx % VNET_QSZ].len = 10 + 60;
  used->idx = used->idx + 1;
  return VirtioNetRxDrain(1);
}
#endif
