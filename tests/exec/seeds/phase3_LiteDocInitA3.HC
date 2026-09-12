// Soft tip micro-rung A3: const-index store into the planted doldoc.dft_de_flags[43].
// Exercises CDolDocGlbls dim.total_cnt from RVExePubCDolDocGlblsLiteIn.
#include "A:/Compiler/DolDocDefines.HC"
public I64 RVDocInitA3SelfTest()
{
  doldoc.dft_de_flags[DOCT_TEXT] = DOCEF_TAG;
  if (doldoc.dft_de_flags[DOCT_TEXT] != DOCEF_TAG)
    return 2;
  return 1;
}
