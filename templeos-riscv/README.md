# TempleOS for RISC-V

This directory is the **operating-system personality** for this project: boot, UART, and a fixed link layout for HolyC AOT blobs. It is intentionally **separate** from the HolyC compiler sources under the repository root (`lexer.c`, `parser.c`, `compiler.c`, `holyc-riscv`).

## Layout

| Path | Role |
|------|------|
| `kernel/` | `boot.S`, **S-mode traps** (`trap_entry.S`), UART, compiler-slot probe, guest call |
| `guest/` | Default HolyC `main` linked at **`0x80100000`** |
| `selfhost/` | HolyC self-host **seed** (`toy_eval.hc`) |
| `link/kernel.ld` | Guest **`0x80100000`**, compiler slot **`0x80200000`**, **`TosApi` @ `0x80300000`** (`kernel/tos_api.h`) |

## Builds

- **Host compiler** (required to build guests): build `../holyc-riscv` from the repo root (`make -C .. holyc-riscv`).
- **Guest image**: `make` or `make image` produces `build/tos-rv.elf` (kernel + `guest/kmain.hc`).
- **Self-hosted seed**: `make selfhost` produces `build/tos-rv-selfhost.elf` (kernel + `selfhost/toy_eval.hc`).

Override the compiler with `HOLYC=/path/to/holyc-riscv`.

## Run

From this directory:

```bash
make qemu          # default guest
make qemu-selfhost # selfhost guest (HolyC in selfhost/)
```

Optional **virtio-blk** (Phase E): attach a raw image so the kernel can read **LBA 0** over PCI (see `kernel/virtio_blk_pci.c`):

```bash
qemu-system-riscv64 -M virt -bios none -kernel build/tos-rv.elf \
  -drive file=disk.img,format=raw,if=virtio -nographic
```

UART then includes `Phase E — virtio-blk (PCI) LBA0 first_u32 = ...` after the HolyC guest returns.

**RedSea-shaped disk** (TempleOS `CRedSeaBoot` + root `CDirEntry`):

```bash
make redsea-smoke-img
qemu-system-riscv64 -M virt -bios none -kernel build/tos-rv.elf \
  -drive file=build/redsea_smoke.img,format=raw,if=virtio -nographic
```

Expect `RedSea boot:` lines, per-slot `root[n]` lines, then one `RedSea file` line per regular file (`README` multi-cluster snip + `BOOT.TXT`).

**virtio-mmio** disk (`virtio-blk-device`): QEMU’s `virtio-mmio` defaults to **legacy** (version 1); this kernel only implements **modern** MMIO (version 2). Use:

```bash
qemu-system-riscv64 -M virt -bios none -global virtio-mmio.force-legacy=off \
  -kernel build/tos-rv.elf \
  -drive file=build/redsea_smoke.img,if=none,id=d0,format=raw \
  -device virtio-blk-device,drive=d0 -nographic
```

If a modern MMIO block device is present, Phase E prefers it over PCI (`virtio-blk MMIO @ ...` then the same RedSea lines).

From the **repository root**:

```bash
make templeos-riscv   # build build/tos-rv.elf only
make templeos-smoke   # build + QEMU ORACLE check (default + selfhost)
```

Requires `riscv64-unknown-elf-{gcc,ld,objcopy}`, `qemu-system-riscv64` (same as `tests/exec` harness), and **Python 3** (generates the 8-byte compiler-slot stub).

## Design: parity with x86 TempleOS

See **[TOS_X86_PARITY.md](TOS_X86_PARITY.md)** for an apples-to-apples map (boot, compiler load, Adam, scheduler, disk, display, multicore) from original TempleOS to this RISC-V kernel, plus phased milestones.

## Self-hosting roadmap

1. **Now**: C kernel + HolyC guest; `selfhost/toy_eval.hc` parses a constant string with `+` and `*` (recursive descent) — proves HolyC code runs as the “user” under this kernel.
2. **Next**: Grow `selfhost/` into a real lexer/parser/codegen for RV64 (or emit to the existing binary format the kernel loads).
3. **End state**: `holyc` built from HolyC, running on TempleOS/RISC-V, while the C compiler at repo root remains the bootstrap for the host.

The **bootstrap compiler** always lives outside `templeos-riscv/`; this tree never needs to include `lexer.c` / `parser.c` to build the OS image.
