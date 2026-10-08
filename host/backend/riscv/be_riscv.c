/* host/backend/riscv/be_riscv.c — the RISC-V code-generation backend (ISA-SPECIFIC).
 *
 * The extraction target for milestone M4: the RISC-V instruction encoders, the branch/call
 * primitives, prologue/epilogue, and immediate materialization move here from host/compiler.c
 * behind the neutral TargetBackend interface, leaving the IC walker in compiler.c arch-neutral.
 *
 * For now (M4b) this TU holds only the RISC-V register-role mapping as data — the first concrete
 * piece of the backend. The neutral walker consumes it at M4e; it is unused (and does not affect
 * emitted code) until then. A non-static definition so an unused const doesn't warn.
 */
#include "be_riscv.h"   /* brings holyc_compiler.h (types) + regs.h */

/* --- Instruction-field decode predicates/extractors (moved from compiler.c, M4c) --- */
I64 RvImmI(U32 w) { return (I64)(I32)w >> 20; }
I64 RvImmS(U32 w) { I64 x=((w>>7)&31)|(((w>>25)&127)<<5); return x&0x800 ? x|~0xFFF : x; }
int RvIsAddi(U32 w, int rd, int rs1, int imm) {
  return (w & 0x7F) == 0x13 && ((w >> 12) & 7) == 0 && (int)((w >> 7) & 0x1F) == rd &&
         (int)((w >> 15) & 0x1F) == rs1 && (((I32)w) >> 20) == imm;
}
/* sd rs2,0(sp) — eval-stack push store (sw on rv32: doubleword = g_wd3). */
int RvIsSdSp0(U32 w, int *rs2) {
  if ((w & 0x7F) != 0x23 || ((w >> 12) & 7) != (U32)g_wd3 || ((w >> 15) & 0x1F) != 2) return 0;
  if ((int)(((w >> 7) & 0x1F) | (((w >> 25) & 0x7F) << 5)) != 0) return 0;
  if (rs2) *rs2 = (int)((w >> 20) & 0x1F);
  return 1;
}
/* mv rd,rs ≡ addi rd,rs,0 */
int RvIsMv(U32 w, int *rd, int *rs) {
  if ((w & 0x7F) != 0x13 || ((w >> 12) & 7) != 0 || (((I32)w) >> 20) != 0) return 0;
  if (rd) *rd = (int)((w >> 7) & 0x1F);
  if (rs) *rs = (int)((w >> 15) & 0x1F);
  return 1;
}

/* --- Typed load/store + AMO encoders (moved from compiler.c, M4c). Width of the doubleword
 *     case is g_wd3 (ld/sd on rv64, lw/sw on rv32); narrower lb/lh/lw are width-correct both. --- */
/* IC_DEREF / IncDec: load *rs1 into rd; width from arg1_type_pointed_to (U32 → lwu, not ld). */
U32 LoadRdFromRs1(U8 pointed_to, U8 rd, U8 rs1) {
  switch (pointed_to) {
  case RT_I8:  return 0x03 | (rd << 7) | (0 << 12) | (rs1 << 15); /* lb  */
  case RT_U8:  return 0x03 | (rd << 7) | (4 << 12) | (rs1 << 15); /* lbu */
  case RT_I16: return 0x03 | (rd << 7) | (1 << 12) | (rs1 << 15); /* lh  */
  case RT_U16: return 0x03 | (rd << 7) | (5 << 12) | (rs1 << 15); /* lhu */
  case RT_I32: return 0x03 | (rd << 7) | (2 << 12) | (rs1 << 15); /* lw  */
  case RT_U32: return 0x03 | (rd << 7) | (6 << 12) | (rs1 << 15); /* lwu */
  default:     return 0x03 | (rd << 7) | (g_wd3<<12) | (rs1 << 15); /* ld */
  }
}
U32 DerefLoadFromRs1(U8 pointed_to, U8 rs1) { return LoadRdFromRs1(pointed_to, RV_A0, rs1); }
U32 DerefLoadFromRs1Off(U8 p, U8 rs1, I64 off) { return DerefLoadFromRs1(p,rs1)|(((U32)off&0xFFF)<<20); }
/* Typed store of rs2 through rs1 (mirror of LoadRdFromRs1). */
U32 StoreRs2ToRs1(U8 pointed_to, U8 rs1, U8 rs2) {
  U32 f3;
  switch (pointed_to) {
  case RT_I8: case RT_U8:   f3 = 0; break; /* sb */
  case RT_I16: case RT_U16: f3 = 1; break; /* sh */
  case RT_I32: case RT_U32: f3 = 2; break; /* sw */
  default:                  f3 = g_wd3; break; /* sd */
  }
  return 0x23 | (f3 << 12) | (rs1 << 15) | (rs2 << 20);
}
U32 StoreA0ToRs1(U8 pointed_to, U8 rs1) { return StoreRs2ToRs1(pointed_to, rs1, RV_A0); }
U32 StoreA0ToRs1Off(U8 p, U8 rs1, I64 off) { return StoreA0ToRs1(p,rs1)|(((U32)off&31)<<7)|(((U32)off&0xFE0)<<20); }
U32 StoreZeroToRs1(U8 pointed_to, U8 rs1) { return StoreRs2ToRs1(pointed_to, rs1, RV_ZERO); /* rs2 = x0 */ }
/* A-ext AMO word: opcode 0x2F; aqrl is {aq,rl} in bits [26:25]. */
U32 RvAmo(U32 f5, U32 aqrl, U32 f3, int rd, int rs1, int rs2) {
  return 0x2Fu | ((U32)rd << 7) | (f3 << 12) | ((U32)rs1 << 15) | ((U32)rs2 << 20) |
         (aqrl << 25) | (f5 << 27);
}

/* --- O1 BB-local frame-slot forwarding (moved from compiler.c, M4c): tracks which register
 *     currently holds each s0-relative frame slot, to elide reloads (HOLYC_O1_MODE>=4). RISC-V-
 *     specific (keys on s0-relative offsets). g_o1_slot_reg is extern (RVU32 reads it directly). --- */
static I64 g_o1_slot_off[32];
static int g_o1_slot_n;
int g_o1_slot_reg[32];
void O1SlotClear(void) { g_o1_slot_n = 0; }
int O1SlotFind(I64 off) { for (int i=0;i<g_o1_slot_n;i++) if (g_o1_slot_off[i]==off) return i; return -1; }
void O1SlotForgetReg(int reg) { for (int i=0;i<g_o1_slot_n;) if (g_o1_slot_reg[i]==reg) { g_o1_slot_off[i]=g_o1_slot_off[--g_o1_slot_n]; g_o1_slot_reg[i]=g_o1_slot_reg[g_o1_slot_n]; } else i++; }
void O1SlotSet(I64 off, int reg) { int i=O1SlotFind(off); if (i<0 && g_o1_slot_n<32) i=g_o1_slot_n++; if (i>=0) { g_o1_slot_off[i]=off; g_o1_slot_reg[i]=reg; } }

/* RISC-V (LP64D) role → physical register. Roles with no RISC-V register are -1. */
const RegFile rv_regfile = {
  .phys = {
    [ROLE_ACC]  = RV_A0,                               /* accumulator / eval-stack top        */
    [ROLE_SCR0] = RV_T0, [ROLE_SCR1] = RV_T1, [ROLE_SCR2] = RV_T2,
    [ROLE_ARG0] = RV_A0, [ROLE_ARG1] = RV_A1, [ROLE_ARG2] = RV_A2, [ROLE_ARG3] = RV_A3,
    [ROLE_ARG4] = RV_A4, [ROLE_ARG5] = RV_A5, [ROLE_ARG6] = RV_A6, [ROLE_ARG7] = RV_A7,
    [ROLE_SP]   = RV_SP, [ROLE_FP]  = RV_S0, [ROLE_LR] = RV_RA,
    [ROLE_RET0] = RV_A0, [ROLE_RET1] = RV_A1,
    [ROLE_ZERO] = RV_ZERO,                             /* RISC-V has a hardwired-zero (x0)     */
    [ROLE_FSCR0] = RV_FA0, [ROLE_FSCR1] = RV_FA1,
  },
};
