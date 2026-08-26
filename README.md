# TempleOS HolyC to RISC-V Compiler

[![CI](https://github.com/npe9/templeos-cursor-riscv/actions/workflows/ci.yml/badge.svg?branch=archive)](https://github.com/npe9/templeos-cursor-riscv/actions/workflows/ci.yml?query=branch%3Aarchive)

HolyC front end and RISC-V code generator, with optional bare-metal REPL and a separate TempleOS/RISC-V tree under `templeos-riscv/`.

**Remotes:** This clone may use `origin` as a local path mirror; **`github`** points at [npe9/templeos-cursor-riscv](https://github.com/npe9/templeos-cursor-riscv). Use `git push github archive` if `origin` rejects pushes (non-bare repo with `archive` checked out).

## Project status

**AOT compiler:** Builds as `holyc-riscv` (symlink `cicl-riscv` for older scripts). The repository includes automated **compile-time** checks over curated TempleOS `.HC` samples and a 52-case HolyC-style parity suite (`make compliance`), execution oracles under QEMU (`make exec-oracle`, 29 cases), and a project-mode coverage tally over the real TempleOS sources (`make coverage`): **`Kernel/Kernel_RV.PRJ`** — the kernel minus its x86 files, with `Kernel/KStartRV.HC` standing in for them — compiles with 0 errors, as do `Compiler/Compiler.PRJ` and `Adam/MakeAdam_RV.PRJ` (Adam on top of the kernel). The port plan is in [docs/RISCV_PORT_PLAN.md](docs/RISCV_PORT_PLAN.md).

**Kernel code runs on RISC-V:** `make kernel-print-smoke` compiles a program that `#include`s the real
TempleOS kernel, formats a string with the kernel's own 900-line `StrPrintJoin`, and prints it over the
QEMU `virt` UART. `make exec-oracle` also runs the kernel's `QSort`, `Str2I64`, `StrPrintHex`, `Str*`,
hash table and heap allocator and checks their results.

**What is verified vs not:** `make compliance` checks that sources compile to RISC-V machine code. It does not prove that every program behaves correctly when linked with a full runtime or run under QEMU bare metal. Treat REPL and long-running bare-metal execution as a separate stability surface.

### Working (high level)

- HolyC parsing and intermediate code generation (`parser.c`, `lexer.c`)
- RISC-V emission and multi-pass layout (`compiler.c`)
- Integer control flow, operators, many aggregate and preprocessor cases (see `tests/holyc/compliance/`)
- Many-parameter calls per RISC-V calling convention (registers + stack)
- Optional interactive REPL in `bootstrap/` (build with `make -f Makefile.repl` in that directory)

### Known rough edges

- **Bare-metal REPL:** Function definition + call across statements, redefinition, recursion, >8 args and long runs of calls are covered by `make repl-smoke` (QEMU). Older reports of hangs after a call / corruption after heavy use were a stale cross-buffer `jal` plus an 8-byte stack leak per statement, both fixed; anything beyond that scope is unverified.
- **Host vs bare split:** Logic exists in both top-level `*.c` and `bootstrap/*_bare.c`; fixes may need to be applied in both places.
- **Runtime:** Simple AOT snippets (e.g. `make test`) work for smoke testing; full OS images and `templeos-riscv` are separate targets.

## Quick start

### Prerequisites

- RISC-V toolchain (`riscv64-unknown-elf-gcc`, `riscv64-unknown-elf-objdump`) for disassembly and some tests
- QEMU with RISC-V support (`qemu-riscv64` / `qemu-system-riscv64`)
- Python 3 (for `templeos-riscv` image steps used by `make templeos-smoke` / `make ci`)
- Make

See [AGENTS.md](AGENTS.md) for a short contributor / coding-agent orientation (layout, `make ci`, remotes).

### Building

```bash
make clean && make
```

Produces `holyc-riscv` and a `cicl-riscv` symlink.

### Compliance (compile-only)

```bash
make compliance
```

Optional: compile and run parity cases under QEMU when the harness supports it:

```bash
make compliance-exec
```

### REPL (bare metal)

```bash
cd bootstrap
make clean && make -f Makefile.repl
qemu-system-riscv64 -M virt -bios none -kernel repl.elf -nographic
```

Type HolyC at the `>` prompt; the input has the same grammar as a source file (functions, classes, globals, `#define`, statements). Statements are compiled and run on the spot and the answer is printed in hex (`I64 Add(I64 a, I64 b) { return a + b; }` then `Add(40,2);` → `0x2a`); `"x=%d\n", 42;` prints through the built-in `Print`. The REPL image carries a small runtime (`Print`, `PutChars`, `MAlloc`/`Free`, `StrLen`/`StrCpy`/`StrCmp`). `make repl-smoke` runs all of this end to end under QEMU; [HOLYC_IMPLEMENTATION_STATUS.md](HOLYC_IMPLEMENTATION_STATUS.md) lists what is execution-verified.

### Example (HolyC)

```holyc
I64 Add(I64 a, I64 b) { return a + b; }
Add(5, 10);

I64 Get11th(I64 a, I64 b, I64 c, I64 d, I64 e, I64 f, I64 g, I64 h, I64 i, I64 j, I64 k) {
  return k;
}
Get11th(1,2,3,4,5,6,7,8,9,10,11);
```

## Architecture

| Piece | Role |
|-------|------|
| `lexer.c` | Tokenization |
| `parser.c` | AST / IC generation |
| `compiler.c` | RISC-V encoding and prologue/epilogue |
| `hash_table.c` | Symbols and types |
| `main_stub.c` | CLI driver for AOT |
| `bootstrap/worry_dream_repl.c` | Interactive environment (bare metal) |
| `riscv_disasm.c`, `riscv_dump.c` | Debugging helpers |

## Testing

Layout of compliance files and scripts: [tests/README.md](tests/README.md).

```bash
make test                    # Minimal AOT smoke (build/smoke.hc → build/simple.bin)
make ci                      # Full gate: compliance + qemu-integration (same as GitHub CI)
make compliance              # TempleOS curated + parity compile suite
make qemu-integration        # exec-oracle + templeos-smoke + repl-smoke (needs RISC-V + qemu-system + python3)
make compliance-exec         # All compile suites then exec oracles via one script (no TempleOS smoke)
make exec-oracle             # UART oracle runs only (tests/exec/)
make templeos-smoke          # TempleOS/RISC-V QEMU smoke only
make repl-smoke              # Bare-metal REPL under QEMU: compile+run over UART (bootstrap/repl.elf)
make lint-sh                 # ShellCheck on the five CI scripts (needs shellcheck)
make syntax-sh               # bash -n on all tests/scripts/*.sh (no extra installs)
```

On GitHub, CI runs four jobs: **`syntax-sh`**, **`shellcheck`**, and **`compile-compliance`** in parallel, then **`qemu-integration`** after all three succeed (same end state as **`make ci`**, plus shell script checks). Doc-only commits (`*.md` only) skip CI (`paths-ignore`); use **Actions → CI → Run workflow** when needed. Dependabot groups weekly Action updates (`.github/dependabot.yml`). See `.github/workflows/ci.yml`.

Compile a single file:

```bash
./holyc-riscv path/to/file.hc -o build/out.bin
riscv64-unknown-elf-objdump -D -b binary -m riscv:rv64 build/out.bin
```

## References

- [TempleOS](https://templeos.org/)
- [RISC-V spec](https://riscv.org/technical/specifications/)
- [HolyC (TempleOS doc)](https://templeos.org/Wb/Doc/HolyC.html)

## License

Based on TempleOS-related work; follow the same licensing terms as the upstream you track.

**Last updated:** March 2026
