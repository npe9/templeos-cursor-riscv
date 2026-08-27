// The kernel booting ITSELF on RISC-V. main() does nothing but call RVKMain() — the RISC-V analogue
// of KMain() that lives in Kernel/KBootRV.HC. RVKMain sets up the heap, creates Adam, and Spawns and
// schedules the first task using the kernel's OWN BlkPoolInit/HeapCtrlInit/Spawn/TaskInit/Yield. No
// heap wiring, no adam, no Spawn here: if RVKMain could not stand on its own, this would not compile.
// Contrast the other kernel_* demos, whose main() hand-wires adam and drives one subsystem directly;
// this one proves the kernel brings itself up. The banner line is printed by a real CTask that Adam's
// own Spawn() created and the kernel's own scheduler ran.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  RVKMain();
  return 0;
}
