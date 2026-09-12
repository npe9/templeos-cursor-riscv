#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"
I64 main()
{
  CTask *adam,*song,*anim; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs;
  CCtrl *bt_run,*bt_mode; U8 *name,*buf; I64 size; Bool old_silent;
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
  if (!RVGrInit(800, 600) || !RVWinMgrInit()) { Print("H7 FAIL\n"); return 1; }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB); RVYieldInit(&Fs);
  adam->put_doc = DocNew; adam->display_doc = adam->put_doc;
  blkdev.home_dir = "A:/Home"; DirMk("A:/Home");
  // Match stock Span() prelude more closely
  SettingsPush;
  Fs->text_attr = BROWN << 4 + BLACK;
  AutoComplete;
  WinBorder;
  WinMax;
  DocCursor;
  song = Spawn(&SongTask, NULL, "Song",, Fs); Fs->song_task = song;
  bt_run = CtrlBttnNew(0, 0, 80,, 2, "Stopped\0Running\0", run_colors, &run_bttn);
  bt_mode = CtrlBttnNew(0, 3 * FONT_HEIGHT, 80,, MD_MODES_NUM, Define("ST_SPAN_MODES"), mode_colors, &mode_bttn);
  Fs->win_inhibit |= WIG_DBL_CLICK;
  MenuPush(
    "File {"
    "  New(,CH_CTRLN);"
    "  Open(,CH_CTRLO);"
    "  SaveAs(,CH_CTRLA);"
    "  Abort(,CH_SHIFT_ESC);"
    "  Exit(,CH_ESC);"
    "}"
    "Play {"
    "  Restart(,'\n');"
    "  RunStop(,CH_SPACE);"
    "  Mass(,'m');"
    "  Concrete(,'c');"
    "  Steel(,'s');"
    "  Wire(,'w');"
    "  Move(,'v');"
    "  Delete(,'d');"
    "}"
  );
  a.saved_ode = NULL; ode = NULL; Init(&a);
  anim = Spawn(&AnimateTask, &a, "Animate",, Fs); Fs->animate_task = anim;
  Fs->draw_it = &DrawIt;
  PopUpOk("h7");
  Print("H7 SpanWrite body\n");
  old_silent = Silent;
  DirMk("~/Span");
  Silent(old_silent);
  Print("H7 after DirMk\n");
  name = PopUpFileName("~/Span/Game.DATA");
  Print("H7 after PopUp name=%s\n", name);
  buf = SpanSave(ode, &size);
  Print("H7 after SpanSave size=%d\n", size);
  FileWrite(name, buf, size);
  Print("H7 after FileWrite\n");
  Free(buf); Free(name);
  Print("H7 MenuPop\n");
  MenuPop;
  Kill(song, FALSE); Kill(anim, FALSE);
  CtrlBttnDel(bt_run); CtrlBttnDel(bt_mode); SpanDel(ode); SettingsPop;
  Print("H7 ok\n"); return 0;
}
