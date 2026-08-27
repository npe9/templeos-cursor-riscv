# Makefile for Cicl→RISC-V Compiler

CC = gcc
# glibc: strdup and other POSIX.1-2008 APIs need a feature macro under -std=c11 (fixes Linux CI).
CFLAGS = -std=c11 -Wall -Wextra -O2 -g -D_DEFAULT_SOURCE
RISCV_CC = riscv64-unknown-elf-gcc
RISCV_OBJDUMP = riscv64-unknown-elf-objdump
QEMU = qemu-riscv64

# Compiler sources (compiler_helper.c provides StrPrintF for lexer/preprocessor)
COMPILER_SOURCES = lexer.c parser.c compiler.c hash_table.c compiler_helper.c main_stub.c
COMPILER_HEADERS = holyc_compiler.h holy_api.h
COMPILER_BIN = holyc-riscv

# Test programs
TEST_SOURCES = $(wildcard tests/*.hc)

.PHONY: all clean test validator help cicl-riscv ci compliance compliance-exec exec-oracle lint-sh syntax-sh qemu-integration repl-smoke kernel-print-smoke kernel-puts-smoke kernel-boot-smoke kernel-calc-smoke kernel-sched-smoke kernel-timer-smoke kernel-preempt-smoke kernel-crit-smoke kernel-sleep-smoke kernel-uartirq-smoke kernel-monitor-smoke kernel-blk-smoke kernel-fs-smoke kernel-shell-smoke kernel-ctask-smoke coverage templeos-riscv templeos-smoke

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

# How much of the TempleOS tree compiles (project builds with all errors, then per file)
coverage: $(COMPILER_BIN)
	@chmod +x tests/scripts/coverage_templeos.sh
	@tests/scripts/coverage_templeos.sh

# Bare-metal REPL (bootstrap/Makefile.repl) under QEMU: function calls across statements etc.
repl-smoke:
	@chmod +x tests/scripts/run_repl_smoke.sh
	@tests/scripts/run_repl_smoke.sh

# UART oracles (tests/exec), TempleOS/RISC-V QEMU smoke, REPL smoke — same as CI after compile-compliance
qemu-integration: $(COMPILER_BIN)
	@$(MAKE) exec-oracle
	@$(MAKE) templeos-smoke
	@$(MAKE) kernel-print-smoke
	@$(MAKE) kernel-puts-smoke
	@$(MAKE) kernel-boot-smoke
	@$(MAKE) kernel-calc-smoke
	@$(MAKE) kernel-sched-smoke
	@$(MAKE) kernel-timer-smoke
	@$(MAKE) kernel-preempt-smoke
	@$(MAKE) kernel-crit-smoke
	@$(MAKE) kernel-sleep-smoke
	@$(MAKE) kernel-uartirq-smoke
	@$(MAKE) kernel-monitor-smoke
	@$(MAKE) kernel-blk-smoke
	@$(MAKE) kernel-fs-smoke
	@$(MAKE) kernel-shell-smoke
	@$(MAKE) kernel-ctask-smoke
	@$(MAKE) repl-smoke

# Compile a program that #includes the real kernel, formats with its StrPrintJoin, and prints
# over the UART under QEMU — proves compiled kernel code runs and outputs on RISC-V.
kernel-print-smoke:
	@chmod +x tests/scripts/run_kernel_print_smoke.sh
	@tests/scripts/run_kernel_print_smoke.sh

# Drive the kernel's OWN PutS (device-dispatch chain) to the UART — proves keydev dispatch runs.
kernel-puts-smoke:
	@chmod +x tests/scripts/run_kernel_puts_smoke.sh
	@tests/scripts/run_kernel_puts_smoke.sh

# Full portable boot init (RVKernelInit): float tables + bit tables + native console over UART.
kernel-boot-smoke:
	@chmod +x tests/scripts/run_kernel_boot_smoke.sh
	@tests/scripts/run_kernel_boot_smoke.sh

# Interactive kernel console: feed numbers over the UART, parse with Str2I64, print results.
kernel-calc-smoke:
	@chmod +x tests/scripts/run_kernel_calc_smoke.sh
	@tests/scripts/run_kernel_calc_smoke.sh

# Cooperative multitasking: RVSpawn/RVYield round-robin two tasks via the RVTaskSwitch context switch.
kernel-sched-smoke:
	@chmod +x tests/scripts/run_kernel_sched_smoke.sh
	@tests/scripts/run_kernel_sched_smoke.sh

# Machine-timer interrupts via a trap vector + CLINT: prove interrupt-driven execution on RISC-V.
kernel-timer-smoke:
	@chmod +x tests/scripts/run_kernel_timer_smoke.sh
	@tests/scripts/run_kernel_timer_smoke.sh

# Preemptive multitasking: two non-yielding tasks forced to interleave by the timer interrupt.
kernel-preempt-smoke:
	@chmod +x tests/scripts/run_kernel_preempt_smoke.sh
	@tests/scripts/run_kernel_preempt_smoke.sh

# Critical sections: a shared counter under preemption loses updates unless locked.
kernel-crit-smoke:
	@chmod +x tests/scripts/run_kernel_crit_smoke.sh
	@tests/scripts/run_kernel_crit_smoke.sh

# RVSleep: tasks wait N timer ticks without busy-spinning; three sleep concurrently and all wake.
kernel-sleep-smoke:
	@chmod +x tests/scripts/run_kernel_sleep_smoke.sh
	@tests/scripts/run_kernel_sleep_smoke.sh

# Interrupt-driven UART input: a fed line arrives via the PLIC external interrupt into a ring buffer.
kernel-uartirq-smoke:
	@chmod +x tests/scripts/run_kernel_uartirq_smoke.sh
	@tests/scripts/run_kernel_uartirq_smoke.sh

# Capstone: interactive monitor — a preemptive background counter + interrupt-driven commands + locks.
kernel-monitor-smoke:
	@chmod +x tests/scripts/run_kernel_monitor_smoke.sh
	@tests/scripts/run_kernel_monitor_smoke.sh

# virtio-blk persistent storage: write a marker sector, read it back, confirm it hit the disk image.
kernel-blk-smoke:
	@chmod +x tests/scripts/run_kernel_blk_smoke.sh
	@tests/scripts/run_kernel_blk_smoke.sh

# Filesystem persistence: format+create on one boot, read the files back on the next (same image).
kernel-fs-smoke:
	@chmod +x tests/scripts/run_kernel_fs_smoke.sh
	@tests/scripts/run_kernel_fs_smoke.sh

# Interactive shell: filesystem + preemptive scheduler + interrupt-driven input composed together.
kernel-shell-smoke:
	@chmod +x tests/scripts/run_kernel_shell_smoke.sh
	@tests/scripts/run_kernel_shell_smoke.sh

# Authentic task switching on the REAL kernel CTask (Fs, next_task, task_flags) — TempleOS's own model.
kernel-ctask-smoke:
	@chmod +x tests/scripts/run_kernel_ctask_smoke.sh
	@tests/scripts/run_kernel_ctask_smoke.sh

# ShellCheck on the same five scripts as the CI shellcheck job (requires shellcheck on PATH).
lint-sh:
	@command -v shellcheck >/dev/null 2>&1 || { echo 'error: install shellcheck (e.g. brew install shellcheck)' >&2; exit 1; }
	@set -e; for f in \
	  tests/scripts/run_holyc_compliance.sh \
	  tests/scripts/run_exec_oracles.sh \
	  tests/scripts/run_templeos_smoke.sh \
	  tests/scripts/run_repl_smoke.sh \
	  tests/scripts/gen_compliance_candidates.sh; do \
	  shellcheck -S error -x "$$f"; \
	done
	@echo '✓ shellcheck (CI scripts)'

# Parse-check every script under tests/scripts (no extra tools; weaker than ShellCheck).
syntax-sh:
	@set -e; for f in tests/scripts/*.sh; do bash -n "$$f"; done
	@echo '✓ bash -n (tests/scripts/*.sh)'

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
	@echo "  lint-sh       - ShellCheck CI shell scripts (needs shellcheck on PATH)"
	@echo "  syntax-sh     - bash -n on all tests/scripts/*.sh (no dependencies)"
	@echo "  templeos-riscv  - Build TempleOS/RISC-V kernel + default HolyC guest"
	@echo "  templeos-smoke  - QEMU smoke (ORACLE) for default + selfhost images"
	@echo "  validator   - Build instruction encoder validator (optional; not in tree by default)"
	@echo "  validate    - Run validator (optional; needs validator.c)"
	@echo "  test        - Quick compile smoke test"
	@echo "  clean       - Clean build artifacts"
	@echo ""
	@echo "Usage:"
	@echo "  make                         # Build holyc-riscv"
	@echo "  make ci                      # Full compliance + QEMU (like GitHub Actions)"
	@echo "  make compliance              # Full compliance tests"
	@echo "  make validate                # Validate RISC-V encoding (if validator.c present)"
	@echo "  make test                    # Test compiler"
	@echo "  ./holyc-riscv program.hc    # Compile program"
	@echo ""
	@echo "Requirements:"
	@echo "  - GCC or Clang"
	@echo "  - riscv64-unknown-elf-gcc (optional, for verification)"
	@echo "  - qemu-system-riscv64 (optional, for exec-oracle / templeos-smoke)"
	@echo "  - python3 (optional, for templeos-riscv image build in templeos-smoke / make ci)"
	@echo "  - shellcheck (optional, for make lint-sh)"

