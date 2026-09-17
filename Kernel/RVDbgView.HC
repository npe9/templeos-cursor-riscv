// RVDbgView.HC — Dbg: the debugger view, as documents rendered to the terminal.
//
// Stock TempleOS (tos/Doc/DbgOverview.DD) has no modal debugger UI: you call Dbg(), you are at a
// prompt, and you inspect with ordinary functions — Dr, U, D/Dm, and registers as var-like
// labels. This file is that entry point for RISC-V: it paints what you always want to see after
// a fault (registers, and the fault itself decoded) and leaves you at the HolyC prompt, where
// _A0, U(_PC-16), AsmStep, Bp and the rest already work.
//
// Both panes are DolDoc documents rendered by Kernel/RVDocText.HC into rectangles the caller
// chooses — the window manager's whole remaining job. The renderer diffs, so re-entering Dbg
// after a step costs a few dozen bytes, not a repaint.
//
// Include after RVDocVT.HC, RVDocText.HC and RVRegPane.HC.
#ifndef RV_DBG_VIEW_HC
#define RV_DBG_VIEW_HC
#help_index "Dbg"

#define DBGV_SNAP 0x87000100
// legacy freeze slots: 18 mcause, 19 mepc, 20 mtval, 21 mstatus
#define DBGV_SNAP_X 0x87000400
// canonical x0..x31
#define DBGV_STATUS_ROW REGP_ROWS
// straight under the register pane

CDoc *dbgv_doc;
I64 dbgv_bytes;

// Dbg -- Dbg()
// NAME
//   Dbg - enter the debugger view: registers + the decoded fault, then back to the prompt
// SYNOPSIS
//   Dbg;
// DESCRIPTION
//   Paints the register pane and a status line (cause name, mepc, mtval, ra, sp, mstatus) from
//   the fault freeze, then returns. There is no modal loop and no separate command language:
//   you are at the HolyC prompt, so inspect with Dr, U(_PC-16), D/Dm, _A0, AsmStep, Bp — the
//   same functions that work anywhere else. That is how stock TempleOS debugs.
//   The REPL calls this for you when a line faults.
// EXAMPLES
//   Dbg;  U(_PC - 16);  _A0 = 5;  AsmStep("addi a0,a0,1");
// SEE ALSO
//   Dr  AsmStep  RegPaneUpdate  U  Uf  Bp  G
// BUGS
//   No disassembly pane yet: DisasmOne prints rather than returning text, so it cannot be put
//   in a document without a buffer variant. Use U(_PC) meanwhile.
public U0 Dbg()
{
  U8 line[192];
  I64 cause;
  RegPaneUpdate;
  if (!dbgv_doc) {
    dbgv_doc = DocNew();
    if (!dbgv_doc)
      return;
  }
  cause = *(I64 *)(DBGV_SNAP + 18 * 8);
  DocClear(dbgv_doc);
  StrPrint(line, "$FG,4$%s$FG$\n", RVWinMcauseName(cause));
  DocPutS(dbgv_doc, line);
  StrPrint(line, "mepc=%016X  mtval=%016X\n", *(I64 *)(DBGV_SNAP + 19 * 8),
           *(I64 *)(DBGV_SNAP + 20 * 8));
  DocPutS(dbgv_doc, line);
  StrPrint(line, "ra  =%016X  sp   =%016X\n", *(I64 *)(DBGV_SNAP_X + 1 * 8),
           *(I64 *)(DBGV_SNAP_X + 2 * 8));
  DocPutS(dbgv_doc, line);
  StrPrint(line, "mstatus=%016X\n", *(I64 *)(DBGV_SNAP + 21 * 8));
  DocPutS(dbgv_doc, line);
  DocPutS(dbgv_doc, "$FG,7$Dr  U(_PC-16)  _A0  AsmStep(\"...\")  Bp(addr)$FG$\n");
  dbgv_bytes = RVDocTextRender(dbgv_doc, DBGV_STATUS_ROW, 0, 6, 80);
}

// G -- G()
// NAME
//   G - continue (stock TempleOS name)
// SYNOPSIS
//   G;
// DESCRIPTION
//   Registers edited while stopped are already applied on resume by the trap path's copy-back
//   (TrapSnapApply / HolyTrapSnapApply), so after a fault that the REPL recovered from there is
//   nothing left to resume — the line was abandoned and you are back at the prompt. G exists so
//   the stock name means something: it clears the view. Resuming a stopped context needs the
//   debugger to run INSIDE the trap handler, which is still to come.
// SEE ALSO
//   Dbg  Dr  AsmStep
public U0 G()
{
  RVDocTextInvalidate;
  dbgv_bytes = 0;
}

I64 DbgViewCost()
{
  return dbgv_bytes;
}

#endif
