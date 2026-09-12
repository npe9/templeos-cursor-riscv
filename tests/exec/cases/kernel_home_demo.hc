// HomeSet / Cd("~") without RedSeaFmt (Fmt→ClusAlloc/FreeLstBuild hang is a
// separate WIP). Soft letter plant proves Let2Drv pre-mount; then RAM slot +
// HomeSet(A:/Home) proves stock ~.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  CTask *adam = 0x86900000;
  CBlkDev *bd;
  CDrv *dv;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  U8 *st;
  I64 i;
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
  gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVYieldInit(&Fs);
  RVKernelInit();
  blkdev.blkdevs = CAlloc(sizeof(CBlkDev) * BLKDEVS_NUM);
  blkdev.drvs = CAlloc(sizeof(CDrv) * DRVS_NUM);
  for (i = 0; i < DRVS_NUM; i++)
    blkdev.let_to_drv[i] = &blkdev.drvs[i];
  // G28 soft Cd / DirCur honesty: pre-mount Cd(__DIR__)-shape must Pwd as ::/…
  // (host __DIR__ / UART Pwd), not bare Unix /… .
  if (Fs->cur_dv) {
    Print("SoftCd pre-mount FAIL unexpected cur_dv\n");
    return 1;
  }
  if (!Cd("::/Apps/Span")) {
    Print("SoftCd ::/Apps/Span FAIL\n");
    return 1;
  }
  st = DirCur;
  if (!st || StrCmp(st, "::/Apps/Span")) {
    Print("SoftCd DirCur FAIL got=%s want=::/Apps/Span\n", st);
    Free(st);
    return 1;
  }
  Print("SoftCd DirCur ok dir=%s\n", st);
  Free(st);
  if (!Cd("A:/Home")) {
    Print("SoftCd A:/Home FAIL\n");
    return 1;
  }
  st = DirCur;
  if (!st || StrCmp(st, "::/Home")) {
    Print("SoftCd DirCur A: FAIL got=%s want=::/Home\n", st);
    Free(st);
    return 1;
  }
  Print("SoftCd DirCur A: ok dir=%s\n", st);
  Free(st);
  // Soft DirNameAbs must not Drv2Let-throw; A:/… → ::/… while !cur_dv.
  st = DirNameAbs("A:/Home");
  if (!st || StrCmp(st, "::/Home")) {
    Print("Soft DirNameAbs A: FAIL got=%s want=::/Home\n", st);
    Free(st);
    return 1;
  }
  Print("Soft DirNameAbs A: ok dir=%s\n", st);
  Free(st);
  // G28 soft letter: Let2Drv works without virtio / RedSeaFmt; cur_dv stays null.
  if (Let2Drv('A', FALSE)) {
    Print("Soft Let2Drv A: FAIL unexpected mounted drv before plant\n");
    return 1;
  }
  if (!RVSoftLetPlant('A')) {
    Print("RVSoftLetPlant FAIL\n");
    return 1;
  }
  if (!(dv = Let2Drv('A', FALSE))) {
    Print("Soft Let2Drv A: FAIL null after plant\n");
    return 1;
  }
  if (!(dv = Let2Drv(':', FALSE))) {
    Print("Soft Let2Drv :: FAIL null after plant\n");
    return 1;
  }
  if (Fs->cur_dv) {
    Print("Soft Let2Drv plant FAIL unexpected cur_dv\n");
    return 1;
  }
  Print("Soft Let2Drv A: ok drv=%c boot=%c\n", dv->drv_let, blkdev.boot_drv_let);
  // Soft DirNameAbs still ::/… (letter mounted for Let2Drv, not selected as cur_dv).
  st = DirNameAbs("A:/Home");
  if (!st || StrCmp(st, "::/Home")) {
    Print("Soft DirNameAbs post-plant FAIL got=%s want=::/Home\n", st);
    Free(st);
    return 1;
  }
  Print("Soft DirNameAbs post-plant ok dir=%s\n", st);
  Free(st);
  // G28: P: = 9P share letter (RVSoftLet9pPlant); soft Cd/DirNameAbs stay ::/….
  if (Let2Drv('P', FALSE)) {
    Print("Soft Let2Drv P: FAIL unexpected mounted drv before plant\n");
    return 1;
  }
  if (!RVSoftLet9pPlant('P')) {
    Print("RVSoftLet9pPlant FAIL\n");
    return 1;
  }
  if (!(dv = Let2Drv('P', FALSE))) {
    Print("Soft Let2Drv P: FAIL null after plant\n");
    return 1;
  }
  if (Fs->cur_dv) {
    Print("Soft Let2Drv P plant FAIL unexpected cur_dv\n");
    return 1;
  }
  Print("Soft Let2Drv P: ok drv=%c type=%d\n", dv->drv_let, dv->bd->type);
  if (!Cd("P:/Host")) {
    Print("SoftCd P:/Host FAIL\n");
    return 1;
  }
  st = DirCur;
  if (!st || StrCmp(st, "::/Host")) {
    Print("SoftCd DirCur P: FAIL got=%s want=::/Host\n", st);
    Free(st);
    return 1;
  }
  Print("SoftCd DirCur P: ok dir=%s\n", st);
  Free(st);
  st = DirNameAbs("P:/Host");
  if (!st || StrCmp(st, "::/Host")) {
    Print("Soft DirNameAbs P: FAIL got=%s want=::/Host\n", st);
    Free(st);
    return 1;
  }
  Print("Soft DirNameAbs P: ok dir=%s\n", st);
  Free(st);
  // Upgrade soft letter in place to a tiny RAM RedSea slot (no second BlkDevNextFreeSlot).
  bd = Let2BlkDev('A');
  if (!bd) {
    Print("Soft Let2BlkDev A: FAIL\n");
    return 1;
  }
  bd->unit = 0;
  bd->RAM_dsk = 0;
  bd->max_blk = 8 - 1;
  bd->bd_signature = BD_SIGNATURE_VAL;
  LBts(&bd->flags, BDf_INITIALIZED);
  bd->RAM_dsk = AMAlloc ((bd->max_blk + 1) << BLK_SIZE_BITS);
  bd->max_blk = MSize(bd->RAM_dsk) >> BLK_SIZE_BITS - 1;
  dv = Let2Drv('A');
  dv->bd = bd;
  dv->drv_offset = bd->drv_offset;
  dv->size = bd->max_blk + 1 - bd->drv_offset;
  dv->dv_signature = DRV_SIGNATURE_VAL;
  dv->fs_type = FSt_REDSEA;
  Drv('A');
  RVHomeBringUp('A');
  if (!blkdev.home_dir || StrCmp(blkdev.home_dir, "A:/Home")) {
    Print("RVHomeBringUp FAIL home=%s\n", blkdev.home_dir);
    return 1;
  }
  if (!Cd("~")) {
    Print("Cd(~) FAIL\n");
    return 1;
  }
  st = DirCur;
  Print("RVHomeBringUp Cd(~) ok dir=%s home=%s\n", st, blkdev.home_dir);
  Free(st);
  // SoftCd null stay-put must not become stock Cd("~") rewrite.
  if (!RVWinSoftCd(NULL)) {
    Print("SoftCd null FAIL\n");
    return 1;
  }
  Print("RVHomeBringUp SoftCd null stay-put ok\n");
  return 0;
}
