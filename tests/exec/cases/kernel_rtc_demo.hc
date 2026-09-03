// Goldfish RTC smoke: read wall-clock ns via RVRtc on QEMU virt.
#include "/Kernel/RVAutoConf.HH"
#include "/Kernel/Drv/RVUart.HC"
#include "/Kernel/Drv/RVRtc.HC"
I64 main()
{
  I64 ns, secs;
  RVUartInit();
  RVUartPutS("rtc-smoke: boot\n");
  if (!RVRtcPresent) {
    RVUartPutS("rtc-smoke: FAIL absent\n");
    return 1;
  }
  ns = RVRtcReadNs;
  secs = ns / 1000000000;
  // QEMU host time — accept anything past 2020-01-01 and before 2100.
  if (secs < 1577836800 || secs > 4102444800) {
    RVUartPutS("rtc-smoke: FAIL range\n");
    return 1;
  }
  RVUartPutS("rtc-smoke: PASS\n");
  return 0;
}
