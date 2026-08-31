# Platform Kconfig tutorial

How this repo selects a **RISC-V board / memory map** and wires HolyC device drivers.
This is **not** Linux Kconfig — it is a small Python tool (`scripts/kconfig.py`) that
speaks a familiar subset of Kconfig syntax.

Machine status tables live in [PLATFORM.md](PLATFORM.md) (**board ports** vs **emulator
targets for CI**). Framebuffer board notes: [BOARD_FB.md](BOARD_FB.md). Proposed
`ARCH_RISCV32` / virt-style map work: [RV32.md](RV32.md).

## 1. What it is for

Kconfig answers: *which platform am I targeting, and what MMIO / drivers does the OS use?*

| Concern | Examples |
|---------|----------|
| Platform | `virt` (CI harness map), `sifive_u`, `spike`, … → `CONFIG_PLATFORM_*` |
| Console | UART kind + base + IRQ |
| Timer / IRQ | CLINT offsets, PLIC (or stub), timebase Hz |
| Storage / FB | virtio-mmio/PCI, fw_cfg/ramfb vs simplefb vs none |
| Link map | DRAM base/size, kernel entry, soft FB base, `SYS_FIXED_AREA` |
| Editors | Default `Src` / `DirEd` / `FunEd` editor (`Vi` / `Edit` / `Ed`) |

`CONFIG_QEMU_MACHINE` / `make qemu-args` exist so CI can print harness argv — they are
not the product API. Drivers speak `MEM_*` / `CONFIG_*` / `RV_*`.

**OS device drivers are HolyC** under `Kernel/Drv/*`, parameterized by generated
`Kernel/RVAutoConf.HH`. There is **no** multi-machine C driver stack in
`templeos-riscv/kernel/` — that C tree is a guest-loader bootstrap.

## 2. Where files live

| Path | Role |
|------|------|
| `templeos-riscv/Kconfig` | Menus: memory map, UART, CLINT/PLIC, virtio, FB, editors, harness helpers |
| `templeos-riscv/Kconfig.machines` | `choice` of `PLATFORM_*` (sourced by `Kconfig`) |
| `templeos-riscv/configs/*_defconfig` | Board / profile presets (partial `.config` fragments) |
| `templeos-riscv/.config` | Resolved symbol values (generated; do not hand-edit long-term) |
| `templeos-riscv/include/generated/autoconf.h` | C `#define`s for the bootstrap image only |
| `Kernel/RVAutoConf.HH` | HolyC `#define`s — included first by `Kernel/Kernel_RV.PRJ` |
| `Kernel/Drv/*Selected.HH` | File-level driver pick (`#include` one `.HC` implementation) |
| `bootstrap/seed/RVEditorSelected.hc` | REPL `editor=&Vi;` (etc.) |
| `templeos-riscv/scripts/kconfig.py` | Parser + `defconfig` / `menuconfig` / `sync` / `qemu-args` |

```
Kconfig + Kconfig.machines + configs/foo_defconfig
        │
        ▼
   scripts/kconfig.py  (defconfig | menuconfig | sync)
        │
        ├── templeos-riscv/.config
        ├── include/generated/autoconf.h     (C bootstrap)
        ├── Kernel/RVAutoConf.HH             (HolyC OS)
        ├── Kernel/Drv/*Selected.HH
        └── bootstrap/seed/RVEditorSelected.hc
```

## 3. Workflow

### From repo root

```bash
make menuconfig-rv                 # → make -C templeos-riscv menuconfig
```

### From `templeos-riscv/`

```bash
make defconfig                     # same as defconfig-virt (CI default)
make defconfig-virt
make defconfig-sifive_u
make defconfig-spike               # experimental HTIF
make defconfig-sifive_e            # experimental (tiny DTIM)
make menuconfig                    # interactive TUI (stdin)
make syncconfig                    # re-resolve .config → headers + Selected.HH
make qemu-args                     # print suggested harness -M / extra args
```

Makefile wrappers cover the common boards. Any `configs/*_defconfig` also works via:

```bash
python3 scripts/kconfig.py defconfig shakti_c
python3 scripts/kconfig.py list-defconfigs
```

`defconfig` / `menuconfig` / `sync` all rewrite `.config` **and** the generated headers.
If `.config` is missing, the Makefile rule and `sync` fall back to **virt**.

### How choices reach HolyC

1. **Defines** — `RVAutoConf.HH` emits `CONFIG_*` and aliases such as `RV_CFG_UART_BASE`.
   Drivers and boot code use those for addresses and feature flags (`#ifdef CONFIG_HAS_PLIC`,
   `RISCV_VIRT` when `PLATFORM_VIRT`, etc.).

2. **Whole-file select** — HolyC AOT must **not** wrap function bodies in `#ifdef`
   (that produces unresolved imports). Instead `kconfig.py` writes e.g.:

   ```text
   // Kernel/Drv/RVUartSelected.HH
   #include "RVUart16550.HC"
   ```

   Entry files (`RVUart.HC`, `RVPlic.HC`, `RVVirtioPlat.HC`, `RVFbPlat.HC`) include the
   `*Selected.HH` shim. `Kernel_RV.PRJ` pulls in `Drv/RV*.HC` after `RVAutoConf.HH`.

3. **Editor seed** — Editors choice → `CONFIG_EDITOR_*` plus `RVEditorSelected.hc` for REPL boot.

### Typical edit loop

```bash
cd templeos-riscv
make defconfig-sifive_u            # or menuconfig → pick PLATFORM_SIFIVE_U → s
# rebuild any HolyC that #includes Kernel_RV.PRJ / RVAutoConf.HH
make -C .. kernel-plat-sifive-u-smoke
make defconfig                     # restore CI default for other smokes
```

## 4. How to add a machine (minimal port)

Assume a platform you can already boot (board firmware or CI harness with `-bios none -kernel`).

1. **`Kconfig.machines`** — add `config PLATFORM_FOO` under the machine `choice`,
   with help text (UART/DRAM guesses, experimental or not). Extend `PLATFORM_NAME`
   defaults and, if experimental, `PLATFORM_EXPERIMENTAL`.

2. **`Kconfig`** — wire conditional defaults:
   - UART choice defaults (`UART_SIFIVE if PLATFORM_FOO`, …)
   - `UART_BASE` / `UART_IRQ` / `TIMEBASE_FREQ`
   - `HAS_PLIC`, virtio, fw_cfg, FB present defaults
   - Optional `QEMU_MACHINE` / `QEMU_EXTRA_ARGS` for harness argv only

3. **`configs/foo_defconfig`** — minimal fragment (platform + UART + feature bools).
   Hex addresses usually come from Kconfig `default … if PLATFORM_FOO`.

4. **Makefile (optional)** — `defconfig-foo:` → `$(KCONFIG) defconfig foo` for discoverability.

5. **HolyC driver** — reuse an existing UART/PLIC/FB kind if possible. New hardware needs a
   new `Kernel/Drv/RVUart*.HC` (etc.) **and** a branch in `write_drv_selecteds()` in
   `scripts/kconfig.py`. Prefer new files over `#ifdef` around function bodies.
   SiFive boards share **`RVSifivePlat`** (`RVSifiveYes` when `UART_SIFIVE` /
   `PLATFORM_SIFIVE_*`) — named UART/CLINT/PLIC API; `RVUartSifive` thin-wraps it.
   `Man("SiFive")` / MemMap column `RVSifivePlat`.

6. **Smoke** — extend `tests/scripts/run_kernel_plat_smoke.sh` (today: `virt` | `sifive_u`)
   and/or add a root `Makefile` target. Keep **virt** as the restored default after non-default runs.

7. **Docs** — add a row to [PLATFORM.md](PLATFORM.md); label **board port** vs **emulator (CI)**; link here for the mechanism.

Tentative / stub boards (`shakti_c`, `microchip_icicle`, …) already follow this pattern with
UART stub + FB none — useful as templates before a real console driver exists.

## 5. How smokes use it

| Target | What it does |
|--------|----------------|
| `make kernel-plat-smoke` | `defconfig-virt`, compile `tests/exec/cases/kernel_plat_demo.hc`, load on CI default map, expect `plat-smoke: PASS` |
| `make kernel-plat-sifive-u-smoke` | Same with `defconfig-sifive_u`; **restores virt** on exit |

The demo includes `RVAutoConf.HH` + `Drv/RVSifivePlat.HC` + `Drv/RVUart.HC` +
`Drv/RVTimer.HC` (not full `Kernel_RV.PRJ`). It prints `CONFIG_PLATFORM_NAME`,
touches CLINT `mtime`, and on SiFive also exercises `RVSifiveUart*` /
`RVSifiveClint*`.

Other kernel `*-smoke` targets assume the **default virt-style** addresses and devices unless they run the
plat script. After experimenting with another defconfig, always:

```bash
make -C templeos-riscv defconfig
```

so CI-oriented builds see the default profile again.

`make -C templeos-riscv qemu` uses `qemu-args` from the current `.config` for the C
bootstrap ELF — still a harness path; multi-machine proof for the **OS**
is the HolyC plat smoke path above.

## 6. What host C does *not* do

- **No** `templeos-riscv/drivers/` (or similar) multi-board UART/PLIC/virtio stack in C.
- `include/generated/autoconf.h` feeds the **bootstrap** C image (link addresses, probes).
- Multi-machine bring-up for TempleOS/RV is **`Kernel/RVAutoConf.HH` + `Kernel/Drv/*`**.
- Host `holyc-riscv` is the AOT bootstrap compiler; it does not replace guest `Compiler_RV`
  long-term — see [COMPILER_RV.md](COMPILER_RV.md).

## Quick reference

```bash
# Interactive
make menuconfig-rv

# CI default profile
make -C templeos-riscv defconfig

# Second machine (board port)
make kernel-plat-sifive-u-smoke

# After hand-editing .config
make -C templeos-riscv syncconfig
```
