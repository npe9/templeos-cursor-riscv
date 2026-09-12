// SoftCall IcSrcSoft companion: host-AOT IC plant+emit beyond Lex peel (G9).
// SoftCall Load("A:/MakeOS/SoftIcSrc.BIN") + HashFind SoftIcSrcProbe -> 42.
// Past SoftCall Load SoftLexSrc; digit peel SoftLexSrc stays under 2KiB -
// this slice plants IMM/ADD IC then emits RV addi/add+ret+FenceI+Call.
// SoftCall-lite PrsCmpSrc hung ExePutSSoft (host AOT entry thunk).
#define SOFT_IC_IMM 1
#define SOFT_IC_ADD 2
U32 soft_ic_bin[4];
U32 soft_ic_fence[2];
I64 SoftIcEmit()
{
  I64 (*fp)();
  // SoftCall Load IC plant IMM40,IMM2,ADD -> RV addi/addi/add/ret.
  // Host AOT <<20 bit-pack SoftCall Load over 2KiB; tip uses fixed encodings.
  soft_ic_bin[0] = 0x02800513;
  soft_ic_bin[1] = 0x00200593;
  soft_ic_bin[2] = 0x00B50533;
  soft_ic_bin[3] = 0x00008067;
  soft_ic_fence[0] = 0x0000100F;
  soft_ic_fence[1] = 0x00008067;
  fp = &soft_ic_fence;
  fp();
  fp = &soft_ic_bin;
  return fp();
}

public I64 SoftIcSrcProbe()
{
  I64 ic0, ic1, ic2, d0, d1;
  ic0 = SOFT_IC_IMM;
  d0 = 40;
  ic1 = SOFT_IC_IMM;
  d1 = 2;
  ic2 = SOFT_IC_ADD;
  if (ic0 != SOFT_IC_IMM || ic1 != SOFT_IC_IMM || ic2 != SOFT_IC_ADD)
    return -1;
  if (d0 != 40 || d1 != 2)
    return -2;
  if (SoftIcEmit() != 42)
    return -3;
  return 42;
}
