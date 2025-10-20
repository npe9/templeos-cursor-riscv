/* RISC-V Backend Test Cases
 * 
 * Test various IC operations and their RISC-V code generation.
 */

#help_index "Compiler/Test"

/* Test 1: Basic Arithmetic */
U0 TestArithmetic()
{
  I64 a = 5;
  I64 b = 10;
  I64 c = a + b;        // IC_ADD
  I64 d = a - b;        // IC_SUB
  I64 e = a * b;        // IC_MUL
  I64 f = b / a;        // IC_DIV
  I64 g = b % a;        // IC_MOD
  
  Print("c=%d d=%d e=%d f=%d g=%d\n", c, d, e, f, g);
}

/* Test 2: Bitwise Operations */
U0 TestBitwise()
{
  I64 a = 0xFF00;
  I64 b = 0x0F0F;
  
  I64 c = a & b;        // IC_AND
  I64 d = a | b;        // IC_OR
  I64 e = a ^ b;        // IC_XOR
  I64 f = ~a;           // IC_COM
  I64 g = a << 4;       // IC_SHL
  I64 h = a >> 4;       // IC_SHR
  
  Print("c=%X d=%X e=%X f=%X g=%X h=%X\n", c, d, e, f, g, h);
}

/* Test 3: Comparisons */
U0 TestComparisons()
{
  I64 a = 5;
  I64 b = 10;
  
  Bool c1 = (a == b);   // IC_EQU_EQU
  Bool c2 = (a != b);   // IC_NOT_EQU
  Bool c3 = (a < b);    // IC_LESS
  Bool c4 = (a > b);    // IC_GREATER
  Bool c5 = (a <= b);   // IC_LESS_EQU
  Bool c6 = (a >= b);   // IC_GREATER_EQU
  
  Print("== %d, != %d, < %d, > %d, <= %d, >= %d\n", c1, c2, c3, c4, c5, c6);
}

/* Test 4: Control Flow */
U0 TestControlFlow()
{
  I64 i;
  
  // Loop with branch
  for (i = 0; i < 10; i++) {  // IC_BR_LESS
    if (i % 2 == 0) {         // IC_BR_EQU_EQU
      Print("Even: %d\n", i);
    } else {
      Print("Odd: %d\n", i);
    }
  }
}

/* Test 5: Function Calls */
I64 AddNumbers(I64 x, I64 y)
{// Test IC_ENTER, IC_LEAVE, IC_RET
  return x + y;  // IC_RETURN_VAL
}

U0 TestFunctionCalls()
{
  I64 result = AddNumbers(5, 10);  // IC_CALL
  Print("Result: %d\n", result);
}

/* Test 6: Recursive Function */
I64 Factorial(I64 n)
{
  if (n <= 1) {          // IC_BR_LESS_EQU
    return 1;            // IC_RETURN_VAL
  }
  return n * Factorial(n - 1);  // IC_MUL, IC_CALL (recursive)
}

U0 TestRecursion()
{
  I64 f5 = Factorial(5);
  Print("5! = %d\n", f5);
}

/* Test 7: Floating-Point */
U0 TestFloatingPoint()
{
  F64 a = 3.14;
  F64 b = 2.0;
  
  F64 c = a + b;        // IC_ADD (F64)
  F64 d = a - b;        // IC_SUB (F64)
  F64 e = a * b;        // IC_MUL (F64)
  F64 f = a / b;        // IC_DIV (F64)
  
  F64 g = Sqrt(16.0);   // IC_SQRT
  
  Print("c=%5.2f d=%5.2f e=%5.2f f=%5.2f g=%5.2f\n", c, d, e, f, g);
}

/* Test 8: Type Conversions */
U0 TestConversions()
{
  I64 i = 42;
  F64 f = i;            // IC_TO_F64
  I64 j = f;            // IC_TO_I64
  
  Bool b1 = i;          // IC_TO_BOOL
  Bool b2 = 0;          // IC_TO_BOOL
  
  Print("i=%d f=%5.2f j=%d b1=%d b2=%d\n", i, f, j, b1, b2);
}

/* Test 9: Pointers and Arrays */
U0 TestPointers()
{
  I64 arr[10];
  I64 *p = arr;
  I64 i;
  
  for (i = 0; i < 10; i++) {
    *p++ = i * 2;       // IC_DEREF_PP, IC_ASSIGN
  }
  
  p = arr;
  for (i = 0; i < 10; i++) {
    Print("%d ", *p++);  // IC_DEREF_PP
  }
  Print("\n");
}

/* Test 10: Switch Statement */
U0 TestSwitch(I64 val)
{
  switch (val) {         // IC_SWITCH
    case 0:
      Print("Zero\n");
      break;
    case 1:
      Print("One\n");
      break;
    case 2:
      Print("Two\n");
      break;
    default:
      Print("Other: %d\n", val);
  }
}

/* Test 11: Bit Operations */
U0 TestBitOps()
{
  I64 val = 0b10110100;
  
  Bool bit3 = Bt(&val, 3);        // IC_BT - Bit test
  Bts(&val, 5);                   // IC_BTS - Bit test and set
  Btr(&val, 2);                   // IC_BTR - Bit test and reset
  Btc(&val, 4);                   // IC_BTC - Bit test and complement
  
  I64 first_set = Bsf(val);       // IC_BSF - Bit scan forward
  I64 last_set = Bsr(val);        // IC_BSR - Bit scan reverse
  
  Print("bit3=%d val=%X first=%d last=%d\n", bit3, val, first_set, last_set);
}

/* Test 12: Min/Max/Abs */
U0 TestMinMaxAbs()
{
  I64 a = -5;
  I64 b = 10;
  
  I64 min_val = MinI64(a, b);     // IC_MIN_I64
  I64 max_val = MaxI64(a, b);     // IC_MAX_I64
  I64 abs_val = AbsI64(a);        // IC_ABS_I64
  I64 sign = SignI64(a);          // IC_SIGN_I64
  
  Print("min=%d max=%d abs=%d sign=%d\n", min_val, max_val, abs_val, sign);
}

/* Test 13: Comprehensive Test */
U0 TestAll()
{
  Print("\n=== RISC-V Backend Test Suite ===\n\n");
  
  Print("Test 1: Arithmetic\n");
  TestArithmetic();
  
  Print("\nTest 2: Bitwise\n");
  TestBitwise();
  
  Print("\nTest 3: Comparisons\n");
  TestComparisons();
  
  Print("\nTest 4: Control Flow\n");
  TestControlFlow();
  
  Print("\nTest 5: Function Calls\n");
  TestFunctionCalls();
  
  Print("\nTest 6: Recursion\n");
  TestRecursion();
  
  Print("\nTest 7: Floating-Point\n");
  TestFloatingPoint();
  
  Print("\nTest 8: Type Conversions\n");
  TestConversions();
  
  Print("\nTest 9: Pointers\n");
  TestPointers();
  
  Print("\nTest 10: Switch\n");
  TestSwitch(0);
  TestSwitch(1);
  TestSwitch(99);
  
  Print("\nTest 11: Bit Operations\n");
  TestBitOps();
  
  Print("\nTest 12: Min/Max/Abs\n");
  TestMinMaxAbs();
  
  Print("\n=== All Tests Complete ===\n");
}

/* Example: Trace IC to RISC-V Translation */
U0 ShowTranslation()
{// Enable trace mode to see IC and generated RISC-V code
  Trace(ON);
  PassTrace(0b1111111111);  // Enable all optimizer passes
  
  // Simple expression to trace
  I64 result = 5 + 10 * 2;
  
  Print("Result: %d\n", result);
  
  Trace(OFF);
}

#help_index ""


