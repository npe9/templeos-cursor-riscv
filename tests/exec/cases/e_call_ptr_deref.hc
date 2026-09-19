// Deref of a pointer-returning CALL must load at the pointee's width.
// Regression: `FsChangeHash` is `return *FsChHashP(i);` where FsChHashP returns
// U32* — the deref emitted an 8-byte load, so FsChanges reported
// hash[i] | (hash[i-1] << 32) (three files printed 0x58BF9CA5E36FA7C0 /
// 0x3445D36258BF9CA5 / 0x3445D362). Assigning the call result to a local first
// always worked; only the direct `*Fn()` form was wrong, because ParsePostfix
// cleared the pointee that the call had just established.
U8 g_u8[8];
U16 g_u16[8];
U32 g_u32[8];
I32 g_i32[8];
U8 *P8(I64 i)
{
  return &g_u8[i];
}

U16 *P16(I64 i)
{
  return &g_u16[i];
}

U32 *P32(I64 i)
{
  return &g_u32[i];
}

I32 *PI32(I64 i)
{
  return &g_i32[i];
}

I64 main()
{
  I64 r = 0;
  U32 *p;
  g_u8[0] = 0x11;
  g_u8[1] = 0x22;
  g_u16[0] = 0x1111;
  g_u16[1] = 0x2222;
  g_u32[0] = 0x11111111;
  g_u32[1] = 0x22222222;
  g_i32[0] = -1;
  g_i32[1] = 0x7F7F7F7F;
  // Narrow loads through a call result: an 8-byte load pulls in the next slot.
  r += (*P8(0) == 0x11) * 1;
  r += (*P16(0) == 0x1111) * 2;
  r += (*P32(0) == 0x11111111) * 4;
  // I32 is signed: a correct 4-byte load sign-extends, so this stays -1.
  r += (*PI32(0) == -1) * 8;
  // The neighbour must read back on its own.
  r += (*P32(1) == 0x22222222) * 16;
  // Control: via a local. This path was always right.
  p = P32(0);
  r += (*p == 0x11111111) * 32;
  // Store through a call result must be 4 bytes, not 8.
  *P32(0) = 0x33333333;
  r += (g_u32[0] == 0x33333333 && g_u32[1] == 0x22222222) * 64;
  // U8 store must not smear over the neighbour.
  *P8(0) = 0x44;
  r += (g_u8[0] == 0x44 && g_u8[1] == 0x22) * 128;
  return r;
  // 0xFF
}
