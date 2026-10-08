/* SINGLE-PRECISION SUPPORT, BECAUSE HolyC HAS NO F32 AND LC COMPARES float32 VALUES.
 *
 * The compiler's type keywords are Bool F64 I16 I32 I64 I8 U0 U16 U32 U64 U8 -- checked in
 * host/lexer.c, not assumed. Real HolyC is the same: TempleOS has F64 and nothing narrower.
 *
 * cFS's Limit Checker reads a value out of a subscribed packet at a byte offset, interprets it as
 * one of twelve types -- two of which are 32-bit IEEE-754 singles, big and little endian -- and
 * compares it against a threshold from an uploaded table. NASA's LC_FloatCompare does ALL of its
 * arithmetic in `float`:
 *
 *     float WPFloat, CompareFloat, Diff;
 *     Diff       = (WPFloat > CompareFloat) ? (WPFloat - CompareFloat) : (CompareFloat - WPFloat);
 *     EvalResult = (Diff <= (float)LC_FLOAT_TOLERANCE) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
 *
 * so the SUBTRACTION is rounded to single precision before the comparison. Keeping the layout is
 * not enough; the arithmetic has to agree too.
 *
 * ### WHAT IS EXACT AND WHAT NEEDED WORK
 *
 * DECODING IS EXACT AND SO ARE ORDERED COMPARISONS. Every float32 value is representable in F64 --
 * 24 bits of significand and 8 of exponent inside 53 and 11 -- and the embedding is monotonic, so
 * `<`, `<=`, `>` and `>=` between two decoded values give exactly C's answers. Those four
 * operators need nothing but F32BitsToF64.
 *
 * THE SUBTRACTION DID NEED WORK. In F64 `a - b` of two float32 values is EXACT; in float32 it may
 * round. By Sterbenz's lemma it is exact in float32 too whenever the operands are within a factor
 * of two of each other -- which is the whole near-equal regime the tolerance exists to test -- so
 * the two would almost always agree. "Almost always" is not 1:1, so F64ToF32Bits rounds the
 * difference the way the C does and the argument is not needed.
 *
 * ### NaN AND Inf ARE BETTER ON THE BIT PATTERN
 *
 * NASA guards the comparison with isnan() and lets infinities through deliberately -- its comment
 * says "comparisons with infinite numbers will behave as they should so we don't try to catch
 * those (we would rather they generate watchpoint violations)". On the pattern, NaN and Inf are an
 * exponent field of all ones with a non-zero or zero mantissa: a mask and a compare, with no
 * dependence on how a host's isnan() treats a signalling NaN and no risk of raising an exception
 * by touching the value.
 *
 * Every function here is pinned by tests/exec/cases/e_f32_bits.hc against values computed by C.
 */
#ifndef CFS_F32_HC
#define CFS_F32_HC

/* The only way to see a double's bits in this language. `union X x;` is a C spelling the compiler
 * rejects -- the union's name IS the type, as a class's is. */
union CfsFBits
{
  F64 d;
  U64 u;
};

/* An exponent field of all ones means Inf or NaN; the mantissa tells which. */
Bool F32BitsIsNaN(U32 Bits)
{
  return (Bits & 0x7F800000) == 0x7F800000 && (Bits & 0x007FFFFF) != 0;
}

Bool F32BitsIsInf(U32 Bits)
{
  return (Bits & 0x7F800000) == 0x7F800000 && (Bits & 0x007FFFFF) == 0;
}

/* A float32 bit pattern as the F64 of exactly the same value. Exact for every input, including
 * subnormals, both zeros, both infinities and NaN (whose payload is carried into the double's top
 * mantissa bits, so a quiet NaN stays quiet).
 *
 * THE SUBNORMAL ARM IS THE ONLY ONE THAT COMPUTES ANYTHING. A float32 subnormal is
 * `mantissa * 2^-149` with the mantissa below 2^23, so it has no implicit leading one -- the loop
 * shifts the leading one up to bit 23, counting shifts k, which makes the value
 * `1.f * 2^(-126-k)` and the double's biased exponent `897 - k`. */
F64 F32BitsToF64(U32 Bits)
{
  CfsFBits Out;
  U64 Sign = (Bits >> 31) & 1;
  U64 Exp = (Bits >> 23) & 0xFF;
  U64 Mant = Bits & 0x7FFFFF;
  I64 Shift;

  if (Exp == 0) {
    if (Mant == 0) {
      /* Signed zero, and the sign has to survive: -0.0 is not 0.0 for a comparison that
         subtracts. */
      Out.u = Sign << 63;
    } else {
      Shift = 0;
      while (!(Mant & 0x800000)) {
        Mant <<= 1;
        Shift++;
      }
      Out.u = (Sign << 63) | ((897 - Shift)(U64) << 52) | ((Mant & 0x7FFFFF) << 29);
    }
  } else if (Exp == 0xFF) {
    /* Inf or NaN. The mantissa moves to the TOP of the double's, so the quiet bit stays the quiet
       bit rather than becoming a low payload bit. */
    Out.u = (Sign << 63) | (0x7FF(U64) << 52) | (Mant << 29);
  } else {
    Out.u = (Sign << 63) | ((Exp - 127 + 1023) << 52) | (Mant << 29);
  }

  return Out.d;
}

/* An F64 rounded to a float32 bit pattern, ROUND TO NEAREST WITH TIES TO EVEN -- which is what a
 * C compiler emits for an assignment to a `float`.
 *
 * The three hard parts, each of which a naive truncation gets wrong:
 *   - TIES TO EVEN, not away from zero: `Round` adds half an ulp and the `Sticky` term is what
 *     distinguishes an exact tie from just above one.
 *   - OVERFLOW GOES TO INFINITY, and it can be CREATED BY ROUNDING: a value just under the
 *     largest float32 can round up to 2^128, so the overflow test is after the increment.
 *   - UNDERFLOW GOES TO A SUBNORMAL AND THEN TO ZERO, gradually, so the small-exponent arm shifts
 *     the significand right by a variable amount and rounds what it shifted out. */
U32 F64ToF32Bits(F64 Value)
{
  CfsFBits In;
  U64 Sign;
  I64 Exp;
  U64 Mant;
  U64 Round;
  U64 Sticky;
  I64 Shift;
  U32 Out;

  In.d = Value;
  Sign = (In.u >> 63) & 1;
  Exp = (In.u >> 52) & 0x7FF;
  Mant = In.u & 0xFFFFFFFFFFFFF;

  if (Exp == 0x7FF) {
    /* Inf or NaN straight through. A NaN keeps its top payload bits and stays non-zero, so it
       stays a NaN rather than becoming an infinity. */
    if (Mant == 0)
      return (Sign << 31)(U32) | 0x7F800000;
    Out = (Sign << 31)(U32) | 0x7F800000 | ((Mant >> 29) & 0x7FFFFF);
    if ((Out & 0x7FFFFF) == 0)
      Out |= 1; /* a NaN whose payload was entirely in the low bits must not become Inf */
    return Out;
  }

  if (Exp == 0) {
    /* A double zero or subnormal is far below float32's range: zero, with the sign. */
    return (Sign << 31)(U32);
  }

  /* Unbias, then re-bias for float32. */
  Exp = Exp - 1023 + 127;
  /* The implicit leading one, made explicit, so one code path handles normal and subnormal. */
  Mant |= 0x10000000000000;

  if (Exp <= 0) {
    /* Gradual underflow. Shifting right by (1 - Exp) more than the usual 29 lands the value in
       the subnormal range; a shift of 54 or more loses everything. */
    Shift = 29 + 1 - Exp;
    if (Shift > 63)
      return (Sign << 31)(U32);
    Round = (Mant >> (Shift - 1)) & 1;
    Sticky = 0;
    if ((Mant & (((1(U64)) << (Shift - 1)) - 1)) != 0)
      Sticky = 1;
    Out = (Mant >> Shift)(U32);
    if (Round && (Sticky || (Out & 1)))
      Out++;
    /* Rounding up out of the subnormal range produces the smallest NORMAL, which is exactly what
       the pattern 0x00800000 already means -- so no special case is needed. */
    return (Sign << 31)(U32) | Out;
  }

  /* The normal path: 53 significand bits down to 24, so 29 shifted out. */
  Round = (Mant >> 28) & 1;
  Sticky = 0;
  if ((Mant & 0xFFFFFFF) != 0)
    Sticky = 1;
  Mant = Mant >> 29;
  if (Round && (Sticky || (Mant & 1))) {
    Mant++;
    if (Mant & 0x1000000) {
      /* The increment carried out of the significand: halve it and step the exponent. */
      Mant >>= 1;
      Exp++;
    }
  }

  if (Exp >= 0xFF) {
    /* Overflow, including overflow CREATED by the rounding above. */
    return (Sign << 31)(U32) | 0x7F800000;
  }

  /* NOTE THE PARENTHESES AROUND EACH CAST OPERAND. HolyC's cast is POSTFIX -- `expr(TYPE)` -- so
     `Exp(U32)` on a bare identifier parses as a CALL to Exp with an argument named U32, and the
     compiler says "Undefined variable 'U32'". A parenthesised operand is unambiguous. */
  return (Sign << 31)(U32) | (((Exp) & 0xFF)(U32) << 23) | (((Mant) & 0x7FFFFF)(U32));
}

#endif
