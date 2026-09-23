// Soft tip micro-rung A4a: sizeof on the planted doldoc member, and NOTHING ELSE.
// A4 does two new things at once -- sizeof/array-member decay AND a call through an
// import -- and it is the only rung in the ladder that imports anything at all. A4 faults
// with mcause=2, so this rung splits those two: same sizeof check, no import, no call.
//   A4a passes -> sizeof and the plant's dim chain are fine; the fault is the import call.
//   A4a fails  -> sizeof on the planted member is the problem and the import is innocent.
#include "A:/Compiler/DolDocDefines.HC"
public I64 RVDocInitA4aSelfTest()
{
  if (sizeof(doldoc.dft_de_flags) != 8 * DOCT_TYPES_NUM)
    return 2;
  return 1;
}
