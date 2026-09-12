// File-scope table of function pointers. Expect 5 if the addresses are relocated.
I64 Five()
{
  return 5;
}
I64 (*g_f[1])() = {&Five};
I64 main()
{
  if (!g_f[0])
    return 0;
  return (*g_f[0])();
}
