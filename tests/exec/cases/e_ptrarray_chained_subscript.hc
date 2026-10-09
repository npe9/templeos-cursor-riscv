// **`ptrarray[i][j]` -- THE SHAPE THAT SCALED THE INNER SUBSCRIPT BY THE OUTER ELEMENT'S SIZE.**
//
// FIXED in host/parser.c. This case pinned the DEFECT for one commit and now pins the fix, which
// is the better of the two things to pin: a case whose expected values are a compiler's mistake
// has to be rewritten the day the mistake is repaired, and one whose values come from C does not.
// Every number below is what C prints.
//
// ### WHAT WAS WRONG
//
// A C programmer writes `SC_OperData.AtsTblAddr[AtsIndex][EntryOffset]` and gets: load the
// pointer at `AtsTblAddr[AtsIndex]`, then index THAT by the size of what it points at. The inner
// subscript was instead scaled by the size of an element of the OUTER array -- eight bytes,
// because the outer array holds pointers -- whatever the pointee was, and the read was eight bytes
// wide too, so the element was wrong AND the width was wrong and the two compounded:
//
//     U32 store[16];  store[k] = 1000 + k;
//     U32 *p32[2];    p32[0] = store;
//
//     p32[0][0]      ==>  4299262264296   // 0x000003E9_000003E8 -- store[0] AND store[1]
//     p32[0][1]      ==>  4307852198890   // store[2] and store[3], so the stride was 8
//
// ### WHAT IT COST
//
// `sc_global.HC` had three accessors in this shape, translating NASA's one-expression bodies
// literally. Every static gate was green -- the text matches NASA's, the types match,
// `check_padding` says the layouts match, `cfs-inblob` says the functions have addresses. The
// first time SC's exercise RAN, `SC_LoadAts` reported an ATS command count of **2** where the C
// half reported 4: the walk stepped eight bytes per word instead of four, so it read every other
// entry. A wrong stride inside a one-line accessor presents as a wrong COUNT three functions
// away.
//
// ### THE FIX, AND THE PART OF IT THAT A SINGLE PROBE WOULD HAVE MISSED
//
// `host/parser.c`'s postfix loop now treats an array of pointers as one level of indirection, the
// way it always treated `U8 **argv`. That alone fixed five of the eight forms. The sixth --
// **a MEMBER array of primitive pointers, which is exactly `SC_OperData.AtsTblAddr[i][j]`** --
// needed more: a member declared `T *arr[N]` has its `pointed_to_type` overwritten with RT_I64 at
// declaration time so the FIRST subscript strides one pointer, which is correct and which
// destroys the only record of what the pointers point at. Two new `CMemberLst` fields keep it.
//
// **AND THE FIRST ATTEMPT LOOKED COMPLETE BECAUSE THE PROBE'S CLASS WAS EIGHT BYTES WIDE.** A
// member array of CLASS pointers appeared to work while the primitive case did not -- the class
// happened to be `sizeof` 8, so the old broken stride and the right stride were the same number.
// The class in this case is deliberately **12 bytes**, and every form is exercised through all
// three storage classes.
//
// ### WHAT IS PINNED -- ten forms, every value from C
//
//   1. a global array of `U32 *`, `U8 *` and `C *` (12 bytes), double-subscripted;
//   2. the same three as MEMBERS of a class, which is the shape cFS uses and the one that needed
//      the extra fields;
//   3. the same as LOCALS, because a local's declaration is recorded by a different path again;
//   4. the hoisted-row spelling (`q = p32[0]; q[i]`), which was correct throughout and must stay
//      equal to the chained spelling -- that EQUALITY is the assertion, not either value alone;
//   5. a file-scope two-dimensional array and a two-dimensional array inside a class, as the
//      controls: both were always right and are spelled identically to the broken form, which is
//      what made the defect hard to see by reading.
//
// ### EXPECTED VALUE, AND MUTATIONS
//
// A C twin (`(C *)`, `uint32_t *[2]`, the same 50 folds) printed `sizeof_C=12` and
// `fold = 0000fb47c157d8f2`, which is this case's pinned value.
//
//   | mutation | result |
//   |---|---|
//   | `g.Grid[1][i]` to `g.Grid[0][i]` | **FAIL** `00000f9aeed96752` -- the 2-D control reads a real second row |
//
// **AND THE PARSER CHANGE ITSELF IS ITS OWN CONTROL.** Re-recording
// `tests/asm/codegen_rv64_golden.txt` after the fix moved **9 rows of 963, all of them this
// case's**: no other exec case's emitted bytes changed under any of the nine optimizer
// environments. That is the evidence that the postfix-loop change is surgical, and it is worth
// more than any number of green cases.
I64 main();

// TWELVE BYTES, deliberately not eight: an eight-byte class agrees with the OLD broken stride by
// accident, and that accident made the first version of the parser fix look complete.
class C
{
  U16 a;
  U16 b;
  U32 c;
  U32 d;
};

// The three storage classes, each with the three pointee widths cFS uses.
class H
{
  U32 *wrows[2];
  U8 *brows[2];
  C *crows[2];
};

// And the two CONTROLS, spelled identically to the broken form and always correct.
class G
{
  U32 Grid[2][4];
};

U32 store[16];
U8 raw[16];
C objs[8];
U32 *gw[2];
U8 *gb[2];
C *gc[2];
H h;
G g;
U32 flat[2][8];

I64 Fold(I64 r, I64 v)
{
  return (r * 1000003 + v) & 0xFFFFFFFFFFFF;
}

I64 main()
{
  I64 res = 0;
  I64 i;
  U32 *lw[2];
  U8 *lb[2];
  C *lc[2];
  U32 *q32;
  C *qc;

  for (i = 0; i < 16; i++) {
    store[i] = 1000 + i;
    raw[i] = 50 + i;
  }
  for (i = 0; i < 8; i++) {
    objs[i].a = i;
    objs[i].b = 100 + i;
    objs[i].c = 9000 + i;
    objs[i].d = 7;
  }
  for (i = 0; i < 8; i++) {
    flat[0][i] = 1000 + i;
    flat[1][i] = 2000 + i;
  }
  for (i = 0; i < 4; i++) {
    g.Grid[0][i] = 300 + i;
    g.Grid[1][i] = 400 + i;
  }
  gw[0] = store;
  gw[1] = store;
  gb[0] = raw;
  gb[1] = raw;
  gc[0] = objs;
  gc[1] = objs;
  h.wrows[0] = store;
  h.wrows[1] = store;
  h.brows[0] = raw;
  h.brows[1] = raw;
  h.crows[0] = objs;
  h.crows[1] = objs;
  lw[0] = store;
  lw[1] = store;
  lb[0] = raw;
  lb[1] = raw;
  lc[0] = objs;
  lc[1] = objs;

  // The class's size is folded first: if it ever stops being 12, the two controls stop being
  // controls and every expected value below moves. Better a failure here than a silent one there.
  res = Fold(res, sizeof(C));

  // ---- 1. GLOBAL arrays of pointers -----------------------------------------------------------
  for (i = 0; i < 4; i++) {
    res = Fold(res, gw[0][i]);      // 1000 1001 1002 1003
  }
  for (i = 0; i < 4; i++) {
    res = Fold(res, gb[1][i]);      // 50 51 52 53
  }
  for (i = 0; i < 4; i++) {
    res = Fold(res, gc[0][i].c);    // 9000 9001 9002 9003
  }

  // ---- 2. MEMBER arrays of pointers -- the shape cFS uses, and the one that needed more ------
  for (i = 0; i < 4; i++) {
    res = Fold(res, h.wrows[1][i]);
  }
  for (i = 0; i < 4; i++) {
    res = Fold(res, h.brows[0][i]);
  }
  for (i = 0; i < 4; i++) {
    res = Fold(res, h.crows[1][i].c);
  }

  // ---- 3. LOCAL arrays of pointers, recorded by a third path ---------------------------------
  for (i = 0; i < 4; i++) {
    res = Fold(res, lw[0][i]);
  }
  for (i = 0; i < 4; i++) {
    res = Fold(res, lb[1][i]);
  }
  for (i = 0; i < 4; i++) {
    res = Fold(res, lc[0][i].c);
  }

  // ---- 4. THE HOISTED-ROW SPELLING, and the EQUALITY is the assertion ------------------------
  //
  // This form was correct throughout the defect, so on its own it proves nothing about the fix.
  // What it proves is that the two spellings now agree -- which is the property the three
  // sc_global.HC accessors were rewritten twice over.
  q32 = h.wrows[1];
  for (i = 0; i < 4; i++) {
    res = Fold(res, q32[i] == h.wrows[1][i]);        // 1 1 1 1
  }
  qc = h.crows[1];
  for (i = 0; i < 4; i++) {
    res = Fold(res, qc[i].c == h.crows[1][i].c);     // 1 1 1 1
  }

  // ---- 5. THE TWO CONTROLS: true two-dimensional arrays ---------------------------------------
  for (i = 0; i < 4; i++) {
    res = Fold(res, flat[1][i]);    // 2000 2001 2002 2003
  }
  for (i = 0; i < 4; i++) {
    res = Fold(res, g.Grid[1][i]);  // 400 401 402 403
  }

  return res;
}
