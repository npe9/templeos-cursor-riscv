// funs.hc -- Funs / FunPick: interactive function picker organized by topic
// (Sections;). No-arg Funs;/FunPick; is interactive: type to filter (case-
// insensitive substring); a lone digit 1-9 shows one section. Tab jumps to the
// next topic (or cycles a lone-digit section filter). Arrows skip headers;
// PgUp/PgDn page; Enter = Src; ^G = Man; Esc quit.
// Funs("Print") / FunPick("Print") = filter-only dump (no Esc wait).
// FunCount/FunName/FunHasSrc/FunSecAt under FunsList(); FunWrite dumps .funlist;
// FunEd opens it like DirEd. FunsS;/FunsSec(n); live in sym.hc.
I64 FpN;
I64 FpMN;
I64 FpSel;
I64 FpTop;
I64 FpSec;
// 0 = any; 1-9 = section filter from a lone digit
U8 FpFilt[64];
// FpMatch[i] >= 0 → FunCount index; < 0 → header for section (-value)
I64 FpMatch[640];
#define FP_MATCH_MAX 640
// FpFiltSet -- FpFiltSet(filt)
// NAME
//   FpFiltSet - copy an optional initial filter into FpFilt
// SYNOPSIS
//   U0 FpFiltSet(U8 *filt);
// DESCRIPTION
//   Clears FpFilt, then copies up to 63 chars from filt when non-nil.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 FpFiltSet(U8 *filt)
{
  I64 i;
  FpFilt[0] = 0;
  if (!filt)
    return;
  i = 0;
  while (filt[i] && i < 63) {
    FpFilt[i] = filt[i];
    i++;
  }
  FpFilt[i] = 0;
}
// FpAdd -- FpAdd(v)
// NAME
//   FpAdd - append one FunPick row (fun index or -section header)
U0 FpAdd(I64 v)
{
  if (FpMN < FP_MATCH_MAX) {
    FpMatch[FpMN] = v;
    FpMN++;
  }
}
// FpIsHdr -- FpIsHdr(li)
// NAME
//   FpIsHdr - nonzero if match row li is a topic header
I64 FpIsHdr(I64 li)
{
  if (li < 0 || li >= FpMN)
    return 0;
  if (FpMatch[li] < 0)
    return 1;
  return 0;
}
// FpSelFix -- FpSelFix()
// NAME
//   FpSelFix - clamp selection onto a function row (skip headers)
U0 FpSelFix()
{
  I64 i;
  if (FpMN <= 0) {
    FpSel = 0;
    return;
  }
  if (FpSel < 0)
    FpSel = 0;
  if (FpSel >= FpMN)
    FpSel = FpMN - 1;
  if (!FpIsHdr(FpSel))
    return;
  i = FpSel + 1;
  while (i < FpMN && FpIsHdr(i))
    i++;
  if (i < FpMN) {
    FpSel = i;
    return;
  }
  i = FpSel - 1;
  while (i >= 0 && FpIsHdr(i))
    i--;
  if (i >= 0)
    FpSel = i;
}
// FpRebuild -- FpRebuild()
// NAME
//   FpRebuild - rebuild FunPick list grouped by topic
// SYNOPSIS
//   FpRebuild()
// DESCRIPTION
//   Builds FpMatch in Sections; order with a header row per topic that has
//   matches. Lone digit filter → one topic; text filter → name substring across
//   topics (still grouped).
// SEE ALSO
//   Sections  FunSecAt  FunPick
U0 FpRebuild()
{
  I64 i, n, s, want, pass, any;
  I64 order[6];
  U8 *nm;
  order[0] = 1;
  order[1] = 2;
  order[2] = 3;
  order[3] = 4;
  order[4] = 5;
  order[5] = 9;
  FpMN = 0;
  FpSec = 0;
  if (FpFilt[0] >= '1' && FpFilt[0] <= '9' && !FpFilt[1])
    FpSec = FpFilt[0] - '0';
  n = FpN;
  for (pass = 0; pass < 6; pass++) {
    want = order[pass];
    if (FpSec && want != FpSec)
      continue;
    any = 0;
    for (i = 0; i < n; i++) {
      nm = FunName(i);
      if (!nm)
        continue;
      s = FunSecAt(i);
      if (s != want)
        continue;
      if (!FpSec && FpFilt[0] && !StrIMatch(FpFilt, nm, 0))
        continue;
      if (!any) {
        FpAdd(-want);
        any = 1;
      }
      FpAdd(i);
    }
  }
  FpSelFix();
}
// FpSecApply -- FpSecApply(sec)
// NAME
//   FpSecApply - set FunPick to one topic (0=all topics)
// SYNOPSIS
//   U0 FpSecApply(I64 sec);
// SEE ALSO
//   Sections  FunSecName  FunPick
U0 FpSecApply(I64 sec)
{
  if (sec <= 0 || sec > 9) {
    FpFilt[0] = 0;
  } else {
    FpFilt[0] = '0' + sec;
    FpFilt[1] = 0;
  }
  FpRebuild();
  FpSel = 0;
  FpTop = 0;
  FpSelFix();
}
// FpJumpNextTopic -- FpJumpNextTopic()
// NAME
//   FpJumpNextTopic - Tab: next topic group or next section filter
// SYNOPSIS
//   U0 FpJumpNextTopic();
// DESCRIPTION
//   With a lone-digit filter, cycles sections (1→2→…→9→all→1). Otherwise jumps
//   the highlight to the first function under the next topic header (wraps).
// SEE ALSO
//   Sections  FpSecApply  FunPick
U0 FpJumpNextTopic()
{
  I64 i, cur, s;
  if (FpSec) {
    s = FpSec;
    if (s < 5)
      FpSecApply(s + 1);
    else if (s == 5)
      FpSecApply(9);
    else
      FpSecApply(0);
    return;
  }
  cur = 0;
  if (FpSel >= 0 && FpSel < FpMN) {
    if (FpIsHdr(FpSel))
      cur = -FpMatch[FpSel];
    else
      cur = FunSecAt(FpMatch[FpSel]);
  }
  for (i = 0; i < FpMN; i++) {
    if (FpIsHdr(i) && -FpMatch[i] > cur) {
      if (i + 1 < FpMN && !FpIsHdr(i + 1))
        FpSel = i + 1;
      else
        FpSel = i;
      return;
    }
  }
  for (i = 0; i < FpMN; i++) {
    if (FpIsHdr(i)) {
      if (i + 1 < FpMN && !FpIsHdr(i + 1))
        FpSel = i + 1;
      else
        FpSel = i;
      return;
    }
  }
}
// FpSelUp -- FpSelUp()
// NAME
//   FpSelUp - move highlight up, skipping topic headers
U0 FpSelUp()
{
  I64 i;
  i = FpSel - 1;
  while (i >= 0) {
    if (!FpIsHdr(i)) {
      FpSel = i;
      return;
    }
    i--;
  }
}
// FpSelDown -- FpSelDown()
// NAME
//   FpSelDown - move highlight down, skipping topic headers
U0 FpSelDown()
{
  I64 i;
  i = FpSel + 1;
  while (i < FpMN) {
    if (!FpIsHdr(i)) {
      FpSel = i;
      return;
    }
    i++;
  }
}
// FpDraw -- FpDraw()
// NAME
//   FpDraw - redraw Funs / FunPick UI (topics + functions)
// SYNOPSIS
//   FpDraw()
// DESCRIPTION
//   Header line + topic groups. Topic rows are dim separators; functions show
//   [src] when editable.
// BUGS
//   See source; RISC-V UART REPL may omit full TempleOS behavior.
U0 FpDraw()
{
  I64 r, tr, tc, sr, li, idx, vis, sec;
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
  UartStr("Funs  filter: ");
  UartStr(FpFilt);
  PutCh('_');
  if (FpSec) {
    "  topic %d ", FpSec;
    UartStr(FunSecName(FpSec));
    "  (%d/%d)", FpMN, FpN;
  } else
    "  by topic  (%d/%d)", FpMN, FpN;
  for (r = 0; r < tr; r++) {
    TermGoto(r + 2, 1);
    TermClearEol();
    li = FpTop + r;
    if (li >= FpMN)
      continue;
    if (FpIsHdr(li)) {
      sec = -FpMatch[li];
      UartStr("--- ");
      "%d ", sec;
      UartStr(FunSecName(sec));
      UartStr(" ---");
      continue;
    }
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
  UartStr(" Enter=Src  ^G=Man  Esc=quit  Tab=topic  type=filter");
  TermGoto(1, 14);
  r = 0;
  while (FpFilt[r])
    r++;
  TermGoto(1, 14 + r);
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
  if (FpIsHdr(FpSel))
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
  if (FpIsHdr(FpSel))
    return;
  nm = FunName(FpMatch[FpSel]);
  if (!nm)
    return;
  TermClear();
  Man(nm);
  UartStr("-- press a key --");
  TermKeyGet();
}
// FunPick -- FunPick(filt=0)
// NAME
//   FunPick - topic-organized picker; type to filter, Tab=topic, Enter=Src
// SYNOPSIS
//   FunPick();  FunPick("Print");
// DESCRIPTION
//   No-arg: full-screen UART picker of HTT_FUN symbols grouped under Sections;
//   topics. Typing narrows within those groups. Tab jumps to the next topic
//   (or cycles a lone-digit section). Arrows skip headers. Enter opens Src;
//   ^G = Man; Esc quits.
//   Non-empty filt: filter-only dump (like repl-holyc FunsList path) — prints
//   matching names and returns; no Esc / TermKeyGet wait (smoke-safe).
// EXAMPLES
//   FunPick;
//   FunPick("Dir");
// SEE ALSO
//   Funs  FunsList  Src  Man  FunsS  Sections
// BUGS
//   No mouse / DolDoc links yet — Enter is the dig-down (TempleOS Activate-style).
U0 FunPick(U8 *filt = 0)
{
  I64 k, fl, vis, i, n;
  U8 *nm;
  /* Filter-only dump when arg provided — no interactive Esc wait. */
  if (filt && *filt) {
    n = FunCount();
    UartStr("Funs  filter: ");
    UartStr(filt);
    PutCh('\n');
    for (i = 0; i < n; i++) {
      nm = FunName(i);
      if (!nm)
        continue;
      if (!StrIMatch(filt, nm, 0))
        continue;
      UartStr("  ");
      UartStr(nm);
      if (FunHasSrc(i))
        UartStr("  [src]");
      PutCh('\n');
    }
    return;
  }
  TermProbe();
  FpN = FunCount();
  FpFiltSet(filt);
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
    else if(k == 9 || k == '\t')FpJumpNextTopic();
    else if(k == KEY_UP)FpSelUp();
    else if(k == KEY_DOWN)FpSelDown();
    else if(k == KEY_PGUP)
    {
      FpSel = FpSel - vis;
      if (FpSel < 0)
        FpSel = 0;
      FpSelFix();
    }
    else if(k == KEY_PGDN)
    {
      FpSel = FpSel + vis;
      if (FpSel >= FpMN && FpMN > 0)
        FpSel = FpMN - 1;
      FpSelFix();
    }
    else if(k == KEY_HOME)
    {
      FpSel = 0;
      FpSelFix();
    }
    else if(k == KEY_END)
    {
      if (FpMN > 0)
        FpSel = FpMN - 1;
      FpSelFix();
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
        FpSelFix();
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
        FpSelFix();
      }
    }
  }
  g_term_rx_own = 0;
  /* release ring to C readline */
  TermClear();
}
// Funs -- Funs(filt=0)
// NAME
//   Funs - topic-organized function browser; type to shrink, Enter to Src
// SYNOPSIS
//   Funs();  Funs("Print");
// DESCRIPTION
//   No-arg: interactive picker (Sections; groups; type/Tab/Enter/^G/Esc).
//   Non-empty filt: filter-only dump (no Esc wait). Full table dump: FunsList;
// EXAMPLES
//   Funs;
//   Funs("Uart");
//   // Funs; then type "Pri" → Enter → Src("Print")
// SEE ALSO
//   FunPick  FunsList  Src  Man  FunsS  FunsSec  Sections  FunEd
// BUGS
//   UART only — no mouse click targets yet; Enter selects (DolDoc-style Activate).
U0 Funs(U8 *filt = 0)
{
  FunPick(filt);
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
