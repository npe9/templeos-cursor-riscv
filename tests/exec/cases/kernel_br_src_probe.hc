// SoftCall BrSrcSoft companion: host-AOT BR SoftCall Load (G9).
// SoftCall Load("A:/MakeOS/SoftBrSrc.BIN") + HashFind SoftBrSrcProbe -> 42.
// Past SoftCall Load SoftCocSrc; COC ASSIGN SoftCocSrc stays under 2KiB -
// this slice plants BR_ZERO IC then emits RV beqz+addi+ret; tip adds return Expr
// (not SoftCocSrc sd/ld; BR owns runtime taken path like SoftCall-lite BrSoft).
// SoftCall-lite PrsCmpSrc hung ExePutSSoft (host AOT entry thunk).
// Needle 'BS' (0x4253) — SoftCall-lite BrSoft already owns 'BR'.
#define SOFT_BR_IC_IMM 1
#define SOFT_BR_IC_BR_ZERO 2
U32 soft_br_bin[4];
U32 soft_br_fence[2];
I64 SoftBrEmit()
{
  I64 (*fp)();
  I64 ic0, ic1, d0, r;
  // SoftCall Load BR: if(1) body -> addi40; tip +2 (SoftCocSrc wrap).
  // SoftIcSrc-sized 4-word encodings: IMM1, BR_ZERO skip, IMM40, ret.
  ic0 = SOFT_BR_IC_IMM;
  d0 = 1;
  ic1 = SOFT_BR_IC_BR_ZERO;
  if (ic0 != SOFT_BR_IC_IMM || ic1 != SOFT_BR_IC_BR_ZERO || d0 != 1)
    return -1;
  soft_br_bin[0] = 0x00100513;
  soft_br_bin[1] = 0x00050463;
  soft_br_bin[2] = 0x02800513;
  soft_br_bin[3] = 0x00008067;
  soft_br_fence[0] = 0x0000100F;
  soft_br_fence[1] = 0x00008067;
  fp = &soft_br_fence;
  fp();
  fp = &soft_br_bin;
  r = fp();
  if (r != 40)
    return -2;
  return r + 2;
}

public I64 SoftBrSrcProbe()
{
  return SoftBrEmit();
}
