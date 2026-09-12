I64 g_toks[8];
I64 g_tok_n;
I64 g_tok_i;
I64 g_token;
I64 g_cur_i64;
I64 g_i64_val;
I64 g_lex_ret;
I64 SoftPlantCall()
{
  I64 t;
  if (g_tok_i >= g_tok_n) {
    g_token = 0;
    return 0;
  }
  t = g_toks[g_tok_i++];
  g_token = t;
  if (t == 0x102)
    g_cur_i64 = g_i64_val;
  return t;
}
/* MenuLexI64SoftGlbl shape with the plant inlined (LiteMenuLexI64Soft seed). */
I64 SoftLexShape()
{
  I64 t;
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
  return 0;
}
/* Same shapes with the index hoisted into a local and the bump stored
 * explicitly - the Soft-Call-safe plant the product Menu seeds now use. */
I64 SoftPlantCallFixed()
{
  I64 t;
  I64 ti;
  if (g_tok_i >= g_tok_n) {
    g_token = 0;
    return 0;
  }
  ti = g_tok_i;
  t = g_toks[ti];
  g_tok_i = ti + 1;
  g_token = t;
  if (t == 0x102)
    g_cur_i64 = g_i64_val;
  return t;
}

I64 SoftLexShapeFixed()
{
  I64 t;
  I64 ti;
  if (g_token == ',' || g_token == ')')
    return 0;
  if (g_token == 0x102) {
    g_lex_ret = g_cur_i64;
    if (g_tok_i >= g_tok_n)
      g_token = 0;
    else {
      ti = g_tok_i;
      t = g_toks[ti];
      g_tok_i = ti + 1;
      g_token = t;
      if (t == 0x102)
        g_cur_i64 = g_i64_val;
    }
    return g_lex_ret;
  }
  return 0;
}
/* Index-form bisect. Globals are set by the caller so the callee has to load
 * them (SoftLexShape shape) instead of folding a same-function constant. */
I64 HelpGlblIdx()
{
  I64 t;
  t = g_toks[g_tok_i];
  return t;
}

I64 HelpLocalIdx()
{
  I64 t;
  I64 i;
  i = g_tok_i;
  t = g_toks[i];
  return t;
}
/* Reads g_toks[1] so a dropped index scales to 11 instead of 22 and is caught. */
public I64 RVLexPlantIdxProbe()
{
  I64 t;
  g_toks[0] = 11;
  g_toks[1] = 22;
  g_tok_n = 4;
  g_tok_i = 1;
  t = HelpGlblIdx();
  if (t != 22)
    return 1;
  g_tok_i = 1;
  t = HelpLocalIdx();
  if (t != 22)
    return 2;
  return 8;
}

public I64 RVLexPlantFixedSelfTest()
{
  I64 t;
  I64 ti;
  g_tok_i = 0;
  g_tok_n = 1;
  g_toks[0] = ';';
  g_token = 0x102;
  t = SoftPlantCallFixed();
  if (t != ';')
    return 6;
  if (g_token != ';')
    return 7;
  if (g_tok_i != 1)
    return 13;
  g_tok_i = 0;
  g_tok_n = 1;
  g_toks[0] = ',';
  g_token = 0x102;
  g_cur_i64 = 8;
  t = SoftLexShapeFixed();
  if (t != 8)
    return 9;
  if (g_token != ',')
    return 10;
  if (g_tok_i != 1)
    return 11;
  ti = g_tok_i;
  g_tok_i = ti + 1;
  if (g_tok_i != 2)
    return 12;
  return 8;
}

public I64 RVLexPlantToken()
{
  return g_token;
}

public I64 RVLexPlantTokI()
{
  return g_tok_i;
}

public I64 RVLexPlantSelfTest()
{
  I64 t;
  g_toks[0] = 41;
  if (g_toks[0] != 41)
    return 1;
  g_tok_i = 0;
  g_tok_n = 1;
  if (g_tok_i >= g_tok_n)
    return 2;
  g_toks[0] = ',';
  t = g_toks[g_tok_i++];
  if (t != ',')
    return 3;
  if (g_tok_i != 1)
    return 4;
  g_token = t;
  if (g_token != ',')
    return 5;
  g_tok_i = 0;
  g_tok_n = 1;
  g_toks[0] = ';';
  g_token = 0x102;
  t = SoftPlantCall();
  if (t != ';')
    return 6;
  if (g_token == 0x102)
    return 7;
  if (!g_token)
    return 13;
  if (g_token != ';')
    return 14;
  g_tok_i = 0;
  g_tok_n = 1;
  g_toks[0] = ',';
  g_token = 0x102;
  g_cur_i64 = 8;
  t = SoftLexShape();
  if (t != 8)
    return 9;
  if (g_token == 0x102)
    return 10;
  if (!g_token)
    return 11;
  if (g_token != ',')
    return 12;
  return 8;
}
