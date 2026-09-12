// Product Runtime Svc.BIN companion for Kernel.BIN SoftCall Load+HashFind+Call (G9).
// SoftCall Load("A:/Runtime/Svc.BIN") + HashFind("RuntimeSvcProbe") → 42.
// StartOS Seed→Svc→Kern chain tip shape: F()→F() (RuntimeSvcVal), no Cmp.
// Single-file pack (no SvcLib #include) — same closed-loop needle as phase3 Svc.
public I64 RuntimeSvcVal()
{
  return 42;
}

public I64 RuntimeSvcProbe()
{
  return RuntimeSvcVal;
}
