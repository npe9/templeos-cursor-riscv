// Platform Kconfig smoke: HolyC Drv UART + CLINT (+ SiFive plat API when selected).
// Addresses/driver select come from Kernel/RVAutoConf.HH (make -C templeos-riscv defconfig*).
#include "/Kernel/RVAutoConf.HH"
#include "/Kernel/Drv/RVSifivePlat.HC"
#include "/Kernel/Drv/RVUart.HC"
#include "/Kernel/Drv/RVTimer.HC"
I64 main()
{
  I64 t;
  RVUartInit();
  RVUartPutS("plat-smoke: machine=");
  RVUartPutS(CONFIG_PLATFORM_NAME);
  RVUartPutS("\n");
  RVUartPutS("plat-smoke: uart_ok\n");
  t = RVClintMtime();
  RVUartPutS("plat-smoke: clint_ok\n");
  if (RVSifivePresent) {
    RVSifiveUartPutS("plat-smoke: sifive_api\n");
    t = RVSifiveClintMtime();
    RVSifiveUartPutS("plat-smoke: sifive_clint_ok\n");
  }
  RVUartPutS("plat-smoke: PASS\n");
  return t & 0;
}
