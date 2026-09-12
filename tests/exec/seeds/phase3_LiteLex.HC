import U8 *StrCpy(U8 *dst,U8 *src);
U8 g_lex_buf[40];
public I64 AdamLiteLexProbe()
{
  StrCpy(g_lex_buf,"TileHorz");
  return g_lex_buf[0];
}
