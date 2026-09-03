// A02_RegsABI.hc -- Part A2: Registers and the RISC-V calling convention
//
// HOW TO WORK THIS LAB
//   Run("A02_RegsABI.hc");  Src("A02_RegsABI");  Run again until PASS.
//
// LEARNING GOALS
//   RV64 has 32 integer GPRs (x0..x31). ABI names matter more than numbers:
//     x0 / zero  -- hardwired 0; writes discarded
//     ra         -- return address (jal/jalr link)
//     sp         -- stack pointer
//     gp / tp    -- global / thread pointer (platform-dependent use)
//     t0..t6     -- temporaries (caller-saved)
//     s0..s11    -- saved (callee-saved); s0 is also fp
//     a0..a7     -- argument / return registers
//
//   HolyC (and the host compiler) follow the standard RISC-V psABI:
//   first integer args in a0..a7, return value in a0 (and a1 for wide
//   pairs when used). Callees must preserve s* across calls; callers must
//   assume t* and a* are clobbered.
//
//   On this REPL, Reg("a0"); Regs; RegHelp; Man("Regs"); are the dig-down
//   tools. After unlabeled asm{}, inspect the registers you touched.
//
// NEXT
//   A03_LoadStore -- putting values in memory (endian, MEM_*).
U0 A02_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

U0 A02_Demo()
{
  Print("A02 demo: ABI temps a0/a1; add leaves sum in a0\n");
  asm {
	li a0, 1
	li a1, 2
	add a0, a0, a1
  }
  ;
  Reg("a0");
  Reg("a1");
  Print("Full dump:\n");
  Regs;
  A02_Expect("A02_Demo_math", 1 + 2, 3);
}
// Ex1 Warmup: which arg register holds the first integer argument?
// Return the ABI index 0 for a0 (not the x-reg number).
I64 A02_Ex1_FirstArgIdx()
{
  // TODO Fill_in: return 0;  // a0
  return -1;
}
// Ex2: sum two args -- models add a0,a0,a1 after li pairs.
I64 A02_Ex2_Sum(I64 a, I64 b)
{
  // TODO Fill_in: return a + b;
  return 0;
}
// Ex3: return register holds the function result -- echo the input via
// "a0 in, a0 out" mental model.
I64 A02_Ex3_Ret(I64 x)
{
  // TODO Fill_in: return x;
  return 0;
}
// Ex4: caller-saved vs callee-saved.
// Return 1 if name is caller-saved temp (t0 style), 0 if callee-saved (s0),
// -1 unknown. We pass a code: 1=t0, 2=s0, 3=a0 (a0 is caller-saved arg).
I64 A02_Ex4_SaveClass(I64 code)
{
  // TODO Fill_in:
  //   if (code == 1) return 1;  // t0 caller-saved
  //   if (code == 2) return 0;  // s0 callee-saved
  //   if (code == 3) return 1;  // a0 caller-saved
  //   return -1;
  return -2;
}
// Ex5: x0 is always zero -- "add a0, zero, a1" copies a1.
I64 A02_Ex5_FromZero(I64 a1)
{
  // TODO Fill_in: return 0 + a1;
  return -1;
}
// Ex6: 8 integer arg regs a0..a7 -- return how many.
I64 A02_Ex6_NumArgRegs()
{
  // TODO Fill_in: return 8;
  return 0;
}
// Ex7 Challenge: simulate spilling a callee-saved reg.
// "Save" s1=old into mem slot, clobber s1=tmp, restore -- return restored.
I64 A02_Ex7_Spill(I64 old, I64 tmp)
{
  I64 slot;
  // TODO Fill_in:
  //   slot = old;   // sd s1, slot
  //   old = tmp;    // clobber
  //   old = slot;   // ld restore
  //   return old;
  return tmp;
}

U0 A02_Check()
{
  Print("-- A02 exercises --\n");
  A02_Expect("Ex1_FirstArgIdx", A02_Ex1_FirstArgIdx(), 0);
  A02_Expect("Ex2_Sum", A02_Ex2_Sum(10, 20), 30);
  A02_Expect("Ex3_Ret", A02_Ex3_Ret(77), 77);
  A02_Expect("Ex4_t0", A02_Ex4_SaveClass(1), 1);
  A02_Expect("Ex4_s0", A02_Ex4_SaveClass(2), 0);
  A02_Expect("Ex4_a0", A02_Ex4_SaveClass(3), 1);
  A02_Expect("Ex5_FromZero", A02_Ex5_FromZero(55), 55);
  A02_Expect("Ex6_NumArgRegs", A02_Ex6_NumArgRegs(), 8);
  A02_Expect("Ex7_Spill", A02_Ex7_Spill(0xABC, 0x111), 0xABC);
}

U0 A02()
{
  Print("=== A02 Registers & ABI ===\n");
  Print("Man(\"Regs\"); RegHelp; after asm. Args a0-a7, return a0, save s*.\n");
  A02_Demo();
  A02_Check();
  Print("Next: Run(\"A03_LoadStore.hc\");\n");
}
A02;
