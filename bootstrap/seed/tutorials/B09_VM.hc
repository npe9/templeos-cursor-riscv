// B09_VM.hc -- CSAPP 3e Ch.9: Virtual Memory
// GAP: full Sv39/Sv48 paging + user processes are not the UART REPL product.
// Teach address-space ideas via physical MEM_* arenas and allocator bounds.
//
// HOW TO WORK THIS LAB
//   Run("B09_VM.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Virtual addresses, page tables, malloc, memory mapping, mmap. Honesty:
//   this REPL is largely a single physical address space with named regions.
//   Kernel paging work (if present) lives under Kernel/ -- not memfs lessons.
//   Still practice: why overlapping FS/heap/stack maps corrupt the world.
//
// NEXT
//   B10_IO -- UART + memfs.
U0 B09_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 B09_Demo()
{
  Print("B09 GAP: no full virtual-memory OS in the UART REPL.\n");
  Print("Physical stand-in: MEM_RAM/HEAP/FS/FIXED/STACK.\n");
  Print("MEM_HEAP=%X MEM_FS=%X MEM_STACK=%X MEM_FIXED=%X\n", MEM_HEAP, MEM_FS, MEM_STACK, MEM_FIXED);
  MemMap;
  B09_Expect("B09_heap", MemMapFind("heap"), MEM_HEAP);
}
// Ex1 Warmup: heap base.
I64 B09_Ex1_Heap()
{
  // TODO Fill_in: return MemMapFind("heap");
  return 0;
}
// Ex2: fs base.
I64 B09_Ex2_Fs()
{
  // TODO Fill_in: return MemMapFind("fs");
  return 0;
}
// Ex3: stack base.
I64 B09_Ex3_Stack()
{
  // TODO Fill_in: return MemMapFind("stack");
  return 0;
}
// Ex4: fixed/control slot region.
I64 B09_Ex4_Fixed()
{
  // TODO Fill_in: return MemMapFind("fixed");
  return 0;
}
// Ex5: page-size intuition -- RV often 4KiB pages. Return 4096.
I64 B09_Ex5_PageSize()
{
  // TODO Fill_in: return 4096;
  return 0;
}
// Ex6: VPN-style -- index = addr / 4096 (for teaching).
I64 B09_Ex6_PageIndex(I64 addr)
{
  // TODO Fill_in: return addr / 4096;
  return 0;
}
// Ex7 Challenge: offset within page = addr & 4095.
I64 B09_Ex7_PageOff(I64 addr)
{
  // TODO Fill_in: return addr & 4095;
  return -1;
}
// Ex8 Challenge: affirm gap -- return 1 ("no full Sv39 user VM in REPL").
I64 B09_Ex8_GapAffirm()
{
  // TODO Fill_in: return 1;
  return 0;
}

U0 B09_Check()
{
  Print("-- B09 exercises --\n");
  B09_Expect("Ex1_Heap", B09_Ex1_Heap(), MEM_HEAP);
  B09_Expect("Ex2_Fs", B09_Ex2_Fs(), MEM_FS);
  B09_Expect("Ex3_Stack", B09_Ex3_Stack(), MEM_STACK);
  B09_Expect("Ex4_Fixed", B09_Ex4_Fixed(), MEM_FIXED);
  B09_Expect("Ex5_PageSize", B09_Ex5_PageSize(), 4096);
  B09_Expect("Ex6_PageIndex", B09_Ex6_PageIndex(0x80001000), 0x80001);
  B09_Expect("Ex7_PageOff", B09_Ex7_PageOff(0x80001234), 0x234);
  B09_Expect("Ex8_GapAffirm", B09_Ex8_GapAffirm(), 1);
}

U0 B09()
{
  Print("=== B09 CSAPP Ch.9 Virtual memory ===\n");
  B09_Demo();
  B09_Check();
  Print("Next: Run(\"B10_IO.hc\");\n");
}
B09;
