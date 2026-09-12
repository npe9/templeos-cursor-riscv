I64 g_sr[8];
public I64 AdamLiteSplitRmwProbe()
{
  I64 i, x;
  i = 0;
  x = g_sr[i];
  g_sr[i] = x & 1;
  return g_sr[0];
}
