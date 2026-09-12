#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Psalmody/Load.HC"
I64 main() {
  CTask *adam=0x86900000; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs;
  CDoc *doc; CDocEntry *se; I64 sz, h0, h1;
  MemSet(adam,0,sizeof(CTask)); Fs=adam; adam_task=adam;
  MemSet(the_heap,0,sizeof(CHeapCtrl)); heap_next=0x82000400; heap_end=0x86000000;
  bp=0x86800000; BlkPoolInit(bp,0x800); sys_code_bp=bp;
  ah=HeapCtrlInit(NULL,NULL,bp); adam->code_heap=ah; adam->data_heap=ah;
  MemSet(SYS_FIXED_AREA,0,8192); TaskInit(adam,0);
  adam->task_signature=TASK_SIGNATURE_VAL; adam->addr=adam;
  QueInit(&adam->next_ode); QueInit(&adam->next_ctrl);
  gs=0x86A00000; MemSet(gs,0,sizeof(CCPU)); gs->seth_task=adam; adam->gs=gs; Gs=gs;
  RVKernelInit;
  if (!RVGrInit(640,480)) { Print("BI17 FAIL gr\n"); return 1; }
  Print("BI17 step gr\n");
  sz = SpriteSize($IB,"<17>",BI=17$);
  Print("BI17 step size=%d\n", sz);
  DCFill(NULL, WHITE);
  h0 = RVFbHash;
  Sprite3(rv_gr.dc, 8, 8, 0, $IB,"<17>",BI=17$);
  h1 = RVFbHash;
  Print("BI17 step sprite3 dhash=%d\n", h0!=h1);
  Fs->put_doc = DocNew;
  Fs->display_doc = Fs->put_doc;
  doc = DocPut;
  Print("BI17 step doc=%d\n", !!doc);
  se = Sprite($IB,"<17>",BI=17$);
  Print("BI17 step DocSprite se=%d\n", !!se);
  Print("BI17 ok size=%d paint=%d\n", sz, h0!=h1);
  return 0;
}
