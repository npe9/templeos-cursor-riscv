// LongLinesFile() — Adam/Opt/Utils/StrUtils.HC, added to Kernel_RV.PRJ — actually COUNTS long
// lines, on the kernel's own RedSea filesystem (RVMountRAMDisk; no device, no disk image).
//
// Why a value and not a survey row. Demo/AcctExample/TOS/TOSDistro.HC said
// "Undefined variable 'LongLines'" and TOSIns.HC said "Argument 3 omitted, but 'Sort' has no
// declaration here to take a default from" — the callee had no declaration in scope, which is
// docs/DEMO_100.md §1, not a compiler bug. Putting StrUtils.HC in the project closes both. But
// "it compiles" is exactly the L1-OK trap §0 is about, so this case asserts what the added code
// COMPUTES: LongLinesFile reads the file into a DolDoc and counts the DOCT_NEW_LINE entries whose
// x exceeds the column limit.
//
// Asserted:
//   * 3 lines of 60 columns and one of 5, at cols=40  -> 3. Not "nonzero", not "found a file":
//     the exact count. A stub returning 0 cannot produce it and neither can a detector.
//   * the same file at cols=100                       -> 0. Same bytes, different limit, so the
//     column comparison is what is being measured.
//   * a file of 3-column lines at cols=40             -> 0.
//
// TWO things this case deliberately does NOT assert, both measured, both outside StrUtils.HC:
//
//  1. Sort(), the unit's other public entry, TRAPS. `QSort(a,cnt/entry_lines,
//     entry_lines*sizeof(CDocEntry *),&DEPtrCompare)` passes a width of 208, because the host
//     compiler evaluates `sizeof(CDocEntry *)` as sizeof(CDocEntry) — measured: sizeof(U8 *)==8
//     but sizeof(CDocEntry *)==208. QSort then takes its width!=8 branch (QSort2b), its pivot is
//     MemCpy'd from far past the end of the array, and DEPtrCompare dereferences NULL:
//     mcause=5 load-fault, mtval=0x10, DEPtrCompare+0x84. host/parser.c's sizeof arm drops
//     cc->last_ptr_depth after ParseType. That is a compiler bug and a tier-7 item; StrUtils.HC
//     gives Sort a DECLARATION, which is what the two demos need to compile, not a working Sort.
//  2. LongLines(), the public wrapper, traps too — but before it reaches any StrUtils code. Its
//     flags are "+r+f+F+S", and FilesFind() with FUF_RECURSE set traps in DirNameAbs+0x48
//     (mcause=5, mtval=0x70) for ANY mask, with no StrUtils involved. Bisected: "+f" and "+f+F"
//     return the file, "+r" alone traps. Pre-existing, in Kernel/BlkDev, not in the added unit.
#include "/Kernel/Kernel_RV.PRJ"

I64 main()
{
  // Boot scaffolding: the sequence RVKMain uses, as tools/survey_demo_one.sh writes it.
  CTask *adam = 0x86900000;
  CBlkPool *bp;
  CHeapCtrl *ah;
  CCPU *gs;
  I64 at40, at100, shorty;
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

  // Three 60-column lines, one 5-column line.
  FileWrite("B:/LONG.TXT",
      "123456789012345678901234567890123456789012345678901234567890\n"
      "abcdefghijabcdefghijabcdefghijabcdefghijabcdefghijabcdefghij\n"
      "short\n"
      "ABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJABCDEFGHIJ\n", 189);
  FileWrite("B:/SHORT.TXT", "aaa\nbbb\nccc\n", 12);

  at40   = LongLinesFile("B:/LONG.TXT", 40);
  at100  = LongLinesFile("B:/LONG.TXT", 100);
  shorty = LongLinesFile("B:/SHORT.TXT", 40);

  return (at40 == 3) * 0x100 + (at100 == 0) * 0x200 + (shorty == 0) * 0x400;
  // 0x700 when all three hold.
}
