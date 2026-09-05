// FileMgr_RV.HC — stock Adam/ABlkDev/FileMgr.HC FMRebuildDocDrv + soft shims.
// DirFileDoc lives in Kernel/RVDoc.HC; MenuPop in Menu_RV — do not redefine here.
// RVFileMgrOpen lives in RVWinMgr (same unit as CRVWin; avoid ABS_ADDR BSS).
// PopUpPickFile: FilesFind first-file (stock FileMgr(FM_PICK_FILE) GetMsg deferred).
#ifndef FILE_MGR_RV_HC
#define FILE_MGR_RV_HC
#ifndef FM_NORMAL
#define FM_NORMAL	0
#define FM_PICK_FILE	1
#define FM_PICK_DIR	2
#endif
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

public U8 *PopUpPickFile(U8 *dir = NULL)
{
  //Libs-first FM_PICK_FILE stand-in: FilesFind first non-dir under dir/*.
  // Stock DocPopUp PopUpPickFile → PopUp(FileMgr(FM_PICK_FILE)) still needs
  // FileMgr() GetMsg + focus loop (deferred). SpanRead uses this path.
  CDirEntry *de, *tmp;
  U8 *mask, *res = NULL;
  rv_popup_file_hits++;
  if (!dir || !*dir)
    return NULL;
  mask = MStrPrint("%s/*", dir);
  de = FilesFind(mask, 0);
  Free(mask);
  tmp = de;
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
#endif
