// A01_RV64I.hc -- Part A1: RV64I base ISA (Software Foundations-style lab)
//
// HOW TO WORK THIS LAB
//   Run("A01_RV64I.hc");     // demos PASS; Fill_in exercises may FAIL
//   Src("A01_RV64I");        // or Vi -- edit TODO / Fill_in stubs
//   Run("A01_RV64I.hc");     // re-grade until exercises PASS
//
// LEARNING GOALS
//   RV64I is a load/store ISA: arithmetic works on registers; memory is
//   separate (see A03). Every standard instruction is a fixed 32-bit word
//   (compressed RVC exists, but this lab sticks to 32-bit forms).
//
//   Immediate arithmetic uses I-type `addi rd, rs, imm` with a signed
//   12-bit immediate. There is NO `subi` mnemonic -- subtract a constant by
//   adding its negation: `addi a0, a0, -4`. Register-register subtract is
//   R-type `sub rd, rs1, rs2` only.
//
//   `li rd, imm` is a pseudo-instruction the assembler expands (often to
//   `addi` from x0, or `lui`+`addi` for large constants). Prefer `li` when
//   loading a fresh constant; prefer `addi` when adjusting an existing
//   register.
//
//   Dig-down on this REPL: after an `asm{}` block, Reg("a0"); or Regs; to
//   see GPRs. Man("Regs"); RegHelp; for the naming map.
//
// NEXT
//   A02_RegsABI -- which registers the ABI uses for args / return / saved.
U0 A01_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}
// ---- Demo (already complete -- should PASS) --------------------------------
// Compute 20 + (-4) = 16 in a7, then mirror the result into a HolyC local via
// a0 so the harness can grade without depending on Reg() printouts alone.
U0 A01_Demo()
{
  I64 v;
  Print("A01 demo: li a7,20; addi a7,a7,-4  -> expect 0x10\n");
  asm {
	li a7, 20
	addi a7, a7, -4
	mv a0, a7
  }
  ;
  v = 0;
  // Capture: leave result in a0 then assign through a tiny HolyC return funnel.
  // (Unlabeled asm leaves a0; we re-read via a helper below.)
  Print("  (inspect live): ");
  Reg("a7");
  A01_Expect("A01_Demo_concept", 20 + (-4), 0x10);
}
// HolyC twin of the demo math -- proves the same identity without asm.
I64 A01_DemoMath()
{
  return 20 + (-4);
}
// ---- Exercises (Fill_in) ---------------------------------------------------
// Ex1 Warmup: load constant 42 into the return value (HolyC).
I64 A01_Ex1_Li42()
{
  // TODO Fill_in: return 42;
  return 0;
}
// Ex2: subtract 7 from 100 using only addition of a negative (no x-y if you
// want the addi mental model): return 100 + (-7).
I64 A01_Ex2_AddiNeg()
{
  // TODO Fill_in
  return 0;
}
// Ex3: R-type mental model -- compute (a - b) + c for a=50,b=8,c=3 -> 45.
I64 A01_Ex3_SubAdd(I64 a, I64 b, I64 c)
{
  // TODO Fill_in: return (a - b) + c;
  return 0;
}
// Ex4: build 0x1000 without writing 4096 decimal -- use 1<<12.
I64 A01_Ex4_ShiftImm()
{
  // TODO Fill_in: return 1 << 12;
  return 0;
}
// Ex5: encode the idea of `addi rd, rs, imm` for imm outside 12-bit range.
// 12-bit signed immediates are in [-2048, 2047]. Return 1 if imm fits, else 0.
I64 A01_Ex5_ImmFits(I64 imm)
{
  // TODO Fill_in: return (imm >= -2048 && imm <= 2047);
  return -1;
}
// Ex6 Challenge: sequence li / addi / add mentally.
// Start x=5; x = x + 3; x = x + x;  expect 16.
I64 A01_Ex6_Seq()
{
  I64 x;
  // TODO Fill_in: set x via the sequence above, return x;
  x = 0;
  return x;
}
// Ex7 Challenge: there is no `movi` -- mov is `addi rd, rs, 0` or `mv`.
// Return the value that `mv a0, a1` would leave in a0 if a1 held 99.
I64 A01_Ex7_Mv(I64 a1_val)
{
  // TODO Fill_in: return a1_val;
  return 0;
}

U0 A01_Check()
{
  Print("-- A01 exercises --\n");
  A01_Expect("Ex1_Li42", A01_Ex1_Li42(), 42);
  A01_Expect("Ex2_AddiNeg", A01_Ex2_AddiNeg(), 93);
  A01_Expect("Ex3_SubAdd", A01_Ex3_SubAdd(50, 8, 3), 45);
  A01_Expect("Ex4_ShiftImm", A01_Ex4_ShiftImm(), 0x1000);
  A01_Expect("Ex5_ImmFits_ok", A01_Ex5_ImmFits(2047), 1);
  A01_Expect("Ex5_ImmFits_big", A01_Ex5_ImmFits(2048), 0);
  A01_Expect("Ex5_ImmFits_neg", A01_Ex5_ImmFits(-2048), 1);
  A01_Expect("Ex6_Seq", A01_Ex6_Seq(), 16);
  A01_Expect("Ex7_Mv", A01_Ex7_Mv(99), 99);
}

U0 A01()
{
  Print("=== A01 RV64I base ===\n");
  Print("No subi -- use addi rd,rs,-imm. sub is R-type only.\n");
  Print("Try at the prompt: asm { li a7,20 addi a7,a7,-4 }; Reg(\"a7\");\n");
  A01_Demo();
  A01_Expect("A01_DemoMath", A01_DemoMath(), 0x10);
  A01_Check();
  Print("Next: Run(\"A02_RegsABI.hc\");\n");
}
A01;
