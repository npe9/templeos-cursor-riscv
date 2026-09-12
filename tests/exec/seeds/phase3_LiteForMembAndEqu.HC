class CForMembAndEqu
{
  I64 flags[8];
};
CForMembAndEqu g_fmae;
public I64 AdamLiteForMembAndEquProbe()
{
  I64 i;
  for (i = 0; i < 8; i++)
    g_fmae.flags[i] &= ~1;
  return g_fmae.flags[0];
}
