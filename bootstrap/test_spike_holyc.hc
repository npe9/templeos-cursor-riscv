// Test HolyC program for Spike
// Simple program to verify HolyC → RISC-V → Spike works

I64 Fibonacci(I64 n) {
  if (n <= 1) {
    return n;
  }
  return Fibonacci(n - 1) + Fibonacci(n - 2);
}

I64 Factorial(I64 n) {
  if (n <= 1) {
    return 1;
  }
  return n * Factorial(n - 1);
}

U0 Main() {
  I64 fib10 = Fibonacci(10);
  I64 fact5 = Factorial(5);
  
  // In Spike, we'd need syscalls to print
  // For now, just compute and exit
  I64 result = fib10 + fact5;  // 55 + 120 = 175
}


