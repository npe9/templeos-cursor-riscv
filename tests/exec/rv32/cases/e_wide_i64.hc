// RV32 register-pair coverage: every value here needs the high word. Same answer on rv64.
I64 Sum8(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h)
{
  return a + b + c + d + e + f + g + h;
}

I64 Pick10(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h, I64 i, I64 j)
{
  return j - a;
}

U64 Ret(U64 x)
{
  return x;
}

I64 main()
{
  I64 r = 0;
  I64 a = 0x00000001FFFFFFFF, b = 1;
  I64 big = 0x123456789ABCDEF0;
  U64 u = 0xFFFFFFFFFFFFFFFF;
  I64 n = 40;
  U32 w = 0xFFFFFFFF;
  I64 k = -3;
  if (a + b == 0x0000000200000000) r |= 1;                         // add carry
  if ((a + b) - b == a) r |= 2;                                    // sub borrow
  if (big * 16 == 0x23456789ABCDEF00) r |= 4;                      // 64-bit mul low
  if (big / 0x10000 == 0x123456789ABC) r |= 8;                     // 64-bit div
  if (big % 0x100000000 == 0x9ABCDEF0) r |= 16;                    // 64-bit rem
  if (u / 3 == 0x5555555555555555) r |= 32;                        // unsigned div
  if (big << 4 == 0x23456789ABCDEF00 && 1 << n == 0x10000000000) r |= 64;  // shifts
  if (big >> n == 0x123456 && -big >> n == -0x123457) r |= 128;    // sra across 32
  if (w + 1 == 0x100000000) r |= 256;                              // U32 zero-extends
  if (0x100000000 > 0xFFFFFFFF && k < 0x7FFFFFFF && -0x100000000 < k) r |= 512;  // hi-word compares
  if (Sum8(a, a, a, a, a, a, a, a) == 0xFFFFFFFF8) r |= 1024;     // pair args in a_i:s(1+i)
  if (Pick10(big, 0, 0, 0, 0, 0, 0, 0, 0, big + a) == a) r |= 2048;  // stack args > 8
  if (Ret(u) == u && k / 2 == -1 && k % 2 == -1) r |= 4096;       // U64 return, signed div
  I64 exact = 0x123456789AB00000;                                  // 41 significant bits
  F64 f = ToF64(exact);
  if (f == 1311768467462946816.0 && ToI64(f) == exact && ToI64(-3.0e9) == -3000000000) r |= 8192;  // F64 <-> I64
  return r;
}
