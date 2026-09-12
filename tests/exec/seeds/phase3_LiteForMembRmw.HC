class CForMembRmw
{
  I64 flags[8];
};
CForMembRmw g_fmr;
public I64 AdamLiteForMembRmwProbe()
{
  I64 i;
  for (i = 0; i < 8; i++)
    g_fmr.flags[i] = g_fmr.flags[i] & ~1;
  return g_fmr.flags[0];
}
