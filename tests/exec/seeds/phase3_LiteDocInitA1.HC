// Soft tip micro-rung A1: bare read of Kernel doldoc.hash (asm_hash plant only).
// Ladder rung A ("doldoc plant") failed guest Cmp with ERROR: Missing expression;
// A1..A4 split it so the erroring construct is named in one run.
public I64 RVDocInitA1SelfTest()
{
  if (!doldoc.hash)
    return 2;
  return 1;
}
