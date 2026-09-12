/* RISC-V Backend - Basic Operations
 * 
 * Translates IC operations to RISC-V machine code.
 * Replaces BackA.HC for RISC-V target.
 */
#help_index "Compiler/Internal/RISCV"
/* PC-rel materialize for MDF_RIP_DISP32 (AOT data_rip or JIT abs). */
U0 RVEmitRipAddr(CIntermediateCode *tmpi, U8 rd, I64 abs_val, I64 rip)
{
  I64 offset, hi, lo;
  offset = abs_val - rip - tmpi->ic_cnt;
  hi = (offset + 0x800) >> 12;
  lo = offset - (hi << 12);
  RVAuipc(tmpi, rd, hi);
  RVAddi(tmpi, rd, rd, lo);
}
/* IC Move Operation - Core data movement function */
extern U0 ICLea(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip);
extern U0 ICRVStoreThru(CIntermediateCode *tmpi, I64 pt, I64 addr_reg, I64 addr_disp, CICType t2, I64 r2, I64 d2, I64 rip);
U0 ICMov(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // Move/load/store data between registers and memory
  // t1,r1,d1 = destination type, register, displacement
  // t2,r2,d2 = source type, register, displacement
  I64 raw_type1 = t1.raw_type;
  I64 raw_type2 = t2.raw_type;
  // Handle immediate source
  if (t2 & MDF_IMM) {
    // Load immediate into register
    if (t1 & MDF_REG) {
      RVLi(tmpi, r1, d2);
    } else if (t1 & MDF_STK) {
      // Arg push: OptPass4 turns IC_IMM→IC_MOV with res=STK; must push imm.
      // Leave value in a0 too (RISC-V 1-arg ABI / host EmitLoadArgs skips ld for N<2).
      RVLi(tmpi, RV_REG_A0, d2);
      RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -8);
      RVSd(tmpi, RV_REG_A0, RV_REG_SP, 0);
    } else if (t1 & MDF_RIP_DISP32) {
      // Folded ABS/JIT global: imm first (64-bit RVLi scratches T5), then PC-rel addr.
      RVLi(tmpi, RV_REG_T6, d2);
      RVEmitRipAddr(tmpi, RV_REG_T5, d1, rip);
      switch (raw_type1) {
        case RT_I8 :
        case RT_U8 :
        RVSb(tmpi, RV_REG_T6, RV_REG_T5, 0);
        break;
        case RT_I16 :
        case RT_U16 :
        RVSh(tmpi, RV_REG_T6, RV_REG_T5, 0);
        break;
        case RT_I32 :
        case RT_U32 :
        RVSw(tmpi, RV_REG_T6, RV_REG_T5, 0);
        break;
        default:
        RVSd(tmpi, RV_REG_T6, RV_REG_T5, 0);
      }
    } else if (t1 & MDF_DISP) {
      // Store immediate to memory via temp register
      RVLi(tmpi, RV_REG_T6, d2);
      switch (raw_type1) {
        case RT_I8 :
        case RT_U8 :
        RVSb(tmpi, RV_REG_T6, r1, d1);
        break;
        case RT_I16 :
        case RT_U16 :
        RVSh(tmpi, RV_REG_T6, r1, d1);
        break;
        case RT_I32 :
        case RT_U32 :
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
    if (d2 >= -2048 && d2 <= 2047) {
      switch (raw_type2) {
        case RT_I8 :
        RVLb(tmpi, r1, r2, d2);
        break;
        case RT_U8 :
        RVLbu(tmpi, r1, r2, d2);
        break;
        case RT_I16 :
        RVLh(tmpi, r1, r2, d2);
        break;
        case RT_U16 :
        RVLhu(tmpi, r1, r2, d2);
        break;
        case RT_I32 :
        RVLw(tmpi, r1, r2, d2);
        break;
        case RT_U32 :
        RVLwu(tmpi, r1, r2, d2);
        break;
        default:
        // I64, U64, PTR
        RVLd(tmpi, r1, r2, d2);
      }
    } else {
      // Large offset - compute address first
      RVLi(tmpi, RV_REG_T6, d2);
      RVAdd(tmpi, RV_REG_T6, r2, RV_REG_T6);
      switch (raw_type2) {
        case RT_I8 :
        RVLb(tmpi, r1, RV_REG_T6, 0);
        break;
        case RT_U8 :
        RVLbu(tmpi, r1, RV_REG_T6, 0);
        break;
        case RT_I16 :
        RVLh(tmpi, r1, RV_REG_T6, 0);
        break;
        case RT_U16 :
        RVLhu(tmpi, r1, RV_REG_T6, 0);
        break;
        case RT_I32 :
        RVLw(tmpi, r1, RV_REG_T6, 0);
        break;
        case RT_U32 :
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
    if (d1 >= -2048 && d1 <= 2047) {
      switch (raw_type1) {
        case RT_I8 :
        case RT_U8 :
        RVSb(tmpi, r2, r1, d1);
        break;
        case RT_I16 :
        case RT_U16 :
        RVSh(tmpi, r2, r1, d1);
        break;
        case RT_I32 :
        case RT_U32 :
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
        case RT_I8 :
        case RT_U8 :
        RVSb(tmpi, r2, RV_REG_T6, 0);
        break;
        case RT_I16 :
        case RT_U16 :
        RVSh(tmpi, r2, RV_REG_T6, 0);
        break;
        case RT_I32 :
        case RT_U32 :
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
    ICMov(tmpi, MDF_REG + raw_type2, RV_REG_T6, 0, t2, r2, d2, rip);
    // Store from temp
    ICMov(tmpi, t1, r1, d1, MDF_REG + raw_type1, RV_REG_T6, 0, rip);
    return;
  }
  // RIP before STK: MDF_RIP_DISP32 must not fall into the push path
  // (for-loop `s=s+i` was lea + push instead of sd).
  if (t1 & MDF_RIP_DISP32) {
    // Value before address: a 64-bit imm/load into T6 scratches T5.
    if (!(t2 & MDF_REG)) {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T6, 0, t2, r2, d2, rip);
      r2 = RV_REG_T6;
    }
    RVEmitRipAddr(tmpi, RV_REG_T5, d1, rip);
    switch (raw_type1) {
      case RT_I8 :
      case RT_U8 :
      RVSb(tmpi, r2, RV_REG_T5, 0);
      break;
      case RT_I16 :
      case RT_U16 :
      RVSh(tmpi, r2, RV_REG_T5, 0);
      break;
      case RT_I32 :
      case RT_U32 :
      RVSw(tmpi, r2, RV_REG_T5, 0);
      break;
      default:
      RVSd(tmpi, r2, RV_REG_T5, 0);
    }
    return;
  }
  if (t2 & MDF_RIP_DISP32) {
    RVEmitRipAddr(tmpi, RV_REG_T6, d2, rip);
    switch (raw_type2) {
      case RT_I8 :
      RVLb(tmpi, RV_REG_T0, RV_REG_T6, 0);
      break;
      case RT_U8 :
      RVLbu(tmpi, RV_REG_T0, RV_REG_T6, 0);
      break;
      case RT_I16 :
      RVLh(tmpi, RV_REG_T0, RV_REG_T6, 0);
      break;
      case RT_U16 :
      RVLhu(tmpi, RV_REG_T0, RV_REG_T6, 0);
      break;
      case RT_I32 :
      RVLw(tmpi, RV_REG_T0, RV_REG_T6, 0);
      break;
      case RT_U32 :
      RVLwu(tmpi, RV_REG_T0, RV_REG_T6, 0);
      break;
      default:
      RVLd(tmpi, RV_REG_T0, RV_REG_T6, 0);
    }
    if (t1 & MDF_REG)
      RVMv(tmpi, r1, RV_REG_T0);
    else if (t1 & MDF_STK) {
      RVMv(tmpi, RV_REG_A0, RV_REG_T0);
      RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -8);
      RVSd(tmpi, RV_REG_A0, RV_REG_SP, 0);
    } else
      ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
    return;
  }
  // Stack operations - should be handled by pass 6
  if (t1 & MDF_STK) {
    // Push value (REG or via temp). Direct RVSd — nested ICMov(DISP) hung
    // guest Cmp when pushing STR_CONST call args.
    // Leave value in a0 like IMM→STK path — Soft CALL remat of local args
    // (MenuFpOk good fp) often sees empty FP push slots; 1-arg ABI needs a0.
    if (!(t2 & MDF_REG)) {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_A0, 0, t2, r2, d2, rip);
      r2 = RV_REG_A0;
    } else if (r2 != RV_REG_A0) {
      RVMv(tmpi, RV_REG_A0, r2);
      r2 = RV_REG_A0;
    }
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -8);
    RVSd(tmpi, r2, RV_REG_SP, 0);
    return;
  }
  if (t2 & MDF_STK) {
    /* Pop. Soft VarRmw: nested ICMov(REG←DISP+SP) Soft-hung; ld sp directly. */
    if (t1 & MDF_REG) {
      RVLd(tmpi, r1, RV_REG_SP, 0);
      RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 8);
      return;
    }
    RVLd(tmpi, RV_REG_T6, RV_REG_SP, 0);
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 8);
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, RV_REG_T6, 0, rip);
    return;
  }
  // SIB: [base + index<<scale + disp] (OptPass4 array index)
  if (t2 & MDF_SIB) {
    ICLea(tmpi, MDF_REG + RT_I64, RV_REG_T6, 0, t2, r2, d2, rip);
    ICMov(tmpi, t1, r1, d1, MDF_DISP + raw_type2, RV_REG_T6, 0, rip);
    return;
  }
  if (t1 & MDF_SIB) {
    /* StoreThru: nested ICMov(MDF_DISP+raw) CICType trap for U8/U16 (Ident). */
    ICLea(tmpi, MDF_REG + RT_I64, RV_REG_T5, 0, t1, r1, d1, rip);
    ICRVStoreThru(tmpi, raw_type1, RV_REG_T5, 0, t2, r2, d2, rip);
    return;
  }
}
/* Arithmetic Operations */
/* Load CICArg into a GPR. Soft VarRmw: ICMov(REG←STK) Soft-hung on nested
 * ICMov(DISP+SP); pop with ld. Used by ICAdd/ICAnd/… for STK args. */
U8 RVLoadToReg(CIntermediateCode *tmpi, U8 dest, CICType t, I64 r, I64 d, I64 rip)
{
  if (t & MDF_REG)
    return r;
  if (t & MDF_STK) {
    RVLd(tmpi, dest, RV_REG_SP, 0);
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 8);
    return dest;
  }
  ICMov(tmpi, MDF_REG + RT_I64, dest, 0, t, r, d, rip);
  return dest;
}

U0 ICAdd(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  // IC_ADD: t1/r1/d1 = t2/r2/d2 + t3/r3/d3
  // n+n multi-use is handled in ICLea (OptPass4 folds n+n → SIB LEA).
  U8 dest_reg = RV_REG_A0;
  // Default to a0 for results
  U8 src1_reg, src2_reg;
  src1_reg = RVLoadToReg(tmpi, RV_REG_T0, t2, r2, d2, rip);
  if (t3 & MDF_IMM) {
    // Immediate add
    I64 imm = d3;
    if (imm >= -2048 && imm <= 2047) {
      if (t1 & MDF_REG)
        dest_reg = r1;
      RVAddi(tmpi, dest_reg, src1_reg, imm);
    } else {
      // Large immediate
      RVLi(tmpi, RV_REG_T1, imm);
      if (t1 & MDF_REG)
        dest_reg = r1;
      RVAdd(tmpi, dest_reg, src1_reg, RV_REG_T1);
    }
  } else if (t3 & MDF_REG) {
    src2_reg = r3;
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVAdd(tmpi, dest_reg, src1_reg, src2_reg);
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVAdd(tmpi, dest_reg, src1_reg, RV_REG_T1);
  }
  // Store result if needed
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}

U0 ICSub(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  // IC_SUB: t1/r1/d1 = t2/r2/d2 - t3/r3/d3
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  src1_reg = RVLoadToReg(tmpi, RV_REG_T0, t2, r2, d2, rip);
  if (t3 & MDF_IMM) {
    // Subtract immediate: ADD with negated immediate
    I64 imm = -d3;
    if (imm >= -2048 && imm <= 2047) {
      if (t1 & MDF_REG)
        dest_reg = r1;
      RVAddi(tmpi, dest_reg, src1_reg, imm);
    } else {
      RVLi(tmpi, RV_REG_T1, d3);
      if (t1 & MDF_REG)
        dest_reg = r1;
      RVSub(tmpi, dest_reg, src1_reg, RV_REG_T1);
    }
  } else if (t3 & MDF_REG) {
    src2_reg = r3;
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVSub(tmpi, dest_reg, src1_reg, src2_reg);
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVSub(tmpi, dest_reg, src1_reg, RV_REG_T1);
  }
  // Store result
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}
/* Bitwise Operations */
U0 ICAnd(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  // IC_AND: t1/r1/d1 = t2/r2/d2 & t3/r3/d3
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  src1_reg = RVLoadToReg(tmpi, RV_REG_T0, t2, r2, d2, rip);
  if (t3 & MDF_IMM) {
    I64 imm = d3;
    if (imm >= -2048 && imm <= 2047) {
      if (t1 & MDF_REG)
        dest_reg = r1;
      RVAndi(tmpi, dest_reg, src1_reg, imm);
    } else {
      RVLi(tmpi, RV_REG_T1, imm);
      if (t1 & MDF_REG)
        dest_reg = r1;
      RVAnd(tmpi, dest_reg, src1_reg, RV_REG_T1);
    }
  } else if (t3 & MDF_REG) {
    src2_reg = r3;
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVAnd(tmpi, dest_reg, src1_reg, src2_reg);
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVAnd(tmpi, dest_reg, src1_reg, RV_REG_T1);
  }
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}

U0 ICOr(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  // IC_OR
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  src1_reg = RVLoadToReg(tmpi, RV_REG_T0, t2, r2, d2, rip);
  if (t3 & MDF_IMM) {
    I64 imm = d3;
    if (imm >= -2048 && imm <= 2047) {
      if (t1 & MDF_REG)
        dest_reg = r1;
      RVOri(tmpi, dest_reg, src1_reg, imm);
    } else {
      RVLi(tmpi, RV_REG_T1, imm);
      if (t1 & MDF_REG)
        dest_reg = r1;
      RVOr(tmpi, dest_reg, src1_reg, RV_REG_T1);
    }
  } else if (t3 & MDF_REG) {
    src2_reg = r3;
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVOr(tmpi, dest_reg, src1_reg, src2_reg);
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVOr(tmpi, dest_reg, src1_reg, RV_REG_T1);
  }
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}

U0 ICXor(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  // IC_XOR
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  src1_reg = RVLoadToReg(tmpi, RV_REG_T0, t2, r2, d2, rip);
  if (t3 & MDF_IMM) {
    I64 imm = d3;
    if (imm >= -2048 && imm <= 2047) {
      if (t1 & MDF_REG)
        dest_reg = r1;
      RVXori(tmpi, dest_reg, src1_reg, imm);
    } else {
      RVLi(tmpi, RV_REG_T1, imm);
      if (t1 & MDF_REG)
        dest_reg = r1;
      RVXor(tmpi, dest_reg, src1_reg, RV_REG_T1);
    }
  } else if (t3 & MDF_REG) {
    src2_reg = r3;
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVXor(tmpi, dest_reg, src1_reg, src2_reg);
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVXor(tmpi, dest_reg, src1_reg, RV_REG_T1);
  }
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}
/* Shift Operations */
U0 ICShl(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  // IC_SHL: Shift left
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg;
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  if (t3 & MDF_IMM) {
    I64 shamt = d3 & 0x3F;
    // Mask to 6 bits for RV64
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVSlli(tmpi, dest_reg, src1_reg, shamt);
  } else {
    U8 src2_reg;
    if (t3 & MDF_REG) {
      src2_reg = r3;
    } else {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
      src2_reg = RV_REG_T1;
    }
    if (t1 & MDF_REG)
      dest_reg = r1;
    RVSll(tmpi, dest_reg, src1_reg, src2_reg);
  }
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}

U0 ICShr(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip, Bool is_signed)
{
  // IC_SHR: Shift right (logical or arithmetic)
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg;
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  if (t3 & MDF_IMM) {
    I64 shamt = d3 & 0x3F;
    if (t1 & MDF_REG)
      dest_reg = r1;
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
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
      src2_reg = RV_REG_T1;
    }
    if (t1 & MDF_REG)
      dest_reg = r1;
    if (is_signed) {
      RVSra(tmpi, dest_reg, src1_reg, src2_reg);
    } else {
      RVSrl(tmpi, dest_reg, src1_reg, src2_reg);
    }
  }
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}
/* Unary Operations */
U0 ICCom(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // IC_COM: Bitwise complement (~)
  U8 dest_reg = RV_REG_A0;
  U8 src_reg;
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src_reg = RV_REG_T0;
  }
  if (t1 & MDF_REG)
    dest_reg = r1;
  RVNot(tmpi, dest_reg, src_reg);
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}

U0 ICUnaryMinus(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // IC_UNARY_MINUS: Negate
  U8 dest_reg = RV_REG_A0;
  U8 src_reg;
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src_reg = RV_REG_T0;
  }
  if (t1 & MDF_REG)
    dest_reg = r1;
  RVNeg(tmpi, dest_reg, src_reg);
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}
/* Multiply/Divide - Requires M Extension */
U0 ICMul(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip, Bool is_unsigned)
{
  // IC_MUL: Multiply
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else if (t3 & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, d3);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    src2_reg = RV_REG_T1;
  }
  if (t1 & MDF_REG)
    dest_reg = r1;
  // MUL rd, rs1, rs2 (M extension)
  // Opcode: 0x33, funct3: 0x0, funct7: 0x01
  RVEmitR(tmpi, RV_OP_OP, dest_reg, 0x0, src1_reg, src2_reg, 0x01);
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}

U0 ICDiv(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip, Bool is_unsigned)
{
  // IC_DIV: Divide
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else if (t3 & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, d3);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    src2_reg = RV_REG_T1;
  }
  if (t1 & MDF_REG)
    dest_reg = r1;
  // DIV/DIVU rd, rs1, rs2 (M extension)
  // funct3: 0x4 (DIV) or 0x5 (DIVU), funct7: 0x01
  U8 funct3 = is_unsigned ? 0x5 : 0x4;
  RVEmitR(tmpi, RV_OP_OP, dest_reg, funct3, src1_reg, src2_reg, 0x01);
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}

U0 ICMod(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip, Bool is_unsigned)
{
  // IC_MOD: Modulo/Remainder
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else if (t3 & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, d3);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    src2_reg = RV_REG_T1;
  }
  if (t1 & MDF_REG)
    dest_reg = r1;
  // REM/REMU rd, rs1, rs2 (M extension)
  // funct3: 0x6 (REM) or 0x7 (REMU), funct7: 0x01
  U8 funct3 = is_unsigned ? 0x7 : 0x6;
  RVEmitR(tmpi, RV_OP_OP, dest_reg, funct3, src1_reg, src2_reg, 0x01);
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}
/* Post-inc/dec (fi++ / fi--). OptPass4 folds JIT globals to
 * ICF_BY_VAL + MDF_RIP_DISP32 with reg=REG_RIP (32). Emitting
 * MDF_DISP with that reg truncates to x0 and bleeds bit5 into imm
 * → `ld t0,1(x0)` (mtval=1). Honor BY_VAL + arg1.type/disp like x86.
 *
 * Never build a CICType inline in an ICMov argument out of `tmpi-><member>`:
 * host AOT scales `k + tmpi->arg1_type_pointed_to` as pointer arithmetic on
 * `tmpi` (k + pt*sizeof(CIntermediateCode)), so the write-back arrived as
 * MDF_STK and `g++` pushed the bumped value instead of storing it (guest AOT
 * `t=arr[i++]` read the wrong element and lost the bump). Stage pt/type in
 * locals first, same as ICAssign's tloc.
 *
 * Host trigger (host/parser.c ParseAdd): the left operand's pointer-ness comes
 * from PtrElemInfo, which reads the sticky cc->last_var_symbol/last_member
 * state. A leading int literal sets none of it, so `k + p->m` inherits the
 * pointer left over from an earlier argument -- here `tmpi` itself, already
 * marshalled into arg 1. `p->m + k` and a staged local are both unaffected.
 * Repro: tests/scratch/host_arg_slot_scale_repro.hc. */
U0 ICPostIncDec(CIntermediateCode *tmpi, I64 delta_sign, I64 rip)
{
  CHashClass *tmpc = tmpi->ic_class, *tmpc1;
  I64 step, r, pt;
  CICType tloc;
  tmpc1 = tmpc - 1;
  pt = tmpi->arg1_type_pointed_to;
  if (tmpc->ptr_stars_cnt && tmpc1->size != 1)
    step = tmpc1->size *delta_sign;
  else
    step = delta_sign;
  if (tmpi->ic_flags & ICF_BY_VAL) {
    tloc = (tmpi->arg1.type & MDG_MASK) + pt;
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tloc, tmpi->arg1.reg, tmpi->arg1.disp, rip);
    RVAddi(tmpi, RV_REG_T1, RV_REG_T0, step);
    ICMov(tmpi, tloc, tmpi->arg1.reg, tmpi->arg1.disp, MDF_REG + RT_I64, RV_REG_T1, 0, rip);
    if (tmpi->res.type.mode)
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
  } else {
    if (tmpi->arg1.type & MDF_REG && !(tmpi->res.type & MDF_REG && tmpi->res.reg == tmpi->arg1.reg))
      r = tmpi->arg1.reg;
    else {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
      r = RV_REG_T2;
    }
    tloc = MDF_DISP + pt;
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tloc, r, 0, rip);
    if (tmpi->res.type.mode)
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
    RVAddi(tmpi, RV_REG_T1, RV_REG_T0, step);
    ICRVStoreThru(tmpi, pt, r, 0, MDF_REG + RT_I64, RV_REG_T1, 0, rip);
  }
}

U0 ICPreIncDec(CIntermediateCode *tmpi, I64 delta_sign, I64 rip)
{
  CHashClass *tmpc = tmpi->ic_class, *tmpc1;
  I64 step, r, pt;
  CICType tloc;
  tmpc1 = tmpc - 1;
  pt = tmpi->arg1_type_pointed_to;
  if (tmpc->ptr_stars_cnt && tmpc1->size != 1)
    step = tmpc1->size *delta_sign;
  else
    step = delta_sign;
  if (tmpi->ic_flags & ICF_BY_VAL) {
    tloc = (tmpi->arg1.type & MDG_MASK) + pt;
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tloc, tmpi->arg1.reg, tmpi->arg1.disp, rip);
    RVAddi(tmpi, RV_REG_T0, RV_REG_T0, step);
    ICMov(tmpi, tloc, tmpi->arg1.reg, tmpi->arg1.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
    if (tmpi->res.type.mode)
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
  } else {
    if (tmpi->arg1.type & MDF_REG)
      r = tmpi->arg1.reg;
    else {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
      r = RV_REG_T2;
    }
    RVAddi(tmpi, r, r, step);
    tloc = MDF_DISP + pt;
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tloc, r, 0, rip);
  }
}
/* *p++ / *p-- — match x86 ICDerefPostIncDec: deref old, write back p±size.
 * Prior RV only bumped arg1.reg (no store) → Soft Call r=0 on ident walk. */
U0 ICDerefPostIncDec(CIntermediateCode *tmpi, I64 delta_sign, I64 rip)
{
  CHashClass *tmpc1 = tmpi->ic_class;
  CICType t, tptr, tval;
  I64 r, step, pt;
  step = tmpc1->size *delta_sign;
  pt = tmpi->arg1_type_pointed_to;
  t = tmpi->res.type.raw_type;
  if (t > pt)
    t = pt;
  /* Stage the derived types: inline `k + tmpi-><member>` in an ICMov arg is
   * scaled as pointer arithmetic on tmpi by host AOT (see ICPostIncDec). */
  tptr = (tmpi->arg1.type & MDG_MASK) + RT_I64;
  tval = MDF_DISP + t.raw_type;
  if (tmpi->ic_flags & ICF_BY_VAL) {
    if (tmpi->arg1.type & MDF_REG)
      r = tmpi->arg1.reg;
    else {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tptr, tmpi->arg1.reg, tmpi->arg1.disp, rip);
      r = RV_REG_T0;
    }
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tval, r, 0, rip);
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, tptr, tmpi->arg1.reg, tmpi->arg1.disp, rip);
    RVAddi(tmpi, RV_REG_T1, RV_REG_T1, step);
    ICMov(tmpi, tptr, tmpi->arg1.reg, tmpi->arg1.disp, MDF_REG + RT_I64, RV_REG_T1, 0, rip);
  } else {
    if (tmpi->arg1.type & MDF_REG)
      r = tmpi->arg1.reg;
    else {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tptr, tmpi->arg1.reg, tmpi->arg1.disp, rip);
      r = RV_REG_T2;
    }
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_DISP + RT_I64, r, 0, rip);
    RVAddi(tmpi, RV_REG_T1, RV_REG_T0, step);
    ICMov(tmpi, MDF_DISP + RT_I64, r, 0, MDF_REG + RT_I64, RV_REG_T1, 0, rip);
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tval, RV_REG_T0, 0, rip);
  }
}
/* *p++= / *p--= — match x86 ICAssignPostIncDec (writeback p). */
U0 ICAssignPostIncDec(CIntermediateCode *tmpi, I64 delta_sign, I64 rip)
{
  CHashClass *tmpc1 = tmpi->ic_class2 - 1;
  I64 r, step, pt;
  CICType tptr, tval;
  step = tmpc1->size *delta_sign;
  pt = tmpi->arg1_type_pointed_to;
  /* Stage the derived types (see ICPostIncDec): inline `k + tmpi-><member>`
   * in an ICMov arg is scaled as pointer arithmetic on tmpi by host AOT. */
  tptr = (tmpi->arg1.type & MDG_MASK) + RT_I64;
  tval = MDF_DISP + pt;
  if (tmpi->ic_flags & ICF_BY_VAL) {
    if (tmpi->arg1.type & MDF_REG)
      r = tmpi->arg1.reg;
    else if (tmpi->arg1.type & (MDF_DISP | MDF_SIB | MDF_RIP_DISP32)) {
      ICLea(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
      r = RV_REG_T2;
    } else {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tptr, tmpi->arg1.reg, tmpi->arg1.disp, rip);
      r = RV_REG_T0;
    }
    /* Narrow: StoreThru — not ICMov(MDF_DISP+pt) CICType trap. */
    if (pt && pt < RT_I64)
      ICRVStoreThru(tmpi, pt, r, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
    else
      ICMov(tmpi, tval, r, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
    if (tmpi->res.type.mode)
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, tptr, tmpi->arg1.reg, tmpi->arg1.disp, rip);
    RVAddi(tmpi, RV_REG_T1, RV_REG_T1, step);
    ICMov(tmpi, tptr, tmpi->arg1.reg, tmpi->arg1.disp, MDF_REG + RT_I64, RV_REG_T1, 0, rip);
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_DISP + RT_I64, RV_REG_T2, 0, rip);
    if (pt && pt < RT_I64)
      ICRVStoreThru(tmpi, pt, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
    else
      ICMov(tmpi, tval, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
    if (tmpi->res.type.mode)
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
    RVAddi(tmpi, RV_REG_T1, RV_REG_T0, step);
    ICMov(tmpi, MDF_DISP + RT_I64, RV_REG_T2, 0, MDF_REG + RT_I64, RV_REG_T1, 0, rip);
  }
}
/* Match x86 ICAssign: BY_VAL stores to folded RIP/DISP/REG lvalues.
 * BY_VAL+STK is inconsistent (pointer still on stack) — store through it.
 * Narrow store through ptr REG: gate on pointed_to width (not arg1.raw).
 * H5 raw<I64 missed *d= (raw=PTR). Dropping REG&& (pt-only DISP) hung
 * after MakeAdam — keep REG&&. Ident now has pt=U8 at Pass3/6.
 *
 * Ident emit dump: non-BY_VAL REG path took br=3 with pt=U8 arg2=DISP+U8 but
 * ic_cnt=4 emitted only `lbu s1,0(s2)` — inline `ICMov(MDF_DISP+pt,…)` was
 * received as REG←DISP (host-AOT CICType arg). Store via I64 pt + RVSb. */
U0 ICRVStoreThru(CIntermediateCode *tmpi, I64 pt, I64 addr_reg, I64 addr_disp, CICType t2, I64 r2, I64 d2, I64 rip)
{
  I64 val_reg;
  if (t2 & MDF_REG)
    val_reg = r2;
  else {
    /* REG+I64 dest: load width still follows t2.raw (REG←DISP uses raw_type2). */
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    val_reg = RV_REG_T0;
  }
  if (addr_disp && (addr_disp < -2048 || addr_disp > 2047)) {
    RVLi(tmpi, RV_REG_T1, addr_disp);
    RVAdd(tmpi, RV_REG_T1, addr_reg, RV_REG_T1);
    addr_reg = RV_REG_T1;
    addr_disp = 0;
  }
  switch (pt) {
    case RT_I8 :
    case RT_U8 :
    RVSb(tmpi, val_reg, addr_reg, addr_disp);
    break;
    case RT_I16 :
    case RT_U16 :
    RVSh(tmpi, val_reg, addr_reg, addr_disp);
    break;
    case RT_I32 :
    case RT_U32 :
    RVSw(tmpi, val_reg, addr_reg, addr_disp);
    break;
    default:
    RVSd(tmpi, val_reg, addr_reg, addr_disp);
  }
}
/* Soft DocInit for(i) arr[i]&=mask — IC_AND_EQU/OR/XOR. */
U0 ICAndEqu(CIntermediateCode *tmpi, I64 rip)
{
  I64 pt = tmpi->arg1_type_pointed_to;
  U8 addr;
  if (!pt)
    pt = RT_I64;
  if (tmpi->ic_flags & ICF_BY_VAL && !(tmpi->arg1.type & MDF_STK)) {
    ICLea(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
    addr = RV_REG_T2;
  } else
    addr = RVLoadToReg(tmpi, RV_REG_T2, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_DISP + pt, addr, 0, rip);
  ICAnd(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  ICRVStoreThru(tmpi, pt, addr, 0, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
  if (tmpi->res.type.mode)
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
}

U0 ICOrEqu(CIntermediateCode *tmpi, I64 rip)
{
  I64 pt = tmpi->arg1_type_pointed_to;
  U8 addr;
  if (!pt)
    pt = RT_I64;
  if (tmpi->ic_flags & ICF_BY_VAL && !(tmpi->arg1.type & MDF_STK)) {
    ICLea(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
    addr = RV_REG_T2;
  } else
    addr = RVLoadToReg(tmpi, RV_REG_T2, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_DISP + pt, addr, 0, rip);
  ICOr(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  ICRVStoreThru(tmpi, pt, addr, 0, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
  if (tmpi->res.type.mode)
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
}

U0 ICXorEqu(CIntermediateCode *tmpi, I64 rip)
{
  I64 pt = tmpi->arg1_type_pointed_to;
  U8 addr;
  if (!pt)
    pt = RT_I64;
  if (tmpi->ic_flags & ICF_BY_VAL && !(tmpi->arg1.type & MDF_STK)) {
    ICLea(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
    addr = RV_REG_T2;
  } else
    addr = RVLoadToReg(tmpi, RV_REG_T2, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_DISP + pt, addr, 0, rip);
  ICXor(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  ICRVStoreThru(tmpi, pt, addr, 0, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
  if (tmpi->res.type.mode)
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
}

// Compound assignment (`x op= y`) for the ops stock x86 emits as ICAddSubEctEqu / ICMulEqu /
// ICDivEqu / ICShiftEqu. Same read-modify-write shape as ICAndEqu above: resolve the target
// address (arg1 is a pointer, arg1_type_pointed_to its width), load, op with arg2, store back,
// and copy to res when the expression value is used. Without these the guest (REPL) compiler
// hit the "not implemented" default: `x+=3` silently did nothing and `x*=2` faulted, because
// the NOP left arg2 pushed and res unset. Signedness comes from the TARGET type (`U64 q; q/=2`
// must divide unsigned), and an F64 target takes the FP path.
U8 ICEquAddr(CIntermediateCode *tmpi, I64 rip)
{
  if (tmpi->ic_flags & ICF_BY_VAL && !(tmpi->arg1.type & MDF_STK)) {
    ICLea(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
    return RV_REG_T2;
  }
  return RVLoadToReg(tmpi, RV_REG_T2, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
}
// op: 0 add, 1 sub, 2 mul, 3 div, 4 mod, 5 shl, 6 shr
U0 ICArithEqu(CIntermediateCode *tmpi, I64 op, I64 rip)
{
  // IC_ADD_EQU..IC_SHR_EQU (op 0..6): *lval op= arg2. Stock picks the F64 form by
  // !ICF_USE_INT (OptPass6), converting an int lval/rhs like ICFOpEqu does.
  I64 pt = tmpi->arg1_type_pointed_to;
  U8 addr;
  Bool uns;
  if (!pt)
    pt = RT_I64;
  addr = ICEquAddr(tmpi, rip);
  if (!(tmpi->ic_flags & ICF_USE_INT) && op <= 3) {
    if (pt == RT_F64)
      RVFld(tmpi, RV_FREG_FT0, addr, 0);
    else {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_DISP + pt, addr, 0, rip);
      if (pt & RTF_UNSIGNED)
        RVFcvtDLu(tmpi, RV_FREG_FT0, RV_REG_T0);
      else
        RVFcvtDL(tmpi, RV_FREG_FT0, RV_REG_T0);
    }
    if (tmpi->arg2.type.raw_type == RT_F64 || tmpi->arg2.type & MDF_IMM)
      ICFLoad(tmpi, RV_FREG_FT1, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
    else {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
      RVFcvtDL(tmpi, RV_FREG_FT1, RV_REG_T1);
    }
    if (op == 0)
      RVFaddD(tmpi, RV_FREG_FT0, RV_FREG_FT0, RV_FREG_FT1);
    else if (op == 1)
      RVFsubD(tmpi, RV_FREG_FT0, RV_FREG_FT0, RV_FREG_FT1);
    else if (op == 2)
      RVFmulD(tmpi, RV_FREG_FT0, RV_FREG_FT0, RV_FREG_FT1);
    else
      RVFdivD(tmpi, RV_FREG_FT0, RV_FREG_FT0, RV_FREG_FT1);
    if (pt == RT_F64) {
      RVFsd(tmpi, RV_FREG_FT0, addr, 0);
      ICFStore(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, RV_FREG_FT0, rip);
    } else {
      RVFcvtLD(tmpi, RV_REG_T0, RV_FREG_FT0, 1);   // rtz: HolyC ToI64 truncates
      ICRVStoreThru(tmpi, pt, addr, 0, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
      if (tmpi->res.type.mode)
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
    }
    return;
  }
  uns = pt & RTF_UNSIGNED;
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_DISP + pt, addr, 0, rip);
  if (op == 0)
    ICAdd(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  else if (op == 1)
    ICSub(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  else if (op == 2)
    ICMul(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip, uns);
  else if (op == 3)
    ICDiv(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip, uns);
  else if (op == 4)
    ICMod(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip, uns);
  else if (op == 5)
    ICShl(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  else
    ICShr(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip, !uns);
  ICRVStoreThru(tmpi, pt, addr, 0, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
  if (tmpi->res.type.mode)
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip);
}

U0 ICAssign(CIntermediateCode *tmpi, I64 rip)
{
  CICType tloc;
  I64 pt;
  if (tmpi->ic_flags & ICF_BY_VAL && !(tmpi->arg1.type & MDF_STK)) {
    pt = tmpi->arg1_type_pointed_to;
    /* Narrow BY_VAL: REG (*d=) and SIB/DISP/RIP (out[n]=) — never
     * ICMov(MDF_*+pt); host-AOT CICType arg made that a load (Ident). */
    if (pt && pt < RT_I64) {
      if (tmpi->arg1.type & MDF_REG)
        ICRVStoreThru(tmpi, pt, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
      else if (tmpi->arg1.type & (MDF_DISP | MDF_SIB | MDF_RIP_DISP32)) {
        ICLea(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
        ICRVStoreThru(tmpi, pt, RV_REG_T2, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
      } else {
        tloc = (tmpi->arg1.type & MDG_MASK) + pt;
        ICMov(tmpi, tloc, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
      }
      if (tmpi->res.type.mode) {
        if (tmpi->res.type & MDF_REG)
          ICRVStoreThru(tmpi, pt, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
        else if (tmpi->res.type & (MDF_DISP | MDF_SIB | MDF_RIP_DISP32)) {
          ICLea(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, rip);
          ICRVStoreThru(tmpi, pt, RV_REG_T2, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
        } else {
          tloc = (tmpi->res.type & MDG_MASK) + pt;
          ICMov(tmpi, tloc, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
        }
      }
      return;
    }
    tloc = (tmpi->arg1.type & MDG_MASK) + pt;
    ICMov(tmpi, tloc, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
    if (tmpi->res.type.mode) {
      tloc = (tmpi->res.type & MDG_MASK) + pt;
      ICMov(tmpi, tloc, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
    }
    return;
  }
  if (tmpi->arg1.type & MDF_REG) {
    ICRVStoreThru(tmpi, tmpi->arg1_type_pointed_to, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
    if (tmpi->res.type.mode)
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
    return;
  }
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  ICRVStoreThru(tmpi, tmpi->arg1_type_pointed_to, RV_REG_T2, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  if (tmpi->res.type.mode)
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
}
/* LEA - Load Effective Address */
U0 ICLea(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // IC_LEA: Load effective address
  // OptPass4 folds n+n to SIB [reg+reg]; never ADD into that shared GPR.
  U8 dest_reg = RV_REG_A0, acc, base, index, shamt;
  Bool retarget = FALSE;
  CIntermediateCode *nxt;
  if (t1 & MDF_REG)
    dest_reg = r1;
  acc = dest_reg;
  if (t2 & MDF_DISP) {
    // LEA reg, [base + offset] — in-place lea rd,[rd+imm] is intentional.
    if (d2 >= -2048 && d2 <= 2047) {
      RVAddi(tmpi, dest_reg, r2, d2);
    } else {
      RVLi(tmpi, RV_REG_T6, d2);
      RVAdd(tmpi, dest_reg, r2, RV_REG_T6);
    }
    acc = dest_reg;
  } else if (t2 & MDF_SIB) {
    // [base + index<<scale + disp]; scale in bits[15:14] (0,1,2,3 → 1,2,4,8)
    base = r2.u8[0];
    index = r2.u8[1] & 31;
    shamt = r2 >> 14 & 3;
    // n+n fold: base==index; writing dest==base destroys the live arg.
    if (acc == base || acc == index) {
      acc = RV_REG_A0;
      if (acc == base || acc == index)
        acc = RV_REG_T2;
    }
    if (shamt) {
      RVSlli(tmpi, RV_REG_T6, index, shamt);
      RVAdd(tmpi, acc, base, RV_REG_T6);
    } else
      RVAdd(tmpi, acc, base, index);
    if (d2) {
      if (d2 >= -2048 && d2 <= 2047)
        RVAddi(tmpi, acc, acc, d2);
      else {
        RVLi(tmpi, RV_REG_T6, d2);
        RVAdd(tmpi, acc, acc, RV_REG_T6);
      }
    }
    if (t1 & MDF_REG && acc != dest_reg) {
      if (base == index && dest_reg == base) {
        tmpi->res.type = MDF_REG + RT_I64;
        tmpi->res.reg = acc;
        tmpi->res.disp = 0;
        retarget = TRUE;
      } else
        RVMv(tmpi, dest_reg, acc);
    }
  } else if (t2 & MDF_RIP_DISP32) {
    I64 pc = rip + tmpi->ic_cnt, off = d2 - pc;
    RVAuipc(tmpi, dest_reg, (off + 0x800) >> 12 & 0xFFFFF);
    RVAddi(tmpi, dest_reg, dest_reg, off << 52 >> 52);
    acc = dest_reg;
  } else if (t2 & MDF_IMM) {
    RVLi(tmpi, dest_reg, d2);
    acc = dest_reg;
  }
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, acc, 0, rip);
  }
  if (retarget) {
    nxt = tmpi->next;
    while (nxt && nxt->ic_code <= IC_NOP2)
      nxt = nxt->next;
    if (nxt && intermediate_code_table[nxt->ic_code].arg_cnt == IS_2_ARG && nxt->arg1.type & MDF_REG && nxt->arg1.reg == dest_reg)
      nxt->arg1.reg = acc;
  }
}
#help_index ""
