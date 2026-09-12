# TempleOS HolyC → RISC-V

[![CI](https://github.com/npe9/templeos-cursor-riscv/actions/workflows/ci.yml/badge.svg?branch=archive)](https://github.com/npe9/templeos-cursor-riscv/actions/workflows/ci.yml?query=branch%3Aarchive)

Host **HolyC → RISC-V** AOT compiler (`holyc-riscv`), bare-metal **REPL**, and a TempleOS-shaped
**Kernel / Compiler_RV / Adam** tree for real RISC-V boards (Kconfig + HolyC drivers). QEMU is the
**dev/CI harness**, not the product — see [PLATFORM.md](templeos-riscv/PLATFORM.md).

**Remotes:** `origin` may be a local path mirror; **`github`** → [npe9/templeos-cursor-riscv](https://github.com/npe9/templeos-cursor-riscv). Use `git push github archive` if `origin` rejects pushes.

## Status (honest)

| Works today | Not there yet |
|-------------|----------------|
| Host AOT + compliance / exec oracles / many `kernel-*-smoke` (CI on virt) | Full x86 TempleOS parity (DolDoc, mouse, VGA model) |
| HolyC UART/CLINT/PLIC/virtio/FB drivers via Kconfig (SiFive and other ports) | Forever-host-AOT as the definition of done |
| Guest `Compiler_RV` `ExePutS` / `Cmp` → Load → Call (phase3) | Boot baseline fully free of host-AOT demos ([COMPILER_RV.md](templeos-riscv/COMPILER_RV.md)) |
| Text_base WinMgr + 32-bpp ramfb/simplefb | Full Adam graphics stack |
| REPL `Src` / Vi / Fmt / MemMap (regression-gated) | Pure HolyC with zero host slots on `repl.elf` |

Layout and self-host: **[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)**. Tree map: **[docs/LAYOUT.md](docs/LAYOUT.md)** (`tos/` = TempleOS ISO/home; port trees stay at root). Language surface: [docs/HOLYC_IMPLEMENTATION_STATUS.md](docs/HOLYC_IMPLEMENTATION_STATUS.md).

## Quick start

### Prerequisites

- Host C toolchain + Make — the HolyC compiler **sources** live in `host/`; `make` builds `./holyc-riscv` (not downloaded or committed)
- Cross tools for guest images / CI: `riscv64-unknown-elf-gcc` (and `ld`/`objcopy`), Python 3
- Optional for local smokes: `qemu-system-riscv64` (CI harness only)
- Optional: `shellcheck` (`make lint-sh`)

Self-contained workflow: [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md#self-contained-repository).

### Build and CI gate

```bash
make clean && make          # → holyc-riscv
make test                   # tiny AOT smoke + fmt-test
make fmt / make fmt-check   # rewrite / gate HolyC under enforced roots (gofmt-style)
make ci                     # compliance + fmt-test + fmt-check + qemu-integration
```

Same stages as GitHub Actions after shellcheck/syntax. Details: [docs/CI.md](docs/CI.md), [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

### REPL / kernel / platform

```bash
make hc-repl                # → build/repl-holyc.elf (classic UART HolyC REPL)
# load build/repl-holyc.elf on your board or CI emulator — docs/REPL.md
# gates: make repl-holyc-smoke / repl-holyc-regression

make kernel-print-smoke     # Kernel_RV StrPrintJoin → UART
make kernel-plat-smoke      # Kconfig HolyC UART+CLINT (CI default board)
make kernel-fb-smoke        # FB present path (headless hash) — BOARD_FB.md
make menuconfig             # curses Kconfig (ISA / entry / board) → RVAutoConf.HH
# or: make -C templeos-riscv defconfig-sifive_u
```

## Documentation

**Topic index:** [docs/README.md](docs/README.md) (architecture, REPL/UART, drivers/boards, CI/ops, tutorials, gaps, …).

| Jump | Doc |
|------|-----|
| Norms / layout | [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md) · [docs/LAYOUT.md](docs/LAYOUT.md) · [AGENTS.md](AGENTS.md) |
| Architecture / self-host | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) · [docs/SELF_HOST.md](docs/SELF_HOST.md) |
| Boards / Kconfig / guest Cmp | [templeos-riscv/PLATFORM.md](templeos-riscv/PLATFORM.md) · [templeos-riscv/KCONFIG.md](templeos-riscv/KCONFIG.md) · [templeos-riscv/COMPILER_RV.md](templeos-riscv/COMPILER_RV.md) |
| CI / tests | [docs/CI.md](docs/CI.md) · [tests/README.md](tests/README.md) |
| Tutorials | [docs/tutorials/README.md](docs/tutorials/README.md) |

## Example (HolyC)

```holyc
I64 Add(I64 a, I64 b) { return a + b; }
Add(5, 10);
```

```bash
./holyc-riscv path/to/file.hc -o build/out.bin
riscv64-unknown-elf-objdump -D -b binary -m riscv:rv64 build/out.bin
```

## License

Based on TempleOS-related work; follow the licensing terms of the upstream you track.
