// PopUp_RV.HC — PopUpOk / NoYes + DocForm (class-meta via RVDoc) on FB (P3).
// Stock Job.HC PopUp (SrvCmdLine+ExePrint+JobRes) is mepc=0-safe via Spawn→RVKFixSpawnFrame.
// This unit: CRVWin chrome (Ok/NoYes/Form) + thin RVPopUp shim; does not replace fp_popup.
#ifndef POPUP_RV_HC
#define POPUP_RV_HC
#define RV_POPUP_NONE  0
#define RV_POPUP_OK    1
#define RV_POPUP_NOYES 2
#define RV_POPUP_FORM  3
#define RV_POPUP_DOCFORM 4
#define RV_POPUP_SRV_HDR_MAX 192
I64 rv_popup_mode = RV_POPUP_NONE;
I64 rv_popup_idx = -1;
I64 rv_popup_hits;
I64 rv_popup_result = -1;
I64 rv_form_val;
Bool rv_form_check;
I64 rv_form_focus;
I64 rv_form_hits;
I64 rv_docform_hits;
U8 rv_form_header[64];
CDoc *rv_form_doc;
U8 *rv_form_data;
U8 rv_form_class[64];
// Spawn-path counters — stock Job.HC PopUp bumps sys_popup_*; shim tracks local hits.
I64 rv_popup_print_hits;
I64 rv_popup_spawn_hits;
I64 rv_popup_spawn_alive;
CTask *rv_popup_srv_task;
U8 rv_popup_srv_hdr[RV_POPUP_SRV_HDR_MAX];
extern CTask *RVKSpawn(U0 (*entry)(), U8 *name, CTask *adam);
// Demo class-meta target (smoke without HTT_CLASS plant).
class CRVFormDemo
{
  I64 val;
  Bool check;
};
CRVFormDemo rv_form_demo;
I64 RVMemberMetaData(U8 *needle_str, CMemberLst *haystack_member_lst)
{
  //Port of Compiler LexLib MemberMetaData — safe without Compiler body.
  CMemberLstMeta *meta;
  if (!haystack_member_lst)
    return 0;
  meta = haystack_member_lst->meta;
  while (meta) {
    if (!StrCmp(meta->str, needle_str))
      return meta->user_data;
    meta = meta->next;
  }
  return 0;
}

U0 RVPopUpSrvKill()
{
  //Clear popup_task before teardown so TaskEnd does not Kill parent.
  // Never Kill(wait=TRUE): Suspended servants never run TaskEnd → hang (WS5).
  // Same soft-kill shape as RVWinTaskSoftKill (unlink + park + invalidate).
  CTask *t = rv_popup_srv_task;
  CTask *p;
  rv_popup_srv_task = NULL;
  rv_popup_spawn_alive = 0;
  if (!TaskValidate(t))
    return;
  p = t->parent_task;
  if (TaskValidate(p) && p->popup_task == t)
    p->popup_task = NULL;
  if (Fs->popup_task == t)
    Fs->popup_task = NULL;
  if (t->next_task && t->last_task && t->next_task != t && t->next_task->last_task == t && t->last_task->next_task == t) {
    TaskQueRem(t);
    t->next_task = t;
    t->last_task = t;
  }
  LBts(&t->task_flags, TASKf_KILL_TASK);
  LBts(&t->task_flags, TASKf_SUSPENDED);
  LBts(&t->task_flags, TASKf_AWAITING_MSG);
  t->task_signature = 0;
}

U0 RVPopUpClose()
{
  if (rv_popup_mode == RV_POPUP_NONE) {
    rv_popup_idx = -1;
    return;
  }
  if (rv_popup_idx >= 0 && rv_popup_idx < RV_WIN_MAX) {
    rv_winmgr.wins[rv_popup_idx].used = FALSE;
    rv_winmgr.wins[rv_popup_idx].show = FALSE;
    rv_winmgr.wins[rv_popup_idx].doc = NULL;
  }
  if (rv_form_doc && rv_popup_mode == RV_POPUP_DOCFORM) {
    // Keep doc until resolve copies data; Del on close after scan.
  }
  rv_popup_idx = -1;
  rv_popup_mode = RV_POPUP_NONE;
}

U0 RVPopUpFormBody(U8 *body, U8 *header)
{
  U8 chk[8];
  if (!header)
    header = "DocForm";
  if (rv_form_check)
    StrCpy(chk, "[X]");
  else
    StrCpy(chk, "[ ]");
  StrPrint(body, "$$E%s\n" "$$FValue: %d  (0-9 / +-)  Tab=field\n" "$$3%s Check  Space=toggle\n" "$$FOK=Enter   Cancel=Esc\n", header, rv_form_val, chk);
}

Bool RVPopUpOpen(I64 mode, U8 *header)
{
  I64 idx, left, right, top, bottom, cols, rows;
  U8 body[RV_WIN_BODY_MAX];
  if (!rv_winmgr.ready)
    return FALSE;
  RVPopUpClose;
  cols = rv_winmgr.cols;
  rows = rv_winmgr.rows;
  left = cols / 4;
  right = cols - cols / 4 - 1;
  top = rows / 3;
  bottom = top + 7;
  if (right - left < 20) {
    left = 2;
    right = cols - 3;
  }
  if (bottom >= rows - 2)
    bottom = rows - 3;
  if (!header)
    header = "PopUp";
  if (mode == RV_POPUP_FORM || mode == RV_POPUP_DOCFORM) {
    if (header)
      StrCpy(rv_form_header, header);
    else
      StrCpy(rv_form_header, "DocForm");
    RVPopUpFormBody(body, rv_form_header);
  } else if (mode == RV_POPUP_NOYES)
    StrPrint(body, "$$E%s\n$$FYES = Y / Enter\n$$3NO = N / Esc\n", header);
  else
    StrPrint(body, "$$E%s\n$$FOK = Enter / click\n$$3Esc = cancel\n", header);
  idx = RVWinNew(left, right, top, bottom, "PopUp", body, TRUE);
  if (idx < 0)
    return FALSE;
  rv_winmgr.wins[idx].border_attr = PURPLE;
  rv_winmgr.wins[idx].text_attr = BLUE << 4 + WHITE;
  rv_winmgr.wins[idx].z = 1000;
  if (mode == RV_POPUP_DOCFORM && rv_form_doc)
    rv_winmgr.wins[idx].doc = rv_form_doc;
  rv_popup_mode = mode;
  rv_popup_idx = idx;
  rv_popup_result = -1;
  rv_popup_hits++;
  if (mode == RV_POPUP_FORM || mode == RV_POPUP_DOCFORM)
    rv_form_hits++;
  Print("RVWinMgr PopUp open mode=%d hits=%d form=%d docform=%d\n", mode, rv_popup_hits, rv_form_hits, rv_docform_hits);
  return TRUE;
}

public Bool RVPopUpOk(U8 *header = NULL)
{
  return RVPopUpOpen(RV_POPUP_OK, header);
}

public Bool RVPopUpNoYes(U8 *header = NULL)
{
  return RVPopUpOpen(RV_POPUP_NOYES, header);
}

U0 RVPopUpSrv()
{
  //Thin park body if a shim ever RVKSpawns without SrvCmdLine. Prefer stock Job PopUp.
  rv_popup_spawn_alive = 1;
  while (TRUE) {
    LBts(&Fs->task_flags, TASKf_IDLE);
    LBts(&Fs->task_flags, TASKf_AWAITING_MSG);
    Yield;
  }
}

public I64 RVPopUp(U8 *buf, CTask *parent = NULL, CTask **_pu_task = NULL)
{
  //Thin CRVWin chrome around stock Job.HC PopUp (SrvCmdLine+ExePrint+JobRes).
  // Does not replace the servant — fp_popup stays NULL so PopUp is TempleOS-shaped.
  I64 res = 0;
  if (!parent)
    parent = Fs;
  if (_pu_task)
    *_pu_task = NULL;
  rv_popup_spawn_hits++;
  if (rv_winmgr.ready && buf) {
    I64 i = 0;
    while (buf[i] && i < RV_POPUP_SRV_HDR_MAX - 1) {
      rv_popup_srv_hdr[i] = buf[i];
      i++;
    }
    rv_popup_srv_hdr[i] = 0;
    RVPopUpOk(rv_popup_srv_hdr[0] ? rv_popup_srv_hdr : "PopUp");
  }
  // Stock servant path (Spawn already RVKFixSpawnFrame — mepc=0-safe).
  if (buf && parent) {
    // Code stmt: ExePrint/JobRes. Non-code header: probe 1; then CRVWin shows hdr.
    I64 len = StrLen(buf);
    if (len > 0 && buf[len - 1] == ';')
      res = PopUp(buf, parent, _pu_task);
    else
      res = PopUp("1;", parent, _pu_task);
    rv_popup_spawn_alive = 0;
    Print("RVPopUp stock JobRes res=%d spawn_hits=%d\n", res, rv_popup_spawn_hits);
  } else if (buf)
    Print("RVPopUp soft: %s\n", buf);
  return res;
}

public U0 RVPopUpWire()
{
  //Stock Job.HC PopUp is live (Spawn→RVKFixSpawnFrame→SrvCmdLine→JobRes).
  // No fp_popup override — TempleOS servant path stays stock.
  // WinDemo_RV PopUpOk/PopUpNoYes → RVPopUp* when rv_winmgr.ready.
  Print("RVPopUpWire: stock Job PopUp; CRVWin Ok/NoYes remain\n");
}

public I64 RVPopUpPrint(U8 *fmt,...)
{
  //PopUpPrint-shaped: StrPrintJoin then stock PopUp (and CRVWin hdr when ready).
  U8 *buf;
  I64 res = 0;
  buf = StrPrintJoin(NULL, fmt, argc, argv);
  if (!buf)
    return 0;
  rv_popup_print_hits++;
  res = RVPopUp(buf, Fs, NULL);
  Free(buf);
  return res;
}

public Bool RVDocForm(U8 *header = NULL, I64 dft_val = 0, Bool dft_check = FALSE)
{
  //DocForm-lite fallback (no class hash).
  rv_form_val = dft_val;
  rv_form_check = dft_check;
  rv_form_focus = 0;
  return RVPopUpOpen(RV_POPUP_FORM, header);
}

U0 RVDocFormScanDemo(CDoc *doc)
{
  CDocEntry *doc_e;
  if (!doc)
    return;
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->type_u8 == DOCT_DATA && doc_e->data)
      rv_form_demo.val = *doc_e->data(I64 *);
    if (doc_e->type_u8 == DOCT_CHECK_BOX) {
      if (doc_e->de_flags & DOCEF_CHECKED_COLLAPSED)
        rv_form_demo.check = TRUE;
      else
        rv_form_demo.check = FALSE;
    }
    doc_e = doc_e->next;
  }
  rv_form_val = rv_form_demo.val;
  rv_form_check = rv_form_demo.check;
}

U0 RVDocFormScanClass(CDoc *doc, U8 *_d, CHashClass *tmpc)
{
  CDocEntry *doc_e;
  CMemberLst *ml;
  U8 *format;
  I64 *ip;
  if (!doc || !_d || !tmpc)
    return;
  doc_e = doc->head.next;
  ml = tmpc->member_lst_and_root;
  while (doc_e != doc && ml) {
    format = RVMemberMetaData("format", ml)(U8 *);
    if (format && (doc_e->type_u8 == DOCT_DATA || doc_e->type_u8 == DOCT_CHECK_BOX)) {
      if (doc_e->type_u8 == DOCT_DATA && doc_e->data) {
        ip = (_d + ml->offset)(I64 *);
        *ip = *doc_e->data(I64 *);
      } else if (doc_e->type_u8 == DOCT_CHECK_BOX) {
        *(_d + ml->offset)(Bool *) = !!(doc_e->de_flags & DOCEF_CHECKED_COLLAPSED);
      }
      ml = ml->next;
    }
    doc_e = doc_e->next;
  }
}

Bool RVDocFormBuildDemo(U8 *header)
{
  //Class-meta shape without HTT_CLASS: DocPutS DA/CB → PopUp (hooks RVDoc).
  CDoc *doc;
  CDocEntry *doc_e;
  U8 line[96];
  if (rv_form_doc) {
    DocDel(rv_form_doc);
    rv_form_doc = NULL;
  }
  doc = DocNew;
  if (!doc)
    return FALSE;
  doc->desc = 'Form';
  doc->flags |= DOCF_FORM;
  if (header)
    StrPrint(line, "$$TX,\"%s\"$$\n", header);
  else
    StrCpy(line, "$$TX,\"DocForm\"$$\n");
  DocPutS(doc, line);
  doc_e = DocPutS(doc, "$$DA-TRM,A=\"Value:%d\"$$\n");
  if (doc_e) {
    doc_e->data = &rv_form_demo.val;
    doc_e->raw_type = RT_I64;
  }
  doc_e = DocPutS(doc, "$$CB,\"Check\"$$\n");
  if (doc_e) {
    doc_e->data = &rv_form_demo.check;
    if (rv_form_demo.check)
      doc_e->de_flags |= DOCEF_CHECKED_COLLAPSED;
  }
  DocPutS(doc, "$$BT,\"OK\",LE=1$$\n$$BT,\"Cancel\",LE=0$$\n");
  DocRecalc(doc);
  rv_form_doc = doc;
  rv_form_data = &rv_form_demo;
  StrCpy(rv_form_class, "CRVFormDemo");
  rv_docform_hits++;
  rv_form_val = rv_form_demo.val;
  rv_form_check = rv_form_demo.check;
  return RVPopUpOpen(RV_POPUP_DOCFORM, header);
}

Bool RVDocFormBuildClass(U8 *_d, U8 *class_name, U8 *header, U8 *footer)
{
  CHashClass *tmpc;
  CMemberLst *ml;
  CDoc *doc;
  CDocEntry *doc_e;
  U8 *format;
  if (!_d || !class_name || !Fs || !Fs->hash_table)
    return FALSE;
  tmpc = HashFind(class_name, Fs->hash_table, HTT_CLASS);
  if (!tmpc)
    return FALSE;
  if (rv_form_doc) {
    DocDel(rv_form_doc);
    rv_form_doc = NULL;
  }
  doc = DocNew;
  if (!doc)
    return FALSE;
  doc->desc = 'Form';
  doc->flags |= DOCF_FORM | DOCF_OVERSTRIKE;
  if (header)
    DocPutS(doc, header);
  ml = tmpc->member_lst_and_root;
  while (ml) {
    format = RVMemberMetaData("format", ml)(U8 *);
    if (format && (doc_e = DocPutS(doc, format))) {
      doc_e->data = _d + ml->offset;
      if (doc_e->type_u8 == DOCT_DATA)
        doc_e->raw_type = RT_I64;
    }
    ml = ml->next;
  }
  if (footer)
    DocPutS(doc, footer);
  DocPutS(doc, "$$BT,\"OK\",LE=1$$\n$$BT,\"Cancel\",LE=0$$\n");
  DocRecalc(doc);
  rv_form_doc = doc;
  rv_form_data = _d;
  StrCpy(rv_form_class, class_name);
  rv_docform_hits++;
  return RVPopUpOpen(RV_POPUP_DOCFORM, header ? header : class_name);
}

public Bool RVDocFormMeta(U8 *header = NULL, I64 dft_val = 42, Bool dft_check = TRUE)
{
  //PopUp class-meta demo (DocPutS DA/CB) — does not override RVDoc DocForm.
  rv_form_demo.val = dft_val;
  rv_form_demo.check = dft_check;
  return RVDocFormBuildDemo(header);
}

U0 RVPopUpFormRefresh()
{
  U8 body[RV_WIN_BODY_MAX];
  if (rv_popup_mode == RV_POPUP_DOCFORM && rv_form_doc && rv_popup_idx >= 0) {
    DocRecalc(rv_form_doc);
    return;
  }
  if (rv_popup_mode != RV_POPUP_FORM || rv_popup_idx < 0)
    return;
  RVPopUpFormBody(body, rv_form_header);
  RVWinSetBody(rv_popup_idx, body);
}

Bool RVPopUpResolve(I64 res)
{
  CHashClass *tmpc;
  if (rv_popup_mode == RV_POPUP_NONE)
    return FALSE;
  if (res && rv_popup_mode == RV_POPUP_DOCFORM && rv_form_doc) {
    if (rv_form_data == &rv_form_demo)
      RVDocFormScanDemo(rv_form_doc);
    else if (rv_form_data && rv_form_class[0] && Fs && Fs->hash_table) {
      tmpc = HashFind(rv_form_class, Fs->hash_table, HTT_CLASS);
      if (tmpc)
        RVDocFormScanClass(rv_form_doc, rv_form_data, tmpc);
    }
  }
  rv_popup_result = res;
  if (rv_form_doc) {
    DocDel(rv_form_doc);
    rv_form_doc = NULL;
  }
  RVPopUpClose;
  // Kill suspended PopUp servant (popup_task cleared first — no TaskEnd parent Kill).
  if (rv_popup_srv_task)
    RVPopUpSrvKill;
  Print("RVWinMgr PopUp resolve=%d hits=%d form_val=%d check=%d docform=%d spawn=%d\n", res, rv_popup_hits, rv_form_val, rv_form_check, rv_docform_hits, rv_popup_spawn_hits);
  return TRUE;
}

Bool RVPopUpPutKey(I64 ch)
{
  if (rv_popup_mode == RV_POPUP_NONE)
    return FALSE;
  if (rv_popup_mode == RV_POPUP_FORM || rv_popup_mode == RV_POPUP_DOCFORM) {
    if (ch == '\t') {
      rv_form_focus = (rv_form_focus + 1) & 1;
      return TRUE;
    }
    if (ch == ' ') {
      rv_form_check = !rv_form_check;
      rv_form_demo.check = rv_form_check;
      RVPopUpFormRefresh;
      return TRUE;
    }
    if (rv_form_focus == 0) {
      if (ch >= '0' && ch <= '9') {
        rv_form_val = rv_form_val * 10 + (ch - '0');
        if (rv_form_val > 999999)
          rv_form_val = 999999;
        rv_form_demo.val = rv_form_val;
        RVPopUpFormRefresh;
        return TRUE;
      }
      if (ch == '+' || ch == '=') {
        rv_form_val++;
        rv_form_demo.val = rv_form_val;
        RVPopUpFormRefresh;
        return TRUE;
      }
      if (ch == '-' || ch == '_') {
        rv_form_val--;
        rv_form_demo.val = rv_form_val;
        RVPopUpFormRefresh;
        return TRUE;
      }
      if (ch == 8 || ch == 127) {
        rv_form_val /= 10;
        rv_form_demo.val = rv_form_val;
        RVPopUpFormRefresh;
        return TRUE;
      }
    }
    if (ch == '\n' || ch == '\r') {
      RVPopUpResolve(1);
      return TRUE;
    }
    if (ch == CH_ESC) {
      RVPopUpResolve(0);
      return TRUE;
    }
    return TRUE;
  }
  if (ch == '\n' || ch == '\r' || ch == 'y' || ch == 'Y' || ch == ' ') {
    RVPopUpResolve(1);
    return TRUE;
  }
  if (ch == CH_ESC || ch == 'n' || ch == 'N') {
    RVPopUpResolve(0);
    return TRUE;
  }
  return TRUE;
}

Bool RVPopUpClick(I64 cx, I64 cy)
{
  CRVWin *w;
  I64 row;
  if (rv_popup_mode == RV_POPUP_NONE || rv_popup_idx < 0)
    return FALSE;
  w = &rv_winmgr.wins[rv_popup_idx];
  if (!w->used || !w->show)
    return FALSE;
  if (cx >= w->left && cx <= w->right && cy >= w->top && cy <= w->bottom) {
    if (rv_popup_mode == RV_POPUP_FORM || rv_popup_mode == RV_POPUP_DOCFORM) {
      row = cy - (w->top + 1);
      if (row == 2) {
        rv_form_check = !rv_form_check;
        rv_form_demo.check = rv_form_check;
        RVPopUpFormRefresh;
        return TRUE;
      }
    }
    RVPopUpResolve(1);
    return TRUE;
  }
  RVPopUpResolve(0);
  return TRUE;
}
#endif
