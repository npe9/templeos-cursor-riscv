#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"
CTask *g_fs;
U0 Pump(U8 *u)
{
  I64 i; no_warn u;
  for (i = 0; i < 30; i++) Yield;
  Print("P ESC\n");
  TaskMsg(g_fs, NULL, MSG_KEY_DOWN, CH_ESC, 0, 0);
  for (i = 0; i < 4; i++) Yield;
  TaskMsg(g_fs, NULL, MSG_KEY_UP, CH_ESC, 0, 0);
  Print("P UP\n");
  while (TRUE) Yield;
}
I64 main()
{
  CTask *adam,*pump,*song,*anim; CBlkPool *bp; CHeapCtrl *ah; CCPU *gs;
  CCtrl *bt_run,*bt_mode; CDC *dc; I64 msg,a1,a2,mask,n;
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
  if (!RVGrInit(800, 600) || !RVWinMgrInit()) { Print("H6 FAIL\n"); return 1; }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB); RVYieldInit(&Fs);
  adam->put_doc = DocNew; adam->display_doc = adam->put_doc;
  blkdev.home_dir = "A:/Home"; DirMk("A:/Home");
  g_fs = Fs; sys_focus_task = Fs;
  SettingsPush; WinBorder; WinMax; DocCursor;
  song = Spawn(&SongTask, NULL, "Song",, Fs); Fs->song_task = song;
  bt_run = CtrlBttnNew(0, 0, 80,, 2, "Stopped\0Running\0", run_colors, &run_bttn);
  bt_mode = CtrlBttnNew(0, 3 * FONT_HEIGHT, 80,, MD_MODES_NUM, Define("ST_SPAN_MODES"), mode_colors, &mode_bttn);
  a.saved_ode = NULL; ode = NULL; Init(&a);
  anim = Spawn(&AnimateTask, &a, "Animate",, Fs); Fs->animate_task = anim;
  Fs->draw_it = &DrawIt;
  PopUpOk("h6");
  dc = DCAlias;
  pump = Spawn(&Pump, NULL, "Pump",, Fs);
  Print("H6 loop\n");
  mask = 1 << MSG_MS_L_DOWN | 1 << MSG_MS_R_DOWN | 1 << MSG_MS_L_UP | 1 << MSG_KEY_DOWN | 1 << MSG_MS_MOVE;
  n = 0;
  try {
    while (TRUE) {
      msg = GetMsg(&a1, &a2, mask);
      n++;
      if (msg == MSG_KEY_DOWN && a1 == CH_ESC) {
        Print("H6 ESC save\n");
        if (!SpanTime || !a.saved_ode) {
          Free(a.saved_ode);
          a.saved_ode = SpanSave(ode);
          Print("H6 saved\n");
        }
        Print("H6 re-Init\n");
        Init(&a);
        Print("H6 SpanWrite\n");
        SpanWrite(ode);
        Print("H6 SpanWrite done\n");
        goto done;
      }
      if (msg == MSG_KEY_DOWN && a1 == CH_SHIFT_ESC) goto done;
      if (n > 40) goto done;
    }
    done:
    Print("H6 KEY_UP wait\n");
    GetMsg(,, 1 << MSG_KEY_UP);
    Print("H6 KEY_UP ok\n");
  } catch PutExcept;
  Kill(pump, FALSE); Kill(song, FALSE); Kill(anim, FALSE);
  CtrlBttnDel(bt_run); CtrlBttnDel(bt_mode); SpanDel(ode); DCDel(dc); SettingsPop;
  Print("H6 ok\n"); return 0;
}
