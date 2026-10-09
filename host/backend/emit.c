/* host/backend/emit.c — portable code byte-stream (ARCHITECTURE-NEUTRAL). See emit.h. */
#include "backend/emit.h"

/* Append n raw bytes to the code stream and advance rip by the ACTUAL length. The arch-neutral
 * emission primitive: fixed-width backends write constant-size words through it; variable-length
 * backends write 1..15 bytes. Explicit little-endian — no host-endian or alignment assumption. */
void emit_bytes(U8 *buf, U8 **ptr, I64 *rip, const U8 *p, int n) {
  if (buf && ptr) { for (int i = 0; i < n; i++) (*ptr)[i] = p[i]; (*ptr) += n; }
  (*rip) += n;
}

/* Undo `bytes` of buffered emission (a peephole cancel). No caller hardcodes a word size. */
void StreamRewind(U8 *buf, U8 **ptr, I64 *rip, int bytes) {
  if (buf && ptr) *ptr -= bytes;
  (*rip) -= bytes;
}
