public I64 KernScale(I64 n)
{
  return n + n + n;
}

public I64 KernBase()
{
  return 15;
}

public I64 KernInit()
{
  return KernBase + KernScale(9);
}
