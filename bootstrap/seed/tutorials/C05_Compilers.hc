// C05_Compilers.hc -- Beck 3e Ch.5: Compilers
// Remap: host holyc-riscv vs guest Compiler_RV / ExePutS.
//
// HOW TO WORK THIS LAB
//   Run("C05_Compilers.hc");  Uf("C05_Sq");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   Lexing, parsing, codegen, optimization. Two compilers matter here:
//     host/  -- holyc-riscv (lexer.c parser.c compiler.c) drives REPL today
//     Compiler/* + Back*_RV + OptPass_RV -- guest self-host path
//   Study Uf output as the compiler's evidence. Docs: COMPILER_RV.md.
//
// NEXT
//   C06_OperatingSystems.
U0 C05_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

I64 C05_Sq(I64 x)
{
  return x *x;
}

I64 C05_Add(I64 a, I64 b)
{
  return a + b;
}

U0 C05_Demo()
{
  Print("C05 demo Sq(7)=%d Add(20,22)=%d\n", C05_Sq(7), C05_Add(20, 22));
  Uf("C05_Sq");
  Print("Host: host/lexer.c parser.c compiler.c -> RV\n");
  Print("Guest: Compiler/* + Back*_RV + OptPass_RV; ExePutS/Cmp\n");
  C05_Expect("C05_Sq", C05_Sq(7), 49);
}
// Ex1 Warmup: square.
I64 C05_Ex1_Sq(I64 x)
{
  // TODO Fill_in: return x * x;
  return 0;
}
// Ex2: three-address style -- t1=a+b; t2=t1*c; return t2.
I64 C05_Ex2_Tac(I64 a, I64 b, I64 c)
{
  I64 t1, t2;
  // TODO Fill_in
  return 0;
}
// Ex3: constant fold mental -- 2+3*4.
I64 C05_Ex3_Fold()
{
  // TODO Fill_in: return 2 + 3 * 4;
  return 0;
}
// Ex4: Uf linked.
I64 C05_Ex4_Uf()
{
  // TODO Fill_in: if (FnAddr("Uf")) return 1; return 0;
  return 0;
}
// Ex5: C05_Sq linked.
I64 C05_Ex5_Self()
{
  // TODO Fill_in: if (FnAddr("C05_Sq")) return 1; return 0;
  return 0;
}
// Ex6: phases taught -- lex/parse/codegen = 3.
I64 C05_Ex6_Phases()
{
  // TODO Fill_in: return 3;
  return 0;
}
// Ex7 Challenge: identity IR -- return x.
I64 C05_Ex7_Id(I64 x)
{
  // TODO Fill_in: return x;
  return 0;
}
// Ex8 Challenge: compare Sq vs mul -- Sq(8)==64.
I64 C05_Ex8_CheckSq()
{
  // TODO Fill_in: if (C05_Ex1_Sq(8) == 64) return 1; return 0;
  return 0;
}

U0 C05_Check()
{
  Print("-- C05 exercises --\n");
  C05_Expect("Ex1_Sq", C05_Ex1_Sq(7), 49);
  C05_Expect("Ex2_Tac", C05_Ex2_Tac(2, 3, 4), 20);
  C05_Expect("Ex3_Fold", C05_Ex3_Fold(), 14);
  C05_Expect("Ex4_Uf", C05_Ex4_Uf(), 1);
  C05_Expect("Ex5_Self", C05_Ex5_Self(), 1);
  C05_Expect("Ex6_Phases", C05_Ex6_Phases(), 3);
  C05_Expect("Ex7_Id", C05_Ex7_Id(99), 99);
  C05_Expect("Ex8_CheckSq", C05_Ex8_CheckSq(), 1);
}

U0 C05()
{
  Print("=== C05 Beck Ch.5 Compilers ===\n");
  C05_Demo();
  C05_Check();
  Print("Host: make kernel-phase3-smoke; skim COMPILER_RV.md\n");
  Print("Next: Run(\"C06_OperatingSystems.hc\");\n");
}
C05;
