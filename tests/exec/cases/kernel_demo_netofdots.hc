// First stock Demo on RV Gr subset: Demo/Graphics/NetOfDots.HC (DCAlias/GrLine/DocClear).
// Soft PressAKey does not block; UART FB hash oracle.
#include "/Kernel/Kernel_RV.PRJ"
#define RV_NO_DEMO_AUTORUN
#define RV_DEMO_KEEP_FRAME
#include "/Demo/Graphics/NetOfDots.HC"
I64 main()
{
  I64 h;
  RVKernelInit();
  if (!RVGrInit(800, 600)) {
    Print("RVDemo NetOfDots init FAIL\n");
    return 1;
  }
  // Black backdrop so palette RED lines are visible in the hash.
  DCFill(NULL, 0);
  NetOfDots;
  RVGrRefresh();
  h = RVFbHash() & 0xFFFFFFFF;
  Print("RVDemo NetOfDots smoke hash=0x%08X present=%d %dx%d\n", h, rv_fb.present_ok, rv_fb.width, rv_fb.height);
  if (!h) {
    Print("RVDemo NetOfDots FAIL empty frame\n");
    return 1;
  }
  return 0;
}
