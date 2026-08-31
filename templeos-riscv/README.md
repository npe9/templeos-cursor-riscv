# TempleOS for RISC-V

This directory is the **C guest-loader / image** personality: boot, traps, console putc,
and a fixed link layout for HolyC AOT blobs. It is intentionally **separate** from the host
HolyC compiler at the repo root (`holyc-riscv`) and from the **HolyC OS** under `../Kernel/`.

Repo-wide map: [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md). Emulator `make qemu*`
targets here are the **CI/dev harness** for loading the ELF — not the product story.
Board selection: [PLATFORM.md](PLATFORM.md), [KCONFIG.md](KCONFIG.md).

## Layout

| Path | Role |
|------|------|
| `kernel/` | `boot.S`, **S-mode traps** (`trap_entry.S`), virt-oriented console putc, guest call |
| `Kconfig` + `configs/` | Machine + memory-map menu → `Kernel/RVAutoConf.HH` — **[KCONFIG.md](KCONFIG.md)** |
| `guest/` | Default HolyC `main` linked at **`0x80100000`** |
| `selfhost/` | HolyC self-host **seed** (`toy_eval.hc`) |
| `link/kernel.ld` | Guest **`0x80100000`**, compiler slot **`0x80200000`**, **`TosApi` @ `0x80300000`** (`kernel/tos_api.h`) |

**Multi-machine OS drivers are HolyC** (`Kernel/Drv/*` + Kconfig) — [PLATFORM.md](PLATFORM.md), tutorial [KCONFIG.md](KCONFIG.md). This C tree is **not** a parallel device-driver stack.

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

## Framebuffer (Phase F — not VGA)

Native **32-bpp XRGB8888** linear FB in `Kernel/RVFb.HC` (put-pixel / fill / blit / 8×8 `sys_font_std` glyphs). Thin **Gr*/CDC** + soft terminal in `Kernel/RVGr.HC`. TempleOS-style **text_base WinMgr** in `Kernel/RVWinMgr.HC` (borders, wallpaper, titles, z-order, optional `draw_it` → `RVFbPresent`). **`RVSysWinInit`** (from `RVKMain`) brings up the windowed desktop when QEMU **ramfb** is present or a board has called **`RVFbSimpleFbBind`**; under UART-only `-nographic` (no ramfb) it is a no-op so CI stays green.

Present backends (`RVFbSetPresent`):

| Kind | Constant | When |
|------|----------|------|
| soft only | `RV_FB_PRESENT_NONE` | draw + hash; no scanout |
| QEMU ramfb | `RV_FB_PRESENT_RAMFB` (default on virt) | fw_cfg `etc/ramfb` |
| DT/firmware linear FB | `RV_FB_PRESENT_SIMPLEFB` | after `RVFbSimpleFbBind(base,w,h,…)` |

```bash
# Headless smokes (UART hash oracle; part of make qemu-integration)
# These use -display none — you will NOT see a window.
make kernel-fb-smoke
make kernel-gr-smoke
make kernel-win-smoke

# --- Visible pixels (macOS: cocoa; do NOT pass -nographic or -display none) ---
# Color bars + "Hello from TempleOS/RV":
make kernel-fb-smoke   # also writes build/exec/fb.elf
qemu-system-riscv64 -M virt -m 128M -bios none -kernel build/exec/fb.elf \
  -device ramfb -display cocoa -serial stdio

# Soft term + Gr* demo:
make kernel-gr-smoke
qemu-system-riscv64 -M virt -m 128M -bios none -kernel build/exec/gr.elf \
  -device ramfb -display cocoa -serial stdio

# TempleOS-style bordered windows (Adam + Demo/Graphics):
make kernel-win-smoke
qemu-system-riscv64 -M virt -m 128M -bios none -kernel build/exec/win.elf \
  -device ramfb -display cocoa -serial stdio

# Self-boot with WinMgr desktop when ramfb is present:
make kernel-selfboot-smoke   # writes build/exec/kp.elf (default host O1; bisect with HOLYC_NO_OPT=1)
qemu-system-riscv64 -M virt -m 128M -bios none -kernel build/exec/kp.elf \
  -device ramfb -display cocoa -serial stdio
# Gate: rv_sys_gr_force=-1 never; =1 force soft path. Auto (0) probes ramfb / bound simplefb.
# On Linux hosts, use -display sdl or gtk instead of cocoa if available.
```

See **[BOARD_FB.md](BOARD_FB.md)** for VisionFive / Milk-V / MangoPi bring-up notes (simplefb vs vendor DRM — honest). Full Adam `DolDoc` / mouse grab / 8-bit VGA `GrBitMap` is not on RV; WinMgr keeps the text_base model and presents via 32-bpp.

From the **repository root**:

```bash
make templeos-riscv   # build build/tos-rv.elf only
make templeos-smoke   # build + QEMU ORACLE check (default + selfhost)
```

Requires `riscv64-unknown-elf-{gcc,ld,objcopy}`, `qemu-system-riscv64` (same as `tests/exec` harness), and **Python 3** (generates the 8-byte compiler-slot stub).

## Design: parity with x86 TempleOS

See **[TOS_X86_PARITY.md](TOS_X86_PARITY.md)** for an apples-to-apples map (boot, compiler load, Adam, scheduler, disk, display, multicore) from original TempleOS to this RISC-V kernel, plus phased milestones.

## Self-hosting

Language / boot destination is **guest `Compiler_RV` + `ExePutS` / `Cmp`**, not growing
`bootstrap/hc_repl/jit.hc`. Host `holyc-riscv` remains the transitional AOT bootstrap.
Plan and gates: **[COMPILER_RV.md](COMPILER_RV.md)**. Architecture summary: [../docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md). Doc index: [../docs/README.md](../docs/README.md).

`selfhost/toy_eval.hc` is an early seed under this C loader; the live Cmp path lives in
`Kernel/` + `Compiler/` phase3 smokes (`make kernel-phase3-smoke` from repo root).

The **bootstrap compiler** always lives outside `templeos-riscv/` (`../host/`); this tree never needs to include those sources to build the OS image.
