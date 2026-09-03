// Regression for the array-deref store-width codegen bug: `*arr = v` on a narrow local array must
// store a SINGLE element, not an 8-byte word that zeros the following bytes. Pre-fix this returned
// 0x99000000 (the sd clobbered a[1..3]); fixed it returns 0x99112233.
I64 main()
{
  U8 a[4];
  U8 v = 0x99;
  a[1] = 0x11;
  a[2] = 0x22;
  a[3] = 0x33;
  *a = v;
  // must be a byte store to a[0] only
  return a[0] << 24 | a[1] << 16 | a[2] << 8 | a[3];
}
