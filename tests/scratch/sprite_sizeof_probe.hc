#include "/Kernel/Kernel_RV.PRJ"
I64 main() {
  CTask *adam=0x86900000; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs;
  MemSet(adam,0,sizeof(CTask)); Fs=adam; adam_task=adam;
  MemSet(the_heap,0,sizeof(CHeapCtrl)); heap_next=0x82000400; heap_end=0x86000000;
  bp=0x86800000; BlkPoolInit(bp,0x200); sys_code_bp=bp;
  ah=HeapCtrlInit(NULL,NULL,bp); adam->code_heap=ah; adam->data_heap=ah;
  MemSet(SYS_FIXED_AREA,0,8192); TaskInit(adam,0);
  adam->task_signature=TASK_SIGNATURE_VAL; adam->addr=adam;
  gs=0x86A00000; MemSet(gs,0,sizeof(CCPU)); gs->seth_task=adam; adam->gs=gs; Gs=gs;
  RVKernelInit;
  Print("SPRITE_SZ COLOR=%d DITHER=%d THICK=%d PT=%d LINE=%d CIRCLE=%d BASE=%d TEXT=%d FLOOD=%d\n",
    sizeof(CSpriteColor), sizeof(CSpriteDitherColor), sizeof(CSpriteT),
    sizeof(CSpritePt), sizeof(CSpritePtPt), sizeof(CSpritePtRad),
    sizeof(CSpriteBase), sizeof(CSpritePtStr), sizeof(CSpritePt));
  return 0;
}
