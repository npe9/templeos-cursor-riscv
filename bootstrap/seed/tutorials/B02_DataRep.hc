// B02_DataRep.hc -- CSAPP 3e Ch.2: Representing and Manipulating Information
// Remap: HolyC I64/U8 on little-endian RV64 (not C int on x86-64 Linux).
//
// HOW TO WORK THIS LAB
//   Run("B02_DataRep.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Bits, two's complement, unsigned casting, shifts, masks, endianness,
//   IEEE floats (lightly). Worked demos show wraparound and LE peeks.
//
// NEXT
//   B03_Machine -- machine-level programs via Uf/Disasm/asm{}.
U0 B02_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 B02_Demo()
{
  I64 a, w;
  U8 *p;
  a = 0x7FFFFFFFFFFFFFFF;
  Print("max I64 a=%X a+1=%X (wrap to min)\n", a, a + 1);
  w = 0x0102030405060708;
  p = &w;
  Print("LE bytes: %02X %02X %02X %02X\n", p[0], p[1], p[2], p[3]);
  B02_Expect("B02_LE", p[0], 0x08);
  B02_Expect("B02_wrap", a + 1, 0x8000000000000000);
}

I64 B02_BitCount(I64 v)
{
  I64 n;
  n = 0;
  while (v) {
    n++;
    v = v & (v - 1);
  }
  return n;
}
// Ex1 Warmup: popcount (Kernighan).
I64 B02_Ex1_BitCount(I64 v)
{
  // TODO Fill_in
  return 0;
}
// Ex2: sign-extend U8 to I64.
I64 B02_Ex2_SignExtU8(I64 b)
{
  // TODO Fill_in
  return -1;
}
// Ex3: isolate bit n (0=LSB) -> 0/1.
I64 B02_Ex3_GetBit(I64 x, I64 n)
{
  // TODO Fill_in: return (x >> n) & 1;
  return -1;
}
// Ex4: set bit n.
I64 B02_Ex4_SetBit(I64 x, I64 n)
{
  // TODO Fill_in: return x | (1 << n);
  return x;
}
// Ex5: clear bit n.
I64 B02_Ex5_ClearBit(I64 x, I64 n)
{
  // TODO Fill_in: return x & ~(1 << n);
  return x;
}
// Ex6: arithmetic vs logical shift intuition on I64.
// For negative x, x>>1 should sign-extend (HolyC I64 >> is arithmetic).
I64 B02_Ex6_Sar(I64 x)
{
  // TODO Fill_in: return x >> 1;
  return 0;
}
// Ex7: unsigned right shift of low 32 bits: ((U32)x)>>n
I64 B02_Ex7_ShrU32(I64 x, I64 n)
{
  // TODO Fill_in: return ((U32)x) >> n;
  return 0;
}
// Ex8 Challenge: saturating add for U8 lane -- clamp to 255.
I64 B02_Ex8_SatAddU8(I64 a, I64 b)
{
  I64 s;
  // TODO Fill_in:
  //   a = a & 0xFF; b = b & 0xFF; s = a + b;
  //   if (s > 255) return 255;
  //   return s;
  return 0;
}

U0 B02_Check()
{
  Print("-- B02 exercises --\n");
  B02_Expect("Demo_BitCount", B02_BitCount(0xF0), 4);
  B02_Expect("Ex1_BitCount", B02_Ex1_BitCount(0xF0), 4);
  B02_Expect("Ex2_SignExt_FF", B02_Ex2_SignExtU8(0xFF), -1);
  B02_Expect("Ex2_SignExt_7F", B02_Ex2_SignExtU8(0x7F), 0x7F);
  B02_Expect("Ex3_GetBit", B02_Ex3_GetBit(0xA, 1), 1);
  B02_Expect("Ex4_SetBit", B02_Ex4_SetBit(0, 3), 8);
  B02_Expect("Ex5_ClearBit", B02_Ex5_ClearBit(0xF, 1), 0xD);
  B02_Expect("Ex6_Sar", B02_Ex6_Sar(-2), -1);
  B02_Expect("Ex7_ShrU32", B02_Ex7_ShrU32(0x80000000, 1), 0x40000000);
  B02_Expect("Ex8_SatAdd", B02_Ex8_SatAddU8(200, 100), 255);
  B02_Expect("Ex8_SatAdd2", B02_Ex8_SatAddU8(10, 20), 30);
}

U0 B02()
{
  Print("=== B02 CSAPP Ch.2 Data representation ===\n");
  B02_Demo();
  B02_Check();
  Print("Next: Run(\"B03_Machine.hc\");\n");
}
B02;
