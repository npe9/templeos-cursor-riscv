/* RISC-V Backend - Floating-Point Operations
 * 
 * Handles floating-point arithmetic using RISC-V F/D extensions.
 * Replaces BackFA.HC and BackFB.HC for RISC-V target.
 */
#help_index "Compiler/Internal/RISCV"
/* Kernel F64 runtime for the transcendental/power ICs (host AOT lowers the
 * _intern Sin/Cos/… to its runtime; guest JIT calls these Kernel wrappers). */
/* Kernel fills this before CInit (RVCmpSetF64Rt): 0 Sin, 1 Cos, 2 Tan, 3 ATan, 4 Pow.
 * A cross-unit `&RVF64Sin` from here is an unresolved HOFYIMP1 slot in the win blob. */
I64 rv_f64_rt[8];
public U0 RVCmpSetF64Rt(I64 *tbl)
{
  I64 i;
  for (i = 0; i < 8; i++)
    rv_f64_rt[i] = tbl[i];
}
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
{
  // FLD frd, offset(rs1) - Load 64-bit float
  RVEmitI(tmpi, RV_OP_LOAD_FP, frd, 0x3, rs1, offset);
}

U0 RVFsd(CIntermediateCode *tmpi, U8 frs2, U8 rs1, I64 offset)
{
  // FSD frs2, offset(rs1) - Store 64-bit float
  RVEmitS(tmpi, RV_OP_STORE_FP, 0x3, rs1, frs2, offset);
}
/* Floating-Point Arithmetic (Double Precision) */
U0 RVFaddD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{
  // FADD.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, frs1, frs2, 0x01);
}

U0 RVFsubD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{
  // FSUB.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, frs1, frs2, 0x05);
}

U0 RVFmulD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{
  // FMUL.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, frs1, frs2, 0x09);
}

U0 RVFdivD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{
  // FDIV.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, frs1, frs2, 0x0D);
}

U0 RVFsqrtD(CIntermediateCode *tmpi, U8 frd, U8 frs1)
{
  // FSQRT.D frd, frs1
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, frs1, 0, 0x2D);
}

U0 RVFsgnjD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{
  // FSGNJ.D frd, frs1, frs2 (copy sign from frs2 to frs1)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 0, frs1, frs2, 0x11);
}

U0 RVFsgnjnD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{
  // FSGNJN.D frd, frs1, frs2 (copy negated sign)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 1, frs1, frs2, 0x11);
}

U0 RVFsgnjxD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{
  // FSGNJX.D frd, frs1, frs2 (XOR signs)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 2, frs1, frs2, 0x11);
}

U0 RVFminD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{
  // FMIN.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 0, frs1, frs2, 0x15);
}

U0 RVFmaxD(CIntermediateCode *tmpi, U8 frd, U8 frs1, U8 frs2)
{
  // FMAX.D frd, frs1, frs2
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 1, frs1, frs2, 0x15);
}
/* Floating-Point Conversion */
U0 RVFcvtDL(CIntermediateCode *tmpi, U8 frd, U8 rs1)
{
  // FCVT.D.L frd, rs1 (convert signed I64 to F64)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, rs1, 2, 0x69);
}

U0 RVFcvtDLu(CIntermediateCode *tmpi, U8 frd, U8 rs1)
{
  // FCVT.D.LU frd, rs1 (convert unsigned U64 to F64)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, rs1, 3, 0x69);
}

U0 RVFcvtLD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 rm)
{
  // FCVT.L.D rd, frs1, rm (convert F64 to signed I64)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, rm, frs1, 2, 0x61);
}

U0 RVFcvtLuD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 rm)
{
  // FCVT.LU.D rd, frs1, rm (convert F64 to unsigned U64)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, rm, frs1, 3, 0x61);
}

U0 RVFcvtDW(CIntermediateCode *tmpi, U8 frd, U8 rs1)
{
  // FCVT.D.W frd, rs1 (convert I32 to F64)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, rs1, 0, 0x69);
}

U0 RVFcvtDWu(CIntermediateCode *tmpi, U8 frd, U8 rs1)
{
  // FCVT.D.WU frd, rs1 (convert U32 to F64)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, RV_RM_DYN, rs1, 1, 0x69);
}

U0 RVFcvtWD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 rm)
{
  // FCVT.W.D rd, frs1, rm (convert F64 to I32)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, rm, frs1, 0, 0x61);
}

U0 RVFcvtWuD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 rm)
{
  // FCVT.WU.D rd, frs1, rm (convert F64 to U32)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, rm, frs1, 1, 0x61);
}
/* Floating-Point Move */
U0 RVFmvDX(CIntermediateCode *tmpi, U8 frd, U8 rs1)
{
  // FMV.D.X frd, rs1 (move bits from integer to FP register)
  RVEmitR(tmpi, RV_OP_OP_FP, frd, 0, rs1, 0, 0x79);
}

U0 RVFmvXD(CIntermediateCode *tmpi, U8 rd, U8 frs1)
{
  // FMV.X.D rd, frs1 (move bits from FP to integer register)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, 0, frs1, 0, 0x71);
}
/* Floating-Point Comparison */
U0 RVFeqD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 frs2)
{
  // FEQ.D rd, frs1, frs2 (equal)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, 2, frs1, frs2, 0x51);
}

U0 RVFltD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 frs2)
{
  // FLT.D rd, frs1, frs2 (less than)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, 1, frs1, frs2, 0x51);
}

U0 RVFleD(CIntermediateCode *tmpi, U8 rd, U8 frs1, U8 frs2)
{
  // FLE.D rd, frs1, frs2 (less than or equal)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, 0, frs1, frs2, 0x51);
}
/* Floating-Point Classify */
U0 RVFclassD(CIntermediateCode *tmpi, U8 rd, U8 frs1)
{
  // FCLASS.D rd, frs1 (classify floating-point number)
  RVEmitR(tmpi, RV_OP_OP_FP, rd, 1, frs1, 0, 0x71);
}
/* Pseudo-Instructions for FP */
U0 RVFmvD(CIntermediateCode *tmpi, U8 frd, U8 frs)
{
  // FMV.D frd, frs (pseudo: FSGNJ.D frd, frs, frs)
  RVFsgnjD(tmpi, frd, frs, frs);
}

U0 RVFabsD(CIntermediateCode *tmpi, U8 frd, U8 frs)
{
  // FABS.D frd, frs (pseudo: FSGNJX.D frd, frs, frs)
  RVFsgnjxD(tmpi, frd, frs, frs);
}

U0 RVFnegD(CIntermediateCode *tmpi, U8 frd, U8 frs)
{
  // FNEG.D frd, frs (pseudo: FSGNJN.D frd, frs, frs)
  RVFsgnjnD(tmpi, frd, frs, frs);
}
/* High-Level IC Floating-Point Operations */
/* F64 operand convention (stock x86 / host AOT): an F64 IC operand in MDF_REG is an
 * INTEGER register holding the raw bits; stack slots and memory hold the bits too.
 * FP registers are transient: ICFLoad brings an operand into an FP reg, ICFStore
 * writes one back. arg2 is on top of the eval stack, so load it before arg1. */
U0 ICFLoad(CIntermediateCode *tmpi, U8 freg, CICType t, I64 r, I64 d, I64 rip)
{
  if (t & MDF_REG)
    RVFmvDX(tmpi, freg, r);
  else if (t & MDF_IMM) {
    RVLi(tmpi, RV_REG_T6, d);
    RVFmvDX(tmpi, freg, RV_REG_T6);
  } else if (t & MDF_STK) {
    RVFld(tmpi, freg, RV_REG_SP, 0);
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 8);
  } else if (t & MDF_RIP_DISP32) {
    RVEmitRipAddr(tmpi, RV_REG_T6, d, rip);
    RVFld(tmpi, freg, RV_REG_T6, 0);
  } else if (t & MDF_DISP) {
    if (-2048 <= d <= 2047)
      RVFld(tmpi, freg, r, d);
    else {
      RVLi(tmpi, RV_REG_T6, d);
      RVAdd(tmpi, RV_REG_T6, r, RV_REG_T6);
      RVFld(tmpi, freg, RV_REG_T6, 0);
    }
  } else {
    // SIB etc.: let ICMov compute/load the bits, then move in.
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T6, 0, t, r, d, rip);
    RVFmvDX(tmpi, freg, RV_REG_T6);
  }
}

U0 ICFStore(CIntermediateCode *tmpi, CICType t, I64 r, I64 d, U8 freg, I64 rip)
{
  if (!t.mode)
    return;
  if (t & MDF_REG)
    RVFmvXD(tmpi, r, freg);
  else if (t & MDF_STK) {
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -8);
    RVFsd(tmpi, freg, RV_REG_SP, 0);
  } else if (t & MDF_RIP_DISP32) {
    RVEmitRipAddr(tmpi, RV_REG_T5, d, rip);
    RVFsd(tmpi, freg, RV_REG_T5, 0);
  } else if (t & MDF_DISP) {
    if (-2048 <= d <= 2047)
      RVFsd(tmpi, freg, r, d);
    else {
      RVLi(tmpi, RV_REG_T6, d);
      RVAdd(tmpi, RV_REG_T6, r, RV_REG_T6);
      RVFsd(tmpi, freg, RV_REG_T6, 0);
    }
  } else {
    RVFmvXD(tmpi, RV_REG_T6, freg);
    ICMov(tmpi, t, r, d, MDF_REG + RT_I64, RV_REG_T6, 0, rip);
  }
}

U0 ICFMov(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // Bits are bits: a plain integer move implements every F64 move.
  ICMov(tmpi, t1, r1, d1, t2, r2, d2, rip);
}
/* op: 0 add, 1 sub, 2 mul, 3 div */
U0 ICFArith(CIntermediateCode *tmpi, I64 op, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  ICFLoad(tmpi, RV_FREG_FT1, t3, r3, d3, rip);
  ICFLoad(tmpi, RV_FREG_FT0, t2, r2, d2, rip);
  if (op == 0)
    RVFaddD(tmpi, RV_FREG_FT0, RV_FREG_FT0, RV_FREG_FT1);
  else if (op == 1)
    RVFsubD(tmpi, RV_FREG_FT0, RV_FREG_FT0, RV_FREG_FT1);
  else if (op == 2)
    RVFmulD(tmpi, RV_FREG_FT0, RV_FREG_FT0, RV_FREG_FT1);
  else
    RVFdivD(tmpi, RV_FREG_FT0, RV_FREG_FT0, RV_FREG_FT1);
  ICFStore(tmpi, t1, r1, d1, RV_FREG_FT0, rip);
}

U0 ICFAdd(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  ICFArith(tmpi, 0, t1, r1, d1, t2, r2, d2, t3, r3, d3, rip);
}

U0 ICFSub(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  ICFArith(tmpi, 1, t1, r1, d1, t2, r2, d2, t3, r3, d3, rip);
}

U0 ICFMul(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  ICFArith(tmpi, 2, t1, r1, d1, t2, r2, d2, t3, r3, d3, rip);
}

U0 ICFDiv(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  ICFArith(tmpi, 3, t1, r1, d1, t2, r2, d2, t3, r3, d3, rip);
}

U0 ICFSqrt(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  ICFLoad(tmpi, RV_FREG_FT0, t2, r2, d2, rip);
  RVFsqrtD(tmpi, RV_FREG_FT0, RV_FREG_FT0);
  ICFStore(tmpi, t1, r1, d1, RV_FREG_FT0, rip);
}

U0 ICFAbs(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  ICFLoad(tmpi, RV_FREG_FT0, t2, r2, d2, rip);
  RVFabsD(tmpi, RV_FREG_FT0, RV_FREG_FT0);
  ICFStore(tmpi, t1, r1, d1, RV_FREG_FT0, rip);
}

U0 ICFNeg(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  ICFLoad(tmpi, RV_FREG_FT0, t2, r2, d2, rip);
  RVFnegD(tmpi, RV_FREG_FT0, RV_FREG_FT0);
  ICFStore(tmpi, t1, r1, d1, RV_FREG_FT0, rip);
}

U0 ICToF64(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip, Bool is_unsigned)
{
  // IC_TO_F64: integer (bits in int reg/mem) -> F64 bits
  U8 src_reg = RVLoadToReg(tmpi, RV_REG_T0, t2, r2, d2, rip);
  if (is_unsigned)
    RVFcvtDLu(tmpi, RV_FREG_FT0, src_reg);
  else
    RVFcvtDL(tmpi, RV_FREG_FT0, src_reg);
  ICFStore(tmpi, t1, r1, d1, RV_FREG_FT0, rip);
}

U0 ICToI64(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip, Bool is_unsigned)
{
  // IC_TO_I64: F64 -> integer, round toward zero (HolyC truncates)
  ICFLoad(tmpi, RV_FREG_FT0, t2, r2, d2, rip);
  if (is_unsigned)
    RVFcvtLuD(tmpi, RV_REG_A0, RV_FREG_FT0, RV_RM_RTZ);
  else
    RVFcvtLD(tmpi, RV_REG_A0, RV_FREG_FT0, RV_RM_RTZ);
  if (t1.mode)
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}

U0 ICFCmp(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip, U8 cmp_type)
{
  // cmp_type: 0=EQU, 1=NOT_EQU, 2=LESS, 3=GREATER_EQU, 4=GREATER, 5=LESS_EQU
  ICFLoad(tmpi, RV_FREG_FT1, t3, r3, d3, rip);
  ICFLoad(tmpi, RV_FREG_FT0, t2, r2, d2, rip);
  switch (cmp_type) {
    case 0 :
    RVFeqD(tmpi, RV_REG_A0, RV_FREG_FT0, RV_FREG_FT1);
    break;
    case 1 :
    RVFeqD(tmpi, RV_REG_A0, RV_FREG_FT0, RV_FREG_FT1);
    RVXori(tmpi, RV_REG_A0, RV_REG_A0, 1);
    break;
    case 2 :
    RVFltD(tmpi, RV_REG_A0, RV_FREG_FT0, RV_FREG_FT1);
    break;
    case 3 :
    RVFltD(tmpi, RV_REG_A0, RV_FREG_FT0, RV_FREG_FT1);
    RVXori(tmpi, RV_REG_A0, RV_REG_A0, 1);
    break;
    case 4 :
    RVFltD(tmpi, RV_REG_A0, RV_FREG_FT1, RV_FREG_FT0);
    break;
    default:
    RVFleD(tmpi, RV_REG_A0, RV_FREG_FT0, RV_FREG_FT1);
  }
  if (t1.mode)
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}
/* F64 runtime call, host convention: bits in a0 (a1), result bits in a0.
 * ICCall saves/restores ra around the call. */
U0 ICFRtCall1(CIntermediateCode *tmpi, I64 fn, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_A0, 0, t2, r2, d2, rip);
  if (fn)
    ICCall(tmpi, fn, rip);
  if (t1.mode)
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}

U0 ICFSin(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  ICFRtCall1(tmpi, rv_f64_rt[0], t1, r1, d1, t2, r2, d2, rip);
}

U0 ICFCos(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  ICFRtCall1(tmpi, rv_f64_rt[1], t1, r1, d1, t2, r2, d2, rip);
}

U0 ICFTan(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  ICFRtCall1(tmpi, rv_f64_rt[2], t1, r1, d1, t2, r2, d2, rip);
}

U0 ICFAtan(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  ICFRtCall1(tmpi, rv_f64_rt[3], t1, r1, d1, t2, r2, d2, rip);
}

U0 ICFPow(CIntermediateCode *tmpi, I64 rip)
{
  // IC_POWER (a`b): OptPass012 makes both operands F64. arg2 (exponent) is on top.
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_A1, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_A0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  if (rv_f64_rt[4])
    ICCall(tmpi, rv_f64_rt[4], rip);
  if (tmpi->res.type.mode)
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}

U0 ICFSqr(CIntermediateCode *tmpi, I64 rip)
{
  // Sqr(d): d*d
  ICFLoad(tmpi, RV_FREG_FT0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  RVFmulD(tmpi, RV_FREG_FT0, RV_FREG_FT0, RV_FREG_FT0);
  ICFStore(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, RV_FREG_FT0, rip);
}
