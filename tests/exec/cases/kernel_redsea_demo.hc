// TempleOS's OWN RedSea filesystem running on RISC-V, over a RAM disk. Every storage layer here is
// the kernel's real HolyC (Kernel/BlkDev/*.HC, no asm): a CBlkDev of type BDT_RAM whose BlkRead/
// BlkWrite are plain MemCpy to/from a RAM buffer; the kernel's BlkDevAdd/BlkDevInit, which auto-
// format a blank disk as RedSea (RedSeaFmt writes the superblock + root directory + allocation
// bitmap); the kernel's FileWrite, which walks the RedSea directory and allocates contiguous
// clusters (RedSeaFileWrite/RedSeaDirNew/RedSeaAllocClus); and the kernel's own RedSeaFileRead. No
// device driver is needed — the BDT_RAM path never touches the x86 ATA port I/O. Only the boot
// scaffolding (heap + Adam) is the usual RISC-V setup. Supersedes the Phase-1 kernel_fs_demo.hc,
// which used a hand-rolled superblock rather than the real RedSea code.
//
// Read here goes through RedSeaFileRead directly (the exact FSt_REDSEA case FileRead dispatches to).
// The generic FileRead/Load wrapper additionally runs FileNameAbs->DirNameAbs, whose drive-letter
// handling still needs work under this minimal hand-mount — that is the next step (it gates Load).
#include "/Kernel/Kernel_RV.PRJ"
U0 UartS(U8 *s){ U8 *u=0x10000000; while(*s)*u=*s++; }
Bool CheckFile(U8 *name,U8 *want)
{//Read `name` back with the kernel's own RedSea read and compare to `want`.
  I64 size=0,attr=0;
  U8 *back=RedSeaFileRead(Fs->cur_dv,"/",name,&size,&attr);
  return back && size==StrLen(want) && !StrNCmp(back,want,StrLen(want));
}
I64 main(){
  // --- Boot scaffolding: heap + Adam (the proven RVKMain sequence, hand-wired; advisor: keep this
  // out of RVKMain so a storage failure and a boot failure don't look alike). Uses the kernel's MAlloc.
  CTask *adam=0x86900000; MemSet(adam,0,sizeof(CTask));
  Fs=adam; adam_task=adam;
  MemSet(the_heap,0,sizeof(CHeapCtrl)); heap_next=0x82000400; heap_end=0x86000000;
  CBlkPool *bp=0x86800000; BlkPoolInit(bp,0x2000); sys_code_bp=bp;
  CHeapCtrl *ah=HeapCtrlInit(NULL,NULL,bp); adam->code_heap=ah; adam->data_heap=ah;
  MemSet(SYS_FIXED_AREA,0,8192);
  TaskInit(adam,0);
  CCPU *gs=0x86A00000; MemSet(gs,0,sizeof(CCPU)); gs->seth_task=adam; adam->gs=gs; Gs=gs;
  RVYieldInit(&Fs);
  RVKernelInit();

  // --- Block-device tables (the runtime body of BlkDevsInitAll, minus its #exe MountIDEAuto which
  // would bring up the x86 IDE controller): blkdevs/drvs arrays + the drive-letter map.
  blkdev.blkdevs=CAlloc(sizeof(CBlkDev)*BLKDEVS_NUM);
  blkdev.drvs=CAlloc(sizeof(CDrv)*DRVS_NUM);
  I64 i; for (i=0;i<DRVS_NUM;i++) blkdev.let_to_drv[i]=&blkdev.drvs[i];

  // --- Register a 2 MB RAM disk on drive 'A'; BlkDevAdd->BlkDevInit auto-formats it RedSea.
  UartS("mounting a RAM disk and formatting it RedSea (kernel's own RedSeaFmt)...\n");
  CBlkDev *bd=BlkDevNextFreeSlot('A',BDT_RAM);
  bd->unit=0; bd->RAM_dsk=0; bd->max_blk=4096-1;       // RAM_dsk=0 -> BlkDevInit AMAllocs 4096*512 B
  BlkDevAdd(bd,I64_MIN,FALSE,TRUE);
  Drv('A');                                            // sets Fs->cur_dv, Fs->cur_dir="/"

  // --- Write two files with the kernel's own FileWrite, read them back with RedSeaFileRead.
  U8 *m1="hello from the real RedSea on RISC-V\n";
  U8 *m2="a second file, to exercise the cluster allocator\n";
  I64 w1=FileWrite("A:/HELLO.TXT",m1,StrLen(m1));
  I64 w2=FileWrite("A:/SECOND.TXT",m2,StrLen(m2));
  UartS("wrote A:/HELLO.TXT and A:/SECOND.TXT\n");
  Bool ok = w1>0 && w2>0 && CheckFile("HELLO.TXT",m1) && CheckFile("SECOND.TXT",m2);
  U8 line[128];
  StrPrint(line,"redsea test: files=2 read-back-both-match=%d %s\n", ok, ok?"OK":"BAD");
  UartS(line);
  return 0;
}
