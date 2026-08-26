# HolyC Implementation Status

## Execution-verified status (2026-08-24)

The sections below this one describe what *parses/compiles*; `make compliance` cannot see whether
the generated code is right (it now fails on parse errors instead of silently truncating). This
table is what actually **runs correctly** under QEMU — the bare-metal REPL over the UART
(`make repl-smoke`) and the AOT exec harness (`tests/exec/`) — from probing each feature end to end.

| Runs correctly | Missing / known wrong |
|---|---|
| **Real TempleOS demos on the bare-metal REPL and under the AOT harness** (`make repl-smoke` feeds the files and checks their output): `Demo/Print.HC`, `Demo/NullCase.HC`, `Demo/SubSwitch.HC` (exact `Zero [One] Two …` output), `Demo/RadixSort.HC` (sorts correctly), `Demo/Exceptions.HC`, `Demo/GlblVars.HC` (aggregate initializers, `D()` dumps, `tS`) | `Demo/Carry.HC` (x86 carry flag), `Demo/Define.HC` (`DefineLoad` API), `Demo/MagicPairs.HC` (F64 math library, job queues), DolDoc/graphics/file demos |
| Top level is program level (REPL and AOT): functions, `class`/`union` (incl. `class X {…} a, *b[N];`, self-referential members), `enum`, globals with any initializer incl. **aggregates** (`T a[] = {…}`, `Cls c[] = {{…},{…}}`, strings into `U8` arrays, runtime expressions), `#define` (parameterized, nested, inside parentheses, TABs), `#ifjit`/`#ifaot`/`#exe`, statements — compiled as a frame of their own, so `switch`/`try`/block locals work there too | local (non-static) aggregate initializers |
| `if/else` ladders, ternary, `while`, `do…while`, `for`, `goto`/labels (backward `goto` pops `try` handlers), `switch` incl. `case a...b`, `case:` (auto-increment), fallthrough, `default`, **`sub_switch` `start:`/`end:` blocks** | forward `goto` out of a `try` does not pop the handler |
| **HolyC operator precedence** (Compiler/CInit.HC `binary_ops`): `` ` ``/`<<`/`>>` bind tightest, then `* / %`, then `& ^ |`, then `+ -`, then `< >`, then `== !=`, then `&& ^^ ||` — differs from C (bitwise binds tighter than `+`), so `m&15 +'0'` is `(m&15)+'0'` (the kernel's %X hex path relies on this) | |
| `&&`/`||` (correct even mid-expression, e.g. `x + (a && b) + y` — the short-circuit no longer drops the accumulated operand), `!`, `++`/`--`, all compound assignments, chained `a = b = 3`, unary `-`/`~`, shifts, comparisons; unsigned `/ % < <= > >= >>` when an operand is unsigned | class member functions (not HolyC; `c073`/`p028` are xfail) |
| **F64** through aggregates and pointers: array elements (`a[i]`), struct members (`s.x`), pointer derefs (`*p`) all keep their F64 type; `&x` is a pointer type (not F64). literals (incl. `.5`), `+ - * / %`, compares, unary `-`, I64↔F64 promotion in mixed expressions / assignment / `return`, casts, `Print("%f")`, F64-returning runtime calls (`tS`) | |
| casts: `(U8)`/`(U16)`/`(U32)` mask, `(I8)`/`(I16)`/`(I32)` sign-extend, pointer casts; **F64↔I64 casts relabel the bits** (HolyC: "to typecast int or F64, use ToI64()/ToF64()" — `0x7FF0000000000000(F64)` is inf, `i(F64)` reads i as a double); `ToI64()`, `ToF64()`, `ToBool()` convert | |
| locals, params (own scope), globals (also in expressions with other globals), `static` locals (init-once), typed sub-word loads/stores; arrays (local, global, N-dimensional) decay to their address as values | |
| **AOT data section**: globals and statics work in `holyc-riscv` output (laid out after code+strings, addressed PC-relative) | |
| pointers (`&x`, `*p`, `p[i]`, **pointer arithmetic scaled by element size** — `p+1`/`p++`/`p-q` for `I64*` step by 8, like C), pointee-sized typed elements, **typed class members** (`U8` fields, pointer members `*p->a`, array members `s.name[i]`, `StrCpy(s.name, …)`), `s.x` / `p->x` / `a[i].m` / `a[i].p->m` chains | |
| string literals (PC-relative), char literals (`'AB'` packs; `'ab\n';` statements call `PutChars`), adjacent literals, `"fmt", args;` ≡ `Print(...)`; predefined `NULL TRUE FALSE ON OFF I64_MAX …` | |
| **Runtime, shared by REPL and AOT** (`bootstrap/holy_rt.h`): `Print` (`%d %u %x %X %s %c %p %P %f %n %%`, width/precision, `,` flag, `h<n>`/`h*` repeat), `PutS`, `PutChars`, `MAlloc`/`CAlloc`/`Free`, `StrLen`/`StrCpy`/`StrCmp`/`StrCat`/`StrNew`, `MemCpy`/`MemSet`/`MemCmp`/`MemSetI64`, `AbsI64`/`MaxI64`/`MinI64`, `ToUpper`/`ToLower`, `RandU16`/`RandI64`/`Seed`, `YorN` (answers no), `tS`, `D()` hex dump; `MAlloc`/`Free` with a free list | |
| **AOT calls the runtime too**: externs go through import slots in the data section; the blob ends with a name directory that the exec harness resolves at load (`holy_resolve_imports`) | |
| calls: `Fn(args)`, HolyC `Fn;`, `&Fn`, function pointers, default arguments (trailing and omitted `f(,2)`), same-input define+call, recursion, >8 args; declared-but-undefined or too-few-arguments calls are compile errors | |
| `try`/`catch`/`throw` across calls and nested tries; `Fs->except_ch`, `Fs->catch_except`, `Fs->except_callers[]` exist (`class CTask` + `Fs` are built in) | |
| AOT: entry chunk sets `Fs`, runs the top-level statements (or calls `main()` when there are none); last value → `ORACLE`; parse errors fail the build; REPL errors report the token and line | |
| **2026-08-25 (both REPL and AOT, `tests/exec/cases/e_varargs…e_no_paren_call`)**: chained relations `2<=r<=36`, `switch [x]`, const-expression `case`s (`case -1:`, `case 'a':`), `0b/0o/0d` literals, `∞`, `1e300`, `'$$'`, `$$` as the current address, string literals with `\0` and adjacent-literal concatenation (also across macros), DolDoc `$…$` inside strings, postfix casts `x(U8)` / `"…"(U8 *)[i]` / `(&x)(U8 *)[0]`, `offset(Class.member)`, `>>= <<= %=`, `lock`, `no_warn`, `PUSHFD CLI STI POPFD PAUSE HLT INT` statements, varargs `argc`/`argv`, `(*fp)(args)`, function-pointer values are code addresses (global and local initializers, AOT too), `Fn;` calls when every parameter has a default, `;` between parameters, unnamed parameters, F64 runtime math (`Pow` via `` a`b ``, `Sqrt Exp Ln Floor Ceil Round Sign …`) with I64→F64 argument conversion from the callee's parameter types; **`Kernel/Kernel_RV.PRJ` compiles with 0 errors** (`make coverage`) | DolDoc commands are printed raw on the UART; the compiled kernel's Print reaches its keyboard/screen device layer (PutS), which needs phase-2 device init |
| **pointer depth** (`T **p`, `argv[i][j]`), **large stack frames** (lui/add beyond ±2 KB), frame-slot markers at `-(1<<40)` (no collision on big frames), **import self-resolution** (forward-referenced defs filled by the entry chunk; unresolved imports named at load), ~90 kernel runtime intrinsics (Bt/Que/port-IO/registers/Hash/StrMatch), `HOLYC_MAP` fault-address map, **conditional-branch relaxation** (branches beyond the ±4 KB B-type range jump over a `jal` — the bug that faulted the kernel's 900-line StrPrintJoin); the kernel's StrPrintJoin, QSort (recursion + fn-pointer comparator), Str2I64/StrPrintHex/Str*/Sqrt and the **%f float formatter** (StrPrintJoin("%.4f",3.25)="3.2500", given a populated pow10_I64 table — the test fills it; kernel boot-init is phase 2) all execute correctly (tests/exec/cases/e_kernel_*.hc). An F64-element array decays to its address (an integer), so it must not be typed F64 — else passing it as a vararg mangles the pointer to 0; the kernel's own **PutS drives the UART** via KeyDevAdd + the native keydev walk (register a UART put_s, clear Fs->display_flags/kbd.scan_code); this needed a codegen fix — two indirect calls through fn-pointer members of different arity in one if/else (PutS's put_s/put_key) had the second's arg count clobber the first (SetCallArgCnt now stamps only the tail call IC) | full boot-time device/task init is still phase 2 |
| **2026-08-25, later**: call-site default expressions (`=gr.dc`, `=2.75`, `=-π`), `reg RSI` declarator hints, `sizeof(Class.member)`, unbraced/nested array initializers, `^^`, `π`, `F64_MAX` bit patterns, casts on literals reinterpret, `(*p)(T)`, `->reg`, `format "…"` member meta-data, prototypes without `;`, F64 results of user functions typed at call sites (`K()==2.5`); **`Compiler/Compiler.PRJ` and `Adam/MakeAdam_RV.PRJ` compile with 0 errors** | |

## Overview

This is a comprehensive status report of what's implemented and what's missing in the TempleOS RISC-V HolyC compiler.

### Automated compile checks

- `make compliance` — curated TempleOS `.HC` tree (expected XFAILs marked in the script) plus **52** HolyC-style parity files under `tests/holyc/compliance/parity/`; last green run: all required cases pass.
- `make ci` — **`make compliance`** then **`make qemu-integration`** (UART **execution oracles** in `tests/exec/`, 14 cases in `oracle_manifest.tsv`, plus **TempleOS/RISC-V QEMU smoke**). Matches [GitHub Actions](.github/workflows/ci.yml). Needs RISC-V toolchain, `qemu-system-riscv64`, and Python 3. See [AGENTS.md](AGENTS.md).
- `make compliance-exec` — runs `run_holyc_compliance.sh --suite all --exec`: all manifest compile checks again, then embedded **`make exec-oracle`** path. Does **not** run **`make templeos-smoke`** (use **`make ci`** for full CI parity).

---

## ✅ FULLY IMPLEMENTED

### Core Compiler Infrastructure
- **Lexer** (`lexer.c`): Complete tokenization
  - Identifiers, keywords, numbers
  - All operators (arithmetic, bitwise, logical, comparison)
  - String literals
  - Character literals
  - Comments (`#` line comments)
  - Multi-character operators (`==`, `!=`, `&&`, `||`, `++`, `--`, etc.)

- **Parser** (`parser.c`): Complete AST/IC generation
  - Expression parsing with proper precedence
  - Function definitions and declarations
  - Variable declarations
  - Statement parsing
  - Block parsing with symbol table scoping

- **Code Generator** (`compiler.c`): RISC-V assembly emission
  - All basic instructions (addi, ld, sd, jal, jalr, etc.)
  - Stack frame management
  - Register allocation (a0-a7, s0-s11, t0-t6)
  - Function prologues and epilogues
  - Label resolution in multi-pass compilation

- **Hash Table** (`hash_table.c`): Symbol management
  - Function storage and lookup
  - Type storage
  - Persistent across REPL inputs

### Data Types
- **Integer Types**: `I8`, `I16`, `I32`, `I64`
- **Unsigned Types**: `U8`, `U16`, `U32`, `U64`
- **Floating Point**: `F64` (declared, not fully tested)
- **Boolean**: `Bool` (implemented as I64)
- **Void**: `U0` (no return type)

### Operators
**Arithmetic** ✅
- `+`, `-`, `*`, `/`, `%` (modulo)
- `-` (unary minus) ✅ FULLY IMPLEMENTED
- `++`, `--` (pre/post increment/decrement) ✅ FULLY IMPLEMENTED

**Bitwise** ✅ ALL IMPLEMENTED
- `&`, `|`, `^`, `~`, `<<`, `>>` ✅ ALL FULLY IMPLEMENTED
- `~` (bitwise complement) ✅ FULLY IMPLEMENTED
- `&`, `|`, `^` (bitwise operations) ✅ FULLY IMPLEMENTED
- `&=`, `|=`, `^=` ✅ FULLY IMPLEMENTED

**Logical** ✅
- `&&`, `||`, `!` ✅ FULLY IMPLEMENTED with short-circuit evaluation
- `!` (logical NOT) ✅ FULLY IMPLEMENTED

**Comparison** ✅
- `==`, `!=`, `<`, `>`, `<=`, `>=`

**Assignment** ✅ ALL IMPLEMENTED
- `=` ✅
- `+=`, `-=`, `*=`, `/=` ✅ FULLY IMPLEMENTED
- `&=`, `|=`, `^=` ✅ FULLY IMPLEMENTED

### Control Flow
**Conditionals** ✅
- `if`, `else`
- Nested if/else

**Loops** ✅ ALL IMPLEMENTED
- `while` loops with break/continue
- `for` loops with:
  - Init expressions
  - Condition expressions
  - Increment expressions ✅ FIXED
  - Body statements
- `do-while` loops with break/continue ✅ IMPLEMENTED
- `break` (jump to end of loop)
- `continue` (jump to loop increment/start)

**Unconditional Jumps** ✅
- `return` (with or without value)
- `goto` (labels)
- Switch/case with proper jump handling ✅

**Exception Handling** (parsed, not tested)
- `try/catch`
- `throw`

### Functions
**Function Definitions** ✅
- Return types
- Function names
- Parameters (up to 10+ parameters tested)
- Bodies with multiple statements
- Local variables
- **Forward declarations** ✅ NEWLY ADDED
  - Syntax: `I64 Fibonacci(I64 n);`
  - Adds function signature to hash table without body
  - Can be followed by full definition later

**Function Calls** ✅
- Direct calls: `func()`
- Parameter passing (0-7 in registers, 8+ on stack)
- Return values
- Nested function calls
- Function calls in expressions

**Parameter Passing** ✅
- Parameters 0-7: Registers a0-a7
- Parameters 8+: Stack above caller's frame
- Return value: Register a0
- Proper stack frame management

**RISC-V Calling Convention** ✅
- Callee-saved: ra, s0, s1-s11
- Caller-saved: a0-a7, t0-t6
- Stack alignment (16-byte minimum)
- Frame pointer (s0)

### Variables
**Local Variables** ✅
- Declarations with initialization
- Multiple locals per function
- Locals in nested scopes
- Stack-based storage with proper offsets

**Global Variables** (parsed, not fully tested)
- Global declarations
- Global access

**Parameters** ✅
- Parameter declarations
- Parameter access in body
- Correct stack offsets

### Expressions
**Basic Expressions** ✅
- Integer literals
- Variable references
- Function calls
- Operator precedence
- `sizeof` works for primitive types, struct/enum types, and local/global identifiers

**Complex Expressions** ✅
- Nested expressions
- Multi-operator expressions
- Parenthesized expressions

### Memory Operations
**Pointers** ✅
- Pointer declarations
- Pointer dereferencing (`*`)
- Address-of (`&`)

**Arrays** (parsed, not fully tested)
- Array declarations
- Array subscripting `[]`
- Multi-dimensional arrays (syntax parsed)

### REPL Features
**Interactive Environment** ✅
- Multiple REPL implementations:
  - `worry_dream_repl.c` - Full-featured
  - `simple_repl.c` - Basic
  - `templeos_debugger.c` - TempleOS-style
  - `stepping_debugger.c` - Single-step debugger
- Persistent hash table across inputs
- Multiple function definitions
- Multiple function calls

### Debugging
**Disassembler** ✅
- `U()` - Disassemble instructions
- `D()` - Dump memory
- `Dr()` - Dump registers
- Proper instruction formatting
- Hex address output

**Stepping Debugger** ✅
- Single-step execution (`s`, `step`)
- Continue (`run`)
- Breakpoints (`break`, `clear`)
- PC tracking
- Register state inspection

### RISC-V Backend
**Instruction Set** ✅
- Base integer instructions (RV64I)
- M extension (multiplication/division)
- Proper instruction encoding
- Sign extension for immediates
- Jump/call instruction generation

**Memory Model** ✅
- 64-bit addresses
- Little-endian byte order
- Stack grows downward
- Proper alignment (8-byte for 64-bit values)

**Code Generation** ✅
- AOT (Ahead-Of-Time) compilation
- Executable machine code output
- Proper prologue/epilogue
- Call site code generation
- Return handling

---

## ⚠️ PARTIALLY IMPLEMENTED / NOT TESTED

### Classes & Objects
- Status: Class definitions parsed, member access not tested
- Missing: Member function calls, inheritance, virtual functions

### Arrays
- Status: Syntax parsed, operations not fully tested
- Missing: Bounds checking, initialization, multi-dimensional access

### String Operations
- Status: String literals parsed
- Missing: String manipulation functions, concatenation

### Floating Point
- Status: F64 type declared
- Missing: Floating point arithmetic, comparisons

### Exception Handling
- Status: Try/catch/throw syntax parsed
- Missing: Exception propagation, handler execution

### Switch Statements (FIXED)
- Status: Fully implemented with cascading comparisons
- Supports multiple case labels
- Supports default case
- Proper break handling
- Jump table optimization possible

### Function Pointers
- Status: Parser supports `I64 (*fn)(I64, I64)` declarators, local/static/global storage, and indirect calls
- Missing: Variadic signature metadata, pointer-to-member semantics, richer type checking

### Global Variables
- Status: Parsed but not tested
- Missing: Proper global initialization, access across compilation units

### Preprocessor
- Status: Basic `#define` (simple and parameterized) expansion, `#if 0/1`, `#ifdef`/`#ifndef`, `#else`, `#endif`, `#include` with relative path resolution
- Recent: `#undef` removes macros and frees parameter lists; redeclarations replace the previous definition; `#include` loads files relative to the including source or CWD
- Missing: Nested conditional stacks beyond simple skipping, token pasting edge cases, angle-bracket system include search paths

### Structs/Unions/Enums
- Status: Structs/unions parsed with member access; enums generate integer constants
- Enum type names are registered as I64 aliases and can be used directly in variable declarations
- Anonymous and inline `enum { ... }` definitions allowed in local and global contexts
- Missing: Alignment/packing controls, using enum types as distinct type names

---

## ❌ NOT IMPLEMENTED

### Recursion
- Status: **MOSTLY WORKING** - Functions compile but execution hangs in REPL
- Issue: REPL doesn't auto-execute expressions, requires manual stepping
- Impact: Recursive functions compile successfully, but need explicit execution

### Advanced Object-Oriented Features
- Virtual functions
- Method overloading
- Operator overloading
- Templates/generics

### Memory Management
- `new` / `delete` operators
- Garbage collection
- Smart pointers

### Concurrency
- Threads
- Mutexes
- Atomic operations

### File I/O
- File operations
- Stream handling

### Networking
- Network protocols
- Socket operations

### Graphics
- 2D graphics
- 3D graphics
- Sprites

### Audio
- Sound playback
- Music

### Keyboard/Mouse Input
- Keyboard handling
- Mouse handling

### System Calls
- Process management
- IPC
- Signals

---

## Test Coverage

### ✅ Working Tests
- Basic arithmetic: `42`, `10+20*2`
- Modulo: `17 % 5`
- Functions with 0-10 parameters
- Control flow: `if/else`, `while`, `for`
- Local variables
- Function calls
- Return values
- Nested calls
- Complex expressions
- Factorial function
- GCD algorithm (iterative)
- While loop summation

### ❌ Failing / fragile (execution or REPL)
- **Bare-metal REPL:** Stress tests and some multi-call sequences have reported hangs or corruption; treat as under investigation (compile often still succeeds).
- **Complex array operations:** Parsed and partially covered by compliance; edge cases remain.
- **Recursive / deep call patterns:** May still hit runtime or REPL issues even when `make compliance` compiles recursive examples (e.g. parity GCD).

---

## Known Issues

1. **Recursion Bug**: Functions calling themselves hang because `exe_addr` isn't set before compiling the body
   - Fix: Set function address in hash table before parsing body

2. **9th Parameter**: Minor offset bug for 9th parameter (missing param 7)
   - Status: Known issue, doesn't affect most code

3. **For Loop Increment**: Fixed in recent commit - increment is now properly placed after body

4. **Missing Braces**: Fixed in recent commit - function call parsing had missing braces

5. **Terminal Corruption**: Sometimes output becomes corrupted during stress tests
   - Cause: Unknown, needs investigation

---

## Recent Additions

### Latest Commits
1. **Bitwise Operations** ✅: Implemented `&`, `|`, `^` (bitwise AND, OR, XOR)
   - Bitwise AND (`&`): IC_AND - generates `and` instruction
   - Bitwise OR (`|`): IC_OR - generates `or` instruction
   - Bitwise XOR (`^`): IC_XOR - generates `xor` instruction
   - Full code generation in both passes

2. **Compound Assignment Operators** ✅: Implemented `+=`, `-=`, `*=`, `/=`, `&=`, `|=`, `^=`
   - All compound assignments: x += y means x = x + y
   - Loads value, performs operation, stores back
   - Full code generation in both passes

3. **Unary Operators** ✅: Implemented `!`, `~`, `-`, `&` (address-of)
   - Logical NOT (`!`): IC_NOT - generates `sltiu a0, a0, 1`
   - Bitwise complement (`~`): IC_COM - generates `xori a0, a0, -1`
   - Unary minus (`-`): IC_UNARY_MINUS - generates `sub a0, zero, a0`
   - Address-of (`&`): IC_ADDR - no-op (address already available)
   - Full code generation in both passes

4. **Logical Operators** ✅: Implemented `&&`, `||` with **short-circuit** control flow (`IC_BR_ZERO` / `IC_BR_NOT_ZERO` and labels in `ParseLogicalAnd` / `ParseLogicalOr`)
   - Distinct from single `&` / `|` (bitwise), which use `IC_AND` / `IC_OR`

5. **Shift Operators** ✅: Implemented `<<`, `>>` (shift left/right)
   - Left shift (`<<`): IC_SHL - generates `sll` instruction
   - Right shift (`>>`): IC_SHR - generates `srl` instruction
   - Full code generation in both passes

6. **Increment/Decrement Operators** ✅: Implemented `