// Raw first byte through a file-scope string-pointer table. 'z' = 0x7a.
U8 *g_n[2] = {"zero", "ra"};
I64 main()
{
  U8 *p;
  p = g_n[0];
  return p[0];
}
