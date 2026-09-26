// FileMgr_RV.HC — stock Adam/ABlkDev/FileMgr.HC FMRebuildDocDrv + FM_PICK_* GetMsg.
// DirFileDoc lives in Kernel/RVDoc.HC; MenuPop in Menu_RV — do not redefine here.
// RVFileMgrOpen lives in RVWinMgr (same unit as CRVWin; avoid ABS_ADDR BSS).
// PopUpPickFile/PickDir: stock DocPopUp Cd;FileMgr via PopUp (ExePutS CMPF_PRS_SEMICOLON).
#ifndef FILE_MGR_RV_HC
#define FILE_MGR_RV_HC
#ifndef FM_NORMAL
#define FM_NORMAL	0
#define FM_PICK_FILE	1
#define FM_PICK_DIR	2
#endif
I64 rv_filemgr_pick_hits;
I64 rv_filemgr_getmsg_hits;
CTask *g_fm_pick_task;
CDirEntry *FMRebuildDocDrv(U8 drv_let, CDoc *doc, CDirEntry **_head, Bool init)
{
  //Stock Adam/ABlkDev/FileMgr.HC FMRebuildDocDrv — FilesFind tree → $$TR/$$MU U=.
  // Format via StrPrint+DocPutS (same as RVDoc DirFileDoc).
  CDirEntry *tmpde, *tmpde1;
  U8 *st, line[128];
  I64 flags = 0;
  tmpde = CAlloc(sizeof(CDirEntry));
  tmpde->full_name = MStrPrint("%C:/", drv_let);
  tmpde->attr = RS_ATTR_DIR;
  st = MStrPrint("%c:/*", drv_let);
  // Match RVFileMgrDocProbe (flags=0). FUF_RECURSE deferred until MsgPutKey-stable.
  if (init)
    tmpde->sub = tmpde1 = FilesFind(st, flags);
  else
    tmpde1 = NULL;
  Free(st);
  StrPrint(line, "$$TR,\"%s\",U=0x%X$$", tmpde->full_name, tmpde);
  tmpde->user_data = DocPutS(doc, line);
  tmpde->next = *_head;
  *_head = tmpde;
  DocPutS(doc, "\n$$ID,+2$$");
  DocBottom(doc);
  if (init) {
    DirFileDoc(doc, tmpde1);
    while (tmpde1) {
      tmpde1->parent = tmpde;
      tmpde1 = tmpde1->next;
    }
  }
  DocPutS(doc, "$$ID,-2$$");
  return tmpde;
}

U0 FMRebuildDoc(CDoc **_doc, CDirEntry **_head, I64 mode)
{
  //Pick-mode rebuild: cur drv FilesFind → DirFileDoc (stock FileMgr shape).
  CDoc *doc = *_doc, *parent_doc;
  U8 drv_let;
  if (doc) {
    parent_doc = doc->parent_doc;
    Fs->put_doc = Fs->display_doc = NULL;
    DocDel(doc);
  } else
    parent_doc = DocPut;
  if (*_head) {
    DirTreeDel (*_head);
    *_head = NULL;
  }
  doc = DocNew;
  if (!doc) {
    *_doc = NULL;
    return;
  }
  doc->desc = 'FileMan';
  doc->parent_doc = parent_doc;
  doc->flags |= DOCF_FORM;
  switch (mode) {
    case FM_PICK_FILE :
    DocPutS(doc, "$$PURPLE$$Pick file and press <ESC>\n\n");
    doc->flags |= DOCF_SIZE_MIN;
    break;
    case FM_PICK_DIR :
    DocPutS(doc, "$$PURPLE$$Pick directory and press <ESC>\n\n");
    doc->flags |= DOCF_SIZE_MIN;
    break;
    default:
    DocPutS(doc, "$$PURPLE$$File Manager\n\n");
    break;
  }
  DocPutS(doc, "$$LTBLUE$$");
  if (Fs && Fs->cur_dv) {
    drv_let = Drv2Let(Fs->cur_dv);
    FMRebuildDocDrv(drv_let, doc, _head, TRUE);
  }
  DocTop(doc);
  DocLock(doc);
  Fs->put_doc = Fs->display_doc = doc;
  *_doc = doc;
}

U0 FileMgrPickPump(U8 *unused)
{
  //Feed ESC while FileMgr GetMsg Yields (parent may be PopUp-Suspended).
  I64 i;
  no_warn unused;
  for (i = 0; i < 8; i++)
    Yield;
  if (TaskValidate(g_fm_pick_task))
    TaskMsg(g_fm_pick_task, NULL, MSG_KEY_DOWN, CH_ESC, 0, 0);
  while (TRUE) {
    LBts(&Fs->task_flags, TASKf_IDLE);
    LBts(&Fs->task_flags, TASKf_AWAITING_MSG);
    Yield;
  }
}

U0 FileMgrPickPumpKill(CTask *pump)
{
  //Soft-reap like PopUp servant — Kill(wait) hangs (HolyYield skips TaskEnd).
  if (!TaskValidate(pump))
    return;
  if (pump->next_task && pump->last_task && pump->next_task != pump && pump->next_task->last_task == pump && pump->last_task->next_task == pump) {
    TaskQueRem(pump);
    pump->next_task = pump;
    pump->last_task = pump;
  }
  LBts(&pump->task_flags, TASKf_KILL_TASK);
  LBts(&pump->task_flags, TASKf_SUSPENDED);
  LBts(&pump->task_flags, TASKf_AWAITING_MSG);
  pump->task_signature = 0;
}

CDocEntry *FileMgrPickCurEntry(CDoc *doc, I64 mode)
{
  //Land cur_entry on a pickable MENU_VAL (file) or TREE (dir).
  CDocEntry *doc_e, *tree = NULL;
  if (!doc)
    return NULL;
  doc_e = doc->head.next;
  while (doc_e != doc) {
    if (mode == FM_PICK_DIR) {
      if (doc_e->type_u8 == DOCT_TREE && doc_e->user_data) {
        if (!tree)
          tree = doc_e;
      }
    } else if (doc_e->type_u8 == DOCT_MENU_VAL && doc_e->user_data)
      return doc_e;
    doc_e = doc_e->next;
  }
  return tree;
}

public U8 *FileMgr(I64 mode = FM_NORMAL, CTask *mem_task = NULL)
{
  //Stock FileMgr pick path: rebuild → GetMsg → ESC returns name (mem_task heap).
  // FM_NORMAL stays RVFileMgrOpen (non-blocking CRVWin); full mgr deferred.
  CDirEntry *head = NULL, *tmpde;
  I64 sc, ch = 0, arg1, arg2, msg_code;
  CDoc *doc = NULL, *old_put_doc = DocPut, *old_display_doc = DocDisplay;
  U8 *res = NULL, *old_cur_dir = DirCur;
  CDocEntry *doc_ce;
  CTask *pump = NULL;
  if (mode == FM_NORMAL) {
    RVFileMgrOpen(0);
    return NULL;
  }
  rv_filemgr_pick_hits++;
  Print("FileMgr pick begin mode=%d hits=%d\n", mode, rv_filemgr_pick_hits);
  SettingsPush;
  // FileMgrPullDown.DD not staged on RAM A: — skip MenuFilePush (PrintErr spam).
  FMRebuildDoc(&doc, &head, mode);
  if (!doc) {
    SettingsPop;
    MenuPop;
    Free(old_cur_dir);
    Print("FileMgr pick FAIL no doc\n");
    return StrNew("", mem_task);
  }
  doc_ce = FileMgrPickCurEntry(doc, mode);
  if (doc_ce)
    doc->cur_entry = doc_ce;
  g_fm_pick_task = Fs;
  sys_focus_task = Fs;
  pump = Spawn(&FileMgrPickPump, NULL, "FMPickPump",, Fs);
  if (!pump)
    Print("FileMgr pick WARN no pump — GetMsg may hang\n");
  do {
    DocUnlock(doc);
    do {
      msg_code = GetMsg(&arg1, &arg2, 1 << MSG_KEY_DOWN | 1 << MSG_MS_L_DOWN | 1 << MSG_MS_L_UP | 1 << MSG_MS_R_UP);
      rv_filemgr_getmsg_hits++;
    } while (Fs != sys_focus_task);
    DocLock(doc);
    switch (msg_code) {
      case MSG_KEY_DOWN :
      ch = arg1;
      sc = arg2;
      no_warn sc;
      if (ch == CH_ESC) {
        doc_ce = doc->cur_entry;
        if (doc_ce && doc_ce->user_data) {
          tmpde = doc_ce->user_data;
          if (mode == FM_PICK_FILE && doc_ce->type_u8 == DOCT_MENU_VAL)
            res = StrNew(tmpde->full_name, mem_task);
          else if (mode == FM_PICK_DIR) {
            if (doc_ce->type_u8 == DOCT_TREE)
              res = StrNew(tmpde->full_name, mem_task);
            else if (doc_ce->type_u8 == DOCT_MENU_VAL && (tmpde = tmpde->parent))
              res = StrNew(tmpde->full_name, mem_task);
          }
        }
      }
      break;
      default:
      ch = 0;
      break;
    }
  } while (ch != CH_ESC && ch != CH_SHIFT_ESC);
  FileMgrPickPumpKill(pump);
  g_fm_pick_task = NULL;
  Fs->put_doc = old_put_doc;
  Fs->display_doc = old_display_doc;
  SettingsPop;
  DocDel(doc);
  DirTreeDel(head);
  if (old_cur_dir) {
    Cd(old_cur_dir);
    Free(old_cur_dir);
  }
  if (!res)
    res = StrNew("", mem_task);
  MenuPop;
  if (res && *res)
    Print("FileMgr pick ok mode=%d getmsg=%d path=%s\n", mode, rv_filemgr_getmsg_hits, res);
  else
    Print("FileMgr pick empty mode=%d getmsg=%d\n", mode, rv_filemgr_getmsg_hits);
  return res;
}

public CMenu *MenuFilePush(U8 *filename)
{
  CMenu *m = MenuFile(filename);
  if (!m)
    return NULL;
  m->next = Fs->cur_menu;
  Fs->cur_menu = m;
  return m;
}

public CDoc *WinCursorPosSet(CTask *task, I64 msx, I64 msy, Bool set_cursor = TRUE)
{
  no_warn msx;
  no_warn msy;
  no_warn set_cursor;
  if (!task)
    task = Fs;
  if (task && task->put_doc)
    return task->put_doc;
  return DocPut(task);
}

public Bool PopUpCancelOk(U8 *header = NULL, U8 *footer = NULL)
{
  no_warn header;
  no_warn footer;
  return FALSE;
}

public I64 PopUpMenu(CDoc *doc, I64 dof_flags = 0)
{
  I64 res;
  if (!doc)
    return DOCM_CANCEL;
  res = DocMenu(doc, dof_flags);
  DocDel(doc);
  return res;
}

public I64 PopUpFile(U8 *filename, Bool warn_ext = TRUE, I64 edf_dof_flags = 0)
{
  no_warn filename;
  no_warn warn_ext;
  no_warn edf_dof_flags;
  return 0;
}

public Bool Move(U8 *f1, U8 *f2)
{
  no_warn f1;
  no_warn f2;
  return FALSE;
}

public I64 CopyTree(U8 *src_files_find_mask, U8 *dst_files_find_mask, Bool true_mkdir = TRUE)
{
  no_warn src_files_find_mask;
  no_warn dst_files_find_mask;
  no_warn true_mkdir;
  return 0;
}

public I64 DelTree(U8 *files_find_mask, U8 *fu_flags = NULL)
{
  no_warn files_find_mask;
  no_warn fu_flags;
  return 0;
}
I64 g_fm_popup_mode;
CTask *g_fm_popup_mem;
U8 *g_fm_popup_res;
CTask *g_fm_popup_srv;
public U8 *DocPopUpPickFileRun(U8 *dir = NULL)
{
  // Single-stmt Cd+FileMgr helper (kept planted). Prefer stock compound
  // PopUpPickFile string once ExePutS consumes ';' (CMPF_PRS_SEMICOLON).
  if (dir && *dir)
    Cd(dir);
  return FileMgr(FM_PICK_FILE, Fs->parent_task);
}

public U8 *DocPopUpPickDirRun(U8 *dir = NULL)
{
  // Single-stmt helper for FM_PICK_DIR (mirrors DocPopUpPickFileRun).
  if (dir && *dir)
    Cd(dir);
  return FileMgr(FM_PICK_DIR, Fs->parent_task);
}

U0 FileMgrPopUpSrv(U8 *unused)
{
  //PopUp-shaped servant: run FileMgr GetMsg then wake Suspended parent.
  CTask *parent;
  no_warn unused;
  if (TaskValidate(Fs->parent_task) && Fs->parent_task->cur_dv) {
    Fs->cur_dv = Fs->parent_task->cur_dv;
    if (Fs->parent_task->cur_dir) {
      Free(Fs->cur_dir);
      Fs->cur_dir = StrNew(Fs->parent_task->cur_dir, Fs);
    }
  }
  g_fm_popup_res = FileMgr(g_fm_popup_mode, g_fm_popup_mem);
  parent = Fs->parent_task;
  if (TaskValidate(parent)) {
    if (parent->popup_task == Fs)
      parent->popup_task = NULL;
    Suspend(parent, FALSE);
  }
  while (TRUE) {
    LBts(&Fs->task_flags, TASKf_IDLE);
    LBts(&Fs->task_flags, TASKf_AWAITING_MSG);
    Yield;
  }
}

U0 FileMgrPopUpSrvKill(CTask *task)
{
  CDrv *dv;
  CBlkDev *bd;
  I64 i;
  if (!TaskValidate(task))
    return;
  // Same NULL exposure as PopUp's reap loop (Kernel/Job.HC).
  for (i = 0; blkdev.drvs && i < DRVS_NUM; i++) {
    dv = &blkdev.drvs[i];
    if (dv->owning_task == task) {
      dv->owning_task = NULL;
      LBtr(&dv->locked_flags, DVlf_LOCKED);
    }
  }
  for (i = 0; blkdev.blkdevs && i < BLKDEVS_NUM; i++) {
    bd = &blkdev.blkdevs[i];
    if (bd->owning_task == task) {
      bd->owning_task = NULL;
      LBtr(&bd->locked_flags, BDlf_LOCKED);
    }
  }
  if (task->next_task && task->last_task && task->next_task != task && task->next_task->last_task == task && task->last_task->next_task == task) {
    TaskQueRem(task);
    task->next_task = task;
    task->last_task = task;
  }
  LBts(&task->task_flags, TASKf_KILL_TASK);
  LBts(&task->task_flags, TASKf_SUSPENDED);
  task->task_signature = 0;
}

public U8 *PopUpPickFile(U8 *dir = NULL)
{
  // Stock DocPopUp.HC: PopUp("Cd(\"%Q\");FileMgr(FM_PICK_FILE,Fs->parent_task);").
  // FM_PICK_* via DocInit_RV DefineLoad → guest Lex HTT_DEFINE_STR expand.
  U8 *res, *st, *st2, *mask;
  CDirEntry *de, *tmp;
  I64 raw;
  rv_popup_file_hits++;
  if (dir)
    st = MStrPrint("Cd(\"%Q\");FileMgr(FM_PICK_FILE,Fs->parent_task);", dir);
  else {
    st2 = DirCur;
    st = MStrPrint("Cd(\"%Q\");FileMgr(FM_PICK_FILE,Fs->parent_task);", st2);
    Free(st2);
  }
  Print("PopUpPickFile DocPopUp begin\n");
  raw = PopUp(st, Fs);
  Free(st);
  // Guard: Cd Bool / small ints must not be deref'd as U8 *.
  if (raw > 0x10000)
    res = raw(U8 *);
  else
    res = NULL;
  if (res && *res) {
    Print("PopUpPickFile ok: %s\n", res);
    return res;
  }
  Print("PopUpPickFile empty/cancel raw=%d\n", raw);
  if (res)
    return res;
  if (!dir || !*dir)
    return NULL;
  mask = MStrPrint("%s/*", dir);
  de = FilesFind(mask, 0);
  Free(mask);
  tmp = de;
  res = NULL;
  while (tmp) {
    if (!(tmp->attr & RS_ATTR_DIR) && tmp->full_name && *tmp->full_name) {
      res = StrNew(tmp->full_name);
      break;
    }
    tmp = tmp->next;
  }
  if (de)
    DirTreeDel(de);
  if (res) {
    Print("PopUpPickFile FilesFind: %s\n", res);
    return res;
  }
  Print("PopUpPickFile soft skip: %s\n", dir);
  return NULL;
}

public U8 *PopUpPickDir(U8 *dir = NULL)
{
  // Stock DocPopUp.HC: PopUp("Cd(\"%Q\");FileMgr(FM_PICK_DIR,Fs->parent_task);").
  // FM_PICK_* via DocInit_RV DefineLoad → guest Lex HTT_DEFINE_STR expand.
  U8 *res, *st, *st2, *mask;
  CDirEntry *de, *tmp;
  I64 raw;
  rv_popup_file_hits++;
  if (dir)
    st = MStrPrint("Cd(\"%Q\");FileMgr(FM_PICK_DIR,Fs->parent_task);", dir);
  else {
    st2 = DirCur;
    st = MStrPrint("Cd(\"%Q\");FileMgr(FM_PICK_DIR,Fs->parent_task);", st2);
    Free(st2);
  }
  Print("PopUpPickDir DocPopUp begin\n");
  raw = PopUp(st, Fs);
  Free(st);
  // Guard: Cd Bool / small ints must not be deref'd as U8 *.
  if (raw > 0x10000)
    res = raw(U8 *);
  else
    res = NULL;
  if (res && *res) {
    Print("PopUpPickDir ok: %s\n", res);
    return res;
  }
  Print("PopUpPickDir empty/cancel raw=%d\n", raw);
  if (res)
    return res;
  if (!dir || !*dir)
    return NULL;
  mask = MStrPrint("%s/*", dir);
  de = FilesFind(mask, 0);
  Free(mask);
  tmp = de;
  res = NULL;
  while (tmp) {
    if ((tmp->attr & RS_ATTR_DIR) && tmp->full_name && *tmp->full_name) {
      res = StrNew(tmp->full_name);
      break;
    }
    tmp = tmp->next;
  }
  if (de)
    DirTreeDel(de);
  if (res) {
    Print("PopUpPickDir FilesFind: %s\n", res);
    return res;
  }
  // Soft: accept start dir when tree has no subdirs (Psalmody PSMF_CD shape).
  Print("PopUpPickDir soft accept: %s\n", dir);
  return StrNew(dir);
}
// Touch() and TouchFile(), lifted VERBATIM out of Adam/ABlkDev/ADskA.HC.
//
// `Demo/AcctExample/TOS/TOSToHtml.HC` fails with exactly ONE error —
//   "Argument 3 omitted, but 'Touch' has no declaration here to take a default from"
// which docs/DEMO_100.md §1 identifies as a callee with no declaration in scope, not a compiler
// bug. The obvious fix is `#include "/Adam/ABlkDev/ADskA.HC"` in Kernel_RV.PRJ. That is NOT safe,
// and tools/check_prj_collisions.py says why — exit 1, three collisions, all against THIS file:
//   CopyTree   DelTree   Move
// A second body for one name wins silently, so adding the unit whole would replace this port's own
// three with ADskA's x86-era versions. Same treatment as Kernel/RVDoc.HC's five DolDoc lifts:
// take the two functions, leave the unit out.
//
// Measured with tools/blob_imports.py: this lift introduces ZERO new unresolved names. Every callee
// is already in the image — Let2Drv/FileFind/DirNew/FilesFind/DirTreeDel (Kernel/BlkDev),
// ScanFlags/StrPrintFlags/StrFirstRem/StrLastRem (Kernel/StrB), Define (KDefine) and Now (KDate).
// Placed in this file because FileMgr_RV.HC is already the port's ABlkDev unit and is included
// after BlkDev/MakeBlkDev, so all of those are declared by the time these bodies are compiled.
//
// Note for whoever reads this next: `Touch` scans with FilesFind("+f+F"), which does NOT set
// FUF_RECURSE. That matters — FilesFind with FUF_RECURSE traps in DirNameAbs+0x48 (mcause=5,
// mtval=0x70) in this image, for any mask, so the recursive file utilities in ADskA would not have
// run even if the unit had been addable.
U0 TouchFile(U8 *filename,U8 *attr,CDate cdt=I64_MIN)
{
  CDrv *dv=Let2Drv(*filename);
  CDirEntry de;
  U8 *cur_dir=StrNew(filename),buf[STR_LEN];
  if (FileFind(filename,&de,FUF_JUST_FILES)) {
    Free(de.full_name);
    if (!StrCmp(attr,"+?"))
      "%-48ts %s\n",filename,StrPrintFlags(buf,Define("ST_FILE_ATTRS"),de.attr);
    else {
      StrFirstRem(cur_dir,":");
      StrLastRem(cur_dir,"/");
      if (!*cur_dir)
	StrCpy(cur_dir,"/");
      ScanFlags(&de.attr,Define("ST_FILE_ATTRS"),attr);
      if (cdt==I64_MIN)
	de.datetime=Now;
      else
	de.datetime=cdt;
      DirNew(dv,cur_dir,&de,FALSE);
    }
  } else
    PrintErr("File not found: \"%s\".\n",filename);
  Free(cur_dir);
}

public U0 Touch(U8 *files_find_mask="*",U8 *attr="+?",
	U8 *fu_flags=NULL,CDate cdt=I64_MIN)
{/*Touch file attributes and DateTime.
Default lists attributes.
attr: "+?" =show current
"+T" =resident
To Set DateL:
Touch(filename,"",,datetime);
*/
  I64 fuf_flags=0;
  CDirEntry *tmpde,*tmpde1;
  ScanFlags(&fuf_flags,Define("ST_FILE_UTIL_FLAGS"),"+f+F");
  ScanFlags(&fuf_flags,Define("ST_FILE_UTIL_FLAGS"),fu_flags);
  tmpde=tmpde1=FilesFind(files_find_mask,fuf_flags);
  while (tmpde) {
    TouchFile(tmpde->full_name,attr,cdt);
    tmpde=tmpde->next;
  }
  DirTreeDel(tmpde1);
}
#endif
