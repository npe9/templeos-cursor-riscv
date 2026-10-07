// A CLASS PARAMETER PASSED BY VALUE CARRIES ONLY ITS FIRST 8 BYTES.
//
// Silent. No diagnostic, no refusal -- and the bytes past the first eight are not zero or
// garbage but THE NEXT ARGUMENT'S VALUE, which is a plausible number. This is the sibling of
// docs/HOLYC_STRUCT_LIMITS.md #21 (a struct copy into an array slot or through a bare pointer)
// in the other syntactic position, and the compiler's treatment of the three forms is
// inconsistent:
//
//   return a class > 8 bytes      REFUSED, with a diagnostic (tests/holyc/refused/)
//   assign a class > 8 bytes      first 8 bytes, silently          (#21)
//   PASS a class > 8 bytes        first 8 bytes, silently          (#26, this file)
//
// THE BOUNDARY IS EIGHT AND THAT IS THE POINT OF THE 16-BYTE CASE. The RISC-V LP64D ABI passes
// a 16-byte struct in a REGISTER PAIR, so 16 is where a reader expects this to work -- and
// where tools/cfs/check_struct_copy.py's limit of 8 would be rejecting correct code if the
// expectation held. It does not: one register, never two.
//
// `tag` is the argument AFTER the class in every call, and it is what the truncated bytes read
// back as. Its value is 5 so that a nibble can tell it apart from the field's real contents.
I64 main();

class Big                   // 72 bytes
{
  U64 Offset;
  U8 Name[64];
};
class Two                   // 16 bytes -- a register PAIR in the C ABI, not here
{
  U64 A;
  U64 B;
};
class Half                  // 8 bytes -- fits one register, so it is whole
{
  U32 A;
  U32 B;
};

I64 TakeBig(Big b, I64 tag)
{
  return (b.Offset << 8) | (b.Name[0] << 4) | tag;
}

I64 TakeTwo(Two t, I64 tag)
{
  return (t.A << 8) | (t.B << 4) | tag;
}

I64 TakeHalf(Half h, I64 tag)
{
  return (h.A << 8) | (h.B << 4) | tag;
}

// A by-value copy must not reach the caller, and the first eight bytes really ARE a copy --
// which is what rules out "the class is silently passed by reference" as the explanation.
U0 Clobber(Half h)
{
  h.A = 15;
}

Big gBig;
Two gTwo;
Half gHalf;

I64 main()
{
  I64 r = 0;
  I64 v;

  gBig.Offset = 1;
  gBig.Name[0] = 7;
  v = TakeBig(gBig, 5);
  r = (r << 4) | ((v >> 8) & 15);
  // 1 -- the first 8 bytes arrive
  r = (r << 4) | ((v >> 4) & 15);
  // 5 today (the tag), 7 when fixed
  r = (r << 4) | (v & 15);
  // 5 -- the tag itself is intact, so it is the CLASS that is short, not the call

  gTwo.A = 2;
  gTwo.B = 3;
  v = TakeTwo(gTwo, 5);
  r = (r << 4) | ((v >> 8) & 15);
  // 2
  r = (r << 4) | ((v >> 4) & 15);
  // 5 today (the tag), 3 when fixed -- SIXTEEN bytes is already too many
  r = (r << 4) | (v & 15);
  // 5

  gHalf.A = 4;
  gHalf.B = 6;
  v = TakeHalf(gHalf, 5);
  r = (r << 4) | ((v >> 8) & 15);
  // 4
  r = (r << 4) | ((v >> 4) & 15);
  // 6 -- EIGHT bytes is whole, today and when fixed
  r = (r << 4) | (v & 15);
  // 5

  gHalf.A = 4;
  Clobber(gHalf);
  r = (r << 4) | gHalf.A;
  // 4 -- the callee's write did not reach the caller, so this is a COPY and not a reference

  return r;
}
