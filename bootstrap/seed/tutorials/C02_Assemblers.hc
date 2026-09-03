// C02_Assemblers.hc -- Beck 3e Ch.2: Assemblers
// Remap: HolyC asm{} + Asm_RV / host TryAssembleRiscV (not SIC assembler).
//
// HOW TO WORK THIS LAB
//   Run("C02_Assemblers.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Two-pass assembly, symbol tables, literals, program blocks. Here:
//   unlabeled asm{} is pass-ish (host encodes now); symbols live in the
//   HolyC hash; Disasm/Uf verify. Tables: seed/asm_complete.hc.
//
// NEXT
//   C03_LoadersLinkers.
U0 C02_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 C02_Demo()
{
  Print("C02 demo: assemble a short block; Reg to verify\n");
  asm {
	li a0, 0x11
	addi a0, a0, 0x22
  }
  ;
  Reg("a0");
  Print("Expect mental math 0x11+0x22=0x33. Tables: asm_complete.hc\n");
  C02_Expect("C02_math", 0x11 + 0x22, 0x33);
}
// Ex1 Warmup: li+addi math.
I64 C02_Ex1_LiAddi()
{
  // TODO Fill_in: return 0x11 + 0x22;
  return 0;
}
// Ex2: opcode low 7 of addi = 0x13.
I64 C02_Ex2_AddiOp()
{
  // TODO Fill_in: return 0x13;
  return 0;
}
// Ex3: number of GPRs.
I64 C02_Ex3_NGpr()
{
  // TODO Fill_in: return 32;
  return 0;
}
// Ex4: two-pass idea -- return 2.
I64 C02_Ex4_Passes()
{
  // TODO Fill_in: return 2;
  return 0;
}
// Ex5: asm_complete seed idea -- StrLen("addi").
I64 C02_Ex5_Mnemonic()
{
  // TODO Fill_in: return StrLen("addi");
  return 0;
}
// Ex6: encode rd=1 field <<7 into a word that already has opcode 0x13.
I64 C02_Ex6_WithRd()
{
  // TODO Fill_in: return 0x13 | (1 << 7);
  return 0;
}
// Ex7 Challenge: Disasm/Uf available -- FnAddr("Uf") non-zero.
I64 C02_Ex7_Uf()
{
  // TODO Fill_in: if (FnAddr("Uf")) return 1; return 0;
  return 0;
}
// Ex8 Challenge: simulate symbol resolution -- "value of L" given L=40+2.
I64 C02_Ex8_Sym()
{
  I64 L;
  // TODO Fill_in: L = 40 + 2; return L;
  return 0;
}

U0 C02_Check()
{
  Print("-- C02 exercises --\n");
  C02_Expect("Ex1_LiAddi", C02_Ex1_LiAddi(), 0x33);
  C02_Expect("Ex2_AddiOp", C02_Ex2_AddiOp(), 0x13);
  C02_Expect("Ex3_NGpr", C02_Ex3_NGpr(), 32);
  C02_Expect("Ex4_Passes", C02_Ex4_Passes(), 2);
  C02_Expect("Ex5_Mnemonic", C02_Ex5_Mnemonic(), 4);
  C02_Expect("Ex6_WithRd", C02_Ex6_WithRd(), 0x13 | (1 << 7));
  C02_Expect("Ex7_Uf", C02_Ex7_Uf(), 1);
  C02_Expect("Ex8_Sym", C02_Ex8_Sym(), 42);
}

U0 C02()
{
  Print("=== C02 Beck Ch.2 Assemblers ===\n");
  C02_Demo();
  C02_Check();
  Print("Next: Run(\"C03_LoadersLinkers.hc\");\n");
}
C02;
