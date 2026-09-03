// B03_Machine.hc -- CSAPP 3e Ch.3: Machine-Level Representation of Programs
// Remap: HolyC -> RV64 via Uf / Disasm / asm{}; not x86-64 AT&T listings.
//
// HOW TO WORK THIS LAB
//   Run("B03_Machine.hc");  edit Fill_in;  Uf("B03_Add");  Run again.
//
// BOOK THEMES
//   CSAPP Ch.3 walks compilers' lowering of C to asm. Here you study the
//   RV64 the host emits: call/return, stack frames, lea-like addi patterns,
//   and how HolyC control becomes beq/jal. Prefer Uf("Name") over guessing.
//
// NEXT
//   B04_Processor -- pipeline intuition on real RV encodings.
U0 B03_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

I64 B03_Add(I64 x, I64 y)
{
  return x + y;
}

U0 B03_Demo()
{
  Print("B03 demo Add(20,22)=%d\n", B03_Add(20, 22));
  Print("Disassemble:\n");
  Uf("B03_Add");
  B03_Expect("B03_Add", B03_Add(20, 22), 42);
}
// Ex1 Warmup: mul by 3.
I64 B03_Ex1_Mul3(I64 x)
{
  // TODO Fill_in: return x * 3;  then Uf("B03_Ex1_Mul3");
  return x;
}
// Ex2: lea-like -- 4*x + y (scale + add).
I64 B03_Ex2_Lea(I64 x, I64 y)
{
  // TODO Fill_in: return (x << 2) + y;
  return 0;
}
// Ex3: abs via control (study Uf after).
I64 B03_Ex3_Abs(I64 x)
{
  // TODO Fill_in
  return x;
}
// Ex4: swap via temps -- return a after swap(a,b) conceptually as b.
// Function returns the new a (= old b).
I64 B03_Ex4_SwapRetA(I64 a, I64 b)
{
  I64 t;
  // TODO Fill_in: t=a; a=b; b=t; return a;
  return a;
}
// Ex5: pointer deref write.
I64 B03_Ex5_Store(I64 *p, I64 v)
{
  // TODO Fill_in: *p = v; return *p;
  return 0;
}
// Ex6: array sum of 4 I64s pointed by p.
I64 B03_Ex6_Sum4(I64 *p)
{
  // TODO Fill_in: return p[0]+p[1]+p[2]+p[3];
  return 0;
}
// Ex7 Challenge: factorial n! for n in 0..10.
I64 B03_Ex7_Fact(I64 n)
{
  I64 r, i;
  // TODO Fill_in
  r = 1;
  return r;
}
// Ex8 Challenge: FnAddr of B03_Add non-zero + call through intuition.
I64 B03_Ex8_Addr()
{
  // TODO Fill_in: return FnAddr("B03_Add") != 0;
  return 0;
}

U0 B03_Check()
{
  I64 a[4], cell;
  Print("-- B03 exercises --\n");
  B03_Expect("Ex1_Mul3", B03_Ex1_Mul3(7), 21);
  B03_Expect("Ex2_Lea", B03_Ex2_Lea(3, 5), 17);
  B03_Expect("Ex3_Abs", B03_Ex3_Abs(-9), 9);
  B03_Expect("Ex4_SwapRetA", B03_Ex4_SwapRetA(1, 2), 2);
  cell = 0;
  B03_Expect("Ex5_Store", B03_Ex5_Store(&cell, 0x55), 0x55);
  a[0] = 1;
  a[1] = 2;
  a[2] = 3;
  a[3] = 4;
  B03_Expect("Ex6_Sum4", B03_Ex6_Sum4(a), 10);
  B03_Expect("Ex7_Fact", B03_Ex7_Fact(5), 120);
  B03_Expect("Ex8_Addr", B03_Ex8_Addr(), 1);
}

U0 B03()
{
  Print("=== B03 CSAPP Ch.3 Machine-level representation ===\n");
  B03_Demo();
  B03_Check();
  Print("Next: Run(\"B04_Processor.hc\");\n");
}
B03;
