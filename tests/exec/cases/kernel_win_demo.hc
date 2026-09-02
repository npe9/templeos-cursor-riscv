// TempleOS-style WinMgr DocTerm on 32-bpp FB: Adam + Term + HOME.DD → ramfb.
// UART prints pixel hash for headless CI (`make kernel-win-smoke`).
// No RedSea here (keeps smoke light); HOME.DD uses Doc-lite fallback body.
// Interactive path mounts A: and loads real HOME.DD — see kernel_win_interactive.hc.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  RVKernelInit();
  // Force ramfb present path (smoke always passes -device ramfb).
  rv_sys_gr_force = 1;
  if (!RVGrInit()) {
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
  if (!DocPut() || !DocDisplay() || !DocBorder()) {
    Print("RVWinMgr DocTerm docs FAIL put=%d display=%d border=%d\n", DocPut() != NULL, DocDisplay() != NULL, DocBorder() != NULL);
    return 1;
  }
  RVDocPutS("smoke\n");
  RVWinMgrRefresh();
  I64 h = RVFbHash() & 0xFFFFFFFF;
  Print("RVWinMgr smoke hash=0x%08X present=%d backend=%d %dx%d wins=%d cols=%d rows=%d term=%d home=%d put=%d\n", h, rv_fb.present_ok, rv_fb.backend, rv_fb.width, rv_fb.height, rv_winmgr.n_wins, rv_winmgr.cols, rv_winmgr.rows, rv_winmgr.term_idx, rv_winmgr.home_idx, DocPut() != NULL);
  return 0;
}
