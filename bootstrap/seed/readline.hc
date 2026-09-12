// readline.hc -- HolyC REPL smart Tab + history Up/Down (G5).
// Mid-token at CompCx/g_rl_cur → CompTab; else 2-space indent (mid-line ok).
// Multi-entry history ring (compile units).
// Multiline asm{} context: feed g_rl_accum before the current line (CompAsmMode).
// Include after complete.hc + term.hc + tty.hc (TermClearEol / KEY_* / TtyInCh).
// Soft RX via TtyInCh (HcUartGet + ICRNL) — do not TermKeyGet; do not touch uart ring.
// Erase/kill/eof policy lives in tty.hc; Tab/history stay here.
// History stores whole compile units (embedded '\n'); Up recalls multiline via
// RlHistRecallUnit (prefix → repl_accum, last line → edit buf). Single-line HIST_*
// needles unchanged (seeds / session Prints have no '\n').
U8 *g_rl_accum;
I64 g_rl_accum_len;
U8 *g_rl_prompt;
I64 g_rl_cont;
I64 g_rl_cur;
// After eval/compile error: next ReplReadLine starts with this line (mid-line edit).
U8 g_rl_seed[512];
I64 g_rl_seed_len;
// Copy of the last seed handed to the reader, kept past the consume so the loop can
// tell a real cursor edit from a pipe that just appended to it.
U8 g_rl_seed_out[512];
I64 g_rl_seed_out_len;
#define RL_HIST_MAX 16
#define RL_HIST_CAP 1024
U8 g_rl_hist_ring[16][1024];
I64 g_rl_hist_n;
I64 g_rl_hist_head;
I64 g_rl_hist_age;
U8 g_rl_hist_draft[1024];
I64 g_rl_hist_accum_clear;
U8 *g_rl_hist_recall_unit;
// RlSeedLine -- keep last physical line of a failed unit for re-edit.
U0 RlSeedLine(U8 *s, I64 n)
{
  I64 i, start;
  g_rl_seed_len = 0;
  g_rl_seed[0] = 0;
  if (!s || n <= 0)
    return;
  start = 0;
  i = 0;
  while (i < n) {
    if (s[i] == '\n')
      start = i + 1;
    i++;
  }
  i = 0;
  while (start + i < n && i < 511) {
    g_rl_seed[i] = s[start + i];
    i++;
  }
  g_rl_seed[i] = 0;
  g_rl_seed_len = i;
  i = 0;
  while (i < g_rl_seed_len) {
    g_rl_seed_out[i] = g_rl_seed[i];
    i++;
  }
  g_rl_seed_out[i] = 0;
  g_rl_seed_out_len = i;
}
// Drop the pending seed only (the reader calls this once it has taken it).
U0 RlSeedClear()
{
  g_rl_seed_len = 0;
  g_rl_seed[0] = 0;
}
// Drop the pending seed and forget what was handed out.
U0 RlSeedForget()
{
  RlSeedClear;
  g_rl_seed_out_len = 0;
  g_rl_seed_out[0] = 0;
}
// RlSeedWasAppended -- s is the seed we handed out with more text glued on the end
// (or unchanged). Piped stdin has no cursor, so a re-seed there would glue every
// later line onto the failed one and wedge the rest of the session.
I64 RlSeedWasAppended(U8 *s, I64 n)
{
  I64 i;
  if (!s || g_rl_seed_out_len <= 0 || n < g_rl_seed_out_len)
    return 0;
  for (i = 0; i < g_rl_seed_out_len; i++)
    if (s[i] != g_rl_seed_out[i])
      return 0;
  return 1;
}
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
  I64 n, cx, i;
  if (!buf || !len_p || max < 4)
    return -1;
  n = *len_p;
  if (n < 0)
    n = 0;
  if (n >= max)
    n = max - 1;
  cx = g_rl_cur;
  if (cx < 0)
    cx = 0;
  if (cx > n)
    cx = n;
  CompCx = cx;
  CompAsmMode = 0;
  CompAsmReset();
  if (g_rl_accum && g_rl_accum_len > 0)
    CompAsmFeed(g_rl_accum, g_rl_accum_len);
  // Feed only through cursor so asm{} context matches CompCx.
  CompAsmFeed(buf, cx);
  if (CompAsmInside())
    CompAsmMode = 1;
  if (cx > 0 && CompIsPath(buf[cx - 1])) {
    CompTab(buf, max, list_ok);
    CompAsmMode = 0;
    i = 0;
    while (i < max - 1 && buf[i])
      i++;
    *len_p = i;
    if (CompCx < 0)
      CompCx = 0;
    if (CompCx > i)
      CompCx = i;
    g_rl_cur = CompCx;
    return 1;
  }
  CompAsmMode = 0;
  if (n + 2 >= max)
    return -1;
  // Mid-line or EOL: insert 2-space indent at cursor.
  i = n;
  while (i >= cx) {
    buf[i + 2] = buf[i];
    i--;
  }
  buf[cx] = ' ';
  buf[cx + 1] = ' ';
  *len_p = n + 2;
  CompCx = cx + 2;
  g_rl_cur = CompCx;
  return 0;
}
// Probe: ReplSmartTab uses g_rl_cur (not EOL-only CompCx=n).
U0 RlMidDemo()
{
  U8 line[32];
  U8 *s;
  I64 i, n;
  s = "x=MEM_PL;";
  i = 0;
  while (s[i] && i < 31) {
    line[i] = s[i];
    i++;
  }
  line[i] = 0;
  n = i;
  CompAsmMode = 0;
  CompAsmReset();
  g_rl_cur = 8;
  ReplSmartTab(line, 32, &n, 0);
  UartStr(line);
  PutCh('\n');
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
    PutCh(8);
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
  // Preserve embedded newlines (compile-unit recall); do not flatten to spaces.
  while (i < n && j < RL_HIST_CAP - 1) {
    g_rl_hist_draft[j] = unit[s + i];
    j++;
    i++;
  }
  g_rl_hist_draft[j] = 0;
  RlHistPush(g_rl_hist_draft);
}

I64 RlHistHasNl(U8 *s)
{
  I64 i;
  if (!s)
    return 0;
  i = 0;
  while (s[i]) {
    if (s[i] == '\n')
      return 1;
    i++;
  }
  return 0;
}

U0 RlHistScanDepths(U8 *text, I64 n, I64 *bd, I64 *pd)
{
  I64 i, q, brace, paren;
  brace = 0;
  paren = 0;
  if (!text || n <= 0) {
    if (bd)
      *bd = 0;
    if (pd)
      *pd = 0;
    return;
  }
  i = 0;
  while (i < n) {
    if (text[i] == '"' || text[i] == '\'') {
      q = text[i];
      i++;
      while (i < n && text[i] != q) {
        if (text[i] == '\\' && i + 1 < n)
          i++;
        i++;
      }
      if (i < n)
        i++;
      continue;
    }
    if (text[i] == '{')
      brace++;
    else if (text[i] == '}') {
      if (brace > 0)
        brace--;
    } else if (text[i] == '(')
      paren++;
    else if (text[i] == ')') {
      if (paren > 0)
        paren--;
    }
    i++;
  }
  if (bd)
    *bd = brace;
  if (pd)
    *pd = paren;
}
// RlHistRecallUnit -- replay prefix lines to UART; last line → buf for edit.
// Fills g_rl_accum[0..accum_len) with prefix including final '\n' when present.
// Caller owns brace/paren via out pointers; sets g_rl_cont.
I64 RlHistRecallUnit(U8 *unit, U8 *buf, I64 max, I64 *len_p, U8 *accum, I64 accum_max, I64 *accum_len_p, I64 *brace_p, I64 *paren_p)
{
  I64 ulen, i, prefix, llen, first;
  U8 *p, *nl, *last_nl, *last;
  if (!unit || !buf || !len_p || !accum || !accum_len_p || max < 2 || accum_max < 2)
    return 0;
  ulen = 0;
  while (unit[ulen])
    ulen++;
  RlHistScanDepths(unit, ulen, brace_p, paren_p);
  last_nl = 0;
  p = unit;
  while (*p) {
    if (*p == '\n')
      last_nl = p;
    p++;
  }
  if (!last_nl) {
    i = 0;
    while (unit[i] && i < max - 1) {
      buf[i] = unit[i];
      i++;
    }
    buf[i] = 0;
    *len_p = i;
    *accum_len_p = 0;
    accum[0] = 0;
    g_rl_cont = 0;
    return 1;
  }
  prefix = last_nl - unit + 1;
  if (prefix >= accum_max)
    prefix = accum_max - 1;
  i = 0;
  while (i < prefix) {
    accum[i] = unit[i];
    i++;
  }
  accum[prefix] = 0;
  *accum_len_p = prefix;
  PutCh('\n');
  p = unit;
  first = 1;
  while (p <= last_nl) {
    nl = p;
    while (nl <= last_nl && *nl != '\n')
      nl++;
    if (nl > last_nl)
      break;
    if (first) {
      UartStr("> ");
      first = 0;
    } else
      UartStr("... ");
    i = 0;
    while (p + i < nl) {
      PutCh(p[i]);
      i++;
    }
    PutCh('\n');
    p = nl + 1;
  }
  last = last_nl + 1;
  llen = 0;
  while (last[llen] && last[llen] != '\n')
    llen++;
  if (llen >= max)
    llen = max - 1;
  i = 0;
  while (i < llen) {
    buf[i] = last[i];
    i++;
  }
  buf[llen] = 0;
  *len_p = llen;
  g_rl_cont = 1;
  return 2;
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
// RlHistUp -- 0=noop 1=single-line fill 2=multiline (g_rl_hist_recall_unit set).
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
  if (RlHistHasNl(ent)) {
    g_rl_hist_recall_unit = ent;
    buf[0] = 0;
    *len_p = 0;
    return 2;
  }
  g_rl_hist_recall_unit = 0;
  g_rl_hist_accum_clear = 1;
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
    g_rl_hist_recall_unit = 0;
    g_rl_hist_accum_clear = 1;
    RlHistSetFrom(buf, max, len_p, g_rl_hist_draft);
    return 1;
  }
  ent = RlHistGet(g_rl_hist_age);
  if (!ent)
    return 0;
  if (RlHistHasNl(ent)) {
    g_rl_hist_recall_unit = ent;
    buf[0] = 0;
    *len_p = 0;
    return 2;
  }
  g_rl_hist_recall_unit = 0;
  g_rl_hist_accum_clear = 1;
  RlHistSetFrom(buf, max, len_p, ent);
  return 1;
}

U0 RlHistLeaveBrowse()
{
  g_rl_hist_age = -1;
  g_rl_hist_recall_unit = 0;
}
// RlHistSeed -- boot demos oldest→newest; first Up recalls HIST_SEED_OK.
U0 RlHistSeed()
{
  g_rl_hist_n = 0;
  g_rl_hist_head = 0;
  g_rl_hist_age = -1;
  g_rl_hist_accum_clear = 0;
  g_rl_hist_recall_unit = 0;
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
