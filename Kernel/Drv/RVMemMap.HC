// RVMemMap.HC — MEM/MMIO region ↔ HolyC driver legend (Kconfig-driven).
// Include after RVAutoConf.HH + Drv selects. Dig-down: RVMemMap;
// REPL MemMap (bootstrap/seed/MemMapSelected.hc) tracks the same Kconfig bases;
// this file is the Kernel/Drv legend after defconfig*.
#ifndef RV_DRV_MEMMAP_HC
#define RV_DRV_MEMMAP_HC
#ifdef CONFIG_UART_16550
#define RV_MEMMAP_DRV_UART "RVUart16550"
#else
#ifdef CONFIG_UART_SIFIVE
#define RV_MEMMAP_DRV_UART "RVSifivePlat"
#else
#ifdef CONFIG_UART_HTIF
#define RV_MEMMAP_DRV_UART "RVUartHtif"
#else
#ifdef CONFIG_UART_SHAKTI
#define RV_MEMMAP_DRV_UART "RVUartShakti"
#else
#ifdef CONFIG_UART_UARTLITE
#define RV_MEMMAP_DRV_UART "RVUartUartlite"
#else
#ifdef CONFIG_UART_IBEX
#define RV_MEMMAP_DRV_UART "RVUartIbex"
#else
#define RV_MEMMAP_DRV_UART "RVUartStub"
#endif
#endif
#endif
#endif
#endif
#endif
#ifdef CONFIG_UART_SIFIVE
#define RV_MEMMAP_DRV_CLINT "RVSifivePlat / RVTimer"
#else
#ifdef CONFIG_HAS_CLINT
#define RV_MEMMAP_DRV_CLINT "RVTimer / CLINT"
#else
#ifdef CONFIG_HAS_IBEX_TIMER
#define RV_MEMMAP_DRV_CLINT "RVTimerIbex"
#else
#define RV_MEMMAP_DRV_CLINT "RVTimerStub (no CLINT)"
#endif
#endif
#endif
#ifdef CONFIG_HAS_PLIC
#ifdef CONFIG_UART_SIFIVE
#define RV_MEMMAP_DRV_PLIC "RVSifivePlat / RVPlicHw"
#else
#define RV_MEMMAP_DRV_PLIC "RVPlicHw"
#endif
#define RV_MEMMAP_PLIC_BASE CONFIG_PLIC_BASE
#else
#ifdef CONFIG_HAS_APLIC
#define RV_MEMMAP_DRV_PLIC "RVPlicAplic"
#define RV_MEMMAP_PLIC_BASE CONFIG_APLIC_BASE
#else
#define RV_MEMMAP_DRV_PLIC "RVPlicStub"
#define RV_MEMMAP_PLIC_BASE 0
#endif
#endif
#ifdef CONFIG_HAS_VIRTIO_MMIO
#ifdef CONFIG_HAS_VIRTIO_PCI
#define RV_MEMMAP_DRV_VIRTIO "DskVirtioRV / VirtioNet / VirtioInput / Virtio9p / VirtioConsole / VirtioBalloon / VirtioScsi / VirtioPciBlk / VirtioPciNet"
#else
#define RV_MEMMAP_DRV_VIRTIO "DskVirtioRV / VirtioNet / VirtioInput / Virtio9p / VirtioConsole / VirtioBalloon / VirtioScsi"
#endif
#define RV_MEMMAP_VIRTIO_BASE CONFIG_VIRTIO_MMIO_BASE
#else
#ifdef CONFIG_HAS_VIRTIO_PCI
#define RV_MEMMAP_DRV_VIRTIO "VirtioPci / VirtioPciBlk / VirtioPciNet / NinePVirtioPci"
#define RV_MEMMAP_VIRTIO_BASE CONFIG_PCI_ECAM_BASE
#else
#define RV_MEMMAP_DRV_VIRTIO "RVVirtioMmioNo"
#define RV_MEMMAP_VIRTIO_BASE 0
#endif
#endif
#ifdef CONFIG_FB_PRESENT_RAMFB
#define RV_MEMMAP_DRV_FB "RVFb / ramfb"
#else
#ifdef CONFIG_FB_PRESENT_SIMPLEFB
#define RV_MEMMAP_DRV_FB "RVFb / simplefb"
#else
#define RV_MEMMAP_DRV_FB "RVFb / none"
#endif
#endif
#ifdef CONFIG_HAS_FW_CFG
#define RV_MEMMAP_DRV_FW_CFG "RVFwCfgYes"
#define RV_MEMMAP_FW_CFG_BASE CONFIG_FW_CFG_BASE
#else
#define RV_MEMMAP_DRV_FW_CFG "RVFwCfgNo"
#define RV_MEMMAP_FW_CFG_BASE 0
#endif
#ifdef CONFIG_HAS_GOLDFISH_RTC
#define RV_MEMMAP_DRV_RTC "RVRtcGoldfish"
#define RV_MEMMAP_RTC_BASE CONFIG_RTC_BASE
#else
#define RV_MEMMAP_DRV_RTC "RVRtcNo"
#define RV_MEMMAP_RTC_BASE 0
#endif
#ifndef CONFIG_SMP_MAILBOX_BASE
#define CONFIG_SMP_MAILBOX_BASE 0
#endif
#ifndef CONFIG_SIFIVE_TEST_BASE
#define CONFIG_SIFIVE_TEST_BASE 0
#endif
#ifndef CONFIG_SIFIVE_AON_BASE
#define CONFIG_SIFIVE_AON_BASE 0
#endif
#ifndef CONFIG_SIFIVE_GPIO_BASE
#define CONFIG_SIFIVE_GPIO_BASE 0
#endif
#ifndef CONFIG_SIFIVE_UART1_BASE
#define CONFIG_SIFIVE_UART1_BASE 0
#endif
#ifndef CONFIG_SIFIVE_PRCI_BASE
#define CONFIG_SIFIVE_PRCI_BASE 0
#endif
#ifndef CONFIG_SIFIVE_ETH_BASE
#define CONFIG_SIFIVE_ETH_BASE 0
#endif
// RVMemMap -- RVMemMap()
// NAME
//   RVMemMap - print platform MMIO bases with owning Kernel/Drv drivers
// SYNOPSIS
//   U0 RVMemMap();
// DESCRIPTION
//   Kconfig addresses (CONFIG_*_BASE) plus the selected HolyC driver flavor.
//   Mirrors REPL MemMap's driver column for non-virt boards after defconfig*.
//   Base 0 means the feature is stubbed / absent on this machine.
U0 RVMemMap()
{
  "RVMemMap (%s) — region → Kernel/Drv:\n", CONFIG_PLATFORM_NAME;
  "  UART     0x%X  %s\n", CONFIG_UART_BASE, RV_MEMMAP_DRV_UART;
#ifdef CONFIG_HAS_IBEX_TIMER
  "  TIMER    0x%X  %s\n", CONFIG_IBEX_TIMER_BASE, RV_MEMMAP_DRV_CLINT;
#else
  "  CLINT    0x%X  %s\n", CONFIG_CLINT_BASE, RV_MEMMAP_DRV_CLINT;
#endif
  "  PLIC/APLIC 0x%X  %s\n", RV_MEMMAP_PLIC_BASE, RV_MEMMAP_DRV_PLIC;
#ifdef CONFIG_HAS_APLIC
  "  IMSIC_M  0x%X  RVPlicAplic (mtopei / eithreshold; 4 KiB/hart)\n", CONFIG_IMSIC_BASE;
#endif
  "  VIRTIO   0x%X  %s\n", RV_MEMMAP_VIRTIO_BASE, RV_MEMMAP_DRV_VIRTIO;
  "  FB soft 0x%X  %s\n", CONFIG_FB_SOFT_BASE, RV_MEMMAP_DRV_FB;
  "  FW_CFG   0x%X  %s\n", RV_MEMMAP_FW_CFG_BASE, RV_MEMMAP_DRV_FW_CFG;
  "  RTC      0x%X  %s\n", RV_MEMMAP_RTC_BASE, RV_MEMMAP_DRV_RTC;
  if (CONFIG_SMP_MAILBOX_BASE)
    "  SMP mbx  0x%X  RVSmp\n", CONFIG_SMP_MAILBOX_BASE;
  if (CONFIG_SIFIVE_TEST_BASE)
    "  TEST     0x%X  RVSifivePlat test finisher\n", CONFIG_SIFIVE_TEST_BASE;
  if (CONFIG_SIFIVE_AON_BASE)
    "  AON      0x%X  RVSifivePlat AON/WDT\n", CONFIG_SIFIVE_AON_BASE;
  if (CONFIG_SIFIVE_GPIO_BASE)
    "  GPIO     0x%X  RVSifivePlat (reset pin)\n", CONFIG_SIFIVE_GPIO_BASE;
  if (CONFIG_SIFIVE_UART1_BASE)
    "  UART1    0x%X  RVSifivePlat (legend)\n", CONFIG_SIFIVE_UART1_BASE;
  if (CONFIG_SIFIVE_PRCI_BASE)
    "  PRCI     0x%X  RVSifivePlat (legend)\n", CONFIG_SIFIVE_PRCI_BASE;
  if (CONFIG_SIFIVE_ETH_BASE)
    "  ETH/GEM  0x%X  RVSifiveGem\n", CONFIG_SIFIVE_ETH_BASE;
}

U8 *RVMemMapDrvUart()
{
  return RV_MEMMAP_DRV_UART;
}

U8 *RVMemMapDrvClint()
{
  return RV_MEMMAP_DRV_CLINT;
}

U8 *RVMemMapDrvPlic()
{
  return RV_MEMMAP_DRV_PLIC;
}

U8 *RVMemMapDrvVirtio()
{
  return RV_MEMMAP_DRV_VIRTIO;
}

U8 *RVMemMapDrvFb()
{
  return RV_MEMMAP_DRV_FB;
}

U8 *RVMemMapDrvFwCfg()
{
  return RV_MEMMAP_DRV_FW_CFG;
}

U8 *RVMemMapDrvRtc()
{
  return RV_MEMMAP_DRV_RTC;
}
#endif
