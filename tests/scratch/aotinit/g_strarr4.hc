// Same, but subscripted twice in one expression.
U8 *g_n[2] = {"zero", "ra"};
I64 main()
{
  return g_n[0][0];
}
