// Stock Apps/Psalmody via Load.HC + WinMgr GetMsg live + Draw $IB imgs + PopUpDuration.
// Host $IB fixture remains ib=3 oracle; psm_duration_imgs prove Draw ABS_ADDR + Sprite3.
#include "/Kernel/Kernel_RV.PRJ"
#include "/tos/Apps/Psalmody/Load.HC"
#include "/tests/exec/fixtures/ib_staff_embed.HC"
CTask *g_psm_live_fs;
I64 g_psm_live_msgs;
I64 g_psm_live_notes;
I64 g_psm_needle_esc;
I64 g_psm_needle_rec;
I64 g_psm_needle_dur;
CTask *g_psm_stock_fs;
I64 g_psm_stock_esc;
I64 g_psm_stock_rec;
I64 g_psm_stock_dur;
I64 g_psm_stock_notes;
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
    // Record toggle ('z') then right-click → PopUpDuration (LE=6).
    TaskMsg(g_psm_live_fs, NULL, MSG_KEY_DOWN, 'z', 0, 0);
    for (i = 0; i < 2; i++)
      Yield;
    TaskMsg(g_psm_live_fs, NULL, MSG_KEY_UP, 'z', 0, 0);
    for (i = 0; i < 2; i++)
      Yield;
    DocEdKeyInjectClear;
    for (i = 0; i < 1 + 7 + 6; i++)
      DocEdKeyInject('\t');
    DocEdKeyInject('\n');
    TaskMsg(g_psm_live_fs, NULL, MSG_MS_R_UP, 80, 4 * FONT_HEIGHT, 0);
    for (i = 0; i < 8; i++)
      Yield;
    DocEdKeyInjectClear;
    TaskMsg(g_psm_live_fs, NULL, MSG_KEY_DOWN, CH_SHIFT_ESC, 0, 0);
    for (i = 0; i < 2; i++)
      Yield;
    TaskMsg(g_psm_live_fs, NULL, MSG_KEY_UP, CH_SHIFT_ESC, 0, 0);
  }
  while (TRUE)
    Yield;
}

I64 PsalmodyDrawUIProbe()
{
  //psm_duration_imgs $IB ABS_ADDR + DrawNote/DrawIt Sprite3 + PopUpDuration DocMenu.
  CDC *dc;
  PsmNote *tmpn;
  I64 i, nnull = 0, first = -1, h0, h1, dur;
  U8 *p;
  MemSet(&psm, 0, sizeof(PsmCtrl));
  psm.head.next = psm.head.last = &psm.head;
  psm.clip.next = psm.clip.last = &psm.clip;
  psm.cur_note = &psm.head;
  psm.dc2 = DCAlias;
  Fs->pix_width = 640;
  Fs->pix_height = 480;
  for (i = 0; i < PSM_DURATIONS_NUM; i++) {
    if (!psm_duration_imgs[i])
      nnull++;
  }
  p = psm_duration_imgs[6];
  if (p)
    first = *p;
  if (nnull || first != 10) {
    Print("RVPsalmody UI FAIL imgs null=%d first=%d\n", nnull, first);
    DCDel(psm.dc2);
    psm.dc2 = NULL;
    return 0;
  }
  dc = DCAlias;
  // Duration $IB bins are COLOR-less LINE streams; DrawIt pens BLACK. WinMgr TextRect /
  // Doc $$BG,WHITE$$ supply a non-black client — probe must too or hash is black-on-black.
  DCFill(dc, WHITE);
  h0 = RVFbHash() & 0xFFFFFFFF;
  DrawNote(dc, 40, 80, 6);
  tmpn = CAlloc(sizeof(PsmNote));
  tmpn->type = PSMT_NOTE;
  tmpn->ona = Note2Ona(3, 4);
  tmpn->duration = 6;
  PsmSetWidth(tmpn);
  QueIns(tmpn, psm.head.last);
  psm.cur_note = tmpn->next;
  PsmRecalcNoteXY;
  DrawIt(Fs, dc);
  h1 = RVFbHash() & 0xFFFFFFFF;
  if (h0 == h1) {
    Print("RVPsalmody UI FAIL DrawIt hash\n");
    DCDel(dc);
    DCDel(psm.dc2);
    psm.dc2 = NULL;
    return 0;
  }
  // PopUpDuration: $$GREEN$$ then 7 action MUs then duration LE=0..; tab to LE=6 + Enter.
  DocEdKeyInjectClear;
  for (i = 0; i < 1 + 7 + 6; i++)
    DocEdKeyInject('\t');
  DocEdKeyInject('\n');
  dur = PopUpDuration;
  DocEdKeyInjectClear;
  // DocSpriteIns play/record shape (PsmMenu Sprite($IB, "$$SP,\"\",LM=\"z\",BI=%d$$")).
  
  {
    CDoc *sdoc;
    CDocEntry *se;
    sdoc = DocNew;
    if (!sdoc) {
      Print("RVPsalmody UI FAIL DocNew Sprite\n");
      PsmSongDel(&psm.head);
      DCDel(dc);
      DCDel(psm.dc2);
      psm.dc2 = NULL;
      return 0;
    }
    se = DocSpriteIns(sdoc, psm_duration_imgs[6], "$$SP,\"\",LM=\"z\",BI=%d$$");
    if (!se || !(se->de_flags & DOCEF_LEFT_MACRO) || !(se->de_flags & DOCEF_HAS_BIN)) {
      Print("RVPsalmody UI FAIL SpriteIns e=%d lm=%d bin=%d\n", !!se, se ? !!(se->de_flags & DOCEF_LEFT_MACRO) : 0, se ? !!(se->de_flags & DOCEF_HAS_BIN) : 0);
      DocDel(sdoc);
      PsmSongDel(&psm.head);
      DCDel(dc);
      DCDel(psm.dc2);
      psm.dc2 = NULL;
      return 0;
    }
    DocDel(sdoc);
  }
  Print("RVPsalmody UI ok imgs=%d first=%d draw=%d dur=%d sprite=1\n", PSM_DURATIONS_NUM - nnull, first, h0 != h1, dur);
  PsmSongDel(&psm.head);
  DCDel(dc);
  DCDel(psm.dc2);
  psm.dc2 = NULL;
  if (dur != 6) {
    Print("RVPsalmody UI FAIL PopUpDuration dur=%d\n", dur);
    return 0;
  }
  return 1;
}

I64 PsalmodyLiveGetMsgLoop()
{
  //Stock Psalmody GetMsg mask under Yield+pump: note click, 'z' record, R_UP PopUpDuration, SHIFT_ESC.
  CTask *pump;
  CCtrl *tempo;
  PsmNote *tmpn;
  CMenuEntry *rec;
  I64 msg, a1, a2, mask, idx, n_msg = 0, before, dur;
  if (!rv_winmgr.ready)
    return -1;
  RVYieldInit(&Fs);
  g_psm_live_fs = Fs;
  g_psm_needle_esc = 0;
  g_psm_needle_rec = 0;
  g_psm_needle_dur = -1;
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
  MenuPush("File {" "  Abort(,CH_SHIFT_ESC);" "  Exit(,CH_ESC);" "}" "Song {" "  Record(,'z');" "}");
  psm.record_entry = MenuEntryFind(Fs->cur_menu, "Song/Record");
  rec = psm.record_entry;
  if (rec)
    rec->checked = FALSE;
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
  mask = 1 << MSG_KEY_DOWN | 1 << MSG_KEY_UP | 1 << MSG_MS_L_DOWN | 1 << MSG_MS_L_UP | 1 << MSG_MS_R_UP | 1 << MSG_MS_MOVE | 1 << MSG_CMD;
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
        case MSG_MS_R_UP :
        //PsmRightClick-shaped: PopUpDuration on cur note (inject LE=6).
        tmpn = psm.head.next;
        if (tmpn != &psm.head) {
          psm.cur_note = tmpn;
          dur = PopUpDuration;
          if (0 <= dur < PSM_DURATIONS_NUM) {
            tmpn->duration = dur;
            g_psm_needle_dur = dur;
          }
        }
        break;
        case MSG_KEY_DOWN :
        if (a1 == 'z') {
          if (rec) {
            if (rec->checked)
              rec->checked = FALSE;
            else
              rec->checked = TRUE;
            g_psm_needle_rec = !!rec->checked;
          }
        } else if (a1 == CH_SHIFT_ESC || a1 == CH_ESC) {
          g_psm_needle_esc = 1;
          goto psm_live_done;
        }
        break;
      }
      if (n_msg > 48)
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
  if (!g_psm_needle_esc || !g_psm_needle_rec || g_psm_needle_dur != 6) {
    Print("RVPsalmody needles FAIL esc=%d rec=%d dur=%d\n", g_psm_needle_esc, g_psm_needle_rec, g_psm_needle_dur);
    return 0;
  }
  Print("RVPsalmody needles ok esc=%d rec=%d dur=%d\n", g_psm_needle_esc, g_psm_needle_rec, g_psm_needle_dur);
  return g_psm_live_notes;
}

U0 PsalmodyStockPump(U8 *unused)
{
  // Drive stock Psalmody(): record 'z', note 'h', right-click→PopUpDuration, SHIFT_ESC.
  I64 i, rx;
  PsmNote *tmpn;
  no_warn unused;
  for (i = 0; i < 32; i++)
    Yield;
  if (g_psm_stock_fs) {
    TaskMsg(g_psm_stock_fs, NULL, MSG_KEY_DOWN, 'z', 0, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_psm_stock_fs, NULL, MSG_KEY_UP, 'z', 0, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_psm_stock_fs, NULL, MSG_KEY_DOWN, 'h', 0, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_psm_stock_fs, NULL, MSG_KEY_UP, 'h', 0, 0);
    for (i = 0; i < 12; i++)
      Yield;
    g_psm_stock_notes = 0;
    tmpn = psm.head.next;
    while (tmpn != &psm.head) {
      g_psm_stock_notes++;
      tmpn = tmpn->next;
    }
    if (psm.record_entry)
      g_psm_stock_rec = !!psm.record_entry->checked;
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
    TaskMsg(g_psm_stock_fs, NULL, MSG_MS_R_UP, rx, 4 * FONT_HEIGHT, 0);
    for (i = 0; i < 16; i++)
      Yield;
    DocEdKeyInjectClear;
    g_psm_stock_dur = -1;
    tmpn = psm.head.next;
    if (tmpn != &psm.head)
      g_psm_stock_dur = tmpn->duration;
    TaskMsg(g_psm_stock_fs, NULL, MSG_KEY_DOWN, CH_SHIFT_ESC, 0, 0);
    for (i = 0; i < 4; i++)
      Yield;
    TaskMsg(g_psm_stock_fs, NULL, MSG_KEY_UP, CH_SHIFT_ESC, 0, 0);
    g_psm_stock_esc = 1;
  }
  while (TRUE)
    Yield;
}

I64 PsalmodyStockNeedleLoop()
{
  //Full stock Psalmody() under Yield+pump — SHIFT_ESC / record / right-click needles.
  CTask *pump;
  I64 idx;
  if (!rv_winmgr.ready)
    return -1;
  RVYieldInit(&Fs);
  g_psm_stock_fs = Fs;
  g_psm_stock_esc = 0;
  g_psm_stock_rec = 0;
  g_psm_stock_dur = -1;
  g_psm_stock_notes = 0;
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
  pump = Spawn(&PsalmodyStockPump, NULL, "PsmStockPump",, Fs);
  if (!pump) {
    Print("RVPsalmody stock Spawn FAIL\n");
    return 0;
  }
  Print("RVPsalmody stock enter\n");
  Psalmody("A:/Home/Psalmody");
  Print("RVPsalmody stock exit\n");
  Kill(pump, FALSE);
  if (!g_psm_stock_esc || !g_psm_stock_rec || g_psm_stock_dur != 6 || g_psm_stock_notes < 1) {
    Print("RVPsalmody stock needles FAIL esc=%d rec=%d dur=%d notes=%d\n", g_psm_stock_esc, g_psm_stock_rec, g_psm_stock_dur, g_psm_stock_notes);
    return 0;
  }
  Print("RVPsalmody stock needles ok esc=%d rec=%d dur=%d notes=%d\n", g_psm_stock_esc, g_psm_stock_rec, g_psm_stock_dur, g_psm_stock_notes);
  return 1;
}

I64 main()
{
  I64 ona, note, oct, live, ui;
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
  // Same reason as kernel_span_demo: PopUp() waits on its servant with JobResGet's
  // `while (!DONE) Yield;`, so the scheduler has to be up before any popup. The setup above
  // runs without it, and without this the wait spins forever.
  RVYieldInit(&Fs);
  PopUpPickDir("~/Psalmody");
  PopUpEd("::/Apps/Psalmody/Help.DD", Fs);
  Print("RVPsalmody smoke ona=%d play=%d rst=%d menu=%d tempo=%d popup_file=%d ib=%d ona_hits=%d pcm=%d notes=%d vsnd=%d\n", ona, rv_snd_play_hits, rv_snd_rst_hits, ent->arg1, !!tempo, rv_popup_file_hits, g_ib_staff[0], rv_snd_ona_hits, rv_snd_pcm_n, rv_snd_note_hits, !!rv_snd_virtio_base);
  TempoDel(tempo);
  MenuPop;
  ui = PsalmodyDrawUIProbe;
  if (!ui) {
    Print("RVPsalmody UI FAIL\n");
    return 1;
  }
  live = PsalmodyLiveGetMsgLoop;
  if (live < 1) {
    Print("RVPsalmody live FAIL live=%d notes=%d msgs=%d\n", live, g_psm_live_notes, g_psm_live_msgs);
    return 1;
  }
  Print("RVPsalmody live ok live=%d notes=%d msgs=%d esc=%d rec=%d dur=%d\n", live, g_psm_live_notes, g_psm_live_msgs, g_psm_needle_esc, g_psm_needle_rec, g_psm_needle_dur);
  if (!PsalmodyStockNeedleLoop) {
    Print("RVPsalmody stock FAIL\n");
    return 1;
  }
  return 0;
}
