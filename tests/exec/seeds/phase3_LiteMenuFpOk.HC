I64 RVMenuFpOk(I64 fp)
{
  if (!fp)
    return 0;
  if (fp & 1)
    return 0;
  if (fp < 0x10000)
    return 0;
  return 1;
}

I64 RVMenuFpsWired(I64 a, I64 b, I64 c, I64 d)
{
  if (!RVMenuFpOk(a))
    return 0;
  if (!RVMenuFpOk(b))
    return 0;
  if (!RVMenuFpOk(c))
    return 0;
  if (!RVMenuFpOk(d))
    return 0;
  return 1;
}

public I64 RVMenuFpOkSelfTest()
{
  I64 good;
  if (RVMenuFpOk(0))
    return 1;
  if (RVMenuFpOk(1))
    return 2;
  if (RVMenuFpOk(0x1000))
    return 3;
  if (!RVMenuFpOk(0x20000))
    return 4;
  if (!RVMenuFpOk(0x80001000))
    return 7;
  good = 0x80001000;
  if (!RVMenuFpOk(good))
    return 9;
  if (RVMenuFpsWired(0x20000, 0x21000, 0x22000, 1))
    return 5;
  if (!RVMenuFpsWired(0x20000, 0x21000, 0x22000, 0x23000))
    return 6;
  return 8;
}
