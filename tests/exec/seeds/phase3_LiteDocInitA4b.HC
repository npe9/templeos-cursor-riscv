// Soft tip micro-rung A4b: an import call whose argument is a PLAIN GLOBAL ARRAY.
// No doldoc, no planted member, no sizeof. A4 emits a prologue and no body; A4a (sizeof,
// no call) is fine, so the trigger is the call through the import. This rung asks whether
// that needs the planted member at all.
//   A4b fails -> "import call with an array argument" reproduces WITHOUT doldoc, so the
//                repro can move to a tiny exec case and stop costing a phase3 run per try.
//   A4b passes -> the planted member specifically is what breaks the call lowering.
import U8 *MemSet(U8 *dst, I64 dat, I64 size);
U8 rv_a4b_buf[64];
public I64 RVDocInitA4bSelfTest()
{
  rv_a4b_buf[0] = 9;
  MemSet(rv_a4b_buf, 0, 8);
  if (rv_a4b_buf[0])
    return 2;
  return 1;
}
