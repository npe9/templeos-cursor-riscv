// Thin-only stubs when StrScan.HC is gated (SoftCall path never parses numbers).
#ifndef K_THIN_STRSCAN_STUBS_HC
#define K_THIN_STRSCAN_STUBS_HC
I64 Str2I64(U8 *st, I64 radix = 10, U8 **_end_ptr = NULL)
{
  no_warn st;
  no_warn radix;
  if (_end_ptr)
    *_end_ptr = st;
  return 0;
}

F64 Str2F64(U8 *st, U8 **_end_ptr = NULL)
{
  no_warn st;
  if (_end_ptr)
    *_end_ptr = st;
  return 0.0;
}

CDate Str2Date(U8 *st)
{
  no_warn st;
  return 0;
}

I64 StrScan(U8 *src, U8 *fmt,...)
{
  no_warn src;
  no_warn fmt;
  return 0;
}
#endif
