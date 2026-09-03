// A04_Branches.hc -- Part A4: Branches and control flow
//
// HOW TO WORK THIS LAB
//   Run("A04_Branches.hc");  edit Fill_in;  Run again.
//
// LEARNING GOALS
//   Conditional branches compare two registers: beq/bne/blt/bge/bltu/bgeu.
//   There is no single "branch on register == 0" distinct from beq rs,x0,lab
//   (pseudo: beqz). Jumps: jal (link), jalr (indirect), and pseudo j/jr/ret.
//
//   HolyC if / while / for compile to those branches. Studying Uf("Name")
//   shows the concrete RV mix for your function -- use that instead of an
//   x86 CSAPP listing.
//
//   Compare signed vs unsigned carefully (blt vs bltu). HolyC I64 compares
//   are signed unless you cast to unsigned widths.
//
// NEXT
//   A05_CSRTraps -- CSRs, traps, CLINT (do not TrapInit at lesson load).
U0 A04_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

I64 A04_Abs(I64 x)
{
  if (x < 0)
    return -x;
  return x;
}

U0 A04_Demo()
{
  Print("A04 demo Abs(-5)=%d Abs(7)=%d\n", A04_Abs(-5), A04_Abs(7));
  Print("Disassemble Abs -- find branches:\n");
  Uf("A04_Abs");
  A04_Expect("A04_Abs", A04_Abs(-5), 5);
}
// Ex1 Warmup: equality -> 1 / 0.
I64 A04_Ex1_Eq(I64 a, I64 b)
{
  // TODO Fill_in: if (a == b) return 1; return -1;
  return 0;
}
// Ex2: not-equal.
I64 A04_Ex2_Ne(I64 a, I64 b)
{
  // TODO Fill_in
  return -1;
}
// Ex3: signed less-than (models blt).
I64 A04_Ex3_Lt(I64 a, I64 b)
{
  // TODO Fill_in: if (a < b) return 1; return -1;
  return 0;
}
// Ex4: clamp x into [lo, hi] inclusive.
I64 A04_Ex4_Clamp(I64 x, I64 lo, I64 hi)
{
  // TODO Fill_in
  return x;
}
// Ex5: countdown sum: sum 1..n (0 if n<1).
I64 A04_Ex5_SumTo(I64 n)
{
  I64 s, i;
  // TODO Fill_in: for-loop or while
  s = 0;
  return s;
}
// Ex6: max of three.
I64 A04_Ex6_Max3(I64 a, I64 b, I64 c)
{
  // TODO Fill_in
  return a;
}
// Ex7 Challenge: branchless abs using arithmetic (optional style).
// Allowed to use if; challenge is correct for INT_MIN-ish: for this lab,
// only test values where -x does not overflow the exercise (no 1<<63).
I64 A04_Ex7_Abs(I64 x)
{
  // TODO Fill_in
  return x;
}
// Ex8 Challenge: compare unsigned -- treat args as U64 via cast.
// Return 1 if (U64)a < (U64)b.
I64 A04_Ex8_Ltu(I64 a, I64 b)
{
  // TODO Fill_in: if ((U64)a < (U64)b) return 1; return -1;
  return 0;
}

U0 A04_Check()
{
  Print("-- A04 exercises --\n");
  A04_Expect("Ex1_Eq_yes", A04_Ex1_Eq(3, 3), 1);
  A04_Expect("Ex1_Eq_no", A04_Ex1_Eq(1, 2), 0);
  A04_Expect("Ex2_Ne", A04_Ex2_Ne(1, 2), 1);
  A04_Expect("Ex3_Lt", A04_Ex3_Lt(-1, 0), 1);
  A04_Expect("Ex4_Clamp", A04_Ex4_Clamp(50, 0, 10), 10);
  A04_Expect("Ex4_Clamp_lo", A04_Ex4_Clamp(-3, 0, 10), 0);
  A04_Expect("Ex5_SumTo", A04_Ex5_SumTo(10), 55);
  A04_Expect("Ex6_Max3", A04_Ex6_Max3(3, 9, 4), 9);
  A04_Expect("Ex7_Abs", A04_Ex7_Abs(-42), 42);
  A04_Expect("Ex8_Ltu", A04_Ex8_Ltu(-1, 1), 0);
  // U64(-1) > 1
  A04_Expect("Ex8_Ltu2", A04_Ex8_Ltu(1, -1), 1);
}

U0 A04()
{
  Print("=== A04 Branches & control ===\n");
  A04_Demo();
  A04_Check();
  Print("Next: Run(\"A05_CSRTraps.hc\");\n");
}
A04;
