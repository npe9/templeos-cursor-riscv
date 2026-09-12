I64 g_vr[8];
public I64 AdamLiteVarRmwProbe()
{
  I64 i;
  i = 0;
  g_vr[i] = g_vr[i] & 1;
  return g_vr[0];
}
