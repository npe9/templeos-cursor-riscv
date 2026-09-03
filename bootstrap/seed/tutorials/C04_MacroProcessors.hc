// C04_MacroProcessors.hc -- Beck 3e Ch.4: Macro Processors
// Remap: #define / seed generators -- not a full SIC macro language.
// GAP: no Beck-style macro assembler processor in-tree.
//
// HOW TO WORK THIS LAB
//   Run("C04_MacroProcessors.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Macro definition, expansion, conditional assembly. Closest tools here:
//   C-preprocessor-ish #define in HolyC, plus Python seed gens
//   (gen_boot_blob / gen_seeds) on the host.
//
// NEXT
//   C05_Compilers.
#define C04_SCALE 10
#define C04_TWICE(x) ((x) + (x))
U0 C04_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 C04_Demo()
{
  Print("C04: #define C04_SCALE=%d; 3*SCALE=%d\n", C04_SCALE, 3 * C04_SCALE);
  Print("C04_TWICE(21)=%d\n", C04_TWICE(21));
  Print("GAP: no Beck macro-assembler processor; use #define + host gens.\n");
  C04_Expect("C04_SCALE", C04_SCALE, 10);
  C04_Expect("C04_TWICE", C04_TWICE(21), 42);
}
// Ex1 Warmup: return C04_SCALE.
I64 C04_Ex1_Scale()
{
  // TODO Fill_in: return C04_SCALE;
  return 0;
}
// Ex2: 3 * SCALE.
I64 C04_Ex2_Triple()
{
  // TODO Fill_in: return 3 * C04_SCALE;
  return 0;
}
// Ex3: TWICE macro.
I64 C04_Ex3_Twice()
{
  // TODO Fill_in: return C04_TWICE(7);
  return 0;
}
// Ex4: nested -- TWICE(SCALE).
I64 C04_Ex4_Nested()
{
  // TODO Fill_in: return C04_TWICE(C04_SCALE);
  return 0;
}
// Ex5: affirm gap.
I64 C04_Ex5_Gap()
{
  // TODO Fill_in: return 1;
  return -1;
}
// Ex6: expansion count idea -- TWICE does 1 add of x+x. Return 2 operands.
I64 C04_Ex6_Operands()
{
  // TODO Fill_in: return 2;
  return 0;
}
// Ex7 Challenge: define local idea -- return 100 via a #define in comments
// already: use 10*C04_SCALE.
I64 C04_Ex7_Product()
{
  // TODO Fill_in: return 10 * C04_SCALE;
  return 0;
}
// Ex8 Challenge: StrLen("define").
I64 C04_Ex8_Word()
{
  // TODO Fill_in: return StrLen("define");
  return 0;
}

U0 C04_Check()
{
  Print("-- C04 exercises --\n");
  C04_Expect("Ex1_Scale", C04_Ex1_Scale(), 10);
  C04_Expect("Ex2_Triple", C04_Ex2_Triple(), 30);
  C04_Expect("Ex3_Twice", C04_Ex3_Twice(), 14);
  C04_Expect("Ex4_Nested", C04_Ex4_Nested(), 20);
  C04_Expect("Ex5_Gap", C04_Ex5_Gap(), 1);
  C04_Expect("Ex6_Operands", C04_Ex6_Operands(), 2);
  C04_Expect("Ex7_Product", C04_Ex7_Product(), 100);
  C04_Expect("Ex8_Word", C04_Ex8_Word(), 6);
}

U0 C04()
{
  Print("=== C04 Beck Ch.4 Macro processors ===\n");
  C04_Demo();
  C04_Check();
  Print("Next: Run(\"C05_Compilers.hc\");\n");
}
C04;
