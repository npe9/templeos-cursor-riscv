# Notes for contributors and coding agents

## Build and test

- **`make`** — host compiler `holyc-riscv`. The root `Makefile` passes **`-D_DEFAULT_SOURCE`** so glibc exposes `strdup` and related APIs under **`-std=c11`** (required for correct Linux builds / GitHub Actions).
- **`make test`** — quick AOT smoke (`build/smoke.hc`).
- **`make ci`** — same stages as [`.github/workflows/ci.yml`](.github/workflows/ci.yml): **`make compliance`** then **`make qemu-integration`** (exec oracles, TempleOS smoke, and **`make repl-smoke`** — the bare-metal REPL compiling and running statements over the UART). Requires a RISC-V bare-metal toolchain (`riscv64-unknown-elf-gcc`), **`qemu-system-riscv64`**, and **Python 3** (TempleOS image helper).
- **`make lint-sh`** — runs **ShellCheck** (`-S error -x`) on the five CI shell scripts; requires **`shellcheck`** on `PATH` (same checks as the **`shellcheck`** CI job).
- **`make syntax-sh`** — **`bash -n`** on every **`tests/scripts/*.sh`**; no extra tools (quick syntax smoke for scripts not covered by **`lint-sh`**).
- **`make coverage`** — project-mode compiles of `Kernel/Kernel_RV.PRJ` (0 errors), `Kernel/Kernel.PRJ`, `Adam/MakeAdam.HC`, `Compiler/Compiler.PRJ` with an all-errors tally (`HOLYC_ALL_ERRORS=1 HOLYC_INCLUDE_ROOT=$PWD ./holyc-riscv <prj>` prints every `file:line: msg`). `Kernel/KStartRV.HC` is the RISC-V stand-in for the excluded x86 files (data labels + stub functions) — keep it in sync with what phase 2 implements.
- Debug env (host build only): `HOLYC_TRACE=1` (parser failure traces), `HOLYC_TOKTRACE=<substr>` (every token from files whose name contains the substring, with brace depth). `bootstrap/Makefile.repl` and `tests/scripts/run_exec_oracles.sh` rebuild when `holyc_compiler.h` / `bootstrap/holy_rt*.h` change — a stale `repl.elf` or harness object shows up as REPL cases that all "CRASH" or runtime calls that hang.

## CI (GitHub Actions)

- Pushes and PRs that change **only** Markdown (`*.md` anywhere) **do not** run CI (`paths-ignore`), to save time on doc edits. Use **Actions → CI → Run workflow** when you need a full run after doc-only changes.
- **`concurrency: cancel-in-progress`** stops the previous run when a new push lands; an older commit may show **cancelled** even though the tip commit is green.
- **`syntax-sh`** and **`shellcheck`** are separate jobs (run in parallel with **`compile-compliance`**). **`qemu-integration`** waits for all three. **`syntax-sh`** is **`make syntax-sh`** only; **`shellcheck`** installs **ShellCheck** and lints the five primary scripts.
- **Branch protection (optional):** if you require status checks on `archive`, include all four job names: **`syntax-sh`**, **`shellcheck`**, **`compile-compliance`**, **`qemu-integration`**.

## Implementation status

- Feature-level notes: [HOLYC_IMPLEMENTATION_STATUS.md](HOLYC_IMPLEMENTATION_STATUS.md).

## Layout

- Compiler: `lexer.c`, `parser.c`, `compiler.c`, `hash_table.c`, `compiler_helper.c`, `main_stub.c`; headers `holyc_compiler.h`, `holy_api.h`.
- Test layout: [tests/README.md](tests/README.md).
- Compliance: `tests/holyc/compliance/` and `tests/scripts/run_holyc_compliance.sh`.
- QEMU UART oracles: `tests/exec/` and `tests/scripts/run_exec_oracles.sh`.
- Bare-metal REPL: `bootstrap/` (e.g. `Makefile.repl` builds with `../parser.c`).
- OS scaffold: `templeos-riscv/`.

## Git remotes

This clone may use **`origin`** as a local path mirror. **`github`** points at the GitHub repo; use **`git push github archive`** if `origin` rejects pushes (non-bare checkout of `archive`).
