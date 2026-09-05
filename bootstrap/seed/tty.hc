// tty.hc -- HolyC UART line discipline (CONSOLE.md #1).
// Canonical vs raw, echo, erase/kill/werase, CR→NL, optional ONLCR, ^D EOF flag.
// Builds on uart soft ring; readline/ReplReadLine call the hooks.
// XON/XOFF stay in uart drain (not here). RTS/CTS not owned here.
// Include after uart.hc (PutCh / UartStr / HcUartGet). Prefer before readline.hc.
#define TTY_RAW 0
#define TTY_CANON 1
#define TTY_CH_ERASE 8
#define TTY_CH_DEL 127
#define TTY_CH_KILL 0x15
#define TTY_CH_WERASE 0x17
#define TTY_CH_EOF 0x04
#define TTY_CH_CR 13
#define TTY_CH_NL 10
I64 g_tty_mode;
I64 g_tty_echo;
I64 g_tty_icrnl;
I64 g_tty_onlcr;
I64 g_tty_erase;
I64 g_tty_kill;
I64 g_tty_werase;
I64 g_tty_eof;
I64 g_tty_eof_hit;
I64 g_tty_inited;
// TtyInit -- TtyInit()
// NAME
//   TtyInit - reset line-discipline defaults (canonical + echo + ICRNL)
// SYNOPSIS
//   U0 TtyInit();
// DESCRIPTION
//   Canon mode, echo on, CR→NL on input, ONLCR off (opt-in), erase=BS (DEL
//   also), kill=^U, werase=^W, eof=^D. Clears eof-hit. Does not touch
//   UartXonXoff / UartRtsCts.
// EXAMPLES
//   TtyInit;
// SEE ALSO
//   TtyCanon  TtyRaw  Tty  UartXonXoff
U0 TtyInit()
{
  g_tty_mode = TTY_CANON;
  g_tty_echo = 1;
  g_tty_icrnl = 1;
  g_tty_onlcr = 0;
  g_tty_erase = TTY_CH_ERASE;
  g_tty_kill = TTY_CH_KILL;
  g_tty_werase = TTY_CH_WERASE;
  g_tty_eof = TTY_CH_EOF;
  g_tty_eof_hit = 0;
  g_tty_inited = 1;
}

U0 TtyEnsure()
{
  if (!g_tty_inited)
    TtyInit;
}
// TtyCanon -- TtyCanon()
U0 TtyCanon()
{
  TtyEnsure;
  g_tty_mode = TTY_CANON;
}
// TtyRaw -- TtyRaw()
// DESCRIPTION
//   Byte-oriented; erase/kill/eof classifiers off. Echo/ICRNL/ONLCR stay as set.
U0 TtyRaw()
{
  TtyEnsure;
  g_tty_mode = TTY_RAW;
}

I64 TtyModeGet()
{
  TtyEnsure;
  return g_tty_mode;
}

I64 TtyIsCanon()
{
  TtyEnsure;
  return g_tty_mode == TTY_CANON;
}

I64 TtyIsRaw()
{
  TtyEnsure;
  return g_tty_mode == TTY_RAW;
}

U0 TtyEcho(I64 on)
{
  TtyEnsure;
  g_tty_echo = on != 0;
}

I64 TtyEchoGet()
{
  TtyEnsure;
  return g_tty_echo;
}

U0 TtyIcrnl(I64 on)
{
  TtyEnsure;
  g_tty_icrnl = on != 0;
}

I64 TtyIcrnlGet()
{
  TtyEnsure;
  return g_tty_icrnl;
}
// TtyOnlcr -- TtyOnlcr(1)
// NAME
//   TtyOnlcr - map NL → CR+LF on TtyOutCh / TtyOutNl (opt-in; default off)
// DESCRIPTION
//   Does not wrap global PutCh (binary DumpFile / framed mux stay raw).
//   REPL line-end uses TtyOutNl when enabled.
U0 TtyOnlcr(I64 on)
{
  TtyEnsure;
  g_tty_onlcr = on != 0;
}

I64 TtyOnlcrGet()
{
  TtyEnsure;
  return g_tty_onlcr;
}

U0 TtyEraseSet(I64 ch)
{
  TtyEnsure;
  g_tty_erase = ch & 0xFF;
}

I64 TtyEraseGet()
{
  TtyEnsure;
  return g_tty_erase;
}

U0 TtyKillSet(I64 ch)
{
  TtyEnsure;
  g_tty_kill = ch & 0xFF;
}

I64 TtyKillGet()
{
  TtyEnsure;
  return g_tty_kill;
}

U0 TtyWeraseSet(I64 ch)
{
  TtyEnsure;
  g_tty_werase = ch & 0xFF;
}

I64 TtyWeraseGet()
{
  TtyEnsure;
  return g_tty_werase;
}

U0 TtyEofSet(I64 ch)
{
  TtyEnsure;
  g_tty_eof = ch & 0xFF;
}

I64 TtyEofGet()
{
  TtyEnsure;
  return g_tty_eof;
}
// TtyEofHit -- sticky flag: empty-line ^D requested session EOF
I64 TtyEofHit()
{
  TtyEnsure;
  return g_tty_eof_hit;
}

U0 TtyEofClear()
{
  TtyEnsure;
  g_tty_eof_hit = 0;
}

U0 TtyEofRaise()
{
  TtyEnsure;
  g_tty_eof_hit = 1;
}

I64 TtyMapIn(I64 ch)
{
  TtyEnsure;
  if (g_tty_icrnl && ch == TTY_CH_CR)
    return TTY_CH_NL;
  return ch;
}

I64 TtyInCh()
{
  return TtyMapIn(HcUartGet());
}
// TtyOutCh -- printable/out byte; NL→CRLF when ONLCR (opt-in)
U0 TtyOutCh(I64 ch)
{
  TtyEnsure;
  if (g_tty_onlcr && ch == TTY_CH_NL) {
    PutCh(TTY_CH_CR);
    PutCh(TTY_CH_NL);
    return;
  }
  PutCh(ch);
}

U0 TtyOutNl()
{
  TtyOutCh(TTY_CH_NL);
}

I64 TtyIsErase(I64 ch)
{
  TtyEnsure;
  if (g_tty_mode != TTY_CANON)
    return 0;
  if (ch == g_tty_erase || ch == TTY_CH_DEL)
    return 1;
  return 0;
}

I64 TtyIsKill(I64 ch)
{
  TtyEnsure;
  if (g_tty_mode != TTY_CANON)
    return 0;
  if (ch == g_tty_kill)
    return 1;
  return 0;
}

I64 TtyIsWerase(I64 ch)
{
  TtyEnsure;
  if (g_tty_mode != TTY_CANON)
    return 0;
  if (ch == g_tty_werase)
    return 1;
  return 0;
}

I64 TtyIsEof(I64 ch)
{
  TtyEnsure;
  if (g_tty_mode != TTY_CANON)
    return 0;
  if (ch == g_tty_eof)
    return 1;
  return 0;
}

U0 TtyEchoErase()
{
  if (!g_tty_echo)
    return;
  // BS-space-BS (TTY_CH_ERASE=8).
  PutCh(TTY_CH_ERASE);
  PutCh(' ');
  PutCh(TTY_CH_ERASE);
}

U0 TtyEchoKill(I64 n)
{
  I64 i;
  if (!g_tty_echo || n <= 0)
    return;
  i = 0;
  while (i < n) {
    PutCh(TTY_CH_ERASE);
    PutCh(' ');
    PutCh(TTY_CH_ERASE);
    i++;
  }
}

U0 TtyEchoCh(I64 ch)
{
  if (!g_tty_echo)
    return;
  if (ch >= 32 && ch < 127)
    PutCh(ch);
}

I64 TtyWeraseLen(U8 *buf, I64 n)
{
  I64 i;
  if (!buf || n <= 0)
    return 0;
  i = n;
  while (i > 0 && (buf[i - 1] == ' ' || buf[i - 1] == '\t'))
    i--;
  while (i > 0 && buf[i - 1] != ' ' && buf[i - 1] != '\t')
    i--;
  return n - i;
}

U0 Tty()
{
  TtyEnsure;
  UartStr("=== tty (line discipline) ===\n");
  if (g_tty_mode == TTY_CANON)
    UartStr("  mode=canon\n");
  else
    UartStr("  mode=raw\n");
  "  echo=%d  icrnl=%d  onlcr=%d  eof_hit=%d\n", g_tty_echo, g_tty_icrnl, g_tty_onlcr, g_tty_eof_hit;
  "  erase=0x%X  kill=0x%X  werase=0x%X  eof=0x%X\n", g_tty_erase, g_tty_kill, g_tty_werase, g_tty_eof;
  UartStr("  flow: UartXonXoff (uart.hc) — not owned here\n");
  UartStr("=== tty end ===\n");
}

U0 TtyHelp()
{
  UartStr("TtyHelp — UART line discipline (CONSOLE.md #1)\n");
  UartStr("  Tty; TtyCanon; TtyRaw;  TtyEcho(1|0); TtyIcrnl(1|0); TtyOnlcr(1|0);\n");
  UartStr("  erase BS/DEL  kill ^U  werase ^W  empty ^D=session eof (TtyEofHit)\n");
  UartStr("  arrows/Home/End mid-line (ReplReadLine); Tab/history in readline.hc\n");
  UartStr("  TtyMapIn / TtyInCh / TtyOutNl — hooks; XON: UartXonXoff;\n");
}
TtyInit;
