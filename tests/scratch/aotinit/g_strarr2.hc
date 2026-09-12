// Is the slot itself zero, or just the deref wrong? Expect 3 = both slots non-NULL.
U8 *g_n[2] = {"zero", "ra"};
I64 main()
{
  I64 r = 0;
  if (g_n[0])
    r = r + 1;
  if (g_n[1])
    r = r + 2;
  return r;
}
