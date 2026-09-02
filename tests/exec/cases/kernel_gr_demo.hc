// Phase F Gr/WinMgr-lite smoke: CRVDC draws + soft terminal on native 32-bpp FB.
// Uses GrPlot/GrRect/GrLine/GrPrint and RVGrRefresh → RVFbPresent; UART hash oracle.
#include "/Kernel/Kernel_RV.PRJ"
U0 DrawIt(CRVDC *dc)
{
  //Minimal draw_it: window chrome + geometry on the screen DC.
  RVWinFill(16, 16, 360, 200, RV_RGB(32, 40, 56), RV_RGB(96, 112, 144), "RVGr demo");
  dc->color = RV_RGB(220, 48, 48);
  GrRect(dc, 40, 56, 80, 48);
  dc->color = RV_RGB(48, 200, 72);
  GrRect(dc, 100, 80, 80, 48);
  dc->color = RV_RGB(72, 144, 255);
  GrRect(dc, 70, 104, 80, 48);
  dc->color = RV_RGB(255, 220, 64);
  dc->thick = 2;
  GrLine(dc, 40, 180, 340, 60);
  dc->thick = 1;
  dc->color = RVColor(WHITE);
  GrPrint(dc, 40, 170, "GrPlot/Line/Rect");
  GrPlot(dc, 200, 120);
  GrPlot(dc, 201, 121);
  GrPlot(dc, 202, 122);
}

I64 main()
{
  RVKernelInit();
  if (!RVGrInit(800, 600)) {
    Print("RVGr init FAIL\n");
    return 1;
  }
  // Soft terminal in the lower band (leave upper area for draw_it geometry).
  rv_term.rows = 8;
  rv_term.cols = 60;
  rv_term.ox = 16;
  rv_term.oy = 400;
  rv_term.fg = RVColor(WHITE);
  rv_term.bg = RV_RGB(24, 48, 96);
  RVTermClear();
  RVTermPutS("TempleOS/RV soft term\n");
  RVTermPutS("RVGrRefresh -> RVFbPresent\n");
  RVGrSetDrawIt(&DrawIt);
  RVGrRefresh();
  I64 h = RVFbHash() & 0xFFFFFFFF;
  Print("RVGr smoke hash=0x%08X present=%d backend=%d %dx%d term=%dx%d\n", h, rv_fb.present_ok, rv_fb.backend, rv_fb.width, rv_fb.height, rv_term.cols, rv_term.rows);
  return 0;
}
