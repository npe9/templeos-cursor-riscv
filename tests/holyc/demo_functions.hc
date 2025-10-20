I64 Add(I64 a, I64 b) { return a + b; }
I64 Multiply(I64 x, I64 y) { return x * y; }
I64 Fibonacci(I64 n) { 
  if (n <= 1) return n;
  return Fibonacci(n-1) + Fibonacci(n-2);
}
I64 Main() { 
  return Add(10, 32);
}
