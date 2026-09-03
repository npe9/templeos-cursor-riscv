/* Extracted mirror of host/parser.c RvI (TryAssembleRiscV OP-IMM I-type).
 *
 *   static U32 RvI(U32 f3,int rd,int rs1,int imm){
 *     return 0x13u|(rd<<7)|(f3<<12)|(rs1<<15)|(((U32)imm&0xFFF)<<20);
 *   }
 *
 * Standalone for P0 differential check vs tests/asm/riscv_oracle.py::rv_i.
 * Optional -DRV_I_SEED_BUG flips opcode to R-type 0x33 (demo fail).
 */
#include <stdint.h>

#ifndef RV_I_OPCODE
#ifdef RV_I_SEED_BUG
#define RV_I_OPCODE 0x33u /* intentional wrong opcode for fail demo */
#else
#define RV_I_OPCODE 0x13u /* OP-IMM */
#endif
#endif

uint32_t RvI(uint32_t f3, int rd, int rs1, int imm) {
  return RV_I_OPCODE | ((uint32_t)rd << 7) | (f3 << 12) | ((uint32_t)rs1 << 15) |
         (((uint32_t)imm & 0xFFFu) << 20);
}
