# Multi-platform Kconfig (RISC-V boards)

TempleOS/RV targets **real RISC-V platforms** via **Kconfig** + **HolyC drivers**.
There is **no** C device-driver stack for the OS: UART / CLINT / PLIC / virtio / FB
present selection live under `Kernel/Drv/*.HC`, parameterized by generated defines.

**Emulator targets for CI** (machine names such as `virt`) share the same Kconfig so
smokes can load ELF images without hardware. They are harness profiles, not the
product definition. Prefer speaking in `MEM_*` / `CONFIG_*` / board names in Help and Man.

RV32 / ILP32 port plan (virt-style map first; OpenTitan is tiny-profile only): [RV32.md](RV32.md).

| Output | Role |
|--------|------|
| `templeos-riscv/.config` | Saved symbol values |
| `templeos-riscv/include/generated/autoconf.h` | C `#define`s (link addresses for the C *bootstrap* image only) |
| `Kernel/RVAutoConf.HH` | HolyC `#define`s — included first by `Kernel_RV.PRJ` |

Default profile is always **`virt`** so existing `make kernel-*-smoke` / CI stay green.

## Configure

```bash
cd templeos-riscv
make defconfig                 # virt (CI default profile)
make defconfig-sifive_u        # SiFive UART0 @ 0x10010000
make defconfig-spike           # experimental HTIF
make defconfig-amd_microblaze_v
make defconfig-opentitan       # RV32 tiny profile
make list-defconfigs
make menuconfig                # pick machine + tweak hex addresses
make syncconfig                # refresh autoconf + Kernel/RVAutoConf.HH
make qemu-args                 # prints suggested harness argv for CI/local smokes
```

From the **repo root**: `make menuconfig-rv`

## HolyC drivers (`Kernel/Drv/`)

| File | Role |
|------|------|
| `RVSifivePlat.HC` → `RVSifiveSelected.HH` | SiFive UART/CLINT/PLIC **named** facade (`RVSifiveYes` on `sifive_u`/`e`) |
| `RVUart.HC` → `RVUartSelected.HH` | Includes 16550 / SiFive / HTIF / stub |
| `RVUart16550.HC` / `RVUartSifive.HC` / … | Concrete UART drivers (`RVUartSifive` thin-wraps `RVSifiveUart*`) |
| `RVTimer.HC` | CLINT `mtime` / `mtimecmp` |
| `RVPlic.HC` → `RVPlicSelected.HH` | PLIC hw or stub |
| `RVVirtioPlat.HC` → `RVVirtioSelected.HH` | virtio-mmio/PCI present helpers |
| `RVFbPlat.HC` → `RVFbSelected.HH` | `RVFbSetPresent` kind + fw_cfg base |
| `RVMemMap.HC` | MMIO region ↔ driver legend (`RVMemMap`; SiFive → `RVSifivePlat`) |

`kconfig.py` regenerates `*Selected.HH` with `.config`. Prefer **HolyC stubs** over new C drivers for tentative boards.

### Default editor (Src / DirEd / FunEd)

Kconfig **Editors** choice (default **Vi**) writes into `Kernel/RVAutoConf.HH` and
`bootstrap/seed/RVEditorSelected.hc`. Live override: `editor=&EditHoly;` / `editor=&EdHoly;`.

## Machine status

Two kinds of rows:

- **Board ports** — SiFive and other SoC-shaped bring-ups (UART/CLINT/PLIC wired or stubbed).
- **Emulator targets for CI** — profiles whose primary job is automated load/smoke (still valid Kconfig; not “the OS is this emulator”).

Inventory checked against common RISC-V emulator `-M help` lists (e.g. QEMU 10.1) so CI
machine strings stay accurate.

| Machine / profile | Defconfig | Kind | Status | Wired | Stub / notes |
|-------------------|-----------|------|--------|-------|--------------|
| **virt** | `virt` | Emulator (CI) | **CI** | 16550 @ `0x10000000`, CLINT, PLIC, fw_cfg/ramfb, virtio | Supported default harness map |
| **sifive_u** | `sifive_u` | Board port | **Smoke** | SiFive UART0 @ `0x10010000`, CLINT/PLIC via **`RVSifivePlat`** | No virtio/ramfb; `make kernel-plat-sifive-u-smoke` |
| **sifive_e** | `sifive_e` | Board port | Tentative | Same **`RVSifivePlat`** API; UART @ `0x10013000`, PLIC | Tiny DTIM (~16 KiB) — image does not fit |
| **spike** | `spike` | Emulator | Tentative | HTIF console, CLINT | No PLIC/virtio; experimental HTIF driver |
| **shakti_c** | `shakti_c` | Board port | Tentative | CLINT/PLIC virt-like | Shakti UART @ `0x11300` → UART **stub** |
| **microchip-icicle-kit** | `microchip_icicle` | Board port | Tentative | CLINT/PLIC; MMUART0 best-guess 16550 @ `0x20000000` | Needs **hss.bin**; bare `-bios none` fails in harness |
| **xiangshan-kunminghu** | `xiangshan` | Board port | Tentative | 16550 @ `0x310B0000` (regshift 2), ACLINT @ `0x38000000` | APLIC/IMSIC — PLIC **stub**; RX may need spaced 16550 |
| **amd-microblaze-v-generic** | `amd_microblaze_v` | Board port | Tentative | 16550 @ `0x44A11000` (serial1) | UARTLite is serial0; no PLIC/CLINT |
| **opentitan** | `opentitan` | Board port | Tentative | PLIC @ `0x48000000`; DRAM 128 KiB @ `0x10000000` | Ibex UART → **stub**; image does not fit — see [RV32.md](RV32.md) |
| **host** | `host` | Legacy stub | — | — | Completeness only |

Harness binary / `-M` strings for each defconfig: `make -C templeos-riscv qemu-args` (and
[CI.md](../docs/CI.md)). Milk-V / VisionFive: `PLATFORM_CUSTOM` + `RVFbSimpleFbBind` —
[BOARD_FB.md](BOARD_FB.md).

### Added vs already present

| Already had | Added this pass |
|-------------|-----------------|
| virt, sifive_u, sifive_e, spike, shakti_c, microchip_icicle, xiangshan, host | **amd_microblaze_v**, **opentitan** |
| PLATFORM.md sketch | Full status table + wired/stub notes |
| `defconfig-{virt,sifive_u,spike,sifive_e}` | Pattern `defconfig-%` for **all** machines + `list-defconfigs` |

## Run

### Default CI profile (`virt`)

```bash
make -C templeos-riscv defconfig
make kernel-print-smoke
make kernel-plat-smoke          # HolyC Drv UART+CLINT on CI default map
```

### sifive_u (second machine — HolyC smoke)

```bash
make kernel-plat-sifive-u-smoke
# Restores virt defconfig afterward
```

Exercises `RVUart*` / `RVClint*` plus, when `RVSifivePresent`, the named
`RVSifiveUart*` / `RVSifiveClint*` API (`Kernel/Drv/RVSifivePlat.*`). Dig-down:
`Man("SiFive")` (REPL topic) / `RVMemMap` driver column `RVSifivePlat`.

### Tentative ports (config / build; no CI smoke)

```bash
make -C templeos-riscv defconfig-xiangshan
make -C templeos-riscv qemu-args
# → suggested harness argv for that profile

make -C templeos-riscv defconfig-amd_microblaze_v
make -C templeos-riscv qemu-args

make -C templeos-riscv defconfig-opentitan
make -C templeos-riscv qemu-args

make -C templeos-riscv defconfig   # restore CI default
```

After building a HolyC blob that `#include`s `Kernel_RV.PRJ`, load the ELF with your
board’s boot path or the harness argv from `qemu-args`. Tentative boards may hang or
print nothing without matching UART hardware; that is expected until a real driver lands.
Prefer extending `Kernel/Drv/*` stubs over inventing C drivers.
