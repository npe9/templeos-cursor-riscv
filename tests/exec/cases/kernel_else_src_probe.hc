// SoftCall ElseSrcSoft companion: host-AOT if/else JMP join SoftCall Load (G9).
// SoftCall Load("A:/MakeOS/SoftElseSrc.BIN") + HashFind SoftElseSrcProbe -> 42.
// Past SoftCall Load SoftBrSrc; SoftCocSrc tip wrap SoftOptSrc addi42.
// SoftCall-lite JMP=beq x0,x0; needle 'ES' (ElseSoft owns 'EL').
#define SOFT_ES_IMM 1
#define SOFT_ES_BRZ 2
#define SOFT_ES_JMP 3
U32 soft_es_bin[5];
U32 soft_es_fence[2];
I64 SoftElseEmit()
{
  I64 (*fp)();
  I64 ic0, ic1, ic2, d0;
  // if(0) JMP join; else addi42 ret. SoftCall-lite JMP plant.
  ic0 = SOFT_ES_IMM;
  d0 = 0;
  ic1 = SOFT_ES_BRZ;
  ic2 = SOFT_ES_JMP;
  if (ic0 != SOFT_ES_IMM || ic1 != SOFT_ES_BRZ || ic2 != SOFT_ES_JMP || d0 != 0)
    return -1;
  soft_es_bin[0] = 0x00000513;
  soft_es_bin[1] = 0x00050463;
  soft_es_bin[2] = 0x00000463;
  soft_es_bin[3] = 0x02A00513;
  soft_es_bin[4] = 0x00008067;
  soft_es_fence[0] = 0x0000100F;
  soft_es_fence[1] = 0x00008067;
  fp = &soft_es_fence;
  fp();
  fp = &soft_es_bin;
  return fp();
}

public I64 SoftElseSrcProbe()
{
  return SoftElseEmit();
}
