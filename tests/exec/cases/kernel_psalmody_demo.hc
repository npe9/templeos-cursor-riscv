// Stock Apps/Psalmody via Load.HC + WinMgr GetMsg live (beyond API-only smoke).
// Host $IB staff fixture remains the ib=3 oracle (Draw imgs ABS_ADDR still soft).
#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Psalmody/Load.HC"
#include "/tests/exec/fixtures/ib_staff_embed.HC"
CTask *g_psm_live_fs;
I64 g_psm_live_msgs;
I64 g_psm_live_notes;
U0 PsalmodyLivePump(U8 *unused)
{
  I64 i;
  no_warn unused;
  for (i = 0; i < 8; i++)
    Yield;
  if (g_psm_live_fs) {
    // Staff region click (below menu chrome) — PlaceNote-shaped via msg.
    TaskMsg(g_psm_live_fs, NULL, MSG_MS_L_DOWN, 80, 4 * FONT_HEIGHT, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_psm_live_fs, NULL, MSG_KEY_DOWN, CH_SHIFT_ESC, 0, 0);
    for (i = 0; i < 2; i++)
      Yield;
    TaskMsg(g_psm_live_fs, NULL, MSG_KEY_UP, CH_SHIFT_ESC, 0, 0);
  }
  while (TRUE)
    Yield;
}

I64 PsalmodyLiveGetMsgLoop()
{
  //Stock Psalmody GetMsg mask under Yield+pump (not full Psalmody() UI).
  CTask *pump;
  CCtrl *tempo;
  PsmNote *tmpn;
  I64 msg, a1, a2, mask, idx, n_msg = 0, before;
  if (!rv_winmgr.ready)
    return -1;
  RVYieldInit(&Fs);
  g_psm_live_fs = Fs;
  MemSet(&psm, 0, sizeof(PsmCtrl));
  psm.head.next = psm.head.last = &psm.head;
  psm.clip.next = psm.clip.last = &psm.clip;
  psm.cur_note = &psm.head;
  psm.dc2 = DCAlias;
  idx = RVWinNew(2, 70, 2, 40, "Psalmody", "", TRUE);
  if (idx >= 0) {
    RVWinBindTask(idx, Fs, RV_WIN_KIND_USER, FALSE);
    RVWinFocus(idx);
  }
  sys_focus_task = Fs;
  MenuPush("File {" "  Abort(,CH_SHIFT_ESC);" "  Exit(,CH_ESC);" "}");
  tempo = TempoNew;
  if (!tempo) {
    Print("RVPsalmody live Tempo FAIL\n");
    return 0;
  }
  before = 0;
  tmpn = psm.head.next;
  while (tmpn != &psm.head) {
    before++;
    tmpn = tmpn->next;
  }
  pump = Spawn(&PsalmodyLivePump, NULL, "PsmPump",, Fs);
  if (!pump) {
    Print("RVPsalmody live Spawn FAIL\n");
    return 0;
  }
  Print("RVPsalmody live enter\n");
  mask = 1 << MSG_KEY_DOWN | 1 << MSG_KEY_UP | 1 << MSG_MS_L_DOWN | 1 << MSG_MS_L_UP | 1 << MSG_MS_MOVE | 1 << MSG_CMD;
  try {
    while (TRUE) {
      msg = GetMsg(&a1, &a2, mask);
      n_msg++;
      switch (msg) {
        case MSG_MS_L_DOWN :
        //Stock-ish note insert at click (PsalmodyMain PickNoteBox shape, no drag).
        tmpn = CAlloc(sizeof(PsmNote));
        tmpn->type = PSMT_NOTE;
        tmpn->ona = Note2Ona(3, 4);
        tmpn->duration = 6;
        QueIns(tmpn, psm.head.last);
        psm.cur_note = tmpn->next;
        break;
        case MSG_KEY_DOWN :
        if (a1 == CH_SHIFT_ESC || a1 == CH_ESC)
          goto psm_live_done;
        break;
      }
      if (n_msg > 32)
        goto psm_live_done;
    }
    psm_live_done:
    GetMsg(,, 1 << MSG_KEY_UP);
  } catch
    PutExcept;
  Print("RVPsalmody live exit\n");
  g_psm_live_msgs = n_msg;
  g_psm_live_notes = 0;
  tmpn = psm.head.next;
  while (tmpn != &psm.head) {
    g_psm_live_notes++;
    tmpn = tmpn->next;
  }
  g_psm_live_notes -= before;
  Kill(pump, FALSE);
  TempoDel(tempo);
  MenuPop;
  PsmSongDel(&psm.head);
  DCDel(psm.dc2);
  psm.dc2 = NULL;
  if (g_psm_live_notes < 1 || g_psm_live_msgs < 2) {
    Print("RVPsalmody live FAIL notes=%d msgs=%d\n", g_psm_live_notes, g_psm_live_msgs);
    return 0;
  }
  return g_psm_live_notes;
}

I64 main()
{
  I64 ona, note, oct, live;
  CCtrl *tempo;
  CMenu *m;
  CMenuEntry *ent;
  CTask *adam;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
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
    Print("RVPsalmody init FAIL\n");
    return 1;
  }
  RVFbSetPresent(RV_FB_PRESENT_RAMFB);
  if (!RVWinMgrInit()) {
    Print("RVPsalmody WinMgr FAIL\n");
    return 1;
  }
  IbStaffInit;
  if (!g_ib_staff) {
    Print("RVPsalmody IB FAIL null\n");
    return 1;
  }
  // Psalmody BI=15 head is SPT_THICK (3) — prove host $IB carried trailer bytes.
  if (g_ib_staff[0] != 3) {
    Print("RVPsalmody IB FAIL first=%d\n", g_ib_staff[0]);
    return 1;
  }
  ona = Note2Ona(3, 4);
  note = Ona2Note(ona);
  oct = Ona2Octave(ona);
  if (ona != 51 || note != 3 || oct != 4) {
    Print("RVPsalmody Note2Ona FAIL ona=%d note=%d oct=%d\n", ona, note, oct);
    return 1;
  }
  MusicSettingsRst;
  Play("5qC");
  Snd(ona);
  Snd(0);
  m = MenuPush("File {" "  Open(,1);" "  Help(,2);" "}");
  if (!m) {
    Print("RVPsalmody MenuPush FAIL\n");
    return 1;
  }
  ent = MenuEntryFind(m, "File/Open");
  if (!ent) {
    Print("RVPsalmody MenuEntryFind FAIL\n");
    return 1;
  }
  tempo = TempoNew;
  if (!tempo) {
    Print("RVPsalmody TempoNew FAIL\n");
    return 1;
  }
  PopUpPickDir("~/Psalmody");
  PopUpEd("::/Apps/Psalmody/Help.DD", Fs);
  Print("RVPsalmody smoke ona=%d play=%d rst=%d menu=%d tempo=%d popup_file=%d ib=%d\n", ona, rv_snd_play_hits, rv_snd_rst_hits, ent->arg1, !!tempo, rv_popup_file_hits, g_ib_staff[0]);
  TempoDel(tempo);
  MenuPop;
  live = PsalmodyLiveGetMsgLoop;
  if (live < 1) {
    Print("RVPsalmody live FAIL live=%d notes=%d msgs=%d\n", live, g_psm_live_notes, g_psm_live_msgs);
    return 1;
  }
  Print("RVPsalmody live ok live=%d notes=%d msgs=%d\n", live, g_psm_live_notes, g_psm_live_msgs);
  return 0;
}
