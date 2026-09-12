// Guest Cmp source: lands on RedSea as A:/Compiler/SoftPtr.HC.
// Kernel.BIN SoftCall reads these bytes off the disk at runtime and hands them
// to the in-BIN lite Prs (KernelPrsGlblFunDefSoft), which Cmps and Calls them.
// Nothing here is an in-BIN literal; the Mac phase3.elf is not in the loop.
// Shape mirrors the char walk Compiler/Lex.HC does over cur_buf_ptr: a file-scope
// U8 buffer, a U8 * cursor that advances one byte per pass, and a NUL-terminated
// scan that accumulates the bytes it reads. Nothing here is an I64 cell read: the
// buffer name decays to an address, every write is an sb through the cursor and
// every read is an lbu through it, so the answer only comes out right if the
// stores really landed in Kernel.BIN storage and the loads really re-read them.
// A fold would have to invent both the address and the byte:
//   Seed  buf[0] = 20, buf[1] = 22, buf[2] = 0 through *g_rv_lex_ptr (three sb)
//   Walk  for (p = buf; *p; p = p + 1) n = n + *p  (two lbu, stops on the NUL)
//   Scan  0 + 42
U8 g_rv_lex_buf[8];
U8 *g_rv_lex_ptr;
I64 g_rv_lex_sum;
I64 RvLexSeedText()
{
  g_rv_lex_ptr = g_rv_lex_buf;
  *g_rv_lex_ptr = 20;
  g_rv_lex_ptr = g_rv_lex_ptr + 1;
  *g_rv_lex_ptr = 22;
  g_rv_lex_ptr = g_rv_lex_ptr + 1;
  *g_rv_lex_ptr = 0;
  return 0;
}

I64 RvLexWalkText()
{
  I64 n;
  n = 0;
  for (g_rv_lex_ptr = g_rv_lex_buf; *g_rv_lex_ptr; g_rv_lex_ptr = g_rv_lex_ptr + 1)
    n = n + *g_rv_lex_ptr;
  g_rv_lex_sum = n;
  return n;
}

I64 RvLexTokScan()
{
  I64 s, w;
  s = RvLexSeedText();
  w = RvLexWalkText();
  return s + w;
}
RvLexTokScan();
