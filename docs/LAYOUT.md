# Repository layout

Canonical map of the tree. Port-owned trees stay at the git root; upstream
TempleOS ISO/home content lives under **`tos/`**.

## Target tree (top level)

```
.
├── Makefile                 # Orchestrator: holyc-riscv, smokes, ci
├── README.md / AGENTS.md
├── host/                    # Host HolyC → RISC-V AOT compiler (C)
│   ├── lexer.c parser.c compiler.c holyc_fmt.c …
│   └── README.md
├── bootstrap/               # Bare-metal REPL + transitional Mac-AOT
│   ├── Makefile.repl        # Primary: worry_dream_repl + seed/
│   ├── worry_dream_repl.c / holy_rt*.h / startup.s / linker.ld
│   ├── gen_seeds.py
│   ├── seed/                # HolyC memfs seeds → /Boot /Lib /Apps /Doc /Tutorials
│   ├── hc_repl/             # Transitional Mac-AOT guest (do not grow jit.hc)
│   ├── archive/             # Historical demos / old Makefiles (not built by CI)
│   └── README.md
├── Kernel/ Compiler/ Adam/ Demo/   # Actively ported HolyC — do not rename
├── tos/                     # Upstream TempleOS ISO/home (StartOS, Apps, Doc, …)
├── templeos-riscv/          # C loader image + Kconfig / PLATFORM
├── tests/                   # Compliance, oracles, smokes, regression
├── tools/                   # Generators / packers; tools/legacy/ = old utilities
└── docs/                    # Product docs (this file, ARCHITECTURE, …)
```

## What stays TempleOS-shaped (names)

Do **not** invent a Linux-style `src/kernel` rename of the ported trees:

| Path | Role |
|------|------|
| `Kernel/` | HolyC kernel (`Kernel_RV.PRJ`, `Drv/`, …) |
| `Compiler/` | Guest Cmp (`Compiler_RV.PRJ`, `Back*_RV.HC`, …) |
| `Adam/` | Adam / StartOS subset (`StartOS_RV.HC`, …) |
| `Demo/` | TempleOS demos (port / smoke inputs) |

Upstream ISO/home (menus, Apps, Doc, …) is under **`tos/`** — same internal
relative layout as TempleOS `/`, not scattered at the git root:

| Path | Role |
|------|------|
| `tos/StartOS.HC` `tos/Home*.HC` `tos/MakeHome.HC` `tos/Once.HC` | x86 reference StartOS / Home |
| `tos/Personal*.DD` `tos/ReadMe.TXT` | Menus / notes |
| `tos/Apps/` `tos/Doc/` `tos/Misc/` `tos/Linux/` `tos/Downloads/` `tos/0000Boot/` | Upstream product trees |

See [tos/README.md](../tos/README.md). Guest `::/` paths still mean ISO root;
host scripts use `tos/…`.

## Host compiler (`host/`)

Built by root `make` → `./holyc-riscv` (symlink `cicl-riscv` for older scripts).

Sources live under `host/` so the repo root is not a pile of `.c` files.
Compile flags include `-Ihost -I.` so `#include "holyc_compiler.h"` and
`#include "bootstrap/holy_rt_names.h"` both resolve from the repo root cwd.

## Bootstrap (`bootstrap/`)

| Path | Role |
|------|------|
| `Makefile.repl` + `worry_dream_repl.c` | Live UART REPL (C guest + host slots) |
| `seed/` | Editable HolyC primitives baked into `seed_files.h` |
| `hc_repl/` | Temporary HolyC-only AOT ELF — **do not grow `jit.hc`** |
| `archive/` | Old one-off demos, stress `.txt`, alternate Makefiles — not CI |

See [REPL.md](REPL.md) and [bootstrap/README.md](../bootstrap/README.md).

## Other areas

| Path | Role |
|------|------|
| `templeos-riscv/` | Separate C OS image + Kconfig → `Kernel/RVAutoConf.HH` |
| `tests/` | Matrix in [tests/README.md](../tests/README.md) |
| `tools/` | `pack_tosb`, generators; `tools/legacy/` = retired root utilities |
| `docs/archive/` | Session notes (gitignored; not product docs) |
| `build/` | Local build outputs (gitignored) |

## Before / after (reorganizations)

**Host / bootstrap (earlier):**
- Host `lexer.c` / `parser.c` / … moved from repo root → `host/`
- Historical bootstrap demos → `bootstrap/archive/`

**TempleOS ISO/home (this pass):**
- Root `StartOS.HC` `Home*` `Apps/` `Doc/` `Misc/` … → **`tos/`**
- Port root keeps `Kernel/` `Compiler/` `Adam/` `Demo/` + tooling

```
host/ bootstrap/ templeos-riscv/ tests/ tools/ docs/
Kernel/ Compiler/ Adam/ Demo/
tos/            # ISO/home reference tree
```

Verified: `make`, `make test`; phase3 uses `Adam/StartOS_RV.HC` (unchanged).
