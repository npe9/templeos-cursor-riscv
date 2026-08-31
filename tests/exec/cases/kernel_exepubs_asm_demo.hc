// Guest ExePutS must assemble+run unlabeled RISC-V asm{} (Compiler_RV).
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

I64 main()
{
  I64 r;
  U8 buf[64];
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
  CInit();
  if (adam_task && cmp.asm_hash)
    adam_task->hash_table->next = cmp.asm_hash;
  UartPutS("ExePutS asm: compiling...\n");
  r = ExePutS("I64 AsmAdd3(I64 x){asm{addi a0,a0,3}} " "I64 AsmS2(){asm{li s2,0 addi s2,s2,3 mv a0,s2}} " "I64 AsmSemi(){asm{li s2,1; li a7,4; sub a7,a7,s2; mv a0,a7}} " "AsmAdd3(39)+AsmS2+AsmSemi;\n");
  StrPrint(buf, "ExePutS asm=%d\n", r);
  UartPutS(buf);
  if (r == 48) {
    UartPutS("ExePutS asm: OK\n");
    return r;
  }
  UartPutS("ExePutS asm: FAIL\n");
  return r;
}
