# Makefile for Cicl→RISC-V Compiler

CC = gcc
CFLAGS = -std=c11 -Wall -Wextra -O2 -g
RISCV_CC = riscv64-unknown-elf-gcc
RISCV_OBJDUMP = riscv64-unknown-elf-objdump
QEMU = qemu-riscv64

# Compiler sources
COMPILER_SOURCES = lexer.c parser.c compiler.c hash_table.c
COMPILER_HEADERS = holyc_compiler.h
COMPILER_BIN = cicl-riscv

# Test programs
TEST_SOURCES = $(wildcard tests/*.hc)

.PHONY: all clean test validator help

all: $(COMPILER_BIN) validator

# Build the compiler
$(COMPILER_BIN): $(COMPILER_SOURCES) $(COMPILER_HEADERS)
	$(CC) $(CFLAGS) -DHOLYC_STANDALONE $(COMPILER_SOURCES) -o $(COMPILER_BIN)
	@echo "✓ Built Cicl→RISC-V compiler"

# Build the validator
validator: validator.c
	$(CC) $(CFLAGS) validator.c -o validator
	@echo "✓ Built validator"

# Run validator
validate: validator
	./validator
	@echo ""
	@if command -v $(RISCV_OBJDUMP) >/dev/null 2>&1; then \
		echo "Disassembly:"; \
		$(RISCV_OBJDUMP) -D -b binary -m riscv:rv64 test_arithmetic.bin; \
	else \
		echo "Install riscv-gnu-toolchain to see disassembly"; \
	fi

# Test the compiler
test: $(COMPILER_BIN)
	@echo "Testing Cicl→RISC-V compiler..."
	@mkdir -p tests build
	@echo "I64 main() { return 42; }" > tests/simple.hc
	./$(COMPILER_BIN) tests/simple.hc -o build/simple.bin
	@if [ -f build/simple.bin ]; then \
		echo "✓ Compiled tests/simple.hc"; \
		$(RISCV_OBJDUMP) -D -b binary -m riscv:rv64 build/simple.bin 2>/dev/null || echo "  (install riscv-objdump to see disassembly)"; \
	fi

# Clean build artifacts
clean:
	rm -f $(COMPILER_BIN) validator
	rm -f validator.c
	rm -f *.bin *.o *.out
	rm -rf build/
	@echo "✓ Cleaned"

# Help
help:
	@echo "Cicl→RISC-V Compiler - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all        - Build compiler and validator"
	@echo "  validator  - Build the instruction encoder validator"
	@echo "  validate   - Run validator and show disassembly"
	@echo "  test       - Run compiler tests"
	@echo "  clean      - Clean build artifacts"
	@echo ""
	@echo "Usage:"
	@echo "  make                        # Build everything"
	@echo "  make validate               # Validate RISC-V encoding"
	@echo "  make test                   # Test compiler"
	@echo "  ./cicl-riscv program.hc    # Compile program"
	@echo ""
	@echo "Requirements:"
	@echo "  - GCC or Clang"
	@echo "  - riscv64-unknown-elf-gcc (optional, for verification)"
	@echo "  - qemu-riscv64 (optional, for execution)"

