// C01_Background.hc -- Beck 3e Ch.1: Background
// Remap: system software <-> machine architecture. Machine = RV64 + HolyC,
// not SIC/XE from the textbook examples.
//
// HOW TO WORK THIS LAB
//   Run("C01_Background.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Beck's thesis: assemblers, loaders, compilers, OS are machine-dependent.
//   Map each class of tool onto THIS tree:
//     assembler  -> asm{} / Asm_RV / TryAssembleRiscV
//     loader     -> Run() / ExePutS into live image
//     compiler   -> host holyc-riscv + guest Compiler_RV
//     OS         -> Kernel_*RV + REPL environment
//
// NEXT
//   C02_Assemblers.
U0 C01_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 C01_Demo()
{
  Print("C01: system software supports the machine itself.\n");
  Print("This machine: RV64I + TempleOS HolyC + board MEM_*.\n");
  Print("Pieces: host holyc-riscv, UART REPL seeds, Kernel, Compiler_RV.\n");
  C01_Expect("C01_uart", MemMapFind("uart"), MEM_UART);
}
// Ex1 Warmup: layers -- return 4 (asm/load/cmp/OS) as taught above.
I64 C01_Ex1_ToolClasses()
{
  // TODO Fill_in: return 4;
  return 0;
}
// Ex2: UART still the console.
I64 C01_Ex2_Uart()
{
  // TODO Fill_in: return MemMapFind("uart");
  return 0;
}
// Ex3: Print linked (runtime support).
I64 C01_Ex3_Print()
{
  // TODO Fill_in: if (FnAddr("Print")) return 1; return 0;
  return 0;
}
// Ex4: Tutorial linked.
I64 C01_Ex4_Tutorial()
{
  // TODO Fill_in: if (FnAddr("Tutorial")) return 1; return 0;
  return 0;
}
// Ex5: machine dependency -- RV != x86. Return 64 for XLEN.
I64 C01_Ex5_Xlen()
{
  // TODO Fill_in: return 64;
  return 0;
}
// Ex6: memfs present.
I64 C01_Ex6_Fs()
{
  // TODO Fill_in: return MemMapFind("fs");
  return 0;
}
// Ex7 Challenge: StrLen("HolyC").
I64 C01_Ex7_Name()
{
  // TODO Fill_in: return StrLen("HolyC");
  return 0;
}
// Ex8 Challenge: SIC/XE is NOT this machine -- affirm 1.
I64 C01_Ex8_NotSic()
{
  // TODO Fill_in: return 1;
  return -1;
}

U0 C01_Check()
{
  Print("-- C01 exercises --\n");
  C01_Expect("Ex1_ToolClasses", C01_Ex1_ToolClasses(), 4);
  C01_Expect("Ex2_Uart", C01_Ex2_Uart(), MEM_UART);
  C01_Expect("Ex3_Print", C01_Ex3_Print(), 1);
  C01_Expect("Ex4_Tutorial", C01_Ex4_Tutorial(), 1);
  C01_Expect("Ex5_Xlen", C01_Ex5_Xlen(), 64);
  C01_Expect("Ex6_Fs", C01_Ex6_Fs(), MEM_FS);
  C01_Expect("Ex7_Name", C01_Ex7_Name(), 5);
  C01_Expect("Ex8_NotSic", C01_Ex8_NotSic(), 1);
}

U0 C01()
{
  Print("=== C01 Beck Ch.1 Background ===\n");
  C01_Demo();
  C01_Check();
  Print("Next: Run(\"C02_Assemblers.hc\");\n");
}
C01;
