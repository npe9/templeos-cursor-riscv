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
  return r & 0xFFFFFFFFFFFF;
}
