# Guest self-host (remote recompile)

**Point of this port:** the **entire guest system** — REPL, Kernel, `Compiler_RV`, Adam —
is **self-hosting** and can be **recompiled on target** (QEMU / FPGA / board) without
needing the Mac host compiler for day-to-day rebuilds.

This is **not** a project to purge C from the universe, replace Xcode/Homebrew, or make
HolyC emit Mac/Linux natives.

## Definition of done

| Layer | Done when |
|-------|-----------|
| **Guest / product images** | Zero C *source* and zero C *objects* in REPL, bootloader, Kernel plat, and phase3 boot path. HolyC (+ `asm{}`) only. |
| **Remote rebuild** | On target: guest `Compiler_RV` + `ExePutS` / `Cmp` + RedSea/`Load` rebuild Kernel / Compiler / Adam BINs without invoking Mac `holyc-riscv`. |
| **Host / Mac workstation** | **Stays.** `host/*.c` → `./holyc-riscv` is the legitimate bootstrap AOT. Python, Make, ld scripts, Homebrew toolchains stay. **Do not delete `host/`.** |
| **CI harness** | Prefer HolyC product images; thin asm `crt0` / `oracle_out.c` OK as test glue until rewritten. |
| **Out of scope** | Vendored `scripts/kconfig/*.c`, `bootstrap/archive/`, `tools/legacy/`, rewriting the Mac OS. |

**One paragraph:** Mac `holyc-riscv` (C) bootstraps the first guest images; after that, the
guest recompiles itself on the board. Legacy C guest (`worry_dream_repl.c`) is deprecated
because a C runtime **blocks** that self-host story — not because host C is evil.

Related: [ARCHITECTURE.md](ARCHITECTURE.md), [COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md),
[BAREMETAL.md](BAREMETAL.md), [bootstrap/README.md](../bootstrap/README.md).

---

## Track A — Zero guest C

Goal: product images and CI honesty path do not depend on a C guest runtime, so remote
recompile is not blocked on `worry_dream` / host slots.

| Phase | Goal | Acceptance |
|-------|------|------------|
| **A0** | Bootloader + REPL payload HolyC-only; no new C guest | `make bootloader-smoke`, `make repl-holyc-smoke` green |
| **A1** | UART / RX ring / hash / srcmap / editor live in `seed/*.hc` on HolyC path | No `HostSlotsInstall` mass on `repl-holyc` |
| **A2** | Guest `ExePutS` / `Cmp` owns the REPL compile loop | **Done** — see A2 status below |
| **A3** | CI flip: honesty gates use `repl-holyc` / `bootloader-repl` | **In progress** — expanded HolyC regression; legacy still required (blockers) |
| **A4** | Retire `templeos-riscv/kernel/*.c` from default CI | `templeos-smoke` → HolyC plat / phase3 (or drop) |
| **A5** | Phase3 boot = thin HolyC loader + RedSea guest BINs | Success ≠ “host AOT’d the demo ELF” alone |
| **A6** | Optional: harness without `oracle_out.c` | Kernel smokes link HolyC/`asm{}` `_start` |

**Non-goal:** deleting `host/*.c`.

### Flip criteria (A3)

Keep **dual-run** (legacy + HolyC) as **required** CI until **all** of:

1. `make repl-holyc-smoke` green (language + Dir/Src subset).
2. `make bootloader-smoke` green (product split-boot path).
3. `make repl-holyc-regression` covers honesty needles that matter on the HolyC path —
   expand toward full `repl-regression`. Guest Cmp compile is gated by
   `make repl-cmp-smoke` (A2). **G6 cover (thin image):** memfs/Dir/MkDir, Src→Vi quit
   (reject stub), DumpFile/DumpChanges/FsLog/Checkpoint, Run+FileWrite, Man/Funs/SrcFile/
   FnSize, Tab/CompCollectSyms/asm{} body + history Up (`HIST_RECALL_OK`), G1 soft
   Regs/MemMap/StkRep/Callers (`post_regs_a7=5`), `Sys;` (/proc-ish), Atoi + JIT language,
   G3 `gd`/`K` (nested + same-file seek; Man-under-cursor).
   **G7 flip blockers:** none listed in `run_a3_flip_check.sh` after G2 trap/Ctrl-C
   green (`trap-smoke` + holyc-regression needles). **Fmt host rewrite: waived for A3** — Mac host stays; honesty = `make fmt-test` /
   `fmt-check` (`holyc-riscv --fmt`). Guest `Fmt()` needs host slots (thin forbids).
   **Demo/*.HC UART batch: waived for A3** — thin JIT / line-oriented `repl-cmp`
   cannot run TempleOS Demo constructs; substitute = curated six demos `pass_any` in
   `make compliance` (+ host AOT). Legacy `repl-smoke` keeps UART Demo until delete.
   **ZMODEM/trzsz on thin image: waived** (DumpFile + DumpChanges + virtio-9p; G11).
4. Docs + Makefile help call `worry_dream` / `repl.elf` **deprecated**.

**Then** drop `repl-smoke` / `repl-regression` from `qemu-integration` and delete
`bootstrap/worry_dream_repl.c` (+ `startup.s` / legacy `Makefile.repl` link path).
Draft only (do not apply yet): [A3_FLIP_DRAFT.md](A3_FLIP_DRAFT.md). Local readiness:
`make a3-flip-check`.

Until flip: `qemu-integration` runs **both** legacy and HolyC. Local-only opt-out:
`SKIP_REPL_LEGACY=1 make qemu-integration` (CI must **not** set this).

### G7 A3 flip checklist

| Item | Status | Gate / substitute |
|------|--------|-------------------|
| `repl-holyc-smoke` | Required | `make a3-flip-check` / qemu-integration |
| `repl-holyc-regression` (G6 cover) | Required | same |
| `repl-cmp-smoke` (A2) | **Done** | same / `kernel-repl-exepubs-smoke` |
| `bootloader-smoke` | Required (run before apply) | not inside `a3-flip-check` |
| **G2 trap / Ctrl-C** | **Done** | holyc-regression + `trap-smoke`; Fault→crash>→go, Break, SetTrap/Ecall, Ctrl-C |
| **G3 livedrv** | **Done** | Home/`livedrv.hc` Ed+Run → `livedrv `/`LIVEDRV ` via `PutS` rewrite (not char-walk JIT) |
| G3 `gd` / Vi `K` | Covered | nested + same-file gd; Man-under-cursor |
| Fmt host rewrite | **Waived** | `fmt-test` / `fmt-check` |
| Demo/*.HC UART batch | **Waived** | compliance curated six |
| ZMODEM / trzsz thin embed | **Waived** (G11) | DumpFile / DumpChanges + virtio-9p |
| Drop dual-run + delete `worry_dream` | **Not yet** | [A3_FLIP_DRAFT.md](A3_FLIP_DRAFT.md) after READY |

### A3 status (this pass)

| Piece | Status |
|-------|--------|
| `repl-cmp-smoke` in `qemu-integration` | **Done** — via `kernel-repl-exepubs-smoke` (alias) |
| Expand `repl-holyc-regression` (G6) | **Done** — G1–G5+Sys/journal+`gd`/`K`+livedrv+G2 trap covered; Fmt+Demo+ZMODEM waived |
| Legacy dual-run still **required** | **Yes** — until flip draft applied; G2 session + livedrv PutS Done; Fmt+Demo+ZMODEM waived |
| `make a3-flip-check` | **Wired** — scaffolding only; prints READY/NOT READY (does not flip CI) |
| `SKIP_REPL_LEGACY=1` local skip | **Wired** — deprecated path optional locally; CI keeps dual-run |
| Delete `worry_dream_repl.c` | **Not yet** — keep until blockers clear |

**As-of this wiring:** HolyC dual-run targets are green on virt with hierarchical memfs
(`/Home` `/Lib` `/Tutorials` …). **A2 Done** — `build/repl-cmp.elf` / `make repl-cmp-smoke`.
Thin `repl-holyc` keeps ExePutS→`JitTry` for memfs honesty (full Cmp ≈1.9 MB vs ≈288 KB
bridge). Do **not** grow `jit.hc` (capacity `JIT_FUN_MAX` bump only when Wave embeds saturate).

### Blockers before deleting `worry_dream`

| Needle class (legacy `repl-regression`) | Thin `repl-holyc` | G6 | Notes |
|----------------------------------------|-------------------|----|--------|
| Vi / Edit / Ed / Src→editor seek | **Partial** | **Cover** Src+`:q`, `gd`, Vi `K`; livedrv **done** | Ed→EdHoly (no host EdC); livedrv = Home file insert+Run (not uart — soft RX) |
| Man / SrcFile / FnSize / SymFile / Funs* | **Partial** | **Cover** Man/Sections/Funs*/SrcFileRep/FnSizeRep | FunPick + full hash/srcmap still legacy/dbg |
| Callers / CallerName | **Done soft** | **Cover** `Callers("CB")` / `callers of CB` | Soft HolyC path; `CallerName` index API still thinner than legacy |
| MemMap / Regs / StkRep / Reg / CSR live | **Done soft** | **Cover** MemMap + soft Regs + StkRep/Callers + `Bt (trap freeze)` after Fault | G1 soft green on smoke + holyc-regression |
| Trap / Ecall / SetTrap / Ctrl-C Break | **Done** | **Cover** | Needles in holyc-regression + `trap-smoke` (Fault→crash>→go; Break; Zap/Ecall; Ctrl-C) |
| Livedrv edit+Run (Home substitute) | **Done** | **Cover** | Home/`livedrv.hc` Ed+Run → `livedrv `/`LIVEDRV ` via `PutS` rewrite (`3d`/`2a`); do **not** Run `Lib/uart.hc` (clobbers soft RX). Thin JIT `*s++`/`s[i]` walk still faults on return — PutS is the product substitute. Legacy uart insert = `150a` |
| Fmt host rewrite confirmation | **Waived** | **Waive** | **Not a G7 blocker.** Host rewrite OK for A3 (Mac `host/` stays). Substitute: `make fmt-test` / `fmt-check` / `holyc-riscv --fmt` (same `HolyFmtSrc` engine). Guest `Fmt()` / format-on-save need `0x87001xxx` slots — forbidden on thin; intentional legacy bridge ([IDE.md](IDE.md) P2) |
| Multiline Tab / asm{} Tab / CompCollectSyms | **Partial** | **Cover** CompCollect*/Fun Tab/MEM_* Tab/multiline indent/asm{} + Up (`HIST_RECALL_OK`) | Multi-entry hist_seed, multiline unit recall, live define_table = legacy residual (not flip-blocking alone) |
| DumpFile / DumpChanges / FsLog | **Done** | **Cover** | UART export on thin; operate-through substitute for ZMODEM |
| Sys / Uptime / MemRep (/proc-ish) | **Done** | **Cover** | `Sys;` → `=== sys (UART /proc-ish) ===` (G27 core) |
| Demo/*.HC batch + boot banner | **Waived** | **Waive** | **Not a G7 blocker.** Probe: thin JIT `FileWrite`+`Run` of `NullCase.HC` → `JIT: compile error` (`case:` / `start:`/`end:`); `repl-cmp` is line-at-a-time ExePutS (160 B) — not a Demo file runner. Substitute: curated six (`NullCase`/`Print`/`SubSwitch`/`RadixSort`/`Exceptions`/`GlblVars`) `pass_any` in `make compliance` + host AOT OK. UART Demo batch stays legacy `repl-smoke` until delete |
| ZMODEM / trzsz on thin image | **Waived** | **Waive** | **Not a G7 blocker.** Product path: `DumpFile` / `DumpChanges` / `FsChanges` + virtio-9p (`NineExport`). Embed refused: `zmodem.hc`+`trzsz.hc` ≈28 KiB / ~1.3k lines — thin-image + JIT risk ([CONSOLE.md](CONSOLE.md) demote; [GAPS.md](GAPS.md) **G11 waived**). Legacy `repl.elf` keeps `zmodem-smoke` / `trzsz-smoke` until A3 delete |

**G7 readiness:** Do **not** drop dual-run until every **G7 blocker** row above is green on HolyC/`repl-cmp` **or** explicitly waived with a product-path substitute — and criteria 1–4 hold. Check locally with `make a3-flip-check`. G6 expands cover; flip = apply [A3_FLIP_DRAFT.md](A3_FLIP_DRAFT.md) in a separate change (**not** yet). **Fmt, Demo, and G11 ZMODEM are waived** and do **not** hold the flip. **G2 trap/Ctrl-C and G3 livedrv (PutS) are Done** — `make repl-holyc-regression` green (livedrv/`LIVEDRV` + gd/K + trap session + `Man("Regs")` + `Bt (trap freeze)`).

### A2 status (ExePutS owns compile)

| Piece | Status |
|-------|--------|
| Product `repl-holyc` compile entry = `ExePutS` | **Done** — `exepubs.hc`; smoke needles `A2: ExePutS owns compile loop` |
| Host compile slot on product path | **Absent** (A1) — no `0x87001xxx` |
| `seed/run.hc` prefers ExePutS when `g_exepubs_prefer` | **Done** — flag ready; set after CInit when that seed co-resides with Compiler |
| Guest `Compiler_RV` ExePutS UART REPL loop | **Done** — `make repl-cmp-smoke` / `kernel-repl-exepubs-smoke` |
| Product compile image = Kernel+`Compiler_RV` | **Done** — `build/repl-cmp.elf`; needles `A2: Compiler_RV owns ExePutS`, `A2: Cmp compiled 40+2` (`probe ans=42`) |
| Embed full Cmp into thin `repl-holyc` | **Won’t** — size; converge on `repl-cmp` instead |
| Transitional Jit backend on `repl-holyc` | **Kept** — bridge for memfs/Dir until A3; do not grow `jit.hc` |
| Delete Jit / flip A3 | **Open** — A3 in progress (expanded HolyC regression; legacy still required) |

**Converge path (interactive guest Cmp):**

```bash
make repl-cmp          # builds build/repl-cmp.elf (also runs smoke)
qemu-system-riscv64 -M virt -m 128M -bios none -kernel build/repl-cmp.elf -nographic
# type HolyC; ExePutS returns expr values (e.g. 40+2 → 42). 'q' quits smoke demo.
make repl-cmp-smoke    # CI gate; Cmp-distinct needles
```

---

## Track B — Guest Cmp rebuilds the system on target

Goal: day-to-day system rebuilds happen **on the guest**, with Mac AOT only as bootstrap.

| Phase | What | Output / gate |
|-------|------|----------------|
| **B0** | Guest `Cmp` of `Compiler_RV` subset → loadable BIN | UART proof under phase3 / ExePutS |
| **B1** | Guest Cmp builds larger Compiler + Runtime modules | RedSea `Load` of guest-built BINs |
| **B2** | Under QEMU/board: guest Cmp recompiles Kernel / Compiler / Adam | Smoke-equivalent to host-AOT’d images |
| **B3** | Documented remote rebuild recipe (`MakeOS` / Cmp / Load) | CI or docs smoke that does **not** invoke Mac `holyc-riscv` for the rebuild step |

**Cancelled / footnote only:** “delete `host/*.c`” or freeze-binary removal of host C source.
Host C stays as the bootstrap workstation compiler forever (or until someone voluntarily
ports it — not a project goal).

---

## Inventory — remaining C

### Guest / product (Track A — eliminate)

| Path | ~Role | Status |
|------|-------|--------|
| `bootstrap/worry_dream_repl.c` | Legacy UART REPL + host slots | **Deprecated**; required CI dual-run until A3 flip (see blockers) |
| `bootstrap/startup.s` / `linker.ld` | Legacy `repl.elf` only | Retire with worry_dream |
| `bootstrap/holy_rt*.h` in guest | Import resolve / legacy link | Build-only OK for AOT; not OS API |
| `templeos-riscv/kernel/*.c` | C `tos-rv.elf` image | CI via `templeos-smoke`; retire in A4 |

### Host / Mac (keep)

| Path | Role |
|------|------|
| `host/*.c` | `./holyc-riscv` bootstrap AOT — **keep** |
| `tools/pack_tosb.c` | Host BIN packer — OK |
| Python / Make / ld / Kconfig | Meta-build — OK |

### CI harness (tolerated)

| Path | Role |
|------|------|
| `tests/exec/harness/oracle_out.c` + `crt0.S` | Smoke link glue — A6 optional |
| `templeos-riscv/scripts/kconfig/*.c` | menuconfig infra — out of scope |

### Not product

`bootstrap/archive/**`, `tools/legacy/**`, `tests/c/**`, `tests/scratch/**`.

---

## First PRs checklist

1. **PR1 — HolyC REPL CI path (this work)**  
   - [x] Document self-host DoD (`docs/SELF_HOST.md`)  
   - [x] Dual-run: `repl-holyc-smoke` + `bootloader-smoke` in `qemu-integration` alongside legacy  
   - [x] Demote `worry_dream` wording (Makefile help / bootstrap docs)  
   - [x] A2: guest Cmp owns compile (`repl-cmp-smoke`; Cmp-distinct needles)  
   - [x] Expand HolyC regression (thin-image honesty: memfs/language/Run/Src-dump; A3 in progress)  
   - [ ] Flip default honesty gate off legacy `repl.elf` (blockers: editors/Man/Regs/trap/…)  
   - [ ] Delete `worry_dream_repl.c` after flip

2. **PR2 — Retire C `templeos-riscv/kernel` from CI**  
   - [ ] Optional / documented exclude of `kernel/*.c` from default image  
   - [ ] Point smoke at HolyC plat / phase3  
   - [ ] Do **not** remove while `templeos-smoke` is the only ORACLE for that image

3. **PR3 — B0 Cmp spike**  
   - [ ] Guest Cmp of Compiler_RV subset → loadable BIN  
   - [ ] UART proof; document gap to full remote `MakeOS`

---

## Make targets (product vs legacy)

| Target | Guest | Notes |
|--------|-------|-------|
| `make repl-holyc` / `repl-holyc-smoke` | HolyC | Memfs/Dir honesty; ExePutS→Jit bridge |
| `make repl-cmp` / `repl-cmp-smoke` | HolyC | **A2 product compile:** Kernel+`Compiler_RV` ExePutS |
| `make bootloader-repl` / `bootloader-smoke` | HolyC | Split boot + payload |
| `make kernel-repl-exepubs-smoke` | HolyC | Alias of `repl-cmp-smoke` |
| `make repl-smoke` / `repl-regression` | **Legacy C** | Deprecated; **required** CI until A3 flip; local `SKIP_REPL_LEGACY=1` |
| `make a3-flip-check` | HolyC | G7 scaffolding — READY/NOT READY; does **not** flip CI |
| `make templeos-smoke` | C kernel image | Retire in A4 |
| `make kernel-phase3-smoke` / `kernel-plat-smoke` | HolyC | Self-host building blocks |

See [CI.md](CI.md) and [../tests/README.md](../tests/README.md).
