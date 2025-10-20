/* RISC-V Backend - Floating-Point Operations
 * 
 * Handles floating-point arithmetic using RISC-V F/D extensions.
 * Replaces BackFA.HC and BackFB.HC for RISC-V target.
 */

#help_index "Compiler/Internal/RISCV"

// RISC-V Floating-Point Register Definitions
#define RV_FREG_FT0   0   // f0 - temporary
#define RV_FREG_FT1   1   // f1 - temporary
#define RV_FREG_FT2   2   // f2 - temporary
#define RV_FREG_FT3   3   // f3 - temporary
#define RV_FREG_FT4   4   // f4 - temporary
#define RV_FREG_FT5   5   // f5 - temporary
#define RV_FREG_FT6   6   // f6 - temporary
#define RV_FREG_FT7   7   // f7 - temporary
#define RV_FREG_FS0   8   // f8 - saved
#define RV_FREG_FS1   9   // f9 - saved
#define RV_FREG_FA0   10  // f10 - argument/return
#define RV_FREG_FA1   11  // f11 - argument/return
#define RV_FREG_FA2   12  // f12 - argument
#define RV_FREG_FA3   13  // f13 - argument
#define RV_FREG_FA4   14  // f14 - argument
#define RV_FREG_FA5   15  // f15 - argument
#define RV_FREG_FA6   16  // f16 - argument
#define RV_FREG_FA7   17  // f17 - argument
#define RV_FREG_FS2   18  // f18 - saved
#define RV_FREG_FS3   19  // f19 - saved
#define RV_FREG_FS4   20  // f20 - saved
#define RV_FREG_FS5   21  // f21 - saved
#define RV_FREG_FS6   22  // f22 - saved
#define RV_FREG_FS7   23  // f23 - saved
#define RV_FREG_FS8   24  // f24 - saved
#define RV_FREG_FS9   25  // f25 - saved
#define RV_FREG_FS10  26  // f26 - saved
#define RV_FREG_FS11  27  // f27 - saved
#define RV_FREG_FT8   28  // f28 - temporary
#define RV_FREG_FT9   29  // f29 - temporary
#define RV_FREG_FT10  30  // f30 - temporary
#define RV_FREG_FT11  31  // f31 - temporary

// Rounding modes
#define RV_RM_RNE   0  // Round to nearest, ties to even
#define RV_RM_RTZ   1  // Round towards zero
#define RV_RM_RDN   2  // Round down (towards -∞)
#define RV_RM_RUP   3  // Round up (towards +∞)
#define RV_RM_RMM   4  // Round to nearest, ties to max magnitude
#define RV_RM_DYN   7  // Dynamic rounding mode (use fcsr)

/* Floating-Point Load/Store */

U0 RVFld(CIntermediateCode *tmpi, U8 frd, U8 rs1, I64 offset)
{// FLD frd, offset(rs1) - Load 64-bit float
  RVEmitI(tmpi, RV_OP_LOAD_FP, frd, 0x3, rs1, offset);
}

U0 RVFsd(CIntermediateCode *tmpi, U8 frs2, U8 rs1, I64 offset)
{// FSD frs2, offset(rs1) - Store 64-bit float
  RVEmitS(tmpi, RV_OP_STORE_FP, 0x3, rs1, frs2, offset);
}

/* Floating-Point Arithmetic (Double Precision) */

U0 RVFaddD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{// FADD.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, frs1, frs2, 0x01);
}

U0 RVFsubD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{// FSUB.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, frs1, frs2, 0x05);
}

U0 RVFmulD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{// FMUL.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, frs1, frs2, 0x09);
}

U0 RVFdivD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{// FDIV.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, frs1, frs2, 0x0D);
}

U0 RVFsqrtD(CIntermediateCode *tmpi, U8 frd, U8 frs1)
{// FSQRT.D frd, frs1
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, frs1, 0, 0x2D);
}

U0 RVFsgnjD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{// FSGNJ.D frd, frs1, frs2 (copy sign from frs2 to frs1)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 0, frs1, frs2, 0x11);
}

U0 RVFsgnjnD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{// FSGNJN.D frd, frs1, frs2 (copy negated sign)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 1, frs1, frs2, 0x11);
}

U0 RVFsgnjxD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{// FSGNJX.D frd, frs1, frs2 (XOR signs)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 2, frs1, frs2, 0x11);
}

U0 RVFminD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{// FMIN.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 0, frs1, frs2, 0x15);
}

U0 RVFmaxD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{// FMAX.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 1, frs1, frs2, 0x15);
}

/* Floating-Point Conversion */

U0 RVFcvtDL(CIntermediateCode *tmpi, U8 frd, U8 rs1)
{// FCVT.D.L frd, rs1 (convert signed I64 to F64)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, rs1, 2, 0x69);
}

U0 RVFcvtDLu(CIntermediateCode *tmpi, U8 frd, U8 rs1)
{// FCVT.D.LU frd, rs1 (convert unsigned U64 to F64)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, rs1, 3, 0x69);
}

U0 RVFcvtLD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 rm)
{// FCVT.L.D rd, frs1, rm (convert F64 to signed I64)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, rm, frs1, 2, 0x61);
}

U0 RVFcvtLuD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 rm)
{// FCVT.LU.D rd, frs1, rm (convert F64 to unsigned U64)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, rm, frs1, 3, 0x61);
}

U0 RVFcvtDW(CIntermediateCode *tmpi, U8 frd, U8 rs1)
{// FCVT.D.W frd, rs1 (convert I32 to F64)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, rs1, 0, 0x69);
}

U0 RVFcvtDWu(CIntermediateCode *tmpi, U8 frd, U8 rs1)
{// FCVT.D.WU frd, rs1 (convert U32 to F64)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, rs1, 1, 0x69);
}

U0 RVFcvtWD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 rm)
{// FCVT.W.D rd, frs1, rm (convert F64 to I32)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, rm, frs1, 0, 0x61);
}

U0 RVFcvtWuD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 rm)
{// FCVT.WU.D rd, frs1, rm (convert F64 to U32)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, rm, frs1, 1, 0x61);
}

/* Floating-Point Move */

U0 RVFmvDX(CIntermediateCode *tmpi, U8 frd, U8 rs1)
{// FMV.D.X frd, rs1 (move bits from integer to FP register)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 0, rs1, 0, 0x79);
}

U0 RVFmvXD(CIntermediateCode *tmpi, U8 rd, U8 frs1)
{// FMV.X.D rd, frs1 (move bits from FP to integer register)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, 0, frs1, 0, 0x71);
}

/* Floating-Point Comparison */

U0 RVFeqD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 frs2)
{// FEQ.D rd, frs1, frs2 (equal)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, 2, frs1, frs2, 0x51);
}

U0 RVFltD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 frs2)
{// FLT.D rd, frs1, frs2 (less than)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, 1, frs1, frs2, 0x51);
}

U0 RVFleD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 frs2)
{// FLE.D rd, frs1, frs2 (less than or equal)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, 0, frs1, frs2, 0x51);
}

/* Floating-Point Classify */

U0 RVFclassD(CIntermediateCode *tmpi, U8 rd, U8 frs1)
{// FCLASS.D rd, frs1 (classify floating-point number)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, 1, frs1, 0, 0x71);
}

/* Pseudo-Instructions for FP */

U0 RVFmvD(CIntermediateCode *tmpi, U8 frd, U8 frs)
{// FMV.D frd, frs (pseudo: FSGNJ.D frd, frs, frs)
  RVFsgnjD(tmpi, frd, frs, frs);
}

U0 RVFabsD(CIntermediateCode *tmpi, U8 frd, U8 frs)
{// FABS.D frd, frs (pseudo: FSGNJX.D frd, frs, frs)
  RVFsgnjxD(tmpi, frd, frs, frs);
}

U0 RVFnegD(CIntermediateCode *tmpi, U8 frd, U8 frs)
{// FNEG.D frd, frs (pseudo: FSGNJN.D frd, frs, frs)
  RVFsgnjnD(tmpi, frd, frs, frs);
}

/* High-Level IC Floating-Point Operations */

U0 ICFMov(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, I64 rip)
{// Move F64 value between registers/memory
  if (t2 & MDF_IMM) {
    // Load F64 immediate - move through integer register
    RVLi(tmpi, RV_REG_T6, d2);
    RVFmvDX(tmpi, RV_FREG_FT0, RV_REG_T6);
    if (t1 & MDF_REG) {
      RVFmvD(tmpi, r1, RV_FREG_FT0);
    } else if (t1 & MDF_DISP) {
      if (-2048 <= d1 <= 2047) {
        RVFsd(tmpi, RV_FREG_FT0, r1, d1);
      } else {
        RVLi(tmpi, RV_REG_T6, d1);
        RVAdd(tmpi, RV_REG_T6, r1, RV_REG_T6);
        RVFsd(tmpi, RV_FREG_FT0, RV_REG_T6, 0);
      }
    }
    return;
  }
  
  // FP register to FP register
  if ((t1 & MDF_REG) && (t2 & MDF_REG)) {
    if (r1 != r2) {
      RVFmvD(tmpi, r1, r2);
    }
    return;
  }
  
  // Load from memory to FP register
  if ((t1 & MDF_REG) && (t2 & MDF_DISP)) {
    if (-2048 <= d2 <= 2047) {
      RVFld(tmpi, r1, r2, d2);
    } else {
      RVLi(tmpi, RV_REG_T6, d2);
      RVAdd(tmpi, RV_REG_T6, r2, RV_REG_T6);
      RVFld(tmpi, r1, RV_REG_T6, 0);
    }
    return;
  }
  
  // Store from FP register to memory
  if ((t1 & MDF_DISP) && (t2 & MDF_REG)) {
    if (-2048 <= d1 <= 2047) {
      RVFsd(tmpi, r2, r1, d1);
    } else {
      RVLi(tmpi, RV_REG_T6, d1);
      RVAdd(tmpi, RV_REG_T6, r1, RV_REG_T6);
      RVFsd(tmpi, r2, RV_REG_T6, 0);
    }
    return;
  }
  
  // Memory to memory - use FT0 as temp
  if ((t1 & MDF_DISP) && (t2 & MDF_DISP)) {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT0, 0, t2, r2, d2, rip);
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, RV_FREG_FT0, 0, rip);
    return;
  }
}

U0 ICFAdd(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// IC_ADD for F64
  U8 dest_reg = RV_FREG_FA0;
  U8 src1_reg, src2_reg;
  
  // Load operands into FP registers
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT0, 0, t2, r2, d2, rip);
    src1_reg = RV_FREG_FT0;
  }
  
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT1, 0, t3, r3, d3, rip);
    src2_reg = RV_FREG_FT1;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  RVFaddD(tmpi, dest_reg, src1_reg, src2_reg);
  
  if (!(t1 & MDF_REG)) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, dest_reg, 0, rip);
  }
}

U0 ICFSub(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// IC_SUB for F64
  U8 dest_reg = RV_FREG_FA0;
  U8 src1_reg, src2_reg;
  
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT0, 0, t2, r2, d2, rip);
    src1_reg = RV_FREG_FT0;
  }
  
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT1, 0, t3, r3, d3, rip);
    src2_reg = RV_FREG_FT1;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  RVFsubD(tmpi, dest_reg, src1_reg, src2_reg);
  
  if (!(t1 & MDF_REG)) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, dest_reg, 0, rip);
  }
}

U0 ICFMul(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// IC_MUL for F64
  U8 dest_reg = RV_FREG_FA0;
  U8 src1_reg, src2_reg;
  
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT0, 0, t2, r2, d2, rip);
    src1_reg = RV_FREG_FT0;
  }
  
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT1, 0, t3, r3, d3, rip);
    src2_reg = RV_FREG_FT1;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  RVFmulD(tmpi, dest_reg, src1_reg, src2_reg);
  
  if (!(t1 & MDF_REG)) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, dest_reg, 0, rip);
  }
}

U0 ICFDiv(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// IC_DIV for F64
  U8 dest_reg = RV_FREG_FA0;
  U8 src1_reg, src2_reg;
  
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT0, 0, t2, r2, d2, rip);
    src1_reg = RV_FREG_FT0;
  }
  
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT1, 0, t3, r3, d3, rip);
    src2_reg = RV_FREG_FT1;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  RVFdivD(tmpi, dest_reg, src1_reg, src2_reg);
  
  if (!(t1 & MDF_REG)) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, dest_reg, 0, rip);
  }
}

U0 ICFSqrt(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
           CICType t2, I64 r2, I64 d2, I64 rip)
{// IC_SQRT for F64
  U8 dest_reg = RV_FREG_FA0;
  U8 src_reg;
  
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT0, 0, t2, r2, d2, rip);
    src_reg = RV_FREG_FT0;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  RVFsqrtD(tmpi, dest_reg, src_reg);
  
  if (!(t1 & MDF_REG)) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, dest_reg, 0, rip);
  }
}

U0 ICFAbs(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, I64 rip)
{// IC_ABS for F64
  U8 dest_reg = RV_FREG_FA0;
  U8 src_reg;
  
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT0, 0, t2, r2, d2, rip);
    src_reg = RV_FREG_FT0;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  RVFabsD(tmpi, dest_reg, src_reg);
  
  if (!(t1 & MDF_REG)) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, dest_reg, 0, rip);
  }
}

U0 ICFNeg(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, I64 rip)
{// Negate F64
  U8 dest_reg = RV_FREG_FA0;
  U8 src_reg;
  
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT0, 0, t2, r2, d2, rip);
    src_reg = RV_FREG_FT0;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  RVFnegD(tmpi, dest_reg, src_reg);
  
  if (!(t1 & MDF_REG)) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, dest_reg, 0, rip);
  }
}

/* Floating-Point Conversion Operations */

U0 ICToF64(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
           CICType t2, I64 r2, I64 d2, I64 rip, Bool is_unsigned)
{// IC_TO_F64: Convert integer to F64
  U8 dest_reg = RV_FREG_FA0;
  U8 src_reg;
  
  // Load integer operand
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src_reg = RV_REG_T0;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  
  // Convert I64/U64 to F64
  if (is_unsigned) {
    RVFcvtDLu(tmpi, dest_reg, src_reg);
  } else {
    RVFcvtDL(tmpi, dest_reg, src_reg);
  }
  
  if (!(t1 & MDF_REG)) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, dest_reg, 0, rip);
  }
}

U0 ICToI64(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
           CICType t2, I64 r2, I64 d2, I64 rip, Bool is_unsigned)
{// IC_TO_I64: Convert F64 to integer
  U8 dest_reg = RV_REG_A0;
  U8 src_reg;
  
  // Load F64 operand
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT0, 0, t2, r2, d2, rip);
    src_reg = RV_FREG_FT0;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  
  // Convert F64 to I64/U64 (round toward zero)
  if (is_unsigned) {
    RVFcvtLuD(tmpi, dest_reg, src_reg, RV_RM_RTZ);
  } else {
    RVFcvtLD(tmpi, dest_reg, src_reg, RV_RM_RTZ);
  }
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

/* Floating-Point Comparison */

U0 ICFCmp(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip,
          U8 cmp_type)
{// Compare F64 values and set result
  // cmp_type: 0=EQU, 1=NOT_EQU, 2=LESS, 3=GREATER_EQU, 4=GREATER, 5=LESS_EQU
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  // Load operands
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT0, 0, t2, r2, d2, rip);
    src1_reg = RV_FREG_FT0;
  }
  
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FT1, 0, t3, r3, d3, rip);
    src2_reg = RV_FREG_FT1;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  
  switch (cmp_type) {
    case 0: // EQU: a == b
      RVFeqD(tmpi, dest_reg, src1_reg, src2_reg);
      break;
      
    case 1: // NOT_EQU: a != b
      RVFeqD(tmpi, dest_reg, src1_reg, src2_reg);
      RVXori(tmpi, dest_reg, dest_reg, 1); // Invert result
      break;
      
    case 2: // LESS: a < b
      RVFltD(tmpi, dest_reg, src1_reg, src2_reg);
      break;
      
    case 3: // GREATER_EQU: a >= b  ==  !(a < b)
      RVFltD(tmpi, dest_reg, src1_reg, src2_reg);
      RVXori(tmpi, dest_reg, dest_reg, 1);
      break;
      
    case 4: // GREATER: a > b  ==  b < a
      RVFltD(tmpi, dest_reg, src2_reg, src1_reg);
      break;
      
    case 5: // LESS_EQU: a <= b
      RVFleD(tmpi, dest_reg, src1_reg, src2_reg);
      break;
  }
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

/* Transcendental Functions (Software Implementation Required) */

// These require software library implementations since RISC-V has no
// hardware support for sin/cos/tan/atan/etc.
// For now, provide stubs that call runtime library functions.

U0 ICFSin(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, I64 rip)
{// IC_SIN: sin(x) - requires libm
  // Load argument into fa0
  if (!(t2 & MDF_REG) || r2 != RV_FREG_FA0) {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FA0, 0, t2, r2, d2, rip);
  }
  
  // Call sin() from math library
  // This requires linking with libm and having the function available
  // For now, just emit a placeholder CALL instruction
  // In a real implementation, this would be:
  // ICCall(tmpi, sin_function_address, rip);
  
  // TODO: Implement software sin() or link to libm
  // For now, result is in fa0
  
  // Store result
  if (!(t1 & MDF_REG) || r1 != RV_FREG_FA0) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, RV_FREG_FA0, 0, rip);
  }
}

U0 ICFCos(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, I64 rip)
{// IC_COS: cos(x) - requires libm
  if (!(t2 & MDF_REG) || r2 != RV_FREG_FA0) {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FA0, 0, t2, r2, d2, rip);
  }
  // TODO: Call cos() from libm
  if (!(t1 & MDF_REG) || r1 != RV_FREG_FA0) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, RV_FREG_FA0, 0, rip);
  }
}

U0 ICFTan(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, I64 rip)
{// IC_TAN: tan(x) - requires libm
  if (!(t2 & MDF_REG) || r2 != RV_FREG_FA0) {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FA0, 0, t2, r2, d2, rip);
  }
  // TODO: Call tan() from libm
  if (!(t1 & MDF_REG) || r1 != RV_FREG_FA0) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, RV_FREG_FA0, 0, rip);
  }
}

U0 ICFAtan(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
           CICType t2, I64 r2, I64 d2, I64 rip)
{// IC_ATAN: atan(x) - requires libm
  if (!(t2 & MDF_REG) || r2 != RV_FREG_FA0) {
    ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FA0, 0, t2, r2, d2, rip);
  }
  // TODO: Call atan() from libm
  if (!(t1 & MDF_REG) || r1 != RV_FREG_FA0) {
    ICFMov(tmpi, t1, r1, d1, MDF_REG+RT_F64, RV_FREG_FA0, 0, rip);
  }
}

#help_index ""


