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

I64 main()
{
  I64 n, h, fill, placed, win_placed, pick_ok;
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
  // DirMk("A:/Span") OK in dir-demo / phase3 Soft Call after Yield-skip unlock;
  // still hangs in this WinMgr+Doc put_doc session (Print Make Directory path).
  // Soft-skip; phase3 LiteSpanDir Call is the DirMk proof. Plant at A:/.
  FileWrite("A:/SpanGame.DATA", "SPAN", 4);
  pick = PopUpPickFile("A:");
  pick_ok = pick != NULL;
  if (!pick_ok) {
    Print("RVSpan PopUpPickFile FAIL\n");
    return 1;
  }
  Free(pick);
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
  return 0;
}
