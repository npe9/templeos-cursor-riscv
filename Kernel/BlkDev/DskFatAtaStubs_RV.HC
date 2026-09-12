// Thin-loader stubs: FAT32 / ATA / ATAPI / ISO surfaces referenced from BlkDev
// switch arms. SoftCall mounts BDT_VIRTIO RedSea only — these paths never run.
// Replaces FileSysFAT + DskATA + DskATAId + DskCDDVD under RV_THIN_LOADER.
#ifndef DSK_FAT_ATA_STUBS_RV_HC
#define DSK_FAT_ATA_STUBS_RV_HC
Bool ATAInit(CBlkDev *bd)
{
  no_warn bd;
  return FALSE;
}

U0 ATAReadBlks(CBlkDev *bd, U8 *buf, I64 blk, I64 cnt)
{
  no_warn bd;
  no_warn buf;
  no_warn blk;
  no_warn cnt;
}

U0 ATAWriteBlks(CBlkDev *bd, U8 *buf, I64 blk, I64 cnt)
{
  no_warn bd;
  no_warn buf;
  no_warn blk;
  no_warn cnt;
}

Bool ATARBlks(CDrv *dv, U8 *buf, I64 blk, I64 cnt)
{
  no_warn dv;
  no_warn buf;
  no_warn blk;
  no_warn cnt;
  return FALSE;
}

Bool ATAWBlks(CDrv *dv, U8 *buf, I64 blk, I64 cnt)
{
  no_warn dv;
  no_warn buf;
  no_warn blk;
  no_warn cnt;
  return FALSE;
}

U0 FAT32Init(CDrv *dv)
{
  no_warn dv;
}

U0 FAT32Fmt(U8 drv_let, Bool quick = TRUE)
{
  no_warn drv_let;
  no_warn quick;
}

Bool FAT32FileFind(CDrv *dv, I64 cur_dir_clus, U8 *name, CDirEntry *_res, I64 fuf_flags = 0)
{
  no_warn dv;
  no_warn cur_dir_clus;
  no_warn name;
  no_warn fuf_flags;
  if (_res)
    MemSet(_res, 0, sizeof(CDirEntry));
  return FALSE;
}

U8 *FAT32FileRead(CDrv *dv, U8 *cur_dir, U8 *filename, I64 *_size, I64 *_attr)
{
  no_warn dv;
  no_warn cur_dir;
  no_warn filename;
  if (_size)
    *_size = 0;
  if (_attr)
    *_attr = 0;
  return NULL;
}

I64 FAT32FileWrite(CDrv *dv, U8 *cur_dir, U8 *name, U8 *buf, I64 size, CDate cdt, I64 attr)
{
  no_warn dv;
  no_warn cur_dir;
  no_warn name;
  no_warn buf;
  no_warn size;
  no_warn cdt;
  no_warn attr;
  return 0;
}

I64 FAT32FilesDel(CDrv *dv, U8 *cur_dir, U8 *files_find_mask, I64 fuf_flags, Bool del_dir, Bool print_msg)
{
  no_warn dv;
  no_warn cur_dir;
  no_warn files_find_mask;
  no_warn fuf_flags;
  no_warn del_dir;
  no_warn print_msg;
  return 0;
}

CDirEntry *FAT32FilesFind(U8 *files_find_mask, I64 fuf_flags, CDirEntry *parent = NULL, I64 *_dir_size = NULL)
{
  no_warn files_find_mask;
  no_warn fuf_flags;
  no_warn parent;
  if (_dir_size)
    *_dir_size = 0;
  return NULL;
}

Bool FAT32DirNew(CDrv *dv, U8 *cur_dir, CDirEntry *tmpde, Bool free_old_chain)
{
  no_warn dv;
  no_warn cur_dir;
  no_warn tmpde;
  no_warn free_old_chain;
  return FALSE;
}

Bool FAT32Cd(U8 *name, I64 cur_dir_clus)
{
  no_warn name;
  no_warn cur_dir_clus;
  return FALSE;
}

Bool FAT32MkDir(CDrv *dv, U8 *cur_dir, U8 *name, I64 entry_cnt)
{
  no_warn dv;
  no_warn cur_dir;
  no_warn name;
  no_warn entry_cnt;
  return FALSE;
}

I64 FAT32AllocClus(CDrv *dv, I64 c, I64 cnt)
{
  no_warn dv;
  no_warn c;
  no_warn cnt;
  return 0;
}

I64 FAT32AllocContiguousClus(CDrv *dv, I64 cnt)
{
  no_warn dv;
  no_warn cnt;
  return 0;
}

Bool ISOInit(CDrv *dv, I64 blk)
{
  no_warn dv;
  no_warn blk;
  return FALSE;
}
#endif
