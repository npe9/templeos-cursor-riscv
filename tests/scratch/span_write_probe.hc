#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"

I64 main()
{
  CTask *adam;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  CMathODE *o;
  U8 *name;
  adam = 0x86900000;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400;
  heap_end = 0x86000000;
  bp = 0x86800000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah;
  adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0);
  adam->task_signature = TASK_SIGNATURE_VAL;
  adam->addr = adam;
  QueInit(&adam->next_ode);
  QueInit(&adam->next_ctrl);
  gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVKernelInit();
  RVMountRAMDisk('A', 4096);
  DefineLstLoad("ST_SPAN_MODES", "Mass\0Concrete\0Steel\0Wire\0Move\0Delete\0");
  if (!RVGrInit(800, 600) || !RVWinMgrInit()) {
    Print("W FAIL init\n");
    return 1;
  }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB);
  RVYieldInit(&Fs);
  adam->put_doc = DocNew;
  adam->display_doc = adam->put_doc;
  blkdev.home_dir = "A:/Home";
  Print("W1\n");
  DirMk("A:/Home");
  Print("W2\n");
  DirMk("~/Span");
  Print("W3 FileWrite A\n");
  FileWrite("A:/Span/Game.DATA", "SPAN", 4);
  Print("W4 FileWrite tilde\n");
  FileWrite("~/Span/Game.DATA", "SPAN", 4);
  Print("W5 PopUpFileName\n");
  name = PopUpFileName("~/Span/Game.DATA");
  Print("W6 name=%s\n", name);
  FileWrite(name, "SPAN", 4);
  Print("W7 after name write\n");
  Free(name);
  Print("W8 SpanNew\n");
  o = SpanNew;
  Print("W9 bridge\n");
  SpanBridge1Init(o);
  Print("W10 SpanWrite\n");
  SpanWrite(o);
  Print("W11 done\n");
  SpanDel(o);
  Print("W ok\n");
  return 0;
}
