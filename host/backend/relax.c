/* host/backend/relax.c — monotone-growth branch relaxation (ARCHITECTURE-NEUTRAL).
 * See relax.h. No ISA knowledge: all encoding facts come through RelaxArch. */
#include "relax.h"

/* Byte size of a fragment at its current state. */
static int frag_size(const RelaxFrag *f, const RelaxArch *a) {
  switch (f->type) {
    case RELAX_FIXED:  return f->fixed_len;
    case RELAX_LABEL:  return 0;
    case RELAX_BRANCH: return a->branch_size(f->kind, f->size_class);
    default:           return 0;
  }
}

/* Offset of the LABEL fragment with `id`, or INT64_MIN if none. O(n) scan — code units are
 * small and this runs a handful of passes; a backend with huge functions can index later. */
static int64_t label_offset(const RelaxFrag *frags, int n, int32_t id, int *found) {
  for (int i = 0; i < n; i++)
    if (frags[i].type == RELAX_LABEL && frags[i].label_id == id) { *found = 1; return frags[i].offset; }
  *found = 0;
  return 0;
}

int relax_run(RelaxFrag *frags, int n, const RelaxArch *arch) {
  if (n < 0 || !arch) return -1;

  /* Monotone-growth bound: each branch can grow at most max_class times; add one settle pass. */
  long bound = 1;
  for (int i = 0; i < n; i++)
    if (frags[i].type == RELAX_BRANCH) {
      if (frags[i].size_class > arch->max_class(frags[i].kind)) return -1; /* bad start class */
      bound += arch->max_class(frags[i].kind);
    }

  for (long pass = 0; pass <= bound + 1; pass++) {
    /* (1) assign offsets from the current size classes */
    int64_t off = 0;
    for (int i = 0; i < n; i++) { frags[i].offset = off; off += frag_size(&frags[i], arch); }

    /* (2) grow any branch that can no longer reach its target; growth only increases a class */
    int grew = 0;
    for (int i = 0; i < n; i++) {
      RelaxFrag *b = &frags[i];
      if (b->type != RELAX_BRANCH) continue;
      int found = 0;
      int64_t tgt = label_offset(frags, n, b->label_id, &found);
      if (!found) return -1;                     /* branch to a nonexistent label */
      int64_t disp = tgt - b->offset;
      uint8_t top = arch->max_class(b->kind);
      while (b->size_class < top && !arch->reaches(b->kind, b->size_class, disp)) {
        b->size_class++;
        grew = 1;
      }
    }
    if (!grew) return (int)(pass + 1);           /* converged */
  }
  return -1;                                     /* did not settle within the bound — model bug */
}
