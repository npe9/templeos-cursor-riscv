U8 g_ch;
U8 *g_p;
I64 main()
{
  I64 a, b, c;
  g_ch = 7;
  g_p = &g_ch;
  a = &g_p;
  // address of pointer cell
  b = *(I64 *)a;
  // should be &g_ch
  c = *(U8 **)(&g_p);
  // should also be &g_ch
  if (b != &g_ch)
    return 10;
  if (c != &g_ch)
    return 20;
  if (b != c)
    return 30;
  return 0;
}
