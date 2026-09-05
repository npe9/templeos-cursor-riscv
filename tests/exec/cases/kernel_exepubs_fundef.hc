// kernel_exepubs_fundef.hc — guest ExePutS of a function def (P0 gate).
// TempleOS-shaped path (Compiler_RV / ExePutS), not jit.hc.
#include "/Kernel/Kernel_RV.PRJ"
#include "/Compiler/RISCVRegs.HH"
#include "/Compiler/Compiler_RV_Body.PRJ"
#define MEM_UART 0x10000000
U0 UartPutC(I64 ch)
{
  U8 *uart = MEM_UART;
  *uart = ch;
}

U0 UartPutS(U8 *s)
{
  while (s && *s) {
    UartPutC (*s);
    s++;
  }
}
UartPutS("toplevel-before-main\n");
I64 main()
{
  I64 r;
  U8 buf[48];
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
  RVJiffiesInit(CONFIG_TIMEBASE_FREQ / 1000);
  RVKernelInit();
  RVMountRAMDisk('A', 4096);
  UartPutS("ExePutS smoke: fs ok\n");
  CInit();
  UartPutS("ExePutS smoke: CInit ok\n");
  if (cmp.asm_hash)
    cmp.asm_hash->next = NULL;
  if (adam_task && adam_task->hash_table && cmp.asm_hash &&
      adam_task->hash_table != cmp.asm_hash)
    adam_task->hash_table->next = cmp.asm_hash;
  if (HashFind("I64", cmp.asm_hash, HTT_INTERNAL_TYPE, 1))
    UartPutS("ExePutS smoke: I64 ok\n");
  else
    UartPutS("ExePutS smoke: I64 FAIL\n");
  UartPutS("ExePutS smoke: compiling 40+2...\n");
  r = ExePutS("40+2;\n");
  StrPrint(buf, "ExePutS 40+2=%d\n", r);
  UartPutS(buf);
  if (r != 42) {
    UartPutS("ExePutS smoke: FAIL\n");
    return r;
  }
  UartPutS("ExePutS smoke: compiling fun...\n");
  r = ExePutS("I64 MakeOSProbe(){return 42;}\n");
  UartPutS("ExePutS after fun def\n");
  r = ExePutS("MakeOSProbe;\n");
  StrPrint(buf, "ExePutS fun=%d\n", r);
  UartPutS(buf);
  if (r == 42) {
    UartPutS("ExePutS smoke: OK\n");
    return r;
  }
  UartPutS("ExePutS smoke: fun FAIL\n");
  return r;
}
