// TempleOS-style math functions

I64 Abs(I64 x) {
  if (x < 0) return -x;
  return x;
}

I64 Max(I64 a, I64 b) {
  if (a > b) return a;
  return b;
}

I64 Min(I64 a, I64 b) {
  if (a < b) return a;
  return b;
}

I64 Main() {
  return Max(Abs(-42), Min(10, 20));  // Should be 42
}
