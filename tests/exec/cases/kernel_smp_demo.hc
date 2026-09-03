// Phase G SMP smoke: hart0 wakes hart1; hart1 amoadd's a shared counter; UART reports.
// Link with crt0_smp.S and run: qemu-system-riscv64 -M virt -smp 2 -bios none -kernel …
#include "/Kernel/RVAutoConf.HH"
#include "/Kernel/Drv/RVUart.HC"
#include "/Kernel/Drv/RVSmp.HC"
I64 g_cnt;
I64 SethWork(I64 arg)
{
  RVAmoAddI64(&g_cnt, 1);
  RVAmoAddI64(&g_cnt, arg);
  return 0;
}

I64 main()
{
  I64 alive, i;
  RVUartInit();
  RVUartPutS("smp-smoke: hart0 boot\n");
  // Wait briefly for hart1 to set its alive bit
  i = 0;
  while (i < 1000000) {
    alive = RVSmpAlive();
    if (alive & 2)
      break;
    i++;
  }
  if (!(alive & 2)) {
    RVUartPutS("smp-smoke: FAIL no hart1\n");
    return 1;
  }
  if (RVSmpMpCnt < 2) {
    RVUartPutS("smp-smoke: FAIL mp_cnt\n");
    return 1;
  }
  g_cnt = 0;
  RVSmpWakeHart(1, &SethWork, 41);
  RVSmpWait();
  if (g_cnt != 42) {
    RVUartPutS("smp-smoke: FAIL bad counter\n");
    return 1;
  }
  RVUartPutS("smp-smoke: hart1_count=42 PASS\n");
  return 0;
}
