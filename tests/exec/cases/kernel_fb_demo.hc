// Phase 0–1 framebuffer smoke: soft 32-bpp XRGB buffer + optional QEMU ramfb present.
// Draws colored rects and an 8×8 font string, then prints an FNV-1a hash over UART for CI.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  RVKernelInit();
  if (!RVFbInit(800, 600)) {
    Print("RVFb init FAIL\n");
    return 1;
  }
  RVFbFill(0x00101820);
  // dark blue-gray
  RVFbFillRect(40, 40, 240, 120, 0x00C04040);
  // red-ish
  RVFbFillRect(200, 100, 240, 120, 0x0040C040);
  // green-ish
  RVFbFillRect(120, 160, 240, 120, 0x004040C0);
  // blue-ish
  RVFbPutStr(48, 320, 0x00FFFFFF, "Hello from TempleOS/RV");
  RVFbPutStr(48, 336, 0x00FFE080, "800x600 XR24 ramfb");
  RVFbPresent();
  // configures QEMU -device ramfb when present; soft path always hashed
  I64 h = RVFbHash() & 0xFFFFFFFF;
  Print("RVFb smoke hash=0x%08X present=%d backend=%d %dx%d\n", h, rv_fb.present_ok, rv_fb.backend, rv_fb.width, rv_fb.height);
  return 0;
}
