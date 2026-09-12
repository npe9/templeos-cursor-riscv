I64 g_lex_fp;
I64 g_toks[8];
I64 g_tok_n;
I64 g_tok_i;
I64 g_i64_val;
I64 g_token;
I64 g_cur_i64;
/* Soft Call: live local across SoftLexPlant Soft Call clobbers a0 → r=1 (v!=8). */
I64 g_lex_ret;
/* Flat Soft I64; SoftLexPlant inlined (no nested Soft Call SoftLexPlant remat r=2). */
/* Soft Call: g_toks[g_tok_i++] plant (was hoisted while the post-inc
 * write-back was lost; ICPostIncDec in Compiler/BackA_RV.HC now stores it). */
I64 MenuLexI64SoftGlbl()
{
  I64 steps;
  I64 t;
  if (!g_lex_fp)
    return 0;
  if (g_token == ',' || g_token == ')')
    return 0;
  if (g_token == 0x102) {
    g_lex_ret = g_cur_i64;
    if (g_tok_i >= g_tok_n)
      g_token = 0;
    else {
      t = g_toks[g_tok_i++];
      g_token = t;
      if (t == 0x102)
        g_cur_i64 = g_i64_val;
    }
    return g_lex_ret;
  }
  if (g_token == 0x103) {
    g_lex_ret = g_cur_i64;
    if (g_tok_i >= g_tok_n)
      g_token = 0;
    else {
      t = g_toks[g_tok_i++];
      g_token = t;
      if (t == 0x102)
        g_cur_i64 = g_i64_val;
    }
    return g_lex_ret;
  }
  steps = 0;
  while (g_token && g_token != ',' && g_token != ')' && steps < 64) {
    if (g_tok_i >= g_tok_n)
      g_token = 0;
    else {
      t = g_toks[g_tok_i++];
      g_token = t;
      if (t == 0x102)
        g_cur_i64 = g_i64_val;
    }
    steps++;
  }
  return 0;
}

public I64 RVMenuLexI64SoftSelfTest()
{
  I64 v;
  g_lex_fp = 1;
  g_tok_n = 1;
  g_tok_i = 0;
  g_i64_val = 0;
  g_toks[0] = ',';
  g_token = 0x102;
  g_cur_i64 = 8;
  v = MenuLexI64SoftGlbl();
  if (v != 8)
    return 1;
  if (g_token != ',')
    return 2;
  g_lex_fp = 0;
  g_token = 0x102;
  g_cur_i64 = 9;
  if (MenuLexI64SoftGlbl())
    return 3;
  g_lex_fp = 1;
  g_token = ',';
  if (MenuLexI64SoftGlbl())
    return 4;
  g_tok_n = 1;
  g_tok_i = 0;
  g_toks[0] = ')';
  g_token = 0x103;
  g_cur_i64 = 65;
  v = MenuLexI64SoftGlbl();
  if (v != 65)
    return 5;
  return 8;
}
