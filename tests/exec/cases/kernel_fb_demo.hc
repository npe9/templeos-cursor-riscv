// Phase 0–1 framebuffer smoke: soft 32-bpp XRGB buffer + optional QEMU ramfb present.
// Draws colored rects and an 8×8 font string, then prints an FNV-1a hash over UART for CI.
// Also proves RVFbSimpleFbBind → present (soft scanout copy) without virtio-gpu/DRM.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  U32 *scan;
  I64 ok;
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
  // simplefb bind stub: copy soft FB into a second XR24 buffer (board-shaped path).
  scan = 0x86500000;
  // above soft FB @ 0x86100000 (800×600×4 ≈ 1.9MB ends ~0x862D4C00)
  ok = RVFbSimpleFbBind(scan, 800, 600, 0, RV_FB_FOURCC_XR24);
  if (!ok || !RVFbSimpleFbBound()) {
    Print("RVFb simplefb FAIL bind\n");
    return 1;
  }
  RVFbPresent();
  // first pixel should match soft FB after row copy
  if ((scan[0] & 0xFFFFFFFF) != (rv_fb.pixels[0] & 0xFFFFFFFF) || rv_fb.backend != RV_FB_PRESENT_SIMPLEFB || !rv_fb.present_ok) {
    Print("RVFb simplefb FAIL present backend=%d ok=%d pix=0x%08X soft=0x%08X\n", rv_fb.backend, rv_fb.present_ok, scan[0] & 0xFFFFFFFF, rv_fb.pixels[0] & 0xFFFFFFFF);
    return 1;
  }
  Print("RVFb simplefb OK bind=1 present=%d backend=%d first=0x%08X\n", rv_fb.present_ok, rv_fb.backend, scan[0] & 0xFFFFFFFF);
  return 0;
}
