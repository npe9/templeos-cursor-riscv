// Guest Cmp source: lands on RedSea as A:/Compiler/SoftArg.HC.
// Kernel.BIN SoftCall reads these bytes off the disk at runtime and hands them
// to the in-BIN lite Prs (KernelPrsGlblFunDefSoft), which Cmps and Calls them.
// Nothing here is an in-BIN literal; the Mac phase3.elf is not in the loop.
// Shape mirrors the per-IC cost walk Compiler/OptPass_RV.HC does: one helper that
// takes the opcode and a width flag, and two call sites that hand it different
// values. Arguments are load-bearing in both positions, so a helper that ignored
// a1, or a Cmp that folded the callee to a fixed answer, gives a wrong total:
//   Cost(code, wide)  code * 3, plus 4 more when the wide flag is set
//   Sum   Cost(2, 1) = 10 and Cost(8, 0) = 24, banked in a file-scope cell
//   Tally 34 + 8 = 42
// Only a0 and a1 can carry that: a fixed-arg callee returns 10 + 28 or 6 + 24.
I64 g_rv_ic_cost;
I64 RvIcOpCost(I64 code, I64 wide)
{
  I64 c;
  c = code * 3;
  if (wide)
    c = c + 4;
  return c;
}

I64 RvIcOpSum()
{
  I64 a, b;
  a = RvIcOpCost(2, 1);
  b = RvIcOpCost(8, 0);
  g_rv_ic_cost = a + b;
  return a + b;
}

I64 RvIcOpTally()
{
  return RvIcOpSum() + 8;
}
RvIcOpTally();
