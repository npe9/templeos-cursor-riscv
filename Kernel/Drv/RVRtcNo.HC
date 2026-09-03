// No Goldfish RTC on this board.
#ifndef RV_DRV_RTC_NO_HC
#define RV_DRV_RTC_NO_HC
I64 RVRtcBase()
{
  return 0;
}

Bool RVRtcPresent()
{
  return FALSE;
}

I64 RVRtcReadNs()
{
  return 0;
}
#endif
