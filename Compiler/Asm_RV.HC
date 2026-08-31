// Asm_RV.HC — RISC-V asm{} for Compiler_RV (ExePutS / COCCompile).
// Unlabeled `asm { addi s2,s2,3 }` → AOTStoreCodeU32 (or LexExcept).
I64 g_rv_asm_exports;
Bool RvAsmStrEqI(U8 *a, U8 *b)
{
  U8 ca, cb;
  if (!a || !b)
    return FALSE;
  while (*a || *b) {
    ca = *a++;
    cb = *b++;
    if ('A' <= ca <= 'Z')
      ca += 32;
    if ('A' <= cb <= 'Z')
      cb += 32;
    if (ca != cb)
      return FALSE;
  }
  return TRUE;
}

Bool RvAsmIsMn(U8 *s)
{
  if (!s)
    return FALSE;
  if (RvAsmStrEqI(s, "ret") || RvAsmStrEqI(s, "nop") || RvAsmStrEqI(s, "wfi") || RvAsmStrEqI(s, "mret") || RvAsmStrEqI(s, "sret") || RvAsmStrEqI(s, "ecall") || RvAsmStrEqI(s, "ebreak") || RvAsmStrEqI(s, "fencei") || RvAsmStrEqI(s, "fence.i") || RvAsmStrEqI(s, "mv") || RvAsmStrEqI(s, "not") || RvAsmStrEqI(s, "neg") || RvAsmStrEqI(s, "li") || RvAsmStrEqI(s, "addi") || RvAsmStrEqI(s, "andi") || RvAsmStrEqI(s, "ori") || RvAsmStrEqI(s, "xori") || RvAsmStrEqI(s, "slti") || RvAsmStrEqI(s, "slli") || RvAsmStrEqI(s, "srli") || RvAsmStrEqI(s, "srai") || RvAsmStrEqI(s, "add") || RvAsmStrEqI(s, "sub") || RvAsmStrEqI(s, "and") || RvAsmStrEqI(s, "or") || RvAsmStrEqI(s, "xor") || RvAsmStrEqI(s, "sll") || RvAsmStrEqI(s, "srl") || RvAsmStrEqI(s, "sra") || RvAsmStrEqI(s, "slt") || RvAsmStrEqI(s, "sltu") || RvAsmStrEqI(s, "mul") || RvAsmStrEqI(s, "div") || RvAsmStrEqI(s, "rem") || RvAsmStrEqI(s, "divu") || RvAsmStrEqI(s, "remu") || RvAsmStrEqI(s, "ld") || RvAsmStrEqI(s, "lw") || RvAsmStrEqI(s, "sd") || RvAsmStrEqI(s, "sw") || RvAsmStrEqI(s, "jalr") || RvAsmStrEqI(s, "csrr") || RvAsmStrEqI(s, "csrw") || RvAsmStrEqI(s, "csrs") || RvAsmStrEqI(s, "csrrw") || RvAsmStrEqI(s, "csrrs") || RvAsmStrEqI(s, "csrrc"))
    return TRUE;
  // subi is not a standard gas mnemonic — reject with a clear LexExcept in PrsAsmRVIns.
  if (RvAsmStrEqI(s, "subi"))
    return TRUE;
  return FALSE;
}

I64 RvAsmRegNum(U8 *n)
{
  I64 k;
  if (!n)
    return -1;
  if (RvAsmStrEqI(n, "zero") || RvAsmStrEqI(n, "x0"))
    return 0;
  if (RvAsmStrEqI(n, "ra"))
    return 1;
  if (RvAsmStrEqI(n, "sp"))
    return 2;
  if (RvAsmStrEqI(n, "gp"))
    return 3;
  if (RvAsmStrEqI(n, "tp"))
    return 4;
  if (RvAsmStrEqI(n, "fp") || RvAsmStrEqI(n, "s0"))
    return 8;
  if (RvAsmStrEqI(n, "s1"))
    return 9;
  if ((n[0] == 't' || n[0] == 'T') && n[1]) {
    k = Str2I64(n + 1);
    if (0 <= k <= 2)
      return 5 + k;
    if (3 <= k <= 6)
      return 28 + (k - 3);
  }
  if ((n[0] == 'a' || n[0] == 'A') && n[1]) {
    k = Str2I64(n + 1);
    if (0 <= k <= 7)
      return 10 + k;
  }
  if ((n[0] == 's' || n[0] == 'S') && n[1]) {
    k = Str2I64(n + 1);
    if (2 <= k <= 11)
      return 16 + k;
  }
  if ((n[0] == 'x' || n[0] == 'X') && n[1]) {
    k = Str2I64(n + 1);
    if (0 <= k <= 31)
      return k;
  }
  return -1;
}

U0 AsmRVRegsAdd()
{
  U8 *p, *names;
  CHashReg *tmpr;
  I64 i, nums[33];
  names = "zero\0ra\0sp\0gp\0tp\0t0\0t1\0t2\0s0\0fp\0s1\0" "a0\0a1\0a2\0a3\0a4\0a5\0a6\0a7\0" "s2\0s3\0s4\0s5\0s6\0s7\0s8\0s9\0s10\0s11\0" "t3\0t4\0t5\0t6\0";
  nums[0] = 0;
  nums[1] = 1;
  nums[2] = 2;
  nums[3] = 3;
  nums[4] = 4;
  nums[5] = 5;
  nums[6] = 6;
  nums[7] = 7;
  nums[8] = 8;
  nums[9] = 8;
  nums[10] = 9;
  nums[11] = 10;
  nums[12] = 11;
  nums[13] = 12;
  nums[14] = 13;
  nums[15] = 14;
  nums[16] = 15;
  nums[17] = 16;
  nums[18] = 17;
  nums[19] = 18;
  nums[20] = 19;
  nums[21] = 20;
  nums[22] = 21;
  nums[23] = 22;
  nums[24] = 23;
  nums[25] = 24;
  nums[26] = 25;
  nums[27] = 26;
  nums[28] = 27;
  nums[29] = 28;
  nums[30] = 29;
  nums[31] = 30;
  nums[32] = 31;
  if (!cmp.asm_hash)
    return;
  p = names;
  i = 0;
  while (*p) {
    if (!HashFind(p, cmp.asm_hash, HTT_REG, 1)) {
      tmpr = CAlloc(sizeof(CHashReg));
      tmpr->str = AStrNew(p);
      tmpr->type = HTT_REG;
      tmpr->reg_type = REGT_R64;
      tmpr->reg_num = nums[i];
      HashAdd(tmpr, cmp.asm_hash);
    }
    while (*p++)
      ;
    i++;
  }
}

I64 RvAsmRegTok(CCmpCtrl *cc)
{
  I64 r;
  if (cc->token != TK_IDENT)
    return -1;
  r = RvAsmRegNum(cc->cur_str);
  Lex(cc);
  return r;
}

Bool RvAsmImmTok(CCmpCtrl *cc, I64 *out)
{
  I64 neg = 0, v;
  if (cc->token == '-') {
    neg = 1;
    Lex(cc);
  }
  if (cc->token != TK_I64)
    return FALSE;
  v = cc->cur_i64;
  if (neg)
    v = -v;
  *out = v;
  Lex(cc);
  return TRUE;
}

U32 RvAsmI(U32 f3, I64 rd, I64 rs1, I64 imm)
{
  return 0x13 | (rd << 7) | (f3 << 12) | (rs1 << 15) | ((imm & 0xFFF) << 20);
}

U32 RvAsmR(U32 f7, U32 f3, I64 rd, I64 rs1, I64 rs2)
{
  return 0x33 | (rd << 7) | (f3 << 12) | (rs1 << 15) | (rs2 << 20) | (f7 << 25);
}

U32 RvAsmLoad(U32 f3, I64 rd, I64 imm, I64 rs1)
{
  return 0x03 | (rd << 7) | (f3 << 12) | (rs1 << 15) | ((imm & 0xFFF) << 20);
}

U32 RvAsmStore(U32 f3, I64 rs2, I64 imm, I64 rs1)
{
  return 0x23 | ((imm & 0x1F) << 7) | (f3 << 12) | (rs1 << 15) | (rs2 << 20) | (((imm >> 5) & 0x7F) << 25);
}

U32 RvAsmJalr(I64 rd, I64 rs1, I64 imm)
{
  return 0x67 | (rd << 7) | (rs1 << 15) | ((imm & 0xFFF) << 20);
}

Bool PrsAsmRVIns(CCmpCtrl *cc)
{
  // TRUE if a known RV mnemonic was assembled. FALSE → caller may treat as label.
  I64 rd, rs1, rs2, imm, first, is_imm;
  U32 word;
  U8 *mn;
  if (cc->token != TK_IDENT || !cc->cur_str)
    return FALSE;
  if (!RvAsmIsMn(cc->cur_str))
    return FALSE;
  mn = StrNew(cc->cur_str);
  Lex(cc);
  // skip mnemonic
  if (RvAsmStrEqI(mn, "ret")) {
    Free(mn);
    AOTStoreCodeU32(cc, RvAsmJalr(0, 1, 0));
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "nop")) {
    Free(mn);
    AOTStoreCodeU32(cc, RvAsmI(0, 0, 0, 0));
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "wfi")) {
    Free(mn);
    AOTStoreCodeU32(cc, 0x10500073);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "fencei") || RvAsmStrEqI(mn, "fence.i")) {
    Free(mn);
    AOTStoreCodeU32(cc, 0x0000100F);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "mret")) {
    Free(mn);
    AOTStoreCodeU32(cc, 0x30200073);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "sret")) {
    Free(mn);
    AOTStoreCodeU32(cc, 0x10200073);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "ecall")) {
    Free(mn);
    AOTStoreCodeU32(cc, 0x00000073);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "ebreak")) {
    Free(mn);
    AOTStoreCodeU32(cc, 0x00100073);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "subi")) {
    Free(mn);
    LexExcept(cc, "no subi; use addi rd,rs1,-imm (or sub rd,rs1,rs2) at ");
  }
  if (RvAsmStrEqI(mn, "csrr")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    if (!RvAsmImmTok(cc, &imm)) {
      Free(mn);
      LexExcept(cc, "Expecting csr imm at ");
    }
    if (rd < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    Free(mn);
    AOTStoreCodeU32(cc, 0x00002073 | (rd << 7) | ((imm & 0xFFF) << 20));
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "csrw")) {
    if (!RvAsmImmTok(cc, &imm)) {
      Free(mn);
      LexExcept(cc, "Expecting csr imm at ");
    }
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (rs1 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    Free(mn);
    AOTStoreCodeU32(cc, 0x00001073 | (rs1 << 15) | ((imm & 0xFFF) << 20));
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "csrs")) {
    if (!RvAsmImmTok(cc, &imm)) {
      Free(mn);
      LexExcept(cc, "Expecting csr imm at ");
    }
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (rs1 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    Free(mn);
    AOTStoreCodeU32(cc, 0x00002073 | (rs1 << 15) | ((imm & 0xFFF) << 20));
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "csrrw") || RvAsmStrEqI(mn, "csrrs") || RvAsmStrEqI(mn, "csrrc")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    if (!RvAsmImmTok(cc, &imm)) {
      Free(mn);
      LexExcept(cc, "Expecting csr imm at ");
    }
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (rd < 0 || rs1 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (RvAsmStrEqI(mn, "csrrw"))
      word = 0x00001073 | (rd << 7) | (rs1 << 15) | ((imm & 0xFFF) << 20);
    else if (RvAsmStrEqI(mn, "csrrs"))
      word = 0x00002073 | (rd << 7) | (rs1 << 15) | ((imm & 0xFFF) << 20);
    else
      word = 0x00003073 | (rd << 7) | (rs1 << 15) | ((imm & 0xFFF) << 20);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "mv") || RvAsmStrEqI(mn, "not") || RvAsmStrEqI(mn, "neg")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (rd < 0 || rs1 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (RvAsmStrEqI(mn, "mv"))
      word = RvAsmI(0, rd, rs1, 0);
    else if (RvAsmStrEqI(mn, "not"))
      word = RvAsmI(4, rd, rs1, -1);
    else
      word = RvAsmR(0x20, 0, rd, 0, rs1);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "li")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    if (!RvAsmImmTok(cc, &imm)) {
      Free(mn);
      LexExcept(cc, "Expecting imm at ");
    }
    if (rd < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    Free(mn);
    AOTStoreCodeU32(cc, RvAsmI(0, rd, 0, imm));
    return TRUE;
  }
  is_imm = RvAsmStrEqI(mn, "addi") || RvAsmStrEqI(mn, "andi") || RvAsmStrEqI(mn, "ori") || RvAsmStrEqI(mn, "xori") || RvAsmStrEqI(mn, "slti") || RvAsmStrEqI(mn, "slli") || RvAsmStrEqI(mn, "srli") || RvAsmStrEqI(mn, "srai");
  if (is_imm) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    if (!RvAsmImmTok(cc, &imm)) {
      Free(mn);
      LexExcept(cc, "Expecting imm at ");
    }
    if (rd < 0 || rs1 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (RvAsmStrEqI(mn, "addi"))
      word = RvAsmI(0, rd, rs1, imm);
    else if (RvAsmStrEqI(mn, "andi"))
      word = RvAsmI(7, rd, rs1, imm);
    else if (RvAsmStrEqI(mn, "ori"))
      word = RvAsmI(6, rd, rs1, imm);
    else if (RvAsmStrEqI(mn, "xori"))
      word = RvAsmI(4, rd, rs1, imm);
    else if (RvAsmStrEqI(mn, "slti"))
      word = RvAsmI(2, rd, rs1, imm);
    else if (RvAsmStrEqI(mn, "slli"))
      word = 0x13 | (rd << 7) | (1 << 12) | (rs1 << 15) | ((imm & 0x3F) << 20);
    else if (RvAsmStrEqI(mn, "srli"))
      word = 0x13 | (rd << 7) | (5 << 12) | (rs1 << 15) | ((imm & 0x3F) << 20);
    else
      word = 0x13 | (rd << 7) | (5 << 12) | (rs1 << 15) | ((imm & 0x3F) << 20) | (0x20 << 25);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "add") || RvAsmStrEqI(mn, "sub") || RvAsmStrEqI(mn, "and") || RvAsmStrEqI(mn, "or") || RvAsmStrEqI(mn, "xor") || RvAsmStrEqI(mn, "sll") || RvAsmStrEqI(mn, "srl") || RvAsmStrEqI(mn, "sra") || RvAsmStrEqI(mn, "slt") || RvAsmStrEqI(mn, "sltu") || RvAsmStrEqI(mn, "mul") || RvAsmStrEqI(mn, "div") || RvAsmStrEqI(mn, "rem") || RvAsmStrEqI(mn, "divu") || RvAsmStrEqI(mn, "remu")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    if (cc->token == TK_I64 || cc->token == '-') {
      if (RvAsmStrEqI(mn, "sub")) {
        Free(mn);
        LexExcept(cc, "sub is R-type (rd,rs1,rs2); use addi rd,rs1,-imm at ");
      }
      if (RvAsmStrEqI(mn, "add")) {
        Free(mn);
        LexExcept(cc, "add is R-type (rd,rs1,rs2); use addi rd,rs1,imm at ");
      }
      Free(mn);
      LexExcept(cc, "R-type op needs register rs2, not immediate at ");
    }
    rs2 = RvAsmRegTok(cc);
    if (rd < 0 || rs1 < 0 || rs2 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (RvAsmStrEqI(mn, "add"))
      word = RvAsmR(0, 0, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "sub"))
      word = RvAsmR(0x20, 0, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "and"))
      word = RvAsmR(0, 7, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "or"))
      word = RvAsmR(0, 6, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "xor"))
      word = RvAsmR(0, 4, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "sll"))
      word = RvAsmR(0, 1, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "srl"))
      word = RvAsmR(0, 5, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "sra"))
      word = RvAsmR(0x20, 5, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "slt"))
      word = RvAsmR(0, 2, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "sltu"))
      word = RvAsmR(0, 3, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "mul"))
      word = RvAsmR(1, 0, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "div"))
      word = RvAsmR(1, 4, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "rem"))
      word = RvAsmR(1, 6, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "divu"))
      word = RvAsmR(1, 5, rd, rs1, rs2);
    else
      word = RvAsmR(1, 7, rd, rs1, rs2);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "ld") || RvAsmStrEqI(mn, "lw") || RvAsmStrEqI(mn, "sd") || RvAsmStrEqI(mn, "sw")) {
    first = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    imm = 0;
    if (!RvAsmImmTok(cc, &imm) && cc->token != '(') {
      Free(mn);
      LexExcept(cc, "Expecting imm(reg) at ");
    }
    if (cc->token != '(') {
      Free(mn);
      LexExcept(cc, "Expecting '(' at ");
    }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (cc->token != ')') {
      Free(mn);
      LexExcept(cc, "Expecting ')' at ");
    }
    Lex(cc);
    if (first < 0 || rs1 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (RvAsmStrEqI(mn, "ld"))
      word = RvAsmLoad(3, first, imm, rs1);
    else if (RvAsmStrEqI(mn, "lw"))
      word = RvAsmLoad(2, first, imm, rs1);
    else if (RvAsmStrEqI(mn, "sd"))
      word = RvAsmStore(3, first, imm, rs1);
    else
      word = RvAsmStore(2, first, imm, rs1);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "jalr")) {
    rd = RvAsmRegTok(cc);
    if (cc->token == ',') {
      Lex(cc);
      imm = 0;
      if (!RvAsmImmTok(cc, &imm))
        imm = 0;
      if (cc->token != '(') {
        Free(mn);
        LexExcept(cc, "Expecting '(' at ");
      }
      Lex(cc);
      rs1 = RvAsmRegTok(cc);
      if (cc->token != ')') {
        Free(mn);
        LexExcept(cc, "Expecting ')' at ");
      }
      Lex(cc);
    } else {
      rs1 = rd;
      rd = 1;
      imm = 0;
    }
    if (rs1 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    Free(mn);
    AOTStoreCodeU32(cc, RvAsmJalr(rd, rs1, imm));
    return TRUE;
  }
  Free(mn);
  LexExcept(cc, "Unsupported RISC-V asm mnemonic at ");
  return FALSE;
}
