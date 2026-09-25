// kernel_gr_scenes.hc — the framebuffer-parity oracle (docs/FB_PARITY_PLAN.md phase 1).
//
// Each scene draws a FIXED picture into an OFFSCREEN 8-bit DC and hashes the bitmap. No screen, no
// window manager, no palette→pixel step, no timing: just DCNew8(w,h), a deterministic drawing
// sequence, and FNV-1a over width_internal*height bytes of dc->body.
//
// Why this shape:
//   * it is the same 8-bit CDC body shape stock TempleOS draws into (COLORS_NUM is 16), so the same
//     program can run on x86 TempleOS and produce a reference column;
//   * it fails LOCALLY — a wrong GrCircle is one scene hash, not a screenshot someone has to eyeball;
//   * it needs no display, so it runs in the same exec harness as every other case here.
//
// SCENE_DC_NEW is one line on purpose. Today the port's stock-CDC-shaped DC is DCNew8; after
// FB_PARITY_PLAN phase 2 adopts stock CDC, plain DCNew is that shape and only this define changes.
//
// The hashes are pinned in tests/gr_scene_hashes.tsv. They are expected to MOVE when a phase lands —
// re-pin with `GR_SCENE_PIN=1 make kernel-gr-scenes-smoke` and say in the commit which scenes moved
// and why. A scene moving that the change does not explain is the finding.

#include "/Kernel/Kernel_RV.PRJ"

#define SCENE_DC_NEW(w, h)	DCNew8(w, h)
#define SCENE_W		128
#define SCENE_H		 96

U0 SceneBoot()
{
  CTask *adam = 0x86900000; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs;
  MemSet(adam, 0, sizeof(CTask)); Fs = adam; adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400; heap_end = 0x86000000;
  bp = 0x86800000; BlkPoolInit(bp, 0x2000); sys_code_bp = bp;
  ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah; adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0); adam->task_signature = TASK_SIGNATURE_VAL; adam->addr = adam;
  gs = 0x86A00000; MemSet(gs, 0, sizeof(CCPU)); gs->seth_task = adam; adam->gs = gs; Gs = gs;
  RVYieldInit(&Fs);
  RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);
  RVKernelInit();
  RVGrInit(640, 480);
  text.cols = 80; text.rows = 60;
  text.font = sys_font_std; text.aux_font = sys_font_cyrillic;
  Fs->win_left = 0; Fs->win_right = 79; Fs->win_top = 0; Fs->win_bottom = 59;
  WinDerivedValsUpdate(Fs);
}
SceneBoot;

U64 SceneHash(CRVDC *dc)
{//FNV-1a over the whole bitmap INCLUDING the row padding, so a stride change is a hash change.
  U64 h = 0xCBF29CE484222325;
  U8 *p;
  I64 i, n;
  if (!dc || !dc->body)
    return 0;
  p = dc->body;
  n = dc->width_internal * dc->height;
  for (i = 0; i < n; i++) {
    h ^= p[i];
    h *= 0x100000001B3;
  }
  return h;
}

U0 SceneReport(U8 *name, CRVDC *dc)
{
  "GRSCENE %s %016X\n", name, SceneHash(dc);
}

//--- the scenes. Every coordinate is a literal: no Rand, no time, no screen size. -----------------

U0 SPlot(CRVDC *dc)
{
  I64 i;
  for (i = 0; i < 64; i++) {
    dc->color = i & 15;
    GrPlot(dc, i * 2, i + 8);
  }
}

U0 SHLine(CRVDC *dc)
{
  I64 i;
  for (i = 0; i < 12; i++) {
    dc->color = i + 1 & 15;
    GrHLine(dc, 4, 120, i * 7 + 2);
  }
}

U0 SLine(CRVDC *dc)
{
  I64 i;
  for (i = 0; i < 8; i++) {
    dc->color = i + 1 & 15;
    GrLine(dc, 4, 4 + i * 10, 120, 90 - i * 10);
  }
}

U0 SLineThick(CRVDC *dc)
{
  I64 i;
  for (i = 0; i < 4; i++) {
    dc->color = i + 9 & 15;
    dc->thick = i + 1;
    GrLine(dc, 8 + i * 28, 6, 8 + i * 28, 88);
  }
  dc->thick = 1;
}

U0 SRect(CRVDC *dc)
{
  I64 i;
  for (i = 0; i < 6; i++) {
    dc->color = i + 2 & 15;
    GrRect(dc, 6 + i * 9, 6 + i * 6, 40 - i * 4, 30 - i * 3);
  }
}

U0 SCircle(CRVDC *dc)
{
  I64 i;
  for (i = 1; i <= 6; i++) {
    dc->color = i + 3 & 15;
    GrCircle(dc, 64, 48, i * 7);
  }
}

U0 SFillCircle(CRVDC *dc)
{
  I64 i;
  for (i = 4; i >= 1; i--) {
    dc->color = i + 4 & 15;
    GrFillCircle(dc, 40 + i * 8, 48, i * 9);
  }
}

U0 SFloodFill(CRVDC *dc)
{
  dc->color = 7;
  GrRect(dc, 10, 10, 60, 40);
  dc->color = 3;
  GrFloodFill(dc, 40, 30);
}

U0 STri(CRVDC *dc)
{//Stock is GrFillTri0(CDC*,CD3I32*,CD3I32*,CD3I32*) — three POINTS, not six coordinates.
 //Passing 10,80,64,… made p1->x load from address 10, which is the mtval=0xa this scene
 //trapped with on its first run. The oracle's first find was a bug in the oracle.
  CD3I32 a, b, c;
  a.x = 10;  a.y = 80; a.z = 0;
  b.x = 64;  b.y =  8; b.z = 0;
  c.x = 118; c.y = 80; c.z = 0;
  dc->color = 11;
  GrFillTri0(dc, &a, &b, &c);
}

U0 SBlot(CRVDC *dc)
{
  CRVDC *b = SCENE_DC_NEW(16, 16);
  I64 i;
  if (!b)
    return;
  for (i = 0; i < 16; i++) {
    b->color = i & 15;
    GrHLine(b, 0, 15, i);
  }
  GrBlot(dc, 20, 20, b);
  GrBlot(dc, 70, 50, b);
  DCDel(b);
}

U0 SPrint(CRVDC *dc)
{
  dc->color = 15;
  GrPrint(dc, 8, 8, "Parity");
  dc->color = 4;
  GrPrint(dc, 8, 24, "0123456789");
}

U0 SFill(CRVDC *dc)
{
  DCFill(dc, 6);
}

U0 SPeekWrite(CRVDC *dc)
{//GrPeek must read back exactly what GrPlot wrote: a round trip, not just a draw.
  I64 x, y;
  for (y = 0; y < 16; y++)
    for (x = 0; x < 16; x++) {
      dc->color = x ^ y & 15;
      GrPlot(dc, x + 4, y + 4);
    }
  for (y = 0; y < 16; y++)
    for (x = 0; x < 16; x++) {
      dc->color = GrPeek(dc, x + 4, y + 4);
      GrPlot(dc, x + 40, y + 4);
    }
}

U0 RunScene(U8 *name, U0 (*fp)(CRVDC *dc))
{
  CRVDC *dc = SCENE_DC_NEW(SCENE_W, SCENE_H);
  if (!dc) {
    "GRSCENE %s DCNEW-FAILED\n", name;
    return;
  }
  dc->thick = 1;
  (*fp)(dc);
  SceneReport(name, dc);
  DCDel(dc);
}

I64 main()
{
  "GRSCENE-BEGIN w=%d h=%d\n", SCENE_W, SCENE_H;
  RunScene("plot",        &SPlot);
  RunScene("hline",       &SHLine);
  RunScene("line",        &SLine);
  RunScene("line_thick",  &SLineThick);
  RunScene("rect",        &SRect);
  RunScene("circle",      &SCircle);
  RunScene("fill_circle", &SFillCircle);
  RunScene("flood_fill",  &SFloodFill);
  RunScene("tri",         &STri);
  RunScene("blot",        &SBlot);
  RunScene("print",       &SPrint);
  RunScene("fill",        &SFill);
  RunScene("peek_write",  &SPeekWrite);
  "GRSCENE-END\n";
  return 0;
}
