// WinDemo_RV.HC — soft Adam Win/Settings/PopUpColor shims for stock Demo/*.HC.
// SettingsPush/Pop, WinMax/WinBorder, AutoComplete, Refresh, PopUpColor — no full
// Adam WinMgr palette/song/AC task. GetMsg/ms already Kernel (Message/Mouse).
#ifndef WIN_DEMO_RV_HC
#define WIN_DEMO_RV_HC
// Adam GrInitB DefinePrint(TEXT_ROWS/COLS) — fixed grid for stock Apps/Demo on RV.
#ifndef TEXT_COLS
#define TEXT_COLS 80
#endif
#ifndef TEXT_ROWS
#define TEXT_ROWS 60
#endif
I64 rv_settings_push_hits;
I64 rv_winmax_hits;
I64 rv_popup_color_hits;
I64 rv_refresh_hits;
I64 rv_refresh_paint_hits;
I64 rv_popup_color_dft = RED;
public CTaskSettings *SettingsPush(CTask *task = NULL, I64 flags = 0)
{
  //Soft Adam TaskSettings — save win_* / win_inhibit / draw_it; skip palette/song/AC.
  CTaskSettings *tmpse;
  no_warn flags;
  if (!task)
    task = Fs;
  if (!task)
    return NULL;
  tmpse = CAlloc(sizeof(CTaskSettings), task);
  if (!tmpse)
    return NULL;
  tmpse->draw_it = task->draw_it;
  tmpse->left = task->win_left;
  tmpse->right = task->win_right;
  tmpse->top = task->win_top;
  tmpse->bottom = task->win_bottom;
  tmpse->scroll_x = task->scroll_x;
  tmpse->scroll_y = task->scroll_y;
  tmpse->scroll_z = task->scroll_z;
  tmpse->win_inhibit = task->win_inhibit;
  tmpse->text_attr = task->text_attr;
  tmpse->border_attr = task->border_attr;
  tmpse->border_src = task->border_src;
  tmpse->title_src = task->title_src;
  StrCpy(tmpse->task_title, task->task_title);
  tmpse->next = task->next_settings;
  task->next_settings = tmpse;
  rv_settings_push_hits++;
  return tmpse;
}

public U0 SettingsPop(CTask *task = NULL, I64 flags = 0)
{
  CTaskSettings *tmpse;
  no_warn flags;
  if (!task)
    task = Fs;
  if (!task)
    return;
  tmpse = task->next_settings;
  if (!tmpse)
    return;
  task->next_settings = tmpse->next;
  task->draw_it = tmpse->draw_it;
  task->win_left = tmpse->left;
  task->win_right = tmpse->right;
  task->win_top = tmpse->top;
  task->win_bottom = tmpse->bottom;
  task->scroll_x = tmpse->scroll_x;
  task->scroll_y = tmpse->scroll_y;
  task->scroll_z = tmpse->scroll_z;
  task->win_inhibit = tmpse->win_inhibit;
  task->text_attr = tmpse->text_attr;
  task->border_attr = tmpse->border_attr;
  task->border_src = tmpse->border_src;
  task->title_src = tmpse->title_src;
  StrCpy(task->task_title, tmpse->task_title);
  Free(tmpse);
}

public U0 WinMax(CTask *task = NULL)
{
  //Adam WinMax → RVWinMax when WinMgr up; else soft text-grid fill on task.
  I64 idx;
  if (!task)
    task = Fs;
  rv_winmax_hits++;
  if (rv_winmgr.ready) {
    idx = -1;
    if (task) {
      for (idx = 0; idx < RV_WIN_MAX; idx++) {
        if (rv_winmgr.wins[idx].used && rv_winmgr.wins[idx].task == task)
          break;
      }
      if (idx >= RV_WIN_MAX)
        idx = -1;
    }
    RVWinMax(idx);
    return;
  }
  if (!task)
    return;
  task->win_left = 0;
  task->win_top = 0;
  if (rv_winmgr.cols > 2)
    task->win_right = rv_winmgr.cols - 2;
  else
    task->win_right = 78;
  if (rv_winmgr.rows > 2)
    task->win_bottom = rv_winmgr.rows - 2;
  else
    task->win_bottom = 58;
}

public Bool WinBorder(Bool val = OFF, CTask *task = NULL)
{
  //Soft border toggle — DISPLAYf_NO_BORDER bit only (no layout resize).
  Bool old;
  if (!task)
    task = Fs;
  if (!task)
    return FALSE;
  old = !Bt(&task->display_flags, DISPLAYf_NO_BORDER);
  if (val)
    LBtr(&task->display_flags, DISPLAYf_NO_BORDER);
  else
    LBts(&task->display_flags, DISPLAYf_NO_BORDER);
  return old;
}

public Bool AutoComplete(Bool val = OFF)
{
  //No AC task on RV WinMgr subset — accept / ignore.
  no_warn val;
  return FALSE;
}

public U0 Refresh(I64 cnt = 1, Bool force = FALSE)
{
  //Soft Adam Refresh — Yield so stock AnimateTask / SongTask share the CPU.
  // Full RVWinMgrRefresh from Animate while Fs is mid-DirContextNew/Cd/FileWrite
  // hung stock Span() ESC save (UART last line: PopUpFileName; never FileWrite
  // return). WinMgrTask / explicit present still paint; force=TRUE = old path.
  I64 i;
  if (cnt < 1)
    cnt = 1;
  for (i = 0; i < cnt; i++) {
    if (force) {
      if (rv_winmgr.ready)
        RVWinMgrRefresh;
      else
        RVGrRefresh;
    }
    rv_refresh_hits++;
    // Soft H2: Span Animate Refresh tally (ODE/paint coexist with ESC save).
    rv_refresh_paint_hits++;
    Yield;
  }
}

public I64 PopUpColor(U8 *header = NULL, Bool allow_transparent = TRUE, Bool allow_dft = TRUE)
{
  //Soft color chooser — return dft palette index (no modal DocMenu).
  no_warn header;
  no_warn allow_transparent;
  no_warn allow_dft;
  rv_popup_color_hits++;
  return rv_popup_color_dft;
}
// Soft PopUp* for stock Apps (Span). Real servant PopUp lives in PopUp_RV (sibling).
// PopUpPickFile/PickDir: FileMgr_RV. PopUpFileName: stock DocPopUp FileNameForm+PopUp.
I64 rv_popup_ok_hits;
I64 rv_popup_file_hits;
public Bool PopUpOk(U8 *header = NULL, U8 *footer = NULL)
{
  //TempleOS PopUpOk blocks until dismissed. RV open is non-blocking — auto-resolve
  // so stock Apps (Span) can reach GetMsg without a stuck modal focus.
  no_warn footer;
  rv_popup_ok_hits++;
  if (rv_winmgr.ready) {
    if (RVPopUpOk(header))
      RVPopUpResolve(1);
    return TRUE;
  }
  if (header)
    Print("PopUpOk soft: %s\n", header);
  return TRUE;
}

public Bool PopUpNoYes(U8 *header = NULL, U8 *footer = NULL)
{
  //TempleOS PopUpNoYes → RVPopUpNoYes when WinMgr up; else soft YES.
  no_warn footer;
  rv_popup_ok_hits++;
  if (rv_winmgr.ready)
    return RVPopUpNoYes(header);
  if (header)
    Print("PopUpNoYes soft: %s\n", header);
  return TRUE;
}

public U8 *FileNameForm(U8 *dft = NULL, I64 dof_flags = 0, CTask *mem_task = NULL)
{
  // Stock DocPopUp.HC FileNameForm — DocForm on CEdFileName.
  // Host AOT skips member `format` meta, so hand-build stock DA template + DocEd
  // (same shape as RVDoc DocForm Lex-lite). Headless: focus first BT + Enter.
  CEdFileName fn;
  CDoc *doc;
  CDocEntry *doc_e;
  U8 line[280];
  Bool ok = FALSE;
  no_warn dof_flags;
  fn.dirc = NULL;
  if (dft && *dft)
    StrCpy(fn.name, dft);
  else
    *fn.name = 0;
  doc = DocNew("FORM.DD");
  if (!doc)
    return NULL;
  doc->flags |= DOCF_FORM | DOCF_ALLOW_UNDO | DOCF_OVERSTRIKE;
  if (dof_flags & DOF_SIZE_MIN)
    doc->flags |= DOCF_SIZE_MIN;
  DocPutS(doc, "$$DA,A=\"FileName:%s\"$$\n");
  doc_e = doc->cur_entry->last;
  if (doc_e && doc_e->type_u8 == DOCT_DATA) {
    doc_e->data = fn.name;
    StrPrint(line, "FileName:%s", fn.name);
    Free(doc_e->tag);
    doc_e->tag = RVDocStrNew(doc, line);
    doc_e->max_col = StrLen(line);
  }
  DocPutS(doc, "$$BT,\"OK\",LE=1$$\n$$BT,\"Cancel\",LE=-1$$\n");
  DocRecalc(doc);
  DocTop(doc);
  // First BTTN = OK; force LE=1 if PrsArg missed (doldoc LE= HashFind cold).
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (doc_e->type_u8 == DOCT_BTTN) {
      doc->cur_entry = doc_e;
      doc_e->de_flags |= DOCEF_LEFT_EXP;
      if (!doc_e->left_exp)
        doc_e->left_exp = 1;
      break;
    }
    doc_e = doc_e->next;
  }
  if (rv_doc_ed_key_n <= 0)
    DocEdKeyInject('\n');
  // DOF_DONT_HOME: keep OK cur_entry (DocEd DocTop would wipe focus).
  if (DocEd(doc, dof_flags | DOF_DONT_HOME)) {
    ok = TRUE;
    if (rv_doc_ed_result == DOCM_CANCEL || rv_doc_ed_result < 0)
      ok = FALSE;
  }
  DocDel(doc);
  if (ok && *fn.name)
    return StrNew(fn.name, mem_task);
  return NULL;
}
// Zero-arg PopUp helper — planted in RVExePubsWireAddrs for servant ExePutS
// (mirrors DocPopUpPick*Run). Stock PopUpFileName uses FileNameForm(…) string.
U8 *g_popup_filename_dft;
I64 g_popup_filename_dof;
public U8 *DocPopUpFileNameRun()
{
  // Single-stmt helper for PopUp("DocPopUpFileNameRun;"); mirrors DocPopUpPick*Run.
  return FileNameForm(g_popup_filename_dft, g_popup_filename_dof | DOF_SIZE_MIN, Fs->parent_task);
}

public U8 *PopUpFileName(U8 *dft = NULL, I64 dof_flags = 0)
{
  // Stock DocPopUp.HC: PopUp("FileNameForm(\"%Q\",0x%X,Fs->parent_task);").
  // Needs FileNameForm HTT_FUN via RVExePubsWireAddrs (servant ExePutS).
  U8 *res, *st;
  I64 raw;
  rv_popup_file_hits++;
  g_popup_filename_dft = dft;
  g_popup_filename_dof = dof_flags;
  st = MStrPrint("FileNameForm(\"%Q\",0x%X,Fs->parent_task);", dft, dof_flags | DOF_SIZE_MIN);
  Print("PopUpFileName DocPopUp begin\n");
  raw = PopUp(st, Fs);
  Free(st);
  if (raw > 0x10000)
    res = raw(U8 *);
  else
    res = NULL;
  if (res && *res) {
    Print("PopUpFileName ok: %s\n", res);
    return res;
  }
  Print("PopUpFileName empty/cancel raw=%d\n", raw);
  // Soft Call fallback: parent FileNameForm (DocEd) if servant hash miss / cancel.
  res = FileNameForm(dft, dof_flags | DOF_SIZE_MIN, Fs);
  if (res && *res) {
    Print("PopUpFileName parent FileNameForm ok: %s\n", res);
    return res;
  }
  if (dft && *dft) {
    Print("PopUpFileName soft accept dft: %s\n", dft);
    return StrNew(dft);
  }
  return NULL;
}
// PopUpPickFile/PickDir: Adam/ABlkDev/FileMgr_RV.HC (DocPopUp MStrPrint+PopUp).
public I64 PopUpEd(U8 *filename, CTask *parent = NULL, CTask **_pu_task = NULL)
{
  //Psalmody Help — soft ack; real Ed servant deferred.
  no_warn parent;
  if (_pu_task)
    *_pu_task = NULL;
  rv_popup_ok_hits++;
  if (filename)
    Print("PopUpEd soft: %s\n", filename);
  return 0;
}
#endif
