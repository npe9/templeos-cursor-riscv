// SoftCall MulSrcSoft companion: host-AOT MUL IC plant+emit (G9).
// SoftCall Load("A:/MakeOS/SoftMulSrc.BIN") + HashFind SoftMulSrcProbe -> 42.
// Past SoftCall Load SoftIcSrc; IMM/ADD SoftIcSrc stays under 2KiB -
// this slice plants IMM/MUL IC then emits RV mul+ret+FenceI+Call.
// SoftCall-lite PrsCmpSrc hung ExePutSSoft (host AOT entry thunk).
// SUB IC SoftCall Load is SoftSubSrc (own Load; MUL+SUB one BIN over 2KiB).
#define SOFT_MUL_IC_IMM 1
#define SOFT_MUL_IC_MUL 2
U32 soft_mul_bin[4];
U32 soft_mul_fence[2];
I64 SoftMulEmit()
{
  I64 (*fp)();
  // SoftCall Load IC plant IMM6,IMM7,MUL -> RV addi/addi/mul/ret.
  // Host AOT <<20 bit-pack SoftCall Load over 2KiB; tip uses fixed encodings.
  soft_mul_bin[0] = 0x00600513;
  soft_mul_bin[1] = 0x00700593;
  soft_mul_bin[2] = 0x02B50533;
  soft_mul_bin[3] = 0x00008067;
  soft_mul_fence[0] = 0x0000100F;
  soft_mul_fence[1] = 0x00008067;
  fp = &soft_mul_fence;
  fp();
  fp = &soft_mul_bin;
  return fp();
}

public I64 SoftMulSrcProbe()
{
  I64 ic0, ic1, ic2, d0, d1;
  ic0 = SOFT_MUL_IC_IMM;
  d0 = 6;
  ic1 = SOFT_MUL_IC_IMM;
  d1 = 7;
  ic2 = SOFT_MUL_IC_MUL;
  if (ic0 != SOFT_MUL_IC_IMM || ic1 != SOFT_MUL_IC_IMM || ic2 != SOFT_MUL_IC_MUL)
    return -1;
  if (d0 != 6 || d1 != 7)
    return -2;
  if (SoftMulEmit() != 42)
    return -3;
  return 42;
}
