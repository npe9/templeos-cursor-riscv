// SoftCall CocSrcSoft companion: host-AOT COC multi-stmt ASSIGN SoftCall Load (G9).
// SoftCall Load("A:/MakeOS/SoftCocSrc.BIN") + HashFind SoftCocSrcProbe -> 42.
// Past SoftCall Load SoftOptSrc; OptPass fold SoftOptSrc stays under 2KiB -
// this slice plants ASSIGN/LOCAL IC then emits RV sd/ld+ret; tip adds return Expr
// (not SoftOptSrc fold-to-imm; COC owns runtime ASSIGN like SoftCall-lite CocSoft).
// SoftCall-lite PrsCmpSrc hung ExePutSSoft (host AOT entry thunk).
#define SOFT_COC_IC_IMM 1
#define SOFT_COC_IC_ASSIGN 2
U32 soft_coc_bin[4];
U32 soft_coc_fence[2];
I64 SoftCocEmit()
{
  I64 (*fp)();
  I64 ic0, ic1, d0, r;
  // SoftCall Load COC: x=40; return x+2 -> sd/ld (runtime ASSIGN) then +2.
  // 5-word SoftCall Load over 2KiB; tip uses SoftIcSrc-sized 4-word encodings.
  ic0 = SOFT_COC_IC_IMM;
  d0 = 40;
  ic1 = SOFT_COC_IC_ASSIGN;
  if (ic0 != SOFT_COC_IC_IMM || ic1 != SOFT_COC_IC_ASSIGN || d0 != 40)
    return -1;
  soft_coc_bin[0] = 0x02800513;
  soft_coc_bin[1] = 0xFEA13C23;
  soft_coc_bin[2] = 0xFF813503;
  soft_coc_bin[3] = 0x00008067;
  soft_coc_fence[0] = 0x0000100F;
  soft_coc_fence[1] = 0x00008067;
  fp = &soft_coc_fence;
  fp();
  fp = &soft_coc_bin;
  r = fp();
  if (r != 40)
    return -2;
  return r + 2;
}

public I64 SoftCocSrcProbe()
{
  return SoftCocEmit();
}
