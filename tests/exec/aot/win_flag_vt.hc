// win_vt flag unit: present the desktop to a VT100 over UART instead of a framebuffer.
//
// Geometry is PACKED into the return value rather than exported as extra functions.
// Two additional cross-unit imports (RVWinVtCols/RVWinVtRows) measurably broke the
// shared win Kernel unit: kernel-win-interactive's DocInit_RV hash went cold
// (lex 1 -> 0) purely from their presence. One flag, no new HOFYIMP1 slots.
//
//   bits 0..7   variant: 0 headless proof, 1 FB hold, 2 VT present
//   bits 8..19  text columns
//   bits 20..31 text rows
//
// run_kernel_vt_holyc.sh rewrites the two #defines to match the caller's terminal.
#define RV_VT_COLS 80
#define RV_VT_ROWS 24
I64 RVWinHoldFlag()
{
  return 2 + (RV_VT_COLS << 8) + (RV_VT_ROWS << 20);
}
