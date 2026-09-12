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

U8 *RVMenuReadIdent(U8 *p, U8 *out, I64 max)
{
  I64 n;
  I64 lim;
  if (!p || !out || max < 2)
    return p;
  lim = max - 1;
  while (p && *p && RVMenuLexOk()) {
    if (*p == 32 || *p == 9 || *p == 13 || *p == 10) {
      p++;
      continue;
    }
    break;
  }
  if (!p)
    return p;
  n = 0;
  out[0] = 0;
  while (*p && n < lim && RVMenuLexOk()) {
    if (*p == 32 || *p == 9 || *p == 13 || *p == 10)
      break;
    out[n++] = *p++;
  }
  out[n] = 0;
  return p;
}

public I64 RVMenuReadIdentSelfTest()
{
  U8 name[32];
  U8 *p;
  rv_menu_lex_steps = 0;
  rv_menu_lex_abort = 0;
  name[0] = 0;
  p = RVMenuReadIdent(" Tile", name, 32);
  if (!p)
    return 0;
  if (name[0] != 'T')
    return 0;
  if (name[1] != 'i')
    return 0;
  if (name[2] != 'l')
    return 0;
  if (name[3] != 'e')
    return 0;
  if (name[4] != 0)
    return 0;
  return name[0];
}
