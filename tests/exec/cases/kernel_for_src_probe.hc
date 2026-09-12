// SoftCall ForSrcSoft companion: host-AOT for-loop SoftCall Load (G9).
// SoftCall Load("A:/MakeOS/SoftForSrc.BIN") + HashFind SoftForSrcProbe -> 42.
// Past SoftCall Load SoftElseSrc; SoftElseSrc tip wrap stays under 2KiB -
// this slice plants the for IC slot layout (init IMM / cond / BR_ZERO exit /
// step / JMP back / ret) then emits RV addi+addi+beqz+addi+JMP+ret and Calls it,
// so the loop counts 40->42 at runtime (not plant-fold like SoftOptSrc).
// SoftCall-lite JMP back = beq x0,x0,-12; needle 'FS' (ForSoft owns 'FR').
// SoftCall-lite PrsCmpSrc hung ExePutSSoft (host AOT entry thunk) - Load slice instead.
// IC slot indices (const-folded - no tip code budget).
#define SOFT_FS_IMM 0
#define SOFT_FS_COND 1
#define SOFT_FS_BRZ 2
#define SOFT_FS_STEP 3
#define SOFT_FS_JMP 4
#define SOFT_FS_RET 5
U32 soft_fs_bin[6];
U32 soft_fs_fence[2];
I64 SoftForEmit()
{
  I64 (*fp)();
  // for(x=40;x-42;x=x+1); return x -> runtime loop, a0 ends 42.
  soft_fs_bin[SOFT_FS_IMM] = 0x02800513;
  soft_fs_bin[SOFT_FS_COND] = 0xFD650293;
  soft_fs_bin[SOFT_FS_BRZ] = 0x00028663;
  soft_fs_bin[SOFT_FS_STEP] = 0x00150513;
  soft_fs_bin[SOFT_FS_JMP] = 0xFE000AE3;
  soft_fs_bin[SOFT_FS_RET] = 0x00008067;
  soft_fs_fence[0] = 0x0000100F;
  soft_fs_fence[1] = 0x00008067;
  fp = &soft_fs_fence;
  fp();
  fp = &soft_fs_bin;
  return fp();
}

public I64 SoftForSrcProbe()
{
  return SoftForEmit();
}
