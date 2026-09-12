#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"
I64 main()
{
  CTask *adam,*song,*anim; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs;
  CCtrl *bt_run,*bt_mode; CDC *dc;
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
  if (!RVGrInit(800, 600) || !RVWinMgrInit()) { Print("H9 FAIL\n"); return 1; }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB); RVYieldInit(&Fs);
  adam->put_doc = DocNew; adam->display_doc = adam->put_doc;
  blkdev.home_dir = "A:/Home"; DirMk("A:/Home");
  SettingsPush; AutoComplete; WinBorder; WinMax; DocCursor;
  song = Spawn(&SongTask, NULL, "Song",, Fs); Fs->song_task = song;
  bt_run = CtrlBttnNew(0, 0, 80,, 2, "Stopped\0Running\0", run_colors, &run_bttn);
  bt_mode = CtrlBttnNew(0, 3 * FONT_HEIGHT, 80,, MD_MODES_NUM, Define("ST_SPAN_MODES"), mode_colors, &mode_bttn);
  MenuPush("File {Exit(,CH_ESC);}");
  a.saved_ode = NULL; ode = NULL; Init(&a);
  anim = Spawn(&AnimateTask, &a, "Animate",, Fs); Fs->animate_task = anim;
  Fs->draw_it = &DrawIt;
  dc = DCAlias;
  PopUpOk("h9");
  Print("H9 ESC-like\n");
  DCFill(dc);
  if (!SpanTime || !a.saved_ode) {
    Free(a.saved_ode);
    a.saved_ode = SpanSave(ode);
    Print("H9 saved1\n");
  }
  Print("H9 Init2\n");
  Init(&a);
  Print("H9 SpanWrite\n");
  SpanWrite(ode);
  Print("H9 SpanWrite done\n");
  MenuPop; Kill(song, FALSE); Kill(anim, FALSE);
  CtrlBttnDel(bt_run); CtrlBttnDel(bt_mode); SpanDel(ode); DCFill(dc); DCDel(dc); SettingsPop;
  Print("H9 ok\n"); return 0;
}
