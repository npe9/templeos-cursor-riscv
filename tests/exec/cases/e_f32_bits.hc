// SINGLE-PRECISION SUPPORT, PINNED AGAINST IEEE-754. HolyC has no F32 -- the compiler's type
// keywords are Bool F64 I16 I32 I64 I8 U0 U16 U32 U64 U8 -- and cFS's Limit Checker compares
// 32-bit floats pulled out of telemetry packets, so Kernel/Cfs/CfsF32.HC implements the two
// conversions by hand. This case is what says they are right.
//
// TWO CHECKSUMS, because the two directions fail differently:
//
//   ROUND TRIP   every float32 pattern decoded to F64 and re-encoded must come back IDENTICAL.
//                Catches a decode that loses the sign of zero, mishandles a subnormal, or turns a
//                NaN into an infinity. Includes both zeros, the smallest and largest subnormals,
//                the smallest and largest normals, both infinities, a quiet NaN and a SIGNALLING
//                NaN -- which must stay signalling.
//
//   ROUNDING     thirteen DOUBLES that are not float32 values, rounded to nearest with ties to
//                even. Catches the three things a naive truncation gets wrong: a tie (2^24+1 must
//                go DOWN to 2^24, 2^24+3 must go UP), gradual underflow (half the smallest
//                subnormal is an exact tie and must go to ZERO, 1.5x it must go to 2), and
//                overflow (1e300 must become +Inf, while a double just below FLT_MAX must stay
//                FLT_MAX rather than rounding up to it).
//
// Both expected values come from IEEE-754 single-rounding of the same inputs, not from this
// implementation.
#include "/Kernel/Cfs/CfsF32.HC"

I64 main()
{
  U32 pats[18];
  U64 dbls[13];
  CfsFBits b;
  I64 i;
  U64 chk1 = 0;
  U64 chk2 = 0;

  pats[0]  = 0x00000000; // +0
  pats[1]  = 0x80000000; // -0, and the sign must survive the trip
  pats[2]  = 0x00000001; // smallest subnormal
  pats[3]  = 0x007FFFFF; // largest subnormal
  pats[4]  = 0x00800000; // smallest normal
  pats[5]  = 0x7F7FFFFF; // largest normal
  pats[6]  = 0x3F800000; // 1.0
  pats[7]  = 0xBF800000; // -1.0
  pats[8]  = 0x40490FDB; // pi
  pats[9]  = 0xC0490FDB; // -pi
  pats[10] = 0x7F800000; // +Inf
  pats[11] = 0xFF800000; // -Inf
  pats[12] = 0x7FC00000; // quiet NaN
  pats[13] = 0x7F800001; // SIGNALLING NaN -- must not become Inf
  pats[14] = 0x12345678;
  pats[15] = 0x00000002;
  pats[16] = 0x15F79688; // (float)1e-25, LC_FLOAT_TOLERANCE as LC actually uses it
  pats[17] = 0x7F7FFFFE;

  for (i = 0; i < 18; i++)
    chk1 = chk1 * 31 + F64ToF32Bits(F32BitsToF64(pats[i]));

  dbls[0]  = 0x3FD5555555555555; // 1/3
  dbls[1]  = 0x3ABEF2D0F5DA7DD9; // 1e-25
  dbls[2]  = 0x4170000010000000; // 2^24+1  -- an exact TIE, must round DOWN to 2^24
  dbls[3]  = 0x4170000030000000; // 2^24+3  -- must round UP
  dbls[4]  = 0x47EFFFFFE0000000; // just below FLT_MAX, must stay FLT_MAX
  dbls[5]  = 0x7E37E43C8800759C; // 1e300, must become +Inf
  dbls[6]  = 0x3690000000000000; // half the smallest subnormal -- a TIE, must go to ZERO
  dbls[7]  = 0x36A8000000000000; // 1.5x the smallest subnormal, must go to 2
  dbls[8]  = 0x3810000000000000; // float32's smallest normal, exact
  dbls[9]  = 0xBFD5555555555555; // -1/3
  dbls[10] = 0x3379B604AAACA626; // 1e-60, must go to zero
  dbls[11] = 0x7FF0000000000000; // +Inf
  dbls[12] = 0x7FF8000000000000; // quiet NaN

  for (i = 0; i < 13; i++) {
    b.u = dbls[i];
    chk2 = chk2 * 31 + F64ToF32Bits(b.d);
  }

  // Both checksums folded into one answer: the low 32 bits of each.
  return ((chk1 & 0xFFFFFFFF) << 32) | (chk2 & 0xFFFFFFFF);
}
