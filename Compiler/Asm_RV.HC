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
  if (RvAsmStrEqI(s, "ret") || RvAsmStrEqI(s, "nop") || RvAsmStrEqI(s, "wfi") || RvAsmStrEqI(s, "mret") || RvAsmStrEqI(s, "sret") || RvAsmStrEqI(s, "ecall") || RvAsmStrEqI(s, "ebreak") || RvAsmStrEqI(s, "fencei") || RvAsmStrEqI(s, "fence.i") || RvAsmStrEqI(s, "mv") || RvAsmStrEqI(s, "not") || RvAsmStrEqI(s, "neg") || RvAsmStrEqI(s, "li") || RvAsmStrEqI(s, "lui") || RvAsmStrEqI(s, "auipc") || RvAsmStrEqI(s, "addi") || RvAsmStrEqI(s, "andi") || RvAsmStrEqI(s, "ori") || RvAsmStrEqI(s, "xori") || RvAsmStrEqI(s, "slti") || RvAsmStrEqI(s, "slli") || RvAsmStrEqI(s, "srli") || RvAsmStrEqI(s, "srai") || RvAsmStrEqI(s, "add") || RvAsmStrEqI(s, "sub") || RvAsmStrEqI(s, "and") || RvAsmStrEqI(s, "or") || RvAsmStrEqI(s, "xor") || RvAsmStrEqI(s, "sll") || RvAsmStrEqI(s, "srl") || RvAsmStrEqI(s, "sra") || RvAsmStrEqI(s, "slt") || RvAsmStrEqI(s, "sltu") || RvAsmStrEqI(s, "mul") || RvAsmStrEqI(s, "div") || RvAsmStrEqI(s, "rem") || RvAsmStrEqI(s, "divu") || RvAsmStrEqI(s, "remu") || RvAsmStrEqI(s, "ld") || RvAsmStrEqI(s, "lw") || RvAsmStrEqI(s, "sd") || RvAsmStrEqI(s, "sw") || RvAsmStrEqI(s, "jalr") || RvAsmStrEqI(s, "jal") || RvAsmStrEqI(s, "jr") || RvAsmStrEqI(s, "beq") || RvAsmStrEqI(s, "bne") || RvAsmStrEqI(s, "blt") || RvAsmStrEqI(s, "bge") || RvAsmStrEqI(s, "bltu") || RvAsmStrEqI(s, "bgeu") || RvAsmStrEqI(s, "beqz") || RvAsmStrEqI(s, "bnez") || RvAsmStrEqI(s, "csrr") || RvAsmStrEqI(s, "csrw") || RvAsmStrEqI(s, "csrs") || RvAsmStrEqI(s, "csrrw") || RvAsmStrEqI(s, "csrrs") || RvAsmStrEqI(s, "csrrc") || RvAsmStrEqI(s, "csrrwi") || RvAsmStrEqI(s, "csrrsi") || RvAsmStrEqI(s, "csrrci") || RvAsmStrEqI(s, "csrwi") || RvAsmStrEqI(s, "csrsi") || RvAsmStrEqI(s, "csrci") || RvAsmStrEqI(s, "lrd") || RvAsmStrEqI(s, "lrw") || RvAsmStrEqI(s, "scd") || RvAsmStrEqI(s, "scw") || RvAsmStrEqI(s, "amoswapd") || RvAsmStrEqI(s, "amoaddd") || RvAsmStrEqI(s, "amoxord") || RvAsmStrEqI(s, "amoandd") || RvAsmStrEqI(s, "amoord") || RvAsmStrEqI(s, "amomind") || RvAsmStrEqI(s, "amomaxd") || RvAsmStrEqI(s, "amominud") || RvAsmStrEqI(s, "amomaxud") || RvAsmStrEqI(s, "amoswapw") || RvAsmStrEqI(s, "amoaddw") || RvAsmStrEqI(s, "amoxorw") || RvAsmStrEqI(s, "amoandw") || RvAsmStrEqI(s, "amoorw") || RvAsmStrEqI(s, "amominw") || RvAsmStrEqI(s, "amomaxw") || RvAsmStrEqI(s, "amominuw") || RvAsmStrEqI(s, "amomaxuw") || RvAsmStrEqI(s, "lr") || RvAsmStrEqI(s, "sc") || RvAsmStrEqI(s, "amoswap") || RvAsmStrEqI(s, "amoadd") || RvAsmStrEqI(s, "amoxor") || RvAsmStrEqI(s, "amoand") || RvAsmStrEqI(s, "amoor") || RvAsmStrEqI(s, "amomin") || RvAsmStrEqI(s, "amomax") || RvAsmStrEqI(s, "amominu") || RvAsmStrEqI(s, "amomaxu"))
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

I64 RvAsmCsrNum(U8 *n)
{
  if (!n)
    return -1;
  if (RvAsmStrEqI(n, "sstatus"))
    return 0x100;
  if (RvAsmStrEqI(n, "sie"))
    return 0x104;
  if (RvAsmStrEqI(n, "stvec"))
    return 0x105;
  if (RvAsmStrEqI(n, "sscratch"))
    return 0x140;
  if (RvAsmStrEqI(n, "sepc"))
    return 0x141;
  if (RvAsmStrEqI(n, "scause"))
    return 0x142;
  if (RvAsmStrEqI(n, "stval"))
    return 0x143;
  if (RvAsmStrEqI(n, "sip"))
    return 0x144;
  if (RvAsmStrEqI(n, "satp"))
    return 0x180;
  if (RvAsmStrEqI(n, "mstatus"))
    return 0x300;
  if (RvAsmStrEqI(n, "misa"))
    return 0x301;
  if (RvAsmStrEqI(n, "medeleg"))
    return 0x302;
  if (RvAsmStrEqI(n, "mideleg"))
    return 0x303;
  if (RvAsmStrEqI(n, "mie"))
    return 0x304;
  if (RvAsmStrEqI(n, "mtvec"))
    return 0x305;
  if (RvAsmStrEqI(n, "mcounteren"))
    return 0x306;
  if (RvAsmStrEqI(n, "mscratch"))
    return 0x340;
  if (RvAsmStrEqI(n, "mepc"))
    return 0x341;
  if (RvAsmStrEqI(n, "mcause"))
    return 0x342;
  if (RvAsmStrEqI(n, "mtval"))
    return 0x343;
  if (RvAsmStrEqI(n, "mip"))
    return 0x344;
  if (RvAsmStrEqI(n, "mcycle"))
    return 0xB00;
  if (RvAsmStrEqI(n, "minstret"))
    return 0xB02;
  if (RvAsmStrEqI(n, "cycle"))
    return 0xC00;
  if (RvAsmStrEqI(n, "time"))
    return 0xC01;
  if (RvAsmStrEqI(n, "instret"))
    return 0xC02;
  if (RvAsmStrEqI(n, "mhartid"))
    return 0xF14;
  return -1;
}

Bool RvAsmImmTok(CCmpCtrl *cc, I64 *out)
{
  I64 neg = 0, v;
  if (cc->token == '-') {
    neg = 1;
    Lex(cc);
  }
  if (cc->token == TK_I64) {
    v = cc->cur_i64;
    if (neg)
      v = -v;
    *out = v;
    Lex(cc);
    return TRUE;
  }
  if (!neg && cc->token == TK_IDENT && cc->cur_str) {
    v = RvAsmCsrNum(cc->cur_str);
    if (v >= 0) {
      *out = v;
      Lex(cc);
      return TRUE;
    }
  }
  return FALSE;
}

Bool RvAsmFitsSimm12(I64 imm)
{
  return imm >= -2048 && imm <= 2047;
}

Bool RvAsmFitsShamt(I64 sh)
{
  return 0 <= sh <= 63;
}

Bool RvAsmFitsUimm20(I64 imm)
{
  return (0 <= imm <= 0xFFFFF) || (-0x80000 <= imm < 0);
}

Bool RvAsmFitsCsrImm(I64 imm)
{
  return 0 <= imm <= 0xFFF;
}

Bool RvAsmFitsZimm5(I64 z)
{
  return 0 <= z <= 31;
}

// B-type branch: 13-bit signed byte offset, imm[0] always 0 (even). PC-relative.
Bool RvAsmFitsBimm(I64 imm)
{
  if (imm & 1)
    return FALSE;
  return -4096 <= imm <= 4094;
}

// J-type jal: 21-bit signed byte offset, imm[0] always 0 (even). PC-relative.
Bool RvAsmFitsJimm(I64 imm)
{
  if (imm & 1)
    return FALSE;
  return -1048576 <= imm <= 1048574;
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

U32 RvAsmU(U32 opc, I64 rd, I64 imm20)
{
  return opc | (rd << 7) | ((imm20 & 0xFFFFF) << 12);
}

// B-type (opcode 0x63). imm is a PC-relative byte offset; the scramble is
// imm[12]->31, imm[10:5]->30:25, imm[4:1]->11:8, imm[11]->7 (imm[0] dropped).
U32 RvAsmB(U32 f3, I64 rs1, I64 rs2, I64 imm)
{
  U32 w = 0x63 | (f3 << 12) | (rs1 << 15) | (rs2 << 20);
  w |= ((imm >> 12) & 1) << 31;
  w |= ((imm >> 5) & 0x3F) << 25;
  w |= ((imm >> 1) & 0xF) << 8;
  w |= ((imm >> 11) & 1) << 7;
  return w;
}

// J-type jal (opcode 0x6F). imm is a PC-relative byte offset; the scramble is
// imm[20]->31, imm[10:1]->30:21, imm[11]->20, imm[19:12]->19:12 (imm[0] dropped).
U32 RvAsmJ(I64 rd, I64 imm)
{
  U32 w = 0x6F | (rd << 7);
  w |= ((imm >> 20) & 1) << 31;
  w |= ((imm >> 1) & 0x3FF) << 21;
  w |= ((imm >> 11) & 1) << 20;
  w |= ((imm >> 12) & 0xFF) << 12;
  return w;
}

U32 RvAsmA(U32 f5, U32 aqrl, U32 f3, I64 rd, I64 rs1, I64 rs2)
{
  return 0x2F | (rd << 7) | (f3 << 12) | (rs1 << 15) | (rs2 << 20) | (aqrl << 25) | (f5 << 27);
}
// Wide li: match host EmitLoadImm64 / BackLib RVLi (lui+addi; U32 bit31 → slli/srli 32 zext).
U0 RvAsmEmitLi(CCmpCtrl *cc, I64 rd, I64 imm)
{
  I64 hi, lo, hi32, lo32, hi_hi, hi_lo, lo_hi, lo_lo, scratch;
  if (imm >= -2048 && imm <= 2047) {
    AOTStoreCodeU32(cc, RvAsmI(0, rd, 0, imm));
    return;
  }
  hi32 = imm >> 32;
  if (!hi32 || hi32 == -1) {
    hi = (imm + 0x800) >> 12;
    lo = imm & 0xFFF;
    if (lo & 0x800)
      lo |= 0xFFFFFFFFFFFFF000;
    AOTStoreCodeU32(cc, RvAsmU(0x37, rd, hi));
    if (lo)
      AOTStoreCodeU32(cc, RvAsmI(0, rd, rd, lo));
    if (!hi32 && imm & 0x80000000) {
      AOTStoreCodeU32(cc, 0x13 | (rd << 7) | (1 << 12) | (rd << 15) | (32 << 20));
      AOTStoreCodeU32(cc, 0x13 | (rd << 7) | (5 << 12) | (rd << 15) | (32 << 20));
    }
    return;
  }
  scratch = 5;
  // t0
  if (rd == scratch)
    scratch = 6;
  // t1
  hi_hi = (hi32 + 0x800) >> 12;
  hi_lo = hi32 & 0xFFF;
  if (hi_lo & 0x800)
    hi_lo |= 0xFFFFFFFFFFFFF000;
  AOTStoreCodeU32(cc, RvAsmU(0x37, rd, hi_hi));
  if (hi_lo)
    AOTStoreCodeU32(cc, RvAsmI(0, rd, rd, hi_lo));
  AOTStoreCodeU32(cc, 0x13 | (rd << 7) | (1 << 12) | (rd << 15) | (32 << 20));
  // slli rd,32
  lo32 = imm & 0xFFFFFFFF;
  lo_hi = (lo32 + 0x800) >> 12;
  lo_lo = lo32 & 0xFFF;
  if (lo_lo & 0x800)
    lo_lo |= 0xFFFFFFFFFFFFF000;
  if (lo_hi) {
    AOTStoreCodeU32(cc, RvAsmU(0x37, scratch, lo_hi));
    if (lo_lo)
      AOTStoreCodeU32(cc, RvAsmI(0, scratch, scratch, lo_lo));
    if (lo32 & 0x80000000) {
      AOTStoreCodeU32(cc, 0x13 | (scratch << 7) | (1 << 12) | (scratch << 15) | (32 << 20));
      AOTStoreCodeU32(cc, 0x13 | (scratch << 7) | (5 << 12) | (scratch << 15) | (32 << 20));
    }
    AOTStoreCodeU32(cc, RvAsmR(0, 0, rd, rd, scratch));
  } else if (lo_lo)
    AOTStoreCodeU32(cc, RvAsmI(0, rd, rd, lo_lo));
}

U0 RvAsmMergeDotSuffix(U8 *mn, CCmpCtrl *cc)
{
  U8 *s;
  I64 n, i;
  if (cc->token != '.')
    return;
  Lex(cc);
  if (cc->token != TK_IDENT || !cc->cur_str)
    return;
  s = cc->cur_str;
  n = 0;
  while (mn[n])
    n++;
  mn[n++] = '.';
  i = 0;
  while (s[i] && n < 31) {
    mn[n] = s[i];
    if ('A' <= mn[n] <= 'Z')
      mn[n] += 32;
    n++;
    i++;
  }
  mn[n] = 0;
  Lex(cc);
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
  RvAsmMergeDotSuffix(mn, cc);
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
    if (!RvAsmFitsCsrImm(imm)) {
      Free(mn);
      LexExcept(cc, "CSR immediate out of range (need 0..0xFFF) at ");
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
    if (!RvAsmFitsCsrImm(imm)) {
      Free(mn);
      LexExcept(cc, "CSR immediate out of range (need 0..0xFFF) at ");
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
    if (!RvAsmFitsCsrImm(imm)) {
      Free(mn);
      LexExcept(cc, "CSR immediate out of range (need 0..0xFFF) at ");
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
    if (!RvAsmFitsCsrImm(imm)) {
      Free(mn);
      LexExcept(cc, "CSR immediate out of range (need 0..0xFFF) at ");
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
    RvAsmEmitLi(cc, rd, imm);
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
    if (RvAsmStrEqI(mn, "slli") || RvAsmStrEqI(mn, "srli") || RvAsmStrEqI(mn, "srai")) {
      if (!RvAsmFitsShamt(imm)) {
        Free(mn);
        LexExcept(cc, "shift amount out of range (need 0..63) at ");
      }
    } else if (!RvAsmFitsSimm12(imm)) {
      Free(mn);
      LexExcept(cc, "immediate out of range for 12-bit signed field (need -2048..2047; use li) at ");
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
    if (!RvAsmFitsSimm12(imm)) {
      Free(mn);
      LexExcept(cc, "immediate out of range for 12-bit signed field (need -2048..2047) at ");
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
  // B-type branches (numeric PC-relative offset; no label resolution yet — use
  // an even byte offset, exactly as the kernel's hand-computed asm{} does).
  if (RvAsmStrEqI(mn, "beq") || RvAsmStrEqI(mn, "bne") || RvAsmStrEqI(mn, "blt") || RvAsmStrEqI(mn, "bge") || RvAsmStrEqI(mn, "bltu") || RvAsmStrEqI(mn, "bgeu") || RvAsmStrEqI(mn, "beqz") || RvAsmStrEqI(mn, "bnez")) {
    // first := funct3; beqz/bnez are beq/bne against x0.
    if (RvAsmStrEqI(mn, "beq") || RvAsmStrEqI(mn, "beqz"))
      first = 0;
    else if (RvAsmStrEqI(mn, "bne") || RvAsmStrEqI(mn, "bnez"))
      first = 1;
    else if (RvAsmStrEqI(mn, "blt"))
      first = 4;
    else if (RvAsmStrEqI(mn, "bge"))
      first = 5;
    else if (RvAsmStrEqI(mn, "bltu"))
      first = 6;
    else
      first = 7;
    rs1 = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    if (RvAsmStrEqI(mn, "beqz") || RvAsmStrEqI(mn, "bnez")) {
      rs2 = 0;
    } else {
      rs2 = RvAsmRegTok(cc);
      if (cc->token != ',') {
        Free(mn);
        LexExcept(cc, "Expecting ',' at ");
      }
      Lex(cc);
    }
    if (!RvAsmImmTok(cc, &imm)) {
      Free(mn);
      LexExcept(cc, "Expecting branch offset at ");
    }
    if (rs1 < 0 || rs2 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (!RvAsmFitsBimm(imm)) {
      Free(mn);
      LexExcept(cc, "branch offset out of range (need even, -4096..4094; PC-relative) at ");
    }
    Free(mn);
    AOTStoreCodeU32(cc, RvAsmB(first, rs1, rs2, imm));
    return TRUE;
  }
  // jal (J-type PC-relative offset), jr (jalr x0,rs,0). We deliberately do NOT
  // define a numeric-offset `j`: the host asm{} parser defines `j label` as
  // label-only, so a guest `j 8` would give the same mnemonic two meanings.
  // Use `jal x0,off` for an unconditional numeric-offset jump.
  if (RvAsmStrEqI(mn, "jal")) {
    if (cc->token == TK_I64 || cc->token == '-') {
      rd = 1; // `jal offset` implies rd=ra
      RvAsmImmTok(cc, &imm);
    } else {
      rd = RvAsmRegTok(cc);
      if (cc->token != ',') {
        Free(mn);
        LexExcept(cc, "Expecting ',' at ");
      }
      Lex(cc);
      if (!RvAsmImmTok(cc, &imm)) {
        Free(mn);
        LexExcept(cc, "Expecting jump offset at ");
      }
    }
    if (rd < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (!RvAsmFitsJimm(imm)) {
      Free(mn);
      LexExcept(cc, "jump offset out of range (need even, -1MiB..+1MiB-2; PC-relative) at ");
    }
    Free(mn);
    AOTStoreCodeU32(cc, RvAsmJ(rd, imm));
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "jr")) {
    rs1 = RvAsmRegTok(cc);
    if (rs1 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    Free(mn);
    AOTStoreCodeU32(cc, RvAsmJalr(0, rs1, 0));
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
    if (!RvAsmFitsSimm12(imm)) {
      Free(mn);
      LexExcept(cc, "immediate out of range for 12-bit signed field (need -2048..2047) at ");
    }
    Free(mn);
    AOTStoreCodeU32(cc, RvAsmJalr(rd, rs1, imm));
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "lui") || RvAsmStrEqI(mn, "auipc")) {
    // imm is the 20-bit U-type field (gas-compatible), not a full address.
    // `lui a0, 0x81397` → 0x81397000; prefer `li` for constants.
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
    if (!RvAsmFitsUimm20(imm)) {
      Free(mn);
      LexExcept(cc, "lui/auipc immediate out of range (need 20-bit field 0..0xFFFFF; prefer li) at ");
    }
    if (RvAsmStrEqI(mn, "lui"))
      word = RvAsmU(0x37, rd, imm);
    else
      word = RvAsmU(0x17, rd, imm);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "csrrwi") || RvAsmStrEqI(mn, "csrrsi") || RvAsmStrEqI(mn, "csrrci")) {
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
    if (!RvAsmImmTok(cc, &rs1)) {
      Free(mn);
      LexExcept(cc, "Expecting zimm at ");
    }
    if (!RvAsmFitsCsrImm(imm) || !RvAsmFitsZimm5(rs1)) {
      Free(mn);
      LexExcept(cc, "CSR imm/zimm out of range at ");
    }
    if (rd < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (RvAsmStrEqI(mn, "csrrwi"))
      word = 0x00005073 | (rd << 7) | (rs1 << 15) | ((imm & 0xFFF) << 20);
    else if (RvAsmStrEqI(mn, "csrrsi"))
      word = 0x00006073 | (rd << 7) | (rs1 << 15) | ((imm & 0xFFF) << 20);
    else
      word = 0x00007073 | (rd << 7) | (rs1 << 15) | ((imm & 0xFFF) << 20);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "csrwi") || RvAsmStrEqI(mn, "csrsi") || RvAsmStrEqI(mn, "csrci")) {
    if (!RvAsmImmTok(cc, &imm)) {
      Free(mn);
      LexExcept(cc, "Expecting csr imm at ");
    }
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    if (!RvAsmImmTok(cc, &rs1)) {
      Free(mn);
      LexExcept(cc, "Expecting zimm at ");
    }
    if (!RvAsmFitsCsrImm(imm) || !RvAsmFitsZimm5(rs1)) {
      Free(mn);
      LexExcept(cc, "CSR imm/zimm out of range at ");
    }
    if (RvAsmStrEqI(mn, "csrwi"))
      word = 0x00005073 | (rs1 << 15) | ((imm & 0xFFF) << 20);
    else if (RvAsmStrEqI(mn, "csrsi"))
      word = 0x00006073 | (rs1 << 15) | ((imm & 0xFFF) << 20);
    else
      word = 0x00007073 | (rs1 << 15) | ((imm & 0xFFF) << 20);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "lr.d") || RvAsmStrEqI(mn, "lrd") || RvAsmStrEqI(mn, "lr.w") || RvAsmStrEqI(mn, "lrw")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
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
    if (rd < 0 || rs1 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (RvAsmStrEqI(mn, "lr.d") || RvAsmStrEqI(mn, "lrd"))
      word = RvAsmA(0x02, 0, 0x3, rd, rs1, 0);
    else
      word = RvAsmA(0x02, 0, 0x2, rd, rs1, 0);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "sc.d") || RvAsmStrEqI(mn, "scd") || RvAsmStrEqI(mn, "sc.w") || RvAsmStrEqI(mn, "scw") || RvAsmStrEqI(mn, "amoswap.d") || RvAsmStrEqI(mn, "amoswapd") || RvAsmStrEqI(mn, "amoadd.d") || RvAsmStrEqI(mn, "amoaddd") || RvAsmStrEqI(mn, "amoxor.d") || RvAsmStrEqI(mn, "amoxord") || RvAsmStrEqI(mn, "amoand.d") || RvAsmStrEqI(mn, "amoandd") || RvAsmStrEqI(mn, "amoor.d") || RvAsmStrEqI(mn, "amoord") || RvAsmStrEqI(mn, "amomin.d") || RvAsmStrEqI(mn, "amomind") || RvAsmStrEqI(mn, "amomax.d") || RvAsmStrEqI(mn, "amomaxd") || RvAsmStrEqI(mn, "amominu.d") || RvAsmStrEqI(mn, "amominud") || RvAsmStrEqI(mn, "amomaxu.d") || RvAsmStrEqI(mn, "amomaxud") || RvAsmStrEqI(mn, "amoswap.w") || RvAsmStrEqI(mn, "amoswapw") || RvAsmStrEqI(mn, "amoadd.w") || RvAsmStrEqI(mn, "amoaddw") || RvAsmStrEqI(mn, "amoxor.w") || RvAsmStrEqI(mn, "amoxorw") || RvAsmStrEqI(mn, "amoand.w") || RvAsmStrEqI(mn, "amoandw") || RvAsmStrEqI(mn, "amoor.w") || RvAsmStrEqI(mn, "amoorw") || RvAsmStrEqI(mn, "amomin.w") || RvAsmStrEqI(mn, "amominw") || RvAsmStrEqI(mn, "amomax.w") || RvAsmStrEqI(mn, "amomaxw") || RvAsmStrEqI(mn, "amominu.w") || RvAsmStrEqI(mn, "amominuw") || RvAsmStrEqI(mn, "amomaxu.w") || RvAsmStrEqI(mn, "amomaxuw")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs2 = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
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
    if (rd < 0 || rs1 < 0 || rs2 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (RvAsmStrEqI(mn, "sc.d") || RvAsmStrEqI(mn, "scd"))
      word = RvAsmA(0x03, 0, 0x3, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "sc.w") || RvAsmStrEqI(mn, "scw"))
      word = RvAsmA(0x03, 0, 0x2, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amoswap.d") || RvAsmStrEqI(mn, "amoswapd"))
      word = RvAsmA(0x01, 0, 0x3, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amoadd.d") || RvAsmStrEqI(mn, "amoaddd"))
      word = RvAsmA(0x00, 0, 0x3, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amoxor.d") || RvAsmStrEqI(mn, "amoxord"))
      word = RvAsmA(0x04, 0, 0x3, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amoand.d") || RvAsmStrEqI(mn, "amoandd"))
      word = RvAsmA(0x0C, 0, 0x3, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amoor.d") || RvAsmStrEqI(mn, "amoord"))
      word = RvAsmA(0x08, 0, 0x3, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amomin.d") || RvAsmStrEqI(mn, "amomind"))
      word = RvAsmA(0x10, 0, 0x3, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amomax.d") || RvAsmStrEqI(mn, "amomaxd"))
      word = RvAsmA(0x14, 0, 0x3, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amominu.d") || RvAsmStrEqI(mn, "amominud"))
      word = RvAsmA(0x18, 0, 0x3, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amomaxu.d") || RvAsmStrEqI(mn, "amomaxud"))
      word = RvAsmA(0x1C, 0, 0x3, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amoswap.w") || RvAsmStrEqI(mn, "amoswapw"))
      word = RvAsmA(0x01, 0, 0x2, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amoadd.w") || RvAsmStrEqI(mn, "amoaddw"))
      word = RvAsmA(0x00, 0, 0x2, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amoxor.w") || RvAsmStrEqI(mn, "amoxorw"))
      word = RvAsmA(0x04, 0, 0x2, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amoand.w") || RvAsmStrEqI(mn, "amoandw"))
      word = RvAsmA(0x0C, 0, 0x2, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amoor.w") || RvAsmStrEqI(mn, "amoorw"))
      word = RvAsmA(0x08, 0, 0x2, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amomin.w") || RvAsmStrEqI(mn, "amominw"))
      word = RvAsmA(0x10, 0, 0x2, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amomax.w") || RvAsmStrEqI(mn, "amomaxw"))
      word = RvAsmA(0x14, 0, 0x2, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "amominu.w") || RvAsmStrEqI(mn, "amominuw"))
      word = RvAsmA(0x18, 0, 0x2, rd, rs1, rs2);
    else
      word = RvAsmA(0x1C, 0, 0x2, rd, rs1, rs2);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  Free(mn);
  LexExcept(cc, "Unsupported RISC-V asm mnemonic at ");
  return FALSE;
}
