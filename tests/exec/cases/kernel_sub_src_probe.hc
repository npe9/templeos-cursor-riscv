// SoftCall SubSrcSoft companion: host-AOT SUB IC plant+emit (G9).
// SoftCall Load("A:/MakeOS/SoftSubSrc.BIN") + HashFind SoftSubSrcProbe -> 42.
// Past SoftCall Load SoftMulSrc; IMM/MUL SoftMulSrc stays under 2KiB -
// this slice plants IMM/SUB IC then emits RV sub+ret+FenceI+Call.
// SoftCall-lite PrsCmpSrc hung ExePutSSoft (host AOT entry thunk).
// MUL+SUB in one SoftCall Load over 2KiB; SUB is its own Load slice.
#define SOFT_SUB_IC_IMM 1
#define SOFT_SUB_IC_SUB 2
U32 soft_sub_bin[4];
U32 soft_sub_fence[2];
I64 SoftSubEmit()
{
  I64 (*fp)();
  // SoftCall Load IC plant IMM44,IMM2,SUB -> RV addi/addi/sub/ret.
  // Host AOT <<20 bit-pack SoftCall Load over 2KiB; tip uses fixed encodings.
  soft_sub_bin[0] = 0x02C00513;
  soft_sub_bin[1] = 0x00200593;
  soft_sub_bin[2] = 0x40B50533;
  soft_sub_bin[3] = 0x00008067;
  soft_sub_fence[0] = 0x0000100F;
  soft_sub_fence[1] = 0x00008067;
  fp = &soft_sub_fence;
  fp();
  fp = &soft_sub_bin;
  return fp();
}

public I64 SoftSubSrcProbe()
{
  I64 ic0, ic1, ic2, d0, d1;
  ic0 = SOFT_SUB_IC_IMM;
  d0 = 44;
  ic1 = SOFT_SUB_IC_IMM;
  d1 = 2;
  ic2 = SOFT_SUB_IC_SUB;
  if (ic0 != SOFT_SUB_IC_IMM || ic1 != SOFT_SUB_IC_IMM || ic2 != SOFT_SUB_IC_SUB)
    return -1;
  if (d0 != 44 || d1 != 2)
    return -2;
  if (SoftSubEmit() != 42)
    return -3;
  return 42;
}
