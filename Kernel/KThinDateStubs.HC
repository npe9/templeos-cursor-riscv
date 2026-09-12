// KThinDateStubs.HC — RV_THIN_LOADER: drop KDate (~8 KiB Date2Struct/Struct2Date/
// Now*). Thin Jump never stamps files or formats %D/%T; SoftCall DateSoft
// (Kernel.BIN →'KG') owns real calendar + Goldfish RTC Now.
#ifndef K_THIN_DATE_STUBS_HC
#define K_THIN_DATE_STUBS_HC
I64 YearStartDate(I64 year)
{
  no_warn year;
  return 0;
}

CDate Struct2Date(CDateStruct *_ds)
{
  no_warn _ds;
  return 0;
}

I64 DayOfWeek(I64 i)
{
  no_warn i;
  return 0;
}

U0 Date2Struct(CDateStruct *_ds, CDate cdt)
{
  no_warn cdt;
  if (_ds)
    MemSet(_ds, 0, sizeof(CDateStruct));
}

I64 FirstDayOfMon(I64 i)
{
  no_warn i;
  return 0;
}

I64 LastDayOfMon(I64 i)
{
  no_warn i;
  return 0;
}

I64 FirstDayOfYear(I64 i)
{
  no_warn i;
  return 0;
}

I64 LastDayOfYear(I64 i)
{
  no_warn i;
  return 0;
}

I64 Bcd2Bin(U64 b)
{
  no_warn b;
  return 0;
}

U0 NowDateTimeStruct(CDateStruct *_ds)
{
  if (_ds)
    MemSet(_ds, 0, sizeof(CDateStruct));
}

CDate Now()
{
  return 0;
}
#endif
