// Human-eyeball VT demo: paint a full-grid frame on a REAL terminal and HOLD it.
//
// The gated smoke (kernel_vt_present.hc) paints three frames, measures cost and exits,
// which is right for CI and useless for looking at. This one is the opposite: it draws
// a frame designed to make the two open questions in docs/DOLDOC_VT.md falsifiable at a
// glance, then idles forever so you can actually see it. Quit with Ctrl-A then X.
//
//   make kernel-vt-demo                      # 80x24, the usual real-terminal size
//   RV_VT_ROWS=25 make kernel-vt-demo        # 80x25, what RVWinMgrLiteInit hardcodes
//
// What to look for is written into the frame itself: the bottom border and the last
// row label must both be visible, and the top border must not have scrolled away.
#include "/Kernel/Kernel_RV.PRJ"
#include "/Kernel/RVDocVT.HC"
#ifndef RV_VT_DEMO_ROWS
#define RV_VT_DEMO_ROWS 24
#endif
#ifndef RV_VT_DEMO_COLS
#define RV_VT_DEMO_COLS 80
#endif
// Terminal capability is told, not probed (RVVtInit takes flags, not a query) — which
// is exactly the limitation worth exercising against a real terminal.
#ifndef RV_VT_DEMO_UTF8
#define RV_VT_DEMO_UTF8 0
#endif
#ifndef RV_VT_DEMO_COLOR
#define RV_VT_DEMO_COLOR 1
#endif

I64 main()
{
  I64 rows = RV_VT_DEMO_ROWS, cols = RV_VT_DEMO_COLS, y, n;
  U8 buf[96];
  RVKernelInit();
  if (!RVWinMgrLiteInit())
    return 1;
  // RVVtPresent refuses a grid larger than its shadow; say so here rather than
  // silently painting nothing.
  if (rows * cols > RV_VT_CELLS_MAX) {
    RVUartPutS("VT demo: rows*cols exceeds RV_VT_CELLS_MAX (8192)\n");
    return 2;
  }
  // RVVtPresent reads rv_winmgr.rows/cols live, so the 80x25 LiteInit hardcodes can be
  // retargeted here without touching the kernel. text.* mirrors it for DocRecalc.
  rv_winmgr.rows = rows;
  rv_winmgr.cols = cols;
  text.rows = rows;
  text.cols = cols;
  RVVtInit(RV_VT_DEMO_UTF8, RV_VT_DEMO_COLOR);
  // Layout, chosen so nothing overdraws anything else. RVTextBorder draws OUTSIDE the
  // rect it is handed, so a border of (1, cols-2, 2, rows-2) puts its top edge on row 1
  // and its bottom edge on row rows-1 — leaving row 0 free for the ruler.
  //   row 0            column ruler
  //   row 1            border top
  //   rows 2..rows-2   interior (labels + messages)
  //   row rows-1       border bottom  <- must be visible
  for (n = 0; n < cols; n++) {
    if (!(n % 10))
      RVTextPrint(n, 0, LTGREEN, "|");
    else
      RVTextPrint(n, 0, DKGRAY, ".");
  }
  for (y = 2; y < rows - 1; y++) {
    StrPrint(buf, "row %02d", y);
    RVTextPrint(2, y, WHITE, buf);
  }
  StrPrint(buf, "TempleOS/RISC-V DolDoc VT presenter  %dx%d  utf8=%d color=%d",
           cols, rows, RV_VT_DEMO_UTF8, RV_VT_DEMO_COLOR);
  RVTextPrint(12, 3, LTCYAN, buf);
  RVTextPrint(12, 5, YELLOW, "Top ruler AND bottom border must both be visible.");
  RVTextPrint(12, 6, YELLOW, "If the ruler scrolled off, the grid is taller than this terminal.");
  RVTextPrint(12, 7, YELLOW, "Ctrl-A then X quits QEMU.");
  StrPrint(buf, "<- last interior row (%02d); border below it", rows - 2);
  RVTextPrint(30, rows - 2, LTRED, buf);
  RVTextBorder(1, cols - 2, 2, rows - 2, LTGRAY, 0);
  n = RVVtPresent();
  // Hold. Idle presents cost 0 bytes by design, so the frame simply stays put.
  while (1)
    RVVtPresent();
  return 0;
}
