/* host/backend/riscv/regs.h — RISC-V register numbers (ISA-SPECIFIC).
 *
 * Lives under host/backend/riscv/ (per host/backend/README.md): these are RISC-V ABI register
 * NUMBERS, used to field-pack opcodes in the RISC-V backend. They must NOT appear in the
 * architecture-neutral files in host/backend/ — the neutral code addresses registers by ROLE
 * (RegRole) and lets each backend's RegFile resolve the role to its own physical number.
 */
#ifndef HOST_BACKEND_RISCV_REGS_H
#define HOST_BACKEND_RISCV_REGS_H
#include "../target_backend.h"   /* RegFile / RegRole */

/* Integer registers (x0..x31 ABI subset the backend uses). */
#define RV_ZERO 0
#define RV_RA   1
#define RV_SP   2
#define RV_T0   5
#define RV_T1   6
#define RV_T2   7
#define RV_S0   8
#define RV_S1   9
#define RV_A0   10
#define RV_A1   11
#define RV_A2   12
#define RV_A3   13
#define RV_A4   14
#define RV_A5   15
#define RV_A6   16
#define RV_A7   17
#define RV_S2   18
#define RV_S3   19
#define RV_S4   20
#define RV_S5   21
#define RV_S6   22
#define RV_S7   23
#define RV_S8   24

/* Float registers (RV64D). F64 values ride as raw bits in integer regs / eval-stack slots;
 * these name the FP scratch pair the arithmetic bridges (fmv.d.x) hop through. */
#define RV_FA0 10
#define RV_FA1 11

/* The RISC-V ABI expressed as role→physical data (consumed by the neutral walker at M4e).
 * Defined in host/backend/riscv/be_riscv.c. */
extern const RegFile rv_regfile;

#endif /* HOST_BACKEND_RISCV_REGS_H */

