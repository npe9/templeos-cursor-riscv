// kernel_phase3_demo.hc — RVKMain phase 3 smoke:
// Kernel + Load(Compiler.BIN seed) → guest MakeOS(Cmp) →
// RedSea Kernel.BIN seed (FileFind+Load) → StartOS Loads Runtime BINs.
// G9: no in-image Compiler_RV_Body / HostBinEmbed — Cmp is loaded seed.
// TempleOS Boot.DD shape (not jit.hc). See templeos-riscv/COMPILER_RV.md.
#define RV_PHASE3 1
#define RV_PHASE3_LOADED_CMP_ONLY 1
#include "/Kernel/Kernel_RV.PRJ"
#include "/Compiler/RISCVRegs.HH"
#include "/Adam/Opt/Boot/MakeAll_RV.HC"
#include "/Kernel/RVCmpImports.HC"
#include "/Kernel/RVCmpRtPatch.HH"
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
