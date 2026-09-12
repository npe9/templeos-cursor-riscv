// kernel_thin_loader_demo.hc — G9 thin loader smoke:
// Embed Kernel.BIN @0x81000000 → export-only LoadBufLite → HashAdd →
// HashFind("KernelEntry") → Call. SoftCall owns virtio remount + FS/Load ENTER;
// KernelEntry (STAY) then HLT. No RVThinVirtioBlk/RVRedSeaRaw chicken-egg.
// RVThinLoader.HC is pulled in by Kernel_RV.PRJ under RV_THIN_LOADER (before RVKMain).
#define RV_THIN_LOADER 1
#define RV_THIN_EMBED_BIN 1
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  RVKMain;
  // Jump KernelEntry never returns when Stay holds; unreachable = FAIL.
  if (!rv_thin_loader_ok)
    return 1;
  return 2;
}
