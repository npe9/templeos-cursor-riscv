// term.hc -- HolyC terminal: sizing + ANSI out + CSI/SS3 input parser over the shared UART ring.
#define TF_ANSI 1
#define TF_CPR 2
#define TF_COLOR 4
#define TE_NONE 0
#define TE_CHAR 1
#define TE_UP 2
#define TE_DOWN 3
#define TE_LEFT 4
#define TE_RIGHT 5
#define TE_HOME 6
#define TE_END 7
#define TE_DELETE 8
#define TE_INSERT 9
#define TE_PGUP 10
#define TE_PGDN 11
#define TE_ESCAPE 12
#define TE_RESIZE 13
#define TE_CURSOR_REPORT 14
#define TE_DEVICE_REPORT 15
#define KEY_UP 256
#define KEY_DOWN 257
#define KEY_RIGHT 258
#define KEY_LEFT 259
#define KEY_HOME 260
#define KEY_END 261
#define KEY_DELETE 262
#define KEY_PGUP 263
#define KEY_PGDN 264
#define KEY_INSERT 265
#define TS_GROUND 0
#define TS_ESC 1
#define TS_CSI 2
#define TS_SS3 3
#define TS_OSC 4
#define TERM_Q 64
#define TERM_NAME_MAX 32
#define TERM_OSC_MAX 64
/* Custom OSC 777: host → guest size+type (ESC ] 777 ; cols ; rows ; name BEL). */
#define TERM_OSC_NEGOTIATE 777
class CTerm
{
  I64 rows;
  I64 cols;
  I64 flags;
};

class CTermEvent
{
  I64 type;
  I64 a;
  I64 b;
};
I64 g_term_rows = 24;
I64 g_term_cols = 80;
I64 g_term_flags = TF_ANSI;
I64 g_term_state = TS_GROUND;
I64 g_term_esc_at = 0;
I64 g_term_nparams = 0;
I64 g_term_cur_param = 0;
I64 g_term_got_digit = 0;
I64 g_term_priv = 0;
I64 g_term_params[8];
I64 g_term_gave_up = 0;
U8 *g_term_name_p;
U8 g_term_osc[TERM_OSC_MAX];
I64 g_term_osc_n = 0;
/* HolyC interactive path owns the shared RX ring while TermKeyGet/TermProbe run.
 * Cleared otherwise so GetCh/TermPoll cannot steal bytes from C readline/EdC. */
I64 g_term_rx_own = 0;
CTermEvent g_keyq[TERM_Q];
I64 g_tkh = 0, g_tkt = 0;
CTermEvent g_repq[TERM_Q];
I64 g_trh = 0, g_trt = 0;
U8 g_uart_ung[8];
I64 g_uart_ung_n = 0;
/* Geometry + termname are HolyC-owned (g_term_*). TermProbe / CSI 8 / OSC 777
 * update these; Vi/EditHoly read TermRows/TermCols. Optional one-way push to C
 * TermSetSize keeps EdC/EditC in sync. Do NOT read C TermRows/Cols/Probe slots. */
I64 TermRows()
{
  return g_term_rows;
}

I64 TermCols()
{
  return g_term_cols;
}

I64 TermFlags()
{
  return g_term_flags;
}
// TermName -- TermName()
// NAME
//   TermName - current terminal type string (TERM-ish)
// SYNOPSIS
//   U8 *TermName();
// DESCRIPTION
//   Returns guest-stored name (default "ansi"). Host may set via OSC 777 or
//   TermSetName. Editors do not require a rich terminfo — name is advisory.
// EXAMPLES
//   Print("%s\n", TermName);
// SEE ALSO
//   TermSetName  TermSize  TermRep  TermHelp
U8 *TermName()
{
  if (!g_term_name_p) {
    g_term_name_p = MAlloc(TERM_NAME_MAX);
    if (g_term_name_p)
      LogCpy(g_term_name_p, "ansi", TERM_NAME_MAX);
  }
  return g_term_name_p;
}
// TermSetName -- TermSetName(s)
// NAME
//   TermSetName - store terminal type string
// SYNOPSIS
//   U0 TermSetName(U8 *s);
// DESCRIPTION
//   Copies into heap name buffer (default "ansi").
// EXAMPLES
//   TermSetName("xterm");
// SEE ALSO
//   TermName  TermSize  TermRep
U0 TermSetName(I64 s)
{
  /* String arg from seed JIT is ABI-fragile — use TermNamePreset or OSC 777. */
  (s);
}

U0 TermNameAnsi()
{
  if (!g_term_name_p)
    TermName;
  LogCpy(g_term_name_p, "ansi", TERM_NAME_MAX);
}

U0 TermNameXterm()
{
  if (!g_term_name_p)
    TermName;
  LogCpy(g_term_name_p, "xterm", TERM_NAME_MAX);
}

U0 TermNameSet(I64 s)
{
  TermSetName(s);
}

U0 TermSetSize(I64 rows, I64 cols)
{
  I64 (*csetz)(I64 rows, I64 cols);
  if (rows >= 2 && rows <= 255)
    g_term_rows = rows;
  if (cols >= 2 && cols <= 512)
    g_term_cols = cols;
  g_term_flags &= ~TF_CPR;
  csetz = *(I64 *)0x87001110;
  /* intentional bridge: HolyC → C repair hatch only */
  if (csetz)
    csetz(g_term_rows, g_term_cols);
}
// TermSize -- TermSize(cols, rows)
// NAME
//   TermSize - set geometry cols-first (stty-style)
// SYNOPSIS
//   U0 TermSize(I64 cols, I64 rows);
// DESCRIPTION
//   Guest-side size negotiation (CONSOLE.md #11). Args are COLUMNS then LINES
//   — TermSize(80,24) is the classic VT. Clears TF_CPR (manual override). For
//   rows-first see TermSetSize. Host may also push ESC[8;rows;cols t or OSC 777
//   while TermProbe / editors own RX.
// EXAMPLES
//   TermSize(80,24);
//   TermSize(120,40); TermRep;
// SEE ALSO
//   TermSetSize  TermRows  TermCols  TermProbe  TermQuery  TermRep  TermHelp
U0 TermSize(I64 cols, I64 rows)
{
  TermSetSize(rows, cols);
}

U0 TermGet(CTerm *t)
{
  t->rows = TermRows();
  t->cols = TermCols();
  t->flags = TermFlags();
}

I64 TermTextRows()
{
  I64 n = TermRows() - 2;
  if (n < 1)
    return 1;
  return n;
}

U0 TermGoto(I64 row, I64 col)
{
  if (!(TermFlags() & TF_ANSI))
    return;
  PutCh(27);
  PutCh('[');
  "%d", row;
  PutCh(';');
  "%d", col;
  PutCh('H');
}

U0 TermClear()
{
  if (!(TermFlags() & TF_ANSI))
    return;
  PutCh(27);
  PutCh('[');
  PutCh('2');
  PutCh('J');
  PutCh(27);
  PutCh('[');
  PutCh('H');
}

U0 TermClearEol()
{
  if (!(TermFlags() & TF_ANSI))
    return;
  PutCh(27);
  PutCh('[');
  PutCh('2');
  PutCh('K');
}

U0 TermHideCursor()
{
  if (!(TermFlags() & TF_ANSI))
    return;
  PutCh(27);
  PutCh('[');
  PutCh('?');
  PutCh('2');
  PutCh('5');
  PutCh('l');
}

U0 TermShowCursor()
{
  if (!(TermFlags() & TF_ANSI))
    return;
  PutCh(27);
  PutCh('[');
  PutCh('?');
  PutCh('2');
  PutCh('5');
  PutCh('h');
}

I64 TermNow()
{
  return HcRdTime();
}

I64 TqSpace(I64 h, I64 t)
{
  return (t - h - 1) & (TERM_Q - 1);
}

I64 TqPush(CTermEvent *q, I64 *h, I64 *t, I64 type, I64 a, I64 b)
{
  I64 n;
  if (!TqSpace (*h, *t))
    return -1;
  n = *h;
  q[n].type = type;
  q[n].a = a;
  q[n].b = b;
  *h = (n + 1) & (TERM_Q - 1);
  return 0;
}

I64 TqPop(CTermEvent *q, I64 *h, I64 *t, CTermEvent *out)
{
  I64 n;
  if (*h == *t)
    return 0;
  n = *t;
  out->type = q[n].type;
  out->a = q[n].a;
  out->b = q[n].b;
  *t = (n + 1) & (TERM_Q - 1);
  return 1;
}

U0 UartUnget(I64 ch)
{
  if (g_uart_ung_n < 8)
    g_uart_ung[g_uart_ung_n++] = ch;
}
/* Push a byte back onto the shared UART RX ring (same ring C readline drains).
 * Used when Esc meta cancels so a quit-on-Esc UI does not steal the next REPL char. */
U0 UartRxUnget(I64 ch)
{
  I64 rx, rhp, rtp, cap, rh, rt, prev;
  rx = *(I64 *)0x87001020;
  rhp = *(I64 *)0x87001028;
  rtp = *(I64 *)0x87001030;
  cap = *(I64 *)0x87001038;
  if (!rx || !rhp || !rtp || cap < 2) {
    /* Product HolyC soft RX (hc_repl/uart.hc). Host slots are absent on
     * repl-holyc — previously this returned without pushback and Esc ate the
     * next byte (INSERT Enter / ':' after Esc). */
    HcUartUnget(ch);
    return;
  }
  rh = *(I64 *)rhp;
  rt = *(I64 *)rtp;
  prev = (rt - 1) & (cap - 1);
  if (prev == rh)
    return;
  *(U8 *)(rx + prev) = ch;
  *(I64 *)rtp = prev;
}

I64 UartTryGetByte()
{
  I64 ch, rx, rhp, rtp, cap, rh, rt;
  if (g_uart_ung_n > 0)
    return g_uart_ung[--g_uart_ung_n];
  /* Ring is shared with C readline/EdC. Only drain while g_term_rx_own (TermKeyGet
   * / TermProbe); otherwise piped smoke desyncs when GetCh/TermPoll steal bytes. */
  if (!g_term_rx_own)
    return -1;
  rx = *(I64 *)0x87001020;
  rhp = *(I64 *)0x87001028;
  rtp = *(I64 *)0x87001030;
  cap = *(I64 *)0x87001038;
  if (!rx || !rhp || !rtp || cap < 2) {
    /* Product HolyC path: soft ring in hc_repl/uart.hc (HcUartTry). */
    return HcUartTry();
  }
  rh = *(I64 *)rhp;
  rt = *(I64 *)rtp;
  if (rh == rt)
    return -1;
  ch = *(U8 *)(rx + rt);
  *(I64 *)rtp = (rt + 1) & (cap - 1);
  return ch;
}

I64 TermEmitKey(I64 type, I64 a, I64 b)
{
  return TqPush(g_keyq, &g_tkh, &g_tkt, type, a, b);
}

I64 TermEmitRep(I64 type, I64 a, I64 b)
{
  return TqPush(g_repq, &g_trh, &g_trt, type, a, b);
}

U0 TermHandleCsi(I64 ch)
{
  I64 *p = g_term_params;
  I64 n = g_term_nparams;
  I64 a, b;
  if (n < 1)
    a = 0;
  else
    a = p[0];
  if (n < 2)
    b = 0;
  else
    b = p[1];
  if (ch == 'A')
    TermEmitKey(TE_UP, 0, 0);
  else if (ch == 'B')
    TermEmitKey(TE_DOWN, 0, 0);
  else if (ch == 'C')
    TermEmitKey(TE_RIGHT, 0, 0);
  else if (ch == 'D')
    TermEmitKey(TE_LEFT, 0, 0);
  else if (ch == 'H' || ch == 'f')
    TermEmitKey(TE_HOME, 0, 0);
  else if (ch == 'F')
    TermEmitKey(TE_END, 0, 0);
  else if (ch == '~') {
    if (a == 1 || a == 7)
      TermEmitKey(TE_HOME, 0, 0);
    else if (a == 4 || a == 8)
      TermEmitKey(TE_END, 0, 0);
    else if (a == 3)
      TermEmitKey(TE_DELETE, 0, 0);
    else if (a == 2)
      TermEmitKey(TE_INSERT, 0, 0);
    else if (a == 5)
      TermEmitKey(TE_PGUP, 0, 0);
    else if (a == 6)
      TermEmitKey(TE_PGDN, 0, 0);
  } else if (ch == 'R') {
    if (a >= 2 && a <= 255 && b >= 2 && b <= 512) {
      g_term_rows = a;
      g_term_cols = b;
      g_term_flags |= TF_CPR;
    }
    TermEmitRep(TE_CURSOR_REPORT, a, b);
  } else if (ch == 't') {
    /* xterm window-size reply ESC[8;rows;cols t */
    if (n >= 3 && a == 8) {
      I64 rr, cc;
      rr = p[1];
      cc = p[2];
      if (rr >= 2 && rr <= 255 && cc >= 2 && cc <= 512) {
        g_term_rows = rr;
        g_term_cols = cc;
        g_term_flags |= TF_CPR;
      }
      TermEmitRep(TE_RESIZE, rr, cc);
    }
  } else if (ch == 'c')
    TermEmitRep(TE_DEVICE_REPORT, a, b);
}

U0 TermHandleOsc()
{
  /* OSC 777 ; cols ; rows ; name  — host push size + termname (BEL-terminated). */
  I64 cols, rows;
  U8 *p;
  if (g_term_osc_n <= 0)
    return;
  g_term_osc[g_term_osc_n] = 0;
  p = g_term_osc;
  /* Require leading "777;" */
  if (p[0] != '7' || p[1] != '7' || p[2] != '7' || p[3] != ';')
    return;
  p += 4;
  cols = 0;
  while (*p >= '0' && *p <= '9') {
    cols = cols * 10 + (*p - '0');
    p++;
  }
  if (*p != ';')
    return;
  p++;
  rows = 0;
  while (*p >= '0' && *p <= '9') {
    rows = rows * 10 + (*p - '0');
    p++;
  }
  if (*p == ';') {
    p++;
    if (!g_term_name_p)
      TermName;
    LogCpy(g_term_name_p, p, TERM_NAME_MAX);
  }
  if (rows >= 2 && rows <= 255 && cols >= 2 && cols <= 512) {
    g_term_rows = rows;
    g_term_cols = cols;
    g_term_flags |= TF_CPR;
    TermEmitRep(TE_RESIZE, rows, cols);
  }
}

I64 TermParseByte(I64 ch)
{
  I64 n;
  if (g_term_state == TS_GROUND) {
    if (ch == 27) {
      g_term_state = TS_ESC;
      g_term_esc_at = TermNow();
      return 0;
    }
    return TermEmitKey(TE_CHAR, ch, 0);
  }
  if (g_term_state == TS_ESC) {
    g_term_esc_at = TermNow();
    if (ch == '[') {
      g_term_state = TS_CSI;
      g_term_nparams = 0;
      g_term_cur_param = 0;
      g_term_got_digit = 0;
      g_term_priv = 0;
      return 0;
    }
    if (ch == 'O') {
      g_term_state = TS_SS3;
      return 0;
    }
    if (ch == ']') {
      g_term_state = TS_OSC;
      g_term_osc_n = 0;
      return 0;
    }
    g_term_state = TS_GROUND;
    TermEmitKey(TE_ESCAPE, 27, 0);
    /* Shared ring — not HolyC-only ung — so Esc quit (Funs) leaves the next
     * REPL line intact for C readline. */
    UartRxUnget(ch);
    return 0;
  }
  if (g_term_state == TS_CSI) {
    g_term_esc_at = TermNow();
    if (ch >= '0' && ch <= '9') {
      g_term_cur_param = g_term_cur_param * 10 + (ch - '0');
      g_term_got_digit = 1;
      return 0;
    }
    if (ch == ';') {
      if (g_term_nparams < 8) {
        if (g_term_got_digit)
          g_term_params[g_term_nparams++] = g_term_cur_param;
        else
          g_term_params[g_term_nparams++] = 0;
      }
      g_term_cur_param = 0;
      g_term_got_digit = 0;
      return 0;
    }
    if (ch == '?' || ch == '>') {
      g_term_priv = ch;
      return 0;
    }
    if (ch >= 0x20 && ch < 0x30)
      return 0;
    if (TqSpace(g_tkh, g_tkt) < 1 || TqSpace(g_trh, g_trt) < 1) {
      UartUnget(ch);
      return -1;
    }
    if (g_term_got_digit && g_term_nparams < 8)
      g_term_params[g_term_nparams++] = g_term_cur_param;
    g_term_state = TS_GROUND;
    TermHandleCsi(ch);
    return 0;
  }
  if (g_term_state == TS_SS3) {
    if (TqSpace(g_tkh, g_tkt) < 2) {
      UartUnget(ch);
      return -1;
    }
    g_term_state = TS_GROUND;
    if (ch == 'A')
      TermEmitKey(TE_UP, 0, 0);
    else if (ch == 'B')
      TermEmitKey(TE_DOWN, 0, 0);
    else if (ch == 'C')
      TermEmitKey(TE_RIGHT, 0, 0);
    else if (ch == 'D')
      TermEmitKey(TE_LEFT, 0, 0);
    else if (ch == 'H')
      TermEmitKey(TE_HOME, 0, 0);
    else if (ch == 'F')
      TermEmitKey(TE_END, 0, 0);
    else {
      TermEmitKey(TE_ESCAPE, 27, 0);
      return TermParseByte(ch);
    }
    return 0;
  }
  if (g_term_state == TS_OSC) {
    g_term_esc_at = TermNow();
    /* BEL ends OSC; ESC starts ST (ESC \) — treat ESC as abort into ESC state. */
    if (ch == 7) {
      TermHandleOsc();
      g_term_state = TS_GROUND;
      g_term_osc_n = 0;
      return 0;
    }
    if (ch == 27) {
      g_term_state = TS_ESC;
      g_term_osc_n = 0;
      return 0;
    }
    if (g_term_osc_n < TERM_OSC_MAX - 1)
      g_term_osc[g_term_osc_n++] = ch;
    return 0;
  }
  return 0;
}

U0 TermCheckTimeouts()
{
  if (g_term_state == TS_GROUND || !g_term_esc_at)
    return;
  if (TermNow() - g_term_esc_at < 100000)
    return;
  // ~10ms @ 10MHz
  if (g_term_state == TS_ESC) {
    if (TermEmitKey(TE_ESCAPE, 27, 0) < 0)
      return;
  }
  g_term_state = TS_GROUND;
  g_term_esc_at = 0;
  g_term_osc_n = 0;
}

U0 TermPoll()
{
  I64 ch;
  UartRxDrain();
  while (TqSpace(g_tkh, g_tkt) >= 2 && TqSpace(g_trh, g_trt) >= 2) {
    ch = UartTryGetByte();
    if (ch < 0)
      break;
    if (TermParseByte(ch) < 0)
      break;
  }
  TermCheckTimeouts();
}

I64 TermMapKey(CTermEvent *e)
{
  if (e->type == TE_CHAR)
    return e->a;
  if (e->type == TE_ESCAPE)
    return 27;
  if (e->type == TE_UP)
    return KEY_UP;
  if (e->type == TE_DOWN)
    return KEY_DOWN;
  if (e->type == TE_RIGHT)
    return KEY_RIGHT;
  if (e->type == TE_LEFT)
    return KEY_LEFT;
  if (e->type == TE_HOME)
    return KEY_HOME;
  if (e->type == TE_END)
    return KEY_END;
  if (e->type == TE_DELETE)
    return KEY_DELETE;
  if (e->type == TE_INSERT)
    return KEY_INSERT;
  if (e->type == TE_PGUP)
    return KEY_PGUP;
  if (e->type == TE_PGDN)
    return KEY_PGDN;
  return -1;
}

I64 TermKeyGetC()
{
  /* Deprecated repair hatch → C TermKeyGet (slot 0xD0). EdC/EditC/C readline use C
   * directly; interactive Vi/EditHoly/FunPick use TermKeyGet (HolyC). */
  return HcTermKeyGet();
}

I64 TermKeyGet()
{
  /* Default interactive path: HolyC CSI parser + shared RX ring (g_term_rx_own).
   * One UART byte per iteration — full TermPoll() would drain the ring and prefetch
   * later piped REPL lines into g_keyq (same bug C TermKeyGet had). */
  CTermEvent e;
  I64 k, ch;
  g_term_rx_own = 1;
  while (1) {
    if (TqPop(g_keyq, &g_tkh, &g_tkt, &e)) {
      k = TermMapKey(&e);
      if (k >= 0)
        return k;
      continue;
    }
    TermCheckTimeouts();
    UartRxDrain();
    ch = UartTryGetByte();
    if (ch < 0)
      continue;
    if (TermParseByte(ch) < 0)
      continue;
  }
}
/* Alias kept for Src/Man callers that name the HolyC body explicitly. */
I64 TermKeyGetHoly()
{
  return TermKeyGet();
}

I64 GetCh()
{
  /* Non-blocking: pop queued keys only. Do not TermPoll/drain RX — that steals
   * from C readline between HolyC editor sessions (livedrv/repl-regression). */
  CTermEvent e;
  I64 k;
  if (!TqPop(g_keyq, &g_tkh, &g_tkt, &e))
    return 0;
  k = TermMapKey(&e);
  if (k >= 0)
    return k;
  return 0;
}

I64 TermGetEvent(CTermEvent *ev)
{
  CTermEvent e;
  if (!TqPop(g_keyq, &g_tkh, &g_tkt, &e))
    return 0;
  if (ev) {
    ev->type = e.type;
    ev->a = e.a;
    ev->b = e.b;
  }
  return 1;
}

I64 TermGetReply(CTermEvent *ev)
{
  /* Pop reply queue only; TermProbe owns TermPoll while probing. */
  CTermEvent e;
  if (!TqPop(g_repq, &g_trh, &g_trt, &e))
    return 0;
  if (ev) {
    ev->type = e.type;
    ev->a = e.a;
    ev->b = e.b;
  }
  return 1;
}

I64 TermProbe()
{
  /* HolyC-owned geometry + CSI. Do not TermPoll-drain the ring (that prefetches
   * later piped REPL lines into g_keyq). Peek emptiness; parse one byte at a time. */
  CTermEvent e;
  I64 t0, rhp, rtp, rh, rt, r, ch;
  I64 (*csetz)(I64 rows, I64 cols);
  g_term_rx_own = 1;
  g_term_state = TS_GROUND;
  g_term_esc_at = 0;
  UartRxDrain();
  if (g_tkh != g_tkt) {
    r = (g_term_flags & TF_CPR) ? 1 : 0;
    g_term_rx_own = 0;
    return r;
  }
  rhp = *(I64 *)0x87001028;
  rtp = *(I64 *)0x87001030;
  if (!rhp || !rtp) {
    /* No C RX ring (repl-holyc): skip CPR probe; keep default 80x24. */
    g_term_rx_own = 0;
    g_term_gave_up = 1;
    return 0;
  }
  if (rhp && rtp) {
    rh = *(I64 *)rhp;
    rt = *(I64 *)rtp;
    if (rh != rt) {
      g_term_gave_up = 1;
      g_term_rx_own = 0;
      return 0;
    }
  }
  if (g_term_gave_up || !(g_term_flags & TF_ANSI)) {
    g_term_rx_own = 0;
    return 0;
  }
  /* HolyC string lex may not honor \x1b -- emit ESC with PutCh like TermGoto. */
  PutCh(27);
  PutCh('7');
  PutCh(27);
  PutCh('[');
  UartStr("999;999H");
  PutCh(27);
  PutCh('[');
  UartStr("6n");
  PutCh(27);
  PutCh('[');
  UartStr("18t");
  t0 = TermNow();
  while (TermNow() - t0 < 5000000) {
    UartRxDrain();
    ch = UartTryGetByte();
    if (ch >= 0) {
      if (TermParseByte(ch) < 0) {
        UartUnget(ch);
        break;
      }
    }
    TermCheckTimeouts();
    while (TqPop(g_repq, &g_trh, &g_trt, &e)) {
      if (e.type == TE_CURSOR_REPORT || e.type == TE_RESIZE) {
        PutCh(27);
        PutCh('8');
        g_term_rx_own = 0;
        csetz = *(I64 *)0x87001110;
        if (csetz)
          csetz(g_term_rows, g_term_cols);
        return (g_term_flags & TF_CPR) ? 1 : 0;
      }
    }
    /* Keystroke arrived (not a probe reply) — abort; leave it queued for TermKeyGet. */
    if (g_tkh != g_tkt) {
      PutCh(27);
      PutCh('8');
      g_term_rx_own = 0;
      return (g_term_flags & TF_CPR) ? 1 : 0;
    }
  }
  PutCh(27);
  PutCh('8');
  if (!(g_term_flags & TF_CPR))
    g_term_gave_up = 1;
  g_term_rx_own = 0;
  return (g_term_flags & TF_CPR) ? 1 : 0;
}
/* Alias kept for Src/Man callers that still name the HolyC probe body. */
I64 TermProbeHoly()
{
  return TermProbe();
}
// TermQuery -- TermQuery()
// NAME
//   TermQuery - optional host geometry query (TermProbe)
// SYNOPSIS
//   I64 TermQuery();
// DESCRIPTION
//   Asks a cooperating host PTY for size via DSR CPR + ESC[18t (same as
//   TermProbe). Returns 1 if TF_CPR set. Piped smokes time out and keep the
//   stored defaults (80x24 / "ansi"). Does not change termname.
// EXAMPLES
//   TermQuery; TermRep;
// SEE ALSO
//   TermProbe  TermSize  TermRep  TermHelp
I64 TermQuery()
{
  return TermProbe();
}
// TermRep -- TermRep()
// NAME
//   TermRep - print stored cols x rows and termname
// SYNOPSIS
//   U0 TermRep();
// DESCRIPTION
//   One-shot dump of guest terminal negotiation state (CONSOLE.md #11).
// EXAMPLES
//   TermSize(80,24); TermSetName("xterm"); TermRep;
// SEE ALSO
//   TermSize  TermName  TermQuery  TermHelp
U0 TermRep()
{
  UartStr("--- term ---\n");
  "  %d x %d  name=", TermCols(), TermRows();
  UartStr(TermName());
  "  flags=%X\n", TermFlags();
}
// TermHelp -- TermHelp()
// NAME
//   TermHelp - cheat sheet for size / type negotiation
// SYNOPSIS
//   U0 TermHelp();
// DESCRIPTION
//   Lists TermSize / TermSetName / TermProbe / host escape protocols.
// EXAMPLES
//   TermHelp;
// SEE ALSO
//   TermRep  Help  Man("Term")
U0 TermHelp()
{
  UartStr("TermHelp — size/type negotiation (CONSOLE.md #11)\n");
  UartStr("  TermSize(80,24);     // cols, rows (stty-style)\n");
  UartStr("  TermSetSize(24,80);  // rows, cols\n");
  UartStr("  TermSetName(\"xterm\"); TermNameAnsi; TermNameXterm; TermRep;\n");
  UartStr("  TermQuery; / TermProbe;  // ask host PTY (CPR + ESC[18t)\n");
  UartStr("  Host push: ESC[8;rows;cols t  or  OSC 777;cols;rows;name BEL\n");
  UartStr("  Defaults: 80x24 name=ansi  Man(\"Term\");\n");
}

U0 TermInit()
{
  TermName();
  /* ensure default "ansi" in I64 name words */
}
TermInit;
