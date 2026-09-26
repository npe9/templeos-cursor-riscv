// Abs/Sqr/Floor/Trunc compute the right answers. BEHAVIOUR ONLY — read the next paragraph before
// trusting this case for anything else.
//
// This case CANNOT detect the bug it was written for. `Abs` lives in an asm{} block in
// Kernel/KUtilsRV.HC written with `fabsd`, a PSEUDO-instruction (fabs.d rd,rs IS fsgnjx.d rd,rs,rs;
// there is no fabs.d opcode). The assembler rejected the block, so `Abs` left the blob and became
// an unresolved host-import — and this harness links tests/exec/harness/oracle_out.c, whose C
// runtime (bootstrap/holy_rt_names.h) supplies `Abs` and answers correctly. Measured, both ways:
// this case returns 0x3f with the block present AND with it dropped, in two different versions of
// it, including one written with opaque non-constant arguments to defeat folding.
//
// The gate that does discriminate is tests/scripts/check_blob_imports.sh, which asserts these
// names are resolved INSIDE the blob. Keep both: that one proves the code is there, this one
// proves it computes.
//
// Arguments still come from an opaque call — with literals the compiler folds the whole thing and
// the case stops exercising any implementation at all.
#include "/Kernel/Kernel_RV.PRJ"
F64 noinline_f64(F64 d) { return d; }   // opaque to the constant folder
I64 main()
{
  F64 n = noinline_f64(-3.25), p = noinline_f64(3.25), z = noinline_f64(0.0),
      q = noinline_f64(-4.0), h = noinline_f64(-2.5);
  return (Abs(n) == 3.25) * 1 + (Abs(p) == 3.25) * 2 + (Abs(z) == 0.0) * 4 +
         (Sqr(q) == 16.0) * 8 + (Floor(h) == -3.0) * 16 + (Trunc(h) == -2.0) * 32;
  // 0x3f
}
