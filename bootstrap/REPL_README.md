# TempleOS RISC-V REPL

## Overview

The TempleOS RISC-V REPL (Read-Eval-Print Loop) provides an interactive environment for executing HolyC code on RISC-V hardware. This implementation is based on the TempleOS compiler architecture and supports both expressions and function definitions.

## Features

- **Interactive Expression Evaluation**: Type HolyC expressions and see results immediately
- **Function Definitions**: Define and store functions for later use
- **RISC-V Native Code Generation**: Compiles to native RISC-V machine code
- **UART Communication**: Full UART support for input/output
- **Memory Management**: Proper heap management for REPL operations

## Building the REPL

```bash
cd bootstrap/
make -f Makefile.repl clean
make -f Makefile.repl
```

This creates `repl.elf` which can be run in QEMU.

## Running the REPL

### Using QEMU
```bash
qemu-system-riscv64 -M virt -bios none -kernel repl.elf -nographic
```

### Testing with Scripts
```bash
# Test basic expressions
./test_repl.sh

# Test simple REPL (if available)
./test_simple_repl.sh
```

## Usage Examples

### Basic Arithmetic
```
> 42;
0x000000000000002a
> 1+2+3;
0x0000000000000006
> 5*10;
0x0000000000000032
> 100/4;
0x0000000000000019
```

### Complex Expressions
```
> ((10+20)*2)-5;
0x0000000000000037
> 0xDEADBEEF;
0xffffffffdeadbeef
```

### Function Definitions
```
> I64 add(I64 a, I64 b) { return a + b; }
Function compiled successfully
> add(5, 3);
0x0000000000000008
```

## Architecture

The REPL is built on the TempleOS compiler infrastructure:

- **Lexer**: Tokenizes HolyC input
- **Parser**: Parses expressions and function definitions
- **Code Generator**: Generates RISC-V machine code
- **Memory Manager**: Handles heap allocation for compiler structures
- **UART Interface**: Provides console I/O

## Files

- `worry_dream_repl.c`: Main REPL implementation
- `simple_repl.c`: Simplified REPL for basic testing
- `repl_parser.c`: REPL-specific parsing utilities
- `Makefile.repl`: Build configuration
- `test_repl.sh`: Automated testing script

## Memory Layout

- **Code Space**: 4MB for compiled functions (never reused)
- **Heap Space**: 12MB for compiler structures (reusable)
- **Stack**: Standard RISC-V stack for execution

## Troubleshooting

### Common Issues

1. **QEMU Serial Issues**: Use `-nographic` without `-serial stdio`
2. **Memory Issues**: The REPL has built-in memory management
3. **Compilation Errors**: Check that all compiler components are built

### Debug Output

The REPL provides detailed output for debugging:
- Function compilation status
- Expression evaluation results
- Memory allocation information

## Implementation Notes

The REPL follows the TempleOS pattern from `CMain.HC`:
1. Parse input (expression or function)
2. Generate intermediate code (IC)
3. Compile to RISC-V machine code
4. Execute and return result

This ensures compatibility with the full TempleOS compiler while providing an interactive environment.
