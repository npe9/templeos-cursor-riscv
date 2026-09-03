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
| **G5** Tab/complete/history | Smart Tab + multiline `...` + Up/Down multi-entry ring + hist_seed (`HIST_RECALL_OK` / `HIST_UP2_OK` / `HIST_SEED_OK`) on `repl-holyc`. Remaining vs legacy: live define_table, multiline unit recall; mid-line cursor with TTY lane |
| HW debugger twin (virt) | Guest `hwdbg.hc` Sdtrig probe + `make hwdbg-smoke` gdbstub; OpenOCD still board path |
| Dual-run A3 wiring | HolyC + legacy both required in `qemu-integration` |
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
`asm_doc.hc` / `complete.hc` / `readline.hc`. Smart Tab: mid-token → CompTab
(JIT Fun* + MEM_* CompAdd list + memfs + asm{} ops/regs/CSRs); else 2sp indent.
Multiline `...` prompt. History Up/Down: multi-entry ring `RL_HIST_MAX=16` ×
`RL_HIST_CAP=256` (`RlHistPush` / `RlHistGet` + `RlReadKey` CSI via soft
`TtyInCh`/`HcUartGet` — not `TermKeyGet`). Boot `RlHistSeed` demos (Dir/Regs/
MemMap/Man/Help + `HIST_SEED_OK`). Needles `HIST_SEED_OK` + `HIST_RECALL_OK`
(Up×1) + `HIST_UP2_OK` (Up×2). Remaining vs legacy: multiline unit recall, live
define_table; mid-line cursor owned with TTY (`g_rl_cur` / arrows).

---

## Prioritized gap list

Effort: **S** ≤1–2 days · **M** ~3–7 days · **L** multi-week / multi-agent.
Depends-on = DAG edges (do upstream first). Lane = file ownership for parallel agents.

| ID | Name | Why (DoD) | Depends | Effort | Lane (paths) |
|----|------|-----------|---------|--------|--------------|
| **G1** | HolyC Regs / MemMap / StkRep / Callers | **Done** — soft path green on smoke + holyc-regression | — | M | **dbg** — Watch/Step soft remain `hwdbg.hc`; G17 `dbg-smoke` CI optional |
| **G2** | HolyC trapvec + Ctrl-C Break | **Done** on `repl-holyc` (`trap-smoke` + regression) | G1 helpful | M | **trap** — `seed/trap.hc`; asm secondary `::` labels + asm setjmp @ `REPL_JB_FIXED` |
| **G3** | HolyC Vi / Ed / Src→editor | **Partial:** `Ed`/`Vi`/`Src`→Vi on `repl-holyc` (soft RX; Ed→EdHoly); `gd`/`K` covered; **livedrv Done** (`PutS` Home Ed+Run substitute — not char-walk JIT) | — | L | **ide** — `seed/{ed,edit,vim}.hc`, `hc_repl/{ide_bridge,ide_src,dir,uart}.hc`; [IDE.md](IDE.md) |
| **G4** | HolyC Man / Funs / SymFile embed | **Partial** — Man/Funs needles green; FunPick/hash residual | — | M | **man** — `seed/{man,man_topics,funs}.hc` + `hc_repl/man_sym.hc` |
| **G5** | HolyC multiline Tab / complete | **Partial** — Tab/indent/asm + ring Up/Down + hist_seed (`HIST_SEED_OK`); live defines / multiline-unit residual | G3 or shared readline | M | **rl** — `seed/{complete,asm_complete,asm_doc,readline}.hc` |
| **G6** | Expand `repl-holyc-regression` → flip needles | **Done** — cover G1–G5+G2 trap+livedrv+Sys/journal/Man/Tab/HIST/language; **Fmt+Demo+G11 ZMODEM waived** | G1–G5 | M | **ci** — `tests/scripts/*holyc*`, [REGRESSION.md](../tests/REGRESSION.md); Makefile only |
| **G7** | **A3 flip** + delete `worry_dream` | Zero guest C honesty path; drop dual-run | G6 + criteria 1–4 | S | **ci** — scaffolding: `make a3-flip-check` + [A3_FLIP_DRAFT.md](A3_FLIP_DRAFT.md) (**do not apply CI yet**); G2 session + livedrv PutS Done; **Fmt+Demo+ZMODEM waived** |
| **G8** | **B0** guest Cmp → loadable BIN | Remote rebuild starts; self-host DoD Track B | A2 done | L | **cmp** — `Compiler/**/*RV*`, phase3 / ExePutS UART proof; [COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md) |
| **G9** | **A5** thin HolyC phase3 + RedSea BINs | Boot ≠ “host AOT’d demo ELF” alone | G8 partial OK | L | **phase3** — `Adam/`, `Kernel/RVPhase3.HC`, RedSea Load path |
| **G10** | **A4** retire `templeos-riscv/kernel/*.c` from CI | Honest product images; drop `templeos-smoke` dependency | G9 or HolyC plat ORACLE | M | **c-kernel** — `templeos-riscv/kernel/`, Makefile `templeos-smoke` |
| **G11** | ZMODEM on `repl-holyc` | **Waived** — not A3/G7 | — | S | **export** — embed refused (~28 KiB `zmodem.hc`+`trzsz.hc`, JIT risk); product = DumpFile/DumpChanges + virtio-9p; legacy smokes until A3 delete |
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

**Critical path to A3 flip / delete `worry_dream`:**

```text
G1 ─┐
G2 ─┼─► G6 (regression cover/waive) ─► G7 (flip CI + delete worry_dream)
G3 ─┤
G4 ─┤
G5 ─┘
         then G8 → G9 → G10 → G18  (remote self-host)
```

---

## Wave schedule (max 3–4 lanes)

### Wave 1 — immediate parallel (A3 unblock)

| Lane | Owner focus | Paths (do not collide) | Exit |
|------|-------------|------------------------|------|
| **dbg** | G1 HolyC Regs/StkRep/Callers/MemMap | `bootstrap/seed/debug.hc`, `csr.hc`, `sym.hc`; `hc_repl/repl.hc` `#include` + JitAdd | **Done** — needles in holyc-smoke + holyc-regression |
| **trap** | G2 trap + Break | `bootstrap/seed/trap.hc`, `hc_repl/start.hc` / UART; no C guest growth | **Done** — Fault dump + Ctrl-C on HolyC path |
| **ide** | G3 editor surface | `bootstrap/seed` editor seeds; `hc_repl/{dir,ide_*,uart}.hc` | **Partial** — Src→Vi; Ed→EdHoly; `gd`/`K` covered; **livedrv Done** (`PutS` rewrite) |
| **man** | G4 Man/Funs embed | `bootstrap/seed/man*.hc`, `funs.hc`; `hc_repl/man_sym.hc` + `repl.hc` `#include` | `Man("Print")` / `Man("CLINT")` / `FunsList;` on `repl-holyc` — **partial** (interactive FunPick still legacy; hash/srcmap via dbg) |

Coord rule: **do not grow `jit.hc`**; prefer seed AOT + `repl-cmp` for Cmp-heavy work.
`Makefile` / regression scripts owned by Wave 2 **ci** lane — Wave 1 only add `#include`s.

### Wave 2 — close A3 + export polish

| Lane | Focus | Paths | Exit |
|------|-------|-------|------|
| **rl** | G5 Tab/complete | `seed/complete.hc`, HolyC readline | **partial** — Tab + 16-slot ring + hist_seed on `repl-holyc`; multiline unit recall / live defines remain; mid-line with TTY |
| **ci** | G6 + G7 | `Makefile`, `tests/scripts/`, SELF_HOST, A3_FLIP_DRAFT | **G6 done**; **G7 scaffolding** (`a3-flip-check`) — G2 session + livedrv PutS Done, Fmt+Demo+ZMODEM waived; draft notes only — do not flip CI |
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
| `repl-holyc-smoke` / `repl-holyc-regression` | A3 product honesty — **expand** (G6) |
| `a3-flip-check` | G7 readiness scaffolding — READY/NOT READY; **does not** flip CI |
| `repl-cmp-smoke` / `kernel-repl-exepubs-smoke` | A2 **done**; Cmp home for G8 |
| `bootloader-smoke` | A3 criterion — keep green |
| `repl-smoke` / `repl-regression` | Legacy — **delete after G7** |
| `dbg-smoke` | Soft dbg — not in `qemu-integration` yet (G17) |
| `hwdbg-smoke` | Host gdbstub + guest `HwTrigProbe` — local/CI-optional; needs `riscv64-*-gdb` |
| `dump-changes-smoke` / `zmodem-smoke` / `trzsz-smoke` | Export — DumpChanges on product; ZMODEM/trzsz legacy-only (**G11 waived**) |
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
| **G25** | VT mux (2+ consoles over UART) | tmux-like attach | G22 | M | **Partial** — `Vt`/`VtAttach`/`VtDetach`/`VtCapture`/`VtKeys`(Ctrl-A); framed `V\tN`; host `--vt-follow`; **no panes** |
| **G26** | XON/XOFF (or RTS/CTS) flow control | Panic/bulk Dump/9P | — / G22 | S | **SW XON/XOFF done** (`UartXonXoff`, `repl-uart-xon-pty`); **RTS/CTS soft stub** (`UartRtsCts` / `RVUartRtsCts`) — **no-op on virt** (real pin wiring TBD) |
| **G27** | /proc-ish inspection remainder | `ps` / mounts UART UI | — | S | **Core done** — `bootstrap/seed/sys.hc` (`Sys`/`Uptime`/`MemRep`/`IrqRep`/`DevRep`/`Cnts`). **Remaining:** task table, mounts |

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
- WinMgr / DolDoc as A3 blockers
- Full POSIX job control / pipelines as console DoD (REPL-as-shell is enough)
