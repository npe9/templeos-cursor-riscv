// Menu_RV_Guest_Lex.HC — index hand Lex → flat Personal ids (P6).
// Folded into guest Menu wrap before Guest (see Menu_RV wrap + MENU_RV_GUEST_LEX_HC).
// Flat Guest alone still Cmps without this file. Uses st[i] + local U8 name[] —
// no local U8* lit walk, no CMenu heap (those still block guest product Menu).
#ifndef MENU_RV_GUEST_LEX_HC
#define MENU_RV_GUEST_LEX_HC
#define RV_MENU_LEX_MAX_STEPS 2048
#define RV_MENU_LEX_MAX 16
I64 rv_menu_lex_n;
I64 rv_menu_lex_id[RV_MENU_LEX_MAX];
I64 rv_menu_lex_steps;
I64 rv_menu_lex_abort;
I64 rv_menu_lex_parse_hits;
Bool RVMenuLexOk()
{
  rv_menu_lex_steps++;
  if (rv_menu_lex_steps > RV_MENU_LEX_MAX_STEPS) {
    rv_menu_lex_abort = 1;
    return FALSE;
  }
  return TRUE;
}

I64 RVMenuSkipI(U8 *st, I64 i)
{
  U8 ch;
  while (st && RVMenuLexOk()) {
    ch = st[i];
    if (!ch)
      break;
    if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') {
      i++;
      continue;
    }
    break;
  }
  return i;
}

I64 RVMenuReadIdentI(U8 *st, I64 i, U8 *out, I64 max)
{
  I64 n = 0;
  U8 ch;
  i = RVMenuSkipI(st, i);
  if (!out || max < 2) {
    if (out && max > 0)
      out[0] = 0;
    return i;
  }
  out[0] = 0;
  if (!st)
    return i;
  ch = st[i];
  if (!((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_'))
    return i;
  while (st[i] && n < max - 1 && RVMenuLexOk()) {
    ch = st[i];
    if (!((ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || (ch >= '0' && ch <= '9') || ch == '_'))
      break;
    out[n++] = ch;
    i++;
  }
  out[n] = 0;
  return i;
}

I64 RVMenuReadI64I(U8 *st, I64 i, I64 *out)
{
  I64 v = 0;
  U8 ch;
  i = RVMenuSkipI(st, i);
  if (!out)
    return i;
  *out = 0;
  if (!st)
    return i;
  while (RVMenuLexOk()) {
    ch = st[i];
    if (ch < '0' || ch > '9')
      break;
    v = v * 10 + (ch - '0');
    i++;
  }
  *out = v;
  return i;
}

I64 RVMenuIdFromIdent(U8 *name)
{
  //Char-wise match — no StrCmp import (guest Cmp unresolved).
  if (!name || !name[0])
    return 0;
  if (name[0] == 'T' && name[4] == 'H')
    return 1;
  if (name[0] == 'T' && name[4] == 'V')
    return 2;
  if (name[0] == 'W' && name[3] == 'M')
    return 3;
  if (name[0] == 'C' && name[1] == 'l')
    return 4;
  if (name[0] == 'A' && name[1] == 'b')
    return 5;
  if (name[0] == 'H' && name[1] == 'e')
    return 6;
  if (name[0] == 'F' && name[1] == 'o')
    return 7;
  if (name[0] == 'C' && name[1] == 't')
    return 8;
  return 0;
}

I64 RVMenuParseFlatI(U8 *st, I64 i)
{
  U8 name[32];
  I64 arg1 = 0, id;
  U8 ch;
  while (st && st[i] && rv_menu_lex_n < RV_MENU_LEX_MAX && RVMenuLexOk()) {
    i = RVMenuSkipI(st, i);
    if (!st[i] || st[i] == '}')
      break;
    i = RVMenuReadIdentI(st, i, name, 32);
    if (!name[0]) {
      if (st[i])
        i++;
      continue;
    }
    i = RVMenuSkipI(st, i);
    ch = st[i];
    if (ch == '(') {
      arg1 = 0;
      i++;
      i = RVMenuSkipI(st, i);
      if (st[i] && st[i] != ',' && st[i] != ')')
        i = RVMenuReadI64I(st, i, &arg1);
      i = RVMenuSkipI(st, i);
      if (st[i] == ',') {
        i++;
        i = RVMenuSkipI(st, i);
        if (st[i] && st[i] != ',' && st[i] != ')')
          i = RVMenuReadI64I(st, i, &arg1);
      }
      while (st[i] && st[i] != ')' && RVMenuLexOk())
        i++;
      if (st[i] == ')')
        i++;
      i = RVMenuSkipI(st, i);
      if (st[i] == ';')
        i++;
      id = RVMenuIdFromIdent(name);
      if (!id && arg1 > 0)
        id = arg1;
      rv_menu_lex_id[rv_menu_lex_n] = id;
      rv_menu_lex_n++;
    } else if (ch == '{') {
      i++;
      i = RVMenuParseFlatI(st, i);
      i = RVMenuSkipI(st, i);
      if (st[i] == '}')
        i++;
    } else {
      if (st[i])
        i++;
    }
  }
  return i;
}

public I64 RVMenuLexNew(U8 *st)
{
  rv_menu_lex_steps = 0;
  rv_menu_lex_abort = 0;
  rv_menu_lex_n = 0;
  if (!st || !st[0])
    return 0;
  rv_menu_lex_parse_hits++;
  RVMenuParseFlatI(st, 0);
  if (rv_menu_lex_abort)
    return 0;
  return rv_menu_lex_n;
}
#endif
