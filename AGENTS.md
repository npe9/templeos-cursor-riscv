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
| `make asm-stress` / `compiler-stress` / `stress` | Assembler encodings + curated codegen oracles — [tests/asm/](tests/asm/README.md), [tests/compiler/](tests/compiler/README.md) |
| `make ci` | `compliance` + `fmt-test` + `fmt-check` + `asm-stress` + `asm-prop` + `qemu-integration` (mirrors Actions after shell jobs) |
| `make syntax-sh` / `make lint-sh` | `bash -n` all scripts / ShellCheck primary scripts |
| `make repl-smoke` / `make repl-regression` | **Deprecated** legacy C guest — **local only** / scheduled delete (A3 Done; not in `qemu-integration`) — [tests/REGRESSION.md](tests/REGRESSION.md) |
| `make repl-holyc` / `repl-holyc-smoke` / `repl-holyc-regression` | Product HolyC REPL path (CI honesty) — [docs/SELF_HOST.md](docs/SELF_HOST.md) |
| `make a3-flip-check` | G7 readiness — HolyC smoke+regression+repl-cmp → READY/NOT READY — [docs/A3_FLIP_DRAFT.md](docs/A3_FLIP_DRAFT.md) |
| `make kernel-plat-smoke` | HolyC Kconfig UART+CLINT on CI default board (in `qemu-integration`) |
| `make kernel-plat-matrix` | Every known `-M` plat smoke — **skips are not allowed** |
| `make kernels` / `list-kernels` | Multi-kernel: `build/kernels/<machine>/plat.elf` per defconfig |
| `make kernel-win-rebuild` | Force full win AOT: `rm -rf build/aot/win` + rebuild `win_*.elf` (all units) |
| `make kernel-win-interactive` / `kernel-win-run` | Incremental AOT: compile changed units only, then link — [OPS.md](docs/OPS.md) § Host AOT |
| `make hc-repl` / `hc-repl-smoke` | Alias of `repl-holyc*` — **do not grow `jit.hc`** |
| `make coverage` | Project-mode compile tally (local; not CI) |
| `make menuconfig` | Platform Kconfig curses UI — [KCONFIG.md](templeos-riscv/KCONFIG.md) |
| `make baremetal` / `make baremetal-smoke` | Legacy C RAM `build/baremetal/repl.{elf,bin}` — [docs/BAREMETAL.md](docs/BAREMETAL.md) |
| `make bootloader` / `bootloader-repl` / `bootloader-smoke` | **HolyC** `build/bootloader/boot.bin` + `hc_repl.blob.bin` — [docs/BAREMETAL.md](docs/BAREMETAL.md) § Split |
| `make firmware` / `make firmware-smoke` | Legacy GNU flash ROM @ `0x20000000` — [docs/BAREMETAL.md](docs/BAREMETAL.md) |

Formatter (gofmt-style): `holyc-riscv --fmt` on edited `.hc`/`.HC`/`.HH` — do not hand-fight style. Roots: `tests/scripts/holyc_fmt_paths.sh`. Goldens: `make fmt-test`. Rule: `.cursor/rules/holyc-fmt.mdc`.

Debug (host build): `HOLYC_TRACE=1`, `HOLYC_TOKTRACE=<substr>`. AOT progress on stderr when stderr is a TTY (`HOLYC_PROGRESS=1` force on / `HOLYC_QUIET=1` off) — per-unit `compile` / `link` lines on win builds; full clean via `make kernel-win-rebuild`. Stale `repl.elf` / harness objects often look like universal CRASH/hang — rebuild after `host/holyc_compiler.h` / `bootstrap/holy_rt*.h` changes. Ops recovery: [docs/OPS.md](docs/OPS.md); pin last-good ELFs with `make known-good-pin`.

Kernel FB/Gr/Win interactive (macOS): see [BOARD_FB.md](templeos-riscv/BOARD_FB.md). Codegen bisect: `HOLYC_NO_OPT=1` / `HOLYC_NO_TIER2=1` / `HOLYC_NO_PROMOTE=1` / `HOLYC_O1_MODE`.

## CI

- Jobs: `syntax-sh` ‖ `shellcheck` ‖ `compile-compliance` → `qemu-integration`. Details: [docs/CI.md](docs/CI.md), matrix: [tests/README.md](tests/README.md).
- **Markdown-only** pushes skip CI (`paths-ignore`); use **Actions → CI → Run workflow** to force a run.
- `concurrency: cancel-in-progress` — an older run may show **cancelled** while tip is green.
- Platform / `kernel-plat-matrix` / board smoke **skips are not allowed** as a success outcome. Boards must boot/smoke green, or work continues until they do (honest blockers = temporary WIP with a fix plan — not permanent skip=OK). Do not add new intentional matrix skips. [PLATFORM.md](templeos-riscv/PLATFORM.md) **WIP** rows are honest blockers (with fix plan) — not skip=OK.

## Docs and layout

Topic index: **[docs/README.md](docs/README.md)**. Lean pointers:

| Topic | Doc |
|-------|-----|
| Getting started / norms | [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) · [docs/LAYOUT.md](docs/LAYOUT.md) |
| Architecture / self-host | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · [docs/SELF_HOST.md](docs/SELF_HOST.md) |
| REPL / UART / console | [docs/REPL.md](docs/REPL.md) · [docs/UART.md](docs/UART.md) · [docs/CONSOLE.md](docs/CONSOLE.md) |
| Debugger | [docs/DEBUGGER.md](docs/DEBUGGER.md) |
| FS / 9P / export | [docs/NINEP.md](docs/NINEP.md) · [docs/FILE_EXPORT.md](docs/FILE_EXPORT.md) |
| Drivers / boards | [docs/DRIVERS.md](docs/DRIVERS.md) · [templeos-riscv/PLATFORM.md](templeos-riscv/PLATFORM.md) |
| Build / CI / ops / verify | [docs/CI.md](docs/CI.md) · [docs/OPS.md](docs/OPS.md) · [docs/VERIFICATION.md](docs/VERIFICATION.md) |
| Tutorials / gaps | [docs/tutorials/README.md](docs/tutorials/README.md) · [docs/GAPS.md](docs/GAPS.md) |
| Language surface | [docs/HOLYC_IMPLEMENTATION_STATUS.md](docs/HOLYC_IMPLEMENTATION_STATUS.md) |

Host compiler: `host/` (`lexer.c`, `parser.c`, …). TempleOS port trees: `Kernel/`, `Compiler/`, `Adam/`, `Demo/` (do not rename). ISO/home reference: `tos/` (`StartOS`, `Apps`, `Doc`, …). Scratch: `tests/scratch/`. Session notes: `docs/archive/` (ignored).

## Remotes

`origin` may be a local path mirror; **`github`** → GitHub. Prefer `git push github archive` if `origin` rejects pushes.
