// A06_AsmHolyC.hc -- Part A6: unlabeled asm{} inside HolyC
//
// HOW TO WORK THIS LAB
//   Run("A06_AsmHolyC.hc");  edit Fill_in;  Run again.
//
// LEARNING GOALS
//   This REPL accepts unlabeled asm { ... } blocks. The host assembler
//   (TryAssembleRiscV) emits raw RV64 into the function body. Constraints:
//     - Prefer simple GPR ops (li/addi/add/sub/ld/sd/...).
//     - Tab-complete opcodes/GPRs via asm_complete.hc inside asm{}.
//     - Labels / complex fixups are limited vs a full .s file -- keep
//       blocks short; use HolyC for control flow when unsure.
//     - After asm, Reg("t0"); to inspect. Uf("Fun"); Disasm("Fun"); show
//       how HolyC and asm coexist in one function.
//
//   Guest destination: Compiler/Asm_RV.HC for self-host; today the UART
//   REPL path is host TryAssembleRiscV (see docs/REPL.md).
//
// NEXT
//   A07_MemMapMan -- dig from address map to drivers to Man pages.
U0 A06_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 A06_Demo()
{
  Print("A06 demo: unlabeled asm mutates t0; Reg to inspect\n");
  asm {
	li t0, 100
	addi t0, t0, 1
  }
  ;
  Reg("t0");
  Print("Tab inside asm{} completes opcodes. Uf(\"Print\"); for codegen.\n");
  A06_Expect("A06_Demo_math", 100 + 1, 101);
}
// Ex1 Warmup: double via shift -- return x*2.
I64 A06_Ex1_Double(I64 x)
{
  // TODO Fill_in: return x << 1;  // models slli rd,rs,1
  return 0;
}
// Ex2: models addi a7,a7,a7 after li a7,21 -> 42.
I64 A06_Ex2_Double21()
{
  I64 a7;
  // TODO Fill_in: a7 = 21; a7 = a7 + a7; return a7;
  a7 = 0;
  return a7;
}
// Ex3: mask low 12 bits (I-type imm width).
I64 A06_Ex3_ImmMask(I64 x)
{
  // TODO Fill_in: return x & 0xFFF;
  return 0;
}
// Ex4: mv pattern -- copy.
I64 A06_Ex4_Mv(I64 rs)
{
  // TODO Fill_in: return rs;
  return 0;
}
// Ex5: sub as add of negate for constants: x - 5 via x + (-5).
I64 A06_Ex5_SubConst(I64 x)
{
  // TODO Fill_in: return x + (-5);
  return 0;
}
// Ex6: which tool lists opcodes for Tab? Return 1 if you will open
// asm_complete.hc / Man topics -- we check a checksum of the idea:
// return StrLen("asm") == 3 as a stand-in "I know the seed exists".
I64 A06_Ex6_AsmCompleteHint()
{
  // TODO Fill_in: return StrLen("asm");
  return 0;
}
// Ex7 Challenge: simulate 3-instruction seq li t0,7; addi t0,t0,1; slli t0,t0,2
// -> ((7+1)<<2) = 32.
I64 A06_Ex7_Seq()
{
  I64 t0;
  // TODO Fill_in
  t0 = 0;
  return t0;
}
// Ex8 Challenge: Uf exists for A06_Ex1_Double after this file loads.
// Return 1 if FnAddr("A06_Ex1_Double") != 0.
I64 A06_Ex8_Linked()
{
  // TODO Fill_in: if (FnAddr("A06_Ex1_Double")) return 1; return 0;
  return 0;
}

U0 A06_Check()
{
  Print("-- A06 exercises --\n");
  A06_Expect("Ex1_Double", A06_Ex1_Double(21), 42);
  A06_Expect("Ex2_Double21", A06_Ex2_Double21(), 42);
  A06_Expect("Ex3_ImmMask", A06_Ex3_ImmMask(0x12345), 0x345);
  A06_Expect("Ex4_Mv", A06_Ex4_Mv(0x55), 0x55);
  A06_Expect("Ex5_SubConst", A06_Ex5_SubConst(12), 7);
  A06_Expect("Ex6_AsmCompleteHint", A06_Ex6_AsmCompleteHint(), 3);
  A06_Expect("Ex7_Seq", A06_Ex7_Seq(), 32);
  A06_Expect("Ex8_Linked", A06_Ex8_Linked(), 1);
}

U0 A06()
{
  Print("=== A06 asm{} in HolyC ===\n");
  A06_Demo();
  A06_Check();
  Print("Next: Run(\"A07_MemMapMan.hc\");\n");
}
A06;
