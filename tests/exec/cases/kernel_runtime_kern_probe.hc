// Product Runtime Kern.BIN companion for Kernel.BIN SoftCall Load+HashFind+Call (G9).
// SoftCall Load("A:/Runtime/Kern.BIN") + HashFind("KernInit") → 42.
// StartOS Seed→Svc→Kern chain tip shape: arg call + n+n+n (KernBase+KernScale(9)).
// Single-file pack (no KernMem #include) — same closed-loop needle as phase3 Kern.
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
