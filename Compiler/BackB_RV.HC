/* RISC-V Backend - Bit Manipulation and Additional Operations
 * 
 * Implements bit test/set/reset operations and other specialized instructions.
 * Emulates x86 bit manipulation using RISC-V sequences.
 */
#help_index "Compiler/Internal/RISCV"
/* Bit Test Operations (emulate x86 BT/BTS/BTR/BTC) */
/* Locked Bit Operations (for atomic operations) */
/* Bit Scan Operations (emulate x86 BSF/BSR) */
/* Byte Swap (emulate x86 BSWAP) */
/* Population Count (count set bits) */
U0 ICPopCount(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // Count set bits
  U8 src_reg, dest_reg = RV_REG_A0;
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src_reg = RV_REG_T0;
  }
  if (t1 & MDF_REG)
    dest_reg = r1;
  // If Zbb extension: use CPOP instruction
  // For now, use software algorithm (Brian Kernighan's)
  RVMv(tmpi, RV_REG_T1, src_reg);
  // Copy value
  RVMv(tmpi, dest_reg, RV_REG_ZERO);
  // Count = 0
  // Loop: while (x) { count++; x &= x-1; }
  // This clears the lowest set bit each iteration
  I64 loop_start = 0;
  // Label for loop
  // loop:
  RVBeq(tmpi, RV_REG_T1, RV_REG_ZERO, 16);
  // Exit if zero
  RVAddi(tmpi, dest_reg, dest_reg, 1);
  // count++
  RVAddi(tmpi, RV_REG_T2, RV_REG_T1, -1);
  // x-1
  RVAnd(tmpi, RV_REG_T1, RV_REG_T1, RV_REG_T2);
  // x &= x-1
  RVJ(tmpi, -20);
  // Jump back to loop
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}
/* Min/Max Operations */
/* Absolute Value */
U0 ICAbs(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // Absolute value
  U8 src_reg, dest_reg = RV_REG_A0;
  if (t2 & MDF_REG) {
    src_reg = r2;
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, t2, r2, d2, rip);
    src_reg = RV_REG_T0;
  }
  if (t1 & MDF_REG)
    dest_reg = r1;
  // if (x < 0) x = -x;
  RVBge(tmpi, src_reg, RV_REG_ZERO, 8);
  // Skip negate if >= 0
  RVNeg(tmpi, dest_reg, src_reg);
  RVJ(tmpi, 8);
  // skip the following 4-byte mv
  RVMv(tmpi, dest_reg, src_reg);
  if (!(t1 & MDF_REG)) {
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, dest_reg, 0, rip);
  }
}
/* Sign Extraction */
#help_index ""
/* ---- Stock-semantics intrinsics (BackB/BackC ICBitOps, ICBrBitOps, ICSwap,
 * ICToUpper, ICQue*, ICModU64, ICSqr). Two-arg intern ICs carry the FIRST
 * source parameter in arg2 and the second in arg1 (OptPass4 IS_2_ARG pops),
 * so Bt(bit_field,bit_num) is arg2=bit_field, arg1=bit_num — exactly what
 * stock `bt r/m64(arg2), reg(arg1)` encodes. arg1 sits on top of the eval
 * stack, so it is always popped first. */
/* Bit ops core: leaves the tested bit (0/1) in a0, applies op to the string.
 * as = bit-string arg (pointer, or the storage itself when by_val),
 * ai = bit-index arg. op: 0 BT, 1 BTS, 2 BTR, 3 BTC. lock: AMO read-modify-write. */
U0 ICBitOpsCore(CIntermediateCode *tmpi, CICArg *ai, CICArg *as, Bool by_val, I64 op, Bool lock, I64 rip)
{
  U8 vreg = 0;
  Bool in_reg = FALSE;
  if (ai->type & MDF_IMM)
    RVLi(tmpi, RV_REG_T1, ai->disp);
  else
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, ai->type, ai->reg, ai->disp, rip);
  if (by_val) {
    if (as->type & MDF_REG) {
      in_reg = TRUE;
      vreg = as->reg;
    } else if (as->type & MDF_IMM) {
      // `imm & (1<<n)` folded to BR_BT on a constant: materialize it.
      in_reg = TRUE;
      vreg = RV_REG_T4;
      RVLi(tmpi, RV_REG_T4, as->disp);
    } else
      ICLea(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, as->type, as->reg, as->disp, rip);
  } else
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, as->type, as->reg, as->disp, rip);
  if (in_reg) {
    RVAndi(tmpi, RV_REG_T1, RV_REG_T1, 63);
    RVSrl(tmpi, RV_REG_T2, vreg, RV_REG_T1);
    RVAndi(tmpi, RV_REG_A0, RV_REG_T2, 1);
    if (op) {
      RVAddi(tmpi, RV_REG_T3, RV_REG_ZERO, 1);
      RVSll(tmpi, RV_REG_T3, RV_REG_T3, RV_REG_T1);
      if (op == 1)
        RVOr(tmpi, vreg, vreg, RV_REG_T3);
      else if (op == 2) {
        RVNot(tmpi, RV_REG_T3, RV_REG_T3);
        RVAnd(tmpi, vreg, vreg, RV_REG_T3);
      } else
        RVXor(tmpi, vreg, vreg, RV_REG_T3);
    }
    return;
  }
  // Bit-string addressing like x86 `bt [mem],reg`: signed index, 64-bit words.
  RVSrai(tmpi, RV_REG_T2, RV_REG_T1, 6);
  RVSlli(tmpi, RV_REG_T2, RV_REG_T2, 3);
  RVAdd(tmpi, RV_REG_T0, RV_REG_T0, RV_REG_T2);
  RVAndi(tmpi, RV_REG_T1, RV_REG_T1, 63);
  if (!op) {
    RVLd(tmpi, RV_REG_T2, RV_REG_T0, 0);
    RVSrl(tmpi, RV_REG_T3, RV_REG_T2, RV_REG_T1);
    RVAndi(tmpi, RV_REG_A0, RV_REG_T3, 1);
    return;
  }
  RVAddi(tmpi, RV_REG_T3, RV_REG_ZERO, 1);
  RVSll(tmpi, RV_REG_T3, RV_REG_T3, RV_REG_T1);
  if (lock) {
    // amo{or,and,xor}.d t2, t3, (t0): t2 = old word. funct7 = funct5<<2 (aq=rl=0).
    if (op == 1)
      RVEmitR(tmpi, 0x2F, RV_REG_T2, 3, RV_REG_T0, RV_REG_T3, 0x20);
    else if (op == 2) {
      RVNot(tmpi, RV_REG_T3, RV_REG_T3);
      RVEmitR(tmpi, 0x2F, RV_REG_T2, 3, RV_REG_T0, RV_REG_T3, 0x30);
    } else
      RVEmitR(tmpi, 0x2F, RV_REG_T2, 3, RV_REG_T0, RV_REG_T3, 0x10);
    RVSrl(tmpi, RV_REG_T3, RV_REG_T2, RV_REG_T1);
    RVAndi(tmpi, RV_REG_A0, RV_REG_T3, 1);
    return;
  }
  RVLd(tmpi, RV_REG_T2, RV_REG_T0, 0);
  RVSrl(tmpi, RV_REG_T4, RV_REG_T2, RV_REG_T1);
  RVAndi(tmpi, RV_REG_A0, RV_REG_T4, 1);
  if (op == 1)
    RVOr(tmpi, RV_REG_T2, RV_REG_T2, RV_REG_T3);
  else if (op == 2) {
    RVNot(tmpi, RV_REG_T3, RV_REG_T3);
    RVAnd(tmpi, RV_REG_T2, RV_REG_T2, RV_REG_T3);
  } else
    RVXor(tmpi, RV_REG_T2, RV_REG_T2, RV_REG_T3);
  RVSd(tmpi, RV_REG_T2, RV_REG_T0, 0);
}

U0 ICBitOpsRV(CIntermediateCode *tmpi, I64 op, Bool lock, I64 rip)
{
  // IC_BT/BTS/BTR/BTC, IC_LBTS/LBTR/LBTC: res = old bit.
  ICBitOpsCore(tmpi, &tmpi->arg1, &tmpi->arg2, ToBool(tmpi->ic_flags & ICF_BY_VAL), op, lock, rip);
  if (tmpi->res.type.mode)
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}

U0 ICBrBitOpsRV(CIntermediateCode *tmpi, CCodeMisc *label, I64 op, Bool br_if_set, I64 rip, I64 rip2)
{
  // IC_BR_BT.. / IC_BR_NOT_BT..: OptPass3 folds `x & (1<<n)` to BY_VAL with the
  // constant bit in arg1 (or arg2 with ICF_SWAP); OptBrZero folds Bt() calls.
  I64 offset;
  if (tmpi->ic_flags & ICF_SWAP)
    ICBitOpsCore(tmpi, &tmpi->arg2, &tmpi->arg1, ToBool(tmpi->ic_flags & ICF_BY_VAL), op, FALSE, rip2);
  else
    ICBitOpsCore(tmpi, &tmpi->arg1, &tmpi->arg2, ToBool(tmpi->ic_flags & ICF_BY_VAL), op, FALSE, rip2);
  if (!label || label->addr == INVALID_PTR)
    offset = 0;
  else
    offset = label->addr - (rip + tmpi->ic_cnt);
  if (br_if_set)
    RVBne(tmpi, RV_REG_A0, RV_REG_ZERO, offset);
  else
    RVBeq(tmpi, RV_REG_A0, RV_REG_ZERO, offset);
}

U0 ICBrMMRV(CIntermediateCode *tmpi, CCodeMisc *label, Bool br_if_zero, I64 rip, I64 rip2)
{
  // IC_BR_MM_ZERO/NOT_ZERO (OptBrZero folds `while (--i)`): decrement, store, branch on new value.
  CHashClass *tmpc = tmpi->ic_class, *tmpc1 = tmpc - 1;
  I64 step = -1, pt = tmpi->arg1_type_pointed_to, offset;
  CICType tloc;
  if (tmpc->ptr_stars_cnt && tmpc1->size != 1)
    step = -tmpc1->size;
  if (!pt)
    pt = RT_I64;
  if (tmpi->ic_flags & ICF_BY_VAL) {
    tloc = (tmpi->arg1.type & MDG_MASK) + pt;
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tloc, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    RVAddi(tmpi, RV_REG_T0, RV_REG_T0, step);
    ICMov(tmpi, tloc, tmpi->arg1.reg, tmpi->arg1.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip2);
  } else {
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T2, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, MDF_DISP + pt, RV_REG_T2, 0, rip2);
    RVAddi(tmpi, RV_REG_T0, RV_REG_T0, step);
    ICRVStoreThru(tmpi, pt, RV_REG_T2, 0, MDF_REG + RT_I64, RV_REG_T0, 0, rip2);
  }
  if (!label || label->addr == INVALID_PTR)
    offset = 0;
  else
    offset = label->addr - (rip + tmpi->ic_cnt);
  if (br_if_zero)
    RVBeq(tmpi, RV_REG_T0, RV_REG_ZERO, offset);
  else
    RVBne(tmpi, RV_REG_T0, RV_REG_ZERO, offset);
}

U0 ICToUpperRV(CIntermediateCode *tmpi, I64 rip)
{
  // if ('a'<=ch<='z') ch-=0x20  →  t1 = (ch-'a') <u 26 ; a0 = ch - (t1<<5)
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  RVAddi(tmpi, RV_REG_T1, RV_REG_T0, -'a');
  RVSltiu(tmpi, RV_REG_T1, RV_REG_T1, 26);
  RVSlli(tmpi, RV_REG_T1, RV_REG_T1, 5);
  RVSub(tmpi, RV_REG_A0, RV_REG_T0, RV_REG_T1);
  if (tmpi->res.type.mode)
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}

U0 ICQueInitRV(CIntermediateCode *tmpi, I64 rip)
{
  // QueInit(head): head->next = head->last = head
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  RVSd(tmpi, RV_REG_T0, RV_REG_T0, 0);
  RVSd(tmpi, RV_REG_T0, RV_REG_T0, 8);
}

U0 ICQueInsRV(CIntermediateCode *tmpi, Bool rev, I64 rip)
{
  // QueIns(entry=arg2, pred=arg1) / QueInsRev(entry=arg2, succ=arg1). arg1 popped first.
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  if (!rev) {
    RVLd(tmpi, RV_REG_T2, RV_REG_T0, 0);
    // t2 = pred->next
    RVSd(tmpi, RV_REG_T1, RV_REG_T0, 0);
    // pred->next = entry
    RVSd(tmpi, RV_REG_T2, RV_REG_T1, 0);
    // entry->next = t2
    RVSd(tmpi, RV_REG_T0, RV_REG_T1, 8);
    // entry->last = pred
    RVSd(tmpi, RV_REG_T1, RV_REG_T2, 8);
    // t2->last = entry
  } else {
    RVLd(tmpi, RV_REG_T2, RV_REG_T0, 8);
    // t2 = succ->last
    RVSd(tmpi, RV_REG_T1, RV_REG_T2, 0);
    // t2->next = entry
    RVSd(tmpi, RV_REG_T0, RV_REG_T1, 0);
    // entry->next = succ
    RVSd(tmpi, RV_REG_T2, RV_REG_T1, 8);
    // entry->last = t2
    RVSd(tmpi, RV_REG_T1, RV_REG_T0, 8);
    // succ->last = entry
  }
}

U0 ICQueRemRV(CIntermediateCode *tmpi, I64 rip)
{
  // QueRem(entry): entry->last->next = entry->next; entry->next->last = entry->last
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  RVLd(tmpi, RV_REG_T1, RV_REG_T0, 0);
  RVLd(tmpi, RV_REG_T2, RV_REG_T0, 8);
  RVSd(tmpi, RV_REG_T1, RV_REG_T2, 0);
  RVSd(tmpi, RV_REG_T2, RV_REG_T1, 8);
}

U0 ICModU64RV(CIntermediateCode *tmpi, I64 rip)
{
  // ModU64(q=arg2, d=arg1): *q /= d unsigned, return remainder.
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  RVLd(tmpi, RV_REG_T2, RV_REG_T0, 0);
  RVEmitR(tmpi, RV_OP_OP, RV_REG_T3, 0x5, RV_REG_T2, RV_REG_T1, 0x01);
  // divu
  RVEmitR(tmpi, RV_OP_OP, RV_REG_A0, 0x7, RV_REG_T2, RV_REG_T1, 0x01);
  // remu
  RVSd(tmpi, RV_REG_T3, RV_REG_T0, 0);
  if (tmpi->res.type.mode)
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}

U0 ICSqrIntRV(CIntermediateCode *tmpi, I64 rip)
{
  // SqrI64/SqrU64: low 64 bits of i*i are the same signed or unsigned.
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  RVEmitR(tmpi, RV_OP_OP, RV_REG_A0, 0x0, RV_REG_T0, RV_REG_T0, 0x01);
  // mul
  if (tmpi->res.type.mode)
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}

U0 ICSwapRV(CIntermediateCode *tmpi, I64 width, I64 rip)
{
  // SwapU8/U16/U32/I64(n1=arg2, n2=arg1): exchange the two pointed-to values.
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T1, 0, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  switch (width) {
    case 1 :
    RVLbu(tmpi, RV_REG_T2, RV_REG_T0, 0);
    RVLbu(tmpi, RV_REG_T3, RV_REG_T1, 0);
    RVSb(tmpi, RV_REG_T3, RV_REG_T0, 0);
    RVSb(tmpi, RV_REG_T2, RV_REG_T1, 0);
    break;
    case 2 :
    RVLhu(tmpi, RV_REG_T2, RV_REG_T0, 0);
    RVLhu(tmpi, RV_REG_T3, RV_REG_T1, 0);
    RVSh(tmpi, RV_REG_T3, RV_REG_T0, 0);
    RVSh(tmpi, RV_REG_T2, RV_REG_T1, 0);
    break;
    case 4 :
    RVLwu(tmpi, RV_REG_T2, RV_REG_T0, 0);
    RVLwu(tmpi, RV_REG_T3, RV_REG_T1, 0);
    RVSw(tmpi, RV_REG_T3, RV_REG_T0, 0);
    RVSw(tmpi, RV_REG_T2, RV_REG_T1, 0);
    break;
    default:
    RVLd(tmpi, RV_REG_T2, RV_REG_T0, 0);
    RVLd(tmpi, RV_REG_T3, RV_REG_T1, 0);
    RVSd(tmpi, RV_REG_T3, RV_REG_T0, 0);
    RVSd(tmpi, RV_REG_T2, RV_REG_T1, 0);
  }
}

U0 ICSign(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // SignI64: (0<x) - (x<0)
  U8 src_reg = RVLoadToReg(tmpi, RV_REG_T0, t2, r2, d2, rip);
  RVSlt(tmpi, RV_REG_T1, RV_REG_ZERO, src_reg);
  RVSlt(tmpi, RV_REG_T2, src_reg, RV_REG_ZERO);
  RVSub(tmpi, RV_REG_A0, RV_REG_T1, RV_REG_T2);
  if (t1.mode)
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}

U0 ICBitScanForward(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // Bsf: index of lowest set bit, -1 for 0 (stock BSF/JZ convention).
  U8 src_reg = RVLoadToReg(tmpi, RV_REG_T0, t2, r2, d2, rip);
  RVMv(tmpi, RV_REG_T1, src_reg);
  RVAddi(tmpi, RV_REG_A0, RV_REG_ZERO, -1);
  RVBeq(tmpi, RV_REG_T1, RV_REG_ZERO, 28);
  // -> done
  RVMv(tmpi, RV_REG_A0, RV_REG_ZERO);
  // loop:
  RVAndi(tmpi, RV_REG_T2, RV_REG_T1, 1);
  RVBne(tmpi, RV_REG_T2, RV_REG_ZERO, 16);
  // -> done
  RVSrli(tmpi, RV_REG_T1, RV_REG_T1, 1);
  RVAddi(tmpi, RV_REG_A0, RV_REG_A0, 1);
  RVJ(tmpi, -16);
  // -> loop
  // done:
  if (t1.mode)
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}

U0 ICBitScanReverse(CIntermediateCode *tmpi, CICType t1, I64 r1, I64 d1, CICType t2, I64 r2, I64 d2, I64 rip)
{
  // Bsr: index of highest set bit, -1 for 0.
  U8 src_reg = RVLoadToReg(tmpi, RV_REG_T0, t2, r2, d2, rip);
  RVMv(tmpi, RV_REG_T1, src_reg);
  RVAddi(tmpi, RV_REG_A0, RV_REG_ZERO, -1);
  RVBeq(tmpi, RV_REG_T1, RV_REG_ZERO, 24);
  // -> done
  RVAddi(tmpi, RV_REG_A0, RV_REG_ZERO, 63);
  // loop:
  RVBlt(tmpi, RV_REG_T1, RV_REG_ZERO, 16);
  // bit63 set -> done
  RVSlli(tmpi, RV_REG_T1, RV_REG_T1, 1);
  RVAddi(tmpi, RV_REG_A0, RV_REG_A0, -1);
  RVJ(tmpi, -12);
  // -> loop
  // done:
  if (t1.mode)
    ICMov(tmpi, t1, r1, d1, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}
/* MinI64/MaxI64/MinU64/MaxU64 (branch-free): t2 = -(a<b); t3 = (a-b)&t2;
 * min = b + t3, max = a - t3. arg1/arg2 order does not matter (symmetric). */
U0 ICMinMaxRV(CIntermediateCode *tmpi, Bool is_max, Bool is_unsigned, I64 rip)
{
  U8 a, b;
  b = RVLoadToReg(tmpi, RV_REG_T1, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip);
  a = RVLoadToReg(tmpi, RV_REG_T0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip);
  if (is_unsigned)
    RVSltu(tmpi, RV_REG_T2, a, b);
  else
    RVSlt(tmpi, RV_REG_T2, a, b);
  RVNeg(tmpi, RV_REG_T2, RV_REG_T2);
  RVSub(tmpi, RV_REG_T3, a, b);
  RVAnd(tmpi, RV_REG_T3, RV_REG_T3, RV_REG_T2);
  if (is_max)
    RVSub(tmpi, RV_REG_A0, a, RV_REG_T3);
  else
    RVAdd(tmpi, RV_REG_A0, b, RV_REG_T3);
  if (tmpi->res.type.mode)
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_A0, 0, rip);
}
