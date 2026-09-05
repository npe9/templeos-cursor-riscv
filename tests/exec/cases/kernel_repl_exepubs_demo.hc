// kernel_repl_exepubs_demo.hc — A2 vertical slice:
// guest Compiler_RV ExePutS owns a UART REPL compile loop (not jit.hc).
// Smoke pipes HolyC lines; each line is ExePutS'd. See docs/SELF_HOST.md A2.
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
  I64 r, n, ok = 0;
  U8 buf[64];
  U8 line[160];
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
  // Soft RX: PutS/FcPoll must not drop piped stdin before GetLine (A2 REPL).
  RVUartSoftOn(1);
  RVMountRAMDisk('A', 4096);
  CInit();
  // Chain Fs → asm_hash only when distinct (aliasing creates a HashFind self-loop).
  if (cmp.asm_hash)
    cmp.asm_hash->next = NULL;
  if (Fs && Fs->hash_table && cmp.asm_hash && Fs->hash_table != cmp.asm_hash)
    Fs->hash_table->next = cmp.asm_hash;
  RVExePubsWire;
  if (!HashFind("I64", cmp.asm_hash, HTT_INTERNAL_TYPE, 1)) {
    UartPutS("A2 ExePutS REPL: I64 FAIL\n");
    return 1;
  }
  // Cmp-distinct: real Compiler_RV ExePutS returns the expr value (Jit bridge maps to -1/0/1).
  UartPutS("A2: Compiler_RV owns ExePutS\n");
  UartPutS("A2 ExePutS REPL\n");
  r = ExePutS("40+2;\n");
  StrPrint(buf, "probe ans=%d\n", r);
  UartPutS(buf);
  if (r != 42) {
    UartPutS("A2 ExePutS REPL: probe FAIL\n");
    return r;
  }
  UartPutS("A2: Cmp compiled 40+2\n");
  UartPutS("A2: type HolyC; 'q' quits\n");
  while (TRUE) {
    UartPutS("> ");
    n = RVUartGetLine(line, 160);
    if (n <= 0)
      continue;
    if (line[0] == 'q' && (!line[1] || line[1] == ';'))
      break;
    r = ExePutS(line);
    StrPrint(buf, "ans=%d\n", r);
    UartPutS(buf);
    ok++;
  }
  if (!ok) {
    UartPutS("A2 ExePutS loop: no lines\n");
    return 2;
  }
  UartPutS("A2 ExePutS loop: OK\n");
  return 0;
}
