// FE310 / sifive_e fuller tiny-Kernel smoke (dual artifact vs slim plat.elf).
// Kernel_FE310.PRJ runs from XIP; DTIM holds bootloader + .data/.bss/stack only.
#include "/Kernel/Kernel_FE310.PRJ"
I64 main()
{
  I64 t, id;
  U8 *drv;
  RVUartInit();
  RVUartPutS("fe310-full: machine=");
  RVUartPutS(CONFIG_PLATFORM_NAME);
  RVUartPutS("\n");
  RVUartPutS("fe310-full: uart_ok\n");
  t = RVClintMtime();
  RVUartPutS("fe310-full: clint_ok\n");
  if (RVSifivePresent) {
    RVSifiveUartPutS("fe310-full: sifive_api\n");
    t = RVSifiveClintMtime();
    RVSifiveUartPutS("fe310-full: sifive_clint_ok\n");
    if (RVSifiveCanReset)
      RVSifiveUartPutS("fe310-full: sifive_can_reset\n");
    else
      RVSifiveUartPutS("fe310-full: sifive_no_hw_reset\n");
    RVSifivePlicSetThreshold(0);
    RVSifivePlicEnable(CONFIG_UART_IRQ, 1);
    id = RVSifivePlicClaim();
    RVSifivePlicComplete(id);
    RVSifiveUartPutS("fe310-full: sifive_plic_ok\n");
    t = RVSifiveTestBase() | RVSifiveAonBase() | RVSifiveGpioBase();
  }
  RVPlicSetThreshold(0);
  RVPlicEnable(CONFIG_UART_IRQ, 1);
  id = RVPlicClaim();
  RVPlicComplete(id);
  RVUartPutS("fe310-full: plic_ok\n");
  RVMemMap();
  drv = RVMemMapDrvUart();
  if (drv)
    RVUartPutS("fe310-full: memmap_drv_ok\n");
  RVUartPutS("fe310-full: PASS\n");
  return t & 0;
}
