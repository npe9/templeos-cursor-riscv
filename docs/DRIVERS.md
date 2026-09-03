# HolyC platform drivers

TempleOS/RV device I/O is **HolyC under `Kernel/Drv/`**, selected by Kconfig
(`templeos-riscv/.config` → `Kernel/RVAutoConf.HH` + `*Selected.HH`). Emulator
`-M` names are CI harness profiles; prefer board / `MEM_*` / `CONFIG_*` language
in product docs. Matrix policy: **skips are not allowed** — see
[PLATFORM.md](../templeos-riscv/PLATFORM.md) and [AGENTS.md](../AGENTS.md).

| Related | Role |
|---------|------|
| [UART.md](UART.md) | UART history / FIFOs / XON/XOFF (which `RVUart*` honor FC) |
| [PLATFORM.md](../templeos-riscv/PLATFORM.md) | Board status + QEMU recipes |
| [KCONFIG.md](../templeos-riscv/KCONFIG.md) | Configure / syncconfig |
| [BOARD_FB.md](../templeos-riscv/BOARD_FB.md) | Framebuffer / WinMgr boards |
| [RV32.md](../templeos-riscv/RV32.md) | OpenTitan / ILP32 plan |
| [SELF_HOST.md](SELF_HOST.md) | Guest recompile path |
| [NINEP.md](NINEP.md) | Virtio-9p pedagogy (not UART bulk copy) |

## Driver inventory (`Kernel/Drv/`)

| Capability | HolyC entry | Implementations | Selected by |
|------------|-------------|-----------------|-------------|
| UART console | `RVUart.HC` → `RVUartSelected.HH` | `RVUart16550`, `RVUartSifive` (→ `RVSifivePlat`), `RVUartHtif`, `RVUartShakti`, `RVUartUartlite`, `RVUartIbex`, `RVUartStub` | `CONFIG_UART_*` |
| Timer | `RVTimer.HC` → `RVTimerSelected.HH` | `RVTimerClint`, `RVTimerIbex`, `RVTimerXps`, `RVTimerStub` | `HAS_CLINT` / `HAS_IBEX_TIMER` / `HAS_XPS_TIMER` |
| PLIC / APLIC / XPS IRQ | `RVPlic.HC` → `RVPlicSelected.HH` | `RVPlicHw`, `RVPlicAplic`, `RVPlicXps`, `RVPlicStub` | `HAS_PLIC` / `HAS_APLIC` / `HAS_XPS_INTC` |
| SiFive facade | `RVSifivePlat.HC` → `RVSifiveSelected.HH` | `RVSifiveYes`, `RVSifiveNo` | UART_SIFIVE / sifive_* |
| Virtio MMIO/PCI present | `RVVirtioPlat.HC` | `RVVirtioMmioYes/No`, `RVVirtioPciYes/No` | `HAS_VIRTIO_*` |
| Virtio blk | `Kernel/BlkDev/DskVirtioRV.HC` | mmio first; PCI via `VirtioPciBlk` | virt map |
| Virtio-PCI blk | `VirtioPci.HC` + `VirtioPciBlk.HC` | ECAM + modern caps, LBA R/W | `HAS_VIRTIO_PCI` |
| Virtio net | `VirtioNet.HC` (+ `VirtioPciNet`) | mmio TX/RX; PCI fallback | `HAS_VIRTIO_NET` |
| SiFive GEM eth | `RVSifiveGem.HC` → `RVSifiveGemSelected.HH` | `RVSifiveGemYes` (Cadence GEM TX/RX + LBL self-test), `RVSifiveGemNo` | `SIFIVE_ETH_BASE≠0` |
| Virtio input | `VirtioInput.HC` | mmio poll + PLIC ACK | `HAS_VIRTIO_INPUT` |
| Virtio 9p | `Virtio9p.HC` (+ `NinePVirtioPci`) | 9P2000.L; MMIO or PCI queues — [NINEP.md](NINEP.md) | `HAS_VIRTIO_9P` |
| Virtio console | `VirtioConsole.HC` | mmio port-0 TX/RX | `HAS_VIRTIO_CONSOLE` |
| Virtio balloon | `VirtioBalloon.HC` | mmio inflate/deflate | `HAS_VIRTIO_BALLOON` |
| Virtio SCSI | `VirtioScsi.HC` | mmio INQUIRY + READ(10) | `HAS_VIRTIO_SCSI` |
| Framebuffer | `RVFbPlat.HC` → `RVFbSelected.HH` | ramfb / simplefb / none | `FB_PRESENT_*` |
| fw_cfg | `RVFwCfg.HC` → `RVFwCfgSelected.HH` | `RVFwCfgYes` (DMA/Find/Sig), `RVFwCfgNo` | `HAS_FW_CFG` |
| Goldfish RTC | `RVRtc.HC` → `RVRtcSelected.HH` | `RVRtcGoldfish`, `RVRtcNo` | `HAS_GOLDFISH_RTC` |
| Mem map legend | `RVMemMap.HC` | MMIO ↔ driver names | all boards |
| SMP mailbox | `RVSmp.HC` | hart wake / MSIP / MpCnt | virt `-smp` |

## Per-platform matrix

Legend: **P** = present (wired), **S** = stub / no-op selected, **—** = N/A for this board, **W** = WIP (HolyC ready or asm smoke only).

| Platform | UART | Timer | PLIC | FB/ramfb | Virtio | RTC | SiFive AON/GPIO/test | SMP mbx | Plat smoke |
|----------|------|-------|------|----------|--------|-----|----------------------|---------|------------|
| **virt** | P 16550 | P CLINT | P | P ramfb+fw_cfg | P mmio + PCI (blk/9p/net) + console/balloon/scsi | P goldfish (cfg) | test finisher P | P | CI |
| **sifive_u** | P SiFive UART0 (+UART1 legend) | P CLINT 1 MHz (`clint_adv`) | P (`plic_ok`) | — | — | — | GPIO reset P; PRCI legend; **GEM TX/RX P** (`RVSifiveGem`) | — | Smoke |
| **sifive_e** | P SiFive | P CLINT | P | — | — | — | AON+GPIO P; test — | — | Smoke (XIP Kernel + DTIM boot) |
| **spike** | P HTIF (tohost+fromhost) | P CLINT 10 MHz (`clint_adv`) | S | — | — | — | — | — | Smoke |
| **shakti_c** | P Shakti @ `0x11300` | P ACLINT-as-CLINT (10 MHz) | P enable/prio; context no-op (QEMU 128 KiB map) | — | — | — | — | — | Smoke (`-bios`) |
| **microchip_icicle** | P 16550 MMUART0 (regshift2, IRQ90) | P ACLINT-as-CLINT (1 MHz) | P | — | — | — | — | min 2 harts | Smoke (`-kernel`) |
| **xiangshan** | P 16550 (regshift2) | P ACLINT-as-CLINT | P APLIC+IMSIC (mtopei/eithreshold/hart TARGET) | — | — | — | — | — | Smoke (`-bios`) |
| **amd_microblaze_v** | P UARTLite | P XPS timer | P XPS INTC | — | — | — | — | — | Smoke (loader) |
| **opentitan** | P Ibex (HolyC) / asm smoke | P Ibex timer (HolyC) / asm poke | P map | — | — | — | — | — | Smoke (RV32 asm) |
| **visionfive2** | P 16550/DW8250 @ `0x10000000` | P CLINT @ `0x02000000` (4 MHz) | P @ `0x0C000000` | W simplefb hook (`SIMPLEFB_BASE=0`) | — | — | — | — | **WIP board** (`make kernel-visionfive2`; no QEMU) |
| **milkv_mars** | P 16550/DW8250 (JH7110 map) | P CLINT @ `0x02000000` | P @ `0x0C000000` | W simplefb hook | — | — | — | — | **WIP board** (`make kernel-milkv-mars`; no QEMU) |
| **none / host** | — | — | — | — | — | — | — | — | **Excluded** (not boards) |

## What each product path needs

| Goal | Required drivers / map |
|------|------------------------|
| **UART REPL smoke** (`repl-holyc-smoke`) | UART (16550 on virt), heap/memfs bases, seed FS — virt only today |
| **kernel-plat smoke / matrix** | UART + timer (CLINT / Ibex / stub that returns) + matching QEMU load mode |
| **WinMgr / Gr** | FB present (ramfb/simplefb), virtio-input optional, larger DRAM | virt (+ BOARD_FB custom) |
| **Self-host remote** | UART console + enough RAM for Compiler_RV; virtio-9p or file export optional | virt |
| **Baremetal / bootloader** | UART + DRAM link @ ENTRY; flash path optional | virt map ([BAREMETAL.md](BAREMETAL.md)) |

## Priority backlog (missing / incomplete by impact)

1. **ARCH_RISCV32 HolyC emit** — **blocked / sequenced later**. Finish **RV64** virtio/net/input/9p and board drivers first — do **not** prioritize `HOLYC_XLEN=32` / FE310 RV32 ahead of that queue. OpenTitan stays RV32 asm plat harness until emit lands ([RV32.md](../templeos-riscv/RV32.md)). Real FE310 silicon is RV32; QEMU smoke today uses RV64 codegen on `-M sifive_e` with the XIP+DTIM boot layout.
2. ~~**Ibex timer HolyC driver**~~ — **done**: `RVTimerIbex.HC` @ `CONFIG_IBEX_TIMER_BASE` (`0x40100000`), selected when `HAS_IBEX_TIMER`.
3. ~~**Xiangshan APLIC**~~ — **done (MSI + IMSIC file)**: `RVPlicAplic.HC` enable, `mtopei` claim, IMSIC `eidelivery`/`eie`/`eithreshold`, multi-hart `RVPlicEnableHart`; nested S-domain / guest files still open.
4. ~~**Virtio-PCI BlkDev fallback**~~ — **done**: `VirtioBlkInit` MMIO→`VirtioPciBlk` (+ R/W); smoke `kernel-virtio-pci-smoke`. **PCI INTx/ISR** for blk+net (`VirtioPciIrqNum`/`IsrAck`/`EnableIntx`; MSI-X disabled on virt PLIC). **Trap MEIE** for mmio + PCI: `RvSetMEIE` from IrqInit; `HolyServiceExternal` ACKs mmio 1..8 and PCI INTx 32..35 via `RVVirtioPciIsrReg`; smokes `kernel-virtioirq-smoke` + `kernel-virtio-pci-irq-smoke`. Still deferred: **AIA MSI-X→IMSIC** (virt board uses PLIC INTx only — MSI-X needs APLIC/IMSIC like Xiangshan); TCP/IP.
5. **Virtio console / balloon / SCSI** — **mmio slices landed**: `VirtioConsole` (port-0 **TX** with file/null chardev; avoid stdio dual with UART), `VirtioBalloon` (inflate/deflate), `VirtioScsi` (**INQUIRY** command path + best-effort READ(10); eventq notify after prime). Still open: multiport console, balloon statsq, reliable SCSI WRITE / BlkDev glue, rng/gpu.
5b. ~~**SiFive GEM eth (sifive_u)**~~ — **done (TX/RX poll slice)**: `RVSifiveGemYes` @ `CONFIG_SIFIVE_ETH_BASE`, local-loopback RX self-test; smoke `kernel-sifive-gem-smoke`. Still open: PLIC/MEIE RX, PHY MDIO, TCP/IP.
6. **Full FE310 / sifive_e product image** — **partial (correct layout)**: Kernel **XIP/QSPI** + **bootloader in DTIM** only (`.data` LMA→VMA copy, `.bss` clear, stack; imports **host-prepatched** — do not write ROM at runtime). Matrix keeps slim `plat.elf`. Fuller: `kernel-fe310.elf` / `make kernel-sifive-e-full-smoke`. Full `Kernel_RV` / REPL still out (16 KiB DTIM). RV32 emit = later (item 1).
7. **VisionFive 2 (JH7110)** — **WIP**: `visionfive2_defconfig` + packed `link_visionfive2.ld` + UART_REG_SHIFT=2 + OpenOCD + `make kernel-visionfive2-help`. No QEMU `-M`; out of matrix until board smoke green.
8. **Milk-V Mars (JH7110)** — **WIP**: sibling of VF2 — `milkv_mars_defconfig` + `link_milkv_mars.ld` + OpenOCD + `make kernel-milkv-mars-help` (do **not** overwrite `visionfive2_*`). Out of matrix until green.

### ARCH_RISCV32 exact blocker (smallest unblock path)

| Layer | Blocker | Smallest stub that unblocks beyond asm |
|-------|---------|----------------------------------------|
| Host emit | `host/compiler.c` hard-codes LP64 `ld`/`sd`, 8-byte eval stack / frames | `--target rv32` (or `HOLYC_XLEN=32`) path: `lw`/`sw`, 4-byte pointers, soft `I64` pairs for one UART-hello exec case |
| Host types | `host/parser.c` `TypeSize` treats pointers / `I64` as 8 | ILP32: pointers 4; keep `I64` size 8 with soft ops ([RV32.md](../templeos-riscv/RV32.md) §3) |
| Guest Cmp | `Compiler/Back*_RV.HC`, `Asm_RV.HC` assume XLEN=64 | Gate later (P3); not required for OpenTitan plat demo |
| Board | OpenTitan smoke is `tests/exec/harness/opentitan_plat.S` | After host P0: compile `kernel_plat_demo.hc` with `RVUartIbex`/`RVTimerIbex` via `qemu-system-riscv32` |

Do **not** start emit until RV32.md §9 gates hold **and** the RV64 driver queue is in good shape. First proving ground is **virt-rv32**, not OpenTitan / FE310. FE310 XIP+bootloader layout comes before RV32 codegen.

## Smoke commands

```bash
make kernel-plat-smoke              # virt (CI)
make kernel-rtc-smoke               # Goldfish RTC (virt)
make kernel-fwcfg-smoke             # fw_cfg signature + file dir (virt)
make kernel-smp-smoke               # optional -smp 2 (not default CI)
make kernel-plat-sifive-u-smoke
make kernel-sifive-gem-smoke        # Cadence GEM TX + local-loopback RX (sifive_u)
make kernel-plat-spike-smoke
make kernel-plat-matrix             # all matrix boards; must be all OK
make kernel-sifive-e-full-smoke     # FE310: DTIM bootloader → XIP Kernel_FE310
make kernel-visionfive2             # JH7110 plat.elf (board-only; no QEMU smoke)
make kernel-milkv-mars              # Milk-V Mars JH7110 plat.elf (own files)
make -C templeos-riscv qemu-args-<machine>
```
