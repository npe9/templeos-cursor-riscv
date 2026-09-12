// FileSys9P_RV.HC — FSt_9P glue so stock FileRead/FilesFind/Cd hit virtfs via P:.
// FileRead/FilesFind use Virtio9p* helpers (real ninep_client in Virtio9p.HC).
// Do not extern ninep_client here — FileSys is included before Virtio9p in Kernel_RV.PRJ.
#ifndef RV_FILESYS_9P_HC
#define RV_FILESYS_9P_HC
#include "../NineP/NineP.HH"
extern I64 Virtio9pReadPath(U8 *path, U8 *buf, I64 cap);
extern U0 Virtio9pNormSharePath(U8 *path, U8 *out, I64 cap);
extern CDirEntry *Virtio9pFilesFindMask(U8 *dir, U8 *mask, I64 fuf_flags);
#define NINEP_FS_READ_CAP (4096 - P9_IOHDRSZ) // leave room for Rread hdr in 4KiB rsp
// True when path letter is P: (9P share) or :: with boot P.
Bool NinePPathIsOurs(U8 *path)
{
  U8 let;
  if (!path || !path[0] || path[1] != ':')
    return FALSE;
  let = path[0];
  if (let == ':')
    let = blkdev.boot_drv_let;
  else
    let = ToUpper(let);
  return let == 'P';
}
// DirContext / stock Cd on FSt_9P: string Cd only (no Twalk/Lopen — hang-prone
// after nested Treaddir). Skip Name2DirClus/DrvLock; FilesFind validates via walk.
Bool NinePCd(U8 *parent, U8 *name)
{
  parent = parent;
  name = name;
  return TRUE;
}

U8 *NinePFileRead(CDrv *dv, U8 *cur_dir, U8 *filename, I64 *_size, I64 *_attr)
{
  U8 path[256], share[256], *buf;
  I64 n;
  DrvChk(dv);
  if (_size)
    *_size = 0;
  if (_attr)
    *_attr = 0;
  if (dv->fs_type != FSt_9P || !filename || !*filename)
    return NULL;
  path[0] = 0;
  if (cur_dir && cur_dir[0] && StrCmp(cur_dir, "/")) {
    if (cur_dir[0] == '/')
      StrPrint(path, "%s/%s", cur_dir + 1, filename);
    else
      StrPrint(path, "%s/%s", cur_dir, filename);
  } else
    StrCpy(path, filename);
  Virtio9pNormSharePath(path, share, 256);
  if (!share[0])
    StrCpy(share, path);
  buf = MAlloc(NINEP_FS_READ_CAP + 1);
  n = Virtio9pReadPath(share, buf, NINEP_FS_READ_CAP);
  if (n < 0) {
    Free(buf);
    return NULL;
  }
  buf[n] = 0;
  if (_size)
    *_size = n;
  if (_attr)
    *_attr = FileAttr(filename, 0);
  return buf;
}

CDirEntry *NinePFilesFind(U8 *files_find_mask, I64 fuf_flags, CDirEntry *parent = NULL)
{
  U8 share[256], *dir = NULL;
  parent = parent;
  // Relative mask under Fs->cur_dir after DirContext Cd("P:/…").
  if (Fs->cur_dir && Fs->cur_dir[0] && StrCmp(Fs->cur_dir, "/")) {
    Virtio9pNormSharePath(Fs->cur_dir, share, 256);
    if (share[0])
      dir = share;
  }
  return Virtio9pFilesFindMask(dir, files_find_mask, fuf_flags);
}

Bool NinePFileFind(CDrv *dv, I64 cur_dir_clus, U8 *name, CDirEntry *_res, I64 fuf_flags = 0)
{
  CDirEntry *tmp, *de;
  Bool ok = FALSE;
  U8 share[256], *dir = NULL;
  cur_dir_clus = cur_dir_clus;
  if (!dv || dv->fs_type != FSt_9P || !name || !*name)
    return FALSE;
  if (_res)
    MemSet(_res, 0, sizeof(CDirEntry));
  if (Fs->cur_dir && Fs->cur_dir[0] && StrCmp(Fs->cur_dir, "/")) {
    Virtio9pNormSharePath(Fs->cur_dir, share, 256);
    if (share[0])
      dir = share;
  }
  tmp = Virtio9pFilesFindMask(dir, "*", fuf_flags & (FUF_JUST_FILES | FUF_JUST_DIRS));
  de = tmp;
  while (de) {
    if (!StrCmp(de->name, name)) {
      if (_res) {
        MemCpy(_res, de, sizeof(CDirEntry));
        _res->next = NULL;
        _res->parent = NULL;
        _res->sub = NULL;
        _res->full_name = NULL;
        if (de->full_name)
          _res->full_name = StrNew(de->full_name);
      }
      ok = TRUE;
      break;
    }
    de = de->next;
  }
  DirTreeDel(tmp);
  return ok;
}
// DirContext-free FileRead for FSt_9P — avoids Drv/Cd hang on soft P:.
U8 *NinePTryFileRead(U8 *filename, I64 *_size, I64 *_attr)
{
  U8 share[256], *buf;
  I64 n;
  if (_size)
    *_size = 0;
  if (_attr)
    *_attr = 0;
  if (!NinePPathIsOurs(filename))
    return NULL;
  Virtio9pNormSharePath(filename, share, 256);
  if (!share[0])
    return NULL;
  buf = MAlloc(NINEP_FS_READ_CAP + 1);
  n = Virtio9pReadPath(share, buf, NINEP_FS_READ_CAP);
  if (n < 0) {
    Free(buf);
    return NULL;
  }
  buf[n] = 0;
  if (_size)
    *_size = n;
  if (_attr)
    *_attr = FileAttr(filename, 0);
  return buf;
}
// DirContext-free FilesFind for FSt_9P ("P:/*" root; "P:/dir/*" nested walk).
CDirEntry *NinePTryFilesFind(U8 *files_find_mask, I64 fuf_flags)
{
  U8 share[256], *mask, *dir;
  if (!NinePPathIsOurs(files_find_mask))
    return NULL;
  Virtio9pNormSharePath(files_find_mask, share, 256);
  mask = share;
  while (*mask)
    mask++;
  while (mask > share && mask[-1] != '/')
    mask--;
  if (mask > share && mask[-1] == '/') {
    mask[-1] = 0;
    // share = dir path; mask = leaf pattern
    dir = share;
  } else {
    mask = share;
    dir = NULL;
  }
  return Virtio9pFilesFindMask(dir, mask, fuf_flags);
}
#endif
