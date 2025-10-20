/* RISC-V Backend - IC to Machine Code Translation
 * 
 * This file implements the final pass that converts IC operations
 * to RISC-V machine code. It replaces the x86-64 specific portions
 * of OptPass789A.HC for RISC-V target.
 */

#help_index "Compiler/Internal/RISCV"

/* Main IC to RISC-V Translation Function */

U0 ICToRISCV(CCmpCtrl *cc, CIntermediateCode *tmpi, U8 *buf, I64 rip, I64 *_rip2)
{// Translate single IC operation to RISC-V machine code
  I64 rip2 = rip + tmpi->ic_cnt;
  I64 code = tmpi->ic_code;
  CCodeMisc *lb;
  I64 offset;
  
  // Reset IC body counter
  tmpi->ic_cnt = 0;
  
  switch (code) {
    /* Data Movement */
    case IC_NOP1:
    case IC_NOP2:
      // No operation - already handled by optimizer
      break;
      
    case IC_MOV:
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      } else {
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      }
      break;
      
    case IC_LEA:
      ICLea(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_PUSH:
      if (tmpi->arg1.type & MDF_REG) {
        RVPush(tmpi, tmpi->arg1.reg);
      } else {
        ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
        RVPush(tmpi, RV_REG_T0);
      }
      break;
      
    case IC_POP:
      if (tmpi->res.type & MDF_REG) {
        RVPop(tmpi, tmpi->res.reg);
      } else {
        RVPop(tmpi, RV_REG_T0);
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              MDF_REG+RT_I64, RV_REG_T0, 0, rip2);
      }
      break;
      
    /* Arithmetic Operations */
    case IC_ADD:
    case IC_ADD_CONST:
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFAdd(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
               tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      } else {
        ICAdd(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
              tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      }
      break;
      
    case IC_SUB:
    case IC_SUB_CONST:
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFSub(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
               tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      } else {
        ICSub(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
              tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      }
      break;
      
    case IC_MUL:
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFMul(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
               tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      } else {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        ICMul(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
              tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, is_unsigned);
      }
      break;
      
    case IC_DIV:
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFDiv(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
               tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      } else {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        ICDiv(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
              tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, is_unsigned);
      }
      break;
      
    case IC_MOD:
      {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        ICMod(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
              tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, is_unsigned);
      }
      break;
      
    /* Bitwise Operations */
    case IC_AND:
      ICAnd(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
            tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      break;
      
    case IC_OR:
      ICOr(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
           tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
           tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      break;
      
    case IC_XOR:
      ICXor(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
            tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      break;
      
    case IC_COM:
      ICCom(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    /* Shift Operations */
    case IC_SHL:
    case IC_SHL_CONST:
      ICShl(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
            tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      break;
      
    case IC_SHR:
    case IC_SHR_CONST:
      {
        Bool is_signed = !(tmpi->ic_class->raw_type & RTF_UNSIGNED);
        ICShr(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
              tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, is_signed);
      }
      break;
      
    /* Unary Operations */
    case IC_UNARY_MINUS:
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFNeg(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      } else {
        ICUnaryMinus(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                     tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      }
      break;
      
    case IC_NOT:
      ICNot(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_TO_BOOL:
      ICToBool(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    /* Type Conversions */
    case IC_TO_F64:
      {
        Bool is_unsigned = tmpi->arg1.type.raw_type & RTF_UNSIGNED;
        ICToF64(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2, is_unsigned);
      }
      break;
      
    case IC_TO_I64:
      {
        Bool is_unsigned = tmpi->res.type.raw_type & RTF_UNSIGNED;
        ICToI64(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2, is_unsigned);
      }
      break;
      
    /* Comparison Operations */
    case IC_EQU_EQU:
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
               tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 0);
      } else {
        ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
              tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 0, FALSE);
      }
      break;
      
    case IC_NOT_EQU:
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
               tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 1);
      } else {
        ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
              tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 1, FALSE);
      }
      break;
      
    case IC_LESS:
      {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        if (tmpi->ic_class->raw_type == RT_F64) {
          ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                 tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 2);
        } else {
          ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 2, is_unsigned);
        }
      }
      break;
      
    case IC_GREATER:
      {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        if (tmpi->ic_class->raw_type == RT_F64) {
          ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                 tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 4);
        } else {
          ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 4, is_unsigned);
        }
      }
      break;
      
    case IC_LESS_EQU:
      {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        if (tmpi->ic_class->raw_type == RT_F64) {
          ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                 tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 5);
        } else {
          ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 5, is_unsigned);
        }
      }
      break;
      
    case IC_GREATER_EQU:
      {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        if (tmpi->ic_class->raw_type == RT_F64) {
          ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                 tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 3);
        } else {
          ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 3, is_unsigned);
        }
      }
      break;
      
    /* Boolean Operations */
    case IC_AND_AND:
      ICAndAnd(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
               tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      break;
      
    case IC_OR_OR:
      ICOrOr(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
             tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
             tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      break;
      
    case IC_XOR_XOR:
      ICXorXor(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
               tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      break;
      
    /* Branches */
    case IC_BR_ZERO:
      ICBranchZero(tmpi, tmpi->ic_data, 
                   tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_BR_NOT_ZERO:
      ICBranchNotZero(tmpi, tmpi->ic_data,
                      tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_BR_EQU_EQU:
      {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        ICBranch(tmpi, tmpi->ic_data,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                 tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp,
                 rip2, 0, is_unsigned);
      }
      break;
      
    case IC_BR_NOT_EQU:
      {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        ICBranch(tmpi, tmpi->ic_data,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                 tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp,
                 rip2, 1, is_unsigned);
      }
      break;
      
    case IC_BR_LESS:
      {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        ICBranch(tmpi, tmpi->ic_data,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                 tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp,
                 rip2, 2, is_unsigned);
      }
      break;
      
    case IC_BR_GREATER:
      {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        ICBranch(tmpi, tmpi->ic_data,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                 tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp,
                 rip2, 4, is_unsigned);
      }
      break;
      
    case IC_BR_LESS_EQU:
      {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        ICBranch(tmpi, tmpi->ic_data,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                 tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp,
                 rip2, 5, is_unsigned);
      }
      break;
      
    case IC_BR_GREATER_EQU:
      {
        Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
        ICBranch(tmpi, tmpi->ic_data,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                 tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp,
                 rip2, 3, is_unsigned);
      }
      break;
      
    /* Jumps and Calls */
    case IC_JMP:
      ICJmp(tmpi, tmpi->ic_data, rip2);
      break;
      
    case IC_SUB_CALL:
      // Subroutine call (used for switch cases, etc.)
      lb = tmpi->ic_data;
      offset = lb->addr - rip2;
      RVJal(tmpi, RV_REG_RA, offset);
      break;
      
    case IC_CALL:
      ICCall(tmpi, tmpi->ic_data, rip2);
      break;
      
    case IC_CALL_INDIRECT:
      // Stack-based indirect call
      // ic_data contains stack offset
      RVLd(tmpi, RV_REG_T6, RV_REG_SP, tmpi->ic_data);
      RVJalr(tmpi, RV_REG_RA, RV_REG_T6, 0);
      break;
      
    case IC_CALL_INDIRECT2:
      // Indirect call through pointer
      ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T6, 0,
            MDF_DISP+RT_I64, 0, tmpi->ic_data, rip2);
      RVJalr(tmpi, RV_REG_RA, RV_REG_T6, 0);
      break;
      
    case IC_CALL_IMPORT:
    case IC_CALL_EXTERN:
      // External/import call - will be resolved by linker
      // For now, emit placeholder
      ICU32(tmpi, 0); // Placeholder for linker relocation
      break;
      
    case IC_RET:
      RVRet(tmpi);
      break;
      
    case IC_RETURN_VAL:
      // Move return value to a0
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFMov(tmpi, MDF_REG+RT_F64, RV_FREG_FA0, 0,
               tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      } else {
        ICMov(tmpi, MDF_REG+RT_I64, RV_REG_A0, 0,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      }
      break;
      
    case IC_RETURN_VAL2:
      // Return value already in a0/fa0, nothing to do
      break;
      
    /* Function Prologue/Epilogue */
    case IC_ENTER:
      ICEnter(tmpi, tmpi->ic_data);
      break;
      
    case IC_LEAVE:
      ICLeave(tmpi, tmpi->ic_data);
      break;
      
    case IC_PUSH_REGS:
      ICPushRegs(tmpi, tmpi->ic_data);
      break;
      
    case IC_POP_REGS:
      ICPopRegs(tmpi, tmpi->ic_data);
      break;
      
    case IC_ADD_RSP:
    case IC_ADD_RSP1:
      ICAddRSP(tmpi, tmpi->ic_data, TRUE);
      break;
      
    /* Switch Statement */
    case IC_SWITCH:
    case IC_NOBOUND_SWITCH:
      // ic_data points to switch table structure
      // TODO: Need to extract table info from ic_data
      // ICSwitch(tmpi, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
      //          jump_table, table_size, rip2);
      break;
      
    /* Bit Manipulation */
    case IC_BT:
      ICBitTest(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 0);
      break;
      
    case IC_BTS:
      ICBitTest(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 1);
      break;
      
    case IC_BTR:
      ICBitTest(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 2);
      break;
      
    case IC_BTC:
      ICBitTest(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 3);
      break;
      
    case IC_LBTS:
      ICLockBitTest(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                    tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                    tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 1);
      break;
      
    case IC_LBTR:
      ICLockBitTest(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                    tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                    tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 2);
      break;
      
    case IC_LBTC:
      ICLockBitTest(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                    tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
                    tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 3);
      break;
      
    case IC_BSF:
      ICBitScanForward(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                       tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_BSR:
      ICBitScanReverse(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                       tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    /* Min/Max/Abs/Sign */
    case IC_MIN_I64:
      ICMin(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
            tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, FALSE);
      break;
      
    case IC_MIN_U64:
      ICMin(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
            tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, TRUE);
      break;
      
    case IC_MAX_I64:
      ICMax(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
            tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, FALSE);
      break;
      
    case IC_MAX_U64:
      ICMax(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
            tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, TRUE);
      break;
      
    case IC_ABS_I64:
      ICAbs(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_ABS:
      ICFAbs(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
             tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_SIGN_I64:
      ICSign(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
             tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_SQRT:
      ICFSqrt(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_SIN:
      ICFSin(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
             tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_COS:
      ICFCos(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
             tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_TAN:
      ICFTan(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
             tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_ATAN:
      ICFAtan(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    /* Byte Swap */
    case IC_SWAP_U16:
      ICByteSwap(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2, 2);
      break;
      
    case IC_SWAP_U32:
      ICByteSwap(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2, 4);
      break;
      
    case IC_SWAP_I64:
      ICByteSwap(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
                 tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2, 8);
      break;
      
    /* Special Instructions - x86 Specific (adapt or remove) */
    case IC_RDTSC:
      // Read cycle counter (RISC-V CSR)
      // CSRR a0, cycle (0xC00)
      RVEmitI(tmpi, RV_OP_SYSTEM, RV_REG_A0, 0x2, RV_REG_ZERO, 0xC00);
      if (tmpi->res.type & MDF_REG && tmpi->res.reg != RV_REG_A0) {
        RVMv(tmpi, tmpi->res.reg, RV_REG_A0);
      } else if (!(tmpi->res.type & MDF_REG)) {
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              MDF_REG+RT_I64, RV_REG_A0, 0, rip2);
      }
      break;
      
    case IC_CLFLUSH:
      // Cache flush - use FENCE instruction
      // FENCE iorw, iorw (full memory fence)
      RVEmitI(tmpi, RV_OP_SYSTEM, RV_REG_ZERO, 0, RV_REG_ZERO, 0x0FF);
      break;
      
    case IC_INVLPG:
      // Invalidate TLB - supervisor mode instruction
      // SFENCE.VMA (requires privilege)
      RVEmitR(tmpi, RV_OP_SYSTEM, RV_REG_ZERO, 0, RV_REG_ZERO, RV_REG_ZERO, 0x09);
      break;
      
    /* Port I/O - Not available on RISC-V */
    case IC_IN_U8:
    case IC_IN_U16:
    case IC_IN_U32:
    case IC_OUT_U8:
    case IC_OUT_U16:
    case IC_OUT_U32:
      // RISC-V uses memory-mapped I/O
      // These should be replaced with MMIO loads/stores
      // For now, generate warning
      PrintWarn("Port I/O not supported on RISC-V (use MMIO)\n");
      break;
      
    /* Segment Register Operations - Not applicable to RISC-V */
    case IC_FS:
    case IC_GS:
    case IC_MOV_FS:
    case IC_MOV_GS:
      // RISC-V has no segment registers
      PrintWarn("Segment registers not supported on RISC-V\n");
      break;
      
    /* Register Access - Direct operations */
    case IC_GET_RAX:
      // RAX is actually a0 - should already be there
      if (tmpi->res.type & MDF_REG && tmpi->res.reg != RV_REG_A0) {
        RVMv(tmpi, tmpi->res.reg, RV_REG_A0);
      }
      break;
      
    case IC_SET_RAX:
      if (tmpi->arg1.type & MDF_REG && tmpi->arg1.reg != RV_REG_A0) {
        RVMv(tmpi, RV_REG_A0, tmpi->arg1.reg);
      } else if (!(tmpi->arg1.type & MDF_REG)) {
        ICMov(tmpi, MDF_REG+RT_I64, RV_REG_A0, 0,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      }
      break;
      
    case IC_GET_RBP:
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            MDF_REG+RT_I64, RV_REG_FP, 0, rip2);
      break;
      
    case IC_SET_RBP:
      ICMov(tmpi, MDF_REG+RT_I64, RV_REG_FP, 0,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_GET_RSP:
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            MDF_REG+RT_I64, RV_REG_SP, 0, rip2);
      break;
      
    case IC_SET_RSP:
      ICMov(tmpi, MDF_REG+RT_I64, RV_REG_SP, 0,
            tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      break;
      
    case IC_RBP:
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            MDF_REG+RT_I64, RV_REG_FP, 0, rip2);
      break;
      
    case IC_REG:
      // Generic register access
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            MDF_REG+RT_I64, tmpi->arg1.reg, 0, rip2);
      break;
      
    /* Assignment Operations */
    case IC_ASSIGN:
    case IC_ASSIGN_PP:
    case IC_ASSIGN_MM:
      // Assignment with possible post-increment/decrement
      ICMov(tmpi, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
            tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      
      if (code == IC_ASSIGN_PP) {
        // Post-increment the pointer
        RVAddi(tmpi, tmpi->arg1.reg, tmpi->arg1.reg, tmpi->ic_class->size);
      } else if (code == IC_ASSIGN_MM) {
        // Post-decrement the pointer
        RVAddi(tmpi, tmpi->arg1.reg, tmpi->arg1.reg, -tmpi->ic_class->size);
      }
      
      if (tmpi->res.type.mode) {
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
      }
      break;
      
    /* Increment/Decrement with Dereference */
    case IC_DEREF:
      // Dereference pointer
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            MDF_DISP+tmpi->arg1_type_pointed_to, tmpi->arg1.reg, 0, rip2);
      break;
      
    case IC_DEREF_PP:
      // Dereference then post-increment pointer
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            MDF_DISP+tmpi->arg1_type_pointed_to, tmpi->arg1.reg, 0, rip2);
      RVAddi(tmpi, tmpi->arg1.reg, tmpi->arg1.reg, tmpi->ic_class->size);
      break;
      
    case IC_DEREF_MM:
      // Dereference then post-decrement pointer
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            MDF_DISP+tmpi->arg1_type_pointed_to, tmpi->arg1.reg, 0, rip2);
      RVAddi(tmpi, tmpi->arg1.reg, tmpi->arg1.reg, -tmpi->ic_class->size);
      break;
      
    case IC_PP_:
      // Pre-increment pointer
      RVAddi(tmpi, tmpi->arg1.reg, tmpi->arg1.reg, tmpi->ic_class->size);
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            MDF_DISP+tmpi->arg1_type_pointed_to, tmpi->arg1.reg, 0, rip2);
      break;
      
    case IC_MM_:
      // Pre-decrement pointer
      RVAddi(tmpi, tmpi->arg1.reg, tmpi->arg1.reg, -tmpi->ic_class->size);
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            MDF_DISP+tmpi->arg1_type_pointed_to, tmpi->arg1.reg, 0, rip2);
      break;
      
    case IC__PP:
      // Dereference, post-increment value
      ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0,
            MDF_DISP+tmpi->arg1_type_pointed_to, tmpi->arg1.reg, 0, rip2);
      RVAddi(tmpi, RV_REG_T0, RV_REG_T0, 1);
      ICMov(tmpi, MDF_DISP+tmpi->arg1_type_pointed_to, tmpi->arg1.reg, 0,
            MDF_REG+RT_I64, RV_REG_T0, 0, rip2);
      RVAddi(tmpi, RV_REG_T0, RV_REG_T0, -1);
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            MDF_REG+RT_I64, RV_REG_T0, 0, rip2);
      break;
      
    case IC__MM:
      // Dereference, post-decrement value
      ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0,
            MDF_DISP+tmpi->arg1_type_pointed_to, tmpi->arg1.reg, 0, rip2);
      RVAddi(tmpi, RV_REG_T0, RV_REG_T0, -1);
      ICMov(tmpi, MDF_DISP+tmpi->arg1_type_pointed_to, tmpi->arg1.reg, 0,
            MDF_REG+RT_I64, RV_REG_T0, 0, rip2);
      RVAddi(tmpi, RV_REG_T0, RV_REG_T0, 1);
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
            MDF_REG+RT_I64, RV_REG_T0, 0, rip2);
      break;
      
    /* Immediates */
    case IC_IMM_I64:
      RVLi(tmpi, tmpi->res.reg, tmpi->ic_data);
      if (!(tmpi->res.type & MDF_REG)) {
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              MDF_REG+RT_I64, tmpi->res.reg, 0, rip2);
      }
      break;
      
    case IC_IMM_F64:
      // Load F64 immediate via integer register
      RVLi(tmpi, RV_REG_T0, tmpi->ic_data);
      RVFmvDX(tmpi, tmpi->res.reg, RV_REG_T0);
      if (!(tmpi->res.type & MDF_REG)) {
        ICFMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
               MDF_REG+RT_F64, tmpi->res.reg, 0, rip2);
      }
      break;
      
    case IC_ABS_ADDR:
    case IC_STR_CONST:
    case IC_ADDR_IMPORT:
    case IC_HEAP_GLBL:
    case IC_GET_LABEL:
      // Load address immediate
      RVLi(tmpi, tmpi->res.reg, tmpi->ic_data);
      if (!(tmpi->res.type & MDF_REG)) {
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              MDF_REG+RT_I64, tmpi->res.reg, 0, rip2);
      }
      break;
      
    /* String Operations */
    case IC_STRLEN:
      // Calculate string length
      // Load string pointer
      if (tmpi->arg1.type & MDF_REG) {
        RVMv(tmpi, RV_REG_T0, tmpi->arg1.reg);
      } else {
        ICMov(tmpi, MDF_REG+RT_I64, RV_REG_T0, 0,
              tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      }
      
      // Save start address
      RVMv(tmpi, RV_REG_T1, RV_REG_T0);
      
      // Loop: while (*p++) ;
      RVLbu(tmpi, RV_REG_T2, RV_REG_T0, 0);
      RVAddi(tmpi, RV_REG_T0, RV_REG_T0, 1);
      RVBne(tmpi, RV_REG_T2, RV_REG_ZERO, -8);
      
      // Calculate length
      RVSub(tmpi, RV_REG_A0, RV_REG_T0, RV_REG_T1);
      RVAddi(tmpi, RV_REG_A0, RV_REG_A0, -1);
      
      if (!(tmpi->res.type & MDF_REG) || tmpi->res.reg != RV_REG_A0) {
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp,
              MDF_REG+RT_I64, RV_REG_A0, 0, rip2);
      }
      break;
      
    /* Label */
    case IC_LABEL:
      // Just a marker, no code generated
      lb = tmpi->ic_data;
      lb->addr = rip2;
      break;
      
    case IC_CALL_START:
    case IC_CALL_END:
    case IC_CALL_END2:
    case IC_END_EXP:
    case IC_END:
      // Markers, no code generation
      break;
      
    /* Assembly Block */
    case IC_ASM:
      // Inline assembly - copy pre-assembled code
      // ic_data points to assembled code
      if (tmpi->ic_data && tmpi->ic_cnt > 0) {
        I64 i;
        U8 *code_ptr = tmpi->ic_data;
        for (i = 0; i < tmpi->ic_cnt; i++) {
          ICU8(tmpi, code_ptr[i]);
        }
      }
      break;
      
    default:
      PrintWarn("IC opcode %d (%s) not implemented for RISC-V\n", 
                code, intermediate_code_table[code].name);
      RVNop(tmpi); // Emit NOP as placeholder
      break;
  }
  
  *_rip2 = rip2 + tmpi->ic_cnt;
}

/* Complete IC Translation Pass */

I64 *OptPassRISCV(CCmpCtrl *cc, I64 *_code_size, U8 **_dbg_info, I64 *_type)
{// Final pass: convert all IC to RISC-V machine code
  I64 rip = 0, rip2;
  CIntermediateCode *tmpi;
  U8 *buf = NULL; // First pass: NULL for address calculation
  I64 pass;
  
  for (pass = 0; pass < 2; pass++) {
    rip = 0;
    tmpi = cc->coc.coc_head.next;
    
    if (pass == 1 && _code_size) {
      // Allocate buffer for machine code
      buf = MAlloc(*_code_size);
    }
    
    while (tmpi->ic_code != IC_END) {
      // Translate IC operation to RISC-V
      ICToRISCV(cc, tmpi, buf, rip, &rip2);
      
      // Copy generated code to buffer if pass 2
      if (pass == 1 && buf) {
        I64 i;
        for (i = 0; i < tmpi->ic_cnt; i++) {
          buf[rip + i] = tmpi->ic_body[i];
        }
      }
      
      rip = rip2;
      tmpi = tmpi->next;
    }
    
    if (pass == 0 && _code_size) {
      *_code_size = rip;
    }
  }
  
  if (_type) *_type = RT_I64;
  return buf;
}

#help_index ""


