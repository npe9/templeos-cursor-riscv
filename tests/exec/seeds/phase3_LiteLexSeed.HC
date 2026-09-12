import U8 *StrCpy(U8 *dst,U8 *src);
U8 g_lex_x[40];
public I64 AdamLiteLexSeedProbe()
{
  g_lex_x[0]='X';
  StrCpy(g_lex_x,"TileHorz");
  return g_lex_x[0];
}
