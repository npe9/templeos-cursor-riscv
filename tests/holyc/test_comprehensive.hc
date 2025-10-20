// Test all implemented features

I64 TestArithmetic() {
  return 10 + 5 - 3;  // Should be 12
}

I64 TestBitwise() {
  return (15 & 7) | 8;  // Should be 15
}

I64 TestUnary() {
  I64 x;
  x = 5;
  return -x;  // Should be -5 (will be 18446744073709551611 as unsigned)
}

I64 TestComparison() {
  if (5 < 10) return 100;
  return 200;
}

I64 TestParams(I64 a, I64 b) {
  return a * b;
}

I64 Main() {
  return TestParams(6, 7);  // Should be 42
}
