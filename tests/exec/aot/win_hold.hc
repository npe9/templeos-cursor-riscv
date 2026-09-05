// Incremental win_hold unit: Kernel + main (HOLD); Compiler linked separately.
#define HOLYC_AOT_NO_COMPILER_BODY
#define RV_WIN_HOLD 1
#include "/tests/exec/cases/kernel_win_interactive.hc"
