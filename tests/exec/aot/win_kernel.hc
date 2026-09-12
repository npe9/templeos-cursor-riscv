// Shared win AOT Kernel unit: Kernel_RV + main (no Compiler Body).
// win_i and win_hold both link this single unit; the hold/headless choice
// lives in the tiny win_flag_{i,hold}.hc unit so a Kernel leaf edit costs
// one ~30s compile instead of two. See Makefile WIN_AOT_* and docs/OPS.md.
#define HOLYC_AOT_NO_COMPILER_BODY
#define RV_WIN_HOLD_UNIT
#include "/tests/exec/cases/kernel_win_interactive.hc"
