// File-scope I64 array initializer. Expect 6 if the AOT applies it, 0 if not.
I64 g_a[3] = {1, 2, 3};
I64 main()
{
  return g_a[0] + g_a[1] + g_a[2];
}
