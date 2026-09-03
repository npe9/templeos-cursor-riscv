# Bare-metal deployment (FPGA OpenOCD + QEMU)

Practical embedded boot paths for TempleOS/RISC-V: load a RAM-linked image with
**OpenOCD** (JTAG) or **QEMU** `-bios none -kernel`, or ship a **flash ROM** stub for
boards that reset from NOR/BRAM at a fixed flash base.

CI still uses these same artifacts; this page is the operator guide for FPGA bring-up
and bare QEMU (not the OpenSBI/EDK2 `-bios` story).

## Artifact matrix

| Artifact | Link / load address | Build | Use |
|----------|---------------------|-------|-----|
| `build/baremetal/repl.elf` | RAM `0x80000000` (virt default) | `make baremetal` | OpenOCD `load_image`, gdb, `qemu -kernel repl.elf` |
| `build/baremetal/repl.bin` | same (flat) | `make baremetal` | OpenOCD binary load, `qemu -kernel repl.bin`, `-device loader` |
| `bootstrap/repl.elf` | RAM `LOAD_BASE` | `make -C bootstrap -f Makefile.repl repl.elf` | Same image; baremetal dir is the install copy |
| `build/kernels/<m>/plat.elf` | RAM `CONFIG_KERNEL_LINK_ADDR` | `make kernel-plat-smoke` / `build_kernel_plat.sh` | HolyC kernel plat demo |
| `build/baremetal/plat.elf` / `.bin` | RAM | `make baremetal-plat` | Plat demo in stable baremetal dir |
| `build/firmware/templeos-fw.bin` | flash `0x20000000` | `make firmware` | FPGA flash / QEMU pflash (`-bios none -drive if=pflash,...`) |
| `build/firmware/templeos-fw.elf` | flash `0x20000000` | `make firmware` | objdump / debug of flash layout |
| `build/firmware/templeos-bios.elf` | RAM `0x80000000` | `make firmware` | QEMU `-bios` RAM payload (QEMU convenience, not primary FPGA path) |
| `build/kernels/<m>/plat.bin` | flash (when Kconfig firmware) | `menuconfig` → **Firmware ROM** + `build_kernel_plat.sh` | Per-board flash image of kernel plat |
| `build/bootloader/boot.bin` | `BOOTLOADER_BASE` (default flash `0x20000000`) | `make bootloader` | **HolyC** jump/copy head (`boot.hc` + `pack_bootloader.py`) |
| `build/hc_repl.blob.bin` | `ENTRY_POINT` / DRAM load | `make repl-payload` / `hc_repl` blob | **HolyC** AOT REPL flat payload |
| `build/baremetal/repl.bin` (via `repl-payload`) | same | `make repl-payload` | Copy of `hc_repl.blob.bin` for OpenOCD naming |

**Entry symbol:** `_start` in HolyC `asm{}` for product images (`bootstrap/bootloader/boot.hc`,
`bootstrap/hc_repl/start.hc`). Legacy C guest uses `bootstrap/startup.s` /
`tests/exec/harness/crt0.S`.

**Linker scripts:**

| Script | Role |
|--------|------|
| `bootstrap/linker.ld` | Legacy C REPL RAM image (`Makefile.repl`) |
| `tests/exec/harness/link_exec.ld` | Kernel/exec harness @ `0x80000000` |
| `bootstrap/kernel_linker.ld` | Full HolyC kernel tree link |
| `bootstrap/firmware.ld` | Legacy GNU flash head @ `FLASH_BASE` + embedded `.fw_payload` |
| *(none for product bootloader)* | Flat `holyc-riscv` bin; optional Python pflash pad |

Override RAM base for a custom board:

```bash
make baremetal LOAD_BASE=0x80200000
make -C bootstrap -f Makefile.repl PLATFORM=my-board   # after adding a Makefile.repl row
```

Kconfig `syncconfig` feeds `RAM_BASE` / `KERNEL_LINK_ADDR` into `make baremetal` and
`make firmware` when `templeos-riscv/include/generated/kconfig.mk` exists.

## Make targets

```bash
make baremetal              # legacy C guest → build/baremetal/repl.{elf,bin}
make repl-payload           # HolyC hc_repl.blob.bin (+ copy to baremetal/repl.bin)
make baremetal-plat         # plat.elf + plat.bin (virt kernel demo)
make baremetal-smoke        # qemu -bios none -kernel legacy repl.bin, REPL 1+1
make bootloader             # HolyC build/bootloader/boot.bin @ BOOTLOADER_BASE
make bootloader-repl        # HolyC bootloader + HolyC REPL blob
make bootloader-smoke       # pflash HolyC jump → REPL 1+1
make firmware               # legacy GNU flash ROM + bios copies (see below)
make firmware-smoke         # pflash boot smoke (legacy wrap)
```

Install dir only copies/links; it does not change the link layout. Rebuild REPL with
`Makefile.repl`, then `make baremetal` refreshes `build/baremetal/*`.

## Workflow A — RAM load (FPGA + bare QEMU)

**When:** JTAG loads directly into DRAM, or QEMU virt with `-bios none` (reset ROM jumps
to `0x80000000`).

1. `make baremetal`
2. OpenOCD: load at `LOAD_BASE`, reset, run from `_start`
3. QEMU: `-bios none -kernel build/baremetal/repl.bin`

Flat `.bin` is a byte-for-byte image starting at `LOAD_BASE` (`.text` through `.data`;
BSS is zero-filled by `_start`). Prefer `.elf` when you need segment-aware loading or
debug symbols.

### OpenOCD example

Adjust `adapter`, `target`, and `WORK_AREA` for your FPGA/SoC. Addresses below match
QEMU virt / many RV64 DRAM maps.

```tcl
# openocd -f board/my_fpga.cfg
source [find interface/jtag.cfg]
# transport select jtag
# adapter speed 10000

set WORK_AREA 0x80000000
set _IMAGE     /path/to/templeos-cursor-riscv/build/baremetal/repl.elf

init
halt

# ELF: honors PT_LOAD segments and link address
load_image $_IMAGE $WORK_AREA elf

# Flat binary alternative (same LOAD_BASE as linker.ld):
# load_image /path/to/build/baremetal/repl.bin $WORK_AREA bin

# Optional: symbols for gdb
# gdb_port 3333

reset halt
reg pc $WORK_AREA
resume
```

With **gdb** (OpenOCD `gdb_port 3333`):

```bash
riscv64-unknown-elf-gdb build/baremetal/repl.elf
# Homebrew often ships riscv64-elf-gdb — same commands
(gdb) target remote :3333
(gdb) monitor reset halt
(gdb) load
(gdb) break main
(gdb) continue
```

### QEMU gdbstub (no OpenOCD)

Same ELF, emulator instead of JTAG — useful on virt before board bring-up:

```bash
make hwdbg-smoke
# manual twin:
qemu-system-riscv64 -M virt -cpu rv64 -m 128M -nographic -bios none \
  -kernel bootstrap/repl.elf -S -gdb tcp:127.0.0.1:3333
riscv64-elf-gdb bootstrap/repl.elf -x tests/gdb/hwdbg_virt.gdb
```

Guest Sdtrig helpers (`HwTrigProbe` / `HwWatch`) and the capability matrix live in
[DEBUGGER.md](DEBUGGER.md). On SiFive or custom boards, set `WORK_AREA` / `LOAD_BASE`
to the DRAM base from your board manual and rebuild with matching `LOAD_BASE`.

### VisionFive 2 (JH7110) RAM load

No QEMU `-M`. Link at **`0x40200000`** (after OpenSBI 2 MiB). Prefer ELF:

```bash
make kernel-visionfive2
make kernel-visionfive2-help
# OpenOCD (DDR already up): source tests/openocd/visionfive2_load_plat.tcl
# U-Boot: tftp $loadaddr plat.bin ; go 0x40200000
```

Details: [PLATFORM.md](../templeos-riscv/PLATFORM.md) § VisionFive 2. Milk-V Mars is a
sibling JH7110 board with its own defconfig when ready.

### QEMU bare metal

```bash
# Default virt: M-mode, reset → 0x80000000
qemu-system-riscv64 -M virt -m 128M -bios none \
  -kernel build/baremetal/repl.bin -nographic

# ELF (same boot path; QEMU parses segments)
qemu-system-riscv64 -M virt -m 128M -bios none \
  -kernel build/baremetal/repl.elf -nographic

# Explicit load address (non-default maps or testing)
qemu-system-riscv64 -M virt -m 128M -bios none \
  -device loader,addr=0x80000000,file=build/baremetal/repl.bin -nographic

tests/scripts/qemu-baremetal.sh           # wrapper (default: repl.bin)
tests/scripts/qemu-baremetal.sh --elf
tests/scripts/qemu-baremetal.sh --loader 0x80000000
```

Smoke: `make baremetal-smoke`.

## Workflow B — Flash ROM (FPGA BRAM / NOR boot)

**When:** Reset vector is at a fixed flash address (QEMU virt pflash @ `0x20000000`).

1. Build RAM payload: `make baremetal` (or kernel plat ELF)
2. Wrap in flash stub: `make firmware` (`bootstrap/Makefile.firmware`)
3. Program `build/firmware/templeos-fw.bin` into flash/BRAM at `FLASH_BASE`

The stub (`bootstrap/firmware_stub.S`) copies the embedded flat payload to `RAM_BASE`
and jumps to `_start`. Payload BSS is still cleared by startup code in RAM.

```bash
make firmware
# OpenOCD — program flash image at FLASH_BASE (not RAM_BASE)
# load_image build/firmware/templeos-fw.bin 0x20000000 bin

# QEMU pflash
qemu-system-riscv64 -M virt -m 128M -bios none \
  -drive if=pflash,format=raw,file=build/firmware/templeos-fw.bin -nographic
```

**Do not** pass `templeos-fw.bin` to `-bios`: QEMU loads `-bios` into DRAM @
`0x80000000`, but the image is linked for flash — it will hang. Use Workflow A
(`repl.bin`) or pflash (above). See [PLATFORM.md](../templeos-riscv/PLATFORM.md) §
Firmware.

Override flash/RAM bases for your FPGA map:

```bash
make firmware FLASH_BASE=0x60000000 RAM_BASE=0x80000000
```

## Workflow C — Split bootloader + REPL (HolyC only)

**Constraint:** Product bootloader / REPL / firmware guest images are **HolyC only**.
Build them with host `holyc-riscv` AOT (`host/*.c` → `./holyc-riscv`). Do **not** use
`riscv64-*-gcc`, GNU `as`/`ld`, or `objcopy` for these guest artifacts. Flat `.bin`
comes from `holyc-riscv … -o out.bin` (and optional Python pad/concat in
`bootstrap/bootloader/pack_bootloader.py`). Legacy `make firmware` / `Makefile.baremetal`
still use GNU for the old C guest path — prefer this split path for new work.

```
[bootloader]  HolyC asm{} _start — holyc-riscv → boot.bin @ BOOTLOADER_BASE
      ↓
[hc_repl.blob.bin]  HolyC AOT REPL @ ENTRY_POINT (default 0x80000000)
```

| Mode | `BOOT_MODE` | Behavior |
|------|-------------|----------|
| **Jump** (default) | `jump` | Payload already at `ENTRY_POINT`; bootloader only jumps |
| **Copy** | `copy` | Python packs stub + `hc_repl.blob.bin`; stub copies to `ENTRY_POINT`, jumps |

```bash
make bootloader-repl              # HolyC boot.bin + hc_repl.blob.bin
make bootloader BOOT_MODE=copy    # embedded HolyC payload (single pflash image)
make repl-payload                 # build/baremetal/repl.bin ← hc_repl.blob.bin

# Jump smoke (preferred): bootloader @ pflash reset, REPL blob @ ENTRY_POINT
qemu-system-riscv64 -M virt -m 128M -bios none \
  -drive if=pflash,format=raw,file=build/bootloader/boot.bin \
  -device loader,file=build/hc_repl.blob.bin,addr=0x80000000 \
  -nographic

tests/scripts/qemu-bootloader.sh          # same as above
tests/scripts/qemu-bootloader.sh --copy   # copy-mode pflash only
```

**Dual-DRAM jump** (no pflash; bootloader owns virt reset @ `0x80000000`):

```bash
make -C bootstrap -f Makefile.bootloader bootloader \
  BOOT_MODE=jump BOOTLOADER_BASE=0x80000000 ENTRY_POINT=0x80200000 PAD_PFLASH=0
make -C bootstrap/hc_repl blob
qemu-system-riscv64 -M virt -m 128M -bios none \
  -device loader,file=build/bootloader/boot.bin,addr=0x80000000 \
  -device loader,file=build/hc_repl.blob.bin,addr=0x80200000 \
  -nographic
```

Smoke: `make bootloader-smoke` (HolyC jump + pflash). Does not replace
`baremetal-smoke` / `firmware-smoke` (legacy C guest / GNU firmware wrap).

**Sources:** `bootstrap/bootloader/boot.hc` + `pack_bootloader.py`. No `bootloader.S`.

**Kconfig** (`make menuconfig` → **Boot / kernel output**):

| Symbol | Role |
|--------|------|
| `BOOT_SPLIT` | Enable split-boot options |
| `BOOTLOADER_BASE` | Bootloader link/reset (default `0x20000000`) |
| `BOOT_MODE_JUMP` / `BOOT_MODE_COPY` | Jump vs embed-and-copy |
| `ENTRY_POINT` | Payload load/jump address (unchanged) |

`syncconfig` writes `BOOTLOADER_BASE` / `BOOT_MODE` into `kconfig.mk` for
`Makefile.bootloader`.

## Menuconfig tie-in

**Boot / kernel output** in `make menuconfig`:

| Kconfig choice | Primary artifact | Deployment |
|----------------|------------------|------------|
| **ELF** (`OUTPUT_FORMAT_ELF`, default) | `build/kernels/<m>/plat.elf` | RAM: OpenOCD / `-bios none -kernel` |
| **Firmware ROM** (`OUTPUT_FORMAT_FIRMWARE`) | `plat.bin` + `plat-fw.elf` under `build/kernels/<m>/` | Flash: program @ `CONFIG_FLASH_BASE`; still builds `plat.elf` for debug |

`syncconfig` writes `include/generated/kconfig.mk` (`OUTPUT_FORMAT`, `FLASH_BASE`,
`RAM_BASE`, `PFLASH_SIZE`, and when enabled `BOOT_SPLIT` / `BOOTLOADER_BASE` /
`BOOT_MODE`). Root `make firmware`, `make baremetal`, and `make bootloader`
consume those variables when the file is present.

REPL bare-metal artifacts are independent of Kconfig unless you rely on shared
`RAM_BASE` from a synced board profile.

## Related docs

- [UART.md](UART.md) — serial primer + flow control (XON/XOFF on 16550 console)
- [FILE_EXPORT.md](FILE_EXPORT.md) — pull memfs / RAM dumps off a live UART session
- [NINEP.md](NINEP.md) — virtio-9p remote FS (prefer over terminal bulk copy)
- [PLATFORM.md](../templeos-riscv/PLATFORM.md) — board matrix, QEMU reset behavior, firmware §
- [KCONFIG.md](../templeos-riscv/KCONFIG.md) — `OUTPUT_FORMAT_*` and defconfigs
- [ARCHITECTURE.md](ARCHITECTURE.md) — system map and build outputs
