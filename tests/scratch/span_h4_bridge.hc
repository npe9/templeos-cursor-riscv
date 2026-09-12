#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"
I64 main()
{
  CTask *adam; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs; CMathODE *o; CCtrl *bt_run,*bt_mode; CTask *song;
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
  if (!RVGrInit(800, 600) || !RVWinMgrInit()) { Print("H4 FAIL\n"); return 1; }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB); RVYieldInit(&Fs);
  adam->put_doc = DocNew; adam->display_doc = adam->put_doc;
  SettingsPush; WinBorder(OFF); WinMax; DocCursor;
  Print("H4 Song\n");
  song = Spawn(&SongTask, NULL, "Song",, Fs); Fs->song_task = song;
  bt_run = CtrlBttnNew(0, 0, 80,, 2, "Stopped\0Running\0", run_colors, &run_bttn);
  bt_mode = CtrlBttnNew(0, 3 * FONT_HEIGHT, 80,, MD_MODES_NUM, Define("ST_SPAN_MODES"), mode_colors, &mode_bttn);
  Print("H4 Init\n");
  a.saved_ode = NULL; a.elapsed_t = 0; ode = NULL;
  Init(&a); // stock Init = SpanDel+SpanNew+Refresh+Bridge
  Print("H4 InitDone play=%d refresh=%d\n", rv_snd_play_hits, rv_refresh_hits);
  Kill(song, FALSE);
  CtrlBttnDel(bt_run); CtrlBttnDel(bt_mode); SpanDel(ode); SettingsPop;
  Print("H4 ok\n"); return 0;
}
