/* RISC-V Backend - Translated from BackLib_RV.HC */

#include "holyc_compiler.h"
#include <string.h>

// RISC-V Register Definitions
#define RV_REG_ZERO  0
#define RV_REG_RA    1
#define RV_REG_SP    2
#define RV_REG_GP    3
#define RV_REG_TP    4
#define RV_REG_T0    5
#define RV_REG_T1    6
#define RV_REG_T2    7
#define RV_REG_S0    8
#define RV_REG_S1    9
#define RV_REG_A0    10
#define RV_REG_A1    11
#define RV_REG_A2    12
#define RV_REG_A3    13
#define RV_REG_A4    14
#define RV_REG_A5    15
#define RV_REG_A6    16
#define RV_REG_A7    17
#define RV_REG_S2    18
#define RV_REG_S3    19
#define RV_REG_S4    20
#define RV_REG_S5    21
#define RV_REG_S6    22
#define RV_REG_S7    23
#define RV_REG_S8    24
#define RV_REG_S9    25
#define RV_REG_S10   26
#define RV_REG_S11   27
#define RV_REG_T3    28
#define RV_REG_T4    29
#define RV_REG_T5    30
#define RV_REG_T6    31

#define RV_REG_FP    RV_REG_S0
#define RV_REG_NONE  0xFF

// RISC-V Opcodes
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
#define RV_OP_OP_IMM_32  0x1B
#define RV_OP_OP_32      0x3B

// funct3 codes
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

// funct7 codes
#define RV_F7_NORMAL     0x00
#define RV_F7_ALT        0x20

// M extension funct7
#define RV_F7_MULDIV     0x01

// Emit a 32-bit instruction
static inline void EmitU32(U8 **ptr, U32 val) {
    *(U32*)(*ptr) = val;
    *ptr += 4;
}

// R-type instruction
static void RVEmitR(U8 **ptr, U8 opcode, U8 rd, U8 funct3, U8 rs1, U8 rs2, U8 funct7) {
    U32 inst = opcode | (rd<<7) | (funct3<<12) | (rs1<<15) | (rs2<<20) | (funct7<<25);
    EmitU32(ptr, inst);
}

// I-type instruction
static void RVEmitI(U8 **ptr, U8 opcode, U8 rd, U8 funct3, U8 rs1, I64 imm) {
    U32 imm12 = imm & 0xFFF;
    U32 inst = opcode | (rd<<7) | (funct3<<12) | (rs1<<15) | (imm12<<20);
    EmitU32(ptr, inst);
}

// S-type instruction
static void RVEmitS(U8 **ptr, U8 opcode, U8 funct3, U8 rs1, U8 rs2, I64 imm) {
    U32 imm_low = imm & 0x1F;
    U32 imm_high = (imm >> 5) & 0x7F;
    U32 inst = opcode | (imm_low<<7) | (funct3<<12) | (rs1<<15) | (rs2<<20) | (imm_high<<25);
    EmitU32(ptr, inst);
}

// B-type instruction
static void RVEmitB(U8 **ptr, U8 opcode, U8 funct3, U8 rs1, U8 rs2, I64 imm) {
    U32 imm12   = (imm >> 12) & 0x1;
    U32 imm11   = (imm >> 11) & 0x1;
    U32 imm10_5 = (imm >> 5) & 0x3F;
    U32 imm4_1  = (imm >> 1) & 0xF;
    
    U32 inst = opcode | (imm11<<7) | (imm4_1<<8) | (funct3<<12) | 
               (rs1<<15) | (rs2<<20) | (imm10_5<<25) | (imm12<<31);
    EmitU32(ptr, inst);
}

// U-type instruction
static void RVEmitU(U8 **ptr, U8 opcode, U8 rd, I64 imm) {
    U32 imm20 = (imm >> 12) & 0xFFFFF;
    U32 inst = opcode | (rd<<7) | (imm20<<12);
    EmitU32(ptr, inst);
}

// J-type instruction
static void RVEmitJ(U8 **ptr, U8 opcode, U8 rd, I64 imm) {
    U32 imm20   = (imm >> 20) & 0x1;
    U32 imm19_12 = (imm >> 12) & 0xFF;
    U32 imm11   = (imm >> 11) & 0x1;
    U32 imm10_1 = (imm >> 1) & 0x3FF;
    
    U32 inst = opcode | (rd<<7) | (imm19_12<<12) | (imm11<<20) | (imm10_1<<21) | (imm20<<31);
    EmitU32(ptr, inst);
}

// ═══════════════════════════════════════════════════════════════
// Common instructions
// ═══════════════════════════════════════════════════════════════

void RVAdd(U8 **ptr, U8 rd, U8 rs1, U8 rs2) {
    RVEmitR(ptr, RV_OP_OP, rd, RV_F3_ADD_SUB, rs1, rs2, RV_F7_NORMAL);
}

void RVSub(U8 **ptr, U8 rd, U8 rs1, U8 rs2) {
    RVEmitR(ptr, RV_OP_OP, rd, RV_F3_ADD_SUB, rs1, rs2, RV_F7_ALT);
}

void RVAddi(U8 **ptr, U8 rd, U8 rs1, I64 imm) {
    RVEmitI(ptr, RV_OP_OP_IMM, rd, RV_F3_ADD_SUB, rs1, imm);
}

void RVMul(U8 **ptr, U8 rd, U8 rs1, U8 rs2) {
    RVEmitR(ptr, RV_OP_OP, rd, 0, rs1, rs2, RV_F7_MULDIV);
}

void RVDiv(U8 **ptr, U8 rd, U8 rs1, U8 rs2) {
    RVEmitR(ptr, RV_OP_OP, rd, 4, rs1, rs2, RV_F7_MULDIV);
}

void RVRem(U8 **ptr, U8 rd, U8 rs1, U8 rs2) {
    RVEmitR(ptr, RV_OP_OP, rd, 6, rs1, rs2, RV_F7_MULDIV);
}

void RVAnd(U8 **ptr, U8 rd, U8 rs1, U8 rs2) {
    RVEmitR(ptr, RV_OP_OP, rd, RV_F3_AND, rs1, rs2, RV_F7_NORMAL);
}

void RVOr(U8 **ptr, U8 rd, U8 rs1, U8 rs2) {
    RVEmitR(ptr, RV_OP_OP, rd, RV_F3_OR, rs1, rs2, RV_F7_NORMAL);
}

void RVXor(U8 **ptr, U8 rd, U8 rs1, U8 rs2) {
    RVEmitR(ptr, RV_OP_OP, rd, RV_F3_XOR, rs1, rs2, RV_F7_NORMAL);
}

void RVSll(U8 **ptr, U8 rd, U8 rs1, U8 rs2) {
    RVEmitR(ptr, RV_OP_OP, rd, RV_F3_SLL, rs1, rs2, RV_F7_NORMAL);
}

void RVSrl(U8 **ptr, U8 rd, U8 rs1, U8 rs2) {
    RVEmitR(ptr, RV_OP_OP, rd, RV_F3_SRL_SRA, rs1, rs2, RV_F7_NORMAL);
}

void RVSra(U8 **ptr, U8 rd, U8 rs1, U8 rs2) {
    RVEmitR(ptr, RV_OP_OP, rd, RV_F3_SRL_SRA, rs1, rs2, RV_F7_ALT);
}

void RVSlli(U8 **ptr, U8 rd, U8 rs1, U8 shamt) {
    RVEmitI(ptr, RV_OP_OP_IMM, rd, RV_F3_SLL, rs1, shamt & 0x3F);
}

void RVSrli(U8 **ptr, U8 rd, U8 rs1, U8 shamt) {
    RVEmitI(ptr, RV_OP_OP_IMM, rd, RV_F3_SRL_SRA, rs1, shamt & 0x3F);
}

void RVSrai(U8 **ptr, U8 rd, U8 rs1, U8 shamt) {
    RVEmitI(ptr, RV_OP_OP_IMM, rd, RV_F3_SRL_SRA, rs1, (shamt & 0x3F) | 0x400);
}

void RVLd(U8 **ptr, U8 rd, U8 rs1, I64 offset) {
    RVEmitI(ptr, RV_OP_LOAD, rd, RV_F3_LD, rs1, offset);
}

void RVSd(U8 **ptr, U8 rs2, U8 rs1, I64 offset) {
    RVEmitS(ptr, RV_OP_STORE, RV_F3_SD, rs1, rs2, offset);
}

void RVLw(U8 **ptr, U8 rd, U8 rs1, I64 offset) {
    RVEmitI(ptr, RV_OP_LOAD, rd, RV_F3_LW, rs1, offset);
}

void RVSw(U8 **ptr, U8 rs2, U8 rs1, I64 offset) {
    RVEmitS(ptr, RV_OP_STORE, RV_F3_SW, rs1, rs2, offset);
}

void RVLb(U8 **ptr, U8 rd, U8 rs1, I64 offset) {
    RVEmitI(ptr, RV_OP_LOAD, rd, RV_F3_LB, rs1, offset);
}

void RVSb(U8 **ptr, U8 rs2, U8 rs1, I64 offset) {
    RVEmitS(ptr, RV_OP_STORE, RV_F3_SB, rs1, rs2, offset);
}

void RVLui(U8 **ptr, U8 rd, I64 imm) {
    RVEmitU(ptr, RV_OP_LUI, rd, imm);
}

void RVAuipc(U8 **ptr, U8 rd, I64 imm) {
    RVEmitU(ptr, RV_OP_AUIPC, rd, imm);
}

void RVJal(U8 **ptr, U8 rd, I64 offset) {
    RVEmitJ(ptr, RV_OP_JAL, rd, offset);
}

void RVJalr(U8 **ptr, U8 rd, U8 rs1, I64 offset) {
    RVEmitI(ptr, RV_OP_JALR, rd, 0, rs1, offset);
}

void RVBeq(U8 **ptr, U8 rs1, U8 rs2, I64 offset) {
    RVEmitB(ptr, RV_OP_BRANCH, RV_F3_BEQ, rs1, rs2, offset);
}

void RVBne(U8 **ptr, U8 rs1, U8 rs2, I64 offset) {
    RVEmitB(ptr, RV_OP_BRANCH, RV_F3_BNE, rs1, rs2, offset);
}

void RVBlt(U8 **ptr, U8 rs1, U8 rs2, I64 offset) {
    RVEmitB(ptr, RV_OP_BRANCH, RV_F3_BLT, rs1, rs2, offset);
}

void RVBge(U8 **ptr, U8 rs1, U8 rs2, I64 offset) {
    RVEmitB(ptr, RV_OP_BRANCH, RV_F3_BGE, rs1, rs2, offset);
}

void RVBltu(U8 **ptr, U8 rs1, U8 rs2, I64 offset) {
    RVEmitB(ptr, RV_OP_BRANCH, RV_F3_BLTU, rs1, rs2, offset);
}

void RVBgeu(U8 **ptr, U8 rs1, U8 rs2, I64 offset) {
    RVEmitB(ptr, RV_OP_BRANCH, RV_F3_BGEU, rs1, rs2, offset);
}

// Pseudo-instructions
void RVLi(U8 **ptr, U8 rd, I64 imm) {
    if (imm >= -2048 && imm <= 2047) {
        RVAddi(ptr, rd, RV_REG_ZERO, imm);
    } else {
        I64 hi = (imm + 0x800) >> 12;
        I64 lo = imm & 0xFFF;
        if (lo & 0x800) lo |= 0xFFFFFFFFFFFFF000LL;
        
        RVLui(ptr, rd, hi);
        if (lo) {
            RVAddi(ptr, rd, rd, lo);
        }
    }
}

void RVMv(U8 **ptr, U8 rd, U8 rs) {
    RVAddi(ptr, rd, rs, 0);
}

void RVRet(U8 **ptr) {
    RVJalr(ptr, RV_REG_ZERO, RV_REG_RA, 0);
}

void RVNop(U8 **ptr) {
    RVAddi(ptr, RV_REG_ZERO, RV_REG_ZERO, 0);
}

// ═══════════════════════════════════════════════════════════════
// Stack operations
// ═══════════════════════════════════════════════════════════════

void RVPush(U8 **ptr, U8 reg) {
    RVAddi(ptr, RV_REG_SP, RV_REG_SP, -8);
    RVSd(ptr, reg, RV_REG_SP, 0);
}

void RVPop(U8 **ptr, U8 reg) {
    RVLd(ptr, reg, RV_REG_SP, 0);
    RVAddi(ptr, RV_REG_SP, RV_REG_SP, 8);
}


