// Array of pointers initialized from a global address (no string literal). Expect 1.
I64 g_v = 9;
I64 *g_p[2] = {&g_v, &g_v};
I64 main()
{
  if (!g_p[0])
    return 0;
  return 1;
}
