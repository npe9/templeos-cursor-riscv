// RVSifivePlat.HH — SiFive platform interface (FU540 / FE310 / QEMU sifive_u|e).
// Named API for UART / CLINT / PLIC; bases from Kernel/RVAutoConf.HH (Kconfig).
// Impl: RVSifivePlat.HC → RVSifiveSelected.HH → RVSifiveYes.HC | RVSifiveNo.HC
// Dig-down: Man("SiFive"); RVMemMap; make kernel-plat-sifive-u-smoke
//
// SiFive -- SiFive platform interface
// NAME
//   SiFive - HolyC facade for SiFive UART0 + CLINT + PLIC (sifive_u / sifive_e)
// SYNOPSIS
//   #include "Drv/RVSifivePlat.HC"
//   if (RVSifivePresent) {
//     RVSifiveUartInit;
//     RVSifiveUartPutS("hi\n");
//     RVSifiveClintArmTicks(1000000);
//     RVSifivePlicEnable(CONFIG_UART_IRQ,1);
//   }
// DESCRIPTION
//   On PLATFORM_SIFIVE_U / PLATFORM_SIFIVE_E (UART_SIFIVE), RVSifiveYes provides:
//     RVSifivePresent / RVSifiveUartBase / RVSifiveClintBase / RVSifivePlicBase
//     RVSifiveUartInit / PutS / DataReady / GetC
//     RVSifiveClintMtime / RVSifiveClintSetMtimecmp / RVSifiveClintArmTicks
//     RVSifivePlicEnable / SetThreshold / Claim / Complete
//   Addresses come from CONFIG_UART_BASE / CONFIG_CLINT_* / CONFIG_PLIC_* in
//   RVAutoConf.HH. Generic RVUart* (RVUartSifive.HC) thin-wraps the UART side;
//   RVTimer / RVPlicHw share the same MMIO windows. Other machines get RVSifiveNo
//   stubs (Present=FALSE). See templeos-riscv/PLATFORM.md.
// CROSS-REFS
//   RVMemMap  RVUartSifive  RVTimer  RVPlicHw  CLINT  PLIC
// BUGS
//   sifive_e DTIM is tiny — full Kernel_RV does not fit; plat UART+CLINT smoke
//   is supported on sifive_u.
#ifndef RV_SIFIVE_PLAT_HH
#define RV_SIFIVE_PLAT_HH
// Bodies live in RVSifiveYes.HC / RVSifiveNo.HC (HolyC AOT cannot #ifdef fn bodies).
#endif
