// Stock Demo/Graphics/Blot.HC on RV Gr: FloodFill3 + brush + GrLine3 + Refresh shim.
// Soft PressAKey / RV_DEMO_KEEP_FRAME; UART FB hash oracle.
#include "/Kernel/Kernel_RV.PRJ"
#define RV_NO_DEMO_AUTORUN
#define RV_DEMO_KEEP_FRAME
#include "/Demo/Graphics/Blot.HC"
I64 main()
{
  I64 h, fill_n, color;
  CTaskSettings *se;
  RVKernelInit();
  if (!RVGrInit(800, 600)) {
    Print("RVDemo Blot init FAIL\n");
    return 1;
  }
  // Prove SettingsPush / WinMax / PopUpColor / Refresh shims (Speedline surface).
  se = SettingsPush;
  WinBorder(OFF);
  WinMax;
  color = PopUpColor;
  if (color < 0) {
    Print("RVDemo Blot FAIL PopUpColor\n");
    return 1;
  }
  ms.speed = 40.0;
  // Non-zero speed for Speedline thick path readiness.
  Refresh;
  SettingsPop;
  DCFill(NULL, 0);
  Blot;
  RVGrRefresh();
  h = RVFbHash() & 0xFFFFFFFF;
  Print("RVDemo Blot smoke hash=0x%08X present=%d %dx%d settings=%d winmax=%d color=%d refresh=%d\n", h, rv_fb.present_ok, rv_fb.width, rv_fb.height, rv_settings_push_hits, rv_winmax_hits, rv_popup_color_hits, rv_refresh_hits);
  if (!h) {
    Print("RVDemo Blot FAIL empty frame\n");
    return 1;
  }
  if (rv_settings_push_hits < 1 || rv_winmax_hits < 1 || rv_popup_color_hits < 1 || rv_refresh_hits < 1) {
    Print("RVDemo Blot FAIL shim hits settings=%d winmax=%d color=%d refresh=%d\n", rv_settings_push_hits, rv_winmax_hits, rv_popup_color_hits, rv_refresh_hits);
    return 1;
  }
  no_warn fill_n;
  no_warn se;
  return 0;
}
