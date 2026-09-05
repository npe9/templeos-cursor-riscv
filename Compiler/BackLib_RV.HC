/* RISC-V Backend - Machine Code Emission Library
 * 
 * This file replaces BackLib.HC for RISC-V target.
 * Provides instruction encoding and emission functions.
 */
#help_index "Compiler/Internal/RISCV"
#ifndef RV_REG_ZERO
// RISC-V Register Definitions
#define RV_REG_ZERO  0  // x0 - hardwired zero
#define RV_REG_RA    1  // x1 - return address
#define RV_REG_SP    2  // x2 - stack pointer
#define RV_REG_GP    3  // x3 - global pointer
#define RV_REG_TP    4  // x4 - thread pointer
#define RV_REG_T0    5  // x5 - temporary
#define RV_REG_T1    6  // x6 - temporary
#define RV_REG_T2    7  // x7 - temporary
#define RV_REG_S0    8  // x8 - saved / frame pointer
#define RV_REG_S1    9  // x9 - saved
#define RV_REG_A0    10 // x10 - argument/return
#define RV_REG_A1    11 // x11 - argument/return
#define RV_REG_A2    12 // x12 - argument
#define RV_REG_A3    13 // x13 - argument
#define RV_REG_A4    14 // x14 - argument
#define RV_REG_A5    15 // x15 - argument
#define RV_REG_A6    16 // x16 - argument
#define RV_REG_A7    17 // x17 - argument
#define RV_REG_S2    18 // x18 - saved
#define RV_REG_S3    19 // x19 - saved
#define RV_REG_S4    20 // x20 - saved
#define RV_REG_S5    21 // x21 - saved
#define RV_REG_S6    22 // x22 - saved
#define RV_REG_S7    23 // x23 - saved
#define RV_REG_S8    24 // x24 - saved
#define RV_REG_S9    25 // x25 - saved
#define RV_REG_S10   26 // x26 - saved
#define RV_REG_S11   27 // x27 - saved
#define RV_REG_T3    28 // x28 - temporary
#define RV_REG_T4    29 // x29 - temporary
#define RV_REG_T5    30 // x30 - temporary
#define RV_REG_T6    31 // x31 - temporary
// Alias for frame pointer
#define RV_REG_FP    RV_REG_S0
// Special value for "no register"
#define RV_REG_NONE  0xFF
#endif
#ifndef REGG_SCRATCH
// Register groups
#define REGG_SCRATCH     ((1<<RV_REG_T0)|(1<<RV_REG_T1)|(1<<RV_REG_T2)|(1<<RV_REG_T3)|(1<<RV_REG_T4)|(1<<RV_REG_T5)|(1<<RV_REG_T6))
#define REGG_SAVED       ((1<<RV_REG_S1)|(1<<RV_REG_S2)|(1<<RV_REG_S3)|(1<<RV_REG_S4)|(1<<RV_REG_S5)|(1<<RV_REG_S6)|(1<<RV_REG_S7)|(1<<RV_REG_S8)|(1<<RV_REG_S9)|(1<<RV_REG_S10)|(1<<RV_REG_S11))
#define REGG_STK_TMP     (1<<RV_REG_T4)
#define REGG_CLOBBERED   ((1<<RV_REG_A0)|(1<<RV_REG_T0)|(1<<RV_REG_T1)|(1<<RV_REG_T2)|(1<<RV_REG_T3))
#endif
// RISC-V Opcodes (base ISA)
#define RV_OP_LOAD       0x03
#define RV_OP_STORE      0x23
#define RV_OP_BRANCH     0x63
#define RV_OP_JALR       0x67
#define RV_OP_JAL        0x6F
#define RV_OP_OP_IMM     0x13
#define RV_OP_OP         0x33
#define RV_OP_LUI        0x37
#define RV_OP_AUIPC      0x17
#define RV_OP_SYSTEM     0x73
// RISC-V funct3 codes
#define RV_F3_ADD_SUB    0x0
#define RV_F3_SLL        0x1
#define RV_F3_SLT        0x2
#define RV_F3_SLTU       0x3
#define RV_F3_XOR        0x4
#define RV_F3_SRL_SRA    0x5
#define RV_F3_OR         0x6
#define RV_F3_AND        0x7
#define RV_F3_BEQ        0x0
#define RV_F3_BNE        0x1
#define RV_F3_BLT        0x4
#define RV_F3_BGE        0x5
#define RV_F3_BLTU       0x6
#define RV_F3_BGEU       0x7
#define RV_F3_LB         0x0
#define RV_F3_LH         0x1
#define RV_F3_LW         0x2
#define RV_F3_LD         0x3
#define RV_F3_LBU        0x4
#define RV_F3_LHU        0x5
#define RV_F3_LWU        0x6
#define RV_F3_SB         0x0
#define RV_F3_SH         0x1
#define RV_F3_SW         0x2
#define RV_F3_SD         0x3
// RISC-V funct7 codes
#define RV_F7_NORMAL     0x00
#define RV_F7_ALT        0x20  // For SUB, SRA
// Floating-point opcodes
#define RV_OP_LOAD_FP    0x07
#define RV_OP_STORE_FP   0x27
#define RV_OP_FMADD      0x43
#define RV_OP_FMSUB      0x47
#define RV_OP_FNMSUB     0x4B
#define RV_OP_FNMADD     0x4F
#define RV_OP_OP_FP      0x53
// Basic instruction emission (keep compatible with x86-64 backend)
U0 ICU8(CIntermediateCode *tmpi, U8 b)
{
  if (tmpi->ic_cnt >= IC_BODY_SIZE)
    return;
  // RV: denser than x86; avoid chain corruption
  tmpi->ic_body[tmpi->ic_cnt++] = b;
}

U0 ICU16(CIntermediateCode *tmpi, U16 w)
{
  if (tmpi->ic_cnt + 2 > IC_BODY_SIZE)
    return;
  *(&tmpi->ic_body[tmpi->ic_cnt])(U16 *) = w;
  tmpi->ic_cnt += 2;
}

U0 ICU32(CIntermediateCode *tmpi, U32 d)
{
  if (tmpi->ic_cnt + 4 > IC_BODY_SIZE)
    return;
  *(&tmpi->ic_body[tmpi->ic_cnt])(U32 *) = d;
  tmpi->ic_cnt += 4;
}

U0 ICU64(CIntermediateCode *tmpi, U64 q)
{
  if (tmpi->ic_cnt + 8 > IC_BODY_SIZE)
    return;
  *(&tmpi->ic_body[tmpi->ic_cnt])(U64 *) = q;
  tmpi->ic_cnt += 8;
}
/* RISC-V Instruction Encoding Functions */
U0 RVEmitR(CIntermediateCode *tmpi, U8 opcode, U8 rd, U8 funct3, U8 rs1, U8 rs2, U8 funct7)
{
  // Emit R-type. Do NOT mask rs2: RVSlli passes shamt here — shamt=32 sets
  // bit25 via (32<<20), the RV64 6-bit shamt encoding. Masking rs2&=31 made
  // slli/srli 32 into no-ops → LUI sign-extend (mtval=0xffffffff82……).
  rd &= 31;
  rs1 &= 31;
  U32 inst = opcode | (rd << 7) | (funct3 << 12) | (rs1 << 15) | (rs2 << 20) | (funct7 << 25);
  ICU32(tmpi, inst);
}

U0 RVEmitI(CIntermediateCode *tmpi, U8 opcode, U8 rd, U8 funct3, U8 rs1, I64 imm)
{
  // Emit I-type instruction: imm[31:20] rs1[19:15] funct3[14:12] rd[11:7] opcode[6:0]
  // Mask regs: unmasked REG_RIP(32) made `ld t0,1(x0)` (bit5→imm[0]).
  rd &= 31;
  rs1 &= 31;
  I64 imm12 = imm & 0xFFF;
  U32 inst = opcode | (rd << 7) | (funct3 << 12) | (rs1 << 15) | (imm12 << 20);
  ICU32(tmpi, inst);
}

U0 RVEmitS(CIntermediateCode *tmpi, U8 opcode, U8 funct3, U8 rs1, U8 rs2, I64 imm)
{
  // Emit S-type instruction: imm[11:5] rs2[24:20] rs1[19:15] funct3[14:12] imm[4:0] opcode[6:0]
  rs1 &= 31;
  rs2 &= 31;
  U32 imm_low = imm & 0x1F;
  U32 imm_high = (imm >> 5) & 0x7F;
  U32 inst = opcode | (imm_low << 7) | (funct3 << 12) | (rs1 << 15) | (rs2 << 20) | (imm_high << 25);
  ICU32(tmpi, inst);
}

U0 RVEmitB(CIntermediateCode *tmpi, U8 opcode, U8 funct3, U8 rs1, U8 rs2, I64 offset)
{
  // Emit B-type instruction: imm[12|10:5] rs2[24:20] rs1[19:15] funct3[14:12] imm[4:1|11] opcode[6:0]
  rs1 &= 31;
  rs2 &= 31;
  U32 imm_11 = (offset >> 11) & 0x1;
  U32 imm_4_1 = (offset >> 1) & 0xF;
  U32 imm_10_5 = (offset >> 5) & 0x3F;
  U32 imm_12 = (offset >> 12) & 0x1;
  U32 inst = opcode | (imm_11 << 7) | (imm_4_1 << 8) | (funct3 << 12) | (rs1 << 15) | (rs2 << 20) | (imm_10_5 << 25) | (imm_12 << 31);
  ICU32(tmpi, inst);
}

U0 RVEmitU(CIntermediateCode *tmpi, U8 opcode, U8 rd, I64 imm)
{
  // Emit U-type: imm is already the 20-bit field (bits[31:12] of result).
  // Do not >>12 here — callers (RVLi) pass (val+0x800)>>12.
  U32 imm20 = imm & 0xFFFFF;
  U32 inst = opcode | (rd << 7) | (imm20 << 12);
  ICU32(tmpi, inst);
}

U0 RVEmitJ(CIntermediateCode *tmpi, U8 opcode, U8 rd, I64 offset)
{
  // Emit J-type instruction: imm[20|10:1|11|19:12] rd[11:7] opcode[6:0]
  U32 imm_20 = (offset >> 20) & 0x1;
  U32 imm_10_1 = (offset >> 1) & 0x3FF;
  U32 imm_11 = (offset >> 11) & 0x1;
  U32 imm_19_12 = (offset >> 12) & 0xFF;
  U32 inst = opcode | (rd << 7) | (imm_19_12 << 12) | (imm_11 << 20) | (imm_10_1 << 21) | (imm_20 << 31);
  ICU32(tmpi, inst);
}
/* High-level RISC-V Instruction Emitters */
U0 RVAdd(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 rs2)
{
  // ADD rd, rs1, rs2
  RVEmitR(tmpi, RV_OP_OP, rd, RV_F3_ADD_SUB, rs1, rs2, RV_F7_NORMAL);
}

U0 RVAddi(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 imm)
{
  // ADDI rd, rs1, imm
  RVEmitI(tmpi, RV_OP_OP_IMM, rd, RV_F3_ADD_SUB, rs1, imm);
}

U0 RVSub(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 rs2)
{
  // SUB rd, rs1, rs2
  RVEmitR(tmpi, RV_OP_OP, rd, RV_F3_ADD_SUB, rs1, rs2, RV_F7_ALT);
}

U0 RVAnd(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 rs2)
{
  // AND rd, rs1, rs2
  RVEmitR(tmpi, RV_OP_OP, rd, RV_F3_AND, rs1, rs2, RV_F7_NORMAL);
}

U0 RVAndi(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 imm)
{
  // ANDI rd, rs1, imm
  RVEmitI(tmpi, RV_OP_OP_IMM, rd, RV_F3_AND, rs1, imm);
}

U0 RVOr(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 rs2)
{
  // OR rd, rs1, rs2
  RVEmitR(tmpi, RV_OP_OP, rd, RV_F3_OR, rs1, rs2, RV_F7_NORMAL);
}

U0 RVOri(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 imm)
{
  // ORI rd, rs1, imm
  RVEmitI(tmpi, RV_OP_OP_IMM, rd, RV_F3_OR, rs1, imm);
}

U0 RVXor(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 rs2)
{
  // XOR rd, rs1, rs2
  RVEmitR(tmpi, RV_OP_OP, rd, RV_F3_XOR, rs1, rs2, RV_F7_NORMAL);
}

U0 RVXori(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 imm)
{
  // XORI rd, rs1, imm
  RVEmitI(tmpi, RV_OP_OP_IMM, rd, RV_F3_XOR, rs1, imm);
}

U0 RVSll(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 rs2)
{
  // SLL rd, rs1, rs2
  RVEmitR(tmpi, RV_OP_OP, rd, RV_F3_SLL, rs1, rs2, RV_F7_NORMAL);
}

U0 RVSlli(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 shamt)
{
  // SLLI rd, rs1, shamt (shift amount in rs2 position for RV64)
  RVEmitR(tmpi, RV_OP_OP_IMM, rd, RV_F3_SLL, rs1, shamt, RV_F7_NORMAL);
}

U0 RVSrl(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 rs2)
{
  // SRL rd, rs1, rs2
  RVEmitR(tmpi, RV_OP_OP, rd, RV_F3_SRL_SRA, rs1, rs2, RV_F7_NORMAL);
}

U0 RVSrli(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 shamt)
{
  // SRLI rd, rs1, shamt
  RVEmitR(tmpi, RV_OP_OP_IMM, rd, RV_F3_SRL_SRA, rs1, shamt, RV_F7_NORMAL);
}

U0 RVSra(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 rs2)
{
  // SRA rd, rs1, rs2
  RVEmitR(tmpi, RV_OP_OP, rd, RV_F3_SRL_SRA, rs1, rs2, RV_F7_ALT);
}

U0 RVSrai(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 shamt)
{
  // SRAI rd, rs1, shamt
  RVEmitR(tmpi, RV_OP_OP_IMM, rd, RV_F3_SRL_SRA, rs1, shamt, RV_F7_ALT);
}

U0 RVSlt(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 rs2)
{
  // SLT rd, rs1, rs2 (set less than)
  RVEmitR(tmpi, RV_OP_OP, rd, RV_F3_SLT, rs1, rs2, RV_F7_NORMAL);
}

U0 RVSlti(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 imm)
{
  // SLTI rd, rs1, imm
  RVEmitI(tmpi, RV_OP_OP_IMM, rd, RV_F3_SLT, rs1, imm);
}

U0 RVSltu(CIntermediateCode *tmpi, U8 rd, U8 rs1, U8 rs2)
{
  // SLTU rd, rs1, rs2 (unsigned)
  RVEmitR(tmpi, RV_OP_OP, rd, RV_F3_SLTU, rs1, rs2, RV_F7_NORMAL);
}

U0 RVSltiu(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 imm)
{
  // SLTIU rd, rs1, imm
  RVEmitI(tmpi, RV_OP_OP_IMM, rd, RV_F3_SLTU, rs1, imm);
}
/* Load/Store Instructions */
U0 RVLd(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 offset)
{
  // LD rd, offset(rs1) - 64-bit load
  RVEmitI(tmpi, RV_OP_LOAD, rd, RV_F3_LD, rs1, offset);
}

U0 RVLw(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 offset)
{
  // LW rd, offset(rs1) - 32-bit load (sign-extend)
  RVEmitI(tmpi, RV_OP_LOAD, rd, RV_F3_LW, rs1, offset);
}

U0 RVLwu(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 offset)
{
  // LWU rd, offset(rs1) - 32-bit load (zero-extend)
  RVEmitI(tmpi, RV_OP_LOAD, rd, RV_F3_LWU, rs1, offset);
}

U0 RVLh(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 offset)
{
  // LH rd, offset(rs1) - 16-bit load (sign-extend)
  RVEmitI(tmpi, RV_OP_LOAD, rd, RV_F3_LH, rs1, offset);
}

U0 RVLhu(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 offset)
{
  // LHU rd, offset(rs1) - 16-bit load (zero-extend)
  RVEmitI(tmpi, RV_OP_LOAD, rd, RV_F3_LHU, rs1, offset);
}

U0 RVLb(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 offset)
{
  // LB rd, offset(rs1) - 8-bit load (sign-extend)
  RVEmitI(tmpi, RV_OP_LOAD, rd, RV_F3_LB, rs1, offset);
}

U0 RVLbu(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 offset)
{
  // LBU rd, offset(rs1) - 8-bit load (zero-extend)
  RVEmitI(tmpi, RV_OP_LOAD, rd, RV_F3_LBU, rs1, offset);
}

U0 RVSd(CIntermediateCode *tmpi, U8 rs2, U8 rs1, I64 offset)
{
  // SD rs2, offset(rs1) - 64-bit store
  RVEmitS(tmpi, RV_OP_STORE, RV_F3_SD, rs1, rs2, offset);
}

U0 RVSw(CIntermediateCode *tmpi, U8 rs2, U8 rs1, I64 offset)
{
  // SW rs2, offset(rs1) - 32-bit store
  RVEmitS(tmpi, RV_OP_STORE, RV_F3_SW, rs1, rs2, offset);
}

U0 RVSh(CIntermediateCode *tmpi, U8 rs2, U8 rs1, I64 offset)
{
  // SH rs2, offset(rs1) - 16-bit store
  RVEmitS(tmpi, RV_OP_STORE, RV_F3_SH, rs1, rs2, offset);
}

U0 RVSb(CIntermediateCode *tmpi, U8 rs2, U8 rs1, I64 offset)
{
  // SB rs2, offset(rs1) - 8-bit store
  RVEmitS(tmpi, RV_OP_STORE, RV_F3_SB, rs1, rs2, offset);
}
/* Branch Instructions */
U0 RVBeq(CIntermediateCode *tmpi, U8 rs1, U8 rs2, I64 offset)
{
  // BEQ rs1, rs2, offset
  RVEmitB(tmpi, RV_OP_BRANCH, RV_F3_BEQ, rs1, rs2, offset);
}

U0 RVBne(CIntermediateCode *tmpi, U8 rs1, U8 rs2, I64 offset)
{
  // BNE rs1, rs2, offset
  RVEmitB(tmpi, RV_OP_BRANCH, RV_F3_BNE, rs1, rs2, offset);
}

U0 RVBlt(CIntermediateCode *tmpi, U8 rs1, U8 rs2, I64 offset)
{
  // BLT rs1, rs2, offset (signed)
  RVEmitB(tmpi, RV_OP_BRANCH, RV_F3_BLT, rs1, rs2, offset);
}

U0 RVBge(CIntermediateCode *tmpi, U8 rs1, U8 rs2, I64 offset)
{
  // BGE rs1, rs2, offset (signed)
  RVEmitB(tmpi, RV_OP_BRANCH, RV_F3_BGE, rs1, rs2, offset);
}

U0 RVBltu(CIntermediateCode *tmpi, U8 rs1, U8 rs2, I64 offset)
{
  // BLTU rs1, rs2, offset (unsigned)
  RVEmitB(tmpi, RV_OP_BRANCH, RV_F3_BLTU, rs1, rs2, offset);
}

U0 RVBgeu(CIntermediateCode *tmpi, U8 rs1, U8 rs2, I64 offset)
{
  // BGEU rs1, rs2, offset (unsigned)
  RVEmitB(tmpi, RV_OP_BRANCH, RV_F3_BGEU, rs1, rs2, offset);
}
/* Jump Instructions */
U0 RVJal(CIntermediateCode *tmpi, U8 rd, I64 offset)
{
  // JAL rd, offset
  RVEmitJ(tmpi, RV_OP_JAL, rd, offset);
}

U0 RVJalr(CIntermediateCode *tmpi, U8 rd, U8 rs1, I64 offset)
{
  // JALR rd, offset(rs1)
  RVEmitI(tmpi, RV_OP_JALR, rd, 0, rs1, offset);
}
/* Upper Immediate Instructions */
U0 RVLui(CIntermediateCode *tmpi, U8 rd, I64 imm)
{
  // LUI rd, imm (load upper immediate)
  RVEmitU(tmpi, RV_OP_LUI, rd, imm);
}

U0 RVAuipc(CIntermediateCode *tmpi, U8 rd, I64 imm)
{
  // AUIPC rd, imm (add upper immediate to PC)
  RVEmitU(tmpi, RV_OP_AUIPC, rd, imm);
}
/* Pseudo-instructions */
U0 RVNop(CIntermediateCode *tmpi)
{
  // NOP (ADDI x0, x0, 0)
  RVAddi(tmpi, RV_REG_ZERO, RV_REG_ZERO, 0);
}

U0 RVMv(CIntermediateCode *tmpi, U8 rd, U8 rs)
{
  // MV rd, rs (ADDI rd, rs, 0)
  RVAddi(tmpi, rd, rs, 0);
}

U0 RVNot(CIntermediateCode *tmpi, U8 rd, U8 rs)
{
  // NOT rd, rs (XORI rd, rs, -1)
  RVXori(tmpi, rd, rs, -1);
}

U0 RVNeg(CIntermediateCode *tmpi, U8 rd, U8 rs)
{
  // NEG rd, rs (SUB rd, x0, rs)
  RVSub(tmpi, rd, RV_REG_ZERO, rs);
}

U0 RVSeqz(CIntermediateCode *tmpi, U8 rd, U8 rs)
{
  // SEQZ rd, rs (SLTIU rd, rs, 1) - set if equal to zero
  RVSltiu(tmpi, rd, rs, 1);
}

U0 RVSnez(CIntermediateCode *tmpi, U8 rd, U8 rs)
{
  // SNEZ rd, rs (SLTU rd, x0, rs) - set if not equal to zero
  RVSltu(tmpi, rd, RV_REG_ZERO, rs);
}

U0 RVRet(CIntermediateCode *tmpi)
{
  // RET (JALR x0, 0(ra))
  RVJalr(tmpi, RV_REG_ZERO, RV_REG_RA, 0);
}

U0 RVJ(CIntermediateCode *tmpi, I64 offset)
{
  // J offset (JAL x0, offset)
  RVJal(tmpi, RV_REG_ZERO, offset);
}
/* Load Immediate (for large constants) */
U0 RVLi(CIntermediateCode *tmpi, U8 rd, I64 imm)
{
  // LI rd, imm - Load immediate (handle various sizes)
  I64 hi, lo, hi32, lo32, hi_hi, hi_lo, lo_hi, lo_lo;
  U8 scratch;
  if (imm >= -2048 && imm <= 2047) {
    RVAddi(tmpi, rd, RV_REG_ZERO, imm);
    return;
  }
  // Host AOT breaks HolyC chained compares; also accept any value that
  // fits in bits[31:0] (LUI+ADDI covers full U32 via +0x800 adjust).
  hi32 = imm >> 32;
  if (!hi32 || hi32 == -1) {
    hi = (imm + 0x800) >> 12;
    lo = imm & 0xFFF;
    if (lo & 0x800)
      lo |= 0xFFFFFFFFFFFFF000;
    RVLui(tmpi, rd, hi);
    if (lo)
      RVAddi(tmpi, rd, rd, lo);
    // RV64 LUI sign-extends bit31 into [63:32]. Kernel/blob VAs like
    // 0x8080_0000 need zero-extend (host EmitCallArgsAndInvoke same).
    if (!hi32 && imm & 0x80000000) {
      RVSlli(tmpi, rd, rd, 32);
      RVSrli(tmpi, rd, rd, 32);
    }
    return;
  }
  // Full 64-bit: build hi32 in rd, shift, add lo32 via scratch != rd.
  scratch = RV_REG_T5;
  if (rd == scratch)
    scratch = RV_REG_T6;
  hi_hi = (hi32 + 0x800) >> 12;
  hi_lo = hi32 & 0xFFF;
  if (hi_lo & 0x800)
    hi_lo |= 0xFFFFFFFFFFFFF000;
  RVLui(tmpi, rd, hi_hi);
  if (hi_lo)
    RVAddi(tmpi, rd, rd, hi_lo);
  RVSlli(tmpi, rd, rd, 32);
  lo32 = imm & 0xFFFFFFFF;
  lo_hi = (lo32 + 0x800) >> 12;
  lo_lo = lo32 & 0xFFF;
  if (lo_lo & 0x800)
    lo_lo |= 0xFFFFFFFFFFFFF000;
  if (lo_hi) {
    RVLui(tmpi, scratch, lo_hi);
    if (lo_lo)
      RVAddi(tmpi, scratch, scratch, lo_lo);
    // RV64 LUI sign-extends bit31; zero-extend before adding into hi<<32.
    if (lo32 & 0x80000000) {
      RVSlli(tmpi, scratch, scratch, 32);
      RVSrli(tmpi, scratch, scratch, 32);
    }
    RVAdd(tmpi, rd, rd, scratch);
  } else if (lo_lo)
    RVAddi(tmpi, rd, rd, lo_lo);
}
/* Stack Operations */
U0 RVPush(CIntermediateCode *tmpi, U8 rs)
{
  // Push register onto stack
  RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -8);
  RVSd(tmpi, rs, RV_REG_SP, 0);
}

U0 RVPop(CIntermediateCode *tmpi, U8 rd)
{
  // Pop register from stack
  RVLd(tmpi, rd, RV_REG_SP, 0);
  RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 8);
}
/* Compatibility Wrappers for IC Backend */
U0 ICPushRegs(CIntermediateCode *tmpi, I64 mask)
{
  // Push registers according to mask
  I64 i;
  for (i = 0; i < 32; i++) {
    if (mask & (1 << i))
      RVPush(tmpi, i);
  }
}

U0 ICPopRegs(CIntermediateCode *tmpi, I64 mask)
{
  // Pop registers according to mask (in reverse order)
  I64 i;
  for (i = 31; i >= 0; i--) {
    if (mask & (1 << i))
      RVPop(tmpi, i);
  }
}

U0 ICAddRSP(CIntermediateCode *tmpi, I64 offset, Bool optimize = TRUE)
{
  // Adjust stack pointer
  if (!offset)
    return;
  if (offset >= -2048 && offset <= 2047) {
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, offset);
  } else {
    // Large offset - use temp register
    RVLi(tmpi, RV_REG_T6, offset);
    RVAdd(tmpi, RV_REG_SP, RV_REG_SP, RV_REG_T6);
  }
}

U0 ICZero(CIntermediateCode *tmpi, I64 r)
{
  // Zero out a register
  RVMv(tmpi, r, RV_REG_ZERO);
}
/* IC Data Movement - Will be expanded in BackA_RV.HC */
extern U0 ICMov(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip);
#help_index ""
