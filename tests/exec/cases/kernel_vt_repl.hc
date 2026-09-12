// Interactive DolDoc/WinMgr REPL presented to a real terminal as ANSI.
//
// The difference from kernel_vt_demo.hc is that this one takes input. The trick is
// which entry point the keystrokes go to:
//
//   RVWinSerialPoll()   reads the UART and echoes + prints straight back to the UART.
//                       That fights the presenter — two writers on one wire, and the
//                       grid gets shredded by the REPL's own output.
//   RVWinTermPutChar()  echoes into the focused window's DolDoc body and, on Enter,
//                       raises rv_win_term_mirror so RVWinSerialDispatch's Print
//                       output is captured into that body too (RVWinTermMirrorPutS).
//
// So this drives the second one and lets RVVtPresent be the ONLY thing that writes to
// the wire. Everything you type and everything the REPL answers is grid content, and
// the terminal only ever sees a diff.
//
// Commands come from RVWinSerialDispatch: help, regs, bt, md, mw, max, tileh, tilev,
// user, fault, crash, q. If ExePutS is linked, RVWinSerialEval is wired to it and
// arbitrary HolyC is accepted too; if it is not, the built-ins still work and the
// banner says so rather than pretending.
#include "/Kernel/Kernel_RV.PRJ"
#include "/Kernel/RVDocVT.HC"
#ifndef RV_VT_REPL_ROWS
#define RV_VT_REPL_ROWS 24
#endif
#ifndef RV_VT_REPL_COLS
#define RV_VT_REPL_COLS 80
#endif
#ifndef RV_VT_REPL_UTF8
#define RV_VT_REPL_UTF8 0
#endif
#ifndef RV_VT_REPL_COLOR
#define RV_VT_REPL_COLOR 1
#endif

// Where to park the terminal's cursor. The WinMgr keeps no caret field (windows are
// composed, not edited in place), so derive it: the last non-blank cell inside the
// Term window is the end of what has been typed, and the caret sits just after it.
// Cheap, and exactly right for an append-only REPL body.
I64 g_vt_caret_row;
I64 g_vt_caret_col;
U0 VtReplCaret(I64 idx)
{
  CRVWin *w;
  I64 x, y, ch;
  w = &rv_winmgr.wins[idx];
  g_vt_caret_row = w->top;
  g_vt_caret_col = w->left;
  for (y = w->top; y <= w->bottom; y++) {
    for (x = w->left; x <= w->right; x++) {
      ch = rv_winmgr.text_base[y *rv_winmgr.cols + x] & 255;
      if (ch > 32) {
        g_vt_caret_row = y;
        g_vt_caret_col = x + 1;
      }
    }
  }
  if (g_vt_caret_col > w->right)
    g_vt_caret_col = w->right;
}

I64 main()
{
  I64 ch, idx, n, last_row = -1, last_col = -1;
  I64 rows = RV_VT_REPL_ROWS, cols = RV_VT_REPL_COLS;
  RVKernelInit();
  if (!RVWinMgrLiteInit()) {
    RVUartPutS("VT-REPL: LiteInit FAILED\n");
    return 1;
  }
  if (rows * cols > RV_VT_CELLS_MAX) {
    RVUartPutS("VT-REPL: rows*cols exceeds RV_VT_CELLS_MAX\n");
    return 2;
  }
  // RVVtPresent reads these live, so the 80x25 LiteInit hardcodes retarget cleanly.
  rv_winmgr.rows = rows;
  rv_winmgr.cols = cols;
  text.rows = rows;
  text.cols = cols;
  // One Term window filling the grid, inset by the border RVTextBorder draws outside.
  idx = RVWinNew(1, cols - 2, 2, rows - 2, "Term",
                 "TempleOS/RISC-V — DolDoc REPL on a VT100\n"
                 "Type a command and press Enter.  help / regs / bt / md ADDR / q\n> ", TRUE);
  if (idx < 0) {
    RVUartPutS("VT-REPL: RVWinNew FAILED\n");
    return 3;
  }
  rv_winmgr.term_idx = idx;
  rv_winmgr.focus = idx;
  rv_winmgr.wins[idx].kind = RV_WIN_KIND_TERM;
  RVWinSerialInit();
  // The presenter owns the UART: everything the REPL prints must go into the window
  // body only, or a raw Print lands in the middle of the ANSI frame. Default is
  // mirror-and-write, which is correct for the FB path where they are two devices.
  rv_console_mirror_only = 1;
  RVVtInit(RV_VT_REPL_UTF8, RV_VT_REPL_COLOR);
  while (!rv_winmgr.want_quit) {
    ch = RVUartTryGet;
    if (ch >= 0)
      RVWinTermPutChar(ch);
    // RVWinMgrRefresh is the FB path's per-tick compose and bails without
    // rv_fb.pixels. Only its first two steps touch the text grid; everything after
    // RVWinMgrBlitTextBase is pixel work this presenter does not want. So call the
    // text half directly and let RVVtPresent be the scanout.
    RVWinMgrWallPaper;
    RVWinMgrComposeWins;
    // Present first: 0 bytes when nothing changed, which is the property the whole
    // presenter exists to provide. Then move the caret ONLY if the frame changed or
    // the caret actually moved.
    //
    // RVVtPresentAt would be the obvious call here and is wrong in this loop: it
    // re-emits goto + cursor-on unconditionally, so a spin loop on an idle screen
    // shipped 80,314 cursor escapes in a few seconds. Measured, not guessed — at
    // 115200 baud that is a saturated wire showing a motionless screen.
    n = RVVtPresent();
    VtReplCaret(idx);
    if (n > 0 || g_vt_caret_row != last_row || g_vt_caret_col != last_col) {
      RVVtGoto(g_vt_caret_row, g_vt_caret_col);
      RVVtCursor(1);
      RVVtFlush();
      last_row = g_vt_caret_row;
      last_col = g_vt_caret_col;
    }
  }
  RVVtStop();
  RVUartPutS("\nVT-REPL: quit\n");
  return 0;
}
