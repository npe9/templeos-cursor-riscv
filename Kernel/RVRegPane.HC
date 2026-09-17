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
#define REGP_PREV 0x87000700
// the pane's own shadow: what it showed last time

#define REGP_ROWS 9
#define REGP_COLS 80
#define REGP_COL_SAME 7
// LTGRAY
#define REGP_COL_MOVED 4
// RED: this register just changed

CDoc *regp_doc;
I64 regp_bytes, regp_shown;

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
  U8 nm[8], line[128];
  I64 n, now, was, col;
  if (!regp_doc) {
    regp_doc = DocNew();
    if (!regp_doc)
      return;
  }
  DocClear(regp_doc);
  DocPutS(regp_doc, "$FG,5$registers$FG$  (red = changed by the last step)\n");
  n = 0;
  col = 0;
  while (n < 32) {
    now = *(I64 *)(REGP_CTX + n * 8);
    was = *(I64 *)(REGP_PREV + n * 8);
    RegPaneName(n, nm);
    StrPrint(line, "$FG,%d$%-4s %016X$FG$ ", now == was ? REGP_COL_SAME : REGP_COL_MOVED, nm, now);
    DocPutS(regp_doc, line);
    col++;
    if (col % 3 == 0)
      DocPutS(regp_doc, "\n");
    n++;
  }
  if (col % 3)
    DocPutS(regp_doc, "\n");
  regp_bytes = RVDocTextRender(regp_doc, 0, 0, REGP_ROWS, REGP_COLS);
  regp_shown = 1;
  n = 0;
  while (n < 32) {
    *(I64 *)(REGP_PREV + n * 8) = *(I64 *)(REGP_CTX + n * 8);
    n++;
  }
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
