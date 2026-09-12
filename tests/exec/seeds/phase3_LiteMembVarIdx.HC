class CMembIdx
{
  I64 flags[8];
};
CMembIdx g_mvi;
public I64 AdamLiteMembVarIdxProbe()
{
  I64 i;
  i = 0;
  g_mvi.flags[i] = 1;
  return g_mvi.flags[0];
}
