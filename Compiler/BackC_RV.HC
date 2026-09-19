/* RISC-V Backend - Control Flow Operations
 * 
 * Handles branches, jumps, calls, and comparisons.
 * Replaces BackC.HC for RISC-V target.
 */
#help_index "Compiler/Internal/RISCV"
/* Comparison Operations */
U0 ICCmp(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip, U8 cmp_type, Bool is_unsigned)
{
  // Compare and set result
  // cmp_type: 0=EQU, 1=NOT_EQU, 2=LESS, 3=GREATER_EQU, 4=GREATER, 5=LESS_EQU
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  // Load operands
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
  switch (cmp_type) {
    case 0 :
    // EQU: a == b
    // XOR then SEQZ
    RVXor(tmpi, dest_reg, src1_reg, src2_reg);
    RVSeqz(tmpi, dest_reg, dest_reg);
    break;
    case 1 :
    // NOT_EQU: a != b
    // XOR then SNEZ
    RVXor(tmpi, dest_reg, src1_reg, src2_reg);
    RVSnez(tmpi, dest_reg, dest_reg);
    break;
    case 2 :
    // LESS: a < b
    if (is_unsigned) {
      RVSltu(tmpi, dest_reg, src1_reg, src2_reg);
    } else {
      RVSlt(tmpi, dest_reg, src1_reg, src2_reg);
    }
    break;
    case 3 :
    // GREATER_EQU: a >= b
    // !(a < b)
    if (is_unsigned) {
      RVSltu(tmpi, dest_reg, src1_reg, src2_reg);
    } else {
      RVSlt(tmpi, dest_reg, src1_reg, src2_reg);
    }
    RVXori(tmpi, dest_reg, dest_reg, 1);
    // Invert
    break;
    case 4 :
    // GREATER: a > b  ==  b < a
    if (is_unsigned) {
      RVSltu(tmpi, dest_reg, src2_reg, src1_reg);
    } else {
      RVSlt(tmpi, dest_reg, src2_reg, src1_reg);
    }
    break;
    case 5 :
    // LESS_EQU: a <= b  ==  !(b < a)
    if (is_unsigned) {
      RVSltu(tmpi, dest_reg, src2_reg, src1_reg);
    } else {
      RVSlt(tmpi, dest_reg, src2_reg, src1_reg);
    }
    RVXori(tmpi, dest_reg, dest_reg, 1);
    // Invert
    break;
  }
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}
/* Branch Operations */
U0 ICBranch(CIntermediateCode *tmpi, CCodeMisc *label, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip, I64 rip2, U8 branch_type, Bool is_unsigned)
{
  // Conditional branch
  // branch_type: 0=EQU, 1=NOT_EQU, 2=LESS, 3=GREATER_EQU, 4=GREATER, 5=LESS_EQU
  U8 src1_reg, src2_reg;
  I64 offset;
  // Load operands
  if (t1 & MDF_REG) {
    src1_reg = r1;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t1, r1, d1, rip2);
    src1_reg = RV_REG_T0;
  }
  if (t2 & MDF_REG) {
    src2_reg = r2;
  } else if (t2 & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, d2);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t2, r2, d2, rip2);
    src2_reg = RV_REG_T1;
  }
  // Fixed-size short B* while label unresolved — avoid far/near size thrash.
  if (!label || label->addr == INVALID_PTR)
    offset = 0;
  else
    offset = label->addr - (rip + tmpi->ic_cnt);
  // Emit appropriate branch instruction
  switch (branch_type) {
    case 0 :
    // EQU: branch if equal
    RVBeq(tmpi, src1_reg, src2_reg, offset);
    break;
    case 1 :
    // NOT_EQU: branch if not equal
    RVBne(tmpi, src1_reg, src2_reg, offset);
    break;
    case 2 :
    // LESS: branch if less than
    if (is_unsigned) {
      RVBltu(tmpi, src1_reg, src2_reg, offset);
    } else {
      RVBlt(tmpi, src1_reg, src2_reg, offset);
    }
    break;
    case 3 :
    // GREATER_EQU: branch if >=
    if (is_unsigned) {
      RVBgeu(tmpi, src1_reg, src2_reg, offset);
    } else {
      RVBge(tmpi, src1_reg, src2_reg, offset);
    }
    break;
    case 4 :
    // GREATER: branch if >  (swap and use <)
    if (is_unsigned) {
      RVBltu(tmpi, src2_reg, src1_reg, offset);
    } else {
      RVBlt(tmpi, src2_reg, src1_reg, offset);
    }
    break;
    case 5 :
    // LESS_EQU: branch if <= (swap and use >=)
    if (is_unsigned) {
      RVBgeu(tmpi, src2_reg, src1_reg, offset);
    } else {
      RVBge(tmpi, src2_reg, src1_reg, offset);
    }
    break;
  }
}
/* Simple Branch Operations */
U0 ICBranchZero(CIntermediateCode *tmpi, CCodeMisc *label, CICType t1, I64 r1, I64 d1, I64 rip, I64 rip2)
{
  // Branch if zero
  U8 src_reg;
  I64 offset;
  if (t1 & MDF_REG) {
    src_reg = r1;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t1, r1, d1, rip2);
    src_reg = RV_REG_T0;
  }
  // Branch PC is after any ICMov bytes already in ic_body.
  if (!label || label->addr == INVALID_PTR)
    offset = 0;
  else
    offset = label->addr - (rip + tmpi->ic_cnt);
  RVBeq(tmpi, src_reg, RV_REG_ZERO, offset);
}

U0 ICBranchNotZero(CIntermediateCode *tmpi, CCodeMisc *label, CICType t1, I64 r1, I64 d1, I64 rip, I64 rip2)
{
  // Branch if not zero
  U8 src_reg;
  I64 offset;
  if (t1 & MDF_REG) {
    src_reg = r1;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t1, r1, d1, rip2);
    src_reg = RV_REG_T0;
  }
  if (!label || label->addr == INVALID_PTR)
    offset = 0;
  else
    offset = label->addr - (rip + tmpi->ic_cnt);
  RVBne(tmpi, src_reg, RV_REG_ZERO, offset);
}
/* OptPass folds (a&b) into BR_AND_*: Soft MenuFpOk `if (fp & 1)` → opcode 149.
 * Without emit, Soft Cmp Warns=0 but Soft Call always returns 0 → r=4. */
U0 ICAndBranch(CIntermediateCode *tmpi, CCodeMisc *label, Bool br_if_zero, I64 rip, I64 rip2)
{
  U8 src1_reg, src2_reg;
  I64 offset;
  CICArg *arg1 = &tmpi->arg1, *arg2 = &tmpi->arg2;
  if (arg1->type & MDF_IMM) {
    arg1 = &tmpi->arg2;
    arg2 = &tmpi->arg1;
  }
  if (arg1->type & MDF_REG)
    src1_reg = arg1->reg;
  else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, arg1->type, arg1->reg, arg1->disp, rip2);
    src1_reg = RV_REG_T0;
  }
  if (arg2->type & MDF_REG)
    src2_reg = arg2->reg;
  else if (arg2->type & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, arg2->disp);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, arg2->type, arg2->reg, arg2->disp, rip2);
    src2_reg = RV_REG_T1;
  }
  RVAnd(tmpi, RV_REG_T0, src1_reg, src2_reg);
  if (!label || label->addr == INVALID_PTR)
    offset = 0;
  else
    offset = label->addr - (rip + tmpi->ic_cnt);
  if (br_if_zero)
    RVBeq(tmpi, RV_REG_T0, RV_REG_ZERO, offset);
  else
    RVBne(tmpi, RV_REG_T0, RV_REG_ZERO, offset);
}
/* Unconditional Jump */
U0 ICJmp(CIntermediateCode *tmpi, CCodeMisc *label, I64 rip)
{
  // Unconditional jump. label->addr and rip are module-relative.
  I64 offset;
  // Unresolved forward label (INVALID_PTR): emit fixed-size short JAL
  // placeholder so pass 7–9 sizing cannot oscillate far↔near (hang).
  if (!label || label->addr == INVALID_PTR) {
    RVJ(tmpi, 0);
    return;
  }
  offset = label->addr - rip;
  // Host AOT does not honor HolyC chained compares — use &&.
  if (offset >= -0x100000 && offset <= 0xFFFFF) {
    RVJ(tmpi, offset);
    // JAL x0, offset
  } else {
    // Far: auipc+jalr via temp with PC-relative absolute
    RVAuipc(tmpi, RV_REG_T6, 0);
    RVLi(tmpi, RV_REG_T5, offset);
    RVAdd(tmpi, RV_REG_T6, RV_REG_T6, RV_REG_T5);
    RVJalr(tmpi, RV_REG_ZERO, RV_REG_T6, 0);
  }
}
/* Function Call/Return */
U0 ICCall(CIntermediateCode *tmpi, I64 target_addr, I64 rip)
{
  /* Direct call. Must preserve ra: expression JIT is `call; ret` without
 * ENTER, so jalr/jal would overwrite ra and ret would spin on itself. */
  I64 offset;
  RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -16);
  RVSd(tmpi, RV_REG_RA, RV_REG_SP, 8);
  offset = target_addr - (rip + tmpi->ic_cnt);
  if (offset >= -0x100000 && offset <= 0xFFFFF)
    RVJal(tmpi, RV_REG_RA, offset);
  else {
    RVLi(tmpi, RV_REG_T6, target_addr);
    RVJalr(tmpi, RV_REG_RA, RV_REG_T6, 0);
  }
  RVLd(tmpi, RV_REG_RA, RV_REG_SP, 8);
  RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 16);
}

U0 ICCallIndirect(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, I64 rip)
{
  // Indirect call; preserve ra for expression-JIT call;ret shape.
  U8 target_reg;
  RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -16);
  RVSd(tmpi, RV_REG_RA, RV_REG_SP, 8);
  if (t1 & MDF_REG)
    target_reg = r1;
  else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T6, 0, t1, r1, d1, rip);
    target_reg = RV_REG_T6;
  }
  RVJalr(tmpi, RV_REG_RA, target_reg, 0);
  RVLd(tmpi, RV_REG_RA, RV_REG_SP, 8);
  RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 16);
}

U0 ICRet(CIntermediateCode *tmpi)
{
  // Return from function
  RVRet(tmpi);
  // JALR x0, 0(ra)
}
/* Function Prologue/Epilogue */
U0 ICEnter(CIntermediateCode *tmpi, I64 frame_size)
{
  // Match host EmitIC_ENTER: 16-byte header (ra+fp) + aligned locals so
  // guest→host calls see ABI-compliant SP (host callees save ra at 0(sp)).
  I64 alloc, f;
  if (frame_size < 0)
    alloc = -frame_size;
  else
    alloc = frame_size;
  if (alloc & 15)
    alloc = alloc + 16 - (alloc & 15);
  f = 16 + alloc;
  if (-f >= -2048 && -f <= 2047)
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -f);
  else {
    RVLi(tmpi, RV_REG_T6, -f);
    RVAdd(tmpi, RV_REG_SP, RV_REG_SP, RV_REG_T6);
  }
  RVSd(tmpi, RV_REG_RA, RV_REG_SP, 0);
  RVSd(tmpi, RV_REG_FP, RV_REG_SP, 8);
  if (f >= -2048 && f <= 2047)
    RVAddi(tmpi, RV_REG_FP, RV_REG_SP, f);
  else {
    RVLi(tmpi, RV_REG_T6, f);
    RVAdd(tmpi, RV_REG_FP, RV_REG_SP, RV_REG_T6);
  }
}

U0 ICLeave(CIntermediateCode *tmpi, I64 frame_size)
{
  // Match host EmitIC_LEAVE: sp = fp - f; restore ra/fp; sp += f; ret.
  I64 alloc, f;
  no_warn frame_size;
  if (frame_size < 0)
    alloc = -frame_size;
  else
    alloc = frame_size;
  if (alloc & 15)
    alloc = alloc + 16 - (alloc & 15);
  f = 16 + alloc;
  if (-f >= -2048 && -f <= 2047)
    RVAddi(tmpi, RV_REG_SP, RV_REG_FP, -f);
  else {
    RVLi(tmpi, RV_REG_T6, -f);
    RVAdd(tmpi, RV_REG_SP, RV_REG_FP, RV_REG_T6);
  }
  RVLd(tmpi, RV_REG_RA, RV_REG_SP, 0);
  RVLd(tmpi, RV_REG_FP, RV_REG_SP, 8);
  if (f >= -2048 && f <= 2047)
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, f);
  else {
    RVLi(tmpi, RV_REG_T6, f);
    RVAdd(tmpi, RV_REG_SP, RV_REG_SP, RV_REG_T6);
  }
  RVRet(tmpi);
}
/* Boolean Operations */
U0 ICNot(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // Logical NOT (convert to 0 or 1)
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
  // SEQZ: set if equal to zero
  RVSeqz(tmpi, dest_reg, src_reg);
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}

U0 ICToBool(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // Convert to boolean (0 or 1)
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
  // SNEZ: set if not equal to zero
  RVSnez(tmpi, dest_reg, src_reg);
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}
/* Logical AND/OR/XOR (boolean versions) */
U0 ICAndAnd(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  // Logical AND (&&): returns 0 or 1
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  // Load and convert first operand to bool
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  RVSnez(tmpi, src1_reg, src1_reg);
  // Convert to 0/1
  // Load and convert second operand to bool
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else if (t3 & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, d3 ? 1 : 0);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    src2_reg = RV_REG_T1;
  }
  RVSnez(tmpi, src2_reg, src2_reg);
  // Convert to 0/1
  if (t1 & MDF_REG)
    dest_reg = r1;
  // AND them together
  RVAnd(tmpi, dest_reg, src1_reg, src2_reg);
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}

U0 ICOrOr(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  // Logical OR (||): returns 0 or 1
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  // Load operands
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
  // OR them together
  RVOr(tmpi, dest_reg, src1_reg, src2_reg);
  // Convert result to boolean
  RVSnez(tmpi, dest_reg, dest_reg);
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}

U0 ICXorXor(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{
  // Logical XOR (^^): returns 0 or 1
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  // Load and convert first operand to bool
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  RVSnez(tmpi, src1_reg, src1_reg);
  // Load and convert second operand to bool
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else if (t3 & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, d3 ? 1 : 0);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    src2_reg = RV_REG_T1;
  }
  RVSnez(tmpi, src2_reg, src2_reg);
  if (t1 & MDF_REG)
    dest_reg = r1;
  // XOR them together
  RVXor(tmpi, dest_reg, src1_reg, src2_reg);
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}
/* Switch Statement — jump-table dispatch.
 *
 * PrsSwitch (Compiler/PrsStmt.HC) already normalized the value to `value-lo` (an
 * IC_IMM_I64+IC_SUB pair) so arg1 is the table index, and it built mc_jt->jmp_table
 * (range entries, default-filled then case labels at val-lo) with mc_jt->dft the
 * default label and mc_jt->range the table size. The table itself is emitted in the
 * misc epilogue at mc_jt->addr (OptPass_RV.HC, CMT_JMP_TABLE) as I64 entries; each
 * entry is stored as a DELTA from the table start (label_off - mc_jt->addr), so a
 * PC-relative base plus the loaded delta yields the runtime target — position
 * independent, exactly like IC_GET_LABEL's auipc/addi.
 *
 * Fixed byte count every pass (offset 0 + clear ICF_CODE_FINAL while a label is
 * unresolved) so pass 7-9 sizing cannot oscillate. */
U0 ICSwitchRV(CIntermediateCode *tmpi, CCodeMisc *mc_jt, Bool nobound, I64 rip)
{
  I64 range, toff, doff;
  if (!mc_jt)
    return;
  range = mc_jt->range;
  // index = value-lo into t0 (arg1 already normalized by PrsSwitch)
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  if (!nobound) {
    // if ((U64)index >= range) goto default   — implemented as: if in-bounds skip
    // the 4-byte default jump that follows.
    RVLi(tmpi, RV_REG_T1, range);
    RVBltu(tmpi, RV_REG_T0, RV_REG_T1, 8);
    if (!mc_jt->dft || mc_jt->dft->addr == INVALID_PTR) {
      doff = 0;
      tmpi->ic_flags &= ~ICF_CODE_FINAL;
    } else
      doff = mc_jt->dft->addr - (rip + tmpi->ic_cnt);
    RVJ(tmpi, doff);
    // JAL x0 — always 4 bytes
  }
  // t1 = runtime address of the jump table (PC-relative to mc_jt->addr)
  if (mc_jt->addr == INVALID_PTR) {
    toff = 0;
    tmpi->ic_flags &= ~ICF_CODE_FINAL;
  } else
    toff = mc_jt->addr - (rip + tmpi->ic_cnt);
  RVAuipc(tmpi, RV_REG_T1, (toff + 0x800) >> 12 & 0xFFFFF);
  RVAddi(tmpi, RV_REG_T1, RV_REG_T1, toff << 52 >> 52);
  // delta = table[index]; target = table_base + delta; jump.
  RVSlli(tmpi, RV_REG_T2, RV_REG_T0, 3);
  RVAdd(tmpi, RV_REG_T2, RV_REG_T1, RV_REG_T2);
  RVLd(tmpi, RV_REG_T3, RV_REG_T2, 0);
  RVAdd(tmpi, RV_REG_T3, RV_REG_T1, RV_REG_T3);
  RVJalr(tmpi, RV_REG_ZERO, RV_REG_T3, 0);
}
#help_index ""
