#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"
CTask *g_fs;
U0 SpanPump(U8 *unused)
{
  I64 i;
  no_warn unused;
  for (i = 0; i < 20; i++)
    Yield;
  Print("PUMP ESC down\n");
  if (g_fs)
    TaskMsg(g_fs, NULL, MSG_KEY_DOWN, CH_ESC, 0, 0);
  // Delay KEY_UP until SpanSave/Init/SpanWrite can finish (stock GetMsg waits KEY_UP).
  for (i = 0; i < 200; i++)
    Yield;
  Print("PUMP ESC up play=%d refresh=%d\n", rv_snd_play_hits, rv_refresh_hits);
  if (g_fs)
    TaskMsg(g_fs, NULL, MSG_KEY_UP, CH_ESC, 0, 0);
  Print("PUMP done\n");
  while (TRUE)
    Yield;
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
  if (!RVGrInit(800, 600) || !RVWinMgrInit()) { Print("ESC init FAIL\n"); return 1; }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB); RVYieldInit(&Fs);
  adam->put_doc = DocNew; adam->display_doc = adam->put_doc;
  blkdev.home_dir = "A:/Home"; DirMk("A:/Home");
  Print("ESC home ok\n");
  g_fs = Fs; sys_focus_task = Fs;
  idx = RVWinNew(2, 70, 2, 40, "Span", "", TRUE);
  if (idx >= 0) { RVWinBindTask(idx, Fs, RV_WIN_KIND_USER, FALSE); RVWinFocus(idx); }
  pump = Spawn(&SpanPump, NULL, "Pump",, Fs);
  Print("ESC enter Span()\n");
  Span;
  Print("ESC Span returned\n");
  Kill(pump, FALSE);
  Print("ESC ok\n");
  return 0;
}
