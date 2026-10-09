// **TAKING THE ADDRESS OF A RELABELLED ARRAY ELEMENT -- THE SHAPE EVERY ATS AND RTS PARSE USES.**
//
// SC's command buffers are `uint32` arrays and its entries are structs, so NASA walks them by
// casting an element's ADDRESS:
//
//     EntryPtr = (SC_AtsEntry_t *)&Buffer32[EntryIndex];        // sc_loads.c, twice
//     EntryPtr = (SC_RtsEntry_t *)&Buffer32[i];
//     return   &SC_OperData.AtsTblAddr[a][off](SC_AtsEntry_t *);  // sc_app.h's accessors
//
// In C the cast is applied to the ADDRESS. **In HolyC the cast is postfix and relabels the
// VALUE**, and `&` is then applied to the result -- `&Buffer32[i](SC_AtsEntry_t *)`. The two agree
// only if `&` of a relabelled lvalue yields that lvalue's own address, which is a property of this
// compiler and not of the source.
//
// Five sources of SC are gated on it: `SC_LoadAts`, `SC_ParseRts`, `SC_UpdateAppend`,
// `SC_VerifyAtsEntry` and every one of `sc_global.HC`'s seven accessors. **If `&` of a relabel
// produced the address of a temporary instead, every entry read would come back as garbage and
// every entry written would be dropped** -- and the differential would show it as a wrong command
// count or a wrong time tag, hundreds of lines from the cast.
//
// ### WHY THIS IS NOT COVERED BY WHAT WAS ALREADY MEASURED
//
// `e_tbl_wrapper_idiom.hc` pins pointer DIFFERENCE scaled by the pointee and an indirect call
// through an arrow member; `e_u32_peel_union.hc` pins reading a wide word as narrow fields.
// Neither takes the address of a cast. A grep for the shape over `Kernel/Cfs/` finds it in three
// places, all of them in `sc_loads.HC`, plus `sc_global.HC`'s two indexed accessors -- and **none
// of those has ever been executed**, because SC is gated statically and has no exercise block yet.
// So the shape had an address in a blob and no evidence behind it.
//
// ### WHAT IS PINNED
//
//   1. reading all four 16-bit fields and the trailing 32-bit one, through a cast at a NON-ZERO
//      index, so an off-by-one-element error shows as a value;
//   2. the byte offset the cast's result actually carries -- `p(U8 *) - Buf(U8 *)` must be 4 for
//      `&Buf[1]`, which is the half a field read cannot distinguish from a lucky layout;
//   3. **a WRITE through the relabelled pointer, read back as raw words.** SC_Insert's hoisted
//      pair stores through one of these, and sc_loads.c's parse writes `CmdOffsetRec->Offset`;
//   4. index 0 and an odd index, because 0 is the case where a temporary and the real element
//      could share an address by accident;
//   5. `sizeof(U32)`, which `SC_ParseRts` divides its byte length by -- a wrong value halves or
//      doubles every RTS stride with no diagnostic -- and `sizeof` of the entry class.
//
// ### EXPECTED VALUE FROM C
//
// A C twin (`(E *)&Buf[i]`, the same eleven folds) printed
//
//     buf1=5a5a2222 buf2=55554444 buf3=deadbeef sizeofE=12
//     fold = 000041f6b4733ecb
//
// ### MUTATIONS
//
//   | mutation | result |
//   |---|---|
//   | `&Buf[1](E *)` to `&Buf[2](E *)` | **FAIL** `0000e97e55fb83f0` -- every field and the offset move |
//   | `U32 Tail` to `U16 Tail`          | **FAIL** `000052227f863ec9` -- sizeof and the write-back both change |
//   | drop the `&`: `Buf[1](E *)`       | **FAIL** `0000ab78cda762df` -- and it COMPILED, see below |
//
// **THE THIRD ONE WAS EXPECTED TO BE A COMPILE ERROR AND IS NOT.** `Buf[1](E *)` relabels the
// WORD 0x33332222 as a pointer and the compiler accepts it, so the case ran to completion through
// a fabricated address and returned a wrong fold rather than failing to build. That is the open
// HolyC pattern from memory in a new place -- a relabel is not a conversion and nothing objects --
// and it is the reason this case exists: the difference between `&x(T *)` and `x(T *)` is one
// character, both compile, and only one of them is the address of anything.
I64 main();

// SC_AtsEntryHeader_t's shape -- NASA's own field names and order, so a reader comparing this to
// sc_tbl.HC is comparing like with like. The trailing U32 stands in for the packet that follows.
class E
{
  U16 Pad;
  U16 CmdNumber;
  U16 TimeTag_MS;
  U16 TimeTag_LS;
  U32 Tail;
};

U32 Buf[8];

I64 Fold(I64 r, I64 v)
{
  return (r * 1000003 + v) & 0xFFFFFFFFFFFF;
}

I64 main()
{
  I64 r = 0;
  E *p;
  I64 i;

  i = 0;
  while (i < 8) {
    Buf[i] = 0x11110000 + i * 0x22222222;
    i++;
  }

  // ---- 1. THE SHAPE, at a non-zero index ------------------------------------------------------
  p = &Buf[1](E *);
  r = Fold(r, p->Pad);
  r = Fold(r, p->CmdNumber);
  r = Fold(r, p->TimeTag_MS);
  r = Fold(r, p->TimeTag_LS);
  r = Fold(r, p->Tail);

  // ---- 2. and the ADDRESS it carries, in bytes from the array base ----------------------------
  r = Fold(r, p(U8 *) - Buf(U8 *));

  // ---- 3. A WRITE THROUGH IT, read back as raw words ------------------------------------------
  p->CmdNumber = 0x5A5A;
  p->Tail = 0xDEADBEEF;
  r = Fold(r, Buf[1]);
  r = Fold(r, Buf[2]); // untouched between the two writes -- an overlapping store would move it
  r = Fold(r, Buf[3]);

  // ---- 4. index 0 and an odd index ------------------------------------------------------------
  p = &Buf[0](E *);
  r = Fold(r, p->CmdNumber);
  p = &Buf[5](E *);
  r = Fold(r, p->CmdNumber);

  // ---- 5. the two sizeofs the parse divides and strides by ------------------------------------
  r = Fold(r, sizeof(U32));
  r = Fold(r, sizeof(E));

  return r;
}
