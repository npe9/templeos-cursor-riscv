// Probe: stock Span() under Yield+pump — UART last line on hang.
#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"

CTask *g_fs;

U0 SpanPump(U8 *unused)
{
  I64 i;
  no_warn unused;
  for (i = 0; i < 16; i++)
    Yield;
  Print("PUMP start play=%d refresh=%d\n", rv_snd_play_hits, rv_refresh_hits);
  if (g_fs) {
    mode_bttn.state = MD_MASS;
    TaskMsg(g_fs, NULL, MSG_MS_L_DOWN, 24, 18, 0);
    for (i = 0; i < 8; i++)
      Yield;
    TaskMsg(g_fs, NULL, MSG_MS_L_DOWN, 48, 30, 0);
    for (i = 0; i < 8; i++)
      Yield;
    TaskMsg(g_fs, NULL, MSG_KEY_DOWN, CH_SHIFT_ESC, 0, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_fs, NULL, MSG_KEY_UP, CH_SHIFT_ESC, 0, 0);
  }
  Print("PUMP done\n");
  while (TRUE)
    Yield;
}

I64 main()
{
  CTask *adam, *pump;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  I64 idx;
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
  if (!RVGrInit(800, 600)) {
    Print("FULL init FAIL\n");
    return 1;
  }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB);
  if (!RVWinMgrInit()) {
    Print("FULL WinMgr FAIL\n");
    return 1;
  }
  RVYieldInit(&Fs);
  adam->put_doc = DocNew;
  adam->display_doc = adam->put_doc;
  g_fs = Fs;
  sys_focus_task = Fs;
  idx = RVWinNew(2, 70, 2, 40, "Span", "", TRUE);
  if (idx >= 0) {
    RVWinBindTask(idx, Fs, RV_WIN_KIND_USER, FALSE);
    RVWinFocus(idx);
  }
  Print("FULL before pump\n");
  pump = Spawn(&SpanPump, NULL, "Pump",, Fs);
  Print("FULL enter Span()\n");
  Span;
  Print("FULL Span returned play=%d refresh=%d\n", rv_snd_play_hits, rv_refresh_hits);
  Kill(pump, FALSE);
  Print("FULL ok\n");
  return 0;
}
