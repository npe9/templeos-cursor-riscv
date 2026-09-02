# Tests

**Doc index:** [../docs/README.md](../docs/README.md) · **CI how-to:** [../docs/CI.md](../docs/CI.md)

## Test matrix (what runs where)

| Area | Location / target | CI job | Notes |
|------|-------------------|--------|-------|
| `bash -n` all scripts | `make syntax-sh` | **syntax-sh** | No extra tools |
| ShellCheck primary scripts | `make lint-sh` | **shellcheck** | Needs `shellcheck` |
| Host build | `make` → `holyc-riscv` | **compile-compliance** | |
| Compile compliance | `make compliance` | **compile-compliance** | TempleOS tree + parity |
| Formatter goldens | `make fmt-test` | **compile-compliance** | `tests/fmt/` |
| HolyC fmt-check | `make fmt-check` | **compile-compliance** | Enforced roots (`holyc_fmt_paths.sh`) |
| Assembler semantics | `make asm-stress` | **compile-compliance** + **qemu-integration** | `tests/asm/` (gas cross-check when toolchain present) |
| Assembler property tests | `make asm-prop` | **compile-compliance** | `tests/asm/run_asm_prop.py` (random RV64I vs Python oracle) |
| Compiler semantics | `make compiler-stress` | **qemu-integration** | Curated exec oracles + negatives ([tests/compiler/](compiler/README.md)) |
| Compiler property tests | `make compiler-prop` | **qemu-integration** | Random HolyC opt-tier equivalence under QEMU (`run_compiler_prop.py`) |
| Exec oracles | `make exec-oracle` | **qemu-integration** | `tests/exec/` |
| C-image TempleOS smoke | `make templeos-smoke` | **qemu-integration** | `templeos-riscv/` |
| Kernel UART smokes | `kernel-*-smoke` (print…virtioshell) | **qemu-integration** | See Makefile list |
| FB / Gr / Win | `kernel-fb/gr/win-smoke` | **qemu-integration** | Headless UART hash |
| Guest ExePutS / fundef | `kernel-exepubs*-smoke` | **qemu-integration** | |
| Phase3 (Compiler_RV + StartOS) | `kernel-phase3-smoke` | **qemu-integration** | [COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md) |
| Plat virt UART/CLINT | `kernel-plat-smoke` | **qemu-integration** | Kconfig HolyC drivers |
| Plat sifive_u | `kernel-plat-sifive-u-smoke` | **local only** | Restores virt defconfig after |
| Mac-AOT `hc_repl` | `hc-repl-smoke` | **qemu-integration** | Transitional bridge |
| REPL language smoke | `repl-smoke` | **qemu-integration** | |
| REPL honesty | `repl-regression` | **qemu-integration** | [REGRESSION.md](REGRESSION.md) |
| REPL 9p transport | `repl-9p-smoke` | **qemu-integration** | Virtio 9p REPL smoke |
| Term geometry PTY | `term-probe-pty` | **qemu-integration** | |
| Project coverage tally | `make coverage` | **local only** | Heavy; not a merge gate |

**Full local gate:** `make ci` (= compliance + fmt-test + fmt-check + asm-stress + asm-prop + qemu-integration; qemu-integration re-runs asm-stress with gas, `compiler-stress`, and `compiler-prop`).

**Note:** `make compliance-exec` = suites + exec oracles in one script; it does **not** run TempleOS smoke or the full `qemu-integration` list.

## Primary harnesses

| Area | Location | Make / script |
|------|----------|----------------|
| Compile compliance | `tests/holyc/compliance/` | `make compliance` → `tests/scripts/run_holyc_compliance.sh` |
| Formatter goldens | `tests/fmt/` | `make fmt-test` → `tests/scripts/run_fmt_test.sh` |
| HolyC tree fmt | enforced roots | `make fmt` / `make fmt-check` → `tests/scripts/run_fmt.sh` (paths: `holyc_fmt_paths.sh`) |
| Assembler semantics | `tests/asm/` | `make asm-stress` → `tests/scripts/run_asm_stress.sh`; `make asm-prop` → property tests |
| Compiler semantics | `tests/compiler/` | `make compiler-stress` → `tests/scripts/run_compiler_stress.sh`; `make compiler-prop` → property tests |
| Stress (both) | asm + compiler (+ property) | `make stress` |
| UART execution oracles | `tests/exec/` | `make exec-oracle` → `tests/scripts/run_exec_oracles.sh` |
| TempleOS/RISC-V QEMU smoke | `templeos-riscv/` | `make templeos-smoke` |
| Bare-metal REPL | `bootstrap/repl.elf` | `make repl-smoke` / `repl-regression` |

## Kernel / platform smokes (selected)

| Make target | Purpose | In CI? |
|-------------|---------|--------|
| `kernel-print-smoke` | `Kernel_RV` `StrPrintJoin` → UART | yes |
| `kernel-plat-smoke` | Kconfig HolyC UART+CLINT on `-M virt` | yes |
| `kernel-plat-sifive-u-smoke` | Same on `-M sifive_u` | **no** (local) |
| `kernel-fb-smoke` / `gr` / `win` | FB / Gr* / text_base WinMgr | yes |
| `kernel-exepubs-smoke` / `phase3-smoke` | Guest `ExePutS` / Cmp / StartOS | yes |

Platform tutorial: [../templeos-riscv/KCONFIG.md](../templeos-riscv/KCONFIG.md). Machines: [PLATFORM.md](../templeos-riscv/PLATFORM.md) (virt, sifive_u, amd_microblaze_v, opentitan, …).

## Scratch / legacy

`tests/scratch/legacy/` holds old root-level `test_*.hc` snippets — **not** CI. New cases go in `tests/exec/cases/` or compliance manifests.

## Shell hygiene

CI runs **syntax-sh** and **shellcheck** in parallel with **compile-compliance**; **qemu-integration** needs all three. Locally: `make syntax-sh`, `make lint-sh`.

**Doc-only pushes** (only `*.md`) **skip** CI; use **Actions → CI → Run workflow**. Contributor notes: [../AGENTS.md](../AGENTS.md), [../docs/CONTRIBUTING.md](../docs/CONTRIBUTING.md).
