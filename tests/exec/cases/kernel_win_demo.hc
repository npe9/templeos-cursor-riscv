// TempleOS-style WinMgr DocTerm on 32-bpp FB: Adam + Term + HOME.DD → ramfb.
// UART prints pixel hash for headless CI (`make kernel-win-smoke`).
// Soft Adam boot (like interactive) so Term RVKSpawn + DocWrite/MenuFile work.
#include "/Kernel/Kernel_RV.PRJ"
U0 RVWinSmokeAdamBoot()
{
  CTask *adam = 0x86900000;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400;
  heap_end = 0x86000000;
  CBlkPool *bp = 0x86800000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  CHeapCtrl *ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah;
  adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0);
  adam->task_signature = TASK_SIGNATURE_VAL;
  adam->addr = adam;
  CCPU *gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVYieldInit(&Fs);
  RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);
}

I64 main()
{
  I64 h, before, mn, sz = 0;
  CDoc *wd;
  U8 *saved, *menu_dd;
  CTask *tt;
  RVWinSmokeAdamBoot;
  RVKernelInit();
  RVMountRAMDisk('A', 4096);
  rv_sys_gr_force = 1;
  if (!RVGrInit()) {
    Print("RVWinMgr init FAIL (Gr)\n");
    return 1;
  }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB);
  if (!RVWinMgrInit()) {
    Print("RVWinMgr init FAIL\n");
    return 1;
  }
  if (!RVWinMgrDemoDesktop()) {
    Print("RVWinMgr desktop FAIL\n");
    return 1;
  }
  if (!DocPut() || !DocDisplay() || !DocBorder()) {
    Print("RVWinMgr DocTerm docs FAIL put=%d display=%d border=%d\n", DocPut() != NULL, DocDisplay() != NULL, DocBorder() != NULL);
    return 1;
  }
  // P1 Term live RVKSpawn: MsgPutKey must consume via GetMsg path.
  if (rv_winmgr.term_idx < 0 || !TaskValidate(rv_winmgr.wins[rv_winmgr.term_idx].task)) {
    Print("RVWinMgr Term live FAIL no task\n");
    return 1;
  }
  tt = rv_winmgr.wins[rv_winmgr.term_idx].task;
  WinFocus(tt);
  before = rv_winmgr.msg_consumed;
  RVWinMsgPutKey('z', 0);
  RVWinMsgPutKey(8, 0);
  if (rv_winmgr.msg_consumed <= before) {
    Print("RVWinMgr Term live_msg FAIL consumed=%d→%d\n", before, rv_winmgr.msg_consumed);
    return 1;
  }
  Print("RVWinMgr Term live_msg ok consumed=%d\n", rv_winmgr.msg_consumed);
  // Stock MassSpring is Demo/Games/MassSpring.HC (ODE smoke); Adam no longer embeds RVODE clone.
  Print("MassSpring stock via Demo/Games/MassSpring.HC (see kernel-ode-smoke)\n");
  wd = DocNew("A:/HOME_OUT.DD");
  if (!wd) {
    Print("RVDoc Write FAIL DocNew\n");
    return 1;
  }
  DocPutS(wd, "$$TX,\"write-lite\"$$\n");
  DocRecalc(wd);
  if (!DocWrite(wd)) {
    Print("RVDoc Write FAIL\n");
    DocDel(wd);
    return 1;
  }
  DocDel(wd);
  saved = FileRead("A:/HOME_OUT.DD", &sz);
  if (!saved || sz < 4) {
    Print("RVDoc Write readback FAIL sz=%d\n", sz);
    Free(saved);
    return 1;
  }
  Free(saved);
  Print("RVDoc Write ok sz=%d\n", sz);
  menu_dd = "Win {\n  TileHorz(,1);\n}\nHelp {\n  About(,5);\n}\n";
  FileWrite("A:/PersonalMenu.DD", menu_dd, StrLen(menu_dd));
  mn = RVMenuFile("A:/PersonalMenu.DD");
  if (mn < 2) {
    Print("RVMenuFile FAIL n=%d\n", mn);
    return 1;
  }
  Print("RVMenuFile n=%d\n", mn);
  RVMenuTableLoad;
  RVDocPutS("smoke\n");
  // AC Doc-complete probe (keyword seed + F1 fill-in).
  AutoComplete(ON);
  if (rv_winmgr.term_idx >= 0) {
    RVWinFocus(rv_winmgr.term_idx);
    RVWinBodyPutChar('P');
    RVWinBodyPutChar('r');
    RVWinBodyPutChar('i');
    ACFillIn(1);
  }
  Print("RVAC words=%d fills=%d refresh=%d\n", ac.num_words, rv_ac_fill_hits, rv_ac_refresh_hits);
  RVWinMgrRefresh();
  h = RVFbHash() & 0xFFFFFFFF;
  Print("RVWinMgr smoke hash=0x%08X present=%d backend=%d %dx%d wins=%d cols=%d rows=%d term=%d home=%d put=%d\n", h, rv_fb.present_ok, rv_fb.backend, rv_fb.width, rv_fb.height, rv_winmgr.n_wins, rv_winmgr.cols, rv_winmgr.rows, rv_winmgr.term_idx, rv_winmgr.home_idx, DocPut() != NULL);
  return 0;
}
