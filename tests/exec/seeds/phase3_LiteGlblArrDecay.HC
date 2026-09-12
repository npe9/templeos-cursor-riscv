I64 g_arr_decay[8];
class CGlblArrDecayMemb
{
  I64 flags[43];
};
CGlblArrDecayMemb g_arr_decay_memb;
public I64 AdamLiteGlblArrDecayProbe()
{
  I64 *p;
  p = g_arr_decay;
  *p = 1;
  return p[0];
}

public I64 AdamLiteGlblArrDecayWalkProbe()
{
  I64 *p;
  I64 *e;
  p = g_arr_decay_memb.flags;
  e = p + 43;
  while (p < e) {
    *p = *p & ~0xB0000000;
    p++;
  }
  return g_arr_decay_memb.flags[0] + 1;
}
