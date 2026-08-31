# Board framebuffer bring-up (RISC-V — not VGA)

TempleOS/RV draws into a **software 32-bpp XRGB8888** buffer (`Kernel/RVFb.HC`) and **presents** through a pluggable backend. Boards should not reimplement Gr*/term — only how scanout memory is discovered and flushed.

## Portable hook: simple-framebuffer

Linux DT binding: `compatible = "simple-framebuffer"` under `/chosen`, with `reg` / `width` / `height` / `stride` / `format` filled by firmware after it has already programmed the display pipeline.

In this kernel (no DT walker yet):

```text
RVFbSimpleFbBind(base, width, height, stride, RV_FB_FOURCC_XR24);
// then RVSysGrInit / RVGrInit — draws into base when bound, present = row copy or no-op
```

`format` must be **x8r8g8b8** / DRM **XR24** for the stub (`RVFbPresentSimpleFb`). Other formats (r5g6b5, a8b8g8r8, …) need an explicit convert path later.

## CI / default profile present (ramfb)

On the **virt-style** CI memory map, present defaults to **ramfb** via fw_cfg (`RV_FB_PRESENT_RAMFB`). Headless smokes use a display-less harness + UART hash — **no window**. Interactive bring-up on a host with a GUI display backend:

```bash
make kernel-fb-smoke   # builds build/exec/fb.elf
# load fb.elf with ramfb + a visible display backend (see make qemu-args / BOARD notes);
# do not use -nographic / headless display if you want a window
```

Same for `build/exec/gr.elf` / `build/exec/win.elf` / `build/exec/kp.elf` (after `make kernel-gr-smoke` / `make kernel-win-smoke` / `make kernel-selfboot-smoke`). Exact harness argv for the default profile: [CI.md](../docs/CI.md) and `make -C templeos-riscv qemu-args`. Soft term / Gr demos remain useful for lower-level FB bring-up; WinMgr is the text_base compositor on top.

**Windowed desktop (TempleOS-style borders):** after `make kernel-win-smoke`, load `win.elf` with ramfb + a visible display. You should see a blue wallpaper, an **Adam** window (solid/focus border) and a **Demo/Graphics** window with `draw_it` color bars. `RVKMain` → `RVSysWinInit` does the same when ramfb is present (`kp.elf`). Without ramfb (typical headless CI) graphics init is skipped.

## Kconfig present default

`make -C templeos-riscv menuconfig` → **Framebuffer present**: `ramfb` on `PLATFORM_VIRT`, `none` on `sifive_u` / experimental boards. HolyC applies this via `Kernel/Drv/RVFbPlat.HC` → `RVFbSetPresent`. See [PLATFORM.md](PLATFORM.md); Kconfig tutorial: [KCONFIG.md](KCONFIG.md).

## Board notes (honest)

| Board / profile | What you typically get | Path for this kernel |
|-----------------|------------------------|----------------------|
| **virt (CI harness map)** | ramfb (not simplefb) | Done — default present for smokes |
| **sifive_u** | no ramfb | UART bring-up; FB via simplefb bind only if you add scanout |
| **VisionFive 2** (StarFive JH7110) | U-Boot/Linux often use **vendor DRM/KMS** (inno HDMI + multi-plane). A **simplefb** node appears only if firmware leaves a linear FB in DT; many desktop boots never expose one. | Prefer: firmware/U-Boot simplefb **or** a tiny JH7110 plane setup that leaves XR24 scanout, then `RVFbSimpleFbBind`. Full DRM is out of scope. |
| **Milk-V** (Duo / Mars / …) | SoC-dependent. Duo-class boards are often **DSI/SPI panel** + vendor drivers; Mars (JH7110 class) similar to VisionFive. Do **not** assume simplefb in the shipping DT. | Same bind hook once firmware publishes a linear FB; otherwise board-specific init before bind. |
| **MangoPi** (MQ / Allwinner D1 variants, etc.) | Allwinner stacks sometimes ship **`allwinner,simple-framebuffer`** during early boot, then hand off to **sunxi DRM**. Early-boot simplefb is the realistic target. | Bind from DT/`chosen` values while simplefb is live; avoid fighting the DRM hand-off. |

**Summary:** simplefb is the **portable** contract when firmware cooperates. Vendor **DRM/KMS** is what Linux uses long-term on these SBCs; this kernel will not drive full DRM soon — get a linear XR24 buffer from firmware or a minimal SoC bring-up, then plug it in with `RVFbSimpleFbBind`.

## Gaps

- No FDT/OF parser yet — addresses are manual or board-stub constants.
- No HDMI/DSI PHY bring-up in-tree.
- **`Kernel/RVWinMgr.HC`** is a faithful **text_base** WinMgr subset (borders, z-order, titles, wallpaper, `draw_it` → 32-bpp present). Still missing vs full Adam: **DolDoc**, mouse/kbd window grab, ODE, 8-bit `CDC` blot / `GrUpdateVGAGraphics`.
- `rv_sys_gr_force`: `-1` disable, `0` auto (default), `1` force soft+present attempt.
- Host O1-lite still has residual risk (bisect with `HOLYC_NO_OPT=1` / `HOLYC_NO_TIER2=1` / `HOLYC_NO_PROMOTE=1`); selfboot smoke does **not** force `HOLYC_NO_OPT` today — Tier-2 folds absolute IMM addresses only when they fit I32 (see `host/compiler.c`).
