// Probe: stock Span SongTask+AnimateTask under Yield — find hang UART last line.
#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"

CTask *g_fs;
I64 g_phase;

U0 SpanPump(U8 *unused)
{
  I64 i;
  no_warn unused;
  for (i = 0; i < 8; i++)
    Yield;
  if (g_fs) {
    mode_bttn.state = MD_MASS;
    TaskMsg(g_fs, NULL, MSG_MS_L_DOWN, 24, 18, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_fs, NULL, MSG_KEY_DOWN, CH_SHIFT_ESC, 0, 0);
    for (i = 0; i < 2; i++)
      Yield;
    TaskMsg(g_fs, NULL, MSG_KEY_UP, CH_SHIFT_ESC, 0, 0);
  }
  while (TRUE)
    Yield;
}

I64 main()
{
  CTask *adam, *pump, *song, *anim;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  CCtrl *bt_run, *bt_mode;
  CDC *dc;
  SpanAnimateStruct sa;
  I64 msg, a1, a2, mask, idx, n_msg, stage;
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
    Print("PROBE init FAIL\n");
    return 1;
  }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB);
  if (!RVWinMgrInit()) {
    Print("PROBE WinMgr FAIL\n");
    return 1;
  }
  RVYieldInit(&Fs);
  adam->put_doc = DocNew;
  adam->display_doc = adam->put_doc;
  g_fs = Fs;
  sys_focus_task = Fs;
  stage = 0;
  Print("PROBE s0 yieldok play=%d\n", rv_snd_play_hits);

  // Stage 1: SongTask alone + Yield rounds
  stage = 1;
  Print("PROBE s1 SongSpawn\n");
  song = Spawn(&SongTask, NULL, "Song",, Fs);
  if (!song) {
    Print("PROBE SongSpawn FAIL\n");
    return 1;
  }
  Fs->song_task = song;
  for (n_msg = 0; n_msg < 20; n_msg++)
    Yield;
  Print("PROBE s1 SongRun play=%d\n", rv_snd_play_hits);

  // Stage 2: CtrlBttn + Init (Refresh under Song) — stock Span order
  stage = 2;
  Print("PROBE s2 Init\n");
  SettingsPush;
  WinBorder(OFF);
  WinMax;
  DocCursor;
  bt_run = CtrlBttnNew(0, 0, 80,, 2, "Stopped\0Running\0", run_colors, &run_bttn);
  bt_mode = CtrlBttnNew(0, 3 * FONT_HEIGHT, 80,, MD_MODES_NUM, Define("ST_SPAN_MODES"), mode_colors, &mode_bttn);
  MemSet(&sa, 0, sizeof(SpanAnimateStruct));
  a.saved_ode = NULL;
  a.elapsed_t = 0;
  ode = NULL;
  Init(&a); // Refresh(2) Yields into Song
  Print("PROBE s2 InitDone ode=%d play=%d refresh=%d\n", ode != NULL, rv_snd_play_hits, rv_refresh_hits);

  // Stage 3: AnimateTask
  stage = 3;
  Print("PROBE s3 AnimSpawn\n");
  anim = Spawn(&AnimateTask, &a, "Animate",, Fs);
  if (!anim) {
    Print("PROBE AnimSpawn FAIL\n");
    return 1;
  }
  Fs->animate_task = anim;
  Fs->draw_it = &DrawIt;
  for (n_msg = 0; n_msg < 30; n_msg++)
    Yield;
  Print("PROBE s3 AnimRun play=%d refresh=%d\n", rv_snd_play_hits, rv_refresh_hits);

  // Stage 4: PopUpOk + GetMsg like Span()
  stage = 4;
  Print("PROBE s4 PopUp\n");
  PopUpOk("probe");
  Print("PROBE s4 PopUpDone hits=%d\n", rv_popup_ok_hits);
  idx = RVWinNew(2, 70, 2, 40, "SpanFull", "", TRUE);
  if (idx >= 0) {
    RVWinBindTask(idx, Fs, RV_WIN_KIND_USER, FALSE);
    RVWinFocus(idx);
  }
  pump = Spawn(&SpanPump, NULL, "Pump",, Fs);
  Print("PROBE s4 GetMsgEnter\n");
  mask = 1 << MSG_MS_L_DOWN | 1 << MSG_MS_R_DOWN | 1 << MSG_MS_L_UP | 1 << MSG_KEY_DOWN | 1 << MSG_MS_MOVE;
  n_msg = 0;
  try {
    while (TRUE) {
      msg = GetMsg(&a1, &a2, mask);
      n_msg++;
      if (msg == MSG_MS_L_DOWN && mode_bttn.state == MD_MASS)
        PlaceMass(a1, a2);
      if (msg == MSG_KEY_DOWN && (a1 == CH_SHIFT_ESC || a1 == CH_ESC))
        break;
      if (n_msg > 32)
        break;
    }
    GetMsg(,, 1 << MSG_KEY_UP);
  } catch
    PutExcept;
  Print("PROBE s4 GetMsgExit msgs=%d play=%d refresh=%d\n", n_msg, rv_snd_play_hits, rv_refresh_hits);
  Kill(pump, FALSE);
  Kill(song, FALSE);
  Kill(anim, FALSE);
  CtrlBttnDel(bt_run);
  CtrlBttnDel(bt_mode);
  SpanDel(ode);
  SettingsPop;
  Print("PROBE ok stage=%d\n", stage);
  return 0;
}
