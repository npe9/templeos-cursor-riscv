// Overlapping windows must composite by Z, not by array index.
//
// RVWinMgrDrawIts walks `for (i = 0; i < RV_WIN_MAX; i++)` and clips each window's draw_it to
// that window's OWN rect — nothing consults rv_winmgr.win_z_buf, which is filled by
// RVWinZBufFill/WinZBufUpdate and read by no one. So a window that happens to sit at a HIGHER
// array index paints over a window that is in FRONT of it. Nothing in the tree could see this:
// the DocTerm desktop tiles its windows and sets draw_it = NULL.
//
// This case is the smallest thing that can see it. Two OVERLAPPING windows, each with a
// draw_it that tries to paint the whole screen (the DC clip is what confines it to the
// window), and the FRONT one deliberately placed at the LOWER array index:
//
//   front: index 0, focused  -> higher z  -> must own the overlap
//   back:  index 1           -> lower z   -> must not paint into it
//
// Painting back-to-front by z fixes it; so does a per-cell win_z_buf clip in GrPlot0. Both are
// checked here by reading the overlap pixel out of the compose buffer.
#include "/Kernel/Kernel_RV.PRJ"

#define ZORDER_FRONT_COLOR 0x00FF00FF
#define ZORDER_BACK_COLOR  0x0000FF00

U0 ZOrderFrontDrawIt(CRVWin *w, CRVDC *dc)
{
  if (!dc)
    return;
  dc->color = ZORDER_FRONT_COLOR;
  GrRect(dc, 0, 0, 800, 600); //whole screen; the window clip is what limits it
}

U0 ZOrderBackDrawIt(CRVWin *w, CRVDC *dc)
{
  if (!dc)
    return;
  dc->color = ZORDER_BACK_COLOR;
  GrRect(dc, 0, 0, 800, 600);
}

U0 ZOrderAdamBoot()
{
  CTask *adam = 0x86900000;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400;
  heap_end = 0x86000000;
  CBlkPool *bp = 0x86800000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  CHeapCtrl *ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah;
  adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0);
  adam->task_signature = TASK_SIGNATURE_VAL;
  adam->addr = adam;
  CCPU *gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVYieldInit(&Fs);
  RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);
}

I64 main()
{
  I64 front, back, px, py, got, want, h;
  CRVWin *wf;
  CRVWin *wb;
  ZOrderAdamBoot;
  RVKernelInit();
  rv_sys_gr_force = 1;
  if (!RVGrInit()) {
    Print("ZOrder init FAIL (Gr)\n");
    return 1;
  }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB);
  if (!RVWinMgrInit()) {
    Print("ZOrder init FAIL (WinMgr)\n");
    return 1;
  }
  // FRONT first so it takes the LOWER array index, and focused so compose gives it the
  // HIGHER z. That pairing is exactly what index-order painting gets wrong.
  front = RVWinNew(10, 40, 10, 30, "front", NULL, TRUE);
  back = RVWinNew(25, 55, 20, 40, "back", NULL, FALSE);
  if (front < 0 || back < 0 || front >= back) {
    Print("ZOrder setup FAIL front=%d back=%d (front must be the lower index)\n", front, back);
    return 1;
  }
  wf = &rv_winmgr.wins[front];
  wb = &rv_winmgr.wins[back];
  wf->draw_it = &ZOrderFrontDrawIt;
  wb->draw_it = &ZOrderBackDrawIt;
  RVWinMgrRefresh();
  if (wf->z <= wb->z) {
    Print("ZOrder setup FAIL front z=%d back z=%d (front must be in front)\n", wf->z, wb->z);
    return 1;
  }
  // A pixel well inside the overlap: cells 25..40 x 20..30 -> +4px off the cell edge.
  px = 30 * FONT_WIDTH + 4;
  py = 25 * FONT_HEIGHT + 4;
  got = rv_fb.pixels[py *rv_fb.width + px] & 0x00FFFFFF;
  want = ZORDER_FRONT_COLOR;
  h = RVFbHash() & 0xFFFFFFFF;
  Print("ZOrder front=%d(z=%d) back=%d(z=%d) overlap=(%d,%d) got=0x%06X want=0x%06X hash=0x%08X\n",
        front, wf->z, back, wb->z, px, py, got, want, h);
  if (got != want) {
    Print("ZOrder FAIL — the back window painted over the front one\n");
    return 1;
  }
  Print("ZOrder OK\n");
  return 0;
}
