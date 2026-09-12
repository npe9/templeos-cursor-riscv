I64 g_fp_open;
I64 g_fp_resolve;
I64 SoftPopUpFpOk(I64 fp)
{
  if (!fp)
    return 0;
  return 1;
}

I64 SoftPopUpFpsWired()
{
  if (!SoftPopUpFpOk(g_fp_open))
    return 0;
  if (!SoftPopUpFpOk(g_fp_resolve))
    return 0;
  return 1;
}

I64 SoftPopUpOkSoft(I64 tag)
{
  if (!SoftPopUpFpsWired)
    return 0;
  if (!tag)
    return 0;
  return 1;
}

I64 SoftPopUpResolveSoft(I64 val)
{
  if (!SoftPopUpFpOk(g_fp_resolve))
    return 0;
  if (!val)
    return 0;
  return 1;
}

public I64 RVPopUpSoftFpSelfTest()
{
  g_fp_open = 0;
  g_fp_resolve = 0;
  if (SoftPopUpOkSoft(7))
    return 1;
  g_fp_open = 1;
  g_fp_resolve = 1;
  if (!SoftPopUpFpsWired)
    return 2;
  if (!SoftPopUpOkSoft(7))
    return 3;
  if (!SoftPopUpResolveSoft(1))
    return 4;
  g_fp_resolve = 0;
  if (SoftPopUpResolveSoft(1))
    return 5;
  return 8;
}
