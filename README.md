# TempleOS HolyC Compiler for RISC-V

A from-scratch implementation of the HolyC programming language compiler targeting bare-metal RISC-V.

## Features

### ✅ Fully Working
- **Arithmetic:** `+`, `-`, `*`, `/`, `%` (modulo)
- **Comparisons:** `<`, `>`, `<=`, `>=`, `==`, `!=`
- **Expressions:** Parentheses, operator precedence
- **Functions:** 0-8 parameter functions with local variables
- **Control Flow:** `while` loops, `if/else` statements
- **REPL:** Interactive programming environment
- **Bare Metal:** Runs on QEMU RISC-V virt machine

### ⚠️ Partially Working
- **Function Calls:** Definitions work, calls return 0 (in progress)
- **9+ Parameters:** Implementation complete (untested)
- **If/Else False Branch:** Requires two-pass assembly (diagnosed)

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
42;                    → 0x2a
10+20*2;              → 0x32  
100/4;                → 0x19
17 % 5;               → 0x2

I64 Simple() { return 42; }
Simple();

I64 Add(I64 a, I64 b) { return a + b; }
Add(10, 20);
```

## Architecture

- **Lexer:** `lexer.c` - Tokenization
- **Parser:** `parser.c` - Syntax analysis and IC generation
- **Compiler:** `compiler.c` - RISC-V code generation
- **Runtime:** `bootstrap/worry_dream_repl.c` - Bare metal REPL loop
- **Hash Table:** `hash_table.c` - Symbol management

## Technical Details

- **IC Chain:** Intermediate Code representation (TempleOS-compatible)
- **Calling Convention:** RISC-V standard (args in a0-a7, stack for 8+)
- **Frame Layout:** GCC-compatible stack frames
- **Memory:** Separate code and heap allocation for bare metal

## Status

**Implemented:** Modulo operator, comparison operators, local variables, loops  
**In Progress:** Function call mechanism, 9+ parameter support  
**Planned:** Two-pass assembly for proper label resolution  

## License

Based on TempleOS source code (Public Domain)

