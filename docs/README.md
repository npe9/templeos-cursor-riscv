# Documentation index

One map for the TempleOS → RISC-V tree. Prefer these pages over anything under
[`archive/`](archive/README.md) (session dumps; often wrong).

**Product:** RISC-V TempleOS / HolyC (boards via Kconfig). Emulator jobs are the CI harness —
see [CI.md](CI.md) and [PLATFORM.md](../templeos-riscv/PLATFORM.md).

## Start here

| Doc | Topic |
|-----|--------|
| [../README.md](../README.md) | Project entry, honest status, quick start |
| [tutorials/README.md](tutorials/README.md) | **Tutorial curriculum** (executable HolyC labs: ISA → CSAPP → Beck) |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Host compiler, REPL, Kernel, guest Cmp, self-host |
| [LAYOUT.md](LAYOUT.md) | **Source-tree map** (host / bootstrap / TempleOS / `tos/`) |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Build / test norms |
| [../AGENTS.md](../AGENTS.md) | Lean make-target cheat sheet for coding agents |
| [CI.md](CI.md) | What CI runs, local mirrors, doc-only skips |
| [../tests/README.md](../tests/README.md) | **Test matrix** (targets ↔ CI jobs) |

## By topic

| Topic | Canonical doc |
|-------|----------------|
| Tutorials (SF-style HolyC labs: ISA / CSAPP / Beck) | [tutorials/README.md](tutorials/README.md) |
| Interactive REPL / Src / Vi / Fmt | [REPL.md](REPL.md) |
| Datasheet bitfield decode (`DsDecode`) | [DATASHEET.md](DATASHEET.md) |
| IDE expected behaviors (Vi / Edit / Src / Man) | [IDE.md](IDE.md) |
| REPL honesty gate | [../tests/REGRESSION.md](../tests/REGRESSION.md) |
| Language / feature surface | [HOLYC_IMPLEMENTATION_STATUS.md](HOLYC_IMPLEMENTATION_STATUS.md) |
| Platform Kconfig tutorial | [../templeos-riscv/KCONFIG.md](../templeos-riscv/KCONFIG.md) |
| Board ports + CI emulator targets | [../templeos-riscv/PLATFORM.md](../templeos-riscv/PLATFORM.md) |
| FPGA OpenOCD + bare QEMU boot | [BAREMETAL.md](BAREMETAL.md) |
| RV32 / ILP32 port plan | [../templeos-riscv/RV32.md](../templeos-riscv/RV32.md) |
| Multi-arch port plan (ARM / PPC / …) | [MULTIARCH.md](MULTIARCH.md) |
| Framebuffer / boards | [../templeos-riscv/BOARD_FB.md](../templeos-riscv/BOARD_FB.md) |
| Guest `Compiler_RV` / phase3 | [../templeos-riscv/COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md) |
| x86 ↔ RV subsystem map | [../templeos-riscv/TOS_X86_PARITY.md](../templeos-riscv/TOS_X86_PARITY.md) |
| C image bootstrap (`templeos-riscv/`) | [../templeos-riscv/README.md](../templeos-riscv/README.md) |
| Mac-AOT `hc_repl` (transitional) | [../bootstrap/hc_repl/README.md](../bootstrap/hc_repl/README.md) |
| Older port-plan notes | [RISCV_PORT_PLAN.md](RISCV_PORT_PLAN.md) *(historical)* |

## Honest status (short)

- **Host `holyc-riscv`** is the required AOT bootstrap (transitional, not “done”).
- **Guest `Compiler_RV`** + `ExePutS` / `Cmp` is the language destination ([COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md)).
- **Boards** are Kconfig ports (`sifive_u`, custom, …); CI’s default profile is the **virt** memory map for automated smokes ([PLATFORM.md](../templeos-riscv/PLATFORM.md)).
- **`bootstrap/hc_repl`** is a temporary Mac-AOT bridge — do not grow `jit.hc`.

## Layout pointers

| Path | Role |
|------|------|
| `host/` | Host HolyC → RISC-V compiler (`make` → `holyc-riscv`) |
| `Kernel/` `Compiler/` `Adam/` | TempleOS HolyC trees (do not mass-rename) |
| `tos/` | Upstream TempleOS ISO/home reference (`StartOS`, `Apps`, `Doc`, …) |
| `bootstrap/` | Bare-metal REPL (`Makefile.repl`) + transitional `hc_repl/`; junk in `archive/` |
| `templeos-riscv/` | C loader image + Kconfig |
| `tests/` | Compliance, oracles, smokes, regression |
| `tools/` | Packers / generators; `tools/legacy/` = old root utilities |
| `docs/archive/` | Non-canonical session notes (gitignored) |

Full map: [LAYOUT.md](LAYOUT.md).
