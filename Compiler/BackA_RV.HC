/* RISC-V Backend - Basic Operations
 * 
 * Translates IC operations to RISC-V machine code.
 * Replaces BackA.HC for RISC-V target.
 */

#help_index "Compiler/Internal/RISCV"

/* IC Move Operation - Core data movement function */

U0 ICMov(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, I64 rip)
{// Move/load/store data between registers and memory
  // t1,r1,d1 = destination type, register, displacement
  // t2,r2,d2 = source type, register, displacement
  
  I64 raw_type1 = t1.raw_type;
  I64 raw_type2 = t2.raw_type;
  
  // Handle immediate source
  if (t2 & MDF_IMM) {
    // Load immediate into register
    if (t1 & MDF_REG) {
      RVLi(tmpi, r1, d2);
    } else if (t1 & MDF_DISP) {
      // Store immediate to memory via temp register
      RVLi(tmpi, RV_REG_T6, d2);
      switch (raw_type1) {
        case RT_I8:
        case RT_U8:
          RVSb(tmpi, RV_REG_T6, r1, d1);
          break;
        case RT_I16:
        case RT_U16:
          RVSh(tmpi, RV_REG_T6, r1, d1);
          break;
        case RT_I32:
        case RT_U32:
          RVSw(tmpi, RV_REG_T6, r1, d1);
          break;
        default:
          RVSd(tmpi, RV_REG_T6, r1, d1);
      }
    }
    return;
  }
  
  // Register to register move
  if ((t1 & MDF_REG) && (t2 & MDF_REG)) {
    if (r1 != r2) {
      RVMv(tmpi, r1, r2);
    }
    return;
  }
  
  // Load from memory to register
  if ((t1 & MDF_REG) && (t2 & MDF_DISP)) {
    // Check if offset fits in 12 bits
    if (-2048 <= d2 <= 2047) {
      switch (raw_type2) {
        case RT_I8:
          RVLb(tmpi, r1, r2, d2);
          break;
        case RT_U8:
          RVLbu(tmpi, r1, r2, d2);
          break;
        case RT_I16:
          RVLh(tmpi, r1, r2, d2);
          break;
        case RT_U16:
          RVLhu(tmpi, r1, r2, d2);
          break;
        case RT_I32:
          RVLw(tmpi, r1, r2, d2);
          break;
        case RT_U32:
          RVLwu(tmpi, r1, r2, d2);
          break;
        default: // I64, U64, PTR
          RVLd(tmpi, r1, r2, d2);
      }
    } else {
      // Large offset - compute address first
      RVLi(tmpi, RV_REG_T6, d2);
      RVAdd(tmpi, RV_REG_T6, r2, RV_REG_T6);
      switch (raw_type2) {
        case RT_I8:
          RVLb(tmpi, r1, RV_REG_T6, 0);
          break;
        case RT_U8:
          RVLbu(tmpi, r1, RV_REG_T6, 0);
          break;
        case RT_I16:
          RVLh(tmpi, r1, RV_REG_T6, 0);
          break;
        case RT_U16:
          RVLhu(tmpi, r1, RV_REG_T6, 0);
          break;
        case RT_I32:
          RVLw(tmpi, r1, RV_REG_T6, 0);
          break;
        case RT_U32:
          RVLwu(tmpi, r1, RV_REG_T6, 0);
          break;
        default:
          RVLd(tmpi, r1, RV_REG_T6, 0);
      }
    }
    return;
  }
  
  // Store from register to memory
  if ((t1 & MDF_DISP) && (t2 & MDF_REG)) {
    if (-2048 <= d1 <= 2047) {
      switch (raw_type1) {
        case RT_I8:
        case RT_U8:
          RVSb(tmpi, r2, r1, d1);
          break;
        case RT_I16:
        case RT_U16:
          RVSh(tmpi, r2, r1, d1);
          break;
        case RT_I32:
        case RT_U32:
          RVSw(tmpi, r2, r1, d1);
          break;
        default:
          RVSd(tmpi, r2, r1, d1);
      }
    } else {
      // Large offset
      RVLi(tmpi, RV_REG_T6, d1);
      RVAdd(tmpi, RV_REG_T6, r1, RV_REG_T6);
      switch (raw_type1) {
        case RT_I8:
        case RT_U8:
          RVSb(tmpi, r2, RV_REG_T6, 0);
          break;
        case RT_I16:
        case RT_U16:
          RVSh(tmpi, r2, RV_REG_T6, 0);
          break;
        case RT_I32:
        case RT_U32:
          RVSw(tmpi, r2, RV_REG_T6, 0);
          break;
        default:
          RVSd(tmpi, r2, RV_REG_T6, 0);
      }
    }
    return;
  }
  
  // Memory to memory - use temp register
  if ((t1 & MDF_DISP) && (t2 & MDF_DISP)) {
    // Load to temp
    ICMov(tmpi, MDF_REG+raw_type2, RV_REG_T6, 0, t2, r2, d2, rip);
    // Store from temp
    ICMov(tmpi, t1, r1, d1, MDF_REG+raw_type1, RV_REG_T6, 0, rip);
    return;
  }
  
  // Stack operations - should be handled by pass 6
  if (t1 & MDF_STK) {
    // Push
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -8);
    ICMov(tmpi, MDF_DISP+RT_I64, RV_REG_SP, 0, t2, r2, d2, rip);
    return;
  }
  if (t2 & MDF_STK) {
    // Pop
    ICMov(tmpi, t1, r1, d1, MDF_DISP+RT_I64, RV_REG_SP, 0, rip);
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 8);
    return;
  }
}

/* Arithmetic Operations */

U0 ICAdd(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// IC_ADD: t1/r1/d1 = t2/r2/d2 + t3/r3/d3
  U8 dest_reg = RV_REG_A0;  // Default to a0 for results
  U8 src1_reg, src2_reg;
  
  // Load operands into registers
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  
  if (t3 & MDF_IMM) {
    // Immediate add
    I64 imm = d3;
    if (-2048 <= imm <= 2047) {
      if (t1 & MDF_REG) dest_reg = r1;
      RVAddi(tmpi, dest_reg, src1_reg, imm);
    } else {
      // Large immediate
      RVLi(tmpi, RV_REG_T1, imm);
      if (t1 & MDF_REG) dest_reg = r1;
      RVAdd(tmpi, dest_reg, src1_reg, RV_REG_T1);
    }
  } else if (t3 & MDF_REG) {
    src2_reg = r3;
    if (t1 & MDF_REG) dest_reg = r1;
    RVAdd(tmpi, dest_reg, src1_reg, src2_reg);
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    if (t1 & MDF_REG) dest_reg = r1;
    RVAdd(tmpi, dest_reg, src1_reg, RV_REG_T1);
  }
  
  // Store result if needed
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

U0 ICSub(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// IC_SUB: t1/r1/d1 = t2/r2/d2 - t3/r3/d3
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  // Load first operand
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  
  if (t3 & MDF_IMM) {
    // Subtract immediate: ADD with negated immediate
    I64 imm = -d3;
    if (-2048 <= imm <= 2047) {
      if (t1 & MDF_REG) dest_reg = r1;
      RVAddi(tmpi, dest_reg, src1_reg, imm);
    } else {
      RVLi(tmpi, RV_REG_T1, d3);
      if (t1 & MDF_REG) dest_reg = r1;
      RVSub(tmpi, dest_reg, src1_reg, RV_REG_T1);
    }
  } else if (t3 & MDF_REG) {
    src2_reg = r3;
    if (t1 & MDF_REG) dest_reg = r1;
    RVSub(tmpi, dest_reg, src1_reg, src2_reg);
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    if (t1 & MDF_REG) dest_reg = r1;
    RVSub(tmpi, dest_reg, src1_reg, RV_REG_T1);
  }
  
  // Store result
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

/* Bitwise Operations */

U0 ICAnd(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// IC_AND: t1/r1/d1 = t2/r2/d2 & t3/r3/d3
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  
  if (t3 & MDF_IMM) {
    I64 imm = d3;
    if (-2048 <= imm <= 2047) {
      if (t1 & MDF_REG) dest_reg = r1;
      RVAndi(tmpi, dest_reg, src1_reg, imm);
    } else {
      RVLi(tmpi, RV_REG_T1, imm);
      if (t1 & MDF_REG) dest_reg = r1;
      RVAnd(tmpi, dest_reg, src1_reg, RV_REG_T1);
    }
  } else if (t3 & MDF_REG) {
    src2_reg = r3;
    if (t1 & MDF_REG) dest_reg = r1;
    RVAnd(tmpi, dest_reg, src1_reg, src2_reg);
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    if (t1 & MDF_REG) dest_reg = r1;
    RVAnd(tmpi, dest_reg, src1_reg, RV_REG_T1);
  }
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

U0 ICOr(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
        CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// IC_OR
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  
  if (t3 & MDF_IMM) {
    I64 imm = d3;
    if (-2048 <= imm <= 2047) {
      if (t1 & MDF_REG) dest_reg = r1;
      RVOri(tmpi, dest_reg, src1_reg, imm);
    } else {
      RVLi(tmpi, RV_REG_T1, imm);
      if (t1 & MDF_REG) dest_reg = r1;
      RVOr(tmpi, dest_reg, src1_reg, RV_REG_T1);
    }
  } else if (t3 & MDF_REG) {
    src2_reg = r3;
    if (t1 & MDF_REG) dest_reg = r1;
    RVOr(tmpi, dest_reg, src1_reg, src2_reg);
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    if (t1 & MDF_REG) dest_reg = r1;
    RVOr(tmpi, dest_reg, src1_reg, RV_REG_T1);
  }
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

U0 ICXor(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// IC_XOR
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  
  if (t3 & MDF_IMM) {
    I64 imm = d3;
    if (-2048 <= imm <= 2047) {
      if (t1 & MDF_REG) dest_reg = r1;
      RVXori(tmpi, dest_reg, src1_reg, imm);
    } else {
      RVLi(tmpi, RV_REG_T1, imm);
      if (t1 & MDF_REG) dest_reg = r1;
      RVXor(tmpi, dest_reg, src1_reg, RV_REG_T1);
    }
  } else if (t3 & MDF_REG) {
    src2_reg = r3;
    if (t1 & MDF_REG) dest_reg = r1;
    RVXor(tmpi, dest_reg, src1_reg, src2_reg);
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    if (t1 & MDF_REG) dest_reg = r1;
    RVXor(tmpi, dest_reg, src1_reg, RV_REG_T1);
  }
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

/* Shift Operations */

U0 ICShl(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// IC_SHL: Shift left
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg;
  
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  
  if (t3 & MDF_IMM) {
    I64 shamt = d3 & 0x3F; // Mask to 6 bits for RV64
    if (t1 & MDF_REG) dest_reg = r1;
    RVSlli(tmpi, dest_reg, src1_reg, shamt);
  } else {
    U8 src2_reg;
    if (t3 & MDF_REG) {
      src2_reg = r3;
    } else {
      ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
      src2_reg = RV_REG_T1;
    }
    if (t1 & MDF_REG) dest_reg = r1;
    RVSll(tmpi, dest_reg, src1_reg, src2_reg);
  }
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

U0 ICShr(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip,
         Bool is_signed)
{// IC_SHR: Shift right (logical or arithmetic)
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg;
  
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  
  if (t3 & MDF_IMM) {
    I64 shamt = d3 & 0x3F;
    if (t1 & MDF_REG) dest_reg = r1;
    if (is_signed) {
      RVSrai(tmpi, dest_reg, src1_reg, shamt);
    } else {
      RVSrli(tmpi, dest_reg, src1_reg, shamt);
    }
  } else {
    U8 src2_reg;
    if (t3 & MDF_REG) {
      src2_reg = r3;
    } else {
      ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
      src2_reg = RV_REG_T1;
    }
    if (t1 & MDF_REG) dest_reg = r1;
    if (is_signed) {
      RVSra(tmpi, dest_reg, src1_reg, src2_reg);
    } else {
      RVSrl(tmpi, dest_reg, src1_reg, src2_reg);
    }
  }
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

/* Unary Operations */

U0 ICCom(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, I64 rip)
{// IC_COM: Bitwise complement (~)
  U8 dest_reg = RV_REG_A0;
  U8 src_reg;
  
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src_reg = RV_REG_T0;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  RVNot(tmpi, dest_reg, src_reg);
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

U0 ICUnaryMinus(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
                CICType t2, I64 r2, I64 d2, I64 rip)
{// IC_UNARY_MINUS: Negate
  U8 dest_reg = RV_REG_A0;
  U8 src_reg;
  
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src_reg = RV_REG_T0;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  RVNeg(tmpi, dest_reg, src_reg);
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

/* Multiply/Divide - Requires M Extension */

U0 ICMul(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip,
         Bool is_unsigned)
{// IC_MUL: Multiply
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else if (t3 & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, d3);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    src2_reg = RV_REG_T1;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  
  // MUL rd, rs1, rs2 (M extension)
  // Opcode: 0x33, funct3: 0x0, funct7: 0x01
  RVEmitR(tmpi, RV_OP_OP, dest_reg, 0x0, src1_reg, src2_reg, 0x01);
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

U0 ICDiv(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip,
         Bool is_unsigned)
{// IC_DIV: Divide
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else if (t3 & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, d3);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    src2_reg = RV_REG_T1;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  
  // DIV/DIVU rd, rs1, rs2 (M extension)
  // funct3: 0x4 (DIV) or 0x5 (DIVU), funct7: 0x01
  U8 funct3 = is_unsigned ? 0x5 : 0x4;
  RVEmitR(tmpi, RV_OP_OP, dest_reg, funct3, src1_reg, src2_reg, 0x01);
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

U0 ICMod(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip,
         Bool is_unsigned)
{// IC_MOD: Modulo/Remainder
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else if (t3 & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, d3);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    src2_reg = RV_REG_T1;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  
  // REM/REMU rd, rs1, rs2 (M extension)
  // funct3: 0x6 (REM) or 0x7 (REMU), funct7: 0x01
  U8 funct3 = is_unsigned ? 0x7 : 0x6;
  RVEmitR(tmpi, RV_OP_OP, dest_reg, funct3, src1_reg, src2_reg, 0x01);
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

/* LEA - Load Effective Address */

U0 ICLea(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, I64 rip)
{// IC_LEA: Load effective address
  U8 dest_reg = RV_REG_A0;
  
  if (t1 & MDF_REG) dest_reg = r1;
  
  if (t2 & MDF_DISP) {
    // LEA reg, [base + offset]
    if (-2048 <= d2 <= 2047) {
      RVAddi(tmpi, dest_reg, r2, d2);
    } else {
      RVLi(tmpi, RV_REG_T6, d2);
      RVAdd(tmpi, dest_reg, r2, RV_REG_T6);
    }
  } else if (t2 & MDF_IMM) {
    // LEA reg, immediate (just load immediate)
    RVLi(tmpi, dest_reg, d2);
  }
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

#help_index ""

