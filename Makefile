# Makefile for Cicl→RISC-V Compiler

CC = gcc
# glibc: strdup and other POSIX.1-2008 APIs need a feature macro under -std=c11 (fixes Linux CI).
CFLAGS = -std=c11 -Wall -Wextra -O2 -g -D_DEFAULT_SOURCE
RISCV_CC = riscv64-unknown-elf-gcc
RISCV_OBJDUMP = riscv64-unknown-elf-objdump
QEMU = qemu-riscv64

# Host compiler sources (see host/README.md, docs/LAYOUT.md)
HOST_DIR = host
# -I. so host/compiler.c can #include "bootstrap/holy_rt_names.h"
# -I$(HOST_DIR) for headers when sources are compiled from other dirs
CFLAGS += -I$(HOST_DIR) -I.
# compiler_helper.c provides StrPrintF for lexer/preprocessor
COMPILER_SOURCES = \
	$(HOST_DIR)/lexer.c \
	$(HOST_DIR)/parser.c \
	$(HOST_DIR)/compiler.c \
	$(HOST_DIR)/hash_table.c \
	$(HOST_DIR)/compiler_helper.c \
	$(HOST_DIR)/holyc_fmt.c \
	$(HOST_DIR)/aot_link.c \
	$(HOST_DIR)/main_stub.c
COMPILER_HEADERS = \
	$(HOST_DIR)/holyc_compiler.h \
	$(HOST_DIR)/holy_api.h \
	$(HOST_DIR)/holyc_fmt.h \
	$(HOST_DIR)/hash_table.h
COMPILER_BIN = holyc-riscv

# Test programs
TEST_SOURCES = $(wildcard tests/*.hc)

.PHONY: all clean test fmt fmt-check fmt-test asm-stress asm-prop asm-gnu-diff compiler-stress compiler-prop stress validator help cicl-riscv ci compliance compliance-exec exec-oracle lint-sh syntax-sh qemu-integration a3-flip-check repl-smoke dbg-smoke hwdbg-smoke gdb-uart-smoke trap-smoke repl-blob repl-regression repl-holyc repl-holyc-smoke repl-holyc-regression hc-repl hc-repl-smoke path-namespace-smoke term-probe-pty repl-uart-echo-pty repl-uart-xon-pty zmodem-smoke trzsz-smoke dump-changes-smoke baremetal baremetal-plat baremetal-smoke repl-payload bootloader bootloader-repl bootloader-smoke firmware bios firmware-smoke bios-smoke kernel-print-smoke kernel-puts-smoke kernel-boot-smoke kernel-calc-smoke kernel-sched-smoke kernel-timer-smoke kernel-preempt-smoke kernel-crit-smoke kernel-sleep-smoke kernel-uartirq-smoke kernel-monitor-smoke kernel-blk-smoke kernel-fs-smoke kernel-shell-smoke kernel-ctask-smoke kernel-heap-smoke kernel-spawn-smoke kernel-ctask-preempt-smoke kernel-ctask-sleep-smoke kernel-selfboot-smoke kernel-redsea-smoke kernel-strprint-smoke kernel-dir-smoke kernel-fsshell-smoke kernel-load-smoke kernel-virtio-smoke kernel-virtiofs-smoke kernel-virtioirq-smoke kernel-virtio-pci-irq-smoke kernel-virtioasync-smoke kernel-virtiopersist-smoke kernel-virtioexec-smoke kernel-virtioshell-smoke kernel-virtio-net-smoke kernel-virtio-input-smoke kernel-fb-smoke kernel-gr-smoke kernel-cdc-smoke kernel-demo-netofdots-smoke kernel-demo-blot-smoke kernel-span-smoke kernel-psalmody-smoke kernel-ode-smoke kernel-win-smoke kernel-win-interactive kernel-win-serial-smoke kernel-win-run kernel-win-rebuild kernel-plat-smoke kernel-plat-sifive-u-smoke kernel-sifive-gem-smoke kernel-plat-spike-smoke kernel-plat-matrix kernel-sifive-e-full kernel-sifive-e-full-smoke kernel-smp-smoke kernel-exepubs-smoke kernel-repl-exepubs-smoke repl-cmp repl-cmp-smoke kernel-phase3-smoke kernel-thin-loader-smoke coverage templeos-riscv templeos-smoke menuconfig-rv kernels list-kernels

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

# Golden + idempotency for holyc-riscv --fmt (tests/fmt/).
fmt-test: $(COMPILER_BIN)
	@chmod +x tests/scripts/run_fmt_test.sh
	@tests/scripts/run_fmt_test.sh

# Rewrite HolyC under enforced roots (tests/scripts/holyc_fmt_paths.sh). Like gofmt.
fmt: $(COMPILER_BIN)
	@chmod +x tests/scripts/holyc_fmt_paths.sh tests/scripts/run_fmt.sh
	@tests/scripts/run_fmt.sh

# Fail if any enforced HolyC file differs from holyc-riscv --fmt (like gofmt -l).
fmt-check: $(COMPILER_BIN)
	@chmod +x tests/scripts/holyc_fmt_paths.sh tests/scripts/run_fmt.sh
	@tests/scripts/run_fmt.sh --check

# Host assembler semantics (TryAssembleRiscV encodings vs goldens; optional gas cross-check).
asm-stress: $(COMPILER_BIN)
	@chmod +x tests/scripts/run_asm_stress.sh
	@tests/scripts/run_asm_stress.sh

# Property-based assembler semantics (random RV64I vs Python oracle; tests/asm/).
asm-prop: $(COMPILER_BIN)
	@chmod +x tests/scripts/run_asm_prop.sh
	@tests/scripts/run_asm_prop.sh

# Optional P0 verification: RvI / OP-IMM I-type model ≡ riscv_oracle (NOT in make ci).
.PHONY: verify-p0
verify-p0:
	@mkdir -p build/verify/p0_rv_i
	@python3 verify/p0_rv_i/run_p0.py --build-dir build/verify/p0_rv_i
	@python3 verify/p0_rv_i/run_p0.py --build-dir build/verify/p0_rv_i --seed-bug
	@echo "✓ verify-p0 (OK-PATH + SEED-BUG demo)"

# Differential assembler tests: holyc-riscv --asm-dump vs GNU gas (immediates/pseudos).
asm-gnu-diff: $(COMPILER_BIN)
	@chmod +x tests/scripts/run_asm_gnu_diff.sh
	@tests/scripts/run_asm_gnu_diff.sh

# Host HolyC→RISC-V codegen semantics (curated exec oracles + negatives + soft patterns).
compiler-stress: $(COMPILER_BIN)
	@chmod +x tests/scripts/run_compiler_stress.sh
	@tests/scripts/run_compiler_stress.sh

# Property-based compiler semantics: random HolyC vs opt-tier equivalence (QEMU).
compiler-prop: $(COMPILER_BIN)
	@chmod +x tests/scripts/run_compiler_prop.sh
	@tests/scripts/run_compiler_prop.sh

# Assembler + compiler stress suites (see tests/asm/, tests/compiler/).
stress: $(COMPILER_BIN)
	@$(MAKE) asm-stress
	@$(MAKE) asm-prop
	@$(MAKE) asm-gnu-diff
	@$(MAKE) compiler-stress
	@$(MAKE) compiler-prop

# Same stages as GitHub Actions: compile compliance, then QEMU (exec oracles + TempleOS smoke).
ci: $(COMPILER_BIN)
	@$(MAKE) compliance
	@$(MAKE) fmt-test
	@$(MAKE) fmt-check
	@$(MAKE) asm-stress
	@$(MAKE) asm-prop
	@$(MAKE) qemu-integration

compliance-exec: $(COMPILER_BIN)
	@tests/scripts/run_holyc_compliance.sh --suite all --exec

exec-oracle: $(COMPILER_BIN)
	@chmod +x tests/scripts/run_exec_oracles.sh
	@tests/scripts/run_exec_oracles.sh

# TempleOS/RISC-V OS tree (separate from compiler sources; see templeos-riscv/README.md)
templeos-riscv: $(COMPILER_BIN)
	@$(MAKE) -C templeos-riscv image

# Platform Kconfig — Linux mconf + lxdialog (scripts/kconfig). See templeos-riscv/KCONFIG.md
.PHONY: menuconfig menuconfig-rv
menuconfig menuconfig-rv:
	@$(MAKE) -C templeos-riscv menuconfig

templeos-smoke: $(COMPILER_BIN)
	@# PR2 scaffolding (docs/SELF_HOST.md A4): default CI still builds C tos-rv.elf.
	@# Future: skip templeos-riscv/kernel/*.c when HOLYC_PLAT_ONLY=1 or after HolyC
	@# plat/phase3 ORACLE replaces this smoke — do not remove while qemu-integration needs it.
	@chmod +x tests/scripts/run_templeos_smoke.sh
	@tests/scripts/run_templeos_smoke.sh

# How much of the TempleOS tree compiles (project builds with all errors, then per file)
coverage: $(COMPILER_BIN)
	@chmod +x tests/scripts/coverage_templeos.sh
	@tests/scripts/coverage_templeos.sh

# Firmware / BIOS image: flash head @ 0x20000000 copies REPL (or plat) payload to RAM;
# also emits templeos-bios.elf for qemu -bios (RAM-loaded payload).
# See bootstrap/Makefile.firmware and templeos-riscv/PLATFORM.md § Firmware.
# When templeos-riscv/.config selects OUTPUT_FORMAT_FIRMWARE, pass FLASH_BASE/RAM_BASE.
firmware bios:
	@kcfg="$(CURDIR)/templeos-riscv/include/generated/kconfig.mk"; \
	extra=; \
	if [ -f "$$kcfg" ]; then . "$$kcfg"; \
	  ram="$${RAM_BASE:-$${ENTRY_POINT:-0x80000000}}"; \
	  extra="FLASH_BASE=$${FLASH_BASE:-0x20000000} RAM_BASE=$$ram PFLASH_SIZE=$${PFLASH_SIZE:-0x02000000}"; \
	fi; \
	$(MAKE) -C bootstrap -f Makefile.firmware firmware $$extra

firmware-smoke:
	@chmod +x tests/scripts/run_firmware_smoke.sh
	@tests/scripts/run_firmware_smoke.sh

bios-smoke:
	@chmod +x tests/scripts/run_bios_smoke.sh
	@tests/scripts/run_bios_smoke.sh

# RAM-linked bare-metal install dir (FPGA OpenOCD / qemu -bios none -kernel). See docs/BAREMETAL.md.
# Legacy C guest (worry_dream) removed — product HolyC payload is `make repl-payload`.
# `make baremetal` without PAYLOAD builds plat; for REPL use `make repl-payload`.
baremetal:
	$(MAKE) -C bootstrap -f Makefile.baremetal baremetal PAYLOAD=plat

baremetal-plat:
	$(MAKE) -C bootstrap -f Makefile.baremetal baremetal PAYLOAD=plat

baremetal-smoke:
	@chmod +x tests/scripts/run_baremetal_smoke.sh
	@tests/scripts/run_baremetal_smoke.sh

# Split bootloader (HolyC AOT) + HolyC REPL blob. See docs/BAREMETAL.md § Split.
# Overrides: BOOT_MODE=jump|copy BOOTLOADER_BASE=… ENTRY_POINT=… (or Kconfig BOOT_SPLIT).
# Guest images: holyc-riscv only — no riscv64-*-gcc/ld/objcopy for boot.bin / payload blob.
bootloader:
	$(MAKE) -C bootstrap -f Makefile.bootloader bootloader

# HolyC REPL flat blob as split-boot payload (build/hc_repl.blob.bin).
repl-payload:
	@$(MAKE) -C . holyc-riscv
	$(MAKE) -C bootstrap/hc_repl blob
	@mkdir -p build/baremetal
	@cp -f build/hc_repl.blob.bin build/baremetal/repl.bin
	@echo "✓ repl-payload (HolyC): build/baremetal/repl.bin ← hc_repl.blob.bin"

bootloader-repl: repl-payload bootloader
	@echo "✓ bootloader-repl: build/bootloader/boot.bin + build/hc_repl.blob.bin (HolyC)"

bootloader-smoke:
	@chmod +x tests/scripts/run_bootloader_smoke.sh
	@tests/scripts/run_bootloader_smoke.sh

# Legacy C guest (worry_dream) deleted — use repl-holyc-smoke / trap-smoke / dbg on HolyC path.
repl-smoke:
	@echo "error: repl-smoke retired (worry_dream deleted); use: make repl-holyc-smoke" >&2
	@exit 2

dbg-smoke:
	@echo "error: dbg-smoke retired with worry_dream C guest; use HolyC REPL / docs/DEBUGGER.md" >&2
	@exit 2

hwdbg-smoke:
	@echo "error: hwdbg-smoke retired with worry_dream C guest; use HolyC REPL / docs/DEBUGGER.md" >&2
	@exit 2

# Guest GDB RSP over UART (GdbStub) — raw UART until mux ch2; not qemu -gdb.
gdb-uart-smoke:
	@chmod +x tests/scripts/run_gdb_uart_smoke.sh
	@tests/scripts/run_gdb_uart_smoke.sh

trap-smoke:
	@chmod +x tests/scripts/run_trap_smoke.sh
	@tests/scripts/run_trap_smoke.sh

# Rebuild REPL boot runtime snapshot (concat seeds → boot_blob_embed.h + AOT validate).
# After editing bootstrap/seed/*.hc, run this (boot_blob_embed.h via Makefile.repl).
repl-blob: $(COMPILER_BIN)
	@$(MAKE) -C bootstrap -f Makefile.repl boot_blob_embed.h HOLYC_HOST=../holyc-riscv
	@echo "✓ repl boot blob ready (bootstrap/boot_blob_embed.h)"

# Product HolyC AOT REPL (no C guest runtime / no host slots). See docs/SELF_HOST.md.
hc-repl:
	@$(MAKE) -C bootstrap/hc_repl all

# Same image as hc-repl; name mirrors legacy bootstrap/repl.elf for the HolyC-only path.
repl-holyc: hc-repl

repl-holyc-smoke: hc-repl-smoke

hc-repl-smoke:
	@chmod +x tests/scripts/run_hc_repl_smoke.sh
	@tests/scripts/run_hc_repl_smoke.sh
	@chmod +x tests/scripts/run_hc_repl_quit_smoke.sh
	@tests/scripts/run_hc_repl_quit_smoke.sh

# SiFive test finisher only (Quit/Exit/Fail @ MEM_TEST on -M virt).
hc-repl-quit-smoke:
	@chmod +x tests/scripts/run_hc_repl_quit_smoke.sh
	@tests/scripts/run_hc_repl_quit_smoke.sh

.PHONY: hc-repl-quit-smoke

# G28: host A:/ + ::/ include + __DIR__ → / (tos-stripped)
path-namespace-smoke: $(COMPILER_BIN)
	@chmod +x tests/scripts/run_path_namespace_smoke.sh
	@tests/scripts/run_path_namespace_smoke.sh

.PHONY: path-namespace-smoke

# HolyC honesty subset (expand toward full repl-regression; see SELF_HOST.md flip criteria).
repl-holyc-regression:
	@chmod +x tests/scripts/run_repl_holyc_regression.sh
	@tests/scripts/run_repl_holyc_regression.sh

# G7 readiness: HolyC smoke+regression+repl-cmp → READY/NOT READY (A3 flip applied).
# See docs/A3_FLIP_DRAFT.md / docs/SELF_HOST.md.
a3-flip-check:
	@chmod +x tests/scripts/run_a3_flip_check.sh
	@tests/scripts/run_a3_flip_check.sh

# Legacy C guest honesty gate retired with worry_dream. Primary: repl-holyc-regression.
repl-regression:
	@echo "error: repl-regression retired (worry_dream deleted); use: make repl-holyc-regression" >&2
	@exit 2

# PTY + mock CPR: TermProbe must leave 80x24 (piped smoke cannot; host TTY answers DSR).
term-probe-pty:
	@chmod +x tests/scripts/run_term_probe_pty.sh
	@tests/scripts/run_term_probe_pty.sh

# Paced PTY typing: one keystroke → one echo (16550 LSR/RBR × nested-IRQ race in uart_hw_drain).
repl-uart-echo-pty:
	@chmod +x tests/scripts/run_repl_uart_echo_pty.sh
	@tests/scripts/run_repl_uart_echo_pty.sh

# Software XON/XOFF: host Ctrl-S pauses bulk TX until Ctrl-Q (virt 16550).
repl-uart-xon-pty:
	@chmod +x tests/scripts/run_repl_uart_xon_pty.sh
	@tests/scripts/run_repl_uart_xon_pty.sh

.PHONY: repl-uart-xon-pty

# Guest ZMODEM send + host Python rz (PTY). Encoder selftest first (no QEMU).
zmodem-smoke:
	@chmod +x tests/scripts/run_zmodem_export_smoke.sh
	@tests/scripts/run_zmodem_export_smoke.sh

.PHONY: zmodem-smoke

# Guest native trzsz (tsz) send + host Python client (QEMU stdio).
trzsz-smoke:
	@chmod +x tests/scripts/run_trzsz_export_smoke.sh
	@tests/scripts/run_trzsz_export_smoke.sh

.PHONY: trzsz-smoke

# DumpChanges UART manifest + DumpFile bodies; P4 rename; P5 wrap (legacy full REPL).
dump-changes-smoke:
	@chmod +x tests/scripts/run_dump_changes_smoke.sh
	@tests/scripts/run_dump_changes_smoke.sh

.PHONY: dump-changes-smoke

# Last-good ELF hash pins (local; see build/known-good/README.md + docs/OPS.md).
known-good-pin:
	@chmod +x tests/scripts/pin_known_good.sh
	@tests/scripts/pin_known_good.sh

known-good-check:
	@chmod +x tests/scripts/pin_known_good.sh
	@tests/scripts/pin_known_good.sh --check

.PHONY: known-good-pin known-good-check

# UART oracles (tests/exec), TempleOS/RISC-V QEMU smoke, REPL smoke — same as CI after compile-compliance
qemu-integration: $(COMPILER_BIN)
	@$(MAKE) asm-stress
	@$(MAKE) compiler-stress
	@$(MAKE) compiler-prop
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
	@$(MAKE) kernel-heap-smoke
	@$(MAKE) kernel-spawn-smoke
	@$(MAKE) kernel-ctask-preempt-smoke
	@$(MAKE) kernel-ctask-sleep-smoke
	@$(MAKE) kernel-selfboot-smoke
	@$(MAKE) kernel-redsea-smoke
	@$(MAKE) kernel-strprint-smoke
	@$(MAKE) kernel-dir-smoke
	@$(MAKE) kernel-fsshell-smoke
	@$(MAKE) kernel-load-smoke
	@$(MAKE) kernel-virtio-smoke
	@$(MAKE) kernel-virtio-pci-smoke
	@$(MAKE) kernel-virtiofs-smoke
	@$(MAKE) kernel-virtioirq-smoke
	@$(MAKE) kernel-virtio-pci-irq-smoke
	@$(MAKE) kernel-virtioasync-smoke
	@$(MAKE) kernel-virtiopersist-smoke
	@$(MAKE) kernel-virtioexec-smoke
	@$(MAKE) kernel-virtioshell-smoke
	@$(MAKE) kernel-virtio-net-smoke
	@$(MAKE) kernel-virtio-net-pci-smoke
	@$(MAKE) kernel-virtio-input-smoke
	@$(MAKE) kernel-virtio-9p-smoke
	@$(MAKE) kernel-virtio-9p-pci-smoke
	@$(MAKE) kernel-virtio-console-smoke
	@$(MAKE) kernel-virtio-balloon-smoke
	@$(MAKE) kernel-virtio-scsi-smoke
	@$(MAKE) kernel-fb-smoke
	@$(MAKE) kernel-gr-smoke
	@$(MAKE) kernel-cdc-smoke
	@$(MAKE) kernel-demo-netofdots-smoke
	@$(MAKE) kernel-demo-blot-smoke
	@$(MAKE) kernel-span-smoke
	@$(MAKE) kernel-psalmody-smoke
	@$(MAKE) kernel-ode-smoke
	@$(MAKE) kernel-win-smoke
	@$(MAKE) kernel-win-interactive
	@$(MAKE) kernel-win-serial-smoke
	@$(MAKE) kernel-plat-smoke
	@$(MAKE) kernel-sifive-gem-smoke
	@$(MAKE) kernel-rtc-smoke
	@$(MAKE) kernel-fwcfg-smoke
	@$(MAKE) kernel-exepubs-smoke
	@$(MAKE) kernel-exepubs-fundef-smoke
	@$(MAKE) kernel-repl-exepubs-smoke
	@$(MAKE) kernel-phase3-smoke
	@$(MAKE) kernel-thin-loader-smoke
	# Track A (docs/SELF_HOST.md A3 Done): HolyC-only honesty gates.
	# repl-cmp-smoke already ran above as kernel-repl-exepubs-smoke → build/repl-cmp.elf.
	# Legacy repl-smoke/repl-regression and zmodem-smoke are local-only (not required).
	@$(MAKE) repl-holyc-smoke
	@$(MAKE) repl-holyc-regression
	@$(MAKE) bootloader-smoke
	@$(MAKE) repl-9p-smoke
	@$(MAKE) term-probe-pty
	@$(MAKE) repl-uart-echo-pty
	@$(MAKE) repl-uart-xon-pty
	@$(MAKE) dump-changes-smoke

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

# The kernel's own CAlloc/MSize on a real CHeapCtrl via a HolyC MAlloc/Free (overriding the runtime).
kernel-heap-smoke:
	@chmod +x tests/scripts/run_kernel_heap_smoke.sh
	@tests/scripts/run_kernel_heap_smoke.sh

# TempleOS's OWN Spawn() creates a real CTask (real TaskInit) and the kernel's Yield() runs it.
kernel-spawn-smoke:
	@chmod +x tests/scripts/run_kernel_spawn_smoke.sh
	@tests/scripts/run_kernel_spawn_smoke.sh

# Timer-driven preemption of real CTasks via the kernel's own Yield() (TempleOS's IntSwapTask model).
kernel-ctask-preempt-smoke:
	@chmod +x tests/scripts/run_kernel_ctask_preempt_smoke.sh
	@tests/scripts/run_kernel_ctask_preempt_smoke.sh

# Cooperative sleep on real CTasks: tasks set CTask.wake_jiffy and the kernel's own Yield() skips
# them until the (mtime-derived) jiffy clock reaches their wake time; all-asleep -> scheduler idles.
kernel-ctask-sleep-smoke:
	@chmod +x tests/scripts/run_kernel_ctask_sleep_smoke.sh
	@tests/scripts/run_kernel_ctask_sleep_smoke.sh

# The kernel booting itself: RVKMain() (Kernel/KBootRV.HC) sets up the heap, creates Adam, and
# Spawns + schedules the first task with the kernel's own code. The demo's main() is only RVKMain().
kernel-selfboot-smoke:
	@chmod +x tests/scripts/run_kernel_selfboot_smoke.sh
	@tests/scripts/run_kernel_selfboot_smoke.sh

# The kernel's OWN RedSea filesystem on a BDT_RAM disk: BlkDevAdd auto-formats (RedSeaFmt), then
# FileWrite + RedSeaFileRead round-trip two files — all real Kernel/BlkDev/*.HC, no device driver.
kernel-redsea-smoke:
	@chmod +x tests/scripts/run_kernel_redsea_smoke.sh
	@tests/scripts/run_kernel_redsea_smoke.sh

# HolyC implicit-print idiom `"fmt",args;` against the kernel's varargs Print (the string-statement
# lowering must set up the HolyC varargs ABI the same way an explicit Print() call does).
kernel-strprint-smoke:
	@chmod +x tests/scripts/run_kernel_strprint_smoke.sh
	@tests/scripts/run_kernel_strprint_smoke.sh

# Directory operations (DirMk / FilesFind / Cd) on the kernel's own RedSea FS over a RAM disk.
kernel-dir-smoke:
	@chmod +x tests/scripts/run_kernel_dir_smoke.sh
	@tests/scripts/run_kernel_dir_smoke.sh

# Interactive shell over the UART on the kernel's own RedSea FS (dir/mkdir/cd/write/cat), as a real
# CTask the kernel scheduled. A scripted session is piped in; exit terminates it.
kernel-fsshell-smoke:
	@chmod +x tests/scripts/run_kernel_fsshell_smoke.sh
	@tests/scripts/run_kernel_fsshell_smoke.sh

# Load and run a program off the RedSea disk: a precompiled position-independent blob is written to
# the FS, read back, and executed with RVRunBlob (import trailer resolved in place). The first step
# of the Load/ExeFile path. The smoke compiles the guest program (prog_hello.hc) at test time.
kernel-load-smoke:
	@chmod +x tests/scripts/run_kernel_load_smoke.sh
	@tests/scripts/run_kernel_load_smoke.sh

kernel-virtio-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_smoke.sh
	@tests/scripts/run_kernel_virtio_smoke.sh

kernel-virtio-pci-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_pci_smoke.sh
	@tests/scripts/run_kernel_virtio_pci_smoke.sh

kernel-virtiofs-smoke:
	@chmod +x tests/scripts/run_kernel_virtiofs_smoke.sh
	@tests/scripts/run_kernel_virtiofs_smoke.sh

kernel-virtioirq-smoke:
	@chmod +x tests/scripts/run_kernel_virtioirq_smoke.sh
	@tests/scripts/run_kernel_virtioirq_smoke.sh

kernel-virtio-pci-irq-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_pci_irq_smoke.sh
	@tests/scripts/run_kernel_virtio_pci_irq_smoke.sh

kernel-virtioasync-smoke:
	@chmod +x tests/scripts/run_kernel_virtioasync_smoke.sh
	@tests/scripts/run_kernel_virtioasync_smoke.sh

kernel-virtiopersist-smoke:
	@chmod +x tests/scripts/run_kernel_virtiopersist_smoke.sh
	@tests/scripts/run_kernel_virtiopersist_smoke.sh

kernel-virtioexec-smoke:
	@chmod +x tests/scripts/run_kernel_virtioexec_smoke.sh
	@tests/scripts/run_kernel_virtioexec_smoke.sh

kernel-virtioshell-smoke:
	@chmod +x tests/scripts/run_kernel_virtioshell_smoke.sh
	@tests/scripts/run_kernel_virtioshell_smoke.sh

kernel-virtio-net-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_net_smoke.sh
	@tests/scripts/run_kernel_virtio_net_smoke.sh

kernel-virtio-net-pci-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_net_pci_smoke.sh
	@tests/scripts/run_kernel_virtio_net_pci_smoke.sh

kernel-virtio-input-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_input_smoke.sh
	@tests/scripts/run_kernel_virtio_input_smoke.sh

kernel-virtio-9p-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_9p_smoke.sh
	@tests/scripts/run_kernel_virtio_9p_smoke.sh

kernel-virtio-9p-pci-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_9p_pci_smoke.sh
	@tests/scripts/run_kernel_virtio_9p_pci_smoke.sh

kernel-virtio-console-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_console_smoke.sh
	@tests/scripts/run_kernel_virtio_console_smoke.sh

kernel-virtio-balloon-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_balloon_smoke.sh
	@tests/scripts/run_kernel_virtio_balloon_smoke.sh

kernel-virtio-scsi-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_scsi_smoke.sh
	@tests/scripts/run_kernel_virtio_scsi_smoke.sh

repl-9p-smoke:
	@chmod +x tests/scripts/run_repl_9p_smoke.sh
	@tests/scripts/run_repl_9p_smoke.sh

# Native 32-bpp FB + QEMU ramfb (UART hash oracle; does not require a display window).
kernel-fb-smoke:
	@chmod +x tests/scripts/run_kernel_fb_smoke.sh
	@tests/scripts/run_kernel_fb_smoke.sh

# Thin Gr*/CDC + soft term on RVFb (UART hash; WinMgr-lite refresh via RVGrRefresh).
kernel-gr-smoke:
	@chmod +x tests/scripts/run_kernel_gr_smoke.sh
	@tests/scripts/run_kernel_gr_smoke.sh

# DCNew/GrBlot + Sprite3 subset on CRVDC (P4 widen; Demo blot/SpriteRaw).
kernel-cdc-smoke:
	@chmod +x tests/scripts/run_kernel_cdc_smoke.sh
	@tests/scripts/run_kernel_cdc_smoke.sh

# Stock Demo/Graphics/NetOfDots.HC on RV Gr (CDC/GrLine step/PressAKey soft).
kernel-demo-netofdots-smoke:
	@chmod +x tests/scripts/run_kernel_demo_netofdots_smoke.sh
	@tests/scripts/run_kernel_demo_netofdots_smoke.sh

# Stock Demo/Graphics/Blot.HC (FloodFill3/brush + SettingsPush/WinMax/PopUpColor/Refresh).
kernel-demo-blot-smoke:
	@chmod +x tests/scripts/run_kernel_demo_blot_smoke.sh
	@tests/scripts/run_kernel_demo_blot_smoke.sh

# Stock Apps/Span Load (Cd(__DIR__) + Bridge/FloodFill + GetMsg/PopUpFileName).
kernel-span-smoke:
	@chmod +x tests/scripts/run_kernel_span_smoke.sh
	@tests/scripts/run_kernel_span_smoke.sh

# Psalmody API + host $IB staff embed (Note2Ona/Menu/Tempo; fixture bins).
kernel-psalmody-smoke:
	@chmod +x tests/scripts/run_kernel_psalmody_smoke.sh
	@tests/scripts/run_kernel_psalmody_smoke.sh

# Lite RVODE mass-spring tick + pause (P5 stretch; UART oracle).
kernel-ode-smoke:
	@chmod +x tests/scripts/run_kernel_ode_smoke.sh
	@tests/scripts/run_kernel_ode_smoke.sh

# TempleOS-style text_base WinMgr on RVFb (bordered windows → ramfb; UART hash).
kernel-win-smoke:
	@chmod +x tests/scripts/run_kernel_win_smoke.sh
	@tests/scripts/run_kernel_win_smoke.sh

# --- win_i.elf / win_hold.elf: incremental AOT compile + link ---
# Units: build/aot/win/{kernel_i|kernel_hold,compiler}.bin → link → blob → ELF.
# Unchanged units skip parse/optimize/emit; only relink when an input .bin is newer.
# Force full rebuild: make kernel-win-rebuild  (rm ELFs + aot units)
WIN_I_ELF := build/exec/win_i.elf
WIN_HOLD_ELF := build/exec/win_hold.elf
WIN_AOT_DIR := build/aot/win
WIN_AOT_COMPILER_BIN := $(WIN_AOT_DIR)/compiler.bin
WIN_AOT_KERNEL_I_BIN := $(WIN_AOT_DIR)/kernel_i.bin
WIN_AOT_KERNEL_HOLD_BIN := $(WIN_AOT_DIR)/kernel_hold.bin
WIN_AOT_BLOB_I := $(WIN_AOT_DIR)/win_i.blob.bin
WIN_AOT_BLOB_HOLD := $(WIN_AOT_DIR)/win_hold.blob.bin
WIN_AOT_CASE_I := tests/exec/aot/win_i.hc
WIN_AOT_CASE_HOLD := tests/exec/aot/win_hold.hc
WIN_AOT_COMPILER_SRC := tests/exec/aot/win_compiler.PRJ
WIN_AOT_SCRIPT := tests/scripts/run_kernel_win_interactive.sh
WIN_AOT_HARNESS := \
	tests/exec/harness/crt0.S \
	tests/exec/harness/oracle_out.c \
	tests/exec/harness/link_exepubs.ld \
	bootstrap/holy_rt.h

# First build writes .d; subsequent builds use precise include graphs.
-include $(WIN_AOT_DIR)/compiler.d
-include $(WIN_AOT_DIR)/kernel_i.d
-include $(WIN_AOT_DIR)/kernel_hold.d

$(WIN_AOT_DIR):
	@mkdir -p $(WIN_AOT_DIR)

$(WIN_AOT_COMPILER_BIN): $(WIN_AOT_COMPILER_SRC) $(COMPILER_BIN) | $(WIN_AOT_DIR)
	@echo "holyc: compile unit compiler ← $(WIN_AOT_COMPILER_SRC)"
	@HOLYC_INCLUDE_ROOT="$(CURDIR)" ./$(COMPILER_BIN) $(WIN_AOT_COMPILER_SRC) \
		-o $@ --deps $(WIN_AOT_DIR)/compiler.d --map $(WIN_AOT_DIR)/compiler.map

$(WIN_AOT_KERNEL_I_BIN): $(WIN_AOT_CASE_I) tests/exec/cases/kernel_win_interactive.hc $(COMPILER_BIN) | $(WIN_AOT_DIR)
	@echo "holyc: compile unit kernel_i ← $(WIN_AOT_CASE_I)"
	@HOLYC_INCLUDE_ROOT="$(CURDIR)" ./$(COMPILER_BIN) $(WIN_AOT_CASE_I) \
		-o $@ --deps $(WIN_AOT_DIR)/kernel_i.d --map $(WIN_AOT_DIR)/kernel_i.map

$(WIN_AOT_KERNEL_HOLD_BIN): $(WIN_AOT_CASE_HOLD) tests/exec/cases/kernel_win_interactive.hc $(COMPILER_BIN) | $(WIN_AOT_DIR)
	@echo "holyc: compile unit kernel_hold ← $(WIN_AOT_CASE_HOLD)"
	@HOLYC_INCLUDE_ROOT="$(CURDIR)" ./$(COMPILER_BIN) $(WIN_AOT_CASE_HOLD) \
		-o $@ --deps $(WIN_AOT_DIR)/kernel_hold.d --map $(WIN_AOT_DIR)/kernel_hold.map

$(WIN_AOT_BLOB_I): $(WIN_AOT_KERNEL_I_BIN) $(WIN_AOT_COMPILER_BIN) $(COMPILER_BIN)
	@echo "holyc: link $(WIN_AOT_BLOB_I)"
	@./$(COMPILER_BIN) --link -o $@ --base 0x80800000 \
		$(WIN_AOT_KERNEL_I_BIN) $(WIN_AOT_COMPILER_BIN)

$(WIN_AOT_BLOB_HOLD): $(WIN_AOT_KERNEL_HOLD_BIN) $(WIN_AOT_COMPILER_BIN) $(COMPILER_BIN)
	@echo "holyc: link $(WIN_AOT_BLOB_HOLD)"
	@./$(COMPILER_BIN) --link -o $@ --base 0x80800000 \
		$(WIN_AOT_KERNEL_HOLD_BIN) $(WIN_AOT_COMPILER_BIN)

$(WIN_I_ELF): $(WIN_AOT_BLOB_I) $(WIN_AOT_SCRIPT) $(WIN_AOT_HARNESS)
	@mkdir -p build/exec
	@chmod +x $(WIN_AOT_SCRIPT)
	@RVWIN_HOLD=0 RVWIN_BUILD_ONLY=1 RVWIN_SKIP_AOT=1 RVWIN_BLOB=$(WIN_AOT_BLOB_I) \
		RVWIN_OUT=$(WIN_I_ELF) $(WIN_AOT_SCRIPT)

$(WIN_HOLD_ELF): $(WIN_AOT_BLOB_HOLD) $(WIN_AOT_SCRIPT) $(WIN_AOT_HARNESS)
	@mkdir -p build/exec
	@chmod +x $(WIN_AOT_SCRIPT)
	@RVWIN_HOLD=1 RVWIN_BUILD_ONLY=1 RVWIN_SKIP_AOT=1 RVWIN_BLOB=$(WIN_AOT_BLOB_HOLD) \
		RVWIN_OUT=$(WIN_HOLD_ELF) $(WIN_AOT_SCRIPT)

# Force AOT even if mtimes look current (e.g. after tool-chain swap without touch).
kernel-win-rebuild:
	@rm -f $(WIN_I_ELF) $(WIN_HOLD_ELF) build/exec/win_serial.elf
	@rm -rf $(WIN_AOT_DIR)
	@$(MAKE) $(WIN_I_ELF) $(WIN_HOLD_ELF)

# Interactive WinMgr ELF + headless UART proof (paint + virtio-input).
# Human cocoa: make kernel-win-run
kernel-win-interactive: $(WIN_I_ELF) $(WIN_HOLD_ELF)
	@chmod +x tests/scripts/run_kernel_win_interactive.sh
	@RVWIN_HOLD=0 RVWIN_SKIP_BUILD=1 RVWIN_OUT=$(WIN_I_ELF) \
		tests/scripts/run_kernel_win_interactive.sh

# UART dig-down while WinMgr hold: help/regs/q needles on -serial
kernel-win-serial-smoke: $(WIN_HOLD_ELF)
	@chmod +x tests/scripts/run_kernel_win_serial_smoke.sh
	@tests/scripts/run_kernel_win_serial_smoke.sh

# One-command interactive desktop (cocoa on macOS / sdl elsewhere; ESC quits).
# Reuses $(WIN_HOLD_ELF) when Kernel/Compiler/holyc-riscv/harness unchanged.
kernel-win-run: $(WIN_HOLD_ELF)
	@chmod +x tests/scripts/run_kernel_win_interactive.sh
	@RVWIN_HOLD=1 RVWIN_DISPLAY=auto RVWIN_SKIP_BUILD=1 RVWIN_OUT=$(WIN_HOLD_ELF) \
		tests/scripts/run_kernel_win_interactive.sh

# Multi-kernel: one plat-demo ELF (+ config snapshot) per Kconfig machine.
# Artifacts: build/kernels/<machine>/plat.elf and build/exec/<machine>_plat.elf
# Global .config / RVAutoConf.HH is restored after each build (see build_kernel_plat.sh).
KERNEL_BUILD_MACHINES := virt sifive_u spike shakti_c sifive_e \
	microchip_icicle xiangshan amd_microblaze_v opentitan visionfive2 milkv_mars
# none / host: not matrix boards (empty / not a QEMU -M) — excluded, not skip=OK.
# visionfive2 / milkv_mars: board-only (no QEMU -M) — builds/links; keep out of plat matrix.

define KERNEL_MACHINE_template
.PHONY: kernel-$(1)
kernel-$(1):
	@chmod +x tests/scripts/build_kernel_plat.sh
	@tests/scripts/build_kernel_plat.sh $(1)
endef
$(foreach m,$(KERNEL_BUILD_MACHINES),$(eval $(call KERNEL_MACHINE_template,$(m))))

.PHONY: kernels list-kernels
kernels:
	@chmod +x tests/scripts/build_kernel_plat.sh
	@set -e; for m in $(KERNEL_BUILD_MACHINES); do \
	  echo "=== building kernel-$$m ==="; \
	  tests/scripts/build_kernel_plat.sh $$m; \
	done
	@$(MAKE) list-kernels

list-kernels:
	@echo "Kconfig machines → multi-kernel layout (build/kernels/<machine>/)"
	@echo "Build:  make kernel-<machine> | make kernels"
	@echo "Smoke:  make kernel-plat-smoke | kernel-plat-sifive-u-smoke | kernel-plat-matrix"
	@echo ""
	@printf '%-22s %-10s %s\n' "machine" "artifact" "notes"
	@printf '%-22s %-10s %s\n' "-------" "--------" "-----"
	@for m in $(KERNEL_BUILD_MACHINES); do \
	  if [ -f build/kernels/$$m/plat.elf ]; then st=OK; else st=missing; fi; \
	  case $$m in \
	    virt) note="CI smoke (-M virt -bios none -kernel)" ;; \
	    sifive_u) note="board smoke (-M sifive_u -bios none -kernel)" ;; \
	    spike) note="HTIF smoke (-M spike -bios none -kernel)" ;; \
	    sifive_e) note="matrix: slim XIP plat.elf; full: make kernel-sifive-e-full-smoke" ;; \
	    shakti_c) note="smoke: -bios plat.elf (RVUartShakti)" ;; \
	    microchip_icicle) note="smoke: -bios none -kernel (no HSS)" ;; \
	    xiangshan) note="smoke: -bios plat.elf" ;; \
	    amd_microblaze_v) note="smoke: -device loader,file=ELF|bin,cpu-num=0" ;; \
	    opentitan) note="smoke: RV32 asm + RVUartIbex map (-kernel)" ;; \
	    visionfive2) note="board-only: U-Boot/OpenOCD @ 0x40200000 (no QEMU -M)" ;; \
	    milkv_mars) note="board-only: U-Boot/OpenOCD @ 0x40200000 (JH7110; no QEMU -M)" ;; \
	    *) note="" ;; \
	  esac; \
	  printf '%-22s %-10s %s\n' "$$m" "$$st" "$$note"; \
	done
	@printf '%-22s %-10s %s\n' "none / host" "excl." "not matrix boards (no CPU/RAM / not a -M)"
	@echo ""
	@echo "Also: make -C templeos-riscv qemu-args-<machine>  # no .config write"
	@echo "Board: make kernel-visionfive2-help | kernel-milkv-mars-help"

.PHONY: kernel-visionfive2-help kernel-milkv-mars-help kernel-milkv-mars
kernel-visionfive2-help:
	@chmod +x tests/scripts/visionfive2_board_help.sh
	@tests/scripts/visionfive2_board_help.sh

kernel-milkv-mars-help:
	@chmod +x tests/scripts/milkv_mars_board_help.sh
	@tests/scripts/milkv_mars_board_help.sh

# Hyphen alias for docs / muscle memory (artifact dir stays milkv_mars).
kernel-milkv-mars: kernel-milkv_mars
	@true

# Kconfig platform UART/CLINT smoke (default virt; sifive_u / spike extras).
kernel-plat-smoke:
	@chmod +x tests/scripts/run_kernel_plat_smoke.sh
	@tests/scripts/run_kernel_plat_smoke.sh virt

kernel-plat-sifive-u-smoke:
	@chmod +x tests/scripts/run_kernel_plat_smoke.sh
	@tests/scripts/run_kernel_plat_smoke.sh sifive_u

kernel-sifive-gem-smoke:
	@chmod +x tests/scripts/run_kernel_sifive_gem_smoke.sh
	@tests/scripts/run_kernel_sifive_gem_smoke.sh

kernel-plat-spike-smoke:
	@chmod +x tests/scripts/run_kernel_plat_smoke.sh
	@tests/scripts/run_kernel_plat_smoke.sh spike

# FE310 dual artifact: slim plat.elf stays matrix path; fuller Kernel_FE310.PRJ
# is XIP Kernel + DTIM bootloader (16 KiB RAM — no external DRAM). Not in qemu-integration.
kernel-sifive-e-full:
	@chmod +x tests/scripts/build_kernel_sifive_e_full.sh
	@tests/scripts/build_kernel_sifive_e_full.sh

kernel-sifive-e-full-smoke:
	@chmod +x tests/scripts/run_kernel_sifive_e_full_smoke.sh
	@tests/scripts/run_kernel_sifive_e_full_smoke.sh

# Honesty matrix: every known -M board must OK (skips not allowed).
kernel-plat-matrix:
	@chmod +x tests/scripts/run_kernel_plat_matrix.sh
	@tests/scripts/run_kernel_plat_matrix.sh

# Optional Phase G multi-hart smoke (virt -smp 2). Not in default qemu-integration.
kernel-smp-smoke:
	@chmod +x tests/scripts/run_kernel_smp_smoke.sh
	@tests/scripts/run_kernel_smp_smoke.sh

# Goldfish RTC wall-clock read (virt).
kernel-rtc-smoke:
	@chmod +x tests/scripts/run_kernel_rtc_smoke.sh
	@tests/scripts/run_kernel_rtc_smoke.sh

# QEMU fw_cfg signature + file dir (virt; no ramfb).
kernel-fwcfg-smoke:
	@chmod +x tests/scripts/run_kernel_fwcfg_smoke.sh
	@tests/scripts/run_kernel_fwcfg_smoke.sh

# Guest ExePutS: Kernel_RV + Compiler_RV_Body → Add(40,2) under QEMU (COMPILER_RV.md).
kernel-exepubs-smoke:
	@chmod +x tests/scripts/run_kernel_exepubs_smoke.sh
	@tests/scripts/run_kernel_exepubs_smoke.sh

# P0: ExePutS of a function def (MakeOSProbe) → 42.
kernel-exepubs-fundef-smoke:
	@chmod +x tests/scripts/run_kernel_exepubs_fundef_smoke.sh
	@tests/scripts/run_kernel_exepubs_fundef_smoke.sh

# A2 product compile path: Kernel_RV + Compiler_RV ExePutS UART REPL → build/repl-cmp.elf.
# Embedding full Cmp into thin repl-holyc (~288K) blows size (~1.9M); this is the converge image.
kernel-repl-exepubs-smoke:
	@chmod +x tests/scripts/run_kernel_repl_exepubs_smoke.sh
	@tests/scripts/run_kernel_repl_exepubs_smoke.sh

repl-cmp-smoke: kernel-repl-exepubs-smoke

# Build-only alias of the smoke’s install step (same ELF).
repl-cmp: kernel-repl-exepubs-smoke
	@test -f build/repl-cmp.elf && ls -lh build/repl-cmp.elf

# RVKMain phase 3: Load Compiler_RV (in-image) → StartOS subset on WinMgr/FB (COMPILER_RV.md).

# Host AOT blob → TempleOS CBinFile (TOSB + IET_IMM_I64 imports).
tools/pack_tosb: tools/pack_tosb.c
	$(CC) -O2 -Wall -o $@ $<

build/Compiler.BIN: tools/pack_tosb build/compiler_rv.blob.bin
	@if [ -f build/compiler_rv.map ]; then \
	  CINIT_OFF=$$(awk '/ CInit$$/{print $$1; exit}' build/compiler_rv.map); \
	  EXEPS_OFF=$$(awk '/ ExePutS$$/{print $$1; exit}' build/compiler_rv.map); \
	  CMP_OFF=$$(awk '/ Cmp$$/{print $$1; exit}' build/compiler_rv.map); \
	  if [ -n "$$CMP_OFF" ]; then \
	    ./tools/pack_tosb -v -e CInit:0x$$CINIT_OFF -e ExePutS:0x$$EXEPS_OFF \
	      -e Cmp:0x$$CMP_OFF build/compiler_rv.blob.bin $@; \
	  else \
	    ./tools/pack_tosb -v -e CInit:0x$$CINIT_OFF -e ExePutS:0x$$EXEPS_OFF \
	      build/compiler_rv.blob.bin $@; \
	  fi; \
	else \
	  ./tools/pack_tosb -v build/compiler_rv.blob.bin $@; \
	fi
	python3 tools/gen_cmp_imports.py

kernel-phase3-smoke:
	@chmod +x tests/scripts/run_kernel_phase3_smoke.sh
	@tests/scripts/run_kernel_phase3_smoke.sh

kernel-thin-loader-smoke:
	@chmod +x tests/scripts/run_kernel_thin_loader_smoke.sh
	@tests/scripts/run_kernel_thin_loader_smoke.sh

# ShellCheck on the same primary scripts as the CI shellcheck job (requires shellcheck on PATH).
lint-sh:
	@command -v shellcheck >/dev/null 2>&1 || { echo 'error: install shellcheck (e.g. brew install shellcheck)' >&2; exit 1; }
	@set -e; for f in \
	  tests/scripts/run_holyc_compliance.sh \
	  tests/scripts/run_exec_oracles.sh \
	  tests/scripts/run_templeos_smoke.sh \
	  tests/scripts/run_repl_smoke.sh \
	  tests/scripts/run_repl_regression.sh \
	  tests/scripts/run_fmt_test.sh \
	  tests/scripts/run_fmt.sh \
	  tests/scripts/holyc_fmt_paths.sh \
	  tests/scripts/gen_compliance_candidates.sh \
	  tests/scripts/run_asm_stress.sh \
	  tests/scripts/run_compiler_stress.sh \
	  tests/scripts/run_compiler_prop.sh; do \
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
	@$(MAKE) fmt-test
	@$(MAKE) path-namespace-smoke

# Clean build artifacts (binaries, dSYMs, build/, bootstrap objs)
clean:
	rm -f $(COMPILER_BIN) cicl-riscv validator validator.c
	rm -f holyc-riscv-dbg
	rm -f *.bin *.o *.out
	rm -rf *.dSYM
	rm -f tools/pack_tosb
	@$(MAKE) -C bootstrap -f Makefile.repl clean
	@$(MAKE) -C bootstrap -f Makefile.firmware clean
	@$(MAKE) -C bootstrap -f Makefile.baremetal clean
	@$(MAKE) -C bootstrap -f Makefile.bootloader clean
	rm -f $(HOST_DIR)/*.o
	rm -rf build/
	@echo "✓ Cleaned"

# Help
help:
	@echo "HolyC→RISC-V Compiler - Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all         - Build holyc-riscv host compiler"
	@echo "  cicl-riscv  - Symlink to holyc-riscv (legacy name)"
	@echo "  fmt             - Rewrite HolyC under enforced roots (holyc-riscv --fmt; like gofmt)"
	@echo "  fmt-check       - Fail if enforced HolyC differs from --fmt (like gofmt -l; CI)"
	@echo "  fmt-test        - Golden + idempotency for holyc-riscv --fmt (tests/fmt/)"
	@echo "  asm-stress      - Assembler semantics (TryAssembleRiscV encodings; tests/asm/)"
	@echo "  asm-prop        - Property-based assembler (random RV64I vs oracle; tests/asm/)"
	@echo "  verify-p0       - Optional: RvI/OP-IMM model ≡ riscv_oracle (+ seeded-bug demo; NOT in ci)"
	@echo "  asm-gnu-diff    - HolyC vs GNU gas differential (immediates/pseudos; tests/asm/)"
	@echo "  compiler-stress - HolyC codegen semantics (curated oracles; tests/compiler/)"
	@echo "  compiler-prop   - Property-based compiler (opt-tier equivalence; tests/compiler/)"
	@echo "  stress          - asm-stress + asm-prop + asm-gnu-diff + compiler-stress + compiler-prop"
	@echo "  compliance      - Compile-only compliance (manifests)"
	@echo "  ci              - compliance, fmt-test, fmt-check, asm-stress, asm-prop, then qemu-integration"
	@echo "  compliance-exec - run_holyc_compliance.sh --exec (suites + exec oracles; no templeos-smoke)"
	@echo "  exec-oracle     - UART oracle tests only (tests/exec; needs RISC-V + qemu-system)"
	@echo "  qemu-integration - asm/compiler-stress + oracles + templeos + kernel smokes + plat/phase3 + HolyC REPL honesty (A3 Done)"
	@echo "  repl-holyc / repl-holyc-smoke - HolyC memfs/Dir REPL (ExePutS→Jit bridge; no C guest)"
	@echo "  repl-cmp / repl-cmp-smoke - A2/A3 required: Kernel+Compiler_RV ExePutS (build/repl-cmp.elf; =kernel-repl-exepubs-smoke)"
	@echo "  repl-holyc-regression - primary HolyC honesty gate (memfs/Dir/Src-dump/JIT language)"
	@echo "  a3-flip-check     - G7 readiness: holyc-smoke+regression+repl-cmp → READY/NOT READY"
	@echo "  bootloader-smoke  - HolyC pflash boot → HolyC REPL blob (product split-boot)"
	@echo "  repl-smoke        - RETIRED (worry_dream deleted); use repl-holyc-smoke"
	@echo "  hc-repl / hc-repl-smoke - alias of repl-holyc* (do not grow jit.hc)"
	@echo "  hc-repl-quit-smoke - Quit/Exit/Fail via SiFive test @ MEM_TEST (virt)"
	@echo "  path-namespace-smoke - G28 host A:/ + ::/ include + __DIR__ /tos-strip"
	@echo "  repl-regression   - RETIRED (worry_dream deleted); use repl-holyc-regression"
	@echo "  term-probe-pty    - PTY + mock CPR: TermProbe updates TermRows/TermCols"
	@echo "  repl-uart-echo-pty - paced PTY: single-echo keys + Ctrl-C (uart_hw_drain race)"
	@echo "  repl-uart-xon-pty  - PTY: host Ctrl-S/Ctrl-Q pauses/resumes bulk UART TX"
	@echo "  zmodem-smoke     - guest ZMODEM send + host Python rz (PTY; local only, G11 waived)"
	@echo "  trzsz-smoke      - guest native trzsz (tsz) send + host Python client (local)"
	@echo "  dump-changes-smoke - DumpChanges UART + rename journal + wrap"
	@echo "  gdb-uart-smoke   - guest GdbStub RSP over UART (regs/mem/Z0/soft-step; not qemu -gdb)"
	@echo "  known-good-pin / known-good-check - hash last-good repl/plat ELFs (docs/OPS.md)"
	@echo "  kernel-fb-smoke   - 32-bpp FB + QEMU ramfb (UART hash; optional display via -device ramfb)"
	@echo "  kernel-gr-smoke   - Gr*/CDC + soft term on FB (UART hash; RVGrRefresh/present)"
	@echo "  kernel-cdc-smoke  - DCNew/GrBlot/FloodFill/brush + Sprite3 (Demo Blot APIs; UART hash)"
	@echo "  kernel-demo-netofdots-smoke - stock Demo/Graphics/NetOfDots.HC on RV Gr (UART hash)"
	@echo "  kernel-demo-blot-smoke - stock Demo/Graphics/Blot.HC FloodFill3/brush + Win shims"
	@echo "  kernel-span-smoke - stock Apps/Span Load + GetMsg live (Yield pump) / PopUpFileName"
	@echo "  kernel-psalmody-smoke - Psalmody Load + Note2Ona/Menu/Tempo/\$IB + GetMsg live"
	@echo "  kernel-ode-smoke  - stock Demo/Games/MassSpring.HC on AMathODE_RV (RK5+ODEsUpdate)"
	@echo "  kernel-win-smoke  - TempleOS-style WinMgr windows on FB (UART hash; bordered desktop)"
	@echo "  kernel-win-interactive - win_i.elf + headless UART proof (ramfb + virtio-kbd/tablet)"
	@echo "  kernel-win-serial-smoke - WinMgr hold + serial HolyC ExePutS (1+1→ans) + crash/q"
	@echo "  kernel-win-run    - one-command cocoa/sdl DocTerm until ESC (reuses win_hold.elf if current)"
	@echo "  kernel-win-rebuild - force full AOT (rm build/aot/win + win_*.elf; recompile all units)"
	@echo "  kernel-plat-smoke - HolyC Kconfig UART/CLINT smoke on -M virt"
	@echo "  kernel-rtc-smoke  - Goldfish RTC wall-clock on virt"
	@echo "  kernel-fwcfg-smoke - QEMU fw_cfg signature + file dir on virt"
	@echo "  kernel-smp-smoke  - optional multi-hart (-smp 2) Seth-style wake smoke (Phase G)"
	@echo "  kernel-virtio-net-smoke - HolyC VirtioNet TX+RX smoke (virtio-mmio)"
	@echo "  kernel-virtio-pci-smoke - HolyC VirtioBlk MMIO→PCI fallback (virtio-blk-pci)"
	@echo "  kernel-virtio-pci-irq-smoke - PCI INTx + trap MEIE ISR ACK"
	@echo "  kernel-virtio-net-pci-smoke - HolyC VirtioNet TX+RX over virtio-net-pci"
	@echo "  kernel-virtio-input-smoke - HolyC VirtioInput init smoke (virtio-mmio)"
	@echo "  kernel-virtio-9p-smoke - HolyC Virtio9p host virtfs read+export smoke"
	@echo "  kernel-virtio-9p-pci-smoke - HolyC Virtio9p over virtio-9p-pci queues"
	@echo "  kernel-virtio-console-smoke - HolyC VirtioConsole TX smoke (virtio-mmio)"
	@echo "  kernel-virtio-balloon-smoke - HolyC VirtioBalloon inflate/deflate smoke"
	@echo "  kernel-virtio-scsi-smoke - HolyC VirtioScsi INQUIRY+READ smoke"
	@echo "  kernel-plat-sifive-u-smoke - HolyC plat smoke on -M sifive_u (PLATFORM.md)"
	@echo "  kernel-sifive-gem-smoke - HolyC Cadence GEM TX+RX loopback on -M sifive_u"
	@echo "  kernel-plat-spike-smoke - HolyC plat smoke on -M spike"
	@echo "  kernel-plat-matrix - every known -M board: must OK (skips not allowed)"
	@echo "  kernel-sifive-e-full-smoke - FE310 DTIM bootloader → XIP Kernel (dual vs slim plat.elf)"
	@echo "  kernels / list-kernels - multi-kernel: build/kernels/<machine>/plat.elf per defconfig"
	@echo "  kernel-<machine>  - one plat kernel (virt|sifive_u|spike|…); see list-kernels"
	@echo "  kernel-exepubs-smoke - Guest ExePutS Add(40,2) (Compiler_RV; see COMPILER_RV.md)"
	@echo "  kernel-repl-exepubs-smoke - alias of repl-cmp-smoke (SELF_HOST.md A2)"
	@echo "  kernel-phase3-smoke  - RVKMain phase 3: Compiler_RV + StartOS subset (UART)"
	@echo "  kernel-thin-loader-smoke - virtio RedSea Load Kernel.BIN + KernelEntry handoff (G9)"
	@echo "  menuconfig      - Linux mconf (ncurses) → .config + RVAutoConf.HH (templeos-riscv/KCONFIG.md)"
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

