# Platform Kconfig tutorial

How this repo selects a **RISC-V board / memory map / ISA / entry point** and wires
HolyC device drivers.

Interactive configuration uses **Linux’s real `mconf` + lxdialog** (vendored under
`templeos-riscv/scripts/kconfig/`, from Linux v6.11). Same binary/UI as
`make menuconfig` on the kernel — not a Python TUI, not Kconfiglib.

Header generation (`autoconf.h`, `RVAutoConf.HH`, `kconfig.mk`, …) still runs through
`scripts/kconfig.py sync` after mconf writes `.config`.

Machine status: [PLATFORM.md](PLATFORM.md). Framebuffer: [BOARD_FB.md](BOARD_FB.md).
RV32 HolyC port plan: [RV32.md](RV32.md).

## Dependencies

| Need | Why |
|------|-----|
| Host **C compiler** (`cc` / clang / gcc) | Build vendored `mconf` / `conf` |
| **ncurses** (dev package) | lxdialog UI |

Install examples:

```bash
# Debian / Ubuntu
sudo apt install libncurses-dev pkg-config

# Fedora / RHEL
sudo dnf install ncurses-devel pkgconf

# macOS
brew install ncurses pkg-config
```

Flex/bison are **not** required — `lexer.lex.c` / `parser.tab.c` are pre-generated
in-tree (see `scripts/kconfig/ORIGIN.md`).

## 1. What it is for

| Concern | Examples |
|---------|----------|
| Platform | `virt`, `sifive_u`, … → `CONFIG_PLATFORM_*` |
| ISA / ABI | `ISA_RV64IMAFDC` → `CONFIG_RISCV_ISA` / `MARCH` / `MABI` |
| Entry point | `CONFIG_ENTRY_POINT` → `LOAD_BASE` / `RAM_BASE` / `KERNEL_ENTRY` |
| Console / IRQ / virtio / FB | UART, CLINT, PLIC, ramfb, … |
| Boot output | ELF vs firmware ROM (`OUTPUT_FORMAT_*`) |
| Editors | Vi / Edit / Ed |

## 2. Where files live

| Path | Role |
|------|------|
| `templeos-riscv/Kconfig` | Menus (arch/ISA/entry, map, UART, …) |
| `templeos-riscv/Kconfig.machines` | `PLATFORM_*` choice |
| `templeos-riscv/configs/*_defconfig` | Board presets |
| `templeos-riscv/.config` | Active config (written by mconf / defconfig) |
| `templeos-riscv/scripts/kconfig/` | **Vendored Linux mconf + lxdialog + conf** |
| `templeos-riscv/scripts/kconfig.py` | `defconfig` / `sync` → headers + `kconfig.mk` |
| `include/generated/kconfig.mk` | `MARCH`, `ENTRY_POINT`, `LOAD_BASE`, … |
| `Kernel/RVAutoConf.HH` | HolyC platform defines |

```
make menuconfig
    │
    ├─ make -C scripts/kconfig   → build mconf (cc + ncurses)
    ├─ ./scripts/kconfig/mconf Kconfig   → edit/save .config
    └─ python3 scripts/kconfig.py sync   → RVAutoConf.HH, kconfig.mk, …
```

## 3. Workflow

### From repo root (same muscle memory as Linux)

```bash
make menuconfig                 # build mconf if needed, run UI, then sync
# menuconfig-rv is an alias of the same target
```

### From `templeos-riscv/`

```bash
make menuconfig                 # Linux mconf
make menuconfig-test            # build conf+mconf; conf --olddefconfig sanity
make defconfig                  # virt CI default via kconfig.py
make syncconfig                 # re-emit headers from .config
```

### Interactive keys

Same as Linux menuconfig (lxdialog): arrows, Enter, Space, Esc, `/` search,
`?` help, save/quit prompts. See the mconf help screen inside the UI.

### Architecture / entry (menu **Architecture / toolchain**)

| Symbol | Virt default | Effect |
|--------|--------------|--------|
| `ISA_RV64IMAFDC` | y | `RISCV_ISA=rv64imafdc`, `MABI=lp64d` → `MARCH`/`MABI` in `kconfig.mk` |
| `ISA_RV64IMAC` / `IMA` / `I` | n | narrower `-march` |
| `ISA_RV32IMAFDC` / `IMA` | n | `ARCH_RISCV32` (headers/QEMU); HolyC emit still RV64 — [RV32.md](RV32.md) |
| `ISA_CUSTOM` + `RISCV_ISA`/`RISCV_ABI` | — | free-form |
| `ENTRY_POINT` | `0x80000000` | boot/link → `ENTRY_POINT`/`LOAD_BASE`/`RAM_BASE` |
| `KERNEL_ENTRY` / `KERNEL_LINK_ADDR` | `default ENTRY_POINT` | override only if VMA ≠ boot jump |
| `BOOT_SPLIT` | n | split bootloader + RAM payload (`make bootloader`) |
| `BOOTLOADER_BASE` | `0x20000000` | bootloader link/reset (depends on `BOOT_SPLIT`) |
| `BOOT_MODE_JUMP` / `BOOT_MODE_COPY` | jump | jump to payload vs embed-and-copy |

### Dialect note

This tree’s `Kconfig` is a **subset** of Linux Kconfig that **Linux mconf accepts**
(verified with vendored `conf --olddefconfig`). `kconfig.py` remains the sync
backend for HolyC/Make artifacts; it is not the interactive UI.

## Quick reference

```bash
make menuconfig                          # Linux mconf
make -C templeos-riscv menuconfig-test   # CI-friendly mconf/conf build check
make -C templeos-riscv defconfig
make -C templeos-riscv syncconfig
```
