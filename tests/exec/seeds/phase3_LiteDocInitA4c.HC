// Soft tip micro-rung A4c: return the DECAYED address of the planted member, and write
// nothing. A4 proves the decayed pointer is wrong by zeroing its own module with it; this
// rung just hands the value back so the kernel can compare it against the real
// &doldoc.dft_de_flags and say by how much it is wrong.
//
// A1-A3 cannot catch this: they only check SELF-CONSISTENCY (store then read back, or
// non-zero), which a uniformly wrong base satisfies. A4c is the first rung to check the
// address against ground truth.
#include "A:/Compiler/DolDocDefines.HC"
public I64 RVDocInitA4cSelfTest()
{
  I64 a;
  a = doldoc.dft_de_flags;
  return a;
}
