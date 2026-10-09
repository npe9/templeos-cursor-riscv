/* host/backend/emit.h — portable code byte-stream (ARCHITECTURE-NEUTRAL).
 *
 * Lives directly in host/backend/ (per README.md) — no ISA knowledge. The one primitive every
 * backend emits through: append raw little-endian bytes and advance rip by the ACTUAL length, so
 * fixed-width ISAs (RISC-V, ARM, AArch64 — constant-size words) and variable-length ISAs (x86,
 * Thumb — 1..15 bytes) share the same writer. StreamRewind undoes buffered bytes on a peephole
 * cancel without any caller hardcoding a word size.
 *
 * Include after holyc_compiler.h (for U8/I64); it pulls that in itself so it is self-contained.
 */
#ifndef HOST_BACKEND_EMIT_H
#define HOST_BACKEND_EMIT_H
#include "holyc_compiler.h"   /* U8 / I64 (resolved via -Ihost) */

/* Append n raw bytes at *ptr (when buffering) and advance *rip by n. */
void emit_bytes(U8 *buf, U8 **ptr, I64 *rip, const U8 *p, int n);
/* Undo `bytes` of buffered emission (peephole cancel). */
void StreamRewind(U8 *buf, U8 **ptr, I64 *rip, int bytes);

#endif /* HOST_BACKEND_EMIT_H */
