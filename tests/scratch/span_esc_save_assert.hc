#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"
CTask *g_fs;
U0 SpanPump(U8 *unused)
{
  I64 i; no_warn unused;
  for (i = 0; i < 24; i++) Yield;
  if (g_fs) {
    mode_bttn.state = MD_MASS;
    TaskMsg(g_fs, NULL, MSG_MS_L_DOWN, 30, 22, 0);
    for (i = 0; i < 8; i++) Yield;
    TaskMsg(g_fs, NULL, MSG_KEY_DOWN, CH_ESC, 0, 0);
    for (i = 0; i < 200; i++) Yield;
    TaskMsg(g_fs, NULL, MSG_KEY_UP, CH_ESC, 0, 0);
  }
  while (TRUE) Yield;
}
I64 main()
{
  CTask *adam, *pump; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs; I64 idx;
  CDirEntry de;
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
  if (!RVGrInit(800, 600) || !RVWinMgrInit()) { Print("ESC FAIL init\n"); return 1; }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB); RVYieldInit(&Fs);
  adam->put_doc = DocNew; adam->display_doc = adam->put_doc;
  blkdev.home_dir = "A:/Home"; DirMk("A:/Home");
  g_fs = Fs; sys_focus_task = Fs;
  idx = RVWinNew(2, 70, 2, 40, "Span", "", TRUE);
  if (idx >= 0) { RVWinBindTask(idx, Fs, RV_WIN_KIND_USER, FALSE); RVWinFocus(idx); }
  pump = Spawn(&SpanPump, NULL, "Pump",, Fs);
  Print("ESC enter paint0=%d\n", rv_refresh_paint_hits);
  Span;
  Print("ESC returned play=%d refresh=%d paint=%d popup=%d\n",
    rv_snd_play_hits, rv_refresh_hits, rv_refresh_paint_hits, rv_popup_file_hits);
  Kill(pump, FALSE);
  MemSet(&de, 0, sizeof(CDirEntry));
  if (!FileFind("A:/Home/Span/Game.DATA", &de) || de.size < 1) {
    Print("ESC save FAIL size=%d\n", de.size);
    Free(de.full_name);
    return 1;
  }
  Print("ESC save ok size=%d paint=%d\n", de.size, rv_refresh_paint_hits);
  Free(de.full_name);
  return 0;
}
