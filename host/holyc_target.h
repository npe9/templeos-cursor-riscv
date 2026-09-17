/* holyc_target.h — code-generation target descriptor (multi-arch seam).
 *
 * The HolyC AOT backend emits RISC-V rv64 today. To retarget it (rv32, then
 * AArch64/ARM32 — bare-metal; see docs/MULTIARCH.md and templeos-riscv/RV32.md)
 * without forking host/compiler.c, the compiler carries ONE of these descriptors
 * (Compiler.tgt) and reads width/ABI facts from it instead of hardcoding rv64.
 *
 * Design (per plan): mostly DATA + a few op hooks, NOT a 93-entry vtable. rv64
 * stays the literal existing code under `if (tgt->xlen == 64)`, so any byte
 * regression bisects to a single branch. compiler.c reads xlen and sd_funct3
 * into module statics (g_xlen/g_wd3) per compile. rv32 emits the P0 subset
 * (32-bit values; wide I64 is later) — see `make rv32-uart-smoke`.
 */
#ifndef HOLYC_TARGET_H
#define HOLYC_TARGET_H

#include <stdint.h>

typedef enum {
  HOLYC_ARCH_RV64 = 0,
  HOLYC_ARCH_RV32 = 1,
  /* HOLYC_ARCH_AARCH64, HOLYC_ARCH_ARM32 — later */
} HolyArch;

typedef struct holyc_target {
  HolyArch    arch;
  const char *name;          /* "rv64", "rv32" — matches --target / HOLYC_ARCH */
  uint8_t     xlen;          /* 64 | 32 */
  uint8_t     ptr_width;     /* pointer size in bytes: 8 | 4. Drives pointer
                              * TypeSize — NOT I64, which stays 8 everywhere. */
  uint8_t     slot_size;     /* eval-stack / frame GPR slot bytes. FROZEN at 8 for
                              * both rv64 and rv32 so P1 wide-I64 stays additive. */
  uint8_t     stack_align;   /* stack alignment in bytes (16 both) */
  uint8_t     little_endian; /* 1 = LE (all current targets) */
  uint8_t     ld_funct3;     /* pointer/word LOAD funct3: rv64=3 (ld), rv32=2 (lw) */
  uint8_t     sd_funct3;     /* pointer/word STORE funct3: rv64=3 (sd), rv32=2 (sw) */

  /* Op hooks for forms that are irreducibly different per target (register-pair
   * wide-I64 on ILP32, etc.) land at RV32 P1 — NULL on rv64. Declared later so
   * the scaffolding PRs need not commit to a signature. */
} holyc_target;

extern const holyc_target holyc_target_rv64;
extern const holyc_target holyc_target_rv32;

#endif /* HOLYC_TARGET_H */
