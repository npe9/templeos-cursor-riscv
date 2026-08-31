// Simple test to verify compiler works

I64 Add(I64 a, I64 b) {
  return a + b;
}

I64 Factorial(I64 n) {
  if (n <= 1) {
    return 1;
  }
  return n * Factorial(n - 1);
}

U0 Main() {
  I64 x = Add(5, 3);
  I64 y = Factorial(5);
}


