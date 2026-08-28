// The HolyC implicit-print idiom `"fmt", args;` (a top-level string statement == Print("fmt",args))
// against the KERNEL's own varargs Print (U0 Print(U8*fmt,...), ABI fmt/argc/argv). TempleOS uses
// this form pervasively (e.g. DirMk's "Make Directory:%s"). The string-statement lowering must set
// up the HolyC varargs the same way an explicit Print() call does.
#include "/Kernel/Kernel_RV.PRJ"
I64 main()
{
  // Boot scaffolding enough for the kernel console (Print -> UART via RVKernelInit).
  CTask *adam=0x86900000; MemSet(adam,0,sizeof(CTask)); Fs=adam; adam_task=adam;
  MemSet(the_heap,0,sizeof(CHeapCtrl)); heap_next=0x82000400; heap_end=0x86000000;
  CBlkPool *bp=0x86800000; BlkPoolInit(bp,0x2000); sys_code_bp=bp;
  CHeapCtrl *ah=HeapCtrlInit(NULL,NULL,bp); adam->code_heap=ah; adam->data_heap=ah;
  MemSet(SYS_FIXED_AREA,0,8192); TaskInit(adam,0);
  CCPU *gs=0x86A00000; MemSet(gs,0,sizeof(CCPU)); gs->seth_task=adam; adam->gs=gs; Gs=gs;
  RVYieldInit(&Fs); RVKernelInit();

  Print("explicit: val=%d s=%s done\n", 42, "AB");     // known-good reference
  "strstmt: val=%d s=%s done\n", 42, "AB";              // the implicit-print form under test
  "strstmt-three: %d %d %d done\n", 1, 2, 3;
  return 0;
}
