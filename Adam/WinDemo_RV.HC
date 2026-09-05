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
// PopUpPickFile lives in FileMgr_RV (FilesFind first-file; FileMgr GetMsg open).
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

public U8 *PopUpFileName(U8 *dft = NULL, I64 dof_flags = 0)
{
  //JobRes PopUp is live; FileNameForm/FileMgr still soft. Accept dft so SpanWrite can FileWrite.
  no_warn dof_flags;
  rv_popup_file_hits++;
  if (dft && *dft) {
    Print("PopUpFileName accept dft: %s\n", dft);
    return StrNew(dft);
  }
  return StrNew("~/Span/Game.DATA");
}
// PopUpPickFile: Adam/ABlkDev/FileMgr_RV.HC (FilesFind first-file; FileMgr GetMsg open).
public U8 *PopUpPickDir(U8 *dir = NULL)
{
  //Psalmody PSMF_CD — soft: keep current / accept dft dir string.
  rv_popup_file_hits++;
  if (dir && *dir) {
    Print("PopUpPickDir accept: %s\n", dir);
    return StrNew(dir);
  }
  return NULL;
}

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
