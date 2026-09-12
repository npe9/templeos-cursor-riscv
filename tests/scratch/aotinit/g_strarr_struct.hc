// Struct-wrapped string-pointer table (the working shape). Expect 3.
class Row
{
  U8 *nm;
};
Row g_r[2] = {{"zero"}, {"ra"}};
I64 main()
{
  I64 r = 0;
  if (g_r[0].nm)
    r = r + 1;
  if (g_r[1].nm)
    r = r + 2;
  return r;
}
