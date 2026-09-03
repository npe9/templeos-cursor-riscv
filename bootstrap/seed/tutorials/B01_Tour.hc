// B01_Tour.hc -- CSAPP 3e Ch.1: A Tour of Computer Systems
// Remap: hello-world tour of THIS stack (HolyC UART REPL + board MEM_*),
// not "hello.c on Linux x86-64".
//
// HOW TO WORK THIS LAB
//   Run("B01_Tour.hc");  Src("B01_Tour");  fix Fill_in;  Run again.
//
// BOOK THEMES -> THIS PORT
//   CSAPP opens with information = bits, programs = translations, systems =
//   hardware + OS services. Here:
//     bits        -> I64 / U8 on RV64 (B02)
//     compile     -> host holyc-riscv + Run() JIT into live hash
//     "OS"        -> Kernel_*RV drivers + REPL memfs/traps (not Linux syscalls)
//     I/O         -> UART MMIO + memfs FileRead/FileWrite
//   QEMU is a CI harness for some boards -- product language is board / MEM_*.
//
// NEXT
//   B02_DataRep -- CSAPP Ch.2.
U0 B01_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 B01_Demo()
{
  Print("B01 tour: bits -> HolyC -> RV64 -> board MMIO\n");
  Print("1+2*3 = %d\n", 1 + 2 * 3);
  Print("MEM_RAM=%X MEM_UART=%X MEM_FS=%X MEM_HEAP=%X\n", MEM_RAM, MEM_UART, MEM_FS, MEM_HEAP);
  Print("Daily dig-down: Help; Dir; Man(\"Print\"); MemMap; Regs;\n");
  B01_Expect("B01_arith", 1 + 2 * 3, 7);
  B01_Expect("B01_uart", MemMapFind("uart"), MEM_UART);
}
// Ex1 Warmup: expression precedence.
I64 B01_Ex1_Arith()
{
  // TODO Fill_in: return 1 + 2 * 3;
  return 0;
}
// Ex2: UART base via map.
I64 B01_Ex2_Uart()
{
  // TODO Fill_in: return MemMapFind("uart");
  return 0;
}
// Ex3: memfs base (where Dir/Cat files live).
I64 B01_Ex3_Fs()
{
  // TODO Fill_in: return MemMapFind("fs");
  return 0;
}
// Ex4: FnAddr("Print") non-zero (runtime is linked).
I64 B01_Ex4_PrintLinked()
{
  // TODO Fill_in: if (FnAddr("Print")) return 1; return 0;
  return 0;
}
// Ex5: Help exists.
I64 B01_Ex5_HelpLinked()
{
  // TODO Fill_in: if (FnAddr("Help")) return 1; return 0;
  return 0;
}
// Ex6: StrLen of a greeting -- "systems" string length.
I64 B01_Ex6_Str()
{
  // TODO Fill_in: return StrLen("systems");
  return 0;
}
// Ex7 Challenge: abstraction layers count for THIS stack.
// We teach 4: HolyC source, compiler/JIT, RV64 machine, board MMIO/drivers.
I64 B01_Ex7_Layers()
{
  // TODO Fill_in: return 4;
  return 0;
}
// Ex8 Challenge: QEMU is harness-only -- return 1 if student affirms.
I64 B01_Ex8_QemuHarness()
{
  // TODO Fill_in: return 1;  // true: prefer board/MEM_* language
  return -1;
}

U0 B01_Check()
{
  Print("-- B01 exercises --\n");
  B01_Expect("Ex1_Arith", B01_Ex1_Arith(), 7);
  B01_Expect("Ex2_Uart", B01_Ex2_Uart(), MEM_UART);
  B01_Expect("Ex3_Fs", B01_Ex3_Fs(), MEM_FS);
  B01_Expect("Ex4_PrintLinked", B01_Ex4_PrintLinked(), 1);
  B01_Expect("Ex5_HelpLinked", B01_Ex5_HelpLinked(), 1);
  B01_Expect("Ex6_Str", B01_Ex6_Str(), 7);
  B01_Expect("Ex7_Layers", B01_Ex7_Layers(), 4);
  B01_Expect("Ex8_QemuHarness", B01_Ex8_QemuHarness(), 1);
}

U0 B01()
{
  Print("=== B01 CSAPP Ch.1 Tour ===\n");
  B01_Demo();
  B01_Check();
  Print("Try: Dir; Cat(\"boot.hc\"); Man(\"Print\");\n");
  Print("Next: Run(\"B02_DataRep.hc\");\n");
}
B01;
