// RVMemMap.HC — MEM/MMIO region ↔ HolyC driver legend (Kconfig-driven).
// Include after RVAutoConf.HH + Drv selects. Dig-down: RVMemMap;
// REPL MemMap (bootstrap/seed + C host slot) hardcodes virt; this tracks defconfig*.
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
#define RV_MEMMAP_DRV_UART "RVUartStub"
#endif
#endif
#endif
#ifdef CONFIG_UART_SIFIVE
#define RV_MEMMAP_DRV_CLINT "RVSifivePlat / RVTimer"
#else
#define RV_MEMMAP_DRV_CLINT "RVTimer / CLINT"
#endif
#ifdef CONFIG_HAS_PLIC
#ifdef CONFIG_UART_SIFIVE
#define RV_MEMMAP_DRV_PLIC "RVSifivePlat / RVPlicHw"
#else
#define RV_MEMMAP_DRV_PLIC "RVPlicHw"
#endif
#define RV_MEMMAP_PLIC_BASE CONFIG_PLIC_BASE
#else
#define RV_MEMMAP_DRV_PLIC "RVPlicStub"
#define RV_MEMMAP_PLIC_BASE 0
#endif
#ifdef CONFIG_HAS_VIRTIO_MMIO
#define RV_MEMMAP_DRV_VIRTIO "DskVirtioRV / RVVirtioMmio*"
#define RV_MEMMAP_VIRTIO_BASE CONFIG_VIRTIO_MMIO_BASE
#else
#define RV_MEMMAP_DRV_VIRTIO "RVVirtioMmioNo"
#define RV_MEMMAP_VIRTIO_BASE 0
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
  "  CLINT    0x%X  %s\n", CONFIG_CLINT_BASE, RV_MEMMAP_DRV_CLINT;
  "  PLIC     0x%X  %s\n", RV_MEMMAP_PLIC_BASE, RV_MEMMAP_DRV_PLIC;
  "  VIRTIO   0x%X  %s\n", RV_MEMMAP_VIRTIO_BASE, RV_MEMMAP_DRV_VIRTIO;
  "  FB soft 0x%X  %s\n", CONFIG_FB_SOFT_BASE, RV_MEMMAP_DRV_FB;
  "  FW_CFG   0x%X  %s\n", RV_MEMMAP_FW_CFG_BASE, RV_MEMMAP_DRV_FW_CFG;
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
#endif
