// File-scope scalar string pointer. Expect 1 if the literal address is relocated.
U8 *g_s = "zero";
I64 main()
{
  if (!g_s)
    return 0;
  return g_s[0] == 'z';
}
