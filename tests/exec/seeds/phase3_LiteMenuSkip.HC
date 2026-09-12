U8 *RVMenuSkipCont(U8 *p)
{
  while (p && *p) {
    if (*p == 32 || *p == 9 || *p == 13 || *p == 10) {
      p++;
      continue;
    }
    break;
  }
  return p;
}

public I64 RVMenuSkipContSelfTest()
{
  U8 *p;
  p = RVMenuSkipCont(" \tx");
  if (!p)
    return 0;
  return *p;
}
