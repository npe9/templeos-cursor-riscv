// C08_SoftwareEngineering.hc -- Beck 3e Ch.8: Software Engineering Issues
// Remap: make ci / fmt / repl-regression as the engineering loop for this port.
//
// HOW TO WORK THIS LAB
//   Run("C08_SoftwareEngineering.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Specs, testing, maintenance, documentation. On this repo the loop is:
//     make / make fmt / make fmt-check
//     make repl-smoke / make repl-regression
//     make ci  (compliance + qemu-integration)
//   Docs: CONTRIBUTING.md AGENTS.md tests/REGRESSION.md docs/tutorials/.
//   After seed edits: make repl-blob && rebuild Makefile.repl.
//
// CURRICULUM
//   Complete -- Tutorial; anytime to pick another lab.
U0 C08_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 C08_Demo()
{
  Print("C08 engineering loop:\n");
  Print("  make / make fmt / make fmt-check\n");
  Print("  make repl-smoke / make repl-regression\n");
  Print("  make ci  (compliance + qemu-integration)\n");
  Print("Docs: CONTRIBUTING.md AGENTS.md tests/REGRESSION.md\n");
  Print("Seeds: make repl-blob after tutorial edits\n");
  C08_Expect("C08_Tutorial", FnAddr("Tutorial") != 0, 1);
}
// Ex1 Warmup: Tutorial linked.
I64 C08_Ex1_Tutorial()
{
  // TODO Fill_in: if (FnAddr("Tutorial")) return 1; return 0;
  return 0;
}
// Ex2: SF alias linked.
I64 C08_Ex2_SF()
{
  // TODO Fill_in: if (FnAddr("SF")) return 1; return 0;
  return 0;
}
// Ex3: fmt tool linked.
I64 C08_Ex3_Fmt()
{
  // TODO Fill_in: if (FnAddr("Fmt")) return 1; return 0;
  return 0;
}
// Ex4: Help linked.
I64 C08_Ex4_Help()
{
  // TODO Fill_in: if (FnAddr("Help")) return 1; return 0;
  return 0;
}
// Ex5: engineering gates count we listed -- smoke/regression/ci/fmt = 4.
I64 C08_Ex5_Gates()
{
  // TODO Fill_in: return 4;
  return 0;
}
// Ex6: affirm must rebuild blob after seed edits.
I64 C08_Ex6_Blob()
{
  // TODO Fill_in: return 1;
  return -1;
}
// Ex7 Challenge: StrLen("regression").
I64 C08_Ex7_Word()
{
  // TODO Fill_in: return StrLen("regression");
  return 0;
}
// Ex8 Challenge: curriculum parts A+B+C = 3.
I64 C08_Ex8_Parts()
{
  // TODO Fill_in: return 3;
  return 0;
}

U0 C08_Check()
{
  Print("-- C08 exercises --\n");
  C08_Expect("Ex1_Tutorial", C08_Ex1_Tutorial(), 1);
  C08_Expect("Ex2_SF", C08_Ex2_SF(), 1);
  C08_Expect("Ex3_Fmt", C08_Ex3_Fmt(), 1);
  C08_Expect("Ex4_Help", C08_Ex4_Help(), 1);
  C08_Expect("Ex5_Gates", C08_Ex5_Gates(), 4);
  C08_Expect("Ex6_Blob", C08_Ex6_Blob(), 1);
  C08_Expect("Ex7_Word", C08_Ex7_Word(), 10);
  C08_Expect("Ex8_Parts", C08_Ex8_Parts(), 3);
}

U0 C08()
{
  Print("=== C08 Beck Ch.8 Software engineering issues ===\n");
  C08_Demo();
  C08_Check();
  Print("Curriculum complete. Tutorial; anytime.\n");
  Print("Rebuild blob after seed edits: make repl-blob\n");
}
C08;
