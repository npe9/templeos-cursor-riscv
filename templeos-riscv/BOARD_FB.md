# Board framebuffer bring-up (RISC-V — not VGA)

TempleOS/RV draws into a **software 32-bpp XRGB8888** buffer (`Kernel/RVFb.HC`) and **presents** through a pluggable backend. Boards should not reimplement Gr*/term — only how scanout memory is discovered and flushed.

## One-command interactive desktop

```bash
make kernel-win-run          # build win_i.elf + QEMU ramfb + virtio-kbd/tablet (cocoa on macOS)
# Tab cycles focus, click selects, type into Term, ESC quits
# Serial TTY stays live on stdio: help / regs / bt / fault / q
# Uses -m 256M (VirtioInput rings sit above 128M).
# QEMU: -serial mon:stdio (UART + monitor on the terminal; Ctrl-A then C for monitor).
```

### Serial REPL while FB is up

WinMgr owns **virtio-keyboard/tablet** for the graphical Term. The **UART** is a separate
always-on dig-down TTY (`Kernel/RVWinSerial.HC`), polled each WinMgr tick:

| Where | What |
|-------|------|
| Graphical Term | Type via virtio-kbd; Tab/click focus; ESC quits |
| Serial (`-serial mon:stdio`) | `>` prompt: `help`, `regs`, `bt`, `md`/`mw`, `fault`, `q` |

```text
# on the host terminal that owns -serial:
help
regs
bt
fault          # → UART crash> (md/mw/regs/bt/go/reboot)
go             # leave crash mon; WinMgr continues
q              # quit WinMgr (same as ESC)
```

Crashes dump to **serial** (`*** UART crash dump`), not only the FB. Full HolyC
`ExePutS` REPL remains `repl-holyc` / A2; this ELF’s serial console is dig-down + crash>.
Smoke: `make kernel-win-interactive` (banner needle) or `make kernel-win-serial-smoke`.

Headless CI proof (paint hash + `input_ok=1` + DocPut, no window):

```bash
make kernel-win-interactive  # also pulled into make qemu-integration
```

## Portable hook: simple-framebuffer

Linux DT binding: `compatible = "simple-framebuffer"` under `/chosen`, with `reg` / `width` / `height` / `stride` / `format` filled by firmware after it has already programmed the display pipeline.

In this kernel (no DT walker yet):

```text
RVFbSimpleFbBind(base, width, height, stride, RV_FB_FOURCC_XR24);
// then RVSysGrInit / RVGrInit — draws into base when bound, present = row copy or no-op
```

Or set Kconfig `FB_PRESENT_SIMPLEFB` + non-zero `SIMPLEFB_BASE` / `WIDTH` / `HEIGHT` (optional `STRIDE`) so `RVFbPlatApplyPresent` → `RVFbSimpleFbTryBoard` auto-binds at boot.

`format` must be **x8r8g8b8** / DRM **XR24** for the stub (`RVFbPresentSimpleFb`). Other formats (r5g6b5, a8b8g8r8, …) need an explicit convert path later.

`make kernel-fb-smoke` also prints `RVFb simplefb OK` after binding a soft scanout copy (no silicon required).

## CI / default profile present (ramfb)

On the **virt-style** CI memory map, present defaults to **ramfb** via fw_cfg (`RV_FB_PRESENT_RAMFB`). Headless smokes use a display-less harness + UART hash — **no window**. Soft bring-up:

```bash
make kernel-fb-smoke   # build/exec/fb.elf + ramfb hash + simplefb bind proof
make kernel-gr-smoke
make kernel-win-smoke  # DocTerm Put/Display/Border desktop hash
```

Same for `build/exec/gr.elf` / `build/exec/win.elf` / `build/exec/kp.elf` (after the smokes above / `make kernel-selfboot-smoke`). Exact harness argv for the default profile: [CI.md](../docs/CI.md) and `make -C templeos-riscv qemu-args`.

**Windowed desktop (DocTerm):** `win.elf` / `win_i.elf` show a blue wallpaper, **Adam**, **Term** (`DocTermNew` + Put/Display/Border docs), and **HOME.DD** with Doc-lite escapes. `RVKMain` → `RVSysWinInit` does the same when ramfb is present (`kp.elf`). Without ramfb (typical headless CI UART-only boot) graphics init is skipped.

## Kconfig present default

`make -C templeos-riscv menuconfig` → **Framebuffer present**: `ramfb` on `PLATFORM_VIRT`, `none` on `sifive_u` / experimental boards. HolyC applies this via `Kernel/Drv/RVFbPlat.HC` → `RVFbSetPresent` (+ optional `RVFbSimpleFbTryBoard`). See [PLATFORM.md](PLATFORM.md); Kconfig tutorial: [KCONFIG.md](KCONFIG.md).

## Board notes (honest)

| Board / profile | What you typically get | Path for this kernel |
|-----------------|------------------------|----------------------|
| **virt (CI harness map)** | ramfb (not simplefb) | Done — default present for smokes |
| **sifive_u** | no ramfb | UART bring-up; FB via simplefb bind only if you add scanout |
| **VisionFive 2** (StarFive JH7110) | U-Boot/Linux often use **vendor DRM/KMS** (inno HDMI + multi-plane). A **simplefb** node appears only if firmware leaves a linear FB in DT; many desktop boots never expose one. | **In progress:** `visionfive2_defconfig` selects `FB_PRESENT_SIMPLEFB` with `SIMPLEFB_BASE=0` (manual bind). Set `SIMPLEFB_*` or call `RVFbSimpleFbBind` once firmware leaves XR24. Full DRM out of scope. UART+mem map: [PLATFORM.md](PLATFORM.md) § VisionFive 2. |
| **Milk-V Mars** (JH7110) | Same SoC class as VisionFive 2 — do **not** assume simplefb in the shipping DT. | **In progress:** `milkv_mars_defconfig` mirrors VF2 simplefb hook (`SIMPLEFB_BASE=0`); own files — do not overwrite `visionfive2_*`. [PLATFORM.md](PLATFORM.md) § Milk-V Mars. |
| **Milk-V Duo / other** | Often **DSI/SPI panel** + vendor drivers (not JH7110). | Board-specific init before bind. |
| **MangoPi** (MQ / Allwinner D1 variants, etc.) | Allwinner stacks sometimes ship **`allwinner,simple-framebuffer`** during early boot, then hand off to **sunxi DRM**. Early-boot simplefb is the realistic target. | Bind from DT/`chosen` values while simplefb is live; avoid fighting the DRM hand-off. |

**Summary:** simplefb is the **portable** contract when firmware cooperates. Vendor **DRM/KMS** is what Linux uses long-term on these SBCs; this kernel will not drive full DRM soon — get a linear XR24 buffer from firmware or a minimal SoC bring-up, then plug it in with `RVFbSimpleFbBind`.

## Deferred (do not build yet)

- **virtio-gpu** and SoC **DRM/KMS** pipelines — out of scope; keep presenting via ramfb / simplefb XR24.
- Full Adam **DolDoc** entry lists / menus / ODE.
- FDT/OF walker for automatic simplefb discovery (addresses stay manual or `SIMPLEFB_*` Kconfig).

## Gaps

- No FDT/OF parser yet — addresses are manual or `SIMPLEFB_*` board-stub constants.
- No HDMI/DSI PHY bring-up in-tree.
- **`Kernel/RVWinMgr.HC`** is a faithful **text_base** WinMgr subset (borders, z-order, titles, wallpaper, `draw_it` → 32-bpp present, VirtioInput click/type) plus **DocTerm** (`DocTermNew`, `DocPut` / `DocDisplay` / `DocBorder`, `DocPrint` → Term body, `RVDocHomeOpen`, `WinMgrTask` / `RVWinMgrSpawn`). **UART dig-down** via `RVWinSerial` stays live beside FB (`help`/`regs`/`bt`/`fault`→`crash>`). Still missing vs full Adam: full DolDoc Put entry streams, ODE, 8-bit `CDC` blot / `GrUpdateVGAGraphics`.
- Doc-lite escapes (HolyC `$$` → one `$` in memory): `$0–$F` FG, `$B0–$BF` BG, `$FG,n$` / `$BG,n$`, `$TX,"text"$`; unknown `$CMD$` soft-skipped. `StartOS_RV` calls `DocTermNew` + `RVDocHomeOpen` when FB WinMgr is up.
- `rv_sys_gr_force`: `-1` disable, `0` auto (default), `1` force soft+present attempt.
- Host O1-lite (default `HOLYC_O1_MODE=3`): Tier-2 constant-folds only **small** IMMs (`|v|` below typical MMIO — see `IcFoldSafeImm` in `host/compiler.c`); leaf I64 promote skips any-LEA / non-leaf. Bisect with `HOLYC_NO_OPT=1` / `HOLYC_NO_TIER2=1` / `HOLYC_NO_PROMOTE=1`. Mode 4 BB slot forwarding stays opt-in (alias-unsafe). Selfboot does **not** force `HOLYC_NO_OPT`.
