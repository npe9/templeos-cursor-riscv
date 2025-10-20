I64 Add(I64 a, I64 b) {
  return a + b;
}

I64 Multiply(I64 a, I64 b) {
  return a * b;
}

I64 Fibonacci(I64 n) {
  if (n <= 1) return n;
  return Fibonacci(n-1) + Fibonacci(n-2);
}

I64 Power(I64 base, I64 exp) {
  I64 result = 1;
  while (exp > 0) {
    result = Multiply(result, base);
    exp = exp - 1;
  }
  return result;
}

I64 Calculate(I64 x) {
  I64 a;
  I64 b;
  I64 c;
  a = Add(x, 10);
  b = Power(2, 5);
  c = Fibonacci(7);
  return Add(Add(a, b), c);
}

I64 Main() {
  return Calculate(100);
}
