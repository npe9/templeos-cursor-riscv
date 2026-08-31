# Host HolyC → RISC-V compiler

C sources for the host AOT compiler that builds **`holyc-riscv`** (repo-root
binary via top-level `make`).

| File | Role |
|------|------|
| `lexer.c` | Tokenization / `#include` |
| `parser.c` | AST / intermediate code |
| `compiler.c` | RISC-V emit |
| `holyc_fmt.c` | `--fmt` / HolyFmtSrc (canonical gofmt-style formatter; `make fmt` / `make fmt-check`) |
| `hash_table.c` | Symbol table |
| `compiler_helper.c` | StrPrintF etc. for lexer |
| `main_stub.c` | CLI entry (`HOLYC_STANDALONE`) |

Headers: `holyc_compiler.h`, `holyc_fmt.h`, `hash_table.h`, `holy_api.h`.

Runtime name table used for AOT imports: `../bootstrap/holy_rt_names.h`
(included as `"bootstrap/holy_rt_names.h"` with `-I.` from the repo root).

Do **not** confuse this with the guest HolyC compiler under `Compiler/`
(`Compiler_RV.PRJ`). Layout map: [docs/LAYOUT.md](../docs/LAYOUT.md).
