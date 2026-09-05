#define MENU_RV_GUEST_LEX_HC 1
#define RV_MENU_LEX_MAX_STEPS 2048
#define RV_MENU_LEX_MAX 16
I64 rv_menu_lex_n;
I64 rv_menu_lex_id[RV_MENU_LEX_MAX];
I64 rv_menu_lex_steps;
I64 rv_menu_lex_abort;
I64 rv_menu_lex_parse_hits;
I64 RVMenuSkipI(U8 *st, I64 i)
{
  U8 ch;
  while (st) {
    rv_menu_lex_steps++;
    if (rv_menu_lex_steps > RV_MENU_LEX_MAX_STEPS) {
      rv_menu_lex_abort = 1;
      break;
    }
    ch = st[i];
    if (!ch)
      break;
    if (ch == 32 || ch == 9 || ch == 13 || ch == 10) {
      i++;
      continue;
    }
    break;
  }
  return i;
}

I64 RVMenuReadIdentI(U8 *st, I64 i, U8 *out, I64 max)
{
  I64 n;
  U8 ch;
  n = 0;
  i = RVMenuSkipI(st, i);
  if (!out || max < 2) {
    if (out)
      if (max > 0)
        out[0] = 0;
    return i;
  }
  out[0] = 0;
  if (!st)
    return i;
  ch = st[i];
  if (!ch)
    return i;
  if (!((ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || ch == 95))
    return i;
  while (st[i]) {
    rv_menu_lex_steps++;
    if (rv_menu_lex_steps > RV_MENU_LEX_MAX_STEPS) {
      rv_menu_lex_abort = 1;
      break;
    }
    if (n >= max - 1)
      break;
    ch = st[i];
    if (!((ch >= 65 && ch <= 90) || (ch >= 97 && ch <= 122) || (ch >= 48 && ch <= 57) || ch == 95))
      break;
    out[n] = ch;
    n++;
    i++;
  }
  out[n] = 0;
  return i;
}

I64 RVMenuReadI64I(U8 *st, I64 i, I64 *out)
{
  I64 v;
  U8 ch;
  v = 0;
  i = RVMenuSkipI(st, i);
  if (out)
    *out = 0;
  if (!st)
    return i;
  while (1) {
    rv_menu_lex_steps++;
    if (rv_menu_lex_steps > RV_MENU_LEX_MAX_STEPS) {
      rv_menu_lex_abort = 1;
      break;
    }
    ch = st[i];
    if (!ch)
      break;
    if (ch < 48 || ch > 57)
      break;
    v = v * 10 + (ch - 48);
    i++;
  }
  if (out)
    *out = v;
  return i;
}

I64 RVMenuIdFromName(U8 *name)
{
  if (!name)
    return 0;
  if (!name[0])
    return 0;
  if (name[0] == 84 && name[4] == 72)
    return 1;
  if (name[0] == 84 && name[4] == 86)
    return 2;
  if (name[0] == 87 && name[3] == 77)
    return 3;
  if (name[0] == 67 && name[1] == 108)
    return 4;
  if (name[0] == 65 && name[1] == 98)
    return 5;
  if (name[0] == 72 && name[1] == 101)
    return 6;
  if (name[0] == 70 && name[1] == 111)
    return 7;
  if (name[0] == 67 && name[1] == 116)
    return 8;
  return 0;
}

I64 RVMenuParseFlatI(U8 *st, I64 i)
{
  I64 depth;
  I64 id;
  I64 arg1;
  U8 name[24];
  U8 ch;
  depth = 0;
  while (st && st[i] && rv_menu_lex_n < RV_MENU_LEX_MAX) {
    rv_menu_lex_steps++;
    if (rv_menu_lex_steps > RV_MENU_LEX_MAX_STEPS) {
      rv_menu_lex_abort = 1;
      break;
    }
    i = RVMenuSkipI(st, i);
    ch = st[i];
    if (!ch)
      break;
    if (ch == 125) {
      if (depth > 0)
        depth--;
      i++;
      continue;
    }
    i = RVMenuReadIdentI(st, i, name, 24);
    i = RVMenuSkipI(st, i);
    ch = st[i];
    if (ch == 40) {
      i++;
      id = 0;
      arg1 = 0;
      i = RVMenuSkipI(st, i);
      if (st[i] && st[i] != 44 && st[i] != 41)
        i = RVMenuReadI64I(st, i, &id);
      i = RVMenuSkipI(st, i);
      if (st[i] == 44) {
        i++;
        i = RVMenuSkipI(st, i);
        if (st[i] && st[i] != 44 && st[i] != 41)
          i = RVMenuReadI64I(st, i, &arg1);
      }
      while (st[i] && st[i] != 41) {
        rv_menu_lex_steps++;
        if (rv_menu_lex_steps > RV_MENU_LEX_MAX_STEPS) {
          rv_menu_lex_abort = 1;
          break;
        }
        i++;
      }
      if (st[i] == 41)
        i++;
      i = RVMenuSkipI(st, i);
      if (st[i] == 59)
        i++;
      if (!id && arg1 > 0)
        id = arg1;
      if (!id)
        id = RVMenuIdFromName(name);
      if (id && rv_menu_lex_n < RV_MENU_LEX_MAX) {
        rv_menu_lex_id[rv_menu_lex_n] = id;
        rv_menu_lex_n++;
      }
    } else if (ch == 123) {
      depth++;
      i++;
    } else {
      if (ch)
        i++;
    }
  }
  return i;
}

public I64 RVMenuLexNew(U8 *st)
{
  rv_menu_lex_n = 0;
  rv_menu_lex_steps = 0;
  rv_menu_lex_abort = 0;
  if (!st || !st[0])
    return 0;
  rv_menu_lex_parse_hits++;
  RVMenuParseFlatI(st, 0);
  if (rv_menu_lex_abort)
    return 0;
  return rv_menu_lex_n;
}

public I64 RVMenuLexSelfTest()
{
  return RVMenuLexNew("Win{TileHorz(,1);TileVert(,2);WinMax(,3);Close(,4);}Help{About(,5);Help(,6);FormDemo(,7);CtrlsDemo(,8);}");
}
