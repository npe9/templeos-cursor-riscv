// Touch() — lifted into Adam/ABlkDev/FileMgr_RV.HC — actually changes a file's attributes and its
// datetime, on the kernel's own RedSea filesystem (RVMountRAMDisk; no device, no disk image).
//
// Why a value and not a survey row. Demo/AcctExample/TOS/TOSToHtml.HC fails with exactly ONE error,
// "Argument 3 omitted, but 'Touch' has no declaration here to take a default from", so the file
// compiles the moment anything declares Touch — which is the L1-OK trap docs/DEMO_100.md §0 is
// about. Touch's job is to FilesFind the mask, ScanFlags the attribute string onto each entry, set
// the datetime and DirNew the directory entry back, so the honest check is to read the entry back
// off the filesystem afterwards.
//
// Asserted:
//   * a freshly written file has RS_ATTR_READ_ONLY clear; after Touch(file,"+R") FileFind reports
//     it SET, and no other attribute bit has moved (2048 -> 2049, measured; 2048 is RS_ATTR_FILE).
//     That is ScanFlags parsing "+R" against Define("ST_FILE_ATTRS") and DirNew writing the entry.
//   * Touch(file,"",,0x1234567890) makes FileFind report exactly that datetime — an arbitrary
//     64-bit value no default could produce — while leaving the attribute from the previous step
//     in place, so the two Touch calls are independent and neither is a no-op.
//
// The attribute is deliberately read back with FileFind rather than remembered: a Touch that
// updated an in-memory CDirEntry and never called DirNew would pass a weaker test.
#include "/Kernel/Kernel_RV.PRJ"

I64 main()
{
  // Boot scaffolding: the sequence RVKMain uses, as tools/survey_demo_one.sh writes it.
  CTask *adam = 0x86900000;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  CDirEntry de;
  I64 a0, a1, a2, dt;
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
  // ScanFlags() inside Touch needs Define("ST_FILE_ATTRS") and Define("ST_FILE_UTIL_FLAGS");
  // RVKernelInit does not load the define lists, and without this it throws 'Undefined Define'.
  SysDefinesLoad();

  FileWrite("B:/T.TXT", "hello", 5);
  FileFind("B:/T.TXT", &de, FUF_JUST_FILES);
  a0 = de.attr;

  Touch("B:/T.TXT", "+R");
  FileFind("B:/T.TXT", &de, FUF_JUST_FILES);
  a1 = de.attr;

  Touch("B:/T.TXT", "", , 0x1234567890);
  FileFind("B:/T.TXT", &de, FUF_JUST_FILES);
  a2 = de.attr;
  dt = de.datetime;

  // The inner parentheses are load-bearing: `a1 == a0 | RS_ATTR_READ_ONLY` parsed as
  // `(a1 == a0) | 1` would be 1 no matter what Touch did, which is a bit that cannot fail.
  return (!(a0 & RS_ATTR_READ_ONLY)) * 0x01 +
         (a1 == (a0 | RS_ATTR_READ_ONLY)) * 0x02 +
         (dt == 0x1234567890) * 0x04 +
         (a2 == a1) * 0x08;
  // 0xf when all four hold.
}
