// B07_Linking.hc -- CSAPP 3e Ch.7: Linking
// Remap: Run/ExePutS + symbol hash (FnAddr) instead of ld.so / ELF shared libs.
//
// HOW TO WORK THIS LAB
//   Run("B07_Linking.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Symbols, relocation, static vs dynamic linking. On this REPL, Run(name)
//   reads memfs, compiles, and binds names into the live hash. FnAddr looks
//   up a function. Guest Compiler_RV + ExePutS is the long-term destination
//   (COMPILER_RV.md). No ELF .so story in the UART product path.
//
// NEXT
//   B08_ECF -- traps / Reset / timer (not Linux signals).
U0 B07_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

I64 B07_Marker()
{
  return 0xB07;
}

U0 B07_Demo()
{
  Print("B07 demo: FnAddr(\"Print\")=%X\n", FnAddr("Print"));
  Print("FnAddr(\"B07_Marker\")=%X\n", FnAddr("B07_Marker"));
  Print("Run(\"file.hc\") compiles+links into the live hash (run.hc).\n");
  B07_Expect("B07_Marker", B07_Marker(), 0xB07);
  B07_Expect("B07_PrintLinked", FnAddr("Print") != 0, 1);
}
// Ex1 Warmup: B07_Marker linked.
I64 B07_Ex1_Self()
{
  // TODO Fill_in: if (FnAddr("B07_Marker")) return 1; return 0;
  return 0;
}
// Ex2: Help linked.
I64 B07_Ex2_Help()
{
  // TODO Fill_in: if (FnAddr("Help")) return 1; return 0;
  return 0;
}
// Ex3: Man linked.
I64 B07_Ex3_Man()
{
  // TODO Fill_in: if (FnAddr("Man")) return 1; return 0;
  return 0;
}
// Ex4: call through -- return B07_Marker().
I64 B07_Ex4_Call()
{
  // TODO Fill_in: return B07_Marker();
  return 0;
}
// Ex5: unknown symbol -> FnAddr returns 0.
I64 B07_Ex5_Missing()
{
  // TODO Fill_in: if (!FnAddr("NoSuchFun_B07_XYZ")) return 1; return 0;
  return 0;
}
// Ex6: two lookups of Print agree.
I64 B07_Ex6_Stable()
{
  I64 a, b;
  // TODO Fill_in:
  //   a = FnAddr("Print"); b = FnAddr("Print");
  //   if (a && a == b) return 1; return 0;
  return 0;
}
// Ex7 Challenge: StrCmp name equality proxy -- "Print" length.
I64 B07_Ex7_NameLen()
{
  // TODO Fill_in: return StrLen("Print");
  return 0;
}
// Ex8 Challenge: Tutorial entry exists after boot Run("tutorial.hc").
I64 B07_Ex8_Tutorial()
{
  // TODO Fill_in: if (FnAddr("Tutorial")) return 1; return 0;
  return 0;
}

U0 B07_Check()
{
  Print("-- B07 exercises --\n");
  B07_Expect("Ex1_Self", B07_Ex1_Self(), 1);
  B07_Expect("Ex2_Help", B07_Ex2_Help(), 1);
  B07_Expect("Ex3_Man", B07_Ex3_Man(), 1);
  B07_Expect("Ex4_Call", B07_Ex4_Call(), 0xB07);
  B07_Expect("Ex5_Missing", B07_Ex5_Missing(), 1);
  B07_Expect("Ex6_Stable", B07_Ex6_Stable(), 1);
  B07_Expect("Ex7_NameLen", B07_Ex7_NameLen(), 5);
  B07_Expect("Ex8_Tutorial", B07_Ex8_Tutorial(), 1);
}

U0 B07()
{
  Print("=== B07 CSAPP Ch.7 Linking ===\n");
  B07_Demo();
  B07_Check();
  Print("Try: Src(\"Help\"); FnAddr(\"Help\");\n");
  Print("Next: Run(\"B08_ECF.hc\");\n");
}
B07;
