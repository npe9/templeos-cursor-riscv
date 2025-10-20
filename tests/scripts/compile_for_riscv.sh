#!/bin/bash
# Compile the C compiler itself to RISC-V bare metal

echo "Building HolyC compiler for RISC-V bare metal..."

# Compile compiler sources for RISC-V
riscv64-unknown-elf-gcc -march=rv64imafdc -mabi=lp64d -mcmodel=medany \
  -O2 -g -nostdlib -ffreestanding \
  -DNO_MAIN_FUNCTION \
  -c lexer.c -o bootstrap/lexer_riscv.o

riscv64-unknown-elf-gcc -march=rv64imafdc -mabi=lp64d -mcmodel=medany \
  -O2 -g -nostdlib -ffreestanding \
  -DNO_MAIN_FUNCTION \
  -c parser.c -o bootstrap/parser_riscv.o

riscv64-unknown-elf-gcc -march=rv64imafdc -mabi=lp64d -mcmodel=medany \
  -O2 -g -nostdlib -ffreestanding \
  -DNO_MAIN_FUNCTION \
  -c compiler.c -o bootstrap/compiler_riscv.o

riscv64-unknown-elf-gcc -march=rv64imafdc -mabi=lp64d -mcmodel=medany \
  -O2 -g -nostdlib -ffreestanding \
  -DNO_MAIN_FUNCTION \
  -c hash_table.c -o bootstrap/hash_riscv.o

# Rename sections to .text
for f in bootstrap/*_riscv.o; do
  riscv64-unknown-elf-objcopy --rename-section .data=.text $f
  riscv64-unknown-elf-objcopy --set-section-flags .text=contents,alloc,load,readonly,code $f
done

echo "✓ Compiler objects built for RISC-V"
