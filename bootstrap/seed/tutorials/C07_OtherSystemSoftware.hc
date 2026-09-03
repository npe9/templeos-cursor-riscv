// C07_OtherSystemSoftware.hc -- Beck 3e Ch.7: Other System Software
// Remap: editors, Man, Fmt, Dir, Disasm -- utilities around compiler/OS.
//
// HOW TO WORK THIS LAB
//   Run("C07_OtherSystemSoftware.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Text editors, debuggers, monitors. Here: Vi / EditHoly / Ed, Man/Help,
//   Fmt, Dir/Cat, Disasm/Uf/Funs, Regs/MemMap dig-down.
//
// NEXT
//   C08_SoftwareEngineering.
U0 C07_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 C07_Demo()
{
  Print("C07 utilities on this stack:\n");
  Print("  editors: Vi / EditHoly / Ed  (Src)\n");
  Print("  docs:    Man / Help / Sections\n");
  Print("  tools:   Fmt Dir Cat Disasm Uf Funs Regs MemMap\n");
  C07_Expect("C07_Man", FnAddr("Man") != 0, 1);
  C07_Expect("C07_Fmt", FnAddr("Fmt") != 0, 1);
}
// Ex1 Warmup: Man linked.
I64 C07_Ex1_Man()
{
  // TODO Fill_in: if (FnAddr("Man")) return 1; return 0;
  return 0;
}
// Ex2: Help linked.
I64 C07_Ex2_Help()
{
  // TODO Fill_in: if (FnAddr("Help")) return 1; return 0;
  return 0;
}
// Ex3: Dir linked.
I64 C07_Ex3_Dir()
{
  // TODO Fill_in: if (FnAddr("Dir")) return 1; return 0;
  return 0;
}
// Ex4: Fmt linked.
I64 C07_Ex4_Fmt()
{
  // TODO Fill_in: if (FnAddr("Fmt")) return 1; return 0;
  return 0;
}
// Ex5: Uf linked.
I64 C07_Ex5_Uf()
{
  // TODO Fill_in: if (FnAddr("Uf")) return 1; return 0;
  return 0;
}
// Ex6: Disasm linked.
I64 C07_Ex6_Disasm()
{
  // TODO Fill_in: if (FnAddr("Disasm")) return 1; return 0;
  return 0;
}
// Ex7 Challenge: Funs linked.
I64 C07_Ex7_Funs()
{
  // TODO Fill_in: if (FnAddr("Funs")) return 1; return 0;
  return 0;
}
// Ex8 Challenge: StrLen("Man").
I64 C07_Ex8_Name()
{
  // TODO Fill_in: return StrLen("Man");
  return 0;
}

U0 C07_Check()
{
  Print("-- C07 exercises --\n");
  C07_Expect("Ex1_Man", C07_Ex1_Man(), 1);
  C07_Expect("Ex2_Help", C07_Ex2_Help(), 1);
  C07_Expect("Ex3_Dir", C07_Ex3_Dir(), 1);
  C07_Expect("Ex4_Fmt", C07_Ex4_Fmt(), 1);
  C07_Expect("Ex5_Uf", C07_Ex5_Uf(), 1);
  C07_Expect("Ex6_Disasm", C07_Ex6_Disasm(), 1);
  C07_Expect("Ex7_Funs", C07_Ex7_Funs(), 1);
  C07_Expect("Ex8_Name", C07_Ex8_Name(), 3);
}

U0 C07()
{
  Print("=== C07 Beck Ch.7 Other system software ===\n");
  C07_Demo();
  C07_Check();
  Print("Try: Src(\"Fmt\"); Fmt a scratch .hc\n");
  Print("Next: Run(\"C08_SoftwareEngineering.hc\");\n");
}
C07;
