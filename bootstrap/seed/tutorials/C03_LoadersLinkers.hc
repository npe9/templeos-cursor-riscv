// C03_LoadersLinkers.hc -- Beck 3e Ch.3: Loaders and Linkers
// Remap: Run/ExePutS loads object text into the live image + hash.
//
// HOW TO WORK THIS LAB
//   Run("C03_LoadersLinkers.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Absolute / relocating loaders, linking, bootstrap. Here Run(name) is the
//   everyday loader+linker. Relocations are handled by the JIT/compiler as
//   it emits into RAM and publishes symbols. FnAddr is the symbol table query.
//
// NEXT
//   C04_MacroProcessors.
U0 C03_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

I64 C03_Payload()
{
  return 0xC03;
}

U0 C03_Demo()
{
  Print("C03: Run(name) = read memfs -> compile -> link into hash.\n");
  Print("FnAddr(\"C03_Payload\")=%X\n", FnAddr("C03_Payload"));
  C03_Expect("C03_Payload", C03_Payload(), 0xC03);
}
// Ex1 Warmup: self linked.
I64 C03_Ex1_Self()
{
  // TODO Fill_in: if (FnAddr("C03_Payload")) return 1; return 0;
  return 0;
}
// Ex2: call payload.
I64 C03_Ex2_Call()
{
  // TODO Fill_in: return C03_Payload();
  return 0;
}
// Ex3: Run linked.
I64 C03_Ex3_Run()
{
  // TODO Fill_in: if (FnAddr("Run")) return 1; return 0;
  return 0;
}
// Ex4: missing symbol.
I64 C03_Ex4_Missing()
{
  // TODO Fill_in: if (!FnAddr("NoSuch_C03_ZZZ")) return 1; return 0;
  return 0;
}
// Ex5: Print addr stable across two lookups.
I64 C03_Ex5_Stable()
{
  I64 a, b;
  // TODO Fill_in:
  //   a = FnAddr("Print"); b = FnAddr("Print");
  //   if (a && a == b) return 1; return 0;
  return 0;
}
// Ex6: bootstrap idea -- MEM_RAM is where code lives.
I64 C03_Ex6_Ram()
{
  // TODO Fill_in: return MemMapFind("ram");
  return 0;
}
// Ex7 Challenge: StrLen("Run").
I64 C03_Ex7_Name()
{
  // TODO Fill_in: return StrLen("Run");
  return 0;
}
// Ex8 Challenge: re-link mental model -- return 1 if FnAddr after Run
// can change (true in general when you redefine). Affirm 1.
I64 C03_Ex8_RedefOk()
{
  // TODO Fill_in: return 1;
  return 0;
}

U0 C03_Check()
{
  I64 a, b;
  Print("-- C03 exercises --\n");
  C03_Expect("Ex1_Self", C03_Ex1_Self(), 1);
  C03_Expect("Ex2_Call", C03_Ex2_Call(), 0xC03);
  C03_Expect("Ex3_Run", C03_Ex3_Run(), 1);
  C03_Expect("Ex4_Missing", C03_Ex4_Missing(), 1);
  a = FnAddr("Print");
  b = FnAddr("Print");
  // Grade Ex5 by calling student fn:
  C03_Expect("Ex5_Stable", C03_Ex5_Stable(), 1);
  C03_Expect("Ex5_oracle", a && a == b, 1);
  C03_Expect("Ex6_Ram", C03_Ex6_Ram(), MEM_RAM);
  C03_Expect("Ex7_Name", C03_Ex7_Name(), 3);
  C03_Expect("Ex8_RedefOk", C03_Ex8_RedefOk(), 1);
}

U0 C03()
{
  Print("=== C03 Beck Ch.3 Loaders and linkers ===\n");
  C03_Demo();
  C03_Check();
  Print("Try: edit this file in Vi, Run again, watch FnAddr.\n");
  Print("Next: Run(\"C04_MacroProcessors.hc\");\n");
}
C03;
