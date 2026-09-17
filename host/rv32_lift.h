/* rv32_lift.h — RV32 backend: rewrite one virtual rv64 word into rv32 words (see rv32_lift.c). */
#ifndef RV32_LIFT_H
#define RV32_LIFT_H

#include <stdint.h>

typedef void (*Rv32EmitFn)(void *ctx, uint32_t word);

/* Call ABI: argument i (0-7) is a pair a_i (lo) : s(1+i) (hi). s1-s8 are free on rv32 (no
 * local promotion). The mode says which role a0-a7 play for the word being lifted. */
enum {
  RV32_ARG_SPILL = 1,   /* IC_ENTER `sd a_i, slot`: store a_i : s(1+i) */
  RV32_ARG_LOAD  = 2,   /* caller `ld a_i, slot`: load a_i : s(1+i) */
};
typedef struct {
  int     mode;          /* RV32_ARG_* or 0 */
  int64_t rip;           /* blob offset the lowering of `w` starts at */
  int64_t divmod_addr;   /* blob offset of the appended rv32_divmod helper (any value while sizing) */
} Rv32LiftEnv;
/* Emit the rv32 lowering of rv64 word `w` through `emit`; returns the word count. */
int Rv32Lift(uint32_t w, const Rv32LiftEnv *env, Rv32EmitFn emit, void *ctx);
/* The helper words (host/rv32_divmod.S) every rv32 blob carries after its code. */
const uint32_t *Rv32DivmodWords(int *count);
void Rv32LiftReset(void);   /* per compile: re-arm the one-shot "no lowering" warning */

#endif
