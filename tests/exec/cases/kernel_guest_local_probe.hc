// Guest Cmp source: lands on RedSea as A:/Compiler/SoftLocal.HC.
// Kernel.BIN SoftCall reads these bytes off the disk at runtime and hands them
// to the in-BIN lite Prs (KernelPrsGlblFunDefSoft), which Cmps and Calls them.
// Nothing here is an in-BIN literal; the Mac phase3.elf is not in the loop.
// Shape mirrors Compiler/PrsLib_RV.HC: one file-scope glbl plus body-scope frame
// locals that a caller keeps live across a jal ra into a callee declaring the
// same local name. RvPrsFrameLeaf writes the glbl and returns 1 out of its own
// frame; RvPrsFrameSum holds 41 in its frame while that call runs, so a shared
// or plant-folded slot would return 2 instead of 41 + 1 = 42.
I64 g_rv_prs_depth;
I64 RvPrsFrameLeaf()
{
  I64 mark;
  mark = 1;
  g_rv_prs_depth = 7;
  return mark;
}

I64 RvPrsFrameSum()
{
  I64 mark, acc;
  mark = 41;
  acc = RvPrsFrameLeaf();
  return mark + acc;
}
RvPrsFrameSum();
