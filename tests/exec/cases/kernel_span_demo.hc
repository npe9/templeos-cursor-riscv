// Stock Apps/Span via Load.HC (Cd(__DIR__) + relative includes).
// Proves host __DIR__/StreamDir builtins + soft pre-init Cd; WinMgr→GetMsg PlaceMass;
// FilesFind PopUpPickFile (FileMgr GetMsg still open).
#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Span/Load.HC"
I64 SpanCountMasses()
{
  I64 n = 0, guard = 0;
  MyMass *tmpm;
  if (!ode)
    return 0;
  tmpm = ode->next_mass(MyMass *);
  while (tmpm != &ode->next_mass) {
    n++;
    tmpm = tmpm->next(MyMass *);
    if (!tmpm || ++guard > 4096)
      break;
  }
  return n;
}

I64 SpanGetMsgProbe()
{
  //Pre-queue MSG_MS_L_DOWN like WinMgr→TaskMsg; GetMsg returns without Yield.
  I64 msg, a1 = -1, a2 = -1, before;
  before = SpanCountMasses;
  mode_bttn.state = MD_MASS;
  TaskMsg(Fs, NULL, MSG_MS_L_DOWN, 120, 80, 0);
  msg = GetMsg(&a1, &a2, 1 << MSG_MS_L_DOWN | 1 << MSG_MS_R_DOWN | 1 << MSG_MS_L_UP | 1 << MSG_KEY_DOWN | 1 << MSG_MS_MOVE);
  if (msg != MSG_MS_L_DOWN)
    return 0;
  PlaceMass(a1, a2);
  return SpanCountMasses - before;
}

I64 SpanWinMgrGetMsgProbe()
{
  //Stock Span() GetMsg shape under WinMgr: bind Fs win, PostMs, GetMsg, PlaceMass, ESC.
  I64 msg, a1 = -1, a2 = -1, before, idx, mask;
  if (!rv_winmgr.ready)
    return -1;
  idx = RVWinNew(2, 70, 2, 40, "Span", "", TRUE);
  if (idx < 0)
    return 0;
  RVWinBindTask(idx, Fs, RV_WIN_KIND_USER, FALSE);
  RVWinFocus(idx);
  sys_focus_task = Fs;
  before = SpanCountMasses;
  mode_bttn.state = MD_MASS;
  mask = 1 << MSG_MS_L_DOWN | 1 << MSG_MS_R_DOWN | 1 << MSG_MS_L_UP | 1 << MSG_KEY_DOWN | 1 << MSG_MS_MOVE;
  RVWinMgrPostMs(MSG_MS_L_DOWN, 18, 12);
  msg = GetMsg(&a1, &a2, mask);
  if (msg != MSG_MS_L_DOWN)
    return 0;
  PlaceMass(a1, a2);
  TaskMsg(Fs, NULL, MSG_KEY_DOWN, CH_ESC, 0, 0);
  msg = GetMsg(&a1, &a2, mask);
  if (msg != MSG_KEY_DOWN || a1 != CH_ESC)
    return 0;
  return SpanCountMasses - before;
}
CTask *g_span_live_fs;
I64 g_span_live_msgs;
I64 g_span_live_placed;
I64 g_span_live_play;
U0 SpanLivePump(U8 *unused)
{
  //Feed TaskMsg while live GetMsg blocks (Yield pump).
  I64 i;
  no_warn unused;
  for (i = 0; i < 8; i++)
    Yield;
  if (g_span_live_fs) {
    mode_bttn.state = MD_MASS;
    TaskMsg(g_span_live_fs, NULL, MSG_MS_L_DOWN, 24, 18, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_span_live_fs, NULL, MSG_MS_L_DOWN, 48, 30, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_span_live_fs, NULL, MSG_KEY_DOWN, CH_SHIFT_ESC, 0, 0);
    for (i = 0; i < 2; i++)
      Yield;
    TaskMsg(g_span_live_fs, NULL, MSG_KEY_UP, CH_SHIFT_ESC, 0, 0);
  }
  while (TRUE)
    Yield;
}

I64 SpanStockLiveLoop()
{
  //Stock Span() GetMsg shape under Yield+pump (kept as live needle).
  // Full Span() Song/Animate is SpanStockFull below.
  CTask *pump;
  CCtrl *bt_run, *bt_mode;
  CDC *dc;
  I64 msg, a1, a2, before, mask, idx, n_msg = 0;
  if (!rv_winmgr.ready)
    return -1;
  RVYieldInit(&Fs);
  g_span_live_fs = Fs;
  g_span_live_msgs = 0;
  g_span_live_placed = 0;
  g_span_live_play = 0;
  if (!Fs->put_doc)
    Fs->put_doc = DocNew;
  Fs->display_doc = Fs->put_doc;
  idx = RVWinNew(2, 70, 2, 40, "SpanLive", "", TRUE);
  if (idx >= 0) {
    RVWinBindTask(idx, Fs, RV_WIN_KIND_USER, FALSE);
    RVWinFocus(idx);
  }
  sys_focus_task = Fs;
  SettingsPush;
  WinBorder(OFF);
  WinMax;
  DocCursor;
  bt_run = CtrlBttnNew(0, 0, 80,, 2, "Stopped\0Running\0", run_colors, &run_bttn);
  bt_mode = CtrlBttnNew(0, 3 * FONT_HEIGHT, 80,, MD_MODES_NUM, Define("ST_SPAN_MODES"), mode_colors, &mode_bttn);
  if (!bt_run || !bt_mode) {
    Print("RVSpan live CtrlBttn FAIL\n");
    return 0;
  }
  ode = SpanNew;
  if (!ode) {
    Print("RVSpan live SpanNew FAIL\n");
    return 0;
  }
  SpanBridge1Init(ode);
  mode_bttn.state = MD_MASS;
  Fs->draw_it = &DrawIt;
  dc = DCAlias;
  before = SpanCountMasses;
  pump = Spawn(&SpanLivePump, NULL, "SpanPump",, Fs);
  if (!pump) {
    Print("RVSpan live Spawn FAIL\n");
    return 0;
  }
  Print("RVSpan live enter\n");
  mask = 1 << MSG_MS_L_DOWN | 1 << MSG_MS_R_DOWN | 1 << MSG_MS_L_UP | 1 << MSG_KEY_DOWN | 1 << MSG_MS_MOVE;
  try {
    while (TRUE) {
      msg = GetMsg(&a1, &a2, mask);
      n_msg++;
      switch (msg) {
        case MSG_MS_L_DOWN :
        if (mode_bttn.state == MD_MASS)
          PlaceMass(a1, a2);
        break;
        case MSG_KEY_DOWN :
        if (a1 == CH_SHIFT_ESC || a1 == CH_ESC)
          goto span_live_done;
        break;
      }
      if (n_msg > 32)
        goto span_live_done;
    }
    span_live_done:
    GetMsg(,, 1 << MSG_KEY_UP);
  } catch
    PutExcept;
  Print("RVSpan live exit\n");
  g_span_live_msgs = n_msg;
  g_span_live_placed = SpanCountMasses - before;
  Kill(pump, FALSE);
  CtrlBttnDel(bt_run);
  CtrlBttnDel(bt_mode);
  SpanDel(ode);
  ode = NULL;
  DCFill(dc);
  DCDel(dc);
  SettingsPop;
  Fs->draw_it = NULL;
  if (g_span_live_placed < 1 || g_span_live_msgs < 2) {
    Print("RVSpan live FAIL placed=%d msgs=%d\n", g_span_live_placed, g_span_live_msgs);
    return 0;
  }
  return g_span_live_placed;
}

U0 SpanFullPump(U8 *unused)
{
  //Stock Span() Song+Animate under Yield: PlaceMass then ESC save + KEY_UP.
  I64 i;
  no_warn unused;
  for (i = 0; i < 24; i++)
    Yield;
  if (g_span_live_fs) {
    mode_bttn.state = MD_MASS;
    TaskMsg(g_span_live_fs, NULL, MSG_MS_L_DOWN, 30, 22, 0);
    for (i = 0; i < 8; i++)
      Yield;
    TaskMsg(g_span_live_fs, NULL, MSG_KEY_DOWN, CH_ESC, 0, 0);
    // Delay KEY_UP until SpanSave/Init/SpanWrite finish (stock GetMsg waits KEY_UP).
    for (i = 0; i < 200; i++)
      Yield;
    TaskMsg(g_span_live_fs, NULL, MSG_KEY_UP, CH_ESC, 0, 0);
  }
  while (TRUE)
    Yield;
}

I64 SpanStockFull()
{
  //Stock Apps/Span Span() — SongTask+AnimateTask+PopUpOk+GetMsg under Yield pump.
  // ESC exit exercises DirMk("~/Span") / FileWrite Game.DATA (SHIFT_ESC is live path).
  // Soft Refresh H2: Animate=ODEsUpdate only; non-Animate paints when !rv_dirc_depth;
  // SpanSave holds ODEF_BUSY so ESC save and paint/ODE coexist.
  CTask *pump;
  CDirEntry de;
  I64 idx, play0, ref0, paint0, popup0, sz;
  if (!rv_winmgr.ready)
    return 0;
  RVYieldInit(&Fs);
  g_span_live_fs = Fs;
  sys_focus_task = Fs;
  if (!Fs->put_doc)
    Fs->put_doc = DocNew;
  Fs->display_doc = Fs->put_doc;
  blkdev.home_dir = "A:/Home";
  DirMk("A:/Home");
  idx = RVWinNew(2, 70, 2, 40, "SpanFull", "", TRUE);
  if (idx >= 0) {
    RVWinBindTask(idx, Fs, RV_WIN_KIND_USER, FALSE);
    RVWinFocus(idx);
  }
  play0 = rv_snd_play_hits;
  ref0 = rv_refresh_hits;
  paint0 = rv_refresh_paint_hits;
  popup0 = rv_popup_file_hits;
  MemSet(&de, 0, sizeof(CDirEntry));
  pump = Spawn(&SpanFullPump, NULL, "SpanFullPump",, Fs);
  if (!pump) {
    Print("RVSpan full Spawn FAIL\n");
    return 0;
  }
  Print("RVSpan full enter\n");
  Span;
  Print("RVSpan full exit play=%d refresh=%d paint=%d\n", rv_snd_play_hits - play0, rv_refresh_hits - ref0, rv_refresh_paint_hits - paint0);
  Kill(pump, FALSE);
  if (rv_snd_play_hits <= play0 && rv_refresh_hits <= ref0) {
    Print("RVSpan full FAIL no Song/Animate activity\n");
    return 0;
  }
  if (rv_refresh_paint_hits <= paint0) {
    Print("RVSpan full FAIL no Animate ODE/paint (paint=%d)\n", rv_refresh_paint_hits - paint0);
    return 0;
  }
  if (rv_popup_file_hits <= popup0) {
    Print("RVSpan save FAIL no PopUpFileName\n");
    return 0;
  }
  if (!FileFind("A:/Home/Span/Game.DATA", &de) || de.size < 1) {
    Print("RVSpan save FAIL FileFind size=%d\n", de.size);
    Free(de.full_name);
    return 0;
  }
  sz = de.size;
  Free(de.full_name);
  Print("RVSpan save ok size=%d path=A:/Home/Span/Game.DATA\n", sz);
  return 1;
}

I64 main()
{
  I64 n, h, fill, placed, win_placed, pick_ok, live, full;
  CCtrl *bt_run, *bt_mode;
  CDC *dc;
  CTask *adam;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  U8 *fn, *pick;
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
  // No RVYieldInit: GetMsg uses pre-queued msgs (no Yield). Live Span()+WinMgrTask
  // Yield pump still open.
  RVKernelInit();
  RVMountRAMDisk('A', 4096);
  // Span.HH DefineLstLoad runs pre-hash; re-plant after Kernel define table is up.
  DefineLstLoad("ST_SPAN_MODES", "Mass\0Concrete\0Steel\0Wire\0Move\0Delete\0");
  if (!RVGrInit(800, 600)) {
    Print("RVSpan init FAIL\n");
    return 1;
  }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB);
  if (!RVWinMgrInit()) {
    Print("RVSpan WinMgr FAIL\n");
    return 1;
  }
  DCFill(NULL, 0);
  SettingsPush;
  WinBorder(OFF);
  WinMax;
  DocCursor;
  // Catch SpanBridge $$BG scenery in a Doc (not UART spam).
  adam->put_doc = DocNew;
  adam->display_doc = adam->put_doc;
  ode = SpanNew;
  if (!ode) {
    Print("RVSpan SpanNew FAIL\n");
    return 1;
  }
  SpanBridge1Init(ode);
  n = SpanCountMasses;
  if (n < 15) {
    Print("RVSpan Bridge FAIL masses=%d (want>=15)\n", n);
    return 1;
  }
  bt_run = CtrlBttnNew(0, 0, 80,, 2, "Stopped\0Running\0", run_colors, &run_bttn);
  bt_mode = CtrlBttnNew(0, 3 * FONT_HEIGHT, 80,, MD_MODES_NUM, Define("ST_SPAN_MODES"), mode_colors, &mode_bttn);
  if (!bt_run || !bt_mode) {
    Print("RVSpan CtrlBttn FAIL\n");
    return 1;
  }
  placed = SpanGetMsgProbe;
  if (placed < 1) {
    Print("RVSpan GetMsg FAIL placed=%d\n", placed);
    return 1;
  }
  win_placed = SpanWinMgrGetMsgProbe;
  if (win_placed < 1) {
    Print("RVSpan WinMgr GetMsg FAIL placed=%d\n", win_placed);
    return 1;
  }
  // Plant + FilesFind first-file for pick= (avoid PopUpPickFile PopUp/ExePrint —
  // sibling FileMgr GetMsg soft-reap wedged later live Yield).
  FileWrite("A:/SpanGame.DATA", "SPAN", 4);
  
  {
    CDirEntry *de, *tmp;
    de = FilesFind("A:/*", 0);
    pick = NULL;
    tmp = de;
    while (tmp) {
      if (!(tmp->attr & RS_ATTR_DIR) && tmp->full_name && *tmp->full_name) {
        pick = StrNew(tmp->full_name);
        break;
      }
      tmp = tmp->next;
    }
    if (de)
      DirTreeDel(de);
  }
  pick_ok = pick != NULL;
  if (!pick_ok) {
    Print("RVSpan PopUpPickFile FAIL\n");
    return 1;
  }
  Free(pick);
  // PopUp() waits on its servant with JobResGet's `while (!DONE) Yield;`, so the
  // scheduler has to be up by here — the setup above runs deliberately without it
  // (pre-queued GetMsg), and without this the wait spins forever.
  RVYieldInit(&Fs);
  fn = PopUpFileName("~/Span/Game.DATA");
  if (!fn) {
    Print("RVSpan PopUpFileName FAIL\n");
    return 1;
  }
  Free(fn);
  dc = DCAlias;
  DrawIt(Fs, dc);
  RVGrRefresh;
  h = RVFbHash() & 0xFFFFFFFF;
  // Flood probe on a cleared patch — DrawIt mass fills can cover (40,40).
  dc->color = 0;
  GrRect(dc, 700, 500, 80, 80);
  dc->color = YELLOW;
  GrCircle(dc, 740, 540, 8);
  fill = GrFloodFill(dc, 740, 540, TRUE);
  n = SpanCountMasses;
  Print("RVSpan smoke masses=%d flood=%d hash=0x%08X bttn=%d settings=%d popup_ok=%d getmsg=%d win_getmsg=%d popup_file=%d pick=%d\n", n, fill, h, rv_ctrls_n, rv_settings_push_hits, rv_popup_ok_hits, placed, win_placed, rv_popup_file_hits, pick_ok);
  if (!h || fill < 1) {
    Print("RVSpan smoke FAIL hash/flood\n");
    return 1;
  }
  CtrlBttnDel(bt_run);
  CtrlBttnDel(bt_mode);
  SpanDel(ode);
  ode = NULL;
  DCDel(dc);
  SettingsPop;
  // Stock Span() live GetMsg under Yield+WinMgr pump (SHIFT_ESC exit; no DirMk save).
  live = SpanStockLiveLoop;
  if (live < 1) {
    Print("RVSpan live FAIL live=%d placed=%d msgs=%d\n", live, g_span_live_placed, g_span_live_msgs);
    return 1;
  }
  Print("RVSpan live ok live=%d placed=%d msgs=%d\n", live, g_span_live_placed, g_span_live_msgs);
  // Stock Span() Song+Animate with ESC save (DirMk/FileWrite Game.DATA).
  full = SpanStockFull;
  if (full < 1) {
    Print("RVSpan full FAIL play=%d refresh=%d paint=%d\n", rv_snd_play_hits, rv_refresh_hits, rv_refresh_paint_hits);
    return 1;
  }
  Print("RVSpan full ok play=%d refresh=%d paint=%d popup_ok=%d\n", rv_snd_play_hits, rv_refresh_hits, rv_refresh_paint_hits, rv_popup_ok_hits);
  return 0;
}
