# Board framebuffer bring-up (RISC-V — not VGA)

TempleOS/RV draws into a **software 32-bpp XRGB8888** compose buffer (`Kernel/RVFb.HC`) and **presents** through a pluggable backend. Each present **MemCpy-flips** compose → scanout (TempleOS `gr.dc2` shape) so cocoa/SDL ramfb never samples mid-frame wallpaper/text blits. Boards should not reimplement Gr*/term — only how scanout memory is discovered and flushed. Soft layout: scanout @ `FB_SOFT_BASE`, compose @ `+2MiB`.

## One-command interactive desktop

```bash
make kernel-win-run          # QEMU ramfb + virtio-kbd/tablet (cocoa on macOS)
# Click the **QEMU cocoa/SDL window** (not the host terminal) for virtio-kbd/tablet.
# Tab cycles focus; click selects a window; drag title bar to move; drag border to resize.
# Term + Adam: HolyC + Enter (ExePutS). HOME: arrows/PgUp/PgDn scroll.
# ESC quits. Serial TTY stays live: HolyC at `>` (e.g. 1+1;) + fault→crash> / q
# Uses -m 256M (VirtioInput rings sit above 128M).
# QEMU: -serial mon:stdio (UART + monitor on the terminal; Ctrl-A then C for monitor).
```

**Focus:** Host-terminal keys → UART HolyC REPL. Cocoa/SDL window keys/clicks → VirtioInput
→ focused WinMgr window (Term by default). Term/Adam Enter runs the **same** `ExePutS` / soft
Dispatch as serial (Print mirrored into that window’s body). If the FB looks dead, click the
QEMU window once so the OS gives it input focus.

### Original TempleOS WinMgr model (in-tree)

Sources: `Adam/WinMgr.HC`, `Adam/Win.HC`, `Adam/DolDoc/DocTerm.HC`, `Adam/DolDoc/DocPutKey.HC`,
`Kernel/SerialDev/Keyboard.HC`, `Kernel/KeyDev.HC`.

| Behavior | Original |
|----------|----------|
| Window identity | One window per Core0 **task** (`CTask.win_*`); WinMgr is its own task |
| Focus | `sys_focus_task`; `WinFocus` / `WinToTop`; click → focus |
| Keys | `TaskMsg` → User live GetMsg (`RVKSpawn` + `RVWinScanKeyDown`) or Fs ScanMsg / parked PutKey |
| Create / destroy | Spawn task + `DocTermNew`; close via title `[X]` → `Kill` / `CH_SHIFT_ESC` |
| Move | L-button drag on **title bar** (not MENU left-4 / `[X]` right-3) → `WinHorz`/`WinVert` while `ms.lb` |
| Resize | Drag **left / right / bottom / BR corner** borders |
| Z-order | Task queue order; focused/`WinToTop` on top; `WinZBufUpdate` |
| Max / tile | `WinMax`, `WinTileHorz`/`WinTileVert` (API, not auto-tiling WM) |
| Scroll | Ctrl+drag = grab scroll (`scroll_x/y`); Doc has own cursor scroll |
| Menu / Ctrl-Alt | Top-row menu when pointer in wallpaper strip; **Ctrl-Alt-C/X/T/N/D/Del** via `KeyDevCtrlAltInit` + Alt tracking → stock `fp_ctrl_alt_cbs` (T/D RV stand-ins; Esc→T, Tab→N) |
| WallPaper | Top status + **heap / idle / task rows** (Adam/WallPaper lite; not full caller-stk) |
| AutoComplete | **RVAC** keyword seed + F1–F10 fill-in on Term/Adam (not full `ACTask` Spawn / dict) |
| Adam / HOME / Term | Adam = parent task Doc; User `DocTermNew` terms; HOME.DD is a normal DolDoc |

Free-floating text-cell windows (not a tiling WM). Wallpaper under windows.

### RV vs original (feature matrix)

| Feature | Original | RV before | RV after (this pass) |
|---------|----------|-----------|----------------------|
| Focus / Tab / click | Yes | Yes | Yes |
| Z-order (focus on top) | Yes | Yes (compose pass) | Yes |
| Title + border chrome | Yes | Yes (Doc-lite) | Yes |
| Title-bar **move** | Yes | No | **Yes** (drag) |
| Border **resize** | Yes | No | **Yes** (L/R/B/BR) |
| Term HolyC ExePutS | DocPutKey→JIT | Yes | Yes |
| Adam HolyC when focused | Adam Doc | Static / body-append only | **Yes** (ExePutS) |
| HOME Doc navigate | Full DolDoc | Static / body-append | **P2 CDoc** (LK/TR click/Enter + scroll) |
| PutKey → focused task Doc | Yes | Term-only special case | Focus router + `TaskMsg(MSG_KEY_*)` → PutKey |
| Per-task windows | Yes | CRVWin slots (not CTask) | **P1** CRVWin↔`CTask.win_*` + `sys_focus_task` |
| `[X]` / MENU / Kill | Yes | Title cue only | **Yes** (hide; User `[X]`≈Kill; **PersonalMenu-lite** / Ctrl-M) |
| Ctrl-grab scroll / menus / ODE | Yes | No | **Ctrl-scroll** + **P3 menu/PopUp lite**; **P5** AMathODE_RV + stock `Demo/Games/MassSpring.HC` (`GetMsg`/`draw_it`) |
| Full DolDoc / CDC blot | Yes | Doc-lite $$ escapes | **P2 subset** HOME CDoc; Term Doc-lite |
| WinMax / WinTile | Yes | No | **Yes** (`RVWinMax` / `RVWinTile*`; serial `max`/`tileh`/`tilev`) |

### Cocoa verify (macOS)

After `make kernel-win-run` (rebuilds `win_hold.elf` if Kernel `.HC` changed):

Screen updates should look stable (no full-frame blink): paint goes to the compose
buffer and only the finished frame is MemCpy'd to the ramfb scanout.

1. Click the **QEMU window** (not the serial terminal).
2. Move the tablet cursor; click Adam / Term / HOME to change focus (solid border).
3. **Drag the title bar** (middle of top border, not the left “MENU” or right `[X]` zone) — window moves.
4. Drag the **right/bottom/corner** border — window resizes.
5. With **Term** focused, type `1+1;` then Enter — `ans=2`, new `>` prompt.
6. Focus **Adam** (upper-left), type `2+2;` Enter — Adam body shows eval / `ans=4`.
7. Focus **HOME** (bottom), press Down / PgDn — scrolls; click a red link or purple tree (or Enter) — wallpaper / collapse; printable keys do not trash the doc.
8. Click title **MENU** (left) — PersonalMenu-lite pulldown (Tile/Max/Close/About/Help); About → PopUpOk; Ctrl-M same. Wallpaper shows live `upd=` / `wins=` / `mem=` plus **heap / idle / task** rows (MENU toast briefly sticky).
8b. **Ctrl-Alt** (click QEMU window first): **C** break flag, **N**/Tab next focus, **T**/Esc new User Term, **X** close focus, **D** soft DbgMode, **Del** quit. Stock `KeyDev` cbs + `RVCtrlAltFlagsService`.
8c. Type a HolyC prefix in Term (e.g. `Pri`) — wallpaper AC line; **F1** completes (`Print`).
9. Hold **Ctrl** and drag on a window body — Doc-lite pans (`scroll_x`/`scroll_y`). Serial: `tileh` / `tilev` / `max` reflow layout.
10. **Stock MassSpring** (not an Adam panel clone): headless oracle `make kernel-ode-smoke` includes `Demo/Games/MassSpring.HC`. Interactive feel: run the demo so `Fs->draw_it=&DrawIt` and `QueIns(ode,Fs->last_ode)` — WinMgr calls `ODEsUpdate` + `task->draw_it`, and posts `MSG_MS_*` (L-click place; R-drag / Shift+L spring). Physics match TempleOS (collision in `MyDerivative`; springs/drag in AMathODE — no synthetic gravity/floor).
10b. **Stock Apps/Span** (Apps ladder after FileMgr): `make kernel-span-smoke` `#include`s `tos/Apps/Span/Load.HC` (`Cd(__DIR__)` via host `__DIR__` builtin + soft pre-init `Cd`). Proves SpanNew/Bridge PlaceMass×15 / DrawIt / CtrlBttn + GrFloodFill + TaskMsg→`GetMsg` PlaceMass + WinMgr bind/`RVWinMgrPostMs`→`GetMsg`+ESC + `PopUpFileName` dft + FilesFind `PopUpPickFile` (`A:/`). Shims: `ASnd_RV`, `TEXT_COLS`/`TEXT_ROWS`, `DocCursor`, `MenuPush`, `CtrlBttnDel`, soft `PopUpOk`. **Still open for full `Span()`:** infinite `Span()` loop with live `WinMgrTask` Yield pump, stock `FileMgr(FM_PICK_FILE)` GetMsg/`PopUp` servant, `DirMk("~/Span")` (RAM-disk DirMk hang), SongTask audio (Play soft). Psalmody API+`$IB`: `make kernel-psalmody-smoke` (Note2Ona/Menu/Tempo + host `$IB` staff fixture); stock `PsalmodyDraw.HC` trailer has 17 CDocBins (TinkerOS/ISO). Full `Load` still needs remaining Psalmody shims under WinMgr.
11. **ESC** closes menu/PopUp first, else quits WinMgr. Serial `q` also quits.

Headless CI: `make kernel-win-interactive` proves paint + `input_ok=1` + serial ExePutS +
**Term** `3+4;` → `ans=7` + **Adam** `5+5;` + **HOME** scrolls + synthetic **move** +
P0 **menu** / **layout** / **ctrl-scroll** / **close**
(`term_cmds`/`adam_cmds`/`home_scrolls`/`move_drags`/`menu_hits`/`layout_ops`/`scroll_drags`/`close_hits` ≥ 1)
plus P1 **task_binds** / **msg_keys** / **msg_consumed** / **user_spawns** / **user_cmds** / **zbuf_updates** / **zbuf_hi** ≥ 1. Guest fair-polls VirtioInput every
WinMgr tick; cursor save-under is outside `CRVWinMgrGlbls` so it cannot clobber `input_ok`.

**AOT cache:** Make owns `build/exec/win_hold.elf` (HOLD / cocoa) and `build/exec/win_i.elf`
(headless). First build runs host `holyc-riscv` AOT of Kernel+Compiler_RV (~10s) and prints
per-file / stage progress on stderr when your terminal is a TTY (`holyc: parse…`, includes,
`optimize…`, `size pass N…`). Force with `HOLYC_PROGRESS=1`; silence with `HOLYC_QUIET=1`.
Later `make kernel-win-run` reuses the ELF when Kernel/Compiler HolyC,
`holyc-riscv`, harness, or the case `.hc` are unchanged — QEMU starts immediately. Force a
rebuild with `make kernel-win-rebuild` (or `rm build/exec/win_hold.elf`). Touching a Kernel
`.HC` or rebuilding the host compiler also triggers AOT.

Headless proof (no cocoa): `make kernel-win-interactive` / `make kernel-win-serial-smoke`
(serial smoke uses the same HOLD ELF with `-display none` + piped `q`).
After serial `q` / ESC, cocoa may keep the QEMU window until you close it or Ctrl-C the
host terminal — that is a display-backend quirk, not a guest hang (UART already shows
`RVWinSerial: quit WinMgr` / `DONE`).

### Serial REPL while FB is up

WinMgr owns **virtio-keyboard/tablet** for graphical Term/Adam/HOME. The **UART** is a separate
always-on HolyC **ExePutS** REPL (`Kernel/RVWinSerial.HC`, same eval path as A2 / `repl-cmp`),
polled each WinMgr tick:

| Where | What |
|-------|------|
| Graphical Term | Focus Term; HolyC + Enter (`ExePutS`); title-drag / border resize; MENU / `[X]` |
| Graphical Adam | Focus Adam (upper-left); same ExePutS into Adam body |
| Graphical HOME | Focus HOME; arrows/PgUp/PgDn/Space scroll Doc-lite; Ctrl-drag scroll |
| Serial (`-serial mon:stdio`) | Same `>` HolyC / meta `fault`/`crash`/`q` / `max`/`tileh`/`tilev` / dig-down `regs`/`bt`/`md`/`mw` |

WinMgr fair-polls VirtioInput every tick (before and after UART serial) so HolyC `ExePutS` on
either console cannot starve kbd/tablet.

```text
# on the host terminal that owns -serial:
1+1;           # → ans=2
Print("hi\n");
fault          # → UART crash> (md/mw/regs/bt/go/reboot)
go             # leave crash mon; WinMgr continues
q              # quit WinMgr (same as ESC)
```

Crashes dump to **serial** (`*** UART crash dump`), not only the FB. Dig-down helpers
remain for CSR/mem without compiling; the primary serial loop is HolyC, not dig-down-only.
Smoke: `make kernel-win-interactive` (banner + `ExePutS probe ans=2`) or `make kernel-win-serial-smoke`
(`40+2;` → `ans=42`, fault→crash dump → `go`, quit).

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
make kernel-cdc-smoke
make kernel-demo-netofdots-smoke  # stock Demo/Graphics/NetOfDots.HC
make kernel-demo-blot-smoke       # stock Demo/Graphics/Blot.HC (FloodFill3/brush + Win shims)
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
- Full Adam **DolDoc** entry lists / ODE / full `MenuNew` Lex — phased 1:1 WinMgr/desktop plan:
  Cursor canvas `templeos-winmgr-parity.canvas.tsx` (P0 chrome → P2 DolDoc → P3 menu lite → P5 ODEsUpdate/next_ode landed → P6 self-host **not** done).
  **P6 honesty:** soft `MakeAdam_RV_Lite` guest Cmp→Load→Call (`menu_n=8` + `LITE.TXT`) after staging Menu_RV on A: — **not** DoD; full on-target desktop Adam blocked on G8 (class/StrCpy/U0-import) + G9 host residuals + DolDoc — see [docs/GAPS.md](../docs/GAPS.md) § MakeAdam_RV.
- FDT/OF walker for automatic simplefb discovery (addresses stay manual or `SIMPLEFB_*` Kconfig).

## Gaps

- No FDT/OF parser yet — addresses are manual or `SIMPLEFB_*` board-stub constants.
- No HDMI/DSI PHY bring-up in-tree.
- **`Kernel/RVWinMgr.HC`** is a faithful **text_base** WinMgr subset (borders, z-order, titles, **live** wallpaper heap/idle/task rows, `draw_it` → 32-bpp present, VirtioInput click/type) plus **DocTerm** (`DocTermNew`, `DocPut` / `DocDisplay` / `DocBorder`, `DocPrint` → Term body, `RVDocHomeOpen`, `WinMgrTask` / `RVWinMgrSpawn`). **HolyC ExePutS REPL** on UART **and** graphical Term via `RVWinSerial` / `RVWinTermPutChar` (`1+1;` → `ans=2`; `fault`→`crash>`). P0 chrome: title **MENU**/`[X]`, `RVWinMax`/`RVWinTile*`, Ctrl-grab `scroll_x`/`scroll_y`. **Ctrl-Alt core** via `KeyDevCtrlAltInit` + Alt track (`C/X/T/N/D/Del`). **RVAC** Doc-complete lite (`Kernel/RVAC.HC`). **P1:** `CRVWin.task` ↔ `CTask.win_*`, `sys_focus_task` / `WinFocus`/`WinToTop`, MsgPutKey (Fs ScanMsg; Term+User live `RVKSpawn`+`ScanMsg`; `JobsHndlr` skips `JOBT_MSG`; HOME parked PutKey), User ExePutS, `WinZBufUpdate` U16 clip buf.   **P3 (partial):** `Adam/Menu_RV` PersonalMenu-lite pulldown + `Adam/PopUp_RV` PopUpOk/NoYes — not full `MenuNew`/DocForm/Ctrls. **P5:** `ODEsUpdate` on `CTask.next_ode` (soft `winmgr`) + stock `Demo/Games/MassSpring.HC` (`PlaceMass`/`DrawIt`/`GetMsg`) via library shims — no Adam hanging-chain clone. Still missing vs full Adam: full DolDoc Put entry streams, full `ACTask`/dict, 8-bit `CDC` blot / `GrUpdateVGAGraphics`, guest `MakeAdam_RV` (P6 not done; soft Lite probe only), interactive MassSpringDemo as a live WinMgr task (smoke covers Init/DrawIt/ODEsUpdate/RK5).
- Doc-lite escapes (HolyC `$$` → one `$` in memory): `$0–$F` FG, `$B0–$BF` BG, `$FG,n$` / `$BG,n$`, `$TX,"text"$`; unknown `$CMD$` soft-skipped. `StartOS_RV` calls `DocTermNew` + `RVDocHomeOpen` when FB WinMgr is up.
- `rv_sys_gr_force`: `-1` disable, `0` auto (default), `1` force soft+present attempt.
- Host O1-lite (default `HOLYC_O1_MODE=3`): Tier-2 constant-folds only **small** IMMs (`|v|` below typical MMIO — see `IcFoldSafeImm` in `host/compiler.c`); leaf I64 promote skips any-LEA / non-leaf. Bisect with `HOLYC_NO_OPT=1` / `HOLYC_NO_TIER2=1` / `HOLYC_NO_PROMOTE=1`. Mode 4 BB slot forwarding stays opt-in (alias-unsafe). Selfboot does **not** force `HOLYC_NO_OPT`.
