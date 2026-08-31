// Test HolyC Functions - Exercise the Compiler

// Simple arithmetic
I64 Factorial(I64 n) {
  I64 result;
  result = 1;
  while (n > 1) {
    result = result * n;
    n = n - 1;
  }
  return result;
}

// Fibonacci with recursion  
I64 Fib(I64 n) {
  if (n <= 1) return n;
  return Fib(n-1) + Fib(n-2);
}

// Multiple parameters
I64 Max(I64 a, I64 b) {
  if (a > b) return a;
  return b;
}

// More parameters
I64 Sum5(I64 a, I64 b, I64 c, I64 d, I64 e) {
  return a + b + c + d + e;
}

// Pointer operations
U8 *StrLen(U8 *str) {
  I64 len;
  len = 0;
  while (*str) {
    len = len + 1;
    str = str + 1;
  }
  return len;
}

// Bit operations
I64 CountBits(I64 n) {
  I64 count;
  count = 0;
  while (n) {
    if (n & 1) count = count + 1;
    n = n >> 1;
  }
  return count;
}

// Test with local variables
I64 LocalsTest(I64 x) {
  I64 a, b, c;
  a = x + 1;
  b = x + 2;
  c = a + b;
  return c;
}

// Nested function calls
I64 Nested(I64 n) {
  return Max(Factorial(3), Factorial(4));
}

// Test >8 parameters
I64 Sum12(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h, I64 i, I64 j, I64 k, I64 l) {
  return a+b+c+d+e+f+g+h+i+j+k+l;
}

