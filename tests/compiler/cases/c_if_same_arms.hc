// Identical if/else arms → IcOptIfElseTailMerge (one body, no duplicated tail).
I64 g;
I64 main()
{
  I64 c;
  c = 1;
  if (c)
    g = g + 1;
  else
    g = g + 1;
  return g;
}
