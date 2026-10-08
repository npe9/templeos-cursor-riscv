/* host/backend/target_backend.h — portable code-generation backend interface (NEUTRAL).
 *
 * The architecture-neutral contract between the IC walker and a per-ISA backend (see
 * host/backend/README.md). This header defines ABSTRACT concepts only — register ROLES, the
 * register file mapping roles to an ISA's physical numbers, and (added as the extraction
 * proceeds) the `Em` context and the `TargetBackend` primitive vtable. It must name no ISA's
 * opcodes or register numbers; each backend supplies those.
 *
 * Populated incrementally by milestone M4: M4b = RegRole/RegFile (here) + the RISC-V RegFile
 * (host/backend/riscv/be_riscv.c); M4c = the `TargetBackend` vtable; M4d = the `Em` context
 * (carrying all per-compile state so the compiler is reentrant — required for the concurrent/
 * heterogeneous guest JIT); M4e = the neutral walker addresses registers by role.
 */
#ifndef HOST_BACKEND_TARGET_BACKEND_H
#define HOST_BACKEND_TARGET_BACKEND_H
#include <stdint.h>

/* Semantic register roles the neutral codegen reasons about. A backend's RegFile maps each to
 * a physical register for its ISA (or marks it absent). The eval-stack machine keeps the
 * working value in ROLE_ACC; ROLE_SCR* are scratch; ROLE_ARG* / ROLE_RET* are the call ABI;
 * ROLE_ZERO is a hardwired-zero register where the ISA has one (RISC-V x0), else absent (x86/
 * ARM) and the neutral path must materialize a zero instead. */
typedef enum {
  ROLE_ACC = 0,                                  /* accumulator / top-of-eval-stack           */
  ROLE_SCR0, ROLE_SCR1, ROLE_SCR2,               /* scratch temporaries                        */
  ROLE_ARG0, ROLE_ARG1, ROLE_ARG2, ROLE_ARG3,    /* integer argument registers                 */
  ROLE_ARG4, ROLE_ARG5, ROLE_ARG6, ROLE_ARG7,
  ROLE_SP, ROLE_FP, ROLE_LR,                      /* stack pointer, frame pointer, link register */
  ROLE_RET0, ROLE_RET1,                           /* return-value register(s)                   */
  ROLE_ZERO,                                      /* hardwired-zero reg, or absent (phys == -1) */
  ROLE_FSCR0, ROLE_FSCR1,                         /* float scratch (soft-float bridge regs)     */
  ROLE_N
} RegRole;

/* Role → physical register number for one ISA. phys[role] == -1 means the ISA has no register
 * for that role (e.g. x86/ARM have no ROLE_ZERO; a 4-arg-register ABI leaves ARG4..7 == -1). */
typedef struct RegFile {
  int8_t phys[ROLE_N];
} RegFile;

/* Resolve a role to its physical register; -1 if the ISA lacks it (callers handle absence). */
static inline int regfile_phys(const RegFile *rf, RegRole role) {
  return (role >= 0 && role < ROLE_N) ? rf->phys[role] : -1;
}

#endif /* HOST_BACKEND_TARGET_BACKEND_H */
