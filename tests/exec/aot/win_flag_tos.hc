// win_tos flag unit: clean interactive boot. Same VT presentation as win_flag_vt
// (variant 2, packed cols/rows), plus bit 32 = "clean" — the harness skips its
// scripted self-test desktop demo and boots straight to the DolDoc REPL prompt.
//   bits 0..7 variant (2=VT), 8..19 cols, 20..31 rows, bit 32 = clean boot.
// run_kernel_tos.sh rewrites the two #defines to match the caller's terminal.
#define RV_VT_COLS 80
#define RV_VT_ROWS 24
I64 RVWinHoldFlag()
{
  return 2 + (RV_VT_COLS << 8) + (RV_VT_ROWS << 20) + (1 << 32);
}
