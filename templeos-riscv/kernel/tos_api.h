/*
 * TempleOS/RISC-V — public kernel API block (Adam / father-task analogue).
 * Laid out at TOS_API_VMA by the linker; HolyC guests use the same offsets.
 */
#ifndef TOS_API_H
#define TOS_API_H

#include <stdint.h>

#define TOS_API_VMA   0x80300000UL
#define TOS_API_MAGIC 0x41534f54UL /* 'TOSA' little-endian */

struct TosApi {
  uint32_t magic;
  uint32_t version;
  void (*putchar)(int c);
  int (*getchar)(void);
  void (*yield)(void);
};

_Static_assert(sizeof(struct TosApi) == 32, "TosApi layout must match HolyC guest");

#endif
