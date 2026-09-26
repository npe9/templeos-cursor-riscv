// Sin/Cos/Tan/ATan/Ceil are computed BY THE PORT and agree with libm.
//
// All five were unresolved imports in every image: nothing under Kernel/ defined them, so the C
// runtime in bootstrap/holy_rt.h answered — including for Kernel/KUtilsRV.HC's own RVF64Sin/Cos/Tan/
// ATan wrappers, whose entire purpose is to hand the guest JIT a callable Sin. They are now HolyC
// over the native RISC-V FPU, ported from rt_sin/rt_atan loop-for-loop so the results match.
//
// Reference values are CPython's math module, not the port's own output, so this is a comparison
// against something independent rather than a re-pin of whatever it happens to produce. Tolerance
// 1e-12: the ported series is 12 terms for Sin and 40 for ATan, not a correctly-rounded libm.
//
// BEHAVIOUR ONLY — this case CANNOT tell the port's Sin from the C runtime's, and that was MEASURED,
// not assumed: it returns 0x3ff at the parent commit too, where all five were unresolved. The gate
// that discriminates is tests/scripts/check_blob_imports.sh, which asserts these names are resolved
// INSIDE the blob. Keep both: that one proves whose code runs, this one proves it is right.
//
// Arguments come through an opaque call — with literals the compiler folds these away and the case
// stops exercising any implementation at all, which is how a first version of e_kernel_fabs.hc lied.
#include "/Kernel/Kernel_RV.PRJ"
F64 opaque(F64 d) { return d; }
Bool Near(F64 a, F64 b) { return Abs(a - b) < 1.0e-12; }
I64 main()
{
  I64 r = 0;
  r += Near(Sin(opaque(1.0)),   0.841470984807897) * 1;
  r += Near(Cos(opaque(1.0)),   0.540302305868140) * 2;
  r += Near(Tan(opaque(1.0)),   1.557407724654902) * 4;
  r += Near(ATan(opaque(1.0)),  0.785398163397448) * 8;
  // |x|>1 takes the reciprocal identity, a different branch.
  r += Near(ATan(opaque(3.0)),  1.249045772398254) * 16;
  // Outside [-PI,PI], so this is the range reduction, not the series.
  r += Near(Sin(opaque(10.0)), -0.544021110889370) * 32;
  r += Near(Cos(opaque(-4.0)), -0.653643620863612) * 64;
  r += (Ceil(opaque(2.1)) == 3.0) * 128;
  r += (Ceil(opaque(-2.1)) == -2.0) * 256;
  // Already integral: Ceil must not add one.
  r += (Ceil(opaque(3.0)) == 3.0) * 512;
  return r;
  // 0x3ff
}
