/* host/backend/relax.h — monotone-growth branch relaxation (ARCHITECTURE-NEUTRAL).
 *
 * Portable codegen core (see host/backend/README.md). Variable-length ISAs (x86, Thumb) and
 * long-branch ISAs (AArch64 B.cond beyond ±1 MiB) need a branch whose encoded size depends on
 * the distance to its target — which isn't known until every other size is fixed. This solves
 * that classic fixed-point: model the emitted stream as ordered fragments, assign offsets, grow
 * any branch that can't reach its label, and repeat until stable. Growth is MONOTONE (a branch's
 * size class only ever increases), so it always terminates — the oscillation that forced the
 * RISC-V backend's "always-2-word" policy cannot happen here.
 *
 * RISC-V (fixed-width) does not use this — its branches are all one size. The first consumers are
 * the AArch64 and x86 backends (milestones M6/M7), which build a RelaxFrag list during sizing,
 * call relax_run(), then emit each branch at its resolved size class.
 */
#ifndef HOST_BACKEND_RELAX_H
#define HOST_BACKEND_RELAX_H
#include <stdint.h>

enum { RELAX_FIXED, RELAX_LABEL, RELAX_BRANCH };

typedef struct RelaxFrag {
  uint8_t  type;        /* RELAX_FIXED | RELAX_LABEL | RELAX_BRANCH                        */
  uint8_t  kind;        /* BRANCH: backend-defined fixup kind (which encoding family)      */
  uint8_t  size_class;  /* BRANCH: current class — in: starting (usually 0); out: resolved */
  int32_t  label_id;    /* LABEL: this fragment's label id; BRANCH: its target label id    */
  int32_t  fixed_len;   /* FIXED: byte length (ignored otherwise)                          */
  int64_t  offset;      /* OUT: resolved byte offset of this fragment from the stream start */
} RelaxFrag;

/* Backend-supplied size/reach model. `disp` is (target label offset) − (branch's own offset);
 * the backend's `reaches` accounts for any end-of-instruction convention its ISA uses. */
typedef struct RelaxArch {
  int     (*branch_size)(uint8_t kind, uint8_t size_class); /* bytes a BRANCH emits at this class */
  uint8_t (*max_class)  (uint8_t kind);                     /* highest class index for this kind  */
  int     (*reaches)    (uint8_t kind, uint8_t size_class, int64_t disp); /* fits at this class?  */
} RelaxArch;

/* Resolve every fragment's `offset` and each BRANCH's final `size_class` to a fixed point.
 * Returns the pass count (>=1) on success, or -1 if a branch references a missing label or the
 * fixed point was not reached within the monotone-growth bound (a backend-model bug). */
int relax_run(RelaxFrag *frags, int n, const RelaxArch *arch);

#endif /* HOST_BACKEND_RELAX_H */
