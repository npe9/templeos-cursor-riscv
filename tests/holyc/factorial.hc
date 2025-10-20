I64 Fact(I64 n) {
  I64 result;
  result = 1;
  I64 i;
  i = 1;
  while (i < n) {
    i = i + 1;
    result = result + result;
  }
  return result;
}

I64 Main() {
  return Fact(5);
}
