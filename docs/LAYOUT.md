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
├── bootstrap/               # Bare-metal HolyC REPL + boot helpers
│   ├── hc_repl/             # Product UART REPL (make hc-repl; do not grow jit.hc)
│   ├── seed/                # HolyC memfs seeds → /Boot /Lib /Apps /Doc /Tutorials
│   ├── Makefile.repl        # seed blob helpers only (legacy C guest deleted)
│   ├── gen_seeds.py
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
host scripts use `tos/…`. Path dual-namespace (BlkDev vs UART memfs vs host AOT):
[PATHS.md](PATHS.md).

## Host compiler (`host/`)

Built by root `make` → `./holyc-riscv` (symlink `cicl-riscv` for older scripts).

Sources live under `host/` so the repo root is not a pile of `.c` files.
Compile flags include `-Ihost -I.` so `#include "holyc_compiler.h"` and
`#include "bootstrap/holy_rt_names.h"` both resolve from the repo root cwd.

## Bootstrap (`bootstrap/`)

| Path | Role |
|------|------|
| `hc_repl/` | **Product UART HolyC REPL** (`make hc-repl`) — **do not grow `jit.hc`** |
| `seed/` | Editable HolyC primitives (embedded by `hc_repl/gen_embed.py`) |
| `Makefile.repl` | Seed/blob helpers only (legacy C `repl.elf` target retired) |
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
