// A ZERO-PADDED **UNSIGNED** CONVERSION, WHICH NOTHING ELSE PINNED.
//
// e_strprint_hex.hc covers `%05d` (zero-pad + SIGNED) and `%5u` (space-pad + unsigned) and every
// zero-padded HEX form cFS uses. It does not cover zero-pad + unsigned decimal -- and that is
// exactly `%03u`, which sc_rtsrq.c uses **thirteen times** in its RTS event text ("RTS Number %03u
// Started"). check_formats reported the form as newly present and "implemented by StrPrintNV",
// which says the conversion is HANDLED and nothing about whether the width and the zero flag come
// out right.
//
// The gap would not have shown up for a while: both halves of the cFS differential agree until
// SC's exercise actually fires an RTS event, so a formatter that rendered `1` where C renders
// `001` would have been invisible until a transcript divergence hundreds of lines into a later
// commit. Pinning it here is three minutes against that.
//
// **EVERY EXPECTED VALUE WAS MEASURED WITH C's snprintf**, not reasoned from CfsStr.HC's padding
// code, and the five shapes are the ones SC really uses plus the two boundaries that break naive
// implementations: a width SHORTER than the number (must not truncate) and 4294967295.
//
//     RTS Number 001 Started
//     RTS Number 004 Started
//     [000][099][100]
//     [1234][4294967295]
//     Start RTS 007 Rejected: Status: 5
//     ATS A Execution Started
//     ATS Switched from A to B
//     Append ATS B command: 7 entries
//     [A][            (a NUL from %c of 0; strlen 4)
//     [  Z][Z]
//
// **THE EXPECTED FOLD IS CUMULATIVE OVER ALL TEN STRINGS, AND THE FIRST ATTEMPT WAS NOT.** When
// %c was added, the C reference program folded only the five NEW strings from zero while this
// case folds all ten in sequence -- so the case "failed" with a correct implementation, and the
// five individual %c strings had to be folded SEPARATELY to show that each one matched C exactly
// before the arithmetic was believed. The lesson is the plain one: a reference value has to be
// computed over the same inputs, in the same order, with the same starting accumulator, or it is
// a number about something else.
#include "/Kernel/Cfs/CfsStr.HC"
I64 StrLenX(U8 *s)
{
  I64 n = 0;
  while (s[n])
    n++;
  return n;
}
I64 Fold(I64 acc, U8 *s)
{
  I64 i = 0;
  while (s[i]) {
    acc = acc * 33 + s[i] * (i + 1);
    acc = acc & 0xFFFFFFFF;
    i++;
  }
  acc = acc * 31 + StrLenX(s);
  return acc & 0xFFFFFFFF;
}
I64 main()
{
  U8 b[160];
  I64 r = 0;
  StrPrintN(b, sizeof(b), "RTS Number %03u Started", 1);
  r = Fold(r, b);
  StrPrintN(b, sizeof(b), "RTS Number %03u Started", 4);
  r = Fold(r, b);
  StrPrintN(b, sizeof(b), "[%03u][%03u][%03u]", 0, 99, 100);
  r = Fold(r, b);
  StrPrintN(b, sizeof(b), "[%03u][%03u]", 1234, 4294967295);
  r = Fold(r, b);
  StrPrintN(b, sizeof(b), "Start RTS %03u Rejected: Status: %lu", 7, 5);
  r = Fold(r, b);
  // ---- AND %c, WHICH ARRIVED WITH SC TOO ------------------------------------------------------
  //
  // check_formats refused sc_atsrq.c outright: ten of its event strings print an ATS as a LETTER
  // ("ATS %c Execution Started" with SC_IDX_AS_CHAR, which is 'A' + index) and %c was not
  // implemented. **An unhandled conversion consumes no argument**, so every later argument on the
  // line shifts -- and three of those ten strings have a SECOND %c, so the shift would have fed
  // an index where a letter belonged. Same mechanism docs/ records for %zu in cfe_sb_api.c and %p
  // in mm_utils.c; this is the third conversion added for it.
  //
  // Expected values from C's snprintf, same as above.
  StrPrintN(b, sizeof(b), "ATS %c Execution Started", 'A' + 0);
  r = Fold(r, b);
  StrPrintN(b, sizeof(b), "ATS Switched from %c to %c", 'A' + 0, 'A' + 1);
  r = Fold(r, b);
  // A %c FOLLOWED BY ANOTHER ARGUMENT -- the shift this exists to prevent.
  StrPrintN(b, sizeof(b), "Append ATS %c command: %d entries", 'B', 7);
  r = Fold(r, b);
  // THE LOW BYTE IS WHAT printf TAKES: 0x141 is 'A'. And %c of 0 writes a NUL into the buffer, so
  // the fold sees only what precedes it -- which is still enough to pin the mask.
  StrPrintN(b, sizeof(b), "[%c][%c]", 0x141, 0);
  r = Fold(r, b);
  // A FIELD WIDTH ON %c, which C right-justifies. No cFS call site uses one; pinned so the path
  // is not merely written.
  StrPrintN(b, sizeof(b), "[%3c][%1c]", 'Z', 'Z');
  r = Fold(r, b);
  return r & 0xFFFFFFFFFFFF;
}
