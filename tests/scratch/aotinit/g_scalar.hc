// Does the AOT image apply a file-scope scalar initializer? Expect 7 if yes, 0 if no.
I64 g_s = 7;
I64 main()
{
  return g_s;
}
