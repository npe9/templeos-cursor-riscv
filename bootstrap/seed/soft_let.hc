// soft_let.hc -- G28 UART soft BlkDev letter tables (match Kernel RVSoftLetPlant).
// Thin repl-holyc has no Kernel BlkDev.HC; plant signed CBlkDev + CDrv so
// Let2Drv('A') / Let2Drv('P') / Let2Drv(':') work without virtio. Does NOT invent
// cur_dv — memfs Cd/Pwd stay on the ::/… FsResolve bridge (see docs/PATHS.md).
// P: is the 9P/virtfs share letter (Kernel RVSoftLet9pPlant / Virtio9pConnect).
#define BLKDEVS_NUM 26
#define DRVS_NUM 26
#define BD_SIGNATURE_VAL 'BDSV'
#define DRV_SIGNATURE_VAL 'DVSV'
#define BDT_NULL 0
#define BDT_RAM 1
#define BDT_ISO_FILE_READ 3
#define FSt_UNKNOWN 5
class CBlkDev
{
  U32 bd_signature;
  U32 type;
  U32 flags;
  U8 first_drv_let;
  U8 unit;
  U8 pad[2];
  I64 drv_offset;
  I64 max_blk;
  U8 *RAM_dsk;
};

class CDrv
{
  I64 locked_flags;
  U32 dv_signature;
  U8 drv_let;
  U8 pad;
  U16 fs_type;
  I64 drv_offset;
  I64 size;
  CBlkDev *bd;
};

class CBlkDevGlbls
{
  CBlkDev *blkdevs;
  CDrv *drvs;
  CDrv *let_to_drv[32];
  U8 boot_drv_let;
};
CBlkDevGlbls blkdev;
U0 RVBlkDevTablesInit()
{
  I64 i;
  if (blkdev.blkdevs)
    return;
  blkdev.blkdevs = CAlloc(sizeof(CBlkDev) * BLKDEVS_NUM);
  blkdev.drvs = CAlloc(sizeof(CDrv) * DRVS_NUM);
  for (i = 0; i < DRVS_NUM; i++)
    blkdev.let_to_drv[i] = &blkdev.drvs[i];
}

CDrv *DrvChk(CDrv *dv, Bool except = TRUE)
{
  if (!dv || dv->dv_signature != DRV_SIGNATURE_VAL) {
    if (except)
      return NULL;
    return NULL;
  }
  return dv;
}

U8 Let2Let(U8 drv_let = 0)
{
  if (!drv_let)
    return 0;
  if (drv_let == ':')
    drv_let = blkdev.boot_drv_let;
  return ToUpper(drv_let);
}
// Match Kernel DskDrv Let2BlkDevType letter bands (P: → ISO_FILE_READ map).
I64 Let2BlkDevType(U8 drv_let)
{
  drv_let = Let2Let(drv_let);
  if ('A' <= drv_let && drv_let <= 'B')
    return BDT_RAM;
  if ('C' <= drv_let && drv_let <= 'L')
    return BDT_RAM;
  // UART soft: ATA unused; keep plantable
  if ('M' <= drv_let && drv_let <= 'P')
    return BDT_ISO_FILE_READ;
  if ('Q' <= drv_let && drv_let <= 'Z')
    return BDT_RAM;
  return BDT_NULL;
}

CDrv *Let2Drv(U8 drv_let = 0, Bool except = TRUE)
{
  CDrv *dv;
  if (!drv_let) {
    // UART: no Fs->cur_dv — soft letter only (same honesty as Kernel !cur_dv).
    return NULL;
  }
  drv_let = Let2Let(drv_let);
  if (!('A' <= drv_let && drv_let <= 'Z'))
    return NULL;
  dv = blkdev.let_to_drv[drv_let - 'A'];
  return DrvChk(dv, except);
}
// Idempotent soft plant — mirrors Kernel/KBootRV.HC RVSoftLetPlant.
CDrv *RVSoftLetPlant(U8 drv_let = 'A')
{
  CBlkDev *bd;
  CDrv *dv;
  I64 i, type;
  drv_let = ToUpper(drv_let);
  if (!('A' <= drv_let && drv_let <= 'Z'))
    return NULL;
  RVBlkDevTablesInit;
  if (dv = Let2Drv(drv_let, FALSE))
    return dv;
  type = Let2BlkDevType(drv_let);
  if (type == BDT_NULL)
    return NULL;
  bd = NULL;
  for (i = 0; i < BLKDEVS_NUM; i++) {
    if (blkdev.blkdevs[i].bd_signature != BD_SIGNATURE_VAL) {
      bd = &blkdev.blkdevs[i];
      break;
    }
  }
  if (!bd)
    return NULL;
  MemSet(bd, 0, sizeof(CBlkDev));
  bd->first_drv_let = drv_let;
  bd->type = type;
  bd->unit = 0;
  bd->RAM_dsk = 0;
  bd->max_blk = 0;
  bd->bd_signature = BD_SIGNATURE_VAL;
  dv = &blkdev.drvs[drv_let - 'A'];
  MemSet(dv, 0, sizeof(CDrv));
  dv->drv_let = drv_let;
  dv->bd = bd;
  dv->drv_offset = 0;
  dv->size = 0;
  dv->dv_signature = DRV_SIGNATURE_VAL;
  dv->fs_type = FSt_UNKNOWN;
  if (!blkdev.boot_drv_let)
    blkdev.boot_drv_let = drv_let;
  Print("RVSoftLetPlant: let=%c boot=%c type=%d (uart memfs)\n", drv_let, blkdev.boot_drv_let, type);
  return dv;
}
// G28: P: = 9P/virtfs share letter (Kernel RVSoftLet9pPlant).
CDrv *RVSoftLet9pPlant(U8 drv_let = 'P')
{
  CDrv *dv;
  drv_let = ToUpper(drv_let);
  if (!drv_let)
    drv_let = 'P';
  dv = RVSoftLetPlant(drv_let);
  if (dv)
    Print("RVSoftLet9pPlant: let=%c (9P share)\n", dv->drv_let);
  return dv;
}
// Smoke / dig-down: prove Let2Drv('A')/('P')/(':') after plant; Cd("P:/…") grammar.
U0 SoftLetRep()
{
  CDrv *dv;
  dv = Let2Drv('A', FALSE);
  if (!dv) {
    Print("Soft Let2Drv A: FAIL null\n");
    return;
  }
  if (!Let2Drv(':', FALSE)) {
    Print("Soft Let2Drv :: FAIL null\n");
    return;
  }
  Print("Soft Let2Drv A: ok drv=%c boot=%c\n", dv->drv_let, blkdev.boot_drv_let);
  dv = Let2Drv('P', FALSE);
  if (!dv) {
    Print("Soft Let2Drv P: FAIL null\n");
    return;
  }
  Print("Soft Let2Drv P: ok drv=%c\n", dv->drv_let);
  // UART Cd returns 0 on success (I64); restore cwd so later smoke cases stay honest.
  if (Cd("P:/Home")) {
    Print("Soft Cd P:/Home FAIL\n");
    return;
  }
  Print("Soft Cd P: ok cwd=::/Home/\n");
  Cd("/");
}
