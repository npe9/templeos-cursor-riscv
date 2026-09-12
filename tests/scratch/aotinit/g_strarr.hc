// File-scope string-pointer table (the disasm.hc RN shape). Expect 1 if applied.
U8 *g_n[2] = {"zero", "ra"};
I64 main()
{
  if (!g_n[0])
    return 0;
  return g_n[0][0] == 'z';
}
