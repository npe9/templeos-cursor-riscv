import U8 *StrCpy(U8 *dst,U8 *src);
class CRVMenuEntM
{
  U8 name[24];
  I64 id;
};
CRVMenuEntM g_ent_m;
public I64 AdamLiteMemProbe()
{
  StrCpy(g_ent_m.name,"TileHorz");
  return g_ent_m.name[0];
}
