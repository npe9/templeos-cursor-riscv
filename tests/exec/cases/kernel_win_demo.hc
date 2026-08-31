// TempleOS-style WinMgr on 32-bpp FB: text_base windows + borders + draw_it → ramfb.
// UART prints pixel hash for headless CI (`make kernel-win-smoke`).
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  RVKernelInit();
  // Force ramfb present path (smoke always passes -device ramfb).
  rv_sys_gr_force = 1;
  if (!RVGrInit(640, 480)) {
    Print("RVWinMgr init FAIL (Gr)\n");
    return 1;
  }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB);
  if (!RVWinMgrInit()) {
    Print("RVWinMgr init FAIL\n");
    return 1;
  }
  if (!RVWinMgrDemoDesktop()) {
    Print("RVWinMgr desktop FAIL\n");
    return 1;
  }
  RVWinMgrRefresh();
  I64 h = RVFbHash() & 0xFFFFFFFF;
  Print("RVWinMgr smoke hash=0x%08X present=%d backend=%d %dx%d wins=%d cols=%d rows=%d\n", h, rv_fb.present_ok, rv_fb.backend, rv_fb.width, rv_fb.height, rv_winmgr.n_wins, rv_winmgr.cols, rv_winmgr.rows);
  return 0;
}
