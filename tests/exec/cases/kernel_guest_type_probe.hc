// Guest Cmp source: lands on RedSea as A:/Compiler/SoftType.HC.
// Kernel.BIN SoftCall reads these bytes off the disk at runtime and hands them
// to the in-BIN lite Prs (KernelPrsGlblFunDefSoft), which Cmps and Calls them.
// Nothing here is an in-BIN literal; the Mac phase3.elf is not in the loop.
// Shape mirrors the RV emitters in Compiler/BackLib_RV.HC: a four-argument U0 that
// banks an encoded word in file-scope storage, a Bool predicate, a U32 carrying a
// value wider than its type, and a U8 * handing an address back across a jal ra.
//   IType imm*8 + rs1*4 + rd*2 + op. Each arg register carries a distinct weight,
//         so any a0..a3 permutation differs: (1,2,3,4) is 26, (4,3,2,1) is 49.
//   Fits  0 or 1, never the difference. 298-0 must return 1: no narrowing shows up
//         as 2980 in the tally, a byte-wide one as 420.
//   Bit31 1024*1024*1024*k, where lw and lwu disagree. k=4 overflows 32 bits and
//         must truncate to 0; k=2 sets bit 31 and must stay positive.
//   Sum   Check 20 + Width 22, banked through the returned pointer as a byte = 42
U8 g_rv_enc_buf[4];
U8 *g_rv_enc_ptr;
U8 *g_rv_enc_end;
I64 g_rv_enc_word;
U0 RvEncIType(I64 imm, I64 rs1, I64 rd, I64 op)
{
  g_rv_enc_word = imm * 8 + rs1 * 4 + rd * 2 + op;
}

Bool RvEncFits(U32 v, I64 lim)
{
  return v - lim;
}

U32 RvEncBit31(I64 k)
{
  I64 v;
  v = 1024;
  v = v * 1024;
  v = v * 1024;
  v = v *k;
  return v;
}

U8 *RvEncBuf()
{
  g_rv_enc_ptr = g_rv_enc_buf;
  return g_rv_enc_ptr;
}

I64 RvEncCheck()
{
  I64 t, u;
  RvEncIType(1, 2, 3, 4);
  t = 0;
  if (g_rv_enc_word == 26)
    t = 10;
  u = RvEncFits(298, 0);
  u = u * 10;
  return t + u;
}

I64 RvEncWidth()
{
  I64 t, u;
  t = 0;
  if (RvEncBit31(4) == 0)
    t = 10;
  u = 0;
  if (RvEncBit31(2) > 0)
    u = 12;
  return t + u;
}

I64 RvEncSum()
{
  I64 a, b;
  a = RvEncCheck();
  b = RvEncWidth();
  g_rv_enc_end = RvEncBuf();
  *g_rv_enc_end = a + b;
  return *g_rv_enc_end;
}
RvEncSum();
