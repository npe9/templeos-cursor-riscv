// Test TempleOS HolyC functions
// Based on actual TempleOS code patterns

// Simple math functions
I64 Add(I64 a, I64 b) {
  return a + b;
}

I64 Mul(I64 a, I64 b) {
  return a * b;
}

I64 Factorial(I64 n) {
  if (n <= 1) return 1;
  return n * Factorial(n - 1);
}

// String functions
U0 PrintString(U8 *str) {
  // Simple string printing (would need UART implementation)
  return;
}

// Array functions
I64 SumArray(I64 *arr, I64 len) {
  I64 sum = 0;
  I64 i;
  for (i = 0; i < len; i++) {
    sum += arr[i];
  }
  return sum;
}

// Complex function with many parameters
I64 ComplexFunc(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h, I64 i, I64 j, I64 k, I64 l) {
  return a + b + c + d + e + f + g + h + i + j + k + l;
}

// Function with mixed parameter types
I64 MixedParams(I64 a, U8 *str, I64 b, U8 *str2, I64 c) {
  return a + b + c;
}

// Nested function calls
I64 NestedCalls(I64 a, I64 b) {
  return Add(Mul(a, 2), Add(b, 3));
}

// Function with local variables
I64 LocalVars(I64 n) {
  I64 i, sum = 0;
  for (i = 1; i <= n; i++) {
    sum += i;
  }
  return sum;
}

// Function with conditional logic
I64 Max(I64 a, I64 b) {
  if (a > b) {
    return a;
  } else {
    return b;
  }
}

// Function with loops
I64 SumSquares(I64 n) {
  I64 i, sum = 0;
  for (i = 1; i <= n; i++) {
    sum += i * i;
  }
  return sum;
}
