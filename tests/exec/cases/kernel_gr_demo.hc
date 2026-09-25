// Phase F / P4 Gr smoke: CRVDC draws + soft term + GrBlot/Circle/clip on 32-bpp FB.
// Uses GrPlot/GrRect/GrLine/GrBlot/GrCircle/GrPrint and RVGrRefresh → RVFbPresent; UART hash oracle.
#include "/Kernel/Kernel_RV.PRJ"
CRVDC *g_img;
U0 DrawIt(CRVDC *dc)
{
  //Minimal draw_it: window chrome + geometry + blot on the screen DC.
  I64 saved_x1, saved_y1, saved_x2, saved_y2;
  RVWinFill(16, 16, 360, 220, DKGRAY, LTGRAY, "RVGr P4");
  // Clip to chrome client so the intentional overflow rect cannot paint the soft term.
  saved_x1 = dc->clip_x1;
  saved_y1 = dc->clip_y1;
  saved_x2 = dc->clip_x2;
  saved_y2 = dc->clip_y2;
  RVDCClipSet(dc, 20, 40, 370, 230);
  dc->color = LTRED;
  GrRect(dc, 40, 56, 80, 48);
  dc->color = LTGREEN;
  GrRect(dc, 100, 80, 80, 48);
  dc->color = LTBLUE;
  GrRect(dc, 70, 104, 80, 48);
  dc->color = YELLOW;
  dc->thick = 2;
  GrLine(dc, 40, 180, 340, 60);
  dc->thick = 1;
  dc->color = WHITE;
  GrCircle(dc, 280, 120, 28);
  if (g_img)
    GrBlot(dc, 300, 150, g_img);
  // Outside clip — must not appear (hash stable vs unclipped magenta).
  dc->color = PURPLE;   //RV_RGB(255,0,255) IS palette 5 exactly
  GrRect(dc, 0, 0, 12, 12);
  dc->color = WHITE;
  GrPrint(dc, 40, 190, "GrPlot/Blot/Circle");
  GrPlot(dc, 200, 120);
  GrPlot(dc, 201, 121);
  GrPlot(dc, 202, 122);
  dc->clip_x1 = saved_x1;
  dc->clip_y1 = saved_y1;
  dc->clip_x2 = saved_x2;
  dc->clip_y2 = saved_y2;
}

I64 main()
{
  I64 x, y;
  RVKernelInit();
  if (!RVGrInit(800, 600)) {
    Print("RVGr init FAIL\n");
    return 1;
  }
  g_img = RVDCNew(24, 24);
  if (g_img) {
    RVDCFill(g_img, RV_TRANSPARENT);
    g_img->color = BROWN;
    for (y = 0; y < 24; y++)
      for (x = 0; x < 24; x++)
        if (AbsI64(x - 12) + AbsI64(y - 12) < 10)
          GrPlot(g_img, x, y);
  }
  // Soft terminal in the lower band (leave upper area for draw_it geometry).
  rv_term.rows = 8;
  rv_term.cols = 60;
  rv_term.ox = 16;
  rv_term.oy = 400;
  rv_term.fg = RVColor(WHITE);
  rv_term.bg = BLUE;
  RVTermClear();
  RVTermPutS("TempleOS/RV soft term\n");
  RVTermPutS("RVGrRefresh -> RVFbPresent\n");
  RVGrSetDrawIt(&DrawIt);
  RVGrRefresh();
  I64 h = RVFbHash() & 0xFFFFFFFF;
  Print("RVGr smoke hash=0x%08X present=%d backend=%d %dx%d term=%dx%d blot=%d\n", h, rv_fb.present_ok, rv_fb.backend, rv_fb.width, rv_fb.height, rv_term.cols, rv_term.rows, g_img != NULL);
  if (g_img)
    RVDCDel(g_img);
  return 0;
}
