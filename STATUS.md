# Status

Superseded — see [HOLYC_IMPLEMENTATION_STATUS.md](HOLYC_IMPLEMENTATION_STATUS.md) (execution-verified
feature table) and [docs/RISCV_PORT_PLAN.md](docs/RISCV_PORT_PLAN.md) (phases and current status).

As of 2026-08-25: `make ci` is green (compliance, QEMU exec oracles, TempleOS smoke, bare-metal
REPL smoke) and the three TempleOS projects — `Kernel/Kernel_RV.PRJ`, `Compiler/Compiler.PRJ`,
`Adam/MakeAdam_RV.PRJ` — compile with 0 parse errors (`make coverage`).
