import U8 *CAlloc(I64 size);
import U0 Free(U8 *addr);
import U8 *StrCpy(U8 *dst, U8 *src);
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
I64 rv_menu_lex_steps;
I64 rv_menu_lex_abort;
I64 RVMenuLexOk()
{
  rv_menu_lex_steps++;
  if (rv_menu_lex_steps > 64) {
    rv_menu_lex_abort = 1;
    return 0;
  }
  return 1;
}

U8 *RVMenuSkip(U8 *p)
{
  while (p && *p && RVMenuLexOk()) {
    if (*p == 32 || *p == 9 || *p == 13 || *p == 10) {
      p++;
      continue;
    }
    break;
  }
  return p;
}

U8 *RVMenuReadIdent(U8 *p, U8 *out, I64 max)
{
  I64 n;
  I64 lim;
  p = RVMenuSkip(p);
  if (!p || !out || max < 2) {
    if (out && max > 0)
      out[0] = 0;
    return p;
  }
  lim = max - 1;
  out[0] = 0;
  if (!((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') || *p == '_'))
    return p;
  n = 0;
  while (*p && n < lim && RVMenuLexOk()) {
    if (!((*p >= 'A' && *p <= 'Z') || (*p >= 'a' && *p <= 'z') || (*p >= '0' && *p <= '9') || *p == '_'))
      break;
    out[n++] = *p++;
  }
  out[n] = 0;
  return p;
}

U8 *RVMenuReadI64(U8 *p, I64 *out)
{
  I64 v;
  p = RVMenuSkip(p);
  if (!out)
    return p;
  *out = 0;
  if (!p)
    return p;
  v = 0;
  while (*p >= '0' && *p <= '9' && RVMenuLexOk()) {
    v = v * 10 + (*p - '0');
    p++;
  }
  *out = v;
  return p;
}

CRVKernMenu *MenuNewHandLeaf(U8 *st, I64 flags)
{
  CRVKernMenu *m;
  CRVKernMenuEntry *tmpme;
  U8 name[32];
  U8 *p;
  I64 arg1;
  rv_menu_lex_steps = 0;
  rv_menu_lex_abort = 0;
  m = CAlloc(sizeof(CRVKernMenu));
  if (!m)
    return 0;
  m->flags = flags;
  m->attr = 7;
  if (!st)
    return m;
  p = st;
  p = RVMenuReadIdent(p, name, 32);
  if (!name[0])
    return m;
  tmpme = CAlloc(sizeof(CRVKernMenuEntry));
  if (!tmpme)
    return m;
  StrCpy(tmpme->name, name);
  p = RVMenuSkip(p);
  arg1 = 0;
  if (p && *p == '(') {
    p++;
    p = RVMenuSkip(p);
    if (p && *p == ',') {
      p++;
      p = RVMenuReadI64(p, &arg1);
    }
    while (p && *p && *p != ')' && RVMenuLexOk())
      p++;
    if (p && *p == ')')
      p++;
    if (p && *p == ';')
      p++;
  }
  tmpme->arg1 = arg1;
  m->sub = tmpme;
  return m;
}

public I64 RVMenuNewHandSelfTest()
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
  m = MenuNewHandLeaf("Tile(,8);", 8);
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
