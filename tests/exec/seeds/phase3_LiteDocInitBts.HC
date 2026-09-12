#include "A:/Compiler/DolDocDefines.HC"
import Bool Bt(U8 *bf, I64 n);
import Bool Bts(U8 *bf, I64 n);
class CDocInitBts
{
  I64 dft_de_flags[43];
  I64 type_flags_form[1];
};
CDocInitBts g_dib;
public I64 AdamLiteDocInitBtsProbe()
{
  I64 i;
  g_dib.dft_de_flags[DOCT_LINK] = DOCEF_TAG;
  g_dib.type_flags_form[0] = 0;
  for (i = 0; i < DOCT_TYPES_NUM; i++)
    if (Bt(&g_dib.dft_de_flags[i], DOCEf_TAG) && i != DOCT_TEXT || i == DOCT_HEX_ED)
      Bts(g_dib.type_flags_form, i);
  return Bt(g_dib.type_flags_form, DOCT_LINK);
}
