I64 g_cr[8];
public I64 AdamLiteConstRmwProbe()
{
  g_cr[0] = g_cr[0] & ~1;
  return g_cr[0];
}
