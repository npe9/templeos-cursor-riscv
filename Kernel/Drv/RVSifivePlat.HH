// RVSifivePlat.HH — SiFive platform interface (FU540 / FE310 / board profiles).
// Named API for UART / CLINT / PLIC / reset-power / trap probes.
// Impl: RVSifivePlat.HC → RVSifiveSelected.HH → RVSifiveYes.HC | RVSifiveNo.HC
// Dig-down: Man("SiFive"); Man("Reset"); RVMemMap; make kernel-plat-sifive-u-smoke
//
// SiFive -- SiFive platform interface
// NAME
//   SiFive - HolyC facade for SiFive UART0 + CLINT + PLIC + reset/halt/fault
// SYNOPSIS
//   #include "Drv/RVSifivePlat.HC"
//   if (RVSifivePresent) {
//     RVSifiveUartInit;
//     RVSifiveUartPutS("hi\n");
//     RVSifiveClintArmTicks(1000000);
//     RVSifivePlicEnable(CONFIG_UART_IRQ,1);
//     // HW reset / park / trap probe (see BUGS for board honesty):
//     // RVSifiveReset;  RVSifiveHalt;  RVSifiveFault;
//   }
// DESCRIPTION
//   On PLATFORM_SIFIVE_U / PLATFORM_SIFIVE_E (UART_SIFIVE), RVSifiveYes provides:
//     RVSifivePresent / RVSifiveUartBase / RVSifiveUart1Base / RVSifiveClintBase
//     RVSifivePlicBase / RVSifivePrciBase / RVSifiveEthBase
//     RVSifiveUartInit / PutS / DataReady / GetC
//     RVSifiveClintMtime / RVSifiveClintSetMtimecmp / RVSifiveClintArmTicks
//     RVSifivePlicEnable / SetThreshold / Claim / Complete
//     RVSifiveTestBase / AonBase / GpioBase / GpioResetPin / CanReset
//     RVSifiveReset / PowerOff / Halt / Fault
//   Addresses come from CONFIG_* in RVAutoConf.HH (UART/CLINT/PLIC + SIFIVE_*).
//   MMIO (SiFive UART0 words): TXDATA@base+0 (bit31=TX full), RXDATA@+4,
//   TXCTRL@+8=1, RXCTRL@+12=1. CLINT: mtime @ BASE+MTIME_OFF, mtimecmp write.
//   PLIC: same enable/claim/complete as RVPlicHw (CONFIG_PLIC_*_OFF).
//   sifive_u extras: UART1, PRCI (legend); GEM eth via RVSifiveGem (TX/RX).
//   Generic RVUart* (RVUartSifive.HC) thin-wraps the UART side; RVTimer / RVPlicHw
//   share the same MMIO windows. Other machines get RVSifiveNo stubs
//   (Present=FALSE). See templeos-riscv/PLATFORM.md. REPL dig-down: Man("SiFive").
// CROSS-REFS
//   RVMemMap  RVUartSifive  RVTimer  RVPlicHw  CLINT  PLIC  UART  Reset  Halt  Fault
// BUGS
//   sifive_e DTIM is tiny (16 KiB) and QEMU has no external DRAM. Product layout:
//     Kernel = XIP/QSPI @ 0x20400000 (execute in place; host-prepatched imports)
//     Bootloader only in DTIM (copy .data, clear .bss, jump to XIP Kernel)
// Dual artifacts: slim plat.elf (matrix) + kernel-fe310.elf (Kernel_FE310.PRJ;
//   make kernel-sifive-e-full-smoke). Full Kernel_RV / REPL still do not fit.
//   RV32 HolyC emit for real FE310: later — after RV64 virtio/net/etc (not G13-first).
//   Reset paths (honest):
//     sifive_u — GPIO active-low pin (CONFIG_SIFIVE_GPIO_RESET_PIN, default 10).
//       Works on the sifive_u board profile; same idea as a wired reset button.
//       No AON at 0x10000000 here (that window is PRCI). No test-finisher.
//     sifive_e / FE310 — AON WDT reset (CONFIG_SIFIVE_AON_BASE). Real silicon
//       also has PMU sleep; this port uses the WDT RSTEN path.
//     Test finisher @ CONFIG_SIFIVE_TEST_BASE (0x7777/0x5555/0x3333) — virt
//       harness / sim only; not real FU540/FE310 silicon and not sifive_u/e.
//   Soft REPL Reset; (Boot re-entry) is separate — Man("Reset").
#ifndef RV_SIFIVE_PLAT_HH
#define RV_SIFIVE_PLAT_HH
// Finisher magic (SiFive test device; U32 stores only).
#define RVSIFIVE_TEST_FAIL  0x3333
#define RVSIFIVE_TEST_PASS  0x5555
#define RVSIFIVE_TEST_RESET 0x7777
// FE310 AON WDT unlock / feed (manual + QEMU sifive_e_aon).
#define RVSIFIVE_AON_WDOGKEY  0x51F15E
#define RVSIFIVE_AON_WDOGFEED 0xD09F00D
#define RVSIFIVE_AON_WDOGCFG  0x00
#define RVSIFIVE_AON_WDOGCOUNT 0x08
#define RVSIFIVE_AON_WDOGKEY_OFF 0x1C
#define RVSIFIVE_AON_WDOGCMP0 0x20
// WDOGCFG: RSTEN bit8, ENALWAYS bit12
#define RVSIFIVE_AON_WDOGCFG_RSTEN_ENALWAYS 0x1100
// SiFive GPIO regs (word offsets / 4 for U32*).
#define RVSIFIVE_GPIO_OUTPUT_EN 2
#define RVSIFIVE_GPIO_PORT      3
// Bodies live in RVSifiveYes.HC / RVSifiveNo.HC (HolyC AOT cannot #ifdef fn bodies).
#endif
