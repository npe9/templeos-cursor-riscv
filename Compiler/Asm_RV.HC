// Asm_RV.HC — RISC-V asm{} for Compiler_RV (ExePutS / COCCompile).
// Unlabeled `asm { addi s2,s2,3 }` → AOTStoreCodeU32 (or LexExcept).
I64 g_rv_asm_exports;

// Block-local label fixups for FORWARD branch/jump references (a label defined
// LATER in the same asm block). Backward refs resolve inline (the label's rip is
// already recorded). Forward refs emit a placeholder word and record an entry here;
// PrsAsmBlk calls RvAsmFixupResolve at block end to patch the offset in place via
// AOTStoreCodeU8At. Reset per block in PrsAsmBlk (next to g_rv_asm_exports=0).
#define RV_ASM_MAX_FIXUP 128
I64 rv_asm_fixup_cnt;
I64 rv_asm_fixup_rip[RV_ASM_MAX_FIXUP];  // byte offset of the placeholder word
U32 rv_asm_fixup_base[RV_ASM_MAX_FIXUP]; // word with imm=0 (opcode+regs+f3)
I64 rv_asm_fixup_btype[RV_ASM_MAX_FIXUP];// 1=B-type scramble, 0=J-type
U8 *rv_asm_fixup_name[RV_ASM_MAX_FIXUP]; // StrNew'd label name to resolve
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
  if (RvAsmStrEqI(s, "ret") || RvAsmStrEqI(s, "nop") || RvAsmStrEqI(s, "wfi") || RvAsmStrEqI(s, "mret") || RvAsmStrEqI(s, "sret") || RvAsmStrEqI(s, "ecall") || RvAsmStrEqI(s, "ebreak") || RvAsmStrEqI(s, "fencei") || RvAsmStrEqI(s, "fence.i") || RvAsmStrEqI(s, "fence") || RvAsmStrEqI(s, "sfence") || RvAsmStrEqI(s, "sfencevma") || RvAsmStrEqI(s, "mv") || RvAsmStrEqI(s, "not") || RvAsmStrEqI(s, "neg") || RvAsmStrEqI(s, "seqz") || RvAsmStrEqI(s, "snez") || RvAsmStrEqI(s, "csrc") || RvAsmStrEqI(s, "rdtime") || RvAsmStrEqI(s, "li") || RvAsmStrEqI(s, "lui") || RvAsmStrEqI(s, "auipc") || RvAsmStrEqI(s, "addi") || RvAsmStrEqI(s, "andi") || RvAsmStrEqI(s, "ori") || RvAsmStrEqI(s, "xori") || RvAsmStrEqI(s, "slti") || RvAsmStrEqI(s, "slli") || RvAsmStrEqI(s, "srli") || RvAsmStrEqI(s, "srai") || RvAsmStrEqI(s, "add") || RvAsmStrEqI(s, "sub") || RvAsmStrEqI(s, "and") || RvAsmStrEqI(s, "or") || RvAsmStrEqI(s, "xor") || RvAsmStrEqI(s, "sll") || RvAsmStrEqI(s, "srl") || RvAsmStrEqI(s, "sra") || RvAsmStrEqI(s, "slt") || RvAsmStrEqI(s, "sltu") || RvAsmStrEqI(s, "sltiu") || RvAsmStrEqI(s, "mul") || RvAsmStrEqI(s, "mulh") || RvAsmStrEqI(s, "mulhsu") || RvAsmStrEqI(s, "mulhu") || RvAsmStrEqI(s, "div") || RvAsmStrEqI(s, "rem") || RvAsmStrEqI(s, "divu") || RvAsmStrEqI(s, "remu") || RvAsmStrEqI(s, "addiw") || RvAsmStrEqI(s, "slliw") || RvAsmStrEqI(s, "srliw") || RvAsmStrEqI(s, "sraiw") || RvAsmStrEqI(s, "addw") || RvAsmStrEqI(s, "subw") || RvAsmStrEqI(s, "sllw") || RvAsmStrEqI(s, "srlw") || RvAsmStrEqI(s, "sraw") || RvAsmStrEqI(s, "mulw") || RvAsmStrEqI(s, "divw") || RvAsmStrEqI(s, "divuw") || RvAsmStrEqI(s, "remw") || RvAsmStrEqI(s, "remuw") || RvAsmStrEqI(s, "ld") || RvAsmStrEqI(s, "lw") || RvAsmStrEqI(s, "lwu") || RvAsmStrEqI(s, "lh") || RvAsmStrEqI(s, "lhu") || RvAsmStrEqI(s, "lb") || RvAsmStrEqI(s, "lbu") || RvAsmStrEqI(s, "sd") || RvAsmStrEqI(s, "sw") || RvAsmStrEqI(s, "sh") || RvAsmStrEqI(s, "sb") || RvAsmStrEqI(s, "jalr") || RvAsmStrEqI(s, "jal") || RvAsmStrEqI(s, "jr") || RvAsmStrEqI(s, "j") || RvAsmStrEqI(s, "beq") || RvAsmStrEqI(s, "bne") || RvAsmStrEqI(s, "blt") || RvAsmStrEqI(s, "bge") || RvAsmStrEqI(s, "bltu") || RvAsmStrEqI(s, "bgeu") || RvAsmStrEqI(s, "beqz") || RvAsmStrEqI(s, "bnez") || RvAsmStrEqI(s, "faddd") || RvAsmStrEqI(s, "fsubd") || RvAsmStrEqI(s, "fmuld") || RvAsmStrEqI(s, "fdivd") || RvAsmStrEqI(s, "fsqrtd") || RvAsmStrEqI(s, "fadd") || RvAsmStrEqI(s, "fsub") || RvAsmStrEqI(s, "fmul") || RvAsmStrEqI(s, "fdiv") || RvAsmStrEqI(s, "fsqrt") || RvAsmStrEqI(s, "flw") || RvAsmStrEqI(s, "fsw") || RvAsmStrEqI(s, "fled") || RvAsmStrEqI(s, "fltd") || RvAsmStrEqI(s, "feqd") || RvAsmStrEqI(s, "fle") || RvAsmStrEqI(s, "flt") || RvAsmStrEqI(s, "feq") || RvAsmStrEqI(s, "fmv") || RvAsmStrEqI(s, "fmvdx") || RvAsmStrEqI(s, "fmvxd") || RvAsmStrEqI(s, "fsgnj") || RvAsmStrEqI(s, "fsgnjn") || RvAsmStrEqI(s, "fsgnjx") || RvAsmStrEqI(s, "fmin") || RvAsmStrEqI(s, "fmax") || RvAsmStrEqI(s, "fclass") || RvAsmStrEqI(s, "fmadd") || RvAsmStrEqI(s, "fmsub") || RvAsmStrEqI(s, "fnmsub") || RvAsmStrEqI(s, "fnmadd") || RvAsmStrEqI(s, "fcvtld_rtz") || RvAsmStrEqI(s, "fcvtld_rdn") || RvAsmStrEqI(s, "fcvtld_rmm") || RvAsmStrEqI(s, "fcvtdl") || RvAsmStrEqI(s, "fcvt") || RvAsmStrEqI(s, "fld") || RvAsmStrEqI(s, "fsd") || RvAsmStrEqI(s, "csrr") || RvAsmStrEqI(s, "csrw") || RvAsmStrEqI(s, "csrs") || RvAsmStrEqI(s, "csrrw") || RvAsmStrEqI(s, "csrrs") || RvAsmStrEqI(s, "csrrc") || RvAsmStrEqI(s, "csrrwi") || RvAsmStrEqI(s, "csrrsi") || RvAsmStrEqI(s, "csrrci") || RvAsmStrEqI(s, "csrwi") || RvAsmStrEqI(s, "csrsi") || RvAsmStrEqI(s, "csrci") || RvAsmStrEqI(s, "lrd") || RvAsmStrEqI(s, "lrw") || RvAsmStrEqI(s, "scd") || RvAsmStrEqI(s, "scw") || RvAsmStrEqI(s, "amoswapd") || RvAsmStrEqI(s, "amoaddd") || RvAsmStrEqI(s, "amoxord") || RvAsmStrEqI(s, "amoandd") || RvAsmStrEqI(s, "amoord") || RvAsmStrEqI(s, "amomind") || RvAsmStrEqI(s, "amomaxd") || RvAsmStrEqI(s, "amominud") || RvAsmStrEqI(s, "amomaxud") || RvAsmStrEqI(s, "amoswapw") || RvAsmStrEqI(s, "amoaddw") || RvAsmStrEqI(s, "amoxorw") || RvAsmStrEqI(s, "amoandw") || RvAsmStrEqI(s, "amoorw") || RvAsmStrEqI(s, "amominw") || RvAsmStrEqI(s, "amomaxw") || RvAsmStrEqI(s, "amominuw") || RvAsmStrEqI(s, "amomaxuw") || RvAsmStrEqI(s, "lr") || RvAsmStrEqI(s, "sc") || RvAsmStrEqI(s, "amoswap") || RvAsmStrEqI(s, "amoadd") || RvAsmStrEqI(s, "amoxor") || RvAsmStrEqI(s, "amoand") || RvAsmStrEqI(s, "amoor") || RvAsmStrEqI(s, "amomin") || RvAsmStrEqI(s, "amomax") || RvAsmStrEqI(s, "amominu") || RvAsmStrEqI(s, "amomaxu"))
    return TRUE;
  // RVC (compressed) stem: c.mv/c.addi/c.li/... all lex as bare "c" then ".suffix".
  if (RvAsmStrEqI(s, "c"))
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

// Float register (RV64D ABI): ft0-7=f0-7, fs0-1=f8-9, fa0-7=f10-17, fs2-11=f18-27,
// ft8-11=f28-31, raw fN. STANDALONE - must NOT share RvAsmRegNum (which maps `fp`->8).
I64 RvAsmFRegNum(U8 *n)
{
  I64 k;
  if (!n || (n[0] != 'f' && n[0] != 'F'))
    return -1;
  if (n[1] == 'a' || n[1] == 'A') {
    k = Str2I64(n + 2);
    if (0 <= k <= 7)
      return 10 + k;
  }
  if (n[1] == 't' || n[1] == 'T') {
    k = Str2I64(n + 2);
    if (0 <= k <= 7)
      return k;
    if (8 <= k <= 11)
      return 28 + (k - 8);
  }
  if (n[1] == 's' || n[1] == 'S') {
    k = Str2I64(n + 2);
    if (0 <= k <= 1)
      return 8 + k;
    if (2 <= k <= 11)
      return 16 + k;
  }
  // raw fN (n[1] is a digit)
  if ('0' <= n[1] <= '9') {
    k = Str2I64(n + 1);
    if (0 <= k <= 31)
      return k;
  }
  return -1;
}

I64 RvAsmFRegTok(CCmpCtrl *cc)
{
  I64 r;
  if (cc->token != TK_IDENT)
    return -1;
  r = RvAsmFRegNum(cc->cur_str);
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

// OP-IMM-32 (opcode 0x1B): addiw/slliw/srliw/sraiw — RV64 word (32-bit) forms.
U32 RvAsmIw(U32 f3, I64 rd, I64 rs1, I64 imm)
{
  return 0x1B | (rd << 7) | (f3 << 12) | (rs1 << 15) | ((imm & 0xFFF) << 20);
}

// OP-32 (opcode 0x3B): addw/subw/.../mulw..remuw — RV64 word (32-bit) R-type forms.
U32 RvAsmRw(U32 f7, U32 f3, I64 rd, I64 rs1, I64 rs2)
{
  return 0x3B | (rd << 7) | (f3 << 12) | (rs1 << 15) | (rs2 << 20) | (f7 << 25);
}

// Parse an optional trailing ", <rm>" rounding mode. Returns rm code (0..7) or -1 if none.
// rne=0 rtz=1 rdn=2 rup=3 rmm=4 dyn=7. LexExcepts on a bad name after the comma.
I64 RvAsmParseOptRm(CCmpCtrl *cc)
{
  U8 *r;
  if (cc->token != ',')
    return -1;
  Lex(cc);
  if (cc->token != TK_IDENT || !cc->cur_str)
    LexExcept(cc, "expected rounding mode after ',' at ");
  r = cc->cur_str;
  if (RvAsmStrEqI(r, "rne")) {
    Lex(cc);
    return 0;
  }
  if (RvAsmStrEqI(r, "rtz")) {
    Lex(cc);
    return 1;
  }
  if (RvAsmStrEqI(r, "rdn")) {
    Lex(cc);
    return 2;
  }
  if (RvAsmStrEqI(r, "rup")) {
    Lex(cc);
    return 3;
  }
  if (RvAsmStrEqI(r, "rmm")) {
    Lex(cc);
    return 4;
  }
  if (RvAsmStrEqI(r, "dyn")) {
    Lex(cc);
    return 7;
  }
  LexExcept(cc, "bad rounding mode (rne/rtz/rdn/rup/rmm/dyn) at ");
  return -1;
}

// fence pred/succ ordering mask: letters i(8) o(4) r(2) w(1); e.g. "rw"=3, "iorw"=15. -1 if any bad letter.
I64 RvAsmFenceMask(U8 *s)
{
  I64 m = 0, i = 0;
  U8 c;
  if (!s || !s[0])
    return -1;
  while (s[i]) {
    c = s[i] | 0x20;
    if (c == 'i')
      m |= 8;
    else if (c == 'o')
      m |= 4;
    else if (c == 'r')
      m |= 2;
    else if (c == 'w')
      m |= 1;
    else
      return -1;
    i++;
  }
  return m;
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

// RVC CJ-type immediate scramble (c.j): PC-relative byte offset, even, -2048..2046.
// Bits [12:2] pack offset[11|4|9:8|10|6|7|3:1|5]. GNU-verified (-march=rv64imac).
U32 RvAsmCJImm(I64 off)
{
  U32 w = 0;
  w |= ((off >> 11) & 1) << 12;
  w |= ((off >> 4) & 1) << 11;
  w |= ((off >> 9) & 1) << 10;
  w |= ((off >> 8) & 1) << 9;
  w |= ((off >> 10) & 1) << 8;
  w |= ((off >> 6) & 1) << 7;
  w |= ((off >> 7) & 1) << 6;
  w |= ((off >> 3) & 1) << 5;
  w |= ((off >> 2) & 1) << 4;
  w |= ((off >> 1) & 1) << 3;
  w |= ((off >> 5) & 1) << 2;
  return w;
}
// RVC CB-type immediate scramble (c.beqz/c.bnez): even, -256..254. Bits [12:10]
// and [6:2] pack offset[8|4:3] and offset[7:6|2:1|5] (rs1' occupies [9:7]).
U32 RvAsmCBImm(I64 off)
{
  U32 w = 0;
  w |= ((off >> 8) & 1) << 12;
  w |= ((off >> 4) & 1) << 11;
  w |= ((off >> 3) & 1) << 10;
  w |= ((off >> 7) & 1) << 6;
  w |= ((off >> 6) & 1) << 5;
  w |= ((off >> 2) & 1) << 4;
  w |= ((off >> 1) & 1) << 3;
  w |= ((off >> 5) & 1) << 2;
  return w;
}
Bool RvAsmFitsCJimm(I64 off)
{
  return !(off & 1) && off >= -2048 && off <= 2046;
}
Bool RvAsmFitsCBimm(I64 off)
{
  return !(off & 1) && off >= -256 && off <= 254;
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

// Duplicate a mnemonic into a FIXED 32-byte buffer (not StrLen+1). RvAsmMergeDotSuffix
// appends ".d"/".w" and writes up to mn[31], so a StrNew(StrLen+1) buffer overflows the
// heap for a short mnemonic like "sc"+".d". 32 bytes covers every mnemonic + suffix.
U8 *RvAsmMnDup(U8 *s)
{
  U8 *d;
  I64 i;
  d = MAlloc(32);
  if (!d)
    return 0;
  i = 0;
  if (s)
    while (s[i] && i < 31) {
      d[i] = s[i];
      i++;
    }
  d[i] = 0;
  return d;
}

U0 RvAsmMergeDotSuffix(U8 *mn, CCmpCtrl *cc)
{
  U8 *s;
  I64 n, i;
  // Loop so multi-dot mnemonics (fcvt.<int>.<fmt>) fully fold into mn.
  while (cc->token == '.') {
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
}

// Look up an asm-block label by name; return its recorded rip via *out_rip.
// Labels are stored as HTT_EXPORT_SYS_SYM (`->val` = aotc->rip at the `name:` line);
// plain `name:` goes to glbl_hash_table, `@@name:` to local_hash_table.
Bool RvAsmLabelRip(CCmpCtrl *cc, U8 *name, I64 *out_rip)
{
  CHashExport *e;
  e = HashFind(name, cc->htc.local_hash_table, HTT_EXPORT_SYS_SYM);
  if (!e)
    e = HashFind(name, cc->htc.glbl_hash_table, HTT_EXPORT_SYS_SYM);
  if (!e)
    return FALSE;
  *out_rip = e->val;
  return TRUE;
}

// Resolve a branch/jump TARGET operand into a PC-relative byte offset from the
// current instruction (aotc->rip). Return: 0 = not a valid target (caller errors);
// 1 = numeric literal or a backward label (already defined) -> *off is the offset;
// 2 = a FORWARD label (not yet defined) -> *fwd_name = StrNew'd name, *off = 0.
I64 RvAsmBrTarget(CCmpCtrl *cc, I64 *off, U8 **fwd_name)
{
  I64 lrip;
  *fwd_name = NULL;
  if (cc->token == '-' || cc->token == TK_I64) {
    if (RvAsmImmTok(cc, off))
      return 1;
    return 0;
  }
  if (cc->token == TK_IDENT && cc->cur_str) {
    // A CSR name is also a valid immediate; a branch to one makes no sense, so
    // labels win here (RvAsmImmTok's CSR path is only reached for the numeric forms).
    if (RvAsmLabelRip(cc, cc->cur_str, &lrip)) {
      *off = lrip - cc->aotc->rip; // backward reference
      Lex(cc);
      return 1;
    }
    *fwd_name = StrNew(cc->cur_str); // forward reference -> fixup at block end
    Lex(cc);
    return 2;
  }
  return 0;
}

// Record a forward branch/jump reference for patching at block end.
U0 RvAsmFixupAdd(CCmpCtrl *cc, U32 base, I64 is_btype, U8 *name)
{
  if (rv_asm_fixup_cnt >= RV_ASM_MAX_FIXUP) {
    Free(name);
    LexExcept(cc, "Too many forward label references in one asm block at ");
  }
  rv_asm_fixup_rip[rv_asm_fixup_cnt] = cc->aotc->rip; // == where AOTStoreCodeU32 stores next
  rv_asm_fixup_base[rv_asm_fixup_cnt] = base;
  rv_asm_fixup_btype[rv_asm_fixup_cnt] = is_btype;
  rv_asm_fixup_name[rv_asm_fixup_cnt] = name;
  rv_asm_fixup_cnt++;
}

// Patch every recorded forward reference now that all labels in the block are defined.
// Called by PrsAsmBlk at block end. Rewrites the placeholder word in place with
// AOTStoreCodeU8At (which does not touch aotc->rip).
U0 RvAsmFixupResolve(CCmpCtrl *cc)
{
  I64 k, off, lrip, bad;
  U32 w, immb;
  bad = 0;
  for (k = 0; k < rv_asm_fixup_cnt; k++) {
    if (!RvAsmLabelRip(cc, rv_asm_fixup_name[k], &lrip)) {
      bad = 1; // undefined label referenced by a forward branch/jump
    } else {
      off = lrip - rv_asm_fixup_rip[k];
      // btype: 0 = J-type (4B), 1 = B-type (4B), 2 = RVC CJ (2B), 3 = RVC CB (2B).
      if (rv_asm_fixup_btype[k] == 2) {
        if (!RvAsmFitsCJimm(off))
          bad = 2;
        w = rv_asm_fixup_base[k] | RvAsmCJImm(off);
        AOTStoreCodeU8At(cc, rv_asm_fixup_rip[k], w & 0xFF, (w >> 8) & 0xFF);
      } else if (rv_asm_fixup_btype[k] == 3) {
        if (!RvAsmFitsCBimm(off))
          bad = 2;
        w = rv_asm_fixup_base[k] | RvAsmCBImm(off);
        AOTStoreCodeU8At(cc, rv_asm_fixup_rip[k], w & 0xFF, (w >> 8) & 0xFF);
      } else {
        if (rv_asm_fixup_btype[k]) {
          if (!RvAsmFitsBimm(off))
            bad = 2;
          immb = ((off >> 12) & 1) << 31;
          immb = immb | (((off >> 5) & 0x3F) << 25);
          immb = immb | (((off >> 1) & 0xF) << 8);
          immb = immb | (((off >> 11) & 1) << 7);
        } else {
          if (!RvAsmFitsJimm(off))
            bad = 2;
          immb = ((off >> 20) & 1) << 31;
          immb = immb | (((off >> 1) & 0x3FF) << 21);
          immb = immb | (((off >> 11) & 1) << 20);
          immb = immb | (((off >> 12) & 0xFF) << 12);
        }
        w = rv_asm_fixup_base[k] | immb;
        AOTStoreCodeU8At(cc, rv_asm_fixup_rip[k], w & 0xFF, (w >> 8) & 0xFF, (w >> 16) & 0xFF, (w >> 24) & 0xFF);
      }
    }
    Free(rv_asm_fixup_name[k]);
    rv_asm_fixup_name[k] = NULL;
  }
  rv_asm_fixup_cnt = 0;
  if (bad == 1)
    LexExcept(cc, "asm{}: branch/jump to an undefined label in this block ");
  if (bad == 2)
    LexExcept(cc, "asm{}: forward branch/jump target out of range ");
}

Bool PrsAsmRVIns(CCmpCtrl *cc)
{
  // TRUE if a known RV mnemonic was assembled. FALSE → caller may treat as label.
  I64 rd, rs1, rs2, imm, first, is_imm, tgt, rm;
  U32 word;
  U8 *mn, *fwdname;
  if (cc->token != TK_IDENT || !cc->cur_str)
    return FALSE;
  if (!RvAsmIsMn(cc->cur_str))
    return FALSE;
  mn = RvAsmMnDup(cc->cur_str); // fixed 32-byte buf; RvAsmMergeDotSuffix appends into it
  Lex(cc);
  // skip mnemonic
  RvAsmMergeDotSuffix(mn, cc);
  rm = 7; // default rounding mode (dyn); rm-taking blocks may override from a trailing operand
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
  if (RvAsmStrEqI(mn, "csrc")) { // csrc csr, rs  -> csrrc x0, csr, rs (clear bits)
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
    AOTStoreCodeU32(cc, 0x00003073 | (rs1 << 15) | ((imm & 0xFFF) << 20));
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "rdtime")) { // rdtime rd -> csrrs rd, time(0xC01), x0
    rd = RvAsmRegTok(cc);
    if (rd < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    Free(mn);
    AOTStoreCodeU32(cc, 0xC0102073 | (rd << 7));
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
  // ---- RVC (compressed, 16-bit) — increment 1: register/immediate forms ----
  // Emitted via AOTStoreCodeU16 (2 bytes); aotc->rip advances by 2 so any labels
  // and branches in the same block stay byte-correct. Every encoding below was
  // byte-verified against GNU gas (riscv64 -march=rv64imac). No immediate-scramble
  // forms here (c.j/c.beqz/c.ld/... come in a later increment).
  if (RvAsmStrEqI(mn, "c.nop")) {
    Free(mn);
    AOTStoreCodeU16(cc, 0x0001);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "c.ebreak")) {
    Free(mn);
    AOTStoreCodeU16(cc, 0x9002);
    return TRUE;
  }
  // CR-type reg,reg: c.mv (funct4=1000) / c.add (funct4=1001). rd,rs2 != x0.
  if (RvAsmStrEqI(mn, "c.mv") || RvAsmStrEqI(mn, "c.add")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs2 = RvAsmRegTok(cc);
    if (rd < 1 || rs2 < 1) {
      Free(mn);
      LexExcept(cc, "c.mv/c.add need non-zero registers (x1-x31) at ");
    }
    if (RvAsmStrEqI(mn, "c.mv"))
      word = 0x8000 | (rd << 7) | (rs2 << 2) | 2;
    else
      word = 0x9000 | (rd << 7) | (rs2 << 2) | 2;
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // CR-type reg: c.jr (funct4=1000) / c.jalr (funct4=1001), rs2=0, rs1 != x0.
  if (RvAsmStrEqI(mn, "c.jr") || RvAsmStrEqI(mn, "c.jalr")) {
    rs1 = RvAsmRegTok(cc);
    if (rs1 < 1) {
      Free(mn);
      LexExcept(cc, "c.jr/c.jalr need a non-zero register (x1-x31) at ");
    }
    if (RvAsmStrEqI(mn, "c.jr"))
      word = 0x8000 | (rs1 << 7) | 2;
    else
      word = 0x9000 | (rs1 << 7) | 2;
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // CI-type reg,imm: c.li / c.addi (6-bit signed imm, op=01) / c.slli (RV64
  // shamt 0..63, op=10). imm[5] -> bit12, imm[4:0] -> bits[6:2], rd != x0.
  if (RvAsmStrEqI(mn, "c.li") || RvAsmStrEqI(mn, "c.addi") || RvAsmStrEqI(mn, "c.slli")) {
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
    if (rd < 1) {
      Free(mn);
      LexExcept(cc, "c.li/c.addi/c.slli need a non-zero register (x1-x31) at ");
    }
    if (RvAsmStrEqI(mn, "c.slli")) {
      if (imm < 0 || imm > 63) {
        Free(mn);
        LexExcept(cc, "c.slli shift amount out of range (need 0..63) at ");
      }
      word = ((imm & 0x20) << 7) | (rd << 7) | ((imm & 0x1F) << 2) | 2;
    } else {
      if (imm < -32 || imm > 31) {
        Free(mn);
        LexExcept(cc, "c.li/c.addi immediate out of range (need -32..31) at ");
      }
      if (RvAsmStrEqI(mn, "c.li"))
        word = 0x4000 | ((imm & 0x20) << 7) | (rd << 7) | ((imm & 0x1F) << 2) | 1;
      else
        word = ((imm & 0x20) << 7) | (rd << 7) | ((imm & 0x1F) << 2) | 1;
    }
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // CA-type reg,reg: c.sub/c.xor/c.or/c.and — both regs MUST be x8-x15 (3-bit
  // subset). funct6=100011, funct2 selects op: sub=00 xor=01 or=10 and=11.
  if (RvAsmStrEqI(mn, "c.sub") || RvAsmStrEqI(mn, "c.xor") || RvAsmStrEqI(mn, "c.or") || RvAsmStrEqI(mn, "c.and")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs2 = RvAsmRegTok(cc);
    if (rd < 8 || rd > 15 || rs2 < 8 || rs2 > 15) {
      Free(mn);
      LexExcept(cc, "c.sub/c.xor/c.or/c.and need registers x8-x15 (s0-s1/a0-a5) at ");
    }
    if (RvAsmStrEqI(mn, "c.sub"))
      word = 0x8C01;
    else if (RvAsmStrEqI(mn, "c.xor"))
      word = 0x8C21;
    else if (RvAsmStrEqI(mn, "c.or"))
      word = 0x8C41;
    else
      word = 0x8C61;
    word |= ((rd - 8) << 7) | ((rs2 - 8) << 2);
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // ---- RVC increment 2: immediate-scramble jumps/branches + subset loads/stores ----
  // CJ `c.j off|label` (funct3=101, op=01). Numeric offset or a label (either
  // direction); a forward label plants a 2-byte placeholder + a CJ fixup (kind 2).
  if (RvAsmStrEqI(mn, "c.j")) {
    tgt = RvAsmBrTarget(cc, &imm, &fwdname);
    if (!tgt) {
      Free(mn);
      LexExcept(cc, "Expecting c.j offset or label at ");
    }
    Free(mn);
    if (tgt == 2) {
      RvAsmFixupAdd(cc, 0xA001, 2, fwdname);
      AOTStoreCodeU16(cc, 0xA001);
      return TRUE;
    }
    if (!RvAsmFitsCJimm(imm))
      LexExcept(cc, "c.j offset out of range (even, -2048..2046; PC-relative) at ");
    AOTStoreCodeU16(cc, 0xA001 | RvAsmCJImm(imm));
    return TRUE;
  }
  // CB `c.beqz/c.bnez rs1', off|label` — rs1' MUST be x8-x15 (3-bit subset).
  // funct3=110 (beqz) / 111 (bnez), op=01; forward label plants a CB fixup (kind 3).
  if (RvAsmStrEqI(mn, "c.beqz") || RvAsmStrEqI(mn, "c.bnez")) {
    rd = RvAsmRegTok(cc); // rs1'
    if (rd < 8 || rd > 15) {
      Free(mn);
      LexExcept(cc, "c.beqz/c.bnez need a register x8-x15 (s0-s1/a0-a5) at ");
    }
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    if (RvAsmStrEqI(mn, "c.beqz"))
      word = 0xC001 | ((rd - 8) << 7);
    else
      word = 0xE001 | ((rd - 8) << 7);
    Free(mn);
    tgt = RvAsmBrTarget(cc, &imm, &fwdname);
    if (!tgt)
      LexExcept(cc, "Expecting c.beqz/c.bnez offset or label at ");
    if (tgt == 2) {
      RvAsmFixupAdd(cc, word, 3, fwdname);
      AOTStoreCodeU16(cc, word);
      return TRUE;
    }
    if (!RvAsmFitsCBimm(imm))
      LexExcept(cc, "c.beqz/c.bnez offset out of range (even, -256..254; PC-relative) at ");
    AOTStoreCodeU16(cc, word | RvAsmCBImm(imm));
    return TRUE;
  }
  // CL/CS `c.ld rd', off(rs1')` / `c.sd rs2', off(rs1')` — regs x8-x15, off a
  // multiple of 8 in 0..248 (uimm scaled). funct3=011 (ld) / 111 (sd), op=00.
  if (RvAsmStrEqI(mn, "c.ld") || RvAsmStrEqI(mn, "c.sd")) {
    rd = RvAsmRegTok(cc); // rd' (ld) or rs2' (sd)
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    imm = 0;
    if (!RvAsmImmTok(cc, &imm) && cc->token != '(') {
      Free(mn);
      LexExcept(cc, "Expecting off(reg) at ");
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
    if (rd < 8 || rd > 15 || rs1 < 8 || rs1 > 15) {
      Free(mn);
      LexExcept(cc, "c.ld/c.sd need registers x8-x15 (s0-s1/a0-a5) at ");
    }
    if (imm < 0 || imm > 248 || (imm & 7)) {
      Free(mn);
      LexExcept(cc, "c.ld/c.sd offset must be a multiple of 8 in 0..248 at ");
    }
    if (RvAsmStrEqI(mn, "c.ld"))
      word = 0x6000;
    else
      word = 0xE000;
    word |= (((imm >> 3) & 7) << 10) | ((rs1 - 8) << 7) | (((imm >> 6) & 3) << 5) | ((rd - 8) << 2);
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // ---- RVC increment 3: word ld/st, CB-arith, RV64 addiw, lui, sp-relative ----
  // All bit-field maps mechanically derived from GNU (-march=rv64imac) and validated
  // over their full operand ranges (10011 checks, 0 diffs).
  // CL/CS word: c.lw rd', off(rs1') / c.sw rs2', off(rs1') — x8-x15, off %4 in 0..124.
  if (RvAsmStrEqI(mn, "c.lw") || RvAsmStrEqI(mn, "c.sw")) {
    rd = RvAsmRegTok(cc); // rd' (lw) or rs2' (sw)
    if (cc->token != ',') { Free(mn); LexExcept(cc, "Expecting ',' at "); }
    Lex(cc);
    imm = 0;
    if (!RvAsmImmTok(cc, &imm) && cc->token != '(') { Free(mn); LexExcept(cc, "Expecting off(reg) at "); }
    if (cc->token != '(') { Free(mn); LexExcept(cc, "Expecting '(' at "); }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (cc->token != ')') { Free(mn); LexExcept(cc, "Expecting ')' at "); }
    Lex(cc);
    if (rd < 8 || rd > 15 || rs1 < 8 || rs1 > 15) { Free(mn); LexExcept(cc, "c.lw/c.sw need registers x8-x15 at "); }
    if (imm < 0 || imm > 124 || (imm & 3)) { Free(mn); LexExcept(cc, "c.lw/c.sw offset must be a multiple of 4 in 0..124 at "); }
    if (RvAsmStrEqI(mn, "c.lw")) word = 0x4000; else word = 0xC000;
    word |= (((rd - 8) & 7) << 2) | (((imm >> 6) & 1) << 5) | (((imm >> 2) & 1) << 6) | (((rs1 - 8) & 7) << 7) | (((imm >> 3) & 1) << 10) | (((imm >> 4) & 1) << 11) | (((imm >> 5) & 1) << 12);
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // CI RV64 add-word: c.addiw rd, imm — rd != x0, 6-bit signed imm.
  if (RvAsmStrEqI(mn, "c.addiw")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') { Free(mn); LexExcept(cc, "Expecting ',' at "); }
    Lex(cc);
    if (!RvAsmImmTok(cc, &imm)) { Free(mn); LexExcept(cc, "Expecting imm at "); }
    if (rd < 1) { Free(mn); LexExcept(cc, "c.addiw needs a non-zero register (x1-x31) at "); }
    if (imm < -32 || imm > 31) { Free(mn); LexExcept(cc, "c.addiw immediate out of range (need -32..31) at "); }
    word = 0x2001 | ((imm & 0x1F) << 2) | ((rd & 0x1F) << 7) | (((imm >> 5) & 1) << 12);
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // CB-arith: c.andi rd', imm (6-bit signed) / c.srli/c.srai rd', shamt (RV64 0..63).
  // rd' in x8-x15. funct2 [11:10]: srli=00, srai=01, andi=10.
  if (RvAsmStrEqI(mn, "c.andi") || RvAsmStrEqI(mn, "c.srli") || RvAsmStrEqI(mn, "c.srai")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') { Free(mn); LexExcept(cc, "Expecting ',' at "); }
    Lex(cc);
    if (!RvAsmImmTok(cc, &imm)) { Free(mn); LexExcept(cc, "Expecting imm at "); }
    if (rd < 8 || rd > 15) { Free(mn); LexExcept(cc, "c.andi/c.srli/c.srai need a register x8-x15 at "); }
    if (RvAsmStrEqI(mn, "c.andi")) {
      if (imm < -32 || imm > 31) { Free(mn); LexExcept(cc, "c.andi immediate out of range (need -32..31) at "); }
      word = 0x8801;
    } else {
      if (imm < 0 || imm > 63) { Free(mn); LexExcept(cc, "c.srli/c.srai shift amount out of range (need 0..63) at "); }
      if (RvAsmStrEqI(mn, "c.srli")) word = 0x8001; else word = 0x8401;
    }
    word |= ((imm & 0x1F) << 2) | (((rd - 8) & 7) << 7) | (((imm >> 5) & 1) << 12);
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // CI c.lui rd, imm — rd not in {x0,x2}; imm a NON-zero 6-bit signed field value
  // (-32..-1, 1..31), loaded as imm<<12 (same field-value convention as c.li).
  if (RvAsmStrEqI(mn, "c.lui")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') { Free(mn); LexExcept(cc, "Expecting ',' at "); }
    Lex(cc);
    if (!RvAsmImmTok(cc, &imm)) { Free(mn); LexExcept(cc, "Expecting imm at "); }
    if (rd < 1 || rd == 2) { Free(mn); LexExcept(cc, "c.lui destination must be x1 or x3-x31 (not x0/x2) at "); }
    if (imm == 0 || imm < -32 || imm > 31) { Free(mn); LexExcept(cc, "c.lui immediate must be non-zero in -32..31 (a 6-bit field; use c.addi16sp for sp) at "); }
    word = 0x6001 | ((imm & 0x1F) << 2) | ((rd & 0x1F) << 7) | (((imm >> 5) & 1) << 12);
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // CI c.addi16sp sp, imm — imm a NON-zero multiple of 16 in -512..496 (adjusts sp).
  if (RvAsmStrEqI(mn, "c.addi16sp")) {
    rs1 = RvAsmRegTok(cc);
    if (rs1 != 2) { Free(mn); LexExcept(cc, "c.addi16sp first operand must be sp at "); }
    if (cc->token != ',') { Free(mn); LexExcept(cc, "Expecting ',' at "); }
    Lex(cc);
    if (!RvAsmImmTok(cc, &imm)) { Free(mn); LexExcept(cc, "Expecting imm at "); }
    if (imm == 0 || imm < -512 || imm > 496 || (imm & 15)) { Free(mn); LexExcept(cc, "c.addi16sp immediate must be a non-zero multiple of 16 in -512..496 at "); }
    word = 0x6101 | (((imm >> 5) & 1) << 2) | (((imm >> 7) & 1) << 3) | (((imm >> 8) & 1) << 4) | (((imm >> 6) & 1) << 5) | (((imm >> 4) & 1) << 6) | (((imm >> 9) & 1) << 12);
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // CIW c.addi4spn rd', sp, uimm — rd' in x8-x15, uimm a NON-zero multiple of 4 in 4..1020.
  if (RvAsmStrEqI(mn, "c.addi4spn")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') { Free(mn); LexExcept(cc, "Expecting ',' at "); }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (rs1 != 2) { Free(mn); LexExcept(cc, "c.addi4spn second operand must be sp at "); }
    if (cc->token != ',') { Free(mn); LexExcept(cc, "Expecting ',' at "); }
    Lex(cc);
    if (!RvAsmImmTok(cc, &imm)) { Free(mn); LexExcept(cc, "Expecting imm at "); }
    if (rd < 8 || rd > 15) { Free(mn); LexExcept(cc, "c.addi4spn needs a register x8-x15 at "); }
    if (imm <= 0 || imm > 1020 || (imm & 3)) { Free(mn); LexExcept(cc, "c.addi4spn immediate must be a non-zero multiple of 4 in 4..1020 at "); }
    word = (((rd - 8) & 7) << 2) | (((imm >> 3) & 1) << 5) | (((imm >> 2) & 1) << 6) | (((imm >> 6) & 1) << 7) | (((imm >> 7) & 1) << 8) | (((imm >> 8) & 1) << 9) | (((imm >> 9) & 1) << 10) | (((imm >> 4) & 1) << 11) | (((imm >> 5) & 1) << 12);
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // CI sp-relative loads: c.lwsp rd, off(sp) (off %4, 0..252) / c.ldsp rd, off(sp)
  // (off %8, 0..504). rd != x0.
  if (RvAsmStrEqI(mn, "c.lwsp") || RvAsmStrEqI(mn, "c.ldsp")) {
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') { Free(mn); LexExcept(cc, "Expecting ',' at "); }
    Lex(cc);
    imm = 0;
    if (!RvAsmImmTok(cc, &imm) && cc->token != '(') { Free(mn); LexExcept(cc, "Expecting off(sp) at "); }
    if (cc->token != '(') { Free(mn); LexExcept(cc, "Expecting '(' at "); }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (cc->token != ')') { Free(mn); LexExcept(cc, "Expecting ')' at "); }
    Lex(cc);
    if (rd < 1) { Free(mn); LexExcept(cc, "c.lwsp/c.ldsp need a non-zero register (x1-x31) at "); }
    if (rs1 != 2) { Free(mn); LexExcept(cc, "c.lwsp/c.ldsp base must be sp at "); }
    if (RvAsmStrEqI(mn, "c.lwsp")) {
      if (imm < 0 || imm > 252 || (imm & 3)) { Free(mn); LexExcept(cc, "c.lwsp offset must be a multiple of 4 in 0..252 at "); }
      word = 0x4002 | (((imm >> 6) & 1) << 2) | (((imm >> 7) & 1) << 3) | (((imm >> 2) & 1) << 4) | (((imm >> 3) & 1) << 5) | (((imm >> 4) & 1) << 6) | ((rd & 0x1F) << 7) | (((imm >> 5) & 1) << 12);
    } else {
      if (imm < 0 || imm > 504 || (imm & 7)) { Free(mn); LexExcept(cc, "c.ldsp offset must be a multiple of 8 in 0..504 at "); }
      word = 0x6002 | (((imm >> 6) & 1) << 2) | (((imm >> 7) & 1) << 3) | (((imm >> 8) & 1) << 4) | (((imm >> 3) & 1) << 5) | (((imm >> 4) & 1) << 6) | ((rd & 0x1F) << 7) | (((imm >> 5) & 1) << 12);
    }
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // CSS sp-relative stores: c.swsp rs2, off(sp) (off %4, 0..252) / c.sdsp rs2, off(sp)
  // (off %8, 0..504). rs2 is any x0-x31.
  if (RvAsmStrEqI(mn, "c.swsp") || RvAsmStrEqI(mn, "c.sdsp")) {
    rs2 = RvAsmRegTok(cc);
    if (cc->token != ',') { Free(mn); LexExcept(cc, "Expecting ',' at "); }
    Lex(cc);
    imm = 0;
    if (!RvAsmImmTok(cc, &imm) && cc->token != '(') { Free(mn); LexExcept(cc, "Expecting off(sp) at "); }
    if (cc->token != '(') { Free(mn); LexExcept(cc, "Expecting '(' at "); }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (cc->token != ')') { Free(mn); LexExcept(cc, "Expecting ')' at "); }
    Lex(cc);
    if (rs2 < 0) { Free(mn); LexExcept(cc, "Bad register at "); }
    if (rs1 != 2) { Free(mn); LexExcept(cc, "c.swsp/c.sdsp base must be sp at "); }
    if (RvAsmStrEqI(mn, "c.swsp")) {
      if (imm < 0 || imm > 252 || (imm & 3)) { Free(mn); LexExcept(cc, "c.swsp offset must be a multiple of 4 in 0..252 at "); }
      word = 0xC002 | ((rs2 & 0x1F) << 2) | (((imm >> 6) & 1) << 7) | (((imm >> 7) & 1) << 8) | (((imm >> 2) & 1) << 9) | (((imm >> 3) & 1) << 10) | (((imm >> 4) & 1) << 11) | (((imm >> 5) & 1) << 12);
    } else {
      if (imm < 0 || imm > 504 || (imm & 7)) { Free(mn); LexExcept(cc, "c.sdsp offset must be a multiple of 8 in 0..504 at "); }
      word = 0xE002 | ((rs2 & 0x1F) << 2) | (((imm >> 6) & 1) << 7) | (((imm >> 7) & 1) << 8) | (((imm >> 8) & 1) << 9) | (((imm >> 3) & 1) << 10) | (((imm >> 4) & 1) << 11) | (((imm >> 5) & 1) << 12);
    }
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // ---- RVC increment 4: float-compressed doubleword loads/stores (RV64 D) ----
  // Field maps validated vs GNU (-march=rv64imafdc, 4736 checks, 0 diffs).
  // CL/CS float: c.fld frd', off(rs1') / c.fsd frs2', off(rs1') — DATA reg is a FLOAT
  // in f8-f15 (subset), BASE rs1' an INTEGER in x8-x15, off %8 in 0..248.
  if (RvAsmStrEqI(mn, "c.fld") || RvAsmStrEqI(mn, "c.fsd")) {
    first = RvAsmFRegTok(cc); // float rd' (load) or rs2' (store)
    if (cc->token != ',') { Free(mn); LexExcept(cc, "Expecting ',' at "); }
    Lex(cc);
    imm = 0;
    if (!RvAsmImmTok(cc, &imm) && cc->token != '(') { Free(mn); LexExcept(cc, "Expecting off(reg) at "); }
    if (cc->token != '(') { Free(mn); LexExcept(cc, "Expecting '(' at "); }
    Lex(cc);
    rs1 = RvAsmRegTok(cc); // integer base
    if (cc->token != ')') { Free(mn); LexExcept(cc, "Expecting ')' at "); }
    Lex(cc);
    if (first < 8 || first > 15) { Free(mn); LexExcept(cc, "c.fld/c.fsd float register must be f8-f15 (fs0-fs1/fa0-fa5) at "); }
    if (rs1 < 8 || rs1 > 15) { Free(mn); LexExcept(cc, "c.fld/c.fsd base register must be x8-x15 at "); }
    if (imm < 0 || imm > 248 || (imm & 7)) { Free(mn); LexExcept(cc, "c.fld/c.fsd offset must be a multiple of 8 in 0..248 at "); }
    if (RvAsmStrEqI(mn, "c.fld")) word = 0x2000; else word = 0xA000;
    word |= (((first - 8) & 7) << 2) | (((imm >> 6) & 3) << 5) | (((rs1 - 8) & 7) << 7) | (((imm >> 3) & 7) << 10);
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  // CI/CSS float sp-relative: c.fldsp frd, off(sp) / c.fsdsp frs2, off(sp) — full
  // float reg f0-f31, base sp, off %8 in 0..504.
  if (RvAsmStrEqI(mn, "c.fldsp") || RvAsmStrEqI(mn, "c.fsdsp")) {
    first = RvAsmFRegTok(cc); // float rd (load) or rs2 (store)
    if (cc->token != ',') { Free(mn); LexExcept(cc, "Expecting ',' at "); }
    Lex(cc);
    imm = 0;
    if (!RvAsmImmTok(cc, &imm) && cc->token != '(') { Free(mn); LexExcept(cc, "Expecting off(sp) at "); }
    if (cc->token != '(') { Free(mn); LexExcept(cc, "Expecting '(' at "); }
    Lex(cc);
    rs1 = RvAsmRegTok(cc);
    if (cc->token != ')') { Free(mn); LexExcept(cc, "Expecting ')' at "); }
    Lex(cc);
    if (first < 0 || first > 31) { Free(mn); LexExcept(cc, "Bad float register at "); }
    if (rs1 != 2) { Free(mn); LexExcept(cc, "c.fldsp/c.fsdsp base must be sp at "); }
    if (imm < 0 || imm > 504 || (imm & 7)) { Free(mn); LexExcept(cc, "c.fldsp/c.fsdsp offset must be a multiple of 8 in 0..504 at "); }
    if (RvAsmStrEqI(mn, "c.fldsp"))
      word = 0x2002 | (((imm >> 6) & 1) << 2) | (((imm >> 7) & 1) << 3) | (((imm >> 8) & 1) << 4) | (((imm >> 3) & 1) << 5) | (((imm >> 4) & 1) << 6) | ((first & 0x1F) << 7) | (((imm >> 5) & 1) << 12);
    else
      word = 0xA002 | ((first & 0x1F) << 2) | (((imm >> 6) & 1) << 7) | (((imm >> 7) & 1) << 8) | (((imm >> 8) & 1) << 9) | (((imm >> 3) & 1) << 10) | (((imm >> 4) & 1) << 11) | (((imm >> 5) & 1) << 12);
    Free(mn);
    AOTStoreCodeU16(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "mv") || RvAsmStrEqI(mn, "not") || RvAsmStrEqI(mn, "neg") || RvAsmStrEqI(mn, "seqz") || RvAsmStrEqI(mn, "snez")) {
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
    else if (RvAsmStrEqI(mn, "neg"))
      word = RvAsmR(0x20, 0, rd, 0, rs1);
    else if (RvAsmStrEqI(mn, "seqz"))
      word = RvAsmI(3, rd, rs1, 1); // sltiu rd, rs, 1
    else
      word = RvAsmR(0, 3, rd, 0, rs1); // snez -> sltu rd, x0, rs
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
  is_imm = RvAsmStrEqI(mn, "addi") || RvAsmStrEqI(mn, "andi") || RvAsmStrEqI(mn, "ori") || RvAsmStrEqI(mn, "xori") || RvAsmStrEqI(mn, "slti") || RvAsmStrEqI(mn, "sltiu") || RvAsmStrEqI(mn, "slli") || RvAsmStrEqI(mn, "srli") || RvAsmStrEqI(mn, "srai");
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
    else if (RvAsmStrEqI(mn, "sltiu"))
      word = RvAsmI(3, rd, rs1, imm);
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
  if (RvAsmStrEqI(mn, "add") || RvAsmStrEqI(mn, "sub") || RvAsmStrEqI(mn, "and") || RvAsmStrEqI(mn, "or") || RvAsmStrEqI(mn, "xor") || RvAsmStrEqI(mn, "sll") || RvAsmStrEqI(mn, "srl") || RvAsmStrEqI(mn, "sra") || RvAsmStrEqI(mn, "slt") || RvAsmStrEqI(mn, "sltu") || RvAsmStrEqI(mn, "mul") || RvAsmStrEqI(mn, "mulh") || RvAsmStrEqI(mn, "mulhsu") || RvAsmStrEqI(mn, "mulhu") || RvAsmStrEqI(mn, "div") || RvAsmStrEqI(mn, "rem") || RvAsmStrEqI(mn, "divu") || RvAsmStrEqI(mn, "remu")) {
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
    else if (RvAsmStrEqI(mn, "mulh"))
      word = RvAsmR(1, 1, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "mulhsu"))
      word = RvAsmR(1, 2, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "mulhu"))
      word = RvAsmR(1, 3, rd, rs1, rs2);
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
  // OP-IMM-32 word immediates (RV64): addiw (12-bit signed), slliw/srliw/sraiw (5-bit shamt).
  if (RvAsmStrEqI(mn, "addiw") || RvAsmStrEqI(mn, "slliw") || RvAsmStrEqI(mn, "srliw") || RvAsmStrEqI(mn, "sraiw")) {
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
    if (RvAsmStrEqI(mn, "addiw")) {
      if (!RvAsmFitsSimm12(imm)) {
        Free(mn);
        LexExcept(cc, "immediate out of range for 12-bit signed field (need -2048..2047; use li) at ");
      }
      word = RvAsmIw(0, rd, rs1, imm);
    } else {
      if (imm < 0 || imm > 31) {
        Free(mn);
        LexExcept(cc, "word shift amount out of range (need 0..31) at ");
      }
      if (RvAsmStrEqI(mn, "slliw"))
        word = 0x1B | (rd << 7) | (1 << 12) | (rs1 << 15) | ((imm & 0x1F) << 20);
      else if (RvAsmStrEqI(mn, "srliw"))
        word = 0x1B | (rd << 7) | (5 << 12) | (rs1 << 15) | ((imm & 0x1F) << 20);
      else
        word = 0x1B | (rd << 7) | (5 << 12) | (rs1 << 15) | ((imm & 0x1F) << 20) | (0x20 << 25);
    }
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  // OP-32 word R-type (RV64): addw subw sllw srlw sraw mulw divw divuw remw remuw.
  if (RvAsmStrEqI(mn, "addw") || RvAsmStrEqI(mn, "subw") || RvAsmStrEqI(mn, "sllw") || RvAsmStrEqI(mn, "srlw") || RvAsmStrEqI(mn, "sraw") || RvAsmStrEqI(mn, "mulw") || RvAsmStrEqI(mn, "divw") || RvAsmStrEqI(mn, "divuw") || RvAsmStrEqI(mn, "remw") || RvAsmStrEqI(mn, "remuw")) {
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
      Free(mn);
      LexExcept(cc, "R-type word op needs register rs2, not immediate at ");
    }
    rs2 = RvAsmRegTok(cc);
    if (rd < 0 || rs1 < 0 || rs2 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (RvAsmStrEqI(mn, "addw"))
      word = RvAsmRw(0, 0, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "subw"))
      word = RvAsmRw(0x20, 0, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "sllw"))
      word = RvAsmRw(0, 1, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "srlw"))
      word = RvAsmRw(0, 5, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "sraw"))
      word = RvAsmRw(0x20, 5, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "mulw"))
      word = RvAsmRw(1, 0, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "divw"))
      word = RvAsmRw(1, 4, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "divuw"))
      word = RvAsmRw(1, 5, rd, rs1, rs2);
    else if (RvAsmStrEqI(mn, "remw"))
      word = RvAsmRw(1, 6, rd, rs1, rs2);
    else
      word = RvAsmRw(1, 7, rd, rs1, rs2);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  // fence [pred, succ] — memory-ordering barrier. Bare fence = iorw,iorw (full barrier).
  // Pred/succ are i/o/r/w letter masks. Operands are detected by a trailing mask token;
  // in single-pass streaming this relies on the ';'/'}' between instructions (REPL form).
  if (RvAsmStrEqI(mn, "fence")) {
    imm = 0xFF; // default fm=0, pred=succ=iorw
    if (cc->token == TK_IDENT && cc->cur_str) {
      first = RvAsmFenceMask(cc->cur_str); // pred
      if (first < 0) {
        Free(mn);
        LexExcept(cc, "bad fence predecessor mask (use i/o/r/w) at ");
      }
      Lex(cc);
      if (cc->token != ',') {
        Free(mn);
        LexExcept(cc, "Expecting ',' between fence pred,succ at ");
      }
      Lex(cc);
      if (cc->token != TK_IDENT || !cc->cur_str) {
        Free(mn);
        LexExcept(cc, "Expecting fence successor mask at ");
      }
      rs2 = RvAsmFenceMask(cc->cur_str); // succ
      if (rs2 < 0) {
        Free(mn);
        LexExcept(cc, "bad fence successor mask (use i/o/r/w) at ");
      }
      Lex(cc);
      imm = (first << 4) | rs2;
    }
    Free(mn);
    AOTStoreCodeU32(cc, 0x0F | ((imm & 0xFFF) << 20));
    return TRUE;
  }
  // sfence.vma [rs1[, rs2]] — flush address translation (bare = zero,zero = flush all).
  if (RvAsmStrEqI(mn, "sfence.vma") || RvAsmStrEqI(mn, "sfencevma")) {
    rs1 = 0;
    rs2 = 0;
    if (cc->token == TK_IDENT && cc->cur_str) {
      rs1 = RvAsmRegTok(cc);
      if (rs1 < 0) {
        Free(mn);
        LexExcept(cc, "Bad register at ");
      }
      if (cc->token == ',') {
        Lex(cc);
        rs2 = RvAsmRegTok(cc);
        if (rs2 < 0) {
          Free(mn);
          LexExcept(cc, "Bad register at ");
        }
      }
    }
    Free(mn);
    AOTStoreCodeU32(cc, 0x12000073 | (rs2 << 20) | (rs1 << 15));
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "fld") || RvAsmStrEqI(mn, "fsd") || RvAsmStrEqI(mn, "flw") || RvAsmStrEqI(mn, "fsw")) {
    // fld/flw frd, imm(rs1) | fsd/fsw frs2, imm(rs1). Value reg is FLOAT; base rs1 INTEGER.
    // Loads opcode 0x07, stores 0x27; f3=3 for .d (fld/fsd), f3=2 for .w (flw/fsw).
    first = RvAsmFRegTok(cc); // float rd (load) or rs2 (store)
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
    rs1 = RvAsmRegTok(cc); // integer base
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
    if (RvAsmStrEqI(mn, "fld"))
      word = 0x07 | (first << 7) | (3 << 12) | (rs1 << 15) | ((imm & 0xFFF) << 20);
    else if (RvAsmStrEqI(mn, "flw"))
      word = 0x07 | (first << 7) | (2 << 12) | (rs1 << 15) | ((imm & 0xFFF) << 20);
    else if (RvAsmStrEqI(mn, "fsd"))
      word = 0x27 | ((imm & 0x1F) << 7) | (3 << 12) | (rs1 << 15) | (first << 20) | (((imm >> 5) & 0x7F) << 25);
    else
      word = 0x27 | ((imm & 0x1F) << 7) | (2 << 12) | (rs1 << 15) | (first << 20) | (((imm >> 5) & 0x7F) << 25);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "ld") || RvAsmStrEqI(mn, "lw") || RvAsmStrEqI(mn, "lwu") || RvAsmStrEqI(mn, "lh") || RvAsmStrEqI(mn, "lhu") || RvAsmStrEqI(mn, "lb") || RvAsmStrEqI(mn, "lbu") || RvAsmStrEqI(mn, "sd") || RvAsmStrEqI(mn, "sw") || RvAsmStrEqI(mn, "sh") || RvAsmStrEqI(mn, "sb")) {
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
    // Loads (opcode 0x03): f3 lb=0 lh=1 lw=2 ld=3 lbu=4 lhu=5 lwu=6.
    // Stores (opcode 0x23): f3 sb=0 sh=1 sw=2 sd=3.
    if (RvAsmStrEqI(mn, "lb"))
      word = RvAsmLoad(0, first, imm, rs1);
    else if (RvAsmStrEqI(mn, "lh"))
      word = RvAsmLoad(1, first, imm, rs1);
    else if (RvAsmStrEqI(mn, "lw"))
      word = RvAsmLoad(2, first, imm, rs1);
    else if (RvAsmStrEqI(mn, "ld"))
      word = RvAsmLoad(3, first, imm, rs1);
    else if (RvAsmStrEqI(mn, "lbu"))
      word = RvAsmLoad(4, first, imm, rs1);
    else if (RvAsmStrEqI(mn, "lhu"))
      word = RvAsmLoad(5, first, imm, rs1);
    else if (RvAsmStrEqI(mn, "lwu"))
      word = RvAsmLoad(6, first, imm, rs1);
    else if (RvAsmStrEqI(mn, "sb"))
      word = RvAsmStore(0, first, imm, rs1);
    else if (RvAsmStrEqI(mn, "sh"))
      word = RvAsmStore(1, first, imm, rs1);
    else if (RvAsmStrEqI(mn, "sw"))
      word = RvAsmStore(2, first, imm, rs1);
    else
      word = RvAsmStore(3, first, imm, rs1);
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
    if (rs1 < 0 || rs2 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    // Target: numeric offset, a backward label (resolved now), or a forward label
    // (placeholder + fixup at block end).
    tgt = RvAsmBrTarget(cc, &imm, &fwdname);
    if (!tgt) {
      Free(mn);
      LexExcept(cc, "Expecting branch offset or label at ");
    }
    Free(mn);
    if (tgt == 2) {
      RvAsmFixupAdd(cc, RvAsmB(first, rs1, rs2, 0), 1, fwdname);
      AOTStoreCodeU32(cc, RvAsmB(first, rs1, rs2, 0));
      return TRUE;
    }
    if (!RvAsmFitsBimm(imm))
      LexExcept(cc, "branch offset out of range (need even, -4096..4094; PC-relative) at ");
    AOTStoreCodeU32(cc, RvAsmB(first, rs1, rs2, imm));
    return TRUE;
  }
  // jal (J-type PC-relative offset), jr (jalr x0,rs,0). We deliberately do NOT
  // define a numeric-offset `j`: the host asm{} parser defines `j label` as
  // label-only, so a guest `j 8` would give the same mnemonic two meanings.
  // Use `jal x0,off` for an unconditional numeric-offset jump.
  if (RvAsmStrEqI(mn, "j")) {
    // `j off|label` = jal x0, target (unconditional jump, no link). Numeric offset or label.
    tgt = RvAsmBrTarget(cc, &imm, &fwdname);
    if (!tgt) {
      Free(mn);
      LexExcept(cc, "Expecting jump offset or label at ");
    }
    Free(mn);
    if (tgt == 2) {
      RvAsmFixupAdd(cc, RvAsmJ(0, 0), 0, fwdname);
      AOTStoreCodeU32(cc, RvAsmJ(0, 0));
      return TRUE;
    }
    if (!RvAsmFitsJimm(imm))
      LexExcept(cc, "jump offset out of range (need even, -1MiB..+1MiB-2; PC-relative) at ");
    AOTStoreCodeU32(cc, RvAsmJ(0, imm));
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "jal")) {
    // Forms: `jal off|label` (rd=ra), `jal rd, off|label`. A leading register name
    // followed by ',' selects the two-operand form; anything else is a target.
    if (cc->token == TK_IDENT && RvAsmRegNum(cc->cur_str) >= 0) {
      rd = RvAsmRegTok(cc);
      if (cc->token != ',') {
        Free(mn);
        LexExcept(cc, "Expecting ',' at ");
      }
      Lex(cc);
    } else {
      rd = 1; // `jal off|label` implies rd=ra
    }
    tgt = RvAsmBrTarget(cc, &imm, &fwdname);
    if (!tgt) {
      Free(mn);
      LexExcept(cc, "Expecting jump offset or label at ");
    }
    if (rd < 0) {
      if (fwdname)
        Free(fwdname);
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    Free(mn);
    if (tgt == 2) {
      RvAsmFixupAdd(cc, RvAsmJ(rd, 0), 0, fwdname);
      AOTStoreCodeU32(cc, RvAsmJ(rd, 0));
      return TRUE;
    }
    if (!RvAsmFitsJimm(imm))
      LexExcept(cc, "jump offset out of range (need even, -1MiB..+1MiB-2; PC-relative) at ");
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
  // RV64D float (dot-free names matching the doc catalog + host). Encodings copied
  // verbatim from the GNU-tested host (host/parser.c:4430-4443). The operand register
  // FILE differs per op (FPR vs GPR) - mirror it exactly; a swap silently misreads.
  if (RvAsmStrEqI(mn, "fsqrtd") || RvAsmStrEqI(mn, "fsqrt.s") || RvAsmStrEqI(mn, "fcvt.s.d") || RvAsmStrEqI(mn, "fcvt.d.s")) { // fd, fs  (both FPR)
    rd = RvAsmFRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmFRegTok(cc);
    if (rd < 0 || rs1 < 0) {
      Free(mn);
      LexExcept(cc, "Bad float register at ");
    }
    if (!RvAsmStrEqI(mn, "fcvt.d.s")) { // fcvt.d.s is exact (no rm); the others round
      tgt = RvAsmParseOptRm(cc);
      if (tgt >= 0)
        rm = tgt;
    }
    if (RvAsmStrEqI(mn, "fcvt.s.d"))
      word = 0x40000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (1 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.d.s"))
      word = 0x42000053 | (rd << 7) | (0 << 12) | (rs1 << 15) | (0 << 20);
    else if (RvAsmStrEqI(mn, "fsqrt.s"))
      word = 0x58000053 | (rd << 7) | (rm << 12) | (rs1 << 15);
    else
      word = 0x5A000053 | (rd << 7) | (rm << 12) | (rs1 << 15);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "faddd") || RvAsmStrEqI(mn, "fsubd") || RvAsmStrEqI(mn, "fmuld") || RvAsmStrEqI(mn, "fdivd")) { // fd, fs1, fs2  (all FPR)
    rd = RvAsmFRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmFRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs2 = RvAsmFRegTok(cc);
    if (rd < 0 || rs1 < 0 || rs2 < 0) {
      Free(mn);
      LexExcept(cc, "Bad float register at ");
    }
    tgt = RvAsmParseOptRm(cc);
    if (tgt >= 0)
      rm = tgt;
    if (RvAsmStrEqI(mn, "faddd"))
      word = 0x02000053;
    else if (RvAsmStrEqI(mn, "fsubd"))
      word = 0x0A000053;
    else if (RvAsmStrEqI(mn, "fmuld"))
      word = 0x12000053;
    else
      word = 0x1A000053;
    word = word | (rd << 7) | (rm << 12) | (rs1 << 15) | (rs2 << 20);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  // 3-FPR ops: D sign/minmax (0x22/0x2A) and F32 arith+sign+minmax (0x00..0x28). rm=dyn where used.
  if (RvAsmStrEqI(mn, "fsgnj.d") || RvAsmStrEqI(mn, "fsgnjn.d") || RvAsmStrEqI(mn, "fsgnjx.d") || RvAsmStrEqI(mn, "fmin.d") || RvAsmStrEqI(mn, "fmax.d") ||
      RvAsmStrEqI(mn, "fadd.s") || RvAsmStrEqI(mn, "fsub.s") || RvAsmStrEqI(mn, "fmul.s") || RvAsmStrEqI(mn, "fdiv.s") ||
      RvAsmStrEqI(mn, "fsgnj.s") || RvAsmStrEqI(mn, "fsgnjn.s") || RvAsmStrEqI(mn, "fsgnjx.s") || RvAsmStrEqI(mn, "fmin.s") || RvAsmStrEqI(mn, "fmax.s")) {
    rd = RvAsmFRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmFRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs2 = RvAsmFRegTok(cc);
    if (rd < 0 || rs1 < 0 || rs2 < 0) {
      Free(mn);
      LexExcept(cc, "Bad float register at ");
    }
    if (RvAsmStrEqI(mn, "fadd.s") || RvAsmStrEqI(mn, "fsub.s") || RvAsmStrEqI(mn, "fmul.s") || RvAsmStrEqI(mn, "fdiv.s")) {
      tgt = RvAsmParseOptRm(cc);
      if (tgt >= 0)
        rm = tgt;
    }
    if (RvAsmStrEqI(mn, "fsgnj.d"))
      word = 0x22000053 | (rd << 7) | (0 << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fsgnjn.d"))
      word = 0x22000053 | (rd << 7) | (1 << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fsgnjx.d"))
      word = 0x22000053 | (rd << 7) | (2 << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fmin.d"))
      word = 0x2A000053 | (rd << 7) | (0 << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fmax.d"))
      word = 0x2A000053 | (rd << 7) | (1 << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fadd.s"))
      word = 0x00000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fsub.s"))
      word = 0x08000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fmul.s"))
      word = 0x10000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fdiv.s"))
      word = 0x18000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fsgnj.s"))
      word = 0x20000053 | (rd << 7) | (0 << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fsgnjn.s"))
      word = 0x20000053 | (rd << 7) | (1 << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fsgnjx.s"))
      word = 0x20000053 | (rd << 7) | (2 << 12) | (rs1 << 15) | (rs2 << 20);
    else if (RvAsmStrEqI(mn, "fmin.s"))
      word = 0x28000053 | (rd << 7) | (0 << 12) | (rs1 << 15) | (rs2 << 20);
    else
      word = 0x28000053 | (rd << 7) | (1 << 12) | (rs1 << 15) | (rs2 << 20);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  // Fused multiply-add (R4-type): 4 FPR operands fd, fs1, fs2, fs3. rm=dyn.
  // opcode fmadd=0x43 fmsub=0x47 fnmsub=0x4B fnmadd=0x4F; fmt bit 25: .d=1, .s=0.
  if (RvAsmStrEqI(mn, "fmadd.d") || RvAsmStrEqI(mn, "fmsub.d") || RvAsmStrEqI(mn, "fnmsub.d") || RvAsmStrEqI(mn, "fnmadd.d") ||
      RvAsmStrEqI(mn, "fmadd.s") || RvAsmStrEqI(mn, "fmsub.s") || RvAsmStrEqI(mn, "fnmsub.s") || RvAsmStrEqI(mn, "fnmadd.s")) {
    rd = RvAsmFRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmFRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs2 = RvAsmFRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    imm = RvAsmFRegTok(cc); // rs3
    if (rd < 0 || rs1 < 0 || rs2 < 0 || imm < 0) {
      Free(mn);
      LexExcept(cc, "Bad float register at ");
    }
    tgt = RvAsmParseOptRm(cc);
    if (tgt >= 0)
      rm = tgt;
    if (RvAsmStrEqI(mn, "fmadd.d"))
      word = 0x02000043;
    else if (RvAsmStrEqI(mn, "fmsub.d"))
      word = 0x02000047;
    else if (RvAsmStrEqI(mn, "fnmsub.d"))
      word = 0x0200004B;
    else if (RvAsmStrEqI(mn, "fnmadd.d"))
      word = 0x0200004F;
    else if (RvAsmStrEqI(mn, "fmadd.s"))
      word = 0x00000043;
    else if (RvAsmStrEqI(mn, "fmsub.s"))
      word = 0x00000047;
    else if (RvAsmStrEqI(mn, "fnmsub.s"))
      word = 0x0000004B;
    else
      word = 0x0000004F;
    word = word | (rd << 7) | (rm << 12) | (rs1 << 15) | (rs2 << 20) | (imm << 27);
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "fled") || RvAsmStrEqI(mn, "fltd") || RvAsmStrEqI(mn, "feqd") ||
      RvAsmStrEqI(mn, "fle.s") || RvAsmStrEqI(mn, "flt.s") || RvAsmStrEqI(mn, "feq.s")) { // rd(GPR), fs1, fs2 (FPR) -> 0/1
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmFRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs2 = RvAsmFRegTok(cc);
    if (rd < 0 || rs1 < 0 || rs2 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (RvAsmStrEqI(mn, "fled") || RvAsmStrEqI(mn, "fle.s"))
      first = 0;
    else if (RvAsmStrEqI(mn, "fltd") || RvAsmStrEqI(mn, "flt.s"))
      first = 1;
    else
      first = 2;
    if (RvAsmStrEqI(mn, "fle.s") || RvAsmStrEqI(mn, "flt.s") || RvAsmStrEqI(mn, "feq.s"))
      word = 0xA0000053;
    else
      word = 0xA2000053;
    Free(mn);
    AOTStoreCodeU32(cc, word | (rd << 7) | (first << 12) | (rs1 << 15) | (rs2 << 20));
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "fmvdx") || RvAsmStrEqI(mn, "fcvtdl") || RvAsmStrEqI(mn, "fcvt.d.w") || RvAsmStrEqI(mn, "fcvt.d.wu") || RvAsmStrEqI(mn, "fcvt.d.l") || RvAsmStrEqI(mn, "fcvt.d.lu") ||
      RvAsmStrEqI(mn, "fmv.w.x") || RvAsmStrEqI(mn, "fcvt.s.w") || RvAsmStrEqI(mn, "fcvt.s.wu") || RvAsmStrEqI(mn, "fcvt.s.l") || RvAsmStrEqI(mn, "fcvt.s.lu")) { // fd(FPR), rs(GPR)
    rd = RvAsmFRegTok(cc);
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
    if (RvAsmStrEqI(mn, "fcvt.d.l") || RvAsmStrEqI(mn, "fcvt.d.lu") || RvAsmStrEqI(mn, "fcvt.s.w") || RvAsmStrEqI(mn, "fcvt.s.wu") || RvAsmStrEqI(mn, "fcvt.s.l") || RvAsmStrEqI(mn, "fcvt.s.lu")) {
      tgt = RvAsmParseOptRm(cc);
      if (tgt >= 0)
        rm = tgt;
    }
    if (RvAsmStrEqI(mn, "fmvdx"))
      word = 0xF2000053 | (rd << 7) | (rs1 << 15);
    else if (RvAsmStrEqI(mn, "fcvt.d.w"))
      word = 0xD2000053 | (rd << 7) | (0 << 12) | (rs1 << 15) | (0 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.d.wu"))
      word = 0xD2000053 | (rd << 7) | (0 << 12) | (rs1 << 15) | (1 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.d.lu"))
      word = 0xD2000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (3 << 20);
    else if (RvAsmStrEqI(mn, "fmv.w.x"))
      word = 0xF0000053 | (rd << 7) | (0 << 12) | (rs1 << 15);
    else if (RvAsmStrEqI(mn, "fcvt.s.w"))
      word = 0xD0000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (0 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.s.wu"))
      word = 0xD0000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (1 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.s.l"))
      word = 0xD0000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (2 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.s.lu"))
      word = 0xD0000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (3 << 20);
    else
      word = 0xD2000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (2 << 20); // fcvtdl == fcvt.d.l
    Free(mn);
    AOTStoreCodeU32(cc, word);
    return TRUE;
  }
  if (RvAsmStrEqI(mn, "fmvxd") || RvAsmStrEqI(mn, "fclass.d") || RvAsmStrEqI(mn, "fcvtld_rtz") || RvAsmStrEqI(mn, "fcvtld_rdn") || RvAsmStrEqI(mn, "fcvtld_rmm") || RvAsmStrEqI(mn, "fcvt.w.d") || RvAsmStrEqI(mn, "fcvt.wu.d") || RvAsmStrEqI(mn, "fcvt.l.d") || RvAsmStrEqI(mn, "fcvt.lu.d") ||
      RvAsmStrEqI(mn, "fmv.x.w") || RvAsmStrEqI(mn, "fclass.s") || RvAsmStrEqI(mn, "fcvt.w.s") || RvAsmStrEqI(mn, "fcvt.wu.s") || RvAsmStrEqI(mn, "fcvt.l.s") || RvAsmStrEqI(mn, "fcvt.lu.s")) { // rd(GPR), fs(FPR)
    rd = RvAsmRegTok(cc);
    if (cc->token != ',') {
      Free(mn);
      LexExcept(cc, "Expecting ',' at ");
    }
    Lex(cc);
    rs1 = RvAsmFRegTok(cc);
    if (rd < 0 || rs1 < 0) {
      Free(mn);
      LexExcept(cc, "Bad register at ");
    }
    if (RvAsmStrEqI(mn, "fcvt.w.d") || RvAsmStrEqI(mn, "fcvt.wu.d") || RvAsmStrEqI(mn, "fcvt.l.d") || RvAsmStrEqI(mn, "fcvt.lu.d") || RvAsmStrEqI(mn, "fcvt.w.s") || RvAsmStrEqI(mn, "fcvt.wu.s") || RvAsmStrEqI(mn, "fcvt.l.s") || RvAsmStrEqI(mn, "fcvt.lu.s")) {
      tgt = RvAsmParseOptRm(cc);
      if (tgt >= 0)
        rm = tgt;
    }
    if (RvAsmStrEqI(mn, "fmvxd"))
      word = 0xE2000053 | (rd << 7) | (rs1 << 15);
    else if (RvAsmStrEqI(mn, "fclass.d"))
      word = 0xE2000053 | (rd << 7) | (1 << 12) | (rs1 << 15);
    else if (RvAsmStrEqI(mn, "fcvtld_rtz"))
      word = 0xC2000053 | (rd << 7) | (1 << 12) | (rs1 << 15) | (2 << 20);
    else if (RvAsmStrEqI(mn, "fcvtld_rdn"))
      word = 0xC2000053 | (rd << 7) | (2 << 12) | (rs1 << 15) | (2 << 20);
    else if (RvAsmStrEqI(mn, "fcvtld_rmm"))
      word = 0xC2000053 | (rd << 7) | (4 << 12) | (rs1 << 15) | (2 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.w.d"))
      word = 0xC2000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (0 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.wu.d"))
      word = 0xC2000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (1 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.l.d"))
      word = 0xC2000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (2 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.lu.d"))
      word = 0xC2000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (3 << 20);
    else if (RvAsmStrEqI(mn, "fmv.x.w"))
      word = 0xE0000053 | (rd << 7) | (0 << 12) | (rs1 << 15);
    else if (RvAsmStrEqI(mn, "fclass.s"))
      word = 0xE0000053 | (rd << 7) | (1 << 12) | (rs1 << 15);
    else if (RvAsmStrEqI(mn, "fcvt.w.s"))
      word = 0xC0000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (0 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.wu.s"))
      word = 0xC0000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (1 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.l.s"))
      word = 0xC0000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (2 << 20);
    else if (RvAsmStrEqI(mn, "fcvt.lu.s"))
      word = 0xC0000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (3 << 20);
    else
      word = 0xC2000053 | (rd << 7) | (rm << 12) | (rs1 << 15) | (3 << 20);
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
