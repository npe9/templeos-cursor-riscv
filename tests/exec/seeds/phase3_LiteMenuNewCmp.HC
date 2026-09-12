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

class CRVKernMenu
{
  I64 next;
  I64 sub;
  I64 task;
  I64 flags;
  U8 attr, pad[7];
};
I64 g_fp_new;
I64 g_fp_lex;
I64 g_fp_lex_i64;
I64 g_fp_del;
I64 g_toks[8];
I64 g_tok_n;
I64 g_tok_i;
I64 g_i64_val;
U8 g_ident[32];
/* Soft Call: live local across SoftLexPlant Soft Call clobbers a0 → Lex soft-fail r=1. */
I64 g_lex_ret;
I64 SoftMenuFpOk(I64 fp)
{
  if (!fp)
    return 0;
  return 1;
}

I64 SoftMenuFpsWired()
{
  if (!SoftMenuFpOk(g_fp_new))
    return 0;
  if (!SoftMenuFpOk(g_fp_lex))
    return 0;
  if (!SoftMenuFpOk(g_fp_lex_i64))
    return 0;
  if (!SoftMenuFpOk(g_fp_del))
    return 0;
  return 1;
}
/* Soft Call: g_toks[g_tok_i++] plant (was hoisted while the post-inc
 * write-back was lost; ICPostIncDec in Compiler/BackA_RV.HC now stores it). */
I64 SoftLexPlant(CRVLiteCmpCtrl *cc)
{
  I64 t;
  if (!cc || !g_fp_lex)
    return 0;
  if (g_tok_i >= g_tok_n) {
    cc->token = 0;
    return 0;
  }
  t = g_toks[g_tok_i++];
  cc->token = t;
  if (t == 0x102)
    cc->cur_i64 = g_i64_val;
  if (t == 0x100)
    cc->cur_str = g_ident;
  return t;
}

CRVLiteCmpCtrl *SoftCmpCtrlNew(U8 *st, I64 flags, U8 *fn)
{
  CRVLiteCmpCtrl *cc;
  if (!g_fp_new)
    return 0;
  cc = CAlloc(sizeof(CRVLiteCmpCtrl));
  if (!cc)
    return 0;
  cc->token = 0;
  cc->cur_i64 = 0;
  cc->cur_str = 0;
  if (st)
    ;
  if (flags)
    ;
  if (fn)
    ;
  return cc;
}

U0 SoftCmpCtrlDel(CRVLiteCmpCtrl *cc)
{
  if (!g_fp_del)
    return;
  if (cc)
    Free(cc);
}

I64 MenuLexI64Soft(CRVLiteCmpCtrl *cc)
{
  I64 steps;
  if (!cc || !g_fp_lex)
    return 0;
  if (cc->token == ',' || cc->token == ')')
    return 0;
  if (cc->token == 0x102) {
    g_lex_ret = cc->cur_i64;
    SoftLexPlant(cc);
    return g_lex_ret;
  }
  if (cc->token == 0x103) {
    g_lex_ret = cc->cur_i64;
    SoftLexPlant(cc);
    return g_lex_ret;
  }
  steps = 0;
  while (cc->token && cc->token != ',' && cc->token != ')' && steps < 64) {
    SoftLexPlant(cc);
    steps++;
  }
  return 0;
}

CRVKernMenuEntry *MenuNewSubCmp(CRVLiteCmpCtrl *cc)
{
  CRVKernMenuEntry *tmpme;
  if (!cc || !g_fp_lex)
    return 0;
  if (cc->token != 0x100)
    return 0;
  tmpme = CAlloc(sizeof(CRVKernMenuEntry));
  if (!tmpme)
    return 0;
  if (cc->cur_str)
    StrCpy(tmpme->name, cc->cur_str);
  if (SoftLexPlant(cc) == '(') {
    tmpme->msg_code = -2;
    if (SoftLexPlant(cc) != ',' && cc->token != ')')
      tmpme->msg_code = MenuLexI64Soft(cc);
    if (cc->token == ',')
      SoftLexPlant(cc);
    if (cc->token != ',' && cc->token != ')')
      tmpme->arg1 = MenuLexI64Soft(cc);
    if (cc->token == ',')
      SoftLexPlant(cc);
    if (cc->token != ',' && cc->token != ')')
      tmpme->arg2 = MenuLexI64Soft(cc);
    if (cc->token != ')')
      SoftLexPlant(cc);
    if (SoftLexPlant(cc) != ';')
      ;
    SoftLexPlant(cc);
  }
  return tmpme;
}

CRVKernMenu *MenuNewCmp(U8 *st, I64 flags)
{
  CRVKernMenu *m;
  CRVLiteCmpCtrl *cc;
  if (!SoftMenuFpsWired())
    return 0;
  cc = SoftCmpCtrlNew(st, 0, 0);
  if (!cc)
    return 0;
  SoftLexPlant(cc);
  m = CAlloc(sizeof(CRVKernMenu));
  if (!m) {
    SoftCmpCtrlDel(cc);
    return 0;
  }
  m->flags = flags;
  m->attr = 7;
  m->sub = MenuNewSubCmp(cc);
  SoftCmpCtrlDel(cc);
  return m;
}

public I64 RVMenuNewCmpSelfTest()
{
  CRVKernMenu *m;
  CRVKernMenuEntry *e;
  I64 ne;
  I64 nm;
  ne = sizeof(CRVKernMenuEntry);
  nm = sizeof(CRVKernMenu);
  if (ne != 80)
    return 2;
  if (nm != 40)
    return 3;
  g_fp_new = 0;
  g_fp_lex = 0;
  g_fp_lex_i64 = 0;
  g_fp_del = 0;
  if (MenuNewCmp(0, 8))
    return 1;
  g_fp_new = 1;
  g_fp_lex = 1;
  g_fp_lex_i64 = 1;
  g_fp_del = 1;
  StrCpy(g_ident, "Tile");
  g_i64_val = 8;
  g_tok_n = 6;
  g_tok_i = 0;
  g_toks[0] = 0x100;
  g_toks[1] = '(';
  g_toks[2] = ',';
  g_toks[3] = 0x102;
  g_toks[4] = ')';
  g_toks[5] = ';';
  m = MenuNewCmp(0, 8);
  if (!m)
    return 4;
  if (m->flags != 8) {
    if (m->sub)
      Free(m->sub);
    Free(m);
    return 5;
  }
  e = m->sub;
  if (!e) {
    Free(m);
    return 6;
  }
  if (e->name[0] != 'T') {
    Free(e);
    Free(m);
    return 7;
  }
  if (e->arg1 != 8) {
    Free(e);
    Free(m);
    return 9;
  }
  Free(e);
  Free(m);
  return 8;
}
