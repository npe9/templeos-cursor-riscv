// funs.hc -- FunPick: interactive function picker on top of Funs(). Type to filter (case-
// insensitive substring), or a lone digit 1-9 to filter by manual section (see Sections; /
// FunsS;). Arrows move, PgUp/PgDn page, Enter = Src, ^G = Man, Esc quit. FunCount/FunName/
// FunHasSrc/FunSecAt are the C enumeration under Funs(); FunWrite (C) dumps .funlist; FunEd
// opens it like DirEd. FunsS;/FunsSec(n); live in C.
I64 FpN;
I64 FpMN;
I64 FpSel;
I64 FpTop;
I64 FpSec;
// 0 = any; 1-9 = section filter from a lone digit
U8 FpFilt[64];
I64 FpMatch[512];
// FpRebuild -- FpRebuild()
// NAME
//   FpRebuild - rebuild FunPick match list from filter.
// SYNOPSIS
//   FpRebuild()
// DESCRIPTION
//   rebuild FunPick match list from filter.
// INPUTS
//   none
// OUTPUTS
//   rebuild FunPick match list from filter.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 FpRebuild()
{
  I64 i, n;
  U8 *nm;
  FpMN = 0;
  FpSec = 0;
  if (FpFilt[0] >= '1' && FpFilt[0] <= '9' && !FpFilt[1])
    FpSec = FpFilt[0] - '0';
  n = FpN;
  for (i = 0; i < n; i++) {
    nm = FunName(i);
    if (!nm)
      continue;
    if (FpSec) {
      if (FunSecAt(i) != FpSec)
        continue;
    } else if (FpFilt[0] && !StrIMatch(FpFilt, nm, 0))
      continue;
    if (FpMN < 512) {
      FpMatch[FpMN] = i;
      FpMN++;
    }
  }
  if (FpMN <= 0)
    FpSel = 0;
  else if (FpSel >= FpMN)
    FpSel = FpMN - 1;
  if (FpSel < 0)
    FpSel = 0;
}
// FpDraw -- FpDraw()
// NAME
//   FpDraw - redraw FunPick UI.
// SYNOPSIS
//   FpDraw()
// DESCRIPTION
//   redraw FunPick UI.
// INPUTS
//   none
// OUTPUTS
//   redraw FunPick UI.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 FpDraw()
{
  I64 r, tr, tc, sr, li, idx, vis;
  U8 *nm;
  tr = TermRows() - 3;
  tc = TermCols();
  sr = TermRows();
  if (tr < 1)
    tr = 1;
  vis = tr;
  if (FpSel < FpTop)
    FpTop = FpSel;
  if (FpSel >= FpTop + vis)
    FpTop = FpSel - vis + 1;
  if (FpTop < 0)
    FpTop = 0;
  TermGoto(1, 1);
  TermClearEol();
  UartStr("FunPick  filter: ");
  UartStr(FpFilt);
  PutCh('_');
  if (FpSec)
    "  sec %d (%d/%d)", FpSec, FpMN, FpN;
  else
    "  (%d/%d)", FpMN, FpN;
  for (r = 0; r < tr; r++) {
    TermGoto(r + 2, 1);
    TermClearEol();
    li = FpTop + r;
    if (li >= FpMN)
      continue;
    idx = FpMatch[li];
    nm = FunName(idx);
    if (!nm)
      continue;
    if (li == FpSel) {
      PutCh(27);
      PutCh('[');
      PutCh('7');
      PutCh('m');
    }
    PutCh(' ');
    UartStr(nm);
    "  %d", FunSecAt(idx);
    if (FunHasSrc(idx))
      UartStr("  [src]");
    if (li == FpSel) {
      PutCh(27);
      PutCh('[');
      PutCh('0');
      PutCh('m');
    }
  }
  TermGoto(sr - 1, 1);
  TermClearEol();
  UartStr(" Enter=Src  ^G=Man  Esc=quit  type/digit=section");
  TermGoto(1, 17);
  r = 0;
  while (FpFilt[r])
    r++;
  TermGoto(1, 17 + r);
}
// FpOpen -- FpOpen()
// NAME
//   FpOpen - Src the FunPick selection.
// SYNOPSIS
//   FpOpen()
// DESCRIPTION
//   Src the FunPick selection.
// INPUTS
//   none
// OUTPUTS
//   Src the FunPick selection.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 FpOpen()
{
  U8 *nm;
  if (FpMN <= 0 || FpSel < 0 || FpSel >= FpMN)
    return;
  nm = FunName(FpMatch[FpSel]);
  if (!nm)
    return;
  TermClear();
  Src(nm);
}
// FpMan -- FpMan()
// NAME
//   FpMan - Man the FunPick selection.
// SYNOPSIS
//   FpMan()
// DESCRIPTION
//   Man the FunPick selection.
// INPUTS
//   none
// OUTPUTS
//   Man the FunPick selection.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 FpMan()
{
  U8 *nm;
  if (FpMN <= 0 || FpSel < 0 || FpSel >= FpMN)
    return;
  nm = FunName(FpMatch[FpSel]);
  if (!nm)
    return;
  TermClear();
  Man(nm);
  UartStr("-- press a key --");
  TermKeyGet();
}
// FunPick -- FunPick()
// NAME
//   FunPick - interactive picker over Funs(). Type to filter, digit=section, Enter=Src.
// SYNOPSIS
//   FunPick()
// DESCRIPTION
//   interactive picker over Funs(). Type to filter, digit=section, Enter=Src.
// INPUTS
//   none
// OUTPUTS
//   interactive picker over Funs(). Type to filter, digit=section, Enter=Src.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 FunPick()
{
  I64 k, fl, vis;
  TermProbe();
  FpN = FunCount();
  FpFilt[0] = 0;
  FpSel = 0;
  FpTop = 0;
  FpRebuild();
  TermClear();
  while (1) {
    FpDraw();
    k = TermKeyGet();
    vis = TermRows() - 3;
    if (vis < 1)
      vis = 1;
    if (k == 27)
      break;
    else if (k == '\r' || k == '\n') {
      if (FpMN > 0) {
        FpOpen();
        break;
      }
    } else if (k == 7)
      FpMan();
    // ^G = Man
    else if(k == KEY_UP)
    {
      if (FpSel > 0)
        FpSel--;
    }
    else if(k == KEY_DOWN)
    {
      if (FpSel + 1 < FpMN)
        FpSel++;
    }
    else if(k == KEY_PGUP)
    {
      FpSel = FpSel - vis;
      if (FpSel < 0)
        FpSel = 0;
    }
    else if(k == KEY_PGDN)
    {
      FpSel = FpSel + vis;
      if (FpSel >= FpMN && FpMN > 0)
        FpSel = FpMN - 1;
    }
    else if(k == KEY_HOME)FpSel = 0;
    else if(k == KEY_END)
    {
      if (FpMN > 0)
        FpSel = FpMN - 1;
    }
    else if(k == 127 || k == 8)
    {
      fl = 0;
      while (FpFilt[fl])
        fl++;
      if (fl > 0) {
        FpFilt[fl - 1] = 0;
        FpRebuild();
        FpSel = 0;
        FpTop = 0;
      }
    }
    else if(k >= 32 && k < 127)
    {
      fl = 0;
      while (FpFilt[fl])
        fl++;
      if (fl < 63) {
        FpFilt[fl] = k;
        FpFilt[fl + 1] = 0;
        FpRebuild();
        FpSel = 0;
        FpTop = 0;
      }
    }
  }
  g_term_rx_own = 0;
  /* release ring to C readline */
  TermClear();
}
// FunEd -- FunEd()
// NAME
//   FunEd - FunWrite() then open .funlist in the preferred editor.
// SYNOPSIS
//   FunEd()
// DESCRIPTION
//   FunWrite() then open .funlist in the preferred editor.
// INPUTS
//   none
// OUTPUTS
//   FunWrite() then open .funlist in the preferred editor.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 FunEd()
{
  FunWrite();
  editor(".funlist");
}
