#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"
I64 main()
{
  CTask *adam; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs; CMathODE *o; U8 *buf; I64 size;
  adam = 0x86900000; MemSet(adam, 0, sizeof(CTask)); Fs = adam; adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl)); heap_next = 0x82000400; heap_end = 0x86000000;
  bp = 0x86800000; BlkPoolInit(bp, 0x2000); sys_code_bp = bp;
  ah = HeapCtrlInit(NULL, NULL, bp); adam->code_heap = ah; adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192); TaskInit(adam, 0);
  adam->task_signature = TASK_SIGNATURE_VAL; adam->addr = adam;
  QueInit(&adam->next_ode); QueInit(&adam->next_ctrl);
  gs = 0x86A00000; MemSet(gs, 0, sizeof(CCPU)); gs->seth_task = adam; adam->gs = gs; Gs = gs;
  RVKernelInit(); RVMountRAMDisk('A', 4096);
  DefineLstLoad("ST_SPAN_MODES", "Mass\0Concrete\0Steel\0Wire\0Move\0Delete\0");
  if (!RVGrInit(800, 600) || !RVWinMgrInit()) { Print("H2 FAIL\n"); return 1; }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB); RVYieldInit(&Fs);
  adam->put_doc = DocNew; adam->display_doc = adam->put_doc;
  blkdev.home_dir = "A:/Home"; DirMk("A:/Home");
  // Minimal ode without Bridge DocPrint
  o = SpanNew; Print("H2 save\n"); buf = SpanSave(o, &size); Print("H2 size=%d\n", size);
  DirMk("~/Span"); Print("H2 dirmk done\n");
  Print("H2 fw\n"); FileWrite("~/Span/Game.DATA", buf, size); Print("H2 fw done\n");
  Free(buf);
  Print("H2 SpanWrite\n"); SpanWrite(o); Print("H2 SpanWrite done\n");
  SpanDel(o); Print("H2 ok\n"); return 0;
}
