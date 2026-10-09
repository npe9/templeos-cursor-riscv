// **`ptrarray[i][j]` USES THE OUTER ARRAY'S ELEMENT SIZE FOR THE INNER SUBSCRIPT.**
//
// Found by a transcript divergence after three gated accessors had used the shape for a week.
//
// A C programmer writes `SC_OperData.AtsTblAddr[AtsIndex][EntryOffset]` and gets: load the
// pointer at `AtsTblAddr[AtsIndex]`, then index THAT by the size of what it points at. In HolyC
// the inner subscript is scaled by the size of an element of the OUTER array -- eight bytes,
// because the outer array holds pointers -- whatever the pointee is.
//
//     U32 store[16];  store[k] = 1000 + k;
//     U32 *p32[2];    p32[0] = store;
//
//     p32[0][0]                 ==>  4299262264296   // 0x000003E9_000003E8 -- store[0] AND [1]
//     q = p32[0];  q[0]         ==>  1000            // correct
//
// The chained read took eight bytes at offset 0, so it is not merely the wrong element -- it is
// the wrong WIDTH as well, and the two errors compound. At `[1]` it reads store[2] and store[3].
//
// ### WHAT IT COST
//
// `sc_global.HC` had three accessors in this shape, translating NASA's one-expression bodies
// literally:
//
//     return (SC_AtsEntry_t *)&SC_OperData.AtsTblAddr[AtsIndex][EntryOffset];
//
// Every static gate was green -- the text matches NASA's, the types match, `check_padding` says
// the layouts match, `cfs-inblob` says the functions have addresses. The first time SC's exercise
// RAN, `SC_LoadAts` reported an ATS command count of **2** where the C half reported 4: the walk
// stepped eight bytes per word instead of four, so it read every other entry. A wrong stride
// inside an accessor presents as a wrong COUNT three functions away.
//
// ### A TRUE TWO-DIMENSIONAL ARRAY IS FINE, AND THAT IS WHY ONLY THREE SITES MOVED
//
// `SC_AppData.AtsCmdIndexBuffer[SC_NUMBER_OF_ATS][SC_MAX_ATS_CMDS]` is a real 2-D array and its
// double subscript is correct. The port has nineteen double-subscript sites; sixteen are 2-D
// arrays and three were arrays of pointers. **The two shapes are spelled identically**, which is
// the whole difficulty: a reviewer has to look up the declaration to tell a correct line from a
// broken one. `tools/cfs/check_chained_subscript.py` does that lookup.
//
// ### WHAT IS PINNED
//
//   1. the broken form, through a `U32 *` row and through a `U8 *` row, so the eight bytes are
//      visibly independent of the pointee;
//   2. the SAFE form -- the row hoisted into a local -- which is what the three accessors now do;
//   3. a true 2-D array of the same element type, which must agree with the safe form;
//   4. a 2-D array **inside a class**, because that is the shape SC actually uses and it is not
//      obviously the same as a file-scope one;
//   5. and the single-subscript global pointer, as the control that says the pointee size is
//      understood when only one subscript is involved.
//
// **THE EXPECTED VALUES FOR THE BROKEN FORM ARE NOT FROM C** -- C cannot express them. They are
// measured from this compiler, and the case exists so the three hoists are not quietly undone by
// someone tidying them back into one expression. Every SAFE line matches what C prints.
//
// Measured from a printing build before the fold was pinned. The first six are the broken form:
//
//     4299262264296            = (1001 << 32) | 1000   -- store[0] and store[1]
//     4307852198890            = (1003 << 32) | 1002   -- store[2] and store[3], so stride 8
//     4316442133484  4325032068078
//     4123106164818064178  4701827547522677562         -- the U8 row, eight bytes all the same
//
// and the rest are the safe forms, every one of them right:
//
//     1000 1001 1002 1003   50 51 52 53   1000 1001 1002 1003   2000 2001 2002 2003
//     10 40 11 41 12 42 13 43   40 41 42 43   1000 1001 1002 1003
//
// ### MUTATIONS
//
//   | mutation | result |
//   |---|---|
//   | `q32[i]` written back as `p32[0][i]` | **FAIL** -- the safe form becomes the broken one |
//   | `flat[0][i]` to `flat[1][i]` | **FAIL** -- the 2-D control reads a real second row |
I64 main();

class Rec
{
  U16 a;
  U16 b;
};

class Holder
{
  Rec Grid[2][4]; // a 2-D array INSIDE a class -- SC's AtsCmdIndexBuffer shape
};

U32 store[16];
U8 raw[16];
U32 *p32[2];
U8 *p8[2];
U32 *one32;
U32 flat[2][8]; // a true 2-D array, file scope
Holder h;

I64 Fold(I64 r, I64 v)
{
  return (r * 1000003 + v) & 0xFFFFFFFFFFFF;
}

I64 main()
{
  I64 res = 0;
  I64 i;
  U32 *q32;
  U8 *q8;
  Rec *row;

  for (i = 0; i < 16; i++) {
    store[i] = 1000 + i;
    raw[i] = 50 + i;
  }
  for (i = 0; i < 8; i++) {
    flat[0][i] = 1000 + i;
    flat[1][i] = 2000 + i;
  }
  for (i = 0; i < 4; i++) {
    h.Grid[0][i].a = 10 + i;
    h.Grid[0][i].b = 20 + i;
    h.Grid[1][i].a = 30 + i;
    h.Grid[1][i].b = 40 + i;
  }
  p32[0] = store;
  p32[1] = store;
  p8[0] = raw;
  p8[1] = raw;
  one32 = store;

  // ---- 1. THE BROKEN FORM, two different pointee sizes ---------------------------------------
  for (i = 0; i < 4; i++) {
    res = Fold(res, p32[0][i]);
  }
  for (i = 0; i < 2; i++) {
    res = Fold(res, p8[0][i]);
  }

  // ---- 2. THE SAFE FORM: the row in a local, one subscript ------------------------------------
  q32 = p32[0];
  for (i = 0; i < 4; i++) {
    res = Fold(res, q32[i]); // 1000 1001 1002 1003
  }
  q8 = p8[0];
  for (i = 0; i < 4; i++) {
    res = Fold(res, q8[i]); // 50 51 52 53
  }

  // ---- 3. a TRUE 2-D array, which needs no hoist ---------------------------------------------
  for (i = 0; i < 4; i++) {
    res = Fold(res, flat[0][i]); // 1000 1001 1002 1003 -- same as the safe form above
  }
  for (i = 0; i < 4; i++) {
    res = Fold(res, flat[1][i]); // 2000 2001 2002 2003 -- and the second row is a real row
  }

  // ---- 4. a 2-D array INSIDE A CLASS, which is SC's shape ------------------------------------
  for (i = 0; i < 4; i++) {
    res = Fold(res, h.Grid[0][i].a);
    res = Fold(res, h.Grid[1][i].b);
  }
  // and through a hoisted row, which must agree
  row = &h.Grid[1][0];
  for (i = 0; i < 4; i++) {
    res = Fold(res, row[i].b); // 40 41 42 43
  }

  // ---- 5. the single-subscript control --------------------------------------------------------
  for (i = 0; i < 4; i++) {
    res = Fold(res, one32[i]); // 1000 1001 1002 1003
  }

  return res;
}
