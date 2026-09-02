# Multi-platform Kconfig (RISC-V boards)

TempleOS/RV targets **real RISC-V platforms** via **Kconfig** + **HolyC drivers**.
There is **no** C device-driver stack for the OS: UART / CLINT / PLIC / virtio / FB
present selection live under `Kernel/Drv/*.HC`, parameterized by generated defines.

**Emulator targets for CI** (machine names such as `virt`) share the same Kconfig so
smokes can load ELF images without hardware. They are harness profiles, not the
product definition. Prefer speaking in `MEM_*` / `CONFIG_*` / board names in Help and Man.

RV32 / ILP32 port plan (virt-style map first; OpenTitan is tiny-profile only): [RV32.md](RV32.md).
Multi-arch beyond RISC-V (ARM / PPC order, shared scaffolding): [MULTIARCH.md](../docs/MULTIARCH.md).

| Output | Role |
|--------|------|
| `templeos-riscv/.config` | Saved symbol values |
| `templeos-riscv/include/generated/autoconf.h` | C `#define`s (link addresses for the C *bootstrap* image only) |
| `Kernel/RVAutoConf.HH` | HolyC `#define`s — included first by `Kernel_RV.PRJ` |

Default profile is always **`virt`** so existing `make kernel-*-smoke` / CI stay green.

## Multi-kernel layout (one image per machine)

Kconfig still has a **single active** `.config` / `Kernel/RVAutoConf.HH` (HolyC includes
those paths). The **build system** packages one durable artifact per profile so flipping
defconfig does not stomp the only ELF on disk:

| Path | Role |
|------|------|
| `build/kernels/<machine>/plat.elf` | Plat-demo HolyC kernel for that board |
| `build/kernels/<machine>/.config` | Snapshot of the defconfig used |
| `build/kernels/<machine>/RVAutoConf.HH` | Snapshot of generated HolyC defines |
| `build/kernels/<machine>/DrvSelected/` | Snapshot of `*Selected.HH` shims |
| `build/kernels/<machine>/qemu-args.txt` | Suggested harness `-M` / extras |
| `build/exec/<machine>_plat.elf` | Convenience copy (also `plat-<machine>.elf`) |

```bash
make list-kernels                 # machines + which ELFs exist
make kernel-virt                  # → build/kernels/virt/plat.elf
make kernel-sifive_u
make kernel-spike
make kernels                      # all KERNEL_BUILD_MACHINES (see Makefile)
make -C templeos-riscv qemu-args-sifive_u   # print -M without writing .config
```

Smokes call `tests/scripts/build_kernel_plat.sh` then load the matching ELF + QEMU `-M`.
Each build restores the previous `.config` (usually virt). Tentative / firmware-needed
machines may still **build** an ELF while `kernel-plat-*-smoke` prints **SKIP**.

## Configure

```bash
make -C templeos-riscv defconfig                 # virt (CI default profile)
make -C templeos-riscv defconfig-sifive_u        # SiFive UART0 @ 0x10010000
make -C templeos-riscv defconfig-spike           # HTIF tohost @ 0x807FF000
make -C templeos-riscv defconfig-amd_microblaze_v
make -C templeos-riscv defconfig-opentitan       # RV32 tiny profile
make -C templeos-riscv defconfig-none            # empty machine (skip)
make -C templeos-riscv list-defconfigs
make -C templeos-riscv menuconfig                # pick machine + tweak hex addresses
make -C templeos-riscv syncconfig                # refresh autoconf + RVAutoConf.HH + MemMapSelected.hc
make -C templeos-riscv qemu-args                 # prints suggested harness argv for CI/local smokes
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
| `VirtioNet.HC` | virtio-mmio net TX/RX (`CONFIG_HAS_VIRTIO_NET`) |
| `VirtioInput.HC` | virtio-mmio input event poll (`CONFIG_HAS_VIRTIO_INPUT`) |
| `Virtio9p.HC` | virtio-mmio 9p2000.l client — host virtfs import (`CONFIG_HAS_VIRTIO_9P`) |
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

Inventory checked against **QEMU 10.1.3** `qemu-system-riscv64 -M help` and
`qemu-system-riscv32 -M help`. Status meanings:

| Status | Meaning |
|--------|---------|
| **CI** | In default `qemu-integration` / `make kernel-plat-smoke` |
| **Smoke** | Extra `make kernel-plat-*-smoke` proven locally; not required for default CI |
| **Tentative** | Defconfig + drivers/stubs; no bare-metal plat smoke yet |
| **Skip** | Defconfig for inventory only; plat script exits 0 with reason |

| Machine / profile | Defconfig | Kind | Status | Wired | Stub / notes |
|-------------------|-----------|------|--------|-------|--------------|
| **virt** | `virt` | Emulator (CI) | **CI** | 16550 @ `CONFIG_UART_BASE`, CLINT, PLIC, fw_cfg/ramfb, virtio-blk/net/input | Supported default harness map |
| **sifive_u** | `sifive_u` | Board port | **Smoke** | SiFive UART0 @ `0x10010000`, CLINT/PLIC via **`RVSifivePlat`** | No virtio/ramfb; `make kernel-plat-sifive-u-smoke` |
| **spike** | `spike` | Emulator | **Smoke** | HTIF `tohost` @ `0x807FF000` (ELF symbols in harness `crt0.S` + `link_exec.ld`), CLINT | No PLIC/virtio; `make kernel-plat-spike-smoke` |
| **sifive_e** | `sifive_e` | Board port | **Skip** | Same **`RVSifivePlat`** API; UART @ `0x10013000`, PLIC | Tiny DTIM (~16 KiB) — image does not fit |
| **shakti_c** | `shakti_c` | Board port | **Skip** | CLINT/PLIC virt-like | Shakti UART @ `0x11300` → UART **stub** |
| **microchip-icicle-kit** | `microchip_icicle` | Board port | **Skip** | CLINT/PLIC; MMUART0 best-guess 16550 @ `0x20000000` | Needs **hss.bin**; bare `-bios none` fails |
| **xiangshan-kunminghu** | `xiangshan` | Board port | **Tentative** | 16550 @ `0x310B0000` (regshift 2), ACLINT @ `0x38000000` | APLIC/IMSIC — PLIC **stub**; RX may need spaced 16550 |
| **amd-microblaze-v-generic** | `amd_microblaze_v` | Board port | **Skip** | 16550 @ `0x44A11000` (serial1) | UARTLite is serial0; no PLIC/CLINT — plat demo needs CLINT |
| **opentitan** | `opentitan` | Board port | **Skip** | PLIC @ `0x48000000`; DRAM 128 KiB @ `0x10000000` | Ibex UART → **stub**; riscv32; image does not fit — [RV32.md](RV32.md) |
| **none** | `none` | Emulator | **Skip** | — | QEMU empty machine; no CPU/RAM until devices added |
| **host** | `host` | Legacy stub | **Skip** | — | Not in QEMU 10.x `-M help`; completeness only |

Harness binary / `-M` strings for each defconfig: `make -C templeos-riscv qemu-args` (and
[CI.md](../docs/CI.md)). Full inventory probe: `make kernel-plat-matrix`. Milk-V /
VisionFive: `PLATFORM_CUSTOM` + `RVFbSimpleFbBind` — [BOARD_FB.md](BOARD_FB.md).

### QEMU `-M` vs this tree (QEMU 10.1.3)

| `qemu-system-riscv64 -M` | In-tree |
|--------------------------|---------|
| amd-microblaze-v-generic | yes (`amd_microblaze_v`) |
| microchip-icicle-kit | yes (`microchip_icicle`) |
| none | yes (`none`) |
| shakti_c | yes |
| sifive_e | yes |
| sifive_u | yes |
| spike | yes |
| virt | yes |
| xiangshan-kunminghu | yes (`xiangshan`) |

| `qemu-system-riscv32 -M` | In-tree |
|--------------------------|---------|
| amd-microblaze-v-generic | yes (same defconfig; still RV64 codegen today) |
| none | yes |
| opentitan | yes |
| sifive_e / sifive_u / spike / virt | yes (same names; RV32 emit not started — [RV32.md](RV32.md)) |

### Added vs already present

| Already had | This pass |
|-------------|-----------|
| virt, sifive_u, sifive_e, spike, shakti_c, microchip_icicle, xiangshan, amd_microblaze_v, opentitan, host | **none** defconfig; spike HTIF→ELF `tohost`; plat matrix |
| Kconfig UART/CLINT/PLIC/virtio/fw_cfg | **HEAP/MEMFS/HOST_SLOTS/SMP_MAILBOX/STACK**, **VIRTIO_MMIO_IRQ_BASE**, **VIRTIO_DRV_RAM_BASE**; `MEM_*` aliases in `RVAutoConf.HH` |
| `kernel-plat-smoke` + sifive_u | **`kernel-plat-spike-smoke`**, **`kernel-plat-matrix`** |

## Fill-gap plan (CSR / asm / virtio / SMP)

Ordered session plan from the unexposed-RV + virt-device audit. Prefer HolyC
`Kernel/Drv` over new C drivers.

1. **CSR exposure** — named Get/Set for `medeleg`/`mideleg`/`mcounteren`,
   `mcycle`/`minstret` (and readable `cycle`/`instret` aliases), plus S-mode
   `sstatus`/`sie`/`stvec`/`sepc`/`scause`/`stval`/`sip` (OS may stay M-mode).
2. **`asm{}` expansion** — A-ext LR/SC + AMO subset, `lui`/`auipc`, CSR imm
   forms; sync guest `Compiler/Asm_RV.HC` with host where feasible. **Done for
   host + guest A-ext used by LXchg/LBts/`lock`.**
3. **Man topics** — new CSRs/opcodes + VirtioNet / VirtioInput + **SMP/atomics**.
4. **virtio-net (mmio, legacy)** — TX/RX + `RxDrain`/`SetRxCb` + PLIC ACK helpers;
   smoke TX + RX self-test (`make kernel-virtio-net-smoke`). Trap-vector IRQ RX deferred.
5. **virtio-input (mmio)** — keyboard/mouse event poll into UART / Term path
   (`make kernel-virtio-input-smoke`).
6. **Phase G SMP** — crt0_smp + `RVSmpWake` + optional `kernel-smp-smoke`.
   Residual: Seth JobQue, `mp_cnt` finalize, mie.MSIE WFI wake polish, OpenSBI HSM.
7. **Defer** — HolyC virtio-blk PCI, virtio-console/rng/gpu, AIA, full S-mode
   OS (document residual below).

## Multi-hart / SMP (Phase G)

TempleOS is **master/slave**, not Linux SMP: hart 0 runs UART REPL / OS; secondaries park then run Seth-style jobs.

| Path | Notes |
|------|--------|
| **QEMU virt `-bios none -smp N`** | All harts enter `tests/exec/harness/crt0_smp.S` (or REPL `bootstrap/startup.s`). Hart 0 clears BSS / runs the blob; others take per-hart stacks and poll a mailbox at `CONFIG_SMP_MAILBOX_BASE` (default `0x87001E00`). Wake: `RVSmpWake` + CLINT MSIP. |
| **OpenSBI HSM** | Use when firmware owns secondary bring-up (not the `-bios none` smoke path). |
| **Atomics** | `LXchgI64` = `amoswap.d`; `LBts`/`LBtr`/`LBtc` = LR.W/SC.W; HolyC `lock` = amoswap spin near host-slots (`0x87001F00` on transitional REPL). |
| **Smoke** | Optional: `make kernel-smp-smoke` (not in default `qemu-integration`). |

HolyC API: `Kernel/Drv/RVSmp.HC` (`RVHartId`, `RVSmpWake`, `RVAmoAddI64`, …). Man: `Man("SMP")`.

## Firmware / BIOS

TempleOS can be packaged as **firmware** for QEMU virt instead of only a RAM-linked
ELF for `-kernel`. For **FPGA OpenOCD RAM load** and **bare QEMU** (`-bios none
-kernel`), use `make baremetal` → `build/baremetal/repl.{elf,bin}` — see
[docs/BAREMETAL.md](../docs/BAREMETAL.md).

Two boot paths exist on QEMU 8+ virt:

| Artifact | Linked at | QEMU invocation | Mode |
|----------|-----------|-----------------|------|
| `build/baremetal/repl.elf` | `0x80000000` (DRAM) | `-bios none -kernel repl.elf` | M-mode, RAM (FPGA/OpenOCD primary) |
| `build/baremetal/repl.bin` | `0x80000000` (flat) | `-bios none -kernel repl.bin` | M-mode, RAM flat |
| `build/firmware/templeos-bios.elf` | `0x80000000` (DRAM) | `-bios templeos-bios.elf` | M-mode, RAM-loaded |
| `build/firmware/templeos-bios.bin` | `0x80000000` (flat) | `-bios templeos-bios.bin` | M-mode, RAM-loaded |
| `build/firmware/templeos-fw.bin` | `0x20000000` (flash) | `-bios none -drive if=pflash,...` | M-mode, flash ROM |
| `build/firmware/templeos-fw.elf` | `0x20000000` | debug / `objdump` | flash-linked ELF |

Build (default payload = bare-metal REPL linked at `0x80000000`):

```bash
make baremetal         # build/baremetal/repl.elf + repl.bin (RAM / OpenOCD / -kernel)
make baremetal-smoke    # -kernel repl.bin + REPL 1+1 oracle
make firmware          # alias: make bios — flash ROM + bios copies
make firmware-smoke    # pflash boot + REPL 1+1 oracle
make bios-smoke        # -bios RAM payload + REPL 1+1 oracle
tests/scripts/qemu-baremetal.sh     # -bios none -kernel (default)
tests/scripts/qemu-bios.sh          # -bios launcher (default)
tests/scripts/qemu-bios.sh --pflash # pflash launcher
```

Other payloads: `make -C bootstrap -f Makefile.firmware PAYLOAD=plat firmware`
(after `build/kernels/virt/plat.elf` exists).

### QEMU virt reset behavior (QEMU 10.x)

QEMU virt reset always starts in **M-mode**. The mask ROM at `0x1000` loads
`fw_dynamic` metadata and jumps to a **start address**:

| Command | Reset `start_addr` | What runs |
|---------|-------------------|-----------|
| `-bios none -drive if=pflash,file=fw.bin` | `0x20000000` (flash base) | M-mode code in pflash0 |
| `-bios payload.elf` (no pflash) | payload ELF entry (typically `0x80000000`) | M-mode payload in DRAM |
| `-bios opensbi.bin` (default) | OpenSBI entry in DRAM | M-mode OpenSBI → S-mode guest |
| `-bios fw.bin -drive if=pflash,...` | OpenSBI in DRAM; `kernel_entry = 0x20000000` | OpenSBI jumps to **S-mode** @ flash — wrong for our M-mode stub |

**Do not** pass `templeos-fw.bin` to `-bios`: QEMU loads raw `-bios` images into DRAM
@ `0x80000000`, but the flash image is linked for `0x20000000` — addresses are wrong
and the guest hangs. Use `templeos-bios.elf` for `-bios`, or pflash for the ROM image.

### Flash ROM path (pflash)

Reset vector in flash at `0x20000000` (`bootstrap/firmware_stub.S`) copies the flat RAM
payload to `0x80000000` and jumps to `_start`; payload startup clears BSS and runs
`main` as with `-bios none -kernel`.

```bash
# M-mode firmware in pflash0 — reset vector @ 0x20000000
qemu-system-riscv64 -M virt -m 128M -bios none \
  -drive if=pflash,format=raw,file=build/firmware/templeos-fw.bin -nographic
```

The image is padded to **32 MiB** (virt `pflash0` size). On QEMU 8+, when pflash is
present and `-bios` is **not** `none`, QEMU assumes pflash0 holds an **S-mode** payload
(EDK2 convention) and OpenSBI owns M-mode — use **`-bios none` + pflash** for our
M-mode flash stub.

### RAM BIOS path (`-bios`)

```bash
qemu-system-riscv64 -M virt -m 128M \
  -bios build/firmware/templeos-bios.elf -nographic
```

Equivalent to `-bios none -kernel repl.elf` for the default REPL payload: QEMU loads
the ELF into DRAM and the reset vector jumps straight to `_start` in M-mode.

**Linker layout (`templeos-fw.elf`):**

| Section | VMA | Contents |
|---------|-----|----------|
| `.text.init` | `0x20000000` | `firmware_stub.S` — copy loop + jump to RAM |
| `.fw_payload` | `0x20000046` | Flat binary of REPL/plat ELF (linked @ `0x80000000`) |

Payload runtime in RAM: `.text` / `.rodata` / `.data` copied to `0x80000000`; `.bss`
cleared by payload `_start` (`bootstrap/startup.s` or harness `crt0.S`).

On real boards with NOR flash at a board-specific base, override
`FLASH_BASE` / `RAM_BASE` in `bootstrap/Makefile.firmware`.

## Run

### Default CI profile (`virt`)

```bash
make -C templeos-riscv defconfig
make kernel-print-smoke
make kernel-plat-smoke          # HolyC Drv UART+CLINT on CI default map
```

### sifive_u / spike (extra machines — HolyC smoke)

```bash
make kernel-sifive_u              # leave ELF under build/kernels/sifive_u/
make kernel-spike
make kernel-plat-sifive-u-smoke   # rebuild if needed + QEMU -M sifive_u
make kernel-plat-spike-smoke      # HTIF console + CLINT
make kernel-plat-matrix           # every known -M: OK or SKIP+why
```

Exercises `RVUart*` / `RVClint*` plus, when `RVSifivePresent`, the named
`RVSifiveUart*` / `RVSifiveClint*` API and reset-capability probes
(`RVSifiveCanReset` — does **not** call `RVSifiveReset`). Dig-down:
`Man("SiFive")` / `Man("Reset")` (REPL topics) / `RVMemMap` driver column
`RVSifivePlat`.

**SiFive reset / halt / fault (board first):**

| Call | sifive_u | sifive_e / FE310 | Notes |
|------|----------|------------------|-------|
| `RVSifiveReset` | GPIO active-low pin (default 10 @ `0x10060000`) | AON WDT RSTEN @ `0x10000000` | Soft REPL `Reset;` is Boot re-entry only |
| `RVSifiveHalt` | `wfi` park | same | |
| `RVSifiveFault` | illegal insn | same | Pair with `SetTrap` / `TrapInit` |
| Test finisher `0x100000` | **absent** | **absent** | Sim/virt harness only (`HardReset;` / `CONFIG_SIFIVE_TEST_BASE`) |

Do not poke `0x10000000` as AON on sifive_u — that window is PRCI on FU540 maps.

### Tentative ports (config / build; no CI smoke)

```bash
make kernels                      # also builds tentative boards that compile
make -C templeos-riscv qemu-args-xiangshan
make -C templeos-riscv qemu-args-amd_microblaze_v
make -C templeos-riscv qemu-args-opentitan   # resolves defconfig; no .config write

# Or interactive / active-tree configure (rewrites global headers):
make -C templeos-riscv defconfig-xiangshan
make -C templeos-riscv qemu-args
make -C templeos-riscv defconfig   # restore CI default
```

Load `build/kernels/<machine>/plat.elf` with the harness argv from `qemu-args-<machine>`
(or your board boot path). Tentative boards may hang or print nothing without matching
UART hardware; that is expected until a real driver lands. Prefer extending
`Kernel/Drv/*` stubs over inventing C drivers.

## Magic numbers → Kconfig

| Concern | Kconfig / define | Must stay fixed (document) |
|---------|------------------|----------------------------|
| UART / CLINT / PLIC / virtio / fw_cfg / RTC | `CONFIG_*_BASE`, `TIMEBASE_FREQ`, IRQ | — |
| Virtio PLIC IRQ math | `CONFIG_VIRTIO_MMIO_IRQ_BASE` | — |
| Virtio driver scratch RAM | `CONFIG_VIRTIO_DRV_RAM_BASE` (needs `-m`≥256M on virt) | — |
| DRAM / link / soft FB / heap / memfs / stack | `CONFIG_DRAM_*`, `KERNEL_*`, `HEAP_BASE`, `MEMFS_BASE`, `STACK_BASE` | — |
| SMP mailbox | `CONFIG_SMP_MAILBOX_BASE` | `crt0_smp.S` `.equ` must match by hand |
| Transitional REPL host slots | `CONFIG_HOST_SLOTS_BASE` | `worry_dream_repl.c` + seed still poke `0x87001xxx` literally until REPL migrates off slots |
| Seed `bootstrap/seed/MemMapSelected.hc` `MEM_*` | Same bases as `RVAutoConf.HH` | Regenerated by `defconfig` / `syncconfig`; rebuild `repl.elf` after board flip |
| SiFive test / AON / GPIO reset | `CONFIG_SIFIVE_*` | — |


## Real vs still missing (fill-gap pass)

| Area | Now real | Still missing / deferred |
|------|----------|--------------------------|
| **CSR HolyC API** | M trap set + `medeleg`/`mideleg`/`mcounteren`, `mcycle`/`minstret`/`cycle`/`instret`, S mirrors `sstatus`/`sie`/`stvec`/`sepc`/`scause`/`stval`/`sip` | PMP, FCSR, H-ext, AIA CSRs, full S-mode OS/SBI |
| **`asm{}`** | A-ext LR/SC + AMO (dotted or undotted), `lui`/`auipc`, CSR imm (`csrrwi`/`csrwi`…) on host + guest `Asm_RV.HC` | RVC emit, V, full F, W-ops, generic `fence` |
| **virtio-mmio blk** | `DskVirtioRV` (unchanged) | HolyC virtio-**PCI** blk |
| **virtio-net** | `Kernel/Drv/VirtioNet.HC` TX/RX + `RxDrain`/`SetRxCb`/`RxSelfTest` + `IrqAck`/`IrqService` (+ `IrqInit` PLIC enable); smoke TX + RX self-test (`make kernel-virtio-net-smoke`) | TCP/IP stack, PCI net, live SLIRP RX gate, trap-vector IRQ RX (`IrqInit` needs RVTrapInit+MEIE — do not enable PLIC without a handler) |
| **virtio-input** | `Kernel/Drv/VirtioInput.HC` poll + `make kernel-virtio-input-smoke` | Term key integration, tablet absolute map |
| **virtio-9p** | `Kernel/Drv/Virtio9p.HC` 9P2000.L **client** (host → guest virtfs) + `make kernel-virtio-9p-smoke` | Guest-as-9p-server (export memfs), PCI 9p, TCP 9p, VFS mount glue |
| **Other virt attachables** | — | gpu, rng, console, balloon, USB, NVMe, AIA |

Enable / test:

```bash
make -C templeos-riscv defconfig   # HAS_VIRTIO_NET / HAS_VIRTIO_INPUT / HAS_VIRTIO_9P default y on virt
make kernel-virtio-net-smoke       # UART oracle: virtio-net: tx_ok + rx_ok
make kernel-virtio-input-smoke     # UART oracle: virtio-input: ready
make kernel-virtio-9p-smoke        # UART oracle: virtio-9p: read_ok (host virtfs)
# REPL: Man("VirtioNet"); Man("Virtio9p"); Man("CSR"); Man("AsmRV");
```

### 9p / virtfs (Phase A — guest client)

QEMU shares a **host directory into the guest** over virtio-9p (not IP). The guest HolyC driver is a **9p client**; QEMU’s 9p backend is the server.

```bash
mkdir -p /tmp/tos-share
echo 'hello from 9p' >/tmp/tos-share/test.txt

qemu-system-riscv64 -M virt -m 256M -bios none -kernel build/exec/kp.elf -nographic \
  -fsdev local,id=fsdev0,path=/tmp/tos-share,security_model=none \
  -device virtio-9p-device,fsdev=fsdev0,mount_tag=hostshare
```

PCI attach (same protocol): replace `-device virtio-9p-device,...` with `-device virtio-9p-pci,...` (needs `-device virtio-pci` bus on virt).

**Not implemented:** guest exporting REPL memfs or RedSea over 9p (needs a 9p **server** in HolyC); mounting host files into `fs.hc` memfs automatically; TCP `9p` over virtio-net (would need a full IP stack + different transport).
