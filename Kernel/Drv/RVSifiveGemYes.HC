// SiFive Cadence GEM present (PLATFORM_SIFIVE_U / CONFIG_SIFIVE_ETH_BASE).
// Poll-driven TX/RX + local-loopback RX self-test for QEMU sifive_u.
#include "RVSifiveGem.HH"
#ifndef CONFIG_SIFIVE_ETH_BASE
#define CONFIG_SIFIVE_ETH_BASE 0
#endif
#ifndef CONFIG_DRAM_BASE
#define CONFIG_DRAM_BASE 0x80000000
#endif
// Fixed DMA arena in DRAM (identity map). Keep clear of typical plat.elf image.
#ifndef CONFIG_SIFIVE_GEM_RAM_BASE
#define CONFIG_SIFIVE_GEM_RAM_BASE (CONFIG_DRAM_BASE + 0x01000000)
#endif
#define GEM_TX_DESC (CONFIG_SIFIVE_GEM_RAM_BASE + 0x0000)
#define GEM_RX_DESC (CONFIG_SIFIVE_GEM_RAM_BASE + 0x0100)
#define GEM_TX_BUF  (CONFIG_SIFIVE_GEM_RAM_BASE + 0x1000)
#define GEM_RX_BUF  (CONFIG_SIFIVE_GEM_RAM_BASE + 0x2000)
I64 sifive_gem_base;
I64 sifive_gem_rx_pkts;
U0 (*sifive_gem_rx_cb)(U8 *pkt, I64 len);
// sifive_gem_base used to be set only by RVSifiveGemInit, so every access before init went to
// ADDRESS 0: reads returned zeros -- which made Eth() report a perfectly configured controller as
// dead, when a raw Dump of 0x10090000 showed ncfgr=0x00100402 and U-Boot's descriptor rings -- and
// a write would have landed in the mask-ROM region. Default it from Kconfig on first use, and
// refuse when the board has no GEM rather than dereferencing 0.
U0 RVSifiveGemWr(I64 off, U32 v)
{
  U32 *p;
  if (!sifive_gem_base)
    sifive_gem_base = CONFIG_SIFIVE_ETH_BASE;
  if (!sifive_gem_base)
    return;
  p = sifive_gem_base + off;
  *p = v;
}

U32 RVSifiveGemRd(I64 off)
{
  U32 *p;
  if (!sifive_gem_base)
    sifive_gem_base = CONFIG_SIFIVE_ETH_BASE;
  if (!sifive_gem_base)
    return 0;
  p = sifive_gem_base + off;
  return *p;
}

I64 RVSifiveGemBase()
{
  return CONFIG_SIFIVE_ETH_BASE;
}

Bool RVSifiveGemPresent()
{
  return CONFIG_SIFIVE_ETH_BASE != 0;
}

I64 RVSifiveGemIrqNum()
{
  return RVSIFIVE_GEM_IRQ;
}

U0 RVSifiveGemSetRxCb(U0 (*fp)(U8 *pkt, I64 len))
{
  sifive_gem_rx_cb = fp;
}

U0 RVSifiveGemDescInit()
{
  U32 *td = GEM_TX_DESC, *rd = GEM_RX_DESC;
  I64 i;
  for (i = 0; i < RVSIFIVE_GEM_QSZ; i++) {
    td[i * 2] = GEM_TX_BUF + i *RVSIFIVE_GEM_MTU;
    td[i * 2 + 1] = RVSIFIVE_GEM_TX_USED;
    if (i == RVSIFIVE_GEM_QSZ - 1)
      td[i * 2 + 1] = td[i * 2 + 1] | RVSIFIVE_GEM_TX_WRAP;
    rd[i * 2] = (GEM_RX_BUF + i *RVSIFIVE_GEM_MTU) & ~3;
    rd[i * 2 + 1] = 0;
    if (i == RVSIFIVE_GEM_QSZ - 1)
      rd[i * 2] = rd[i * 2] | RVSIFIVE_GEM_RX_WRAP;
  }
}

I64 RVSifiveGemInit()
{
  if (!CONFIG_SIFIVE_ETH_BASE)
    return -1;
  sifive_gem_base = CONFIG_SIFIVE_ETH_BASE;
  sifive_gem_rx_pkts = 0;
  sifive_gem_rx_cb = NULL;
  RVSifiveGemWr(RVSIFIVE_GEM_NCR, 0);
  RVSifiveGemWr(RVSIFIVE_GEM_NCR, RVSIFIVE_GEM_NCR_CLRSTAT);
  RVSifiveGemWr(RVSIFIVE_GEM_NCR, 0);
  RVSifiveGemWr(RVSIFIVE_GEM_NCFGR, RVSIFIVE_GEM_NCFGR_INIT);
  RVSifiveGemWr(RVSIFIVE_GEM_DMACFG, RVSIFIVE_GEM_DMACFG_INIT);
  // Local MAC 02:00:00:00:00:01
  RVSifiveGemWr(RVSIFIVE_GEM_SA1B, 0x00000002);
  RVSifiveGemWr(RVSIFIVE_GEM_SA1T, 0x00000100);
  RVSifiveGemDescInit;
  RVSifiveGemWr(RVSIFIVE_GEM_RXQBASE, GEM_RX_DESC);
  RVSifiveGemWr(RVSIFIVE_GEM_TXQBASE, GEM_TX_DESC);
  RVSifiveGemWr(RVSIFIVE_GEM_TXSTATUS, 0xFFFFFFFF);
  RVSifiveGemWr(RVSIFIVE_GEM_RXSTATUS, 0xFFFFFFFF);
  RVSifiveGemWr(RVSIFIVE_GEM_NCR, RVSIFIVE_GEM_NCR_RE | RVSIFIVE_GEM_NCR_TE);
  return 0;
}

I64 RVSifiveGemTx(U8 *pkt, I64 len)
{
  U32 *td = GEM_TX_DESC;
  U8 *buf = GEM_TX_BUF;
  I64 i, spin;
  U32 st;
  if (!sifive_gem_base || !pkt || len <= 0 || len > RVSIFIVE_GEM_MTU)
    return -1;
  if (len < 60)
    len = 60;
  // Wait for TX desc ownership (USED set).
  for (spin = 0; spin < 2000000; spin++) {
    if (td[1] & RVSIFIVE_GEM_TX_USED)
      break;
  }
  if (!(td[1] & RVSIFIVE_GEM_TX_USED))
    return -2;
  for (i = 0; i < len; i++)
    buf[i] = pkt[i];
  td[0] = GEM_TX_BUF;
  td[1] = (len & RVSIFIVE_GEM_RX_LEN) | RVSIFIVE_GEM_TX_LAST | RVSIFIVE_GEM_TX_WRAP;
  RVSifiveGemWr(RVSIFIVE_GEM_TXSTATUS, 0xFFFFFFFF);
  RVSifiveGemWr(RVSIFIVE_GEM_NCR, RVSifiveGemRd(RVSIFIVE_GEM_NCR) | RVSIFIVE_GEM_NCR_TSTART);
  for (spin = 0; spin < 2000000; spin++) {
    if (td[1] & RVSIFIVE_GEM_TX_USED)
      break;
    st = RVSifiveGemRd(RVSIFIVE_GEM_TXSTATUS);
    if (st & RVSIFIVE_GEM_TXSTAT_COMP)
      break;
  }
  if (!(td[1] & RVSIFIVE_GEM_TX_USED) && !(RVSifiveGemRd(RVSIFIVE_GEM_TXSTATUS) & RVSIFIVE_GEM_TXSTAT_COMP))
    return -3;
  RVSifiveGemWr(RVSIFIVE_GEM_TXSTATUS, 0xFFFFFFFF);
  return 0;
}

I64 RVSifiveGemRxPending()
{
  U32 *rd = GEM_RX_DESC;
  if (!sifive_gem_base)
    return 0;
  return (rd[0] & RVSIFIVE_GEM_RX_OWN) != 0;
}

I64 RVSifiveGemRx(U8 *pkt, I64 cap)
{
  U32 *rd = GEM_RX_DESC;
  U8 *buf = GEM_RX_BUF;
  I64 n, i;
  U32 w1;
  if (!sifive_gem_base || !pkt || cap <= 0)
    return -1;
  if (!(rd[0] & RVSIFIVE_GEM_RX_OWN))
    return 0;
  w1 = rd[1];
  n = w1 & RVSIFIVE_GEM_RX_LEN;
  if (n > cap)
    n = cap;
  for (i = 0; i < n; i++)
    pkt[i] = buf[i];
  // Hand buffer back to GEM (clear ownership, keep wrap + addr).
  rd[1] = 0;
  rd[0] = (GEM_RX_BUF & ~3) | RVSIFIVE_GEM_RX_WRAP;
  RVSifiveGemWr(RVSIFIVE_GEM_RXSTATUS, 0xFFFFFFFF);
  sifive_gem_rx_pkts++;
  return n;
}

I64 RVSifiveGemRxDrain(I64 max)
{
  U8 pkt[1514];
  I64 n, got, plen;
  got = 0;
  if (max <= 0)
    max = RVSIFIVE_GEM_QSZ;
  while (got < max) {
    if (!RVSifiveGemRxPending)
      break;
    plen = RVSifiveGemRx(pkt, 1514);
    if (plen <= 0)
      break;
    if (sifive_gem_rx_cb)
      (*sifive_gem_rx_cb)(pkt, plen);
    got++;
  }
  return got;
}

I64 RVSifiveGemTxProbe()
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
  return RVSifiveGemTx(pkt, 60);
}
// Deterministic RX via GEM local loopback (NCR LBL). No SLIRP required.
I64 RVSifiveGemRxSelfTest()
{
  U8 pkt[64];
  I64 i, spin, n, ncr;
  if (!sifive_gem_base)
    return -1;
  RVSifiveGemDescInit;
  RVSifiveGemWr(RVSIFIVE_GEM_RXQBASE, GEM_RX_DESC);
  RVSifiveGemWr(RVSIFIVE_GEM_TXQBASE, GEM_TX_DESC);
  ncr = RVSIFIVE_GEM_NCR_RE | RVSIFIVE_GEM_NCR_TE | RVSIFIVE_GEM_NCR_LBL;
  RVSifiveGemWr(RVSIFIVE_GEM_NCR, ncr);
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
    pkt[i] = 0xA0 + (i & 0xF);
  if (RVSifiveGemTx(pkt, 60))
    return -2;
  for (spin = 0; spin < 2000000; spin++) {
    n = RVSifiveGemRxDrain(RVSIFIVE_GEM_QSZ);
    if (n > 0) {
      RVSifiveGemWr(RVSIFIVE_GEM_NCR, RVSIFIVE_GEM_NCR_RE | RVSIFIVE_GEM_NCR_TE);
      return n;
    }
  }
  RVSifiveGemWr(RVSIFIVE_GEM_NCR, RVSIFIVE_GEM_NCR_RE | RVSIFIVE_GEM_NCR_TE);
  return 0;
}
// The DMA arena, so callers outside this file can flush it. GEM_TX_DESC sits at +0, GEM_RX_DESC
// at +0x100, the TX buffers at +0x1000 and the RX buffers at +0x2000, so the span that any cache
// maintenance has to cover runs to the end of the RX buffers.
I64 RVSifiveGemDmaBase()
{
  return CONFIG_SIFIVE_GEM_RAM_BASE;
}

I64 RVSifiveGemDmaLen()
{
  return 0x2000 + RVSIFIVE_GEM_QSZ * RVSIFIVE_GEM_MTU;
}
// The first TX descriptor's status word, which is where the controller reports that it took the
// buffer (USED). Reading it from outside is how the A/B below tells "GEM never saw the
// descriptor" apart from "GEM saw it and the link did not come up".
I64 RVSifiveGemTxDescW1()
{
  U32 *td = GEM_TX_DESC;
  if (!sifive_gem_base)
    return 0;
  return td[1];
}
