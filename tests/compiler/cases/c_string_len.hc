// String literal address + byte walk.
I64 main()
{
  U8 *s;
  I64 n;
  s = "hello";
  n = 0;
  while (*s) {
    n++;
    s++;
  }
  return n;
}
