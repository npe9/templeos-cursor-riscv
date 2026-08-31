# Notes for contributors and coding agents

Lean cheat sheet. Tutorials and status live under **[docs/](docs/README.md)**.

This is a **RISC-V TempleOS / HolyC** port (Kconfig boards, SiFive, …). Emulator smokes
(`qemu-integration`) are the CI harness — not the product story. Prefer board / `MEM_*` /
HolyC driver language in user-facing text.

## Build and test

| Command | Purpose |
|---------|---------|
| `make` | Host compiler `holyc-riscv` (`-D_DEFAULT_SOURCE` for glibc/`strdup` under `-std=c11`) |
| `make test` | Tiny AOT smoke + `fmt-test` |
| `make fmt` / `make fmt-check` | Rewrite / gate HolyC under enforced roots (`holyc-riscv --fmt`, like gofmt) |
| `make ci` | `compliance` + `fmt-test` + `fmt-check` + `qemu-integration` (mirrors Actions after shell jobs) |
| `make syntax-sh` / `make lint-sh` | `bash -n` all scripts / ShellCheck primary scripts |
| `make repl-smoke` / `make repl-regression` | REPL UART smoke / honesty gate — [tests/REGRESSION.md](tests/REGRESSION.md) |
| `make kernel-plat-smoke` | HolyC Kconfig UART+CLINT on CI default board (in `qemu-integration`) |
| `make kernel-phase3-smoke` | Guest Compiler_RV + StartOS subset — [COMPILER_RV.md](templeos-riscv/COMPILER_RV.md) |
| `make hc-repl` / `hc-repl-smoke` | Transitional Mac-AOT guest — **do not grow `jit.hc`** |
| `make coverage` | Project-mode compile tally (local; not CI) |
| `make menuconfig-rv` | Platform Kconfig — [KCONFIG.md](templeos-riscv/KCONFIG.md) |

Formatter (gofmt-style): `holyc-riscv --fmt` on edited `.hc`/`.HC`/`.HH` — do not hand-fight style. Roots: `tests/scripts/holyc_fmt_paths.sh`. Goldens: `make fmt-test`. Rule: `.cursor/rules/holyc-fmt.mdc`.

Debug (host build): `HOLYC_TRACE=1`, `HOLYC_TOKTRACE=<substr>`. Stale `repl.elf` / harness objects often look like universal CRASH/hang — rebuild after `host/holyc_compiler.h` / `bootstrap/holy_rt*.h` changes.

Kernel FB/Gr/Win interactive (macOS): see [BOARD_FB.md](templeos-riscv/BOARD_FB.md). Codegen bisect: `HOLYC_NO_OPT=1` / `HOLYC_NO_TIER2=1` / `HOLYC_NO_PROMOTE=1` / `HOLYC_O1_MODE`.

## CI

- Jobs: `syntax-sh` ‖ `shellcheck` ‖ `compile-compliance` → `qemu-integration`. Details: [docs/CI.md](docs/CI.md), matrix: [tests/README.md](tests/README.md).
- **Markdown-only** pushes skip CI (`paths-ignore`); use **Actions → CI → Run workflow** to force a run.
- `concurrency: cancel-in-progress` — an older run may show **cancelled** while tip is green.

## Docs and layout

| Doc | Topic |
|-----|--------|
| [docs/LAYOUT.md](docs/LAYOUT.md) | Source-tree map (`host/` / `tos/` / TempleOS) |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | System map / self-host |
| [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) | Norms |
| [docs/REPL.md](docs/REPL.md) | Interactive HolyC |
| [docs/HOLYC_IMPLEMENTATION_STATUS.md](docs/HOLYC_IMPLEMENTATION_STATUS.md) | Language surface |
| [templeos-riscv/PLATFORM.md](templeos-riscv/PLATFORM.md) | Board ports + CI emulator targets (virt, sifive_u, …) |

Host compiler: `host/` (`lexer.c`, `parser.c`, …). TempleOS port trees: `Kernel/`, `Compiler/`, `Adam/`, `Demo/` (do not rename). ISO/home reference: `tos/` (`StartOS`, `Apps`, `Doc`, …). Scratch: `tests/scratch/`. Session notes: `docs/archive/` (ignored).

## Remotes

`origin` may be a local path mirror; **`github`** → GitHub. Prefer `git push github archive` if `origin` rejects pushes.
