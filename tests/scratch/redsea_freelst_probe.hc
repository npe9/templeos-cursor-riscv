#include "/Kernel/Kernel_RV.PRJ"
#define MEM_UART 0x10000000
U0 UartS(U8 *s) { U8 *u = MEM_UART; while (*s) *u = *s++; }
U0 UartHex(I64 x) {
  U8 b[20]; I64 i=18; b[19]=0;
  if (!x) { UartS("0"); return; }
  while (x && i>=0) { I64 d=x&15; b[i--]=d<10?'0'+d:'a'+d-10; x>>=4; }
  UartS(b+i+1);
}
I64 main() {
  CTask *adam = 0x86900000;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam; adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400; heap_end = 0x86000000;
  CBlkPool *bp = 0x86800000;
  BlkPoolInit(bp, 0x2000); sys_code_bp = bp;
  CHeapCtrl *ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah; adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0);
  CCPU *gs = 0x86A00000; MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam; adam->gs = gs; Gs = gs;
  RVYieldInit(&Fs); RVKernelInit();
  blkdev.blkdevs = CAlloc(sizeof(CBlkDev) * BLKDEVS_NUM);
  blkdev.drvs = CAlloc(sizeof(CDrv) * DRVS_NUM);
  I64 i; for (i = 0; i < DRVS_NUM; i++) blkdev.let_to_drv[i] = &blkdev.drvs[i];
  CBlkDev *bd = BlkDevNextFreeSlot('A', BDT_RAM);
  bd->unit = 0; bd->RAM_dsk = 0; bd->max_blk = 64 - 1; // SMALL disk
  bd->bd_signature=BD_SIGNATURE_VAL;
  CDrv *dv=DrvMakeFreeSlot(bd->first_drv_let);
  dv->bd=bd; dv->drv_offset=bd->drv_offset;
  dv->size=bd->max_blk+1-bd->drv_offset;
  dv->dv_signature=DRV_SIGNATURE_VAL; dv->fs_type=FSt_REDSEA;
  LBts(&bd->flags,BDf_INITIALIZED);
  bd->flags|=BDF_INIT_IN_PROGRESS;
  bd->RAM_dsk=AMAlloc((bd->max_blk+1)<<BLK_SIZE_BITS);
  bd->max_blk=MSize(bd->RAM_dsk)>>BLK_SIZE_BITS-1;
  dv->size=bd->max_blk+1-bd->drv_offset;
  CRedSeaBoot *br=CAlloc(BLK_SIZE);
  DrvLock(dv);
  br->signature=MBR_PT_REDSEA; br->signature2=0xAA55;
  br->drv_offset=dv->drv_offset; br->sects=dv->size;
  I64 n=(br->sects+BLK_SIZE<<3-1)/BLK_SIZE<<3;
  br->bitmap_sects=n; br->root_clus=0;
  UartS("n="); UartHex(n); UartS(" size="); UartHex(dv->size); UartS("\n");
  BlkWriteZero(dv,dv->drv_offset,n+1);
  BlkWrite(dv,br,dv->drv_offset,1);
  RedSeaInit(dv);
  UartS("data_area="); UartHex(dv->data_area); UartS(" fat1="); UartHex(dv->fat1); UartS("\n");
  UartS("B1 FreeLstBuild\n");
  RedSeaFreeLstBuild(dv);
  UartS("B2 build ok\n");
  DrvUnlock(dv);
  UartS("B3 done\n");
  return 0;
}
