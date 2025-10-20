// Real TempleOS-style code

I64 StrLen(U8 *str) {
  I64 count;
  count = 0;
  while (*str) {
    count = count + 1;
    str = str + 1;
  }
  return count;
}

I64 Main() {
  return 42;
}
