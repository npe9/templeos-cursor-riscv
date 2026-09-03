// B05_Optimize.hc -- CSAPP 3e Ch.5: Optimizing Program Performance
// Remap: HolyC loops + closed forms; host flags HOLYC_NO_OPT / tiers -- not gcc -O3 x86.
//
// HOW TO WORK THIS LAB
//   Run("B05_Optimize.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   CSAPP measures CPE, removes memory aliases, unrolls, exploits ILP.
//   Here: write clear HolyC first; compare naive vs closed form; peek Uf
//   for instruction mix. Host bisect: HOLYC_NO_OPT=1 / HOLYC_NO_TIER2=1.
//
// NEXT
//   B06_MemHierarchy -- MEM_* as the visible hierarchy.
U0 B05_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

I64 B05_SumLoop(I64 n)
{
  I64 i, s;
  s = 0;
  for (i = 1; i <= n; i++)
    s += i;
  return s;
}

U0 B05_Demo()
{
  Print("B05 demo SumLoop(100)=%d (expect 5050)\n", B05_SumLoop(100));
  Uf("B05_SumLoop");
  B05_Expect("B05_SumLoop", B05_SumLoop(100), 5050);
}
// Ex1 Warmup: closed form n(n+1)/2.
I64 B05_Ex1_SumClosed(I64 n)
{
  // TODO Fill_in: return n * (n + 1) / 2;
  return 0;
}
// Ex2: sum of squares 1^2..n^2 = n(n+1)(2n+1)/6.
I64 B05_Ex2_SumSq(I64 n)
{
  // TODO Fill_in: return n * (n + 1) * (2 * n + 1) / 6;
  return 0;
}
// Ex3: naive product 1..n (factorial) -- careful n<=12 for I64 demos.
I64 B05_Ex3_Fact(I64 n)
{
  I64 i, p;
  // TODO Fill_in
  p = 1;
  return p;
}
// Ex4: strength reduction -- 8*x via shift.
I64 B05_Ex4_Mul8(I64 x)
{
  // TODO Fill_in: return x << 3;
  return 0;
}
// Ex5: avoid repeated work -- compute x*x once for x^2 + 2*x*x = 3 x^2.
I64 B05_Ex5_ThreeSq(I64 x)
{
  I64 sq;
  // TODO Fill_in: sq = x * x; return 3 * sq;
  return 0;
}
// Ex6: loop accumulation of array -- sum n elements at p.
I64 B05_Ex6_ArrSum(I64 *p, I64 n)
{
  I64 i, s;
  // TODO Fill_in
  s = 0;
  return s;
}
// Ex7 Challenge: Horner evaluate ((a*x+b)*x+c) for a,b,c,x.
I64 B05_Ex7_Horner(I64 a, I64 b, I64 c, I64 x)
{
  // TODO Fill_in: return (a * x + b) * x + c;
  return 0;
}
// Ex8 Challenge: is SumClosed(100) == SumLoop(100)? return 1 if equal.
I64 B05_Ex8_Agree()
{
  // TODO Fill_in:
  //   if (B05_Ex1_SumClosed(100) == B05_SumLoop(100)) return 1;
  //   return 0;
  return 0;
}

U0 B05_Check()
{
  I64 buf[4];
  Print("-- B05 exercises --\n");
  B05_Expect("Ex1_SumClosed", B05_Ex1_SumClosed(100), 5050);
  B05_Expect("Ex2_SumSq", B05_Ex2_SumSq(3), 14);
  B05_Expect("Ex3_Fact", B05_Ex3_Fact(5), 120);
  B05_Expect("Ex4_Mul8", B05_Ex4_Mul8(5), 40);
  B05_Expect("Ex5_ThreeSq", B05_Ex5_ThreeSq(4), 48);
  buf[0] = 1;
  buf[1] = 2;
  buf[2] = 3;
  buf[3] = 4;
  B05_Expect("Ex6_ArrSum", B05_Ex6_ArrSum(buf, 4), 10);
  B05_Expect("Ex7_Horner", B05_Ex7_Horner(2, 3, 4, 5), 69);
  // (2*5+3)*5+4
  B05_Expect("Ex8_Agree", B05_Ex8_Agree(), 1);
}

U0 B05()
{
  Print("=== B05 CSAPP Ch.5 Optimizing performance ===\n");
  B05_Demo();
  B05_Check();
  Print("Next: Run(\"B06_MemHierarchy.hc\");\n");
}
B05;
