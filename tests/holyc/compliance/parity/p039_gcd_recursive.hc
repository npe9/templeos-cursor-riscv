// Parity: recursion different from Fibonacci
I64 Gcd(I64 a, I64 b) {
  if (b == 0)
    return a;
  return Gcd(b, a % b);
}

I64 main() {
  return Gcd(84, 30);
}
