// B04_Processor.hc -- CSAPP 3e Ch.4: Processor Architecture
// Remap: Y86-64 PIPE labs -> RV64I encoding + hazard intuition on real bits.
// GAP: no Y86 simulator in-tree -- study encodings + Disasm instead.
//
// HOW TO WORK THIS LAB
//   Run("B04_Processor.hc");  edit Fill_in;  Run again.
//
// BOOK THEMES
//   CSAPP builds a pipelined CPU. We extract transferable ideas: instruction
//   formats (R/I/S/B/U/J), datapath stages (IF/ID/EX/MEM/WB), and why
//   dependencies force stalls/forwards. Your CPU/emulator still executes
//   the same RV64I words Uf shows.
//
// NEXT
//   B05_Optimize -- performance at the HolyC/RV level.
U0 B04_Expect(U8 *name, I64 got, I64 want)
{
  if (got == want)
    Print("PASS %s\n", name);
  else
    Print("FAIL %s got=%X want=%X\n", name, got, want);
}

I64 B04_NopLike(I64 x)
{
  return x + 0;
}

U0 B04_Demo()
{
  Print("B04: RV64I fixed 32-bit patterns; Uf shows real words\n");
  Uf("B04_NopLike");
  Print("Formats: R(add) I(addi) S(sd) B(beq) U(lui) J(jal)\n");
  Print("GAP: no Y86 PIPE -- encodings are the lab.\n");
  B04_Expect("B04_NopLike", B04_NopLike(41), 41);
}
// Ex1 Warmup: opcode field is low 7 bits.
I64 B04_Ex1_Opcode(I64 word)
{
  // TODO Fill_in: return word & 0x7F;
  return -1;
}
// Ex2: rd field bits [11:7].
I64 B04_Ex2_Rd(I64 word)
{
  // TODO Fill_in: return (word >> 7) & 0x1F;
  return 0;
}
// Ex3: funct3 bits [14:12].
I64 B04_Ex3_Funct3(I64 word)
{
  // TODO Fill_in: return (word >> 12) & 7;
  return -1;
}
// Ex4: rs1 bits [19:15].
I64 B04_Ex4_Rs1(I64 word)
{
  // TODO Fill_in: return (word >> 15) & 0x1F;
  return 0;
}
// Ex5: rs2 bits [24:20].
I64 B04_Ex5_Rs2(I64 word)
{
  // TODO Fill_in: return (word >> 20) & 0x1F;
  return 0;
}
// Ex6: how many bytes is a standard (non-C) instruction?
I64 B04_Ex6_InstBytes()
{
  // TODO Fill_in: return 4;
  return 0;
}
// Ex7 Challenge: addi opcode is 0x13. Return 1 if (word&0x7F)==0x13.
I64 B04_Ex7_IsAddi(I64 word)
{
  // TODO Fill_in: if ((word & 0x7F) == 0x13) return 1; return -1;
  return 0;
}
// Ex8 Challenge: pipeline stages taught here -- return 5 (IF ID EX MEM WB).
I64 B04_Ex8_Stages()
{
  // TODO Fill_in: return 5;
  return 0;
}

U0 B04_Check()
{
  I64 add_x0;
  // synthetic: opcode 0x33, rd=1, funct3=0, rs1=2, rs2=3
  // word = opcode | rd<<7 | funct3<<12 | rs1<<15 | rs2<<20 | funct7<<25
  add_x0 = 0x33 | (1 << 7) | (0 << 12) | (2 << 15) | (3 << 20);
  Print("-- B04 exercises --\n");
  B04_Expect("Ex1_Opcode", B04_Ex1_Opcode(add_x0), 0x33);
  B04_Expect("Ex2_Rd", B04_Ex2_Rd(add_x0), 1);
  B04_Expect("Ex3_Funct3", B04_Ex3_Funct3(add_x0), 0);
  B04_Expect("Ex4_Rs1", B04_Ex4_Rs1(add_x0), 2);
  B04_Expect("Ex5_Rs2", B04_Ex5_Rs2(add_x0), 3);
  B04_Expect("Ex6_InstBytes", B04_Ex6_InstBytes(), 4);
  B04_Expect("Ex7_IsAddi_yes", B04_Ex7_IsAddi(0x13), 1);
  B04_Expect("Ex7_IsAddi_no", B04_Ex7_IsAddi(0x33), 0);
  B04_Expect("Ex8_Stages", B04_Ex8_Stages(), 5);
}

U0 B04()
{
  Print("=== B04 CSAPP Ch.4 Processor architecture ===\n");
  B04_Demo();
  B04_Check();
  Print("Next: Run(\"B05_Optimize.hc\");\n");
}
B04;
