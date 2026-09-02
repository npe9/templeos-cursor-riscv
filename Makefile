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
	$(HOST_DIR)/main_stub.c
COMPILER_HEADERS = \
	$(HOST_DIR)/holyc_compiler.h \
	$(HOST_DIR)/holy_api.h \
	$(HOST_DIR)/holyc_fmt.h \
	$(HOST_DIR)/hash_table.h
COMPILER_BIN = holyc-riscv

# Test programs
TEST_SOURCES = $(wildcard tests/*.hc)

.PHONY: all clean test fmt fmt-check fmt-test asm-stress asm-prop asm-gnu-diff compiler-stress compiler-prop stress validator help cicl-riscv ci compliance compliance-exec exec-oracle lint-sh syntax-sh qemu-integration repl-smoke repl-blob repl-regression hc-repl hc-repl-smoke term-probe-pty repl-uart-echo-pty baremetal baremetal-plat baremetal-smoke firmware bios firmware-smoke bios-smoke kernel-print-smoke kernel-puts-smoke kernel-boot-smoke kernel-calc-smoke kernel-sched-smoke kernel-timer-smoke kernel-preempt-smoke kernel-crit-smoke kernel-sleep-smoke kernel-uartirq-smoke kernel-monitor-smoke kernel-blk-smoke kernel-fs-smoke kernel-shell-smoke kernel-ctask-smoke kernel-heap-smoke kernel-spawn-smoke kernel-ctask-preempt-smoke kernel-ctask-sleep-smoke kernel-selfboot-smoke kernel-redsea-smoke kernel-strprint-smoke kernel-dir-smoke kernel-fsshell-smoke kernel-load-smoke kernel-virtio-smoke kernel-virtiofs-smoke kernel-virtioirq-smoke kernel-virtioasync-smoke kernel-virtiopersist-smoke kernel-virtioexec-smoke kernel-virtioshell-smoke kernel-virtio-net-smoke kernel-virtio-input-smoke kernel-fb-smoke kernel-gr-smoke kernel-win-smoke kernel-win-interactive kernel-win-run kernel-plat-smoke kernel-plat-sifive-u-smoke kernel-plat-spike-smoke kernel-plat-matrix kernel-smp-smoke kernel-exepubs-smoke kernel-phase3-smoke coverage templeos-riscv templeos-smoke menuconfig-rv kernels list-kernels

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

# Platform Kconfig (QEMU machine / UART / CLINT / PLIC / FB / virtio) — see templeos-riscv/KCONFIG.md
menuconfig-rv:
	@$(MAKE) -C templeos-riscv menuconfig

templeos-smoke: $(COMPILER_BIN)
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
	  extra="FLASH_BASE=$${FLASH_BASE:-0x20000000} RAM_BASE=$${RAM_BASE:-0x80000000} PFLASH_SIZE=$${PFLASH_SIZE:-0x02000000}"; \
	fi; \
	$(MAKE) -C bootstrap -f Makefile.firmware firmware $$extra

firmware-smoke:
	@chmod +x tests/scripts/run_firmware_smoke.sh
	@tests/scripts/run_firmware_smoke.sh

bios-smoke:
	@chmod +x tests/scripts/run_bios_smoke.sh
	@tests/scripts/run_bios_smoke.sh

# RAM-linked bare-metal install dir (FPGA OpenOCD / qemu -bios none -kernel). See docs/BAREMETAL.md.
baremetal:
	$(MAKE) -C bootstrap -f Makefile.baremetal baremetal

baremetal-plat:
	$(MAKE) -C bootstrap -f Makefile.baremetal baremetal PAYLOAD=plat

baremetal-smoke:
	@chmod +x tests/scripts/run_baremetal_smoke.sh
	@tests/scripts/run_baremetal_smoke.sh

# Bare-metal REPL (bootstrap/Makefile.repl) under QEMU: function calls across statements etc.
repl-smoke:
	@chmod +x tests/scripts/run_repl_smoke.sh
	@tests/scripts/run_repl_smoke.sh

# Rebuild REPL boot runtime snapshot (concat seeds → boot_blob_embed.h + AOT validate).
# After editing bootstrap/seed/*.hc, run this (or just rebuild repl.elf — Makefile.repl depends on it).
repl-blob: $(COMPILER_BIN)
	@$(MAKE) -C bootstrap -f Makefile.repl boot_blob_embed.h HOLYC_HOST=../holyc-riscv
	@echo "✓ repl boot blob ready (bootstrap/boot_blob_embed.h)"

# Mac-built HolyC AOT REPL (no C guest runtime / no host slots). See bootstrap/hc_repl/README.md.
hc-repl:
	@$(MAKE) -C bootstrap/hc_repl all

# Same image as hc-repl; name mirrors legacy bootstrap/repl.elf for the HolyC-only path.
repl-holyc: hc-repl

repl-holyc-smoke: hc-repl-smoke

hc-repl-smoke:
	@chmod +x tests/scripts/run_hc_repl_smoke.sh
	@tests/scripts/run_hc_repl_smoke.sh

# Hard REPL gate: Src must open Vi (rejects "Src: wrote Name.hc" stub), FnSize>0, Man/SrcFile, trap…
# See tests/REGRESSION.md — prefer this over trusting smoke alone for editor/srcmap claims.
repl-regression:
	@chmod +x tests/scripts/run_repl_regression.sh
	@tests/scripts/run_repl_regression.sh

# PTY + mock CPR: TermProbe must leave 80x24 (piped smoke cannot; host TTY answers DSR).
term-probe-pty:
	@chmod +x tests/scripts/run_term_probe_pty.sh
	@tests/scripts/run_term_probe_pty.sh

# Paced PTY typing: one keystroke → one echo (16550 LSR/RBR × nested-IRQ race in uart_hw_drain).
repl-uart-echo-pty:
	@chmod +x tests/scripts/run_repl_uart_echo_pty.sh
	@tests/scripts/run_repl_uart_echo_pty.sh

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
	@$(MAKE) kernel-virtiofs-smoke
	@$(MAKE) kernel-virtioirq-smoke
	@$(MAKE) kernel-virtioasync-smoke
	@$(MAKE) kernel-virtiopersist-smoke
	@$(MAKE) kernel-virtioexec-smoke
	@$(MAKE) kernel-virtioshell-smoke
	@$(MAKE) kernel-virtio-net-smoke
	@$(MAKE) kernel-virtio-input-smoke
	@$(MAKE) kernel-virtio-9p-smoke
	@$(MAKE) kernel-fb-smoke
	@$(MAKE) kernel-gr-smoke
	@$(MAKE) kernel-win-smoke
	@$(MAKE) kernel-win-interactive
	@$(MAKE) kernel-plat-smoke
	@$(MAKE) kernel-exepubs-smoke
	@$(MAKE) kernel-exepubs-fundef-smoke
	@$(MAKE) kernel-phase3-smoke
	@$(MAKE) hc-repl-smoke
	@$(MAKE) repl-smoke
	@$(MAKE) repl-regression
	@$(MAKE) repl-9p-smoke
	@$(MAKE) term-probe-pty
	@$(MAKE) repl-uart-echo-pty

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

kernel-virtiofs-smoke:
	@chmod +x tests/scripts/run_kernel_virtiofs_smoke.sh
	@tests/scripts/run_kernel_virtiofs_smoke.sh

kernel-virtioirq-smoke:
	@chmod +x tests/scripts/run_kernel_virtioirq_smoke.sh
	@tests/scripts/run_kernel_virtioirq_smoke.sh

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

kernel-virtio-input-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_input_smoke.sh
	@tests/scripts/run_kernel_virtio_input_smoke.sh

kernel-virtio-9p-smoke:
	@chmod +x tests/scripts/run_kernel_virtio_9p_smoke.sh
	@tests/scripts/run_kernel_virtio_9p_smoke.sh

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

# TempleOS-style text_base WinMgr on RVFb (bordered windows → ramfb; UART hash).
kernel-win-smoke:
	@chmod +x tests/scripts/run_kernel_win_smoke.sh
	@tests/scripts/run_kernel_win_smoke.sh

# Interactive WinMgr ELF + headless UART proof (paint + virtio-input).
# Human cocoa: make kernel-win-run
kernel-win-interactive:
	@chmod +x tests/scripts/run_kernel_win_interactive.sh
	@tests/scripts/run_kernel_win_interactive.sh

# One-command interactive desktop (cocoa on macOS / sdl elsewhere; ESC quits).
kernel-win-run:
	@chmod +x tests/scripts/run_kernel_win_interactive.sh
	@RVWIN_HOLD=1 RVWIN_DISPLAY=auto tests/scripts/run_kernel_win_interactive.sh

# Multi-kernel: one plat-demo ELF (+ config snapshot) per Kconfig machine.
# Artifacts: build/kernels/<machine>/plat.elf and build/exec/<machine>_plat.elf
# Global .config / RVAutoConf.HH is restored after each build (see build_kernel_plat.sh).
KERNEL_BUILD_MACHINES := virt sifive_u spike shakti_c sifive_e \
	microchip_icicle xiangshan amd_microblaze_v
# opentitan / none / host: SKIP in build script (rv32 / empty / stub).

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
	    virt) note="CI smoke (-M virt)" ;; \
	    sifive_u) note="board smoke (-M sifive_u)" ;; \
	    spike) note="HTIF smoke (-M spike)" ;; \
	    sifive_e) note="build-only (DTIM too small to run)" ;; \
	    shakti_c) note="build-only (UART stub; smoke SKIP)" ;; \
	    microchip_icicle) note="build-only (needs hss.bin; smoke SKIP)" ;; \
	    xiangshan) note="build-only (tentative; smoke SKIP)" ;; \
	    amd_microblaze_v) note="build-only (tentative; smoke SKIP)" ;; \
	    *) note="" ;; \
	  esac; \
	  printf '%-22s %-10s %s\n' "$$m" "$$st" "$$note"; \
	done
	@printf '%-22s %-10s %s\n' "opentitan" "SKIP" "RV32 profile — see RV32.md"
	@printf '%-22s %-10s %s\n' "none / host" "SKIP" "not buildable plat kernels"
	@echo ""
	@echo "Also: make -C templeos-riscv qemu-args-<machine>  # no .config write"

# Kconfig platform UART/CLINT smoke (default virt; sifive_u / spike extras).
kernel-plat-smoke:
	@chmod +x tests/scripts/run_kernel_plat_smoke.sh
	@tests/scripts/run_kernel_plat_smoke.sh virt

kernel-plat-sifive-u-smoke:
	@chmod +x tests/scripts/run_kernel_plat_smoke.sh
	@tests/scripts/run_kernel_plat_smoke.sh sifive_u

kernel-plat-spike-smoke:
	@chmod +x tests/scripts/run_kernel_plat_smoke.sh
	@tests/scripts/run_kernel_plat_smoke.sh spike

# Honesty matrix: every known QEMU -M (OK / SKIP+why). Not in default qemu-integration.
kernel-plat-matrix:
	@chmod +x tests/scripts/run_kernel_plat_matrix.sh
	@tests/scripts/run_kernel_plat_matrix.sh

# Optional Phase G multi-hart smoke (virt -smp 2). Not in default qemu-integration.
kernel-smp-smoke:
	@chmod +x tests/scripts/run_kernel_smp_smoke.sh
	@tests/scripts/run_kernel_smp_smoke.sh

# Guest ExePutS: Kernel_RV + Compiler_RV_Body → Add(40,2) under QEMU (COMPILER_RV.md).
kernel-exepubs-smoke:
	@chmod +x tests/scripts/run_kernel_exepubs_smoke.sh
	@tests/scripts/run_kernel_exepubs_smoke.sh

# P0: ExePutS of a function def (MakeOSProbe) → 42.
kernel-exepubs-fundef-smoke:
	@chmod +x tests/scripts/run_kernel_exepubs_fundef_smoke.sh
	@tests/scripts/run_kernel_exepubs_fundef_smoke.sh

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
	@echo "  asm-gnu-diff    - HolyC vs GNU gas differential (immediates/pseudos; tests/asm/)"
	@echo "  compiler-stress - HolyC codegen semantics (curated oracles; tests/compiler/)"
	@echo "  compiler-prop   - Property-based compiler (opt-tier equivalence; tests/compiler/)"
	@echo "  stress          - asm-stress + asm-prop + asm-gnu-diff + compiler-stress + compiler-prop"
	@echo "  compliance      - Compile-only compliance (manifests)"
	@echo "  ci              - compliance, fmt-test, fmt-check, asm-stress, asm-prop, then qemu-integration"
	@echo "  compliance-exec - run_holyc_compliance.sh --exec (suites + exec oracles; no templeos-smoke)"
	@echo "  exec-oracle     - UART oracle tests only (tests/exec; needs RISC-V + qemu-system)"
	@echo "  qemu-integration - asm/compiler-stress + oracles + templeos + kernel smokes + plat-virt + phase3 + REPL"
	@echo "  repl-smoke        - bare-metal REPL language/demo smoke under QEMU (C guest + JIT)"
	@echo "  hc-repl / hc-repl-smoke - Mac-built HolyC AOT REPL ELF (no C guest runtime)"
	@echo "  repl-regression   - hard Src/Man/FnSize/trap/editor gate (see tests/REGRESSION.md)"
	@echo "  term-probe-pty    - PTY + mock CPR: TermProbe updates TermRows/TermCols"
	@echo "  repl-uart-echo-pty - paced PTY: single-echo keys + Ctrl-C (uart_hw_drain race)"
	@echo "  kernel-fb-smoke   - 32-bpp FB + QEMU ramfb (UART hash; optional display via -device ramfb)"
	@echo "  kernel-gr-smoke   - Gr*/CDC + soft term on FB (UART hash; RVGrRefresh/present)"
	@echo "  kernel-win-smoke  - TempleOS-style WinMgr windows on FB (UART hash; bordered desktop)"
	@echo "  kernel-win-interactive - win_i.elf + headless UART proof (ramfb + virtio-kbd/tablet)"
	@echo "  kernel-win-run    - one-command cocoa/sdl DocTerm desktop until ESC"
	@echo "  kernel-plat-smoke - HolyC Kconfig UART/CLINT smoke on -M virt"
	@echo "  kernel-smp-smoke  - optional multi-hart (-smp 2) Seth-style wake smoke (Phase G)"
	@echo "  kernel-virtio-net-smoke - HolyC VirtioNet TX+RX smoke (virtio-mmio)"
	@echo "  kernel-virtio-input-smoke - HolyC VirtioInput init smoke (virtio-mmio)"
	@echo "  kernel-virtio-9p-smoke - HolyC Virtio9p host virtfs read smoke (virtio-mmio)"
	@echo "  kernel-plat-sifive-u-smoke - HolyC plat smoke on -M sifive_u (PLATFORM.md)"
	@echo "  kernel-plat-spike-smoke - HolyC plat smoke on -M spike"
	@echo "  kernel-plat-matrix - every known -M: OK or SKIP+why"
	@echo "  kernels / list-kernels - multi-kernel: build/kernels/<machine>/plat.elf per defconfig"
	@echo "  kernel-<machine>  - one plat kernel (virt|sifive_u|spike|…); see list-kernels"
	@echo "  kernel-exepubs-smoke - Guest ExePutS Add(40,2) (Compiler_RV; see COMPILER_RV.md)"
	@echo "  kernel-phase3-smoke  - RVKMain phase 3: Compiler_RV + StartOS subset (UART)"
	@echo "  menuconfig-rv   - Kconfig: QEMU machine / map → Kernel/RVAutoConf.HH (templeos-riscv/KCONFIG.md)"
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

