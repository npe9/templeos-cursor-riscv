// Soft tip micro-rung A4: array-member decay + sizeof on the planted doldoc member.
// sizeof(doldoc.dft_de_flags) needs the plant's dim chain, not just total_cnt.
#include "A:/Compiler/DolDocDefines.HC"
import U8 *MemSet(U8 *dst, I64 dat, I64 size);
public I64 RVDocInitA4SelfTest()
{
  if (sizeof(doldoc.dft_de_flags) != 8 * DOCT_TYPES_NUM)
    return 2;
  MemSet(doldoc.dft_de_flags, 0, sizeof(doldoc.dft_de_flags));
  return 1;
}
