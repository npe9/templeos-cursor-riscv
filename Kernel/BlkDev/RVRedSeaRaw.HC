// RVRedSeaRaw.HC — G9 legacy chicken-egg: contiguous RedSea file via VirtioBlk*.
// Used when RV_THIN_EMBED_BIN is unset (default thin embeds Kernel.BIN).
// No BlkDevAdd/RedSeaInit. SoftCall owns first mount in BIN. dirname="" = root.
// Compare boot AA55 via bytes — U16 signature2 sign-extends vs 0xAA55.
#ifndef RV_REDSEA_RAW_HC
#define RV_REDSEA_RAW_HC
U8 *RVRedSeaRawFileRead(U8 *dirname, U8 *filename, I64 *sz_out)
{
  U8 sec[512];
  I64 i, dclus, fclus, fsz, nblk, take;
  U8 *buf;
  CDirEntry *d;
  CRedSeaBoot *br;
  if (!filename || !*filename)
    return NULL;
  if (sz_out)
    *sz_out = 0;
  if (virtio_blk_kind == VBLK_KIND_NONE && VirtioBlkInit())
    return NULL;
  if (VirtioBlkRead(0, sec))
    return NULL;
  br = sec;
  if (br->signature != MBR_PT_REDSEA || sec[510] != 0x55 || sec[511] != 0xAA)
    return NULL;
  dclus = br->root_clus;
  if (dirname && *dirname) {
    if (VirtioBlkRead(dclus, sec))
      return NULL;
    dclus = -1;
    for (i = 0; i < BLK_SIZE / CDIR_SIZE; i++) {
      d = sec + i *CDIR_SIZE - offset(CDirEntry.start);
      if (!(d->attr & RS_ATTR_DIR) || !d->name[0])
        continue;
      if (!StrCmp(d->name, dirname)) {
        dclus = d->clus;
        break;
      }
    }
    if (dclus < 0)
      return NULL;
  }
  if (VirtioBlkRead(dclus, sec))
    return NULL;
  fclus = -1;
  fsz = 0;
  for (i = 0; i < BLK_SIZE / CDIR_SIZE; i++) {
    d = sec + i *CDIR_SIZE - offset(CDirEntry.start);
    if ((d->attr & RS_ATTR_DIR) || !d->name[0])
      continue;
    if (!StrCmp(d->name, filename)) {
      fclus = d->clus;
      fsz = d->size;
      break;
    }
  }
  if (fclus < 0 || fsz <= 0)
    return NULL;
  // Linear arena (thin KBootRV) or full heap — SoftCall freelist starts @0x86000000.
  buf = MAlloc(fsz);
  if (!buf)
    return NULL;
  nblk = (fsz + BLK_SIZE - 1) / BLK_SIZE;
  for (i = 0; i < nblk; i++) {
    if (VirtioBlkRead(fclus + i, sec)) {
      Free(buf);
      return NULL;
    }
    take = fsz - i *BLK_SIZE;
    if (take > BLK_SIZE)
      take = BLK_SIZE;
    MemCpy(buf + i *BLK_SIZE, sec, take);
  }
  if (sz_out)
    *sz_out = fsz;
  return buf;
}
#endif
