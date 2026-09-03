// B06_MemHierarchy.hc -- CSAPP 3e Ch.6: The Memory Hierarchy
// Remap: MEM_* arenas (code DRAM, heap, memfs, MMIO) as the visible hierarchy.
// Caches exist on boards; this lab grades the map you can see from HolyC.
//
// HOW TO WORK THIS LAB
//   Run("B06_MemHierarchy.hc");  MemMap;  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Locality, cache lines, DRAM vs SRAM vs disks. On bare metal without a
//   cache simulator, locality still matters -- and confusing MEM_FS with
//   MEM_UART is a "hierarchy bug" you can actually hit.
//
// NEXT
//   B07_Linking -- symbols / Run / FnAddr.
U0 B06_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 B06_Demo()
{
  Print("B06 regions (see MemMap):\n");
  Print("  DRAM/code  MEM_RAM   %X\n", MEM_RAM);
  Print("  heap       MEM_HEAP  %X\n", MEM_HEAP);
  Print("  memfs      MEM_FS    %X\n", MEM_FS);
  Print("  UART MMIO  MEM_UART  %X\n", MEM_UART);
  Print("  CLINT      MEM_CLINT %X\n", MEM_CLINT);
  MemMap;
  B06_Expect("B06_fs", MemMapFind("fs"), MEM_FS);
}
// Ex1 Warmup: heap base.
I64 B06_Ex1_Heap()
{
  // TODO Fill_in: return MemMapFind("heap");
  return 0;
}
// Ex2: fs base.
I64 B06_Ex2_Fs()
{
  // TODO Fill_in: return MemMapFind("fs");
  return 0;
}
// Ex3: uart base.
I64 B06_Ex3_Uart()
{
  // TODO Fill_in: return MemMapFind("uart");
  return 0;
}
// Ex4: stack region.
I64 B06_Ex4_Stack()
{
  // TODO Fill_in: return MemMapFind("stack");
  return 0;
}
// Ex5: return 1 if MEM_UART is below typical DRAM (0x80000000) -- MMIO vs RAM.
I64 B06_Ex5_UartIsMmio()
{
  // TODO Fill_in: if (MEM_UART < MEM_RAM) return 1; return -1;
  return 0;
}
// Ex6: locality warmup -- sequential sum of 0..n-1.
I64 B06_Ex6_SeqSum(I64 n)
{
  I64 i, s;
  // TODO Fill_in: s=0; for (i=0; i<n; i++) s+=i; return s;
  s = 0;
  return s;
}
// Ex7 Challenge: stride sum of even indices 0,2,...,n-2 in array p[0..n).
I64 B06_Ex7_Stride(I64 *p, I64 n)
{
  I64 i, s;
  // TODO Fill_in
  s = 0;
  return s;
}
// Ex8 Challenge: fs and heap must differ.
I64 B06_Ex8_Distinct()
{
  // TODO Fill_in:
  //   if (MemMapFind("fs") != MemMapFind("heap")) return 1;
  //   return -1;
  return 0;
}

U0 B06_Check()
{
  I64 a[6], i;
  Print("-- B06 exercises --\n");
  B06_Expect("Ex1_Heap", B06_Ex1_Heap(), MEM_HEAP);
  B06_Expect("Ex2_Fs", B06_Ex2_Fs(), MEM_FS);
  B06_Expect("Ex3_Uart", B06_Ex3_Uart(), MEM_UART);
  B06_Expect("Ex4_Stack", B06_Ex4_Stack(), MEM_STACK);
  B06_Expect("Ex5_UartIsMmio", B06_Ex5_UartIsMmio(), 1);
  B06_Expect("Ex6_SeqSum", B06_Ex6_SeqSum(10), 45);
  // 0..9
  for (i = 0; i < 6; i++)
    a[i] = i + 1;
  B06_Expect("Ex7_Stride", B06_Ex7_Stride(a, 6), 9);
  // 1+3+5
  B06_Expect("Ex8_Distinct", B06_Ex8_Distinct(), 1);
}

U0 B06()
{
  Print("=== B06 CSAPP Ch.6 Memory hierarchy ===\n");
  B06_Demo();
  B06_Check();
  Print("Next: Run(\"B07_Linking.hc\");\n");
}
B06;
