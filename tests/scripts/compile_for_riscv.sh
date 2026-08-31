#!/bin/bash
# Compile the C compiler itself to RISC-V bare metal

echo "Building HolyC compiler for RISC-V bare metal..."
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
HOST="$ROOT/host"

# Compile compiler sources for RISC-V
riscv64-unknown-elf-gcc -march=rv64imafdc -mabi=lp64d -mcmodel=medany \
  -O2 -g -nostdlib -ffreestanding -I"$HOST" -I"$ROOT" \
  -DNO_MAIN_FUNCTION \
  -c "$HOST/lexer.c" -o "$ROOT/bootstrap/lexer_riscv.o"

riscv64-unknown-elf-gcc -march=rv64imafdc -mabi=lp64d -mcmodel=medany \
  -O2 -g -nostdlib -ffreestanding -I"$HOST" -I"$ROOT" \
  -DNO_MAIN_FUNCTION \
  -c "$HOST/parser.c" -o "$ROOT/bootstrap/parser_riscv.o"

riscv64-unknown-elf-gcc -march=rv64imafdc -mabi=lp64d -mcmodel=medany \
  -O2 -g -nostdlib -ffreestanding -I"$HOST" -I"$ROOT" \
  -DNO_MAIN_FUNCTION \
  -c "$HOST/compiler.c" -o "$ROOT/bootstrap/compiler_riscv.o"

riscv64-unknown-elf-gcc -march=rv64imafdc -mabi=lp64d -mcmodel=medany \
  -O2 -g -nostdlib -ffreestanding -I"$HOST" -I"$ROOT" \
  -DNO_MAIN_FUNCTION \
  -c "$HOST/hash_table.c" -o "$ROOT/bootstrap/hash_riscv.o"

# Rename sections to .text
for f in "$ROOT"/bootstrap/*_riscv.o; do
  riscv64-unknown-elf-objcopy --rename-section .data=.text "$f"
  riscv64-unknown-elf-objcopy --set-section-flags .text=contents,alloc,load,readonly,code "$f"
done

echo "Done."
