// DolDoc-to-text renderer smoke (plan D-3): render a document's ENTRY STREAM straight to ANSI,
// with no WinMgr cell grid in the path, and keep the bandwidth property the grid presenter has —
// an idle re-render costs zero bytes, a one-line edit costs far less than the first paint.
// The window manager's only job here is the rectangle each doc is rendered into (tiling).
#include "/Kernel/Kernel_RV.PRJ"
#include "/Kernel/RVDocVT.HC"
#include "/Kernel/RVDocText.HC"
#include "/Kernel/RVRegPane.HC"
#define MEM_UART_DT 0x10000000

U0 DtOut(U8 *s)
{
  U8 *u = MEM_UART_DT;
  while (s && *s) {
    *u = *s;
    s++;
  }
}

I64 main()
{
  CDoc *doc;
  I64 first, idle, after, tiled, pane_first, pane_step;
  U8 buf[160];
  RVKernelInit();
  if (!RVWinMgrLiteInit()) {
    DtOut("doctext: LiteInit FAILED\n");
    return 1;
  }
  RVVtInit(0, 1);
  doc = DocNew();
  if (!doc) {
    DtOut("doctext: DocNew FAILED\n");
    return 2;
  }
  // Ordinary DolDoc source: $FG,n$ colour commands are consumed by DocRecalc, which bakes the
  // resolved attribute into each text entry — the renderer never parses a $ command itself.
  DocPutS(doc, "$FG,5$TempleOS/RISC-V$FG$ doc to text\n");
  DocPutS(doc, "second line\n");
  first = RVDocTextRender(doc, 0, 0, 25, 80);
  // Nothing changed: the shadow must make this free. Same property as the grid presenter.
  idle = RVDocTextRender(doc, 0, 0, 25, 80);
  // Append a line: must cost far less than the first full paint.
  DocPutS(doc, "third line\n");
  after = RVDocTextRender(doc, 0, 0, 25, 80);
  // Tiling: the same doc rendered into a right-hand rectangle. Geometry comes from the caller
  // (the window manager), not from anything the renderer composites.
  RVDocTextInvalidate();
  tiled = RVDocTextRender(doc, 0, 40, 12, 40);
  // The live register pane: the same renderer, fed by the debugger's register file. Paint it,
  // then move ONE register the way a stepped instruction would and repaint — the second paint
  // must cost a fraction of the first, which is what makes "watch the registers change" usable
  // on a serial line.
  RVDocTextInvalidate();
  RegPaneUpdate();
  pane_first = RegPaneCost();
  *(I64 *)(0x87000400 + 10 * 8) = 0x2A;
  // a0 as a step would leave it
  RegPaneUpdate();
  pane_step = RegPaneCost();
  RVVtStop();
  StrPrint(buf, "\ndoctext: pane_first=%d pane_step=%d\n", pane_first, pane_step);
  DtOut(buf);
  StrPrint(buf, "doctext: first=%d idle=%d after=%d tiled=%d\n", first, idle, after, tiled);
  DtOut(buf);
  if (first <= 0) {
    DtOut("doctext: FAIL nothing rendered\n");
    return 3;
  }
  if (idle != 0) {
    DtOut("doctext: FAIL idle re-render was not free\n");
    return 4;
  }
  if (after <= 0 || after >= first) {
    DtOut("doctext: FAIL incremental render not cheaper than full paint\n");
    return 5;
  }
  if (tiled <= 0) {
    DtOut("doctext: FAIL tile render produced nothing\n");
    return 6;
  }
  if (pane_first <= 0) {
    DtOut("doctext: FAIL register pane never painted\n");
    return 7;
  }
  if (pane_step <= 0 || pane_step >= pane_first) {
    DtOut("doctext: FAIL one-register repaint not cheaper than the pane's first paint\n");
    return 8;
  }
  DtOut("doctext: PASS\n");
  return 0;
}
