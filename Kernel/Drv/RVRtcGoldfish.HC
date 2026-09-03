// QEMU Goldfish RTC (virt @ CONFIG_RTC_BASE). TIME_LOW latches TIME_HIGH.
#ifndef RV_DRV_RTC_GOLDFISH_HC
#define RV_DRV_RTC_GOLDFISH_HC
#ifndef CONFIG_RTC_BASE
#define CONFIG_RTC_BASE 0x00101000
#endif
#define RV_RTC_TIME_LOW  0
#define RV_RTC_TIME_HIGH 1
I64 RVRtcBase()
{
  return CONFIG_RTC_BASE;
}

Bool RVRtcPresent()
{
  return TRUE;
}

I64 RVRtcReadNs()
{
  //Nanoseconds since Unix epoch (host wall clock). Read LOW then HIGH.
  U32 *rtc = CONFIG_RTC_BASE;
  U64 lo, hi;
  lo = rtc[RV_RTC_TIME_LOW];
  hi = rtc[RV_RTC_TIME_HIGH];
  return lo | (hi << 32);
}
#endif
