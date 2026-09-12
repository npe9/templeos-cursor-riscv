# Documentation index

Topic map for the TempleOS → RISC-V tree. Prefer these pages over anything under
[`archive/`](archive/README.md) (session dumps; often wrong — gitignored, not in the
active index).

**Product:** RISC-V TempleOS / HolyC (boards via Kconfig). Emulator jobs are the CI harness —
see [CI](#build--ci--ops--verification) and [PLATFORM.md](../templeos-riscv/PLATFORM.md).

| Jump | Topics |
|------|--------|
| [Start](#start-here) | [Architecture](#architecture--layout--self-host) · [REPL / console](#repl--console--uart) · [Debugger](#debugger--csr--traps) |
| | [Filesystems](#filesystems--export--9p) · [Drivers / boards](#drivers--platforms--boards) · [Build / CI / ops](#build--ci--ops--verification) |
| | [Tutorials](#tutorials--pedagogy) · [Specs / gaps](#specs--gaps--drafts) · [Language / IDE](#language--ide--tools) |

---

## Start here

| Doc | Blurb |
|-----|--------|
| [../README.md](../README.md) | Project entry, honest status, quick start |
| [tutorials/getting-started.md](tutorials/getting-started.md) | First REPL / tutorial steps |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Build / test norms; self-contained repo |
| [../AGENTS.md](../AGENTS.md) | Lean make-target cheat sheet for coding agents |
| [LAYOUT.md](LAYOUT.md) | Source-tree map (`host/` / bootstrap / TempleOS / `tos/`) |

---

## Architecture / layout / self-host

| Doc | Blurb |
|-----|--------|
| [ARCHITECTURE.md](ARCHITECTURE.md) | Host compiler, REPL, Kernel, guest Cmp, self-host map |
| [LAYOUT.md](LAYOUT.md) | Directory roles; what stays TempleOS-shaped |
| [SELF_HOST.md](SELF_HOST.md) | Guest self-host / remote recompile (zero guest C; Mac AOT stays bootstrap) |
| [../templeos-riscv/COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md) | Guest `Compiler_RV` / phase3 |
| [../templeos-riscv/TOS_X86_PARITY.md](../templeos-riscv/TOS_X86_PARITY.md) | x86 ↔ RV subsystem map |
| [../templeos-riscv/README.md](../templeos-riscv/README.md) | C loader image + Kconfig tree |
| [../bootstrap/README.md](../bootstrap/README.md) | Bare-metal REPL / bootstrap |
| [../bootstrap/hc_repl/README.md](../bootstrap/hc_repl/README.md) | Transitional Mac-AOT `hc_repl` (do not grow `jit.hc`) |
| [../host/README.md](../host/README.md) | Host `holyc-riscv` sources |

**Honest status (short):** Guest self-host is the product DoD ([SELF_HOST.md](SELF_HOST.md)). Host `holyc-riscv` is required AOT bootstrap. Guest `Compiler_RV` is the language destination. Classic UART REPL: **`make hc-repl`**. Legacy `worry_dream` C guest is **deleted**. Ordered remaining work: [GAPS.md](GAPS.md).

---

## REPL / console / UART

| Doc | Blurb |
|-----|--------|
| [REPL.md](REPL.md) | Interactive HolyC: `Src` / Vi / Fmt / MemMap |
| [REPL_FUNS.md](REPL_FUNS.md) | Adam/DocTerm cmdline → UART REPL catalog + DolDoc→ANSI map |
| [UART.md](UART.md) | UART primer (history, framing/FIFOs, flow-control concepts + this repo) |
| [CONSOLE.md](CONSOLE.md) | UART console wishlist audit (TTY / framing / dbg / 9P — have·partial·missing) |
| [DOLDOC_VT.md](DOLDOC_VT.md) | DolDoc on a VT100 / curses terminal — present the WinMgr cell grid as ANSI (`kernel-vt-smoke` green under QEMU; untried on a real terminal) |
| [FLOW_CONTROL.md](FLOW_CONTROL.md) | FC ops sheet (XON/XOFF shipped; RTS/CTS stub; primer → UART.md) |
| [BAREMETAL.md](BAREMETAL.md) | FPGA OpenOCD + bare QEMU; bootloader / firmware / split images |

---

## Debugger / CSR / traps

| Doc | Blurb |
|-----|--------|
| [DEBUGGER.md](DEBUGGER.md) | UART debugger dig-down (Regs / Bp / StkRep; watch/step WIP) |
| [tutorials/part-a/README.md](tutorials/part-a/README.md) | ISA labs including CSR / traps (`A05_…`) |
| [DATASHEET.md](DATASHEET.md) | Datasheet bitfield decode (`DsDecode`) |

---

## Filesystems / export / 9P

| Doc | Blurb |
|-----|--------|
| [NINEP.md](NINEP.md) | 9P / virtfs remote FS (NineExport; prefer over terminal bulk) |
| [PATHS.md](PATHS.md) | TempleOS `::`/`A:` vs UART memfs vs host `/…` namespaces |
| [FILE_EXPORT.md](FILE_EXPORT.md) | Export files from a running guest |
| [MEMFS_LOG.md](MEMFS_LOG.md) | Memfs change journal / epochs (design → export) |

---

## Drivers / platforms / boards

Board-local docs stay under `templeos-riscv/`; this index points by topic.

| Doc | Blurb |
|-----|--------|
| [DRIVERS.md](DRIVERS.md) | HolyC driver survey (UART / timer / PLIC / virtio / …) |
| [../templeos-riscv/PLATFORM.md](../templeos-riscv/PLATFORM.md) | Board ports + CI emulator targets (virt, sifive_u, …) |
| [../templeos-riscv/KCONFIG.md](../templeos-riscv/KCONFIG.md) | Platform Kconfig tutorial (`menuconfig`) |
| [../templeos-riscv/BOARD_FB.md](../templeos-riscv/BOARD_FB.md) | Framebuffer / Gr / Win interactive (incl. macOS) |
| [../templeos-riscv/RV32.md](../templeos-riscv/RV32.md) | RV32 / ILP32 port plan |
| [MULTIARCH.md](MULTIARCH.md) | Multi-arch port plan (ARM / PPC / …) |

---

## Build / CI / ops / verification

| Doc | Blurb |
|-----|--------|
| [CI.md](CI.md) | What CI runs, local mirrors, doc-only skips |
| [../tests/README.md](../tests/README.md) | Test matrix (targets ↔ CI jobs) |
| [../tests/REGRESSION.md](../tests/REGRESSION.md) | REPL honesty gate / regression |
| [OPS.md](OPS.md) | Operate-through / recovery (SafeMode, export, known-good pins) |
| [VERIFICATION.md](VERIFICATION.md) | Formal verification plan (slice proofs; not full OS) |
| [spec/p0_rv_i.md](spec/p0_rv_i.md) | P0 `RvI` model notes |
| [../verify/README.md](../verify/README.md) | Verify tree / `make verify-p0` |

---

## Tutorials / pedagogy

| Doc | Blurb |
|-----|--------|
| [tutorials/README.md](tutorials/README.md) | Curriculum TOC (executable HolyC labs) |
| [tutorials/getting-started.md](tutorials/getting-started.md) | How to run the first lab |
| [tutorials/part-a/README.md](tutorials/part-a/README.md) | Part A — RISC-V ISA |
| [tutorials/part-b/README.md](tutorials/part-b/README.md) | Part B — CSAPP-shaped |
| [tutorials/part-c/README.md](tutorials/part-c/README.md) | Part C — Beck-shaped |

Chapter bodies: `bootstrap/seed/tutorials/*.hc` → memfs `/Tutorials/`.

---

## Specs / gaps / drafts

| Doc | Blurb |
|-----|--------|
| [GAPS.md](GAPS.md) | Ordered gap-fill plan (wave lanes) |
| [A3_FLIP_DRAFT.md](A3_FLIP_DRAFT.md) | G7 flip draft — **applied**; kept as the record of how the flip and the `worry_dream` delete were done |
| [RISCV_PORT_PLAN.md](RISCV_PORT_PLAN.md) | Older port-plan notes *(historical)* |
| [MULTIARCH.md](MULTIARCH.md) | Forward multi-arch sketch |
| [../templeos-riscv/RV32.md](../templeos-riscv/RV32.md) | RV32 plan |

---

## Language / IDE / tools

| Doc | Blurb |
|-----|--------|
| [HOLYC_IMPLEMENTATION_STATUS.md](HOLYC_IMPLEMENTATION_STATUS.md) | Language / feature surface |
| [IDE.md](IDE.md) | IDE expected behaviors (Vi / Edit / Src / Man) |
| [DATASHEET.md](DATASHEET.md) | `DsDecode` bitfield helper |
| [../tools/README.md](../tools/README.md) | Packers / generators |

---

## Layout pointers

| Path | Role |
|------|------|
| `host/` | Host HolyC → RISC-V compiler (`make` → `holyc-riscv`) |
| `Kernel/` `Compiler/` `Adam/` | TempleOS HolyC trees (do not mass-rename) |
| `tos/` | Upstream TempleOS ISO/home reference (`StartOS`, `Apps`, `Doc`, …) |
| `bootstrap/` | Bare-metal REPL + transitional `hc_repl/`; junk in `bootstrap/archive/` |
| `templeos-riscv/` | C loader image + Kconfig + board docs |
| `tests/` | Compliance, oracles, smokes, regression |
| `tools/` | Packers / generators; `tools/legacy/` = old root utilities |
| `docs/archive/` | Non-canonical session notes (gitignored) |
| `verify/` | Formal-verification slices |

Full map: [LAYOUT.md](LAYOUT.md).
