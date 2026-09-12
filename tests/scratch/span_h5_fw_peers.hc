#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"
U0 SpinYield(U8 *u) { no_warn u; while (TRUE) Yield; }
I64 main()
{
  CTask *adam; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs; CTask *s,*a;
  adam = 0x86900000; MemSet(adam, 0, sizeof(CTask)); Fs = adam; adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl)); heap_next = 0x82000400; heap_end = 0x86000000;
  bp = 0x86800000; BlkPoolInit(bp, 0x2000); sys_code_bp = bp;
  ah = HeapCtrlInit(NULL, NULL, bp); adam->code_heap = ah; adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192); TaskInit(adam, 0);
  adam->task_signature = TASK_SIGNATURE_VAL; adam->addr = adam;
  QueInit(&adam->next_ode); QueInit(&adam->next_ctrl);
  gs = 0x86A00000; MemSet(gs, 0, sizeof(CCPU)); gs->seth_task = adam; adam->gs = gs; Gs = gs;
  RVKernelInit(); RVMountRAMDisk('A', 4096);
  if (!RVGrInit(800, 600) || !RVWinMgrInit()) { Print("H5 FAIL\n"); return 1; }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB); RVYieldInit(&Fs);
  adam->put_doc = DocNew; adam->display_doc = adam->put_doc;
  blkdev.home_dir = "A:/Home"; DirMk("A:/Home"); DirMk("~/Span");
  Print("H5 spawn peers\n");
  s = Spawn(&SpinYield, NULL, "SongLike",, Fs);
  a = Spawn(&SpinYield, NULL, "AnimLike",, Fs);
  Print("H5 FileWrite\n");
  FileWrite("~/Span/Game.DATA", "SPAN", 4);
  Print("H5 FileWrite done\n");
  Print("H5 DirMk again\n");
  DirMk("~/Span2");
  Print("H5 DirMk done\n");
  Kill(s, FALSE); Kill(a, FALSE);
  Print("H5 ok\n"); return 0;
}
