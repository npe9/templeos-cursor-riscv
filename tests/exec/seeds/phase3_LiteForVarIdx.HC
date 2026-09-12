I64 g_fvi[8];
public I64 AdamLiteForVarIdxProbe()
{
  I64 i;
  for (i = 0; i < 8; i++)
    g_fvi[i] = 1;
  return g_fvi[0];
}
