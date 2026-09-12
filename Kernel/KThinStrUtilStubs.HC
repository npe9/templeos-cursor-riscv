// KThinStrUtilStubs.HC — RV_THIN_LOADER: drop StrUtil/MStrUtil + tab helpers
// (~8 KiB). Path normalize lives in gated MakeBlkDev; SoftCall StrUtilSoft owns
// real StrUtil/MStrUtil path-normalize flags in Kernel.BIN (→'SU').
#ifndef K_THIN_STRUTIL_STUBS_HC
#define K_THIN_STRUTIL_STUBS_HC
U8 *StrUtil(U8 *_src, I64 flags)
{
  no_warn flags;
  return _src;
}

U8 *MStrUtil(U8 *src, I64 flags, F64 indent_scale_factor = 0)
{
  no_warn flags;
  no_warn indent_scale_factor;
  if (!src)
    return StrNew("");
  return StrNew(src);
}

U0 GetOutOfDollar()
{
}
#endif
