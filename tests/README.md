# Tests

## Primary harnesses (used by CI)

| Area | Location | Make / script |
|------|----------|----------------|
| Compile compliance (TempleOS tree + parity `.hc`) | `tests/holyc/compliance/` | `make compliance` → `tests/scripts/run_holyc_compliance.sh` |
| UART execution oracles (the harness links the shared runtime `bootstrap/holy_rt.h` and resolves the blob's import directory) | `tests/exec/` | `make exec-oracle` → `tests/scripts/run_exec_oracles.sh` |
| TempleOS/RISC-V QEMU smoke | (builds `templeos-riscv/`) | `make templeos-smoke` → `tests/scripts/run_templeos_smoke.sh` |
| Bare-metal REPL over UART (QEMU) — incl. whole TempleOS demo files with expected output | (builds `bootstrap/repl.elf`) | `make repl-smoke` → `tests/scripts/run_repl_smoke.sh` |

**Full gate (matches [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)):** `make ci` — compliance, then `qemu-integration` (exec oracles + TempleOS smoke + REPL smoke).

**Note:** `make compliance-exec` runs `run_holyc_compliance.sh --exec` (compile suites + exec oracles in one script); it does **not** run TempleOS smoke.

## Other scripts

`tests/scripts/` contains additional TempleOS batch runners and utilities; the table above lists the paths wired into the root `Makefile` and CI.

CI runs a **`syntax-sh`** job (**`make syntax-sh`**) and a **`shellcheck`** job (**ShellCheck** `-S error` on the five scripts in the table) in parallel with **`compile-compliance`**; **`qemu-integration`** requires all three. See [`.github/workflows/ci.yml`](../.github/workflows/ci.yml). Locally: **`make syntax-sh`**, **`make lint-sh`**.

**Doc-only pushes** (commits that change only `*.md` files) **skip** CI to save runners; use **Actions → CI → Run workflow** for a manual full run. Contributor notes: [AGENTS.md](../AGENTS.md).
