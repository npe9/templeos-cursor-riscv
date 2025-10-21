// Comprehensive Compiler Test Suite
// Tests all HolyC/TempleOS features

//═══════════════════════════════════════════════════════════════
// BASIC TYPES AND VARIABLES
//═══════════════════════════════════════════════════════════════

I64 TestTypes() {
  I8 a; a = 127;
  U8 b; b = 255;
  I16 c; c = 32767;
  U16 d; d = 65535;
  I32 e; e = 2147483647;
  U32 f; f = 4294967295;
  I64 g; g = 9223372036854775807;
  U64 h; h = 18446744073709551615;
  return a + b + c + d;
}

//═══════════════════════════════════════════════════════════════
// POINTERS AND DEREFERENCING
//═══════════════════════════════════════════════════════════════

I64 TestPointers() {
  I64 x; x = 42;
  I64 *p; p = &x;
  I64 y; y = *p;
  *p = 99;
  return x + y; // Should be 99 + 42 = 141
}

U8 TestPointerArith(U8 *str) {
  U8 *p; p = str;
  I64 len; len = 0;
  while (*p) {
    len = len + 1;
    p = p + 1;
  }
  return len;
}

//═══════════════════════════════════════════════════════════════
// ARRAYS
//═══════════════════════════════════════════════════════════════

I64 TestArrays() {
  I64 arr[5];
  I64 i; i = 0;
  while (i < 5) {
    arr[i] = i * 10;
    i = i + 1;
  }
  return arr[0] + arr[1] + arr[2] + arr[3] + arr[4];
}

//═══════════════════════════════════════════════════════════════
// CONTROL FLOW
//═══════════════════════════════════════════════════════════════

I64 TestIfElse(I64 n) {
  if (n > 10) {
    return 100;
  } else if (n > 5) {
    return 50;
  } else {
    return 10;
  }
}

I64 TestWhileLoop(I64 n) {
  I64 sum; sum = 0;
  I64 i; i = 1;
  while (i <= n) {
    sum = sum + i;
    i = i + 1;
  }
  return sum;
}

I64 TestForLoop(I64 n) {
  I64 sum; sum = 0;
  I64 i;
  for (i = 1; i <= n; i = i + 1) {
    sum = sum + i;
  }
  return sum;
}

//═══════════════════════════════════════════════════════════════
// SWITCH/CASE
//═══════════════════════════════════════════════════════════════

I64 TestSwitch(I64 n) {
  switch (n) {
    case 1: return 10;
    case 2: return 20;
    case 3: return 30;
    default: return 0;
  }
}

//═══════════════════════════════════════════════════════════════
// BREAK AND CONTINUE
//═══════════════════════════════════════════════════════════════

I64 TestBreak(I64 n) {
  I64 sum; sum = 0;
  I64 i; i = 0;
  while (i < 100) {
    if (i >= n) break;
    sum = sum + i;
    i = i + 1;
  }
  return sum;
}

I64 TestContinue(I64 n) {
  I64 sum; sum = 0;
  I64 i; i = 0;
  while (i < n) {
    i = i + 1;
    if (i & 1) continue; // Skip odd numbers
    sum = sum + i;
  }
  return sum;
}

//═══════════════════════════════════════════════════════════════
// RECURSION
//═══════════════════════════════════════════════════════════════

I64 Fib(I64 n) {
  if (n <= 1) return n;
  return Fib(n - 1) + Fib(n - 2);
}

I64 Factorial(I64 n) {
  if (n <= 1) return 1;
  return n * Factorial(n - 1);
}

I64 GCD(I64 a, I64 b) {
  if (b == 0) return a;
  return GCD(b, a % b);
}

//═══════════════════════════════════════════════════════════════
// TRY/CATCH (Exception Handling)
//═══════════════════════════════════════════════════════════════

I64 TestTryCatch() {
  I64 result; result = 0;
  try {
    result = 42;
    // throw; // Would trigger catch
  } catch {
    result = 99;
  }
  return result;
}

I64 TestNestedTry() {
  I64 result; result = 0;
  try {
    try {
      result = 10;
    } catch {
      result = 20;
    }
    result = result + 5;
  } catch {
    result = 100;
  }
  return result;
}

//═══════════════════════════════════════════════════════════════
// CLASSES AND MEMBERS
//═══════════════════════════════════════════════════════════════

class Point {
  I64 x;
  I64 y;
};

I64 TestClass() {
  Point p;
  p.x = 10;
  p.y = 20;
  return p.x + p.y;
}

class Vec3 {
  I64 x, y, z;
};

I64 TestClassMembers() {
  Vec3 v;
  v.x = 1;
  v.y = 2;
  v.z = 3;
  return v.x + v.y + v.z;
}

//═══════════════════════════════════════════════════════════════
// FUNCTION POINTERS
//═══════════════════════════════════════════════════════════════

I64 AddFunc(I64 a, I64 b) { return a + b; }
I64 MulFunc(I64 a, I64 b) { return a * b; }

I64 TestFuncPtr() {
  I64 (*func)(I64, I64);
  func = &AddFunc;
  I64 result; result = func(10, 20);
  func = &MulFunc;
  result = result + func(5, 6);
  return result;
}

//═══════════════════════════════════════════════════════════════
// BITWISE OPERATIONS
//═══════════════════════════════════════════════════════════════

I64 TestBitwise(I64 n) {
  I64 a; a = n & 0xFF;     // AND
  I64 b; b = n | 0x100;    // OR
  I64 c; c = n ^ 0xAA;     // XOR
  I64 d; d = ~n;           // NOT
  I64 e; e = n << 2;       // Left shift
  I64 f; f = n >> 1;       // Right shift
  return a + b + c;
}

//═══════════════════════════════════════════════════════════════
// TERNARY OPERATOR
//═══════════════════════════════════════════════════════════════

I64 TestTernary(I64 n) {
  I64 result;
  result = (n > 10) ? 100 : 50;
  return result;
}

//═══════════════════════════════════════════════════════════════
// COMPOUND ASSIGNMENTS
//═══════════════════════════════════════════════════════════════

I64 TestCompoundAssign(I64 n) {
  I64 x; x = 10;
  x += n;   // x = x + n
  x -= 2;   // x = x - 2
  x *= 3;   // x = x * 3
  x /= 2;   // x = x / 2
  x %= 7;   // x = x % 7
  x <<= 1;  // x = x << 1
  x >>= 1;  // x = x >> 1
  x &= 0xF; // x = x & 0xF
  x |= 0x10;// x = x | 0x10
  x ^= 0x5; // x = x ^ 0x5
  return x;
}

//═══════════════════════════════════════════════════════════════
// PRE/POST INCREMENT/DECREMENT
//═══════════════════════════════════════════════════════════════

I64 TestIncDec() {
  I64 a; a = 10;
  I64 b; b = a++;  // b = 10, a = 11
  I64 c; c = ++a;  // c = 12, a = 12
  I64 d; d = a--;  // d = 12, a = 11
  I64 e; e = --a;  // e = 10, a = 10
  return a + b + c + d + e; // 10+10+12+12+10 = 54
}

//═══════════════════════════════════════════════════════════════
// LOGICAL OPERATORS
//═══════════════════════════════════════════════════════════════

I64 TestLogical(I64 a, I64 b) {
  if (a > 0 && b > 0) return 1;
  if (a > 0 || b > 0) return 2;
  if (!a) return 3;
  return 0;
}

//═══════════════════════════════════════════════════════════════
// GOTO AND LABELS
//═══════════════════════════════════════════════════════════════

I64 TestGoto() {
  I64 sum; sum = 0;
  I64 i; i = 0;
loop_start:
  if (i >= 10) goto loop_end;
  sum = sum + i;
  i = i + 1;
  goto loop_start;
loop_end:
  return sum;
}

//═══════════════════════════════════════════════════════════════
// NESTED FUNCTION CALLS
//═══════════════════════════════════════════════════════════════

I64 Inner(I64 x) { return x * 2; }
I64 Middle(I64 x) { return Inner(x) + 10; }
I64 Outer(I64 x) { return Middle(x) * 3; }

I64 TestNested() {
  return Outer(5); // Should be: (5*2 + 10) * 3 = 60
}

//═══════════════════════════════════════════════════════════════
// VARIADIC FUNCTIONS (VARARGS)
//═══════════════════════════════════════════════════════════════

I64 Sum(I64 count, ...) {
  I64 sum; sum = 0;
  I64 i; i = 0;
  I64 *arg_ptr; arg_ptr = &count + 1;
  while (i < count) {
    sum = sum + *arg_ptr;
    arg_ptr = arg_ptr + 1;
    i = i + 1;
  }
  return sum;
}

//═══════════════════════════════════════════════════════════════
// REGISTER VARIABLES
//═══════════════════════════════════════════════════════════════

I64 TestRegVars() {
  reg I64 a; a = 10;
  reg I64 b; b = 20;
  return a * b;
}

//═══════════════════════════════════════════════════════════════
// STATIC VARIABLES
//═══════════════════════════════════════════════════════════════

I64 TestStatic() {
  static I64 counter; 
  counter = counter + 1;
  return counter;
}

//═══════════════════════════════════════════════════════════════
// SIZEOF
//═══════════════════════════════════════════════════════════════

I64 TestSizeof() {
  I64 size_i64; size_i64 = sizeof(I64);
  I64 size_u8; size_u8 = sizeof(U8);
  I64 size_ptr; size_ptr = sizeof(I64 *);
  return size_i64 + size_u8 + size_ptr; // 8 + 1 + 8 = 17
}

//═══════════════════════════════════════════════════════════════
// CASTING
//═══════════════════════════════════════════════════════════════

I64 TestCasting() {
  I64 a; a = 1000;
  U8 b; b = a; // Truncate to 8 bits
  I64 c; c = b; // Extend back
  I64 *p; p = 0x80000000;
  I64 addr; addr = p;
  return c + addr;
}

//═══════════════════════════════════════════════════════════════
// DOLDOC FEATURES
//═══════════════════════════════════════════════════════════════

U0 TestDolDoc() {
  // Print statements with formatting
  "Hello World\n";
  "Number: %d\n", 42;
  "Hex: 0x%X\n", 255;
  "String: %s\n", "Test";
}

//═══════════════════════════════════════════════════════════════
// EXCEPTIONS WITH THROW
//═══════════════════════════════════════════════════════════════

I64 DivideWithException(I64 a, I64 b) {
  try {
    if (b == 0) throw;
    return a / b;
  } catch {
    return -1; // Error code
  }
}

I64 TestExceptionPropagation() {
  try {
    try {
      throw;
    } catch {
      // Catch and rethrow
      throw;
    }
  } catch {
    return 99; // Caught outer
  }
  return 0;
}

//═══════════════════════════════════════════════════════════════
// COMPLEX EXPRESSIONS
//═══════════════════════════════════════════════════════════════

I64 TestComplexExpr(I64 a, I64 b, I64 c) {
  return (a + b) * c - (a * b) / (c + 1) + ((a << 2) | (b & 0xFF));
}

//═══════════════════════════════════════════════════════════════
// NESTED LOOPS AND BREAK/CONTINUE
//═══════════════════════════════════════════════════════════════

I64 TestNestedLoops() {
  I64 sum; sum = 0;
  I64 i; i = 0;
  while (i < 10) {
    I64 j; j = 0;
    while (j < 10) {
      if (i == j) {
        j = j + 1;
        continue;
      }
      sum = sum + 1;
      j = j + 1;
    }
    i = i + 1;
  }
  return sum; // Should be 90 (10*10 - 10 diagonal)
}

//═══════════════════════════════════════════════════════════════
// TERNARY CHAINS
//═══════════════════════════════════════════════════════════════

I64 TestTernaryChain(I64 n) {
  return (n > 100) ? 1000 : 
         (n > 50) ? 500 :
         (n > 10) ? 100 : 10;
}

//═══════════════════════════════════════════════════════════════
// COMMA OPERATOR
//═══════════════════════════════════════════════════════════════

I64 TestComma() {
  I64 a; I64 b; I64 c;
  c = (a = 10, b = 20, a + b); // Should be 30
  return c;
}

//═══════════════════════════════════════════════════════════════
// MIXED OPERATORS
//═══════════════════════════════════════════════════════════════

I64 TestMixedOps(I64 n) {
  I64 result;
  result = n++ + ++n - n-- + --n; // Complex evaluation order
  result += (n & 0xFF) | ((n >> 8) & 0xFF);
  result ^= (result << 1) & 0xFFFF;
  return result;
}

//═══════════════════════════════════════════════════════════════
// FUNCTION WITH MANY LOCALS
//═══════════════════════════════════════════════════════════════

I64 TestManyLocals() {
  I64 a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p;
  a = 1; b = 2; c = 3; d = 4; e = 5; f = 6; g = 7; h = 8;
  i = 9; j = 10; k = 11; l = 12; m = 13; n = 14; o = 15; p = 16;
  return a+b+c+d+e+f+g+h+i+j+k+l+m+n+o+p; // 136
}

//═══════════════════════════════════════════════════════════════
// ALL PARAMETER COUNTS
//═══════════════════════════════════════════════════════════════

I64 Test0Param() { return 42; }
I64 Test1Param(I64 a) { return a * 2; }
I64 Test2Param(I64 a, I64 b) { return a + b; }
I64 Test3Param(I64 a, I64 b, I64 c) { return a + b + c; }
I64 Test4Param(I64 a, I64 b, I64 c, I64 d) { return a + b + c + d; }
I64 Test5Param(I64 a, I64 b, I64 c, I64 d, I64 e) { return a+b+c+d+e; }
I64 Test6Param(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f) { return a+b+c+d+e+f; }
I64 Test7Param(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g) { return a+b+c+d+e+f+g; }
I64 Test8Param(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h) { return a+b+c+d+e+f+g+h; }
I64 Test9Param(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h, I64 i) { return a+b+c+d+e+f+g+h+i; }
I64 Test10Param(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h, I64 i, I64 j) { return a+b+c+d+e+f+g+h+i+j; }

//═══════════════════════════════════════════════════════════════
// ADVANCED FEATURES
//═══════════════════════════════════════════════════════════════

// Default parameter values
I64 TestDefault(I64 a, I64 b=10, I64 c=20) {
  return a + b + c;
}

// Named constants
#define MAX_VALUE 1000
#define MIN_VALUE 0

I64 TestDefines() {
  return MAX_VALUE + MIN_VALUE;
}

// Inline assembly (if supported)
I64 TestAsm() {
  I64 result;
  asm {
    MOV RAX, 42
    MOV result, RAX
  }
  return result;
}

