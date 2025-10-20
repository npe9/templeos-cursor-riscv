I64 Power(I64 base, I64 exp) {
  I64 result = 1;
  while (exp > 0) {
    result = result * base;
    exp = exp - 1;
  }
  return result;
}

I64 Main() {
  return Power(2, 10);  // Should return 1024
}
