// FilesFind(mask, FUF_RECURSE) traps for any mask (DirNameAbs, mtval=0x70) while the same mask
// without FUF_RECURSE returns the file — found by the tier-1 demo agent; it silently breaks
// LongLines, Words, SU, DelTree and JukeSongsPuppet. Bits: nflat + nrec<<8 + (entries with a
// sub tree)<<16 over a two-level RAM disk.
#include "/Kernel/Kernel_RV.PRJ"

I64 main()
{
  // Boot scaffolding: the sequence RVKMain uses, as tools/survey_demo_one.sh writes it.
  CTask *adam = 0x86900000;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  I64 nflat = 0, nrec = 0, nsub = 0;
  CDirEntry *flat, *rec, *e;
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
  adam->task_signature = TASK_SIGNATURE_VAL;
  adam->addr = adam;
  gs = 0x86A00000;
  MemSet(gs, 0, sizeof(CCPU));
  gs->seth_task = adam;
  adam->gs = gs;
  Gs = gs;
  RVYieldInit(&Fs);
  RVKernelInit();
  RVMountRAMDisk('B', 8192);
  FileWrite("B:/TOP.TXT", "top\n", 4);
  DirMk("B:/SUB");
  FileWrite("B:/SUB/IN.TXT", "in\n", 3);
  flat = FilesFind("B:/*", 0);
  e = flat;
  while (e) { nflat++; e = e->next; }
  rec = FilesFind("B:/*", FUF_RECURSE);
  e = rec;
  while (e) { nrec++; if (e->sub) nsub++; e = e->next; }
  return nflat + nrec * 0x100 + nsub * 0x10000;
}
