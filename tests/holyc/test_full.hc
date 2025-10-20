I64 Factorial(I64 n) {
  if (n <= 1) return 1;
  return n * Factorial(n - 1);
}

I64 Main() {
  return Factorial(5);
}
