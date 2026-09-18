// The BCPL rule, written the ordinary way: every statement ends in a semicolon.
// tests/exec/cases/newline_semi_bare.hc is this same program with them removed; the two must
// compile to identical bytes, which is the whole claim the rule makes.
U0 NlWork(I64 *out)
{
  I64 a = 1;
  I64 b = 2;
  a = a + b;
  if (a > 2)
    b = b + 1;
  while (b < 6)
    b = b + 1;
  do
    a = a + 1;
  while (a < 5);
  out[0] = a;
  out[1] = b;
}

I64 main()
{
  I64 r[2];
  NlWork(r);
  return r[0] + r[1];
}
