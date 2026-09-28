// RVSifiveGem.HH — SiFive Cadence GEM (FU540 / QEMU sifive_u) HolyC iface.
// Impl: RVSifiveGem.HC → RVSifiveGemSelected.HH → Yes (ETH_BASE) | No.
// Dig-down: Man("SiFive"); RVMemMap; make kernel-sifive-gem-smoke
//
// SiFiveGem -- Cadence GEM ethernet
// NAME
//   SiFiveGem - TX/RX slice for FU540 GEM @ CONFIG_SIFIVE_ETH_BASE
// SYNOPSIS
//   #include "Drv/RVSifiveGem.HC"
//   if (!RVSifiveGemInit) {
//     RVSifiveGemTxProbe;
//     RVSifiveGemRxSelfTest;  // local loopback
//   }
// DESCRIPTION
//   Cadence GEM registers (macb/GEM layout): NCR@0, NCFGR@4, DMACFG@0x10,
//   TXSTATUS@0x14, RXQBASE@0x18, TXQBASE@0x1c, RXSTATUS@0x20, SA1@0x88.
//   Descriptor rings are 32-bit (DRAM @ 0x80000000). RX self-test uses
//   NCR LOOPBACK_LOCAL so QEMU does not need a live SLIRP reply.
//   PLIC IRQ 53 is documented; this slice is poll-driven (no MEIE trap).
// CROSS-REFS
//   RVMemMap  RVSifivePlat  VirtioNet  ETH
// BUGS
//   No TCP/IP stack; no PHY MDIO bring-up beyond QEMU defaults; no MSI.
//   GEM mgmt block @ 0x100a0000 is unimplemented in QEMU — ignored.
#ifndef RV_SIFIVE_GEM_HH
#define RV_SIFIVE_GEM_HH
#define RVSIFIVE_GEM_NCR      0x00
#define RVSIFIVE_GEM_NCFGR    0x04
#define RVSIFIVE_GEM_DMACFG   0x10
#define RVSIFIVE_GEM_TXSTATUS 0x14
#define RVSIFIVE_GEM_RXQBASE  0x18
#define RVSIFIVE_GEM_TXQBASE  0x1c
#define RVSIFIVE_GEM_RXSTATUS 0x20
#define RVSIFIVE_GEM_ISR      0x24
#define RVSIFIVE_GEM_IER      0x28
#define RVSIFIVE_GEM_SA1B     0x88
#define RVSIFIVE_GEM_SA1T     0x8c
// NCR bits
#define RVSIFIVE_GEM_NCR_LB   0x01
#define RVSIFIVE_GEM_NCR_LBL  0x02
#define RVSIFIVE_GEM_NCR_RE   0x04
#define RVSIFIVE_GEM_NCR_TE   0x08
#define RVSIFIVE_GEM_NCR_CLRSTAT 0x20
#define RVSIFIVE_GEM_NCR_TSTART  0x200
// NCFGR: FD | PROMISC | gigabit | FCS remove | 1536 recv
#define RVSIFIVE_GEM_NCFGR_INIT 0x00020512
// DMACFG: RXBUF=24×64=1536, burst=16
#define RVSIFIVE_GEM_DMACFG_INIT 0x00180010
#define RVSIFIVE_GEM_TXSTAT_USED 0x01
#define RVSIFIVE_GEM_TXSTAT_COMP 0x20
#define RVSIFIVE_GEM_RXSTAT_FR   0x02
// Descriptor word1 / word0 bits (QEMU cadence_gem)
#define RVSIFIVE_GEM_TX_USED  0x80000000
#define RVSIFIVE_GEM_TX_WRAP  0x40000000
#define RVSIFIVE_GEM_TX_LAST  0x00008000
#define RVSIFIVE_GEM_RX_OWN   0x00000001
#define RVSIFIVE_GEM_RX_WRAP  0x00000002
#define RVSIFIVE_GEM_RX_SOF   0x00004000
#define RVSIFIVE_GEM_RX_EOF   0x00008000
#define RVSIFIVE_GEM_RX_LEN   0x00001FFF
// FU540 / QEMU sifive_u: 53. FU740: 55 (53 is I2C1 there) -- from Kconfig when the board says so.
#ifdef CONFIG_GEM_IRQ
#define RVSIFIVE_GEM_IRQ      CONFIG_GEM_IRQ
#else
#define RVSIFIVE_GEM_IRQ      53
#endif
#define RVSIFIVE_GEM_MTU      1536
#define RVSIFIVE_GEM_QSZ      2
#endif
