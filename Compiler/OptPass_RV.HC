/* RISC-V Backend - IC to Machine Code Translation
 * 
 * This file implements the final pass that converts IC operations
 * to RISC-V machine code. It replaces the x86-64 specific portions
 * of OptPass789A.HC for RISC-V target.
 */
#help_index "Compiler/Internal/RISCV"
/* Map arg index → a0..a7 without `RV_REG_A0 + n` in call args.
 * Guest Compiler.BIN mis-encoded rd when that form was passed as U8
 * (zero loop emitted andi into s2/s10/sp — hung FileWrite ENTER). */
U8 RVAArgReg(I64 n)
{
  switch (n) {
    case 0 :
    return RV_REG_A0;
    case 1 :
    return RV_REG_A1;
    case 2 :
    return RV_REG_A2;
    case 3 :
    return RV_REG_A3;
    case 4 :
    return RV_REG_A4;
    case 5 :
    return RV_REG_A5;
    case 6 :
    return RV_REG_A6;
    case 7 :
    return RV_REG_A7;
    default:
    return RV_REG_A0;
  }
}
/* Shared ABS_ADDR materialize for IC_ABS_ADDR + CALL_IMPORT remat.
 * Keep OUT of ICToRISCV switch cases (host AOT mishandles mid-case locals).
 * Always PC-rel auipc/addi like host EmitGlobalAddrOff — no CCF_AOT flag
 * guard (that guard fell through to RVLi → Soft Call r=0).
 * Dump proof: addr math is correct (auipc/addi → module_base+data_rip);
 * Soft Call r=0 is missing ASSIGN store through that pointer (not reloc).
 * In-module Soft globals stay PC-rel (PC and data move together on Load). */
U0 RVEmitAbsAddr(CCmpCtrl *cc, CIntermediateCode *tmpi, U8 rd, I64 abs_val, U8 *buf, I64 rip2)
{
  I64 offset, hi, lo;
  cc = cc;
  buf = buf;
  offset = abs_val - rip2 - tmpi->ic_cnt;
  hi = (offset + 0x800) >> 12;
  lo = offset - (hi << 12);
  RVAuipc(tmpi, rd, hi);
  RVAddi(tmpi, rd, rd, lo);
}
/* Soft AOT embed of an absolute U64 (Compiler Fs/Gs, CALL_IMPORT callee).
 * Soft Call Load moves Soft module PC; PC-rel to *external* &Fs then reads
 * module_base-aotc->rip+&Fs (garbage) → Soft Call remat hang. Same GOT
 * shape as known CALL_IMPORT callee (auipc/ld/jal + .dword). */
U0 RVEmitAbsImm64(CIntermediateCode *tmpi, U8 rd, I64 abs_val)
{
  RVAuipc(tmpi, rd, 0);
  RVLd(tmpi, rd, rd, 12);
  RVJal(tmpi, RV_REG_ZERO, 12);
  ICU64(tmpi, abs_val);
}
/* IC_FS/IC_GS: TempleOS _intern Fs()/Gs() — x86 FS/GS seg → RV Compiler Fs/Gs slot
 * (RVAotLibSync keeps that slot = live task). IC_MOV_*: Fs->member folded offset.
 * Soft AOT: abs U64 embed (not PC-rel) — Soft Call remat of Fs&&Fs->hash_table. */
U0 RVEmitFsGs(CCmpCtrl *cc, CIntermediateCode *tmpi, U8 *buf, I64 rip2, Bool is_gs, Bool is_mov)
{
  I64 slot;
  U8 rd;
  if (is_gs)
    slot = &Gs;
  else
    slot = &Fs;
  if (tmpi->res.type & MDF_REG)
    rd = tmpi->res.reg;
  else
    rd = RV_REG_A0;
  if (is_mov) {
    if (cc->flags & CCF_AOT_COMPILE)
      RVEmitAbsImm64(tmpi, RV_REG_T0, slot);
    else
      RVEmitAbsAddr(cc, tmpi, RV_REG_T0, slot, buf, rip2);
    RVLd(tmpi, RV_REG_T0, RV_REG_T0, 0);
    // Member loads are always machine pointer width (not CmpRawType of lite class).
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_DISP + RT_I64, RV_REG_T0, tmpi->ic_data, rip2);
  } else {
    if (cc->flags & CCF_AOT_COMPILE)
      RVEmitAbsImm64(tmpi, rd, slot);
    else
      RVEmitAbsAddr(cc, tmpi, rd, slot, buf, rip2);
    RVLd(tmpi, rd, rd, 0);
    if (!(tmpi->res.type & MDF_REG))
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, rd, 0, rip2);
  }
}
/* Remat &x Soft CALL args: IC_ADDR PUSH_RES over LEA (local) or ABS_ADDR
 * (global) used to fall through to empty FP push-slot ld (MenuLex Soft Call
 * r=1). Remat LEA/ADDR(+lag LEA|ABS) only — no arbitrary LEA walk. */
Bool RVRematLeaOrAddrArg(CCmpCtrl *cc, CIntermediateCode *tmpi, CIntermediateCode *tmpi2, U8 ard, U8 *buf, I64 rip2)
{
  CIntermediateCode *lag;
  if (tmpi2->ic_code == IC_LEA) {
    ICLea(tmpi, MDF_REG + RT_I64, ard, 0, tmpi2->arg1.type, tmpi2->arg1.reg, tmpi2->arg1.disp, rip2);
    return TRUE;
  }
  if (tmpi2->ic_code != IC_ADDR)
    return FALSE;
  lag = OptLag1(tmpi2);
  if (lag && lag->ic_code == IC_LEA) {
    ICLea(tmpi, MDF_REG + RT_I64, ard, 0, lag->arg1.type, lag->arg1.reg, lag->arg1.disp, rip2);
    return TRUE;
  }
  if (lag && lag->ic_code == IC_ABS_ADDR) {
    // &g_cc: PrsExp OptFree(DEREF)+ADDR over ABS_ADDR.
    // In-module Soft glbl: always PC-rel like IC_ABS_ADDR emit. AbsImm64 embeds
    // Soft Cmp heap abs — Soft Call Load does not IET-patch remat dwords → a0
    // stale/low → MenuLexI64Soft Soft Call r=1 (v!=8). External Fs/Gs stay AbsImm64.
    RVEmitAbsAddr(cc, tmpi, ard, lag->ic_data, buf, rip2);
    return TRUE;
  }
  if ((tmpi2->arg1.type & MDG_REG_DISP_SIB_RIP) && !(tmpi2->arg1.type & MDF_STK)) {
    if (tmpi2->arg1.type & MDF_REG)
      ICMov(tmpi, MDF_REG + RT_I64, ard, 0, tmpi2->arg1.type, tmpi2->arg1.reg, tmpi2->arg1.disp, rip2);
    else
      ICLea(tmpi, MDF_REG + RT_I64, ard, 0, tmpi2->arg1.type, tmpi2->arg1.reg, tmpi2->arg1.disp, rip2);
    return TRUE;
  }
  return FALSE;
}
/* Remat ICF_PUSH_RES args into a0..a7 before IC_CALL / CALL_IMPORT.
 * ExePub JIT uses IC_CALL (Cf_EXTERN cleared). Without remat, FileMgr(1,0)
 * leaves a0=last IMM (0) → FM_NORMAL → return NULL (res=0, no pick begin).
 * Stack pushes are IC-order; when n>=2 remat reverses into a0.. — FP loads
 * must use push index k, not ABI arg_slot (DocPrintF local+STR+IMM).
 * Local/reg MOV+PUSH_RES: remat from arg1 (REG/DISP/SIB/RIP), not the call
 * SP slot — Pass6 often leaves no store there (MenuFpOk Soft Call r=4:
 * good fp remat as 0; same class as g_lex_fp=0x20000 Soft Call miss).
 * &x LEA/ADDR(+ABS) PUSH_RES: RVRematLeaOrAddrArg (MenuLex Soft Call r=1).
 * Host EmitLoadArgs skips N<2; Soft STK push already leaves a0 (IMM/REG).
 * FP-slot fallback for n==1 loads an empty Pass6 slot → a0=0 → Soft Call r=4
 * (IMM tip greened then Soft Compiler churn soft-failed). Skip that clobber. */
U0 RVEmitCallArgRemat(CCmpCtrl *cc, CIntermediateCode *tmpi, U8 *buf, I64 rip, I64 rip2, I64 frame_off, I64 call_push)
{
  CIntermediateCode *start_i = NULL, *tmpi2;
  CCodeMisc *lb;
  I64 n = 0, k = 0, rev = 0, arg_slot, call_rip, va_argv_slot = -1;
  Bool is_va = FALSE, got_argv = FALSE;
  U8 ard;
  tmpi2 = OptLag(tmpi);
  while (tmpi2) {
    if (tmpi2->ic_code == IC_CALL_START) {
      start_i = tmpi2;
      break;
    }
    tmpi2 = OptLag(tmpi2);
  }
  if (!start_i)
    return;
  tmpi2 = start_i->next;
  while (tmpi2 && tmpi2 != tmpi && n < 8) {
    if (tmpi2->ic_code > IC_NOP2 && (tmpi2->ic_flags & ICF_PUSH_RES))
      n++;
    tmpi2 = tmpi2->next;
  }
  if (n >= 2)
    rev = 1;
  // Print-class callee: the guest pushes fixed args, then argc, then the vararg VALUES
  // (TempleOS stack-aliased argv). The host ABI wants argv = a POINTER to the first vararg
  // slot, so that slot must be LEA'd, not loaded. IC_CALL_IMPORT already did this; ExePub
  // funs (Print/Cd/FileMgr) arrive as IC_CALL / IC_CALL_EXTERN, whose ic_data is an ADDRESS,
  // not a CHashFun — hence the ICF_RV_VA_ARGC marker PrsFunCall leaves on the argc push.
  // Without it the REPL's Print("%d",42) passed 42 as argv and StrPrintJoin ld'd from 42.
  tmpi2 = start_i->next;
  k = 0;
  while (tmpi2 && tmpi2 != tmpi && k < n) {
    if (tmpi2->ic_code > IC_NOP2 && (tmpi2->ic_flags & ICF_PUSH_RES)) {
      if (tmpi2->ic_flags & ICF_RV_VA_ARGC) {
	if (rev)
	  va_argv_slot = n - k;          //(n-1-k) + 1
	else
	  va_argv_slot = k + 1;
	is_va = TRUE;
      }
      k++;
    }
    tmpi2 = tmpi2->next;
  }
  tmpi2 = start_i->next;
  k = 0;
  while (tmpi2 && tmpi2 != tmpi && k < n) {
    if (tmpi2->ic_code > IC_NOP2 && (tmpi2->ic_flags & ICF_PUSH_RES)) {
      if (rev)
        arg_slot = n - 1 - k;
      else
        arg_slot = k;
      if (is_va && arg_slot > va_argv_slot) {
        // Extra vararg values stay on the stack for argv[i]; do not clobber a-regs.
        k++;
        tmpi2 = tmpi2->next;
        continue;
      }
      ard = RVAArgReg(arg_slot);
      if (is_va && arg_slot == va_argv_slot) {
        // argv must point at the pushed vararg slot. FP-relative arithmetic needs the real
        // frame size, which is 0 for a JIT'd REPL snippet (cc->htc.fun->size unset) — measured
        // FP-24 where the slot was FP-144. SP is exact here: the arg block is live at sp and
        // nothing between the remat instructions moves it, so slot `arg_slot` is sp+arg_slot*8.
        RVAddi(tmpi, ard, RV_REG_SP, arg_slot << 3);
        got_argv = TRUE;
      } else if (tmpi2->ic_code == IC_IMM_I64)
        RVLi(tmpi, ard, tmpi2->ic_data);
      else if (tmpi2->ic_code == IC_MOV && (tmpi2->arg1.type & MDF_IMM))
        RVLi(tmpi, ard, tmpi2->arg1.disp);
      else if (RVRematLeaOrAddrArg(cc, tmpi, tmpi2, ard, buf, rip2)) {
      } else if (tmpi2->ic_code == IC_MOV && (tmpi2->arg1.type & MDG_REG_DISP_SIB_RIP) && !(tmpi2->arg1.type & MDF_STK))
        ICMov(tmpi, MDF_REG + RT_I64, ard, 0, tmpi2->arg1.type, tmpi2->arg1.reg, tmpi2->arg1.disp, rip2);
      else if (tmpi2->res.type & MDF_REG)
        ICMov(tmpi, MDF_REG + RT_I64, ard, 0, MDF_REG + RT_I64, tmpi2->res.reg, 0, rip2);
      else if (tmpi2->ic_code == IC_ABS_ADDR)
        RVEmitAbsAddr(cc, tmpi, ard, tmpi2->ic_data, buf, rip2);
      else if (tmpi2->ic_code == IC_FS || tmpi2->ic_code == IC_GS) {
        if (tmpi2->ic_code == IC_GS)
          call_rip = &Gs;
        else
          call_rip = &Fs;
        if (cc->flags & CCF_AOT_COMPILE)
          RVEmitAbsImm64(tmpi, ard, call_rip);
        else
          RVEmitAbsAddr(cc, tmpi, ard, call_rip, buf, rip2);
        RVLd(tmpi, ard, ard, 0);
      } else if (tmpi2->ic_code == IC_MOV_FS || tmpi2->ic_code == IC_MOV_GS) {
        // OptPass012 folded Fs->member; remat load Compiler Fs/Gs slot + offset.
        if (tmpi2->ic_code == IC_MOV_GS)
          call_rip = &Gs;
        else
          call_rip = &Fs;
        if (cc->flags & CCF_AOT_COMPILE)
          RVEmitAbsImm64(tmpi, RV_REG_T0, call_rip);
        else
          RVEmitAbsAddr(cc, tmpi, RV_REG_T0, call_rip, buf, rip2);
        RVLd(tmpi, RV_REG_T0, RV_REG_T0, 0);
        if (tmpi2->ic_data >= -2048 && tmpi2->ic_data <= 2047)
          RVLd(tmpi, ard, RV_REG_T0, tmpi2->ic_data);
        else {
          RVLi(tmpi, RV_REG_T6, tmpi2->ic_data);
          RVAdd(tmpi, RV_REG_T6, RV_REG_T0, RV_REG_T6);
          RVLd(tmpi, ard, RV_REG_T6, 0);
        }
      } else if (tmpi2->ic_code == IC_STR_CONST) {
        lb = tmpi2->ic_data(CCodeMisc *);
        if (!lb || lb->addr == INVALID_PTR) {
          call_rip = 0;
          tmpi->ic_flags &= ~ICF_CODE_FINAL;
        } else
          call_rip = lb->addr - rip - tmpi->ic_cnt;
        RVAuipc(tmpi, ard, (call_rip + 0x800) >> 12 & 0xFFFFF);
        RVAddi(tmpi, ard, ard, call_rip << 52 >> 52);
      } else if (n >= 2) {
        // Any other pushing IC (e.g. ABS_ADDR+DEREF of a heap global above I32_MAX, which
        // OptPass4 cannot fold to RIP): the value IS on the stack — the arg block is live at
        // sp and slot arg_slot is sp+arg_slot*8 (same as the argv remat). The old FP-relative
        // guess read an unrelated frame slot (DisasmAt(xa,2,0) got an F64 pattern in a0).
        // n==1: keep a0 from the STK push.
        RVLd(tmpi, ard, RV_REG_SP, arg_slot << 3);
      }
      k++;
    }
    tmpi2 = tmpi2->next;
  }
  if (is_va && !got_argv && va_argv_slot >= 0 && va_argv_slot < 8)
    RVLi(tmpi, RVAArgReg(va_argv_slot), 0);
}
/* Ident emit dump — keep OUT of ICToRISCV switch (host AOT mid-case locals).
 * A:/AsgIdentEm.DD bytes: byv,pt,a1mode,a1raw,a2mode,a2raw,resmode,resraw,
 * br(1=BYvalDISP 2=BYvalOther 3=REG 4=indir), cnt_after, a1reg, a2reg, resreg,
 * code(ASSIGN=…), pad */
U0 ICIdentEmitDump(CCmpCtrl *cc, CIntermediateCode *tmpi, I64 br)
{
  U8 buf[16];
  if (!cc->htc.fun || !cc->htc.fun->str || StrCmp(cc->htc.fun->str, "AdamLiteIdentProbe"))
    return;
  buf[0] = 0;
  if (tmpi->ic_flags & ICF_BY_VAL)
    buf[0] = 1;
  buf[1] = tmpi->arg1_type_pointed_to;
  buf[2] = tmpi->arg1.type.mode;
  buf[3] = tmpi->arg1.type.raw_type;
  buf[4] = tmpi->arg2.type.mode;
  buf[5] = tmpi->arg2.type.raw_type;
  buf[6] = tmpi->res.type.mode;
  buf[7] = tmpi->res.type.raw_type;
  buf[8] = br;
  buf[9] = tmpi->ic_cnt;
  buf[10] = tmpi->arg1.reg;
  buf[11] = tmpi->arg2.reg;
  buf[12] = tmpi->res.reg;
  buf[13] = tmpi->ic_code;
  buf[14] = tmpi->arg1.type(U8);
  buf[15] = tmpi->arg2.type(U8);
  FileWrite("A:/AsgIdentEm.DD", buf, 16);
}
/* Main IC to RISC-V Translation Function */
U0 ICToRISCV(CCmpCtrl *cc, CIntermediateCode *tmpi, U8 *buf, I64 rip, I64 *_rip2, COptReg *reg_offsets)
{
  // Translate single IC operation to RISC-V machine code
  I64 code = tmpi->ic_code;
  CCodeMisc *lb;
  I64 offset, rip2, call_rip, jal_off, i, j;
  CHashFun *tmpf;
  CHashExport *tmpex;
  CExternUsage *tmpeu;
  CAOTImportExport *tmpie;
  CHashClass *tmpc;
  CICType tdrf;
  /* Match OptPass789A.HC: AOT rip2 is module-absolute (aotc->rip+rip),
   * JIT rip2 is buf+rip. Labels/jmps stay function-local (rip). */
  rip2 = rip;
  if (cc->flags & CCF_AOT_COMPILE && cc->aotc)
    rip2 += cc->aotc->rip;
  else if (buf)
    rip2 += buf;
  tmpi->ic_cnt = 0;
  switch (code) {
    /* Data Movement */
    case IC_NOP1 :
    case IC_NOP2 :
    // No operation - already handled by optimizer
    break;
    case IC_ADDR :
    // &local / &name[i] — same as MOV (stock OptPass789A)
    case IC_MOV :
    if (tmpi->ic_class->raw_type == RT_F64) {
      ICFMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    } else {
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    }
    break;
    case IC_LEA :
    ICLea(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_PUSH :
    if (tmpi->arg1.type & MDF_REG) {
      RVPush(tmpi, tmpi->arg1.reg);
    } else {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
      RVPush(tmpi, RV_REG_T0);
    }
    break;
    case IC_POP :
    if (tmpi->res.type & MDF_REG) {
      RVPop(tmpi, tmpi->res.reg);
    } else {
      RVPop(tmpi, RV_REG_T0);
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip2);
    }
    break;
    /* Arithmetic Operations */
    case IC_ADD :
    if (tmpi->ic_class->raw_type == RT_F64) {
      ICFAdd(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    } else {
      ICAdd(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    }
    break;
    case IC_ADD_CONST :
    ICAdd(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, MDF_IMM + RT_I64, 0, tmpi->ic_data, rip2);
    break;
    case IC_SUB :
    if (tmpi->ic_class->raw_type == RT_F64) {
      ICFSub(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    } else {
      ICSub(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    }
    break;
    case IC_SUB_CONST :
    ICSub(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, MDF_IMM + RT_I64, 0, tmpi->ic_data, rip2);
    break;
    case IC_MUL :
    if (tmpi->ic_class->raw_type == RT_F64) {
      ICFMul(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    } else {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      ICMul(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, is_unsigned);
    }
    break;
    case IC_DIV :
    if (tmpi->ic_class->raw_type == RT_F64) {
      ICFDiv(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    } else {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      ICDiv(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, is_unsigned);
    }
    break;
    case IC_MOD :
    
    {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      ICMod(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, is_unsigned);
    }
    break;
    /* Bitwise Operations */
    case IC_AND :
    ICAnd(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    break;
    case IC_OR :
    ICOr(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    break;
    case IC_XOR :
    ICXor(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    break;
    case IC_COM :
    ICCom(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    /* Shift Operations — CONST forms take shamt from ic_data (x86 ICShift;
     * same as ADD_CONST). Passing arg2 (IS_1_ARG / MemSet 0) Soft-hung
     * glbl[var] (ABS + SHL_CONST + ADD) at first OptPass789A emit. */
    case IC_SHL :
    ICShl(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    break;
    case IC_SHL_CONST :
    ICShl(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, MDF_IMM + RT_I64, 0, tmpi->ic_data, rip2);
    break;
    case IC_SHR :
    
    {
      Bool is_signed = !(tmpi->ic_class->raw_type & RTF_UNSIGNED);
      ICShr(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, is_signed);
    }
    break;
    case IC_SHR_CONST :
    
    {
      Bool is_signed = !(tmpi->ic_class->raw_type & RTF_UNSIGNED);
      ICShr(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, MDF_IMM + RT_I64, 0, tmpi->ic_data, rip2, is_signed);
    }
    break;
    /* Unary Operations */
    case IC_UNARY_MINUS :
    if (tmpi->ic_class->raw_type == RT_F64) {
      ICFNeg(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    } else {
      ICUnaryMinus(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    }
    break;
    case IC_NOT :
    ICNot(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_TO_BOOL :
    ICToBool(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    /* Type Conversions */
    case IC_TO_F64 :
    
    {
      Bool is_unsigned = tmpi->arg1.type.raw_type & RTF_UNSIGNED;
      ICToF64(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2, is_unsigned);
    }
    break;
    case IC_TO_I64 :
    
    {
      Bool is_unsigned = tmpi->res.type.raw_type & RTF_UNSIGNED;
      ICToI64(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2, is_unsigned);
    }
    break;
    /* Comparison Operations */
    case IC_EQU_EQU :
    if (tmpi->ic_class->raw_type == RT_F64) {
      ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 0);
    } else {
      ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 0, FALSE);
    }
    break;
    case IC_NOT_EQU :
    if (tmpi->ic_class->raw_type == RT_F64) {
      ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 1);
    } else {
      ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 1, FALSE);
    }
    break;
    case IC_LESS :
    
    {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 2);
      } else {
        ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 2, is_unsigned);
      }
    }
    break;
    case IC_GREATER :
    
    {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 4);
      } else {
        ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 4, is_unsigned);
      }
    }
    break;
    case IC_LESS_EQU :
    
    {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 5);
      } else {
        ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 5, is_unsigned);
      }
    }
    break;
    case IC_GREATER_EQU :
    
    {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      if (tmpi->ic_class->raw_type == RT_F64) {
        ICFCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 3);
      } else {
        ICCmp(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2, 3, is_unsigned);
      }
    }
    break;
    /* Boolean Operations */
    case IC_AND_AND :
    ICAndAnd(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    break;
    case IC_OR_OR :
    ICOrOr(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    break;
    case IC_XOR_XOR :
    ICXorXor(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    break;
    /* Branches — label->addr is function-local; pass rip not rip2. */
    case IC_BR_ZERO :
    ICBranchZero(tmpi, tmpi->ic_data, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip, rip2);
    break;
    case IC_BR_NOT_ZERO :
    ICBranchNotZero(tmpi, tmpi->ic_data, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip, rip2);
    break;
    case IC_BR_EQU_EQU :
    case IC_BR_EQU_EQU2 :
    
    {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      ICBranch(tmpi, tmpi->ic_data, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip, rip2, 0, is_unsigned);
      // *2: stock has_res — leave arg2 in res for PUSH_CMP/POP_CMP consumers.
      if (code == IC_BR_EQU_EQU2 && tmpi->res.type.mode)
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    }
    break;
    case IC_BR_NOT_EQU :
    case IC_BR_NOT_EQU2 :
    
    {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      ICBranch(tmpi, tmpi->ic_data, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip, rip2, 1, is_unsigned);
      if (code == IC_BR_NOT_EQU2 && tmpi->res.type.mode)
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    }
    break;
    case IC_BR_LESS :
    case IC_BR_LESS2 :
    
    {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      ICBranch(tmpi, tmpi->ic_data, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip, rip2, 2, is_unsigned);
      if (code == IC_BR_LESS2 && tmpi->res.type.mode)
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    }
    break;
    case IC_BR_GREATER :
    case IC_BR_GREATER2 :
    
    {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      ICBranch(tmpi, tmpi->ic_data, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip, rip2, 4, is_unsigned);
      if (code == IC_BR_GREATER2 && tmpi->res.type.mode)
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    }
    break;
    case IC_BR_LESS_EQU :
    case IC_BR_LESS_EQU2 :
    
    {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      ICBranch(tmpi, tmpi->ic_data, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip, rip2, 5, is_unsigned);
      if (code == IC_BR_LESS_EQU2 && tmpi->res.type.mode)
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    }
    break;
    case IC_BR_GREATER_EQU :
    case IC_BR_GREATER_EQU2 :
    
    {
      Bool is_unsigned = tmpi->ic_class->raw_type & RTF_UNSIGNED;
      ICBranch(tmpi, tmpi->ic_data, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip, rip2, 3, is_unsigned);
      if (code == IC_BR_GREATER_EQU2 && tmpi->res.type.mode)
        ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg2.type, tmpi->arg2.reg, tmpi->arg2.disp, rip2);
    }
    break;
    case IC_BR_AND_ZERO :
    // Soft MenuFpOk Soft Call r=4: OptBrZero folds `fp&1` → BR_AND_ZERO (149);
    // unimplemented emit → Soft Call always takes return-0 path.
    ICAndBranch(tmpi, tmpi->ic_data, TRUE, rip, rip2);
    break;
    case IC_BR_AND_NOT_ZERO :
    ICAndBranch(tmpi, tmpi->ic_data, FALSE, rip, rip2);
    break;
    /* Jumps and Calls — JMP/SUB_CALL use function-local rip; CALL uses rip2. */
    case IC_JMP :
    ICJmp(tmpi, tmpi->ic_data, rip);
    break;
    case IC_SUB_CALL :
    // Subroutine call (used for switch cases, etc.)
    lb = tmpi->ic_data;
    offset = lb->addr - rip;
    RVJal(tmpi, RV_REG_RA, offset);
    break;
    case IC_CALL :
    // ExePub HTT_FUN (FileMgr/Cd/…) → IC_CALL not CALL_IMPORT; remat a0.. like IMPORT.
    
    {
      I64 fsz = 16, alloc = 0, call_push = 0, jbit = 0;
      CIntermediateCode *tmpi2;
      if (cc->htc.fun) {
        alloc = cc->htc.fun->size;
        if (alloc < 0)
          alloc = -alloc;
        if (alloc & 15)
          alloc = alloc + 16 - (alloc & 15);
        fsz = 16 + alloc;
        while (jbit < 32) {
          if (cc->htc.fun->used_reg_mask & (REGG_LOCAL_VARS | REGG_LOCAL_NON_PTR_VARS) & (1 << jbit))
            call_push += 8;
          jbit++;
        }
      }
      tmpi2 = OptLag(tmpi);
      while (tmpi2) {
        if (tmpi2->ic_code == IC_CALL_START) {
          jbit = 0;
          while (jbit < 32) {
            if (tmpi2->ic_data & (1 << jbit))
              call_push += 8;
            jbit++;
          }
          break;
        }
        tmpi2 = OptLag(tmpi2);
      }
      RVEmitCallArgRemat(cc, tmpi, buf, rip, rip2, fsz, call_push);
    }
    ICCall(tmpi, tmpi->ic_data, rip2);
    break;
    case IC_CALL_INDIRECT :
    // Stack-based indirect call; preserve ra like ICCall.
    RVLd(tmpi, RV_REG_T6, RV_REG_SP, tmpi->ic_data);
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -16);
    RVSd(tmpi, RV_REG_RA, RV_REG_SP, 8);
    RVJalr(tmpi, RV_REG_RA, RV_REG_T6, 0);
    RVLd(tmpi, RV_REG_RA, RV_REG_SP, 8);
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 16);
    break;
    case IC_CALL_INDIRECT2 :
    // Indirect call through pointer; preserve ra.
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -16);
    RVSd(tmpi, RV_REG_RA, RV_REG_SP, 8);
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T6, 0, MDF_DISP + RT_I64, 0, tmpi->ic_data, rip2);
    RVJalr(tmpi, RV_REG_RA, RV_REG_T6, 0);
    RVLd(tmpi, RV_REG_RA, RV_REG_SP, 8);
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 16);
    break;
    case IC_CALL_EXTERN :
    // Same-module forward ref: JAL placeholder; AOTGlblsResolve patches J-type imm.
    // Remat PUSH_RES into a0.. like IC_CALL — without it Soft MenuFpOk(good)
    // left a0 from the prior IMM call (often 0/1) → accept path r=4.
    
    {
      I64 fsz = 16, alloc = 0, call_push = 0, jbit = 0;
      CIntermediateCode *tmpi2;
      if (cc->htc.fun) {
        alloc = cc->htc.fun->size;
        if (alloc < 0)
          alloc = -alloc;
        if (alloc & 15)
          alloc = alloc + 16 - (alloc & 15);
        fsz = 16 + alloc;
        while (jbit < 32) {
          if (cc->htc.fun->used_reg_mask & (REGG_LOCAL_VARS | REGG_LOCAL_NON_PTR_VARS) & (1 << jbit))
            call_push += 8;
          jbit++;
        }
      }
      tmpi2 = OptLag(tmpi);
      while (tmpi2) {
        if (tmpi2->ic_code == IC_CALL_START) {
          jbit = 0;
          while (jbit < 32) {
            if (tmpi2->ic_data & (1 << jbit))
              call_push += 8;
            jbit++;
          }
          break;
        }
        tmpi2 = OptLag(tmpi2);
      }
      RVEmitCallArgRemat(cc, tmpi, buf, rip, rip2, fsz, call_push);
    }
    tmpf = tmpi->ic_data(CHashFun *);
    call_rip = rip;
    if (cc->flags & CCF_AOT_COMPILE && cc->aotc)
      call_rip += cc->aotc->rip;
    else if (buf)
      call_rip += buf;
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -16);
    RVSd(tmpi, RV_REG_RA, RV_REG_SP, 8);
    jal_off = tmpi->ic_cnt;
    RVJal(tmpi, RV_REG_RA, 0);
    if (buf && cc->flags & CCF_AOT_COMPILE && tmpf) {
      tmpeu = CAlloc(sizeof(CExternUsage));
      tmpeu->next = tmpf->ext_lst;
      tmpf->ext_lst = tmpeu;
      tmpeu->rip = call_rip + jal_off;
    }
    RVLd(tmpi, RV_REG_RA, RV_REG_SP, 8);
    RVAddi(tmpi, RV_REG_SP, RV_REG_SP, 16);
    break;
    case IC_CALL_IMPORT :
    // Remat PUSH_RES into a0... If first PUSH_RES is IMM and any STR follows
    // (RTL IC for FileWrite(path,buf,size)), reverse-assign; else LTR.
    // After _RV_HC_CALL (SP=FP-2048), rebuild SP so ADD_RSP/CALL_END/LEAVE
    // see the same depth as a non-veneer call (store-then-FileWrite hang).
    tmpf = tmpi->ic_data(CHashFun *);
    call_rip = rip;
    if (cc->flags & CCF_AOT_COMPILE && cc->aotc)
      call_rip += cc->aotc->rip;
    i = 0;
    if (cc->htc.fun) {
      i = cc->htc.fun->size;
      if (i < 0)
        i = -i;
    }
    if (i & 15)
      i = i + 16 - (i & 15);
    offset = 16 + i;
    // ENTER PushRegs(local vars) sit below the frame; keep them in depth.
    jal_off = 0;
    if (cc->htc.fun) {
      j = 0;
      while (j < 32) {
        if (cc->htc.fun->used_reg_mask & (REGG_LOCAL_VARS | REGG_LOCAL_NON_PTR_VARS) & (1 << j))
          jal_off += 8;
        j++;
      }
    }
    i = 0;
    
    {
      CIntermediateCode *tmpi2 = OptLag(tmpi);
      I64 call_push = 0;
      while (tmpi2) {
        if (tmpi2->ic_code == IC_CALL_START) {
          j = 0;
          while (j < 32) {
            if (tmpi2->ic_data & (1 << j))
              call_push += 8;
            j++;
          }
          break;
        }
        if (tmpi2->ic_code > IC_NOP2 && (tmpi2->ic_flags & ICF_PUSH_RES))
          i++;
        tmpi2 = OptLag(tmpi2);
      }
      jal_off += call_push;
    }
    if (tmpf) {
      if (tmpf->arg_cnt > i)
        i = tmpf->arg_cnt;
      else if (tmpf->member_cnt > i)
        i = tmpf->member_cnt;
    }
    if (tmpi->next && (tmpi->next->ic_code == IC_ADD_RSP || tmpi->next->ic_code == IC_ADD_RSP1) && tmpi->next->ic_data > i << 3)
      i = tmpi->next->ic_data >> 3;
    if (i > 8)
      i = 8;
    
    {
      CIntermediateCode *start_i = NULL, *tmpi2;
      I64 n = 0, k = 0, rev = 0, arg_slot, va_argv_slot = -1, va_i;
      Bool is_va = FALSE, got_argv = FALSE;
      CMemberLst *va_m;
      U8 ard;
      tmpi2 = OptLag(tmpi);
      while (tmpi2) {
        if (tmpi2->ic_code == IC_CALL_START) {
          start_i = tmpi2;
          break;
        }
        tmpi2 = OptLag(tmpi2);
      }
      if (start_i) {
        tmpi2 = start_i->next;
        while (tmpi2 && tmpi2 != tmpi && n < 8) {
          if (tmpi2->ic_code > IC_NOP2 && (tmpi2->ic_flags & ICF_PUSH_RES))
            n++;
          tmpi2 = tmpi2->next;
        }
      }
      if (n > i)
        i = n;
      if (i > 8)
        i = 8;
      // COCPush appends args RTL (last parsed = list head). Typed remat
      // into a0.. must reverse; FileWrite(size,...) was only IMM-first before
      // — StrCpy(glbl,"lit") RTL is STR then ABS → LTR remat swapped dst/src
      // (Lex Soft Call r=0 / seed-X kept X).
      // Stack pushes follow IC order (first PUSH = FP-(frame+8)); ABI a0 is
      // last IC when RTL. Remat regs by arg_slot, but FP loads by push index k
      // — using arg_slot for FP made DocPrintF(doc,"%d",8) put IMM in a0
      // (hang / DocSize r=4).
      // Host vararg (DocPrint/...): fixed+argc+argv_ptr. Guest PrsFunCall
      // pushes fixed+argc+vararg *values* (TempleOS stack-aliased argv). Remat
      // must LEA the first-vararg FP slot into argv, not RVLi the value (r=4).
      is_va = FALSE;
      va_argv_slot = -1;
      got_argv = FALSE;
      if (tmpf && Bt(&tmpf->flags, Ff_DOT_DOT_DOT)) {
        is_va = TRUE;
        va_argv_slot = tmpf->arg_cnt + 1;
      } else if (tmpf) {
        // Ff_DOT_DOT_DOT lives on the FUNCTION, but a Print-class fun can reach the guest
        // through the kernel export table (RVAC / RVCmpImports) with only MLF_DOT_DOT_DOT on
        // the member after the fixed args. PrsFunCall keys its vararg parse off that member,
        // so key the ABI off it too — otherwise the call parses as variadic but remats the
        // first vararg VALUE into argv, and Print("%d",42) made StrPrintJoin ld from 42.
        va_m = tmpf->member_lst_and_root;
        va_i = tmpf->arg_cnt;
        while (va_i-- && va_m)
          va_m = va_m->next;
        if (va_m && va_m->flags & MLF_DOT_DOT_DOT) {
          is_va = TRUE;
          va_argv_slot = tmpf->arg_cnt + 1;
        }
      }
      if (n >= 2)
        rev = 1;
      if (start_i) {
        tmpi2 = start_i->next;
        k = 0;
        while (tmpi2 && tmpi2 != tmpi && k < n) {
          if (tmpi2->ic_code > IC_NOP2 && (tmpi2->ic_flags & ICF_PUSH_RES)) {
            if (rev)
              arg_slot = n - 1 - k;
            else
              arg_slot = k;
            if (is_va && arg_slot > va_argv_slot) {
              // Extra vararg values stay on stack for argv[i]; do not clobber a-regs.
              k++;
              tmpi2 = tmpi2->next;
              continue;
            }
            ard = RVAArgReg(arg_slot);
            if (is_va && arg_slot == va_argv_slot) {
              // Host argv = LEA of this push's FP slot (first ABI vararg).
              call_rip = -(offset + jal_off + ((k + 1) << 3));
              if (call_rip >= -2048 && call_rip <= 2047)
                RVAddi(tmpi, ard, RV_REG_FP, call_rip);
              else {
                RVLi(tmpi, RV_REG_T6, call_rip);
                RVAdd(tmpi, ard, RV_REG_FP, RV_REG_T6);
              }
              got_argv = TRUE;
            } else if (tmpi2->ic_code == IC_IMM_I64)
              RVLi(tmpi, ard, tmpi2->ic_data);
            else if (tmpi2->ic_code == IC_MOV && (tmpi2->arg1.type & MDF_IMM))
              RVLi(tmpi, ard, tmpi2->arg1.disp);
            else if (RVRematLeaOrAddrArg(cc, tmpi, tmpi2, ard, buf, rip2)) {
            } else if (tmpi2->ic_code == IC_MOV && (tmpi2->arg1.type & MDG_REG_DISP_SIB_RIP) && !(tmpi2->arg1.type & MDF_STK))
              ICMov(tmpi, MDF_REG + RT_I64, ard, 0, tmpi2->arg1.type, tmpi2->arg1.reg, tmpi2->arg1.disp, rip2);
            else if (tmpi2->res.type & MDF_REG)
              ICMov(tmpi, MDF_REG + RT_I64, ard, 0, MDF_REG + RT_I64, tmpi2->res.reg, 0, rip2);
            else if (tmpi2->ic_code == IC_ABS_ADDR)
              RVEmitAbsAddr(cc, tmpi, ard, tmpi2->ic_data, buf, rip2);
            else if (tmpi2->ic_code == IC_FS || tmpi2->ic_code == IC_GS) {
              if (tmpi2->ic_code == IC_GS)
                call_rip = &Gs;
              else
                call_rip = &Fs;
              if (cc->flags & CCF_AOT_COMPILE)
                RVEmitAbsImm64(tmpi, ard, call_rip);
              else
                RVEmitAbsAddr(cc, tmpi, ard, call_rip, buf, rip2);
              RVLd(tmpi, ard, ard, 0);
            } else if (tmpi2->ic_code == IC_MOV_FS || tmpi2->ic_code == IC_MOV_GS) {
              if (tmpi2->ic_code == IC_MOV_GS)
                call_rip = &Gs;
              else
                call_rip = &Fs;
              if (cc->flags & CCF_AOT_COMPILE)
                RVEmitAbsImm64(tmpi, RV_REG_T0, call_rip);
              else
                RVEmitAbsAddr(cc, tmpi, RV_REG_T0, call_rip, buf, rip2);
              RVLd(tmpi, RV_REG_T0, RV_REG_T0, 0);
              if (tmpi2->ic_data >= -2048 && tmpi2->ic_data <= 2047)
                RVLd(tmpi, ard, RV_REG_T0, tmpi2->ic_data);
              else {
                RVLi(tmpi, RV_REG_T6, tmpi2->ic_data);
                RVAdd(tmpi, RV_REG_T6, RV_REG_T0, RV_REG_T6);
                RVLd(tmpi, ard, RV_REG_T6, 0);
              }
            } else if (tmpi2->ic_code == IC_STR_CONST) {
              lb = tmpi2->ic_data(CCodeMisc *);
              if (!lb || lb->addr == INVALID_PTR) {
                call_rip = 0;
                tmpi->ic_flags &= ~ICF_CODE_FINAL;
              } else
                call_rip = lb->addr - rip - tmpi->ic_cnt;
              RVAuipc(tmpi, ard, (call_rip + 0x800) >> 12 & 0xFFFFF);
              RVAddi(tmpi, ard, ard, call_rip << 52 >> 52);
            } else if (n >= 2) {
              // n==1: keep a0 from STK push (same Soft Call MenuFpOk r=4 class).
              call_rip = -(offset + jal_off + ((k + 1) << 3));
              if (call_rip >= -2048 && call_rip <= 2047)
                RVLd(tmpi, ard, RV_REG_FP, call_rip);
              else {
                RVLi(tmpi, RV_REG_T6, call_rip);
                RVAdd(tmpi, RV_REG_T6, RV_REG_FP, RV_REG_T6);
                RVLd(tmpi, ard, RV_REG_T6, 0);
              }
            }
            k++;
          }
          tmpi2 = tmpi2->next;
        }
      }
      if (is_va && !got_argv && va_argv_slot >= 0 && va_argv_slot < 8)
        RVLi(tmpi, RVAArgReg(va_argv_slot), 0);
      if (is_va && va_argv_slot + 1 > i && va_argv_slot + 1 <= 8)
        i = va_argv_slot + 1;
    }
    j = i;
    while (j < 5) {
      RVLi(tmpi, RVAArgReg(j), 0);
      j++;
    }
    call_rip = rip;
    if (cc->flags & CCF_AOT_COMPILE && cc->aotc)
      call_rip += cc->aotc->rip;
    
    {
      I64 callee = 0, patch_off = 0, post_sp;
      if (tmpf && tmpf->str) {
        tmpex = HashFind(tmpf->str, Fs->hash_table, HTT_EXPORT_SYS_SYM);
        if (tmpex)
          callee = tmpex->val;
      }
      if (callee) {
        RVAuipc(tmpi, RV_REG_T1, 0);
        RVLd(tmpi, RV_REG_T1, RV_REG_T1, 12);
        RVJal(tmpi, RV_REG_ZERO, 12);
        patch_off = tmpi->ic_cnt;
        ICU64(tmpi, callee);
      } else {
        RVAuipc(tmpi, RV_REG_T1, 0);
        RVLd(tmpi, RV_REG_T1, RV_REG_T1, 12);
        RVJal(tmpi, RV_REG_ZERO, 12);
        patch_off = tmpi->ic_cnt;
        ICU64(tmpi, 0);
        if (buf && cc->flags & CCF_AOT_COMPILE && tmpf) {
          tmpie = CAlloc(sizeof(CAOTImportExport));
          tmpie->type = IET_IMM_I64;
          tmpie->rip = call_rip + patch_off;
          tmpie->next = tmpf->ie_lst;
          tmpf->ie_lst = tmpie;
        }
      }
      callee = 0;
      tmpex = HashFind("RVHCCall", Fs->hash_table, HTT_EXPORT_SYS_SYM);
      if (tmpex)
        callee = tmpex->val;
      if (!callee)
        RVJalr(tmpi, RV_REG_RA, RV_REG_T1, 0);
      else {
        RVAuipc(tmpi, RV_REG_T0, 0);
        RVLd(tmpi, RV_REG_T0, RV_REG_T0, 12);
        RVJal(tmpi, RV_REG_ZERO, 12);
        ICU64(tmpi, callee);
        RVJalr(tmpi, RV_REG_RA, RV_REG_T0, 0);
      }
      // Veneer left SP=FP-2048; match non-veneer depth for ADD_RSP+CALL_END.
      post_sp = -(offset + jal_off + (i << 3));
      if (post_sp >= -2048 && post_sp <= 2047)
        RVAddi(tmpi, RV_REG_SP, RV_REG_FP, post_sp);
      else {
        RVLi(tmpi, RV_REG_T6, post_sp);
        RVAdd(tmpi, RV_REG_SP, RV_REG_FP, RV_REG_T6);
      }
    }
    break;
    case IC_RET :
    RVRet(tmpi);
    break;
    case IC_RETURN_VAL :
    // Move return value to a0
    // F64 returns as raw bits in a0 too (host AOT/runtime convention).
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_A0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_RETURN_VAL2 :
    // Return value already in a0/fa0, nothing to do
    break;
    /* Function Prologue/Epilogue */
    case IC_ENTER :
    ICEnter(tmpi, tmpi->ic_data);
    if (cc->htc.fun && reg_offsets) {
      ICPushRegs(tmpi, cc->htc.fun->used_reg_mask & (REGG_LOCAL_VARS | REGG_LOCAL_NON_PTR_VARS));
      for (i = 0; i < REG_REGS_NUM; i++) {
        if (reg_offsets[i].offset > 0 && reg_offsets[i].offset != I64_MAX && reg_offsets[i].m) {
          tmpc = OptClassFwd(reg_offsets[i].m->member_class);
          ICMov(tmpi, MDF_REG + RT_I64, i, 0, MDF_DISP + tmpc->raw_type, REG_RBP, reg_offsets[i].offset, rip2);
        }
      }
    }
    break;
    case IC_LEAVE :
    if (cc->htc.fun) {
      ICPopRegs(tmpi, cc->htc.fun->used_reg_mask & (REGG_LOCAL_VARS | REGG_LOCAL_NON_PTR_VARS));
    }
    ICLeave(tmpi, tmpi->ic_data);
    break;
    case IC_PUSH_REGS :
    ICPushRegs(tmpi, tmpi->ic_data);
    break;
    case IC_POP_REGS :
    ICPopRegs(tmpi, tmpi->ic_data);
    break;
    case IC_ADD_RSP :
    case IC_ADD_RSP1 :
    ICAddRSP(tmpi, tmpi->ic_data, TRUE);
    break;
    /* Switch Statement */
    case IC_SWITCH :
    case IC_NOBOUND_SWITCH :
    // ic_data points to switch table structure
    // TODO: Need to extract table info from ic_data
    // ICSwitch(tmpi, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp,
    //          jump_table, table_size, rip2);
    break;
    /* Bit Manipulation */
    case IC_BT :
    ICBitOpsRV(tmpi, 0, FALSE, rip2);
    break;
    case IC_BTS :
    ICBitOpsRV(tmpi, 1, FALSE, rip2);
    break;
    case IC_BTR :
    ICBitOpsRV(tmpi, 2, FALSE, rip2);
    break;
    case IC_BTC :
    ICBitOpsRV(tmpi, 3, FALSE, rip2);
    break;
    case IC_LBTS :
    ICBitOpsRV(tmpi, 1, TRUE, rip2);
    break;
    case IC_LBTR :
    ICBitOpsRV(tmpi, 2, TRUE, rip2);
    break;
    case IC_LBTC :
    ICBitOpsRV(tmpi, 3, TRUE, rip2);
    break;
    case IC_BSF :
    ICBitScanForward(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_BSR :
    ICBitScanReverse(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    /* Min/Max/Abs/Sign */
    case IC_MIN_I64 :
    ICMinMaxRV(tmpi, FALSE, FALSE, rip2);
    break;
    case IC_MIN_U64 :
    ICMinMaxRV(tmpi, FALSE, TRUE, rip2);
    break;
    case IC_MAX_I64 :
    ICMinMaxRV(tmpi, TRUE, FALSE, rip2);
    break;
    case IC_MAX_U64 :
    ICMinMaxRV(tmpi, TRUE, TRUE, rip2);
    break;
    case IC_ABS_I64 :
    ICAbs(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_ABS :
    ICFAbs(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_SIGN_I64 :
    ICSign(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_SQRT :
    ICFSqrt(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_SIN :
    ICFSin(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_COS :
    ICFCos(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_TAN :
    ICFTan(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_ATAN :
    ICFAtan(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    /* Swap two pointed-to values (stock ICSwap) */
    case IC_SWAP_U8 :
    ICSwapRV(tmpi, 1, rip2);
    break;
    case IC_SWAP_U16 :
    ICSwapRV(tmpi, 2, rip2);
    break;
    case IC_SWAP_U32 :
    ICSwapRV(tmpi, 4, rip2);
    break;
    case IC_SWAP_I64 :
    ICSwapRV(tmpi, 8, rip2);
    break;
    /* Special Instructions - x86 Specific (adapt or remove) */
    case IC_RDTSC :
    // Read cycle counter (RISC-V CSR)
    // CSRR a0, cycle (0xC00)
    RVEmitI(tmpi, RV_OP_SYSTEM, RV_REG_A0, 0x2, RV_REG_ZERO, 0xC00);
    if (tmpi->res.type & MDF_REG && tmpi->res.reg != RV_REG_A0) {
      RVMv(tmpi, tmpi->res.reg, RV_REG_A0);
    } else if (!(tmpi->res.type & MDF_REG)) {
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_A0, 0, rip2);
    }
    break;
    case IC_CLFLUSH :
    // Cache flush - use FENCE instruction
    // FENCE iorw, iorw (full memory fence)
    RVEmitI(tmpi, RV_OP_SYSTEM, RV_REG_ZERO, 0, RV_REG_ZERO, 0x0FF);
    break;
    case IC_INVLPG :
    // Invalidate TLB - supervisor mode instruction
    // SFENCE.VMA (requires privilege)
    RVEmitR(tmpi, RV_OP_SYSTEM, RV_REG_ZERO, 0, RV_REG_ZERO, RV_REG_ZERO, 0x09);
    break;
    /* Port I/O - Not available on RISC-V */
    case IC_IN_U8 :
    case IC_IN_U16 :
    case IC_IN_U32 :
    case IC_OUT_U8 :
    case IC_OUT_U16 :
    case IC_OUT_U32 :
    // RISC-V uses memory-mapped I/O
    // These should be replaced with MMIO loads/stores
    // For now, generate warning
    PrintWarn("Port I/O not supported on RISC-V (use MMIO)\n");
    break;
    /* Fs()/Gs() _intern — load Compiler Fs/Gs slot (not x86 segment regs). */
    case IC_FS :
    RVEmitFsGs(cc, tmpi, buf, rip2, FALSE, FALSE);
    break;
    case IC_GS :
    RVEmitFsGs(cc, tmpi, buf, rip2, TRUE, FALSE);
    break;
    case IC_MOV_FS :
    RVEmitFsGs(cc, tmpi, buf, rip2, FALSE, TRUE);
    break;
    case IC_MOV_GS :
    RVEmitFsGs(cc, tmpi, buf, rip2, TRUE, TRUE);
    break;
    /* Register Access - Direct operations */
    case IC_GET_RAX :
    // RAX is actually a0 - should already be there
    if (tmpi->res.type & MDF_REG && tmpi->res.reg != RV_REG_A0) {
      RVMv(tmpi, tmpi->res.reg, RV_REG_A0);
    }
    break;
    case IC_SET_RAX :
    if (tmpi->arg1.type & MDF_REG && tmpi->arg1.reg != RV_REG_A0) {
      RVMv(tmpi, RV_REG_A0, tmpi->arg1.reg);
    } else if (!(tmpi->arg1.type & MDF_REG)) {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_A0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    }
    break;
    case IC_GET_RBP :
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_FP, 0, rip2);
    break;
    case IC_SET_RBP :
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_FP, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_GET_RSP :
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_SP, 0, rip2);
    break;
    case IC_SET_RSP :
    ICMov(tmpi, MDF_REG + RT_I64, RV_REG_SP, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_RBP :
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_FP, 0, rip2);
    break;
    case IC_REG :
    // Generic register access
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, tmpi->arg1.reg, 0, rip2);
    break;
    /* Assignment Operations */
    case IC_AND_EQU :
    ICAndEqu(tmpi, rip2);
    break;
    case IC_OR_EQU :
    ICOrEqu(tmpi, rip2);
    break;
    case IC_XOR_EQU :
    ICXorEqu(tmpi, rip2);
    break;
    case IC_ADD_EQU : ICArithEqu(tmpi, 0, rip2); break;
    case IC_SUB_EQU : ICArithEqu(tmpi, 1, rip2); break;
    case IC_MUL_EQU : ICArithEqu(tmpi, 2, rip2); break;
    case IC_DIV_EQU : ICArithEqu(tmpi, 3, rip2); break;
    case IC_MOD_EQU : ICArithEqu(tmpi, 4, rip2); break;
    case IC_SHL_EQU : ICArithEqu(tmpi, 5, rip2); break;
    case IC_SHR_EQU : ICArithEqu(tmpi, 6, rip2); break;
    case IC_ASSIGN :
    /* OptPass4 folds AOT ABS→BY_VAL+RIP; ICMov RIP is PC-rel store. */
    ICAssign(tmpi, rip2);
    /* br: which ICAssign path (must match BackA_RV). */
    if (tmpi->ic_flags & ICF_BY_VAL && !(tmpi->arg1.type & MDF_STK)) {
      if (tmpi->arg1.type & MDF_REG && tmpi->arg1_type_pointed_to && tmpi->arg1_type_pointed_to < RT_I64)
        ICIdentEmitDump(cc, tmpi, 1);
      else
        ICIdentEmitDump(cc, tmpi, 2);
    } else if (tmpi->arg1.type & MDF_REG)
      ICIdentEmitDump(cc, tmpi, 3);
    else
      ICIdentEmitDump(cc, tmpi, 4);
    break;
    case IC_ASSIGN_PP :
    ICAssignPostIncDec(tmpi, 1, rip2);
    break;
    case IC_ASSIGN_MM :
    ICAssignPostIncDec(tmpi, -1, rip2);
    break;
    /* Increment/Decrement with Dereference */
    case IC_DEREF :
    // Dereference pointer (arg1 holds address in a reg after Pass6).
    // Stage the load type: inline `MDF_DISP + tmpi-><member>` in an ICMov arg
    // is scaled as pointer arithmetic on tmpi by host AOT (see ICPostIncDec).
    tdrf = MDF_DISP + tmpi->arg1_type_pointed_to;
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tdrf, tmpi->arg1.reg, 0, rip2);
    break;
    case IC_DEREF_PP :
    ICDerefPostIncDec(tmpi, 1, rip2);
    break;
    case IC_DEREF_MM :
    ICDerefPostIncDec(tmpi, -1, rip2);
    break;
    case IC_PP_ :
    ICPreIncDec(tmpi, 1, rip2);
    break;
    case IC_MM_ :
    ICPreIncDec(tmpi, -1, rip2);
    break;
    case IC__PP :
    ICPostIncDec(tmpi, 1, rip2);
    break;
    case IC__MM :
    ICPostIncDec(tmpi, -1, rip2);
    break;
    /* Immediates */
    case IC_IMM_I64 :
    // Call-arg PUSH_RES leaves res=MDF_STK; res.reg is often 0 (x0) — RVLi x0 is a
    // no-op, so ICMov(STK←x0) pushed 0 and RVHCAdd1(40) saw a0=0. Materialize like STR_CONST.
    if (tmpi->res.type & MDF_STK) {
      RVLi(tmpi, RV_REG_A0, tmpi->ic_data);
      RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -8);
      RVSd(tmpi, RV_REG_A0, RV_REG_SP, 0);
    } else if (tmpi->res.type & MDF_REG) {
      RVLi(tmpi, tmpi->res.reg, tmpi->ic_data);
    } else {
      RVLi(tmpi, RV_REG_T0, tmpi->ic_data);
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip2);
    }
    break;
    case IC_IMM_F64 :
    // F64 values travel as raw bits in integer regs / stack slots (x86 RAX convention).
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_IMM + RT_I64, 0, tmpi->ic_data, rip2);
    break;
    case IC_STR_CONST :
    case IC_GET_LABEL :
    /* PC-relative la to misc string/label at end of fun (misc epilogue).
       * Match host AOT + x86 OptPass789A: lb->addr is fun-local; clear
       * ICF_CODE_FINAL while unresolved so later passes re-emit.
       * Always materialize into a0 (host STR_CONST / call ABI), then
       * copy to res.reg or push — call-arg path must leave a usable a0. */
    lb = tmpi->ic_data(CCodeMisc *);
    if (!lb || lb->addr == INVALID_PTR) {
      offset = 0;
      tmpi->ic_flags &= ~ICF_CODE_FINAL;
    } else
      offset = lb->addr - rip - tmpi->ic_cnt;
    RVAuipc(tmpi, RV_REG_A0, (offset + 0x800) >> 12 & 0xFFFFF);
    RVAddi(tmpi, RV_REG_A0, RV_REG_A0, offset << 52 >> 52);
    if (tmpi->res.type & MDF_REG && tmpi->res.reg != RV_REG_A0)
      RVMv(tmpi, tmpi->res.reg, RV_REG_A0);
    if (tmpi->res.type & MDF_STK) {
      /* Call-arg push: avoid ICMov(STK) path that hung guest Cmp of FileWrite("..."). */
      RVAddi(tmpi, RV_REG_SP, RV_REG_SP, -8);
      RVSd(tmpi, RV_REG_A0, RV_REG_SP, 0);
    } else if (!(tmpi->res.type & MDF_REG))
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_A0, 0, rip2);
    break;
    case IC_ABS_ADDR :
    /* Guest AOT: ic_data is data_addr_rip. RVLi embeds unpatchable imm.
     * GOT via RVEmitAbsAddr (no mid-case locals). */
    if (tmpi->res.type & MDF_REG)
      RVEmitAbsAddr(cc, tmpi, tmpi->res.reg, tmpi->ic_data, buf, rip2);
    else {
      RVEmitAbsAddr(cc, tmpi, RV_REG_T0, tmpi->ic_data, buf, rip2);
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip2);
    }
    break;
    case IC_ADDR_IMPORT :
    case IC_HEAP_GLBL :
    if (tmpi->res.type & MDF_REG)
      RVLi(tmpi, tmpi->res.reg, tmpi->ic_data);
    else {
      RVLi(tmpi, RV_REG_T0, tmpi->ic_data);
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_T0, 0, rip2);
    }
    break;
    /* String Operations */
    case IC_STRLEN :
    // Calculate string length
    // Load string pointer
    if (tmpi->arg1.type & MDF_REG) {
      RVMv(tmpi, RV_REG_T0, tmpi->arg1.reg);
    } else {
      ICMov(tmpi, MDF_REG + RT_I64, RV_REG_T0, 0, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
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
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_A0, 0, rip2);
    }
    break;
    /* Label */
    case IC_LABEL :
    lb = tmpi->ic_data;
    lb->addr = rip;
    break;
    case IC_CALL_START :
    /* Mid-function (CALL_IMPORT etc.): guest eval-SP is often junk while FP
     * from ENTER is valid — rebuild SP below frame + ENTER local PushRegs so
     * arg pushes do not overwrite saved s-regs (Count→store then FileWrite).
     * Top-level ExePutS expression JIT has no ENTER; FP is host Call()'s s0
     * (unreliable with -fomit-frame-pointer). Leave SP as Call() set it —
     * otherwise SP=FP-16 corrupts the return stack and MakeOSProbe hangs. */
    if (cc->htc.fun) {
      I64 fsz = 0, alloc = 0, local_push = 0, jbit = 0;
      alloc = cc->htc.fun->size;
      if (alloc < 0)
        alloc = -alloc;
      if (alloc & 15)
        alloc = alloc + 16 - (alloc & 15);
      fsz = 16 + alloc;
      while (jbit < 32) {
        if (cc->htc.fun->used_reg_mask & (REGG_LOCAL_VARS | REGG_LOCAL_NON_PTR_VARS) & (1 << jbit))
          local_push += 8;
        jbit++;
      }
      fsz += local_push;
      if (-fsz >= -2048 && -fsz <= 2047)
        RVAddi(tmpi, RV_REG_SP, RV_REG_FP, -fsz);
      else {
        RVLi(tmpi, RV_REG_T6, -fsz);
        RVAdd(tmpi, RV_REG_SP, RV_REG_FP, RV_REG_T6);
      }
    }
    ICPushRegs(tmpi, tmpi->ic_data);
    break;
    case IC_CALL_END :
    ICPopRegs(tmpi, tmpi->ic_data);
    if (tmpi->res.type.mode)
      ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, MDF_REG + RT_I64, RV_REG_A0, 0, rip2);
    break;
    case IC_CALL_END2 :
    case IC_END_EXP :
    case IC_END :
    break;
    /* Assembly Block */
    case IC_ASM :
    // Handled by the emit loop below (needs `buf`/`rip` to relocate and fix up), not here.
    // The old code read ic_data as a byte pointer and ic_cnt as a length: ic_data is a
    // CAOT *, the bytes live at ->buf with length ->aot_U8s, and a block longer than
    // IC_BODY_SIZE cannot go through ic_body at all. `asm{}` in the REPL emitted garbage
    // and every block ended up jumping to 0.
    break;
    case IC_HOLYC_TYPECAST :
    // Stock OptPass789A: a cast that survived the passes is a typed move.
    ICMov(tmpi, tmpi->res.type, tmpi->res.reg, tmpi->res.disp, tmpi->arg1.type, tmpi->arg1.reg, tmpi->arg1.disp, rip2);
    break;
    case IC_BR_BT :
    ICBrBitOpsRV(tmpi, tmpi->ic_data, 0, TRUE, rip, rip2);
    break;
    case IC_BR_BTS :
    ICBrBitOpsRV(tmpi, tmpi->ic_data, 1, TRUE, rip, rip2);
    break;
    case IC_BR_BTR :
    ICBrBitOpsRV(tmpi, tmpi->ic_data, 2, TRUE, rip, rip2);
    break;
    case IC_BR_BTC :
    ICBrBitOpsRV(tmpi, tmpi->ic_data, 3, TRUE, rip, rip2);
    break;
    case IC_BR_NOT_BT :
    ICBrBitOpsRV(tmpi, tmpi->ic_data, 0, FALSE, rip, rip2);
    break;
    case IC_BR_NOT_BTS :
    ICBrBitOpsRV(tmpi, tmpi->ic_data, 1, FALSE, rip, rip2);
    break;
    case IC_BR_NOT_BTR :
    ICBrBitOpsRV(tmpi, tmpi->ic_data, 2, FALSE, rip, rip2);
    break;
    case IC_BR_NOT_BTC :
    ICBrBitOpsRV(tmpi, tmpi->ic_data, 3, FALSE, rip, rip2);
    break;
    case IC_BR_MM_ZERO :
    ICBrMMRV(tmpi, tmpi->ic_data, TRUE, rip, rip2);
    break;
    case IC_BR_MM_NOT_ZERO :
    ICBrMMRV(tmpi, tmpi->ic_data, FALSE, rip, rip2);
    break;
    case IC_TOUPPER :
    ICToUpperRV(tmpi, rip2);
    break;
    case IC_QUE_INIT :
    ICQueInitRV(tmpi, rip2);
    break;
    case IC_QUE_INS :
    ICQueInsRV(tmpi, FALSE, rip2);
    break;
    case IC_QUE_INS_REV :
    ICQueInsRV(tmpi, TRUE, rip2);
    break;
    case IC_QUE_REM :
    ICQueRemRV(tmpi, rip2);
    break;
    case IC_MOD_U64 :
    ICModU64RV(tmpi, rip2);
    break;
    case IC_SQR :
    ICFSqr(tmpi, rip2);
    break;
    case IC_SQR_I64 :
    case IC_SQR_U64 :
    ICSqrIntRV(tmpi, rip2);
    break;
    case IC_POWER :
    ICFPow(tmpi, rip2);
    break;
    default:
    PrintWarn("IC opcode %d (%s) not implemented for RISC-V\n", code, intermediate_code_table[code].name);
    RVNop(tmpi);
    // Emit NOP as placeholder
    break;
  }
  *_rip2 = rip + tmpi->ic_cnt;
}

I64 OptPass789A(CCmpCtrl *cc, COptReg *reg_offsets, U8 *buf, CDbgInfo **_dbg)
{
  /* cc->pass 7..9: size; pass 10: emit into buf. */
  CIntermediateCode *tmpi, *tmpi_next;
  CCodeMisc *cm;
  CAOT *tmpaot_asm;
  I64 rip = 0, rip2, i, guard = 0, misc_guard = 0;
  U8 *uart = 0x10000000, *p;
  if (_dbg)
    *_dbg = NULL;
  tmpi = cc->coc.coc_head.next;
  while (tmpi->ic_code) {
    if (++guard > 100000) {
      *uart = 'O';
      *uart = 'P';
      *uart = '!';
      *uart = '\n';
      break;
    }
    tmpi_next = tmpi->next;
    /* Always re-emit (RV placeholders fixed-size); still mark FINAL like x86. */
    tmpi->ic_flags = tmpi->ic_flags & ~(ICF_PREV_DELETED | ICF_DONT_RESTORE) | ICF_CODE_FINAL;
    /* Inline asm: relocate the assembled blob straight into buf and fix up its labels,
     * exactly as stock OptPass789A does. It cannot go through ic_body — a block may be
     * longer than IC_BODY_SIZE, which is why the size guard below already excludes it. */
    if (tmpi->ic_code == IC_ASM) {
      tmpaot_asm = tmpi->ic_data(CAOT *);
      tmpi->ic_cnt = 0;
      if (tmpaot_asm && tmpaot_asm->aot_U8s > 0) {
        tmpi->ic_cnt = tmpaot_asm->aot_U8s;
        if (buf) {
          MemCpy(buf + rip, tmpaot_asm->buf, tmpaot_asm->aot_U8s);
          Free(tmpaot_asm->buf);
          tmpaot_asm->buf = buf;
          tmpaot_asm->rip = rip;
          tmpaot_asm->rip2 = rip + tmpi->ic_cnt;
          if (cc->flags & CCF_AOT_COMPILE)
            CmpFixUpAOTAsm(cc, tmpaot_asm);
          else
            CmpFixUpJITAsm(cc, tmpaot_asm);
        }
      }
      rip += tmpi->ic_cnt;
      tmpi = tmpi_next;
      continue;
    }
    // PassTrace(…) (stock OptPass789A): dump each IC as it is emitted.
    if (tmpi->ic_flags & ICF_PASS_TRACE && (Bt(&cc->saved_pass_trace, cc->pass) || Bt(&cc->saved_pass_trace, 9)))
      ICPut(cc, tmpi);
    ICToRISCV(cc, tmpi, buf, rip, &rip2, reg_offsets);
    if (tmpi->ic_cnt >= IC_BODY_SIZE && tmpi->ic_code != IC_ASM) {
      *uart = 'B';
      *uart = 'Z';
      *uart = '\n';
      throw('Compiler');
    }
    if (buf) {
      for (i = 0; i < tmpi->ic_cnt; i++)
        buf[rip + i] = tmpi->ic_body[i];
    }
    rip = rip2;
    tmpi = tmpi_next;
  }
  /* Append string / float / jmp-table misc like x86 OptPass789A. */
  cm = cc->coc.coc_next_misc;
  while (cm != &cc->coc.coc_next_misc) {
    if (++misc_guard > 10000) {
      *uart = 'M';
      *uart = '!';
      *uart = '\n';
      break;
    }
    if (cm->type == CMT_STR_CONST) {
      cm->addr = rip;
      if (buf && cm->str && cm->st_len > 0 && cm->st_len < 0x10000)
        MemCpy(buf + rip, cm->str, cm->st_len);
      if (cm->st_len > 0 && cm->st_len < 0x10000)
        rip += cm->st_len;
    } else if (cm->type == CMT_FLOAT_CONSTS) {
      cm->addr = rip;
      if (buf && cm->float_consts)
        MemCpy(buf + rip, cm->float_consts, cm->num_consts *sizeof(F64));
      rip += cm->num_consts *sizeof(F64);
    } else if (cm->type == CMT_JMP_TABLE) {
      cm->addr = rip;
      if (buf && cm->jmp_table) {
        p = buf + rip;
        for (i = 0; i < cm->range; i++) {
          *p(I64 *) = cm->jmp_table[i]->addr;
          p += sizeof(I64);
        }
      }
      rip += cm->range *sizeof(I64);
    }
    cm = cm->next;
  }
  return rip;
}

I64 *OptPassRISCV(CCmpCtrl *cc, I64 *_code_size, U8 **_dbg_info, I64 *_type)
{
  I64 sz = 0;
  U8 *code;
  no_warn _dbg_info;
  sz = OptPass789A(cc, NULL, NULL, NULL);
  if (_code_size)
    *_code_size = sz;
  code = MAlloc(sz);
  OptPass789A(cc, NULL, code, NULL);
  if (_type)
    *_type = RT_I64;
  return code;
}
#help_index ""
