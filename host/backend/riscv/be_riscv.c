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
