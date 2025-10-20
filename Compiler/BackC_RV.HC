/* RISC-V Backend - Control Flow Operations
 * 
 * Handles branches, jumps, calls, and comparisons.
 * Replaces BackC.HC for RISC-V target.
 */

#help_index "Compiler/Internal/RISCV"

/* Comparison Operations */

U0 ICCmp(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip,
         U8 cmp_type, Bool is_unsigned)
{// Compare and set result
  // cmp_type: 0=EQU, 1=NOT_EQU, 2=LESS, 3=GREATER_EQU, 4=GREATER, 5=LESS_EQU
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  // Load operands
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
  
  switch (cmp_type) {
    case 0: // EQU: a == b
      // XOR then SEQZ
      RVXor(tmpi, dest_reg, src1_reg, src2_reg);
      RVSeqz(tmpi, dest_reg, dest_reg);
      break;
      
    case 1: // NOT_EQU: a != b
      // XOR then SNEZ
      RVXor(tmpi, dest_reg, src1_reg, src2_reg);
      RVSnez(tmpi, dest_reg, dest_reg);
      break;
      
    case 2: // LESS: a < b
      if (is_unsigned) {
        RVSltu(tmpi, dest_reg, src1_reg, src2_reg);
      } else {
        RVSlt(tmpi, dest_reg, src1_reg, src2_reg);
      }
      break;
      
    case 3: // GREATER_EQU: a >= b
      // !(a < b)
      if (is_unsigned) {
        RVSltu(tmpi, dest_reg, src1_reg, src2_reg);
      } else {
        RVSlt(tmpi, dest_reg, src1_reg, src2_reg);
      }
      RVXori(tmpi, dest_reg, dest_reg, 1); // Invert
      break;
      
    case 4: // GREATER: a > b  ==  b < a
      if (is_unsigned) {
        RVSltu(tmpi, dest_reg, src2_reg, src1_reg);
      } else {
        RVSlt(tmpi, dest_reg, src2_reg, src1_reg);
      }
      break;
      
    case 5: // LESS_EQU: a <= b  ==  !(b < a)
      if (is_unsigned) {
        RVSltu(tmpi, dest_reg, src2_reg, src1_reg);
      } else {
        RVSlt(tmpi, dest_reg, src2_reg, src1_reg);
      }
      RVXori(tmpi, dest_reg, dest_reg, 1); // Invert
      break;
  }
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

/* Branch Operations */

U0 ICBranch(CIntermediateCode *tmpi, CCodeMisc *label,
            CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2,
            I64 rip, U8 branch_type, Bool is_unsigned)
{// Conditional branch
  // branch_type: 0=EQU, 1=NOT_EQU, 2=LESS, 3=GREATER_EQU, 4=GREATER, 5=LESS_EQU
  U8 src1_reg, src2_reg;
  I64 offset;
  
  // Load operands
  if (t1 & MDF_REG) {
    src1_reg = r1;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t1, r1, d1, rip);
    src1_reg = RV_REG_T0;
  }
  
  if (t2 & MDF_REG) {
    src2_reg = r2;
  } else if (t2 & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, d2);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t2, r2, d2, rip);
    src2_reg = RV_REG_T1;
  }
  
  // Calculate branch offset (will be patched during resolution)
  offset = label->addr - rip;
  
  // Emit appropriate branch instruction
  switch (branch_type) {
    case 0: // EQU: branch if equal
      RVBeq(tmpi, src1_reg, src2_reg, offset);
      break;
      
    case 1: // NOT_EQU: branch if not equal
      RVBne(tmpi, src1_reg, src2_reg, offset);
      break;
      
    case 2: // LESS: branch if less than
      if (is_unsigned) {
        RVBltu(tmpi, src1_reg, src2_reg, offset);
      } else {
        RVBlt(tmpi, src1_reg, src2_reg, offset);
      }
      break;
      
    case 3: // GREATER_EQU: branch if >=
      if (is_unsigned) {
        RVBgeu(tmpi, src1_reg, src2_reg, offset);
      } else {
        RVBge(tmpi, src1_reg, src2_reg, offset);
      }
      break;
      
    case 4: // GREATER: branch if >  (swap and use <)
      if (is_unsigned) {
        RVBltu(tmpi, src2_reg, src1_reg, offset);
      } else {
        RVBlt(tmpi, src2_reg, src1_reg, offset);
      }
      break;
      
    case 5: // LESS_EQU: branch if <= (swap and use >=)
      if (is_unsigned) {
        RVBgeu(tmpi, src2_reg, src1_reg, offset);
      } else {
        RVBge(tmpi, src2_reg, src1_reg, offset);
      }
      break;
  }
}

/* Simple Branch Operations */

U0 ICBranchZero(CIntermediateCode *tmpi, CCodeMisc *label,
                CICType t1, I64 r1, I64 d1, I64 rip)
{// Branch if zero
  U8 src_reg;
  I64 offset;
  
  if (t1 & MDF_REG) {
    src_reg = r1;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t1, r1, d1, rip);
    src_reg = RV_REG_T0;
  }
  
  offset = label->addr - rip;
  RVBeq(tmpi, src_reg, RV_REG_ZERO, offset);
}

U0 ICBranchNotZero(CIntermediateCode *tmpi, CCodeMisc *label,
                   CICType t1, I64 r1, I64 d1, I64 rip)
{// Branch if not zero
  U8 src_reg;
  I64 offset;
  
  if (t1 & MDF_REG) {
    src_reg = r1;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t1, r1, d1, rip);
    src_reg = RV_REG_T0;
  }
  
  offset = label->addr - rip;
  RVBne(tmpi, src_reg, RV_REG_ZERO, offset);
}

/* Unconditional Jump */

U0 ICJmp(CIntermediateCode *tmpi, CCodeMisc *label, I64 rip)
{// Unconditional jump
  I64 offset = label->addr - rip;
  
  // Check if offset fits in JAL (±1MB range)
  if (-0x100000 <= offset <= 0xFFFFF) {
    RVJ(tmpi, offset); // JAL x0, offset
  } else {
    // Large jump - use absolute address
    RVLi(tmpi, RV_REG_T6, label->addr);
    RVJalr(tmpi, RV_REG_ZERO, RV_REG_T6, 0);
  }
}

/* Function Call/Return */

U0 ICCall(CIntermediateCode *tmpi, I64 target_addr, I64 rip)
{// Direct function call
  I64 offset = target_addr - rip;
  
  // Check if offset fits in JAL (±1MB range)
  if (-0x100000 <= offset <= 0xFFFFF) {
    RVJal(tmpi, RV_REG_RA, offset);
  } else {
    // Large call - use absolute address
    RVLi(tmpi, RV_REG_T6, target_addr);
    RVJalr(tmpi, RV_REG_RA, RV_REG_T6, 0);
  }
}

U0 ICCallIndirect(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, I64 rip)
{// Indirect function call through register/memory
  U8 target_reg;
  
  if (t1 & MDF_REG) {
    target_reg = r1;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T6, 0, t1, r1, d1, rip);
    target_reg = RV_REG_T6;
  }
  
  RVJalr(tmpi, RV_REG_RA, target_reg, 0);
}

U0 ICRet(CIntermediateCode *tmpi)
{// Return from function
  RVRet(tmpi); // JALR x0, 0(ra)
}

/* Function Prologue/Epilogue */

U0 ICEnter(CIntermediateCode *tmpi, I64 frame_size)
{// Function prologue
  // Save frame pointer
  RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -8);
  RVSd(tmpi, RV_REG_FP, RV_REG_SP, 0);
  
  // Set up frame pointer
  RVAddi(tmpi, RV_REG_FP, RV_REG_SP, 8);
  
  // Allocate stack frame
  if (frame_size > 0) {
    if (-2048 <= -frame_size <= 2047) {
      RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -frame_size);
    } else {
      RVLi(tmpi, RV_REG_T6, -frame_size);
      RVAdd(tmpi, RV_REG_SP, RV_REG_SP, RV_REG_T6);
    }
  }
}

U0 ICLeave(CIntermediateCode *tmpi, I64 frame_size)
{// Function epilogue
  // Restore stack pointer
  if (frame_size > 0) {
    if (-2048 <= frame_size <= 2047) {
      RVAddi(tmpi, RV_REG_SP, RV_REG_SP, frame_size);
    } else {
      RVLi(tmpi, RV_REG_T6, frame_size);
      RVAdd(tmpi, RV_REG_SP, RV_REG_SP, RV_REG_T6);
    }
  }
  
  // Restore frame pointer
  RVLd(tmpi, RV_REG_FP, RV_REG_SP, 0);
  RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 8);
  
  // Return
  RVRet(tmpi);
}

/* Boolean Operations */

U0 ICNot(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
         CICType t2, I64 r2, I64 d2, I64 rip)
{// Logical NOT (convert to 0 or 1)
  U8 dest_reg = RV_REG_A0;
  U8 src_reg;
  
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src_reg = RV_REG_T0;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  
  // SEQZ: set if equal to zero
  RVSeqz(tmpi, dest_reg, src_reg);
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

U0 ICToBool(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
            CICType t2, I64 r2, I64 d2, I64 rip)
{// Convert to boolean (0 or 1)
  U8 dest_reg = RV_REG_A0;
  U8 src_reg;
  
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src_reg = RV_REG_T0;
  }
  
  if (t1 & MDF_REG) dest_reg = r1;
  
  // SNEZ: set if not equal to zero
  RVSnez(tmpi, dest_reg, src_reg);
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

/* Logical AND/OR/XOR (boolean versions) */

U0 ICAndAnd(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
            CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// Logical AND (&&): returns 0 or 1
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  // Load and convert first operand to bool
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src1_reg = RV_REG_T0;
  }
  RVSnez(tmpi, src1_reg, src1_reg); // Convert to 0/1
  
  // Load and convert second operand to bool
  if (t3 & MDF_REG) {
    src2_reg = r3;
  } else if (t3 & MDF_IMM) {
    RVLi(tmpi, RV_REG_T1, d3 ? 1 : 0);
    src2_reg = RV_REG_T1;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    src2_reg = RV_REG_T1;
  }
  RVSnez(tmpi, src2_reg, src2_reg); // Convert to 0/1
  
  if (t1 & MDF_REG) dest_reg = r1;
  
  // AND them together
  RVAnd(tmpi, dest_reg, src1_reg, src2_reg);
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

U0 ICOrOr(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
          CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// Logical OR (||): returns 0 or 1
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  // Load operands
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
  
  // OR them together
  RVOr(tmpi, dest_reg, src1_reg, src2_reg);
  // Convert result to boolean
  RVSnez(tmpi, dest_reg, dest_reg);
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

U0 ICXorXor(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
            CICType t2, I64 r2, I64 d2, CICType t3, I64 r3, I64 d3, I64 rip)
{// Logical XOR (^^): returns 0 or 1
  U8 dest_reg = RV_REG_A0;
  U8 src1_reg, src2_reg;
  
  // Load and convert first operand to bool
  if (t2 & MDF_REG) {
    src1_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
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
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T1, 0, t3, r3, d3, rip);
    src2_reg = RV_REG_T1;
  }
  RVSnez(tmpi, src2_reg, src2_reg);
  
  if (t1 & MDF_REG) dest_reg = r1;
  
  // XOR them together
  RVXor(tmpi, dest_reg, src1_reg, src2_reg);
  
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG+RT_I64, dest_reg, 0, rip);
  }
}

/* Switch Statement */

U0 ICSwitch(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1,
            I64 *jump_table, I64 table_size, I64 rip)
{// Switch statement via jump table
  U8 index_reg;
  
  // Load switch value
  if (t1 & MDF_REG) {
    index_reg = r1;
  } else {
    ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0, t1, r1, d1, rip);
    index_reg = RV_REG_T0;
  }
  
  // Bounds check (compare with table_size)
  RVLi(tmpi, RV_REG_T1, table_size);
  RVBgeu(tmpi, index_reg, RV_REG_T1, 12); // Skip to default if out of bounds
  
  // Load jump table base address
  RVLi(tmpi, RV_REG_T1, jump_table);
  
  // Calculate offset: index * 8
  RVSlli(tmpi, index_reg, index_reg, 3);
  
  // Load target address from table
  RVAdd(tmpi, RV_REG_T1, RV_REG_T1, index_reg);
  RVLd(tmpi, RV_REG_T6, RV_REG_T1, 0);
  
  // Jump to target
  RVJalr(tmpi, RV_REG_ZERO, RV_REG_T6, 0);
}

#help_index ""

