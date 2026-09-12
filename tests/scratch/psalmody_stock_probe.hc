// Scratch: stock Psalmody() under Yield+WinMgr pump.
#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Psalmody/Load.HC"
#include "/tests/exec/fixtures/ib_staff_embed.HC"

CTask *g_psm_fs;
I64 g_psm_notes;
I64 g_psm_rec;
I64 g_psm_rc;

U0 PsalmodyStockPump(U8 *unused)
{
  I64 i, rx;
  PsmNote *tmpn;
  no_warn unused;
  for (i = 0; i < 32; i++)
    Yield;
  if (g_psm_fs) {
    TaskMsg(g_psm_fs, NULL, MSG_KEY_DOWN, 'z', 0, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_psm_fs, NULL, MSG_KEY_UP, 'z', 0, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_psm_fs, NULL, MSG_KEY_DOWN, 'h', 0, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_psm_fs, NULL, MSG_KEY_UP, 'h', 0, 0);
    for (i = 0; i < 8; i++)
      Yield;
    g_psm_notes = 0;
    tmpn = psm.head.next;
    while (tmpn != &psm.head) {
      g_psm_notes++;
      tmpn = tmpn->next;
    }
    if (psm.record_entry)
      g_psm_rec = !!psm.record_entry->checked;
    // PsmFindNote walks by x; click the note's x (not staff mid) or it returns &psm.head.
    tmpn = psm.head.next;
    rx = 8;
    if (tmpn != &psm.head) {
      PsmRecalcNoteXY;
      rx = tmpn->x;
    }
    DocEdKeyInjectClear;
    for (i = 0; i < 1 + 7 + 6; i++)
      DocEdKeyInject('\t');
    DocEdKeyInject('\n');
    TaskMsg(g_psm_fs, NULL, MSG_MS_R_UP, rx, 4 * FONT_HEIGHT, 0);
    for (i = 0; i < 16; i++)
      Yield;
    DocEdKeyInjectClear;
    g_psm_rc = 1;
    tmpn = psm.head.next;
    if (tmpn != &psm.head && tmpn->duration == 6)
      g_psm_rc = 6;
    TaskMsg(g_psm_fs, NULL, MSG_KEY_DOWN, CH_SHIFT_ESC, 0, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_psm_fs, NULL, MSG_KEY_UP, CH_SHIFT_ESC, 0, 0);
  }
  while (TRUE)
    Yield;
}

I64 main()
{
  CTask *adam, *pump;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  I64 idx, ref0;
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
  if (!RVGrInit(640, 480)) {
    Print("PsmStock init FAIL\n");
    return 1;
  }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB);
  if (!RVWinMgrInit()) {
    Print("PsmStock WinMgr FAIL\n");
    return 1;
  }
  IbStaffInit;
  Print("PsmStock winmgr\n");
  RVYieldInit(&Fs);
  g_psm_fs = Fs;
  if (!Fs->put_doc)
    Fs->put_doc = DocNew;
  Fs->display_doc = Fs->put_doc;
  idx = RVWinNew(2, 70, 2, 40, "Psalmody", "", TRUE);
  if (idx >= 0) {
    RVWinBindTask(idx, Fs, RV_WIN_KIND_USER, FALSE);
    RVWinFocus(idx);
  }
  sys_focus_task = Fs;
  ms.pos_text.y = 4;
  ms.pos.y = 4 * FONT_HEIGHT;
  ref0 = rv_refresh_hits;
  Print("PsmStock spawn\n");
  pump = Spawn(&PsalmodyStockPump, NULL, "PsmStockPump",, Fs);
  if (!pump) {
    Print("PsmStock Spawn FAIL\n");
    return 1;
  }
  Print("PsmStock enter\n");
  Psalmody("A:/Home/Psalmody");
  Print("PsmStock exit refresh=%d rec=%d notes=%d rc=%d\n",
	rv_refresh_hits - ref0, g_psm_rec, g_psm_notes, g_psm_rc);
  Kill(pump, FALSE);
  Print("PsmStock ok\n");
  return 0;
}
