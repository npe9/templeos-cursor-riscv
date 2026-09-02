# Architecture

TempleOS → RISC-V: host HolyC AOT compiler, bare-metal REPL, HolyC kernel/Adam trees,
and a small C bootstrap image under `templeos-riscv/`. The **product** is a RISC-V OS /
HolyC runtime for Kconfig boards; emulators are how CI and local smokes load ELF images.

## Big picture

```
┌─────────────────────────────────────────────────────────────┐
│  Host (macOS / Linux)                                       │
│  holyc-riscv  ←  host/{lexer,parser,compiler,holyc_fmt}.c … │
│       │ AOT .hc / .PRJ → RV64 blob                          │
└───────┼─────────────────────────────────────────────────────┘
        │
        ▼
┌─────────────────────────────────────────────────────────────┐
│  RISC-V target (board or CI emulator harness)               │
│                                                             │
│  bootstrap/repl.elf     interactive HolyC (C + seed/*.hc)   │
│  build/baremetal/*.elf  RAM install @ LOAD_BASE (OpenOCD/-kernel) │
│  build/baremetal/*.bin  flat RAM image for -kernel / load_image │
│  build/firmware/templeos-fw.bin    flash ROM @ 0x20000000 (pflash boot)     │
│  build/firmware/templeos-bios.elf  RAM payload for qemu -bios               │
│  build/exec/*.elf       kernel_* smokes (AOT + harness)     │
│  build/kernels/<m>/     per-machine plat ELF + Kconfig snap │
│  templeos-riscv ELF     C loader + HolyC guest blob         │
│  Kernel/ + Compiler_RV   guest Cmp / ExePutS (self-host)     │
│  Kconfig → RVAutoConf   UART/CLINT/PLIC/FB per board        │
└─────────────────────────────────────────────────────────────┘
```

## Layout

| Area | Path | Role |
|------|------|------|
| **Host compiler** | `host/` (`lexer.c`, `parser.c`, `compiler.c`, `holyc_fmt.c`, …) | Source in git; `make` → `./holyc-riscv` (gitignored native binary); AOT HolyC → RISC-V |
| **Bare-metal REPL** | `bootstrap/` (`Makefile.repl`, `worry_dream_repl.c`, `seed/*.hc`) | UART prompt; full-surface smoke until guest Cmp owns the loop |
| **Bare-metal install** | `bootstrap/Makefile.baremetal`, `docs/BAREMETAL.md` | `build/baremetal/repl.{elf,bin}` @ RAM — OpenOCD / `-bios none -kernel` |
| **Firmware / BIOS** | `bootstrap/Makefile.firmware`, `firmware_stub.S`, `firmware.ld` | `templeos-fw.bin` = flash ROM @ `0x20000000` (pflash); `templeos-bios.elf` = RAM payload for `-bios` — `make firmware` |
| **Mac-AOT bridge** | `bootstrap/hc_repl/` | Temporary HolyC guest ELF; **do not grow `jit.hc`** |
| **TempleOS Kernel (HolyC)** | `Kernel/` (`Kernel_RV.PRJ`, `Drv/*`, `RVFb.HC`, …) | Real OS sources on RV; drivers selected by Kconfig |
| **Guest compiler** | `Compiler/Compiler_RV.PRJ`, `Back*_RV.HC`, `Asm_RV.HC` | Lex/Prs/Opt + RV emit; destination for `ExePutS` / `Cmp` |
| **Adam / StartOS** | `Adam/MakeAdam_RV*.HC`, `Adam/StartOS_RV.HC` | StartOS subset; full DolDoc Adam still open |
| **ISO / home reference** | `tos/` | Upstream TempleOS system-root tree (not the active RV port) |
| **C OS bootstrap** | `templeos-riscv/` | Separate image: boot/traps, console putc, guest link slots — **not** the multi-machine driver layer |
| **Platform config** | `templeos-riscv/Kconfig*`, `scripts/kconfig.py` → `Kernel/RVAutoConf.HH` | Board / MMIO / UART selection — [KCONFIG.md](../templeos-riscv/KCONFIG.md) |
| **Tests** | `tests/` | Compliance, exec oracles, REPL regression — [tests/README.md](../tests/README.md) |

## Self-host status (honest)

| Layer | Today | Direction |
|-------|--------|-----------|
| Host `holyc-riscv` | **Required** bootstrap: built from `host/` via `make`; builds smokes, packs `Compiler.BIN`, phase3 ELF | Remains the seed producer; shrink over time |
| Guest `Compiler_RV` + `ExePutS` | Expr / fun-def → 42; guest `Cmp` → Load → Call proven in phase3 | **Language destination** — not `jit.hc` |
| Boot baseline | Phase3 still host-AOTs the demo ELF + Compiler seed; StartOS **Loads** guest BINs | [COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md) P3: HolyC-built runtime as boot baseline |
| C hooks / `RuntimeRegister` | Still in `worry_dream_repl.c` (readline, UART drain, host compile slot, …) | **Kill** — callable APIs = HolyC only; see [MULTIARCH.md](MULTIARCH.md) §2 |
| x86 parity | Subsystem map in [TOS_X86_PARITY.md](../templeos-riscv/TOS_X86_PARITY.md); not full VGA/DolDoc/mouse | Text_base WinMgr + 32-bpp FB; UART REPL |

**Runtime mandate:** no guest runtime other than HolyC built by the compiler
(`Compiler_RV` / `ExePutS` / `Cmp`). Do not grow `jit.hc`. Host slots /
`RuntimeRegister` / C UART-drain funptrs are transitional bootstrap only —
kill list and per-arch rule in [MULTIARCH.md](MULTIARCH.md) §2.

## Data flow (typical smoke)

1. `./holyc-riscv tests/exec/cases/kernel_….hc -o blob.bin` (often `#include`s `Kernel_RV.PRJ`).
2. Link with `tests/exec/harness/` → ELF at `0x80000000`.
3. CI / local harness loads the ELF on the configured machine profile — UART oracle greps for PASS strings.

Platform-sensitive smokes first run `make -C templeos-riscv defconfig-*` so `RVAutoConf.HH` matches the board under test. Emulator machine names (`-M virt`, …) are harness details — [CI.md](CI.md), [PLATFORM.md](../templeos-riscv/PLATFORM.md).

## Related docs

- [LAYOUT.md](LAYOUT.md) — source-tree map
- [../README.md](../README.md) — quick start
- [CONTRIBUTING.md](CONTRIBUTING.md) — build / test / norms
- [tutorials/README.md](tutorials/README.md) — SF-style executable HolyC labs (ISA / CSAPP / Beck)
- [REPL.md](REPL.md) — interactive HolyC
- [IDE.md](IDE.md) — expected IDE behaviors (Vi / Src / Man / ErrGo)
- [CI.md](CI.md) — CI / local gates
- [../templeos-riscv/PLATFORM.md](../templeos-riscv/PLATFORM.md) — boards + CI targets
- [../templeos-riscv/RV32.md](../templeos-riscv/RV32.md) — RV32 / ILP32 port plan
- [MULTIARCH.md](MULTIARCH.md) — multi-arch port plan (ARM / PPC / …)
- [HOLYC_IMPLEMENTATION_STATUS.md](HOLYC_IMPLEMENTATION_STATUS.md) — language surface
- [README.md](README.md) — documentation index
