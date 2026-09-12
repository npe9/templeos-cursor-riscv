// File-scope struct array with a string member. Expect 1 if applied.
class Row
{
  U8 *nm;
  I64 v;
};
Row g_r[2] = {{"a", 3}, {"b", 4}};
I64 main()
{
  if (!g_r[0].nm)
    return 0;
  return g_r[0].nm[0] == 'a' && g_r[1].v == 4;
}
