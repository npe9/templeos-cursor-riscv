// TempleOS's OWN RedSea filesystem running on a REAL disk over the kernel's native virtio-blk driver.
// This ties the whole stack together: the kernel's block layer (BlkRead/BlkWrite) dispatches a new
// BDT_VIRTIO type to VirtioBlkRead/VirtioBlkWrite (Kernel/BlkDev/DskVirtioRV.HC), so RedSeaFmt formats,
// and FileWrite/FileRead read and write, an actual virtio-mmio disk -- no RAM disk, no ATA. QEMU virt
// is launched with a blank 4096-sector image; RVMountVirtioDisk brings the device up and mounts it as
// drive A:, BlkDevAdd formats it RedSea, then a file is written and read back off the real disk.
#include "/Kernel/Kernel_RV.PRJ"
U0 Sh(U8 *s){ U8 *u=0x10000000; while(*s)*u=*s++; }
I64 main()
{
  // Boot scaffolding + mount (same as the RAM-disk fsshell demo, but a real virtio disk).
  CTask *adam=0x86900000; MemSet(adam,0,sizeof(CTask)); Fs=adam; adam_task=adam;
  MemSet(the_heap,0,sizeof(CHeapCtrl)); heap_next=0x82000400; heap_end=0x86000000;
  CBlkPool *bp=0x86800000; BlkPoolInit(bp,0x2000); sys_code_bp=bp;
  CHeapCtrl *ah=HeapCtrlInit(NULL,NULL,bp); adam->code_heap=ah; adam->data_heap=ah;
  MemSet(SYS_FIXED_AREA,0,8192); TaskInit(adam,0);
  CCPU *gs=0x86A00000; MemSet(gs,0,sizeof(CCPU)); gs->seth_task=adam; adam->gs=gs; Gs=gs;
  RVYieldInit(&Fs); RVKernelInit();

  Sh("mounting a real virtio-blk disk and formatting it RedSea (kernel's own driver + block layer)...\n");
  RVMountVirtioDisk('A');
  HomeSet("A:/");
  FileWrite("A:/HELLO.TXT", "hello from a real virtio disk", 29);
  Sh("wrote A:/HELLO.TXT to the virtio disk\n");
  I64 sz=0; U8 *b=FileRead("A:/HELLO.TXT", &sz, NULL);
  if (b && sz==29 && !StrNCmp(b, "hello from a real virtio disk", 29))
    Sh("virtio RedSea read-back OK\n");
  else
    Sh("virtio RedSea FAILED\n");
  return 0;
}
