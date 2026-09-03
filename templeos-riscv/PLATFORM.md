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
| `build/kernels/<machine>/plat.bin` | Flat RAM image (`objcopy -O binary`; gaps zero-filled ~8 MiB). Useful for `-device loader,addr=ENTRY,file=…`. **Not** a size fix for tiny DTIM. |
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
make kernel-visionfive2           # board-only JH7110 plat.elf (no QEMU smoke yet)
make -C templeos-riscv qemu-args-sifive_u   # print -M without writing .config
```

Smokes call `tests/scripts/build_kernel_plat.sh` then load the matching ELF + QEMU `-M`.
Each build restores the previous `.config` (usually virt). Every matrix board must
smoke green (`plat-smoke: PASS`); see [DRIVERS.md](../docs/DRIVERS.md).
Board-only profiles (VisionFive 2) build/link but stay **out of** `kernel-plat-matrix`
until a green smoke exists — do not add skip=OK.

## Configure

```bash
make -C templeos-riscv defconfig                 # virt (CI default profile)
make -C templeos-riscv defconfig-sifive_u        # SiFive UART0 @ 0x10010000
make -C templeos-riscv defconfig-spike           # HTIF tohost @ 0x807FF000
make -C templeos-riscv defconfig-amd_microblaze_v
make -C templeos-riscv defconfig-opentitan       # RV32 tiny profile
make -C templeos-riscv defconfig-visionfive2     # JH7110 board (no QEMU -M)
make -C templeos-riscv defconfig-none            # empty machine (inventory only)
make -C templeos-riscv list-defconfigs
make -C templeos-riscv menuconfig                # pick machine + tweak hex addresses
make -C templeos-riscv syncconfig                # refresh autoconf + RVAutoConf.HH + MemMapSelected.hc
make -C templeos-riscv qemu-args                 # prints suggested harness argv for CI/local smokes
```

From the **repo root**: `make menuconfig`

## HolyC drivers (`Kernel/Drv/`)

| File | Role |
|------|------|
| `RVSifivePlat.HC` → `RVSifiveSelected.HH` | SiFive UART/CLINT/PLIC **named** facade (`RVSifiveYes` on `sifive_u`/`e`) |
| `RVUart.HC` → `RVUartSelected.HH` | Includes 16550 / SiFive / HTIF / stub |
| `RVUart16550.HC` / `RVUartSifive.HC` / … | Concrete UART drivers (`RVUartIbex` for OpenTitan) |
| `RVTimer.HC` | CLINT `mtime` / `mtimecmp` |
| `RVPlic.HC` → `RVPlicSelected.HH` | PLIC hw or stub |
| `RVVirtioPlat.HC` → `RVVirtioSelected.HH` | virtio-mmio/PCI present helpers |
| `VirtioNet.HC` | virtio-mmio net TX/RX (`CONFIG_HAS_VIRTIO_NET`) |
| `VirtioInput.HC` | virtio-mmio input event poll (`CONFIG_HAS_VIRTIO_INPUT`) |
| `Virtio9p.HC` | virtio-mmio 9p2000.l client — host virtfs import + export (`CONFIG_HAS_VIRTIO_9P`) |
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
| **Smoke** | `make kernel-plat-*-smoke` / matrix proven; not all required for default CI |
| **WIP (board)** | Defconfig + link build; real-board recipe only — out of matrix until green |
| **Excluded** | Not a TempleOS board target — omitted from matrix (not skip=OK) |

| Machine / profile | Defconfig | Kind | Status | Wired | Stub / notes |
|-------------------|-----------|------|--------|-------|--------------|
| **virt** | `virt` | Emulator (CI) | **CI** | 16550 @ `CONFIG_UART_BASE`, CLINT, PLIC, fw_cfg/ramfb, virtio-blk/net/input | Supported default harness map |
| **sifive_u** | `sifive_u` | Board port | **Smoke** | SiFive UART0 @ `0x10010000` (IRQ4), UART1/PRCI/GPIO in MemMap, **GEM TX/RX** (`RVSifiveGem` @ `0x10090000`), CLINT 1 MHz + PLIC via **`RVSifivePlat`**, plat smoke: `clint_adv` + `plic` + `memmap` | No virtio/ramfb; `make kernel-plat-sifive-u-smoke` / `kernel-sifive-gem-smoke` |
| **spike** | `spike` | Emulator | **Smoke** | HTIF `tohost`/`fromhost` @ `0x807FF000` (ELF symbols), CLINT 10 MHz (`clint_adv`), `RVPlicStub` | No PLIC/virtio/ramfb; `make kernel-plat-spike-smoke` |
| **sifive_e** | `sifive_e` | Board port | **Smoke** | Same **`RVSifivePlat`** API; UART @ `0x10013000`, PLIC | Dual: slim XIP `plat.elf` (matrix) + `kernel-fe310.elf` (DTIM boot → XIP Kernel); RV32 emit later |
| **shakti_c** | `shakti_c` | Board port | **Smoke** | **`RVUartShakti`** @ `0x11300` (no UART→PLIC in QEMU); ACLINT @ `0x02000000` (10 MHz); SiFive PLIC @ `0x0C000000` (**QEMU aperture 128 KiB** — `RVPlicHw` no-ops threshold/claim @ `+0x200000`) | Load **`-bios plat.elf`** only (`-bios none` rejected as filename) |
| **microchip-icicle-kit** | `microchip_icicle` | Board port | **Smoke** | MMUART0 16550 @ `0x20000000` (**regshift 2**, PLIC IRQ **90**); ACLINT @ `0x02000000` (**1 MHz**); PLIC @ `0x0C000000` | **`-bios none -kernel`** (HSS not required); `min_cpus=2` (E51+U54) — UART may interleave |
| **xiangshan-kunminghu** | `xiangshan` | Board port | **Smoke** | 16550 @ `0x310B0000` (regshift 2), ACLINT @ `0x38000000`, APLIC @ `0x31100000` + IMSIC @ `0x3A800000` (`RVPlicAplic`: mtopei, eithreshold, multi-hart TARGET) | Load as **`-bios plat.elf`**; MSI→IMSIC |
| **amd-microblaze-v-generic** | `amd_microblaze_v` | Board port | **Smoke** | **`RVUartUartlite`** @ `0x40600000`; **`RVTimerXps`** @ `0x41C00000`; **`RVPlicXps`** @ `0x41200000` | No `-kernel`/`-bios` — smoke: `-device loader,file=ELF,cpu-num=0` (+ `plat.bin` alias) |
| **opentitan** | `opentitan` | Board port | **Smoke** | **`RVUartIbex`** @ `0x40000000`; **`RVTimerIbex`** @ `0x40100000`; PLIC @ `0x48000000`; flash boot @ `0x20000400` | Plat smoke: **RV32 asm** harness until ARCH_RISCV32 emit; HolyC drivers ready — [RV32.md](RV32.md) / [DRIVERS.md](../docs/DRIVERS.md) |
| **visionfive2** | `visionfive2` | Board port | **WIP (board)** | 16550/DW8250 UART0 @ `0x10000000` (regshift 2), CLINT @ `0x02000000`, PLIC @ `0x0C000000`, DDR @ `0x40000000` / entry `0x40200000`, simplefb present hook | **No QEMU `-M`**. `make kernel-visionfive2` / `-help`; packed `plat.bin`. Out of matrix until smoke green (not skip=OK) |
| **milkv-mars** | `milkv_mars` | Board port | **WIP (board)** | Same JH7110 map as VisionFive 2 (own defconfig / `link_milkv_mars.ld` / OpenOCD) | **No QEMU `-M`**. `make kernel-milkv-mars` / `-help`. Out of matrix until smoke green (not skip=OK) |
| **none** | `none` | Emulator | **Excluded** | — | Empty machine; not a matrix board (not skip=OK) |
| **host** | `host` | Legacy stub | **Excluded** | — | Not in QEMU 10.x `-M help`; not a matrix board |

Driver capability survey: **[DRIVERS.md](../docs/DRIVERS.md)**.

Harness binary / `-M` strings for each defconfig: `make -C templeos-riscv qemu-args` (and
[CI.md](../docs/CI.md)). Full inventory probe: `make kernel-plat-matrix` (all matrix boards must
be OK — skips are not allowed). JH7110: `visionfive2_defconfig` +
`milkv_mars_defconfig` + `RVFbSimpleFbBind` — [BOARD_FB.md](BOARD_FB.md).
Do **not** overwrite `visionfive2_*` from the Mars port (or vice versa).

### VisionFive 2 board recipe (no QEMU)

JH7110 map (Linux/`jh7110.dtsi` + TRM): UART0 `0x10000000`, CLINT `0x02000000`, PLIC
`0x0C000000`, DDR `0x40000000+`. OpenSBI/U-Boot typically reserve
`0x40000000`–`0x40200000`; plat ELF links at **`0x40200000`**. UART IRQ 32;
`UART_REG_SHIFT=2`; CLINT timebase **4 MHz**. Console: 115200 8N1 on UART0
(GPIO header / USB-serial).

```bash
make kernel-visionfive2          # → build/kernels/visionfive2/plat.{elf,bin}
make kernel-visionfive2-help     # full U-Boot / OpenOCD recipe + artifact sizes
make -C templeos-riscv qemu-args-visionfive2   # prints BOARD-ONLY note (no -M)

# U-Boot (after firmware left UART0 live) — load flat bin then jump:
#   tftp $loadaddr plat.bin          # or load mmc / sf
#   go 0x40200000
# Expect UART: plat-smoke: PASS

# OpenOCD / gdb (JTAG; after DDR init via SPL/U-Boot or vendor cfg):
#   source tests/openocd/visionfive2_load_plat.tcl
#   # or: load_image build/kernels/visionfive2/plat.elf 0x40200000 elf
# Prefer ELF (segment-aware); flat plat.bin is packed contiguous for tftp/mmc.
```

Framebuffer: select `FB_PRESENT_SIMPLEFB`; leave `SIMPLEFB_BASE=0` until firmware
publishes XR24, then set `SIMPLEFB_*` or call `RVFbSimpleFbBind` — [BOARD_FB.md](BOARD_FB.md).

### Milk-V Mars board recipe (no QEMU)

Same JH7110 SoC class as VisionFive 2 — **separate** files (`milkv_mars_defconfig`,
`link_milkv_mars.ld`, `milkv_mars_load_plat.tcl`). Do not overwrite `visionfive2_*`.

```bash
make kernel-milkv-mars           # → build/kernels/milkv_mars/plat.{elf,bin}
make kernel-milkv-mars-help      # U-Boot / OpenOCD recipe + artifact sizes
make -C templeos-riscv qemu-args-milkv_mars

# U-Boot / OpenOCD: same entry 0x40200000; see make kernel-milkv-mars-help
```

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
| *(VisionFive 2 / Milk-V Mars / JH7110)* | **no** — board-only (`visionfive2`, `milkv_mars`) |

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
| Board ports above | **`visionfive2`** + **`milkv_mars`** defconfigs + packed JH7110 link scripts + OpenOCD (no QEMU `-M`) |

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
6. **Phase G SMP** — crt0_smp + `RVSmpWake`/`RVSmpWakeHart` + MSIE WFI + optional `kernel-smp-smoke`.
   Residual: full Seth JobQue, TempleOS `mp_cnt` finalize, OpenSBI HSM.
7. **Defer** — virtio-rng/gpu, **AIA MSI-X→IMSIC** (virt uses PLIC INTx only), full S-mode; TCP/IP
   (document residual below). Console/balloon/SCSI mmio + BlkDev MMIO→PCI are landed.

## Multi-hart / SMP (Phase G)

TempleOS is **master/slave**, not Linux SMP: hart 0 runs UART REPL / OS; secondaries park then run Seth-style jobs.

| Path | Notes |
|------|--------|
| **QEMU virt `-bios none -smp N`** | All harts enter `tests/exec/harness/crt0_smp.S` (or REPL `bootstrap/startup.s`). Hart 0 clears BSS / runs the blob; others take per-hart stacks and poll a mailbox at `CONFIG_SMP_MAILBOX_BASE` (default `0x87001E00`). Wake: `RVSmpWake` / `RVSmpWakeHart` + CLINT MSIP; secondaries arm `mie.MSIE` (smoke busy-polls mailbox — pure WFI is too slow under QEMU `-smp`). |
| **OpenSBI HSM** | Use when firmware owns secondary bring-up (not the `-bios none` smoke path). |
| **Atomics** | `LXchgI64` = `amoswap.d`; `LBts`/`LBtr`/`LBtc` = LR.W/SC.W; HolyC `lock` = amoswap spin near host-slots (`0x87001F00` on transitional REPL). |
| **Smoke** | Optional: `make kernel-smp-smoke` (not in default `qemu-integration`). |

HolyC API: `Kernel/Drv/RVSmp.HC` (`RVHartId`, `RVSmpWake`, `RVSmpWakeHart`, `RVSmpMpCnt`, `RVAmoAddI64`, …). Man: `Man("SMP")`.

## System devices (virt RTC / fw_cfg)

| Device | HolyC | Smoke |
|--------|-------|-------|
| **Goldfish RTC** | `RVRtc.HC` → `RVRtcGoldfish` @ `CONFIG_RTC_BASE`; `KDate` `NowDateTimeStruct` | `make kernel-rtc-smoke` (also `e_native_date` oracle) |
| **fw_cfg** | `RVFwCfg.HC` → DMA / `RVFwCfgFind` / `RVFwCfgSigOk`; ramfb uses Find+Write | `make kernel-fwcfg-smoke`; FB path still `kernel-fb-smoke` |

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
make kernel-plat-matrix           # every matrix -M: must OK (skips not allowed)
```

Exercises `RVUart*` / `RVClint*` (mtime advance + `ArmTicks`) plus, when
`CONFIG_HAS_PLIC` / APLIC, enable/claim/complete on the UART IRQ; when
`RVSifivePresent`, the named `RVSifiveUart*` / `RVSifiveClint*` / `RVSifivePlic*`
API and reset-capability probes (`RVSifiveCanReset` — does **not** call
`RVSifiveReset`). Plat smoke probes MemMap driver strings (UART1/PRCI/GPIO/ETH
on sifive_u); full `RVMemMap()` needs Print (not in the minimal harness).
Dig-down: `Man("SiFive")` / `Man("Reset")` (REPL topics) / `RVMemMap` driver
column `RVSifivePlat`.

**sifive_u FU540 map (QEMU 10.x DTB):**

| Region | Address | HolyC |
|--------|---------|-------|
| UART0 | `0x10010000` IRQ 4 | `RVUartSifive` / `RVSifivePlat` |
| UART1 | `0x10011000` | MemMap legend (`RVSifiveUart1Base`) |
| CLINT | `0x02000000` (1 MHz) | `RVTimerClint` / `RVSifiveClint*` |
| PLIC | `0x0C000000` | `RVPlicHw` / `RVSifivePlic*` |
| GPIO | `0x10060000` pin 10 | reset via `RVSifiveReset` |
| PRCI | `0x10000000` | legend only (not AON) |
| GEM eth | `0x10090000` | `RVSifiveGem` TX/RX (+ LBL self-test); IRQ 53 poll |
| DRAM | `0x80000000` / 128 MiB | link + soft arenas |

**spike map:**

| Region | Address | HolyC |
|--------|---------|-------|
| HTIF tohost/fromhost | `0x807FF000` / `+0x40` | `RVUartHtif` (putc + getc/fromhost) |
| CLINT | `0x02000000` (10 MHz) | `RVTimerClint` |
| PLIC / virtio / FB | — | stub / absent |

**SiFive reset / halt / fault (board first):**

| Call | sifive_u | sifive_e / FE310 | Notes |
|------|----------|------------------|-------|
| `RVSifiveReset` | GPIO active-low pin (default 10 @ `0x10060000`) | AON WDT RSTEN @ `0x10000000` | Soft REPL `Reset;` is Boot re-entry only |
| `RVSifiveHalt` | `wfi` park | same | |
| `RVSifiveFault` | illegal insn | same | Pair with `SetTrap` / `TrapInit` |
| Test finisher `0x100000` | **absent** | **absent** | Sim/virt harness only (`HardReset;` / `CONFIG_SIFIVE_TEST_BASE`) |

Do not poke `0x10000000` as AON on sifive_u — that window is PRCI on FU540 maps.

### sifive_e / FE310 dual artifacts (XIP Kernel + DTIM bootloader)

QEMU `-M sifive_e` memory (`info mtree`, QEMU 10.1.3):

| Region | Range | Role |
|--------|-------|------|
| XIP | `0x20000000`–`0x3fffffff` (ROM; reset `@ 0x20400000`) | **Kernel** execute-in-place (QSPI) |
| DTIM | `0x80000000`–`0x80003fff` (16 KiB RAM) | **Bootloader** + `.data` / `.bss` / stack only — no external DRAM |

| Artifact | Path | Link | Role |
|----------|------|------|------|
| Slim plat (matrix) | `build/kernels/sifive_e/plat.elf` | `link_sifive_e.ld` — blob in XIP | UART+CLINT; `kernel-plat-matrix` |
| Fuller tiny Kernel | `build/kernels/sifive_e/kernel-fe310.elf` | `link_sifive_e_full.ld` — Kernel XIP, `.boot` in DTIM | `Kernel_FE310.PRJ`; `make kernel-sifive-e-full-smoke` |

**Boot path (fuller image):** reset trampoline in XIP copies `.boot` LMA→DTIM VMA → bootloader sets SP, copies `.data`, clears `.bss`, jumps to HolyC blob in XIP. Import slots are **host-prepatched** (`patch_fe310_xip_imports.py`) because XIP is ROM — do not abandon XIP for “ROM can’t patch”.

**RV32 sequencing:** real FE310 is RV32; today’s smoke is RV64 codegen on QEMU `sifive_e`. Full `HOLYC_XLEN=32` emit is **later** (after RV64 virtio/net/drivers) — see [DRIVERS.md](../docs/DRIVERS.md) / G13 in [GAPS.md](../docs/GAPS.md).

“Full” here means HolyC `Kernel/Drv` UART+CLINT+PLIC+SiFive+MemMap — not full `Kernel_RV.PRJ` and **not** REPL.

### Extra board recipes (HolyC / RV32 harness)

```bash
make kernels                      # all KERNEL_BUILD_MACHINES
make -C templeos-riscv qemu-args-xiangshan
make -C templeos-riscv qemu-args-amd_microblaze_v
make -C templeos-riscv qemu-args-opentitan   # resolves defconfig; no .config write
make -C templeos-riscv qemu-args-sifive_e
make -C templeos-riscv qemu-args-visionfive2 # BOARD-ONLY note (no -M)

# Or interactive / active-tree configure (rewrites global headers):
make -C templeos-riscv defconfig-xiangshan
make -C templeos-riscv defconfig-visionfive2
make -C templeos-riscv qemu-args
make -C templeos-riscv defconfig   # restore CI default
```

Load `build/kernels/<machine>/plat.elf` with the harness argv from `qemu-args-<machine>`.
Driver survey: [DRIVERS.md](../docs/DRIVERS.md). VisionFive 2: board recipe in
§ VisionFive 2 above (`make kernel-visionfive2`).

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
| **virtio-mmio blk** | `DskVirtioRV` (mmio first) + **`VirtioPciBlk`** fallback; `kernel-virtio-smoke` + `kernel-virtio-pci-smoke` | AIA MSI-X→IMSIC (virt = PLIC INTx) |
| **virtio-net** | `VirtioNet.HC` TX/RX (mmio) + **`VirtioPciNet`** fallback; mmio PLIC + **PCI INTx/ISR** (`VirtioPciNetIrq*`); smokes net + net-pci | TCP/IP stack, live SLIRP RX gate; AIA MSI-X |
| **virtio-input** | `VirtioInput.HC` poll + ABS map + PLIC ACK; `make kernel-virtio-input-smoke` | Live key inject gate; more KEY_* glyphs |
| **virtio-9p** | `Virtio9p.HC` 9P2000.L client (MMIO or **PCI queues**/`NinePVirtioPci` SendRecv) + nested `Tmkdir` / overwrite export + `kernel-virtio-9p-smoke` / `kernel-virtio-9p-pci-smoke` | Guest-as-9p-server, TCP 9p, VFS mount glue |
| **virtio-console** | `VirtioConsole.HC` port-0 TX/RX + `kernel-virtio-console-smoke` (file chardev) | Multiport; stdio chardev dual with UART |
| **virtio-balloon** | `VirtioBalloon.HC` inflate/deflate + `kernel-virtio-balloon-smoke` | Stats queue; reclaim policy |
| **virtio-scsi** | `VirtioScsi.HC` INQUIRY + READ(10) + `kernel-virtio-scsi-smoke` | WRITE(10); BlkDev glue; multi-LUN |
| **Other virt attachables** | PCI MSI-X disable + **INTx/ISR** + **trap MEIE** (`RvSetMEIE`, `RVVirtioPciIsrReg`, `kernel-virtioirq-smoke` / `kernel-virtio-pci-irq-smoke`) | gpu, rng, USB, NVMe; **AIA MSI-X→IMSIC** deferred on virt PLIC |

Enable / test:

```bash
make -C templeos-riscv defconfig   # HAS_VIRTIO_NET / HAS_VIRTIO_INPUT / HAS_VIRTIO_9P default y on virt
make kernel-virtio-net-smoke       # UART oracle: virtio-net: tx_ok + rx_ok (mmio)
make kernel-virtio-net-pci-smoke   # same oracle over virtio-net-pci
make kernel-virtio-input-smoke     # UART oracle: virtio-input: ready
make kernel-virtio-9p-smoke        # UART oracle: virtio-9p: read_ok + host export.txt (mmio)
make kernel-virtio-9p-pci-smoke    # same over virtio-9p-pci
make kernel-virtio-console-smoke   # UART oracle: virtio-console: tx_ok
make kernel-virtio-balloon-smoke   # UART oracle: virtio-balloon: ok
make kernel-virtio-scsi-smoke      # UART oracle: virtio-scsi: ok
# REPL: Man("VirtioNet"); Man("Virtio9p"); Man("CSR"); Man("AsmRV");
```

### 9p / virtfs (Phase A — guest client)

Pedagogy (protocol + APIs): [docs/NINEP.md](../docs/NINEP.md). Operator export recipes: [docs/FILE_EXPORT.md](../docs/FILE_EXPORT.md) Method 2.

QEMU shares a **host directory into the guest** over virtio-9p (not IP). The guest HolyC driver is a **9p client**; QEMU’s 9p backend is the server.

```bash
mkdir -p /tmp/tos-share
echo 'hello from 9p' >/tmp/tos-share/test.txt

qemu-system-riscv64 -M virt -m 256M -bios none -kernel build/exec/kp.elf -nographic \
  -fsdev local,id=fsdev0,path=/tmp/tos-share,security_model=none \
  -device virtio-9p-device,fsdev=fsdev0,mount_tag=hostshare
```

PCI attach (same protocol): replace `-device virtio-9p-device,...` with
`-device virtio-9p-pci,...` (virt has a PCIe root; `-bios none` needs guest BAR
assign — `VirtioPciAssignBar4`). Net: `-netdev user,id=net0 -device virtio-net-pci,netdev=net0`
(MMIO: `virtio-net-device`). `Virtio9pConnect` / `VirtioNetInit` prefer MMIO then PCI.

**Also implemented:** guest → host **file export** via the same 9p client
(`Tmkdir` parents, `Tlcreate`/`Twrite`, or overwrite `Tlopen`+`Twrite`):
`NineExport` / `Virtio9pWritePath` write nested paths onto the QEMU virtfs share.
See [docs/FILE_EXPORT.md](../docs/FILE_EXPORT.md) Method 2.

**Not implemented:** guest exporting REPL memfs or RedSea as a 9p **server**;
automatic mount of host files into `fs.hc` memfs; TCP `9p` over virtio-net
(would need a full IP stack + different transport).

Guest → host without virtfs: UART `DumpFile` / `DumpMem` / ZMODEM —
[docs/FILE_EXPORT.md](../docs/FILE_EXPORT.md).
