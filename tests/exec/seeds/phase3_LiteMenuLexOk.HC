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

U8 *RVMenuSkipOk(U8 *p)
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

public I64 RVMenuLexOkSelfTest()
{
  U8 *p;
  rv_menu_lex_steps = 0;
  rv_menu_lex_abort = 0;
  p = RVMenuSkipOk("  x");
  if (!p)
    return 0;
  return *p;
}
