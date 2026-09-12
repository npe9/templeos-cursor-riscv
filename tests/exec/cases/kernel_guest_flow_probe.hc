// Guest Cmp source: lands on RedSea as A:/Compiler/SoftFlow.HC.
// Kernel.BIN SoftCall reads these bytes off the disk at runtime and hands them
// to the in-BIN lite Prs (KernelPrsGlblFunDefSoft), which Cmps and Calls them.
// Nothing here is an in-BIN literal; the Mac phase3.elf is not in the loop.
// Shape mirrors Compiler/OptPass_RV.HC: a for that sweeps the IC array one slot
// per pass, a while that drains the residue, and an if/else that classifies what
// is left. Every branch is load-bearing, so a folded or dead branch shows up as a
// wrong answer rather than a still-green 42:
//   Scan  5 slots * 7 = 35 (a for that never runs leaves 0)
//   Peel  7 -> 5 -> 3 -> 1 (a while that never runs leaves 7, so the else misses)
//   Fold  35 + 7 = 42
I64 g_rv_opt_ic_n;
I64 g_rv_opt_hits;
I64 RvOptPassScan()
{
  I64 i, hits;
  hits = 0;
  for (i = 0; i - g_rv_opt_ic_n; i = i + 1)
    hits = hits + 7;
  g_rv_opt_hits = hits;
  return hits;
}

I64 RvOptPassPeel()
{
  I64 n, r;
  n = 7;
  while (n - 1)
    n = n - 2;
  if (n - 1)
    r = 0;
  else
    r = 7;
  return r;
}

I64 RvOptPassFold()
{
  I64 hits, r;
  g_rv_opt_ic_n = 5;
  hits = RvOptPassScan();
  r = RvOptPassPeel();
  return hits + r;
}
RvOptPassFold();
