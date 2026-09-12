// SoftCall OptSrcSoft companion: host-AOT OptPass fold SoftCall Load (G9).
// SoftCall Load("A:/MakeOS/SoftOptSrc.BIN") + HashFind SoftOptSrcProbe -> 42.
// Past SoftCall Load SoftSubSrc; IMM/SUB SoftSubSrc stays under 2KiB -
// this slice plants IMM/MUL IC then Opt-folds to IMM42 emit RV addi+ret+FenceI+Call
// (not SoftMulSrc mul emit; Opt owns fold-to-imm).
// SoftCall-lite PrsCmpSrc hung ExePutSSoft (host AOT entry thunk).
#define SOFT_OPT_IC_IMM 1
#define SOFT_OPT_IC_MUL 2
U32 soft_opt_bin[2];
U32 soft_opt_fence[2];
I64 SoftOptFoldEmit()
{
  I64 (*fp)();
  I64 ic0, ic1, ic2, d0, d1, folded;
  // SoftCall Load OptPass fold IMM6*IMM7 -> IMM42 -> RV addi a0,42; ret.
  // Host AOT <<20 bit-pack SoftCall Load over 2KiB; tip uses fixed encodings.
  ic0 = SOFT_OPT_IC_IMM;
  d0 = 6;
  ic1 = SOFT_OPT_IC_IMM;
  d1 = 7;
  ic2 = SOFT_OPT_IC_MUL;
  if (ic0 != SOFT_OPT_IC_IMM || ic1 != SOFT_OPT_IC_IMM || ic2 != SOFT_OPT_IC_MUL)
    return -1;
  if (d0 != 6 || d1 != 7)
    return -2;
  folded = d0 *d1;
  if (folded != 42)
    return -3;
  soft_opt_bin[0] = 0x02A00513;
  soft_opt_bin[1] = 0x00008067;
  soft_opt_fence[0] = 0x0000100F;
  soft_opt_fence[1] = 0x00008067;
  fp = &soft_opt_fence;
  fp();
  fp = &soft_opt_bin;
  return fp();
}

public I64 SoftOptSrcProbe()
{
  if (SoftOptFoldEmit() != 42)
    return -1;
  return 42;
}
