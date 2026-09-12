#include "A:/Compiler/DolDocDefines.HC"
import U8 *MemSet(U8 *dst, I64 dat, I64 size);
class CDocInitMemSet
{
  I64 dft_de_flags[43];
  I32 dft_type_flags[43];
};
CDocInitMemSet g_dim;
public I64 AdamLiteDocInitMemSetProbe()
{
  MemSet(g_dim.dft_de_flags, 0, sizeof(g_dim.dft_de_flags));
  MemSet(g_dim.dft_type_flags, 0, sizeof(g_dim.dft_type_flags));
  g_dim.dft_de_flags[DOCT_TEXT] = DOCEF_TAG;
  return g_dim.dft_de_flags[DOCT_TEXT];
}
