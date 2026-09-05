# Ordered gap-fill plan

Survey of remaining work toward **guest self-host remote** + **operate-through**.
Docs/Makefile only — verify claims against tree before implementing.

**DoD:** Zero guest C on product images; day-to-day Kernel/Compiler/Adam rebuild on
target via `Compiler_RV` / `Cmp` / `Load`; Mac `holyc-riscv` stays as bootstrap.
Operate-through: UART still alive → export dirty set → soft Recover / known-good pins.

Related: [SELF_HOST.md](SELF_HOST.md), [OPS.md](OPS.md), [CI.md](CI.md),
[PLATFORM.md](../templeos-riscv/PLATFORM.md), [DRIVERS.md](DRIVERS.md),
[CONSOLE.md](CONSOLE.md) (UART console wishlist — have/partial/missing).

---

## Done / not gaps anymore

| Area | Evidence |
|------|----------|
| **A0 / A1** | `bootloader-smoke`, `repl-holyc-smoke`; no HostSlots mass on product path |
| **A2** ExePutS / guest Cmp compile | `repl-cmp-smoke` / `kernel-repl-exepubs-smoke` → `build/repl-cmp.elf` |
| Memfs journal **P0–P6** | seal / checkpoint / DumpChanges / Rename / wrap / FsReplay / Recover |
| Hierarchical memfs + seed layout | `/Home` `/Lib` `/Tutorials` …; `seed_layout.py` |
| UART export on product HolyC | `DumpFile` / `DumpChanges` / `FsChanges` on `repl-holyc` |
| ZMODEM (legacy full REPL) | `zmodem-smoke`; `ZmodemSendChanges` |
| Native trzsz send (legacy full REPL) | `trzsz-smoke`; `TrzszSend` / `TrzszSendChanges` |
| **G11** ZMODEM on thin image | **Waived** — DumpFile + 9P; no AOT embed (~28 KiB / JIT risk) |
| 9p client import + share-root export | `NineExport` / `kernel-virtio-9p-smoke` / `repl-9p-smoke` |
| SafeMode / Recover / OPS playbook | [OPS.md](OPS.md); known-good pin/check targets |
| Platform matrix **ok=9** | virt…opentitan Smoke/CI; skips not allowed ([PLATFORM.md](../templeos-riscv/PLATFORM.md)) |
| Drivers: Ibex UART+timer, APLIC MSI, Virtio-PCI blk MMIO→PCI, XPS timer/INTC (amd) | [DRIVERS.md](DRIVERS.md) |
| Debugger soft env (legacy) | Regs snap+restore, Bp, Watch, Step; `dbg-smoke` |
| **G1** soft Regs/MemMap/Callers | **Done** soft — `RegsRestoreDemo`/`post_regs_a7=5`/`Callers` green on `repl-holyc-smoke` + regression. Bt honesty = **`Bt (trap freeze)`** after Fault (trap lane); live `Bt;` without freeze is UART stub. Soft Watch/Step still `hwdbg.hc`. `dbg-smoke` legacy until G17 |
| **G4** Man/Funs embed | Thin `repl-holyc` AOT-includes `man.hc` + `hc_repl/man_sym.hc`; needles in smoke + regression. Remaining: FunPick RX, full hash/srcmap |
| **G5** Tab/complete/history | Smart Tab + multiline `...` + Up/Down multi-entry ring + hist_seed (`HIST_RECALL_OK` / `HIST_UP2_OK` / `HIST_SEED_OK` / `HIST_ML_OK`) + define CompAdd catalog (`MEM_*`/`UART_*`/…) + session `#define` registry (`DefRegister`) + mid-line Tab (`g_rl_cur`/`CompCx`) on `repl-holyc`. Remaining vs legacy: host define_table slot / expansion |
| HW debugger twin (virt) | Guest `hwdbg.hc` Sdtrig probe + `make hwdbg-smoke` gdbstub; OpenOCD still board path |
| Dual-run A3 wiring | **Done** — HolyC-only honesty in `qemu-integration` (A3); worry_dream **deleted** |
| Formal verification | [VERIFICATION.md](VERIFICATION.md) **plan only** — intentional; not a product blocker |

Honest leftovers that are **ops polish**, not A3 blockers: pristine seed ROM reinstall
(power-cycle / rebuild), slot-name 63 / `MEMFS_MAX=96`. ZMODEM/trzsz on thin AOT is
**waived** (G11) — DumpFile + 9P cover operate-through.

**G4 progress (Wave 1 man lane):** thin `repl-holyc` AOT-includes `man.hc` +
`hc_repl/man_sym.hc` (JitFind FnAddr/FnSize, memfs SrcFile/SrcText); embeds full
`man_topics.hc` / `man.hc` / `funs.hc`. UART-proven: `Man("Print")` / `Man("CLINT")` /
`Man("Regs")` / `Sections;` / `FunsList;` / `Funs("Print")` / `SrcFileRep` /
`FnSizeRep`. Needles in `repl-holyc-smoke` + `repl-holyc-regression`. Remaining:
interactive FunPick (`term.hc` RX), full hash/srcmap (dbg `sym.hc`), real FnSize.

**G5 progress (Wave 2 rl lane):** `repl-holyc` AOT-includes `asm_complete.hc` /
`asm_doc.hc` / `complete.hc` / `readline.hc`. Smart Tab: mid-token at `g_rl_cur` →
CompTab (JIT Fun* + **expanded CompAdd define catalog** = MemMap/csr `MEM_*`/`UART_*`/
`VIRTIO_*`/`REG_*`/`CSR_*` + session `DefRegister` from `#define` + host SymDefineHash
when published + memfs + asm{}); else 2sp indent (mid-line ok). Multiline `...` prompt.
History Up/Down: multi-entry ring `RL_HIST_MAX=16` × `RL_HIST_CAP=1024` with **compile-unit**
storage (embedded `\n`) + `RlHistRecallUnit` replay; hist_seed demos (`HIST_SEED_OK`).
Needles `HIST_SEED_OK` + `HIST_RECALL_OK` + `HIST_UP2_OK` + `HIST_ML_OK` + `UART_LSR`
CompCollect + `SESDEF_TAB` + `CompMidDemo`/`RlMidDemo`. Remaining vs legacy: host-slot
define_table / `#define` expansion (Tab registry only on thin path).

---

## Prioritized gap list

Effort: **S** ≤1–2 days · **M** ~3–7 days · **L** multi-week / multi-agent.
Depends-on = DAG edges (do upstream first). Lane = file ownership for parallel agents.

| ID | Name | Why (DoD) | Depends | Effort | Lane (paths) |
|----|------|-----------|---------|--------|--------------|
| **G1** | HolyC Regs / MemMap / StkRep / Callers | **Done** — soft path green on smoke + holyc-regression | — | M | **dbg** — Watch/Step soft remain `hwdbg.hc`; G17 `dbg-smoke` CI optional |
| **G2** | HolyC trapvec + Ctrl-C Break | **Done** on `repl-holyc` (`trap-smoke` + regression) | G1 helpful | M | **trap** — `seed/trap.hc`; asm secondary `::` labels + asm setjmp @ `REPL_JB_FIXED` |
| **G3** | HolyC Vi / Ed / Src→editor | **Partial:** `Ed`/`Vi`/`Src`→Vi on `repl-holyc` (soft RX; Ed→EdHoly); `gd`/`K` covered; **livedrv Done** (`6a` ToUpper Home Ed+Run) | — | L | **ide** — `seed/{ed,edit,vim}.hc`, `hc_repl/{ide_bridge,ide_src,dir,uart}.hc`; [IDE.md](IDE.md) |
| **G4** | HolyC Man / Funs / SymFile embed | **Partial** — Man/Funs needles green; FunPick/hash residual | — | M | **man** — `seed/{man,man_topics,funs}.hc` + `hc_repl/man_sym.hc` |
| **G5** | HolyC multiline Tab / complete | **Partial** — Tab/indent/asm + ring Up/Down + hist_seed + define CompAdd catalog + session `#define` Tab registry + mid-line Tab + multiline unit recall (`HIST_ML_OK`); host define_table / expansion residual | G3 or shared readline | M | **rl** — `seed/{complete,asm_complete,asm_doc,readline}.hc` |
| **G6** | Expand `repl-holyc-regression` → flip needles | **Done** — cover G1–G5+G2 trap+livedrv+Sys/journal/Man/Tab/HIST/language; **Fmt+Demo+G11 ZMODEM waived** | G1–G5 | M | **ci** — `tests/scripts/*holyc*`, [REGRESSION.md](../tests/REGRESSION.md); Makefile only |
| **G7** | **A3 flip** (+ delete `worry_dream`) | **Done** — dual-run dropped; worry_dream **deleted** | G6 + criteria 1–4 | S | **ci** — [A3_FLIP_DRAFT.md](A3_FLIP_DRAFT.md) applied; Fmt+Demo+ZMODEM waived |
| **G8** | **B0** guest Cmp → loadable BIN | Remote rebuild starts; self-host DoD Track B | A2 done | L | **cmp** — `Compiler/**/*RV*`, phase3 / ExePutS UART proof; [COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md). **Partial:** MakeOS/Runtime/AdamCore + soft AdamLite (menu_n=8) BINs green; **not** full Adam/DolDoc/`MakeAdam_RV`; class/StrCpy-glbl/U0-import gaps |
| **G9** | **A5** thin HolyC phase3 + RedSea BINs | Boot ≠ “host AOT’d demo ELF” alone | G8 partial OK | L | **phase3** — `Adam/`, `Kernel/RVPhase3.HC`, RedSea Load path. **Partial:** guest BINs + **reloc heap Load** of virtio RedSea `Compiler.BIN` (ELF `.compiler_bin` dropped by default) + **staged probe `Kernel.BIN`** FileFind+Load+`KernelEntry` handoff before Cmp + **`kernel-thin-loader-smoke`** (mount→Load→Call, no Cmp); residual = phase3 ELF Cmp/StartOS scaffold + host `pack_tosb` seeds (not bootable Kernel_RV) |
| **G10** | **A4** retire `templeos-riscv/kernel/*.c` from CI | Honest product images; drop `templeos-smoke` dependency | G9 or HolyC plat ORACLE | M | **c-kernel** — `templeos-riscv/kernel/`, Makefile `templeos-smoke` |
| **G11** | ZMODEM on `repl-holyc` | **Waived** — not A3/G7 | — | S | **export** — embed refused (~28 KiB `zmodem.hc`+`trzsz.hc`, JIT risk); product = DumpFile/DumpChanges + virtio-9p; legacy `zmodem-smoke`/`trzsz-smoke` = local only |
| **G12** | Virtio-PCI finish | TCP/IP; AIA MSI-X→IMSIC | BlkDev MMIO→PCI + 9p/net PCI + INTx MEIE done | M | **virtio** — TCP; MSI-X on AIA boards |
| **G13** | ARCH_RISCV32 host emit | **Later** — after RV64 virtio/net/drivers green; not ahead of FE310 XIP work | RV32.md §9 + RV64 driver queue | L | **rv32** — `host/compiler.c` `parser.c`; FE310 silicon is RV32 but layout/smoke first on RV64 codegen |
| **G14** | APLIC / IMSIC residual | Nested S-domain / guest files | MSI + eithreshold + multi-hart TARGET | M | **plic** — `Kernel/Drv/RVPlicAplic.HC` |
| **G15** | SMP residuals | Seth JobQue / `mp_cnt` finalize / OpenSBI HSM | mailbox + MSIE WFI + `RVSmpMpCnt` + smoke | M | **smp** — `Kernel/Drv/RVSmp.HC`, `crt0_smp.S` |
| **G16** | IDE ErrGo line:col | Operate/debug UX; not A3 gate | G3 | S | **ide** — [IDE.md](IDE.md) P0 |
| **G17** | `dbg-smoke` in CI (optional) | Soft dbg regression without legacy-only | G1 | S | **ci** — wire after HolyC Regs green |
| **G18** | Track **B1–B3** remote MakeOS | Full on-target Kernel/Compiler/Adam rebuild | G8–G9 | L | **cmp** + docs smoke without Mac AOT rebuild step |
| **G19** | Verification P0 experiment | Optional quality; **not** DoD | — | M | **verify** — `host/` encode slice; [VERIFICATION.md](VERIFICATION.md); no default CI |
| **G20** | FE310 / sifive_e product image | XIP Kernel + DTIM bootloader dual artifact; REPL still out | — | M | **plat** — `kernel-sifive-e-full-smoke`; imports host-prepatched; RV32 emit = G13 later |
| **G21** | VisionFive 2 (JH7110) board bring-up | UART+mem+simplefb; **in progress** — packed plat.bin, REG_SHIFT=2, OpenOCD; no QEMU `-M` | — | M | **plat** — `visionfive2_*`; keep **out of** matrix until green |
| **G22** | Milk-V Mars (JH7110) board bring-up | Sibling of G21 — own `milkv_mars_*` (do not overwrite VF2) | G21 patterns | M | **plat** — `milkv_mars_defconfig`, `link_milkv_mars.ld`; out of matrix until green |

**Critical path after A3 flip (delete `worry_dream` → remote self-host):**

```text
G1–G6 Done ─► G7 Done (flip CI) ─► worry_dream deleted
                                    then G8 → G9 → G10 → G18  (remote self-host)
```

---

## Wave schedule (max 3–4 lanes)

### Wave 1 — immediate parallel (A3 unblock)

| Lane | Owner focus | Paths (do not collide) | Exit |
|------|-------------|------------------------|------|
| **dbg** | G1 HolyC Regs/StkRep/Callers/MemMap | `bootstrap/seed/debug.hc`, `csr.hc`, `sym.hc`; `hc_repl/repl.hc` `#include` + JitAdd | **Done** — needles in holyc-smoke + holyc-regression |
| **trap** | G2 trap + Break | `bootstrap/seed/trap.hc`, `hc_repl/start.hc` / UART; no C guest growth | **Done** — Fault dump + Ctrl-C on HolyC path |
| **ide** | G3 editor surface | `bootstrap/seed` editor seeds; `hc_repl/{dir,ide_*,uart}.hc` | **Partial** — Src→Vi; Ed→EdHoly; `gd`/`K` covered; **livedrv Done** (`6a` ToUpper) |
| **man** | G4 Man/Funs embed | `bootstrap/seed/man*.hc`, `funs.hc`; `hc_repl/man_sym.hc` + `repl.hc` `#include` | `Man("Print")` / `Man("CLINT")` / `FunsList;` on `repl-holyc` — **partial** (interactive FunPick still legacy; hash/srcmap via dbg) |

Coord rule: **do not grow `jit.hc`**; prefer seed AOT + `repl-cmp` for Cmp-heavy work.
`Makefile` / regression scripts owned by Wave 2 **ci** lane — Wave 1 only add `#include`s.

### Wave 2 — close A3 + export polish

| Lane | Focus | Paths | Exit |
|------|-------|-------|------|
| **rl** | G5 Tab/complete | `seed/complete.hc`, HolyC readline | **partial** — Tab + define CompAdd catalog + session DefRegister + mid-line Tab + 16×1024 ring + unit recall + hist_seed; host define_table / expansion remain |
| **ci** | G6 + G7 | `Makefile`, `tests/scripts/`, SELF_HOST, A3_FLIP_DRAFT | **G6+G7 done** — dual-run dropped; worry_dream **deleted** |
| **export** | G11 ZMODEM | docs waiver + FILE_EXPORT | **Waived** — DumpFile/DumpChanges + 9P; no thin embed |
| **cmp** | G8 B0 spike start | `Compiler/*RV*`, phase3 harness | UART: guest Cmp → loadable BIN |

### Wave 3 — remote self-host + drivers

| Lane | Focus | Paths | Exit |
|------|-------|-------|------|
| **phase3** | G9 A5 | `Kernel/RVPhase3.HC`, Adam StartOS_RV | Thin loader + guest BINs |
| **c-kernel** | G10 A4 | `templeos-riscv/kernel/`, Makefile | `templeos-smoke` retired or HolyC ORACLE |
| **virtio** | G12 | `Kernel/Drv/Virtio*` | Blk/9p/net PCI + INTx MEIE done; AIA MSI-X / TCP residual |
| **rv32** *or* **smp** | G13 / G15 | `host/` *or* `RVSmp.HC` | Pick one; do not dual-own `host/` |

**Deferred / background:** G14 APLIC polish, G16 ErrGo, G17 dbg CI, G19 verify.
G20 FE310: XIP Kernel + DTIM bootloader dual artifact OK; full REPL still blocked by 16 KiB DTIM.
G13 RV32 emit: **after** RV64 virtio/net/driver queue — do not cut ahead for FE310.

---

## Smoke / CI inventory (gap-relevant)

| Target | Role vs gaps |
|--------|----------------|
| `repl-holyc-smoke` / `repl-holyc-regression` | A3 product honesty — **primary CI gate** (G6 Done) |
| `a3-flip-check` | G7 readiness — last **READY**; A3 flip applied |
| `repl-cmp-smoke` / `kernel-repl-exepubs-smoke` | A2 **done**; Cmp home for G8 |
| `bootloader-smoke` | A3 criterion — keep green |
| `repl-smoke` / `repl-regression` | **Retired** with worry_dream delete |
| `dbg-smoke` | Soft dbg — not in `qemu-integration` yet (G17) |
| `hwdbg-smoke` | Host gdbstub + guest `HwTrigProbe` — local/CI-optional; needs `riscv64-*-gdb` |
| `dump-changes-smoke` / `zmodem-smoke` / `trzsz-smoke` | Export — DumpChanges **required**; ZMODEM/trzsz local-only (**G11 waived**) |
| `kernel-plat-smoke` / `kernel-plat-matrix` | Boards OK; **skips not allowed** |
| `kernel-visionfive2` | JH7110 plat **build** (board-only; not in matrix yet) |
| `kernel-milkv-mars` | Mars JH7110 plat **build** (board-only; not in matrix yet) |
| `kernel-sifive-e-full-smoke` | FE310 DTIM boot → XIP Kernel (optional; not matrix) |
| `kernel-phase3-smoke` | Self-host building block — deepen in G9 |
| `templeos-smoke` | C image — retire in G10 |
| `known-good-pin` / `check` | Ops — done (local) |

---

## Console stack (post-A3 / parallel wishlist)

Full matrix: [CONSOLE.md](CONSOLE.md). Not A3 blockers unless noted (G1/G2/G5 already
are). Top **missing** items to schedule after Wave 1–2:

| ID | Name | Why | Depends | Effort | Notes |
|----|------|-----|---------|--------|-------|
| **G22** | Framed multi-channel UART | Binary-safe ch0..ch4; unlocks dbg/log/FS without eating TTY | G2/G5 helpful | M | **Partial** — `frame.hc` + `tools/uart_mux.py`; off by default (`UartMuxOn`); not in early boot Run |
| **G23** | Guest GDB RSP on UART (dbg ch) | Board dbg without JTAG/qemu-gdbstub | G22 for ch2 | L | **Partial** — `gdbstub.hc` + `gdb-uart-smoke`: `?`/`g`/`G`/`m`/`M`/`Z0`/`z0`/soft-`s`/`c`→S05/`D` (inline snap; soft Bp table). Remaining: live resume while attached, ch2 round-trip |
| **G24** | dmesg ring → log channel | Severity + panic ≠ stdout | G22 for ch3 | S | **Partial** — ring done; `LogMuxEmit` stub in `log.hc`, **redefined** in `frame.hc` → ch3 when `UartMuxOn` |
| **G25** | VT mux (2+ consoles over UART) | tmux-like attach | G22 | M | **Partial** — `Vt`/`VtAttach`/`VtDetach`/`VtCapture`/`VtKeys`(Ctrl-A); `VtPane(a,b)` + framed `P\ta\tb`; host `--vt-follow`/`--vt-split`/`--vt-panes`; **no guest ANSI TTY split** |
| **G26** | XON/XOFF (or RTS/CTS) flow control | Panic/bulk Dump/9P | — / G22 | S | **SW XON/XOFF done** (`UartXonXoff`, `repl-uart-xon-pty`); **RTS/CTS soft stub** (`UartRtsCts` / `RVUartRtsCts`) — **no-op on virt** (real pin wiring TBD) |
| **G27** | /proc-ish inspection remainder | `ps` / mounts UART UI | — | S | **Core done** — `bootstrap/seed/sys.hc` (`Sys`/`Uptime`/`MemRep`/`IrqRep`/`DevRep`/`Cnts`). **Remaining:** task table, mounts |
| **G28** | Path/`::` vs UART/host Unix dual-namespace | One TempleOS grammar for Cd/FilesFind/`#include`/`__DIR__` | — | M | **Partial** — [PATHS.md](PATHS.md): host `A:`/`::` + `tos/` include fallback; `__DIR__`→`/…` (keeps `tos/`); UART `FsResolve` accepts `::`/`A:`/`~`, `Pwd`→`::/`. Residual: memfs≠BlkDev letter; 9P as `P:`; `__DIR__`≠guest `::/` |

**Waived:** **G11** ZMODEM/trzsz on thin `repl-holyc` — DumpFile + DumpChanges + virtio-9p
cover operate-through; embed refused (~28 KiB / JIT risk). See [SELF_HOST.md](SELF_HOST.md).
Virtio-9p remote FS is **not** a gap (have); UART 9P waits on G22.

---

## Explicit non-goals (do not schedule as gaps)

- Deleting Mac `host/*.c` / `holyc-riscv`
- Permanent plat matrix skips
- Growing `jit.hc` for IDE/debugger
- Full OS formal proof / default-CI Frama
- Guest-as-9p-server / TCP 9p / full IP stack
- WinMgr / DolDoc as A3 blockers — FB DocTerm-lite now has title-drag move, border
  resize, Adam ExePutS, HOME scroll, **P0** `[X]`/MENU stub, WinMax/Tile, Ctrl-grab
  scroll (see [BOARD_FB.md](../templeos-riscv/BOARD_FB.md));
  **P1 (done):** User live `RVKSpawn` GetMsg→PutKey (`RVWinScanKeyDown` avoids
  `ScanMsg`/`JobsHndlr` mepc=0 on fresh tasks); Term/HOME parked; Fs ScanMsg.
  Canvas leftover closed (Term live + full JobsHndlr still open polish).
  **P2 (partial, deepen 2026-09-04):** `Kernel/RVDoc.HC` CDoc entry stream for HOME
  **and** Term/Adam paint (`DocNew`/`DocPutS`/`DocRecalc`, `$$LK`/`$$TR`/`$$ID`/
  `$$TX`/`$$FG`/`$$BT`/`$$DA`/`$$CB`/`$$MA`, cheap `$$PB`/`$$CL`/`$$PT`/
  `$$BK`/`$$IV`/`$$UL`, plus `$$AN`/`$$MU`/`$$LS`/`$$CM`/`$$SX`/`$$SY`/`$$WW`/
  `$$HL`/`$$LM`/`$$RM`/`$$PL`/`$$SP`/`$$IB`, plus `$$HX`/`$$SO`/`$$HC` and
  `TX`/`LK` `HTML=`). `DocSave`/`DocWrite`/`DocRead` with trailing `CDocBin` blobs;
  `DocBinFind*`/`DocBinsValidate`/`DocBinNew`. Modal `DocEd` (DOCF_FORM +
  inject/ScanMsg) + `DocForm` Lex-lite + class-meta + `DocMenu`-lite. HOME `FI:`
  open → Welcome/HelloWorld/HelpIndex/DemoInPage. Host `RVDocDemoProbe` embeds
  `Demo/ToHtmlToTXTDemo/DemoInPage.DD` shape via `$$…$$` string fold.
  `Adam/DolDoc/MakeDoc_RV.HC` shim → `DocInit_RV` + `RVDocDemoProbe`. **Landed
  (2026-09-04):** `Adam/DolDoc/DocInit_RV.HC` stock DefineLstLoad +
  `doldoc.hash` HashDefineLstAdd (hand-planted dft flags; no CmpCtrl). DemoInPage
  smoke prints `lex=` HashFind hits. Still open: full stock `PrsDollarCmd` Lex +
  CmpCtrl `PrsDocFlags` (G8), guest MakeDoc `#include` Adam/DolDoc/* — not A3 gates.
  **1:1 desktop parity roadmap (P0–P6):** Cursor canvas
  `templeos-winmgr-parity.canvas.tsx` under the project `canvases/` dir (survey +
  gap matrix + phased exit criteria) — not scheduled as G-lane gaps here.
  **P3 (partial, 2026-09-04):** `MenuNew`/`MenuFile` → real `CMenu` (hand Lex SoT).
  `MenuNewCmpCtrl` **re-enabled** via `RVCmpCtrlAddrsGet` (Compiler-unit abs addrs) +
  soft-I64 (no `LexExpressionI64` Call); Kernel `&CmpCtrlNew` GOT was the illegal-insn
  root (`insn≈0x8098`). `RVDoc` `DocForm` class-meta when `HTT_CLASS`+format else Lex-lite
  DocEd; `Ctrls_RV` `CCtrl` queue + `DrawCtrls` on CRVDC; PopUpOk + `RVDocFormMeta`.
  **Demo enablement:** `GrFloodFill3`/brush/`GrLine3` + soft `SettingsPush`/`WinMax`/
  `PopUpColor`/`Refresh` (`Adam/WinDemo_RV.HC`); stock `Demo/Graphics/Blot.HC` smoke.
  **P6 not done** — see MakeAdam_RV blockers below
- Full POSIX job control / pipelines as console DoD (REPL-as-shell is enough)

---

## MakeAdam_RV / P6 self-host desktop (honest blockers)

**Not complete.** `Adam/MakeAdam_RV.PRJ` still `#include`s full `MakeAdam` (Gr + DolDoc +
Ctrls + AC + WallPaper sprites). Guest Cmp cannot rebuild that stack as product WinMgr yet.
`MakeAdam_RV_Core` / guest `AdamCore.BIN` only plant A: markers — not desktop Adam.

| Blocker | Why it blocks P6 exit | Evidence |
|---------|----------------------|----------|
| **G8 remainder** | Guest Cmp of large multi-file Adam/Compiler projects (not tiny Runtime BINs) | phase3 MakeOS/Runtime OK; full `Compiler.PRJ` / `MakeAdam` not guest-Cmp’d |
| **G9 residual host AOT** | phase3 ELF Cmp/StartOS scaffold + host `pack_tosb`→RedSea virtio img still Mac-built; live Cmp is reloc heap Load (no default ELF `.compiler_bin`); Runtime staging strings in ELF text; RedSea `Kernel.BIN` is **probe** (`KernelProbe→42`, `KernelEntry→0x4B45`) not full Kernel_RV — FileFind+Load+handoff before Cmp landed; **thin loader ELF** (`thin_loader.elf`) proves mount→Load→`KernelEntry` without Cmp | [COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md) P3 residual — Body / HostBinEmbed / Menu U8[] / default `.compiler_bin` **gone**; Kernel seed + thin handoff landed; bootable Kernel.BIN / non-returning handoff next |
| **DolDoc / Menu Lex** | CmpCtrl MenuNew on split-AOT via abs addrs | Hand Lex SoT; `RVCmpCtrlAddrsGet`+soft I64 `MenuNewCmpCtrl`; DocForm class-meta |
| **PopUp_RV / WinMgr** | PopUp needs `CRVWin` / `rv_winmgr` symbols | Soft Lite probe omits PopUp; host AOT `win_*.elf` still bootstrap |

**P6 soft probe (landed, not DoD):** phase3 stages in-tree `Adam/Menu_RV_Guest.HC`
(+ `Menu_RV` wrap with `MENU_RV_GUEST_CMP` + folded `Menu_RV_Guest_Lex`) via
`RVAdamLiteMenuSrc` (G9 — **no** full Menu U8[] embed). Guest chrome APIs: Count/Name/Id/
**Width** (shared with host WinMgr surface). Wrap `#include`s Lex then Guest. Soft probes:
`LiteMenuLex` / `LiteLexFold` / flat Guest — **currently guest Cmp err=1** (regression vs
prior PersonalMenu-only Guest; Width/Lex body under bisect). AdamLite prefers
`#include "Menu_RV"` → Init + `FileWrite(LITE.TXT)` + `return 8`; **menu-free FileWrite
fallback** if Menu include Cmp fails (keeps StartOS Load→Call needle). Nesting
`CMenu`/`CAlloc` still **blocks** guest product Menu. Host `Menu_RV`: real `CMenu` hand Lex
+ `MenuNewCmpCtrl`, `MenuTask`/`MenuEntryWidth`, unified `MenuPush`/`MenuPop`.
PopUp CRVWin / DocTerm remain host WinMgr (`win_*.elf`). Soft — does **not** gate phase3.
Load→Call needle: `P6 MakeAdam_RV_Lite Load→Call OK (menu_n=8 Lex+Guest|Menu_RV, LITE.TXT)`.

**Guest Cmp gaps found this pass (G8 remainder):**

| Surface | Symptom |
|---------|---------|
| `class` with member arrays / globals | guest Cmp **hang** (I64-only class OK) |
| Nested `#include "Menu_RV"` → AdamLite Call | **OK** if Load→Call **before** flat Menu Load |
| Guest `FileWrite` inside AdamLite.BIN | **OK** as Count→local then multi-STR `FileWrite` (CALL_IMPORT restores SP after `_RV_HC_CALL`). Guest plants LITE.TXT |
| Local `U8 name[32]` | guest Cmp **OK** |
| Local `U8 *p="lit"; return 1` | guest Cmp **OK** |
| `*"lit"` / `return *p` / ident walk | guest Cmp+Call **OK** (`CmpU8StarType`: host AOT `type+1` was +1 byte; also prior pack `PREC<<16+i` → ic 0x4000). Ident walk still soft |
| Glbl `U8[]` elem after StrCpy | Cmp OK; Call soft-fail r=0 (ABS_ADDR / REG_RAX=x0 — separate) |
| Span `DirMk("A:/Span")` | phase3 Soft Call **OK** (`DrvUnlock` Yield only if live peer). Span smoke still soft-skips live DirMk (Doc Print under put_doc) |
| Guest index Lex (`Menu_RV_Guest_Lex`) | wrap **folded**; flat Guest_Lex Cmp **err=1** (bisect) |
| Lex+Guest fold wrap (`LiteLexFold`) | Cmp **err=1** while Guest/Lex Cmp red |
| Flat Guest (+Width) | Cmp **err=1** (was OK as PersonalMenu-only extract) |
| Guest Kernel `CMenu` / `CAlloc(sizeof)` | **BLOCKED** flat Cmp — keep `MENU_RV_GUEST_CMP` |
| Rich host `Menu_RV` CmpCtrl / PopUp / DocTerm | WinMgr `win_*.elf` path (not guest product yet) |

**Next 3 steps (order):**

1. Unblock guest Cmp of flat Guest (+Width) then Guest_Lex; only then drop
   menu-free AdamLite fallback. `CMenu`/`CAlloc` remains later. Star-lit/`*p` Soft Call ungated.
2. Finish G9 residual: RedSea probe `A:/Kernel/Kernel.BIN` FileFind+Load+`KernelEntry`
   handoff **landed** (host `pack_tosb` seed; Runtime prefers seed; `make kernel-thin-loader-smoke`
   proves mount→Load→Call without Cmp); **reloc heap Load** of virtio RedSea `Compiler.BIN`
   landed; default ELF `.compiler_bin` **dropped**. Next: grow `Kernel.BIN` into real
   `Kernel_RV` (traps/heap/UART/RedSea/`Load`) so thin loader can jump and not return —
   then retire Mac `phase3.elf` Cmp/StartOS scaffold + guest Cmp of Compiler.
3. Only then attempt guest Cmp of DolDoc subset / real `MakeAdam_RV` — do **not** claim
   P6 until on-target Load runs DocTerm+WinMgr without Mac AOT of `win_*.elf` as DoD.

