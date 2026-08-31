// kernel_phase3_demo.hc — RVKMain phase 3 smoke:
// Kernel + Compiler_RV → CInit/ExePutS → Load(CBinFile) → guest MakeOS(Cmp) →
// guest Runtime BINs → StartOS Loads StartOS+Seed+Svc+Kern.
// TempleOS Boot.DD shape (not jit.hc). See templeos-riscv/COMPILER_RV.md.
#define RV_PHASE3 1
#include "/Kernel/Kernel_RV.PRJ"
#include "/Compiler/RISCVRegs.HH"
#include "/Compiler/Compiler_RV_Body.PRJ"
#include "/Adam/MakeAdam_RV_Core.HC"
#include "/Adam/Opt/Boot/MakeAll_RV.HC"
#include "/Kernel/RVCmpImports.HC"
#include "/Kernel/RVCmpRtPatch.HH"
#include "/Kernel/RVHostBinEmbed.HC"
#include "/Kernel/RVPhase3.HC"
I64 main()
{
  RVKMain;
  if (!rv_phase3_compiler_ok || !rv_phase3_load_ok || !rv_phase3_startos_ok)
    return 1;
  if (!rv_phase3_makeos_ok || !rv_phase3_runtime_ok)
    return 2;
  return 0;
}
