// asm_complete.hc -- RISC-V asm{} Tab completion tables + context helpers.
// Sources: host TryAssembleRiscV (parser.c) + guest Compiler/Asm_RV.HC mnemonics;
// GPR/ABI from RvRegNum / AsmRVRegsAdd; CSR names from csr.hc Reg().
// Tables are '|' -separated (not NUL) so seed memfs embedding stays intact.
// Loaded before complete.hc. Keep in sync with worry_dream_repl.c rl_asm_*.
#define ASM_COMP_OP 0
#define ASM_COMP_REG 1
#define ASM_COMP_CSR 2
#define ASM_COMP_NONE 3
I64 CompAsmSt;
I64 CompAsmDepth;
// 0=auto (default BSS), 1=force inside asm{}, 2=force outside
I64 CompAsmMode;
U8 *AsmCompOps = "add|addi|and|andi|or|ori|xor|xori|" "sub|sll|slli|srl|srli|sra|srai|slt|slti|sltu|" "mul|div|divu|rem|remu|" "lui|auipc|li|mv|not|neg|seqz|snez|jr|" "ld|lw|lwu|lh|lhu|lb|lbu|sd|sw|sh|sb|" "jalr|j|call|beq|bne|blt|bge|bltu|bgeu|beqz|bnez|" "ret|nop|wfi|mret|sret|ecall|ebreak|fencei|fence.i|" "csrr|csrw|csrs|csrc|csrrw|csrrs|csrrc|" "csrrwi|csrrsi|csrrci|csrwi|csrsi|csrci|" "rdtime|sfencevma|lifp|" "lr.d|lr.w|lrd|lrw|sc.d|sc.w|scd|scw|" "amoswap.d|amoadd.d|amoxor.d|amoand.d|amoor.d|" "amomin.d|amomax.d|amominu.d|amomaxu.d|" "amoswap.w|amoadd.w|amoxor.w|amoand.w|amoor.w|" "amomin.w|amomax.w|amominu.w|amomaxu.w|" "amoswapd|amoaddd|amoxord|amoandd|amoord|" "amomind|amomaxd|amominud|amomaxud|" "amoswapw|amoaddw|amoxorw|amoandw|amoorw|" "amominw|amomaxw|amominuw|amomaxuw|" "fsqrtd|faddd|fsubd|fmuld|fdivd|fled|fltd|feqd|" "fmvdx|fmvxd|fcvtdl|fcvtld_rtz|fcvtld_rdn|fcvtld_rmm|";
U8 *AsmCompRegs = "zero|ra|sp|gp|tp|fp|" "t0|t1|t2|t3|t4|t5|t6|" "s0|s1|s2|s3|s4|s5|s6|s7|s8|s9|s10|s11|" "a0|a1|a2|a3|a4|a5|a6|a7|" "x0|x1|x2|x3|x4|x5|x6|x7|x8|x9|" "x10|x11|x12|x13|x14|x15|x16|x17|" "x18|x19|x20|x21|x22|x23|x24|x25|" "x26|x27|x28|x29|x30|x31|" "ft0|ft1|ft2|ft3|ft4|ft5|ft6|ft7|ft8|ft9|ft10|ft11|" "fs0|fs1|fs2|fs3|fs4|fs5|fs6|fs7|fs8|fs9|fs10|fs11|" "fa0|fa1|fa2|fa3|fa4|fa5|fa6|fa7|" "f0|f1|f2|f3|f4|f5|f6|f7|f8|f9|" "f10|f11|f12|f13|f14|f15|f16|f17|" "f18|f19|f20|f21|f22|f23|f24|f25|" "f26|f27|f28|f29|f30|f31|";
U8 *AsmCompCsrs = "mstatus|misa|medeleg|mideleg|mie|mtvec|mcounteren|" "mscratch|mepc|mcause|mtval|mip|" "mcycle|minstret|cycle|time|instret|mhartid|" "sstatus|sie|stvec|sscratch|sepc|scause|stval|sip|satp|";
U0 CompAsmReset()
{
  CompAsmSt = 0;
  CompAsmDepth = 0;
}

I64 CompAsmInside()
{
  if (CompAsmMode == 1)
    return 1;
  if (CompAsmMode == 2)
    return 0;
  return CompAsmSt == 2 && CompAsmDepth > 0;
}

I64 CompAsmChEq(I64 a, I64 b)
{
  if (a >= 'A' && a <= 'Z')
    a += 32;
  if (b >= 'A' && b <= 'Z')
    b += 32;
  return a == b;
}

I64 CompAsmIsWord(I64 c)
{
  if (c >= 'a' && c <= 'z')
    return 1;
  if (c >= 'A' && c <= 'Z')
    return 1;
  if (c >= '0' && c <= '9')
    return 1;
  if (c == '_')
    return 1;
  return 0;
}

U0 CompAsmFeed(U8 *s, I64 n)
{
  I64 i, c, q;
  if (!s || n <= 0)
    return;
  i = 0;
  while (i < n) {
    c = s[i];
    if (c == '"' || c == '\'') {
      q = c;
      i++;
      while (i < n && s[i] != q) {
        if (s[i] == '\\' && i + 1 < n)
          i++;
        i++;
      }
      if (i < n)
        i++;
      if (CompAsmSt == 1)
        CompAsmSt = 0;
      continue;
    }
    if (CompAsmSt == 0 && CompAsmIsWord(c) && (i == 0 || !CompAsmIsWord(s[i - 1]))) {
      if ((c == 'a' || c == 'A') && i + 2 < n) {
        if (CompAsmChEq(s[i + 1], 's') && CompAsmChEq(s[i + 2], 'm') && (i + 3 >= n || !CompAsmIsWord(s[i + 3]))) {
          CompAsmSt = 1;
          i += 3;
          continue;
        }
      }
    }
    if (CompAsmSt == 1) {
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        i++;
        continue;
      }
      if (c == '{') {
        CompAsmSt = 2;
        CompAsmDepth = 1;
        i++;
        continue;
      }
      CompAsmSt = 0;
    }
    if (CompAsmSt == 2) {
      if (c == '{')
        CompAsmDepth++;
      else if (c == '}') {
        if (CompAsmDepth > 0)
          CompAsmDepth--;
        if (CompAsmDepth == 0)
          CompAsmSt = 0;
      }
    }
    i++;
  }
}

I64 CompAsmDetectLine(U8 *line, I64 cx)
{
  CompAsmMode = 0;
  CompAsmReset();
  if (!line || cx < 0)
    return 0;
  CompAsmFeed(line, cx);
  return CompAsmInside();
}

I64 CompAsmStrEqI(U8 *a, U8 *b)
{
  I64 i = 0;
  if (!a || !b)
    return 0;
  while (a[i] || b[i]) {
    if (!CompAsmChEq(a[i], b[i]))
      return 0;
    i++;
  }
  return 1;
}

I64 CompAsmIsCsrOp(U8 *mn)
{
  if (CompAsmStrEqI(mn, "csrr") || CompAsmStrEqI(mn, "csrw") || CompAsmStrEqI(mn, "csrs") || CompAsmStrEqI(mn, "csrc") || CompAsmStrEqI(mn, "csrrw") || CompAsmStrEqI(mn, "csrrs") || CompAsmStrEqI(mn, "csrrc") || CompAsmStrEqI(mn, "csrrwi") || CompAsmStrEqI(mn, "csrrsi") || CompAsmStrEqI(mn, "csrrci") || CompAsmStrEqI(mn, "csrwi") || CompAsmStrEqI(mn, "csrsi") || CompAsmStrEqI(mn, "csrci"))
    return 1;
  return 0;
}

I64 CompAsmCsrOpnd(U8 *mn)
{
  if (CompAsmStrEqI(mn, "csrw") || CompAsmStrEqI(mn, "csrs") || CompAsmStrEqI(mn, "csrc") || CompAsmStrEqI(mn, "csrwi") || CompAsmStrEqI(mn, "csrsi") || CompAsmStrEqI(mn, "csrci"))
    return 0;
  if (CompAsmStrEqI(mn, "csrr") || CompAsmStrEqI(mn, "csrrw") || CompAsmStrEqI(mn, "csrrs") || CompAsmStrEqI(mn, "csrrc") || CompAsmStrEqI(mn, "csrrwi") || CompAsmStrEqI(mn, "csrrsi") || CompAsmStrEqI(mn, "csrrci"))
    return 1;
  return -1;
}

I64 CompAsmImmOpnd(U8 *mn)
{
  if (CompAsmStrEqI(mn, "li") || CompAsmStrEqI(mn, "lui") || CompAsmStrEqI(mn, "auipc") || CompAsmStrEqI(mn, "lifp"))
    return 1;
  if (CompAsmStrEqI(mn, "addi") || CompAsmStrEqI(mn, "andi") || CompAsmStrEqI(mn, "ori") || CompAsmStrEqI(mn, "xori") || CompAsmStrEqI(mn, "slti") || CompAsmStrEqI(mn, "slli") || CompAsmStrEqI(mn, "srli") || CompAsmStrEqI(mn, "srai"))
    return 2;
  if (CompAsmStrEqI(mn, "csrrwi") || CompAsmStrEqI(mn, "csrrsi") || CompAsmStrEqI(mn, "csrrci"))
    return 2;
  if (CompAsmStrEqI(mn, "csrwi") || CompAsmStrEqI(mn, "csrsi") || CompAsmStrEqI(mn, "csrci"))
    return 1;
  return -1;
}

I64 CompAsmBranchOpnd(U8 *mn)
{
  if (CompAsmStrEqI(mn, "j") || CompAsmStrEqI(mn, "call"))
    return 0;
  if (CompAsmStrEqI(mn, "beqz") || CompAsmStrEqI(mn, "bnez"))
    return 1;
  if (CompAsmStrEqI(mn, "beq") || CompAsmStrEqI(mn, "bne") || CompAsmStrEqI(mn, "blt") || CompAsmStrEqI(mn, "bge") || CompAsmStrEqI(mn, "bltu") || CompAsmStrEqI(mn, "bgeu"))
    return 2;
  return -1;
}

I64 CompAsmTokChar(I64 c)
{
  if (CompAsmIsWord(c))
    return 1;
  if (c == '.' || c == '-' || c == '+')
    return 1;
  return 0;
}

I64 CompAsmKind(U8 *line, I64 cx)
{
  I64 i, j, start, t0, commas, opnd, csr_i, imm_i, br_i;
  U8 mn[48];
  if (!line || cx < 0)
    return ASM_COMP_OP;
  i = cx;
  while (i > 0 && CompAsmTokChar(line[i - 1]))
    i--;
  start = i;
  while (start > 0) {
    if (line[start - 1] == '{' || line[start - 1] == ';' || line[start - 1] == '\n')
      break;
    start--;
  }
  while (start < i && (line[start] == ' ' || line[start] == '\t'))
    start++;
  t0 = start;
  while (t0 < i && CompAsmTokChar(line[t0]))
    t0++;
  if (t0 == i)
    return ASM_COMP_OP;
  j = 0;
  while (start + j < t0 && j < 47) {
    mn[j] = line[start + j];
    j++;
  }
  mn[j] = 0;
  commas = 0;
  while (t0 < i) {
    if (line[t0] == ',')
      commas++;
    t0++;
  }
  opnd = commas;
  csr_i = CompAsmCsrOpnd(mn);
  if (csr_i >= 0 && opnd == csr_i)
    return ASM_COMP_CSR;
  imm_i = CompAsmImmOpnd(mn);
  if (imm_i >= 0 && opnd == imm_i)
    return ASM_COMP_NONE;
  br_i = CompAsmBranchOpnd(mn);
  if (br_i >= 0 && opnd >= br_i)
    return ASM_COMP_NONE;
  return ASM_COMP_REG;
}
