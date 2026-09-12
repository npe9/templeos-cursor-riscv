I64 g_fr[8];
public I64 AdamLiteFlatRmwProbe()
{
  I64 i;
  for (i = 0; i < 8; i++)
    g_fr[i] = g_fr[i] & ~1;
  return g_fr[0];
}
