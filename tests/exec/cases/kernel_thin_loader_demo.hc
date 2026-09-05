// kernel_thin_loader_demo.hc — G9 thin loader smoke:
// RVKMain mounts virtio RedSea → Load A:/Kernel/Kernel.BIN → Call KernelEntry.
// No Cmp / MakeOS / StartOS. Proves boot handoff into RedSea Kernel.BIN
// (milestone toward dropping Mac phase3.elf as forever scaffold).
// Kernel.BIN is still a probe module (not full Kernel_RV) — see COMPILER_RV.md.
#define RV_THIN_LOADER 1
#include "/Kernel/Kernel_RV.PRJ"
#include "/Kernel/RVThinLoader.HC"
I64 main()
{
  RVKMain;
  if (!rv_thin_loader_ok)
    return 1;
  return 0;
}
