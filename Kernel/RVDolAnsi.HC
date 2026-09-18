// RVDolAnsi.HC — interpret DolDoc markup on its way to the terminal.
//
// TempleOS writes markup into strings and lets DolDoc render it. Printed straight at a UART it
// arrives as source, which is what the REPL's errors look like today:
//
//   $LTRED$$BK,1$ERROR:$FG$$BK,0$ Missing expression at
//   "s" $LK,",0001",A="FL:A:/,1"$
//
// This sits in the StdOut chain and translates instead: colour commands become SGR, links print
// their visible text, and anything it does not understand is dropped rather than shown. A
// document being RENDERED (Kernel/RVDocText.HC) never comes through here — DocRecalc consumed
// those commands long before. This is for text that was never a document.
//
// Chain order matters: PutS stops at the first sink returning TRUE, and KeyDevAdd runs LOWEST
// priority first. The debugger's capture sink sits at 1 and passes through when disarmed, this
// sits at 2 and consumes, and the console (CONFIG_UART_BASE) never runs while it is installed.
#ifndef RV_DOL_ANSI_HC
#define RV_DOL_ANSI_HC
#help_index "DolDoc/VT"

#define DOLA_PRI 2

I64 rv_dola_on, rv_dola_fg = WHITE, rv_dola_bg = BLACK;
// The text column, and where in it we are. A terminal wraps at ITS width, which would run text
// under a sidebar painted beside it; wrapping here keeps printed output in its own column.
I64 rv_dola_wrap, rv_dola_x;

// RVDolAnsiWrap -- RVDolAnsiWrap(cols)
// NAME
//   RVDolAnsiWrap - how wide the text column is (0 = the whole terminal)
// SEE ALSO
//   RVDolAnsiInstall  RVLineEdWrap  AsmUiLayout
public U0 RVDolAnsiWrap(I64 cols)
{
  rv_dola_wrap = cols;
  rv_dola_x = 0;
}

// RVDolAnsiCol -- RVDolAnsiCol(x)
// NAME
//   RVDolAnsiCol - tell the translator which column the cursor is in
// DESCRIPTION
//   Anything that writes to the wire without going through this sink — the line editor's echo —
//   leaves the column count stale, and the next printed line then breaks in the wrong place.
// SEE ALSO
//   RVDolAnsiWrap  RVLineEd
public U0 RVDolAnsiCol(I64 x)
{
  rv_dola_x = x;
}

// One character on the wire, counting the column and breaking the line when it is full.
U0 DolAnsiEmit(I64 ch)
{
  if (ch == '\n' || ch == '\r') {
    RVVtPut(ch);
    if (ch == '\n')
      RVVtPut('\r');
    // an explicit CR with every LF: the cursor has to come back to the column, and a terminal in
    // LF mode would leave it where it was
    rv_dola_x = 0;
    return;
  }
  if (rv_dola_wrap && rv_dola_x >= rv_dola_wrap) {
    RVVtPut('\n');
    RVVtPut('\r');
    rv_dola_x = 0;
  }
  if (ch == 9) {
    RVVtPut(ch);
    rv_dola_x = (rv_dola_x + 8) & (-8);
    return;
  }
  RVVtPut(ch);
  rv_dola_x++;
}

// Hypertext, kept rather than discarded. A DolDoc link is text plus a target; a terminal has no
// click, so each link is numbered as it goes by and the number is what you type to follow it.
// This is the same idea as a text browser's link numbering, and it keeps the one thing that
// matters about DolDoc — that a message is a place you can go, not just words.
#define DOLA_LINK_MAX 16
#define DOLA_LINK_TEXT 48
#define DOLA_LINK_TGT 96
U8 rv_dola_ltext[DOLA_LINK_MAX * DOLA_LINK_TEXT];
U8 rv_dola_ltgt[DOLA_LINK_MAX * DOLA_LINK_TGT];
I64 rv_dola_link_n;

U0 DolAnsiUnderline(I64 on)
{
  RVVtCsi;
  if (!on)
    RVVtPut('2');
  RVVtPut('4');
  RVVtPut('m');
}

// Escapes go through RVDocVT's emitters, not a formatted string: HolyC does not read "\x1b" as
// an escape, so StrPrint put the literal text "x1b[91m" on the wire. RVVtSgr/RVVtPut write real
// bytes (and keep the byte accounting in rv_vt_cost).
U0 DolAnsiEsc(I64 fg, I64 bg)
{
  if (fg >= 0)
    rv_dola_fg = fg & 15;
  if (bg >= 0)
    rv_dola_bg = bg & 15;
  if (fg < 0 && bg < 0) {
    rv_dola_fg = WHITE;
    rv_dola_bg = BLACK;
  }
  RVVtSgr(rv_dola_fg, rv_dola_bg, 0);
}

// One buffered `$...$` command. The text arrives through PutS in arbitrary pieces, so a command
// can START in one call and END in the next — parsing per call printed the tail of a split
// command as literal text, which is where a stray ",1" came from after an error message. So the
// command is accumulated across calls and executed when its closing `$` shows up.
U0 DolAnsiRun(U8 *cmd)
{
  U8 name[32], arg[160];
  I64 i = 0, n = 0, col;
  if (!*cmd) {
    // "$$": an escaped literal dollar
    RVVtPut('$');
    return;
  }
  while (cmd[i] && cmd[i] != ',' && i < 30) {
    name[i] = cmd[i];
    i++;
  }
  name[i] = 0;
  if (cmd[i] == ',') {
    i++;
    while (cmd[i] && n < 158)
      arg[n++] = cmd[i++];
  }
  arg[n] = 0;
  if (!StrCmp(name, "FG")) {
    if (n)
      DolAnsiEsc(Str2I64(arg), -1);
    else
      DolAnsiEsc(-1, -1);
    return;
  }
  if (!StrCmp(name, "BK") || !StrCmp(name, "BG")) {
    if (n)
      DolAnsiEsc(-1, Str2I64(arg));
    else
      DolAnsiEsc(-1, -1);
    return;
  }
  if (!StrCmp(name, "LK")) {
    // $LK,"text",A="target"$ or $LK,"target"$. Show the text underlined and tag it with the
    // number you type to follow it.
    U8 text[DOLA_LINK_TEXT], tgt[DOLA_LINK_TGT], num[16];
    U8 *q;
    I64 k = 0;
    q = arg;
    while (*q == '"')
      q++;
    while (*q && *q != '"' && k < DOLA_LINK_TEXT - 1)
      text[k++] = *q++;
    text[k] = 0;
    tgt[0] = 0;
    q = StrFind("A=", arg);
    if (q) {
      q += 2;
      while (*q == '"')
        q++;
      k = 0;
      while (*q && *q != '"' && k < DOLA_LINK_TGT - 1)
        tgt[k++] = *q++;
      tgt[k] = 0;
    } else {
      StrCpy(tgt, text);
    }
    if (rv_dola_link_n < DOLA_LINK_MAX) {
      StrCpy(rv_dola_ltext + rv_dola_link_n * DOLA_LINK_TEXT, text);
      StrCpy(rv_dola_ltgt + rv_dola_link_n * DOLA_LINK_TGT, tgt);
      rv_dola_link_n++;
    }
    DolAnsiEsc(LTCYAN, -1);
    DolAnsiUnderline(1);
    q = text;
    if (!*q)
      q = tgt;
    while (*q) {
      DolAnsiEmit(*q);
      q++;
    }
    DolAnsiUnderline(0);
    DolAnsiEsc(DKGRAY, -1);
    StrPrint(num, "[%d]", rv_dola_link_n);
    q = num;
    while (*q) {
      DolAnsiEmit(*q);
      q++;
    }
    DolAnsiEsc(rv_dola_fg, -1);
    return;
  }
  col = RVDocColorName(name);
  if (col >= 0) {
    // a bare colour name: $LTRED$ and friends
    DolAnsiEsc(col, -1);
    return;
  }
  // $TX$, $ID$, $WW$, $HL$ …: layout with nothing to say on a terminal
}

// RVDolAnsiPutS -- StdOut sink
// NAME
//   RVDolAnsiPutS - translate DolDoc markup to ANSI on the way out
// SEE ALSO
//   RVDolAnsiInstall  RVDocTextRender
U8 rv_dola_cmd[192];
I64 rv_dola_in_cmd, rv_dola_cmd_n;

Bool RVDolAnsiPutS(U8 *st)
{
  U8 *p;
  if (!rv_dola_on || !st)
    return FALSE;
  p = st;
  while (*p) {
    if (rv_dola_in_cmd) {
      if (*p == '$') {
        rv_dola_cmd[rv_dola_cmd_n] = 0;
        DolAnsiRun(rv_dola_cmd);
        rv_dola_in_cmd = 0;
        rv_dola_cmd_n = 0;
      } else if (rv_dola_cmd_n < 190) {
        rv_dola_cmd[rv_dola_cmd_n++] = *p;
      }
      p++;
      continue;
    }
    if (*p == '$') {
      rv_dola_in_cmd = 1;
      rv_dola_cmd_n = 0;
      p++;
      continue;
    }
    if (*p == '\n' || *p == '\r' || *p == 9)
      DolAnsiEmit(*p);
    else if (*p >= ' ' && *p < 127)
      DolAnsiEmit(*p);
    else if (*p >= 2 && *p <= 13)
      RVVtPutGlyph(*p);
    // Anything else — a stray control byte or a high-bit byte from the font — is DROPPED, not
    // turned into a space: it is what printed as "1??" runs before the ERROR: line, and a space
    // per byte just moves the mess along the line.
    // Glyph-map everything else: TempleOS text carries font codes 0x02..0x0D and high-bit
    // bytes, and putting those on the wire raw is the "03?" noise around error lines. But
    // newline and tab live INSIDE that range (0x0A, 0x09) and are real control characters
    // here — mapping them turned every line break into a "+".
    p++;
  }
  RVVtFlush;
  return TRUE;
}

Bool RVDolAnsiPutKey(I64 ch, I64 sc)
{
  no_warn sc;
  if (!rv_dola_on)
    return FALSE;
  if (ch == '\n' || ch == '\r' || ch == 9)
    RVVtPut(ch);
  else
    RVVtPutGlyph(ch);
  RVVtFlush;
  return TRUE;
}

// RVDolAnsiInstall -- RVDolAnsiInstall()
// NAME
//   RVDolAnsiInstall - route printed output through the markup translator
// SYNOPSIS
//   RVDolAnsiInstall;
// DESCRIPTION
//   After this, text printed with DolDoc markup shows as coloured terminal output instead of
//   `$LTRED$$BK,1$ERROR:$FG$`. Off by default so nothing changes for images that do not ask.
// SEE ALSO
//   RVDolAnsiPutS
public U0 RVDolAnsiInstall()
{
  rv_dola_on = 1;
  KeyDevAdd(&RVDolAnsiPutKey, &RVDolAnsiPutS, DOLA_PRI, FALSE);
}

// Links -- Links()
// NAME
//   Links - list the hypertext links seen so far
// SYNOPSIS
//   Links;
// SEE ALSO
//   Lk  RVDolAnsiInstall
public U0 Links()
{
  I64 i = 0;
  if (!rv_dola_link_n) {
    "no links yet\n";
    return;
  }
  while (i < rv_dola_link_n) {
    "  [%d] %s  ->  %s\n", i + 1, rv_dola_ltext + i * DOLA_LINK_TEXT,
        rv_dola_ltgt + i * DOLA_LINK_TGT;
    i++;
  }
}

// Lk -- Lk(n)
// NAME
//   Lk - follow link n (the number printed beside it)
// SYNOPSIS
//   Lk(1);
// DESCRIPTION
//   TempleOS link targets say where to go: "FL:file,line" is a place in a file, "MN:Name" a
//   manual entry. There is nothing to click on a terminal, so the number beside a link is the
//   handle — Lk(n) resolves it the way clicking would.
// SEE ALSO
//   Links  Man  Ed
public U0 Lk(I64 n)
{
  U8 *tgt;
  if (n < 1 || n > rv_dola_link_n) {
    "no link %d (Links; lists them)\n", n;
    return;
  }
  tgt = rv_dola_ltgt + (n - 1) * DOLA_LINK_TGT;
  "-> %s\n", tgt;
  if (!MemCmp(tgt, "MN:", 3)) {
    Man(tgt + 3);
    return;
  }
  if (!MemCmp(tgt, "FL:", 3)) {
    // "FL:file,line" — the file is the part before the comma
    U8 file[DOLA_LINK_TGT], *p;
    I64 i = 0;
    p = tgt + 3;
    while (*p && *p != ',' && i < DOLA_LINK_TGT - 1)
      file[i++] = *p++;
    file[i] = 0;
    "   file %s%s\n", file, *p ? p : "";
    return;
  }
  "   (no handler for this target kind yet)\n";
}

// Lk0 -- Lk0()
// NAME
//   Lk0 - forget the collected links
// SEE ALSO
//   Links  Lk
public U0 Lk0()
{
  rv_dola_link_n = 0;
}

#endif
