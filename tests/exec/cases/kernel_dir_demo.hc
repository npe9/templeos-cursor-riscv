// Directory operations on the kernel's OWN RedSea filesystem (RISC-V). Beyond flat files this
// exercises the real directory layer: DirMk creates subdirectories (RedSeaMkDir), Cd changes into
// one (DirContextNew/Name2DirClus), and FilesFind walks a directory returning the kernel's CDirEntry
// list. All of Kernel/BlkDev/*.HC — no asm, no device driver (BDT_RAM). Reuses RVMountRAMDisk
// (Kernel/KBootRV.HC). Depends on BOTH compiler fixes this milestone needed: the array-deref store
// width (DirNameAbs/Cd) and the implicit-print varargs ABI (DirMk's "Make Directory:%s" print).
// KNOWN LIMITATION: writing a file INTO a subdirectory (RedSeaFileWrite with a non-root cur_dir ->
// RedSeaDirNew) still hangs and is a separate follow-up; this demo writes files in the root only.
#include "/Kernel/Kernel_RV.PRJ"
U0 UartS(U8 *s){ U8 *u=0x10000000; while(*s)*u=*s++; }
I64 main()
{
  // Boot scaffolding: heap + Adam (same proven sequence RVKMain uses).
  CTask *adam=0x86900000; MemSet(adam,0,sizeof(CTask)); Fs=adam; adam_task=adam;
  MemSet(the_heap,0,sizeof(CHeapCtrl)); heap_next=0x82000400; heap_end=0x86000000;
  CBlkPool *bp=0x86800000; BlkPoolInit(bp,0x2000); sys_code_bp=bp;
  CHeapCtrl *ah=HeapCtrlInit(NULL,NULL,bp); adam->code_heap=ah; adam->data_heap=ah;
  MemSet(SYS_FIXED_AREA,0,8192); TaskInit(adam,0);
  CCPU *gs=0x86A00000; MemSet(gs,0,sizeof(CCPU)); gs->seth_task=adam; adam->gs=gs; Gs=gs;
  RVYieldInit(&Fs); RVKernelInit();

  RVMountRAMDisk('A',4096);
  UartS("mounted RedSea on A:; exercising directories...\n");

  // Make two subdirectories and write a couple of files in the root.
  Bool md1=DirMk("A:/DOCS"), md2=DirMk("A:/SRC");
  U8 *h="a file in the root", *r="another root file";
  FileWrite("A:/HELLO.TXT",h,StrLen(h));
  FileWrite("A:/READ.ME",r,StrLen(r));

  // List the root with the kernel's own FilesFind; count our entries.
  I64 want=0, n=0;
  CDirEntry *de=FilesFind("A:/*"), *e=de;
  while (e) {
    if (!StrICmp(e->name,"DOCS") || !StrICmp(e->name,"SRC") ||
	!StrICmp(e->name,"HELLO.TXT") || !StrICmp(e->name,"READ.ME")) want++;
    n++;
    e=e->next;
  }

  // Cd into a subdirectory (relative resolution works even if writing into it does not yet).
  Bool cd=Cd("A:/DOCS");
  Bool in_docs = !StrCmp(Fs->cur_dir,"/DOCS");

  U8 line[128];
  Bool ok = md1 && md2 && want==4 && cd && in_docs;
  StrPrint(line,"dir test: mkdir2=%d entries=%d want4=%d cd=%d in_docs=%d %s\n",
	md1&&md2, n, want, cd, in_docs, ok?"OK":"BAD");
  UartS(line);
  return 0;
}
