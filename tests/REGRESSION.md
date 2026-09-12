# REPL / OS honesty & regression

User-facing REPL guide: [docs/REPL.md](../docs/REPL.md). Test layout: [README.md](README.md).

## How to run

```bash
make repl-holyc-regression   # primary HolyC honesty gate (CI; A3 Done)
make a3-flip-check           # G7 readiness: holyc-smoke+regression+repl-cmp → READY/NOT READY
make ci                      # compliance + fmt-test + qemu-integration (HolyC-only honesty)
# make repl-regression / repl-smoke are RETIRED: the legacy C guest is deleted and
# both targets now print an error pointing at the repl-holyc-* equivalents.
```

`tests/scripts/run_repl_holyc_regression.sh` greps the HolyC thin-image QEMU log for
**G6 covered** needles: Dir/Src-quit/DumpFile/Run/Man/Tab/HIST/G1 soft dbg/Sys/journal/Atoi/JIT
+ G2 trap/Ctrl-C + G3 `gd`/`K` + **livedrv Done** (Home Ed+Run `6a` ToUpper; `livedrv `/`LIVEDRV `).
Man needle uses `Man("Regs")` (not `Man("Reg")`). Bt honesty = **`Bt (trap freeze)`** after Fault
(trap lane; live `Bt;` without freeze is UART stub). **Explicitly waived:** Fmt host rewrite
(`fmt-test`/`fmt-check`), Demo/*.HC UART batch (`make compliance` curated six), ZMODEM
(DumpFile+9P). **A3 Done** — `repl-holyc-regression` is now the only REPL honesty gate;
the legacy C guest and its `repl.elf` were deleted in `080f729`, so `repl-regression` and
`tests/scripts/run_repl_regression.sh` only print an error. `zmodem-smoke` is local-only and
currently **red** (it still builds the deleted `repl.elf` — [CI.md](../docs/CI.md) WIP row).
Failures print the missing needle and a log tail.

Kernel FB/Gr/Win/plat smokes are separate (`make kernel-fb-smoke` etc.) and are listed under P3 — do not treat them as proof that the REPL Src loop works.

## Failure that created this gate

HolyC migration replaced C `Src` with `bootstrap/seed/sym.hc` `Src` that only `FileWrite`d `Name.hc` and returned. QEMU showed:

```
> Src("Dir");
Src: wrote Dir.hc
```

No editor, no `Run`, `:q` fell through to the REPL as a parse error. `run_repl_smoke.sh` still passed because it checked `SrcFile` / `Man` / jump-to-def, **never** `Src("…")` + editor quit.

While fixing Src, regression also caught a second P0: HolyC `FsCreate`/`FileWrite` used `FsName(i)[j]=…` / `FsData(i)[k]=…` where the JIT treated the function-returned pointer as an **I64 stride**, truncating new filenames to one character (`.funlist` → invisible, `vf.hc` → missing). `.hc` saves sometimes “worked” only because `FmtSave` → C `HcFmtFile` rewrote the file. Fixed with pointer-bump byte copies in `fs.hc`.

## Claimed vs real (inventory)

| Claim | Reality | Priority |
|-------|---------|----------|
| Mac-built HolyC AOT REPL ELF | `make hc-repl` → bridge only; **do not grow `jit.hc`**. Destination: `Compiler/Compiler_RV.PRJ` + ExePutS (see `templeos-riscv/COMPILER_RV.md`) | **bridge** |
| `Compiler/Compiler_RV.PRJ` | Lex/Prs/Opt012–6 + `Back*_RV` + `OptPass789A` (RV); host AOT 0 errors | **started** |
| `Src("Name")` opens editor + recompiles | Was stubbed; fixed to `HcCallEditor` + `Run` | **P0** fixed |
| Memfs `FileWrite` creates findable files | Was truncating names via U8* I64-stride stores; fixed pointer-bump copies | **P0** fixed |
| `CallerName` / `CallersGo` | Was `return 0`; now host-slot → C `CallerName` (callers_buf). Regression: `Caller0=A` | **P0** fixed |
| `MemMap` / `Regs` / `StkRep` | Were hollow HolyC labels; now host-slot → real C (live `code_mem`, GPR snap + `mstatus`, stack walk). Regression rejects stub text | **P0** fixed |
| Pure HolyC / no host slots / no EdC | Host slots at `0x87001xxx` remain for legacy `repl.elf` (see table below). `hc_repl` has none. `EdC`/`EditC` are repair hatches. Term geometry is HolyC-owned | **P2** — geometry **done**; rest still C |
| Full WinMgr / DolDoc / mouse | Text_base WinMgr + soft FB demos only; no real DolDoc/mouse | **P3** |
| Ethernet / I2C / SPI | Not implemented | **P3** |
| O1 mode 4 | Not done / not gated | **P3** |
| Graphics in REPL | REPL is UART; FB is separate kernel smokes | **P2** docs |
| “Green” agent smoke reports | `repl-smoke` missed Src; FnSize checks matched `=0`; uncommitted mega-WIP can look green locally while features are hollow | **P1** gate |

## Fix plan (prioritized)

1. **P0 — Src + FileWrite + regression gate**: restore `Src`/`SrcFile`/`SrcText`; fix memfs byte copies; ship `make repl-regression` that fails if Src is stubbed or new files are unfindable.
2. **P0 — CallerName / MemMap / Regs / StkRep**: re-expose working C via host slots (honest once-indirect; not fake HolyC). Regression needles for `Caller0=`, `code_mem` live usage, `mstatus`, `stack:`.
3. **P1 — repl-smoke always meaningful**: keep language demos; `qemu-integration` now runs `repl-regression` after `repl-smoke`. Tighten smoke greps that still match `FnSize Print=0`.
4. **P2 — honesty pass**: docs/AGENTS links / PLATFORM / seed comments must say host slots remain, WinMgr is text_base, EdC is repair-only, graphics ≠ REPL.
5. **P3 — deferred features**: full DolDoc/mouse, net/I2C/SPI, O1 mode 4, richer FunPick automation; slice uncommitted mega-WIP into reviewable PRs instead of one false-green blob.

## Still hollow / dishonest (not P0 API shadows)

| Symbol / surface | Claimed | Actual | Severity |
|------------------|---------|--------|----------|
| `holy_rt.h` x86 leftovers (`InU8`/`OutU8`/`GetRAX`/`CPUId`/`FarCall32`/…) | Portability shims for AOT/exec harness | Not RuntimeRegister'd in REPL; `Man("GetRAX")` → no such symbol (rt.hc/c_api Man scrubbed) | **done** |
| `Ed` / `Edit` HolyC | Editable HolyC editors | Entry once-indirects to C (`0xB8`/`0xE0`) so smoke pipes work; `EdHoly`/`EditHoly` editable; `EdC`/`EditC` same slots as repair hatches | **P2** architecture (working, not fake) |
| Host slots generally | “Pure HolyC” | Compiler/UART/srcmap/Callers/MemMap/… still C behind slots on `repl.elf`; memfs arena is HolyC-owned (`0x87800000`) with deprecated C bridges | **P2** docs |
| WinMgr / DolDoc / net | Full TempleOS | Text_base + soft FB demos only | **P3** |

## C bootstrap / host-slot inventory (brutally honest)

| Dependency | Used by | Status |
|------------|---------|--------|
| `TermRows`/`TermCols`/`TermFlags`/`TermSetSize`/`TermProbe` | `term.hc`, Vi, EditHoly, FunPick | **Fixed** — HolyC `g_term_*`; Probe one-byte + RX own (no `TermPoll` prefetch); optional push to C `TermSetSize` for EdC/EditC. C `TermProbe` (EditC) also one-byte — bulk poll starved HolyC Vi after Edit |
| `TermKeyGet` | Vi / EditHoly / FunPick | **Fixed** — default interactive path is HolyC CSI + `g_term_rx_own` (one UART byte/iter, not slot `0xD0`). `TermKeyGetC`/`HcTermKeyGet` repair-only; EdC/EditC/C readline still call C `TermKeyGet` directly |
| UART ring/drain/get slots | `uart.hc`, HolyC TermKeyGet/Probe | **bridge** — ring still published by C; HolyC pops via published ptrs only while `g_term_rx_own` (no steal from C readline) |
| memfs base/cwd slots | `fs.hc` | **Fixed** — HolyC arena at `0x87800000` (+ cwd after slots; fits default 128MiB virt RAM); File*/Dir/Cd/Cat use fixed arena; C no longer publishes `0x87001010`/`0x18` |
| compile/run + `g_run_file` | `run.hc` | **ExePutS path green** — guest `Compiler_RV` + `ExePutS("40+2;")` → 42 (`make kernel-exepubs-smoke`). Host AOT forward-import bug for `OptPass4` fixed via `RewriteForwardImportCalls` (TempleOS name restored). `Run`/`Exec`: ExePutS when host slot unset; REPL keeps `0x87001000` until Compiler_RV is linked there. Do **not** grow `jit.hc`. |
| FmtSrc / FmtFile / fmt buf | `fmt.hc` | **intentional bridge** — host `HolyFmtSrc` (AST/CST `host/holyc_fmt.c`); same as `holyc-riscv --fmt` / `make fmt-test` |
| Ed/Edit/EdC/EditC slots | `ed.hc`/`edit.hc` | **intentional bridge** (repair) + smoke pipe; bodies are HolyC |
| call_editor / hash / srcmap | `sym.hc` Src | **intentional bridge** until guest compiler owns hash |
| CallersScan/Name/Cnt, MemMap, Regs, StkRep | `sym.hc` | **intentional bridge** (honest C; was hollow HolyC) |
| trap name/disp/vec/reentry + `0x87000100` snap | `trap.hc`/`debug.hc`/`start.hc` | **intentional bridge** (C trampoline publishes GPRs) |
| `RuntimeRegister` as OS API | — | **done** — REPL registers **zero** C builtins into HTT_FUN |
| `holy_rt` linked into guest | exec harness only | **build-only OK** for AOT/oracle; the C REPL that also linked it is deleted |
| `worry_dream_repl.c` / `0x87001xxx` | — | **deleted** (`080f729`). A few seed files still poke `0x87001xxx` literally (e.g. `seed/ed.hc`); `bootstrap/Makefile.repl` survives only to generate `boot_blob_embed.h` (its `seed_files.h` / `asm_templates.inc` outputs have no consumer left) |
| REPL multiline `...` Tab | Same as Ed/Vi | **fixed** — C readline used `rl_do_complete` only (empty token listed all syms); now `rl_smart_tab` (2sp indent + mid-token complete). Regression: `MLTAB_MARK` |
| Mac-AOT `hc_repl` | `bootstrap/hc_repl` | **assert no host slots / no `worry_dream`+`holy_rt`+`RuntimeRegister` symbols** — `run_hc_repl_smoke.sh` greps the ELF as a negative assertion; keep the grep even though the C guest is gone |

Do **not** paper over with checks that pass when the feature is a no-op (label-only greps, `SrcFile` without `Src`, FnSize without `>0`, editor paint text without `FileLen`/`Run`).
