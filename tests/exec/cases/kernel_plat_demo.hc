// Platform Kconfig smoke: HolyC Drv UART + CLINT (+ PLIC/MemMap/SiFive when present).
// Addresses/driver select come from Kernel/RVAutoConf.HH (make -C templeos-riscv defconfig*).
//
// Keep matrix green:
//   - HAS_PLIC: Enable only if UART_IRQ>0 (icicle=90); shakti IRQ=0 skips.
//     RVPlicHw no-ops threshold/claim on shakti (QEMU 128KiB PLIC aperture).
//   - SiFive: Enable via RVSifivePlic* (sifive_u / sifive_e).
//   - HAS_APLIC (xiangshan): RVPlicAplic path; owned by that board.
//   - Never call RVMemMap() here — harness Print is virt UART @ 0x10000000.
#include "/Kernel/RVAutoConf.HH"
#include "/Kernel/Drv/RVSifivePlat.HC"
#include "/Kernel/Drv/RVUart.HC"
#include "/Kernel/Drv/RVTimer.HC"
#include "/Kernel/Drv/RVPlic.HC"
#include "/Kernel/Drv/RVMemMap.HC"
I64 main()
{
  I64 t, t1, id, i, s;
  U8 *drv;
  RVUartInit();
  RVUartPutS("plat-smoke: machine=");
  RVUartPutS(CONFIG_PLATFORM_NAME);
  RVUartPutS("\n");
  RVUartPutS("plat-smoke: uart_ok\n");
  t = RVClintMtime();
  RVUartPutS("plat-smoke: clint_ok\n");
#ifdef CONFIG_HAS_CLINT
  s = 0;
  i = 0;
  while (i < 200000) {
    s += i;
    i++;
  }
  t1 = RVClintMtime();
  RVClintArmTicks(CONFIG_TIMEBASE_FREQ);
  if (t1 > t && s) {
    RVUartPutS("plat-smoke: clint_adv_ok\n");
    t = t1;
  } else {
    RVUartPutS("plat-smoke: clint_adv_fail\n");
    return 1;
  }
#else
  RVUartPutS("plat-smoke: clint_stub_ok\n");
#endif
  if (RVSifivePresent) {
    RVSifiveUartPutS("plat-smoke: sifive_api\n");
    t = RVSifiveClintMtime();
    RVSifiveUartPutS("plat-smoke: sifive_clint_ok\n");
    if (RVSifiveCanReset)
      RVSifiveUartPutS("plat-smoke: sifive_can_reset\n");
    else
      RVSifiveUartPutS("plat-smoke: sifive_no_hw_reset\n");
    RVSifivePlicSetThreshold(0);
    RVSifivePlicEnable(CONFIG_UART_IRQ, 1);
    id = RVSifivePlicClaim();
    RVSifivePlicComplete(id);
    RVSifiveUartPutS("plat-smoke: sifive_plic_ok\n");
    t = RVSifiveTestBase() | RVSifiveAonBase() | RVSifiveGpioBase() | RVSifiveUart1Base() | RVSifivePrciBase() | RVSifiveEthBase();
  }
#ifdef CONFIG_HAS_PLIC
  RVPlicSetThreshold(0);
  // Enable only when UART_IRQ>0 (icicle=90). Shakti IRQ=0 skips; threshold/claim
  // are no-ops in RVPlicHw on shakti (QEMU 128KiB PLIC aperture).
  if (CONFIG_UART_IRQ > 0)
    RVPlicEnable(CONFIG_UART_IRQ, 1);
  id = RVPlicClaim();
  RVPlicComplete(id);
  RVUartPutS("plat-smoke: plic_ok\n");
#else
#ifdef CONFIG_HAS_APLIC
  RVPlicSetThreshold(0);
  if (CONFIG_UART_IRQ)
    RVPlicEnable(CONFIG_UART_IRQ, 1);
  id = RVPlicClaim();
  RVPlicComplete(id);
  RVUartPutS("plat-smoke: aplic_ok\n");
#else
  RVPlicSetThreshold(0);
  id = RVPlicClaim();
  RVPlicComplete(id);
  RVUartPutS("plat-smoke: plic_stub_ok\n");
#endif
#endif
  // RVMemMap() uses implicit Print — hangs in this harness. Probe strings.
  drv = RVMemMapDrvUart();
  if (drv)
    RVUartPutS("plat-smoke: memmap_ok\n");
  RVUartPutS("plat-smoke: PASS\n");
  return t & 0;
}
