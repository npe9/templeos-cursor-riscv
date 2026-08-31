I64 g;
I64 main()
{
  I64 *p;
  g = 0;
  p = &g;
  if (!p)
    return 1;
  // must not take
  if (p) {
  } else
    return 2;
  // must take
  p = 0;
  if (p)
    return 3;
  // must not
  if (!p) {
  } else
    return 4;
  // must take
  return 0;
}
