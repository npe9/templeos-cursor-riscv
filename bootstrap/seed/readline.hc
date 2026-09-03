// readline.hc -- HolyC REPL smart Tab + history Up/Down (G5).
// Mid-token → CompTab; else 2-space indent. Multi-entry history ring (compile units).
// Multiline asm{} context: feed g_rl_accum before the current line (CompAsmMode).
// Include after complete.hc + term.hc + tty.hc (TermClearEol / KEY_* / TtyInCh).
// Soft RX via TtyInCh (HcUartGet + ICRNL) — do not TermKeyGet; do not touch uart ring.
// Erase/kill/eof policy lives in tty.hc; Tab/history stay here.
U8 *g_rl_accum;
I64 g_rl_accum_len;
U8 *g_rl_prompt;
I64 g_rl_cont;
I64 g_rl_cur;
#define RL_HIST_MAX 16
#define RL_HIST_CAP 256
U8 g_rl_hist_ring[16][256];
I64 g_rl_hist_n;
I64 g_rl_hist_head;
I64 g_rl_hist_age;
U8 g_rl_hist_draft[256];
// RlReadKey -- TtyInCh + ESC/[ A|B|C|D|H|F → arrows/home/end.
// Optional VT Ctrl-A prefix when g_vt_keys (console.hc VtKeys(1)).
I64 RlReadKey()
{
  I64 ch, n1, n2;
  ch = TtyInCh();
  if (g_vt_keys && ch == 1) {
    n1 = TtyInCh();
    if (n1 >= '0' && n1 <= '3') {
      Vt(n1 - '0');
      return -1;
    }
    if (n1 == 'n' || n1 == 'N') {
      VtNext;
      return -1;
    }
    if (n1 == 'p' || n1 == 'P') {
      VtPrev;
      return -1;
    }
    if (n1 == 'd' || n1 == 'D') {
      VtDetach;
      return -1;
    }
    if (n1 == 'l' || n1 == 'L') {
      VtList;
      return -1;
    }
    if (n1 == 'a' || n1 == 1)
      return 1;
    return -1;
  }
  if (ch != 27)
    return ch;
  n1 = TtyInCh();
  if (n1 == '[') {
    n2 = TtyInCh();
    if (n2 == 'A')
      return KEY_UP;
    if (n2 == 'B')
      return KEY_DOWN;
    if (n2 == 'C')
      return KEY_RIGHT;
    if (n2 == 'D')
      return KEY_LEFT;
    if (n2 == 'H')
      return KEY_HOME;
    if (n2 == 'F')
      return KEY_END;
    // CSI 3~ = Delete (consume '~')
    if (n2 == '3') {
      n2 = TtyInCh();
      if (n2 == '~')
        return KEY_DELETE;
      return -1;
    }
    return -1;
  }
  if (n1 == 'O') {
    n2 = TtyInCh();
    if (n2 == 'A')
      return KEY_UP;
    if (n2 == 'B')
      return KEY_DOWN;
    if (n2 == 'C')
      return KEY_RIGHT;
    if (n2 == 'D')
      return KEY_LEFT;
    if (n2 == 'H')
      return KEY_HOME;
    if (n2 == 'F')
      return KEY_END;
    return -1;
  }
  return -1;
}

I64 ReplSmartTab(U8 *buf, I64 max, I64 *len_p, I64 list_ok)
{
  I64 n;
  if (!buf || !len_p || max < 4)
    return -1;
  n = *len_p;
  if (n < 0)
    n = 0;
  if (n >= max)
    n = max - 1;
  CompCx = n;
  CompAsmMode = 0;
  CompAsmReset();
  if (g_rl_accum && g_rl_accum_len > 0)
    CompAsmFeed(g_rl_accum, g_rl_accum_len);
  CompAsmFeed(buf, n);
  if (CompAsmInside())
    CompAsmMode = 1;
  if (n > 0 && CompIsPath(buf[n - 1])) {
    CompTab(buf, max, list_ok);
    CompAsmMode = 0;
    *len_p = CompCx;
    return 1;
  }
  CompAsmMode = 0;
  if (n + 2 < max) {
    buf[n] = ' ';
    buf[n + 1] = ' ';
    buf[n + 2] = 0;
    *len_p = n + 2;
    CompCx = n + 2;
    return 0;
  }
  return -1;
}

U0 ReplRedrawLine(U8 *buf, I64 n)
{
  I64 i;
  PutCh('\r');
  TermClearEol();
  if (g_rl_cont)
    UartStr("... ");
  else
    UartStr("> ");
  i = 0;
  while (i < n && buf[i]) {
    PutCh(buf[i]);
    i++;
  }
  // Place cursor: backspace from end to g_rl_cur (mid-line edit).
  if (g_rl_cur < 0)
    g_rl_cur = 0;
  if (g_rl_cur > n)
    g_rl_cur = n;
  i = n;
  while (i > g_rl_cur) {
    PutCh('\b');
    i--;
  }
}
// RlHistGet -- age 0 = most recent; returns 0 if out of range.
U8 *RlHistGet(I64 age)
{
  I64 idx;
  if (age < 0 || age >= g_rl_hist_n)
    return 0;
  idx = g_rl_hist_head - 1 - age;
  while (idx < 0)
    idx += RL_HIST_MAX;
  return &g_rl_hist_ring[idx][0];
}
// RlHistPush -- append compile unit (dedupe consecutive identical).
U0 RlHistPush(U8 *line)
{
  I64 i, prev;
  U8 *old;
  if (!line || !line[0])
    return;
  if (g_rl_hist_n > 0) {
    prev = g_rl_hist_head - 1;
    if (prev < 0)
      prev = RL_HIST_MAX - 1;
    old = &g_rl_hist_ring[prev][0];
    i = 0;
    while (old[i] == line[i]) {
      if (!line[i])
        return;
      i++;
    }
  }
  i = 0;
  while (line[i] && i < RL_HIST_CAP - 1) {
    g_rl_hist_ring[g_rl_hist_head][i] = line[i];
    i++;
  }
  g_rl_hist_ring[g_rl_hist_head][i] = 0;
  g_rl_hist_head = (g_rl_hist_head + 1) % RL_HIST_MAX;
  if (g_rl_hist_n < RL_HIST_MAX)
    g_rl_hist_n++;
}

U0 RlHistPushUnit(U8 *unit, I64 ulen)
{
  I64 s, e, i, j, n;
  if (!unit || ulen <= 0)
    return;
  s = 0;
  e = ulen - 1;
  while (s < ulen && (unit[s] == ' ' || unit[s] == '\t' || unit[s] == '\n'))
    s++;
  while (e >= s && (unit[e] == ' ' || unit[e] == '\t' || unit[e] == '\n'))
    e--;
  if (e < s)
    return;
  n = e - s + 1;
  if (n >= RL_HIST_CAP)
    n = RL_HIST_CAP - 1;
  j = 0;
  i = 0;
  while (i < n && j < RL_HIST_CAP - 1) {
    if (unit[s + i] == '\n')
      g_rl_hist_draft[j] = ' ';
    else
      g_rl_hist_draft[j] = unit[s + i];
    j++;
    i++;
  }
  g_rl_hist_draft[j] = 0;
  RlHistPush(g_rl_hist_draft);
}

U0 RlHistDraftSave(U8 *buf, I64 n)
{
  I64 i;
  i = 0;
  while (i < n && i < RL_HIST_CAP - 1) {
    g_rl_hist_draft[i] = buf[i];
    i++;
  }
  g_rl_hist_draft[i] = 0;
}

U0 RlHistSetFrom(U8 *buf, I64 max, I64 *len_p, U8 *src)
{
  I64 i;
  if (!buf || !len_p || max < 2)
    return;
  if (!src)
    src = "";
  i = 0;
  while (src[i] && i < max - 1) {
    buf[i] = src[i];
    i++;
  }
  buf[i] = 0;
  *len_p = i;
  g_rl_cur = i;
}

I64 RlHistUp(U8 *buf, I64 max, I64 *len_p)
{
  U8 *ent;
  if (!buf || !len_p || g_rl_hist_n <= 0)
    return 0;
  if (g_rl_hist_age + 1 >= g_rl_hist_n)
    return 0;
  if (g_rl_hist_age < 0)
    RlHistDraftSave(buf, *len_p);
  g_rl_hist_age++;
  ent = RlHistGet(g_rl_hist_age);
  if (!ent)
    return 0;
  RlHistSetFrom(buf, max, len_p, ent);
  return 1;
}

I64 RlHistDown(U8 *buf, I64 max, I64 *len_p)
{
  U8 *ent;
  if (!buf || !len_p)
    return 0;
  if (g_rl_hist_age < 0)
    return 0;
  g_rl_hist_age--;
  if (g_rl_hist_age < 0) {
    RlHistSetFrom(buf, max, len_p, g_rl_hist_draft);
    return 1;
  }
  ent = RlHistGet(g_rl_hist_age);
  if (!ent)
    return 0;
  RlHistSetFrom(buf, max, len_p, ent);
  return 1;
}

U0 RlHistLeaveBrowse()
{
  g_rl_hist_age = -1;
}
// RlHistSeed -- boot demos oldest→newest; first Up recalls HIST_SEED_OK.
U0 RlHistSeed()
{
  g_rl_hist_n = 0;
  g_rl_hist_head = 0;
  g_rl_hist_age = -1;
  // Legacy-shaped demos (thin-safe). Newest = smoke needle.
  RlHistPush("Dir;");
  RlHistPush("Regs;");
  RlHistPush("MemMap;");
  RlHistPush("Man(\"Print\");");
  RlHistPush("Man(\"Clint\");");
  RlHistPush("1+2*3;");
  RlHistPush("Help;");
  RlHistPush("Print(\"HIST_SEED_OK\\n\");");
}

U0 ReplBraceFeed(U8 *line, I64 n, I64 *brace, I64 *paren)
{
  I64 i, q;
  if (!line || n <= 0 || !brace || !paren)
    return;
  i = 0;
  while (i < n) {
    if (line[i] == '"' || line[i] == '\'') {
      q = line[i];
      i++;
      while (i < n && line[i] != q) {
        if (line[i] == '\\' && i + 1 < n)
          i++;
        i++;
      }
      if (i < n)
        i++;
      continue;
    }
    if (line[i] == '{')
      (*brace)++;
    else if (line[i] == '}') {
      if (*brace > 0)
        (*brace)--;
    } else if (line[i] == '(')
      (*paren)++;
    else if (line[i] == ')') {
      if (*paren > 0)
        (*paren)--;
    }
    i++;
  }
}

I64 ReplDeferBcplSemi(U8 *line, I64 n)
{
  I64 s, e, i;
  if (!line || n <= 0)
    return 0;
  s = 0;
  e = n - 1;
  while (s < n && (line[s] == ' ' || line[s] == '\t'))
    s++;
  while (e >= s && (line[e] == ' ' || line[e] == '\t'))
    e--;
  if (e < s || line[e] != ')')
    return 0;
  for (i = s; i <= e; i++)
    if (line[i] == '{')
      return 0;
  if (line[s] >= 'A' && line[s] <= 'Z')
    return 1;
  if (line[s] >= 'a' && line[s] <= 'z')
    return 1;
  return 0;
}

I64 ReplShouldParse(U8 *line, I64 n, I64 brace, I64 paren)
{
  I64 e;
  if (brace || paren)
    return 0;
  if (n <= 0)
    return 0;
  e = n - 1;
  while (e >= 0 && (line[e] == ' ' || line[e] == '\t'))
    e--;
  if (e < 0)
    return 0;
  if (line[e] == ';' || line[e] == '}')
    return 1;
  if (line[e] == ',')
    return 0;
  if (ReplDeferBcplSemi(line, n))
    return 0;
  return 1;
}
