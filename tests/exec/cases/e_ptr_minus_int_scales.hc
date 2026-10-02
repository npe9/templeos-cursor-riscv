// POINTER MINUS INTEGER SCALES BY THE POINTEE, AND A CAST IS THE ONLY WAY BACK TO BYTES.
//
// This is C's rule, and the translation broke it by dropping a cast NASA wrote on purpose.
// cfe_sb_priv.c finds a buffer DESCRIPTOR from the buffer an app holds by subtracting the
// member offset, and it writes the subtraction on an INTEGER:
//
//     BufDscAddr = (cpuaddr)BufPtr - offsetof(CFE_SB_BufferD_t, Content);
//
// The first translation of that line dropped the `(cpuaddr)`, so `BufPtr - 56` subtracted 56
// WHOLE CFE_SB_Buffer structures. Nothing diagnosed it. The descriptor pointer came back inside
// another buffer's payload, and the failure surfaced as a store fault in
// CFE_SB_TrackingListRemove unlinking a node whose Prev was a fragment of a file header --
// three functions and one module away from the arithmetic.
//
// So the rule is pinned here, in both directions, for a pointee size that could not be confused
// with anything else. Everything is converted to I64 before being compared, because a pointer
// DIFFERENCE scales too and would hide the thing under test.
class Big
{
  U8 x[200];
};

I64 main()
{
  U8 buf[1600];
  Big *b;
  U8 *q;
  I64 base;
  I64 r = 0;
  b = &buf[800];
  base = b(I64);
  // THE BARE FORM SCALES. `b - 3` is three Bigs back, 600 bytes.
  q = b - 3;
  r = r * 10000 + (base - q(I64));
  // 600
  // THE CAST FORM DOES NOT. This is what the translation has to write wherever NASA casts.
  q = b(U8 *) - 3;
  r = r * 10000 + (base - q(I64));
  // 3
  // And forwards, for the same reason: `+` is the shape the host compiler already had a
  // recorded quirk about (docs/HOLYC_STRUCT_LIMITS.md), so both operators are measured.
  q = b + 2;
  r = r * 10000 + (q(I64) - base);
  // 400
  q = b(U8 *) + 2;
  r = r * 10000 + (q(I64) - base);
  // 2
  return r;
}
