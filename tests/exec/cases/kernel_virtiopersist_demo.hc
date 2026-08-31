// Persistence across a reboot on a real virtio-blk disk. The same program runs twice against the same
// disk image: on the first boot RVMountVirtioDisk finds a blank disk and RedSeaFmts it, PERSIST.TXT is
// absent, so it writes the file. On the second boot the disk already holds a valid RedSea filesystem,
// so BlkDevInit takes the RedSeaValidate->RedSeaInit path (mount existing, NOT reformat) -- the mount
// path the format-a-blank-disk demo never exercises -- and the file is read straight back. This proves
// the kernel's own FS on its own driver gives real, durable storage: data written before the reboot is
// still there after it.
#include "/Kernel/Kernel_RV.PRJ"
#define MEM_UART 0x10000000
U0 Sh(U8 *s)
{
  U8 *u = MEM_UART;
  while (*s)
    *u = *s++;
}

I64 main()
{
  CTask *adam = 0x86900000;
  MemSet(adam, 0, sizeof(CTask));
  Fs = adam;
  adam_task = adam;
  MemSet(the_heap, 0, sizeof(CHeapCtrl));
  heap_next = 0x82000400;
  heap_end = 0x86000000;
  CBlkPool *bp = 0x86800000;
  BlkPoolInit(bp, 0x2000);
  sys_code_bp = bp;
  CHeapCtrl *ah = HeapCtrlInit(NULL, NULL, bp);
  adam->code_heap = ah;
  adam->data_heap = ah;
  MemSet(SYS_FIXED_AREA, 0, 8192);
  TaskInit(adam, 0);
  CCPU *gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVYieldInit(&Fs);
  RVKernelInit();
  RVMountVirtioDisk('A');
  HomeSet("A:/");
  U8 *b = NULL;
  I64 sz = 0;
  if (FilesFind("A:/PERSIST.TXT"))
    b = FileRead("A:/PERSIST.TXT", &sz, NULL);
  // avoid the not-found error
  if (b && sz == 24 && !StrNCmp(b, "data survived the reboot", 24))
    Sh("PERSISTED across reboot OK\n");
  else {
    FileWrite("A:/PERSIST.TXT", "data survived the reboot", 24);
    Sh("first boot: wrote PERSIST.TXT\n");
  }
  return 0;
}
