# Makefile for Cicl→RISC-V Compiler

CC = gcc
CFLAGS = -std=c11 -Wall -Wextra -O2 -g
RISCV_CC = riscv64-unknown-elf-gcc
RISCV_OBJDUMP = riscv64-unknown-elf-objdump
QEMU = qemu-riscv64

# Compiler sources (compiler_helper.c provides StrPrintF for lexer/preprocessor)
COMPILER_SOURCES = lexer.c parser.c compiler.c hash_table.c compiler_helper.c main_stub.c
COMPILER_HEADERS = holyc_compiler.h holy_api.h
COMPILER_BIN = holyc-riscv

# Test programs
TEST_SOURCES = $(wildcard tests/*.hc)

.PHONY: all clean test validator help cicl-riscv ci compliance compliance-exec exec-oracle qemu-integration templeos-riscv templeos-smoke

all: $(COMPILER_BIN) cicl-riscv

# Backward-compatible name for scripts that still invoke cicl-riscv
cicl-riscv: $(COMPILER_BIN)
	@ln -sf $(COMPILER_BIN) cicl-riscv

# Build the compiler
$(COMPILER_BIN): $(COMPILER_SOURCES) $(COMPILER_HEADERS)
	$(CC) $(CFLAGS) -DHOLYC_STANDALONE $(COMPILER_SOURCES) -o $(COMPILER_BIN)
	@echo "✓ Built HolyC→RISC-V compiler ($(COMPILER_BIN))"

compliance: $(COMPILER_BIN)
	@tests/scripts/run_holyc_compliance.sh --suite all

# Same stages as GitHub Actions: compile compliance, then QEMU (exec oracles + TempleOS smoke).
ci: $(COMPILER_BIN)
	@$(MAKE) compliance
	@$(MAKE) qemu-integration

compliance-exec: $(COMPILER_BIN)
	@tests/scripts/run_holyc_compliance.sh --suite all --exec

exec-oracle: $(COMPILER_BIN)
	@chmod +x tests/scripts/run_exec_oracles.sh
	@tests/scripts/run_exec_oracles.sh

# TempleOS/RISC-V OS tree (separate from compiler sources; see templeos-riscv/README.md)
templeos-riscv: $(COMPILER_BIN)
	@$(MAKE) -C templeos-riscv image

templeos-smoke: $(COMPILER_BIN)
	@chmod +x tests/scripts/run_templeos_smoke.sh
	@tests/scripts/run_templeos_smoke.sh

# UART oracles (tests/exec) then TempleOS/RISC-V QEMU smoke — same as CI after compile-compliance
qemu-integration: $(COMPILER_BIN)
	@$(MAKE) exec-oracle
	@$(MAKE) templeos-smoke

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
	@echo "Testing HolyC→RISC-V compiler..."
	@mkdir -p build
	@echo 'I64 main() { return 42; }' > build/smoke.hc
	./$(COMPILER_BIN) build/smoke.hc -o build/simple.bin
	@if [ -f build/simple.bin ]; then \
		echo "✓ Compiled build/smoke.hc → build/simple.bin"; \
		$(RISCV_OBJDUMP) -D -b binary -m riscv:rv64 build/simple.bin 2>/dev/null || echo "  (install riscv-objdump to see disassembly)"; \
	fi

# Clean build artifacts
clean:
	rm -f $(COMPILER_BIN) cicl-riscv validator
	rm -f validator.c
	rm -f *.bin *.o *.out
	rm -rf build/
	@echo "✓ Cleaned"

# Help
help:
	@echo "HolyC→RISC-V Compiler - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all         - Build holyc-riscv host compiler"
	@echo "  cicl-riscv  - Symlink to holyc-riscv (legacy name)"
	@echo "  compliance      - Compile-only compliance (manifests)"
	@echo "  ci              - compliance then qemu-integration (full local mirror of GitHub CI)"
	@echo "  compliance-exec - run_holyc_compliance.sh --exec (suites + exec oracles; no templeos-smoke)"
	@echo "  exec-oracle     - UART oracle tests only (tests/exec; needs RISC-V + qemu-system)"
	@echo "  qemu-integration - exec-oracle then templeos-smoke (CI job after compile-compliance)"
	@echo "  templeos-riscv  - Build TempleOS/RISC-V kernel + default HolyC guest"
	@echo "  templeos-smoke  - QEMU smoke (ORACLE) for default + selfhost images"
	@echo "  validator   - Build the instruction encoder validator (needs validator.c)"
	@echo "  validate    - Run validator and show disassembly"
	@echo "  test        - Quick compile smoke test"
	@echo "  clean       - Clean build artifacts"
	@echo ""
	@echo "Usage:"
	@echo "  make                         # Build holyc-riscv"
	@echo "  make ci                      # Full compliance + QEMU (like GitHub Actions)"
	@echo "  make compliance              # Full compliance tests"
	@echo "  make validate                # Validate RISC-V encoding"
	@echo "  make test                    # Test compiler"
	@echo "  ./holyc-riscv program.hc    # Compile program"
	@echo ""
	@echo "Requirements:"
	@echo "  - GCC or Clang"
	@echo "  - riscv64-unknown-elf-gcc (optional, for verification)"
	@echo "  - qemu-system-riscv64 (optional, for exec-oracle / templeos-smoke)"

