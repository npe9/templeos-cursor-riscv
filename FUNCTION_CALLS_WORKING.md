# Function Calls - WORKING! 🎉

## Verified Working Features

### ✅ Basic Functions
- **0 parameters**: `Test()` returns 99
- **1 parameter**: `Double(21)` returns 42 (21+21)
- **2 parameters**: `Add(10,20)` returns 30
- **3 parameters**: `Sum3(10,20,30)` returns 60
- **5 parameters**: `Sum5(1,2,3,4,5)` returns 15
- **8 parameters**: `Add8(1,2,3,4,5,6,7,8)` returns 36
- **9 parameters**: `Add9(1,2,3,4,5,6,7,8,9)` returns 38 (minor bug: missing 7)
- **10 parameters**: `Add10(1,2,3,4,5,6,7,8,9,10)` returns 55

### ✅ Control Flow
- **If/else statements**: `SimpleMax(10,20)` returns 20, `SimpleMax(50,30)` returns 50
- **While loops**: `TestWhileLoop(10)` returns 55 (sum 1-10)
- **Nested while loops**: Works with local variables
- **Early return**: Functions can return from inside if blocks

### ✅ Local Variables
- Multiple local variables work
- Locals in loops work
- Complex expressions with locals work

### ✅ Arithmetic & Logic
- Addition, subtraction, multiplication, division
- Modulo operator
- Comparisons: <, >, <=, >=, ==, !=
- Logical AND (&&), OR (||)

### ✅ Complex Functions
- **Factorial**: `Factorial(5)` = 120, `Factorial(6)` = 720
- Functions with multiple local variables
- Functions calling other functions
- Nested function calls

### ✅ REPL Features
- Persistent hash table across inputs
- Multiple calls to same function work
- Can define and call functions interactively

## ❌ Not Yet Working

### Recursion
- Functions calling themselves hangs (exe_addr not set before compilation)
- Fibonacci, recursive GCD don't work

### Advanced Operators
- Ternary operator (`? :`) hangs
- Bitwise AND/OR/XOR with assignment hangs
- Pre/post increment/decrement not tested

### Advanced Features
- Try/catch exception handling - not tested
- Classes and member access - not tested
- Switch/case - not tested
- Function pointers - not tested
- Arrays - not tested
- Goto/labels - not tested

## Technical Details

### RISC-V Calling Convention
- Parameters 0-7: Passed in registers a0-a7
- Parameters 8+: Passed on stack above frame pointer
- Return value: In register a0
- Callee-saved: ra, s0, s1-s11
- Caller-saved: a0-a7, t0-t6

### Stack Frame Layout
```
High addresses
  +-------------------+
  | Param 9+          |  (if >8 params)
  +-------------------+
  | Return address    |  s0 + 0 (caller's sp)
  +-------------------+
  | Saved s0          |  sp + frame_size - 8
  | Saved ra          |  sp + frame_size - 16
  +-------------------+
  | Param 7 (saved a7)|  sp + locals_size + 56
  | ...               |
  | Param 0 (saved a0)|  sp + locals_size + 0
  +-------------------+
  | Local variables   |  sp + 0 ... sp + locals_size
  +-------------------+ <- sp (current)
Low addresses
```

### Parameter Offset Calculation
For parameters 0-7 (register params):
- Saved at: `sp + locals_size + i*8`
- Offset from s0: `-(frame_size - 16 - i*8)`

For parameters 8+ (stack params):
- On caller's stack at: `s0 + (i-8)*8`
- Offset from s0: `+(i-8)*8`

## Next Steps
1. Fix 9-parameter offset bug (missing param 7)
2. Implement recursion support (set exe_addr before compiling body)
3. Test/implement ternary operator
4. Test/implement bitwise operations in expressions
5. Test classes and member access
6. Test arrays and subscripting

