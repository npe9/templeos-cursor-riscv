// gcmp_doldoc_probe.hc - scratch: guest Cmp of a store to the planted `doldoc`.
// Differential: soft glbl vs planted glbl, 2-arg vs 1-arg HashTableNew call.
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

I64 GCmpOne(U8 *tag, U8 *src)
{
  I64 r;
  U8 buf[128];
  FileWrite("A:/T.PRJ", src, StrLen(src));
  StrPrint(buf, "GCMP: %s Cmp...\n", tag);
  UartPutS(buf);
  try {
    r = Cmp("A:/T.PRJ",, "A:/T.BIN");
  } catch {
    Fs->catch_except = TRUE;
    r = -1;
  }
  StrPrint(buf, "GCMP: %s err=%d\n", tag, r);
  UartPutS(buf);
  return r;
}

I64 main()
{
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
  RVCmpWireAsmHash;
  UartPutS("GCMP: init ok\n");
  // T1: store into a soft-local glbl class member, 2-arg call.
  GCmpOne("T1_soft_store2", "import I64 HashTableNew(I64 size, I64 mem_task);\n" "class CSoftDoc\n" "{\n" "  I64 hash;\n" "};\n" "CSoftDoc g_doldoc;\n" "public I64 T1()\n" "{\n" "  g_doldoc.hash = HashTableNew(512, 0);\n" "  return 1;\n" "}\n");
  // T2: load only from the planted Kernel `doldoc` (known green).
  GCmpOne("T2_plant_load", "public I64 T2()\n" "{\n" "  if (!doldoc.hash)\n" "    return 2;\n" "  return 1;\n" "}\n");
  // T3: store into the planted Kernel `doldoc`, 2-arg call.  DECISIVE.
  GCmpOne("T3_plant_store2", "import I64 HashTableNew(I64 size, I64 mem_task);\n" "public I64 T3()\n" "{\n" "  doldoc.hash = HashTableNew(512, 0);\n" "  return 1;\n" "}\n");
  // T4: store into the planted Kernel `doldoc`, 1-arg call (the stock DocInit form).
  GCmpOne("T4_plant_store1", "import I64 HashTableNew(I64 size, I64 mem_task);\n" "public I64 T4()\n" "{\n" "  doldoc.hash = HashTableNew(512);\n" "  return 1;\n" "}\n");
  // T5: store into a soft-local glbl class member, 1-arg call.
  GCmpOne("T5_soft_store1", "import I64 HashTableNew(I64 size, I64 mem_task);\n" "class CSoftDoc\n" "{\n" "  I64 hash;\n" "};\n" "CSoftDoc g_doldoc;\n" "public I64 T5()\n" "{\n" "  g_doldoc.hash = HashTableNew(512);\n" "  return 1;\n" "}\n");
  // T6: 1-arg call, no store at all (plain local).
  GCmpOne("T6_local_store1", "import I64 HashTableNew(I64 size, I64 mem_task);\n" "public I64 T6()\n" "{\n" "  I64 ht;\n" "  ht = HashTableNew(512);\n" "  if (!ht)\n" "    return 2;\n" "  return 1;\n" "}\n");
  // T7: 1-arg call against an import declared with a default arg.
  GCmpOne("T7_dft_store1", "import I64 HashTableNew(I64 size, I64 mem_task = 0);\n" "public I64 T7()\n" "{\n" "  doldoc.hash = HashTableNew(512);\n" "  return 1;\n" "}\n");
  // T8: const-index store into the planted doldoc.dft_de_flags[43] (rung A3).
  GCmpOne("T8_plant_arr_idx", "public I64 T8()\n" "{\n" "  doldoc.dft_de_flags[0] = 8;\n" "  if (doldoc.dft_de_flags[0] != 8)\n" "    return 2;\n" "  return 1;\n" "}\n");
  // T9: array decay + sizeof of a planted array member (rung A4).
  GCmpOne("T9_plant_arr_decay", "import U8 *MemSet(U8 *dst, I64 dat, I64 size);\n" "public I64 T9()\n" "{\n" "  MemSet(doldoc.dft_de_flags, 0, sizeof(doldoc.dft_de_flags));\n" "  if (sizeof(doldoc.dft_de_flags) != 8 * 43)\n" "    return 2;\n" "  return 1;\n" "}\n");
  // T10: var-index read/write + I32 array member + &member[i] (rungs A/D/E).
  GCmpOne("T10_plant_arr_var", "import Bool Bts(U8 *bf, I64 n);\n" "import Bool Bt(U8 *bf, I64 n);\n" "public I64 T10()\n" "{\n" "  I64 i;\n" "  for (i = 0; i < 43; i++)\n" "    doldoc.dft_de_flags[i] = i;\n" "  if (doldoc.dft_de_flags[42] != 42)\n" "    return 2;\n" "  doldoc.dft_type_flags[7] = 1;\n" "  if (doldoc.dft_type_flags[7] != 1)\n" "    return 3;\n" "  doldoc.type_flags_form[0] = 0;\n" "  Bts(doldoc.clean_scan_codes, 3);\n" "  if (!Bt(&doldoc.dft_de_flags[1], 0))\n" "    return 4;\n" "  return 1;\n" "}\n");
  UartPutS("GCMP: done\n");
  return 0;
}
