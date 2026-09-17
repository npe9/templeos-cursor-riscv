// DolDoc-to-text renderer smoke (plan D-3): render a document's ENTRY STREAM straight to ANSI,
// with no WinMgr cell grid in the path, and keep the bandwidth property the grid presenter has —
// an idle re-render costs zero bytes, a one-line edit costs far less than the first paint.
// The window manager's only job here is the rectangle each doc is rendered into (tiling).
#include "/Kernel/Kernel_RV.PRJ"
#include "/Kernel/RVDocVT.HC"
#include "/Kernel/RVDocText.HC"
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
  I64 first, idle, after, tiled;
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
  RVVtStop();
  StrPrint(buf, "\ndoctext: first=%d idle=%d after=%d tiled=%d\n", first, idle, after, tiled);
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
  DtOut("doctext: PASS\n");
  return 0;
}
