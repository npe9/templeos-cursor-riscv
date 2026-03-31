# Tests

## Primary harnesses (used by CI)

| Area | Location | Make / script |
|------|----------|----------------|
| Compile compliance (TempleOS tree + parity `.hc`) | `tests/holyc/compliance/` | `make compliance` → `tests/scripts/run_holyc_compliance.sh` |
| UART execution oracles | `tests/exec/` | `make exec-oracle` → `tests/scripts/run_exec_oracles.sh` |
| TempleOS/RISC-V QEMU smoke | (builds `templeos-riscv/`) | `make templeos-smoke` → `tests/scripts/run_templeos_smoke.sh` |

**Full gate (matches [`.github/workflows/ci.yml`](../.github/workflows/ci.yml)):** `make ci` — compliance, then `qemu-integration` (exec oracles + TempleOS smoke).

**Note:** `make compliance-exec` runs `run_holyc_compliance.sh --exec` (compile suites + exec oracles in one script); it does **not** run TempleOS smoke.

## Other scripts

`tests/scripts/` contains additional TempleOS batch runners and utilities; the table above lists the paths wired into the root `Makefile` and CI.

Repo orientation: [AGENTS.md](../AGENTS.md).
