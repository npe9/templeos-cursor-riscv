I64 h()
{
  static I64 c = 0;
  c++;
  return c;
}
h();
h();
