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

// One `$...$` command. Returns the address just past it. `$$` is a literal '$'.
U8 *DolAnsiCmd(U8 *p)
{
  U8 name[32], arg[32];
  I64 i = 0, n, col;
  if (*p == '$') {
    // "$$" -> literal
    RVVtPut('$');
    return p + 1;
  }
  while (*p && *p != '$' && *p != ',' && i < 30)
    name[i++] = *p++;
  name[i] = 0;
  n = 0;
  if (*p == ',') {
    p++;
    while (*p && *p != '$' && n < 30)
      arg[n++] = *p++;
  }
  arg[n] = 0;
  while (*p && *p != '$')
    p++;
  if (*p == '$')
    p++;
  if (!StrCmp(name, "FG")) {
    if (n)
      DolAnsiEsc(Str2I64(arg), -1);
    else
      DolAnsiEsc(-1, -1);
    return p;
  }
  if (!StrCmp(name, "BK") || !StrCmp(name, "BG")) {
    if (n)
      DolAnsiEsc(-1, Str2I64(arg));
    else
      DolAnsiEsc(-1, -1);
    return p;
  }
  if (!StrCmp(name, "LK")) {
    // $LK,"text",A="target"$ — show the text, drop the target
    i = 0;
    while (arg[i] == '"')
      i++;
    n = i;
    while (arg[n] && arg[n] != '"')
      n++;
    arg[n] = 0;
    while (arg[i] && arg[i] != '"') {
      RVVtPut(arg[i]);
      i++;
    }
    return p;
  }
  col = RVDocColorName(name);
  if (col >= 0) {
    // bare colour name: $LTRED$ and friends
    DolAnsiEsc(col, -1);
    return p;
  }
  // $TX$, $ID$, $WW$, $$ … : layout commands with nothing to say on a terminal
  return p;
}

// RVDolAnsiPutS -- StdOut sink
// NAME
//   RVDolAnsiPutS - translate DolDoc markup to ANSI on the way out
// SEE ALSO
//   RVDolAnsiInstall  RVDocTextRender
Bool RVDolAnsiPutS(U8 *st)
{
  U8 *p;
  if (!rv_dola_on || !st)
    return FALSE;
  p = st;
  while (*p) {
    if (*p == '$') {
      p = DolAnsiCmd(p + 1);
      continue;
    }
    RVVtPut(*p);
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
  RVVtPut(ch);
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

#endif
