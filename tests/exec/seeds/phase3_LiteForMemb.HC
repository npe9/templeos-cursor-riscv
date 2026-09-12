class CForMemb
{
  I64 flags[8];
};
CForMemb g_fm;
public I64 AdamLiteForMembProbe()
{
  I64 i;
  for (i = 0; i < 8; i++)
    g_fm.flags[i] = 1;
  return g_fm.flags[0];
}
