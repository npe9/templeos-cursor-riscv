// Running a program loaded off a REAL virtio-blk disk on RISC-V. main() writes a precompiled HolyC program (a
// position-independent blob, emitted to build/exec/prog_arr.hc at test time from prog_hello.hc) to
// the kernel's own RedSea filesystem, then reads it back with FileRead and executes it with
// RVRunBlob — which resolves the blob's import trailer in place (against the runtime table) and
// jumps to its entry. The loaded program prints and returns fib(10)=55. This is "load and run a
// program from the filesystem", the first step of the Load/ExeFile path — using only PC-relative
// AOT code, the RedSea FS, and import resolution; no CBinFile/relocation machinery.
#include "/Kernel/Kernel_RV.PRJ"
#include "/build/exec/prog_arr.hc"
U0 Sh(U8 *s){ U8 *u=0x10000000; while(*s)*u=*s++; }
I64 main()
{
  CTask *adam=0x86900000; MemSet(adam,0,sizeof(CTask)); Fs=adam; adam_task=adam;
  MemSet(the_heap,0,sizeof(CHeapCtrl)); heap_next=0x82000400; heap_end=0x86000000;
  CBlkPool *bp=0x86800000; BlkPoolInit(bp,0x2000); sys_code_bp=bp;
  CHeapCtrl *ah=HeapCtrlInit(NULL,NULL,bp); adam->code_heap=ah; adam->data_heap=ah;
  MemSet(SYS_FIXED_AREA,0,8192); TaskInit(adam,0);
  CCPU *gs=0x86A00000; MemSet(gs,0,sizeof(CCPU)); gs->seth_task=adam; adam->gs=gs; Gs=gs;
  RVYieldInit(&Fs); RVKernelInit();
  RVMountVirtioDisk('A');
  Sh("writing program to the virtio disk A:/HELLO.PRG...\n");
  FileWrite("A:/HELLO.PRG",prog_blob,prog_blob_size);
  I64 sz=0; U8 *code=FileRead("A:/HELLO.PRG",&sz,NULL);
  U8 lb[64]; StrPrint(lb,"read %d bytes back; running it...\n",sz); Sh(lb);
  I64 r=RVRunBlob(code,sz);
  StrPrint(lb,"loaded program returned %d (want 55)\n",r); Sh(lb);
  return 0;
}
