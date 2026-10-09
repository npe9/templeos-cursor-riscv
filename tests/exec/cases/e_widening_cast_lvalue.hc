// **A WIDENING CAST OF A NARROW LVALUE WIDENS THE LOAD INSTEAD OF CONVERTING THE VALUE.**
//
// This was found by a transcript divergence, not by reading code, and it had been written into
// five gated SC sources before it ran once.
//
// HolyC's cast is a POSTFIX RELABEL (memory: "casts relabel"), and relabelling an LVALUE changes
// how many bytes the compiler loads from its address. So for a `U16` member whose neighbour holds
// 0xFFFF:
//
//     r.a = 0xFFFF; r.b = 0xFFFF;
//     (r.a)(U32)   ==>  4294967295      // read FOUR bytes: r.a and r.b together
//     r.a          ==>  65535           // the plain load is right
//
// In C, `(unsigned int)r.a` converts the VALUE and is 65535. The two languages disagree, silently,
// and only when the adjacent bytes are non-zero -- which is why it survived 36 uses of
// `SC_IDX_AS_UINT` and 47 of `SC_IDNUM_AS_UINT` in a translation whose static gates were all
// green: most neighbours are zero most of the time.
//
// ### HOW IT PRESENTED
//
// `SC_InitAtsTables` fills every `SC_AtsCmdEntryOffsetRecord_t.Offset` with
// `SC_ENTRY_OFFSET_INVALID`, which is `(uint16)(-1)` = 65535. The exercise then printed
// `SC_IDX_AS_UINT(rec->Offset)` for four consecutive records and got **4294967295** where C got
// 65535 -- two adjacent 0xFFFF halfwords read as one word. One print, four wrong lines, and the
// same macro is what `SC_GetAtsEntryAtOffset` uses to INDEX the ATS buffer.
//
// ### A LOCAL IS WORSE THAN A MEMBER
//
//     U16 loc = 0xFFFF;  (loc)(U32)  ==>  2155937791
//
// A stack slot's neighbour is whatever the frame put there, so the value is not merely wrong, it
// is **unpredictable from the source** -- it moves with the frame layout. That is the one of the
// three forms a reviewer is least likely to catch by inspection, and it is pinned below with the
// neighbour written explicitly so the expected value is stable.
//
// ### WHAT IS PINNED
//
//   1. a U16 MEMBER with a non-zero neighbour, and the same member with a zero neighbour -- the
//      second is CORRECT, which is the whole reason this is silent;
//   2. a U16 ARRAY ELEMENT, same two cases;
//   3. a U16 LOCAL with the neighbouring slot written deliberately;
//   4. a U8 member, where the widening reads FOUR bytes and so spans three neighbours;
//   5. **the three forms that are safe and are what the translation uses instead**: the plain
//      load, `& 0xFFFF`, and the sum `+ 0` -- all three force a load of the declared width;
//   6. and the NARROWING direction, `(U32 lvalue)(U16)`, which is accidentally fine on a
//      little-endian target because the low halfword is at the lower address. The translation
//      still relies on it -- `SC_IDX_FROM_UINT` is exactly this -- so it is pinned rather than
//      assumed.
//
// **THE EXPECTED VALUES ARE NOT FROM C.** They cannot be: C has no way to express "read four
// bytes from a two-byte object", so a C twin would print 65535 for every line and the case would
// have nothing to compare against. These are the values measured from this compiler, and what the
// case asserts is that the behaviour **does not change** while the translation's workaround
// depends on knowing it. The safe forms in step 5 are the ones that do match C, and every one of
// them was checked against a printing build before the fold was pinned:
//
//     4294967295  4660  4294967295  17185  1  4294967295  255
//     65535  65535  65535  65535  65535  255  48059  48059
//
// ### MUTATIONS
//
//   | mutation | result |
//   |---|---|
//   | `AS_UINT_BAD` rewritten as the safe `& 0xFFFF` | **FAIL** `0000e4ce64cdbe69` |
//   | `r.b = 0xFFFF` zeroed, so the neighbour is clean | **FAIL** `00008ffd56e5c592` |
//
// The second is the one worth having: it fails by making the DEFECT disappear. A reader who
// doubts that the neighbour is what is being read can zero it and watch exactly one of the
// fifteen numbers change.
I64 main();

#define AS_UINT_BAD(arg)  ((arg)(U32))
#define AS_UINT_SAFE(arg) ((arg) & 0xFFFF)

class R
{
  U16 a;
  U16 b;
  U16 c;
  U16 d;
  U8 e;
  U8 f;
  U8 g;
  U8 h;
};

R r;
U16 arr[4];
U32 wide[2];

I64 Fold(I64 rr, I64 v)
{
  return (rr * 1000003 + v) & 0xFFFFFFFFFFFF;
}

I64 main()
{
  I64 res = 0;
  U16 loc;
  U16 neighbour; // DECLARED AFTER loc so the frame slot above it is written, not inherited

  r.a = 0xFFFF;
  r.b = 0xFFFF;
  r.c = 0x1234;
  r.d = 0;
  r.e = 0xFF;
  r.f = 0xFF;
  r.g = 0xFF;
  r.h = 0xFF;
  arr[0] = 0xFFFF;
  arr[1] = 0xFFFF;
  arr[2] = 0x4321;
  arr[3] = 0;
  wide[0] = 0xAAAABBBB;
  wide[1] = 0;
  loc = 0xFFFF;
  neighbour = 0xFFFF;

  // ---- 1. a U16 MEMBER, bad neighbour then zero neighbour ------------------------------------
  res = Fold(res, AS_UINT_BAD(r.a)); // 4294967295 -- r.a and r.b
  res = Fold(res, AS_UINT_BAD(r.c)); // 4660 -- CORRECT, because r.d is zero
  // ---- 2. a U16 ARRAY ELEMENT ----------------------------------------------------------------
  res = Fold(res, AS_UINT_BAD(arr[0])); // 4294967295
  res = Fold(res, AS_UINT_BAD(arr[2])); // 17185 -- correct, arr[3] is zero
  // ---- 3. a U16 LOCAL. The value depends on the FRAME, which is why the neighbour is written -
  res = Fold(res, AS_UINT_BAD(loc) != AS_UINT_SAFE(loc)); // 1: they disagree
  // ---- 4. a U8 member: four bytes, three neighbours ------------------------------------------
  res = Fold(res, AS_UINT_BAD(r.e)); // 4294967295
  res = Fold(res, r.e);              // 255 -- the plain load

  // ---- 5. THE THREE SAFE FORMS, which are what the translation uses --------------------------
  res = Fold(res, r.a);                 // 65535
  res = Fold(res, AS_UINT_SAFE(r.a));   // 65535
  res = Fold(res, (r.a + 0)(U32));      // 65535 -- the sum forces an rvalue before the relabel
  res = Fold(res, AS_UINT_SAFE(arr[0]));// 65535
  res = Fold(res, AS_UINT_SAFE(loc));   // 65535
  res = Fold(res, r.e & 0xFF);          // 255

  // ---- 6. AND THE NARROWING DIRECTION, which the translation also relies on -------------------
  //
  // `SC_IDX_FROM_UINT(arg)` is `((arg)(U16))`. Relabelling a U32 lvalue as U16 reads the LOW
  // halfword, which on this little-endian target is the correct truncation -- so unlike the
  // widening direction it agrees with C. Pinned because the translation depends on it.
  res = Fold(res, wide[0](U16));   // 0xBBBB = 48059
  res = Fold(res, wide[0] & 0xFFFF); // the same number by the safe route

  return res;
}
