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

**Entry symbol:** `_start` in `.text.init` (`bootstrap/startup.s` for REPL,
`tests/exec/harness/crt0.S` for kernel plat). Hart 0 clears BSS and calls `main`.

**Linker scripts:**

| Script | Role |
|--------|------|
| `bootstrap/linker.ld` | REPL RAM image; base = `LOAD_BASE` (`--defsym` from `Makefile.repl`) |
| `tests/exec/harness/link_exec.ld` | Kernel/exec harness @ `0x80000000` |
| `bootstrap/kernel_linker.ld` | Full HolyC kernel tree link |
| `bootstrap/firmware.ld` | Flash head @ `FLASH_BASE` + embedded `.fw_payload` |

Override RAM base for a custom board:

```bash
make baremetal LOAD_BASE=0x80200000
make -C bootstrap -f Makefile.repl PLATFORM=my-board   # after adding a Makefile.repl row
```

Kconfig `syncconfig` feeds `RAM_BASE` / `KERNEL_LINK_ADDR` into `make baremetal` and
`make firmware` when `templeos-riscv/include/generated/kconfig.mk` exists.

## Make targets

```bash
make baremetal              # build/baremetal/repl.elf + repl.bin @ LOAD_BASE
make baremetal-plat         # plat.elf + plat.bin (virt kernel demo)
make baremetal-smoke        # qemu -bios none -kernel repl.bin, REPL 1+1
make firmware               # flash ROM + bios copies (see below)
make firmware-smoke         # pflash boot smoke
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
(gdb) target remote :3333
(gdb) monitor reset halt
(gdb) load
(gdb) break main
(gdb) continue
```

On SiFive or custom boards, set `WORK_AREA` / `LOAD_BASE` to the DRAM base from your
board manual and rebuild with matching `LOAD_BASE`.

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

## Menuconfig tie-in

**Boot / kernel output** in `make menuconfig-rv`:

| Kconfig choice | Primary artifact | Deployment |
|----------------|------------------|------------|
| **ELF** (`OUTPUT_FORMAT_ELF`, default) | `build/kernels/<m>/plat.elf` | RAM: OpenOCD / `-bios none -kernel` |
| **Firmware ROM** (`OUTPUT_FORMAT_FIRMWARE`) | `plat.bin` + `plat-fw.elf` under `build/kernels/<m>/` | Flash: program @ `CONFIG_FLASH_BASE`; still builds `plat.elf` for debug |

`syncconfig` writes `include/generated/kconfig.mk` (`OUTPUT_FORMAT`, `FLASH_BASE`,
`RAM_BASE`, `PFLASH_SIZE`). Root `make firmware` and `make baremetal` consume those
variables when the file is present.

REPL bare-metal artifacts are independent of Kconfig unless you rely on shared
`RAM_BASE` from a synced board profile.

## Related docs

- [PLATFORM.md](../templeos-riscv/PLATFORM.md) — board matrix, QEMU reset behavior, firmware §
- [KCONFIG.md](../templeos-riscv/KCONFIG.md) — `OUTPUT_FORMAT_*` and defconfigs
- [ARCHITECTURE.md](ARCHITECTURE.md) — system map and build outputs
