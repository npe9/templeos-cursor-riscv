# TempleOS HolyC Compiler for RISC-V

A from-scratch implementation of the HolyC programming language compiler targeting bare-metal RISC-V.

## Project Structure

```
templeos-cursor-riscv/
├── README.md              # This file
├── Makefile              # Build configuration
│
├── Core Compiler
│   ├── lexer.c           # Tokenization
│   ├── parser.c          # Syntax analysis & IC generation (2600+ lines)
│   ├── compiler.c        # RISC-V code generation (900+ lines)
│   ├── hash_table.c      # Symbol table management
│   ├── holyc_compiler.h  # Compiler data structures
│   └── compiler_helper.c # REPL integration helpers
│
├── bootstrap/            # Bare metal runtime & build
│   ├── worry_dream_repl.c # REPL loop (bare metal)
│   ├── startup.s          # RISC-V boot code
│   ├── linker.ld          # Memory layout
│   ├── Makefile.repl      # REPL build config
│   └── libc_stubs.c       # Minimal libc for bare metal
│
├── tests/                # Test files (organized)
│   ├── holyc/           # .hc test programs
│   ├── c/               # C test programs
│   └── scripts/         # Shell scripts
│
├── docs/                # Generated documentation (180+ files)
├── backup/              # Backup versions of files
│
└── TempleOS Source (Original)
    ├── 0000Boot/        # TempleOS boot files
    ├── Kernel/          # TempleOS kernel
    ├── Compiler/        # Original HolyC compiler
    ├── Apps/            # TempleOS applications
    └── ...
```

## Features

### ✅ Fully Working
- **Arithmetic:** `+`, `-`, `*`, `/`, `%` (modulo)
- **Comparisons:** `<`, `>`, `<=`, `>=`, `==`, `!=`
- **Literals:** Integers, hex (0x...), strings
- **Variables:** Global and local variables
- **Control Flow:** `while` loops, `if/else`
- **REPL:** Interactive programming environment

### ✅ Modulo Operator - NEWLY IMPLEMENTED
```holyc
17 % 5;  → 0x2 (2) ✅
100 % 7; → 0x2 (2) ✅
```

Uses RISC-V M extension `rem` instruction (funct3=6).

### ⚠️ In Progress
- **Function Calls:** Definitions compile, calls return 0 (debugging)
- **9+ Parameters:** Code complete, untested
- **If/Else False Branch:** Needs two-pass assembly

## Building

```bash
cd bootstrap
make -f Makefile.repl
```

## Running

```bash
cd bootstrap  
qemu-system-riscv64 -M virt -bios none -kernel repl.elf -nographic
```

## Examples

```holyc
# Arithmetic with modulo
42;                    → 0x2a
10+20*2;              → 0x32  
100/4;                → 0x19
17 % 5;               → 0x2

# Function definitions (compile successfully)
I64 Simple() { return 42; }
I64 Add(I64 a, I64 b) { return a + b; }
I64 Gcd(I64 a, I64 b) { 
  while (b != 0) { 
    I64 temp; 
    temp = b; 
    b = a % b; 
    a = temp; 
  } 
  return a; 
}
```

## Architecture

### Compilation Flow
1. **Lexer** (`lexer.c`) → Tokens
2. **Parser** (`parser.c`) → IC (Intermediate Code) chain  
3. **Compiler** (`compiler.c`) → RISC-V machine code
4. **Runtime** (bare metal) → Execute on QEMU

### IC Operations Implemented
- Arithmetic: ADD, SUB, MUL, DIV, MOD
- Comparison: LESS, GREATER, LESS_EQU, GREATER_EQU, EQU_EQU, NOT_EQU
- Control: BR_ZERO, JMP, LABEL
- Functions: ENTER, LEAVE, CALL, RET
- Memory: LEA (load effective address), DEREF, ASSIGN
- Misc: IMM_I64, RBP, PUSH_RES

### RISC-V Code Generation
- Multi-pass compilation for label resolution
- Stack-based expression evaluation
- GCC-compatible calling convention
- Proper frame pointer management

## Implementation Status

**Completed This Session:**
- ✅ Modulo operator (`%`) - fully tested
- ✅ All comparison operators - implemented
- ✅ IC_LEA for local variables - added
- ✅ Code cleanup and organization
- ✅ Git repository setup

**Known Issues:**
- ⚠️ Function calls return 0 (exe_addr mechanism)
- ⚠️ Forward label references (needs two-pass fix)

## Requirements

- RISC-V GCC toolchain: `riscv64-unknown-elf-gcc`
- QEMU: `qemu-system-riscv64`

## License

Based on TempleOS source code (Public Domain)

## Testing

```bash
# Run all tests
cd tests/scripts
./comprehensive_test.sh   # If available

# Individual tests
cd bootstrap
echo "42;" | qemu-system-riscv64 -M virt -bios none -kernel repl.elf -nographic
```
