// gcmp_arrpp_probe.hc - scratch: guest Cmp (AOT PRJ->BIN) of `arr[i++]`.
// Reproduces the phase3 LiteLexPlant r=3 soft-fail in a ~40s harness and dumps
// the emitted code bytes of the loaded export so it can be disassembled.
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

I64 GCmpCall(U8 *name)
{
  CHashExport *tmpex;
  tmpex = HashFind(name, Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (!tmpex)
    tmpex = HashFind(name, Fs->hash_table, HTT_FUN);
  if (!tmpex)
    return -1;
  if (tmpex->type & HTT_FUN)
    return Call(tmpex(CHashFun *)->exe_addr);
  return Call(tmpex->val);
}

U0 GCmpDump(U8 *name, I64 n)
{
  CHashExport *tmpex;
  U8 buf[32], *p;
  I64 i;
  tmpex = HashFind(name, Fs->hash_table, HTT_EXPORT_SYS_SYM);
  if (tmpex)
    p = tmpex->val;
  else {
    tmpex = HashFind(name, Fs->hash_table, HTT_FUN);
    if (!tmpex) {
      UartPutS("DUMP miss\n");
      return;
    }
    p = tmpex(CHashFun *)->exe_addr;
  }
  StrPrint(buf, "DUMP %s @%X\n", name, p);
  UartPutS(buf);
  for (i = 0; i < n; i += 4) {
    StrPrint(buf, "%08X\n", *(p + i)(U32 *));
    UartPutS(buf);
  }
  UartPutS("DUMPEND\n");
}

I64 main()
{
  I64 r;
  U8 buf[64], *src;
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
  RVMountRAMDisk('A', 8192);
  CInit();
  if (cmp.asm_hash)
    cmp.asm_hash->next = NULL;
  if (adam_task && adam_task->hash_table && cmp.asm_hash && adam_task->hash_table != cmp.asm_hash)
    adam_task->hash_table->next = cmp.asm_hash;
  UartPutS("GCMP: init ok\n");
  src = "I64 g_toks[8];\n" "I64 g_tok_n;\n" "I64 g_tok_i;\n" "public I64 ArrPP()\n" "{\n" "  I64 t;\n" "  g_toks[0] = 44;\n" "  g_toks[1] = 77;\n" "  g_tok_i = 0;\n" "  t = g_toks[g_tok_i++];\n" "  if (t != 44)\n" "    return 3;\n" "  if (g_tok_i != 1)\n" "    return 4;\n" "  return 8;\n" "}\n" "public I64 ArrPPTokI()\n" "{\n" "  return g_tok_i;\n" "}\n" "public I64 ScalarPP()\n" "{\n" "  I64 t;\n" "  g_tok_i = 5;\n" "  t = g_tok_i++;\n" "  if (t != 5)\n" "    return 3;\n" "  if (g_tok_i != 6)\n" "    return 4;\n" "  return 8;\n" "}\n" "public I64 ArrPPIdx()\n" "{\n" "  I64 t;\n" "  g_toks[0] = 44;\n" "  g_toks[1] = 77;\n" "  g_tok_i = 0;\n" "  t = g_toks[g_tok_i];\n" "  if (t != 44)\n" "    return 3;\n" "  return 8;\n" "}\n";
  FileWrite("A:/T.PRJ", src, StrLen(src));
  UartPutS("GCMP: Cmp...\n");
  try {
    r = Cmp("A:/T.PRJ",, "A:/T.BIN");
  } catch {
    Fs->catch_except = TRUE;
    r = -1;
  }
  StrPrint(buf, "GCMP: Cmp err=%d\n", r);
  UartPutS(buf);
  if (!FileFind("A:/T.BIN")) {
    UartPutS("GCMP: no BIN\n");
    return 1;
  }
  CBinFile *bfh = Load("A:/T.BIN", LDF_JUST_LOAD | LDF_SILENT);
  if (!bfh || bfh->bin_signature != BIN_SIGNATURE_VAL) {
    UartPutS("GCMP: Load FAIL\n");
    return 1;
  }
  UartPutS("GCMP: Load ok\n");
  GCmpDump("ScalarPP", 0x80);
  GCmpDump("ArrPPIdx", 0x80);
  GCmpDump("ArrPP", 0xC0);
  try {
    r = GCmpCall("ScalarPP");
  } catch {
    Fs->catch_except = TRUE;
    r = -2;
  }
  StrPrint(buf, "GCMP: ScalarPP r=%d\n", r);
  UartPutS(buf);
  try {
    r = GCmpCall("ArrPPIdx");
  } catch {
    Fs->catch_except = TRUE;
    r = -2;
  }
  StrPrint(buf, "GCMP: ArrPPIdx r=%d\n", r);
  UartPutS(buf);
  try {
    r = GCmpCall("ArrPP");
  } catch {
    Fs->catch_except = TRUE;
    r = -2;
  }
  StrPrint(buf, "GCMP: ArrPP r=%d\n", r);
  UartPutS(buf);
  try {
    r = GCmpCall("ArrPPTokI");
  } catch {
    Fs->catch_except = TRUE;
    r = -2;
  }
  StrPrint(buf, "GCMP: ArrPP g_tok_i=%d\n", r);
  UartPutS(buf);
  UartPutS("GCMP: done\n");
  return 0;
}
