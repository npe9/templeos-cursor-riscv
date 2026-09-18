// RVRegPane.HC — the live register pane: a DolDoc document, rendered to the terminal by
// Kernel/RVDocText.HC, repainted after every asm step so a changed register lights up in place.
//
// This is the "watch the registers as they change" view. It is deliberately just a DOCUMENT:
// the pane builds DolDoc source (with $FG,n$ on the registers that moved) and hands it to the
// renderer, which diffs against what the terminal already shows. Repainting all 32 registers
// therefore costs only the cells that actually differ — usually one register's worth.
//
// The registers come from the fault freeze (0x87000400), which is also the asm REPL's register
// file and what the _Xn labels alias, so this pane shows the same state whether you got there
// by faulting or by stepping.
//
// Include after RVDocVT.HC and RVDocText.HC. Wire it with AsmWatchInstall(&RegPaneUpdate) —
// the pointer keeps the compiler-image REPL from having to link this file.
#ifndef RV_REG_PANE_HC
#define RV_REG_PANE_HC
#help_index "DolDoc/VT"

#define REGP_CTX  0x87000400
// x0..x31 freeze / asm REPL register file
#define REGP_PREV 0x87000A00
// the pane's own shadow: what it showed last time (72 slots — 32 registers, 4 CSRs, pc, and
// the 32 float registers). Moved up from 0x87000700 when the float block was added: the
// stepper's float register file sits at 0x87000800.
#define REGP_FCTX 0x87000800
// f0..f31, as the asm stepper leaves them

#define REGP_SNAP 0x87000100
// the legacy freeze slots: 18 mcause, 19 mepc, 20 mtval, 21 mstatus

// An entry is "name + value + gap". A general register is %-4s + 16 hex + a space = 22 columns;
// a CSR spells its name out (mstatus, not mstat) and takes 24, one to a row. How many fit on a
// row is worked out from the pane's width rather than fixed, because the pane is a sidebar on a
// wide screen and a full-width block on a narrow one.
#define REGP_ENTRY 22
#define REGP_CSR_ENTRY 24
I64 regp_rows = 12, regp_cols = 70;
#define REGP_COL_SAME 15
// WHITE — LTGRAY landed on the terminal's dim plane (SGR 90) and was hard to read
#define REGP_COL_ZERO 8
// DKGRAY: leading zeros, so the magnitude of a value reads at a glance
#define REGP_COL_MOVED 12
// LTRED: this register just changed
#define REGP_COL_HEAD 14
// YELLOW heading

CDoc *regp_doc;
I64 regp_bytes, regp_shown;
I64 regp_row, regp_col;

// What changed is LATCHED rather than worked out while painting. The pane is painted from two
// places — after a step, and again whenever the layout is put back up — and a painter that
// compares against "what I showed last time" finds nothing changed on the second paint and
// draws every register calm again. That is the red vanishing while you read it. RegPaneMark
// latches; RegPaneUpdate only paints.
#define REGP_MARKS 72
I64 regp_moved[REGP_MARKS];
#define REGP_PC 36
#define REGP_FP0 40
// marks: 0-31 registers, 32-35 CSRs, 36 pc, 40-71 float
#define REGP_FREGS 32
I64 regp_fp = 1;
// Whether the float block is shown. A pane with no room for it says so by turning it off rather
// than cutting it in half — see RegPaneRowsNeeded, and Fp(1) to insist.
// pc's own mark slot, after the 32 registers and the 4 CSRs

// pc rides with the general registers rather than with the CSRs, which is where a debugger puts
// it and where the eye looks for it: x0..x31 and then pc. The value is the freeze's mepc — the
// same thing _PC reads and where G resumes — so "the pc" and "mepc" are one number wearing two
// names, one in each block.
#define REGP_PC_SLOT 19

// RegPaneAt -- RegPaneAt(row, col, rows, cols)
// NAME
//   RegPaneAt - place the register pane
// SYNOPSIS
//   RegPaneAt(0, 36, 21, 44);   // a right-hand sidebar
//   RegPaneAt(0, 0, 12, 70);    // a full-width block across the top
// DESCRIPTION
//   The pane lays itself out to fit: as many registers to a row as the width allows, and the
//   CSRs after them if there are rows left. Nothing is silently dropped — RegPaneRowsNeeded
//   says how many rows a given width wants.
// SEE ALSO
//   RegPaneUpdate  RegPaneRowsNeeded
public U0 RegPaneAt(I64 row, I64 col, I64 rows, I64 cols)
{
  regp_row = row;
  regp_col = col;
  regp_rows = rows;
  regp_cols = cols;
}

// How many registers fit on a row of this pane, and how many rows the whole thing wants.
I64 RegPanePerRow()
{
  I64 n;
  n = regp_cols / REGP_ENTRY;
  if (n < 1)
    n = 1;
  return n;
}

// RegPaneRowsNeeded -- RegPaneRowsNeeded()
// NAME
//   RegPaneRowsNeeded - rows this pane wants at its current width
// DESCRIPTION
//   Heading, the 32 general registers at whatever fits on a row, a heading for the CSRs and the
//   four of them. A layout asks before it hands out rows; a pane given fewer simply stops, which
//   is how ten registers went missing when the sidebar was too narrow.
// SEE ALSO
//   RegPaneAt  RegPaneUpdate
public I64 RegPaneRowsNeeded()
{
  I64 per, csr_per, rows;
  per = RegPanePerRow();
  csr_per = regp_cols / REGP_CSR_ENTRY;
  if (csr_per < 1)
    csr_per = 1;
  rows = 1 + (33 + per - 1) / per + 1 + (4 + csr_per - 1) / csr_per;
  // 33: the 32 registers and pc
  if (regp_fp)
    rows += 1 + (REGP_FREGS + per - 1) / per;
  return rows;
}

// RegPaneFp -- Fp(on)
// NAME
//   Fp - show or hide the float registers in the pane
// SYNOPSIS
//   Fp(1);   Fp(0);
// DESCRIPTION
//   Another 32 values is another 16 rows at two to a row, which a short terminal has not got.
//   The layout turns them off when they do not fit; this insists either way.
// SEE ALSO
//   RegPaneUpdate  AsmUiLayout
public U0 RegPaneFp(I64 on)
{
  regp_fp = on;
}

// The float register's ABI name — ft0-7, fs0-1, fa0-7, fs2-11, ft8-11.
U0 RegPaneFName(I64 n, U8 *out)
{
  if (n <= 7)
    StrPrint(out, "ft%d", n);
  else if (n <= 9)
    StrPrint(out, "fs%d", n - 8);
  else if (n <= 17)
    StrPrint(out, "fa%d", n - 10);
  else if (n <= 27)
    StrPrint(out, "fs%d", n - 16);
  else
    StrPrint(out, "ft%d", n - 20);
}

U0 RegPaneName(I64 n, U8 *out)
{
  if (n == 0)
    StrPrint(out, "zero");
  else if (n == 1)
    StrPrint(out, "ra");
  else if (n == 2)
    StrPrint(out, "sp");
  else if (n == 3)
    StrPrint(out, "gp");
  else if (n == 4)
    StrPrint(out, "tp");
  else if (n >= 5 && n <= 7)
    StrPrint(out, "t%d", n - 5);
  else if (n == 8)
    StrPrint(out, "s0");
  else if (n == 9)
    StrPrint(out, "s1");
  else if (n >= 10 && n <= 17)
    StrPrint(out, "a%d", n - 10);
  else if (n >= 18 && n <= 27)
    StrPrint(out, "s%d", n - 16);
  else
    StrPrint(out, "t%d", n - 25);
}

// One register as document source: name, then the value with its leading zeros dimmed so the
// eye lands on the significant digits. A changed register is loud; everything else stays calm
// but readable — the old LTGRAY mapped onto the terminal's dim plane and disappeared.
U0 RegPaneValue(U8 *out, U8 *nm, I64 v, I64 moved, I64 wide = FALSE)
{
  U8 hex[24];
  I64 i = 0, lead;
  StrPrint(hex, "%016X", v);
  lead = 0;
  while (lead < 15 && hex[lead] == '0')
    lead++;
  // Never put two `$` next to each other: DolDoc reads `$$` as an escaped literal dollar, so
  // "$FG$$FG,15$" parsed as `$FG` + `$` + "FG,15$" and printed "FG,15FG" into the pane. Each
  // command is separated by the text it colours, and only the last one closes.
  out[0] = 0;
  // %-4s for a register name and %-7s for a CSR: the width is the block's, not the name's, or
  // mepc would sit four columns left of mstatus.
  if (wide)
    StrPrint(out, "$FG,%d$%-7s ", moved ? REGP_COL_MOVED : REGP_COL_HEAD, nm);
  else
    StrPrint(out, "$FG,%d$%-4s ", moved ? REGP_COL_MOVED : REGP_COL_HEAD, nm);
  StrPrint(out + StrLen(out), "$FG,%d$", REGP_COL_ZERO);
  while (i < lead) {
    out[StrLen(out) + 1] = 0;
    out[StrLen(out)] = hex[i];
    i++;
  }
  StrPrint(out + StrLen(out), "$FG,%d$", moved ? REGP_COL_MOVED : REGP_COL_SAME);
  while (hex[i]) {
    out[StrLen(out) + 1] = 0;
    out[StrLen(out)] = hex[i];
    i++;
  }
  StrPrint(out + StrLen(out), "$FG$ ");
}

// The CSRs the debugger already freezes: why you stopped (mcause), where (mepc), on what address
// (mtval), and the mode/interrupt state (mstatus). An asm stepper wants them beside the
// registers — a fault is the most common reason a register looks wrong.
#define REGP_CSR_N 4
U0 RegPaneCsrName(I64 i, U8 *out)
{
  if (!i)
    StrPrint(out, "mcause");
  else if (i == 1)
    StrPrint(out, "mepc");
  else if (i == 2)
    StrPrint(out, "mtval");
  else
    StrPrint(out, "mstatus");
}

I64 RegPaneCsrVal(I64 i)
{
  return *(I64 *)(REGP_SNAP + (18 + i) * 8);
}

// RegPaneUpdate -- RegPaneUpdate()
// NAME
//   RegPaneUpdate - repaint the live register pane; changed registers in red
// SYNOPSIS
//   RegPaneUpdate;
// DESCRIPTION
//   Rebuilds the pane as DolDoc source and renders it. Only the cells that differ from what the
//   terminal already shows go on the wire, so a step that moves one register costs a handful of
//   bytes even though the whole pane is re-laid-out. Returns nothing; the byte cost of the last
//   paint is in regp_bytes.
// EXAMPLES
//   AsmWatchInstall(&RegPaneUpdate);  AsmStep("addi a0,a0,7");
// SEE ALSO
//   AsmStep  RVDocTextRender  Dr
U0 RegPaneUpdate()
{
  U8 nm[12], line[160];
  I64 n, now, col, per, csr_per;
  if (!regp_doc) {
    regp_doc = DocNew();
    if (!regp_doc)
      return;
  }
  per = RegPanePerRow();
  csr_per = regp_cols / REGP_CSR_ENTRY;
  if (csr_per < 1)
    csr_per = 1;
  DocClear(regp_doc);
  if (regp_cols >= 40)
    StrPrint(line, "$FG,%d$registers $FG,%d$red = just changed$FG$\n", REGP_COL_HEAD,
             REGP_COL_MOVED);
  else
    StrPrint(line, "$FG,%d$registers$FG$\n", REGP_COL_HEAD);
  DocPutS(regp_doc, line);
  n = 0;
  col = 0;
  while (n < 32) {
    now = *(I64 *)(REGP_CTX + n * 8);
    RegPaneName(n, nm);
    RegPaneValue(line, nm, now, regp_moved[n]);
    DocPutS(regp_doc, line);
    col++;
    if (col % per == 0)
      DocPutS(regp_doc, "\n");
    n++;
  }
  now = *(I64 *)(REGP_SNAP + REGP_PC_SLOT * 8);
  RegPaneValue(line, "pc", now, regp_moved[REGP_PC]);
  DocPutS(regp_doc, line);
  col++;
  if (col % per)
    DocPutS(regp_doc, "\n");
  StrPrint(line, "$FG,%d$machine state$FG$\n", REGP_COL_HEAD);
  DocPutS(regp_doc, line);
  n = 0;
  col = 0;
  while (n < REGP_CSR_N) {
    now = RegPaneCsrVal(n);
    RegPaneCsrName(n, nm);
    RegPaneValue(line, nm, now, regp_moved[32 + n], TRUE);
    DocPutS(regp_doc, line);
    col++;
    if (col % csr_per == 0)
      DocPutS(regp_doc, "\n");
    n++;
  }
  if (col % csr_per)
    DocPutS(regp_doc, "\n");
  if (regp_fp) {
    // Say where these came from. The float file is the asm STEPPER's (0x87000800) and no trap
    // path writes it — neither trap vector contains a single fsd — so after a fault these are
    // whatever the last stepped line left behind, not the faulting context. Until the freeze
    // saves f0..f31 the honest thing is to label them rather than let them sit next to the
    // integer registers looking equally true. See docs/DEBUG_STATE_SURVEY.md.
    StrPrint(line, "$FG,%d$float $FG,%d$(as last stepped)$FG$\n", REGP_COL_HEAD, REGP_COL_ZERO);
    DocPutS(regp_doc, line);
    n = 0;
    col = 0;
    while (n < REGP_FREGS) {
      now = *(I64 *)(REGP_FCTX + n * 8);
      RegPaneFName(n, nm);
      // raw bits, like the stepper prints them: an encoding is what you are checking
      RegPaneValue(line, nm, now, regp_moved[REGP_FP0 + n]);
      DocPutS(regp_doc, line);
      col++;
      if (col % per == 0)
        DocPutS(regp_doc, "\n");
      n++;
    }
    if (col % per)
      DocPutS(regp_doc, "\n");
  }
  regp_bytes = RVDocTextRender(regp_doc, regp_row, regp_col, regp_rows, regp_cols);
  regp_shown = 1;
}

// RegPaneMark -- RegPaneMark()
// NAME
//   RegPaneMark - latch which registers have changed since the last mark
// DESCRIPTION
//   Call once per step, before painting. The marks stay until the next mark, so the pane can be
//   repainted any number of times — a clear, a relayout, a scrolled screen — and the registers
//   that moved are still the ones in red.
// SEE ALSO
//   RegPaneUpdate  RegPaneStep  AsmStep
public U0 RegPaneMark()
{
  I64 n, now;
  n = 0;
  while (n < 32) {
    now = *(I64 *)(REGP_CTX + n * 8);
    regp_moved[n] = now != *(I64 *)(REGP_PREV + n * 8);
    *(I64 *)(REGP_PREV + n * 8) = now;
    n++;
  }
  n = 0;
  while (n < REGP_CSR_N) {
    now = RegPaneCsrVal(n);
    regp_moved[32 + n] = now != *(I64 *)(REGP_PREV + (32 + n) * 8);
    *(I64 *)(REGP_PREV + (32 + n) * 8) = now;
    n++;
  }
  now = *(I64 *)(REGP_SNAP + REGP_PC_SLOT * 8);
  regp_moved[REGP_PC] = now != *(I64 *)(REGP_PREV + REGP_PC * 8);
  *(I64 *)(REGP_PREV + REGP_PC * 8) = now;
  n = 0;
  while (n < REGP_FREGS) {
    now = *(I64 *)(REGP_FCTX + n * 8);
    regp_moved[REGP_FP0 + n] = now != *(I64 *)(REGP_PREV + (REGP_FP0 + n) * 8);
    *(I64 *)(REGP_PREV + (REGP_FP0 + n) * 8) = now;
    n++;
  }
}

// RegPaneStep -- RegPaneStep()
// NAME
//   RegPaneStep - latch what moved and paint it; the watch hook
// SYNOPSIS
//   AsmWatchInstall(&RegPaneStep);
// SEE ALSO
//   RegPaneMark  RegPaneUpdate
public U0 RegPaneStep()
{
  RegPaneMark;
  RegPaneUpdate;
}

// RegPaneCost -- RegPaneCost()
// NAME
//   RegPaneCost - bytes the last pane repaint put on the wire
// SEE ALSO
//   RegPaneUpdate
I64 RegPaneCost()
{
  return regp_bytes;
}

#endif
