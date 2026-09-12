#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"
CTask *g_fs;
U0 Pump(U8 *u)
{
  I64 i; no_warn u;
  for (i = 0; i < 24; i++) Yield;
  TaskMsg(g_fs, NULL, MSG_KEY_DOWN, CH_SHIFT_ESC, 0, 0);
  for (i = 0; i < 200; i++) Yield;
  TaskMsg(g_fs, NULL, MSG_KEY_UP, CH_SHIFT_ESC, 0, 0);
  while (TRUE) Yield;
}
I64 main()
{
  CTask *adam, *pump; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs; I64 idx;
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
  if (!RVGrInit(800, 600) || !RVWinMgrInit()) { Print("H13 FAIL\n"); return 1; }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB); RVYieldInit(&Fs);
  adam->put_doc = DocNew; adam->display_doc = adam->put_doc;
  g_fs = Fs; sys_focus_task = Fs;
  idx = RVWinNew(2, 70, 2, 40, "S", "", TRUE);
  if (idx >= 0) { RVWinBindTask(idx, Fs, RV_WIN_KIND_USER, FALSE); RVWinFocus(idx); }
  pump = Spawn(&Pump, NULL, "P",, Fs);
  Print("H13 Span enter\n");
  Span;
  Print("H13 Span done\n");
  Kill(pump, FALSE);
  Print("H13 before home DirMk\n");
  blkdev.home_dir = "A:/Home";
  DirMk("A:/Home");
  Print("H13 after home DirMk\n");
  Print("H13 ok\n");
  return 0;
}
