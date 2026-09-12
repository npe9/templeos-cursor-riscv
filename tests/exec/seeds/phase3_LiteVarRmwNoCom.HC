I64 g_nr[8];
public I64 AdamLiteVarRmwNoComProbe()
{
  I64 i;
  i = 0;
  g_nr[i] = g_nr[i] & 1;
  return g_nr[0];
}
