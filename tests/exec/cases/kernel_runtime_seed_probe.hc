// Product Runtime Seed.BIN companion for Kernel.BIN SoftCall Load+HashFind+Call (G9).
// SoftCall Load("A:/Runtime/Seed.BIN") + HashFind("RuntimeSeedInit") → 42.
// StartOS Seed→Svc→Kern chain tip shape: F()+imm (RuntimeSeedVal+27), no Cmp.
// Single-file pack (no SeedLib #include) — same closed-loop needle as phase3 Seed.
public I64 RuntimeSeedVal()
{
  return 15;
}

public I64 RuntimeSeedInit()
{
  return RuntimeSeedVal + 27;
}
