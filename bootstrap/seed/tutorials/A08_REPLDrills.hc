// A08_REPLDrills.hc -- Part A8: REPL capstone drills
//
// HOW TO WORK THIS LAB
//   Run("A08_REPLDrills.hc");  edit Fill_in;  Run again.
//   This chapter combines A01-A07 skills: bits, asm intuition, MemMap, Man.
//
// LEARNING GOALS
//   Capstone: you can dig from a symptom (wrong device, wrong value) to
//   MemMap / Regs / Uf / Man without leaving the UART REPL. Part B (CSAPP)
//   assumes this vocabulary -- bits and machines on THIS stack, not x86 Linux.
//
// NEXT
//   B01_Tour -- CSAPP Ch.1 remapped to TempleOS RISC-V HolyC.
U0 A08_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

I64 A08_Popcount(I64 v)
{
  I64 n;
  n = 0;
  while (v) {
    n++;
    v = v & (v - 1);
  }
  return n;
}

U0 A08_Demo()
{
  Print("A08 demo Popcount(0xF0)=%d (expect 4)\n", A08_Popcount(0xF0));
  Uf("A08_Popcount");
  A08_Expect("A08_Popcount", A08_Popcount(0xF0), 4);
  Print("Quick dig: MemMapFind(\"uart\")=%X\n", MemMapFind("uart"));
}
// Ex1 Warmup: popcount.
I64 A08_Ex1_Pop(I64 v)
{
  // TODO Fill_in: reuse Kernighan loop or call A08_Popcount
  return 0;
}
// Ex2: byte-swap low 16 bits (0x1234 -> 0x3412).
I64 A08_Ex2_Bswap16(I64 x)
{
  // TODO Fill_in:
  //   x = x & 0xFFFF;
  //   return ((x & 0xFF) << 8) | ((x >> 8) & 0xFF);
  return x;
}
// Ex3: rotate-left 32-bit lane by n (0..31), low 32 bits only.
I64 A08_Ex3_Rol32(I64 x, I64 n)
{
  U32 u, r;
  // TODO Fill_in:
  //   u = x; n = n & 31;
  //   r = (u << n) | (u >> (32 - n));
  //   if (!n) r = u;
  //   return r;
  return 0;
}
// Ex4: MemMap uart matches MEM_UART.
I64 A08_Ex4_Uart()
{
  // TODO Fill_in: return MemMapFind("uart");
  return 0;
}
// Ex5: sign-extend U8.
I64 A08_Ex5_Sext(I64 b)
{
  // TODO Fill_in (same as A03_Ex4)
  return -1;
}
// Ex6: ABI -- number of arg regs.
I64 A08_Ex6_Args()
{
  // TODO Fill_in: return 8;
  return 0;
}
// Ex7 Challenge: build 0xDEADBEEF from halves.
I64 A08_Ex7_Join()
{
  I64 hi, lo;
  // TODO Fill_in:
  //   hi = 0xDEAD; lo = 0xBEEF;
  //   return (hi << 16) | lo;
  return 0;
}
// Ex8 Challenge: FnAddr("A08_Popcount") non-zero.
I64 A08_Ex8_Sym()
{
  // TODO Fill_in: if (FnAddr("A08_Popcount")) return 1; return 0;
  return 0;
}

U0 A08_Check()
{
  Print("-- A08 exercises --\n");
  A08_Expect("Ex1_Pop", A08_Ex1_Pop(0xF0), 4);
  A08_Expect("Ex2_Bswap16", A08_Ex2_Bswap16(0x1234), 0x3412);
  A08_Expect("Ex3_Rol32", A08_Ex3_Rol32(0x80000001, 1), 0x00000003);
  A08_Expect("Ex4_Uart", A08_Ex4_Uart(), MEM_UART);
  A08_Expect("Ex5_Sext", A08_Ex5_Sext(0xFF), -1);
  A08_Expect("Ex6_Args", A08_Ex6_Args(), 8);
  A08_Expect("Ex7_Join", A08_Ex7_Join(), 0xDEADBEEF);
  A08_Expect("Ex8_Sym", A08_Ex8_Sym(), 1);
}

U0 A08()
{
  Print("=== A08 REPL drills (Part A capstone) ===\n");
  A08_Demo();
  A08_Check();
  Print("Part A done. Part B: Run(\"B01_Tour.hc\"); or Tutorial;\n");
}
A08;
