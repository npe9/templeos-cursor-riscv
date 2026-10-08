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
#include "regs.h"

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
