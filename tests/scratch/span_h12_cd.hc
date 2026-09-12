#include "/Kernel/Kernel_RV.PRJ"
U0 Spin(U8 *u) { no_warn u; while (TRUE) Yield; }
I64 main()
{
  CTask *adam,*s,*a; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs;
  adam = 0x86900000; MemSet(adam, 0, sizeof(CTask)); Fs = adam; adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl)); heap_next = 0x82000400; heap_end = 0x86000000;
  bp = 0x86800000; BlkPoolInit(bp, 0x2000); sys_code_bp = bp;
  ah = HeapCtrlInit(NULL, NULL, bp); adam->code_heap = ah; adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192); TaskInit(adam, 0);
  adam->task_signature = TASK_SIGNATURE_VAL; adam->addr = adam;
  QueInit(&adam->next_ode); QueInit(&adam->next_ctrl);
  gs = 0x86A00000; MemSet(gs, 0, sizeof(CCPU)); gs->seth_task = adam; adam->gs = gs; Gs = gs;
  RVKernelInit(); RVMountRAMDisk('A', 4096); RVYieldInit(&Fs);
  blkdev.home_dir = "A:/Home";
  Print("H12 DirMk Home\n"); DirMk("A:/Home");
  Print("H12 DirMk ~/Span\n"); DirMk("~/Span");
  s = Spawn(&Spin, NULL, "S",, Fs); a = Spawn(&Spin, NULL, "A",, Fs);
  Print("H12 Cd A:/Home/Span\n");
  if (!Cd("A:/Home/Span")) Print("H12 Cd abs FAIL\n");
  else Print("H12 Cd abs ok cur=%s\n", Fs->cur_dir);
  Print("H12 Cd ~/Span\n");
  if (!Cd("~/Span")) Print("H12 Cd tilde FAIL\n");
  else Print("H12 Cd tilde ok cur=%s\n", Fs->cur_dir);
  Print("H12 DirContextNew tilde\n");
  if (!DirContextNew("~/Span/Game.DATA", FALSE, TRUE))
    Print("H12 dirc tilde FAIL\n");
  else Print("H12 dirc tilde ok\n");
  Print("H12 DirContextNew abs\n");
  if (!DirContextNew("A:/Home/Span/Game.DATA", FALSE, TRUE))
    Print("H12 dirc abs FAIL\n");
  else Print("H12 dirc abs ok\n");
  Kill(s, FALSE); Kill(a, FALSE);
  Print("H12 ok\n"); return 0;
}
