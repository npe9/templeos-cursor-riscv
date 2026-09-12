import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
import U8 *StrCpy(U8 *dst, U8 *src);
class CRVLiteCmpCtrl
{
  I64 token;
  I64 cur_i64;
  U8 *cur_str;
};

class CRVKernMenuEntry
{
  I64 next;
  I64 sub;
  U8 name[32];
  I64 msg_code;
  I64 arg1;
  I64 arg2;
  Bool checked, dir, pad[6];
};
I64 g_lex_fp;
I64 g_toks[8];
I64 g_tok_n;
I64 g_tok_i;
I64 g_i64_val;
U8 g_ident[32];
CRVLiteCmpCtrl g_cc;
/* Soft Call: live local across SoftLexPlant Soft Call clobbers a0 → Lex soft-fail r=1. */
I64 g_lex_ret;
/* Soft Call: g_toks[g_tok_i++] plant (was hoisted while the post-inc
 * write-back was lost; ICPostIncDec in Compiler/BackA_RV.HC now stores it). */
I64 SoftLexPlantGlbl()
{
  I64 t;
  if (g_tok_i >= g_tok_n) {
    g_cc.token = 0;
    return 0;
  }
  t = g_toks[g_tok_i++];
  g_cc.token = t;
  if (t == 0x102)
    g_cc.cur_i64 = g_i64_val;
  if (t == 0x100)
    g_cc.cur_str = g_ident;
  return t;
}

I64 MenuLexI64SoftGlbl()
{
  I64 steps;
  if (!g_lex_fp)
    return 0;
  if (g_cc.token == ',' || g_cc.token == ')')
    return 0;
  if (g_cc.token == 0x102) {
    g_lex_ret = g_cc.cur_i64;
    SoftLexPlantGlbl();
    return g_lex_ret;
  }
  if (g_cc.token == 0x103) {
    g_lex_ret = g_cc.cur_i64;
    SoftLexPlantGlbl();
    return g_lex_ret;
  }
  steps = 0;
  while (g_cc.token && g_cc.token != ',' && g_cc.token != ')' && steps < 64) {
    SoftLexPlantGlbl();
    steps++;
  }
  return 0;
}
/* Soft Call SelfTest avoids &g_cc Soft CALL remat; use Fun() not Fun. */
CRVKernMenuEntry *MenuNewSubCmpGlbl()
{
  CRVKernMenuEntry *tmpme;
  if (!g_lex_fp)
    return 0;
  if (g_cc.token != 0x100)
    return 0;
  tmpme = CAlloc(sizeof(CRVKernMenuEntry));
  if (!tmpme)
    return 0;
  if (g_cc.cur_str)
    StrCpy(tmpme->name, g_cc.cur_str);
  if (SoftLexPlantGlbl() == '(') {
    tmpme->msg_code = -2;
    if (SoftLexPlantGlbl() != ',' && g_cc.token != ')')
      tmpme->msg_code = MenuLexI64SoftGlbl();
    if (g_cc.token == ',')
      SoftLexPlantGlbl();
    if (g_cc.token != ',' && g_cc.token != ')')
      tmpme->arg1 = MenuLexI64SoftGlbl();
    if (g_cc.token == ',')
      SoftLexPlantGlbl();
    if (g_cc.token != ',' && g_cc.token != ')')
      tmpme->arg2 = MenuLexI64SoftGlbl();
    if (g_cc.token != ')')
      SoftLexPlantGlbl();
    if (SoftLexPlantGlbl() != ';')
      ;
    SoftLexPlantGlbl();
  }
  return tmpme;
}

public I64 RVMenuNewSubCmpSelfTest()
{
  CRVKernMenuEntry *e;
  I64 ne;
  ne = sizeof(CRVKernMenuEntry);
  if (ne != 80)
    return 2;
  g_lex_fp = 1;
  StrCpy(g_ident, "Tile");
  g_i64_val = 8;
  g_tok_n = 5;
  g_tok_i = 0;
  g_toks[0] = '(';
  g_toks[1] = ',';
  g_toks[2] = 0x102;
  g_toks[3] = ')';
  g_toks[4] = ';';
  g_cc.token = 0x100;
  g_cc.cur_i64 = 0;
  g_cc.cur_str = g_ident;
  e = MenuNewSubCmpGlbl();
  if (!e)
    return 3;
  if (e->name[0] != 'T') {
    Free(e);
    return 4;
  }
  if (e->arg1 != 8) {
    Free(e);
    return 5;
  }
  if (e->msg_code != -2) {
    Free(e);
    return 6;
  }
  Free(e);
  return 8;
}
