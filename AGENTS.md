# Notes for contributors and coding agents

## Build and test

- **`make`** — host compiler `holyc-riscv`. The root `Makefile` passes **`-D_DEFAULT_SOURCE`** so glibc exposes `strdup` and related APIs under **`-std=c11`** (required for correct Linux builds / GitHub Actions).
- **`make test`** — quick AOT smoke (`build/smoke.hc`).
- **`make ci`** — same stages as [`.github/workflows/ci.yml`](.github/workflows/ci.yml): **`make compliance`** then **`make qemu-integration`**. Requires a RISC-V bare-metal toolchain (`riscv64-unknown-elf-gcc`), **`qemu-system-riscv64`**, and **Python 3** (TempleOS image helper).
- **`make lint-sh`** — runs **ShellCheck** (`-S error -x`) on the four CI shell scripts; requires **`shellcheck`** on `PATH` (same checks as the **`shellcheck`** CI job).
- **`make syntax-sh`** — **`bash -n`** on every **`tests/scripts/*.sh`**; no extra tools (quick syntax smoke for scripts not covered by **`lint-sh`**).

## CI (GitHub Actions)

- Pushes and PRs that change **only** Markdown (`*.md` anywhere) **do not** run CI (`paths-ignore`), to save time on doc edits. Use **Actions → CI → Run workflow** when you need a full run after doc-only changes.
- **`concurrency: cancel-in-progress`** stops the previous run when a new push lands; an older commit may show **cancelled** even though the tip commit is green.
- The **`shellcheck`** job runs **`make syntax-sh`** first (**`bash -n`** on every **`tests/scripts/*.sh`**), then installs **ShellCheck** and lints the four primary scripts (faster failure on parse errors).

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
