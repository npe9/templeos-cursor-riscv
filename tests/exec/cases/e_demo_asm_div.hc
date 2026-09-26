// Demo/Asm/DivByHand.HC's restoring division, translated from x86 to RISC-V, actually divides.
//
// The demo survey cannot check this. It compiles each demo with RV_NO_DEMO_AUTORUN defined, which
// guards off the top-level statement — and for this demo that statement IS the only call. So the
// survey's L1-OK means "compiled, linked and booted", not "the algorithm works". Same distinction
// the whole port keeps running into: reaching the end is not doing the job.
//
// Edge cases matter for a shift-and-add divider: exact division, a remainder, division by 1,
// a divisor larger than the dividend (quotient 0), and a dividend with the top bit set, which is
// where the x86 original used the carry flag and the RISC-V version has to extract the bit by hand.
#include "/Kernel/Kernel_RV.PRJ"
#define RV_NO_DEMO_AUTORUN
#include "/Demo/Asm/DivByHand.HC"
I64 opaque(I64 v) { return v; }
I64 main()
{
  I64 r = 0;
  r += (DivU64ByU64(opaque(123456), opaque(10)) == 12345) * 1;   // the demo's own line
  r += (DivU64ByU64(opaque(100), opaque(7)) == 14) * 2;          // 14 rem 2
  r += (DivU64ByU64(opaque(42), opaque(1)) == 42) * 4;           // divide by 1
  r += (DivU64ByU64(opaque(5), opaque(9)) == 0) * 8;             // divisor > dividend
  r += (DivU64ByU64(opaque(0), opaque(3)) == 0) * 16;
  // Top bit set: unsigned, and the bit that x86 moved through the carry flag.
  r += (DivU64ByU64(opaque(0x8000000000000000), opaque(2)) == 0x4000000000000000) * 32;
  r += (DivU64ByU64(opaque(-1), opaque(-1)) == 1) * 64;          // U64 max / U64 max
  return r;
  // 0x7f
}
