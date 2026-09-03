// Verifies NowDateTimeStruct reads the QEMU virt Goldfish RTC (MMIO) and Date2Struct yields a sane
// wall-clock date. QEMU returns the host time, so the exact date varies -- check field ranges only.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  CDateStruct ds;
  I64 r = 0;
  NowDateTimeStruct(&ds);
  if (ds.year >= 2020 && ds.year <= 2100)
    r += 1;
  if (ds.mon >= 1 && ds.mon <= 12)
    r += 2;
  if (ds.day_of_mon >= 1 && ds.day_of_mon <= 31)
    r += 4;
  if (ds.hour <= 23 && ds.min <= 59 && ds.sec <= 59)
    r += 8;
  return r;
  // 0xf
}
