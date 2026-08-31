# Bootstrap: bare-metal REPL

Interactive HolyC on RISC-V (UART). Product guide: **[docs/REPL.md](../docs/REPL.md)**.
Honesty gate: **[tests/REGRESSION.md](../tests/REGRESSION.md)**. Default seed `MEM_*`
matches a typical virt-style map for CI; boards use Kconfig —
[PLATFORM.md](../templeos-riscv/PLATFORM.md).

## Layout

| Path | Role |
|------|------|
| `Makefile.repl` | **Primary** build → `repl.elf` |
| `worry_dream_repl.c` | C guest REPL + host slots (deprecated long-term) |
| `holy_rt.h` / `holy_rt_names.h` | Runtime / import names for host + guest |
| `startup.s` / `linker.ld` | Boot + link |
| `gen_seeds.py` | Bake `seed/*.hc` → `seed_files.h` |
| `seed/` | Editable HolyC memfs seeds |
| `hc_repl/` | Transitional Mac-AOT HolyC ELF — **do not grow `jit.hc`** |
| `archive/` | Historical demos / old Makefiles — **not built by CI** |

## Build / run

```bash
# from repo root
make                          # host/ → ./holyc-riscv
cd bootstrap && make -f Makefile.repl
# → repl.elf — load on board or CI harness (see docs/CI.md / docs/REPL.md)

# or gates
make repl-smoke
make repl-regression
```

Host compiler sources live in **`../host/`** (not repo root).
