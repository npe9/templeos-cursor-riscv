#include "/Kernel/Kernel_RV.PRJ"
I64 main() {
  CTask *adam=0x86900000; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs;
  U8 *st; I64 i;
  MemSet(adam,0,sizeof(CTask)); Fs=adam; adam_task=adam;
  MemSet(the_heap,0,sizeof(CHeapCtrl)); heap_next=0x82000400; heap_end=0x86000000;
  bp=0x86800000; BlkPoolInit(bp,0x800); sys_code_bp=bp;
  ah=HeapCtrlInit(NULL,NULL,bp); adam->code_heap=ah; adam->data_heap=ah;
  MemSet(SYS_FIXED_AREA,0,8192); TaskInit(adam,0);
  adam->task_signature=TASK_SIGNATURE_VAL; adam->addr=adam;
  gs=0x86A00000; MemSet(gs,0,sizeof(CCPU)); gs->seth_task=adam; adam->gs=gs; Gs=gs;
  RVKernelInit;
  Print("MSP step init\n");
  for (i=0;i<8;i++) {
    st = MStrPrint("$$SP+LIS,\"\","
      "LM=\"Msg(MSG_KEY_DOWN,0,SCF_CTRL|SC_CURSOR_RIGHT);\",BI=%d$$", i);
    Print("MSP i=%d st=%s\n", i, st ? st : "null");
    Free(st);
  }
  Print("MSP ok\n");
  return 0;
}
