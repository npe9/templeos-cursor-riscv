// RVComplete.HC — Tab completion over everything the REPL actually knows.
//
// The asm REPL completes registers and mnemonics from a fixed list, which is right for a
// stepper. At the HolyC prompt the useful vocabulary is whatever is in the hash table: every
// function the image exports, every global, the register labels (_A0, _PC…), the debugger
// commands — and it changes as you define things, so a fixed list would be wrong the moment you
// typed a function of your own.
//
// Behaviour follows what a shell does, because that is what fingers expect:
//   one match        complete it
//   several matches  extend to the longest common prefix, and if that adds nothing, list them
//   none             leave the line alone
#ifndef RV_COMPLETE_HC
#define RV_COMPLETE_HC
#help_index "Term"
#define RVCOMP_LIST_MAX 24
// Walk one hash table for entries starting with `word`. Returns the number of matches, fills
// `out` with the longest common prefix of them, and optionally prints them.
I64 RVCompScan(CHashTable *table, U8 *word, I64 n, U8 *out, I64 max, I64 list)
{
  CHashSrcSym *e;
  U8 *nm;
  I64 i, hits = 0, k, listed = 0;
  if (!table)
    return 0;
  i = 0;
  while (i <= table->mask) {
    e = table->body[i];
    while (e) {
      nm = e->str;
      if (nm && !MemCmp(nm, word, n) && StrLen(nm) >= n) {
        hits++;
        if (hits == 1) {
          StrCpy(out, nm);
          if (StrLen(out) >= max)
            out[max - 1] = 0;
        } else {
          // keep only the part every match agrees on
          k = 0;
          while (out[k] && nm[k] && out[k] == nm[k])
            k++;
          out[k] = 0;
        }
        if (list && listed < RVCOMP_LIST_MAX) {
          "  %s", nm;
          listed++;
          if (listed % 6 == 0)
            "\n";
        }
      }
      e = e->next;
    }
    i++;
  }
  if (list && listed && listed % 6)
    "\n";
  return hits;
}
// RVHashComplete -- Tab hook for the HolyC prompt
// NAME
//   RVHashComplete - complete from the compiler's hash table
// SYNOPSIS
//   RVLineEdComplete(&RVHashComplete);
// DESCRIPTION
//   Completes against every symbol the REPL can resolve, including ones defined a moment ago.
//   Returns 1 when it filled `out`, 2 when it printed a list (the editor just redraws), 0 when
//   there was nothing to say.
// SEE ALSO
//   RVLineEd  AsmRepl
I64 RVHashComplete(U8 *word, U8 *out, I64 max)
{
  U8 best[160];
  I64 n, hits;
  if (!word || !*word || !Fs || !Fs->hash_table)
    return 0;
  n = StrLen(word);
  best[0] = 0;
  hits = RVCompScan(Fs->hash_table, word, n, best, 160, FALSE);
  if (!hits)
    return 0;
  if (StrLen(best) > n) {
    // the common prefix is longer than what was typed: take it, however many matched
    StrCpy(out, best);
    if (StrLen(out) >= max)
      out[max - 1] = 0;
    return 1;
  }
  // nothing more to add — show what the choices are instead of beeping
  "\n";
  RVCompScan(Fs->hash_table, word, n, best, 160, TRUE);
  return 2;
}
#endif
