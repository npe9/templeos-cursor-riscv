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
| **Stock Adam parses against the RV kernel** | `Adam/MakeAdam_RV.PRJ` → **0 errors** (was 3). The whole stock tree — Gr, Snd, WinMgr, DolDoc, God, AutoComplete, Ctrls — type-resolves against `Kernel_RV.PRJ`. Last blocker was `#define CDC CRVDC` (`Kernel/RVGr.HC:24`) aliasing stock `CDC` to the thin RV DC, which has no `start`/`end` markers for `GrDC.HC`'s `DCSave`/`DCLoad` span; `CRVDC` now carries its own (zero-size, layout-identical). **Parse only** — the substrate under Adam is still 15 `KThin*Stubs`, so this is not a runtime claim. See `tests/scratch/cdc_member_notes.md` |
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
| **G9** | **A5** thin HolyC phase3 + RedSea BINs | Boot ≠ “host AOT’d demo ELF” alone | G8 partial OK | L | **phase3** — `Adam/`, `Kernel/RVPhase3.HC`, RedSea Load path. **Partial:** guest BINs + **reloc heap Load** of virtio RedSea `Compiler.BIN` (ELF `.compiler_bin` dropped by default) + **staged probe `Kernel.BIN`** FileFind+Load+`KernelEntry` handoff before Cmp + **`kernel-thin-loader-smoke`** (mount→Load→Call + SoftCall **ExeSoft**→`'KB'` + **MakeSoft** product `Tiny.BIN`→`MakeOSProbe=42`→`'KN'` + **SeedSoft**/**SvcSoft**/**KernSoft** + **StartSoft** Seed→Svc→Kern multi-BIN→`'KU'` + **AdamSoft** product `A:/Adam/StartOS.BIN`→`StartOSProbe=1`→`'KA'` + **DateSoft** KDate+RTC Now→`'KG'` + **QSortSoft** QSortI64→`'KO'` + **KeyDevSoft** PutKey/PutS+CtrlAlt→`'KW'` + **ExceptSoft** SysTry/throw/PutExcept→`'KZ'` + **MemSoft** HeapCtrl+MAlloc→`'KH'` + **StrUtilSoft** StrUtil/MStrUtil→`'SU'` + **FifoSoft** FifoU8/I64→`'SF'` + **QueVectSoft** QueVectU8→`'QV'` + **RandSoft** Seed+LCG→`'RN'` + **ScanFlagsSoft** LstMatch+ScanFlags+/-→`'SC'` + **CompressSoft** CompressBuf/ExpandBuf→`'CM'` + **KLoadSoft** LoadPass1 import+ABS→`'LD'` + **MakeMemSoft** MemPag FREE_PAG=0x100→`'MM'` + **PhysMemSoft** BlkPoolsInit+MemPageTable+Mem32Dev→`'PM'` + **LoadMainSoft** CODE_HEAP+MAIN+FileRead→`'LM'` + **Hash2Soft** free_pag_hash2 stock 55→`'H2'` + **DataHeapSoft** DATA_HEAP+ZEROED+ExtDft.Z→`'DH'` + **LoadAbsSoft** FileNameAbs+module_align→`'LA'` + **DirAbsSoft** DirNameAbs parents+Z+ExtDft→`'DN'` + **StartOSSoft** DirAbs+Adam+StartSoft→`'SO'` + **ExePutSSoft** CmpCtrl+ExePutS 40+2→`'EP'` + **CmpSoft** SoftCall CmpWrite SoftCmp.BIN→`'CC'` + **LexStmtSoft** LexStmt2Bin emit+Call→`'LB'` + **PrsOptSoft** Prs/Opt RPN fold+emit→`'PO'` + **ParenSoft** paren+IC emit beyond fold→`'PN'` + **IdentSoft** local/ident IC→`'ID'` + **AssignSoft** PrsStmt assign→`'AS'` + **FunDefSoft** fun-def/return/Call→`'FD'` + **FunBodySoft** multi-stmt/locals-in-fun/single-arg→`'FB'` + **FunCallSoft** multi-arg/call-Expr plant→`'FC'` + **AbiSoft** ABI/a0 frame runtime stores→`'AB'` + **CocSoft** COC multi-stmt ASSIGN emit→`'CO'` + **BrSoft** if/while BR→`'BR'` + **ElseSoft** if/else→`'EL'` + **ForSoft** for→`'FR'` + **CmpBrSoft** relational cmp-BR→`'CB'` (SoftCall-lite; no full Compiler.BIN); residual = phase3 ELF full guest Cmp (Compiler Load+ExePutS + MakeOS/Runtime Cmp) + host `pack_tosb` seeds (not bootable Kernel_RV); SoftCall seed ceiling ~432 KiB (442048; CmpBrSoft; ARC12/BlkDev/FB + full Compiler.BIN skip); SoftCall seed ceiling ~457 KiB (468000; SoftCall Load slices through ForSrcSoft SoftForSrc.BIN 2032 B→'FS' + **CallIcSoft** SoftCall-lite inter-fun CALL IC →'CL' + **GlblMemSoft** SoftCall-lite glbl memory →'GM'; ARC12/BlkDev/FB + full Compiler.BIN skip); SoftCall seed ceiling ~471 KiB (482448; **GuestCmpSoft** →'GC' — first **real guest Cmp**: `A:/Compiler/SoftGlbl.HC` read multi-blk off RedSea, Cmp'd in BIN and Called, gated by a printed sz+sum recomputed host-side plus a no-guest-ident-in-Kernel.BIN grep; **GuestLocalSoft** →'GL' — **frame locals in a glbl-fun body**, `I64 l;` → sp slot at 8,16 above the saved ra, proven off `A:/Compiler/SoftLocal.HC` with the same sz+sum+no-ident trio; **GuestFlowSoft** →'GF' — **if/while/for in that same merged body**, reusing the COC `IC_BR_ZERO`/`IC_JMP`/`IC_LABEL` machinery with `LABEL_MAX` 8 unmoved, proven off `A:/Compiler/SoftFlow.HC` with the same sz+sum+no-ident trio plus a `br=3 jb=2 jf=1` disassembly of the planted branch encodings; **GuestPtrSoft** →'GP' — **first non-`I64` typed values**: `U8 b[N];` byte storage whose name decays to an address (`IC_GLBL_ADDR`, no `ld`), a `U8 *p;` cursor, and byte-width `*p` / `*p = Expr` via new `IC_LOAD_U8`/`IC_STORE_U8` (`lbu`/`sb`), proven off `A:/Compiler/SoftPtr.HC` (`Lex.HC`-shaped `for (p = buf; *p; p = p + 1)` char walk) with the same sz+sum+no-ident trio plus a `lbu=2 sb=3 abs=16` disassembly and a 298→42 byte-width gate; `FUN_CODE` 512→1024, `PRS_IC_MAX` held at 32; **GuestArgSoft** →'GA' — **fun arguments and calls that pass them**: `I64 name(I64 a, I64 b)` plants each arg as a frame slot at `8(sp)`/`16(sp)` and the prologue spills **real a0/a1** into them, while a call site appends its arg Exprs to the caller's own IC so the lite RPN hands out a0 then a1 before a real `jal ra`; the leftmost-`IC_CALL` rule becomes exact (`sp != callee.nargs` → reject), so `G(1)+2` and `H(G(20),2)` are accepted and `2+G(1)` / `H(40,G(2))` are refused at compile time; proven off `A:/Compiler/SoftArg.HC` (`OptPass_RV`-shaped cost helper called `(2,1)` and `(8,0)`, so a fixed-arg or folded callee gives 30/38 not 34) with the same sz+sum+no-ident trio plus a `jal=3 pro=1 set=2` disassembly matched as **three-word sequences** (a lone `sd a0,8(sp)` is indistinguishable from a frame store), and Cmps verbatim `Compiler/Test_RV.HC AddNumbers` in-BIN; **no cap raised** — `ARG_MAX` stays 2, `FUN_CODE`/`PRS_IC_MAX`/`LOCAL_MAX` held, watermark `code=200/1024 ic=15/32 lb=1/8`); **GuestTypeSoft** →`'GT'` — **non-`I64` return and argument types plus arity 4**: `rtype`/`argt` on `CKernelFunSoft` carry a declared type per fun and per arg (`I64`/`U0`/`Bool`/`U32`/`U8 *`/`C8 *`), the epilogue narrows the return in `a0` (`Bool` → `sltu a0,x0,a0`, `U32` → `slli`+`srli` 32 zero-extend, `I64`/ptr → nothing) and the prologue narrows each incoming arg the same way after spilling it, `U0` funs get `IC_CALL_U0` so a call is a **statement** that leaves the RPN stack empty (bare `return;` accepted, a value-position `U0` call refused), `ARG_MAX` 2→**4** spills real **a0..a3** with `ABI_ARG_MAX` 2 pinning the legacy emitters, `LOCAL_MAX` 4→**8**, `FUN_MAX` 4→**8**; proven off `A:/Compiler/SoftType.HC` (`BackLib_RV`-shaped: a 4-arg `U0` banking `imm*8+rs1*4+rd*2+op` so **any a0..a3 permutation differs** — (1,2,3,4)=26 vs (4,3,2,1)=49 — a `Bool` returning `298-0` that must read **1** not 298/42, and a `U32` at `1024*1024*1024*k` where `k=4` must truncate to 0 and `k=2` must stay **positive**, i.e. `srli` not `srai`) with the same sz+sum+no-guest-ident trio plus **two** disassembly gates matched as **three-word sequences** via `KernelSoftScanSeq3Soft` (`bool=1 u32=1 nov=1` for return width, `arg4=1 set4=1 u32a=1` for a2/a3 spill + call-side setup + arg-side narrowing — a lone `sltu`/`slli` is indistinguishable from a `!=` tail or an abs-address materialize); `nargs == 0` paths stay byte-identical and the multi-blk RedSea FileFind/FileWrite MakeOS packing is unmoved; watermark `code=692/1024 ic=25/32 lb=2/8` and `lc=6/8 fun=7/8 glbl=4/4` (`FUN_CODE` and `GLBL_MAX` trimmed back to measured usage after the harvest run, `PRS_IC_MAX` held at 32); **negative controls both go red**: `srli`→`srai` in the U32 narrower (width-only, one funct7 bit) and a (1,2,3,4)→(4,3,2,1) permutation of the guest call's actuals; next tip = the wall is no longer types or arity but **structure** — the same function-granularity survey re-run with the tip's grammar takes non-`I64`-type-blocked 98%→**82%**, fun-args-blocked 71%→**28%** (arity 4 is the knee: 5 only buys 28%→27%) and call-args-blocked 77%→**61%**, yet **still exactly 1 of 227 `Compiler/*RV*.HC` functions compiles verbatim** (`Test_RV.HC AddNumbers`), because **90% call a callee the lite Prs has not planted** and 59% hit the `other` bucket (bitwise/`switch`/div/mid-body `return`/wide types) — so the honest next levers are multi-fun unit intake (planted-callee chains), braced multi-statement bodies (41%), local array / initialized decls (47%), then hex (28%)/`&&`-`||` (25%)/`->` (21%)/strings (13%), not the budget — 8/8/4096/64 caps boot green at 478832 B with `'EP'` held (bigger SoftCall heap alone ≠ Compiler.BIN Load; not ARC12 SoftCall; not TrapPlic) |
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
| `mux-smoke` | G22/G25 gate — demux transparency (byte parity with framing off), soft VT split, framed ch + panes |
| `kernel-vt-smoke` | G29 gate — asserts the presenter's bandwidth properties (idle present **0 B**, incremental < full paint) |
| `kernel-phase3-smoke` | Self-host building block — deepen in G9 |
| `templeos-smoke` | C image — retire in G10 |
| `known-good-pin` / `check` | Ops — done (local) |

---

## Console stack (post-A3 / parallel wishlist)

Full matrix: [CONSOLE.md](CONSOLE.md). Not A3 blockers unless noted (G1/G2/G5 already
are). Top **missing** items to schedule after Wave 1–2:

| ID | Name | Why | Depends | Effort | Notes |
|----|------|-----|---------|--------|-------|
| **G22** | Framed multi-channel UART | Binary-safe ch0..ch4; unlocks dbg/log/FS without eating TTY | G2/G5 helpful | M | **Core done** — `frame.hc` + `tools/uart_mux.py`, gated by **`mux-smoke`**. `UartMuxOn` was compiled into the image but never `JitAdd`'d, so it read as `unknown fun` — now published (`repl.hc`). Off by default; `UartMuxOn();` at the prompt. ch0 (console + VT/pane) and **ch3 log** proven and gated; **ch1 FS / ch2 dbg still unexercised**. ch3 was dead because `frame.hc` "redefined" `log.hc`'s `LogMuxEmit` — impossible in one AOT translation unit — now dispatched via `g_log_mux_hook`. `Run("Lib/frame.hc")` is not an alternative — `Run` does not register functions at all. See `tests/scratch/uart_mux_dataloss_note.md` |
| **G23** | Guest GDB RSP on UART (dbg ch) | Board dbg without JTAG/qemu-gdbstub | G22 for ch2 | L | **Partial** — `gdbstub.hc` + `gdb-uart-smoke`: `?`/`g`/`G`/`m`/`M`/`Z0`/`z0`/soft-`s`/`c`→S05/`D` (inline snap; soft Bp table). Remaining: live resume while attached, ch2 round-trip |
| **G24** | dmesg ring → log channel | Severity + panic ≠ stdout | G22 for ch3 | S | **Partial** — ring done; `LogMuxEmit` stub in `log.hc`, **redefined** in `frame.hc` → ch3 when `UartMuxOn` |
| **G25** | VT mux (2+ consoles over UART) | tmux-like attach | G22 | M | **Partial** — `Vt`/`VtAttach`/`VtDetach`/`VtCapture`/`VtKeys`(Ctrl-A); `VtPane(a,b)` + framed `P\ta\tb`; host `--vt-follow`/`--vt-split`/`--vt-panes`; **no guest ANSI TTY split**. Host demux carried two silent data-loss bugs until `mux-smoke`: a literal `~` in the boot banner was read as frame SYNC and truncated every session (3352B → 1910B), and soft VT banners were scanned a byte at a time against a multi-byte regex so `--vt-split` never split. Both fixed |
| **G26** | XON/XOFF (or RTS/CTS) flow control | Panic/bulk Dump/9P | — / G22 | S | **SW XON/XOFF done** (`UartXonXoff`, `repl-uart-xon-pty`); **RTS/CTS soft stub** (`UartRtsCts` / `RVUartRtsCts`) — **no-op on virt** (real pin wiring TBD) |
| **G27** | /proc-ish inspection remainder | `ps` / mounts UART UI | — | S | **Core done** — `bootstrap/seed/sys.hc` (`Sys`/`Uptime`/`MemRep`/`IrqRep`/`DevRep`/`Cnts`). **Remaining:** task table, mounts |
| **G28** | Path/`::` vs UART/host Unix dual-namespace | One TempleOS grammar for Cd/FilesFind/`#include`/`__DIR__` | — | M | **Done** — [PATHS.md](PATHS.md): host `__DIR__`→`::/…` (tos→ISO); soft Cd `!cur_dv`; soft `DirCur`/`DirNameAbs`/`Pwd`→`::/…` + `RVSoftLetPlant`→`Let2Drv('A')` without virtio (`kernel-home-smoke`); UART `FsResolve` `::`/`A:`/`~`, `Pwd`+`Cd` log→`::/`, seed `soft_let.hc`→`Let2Drv` (`hc-repl-smoke`); `RVSoftLet9pPlant('P')` / `Virtio9pConnect`→`Drv('P')` + stock `Cd("P:/…")` / DirContext + `FileRead("P:/…")` + `FilesFind("P:/*")` + nested (`kernel-home-smoke`, `kernel-virtio-9p-smoke`) |

| **G29** | DolDoc → ANSI terminal presenter | Read a DolDoc on a VT100 / over ssh with no FB | G2 | M | **Core done** — `Kernel/RVDocVT.HC` presents the WinMgr 80×25 cell grid as ANSI, diffed against a shadow so an idle present costs **0 bytes**; `kernel-vt-smoke` green (`first=2373 idle=0 after=41`). Test-case-included, **not** in `Kernel_RV.PRJ` (32 KiB shadow grid). **Remaining:** 80×24 vs the 48-row Adam layout, Tab-to-link nav, `DOCT_SPRITE` placeholders, terminal capability probing. See [DOLDOC_VT.md](DOLDOC_VT.md) |

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
  `Adam/DolDoc/MakeDoc_RV.HC` shim → `DocInit_RV` + `DocPlain_RV` + `RVDocDemoProbe`. **Landed
  (2026-09-04):** `Adam/DolDoc/DocInit_RV.HC` stock DefineLstLoad +
  `doldoc.hash` HashDefineLstAdd (hand-planted dft flags; no CmpCtrl). DemoInPage
  smoke prints `lex=` HashFind hits. **Landed (2026-09-05):** stock
  `PrsDocFlagSingle` HashFind for `TX+CX` → `DOCEF_CENTER_X` (`flag=` smoke;
  body in `RVDoc.HC` — DocPlain_RV forward GOT was null). Soft Call tip
  `+docflag`/`+docflagcmp` green. **Landed (2026-09-05):** stock-shaped arg/tag
  `T=`/`HTML=` via `RVDocPrsArgOnce` (DHT_DOC_FLAG HashFind + quote; Soft Call
  `+docarg`). **Landed (2026-09-05):** `LE=`/`LM=`/`A=`/`BI=` via same HashFind
  `RVDocPrsArgFind`). **Landed (2026-09-05):** DocInit CmpCtrl seed Soft Call —
  `RVDocInitSeedApply` walks stock seed string (`TX+T;DA+…;HC+T`) via
  DHT_DOC_CMD HashFind + `RVDocPrsFlagsCmp` (no CmpCtrl Lex); Soft tip
  `+docinitseed` proves SeedApply ≡ `DocInit_RV` hand plant. Hyp1: calling
  SeedApply from DocInit_RV via `extern` → win split-AOT GOT null (mcause=5);
  hand plant stays SoT. **Landed (2026-09-05):** Soft `+docflaglex` — stock
  `PrsDocFlags`/`PrsDocFlagSingle` via planted abs-addr `CmpCtrlNew`/`Lex`/
  `CmpCtrlDel` (prefer `RVCmpCtrlAddrsGet`) + DHT_DOC_FLAG HashFind for
  `+CX`/`+CX+UL` (body in `RVDoc.HC`; not DocPlain GOT / Kernel `&CmpCtrlNew`).
  **Landed (2026-09-05):** Soft `+doccmdlex` — one-cmd stock `PrsDollarCmd` shape
  via same abs-addr CmpCtrl Lex: IDENT → DHT_DOC_CMD, PrsDocFlags, TK_STR tag
  for `TX+CX,"hi"`. **Landed (2026-09-05):** Soft `+docarglex` — one
  `LexExpressionI64` arg via `RVCmpCtrlAddrsGet`[2] abs fp: `BT,LE=1` /
  `DA,LEN=8` (literal fast-path; Soft tip early before Guest_Lex hang). **Landed
  (2026-09-05):** Soft `+docextstr` — `LexExtStr` T=/LM= via
  `RVCmpCtrlAddrsGet`[4]: `TX,T="hi"` / `MA,LM="Cd;"` (early Soft Call; keeps
  `+docarglex+doccmdlex`). **Landed (2026-09-05):** Soft `+docmultilex` — multi-arg
  stock `PrsDollarCmd` via abs-addr CmpCtrl: `TX+CX,T="hi"` +
  `LK,"hi",A=/HTML=/BI=` (LexExtStr+LexExpressionI64; early Soft Call; keeps
  `+docextstr+docarglex+doccmdlex`).   **Landed (2026-09-06):** Soft `+docplaininc` / `+makedocinc` / `+docinitinc`
  — guest Cmp `#include` DocPlain/MakeDoc/DocInit (`import` DocPlain seed; RedSea
  `Compiler/`) Soft Cmp OK; late Soft Call SelfTest→local→IMPORT OK (DocPlain /
  MakeDoc nest → Kernel `RVDocPrsFlagsProbe`; DocInit import-free probe=1). Early
  Soft Call still deferred (Load before Menu ReadIdent Soft Cmp was fragile).
  **Landed (2026-09-06):** Soft `+docinitu0` — guest DocInit_RV seed comment-free
  empty `U0 DocInit` + `DocInitRVProbe` Soft Cmp+Call OK (prior hang was comments
  with `DocInit;`).   **Landed (2026-09-06):** Soft `+docinitbody` — guest DocInit with
  local `#define DOCT_*/DOCEF_*` + Soft `CDocInitSoftGlbls` + `for (i) member[i]&=`
  Soft Cmp+Call OK. Root of prior `Invalid lval`: Soft Cmp has no KernelA
  `#define`s (`DOCT_*` like TRUE/FALSE). **Landed (2026-09-06):** Soft `glbl[var]`
  — tip `g[i]=1` Soft Cmp OK (`+glblvaridx`). Root: `OptPass_RV` `IC_SHL_CONST`/
  `IC_SHR_CONST` passed `arg2` (IS_1_ARG / zeroed) instead of `MDF_IMM+ic_data`
  (x86 `ICShift` / same as `ADD_CONST`). **Landed (2026-09-06):** Soft
  `for(i) member[i] RMW` / `g[i]=g[i]&…` (`+varrmw+formembrmw`). Root: same-expr
  var-index RMW left second `IC_ADD` `arg1=STK`; `ICMov(REG←STK)` via nested
  `ICMov(DISP+SP)` Soft-hung — fixed with `RVLoadToReg` STK `ld`. **Landed
  (2026-09-06):** Soft Lex `&=` / `|=` / `+=` (`+andeq+formembandeq`) — host AOT
  Lex reused `ch` across `LexGetChar` so `dual_U16_tokens2[ch]` indexed `'='`
  (Missing expression); fix `ch1` + `CmpGetU32` dual reads (same plant as
  `CmpSetU32`). RV `IC_AND_EQU`/`OR`/`XOR` emit. Soft tip DocInit uses stock
  `member[i]&=~m`. Soft `p=glbl_arr` Soft Cmp+Call **OK** (`+glblarrdecay` /
  `+glblarrdecaywalk` / `+docguestafterdecay`) — Soft Cmp alone and Soft Call of
  flat `p=g` + member-arr walk no longer poison later DocGuest Soft Call (was
  r=7 head null; cleared by ABS_ADDR PC-rel / SHL_CONST / ASSIGN store landings).
  Soft tip DocInit uses stock
  `member[i]&=~m`. **Landed (2026-09-06):** Soft `+docdefines` /
  `+docinitdefines` — KernelA DolDoc `#define`s (`DOCT_*`/`DOCEF_*`/…) via Soft
  `#include A:/Compiler/DolDocDefines.HC` (RedSea seed from KernelA.HH subset).
  Soft AOT chains `glbl→asm_hash` (not Fs), so `DefineLoad` into Fs is invisible
  to Soft Cmp; Soft `#include` plants `HTT_DEFINE_STR` into the Soft Cmp glbl
  table (stock KernelA-include shape). Guest DocInit_RV no longer hand-plants
  local `#define`s. Soft tip returns `DOCT_LINK==28`; DocInitInc Soft tip now
  plants the full stock flag table (TEXT/DATA/CM/AN/LK/MA/MU/BT/CB/LS/HX/TR/SP/
  IB/IS/SO/HC + `for &= ~DOCG_BL_IV_UL`) on Soft `CDocInitSoftGlbls` — Soft Cmp+Call
  OK. **Landed (2026-09-06):** Soft `+docinitmemset` / `+docinitbts` /
  `+docinitdefload` / `+docinithashfind` — stock DocInit body slice Soft Cmp+Call:
  `import MemSet/Bt/Bts/DefineLoad` + Soft `CDocInitSoftGlbls g_doldoc` (not Kernel
  `doldoc` — Soft Call Load would shadow Fs) + MemSet clears + full flag plant +
  `Bt/Bts` `type_flags_form` / `clean_scan_codes` + `DefineLoad(FM_PICK_*)` +
  stock `HashFind(Fs->hash_table,…)` FM_PICK_* guard. Soft tip Soft Cmp Soft
  `HashFind(Fs->hash_table)` OK; Soft Call remat `Fs&&Fs->hash_table` + Soft Call Soft
  `HashFind(Fs->hash_table)` **OK** (`+docinithashfind`; Soft AOT `RVEmitAbsImm64`
  for IC_FS — PC-rel to external `&Fs` hung Soft Call Load). Plant:
  `RVCmpWireAsmHash`→asm_hash `_intern Fs` + lite `CTask` BST (`hash_table`
  required; graft if parent_task-only). SoftExeDir WIP wiped InternFs → Soft Cmp
  soft-skip; Soft HashFind tip Soft Cmp restored. Soft tip still needs `import`
  for Kernel funs (DefineLoad/HashFind/…). **Restored (2026-09-06):** Soft
  `+docinithashtablenew` Soft Cmp+Call early after DocEd Soft Call (before Menu
  Soft Call budget; Soft `HashTableNew(size,0)` — 1-arg Soft Call hang). Soft
  `DefineLstLoad`/`HashLstAdd` Soft Cmp+Call early (`+docinitdeflstload`/
  `+docinithashlstadd`; Soft export `HashLstAdd`; local ht — no Soft Fs tip). Soft
  `g_doldoc.hash` Soft Cmp+Call early (`+docinithash`; Soft Call HashLstAdd
  return-count Soft tip — Soft Call HashFind remat Soft glbl.hash Soft-fail r=3). Kernel `doldoc.hash` Soft Cmp+Call early
  (`+docinitkernhash`; Soft Call `RVDocDolDocHashGet` after host DocInit warm; no Soft Call
  Load Soft `doldoc` shadow). Soft Call HashFind remat Soft tip after Soft CALL_IMPORT
  into Soft ht (`+docinitkernhashfind`) Soft Cmp staged. Soft Call DocInitInc Soft tip Soft Call
  DocInit **OK** (`+docinitinc`; Soft `#include` guest DocInit_RV Soft Call
  MemSet/Bts/DefineLoad/HashFind+Fs Soft `g_doldoc`; Soft `DefineLoad` export;
  Soft Call after MakeDocNest Soft Call / Soft HashFind(Fs) Soft Call green). Next: Soft
  `#include` unmodified stock `DocInit_RV.HC` (bare Kernel `doldoc` into Soft
  asm_hash). Full
  guest MakeDoc Soft nest relative `#include` tip restored (`+docplainnest`/
  `+makedocnestcmp` Soft Cmp; Soft Lex file-dir join; nest seed DocPlain-only —
  no Soft `import Cd` / Soft `#define __DIR__` Soft Cmp Invalid lval vs KernelA
  `__DIR__` `#exe{StreamDir}`; DocInitInc Soft Cmp+Call covers Soft Fs DocInit). Dropped
  ff216c53 Soft Cmp soft-skips (`+docinithashfindskip`/`+makedocnestskip`/
  `+docinitincskip`). Stock Soft
  `Cd(__DIR__)` Soft Cmp still blocked (Soft AOT KernelA `__DIR__` `#exe{StreamDir}`
  Invalid lval; SoftExeDir HTT_FUN plant hung DocEd Soft Call — Soft `#define __DIR__`
  string + Soft `import Cd` workaround still Soft Cmp Invalid lval); full product
  `Adam/DolDoc/*` file set still open.
  **Landed (2026-09-05):** Soft
  `+docprintflags` — product `DocPrint("$$TX+CX,\"hi\"$$")` → `CENTER_X` entry +
  `DocRecalc` (`max_col=2`) under phase3 UART (no FB). **Landed (2026-09-05):** Soft
  `+doced` — stock DocEd-lite `DOCF_FORM` + inject Tab/Enter → BT `LE=1` +
  DocMenu MU `LE=42` under phase3 UART (no FB; Soft Call early after Runtime
  StartOS.BIN). **Restored (2026-09-06):** Soft DocInitHashFind Soft Cmp of Soft
  `HashFind(Fs->hash_table)` after DocEd Soft Call — Soft Cmp soft-skips dropped
  (`+docinithashfindcmp`; plant `RVCmpWireAsmHash`→`RVExePubInternFsGsIn`). **Landed
  (2026-09-06):** Soft Call remat `Fs&&Fs->hash_table` + Soft Call Soft
  `HashFind(Fs->hash_table)` OK (`+docinithashfind`) — Soft AOT IC_FS/IC_MOV_FS
  embeds abs U64 of Compiler `&Fs` (`RVEmitAbsImm64`; PC-rel to external `&Fs`
  broke Soft Call Load → hang; `+docinithashfindcallskip` dropped). Soft Call after
  HashLstAdd Soft Call + `RVPhase3SyncCmpFs`. DocInitInc Soft Cmp+Call
  **OK** (`+docinitinc`; Soft Call DocInit Soft tip Soft `#include` guest Soft
  `g_doldoc` Soft Call MemSet/Bts/DefineLoad/HashFind+Fs). MakeDocNest Soft Cmp soft-skip (Cd/__DIR__ nest).
  **Landed (2026-09-07):** Soft `MenuLexI64Soft` Soft Call soft-fail r=1 was live
  local `v` across SoftLexPlant Soft Call (a0 clobber) — Soft tip uses Soft glbl
  `g_lex_ret` (flat Soft I64; keep `IC_BODY_SIZE` 0x83). Soft Call NewSubCmp /
  MenuNewCmp / MenuNewCmpCtrl Soft Call soft-skips dropped (Soft Call after Soft Cmp).
  Soft Cmp stays (`+menulexi64soft+menunewsubcmp+menunewcmp+menunewcmpctrl`). Soft Call
  needles: `+menulexi64softcall+menunewsubcmpcall+menunewcmpcall+menunewcmpctrlcall`
  when green. Keep `MENU_RV_GUEST_CMP` until Soft Call MenuNewCmpCtrl green on tip.
  **Landed (2026-09-06):**
  WinMgr lite/tick/Task/Spawn + PopUp CRV + StartOS Soft Call + StartOS-wave Ctrls
  Soft Call restored (`+winmgrlite`…`+startossoft`+`+ctrlssoft`) — hang was
  `LiteInit→DocInit` `HashFind(Fs->hash_table)` before warm early-return; `DocInit_RV`
  now warm-returns on `doldoc.hash` TX first (FM_PICK plant cold-only). Late Soft Call
  wave still soft-skipped (`+latesoftcallskip`) so StartOS Load Kernel.BIN proves.
  Soft Cmp of those tips stays.
  **Landed (2026-09-05):** Guest_Lex stock Skip Cmp OK (ASCII-only
  seed — UTF-8 em-dash in `//` and/or `\t` in SelfTest → guest LexExcept
  `Missing expression` hang).   **Landed (2026-09-06):** Soft `+menureadident`
  2-arg out-param fill (`RVMenuReadIdent(p,out)` one `*d=*p` into caller buf;
  ASCII `" x"`) + fold into Guest_Lex SelfTest. **Landed (2026-09-06):** Soft
  `+menureadident` 3-arg product shape Soft Call OK (`RVMenuReadIdent(p,out,max)`
  + `" Tile"` via `out[n++]=*p++`; entry `lim=max-1` then nested LexOk — live
  `n<max-1` after calls still Soft Call r=0). Compiler: BY_VAL SIB/DISP narrow
  stores use LEA+`ICRVStoreThru` (same host-AOT `ICMov(MDF_*+pt)` CICType trap
  as Ident REG); OptPass6 skips fuse for narrow SIB/DISP/RIP. Folded into
  Guest_Lex. **Landed (2026-09-06):** Soft flat Guest (+Width) Soft Cmp **OK**; Soft Call
  Count/Width (`+flatcnt+flatwidth`) + tip `+menuwidth`; I64 `CRVLiteMenu`/`CAlloc`
  Soft Cmp+Call OK (`+cmenu+cmenucall`); product-ish `CMenuEntry` `U8 name[32]` Soft
  Cmp+Call OK (`+cmenuent+cmenuentcall`). **Landed (2026-09-06):** Soft Kernel product
  `CMenu`/`CMenuEntry` layout — `U8 attr,pad[7]`, Bool scalars, `Bool checked,dir,pad[6]`,
  full entry=80/menu=40 Soft Cmp+Call OK
  (`+cmenuu8pad+cmenubool+cmenuboolpad+cmenuprod` + Calls). Guest plants same layout
  (`arg1` for id). `MENU_RV_GUEST_CMP` **gated** as Guest chrome vs product
  CmpCtrl/PopUp/DocTerm (not I64-only type fork). Prior “Bool pad hang” was Soft tip
  order behind MakeDocNest `Cd(__DIR__)` hang — Soft Cmp of Bool `pad[]` itself greens.
  **Landed (2026-09-06):** Soft product Menu_RV subsets — `MenuEntryWidth` on product
  `CMenuEntry` (`+prodentrywidth`), hand-Lex `MenuNewHand` leaf `"Tile(,8);"` →
  entry.arg1 (`+menunewhand`) Soft Cmp+Call OK; CmpCtrl `MenuFpOk`/`FpsWired` gate
  Soft Cmp+Call **OK** (`+menufpok+menufpokcall`). Soft Call tip proves IMM
  `0x20000` + bit31 `0x80001000` + local `good` Soft CALL remat (Soft threshold
  `0x10000`; Menu_RV host still `0x80000000`). Root cause of Soft Call r=4
  “churn”: OptBrZero folds `fp&1` → `IC_BR_AND_ZERO` (149) which Soft RV did not
  emit — Soft Call always took return-0. **Landed:** `ICAndBranch` +
  `IC_BR_AND_ZERO`/`NOT_ZERO` in `BackC_RV`/`OptPass_RV`; n==1 remat skips empty
  FP-slot clobber; MOV REG/DISP + STK a0-leave + CALL_EXTERN remat kept. Soft
  `MenuLexI64Soft` / `MenuNewSubCmp` with planted SoftLexPlant + Soft-Call-safe
  `g_lex_fp=1` (not `0x20000` remat / no DRAM-base Soft Call) Soft Cmp+Call **OK**
  (`+menulexi64soft+menunewsubcmp`; HashTableNew sibling Soft Cmp early; Soft Call still r=1/`+menunewsubcmpskip`). Soft `MenuNewCmp` /
  `MenuNewCmpCtrl` with planted CmpCtrl fps (`g_fp_*=1` SoftMenuFpsWired + SoftCmpCtrlNew/
  SoftLexPlant/SoftCmpCtrlDel; no DRAM Soft Call) Soft Cmp **OK**
  (`+menunewcmp+menunewcmpctrl`; Soft Call soft-skip like prior NewSubCmp hang class —
  sibling). **Landed (2026-09-06):** Soft PopUp Ok/Resolve Soft Win + Soft DocTerm
  Wire/Term Soft Doc tip Soft Cmp+Call (`+popupsoft+doctermsoft` +
  `+popupsoftcall+doctermsoftcall`; Soft Call Soft PopUp SelfTest Ok/Resolve/mode/title —
  hits/n_wins delta remat soft-fail r=9 dropped). Soft PopUp planted fps / lite
  Ok+Resolve Soft Cmp (`+popupsoftfp`; SoftPopUpFpOk/FpsWired Soft-Call-safe `g_fp_*=1`).
  Soft PopUp Soft Win + planted fps join Soft Cmp+Call (`+popupsoftwinfp` +
  `+popupsoftwinfpcall`; Soft Ok/Resolve Soft Win gated on SoftPopUpFpsWired).
  `MENU_RV_GUEST_CMP` still gates Guest
  chrome vs live WinMgr PopUp/DocTerm — Soft tips Soft Cmp+Call green; drop ifdef after
  Guest wrap without Guest chrome.
  **Blocked (2026-09-06):** true spill/reload of arg `max` across
  nested Soft Calls — tried (1) ENTER `sd a0..` into RBP+16+8*i → Soft Cmp hang
  (`IC_BODY_SIZE` 0x83 ENTER overflow / silent truncate); (2) CALL_START/END
  caller-save `REGG_LOCAL_VARS` + remat depth → PopUpGuest hang / timeout;
  (3) OptPass3 keep args (`offset>0`) out of s-regs → same late Soft Call hang.
  Root cause (best): live `max` is not memory-stable after LexOk Soft Call
  (entry `max` OK; post-call reload dies) while `lim` local survives — likely
  caller-saved holding of the arg without a frame reload that fits in
  `IC_BODY_SIZE`. Keep entry `lim` workaround. Still open: full guest MakeDoc
  `#include` Adam/DolDoc/* (Soft `#include` unmodified stock `DocInit_RV` with bare
  Kernel `doldoc` into Soft asm_hash; Soft Call DocInitInc Soft tip Soft Call DocInit
  green `+docinitinc`; plant DOCT_* into loaded
  `cmp.asm_hash` for include-free stock; DocRecalc/DocPutKey/Lex). **Landed
  (2026-09-06):** RedSea nested `Adam/DolDoc/` via `mk_redsea_seed_img.py`
  multi-level dirs + Soft `+docplainnest`/`+makedocnest`/`+makedocrel` —
  MakeDoc_RV nest seed uses relative `#include` `DocInit_RV`/`DocPlain_RV`;
  Soft Lex joins relative includes to the including file's dir (host AOT shape;
  Soft AOT does not JIT-run bare `Cd` before Lex). Soft Cmp+Call nest OK.
  Soft `Fs->hash_table` Soft Cmp+Call restored (`+docinithashfind`) via
  `RVCmpWireAsmHash`→`RVExePubInternFsGsIn(cmp.asm_hash)` + lite `CTask` BST.
  Soft `HashTableNew` Soft Cmp+Call restored early after DocEd Soft Call
  (`+docinithashtablenew`; Soft import `HashTableNew(size,0)` — 1-arg Soft Call hang).
  **Landed (2026-09-06):**   Soft `DefineLstLoad`/`HashLstAdd` Soft Cmp+Call early
  (`+docinitdeflstload`/`+docinithashlstadd`; Soft `RVCmpExportOne(HashLstAdd)`; local
  ht tip before Fs remat Soft Call zone).   Soft Call `HashLstAdd` return-count Soft tip
  (Soft Call `HashFind` after Soft CALL_IMPORT remats `ht` Soft-fail r=3 — same
  `IC_BODY_SIZE` Soft Call remat class). **Landed (2026-09-06):** Soft `g_doldoc.hash`
  Soft Cmp+Call early (`+docinithash`; Soft Call HashLstAdd return-count Soft tip —
  Soft Call HashFind after Soft CALL_IMPORT remats Soft glbl.hash Soft-fail r=3;
  before Fs remat Soft Call / Menu Soft Call budget). **Landed (2026-09-06):** Kernel
  `doldoc.hash` Soft Cmp+Call early (`+docinitkernhash`; Soft Call `RVDocDolDocHashGet`
  after host DocInit warm; no Soft Call Load Soft `doldoc`). Soft Call DocInitInc Soft tip Soft Cmp
  **OK** (`+docinitinccmp`); Soft Call soft-skip hang after Soft Cmp (`+docinitinccmp` needle
  class). **Landed (2026-09-07) Soft tip / Soft Cmp hang ceiling:** Soft `#include` unmodified
  stock `Adam/DolDoc/DocInit_RV.HC` Soft tip staged — RedSea `Compiler/DocInit_RV_Stock.HC` =
  stock file (`+docinitrvstockredsea`); Soft tip seed Soft `#include` after DolDocDefines+imports;
  Soft AOT `RVExePubInternDolDocIn(cmp.asm_hash)` plants Kernel `CDolDocGlbls`+`doldoc` abs
  (GVF_ALIAS) from `RVCmpWireAsmHash`. Soft Cmp of Soft `#include` stock **hangs** after Soft
  plant (`+docinitstockskip`; Soft Call soft-skipped same class). StartOS Load Kernel.BIN still
  proves when Soft Call Soft tips soft-skipped. Next Soft tip: bisect Soft Cmp hang of stock Soft
  `#include` (planted doldoc member layout vs Soft AOT AbsImm / Soft `CHashDefineStr` lite /
  DefineLstLoad body) without Soft Call hang budget fights. Still open:
  Soft Call HashFind remat Soft tip after Soft CALL_IMPORT into Soft ht / Soft `g_doldoc.hash`
  (`+docinitkernhashfind` Soft Cmp; r=3 sibling);
  MakeDocNest Soft Cmp restored (DocPlain nest seed;
  Soft DocInitInc Soft Cmp+Call covers Soft Fs DocInit; Soft Call remat Soft `Fs->hash_table`
  **OK** via Soft AOT abs-U64 IC_FS);
  stock Soft `Cd(__DIR__)` (KernelA `__DIR__`
  Soft AOT Invalid lval; Soft `#exe{Cd}`/StreamDir HTT_FUN plant hung DocEd Soft Call);
  full product DolDoc file set on RedSea;
  Runtime Seed/Svc/Kern RedSea seeds flattened (no `#include`) to dodge older
  DirContext `#include` Cmp→no-BIN — not A3 gates.
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
| **G9 residual host AOT** | phase3 ELF Cmp scaffold (StartOS Load SoftCall DoD via StartOSSoft) + host `pack_tosb`→RedSea virtio img still Mac-built; live Cmp is reloc heap Load; RedSea `Kernel.BIN` is **InitLite+SoftCall seed** (TrapIRQ/Timer/Disp + TaskSoft/HashSoft/PrintSoft/YieldSoft→`'KY'` + **JumpSoft**→`'KL'` + **ExeSoft** RedSea Load→HashFind→Call→`'KB'` when LoadProbe on img + **MakeSoft** product `A:/MakeOS/Tiny.BIN`→`MakeOSProbe=42`→`'KN'` + **SeedSoft** product `A:/Runtime/Seed.BIN`→`RuntimeSeedInit=42`→`'KR'` + **SvcSoft** product `A:/Runtime/Svc.BIN`→`RuntimeSvcProbe=42`→`'KC'` + **KernSoft** product `A:/Runtime/Kern.BIN`→`KernInit=42`→`'KK'` + **StartSoft** Seed→Svc→Kern→`'KU'` + **AdamSoft** product `A:/Adam/StartOS.BIN`→`StartOSProbe=1`→`'KA'` + **DateSoft** KDate calendar+Goldfish RTC Now→`'KG'` past `KThinDateStubs` + **QSortSoft** QSortI64→`'KO'` past `KThinQSortStubs` + **KeyDevSoft** PutKey/PutS+CtrlAlt→`'KW'` past `KThinKeyDevStubs` + **ExceptSoft** SysTry/throw/PutExcept→`'KZ'` past thin PutExcept stub (no x86 TestExcept asm) + **MemSoft** HeapCtrl+MAlloc/Free/MSize→`'KH'` past `KThinMemStubs` + **StrUtilSoft** StrUtil/MStrUtil→`'SU'` past `KThinStrUtilStubs` + **FifoSoft** FifoU8/I64→`'SF'` past MapFat Fifo stubs (Serial gated; InputFilterTask wall) + **QueVectSoft** QueVectU8→`'QV'` past MapFat QueVect stubs + **RandSoft** Seed+LCG→`'RN'` past MapFat Rand stubs + **ScanFlagsSoft** LstMatch+ScanFlags+/-→`'SC'` past MapFat ScanFlags stubs + **CompressSoft** CompressBuf/ExpandBuf→`'CM'` past thin Compress gate (SoftCall-local ARC_BITS=9; ARC12 BSS ~96 KiB skipped) + **KLoadSoft** LoadPass1 import+ABS→`'LD'` past JumpSoft export-only (SoftCall-lite) + **MakeMemSoft** MemPag FREE_PAG=0x100→`'MM'` past `KThinMemStubs` (stock FREE_PAG_HASH=0x100; Hash2Soft owns free_pag_hash2 stock 55) + **PhysMemSoft** BlkPoolsInit+MemPageTable+Mem32Dev→`'PM'` past MakeMemSoft (SoftCall-local PTE[16]/ synthetic E820; no x86 SYS_INIT_PAGE_TABLES/Sv39; no Mem64Dev/UncachedAlias; FB/WinMgr SoftCall skipped — RVWinMgr ~120 KiB src) + **LoadMainSoft** CODE_HEAP+MAIN+FileRead→`'LM'` past KLoadSoft (SoftCall-lite ArenaAlloc code_heap; LoadPass2 MAIN Call; FileRead SOFTFW.OK — A:/Kernel/ CDir full; no ExtDft.Z/DATA_HEAP/ZEROED_*) + **Hash2Soft** free_pag_hash2 stock 55→`'H2'` past MakeMemSoft (stock FREE_PAG_HASH2=55; SoftCall-local HASH2_FREE_PAG_HASH=8 threshold) + **DataHeapSoft** DATA_HEAP+ZEROED_*+ExtDft.Z→`'DH'` past LoadMainSoft (SoftCall-lite stack ExtDft; ArenaAlloc data_heap; ZEROED CAlloc MemSet; A:/Kernel/ CDir full; LoadAbsSoft owns full Load(); BlkDev SoftCall skipped — RedSea+virtio ENTER already SoftCalled, full MakeBlkDev ~177 KiB won't fit) + **LoadAbsSoft** FileNameAbs+module_align→`'LA'` past DataHeapSoft (SoftCall-lite FileNameAbs drive-abs+join; FileExtRem; HTT_MODULE `fbuf+2` leading `/`; MAllocAligned min-16; ExtDft+FileRead LoadProbe→aligned LoadPass+MODULE+export Find; DirAbsSoft owns FUF_Z_OR_NOT_Z/DirNameAbs parents/MAlloc ExtDft) + **DirAbsSoft** DirNameAbs parents+Z+ExtDft→`'DN'` past LoadAbsSoft (SoftCall-lite `..`/`.` resolve; ToggleZ+FileFind Z-alt; ArenaAlloc ExtDft; no ~ / FUF_SCAN_PARENTS); **`KernelTrapPlic` unwired** — host-fed UART RX + asm EXT clear hung after THRE/virtio) not full Kernel_RV; thin embed handoff green (**thin Jump** HashFind→Call via lite `KThinHashStubs`); **StartOS/AdamCore/MakeOS/Runtime** + **Menu_RV Guest/Lex/wrap/Lite** + **Lite* bisect PRJs** + Soft tip **LiteMenuSkip/LexOk/RID** prefer RedSea seeds (**product `MakeOS/`+`Runtime/` root dirs** + nested **`Adam/DolDoc/`** via multi-blk `mk_redsea_seed_img.py`; Menu/Lite* under `Compiler/`; Adam lean); phase3 demo **`RV_PHASE3_MENU_REDSEA`** gates out ELF `RVAdamLiteMenuSrc` link | [COMPILER_RV.md](../templeos-riscv/COMPILER_RV.md) P3 residual — SoftCall owns VBlk+TrapCtx CLINT SoftCalls+Yield CtxSw+Jump HashFind+**ExeSoft**+**MakeSoft**+**SeedSoft**+**SvcSoft**+**KernSoft**+**StartSoft**+**AdamSoft** product Load chain+**DateSoft** KDate+**QSortSoft** QSortI64+**KeyDevSoft** KeyDev+**ExceptSoft** try/throw+**MemSoft** HeapCtrl+**StrUtilSoft** StrUtil+**FifoSoft** Fifo+**QueVectSoft** QueVect+**RandSoft** Rand+**ScanFlagsSoft** ScanFlags+**CompressSoft** Compress+**KLoadSoft** KLoad+**MakeMemSoft** MakeMem FREE_PAG=0x100+**PhysMemSoft** PhysMem+**LoadMainSoft** Load MAIN/CODE_HEAP+**Hash2Soft** free_pag_hash2 stock 55+**DataHeapSoft** DATA_HEAP/ExtDft.Z+**LoadAbsSoft** FileNameAbs/align/MODULE+**DirAbsSoft** DirNameAbs/Z/ExtDft; thin Jump HashFind landed; StartOS/AdamCore/MakeOS/Runtime/Menu/Lite*/Adam/DolDoc nest RedSea seeds landed; MenuSrc ELF gated on demo; SoftCall seed ceiling ~339 KiB (346800) (BlkDev/FB/ARC12/full Compiler.BIN skip); **StartOSSoft**→`'SO'` + **ExePutSSoft** CmpCtrl+ExePutS→`'EP'` + **CmpSoft** SoftCmp.BIN→`'CC'` + **LexStmtSoft** LexStmt2Bin emit+Call→`'LB'` + **PrsOptSoft** Prs/Opt RPN fold+emit→`'PO'` + **ParenSoft** paren+IC emit→`'PN'` + **IdentSoft** local/ident IC→`'ID'` + **AssignSoft** PrsStmt assign→`'AS'` + **FunDefSoft** fun-def/return/Call→`'FD'` + **FunBodySoft** multi-stmt/locals-in-fun/single-arg→`'FB'` + **FunCallSoft** multi-arg/call-Expr→`'FC'` + **AbiSoft** ABI/a0 frame→`'AB'` + **CocSoft** COC multi-stmt ASSIGN→`'CO'` + **BrSoft** if/while BR→`'BR'` + **ElseSoft** if/else→`'EL'` + **ForSoft** for→`'FR'` + **CmpBrSoft** relational cmp-BR→`'CB'` SoftCall-lite landed; SoftCall seed ceiling ~457 KiB (468000); next tip: first **real guest Cmp attempt without Mac phase3.elf** past **GlblMemSoft** `'GM'` (SoftCall-lite glbl memory landed — `lui`/`addi` abs + `ld`/`sd` into real Kernel.BIN data, cross-fun visible and HolyC-readback proven; every lite-Cmp primitive now present; `'EP'` held) (full ~1.1 MiB Compiler.BIN still SoftCall ceiling — bigger heap alone not the lever) / drop phase3.elf full Cmp scaffold (**no TrapPlic retry**; **no ARC12 SoftCall**; avoid DocInit/Menu Soft tip fights) |
| **DolDoc / Menu Lex** | CmpCtrl MenuNew on split-AOT via abs addrs | Hand Lex SoT; `RVCmpCtrlAddrsGet`+soft I64 `MenuNewCmpCtrl`; DocForm class-meta |
| **PopUp_RV / WinMgr** | PopUp needs `CRVWin` / `rv_winmgr` symbols | Soft Lite probe omits PopUp; host AOT `win_*.elf` still bootstrap |

**P6 soft probe (landed, not DoD):** phase3 prefers RedSea `Compiler/Menu_RV_Guest.HC`
(+ `Menu_RV` wrap with `MENU_RV_GUEST_CMP` + folded `Menu_RV_Guest_Lex` +
`MakeAdam_RV_Lite.PRJ` + **Lite* bisect PRJs**) under `Compiler/` (Adam stays lean);
copies Menu into `A:/Adam/` for relative includes; Soft tip LiteMenuSkip/LexOk/RID/Width
prefer RedSea under `Compiler/`; phase3 demo `RV_PHASE3_MENU_REDSEA` skips linking
`RVAdamLiteMenuSrc` (miss path UARTs only). Guest chrome APIs: Count/Name/Id/
**Width** (shared with host WinMgr surface). Wrap `#include`s Lex then Guest. Soft probes:
`LiteMenuLex` / `LiteLexFold` / flat Guest / `LiteCMenu` / `LiteCMenuEnt` / `LiteCMenuU8Pad` /
`LiteCMenuBool` / `LiteCMenuBoolPad` / `LiteCMenuProd` / `LiteMenuEntryWidth` /
`LiteMenuNewHand` / `LiteMenuFpOk` / `LiteMenuLexI64Soft` / `LiteMenuNewSubCmp` /
`LiteMenuNewCmp` / `LiteMenuNewCmpCtrl` / `LiteMenuWidth` / `LitePopUpSoft` /
`LitePopUpSoftFp` / `LitePopUpSoftWinFp` / `LiteDocTermSoft`
— **Soft Cmp OK** (prior flat Guest `err=1` was leading `//` → Lex `/` when host AOT
mis-stored `d['/']` duals; fixed `CmpSetU32(d,0x2F,…)`). AdamLite prefers
`#include "Menu_RV"` → Init + `FileWrite(LITE.TXT)` + `return 8`; **menu-free FileWrite
fallback** only if Menu include Cmp fails (keeps StartOS Load→Call needle). Nesting
I64 `CRVLiteMenu`/`CAlloc(sizeof)` Soft Cmp+Call **OK** (`+cmenu+cmenucall`); Kernel product
`CMenu`/`CMenuEntry` Bool `pad[]` Soft Cmp+Call **OK**
(`+cmenuu8pad+cmenubool+cmenuboolpad+cmenuprod`); Guest plants product layout.
Product Soft tips: `MenuEntryWidth` (`+prodentrywidth`), hand-Lex `MenuNewHand` leaf
(`+menunewhand`) Soft Cmp+Call **OK**; CmpCtrl `MenuFpOk` gate Soft Cmp+Call **OK**
(`+menufpok+menufpokcall`; IMM + bit31 + local `good` Soft CALL remat; `IC_BR_AND_ZERO`);
planted SoftLex `MenuLexI64Soft`/`MenuNewSubCmp` Soft Cmp **OK**
(`+menulexi64soft+menunewsubcmp`; Soft Call still blocked); planted CmpCtrl-fp
`MenuNewCmp`/`MenuNewCmpCtrl` Soft Cmp **OK**
(`+menunewcmp+menunewcmpctrl`; Soft Call soft-skip);
Soft PopUp/DocTerm Soft tip Soft Cmp+Call **OK**
(`+popupsoft+doctermsoft+popupsoftcall+doctermsoftcall`). Soft PopUp planted fps /
lite Ok+Resolve Soft Cmp **OK** (`+popupsoftfp`; Soft-Call-safe `g_fp_*=1`). Soft PopUp
Soft Win + planted fps join Soft Cmp+Call **OK** (`+popupsoftwinfp+popupsoftwinfpcall`; Soft Ok/Resolve Soft Win
gated on SoftPopUpFpsWired).
`MENU_RV_GUEST_CMP` still gates Guest chrome vs live WinMgr PopUp/DocTerm (Soft tip
Soft Cmp+Call green; drop after wrap without Guest). Host
`Menu_RV`: real `CMenu` hand Lex + `MenuNewCmpCtrl`, `MenuTask`/`MenuEntryWidth`,
unified `MenuPush`/`MenuPop`. PopUp CRVWin / DocTerm remain host WinMgr (`win_*.elf`).
Soft — does **not** gate phase3. Load→Call needle:
`P6 MakeAdam_RV_Lite Load→Call OK (menu_n=8 Lex+Guest|Menu_RV, LITE.TXT)`.

**Guest Cmp gaps found this pass (G8 remainder):**

| Surface | Symptom |
|---------|---------|
| Soft `glbl[var]` indexed store | Soft Cmp **OK** tip `g[i]=1` (`+glblvaridx`; was hang — `IC_SHL_CONST` used arg2 not `ic_data`) |
| Soft `for(i) member[i] RMW` | Soft Cmp **OK** expanded `a=a&~m` (`+varrmw+formembrmw`; was hang — `ICMov(REG←STK)` nested DISP+SP; `RVLoadToReg`) |
| Soft Lex `&=` / member `&=` | Soft Cmp **OK** `g[i]&=1` / `flags[i]&=~m` (`+andeq+formembandeq`; was Missing expression — Lex `ch` clobber across `LexGetChar` on tokens2 path; `ch1`+`CmpGetU32`) |
| Soft `p = glbl_arr` decay | Soft Cmp+Call **OK** (`+glblarrdecay+glblarrdecaywalk+docguestafterdecay`); Soft Cmp alone + Soft Call of flat/member decay no longer poison DocGuest Soft Call (was r=7 head null) |
| Soft KernelA DolDoc `#define`s | Soft Cmp **OK** via Soft `#include DolDocDefines.HC` (`+docdefines`/`+docinitdefines`; Fs `DefineLoad` invisible to Soft AOT — chain is glbl→asm_hash) |
| Soft DocInit MemSet / Bt / Bts | Soft Cmp+Call **OK** (`+docinitmemset`/`+docinitbts`; Soft `g_doldoc` + `import`) |
| Soft DocInit `DefineLoad` | Soft Cmp+Call **OK** (`+docinitdefload`; `import` + Soft Call `RVCmpExportOne`) |
| Soft `HashFind` (no Fs) | Soft Cmp **OK** (`+docinithashfindcmp`; table=0 tip restored — Soft Call soft) |
| Soft `Fs->hash_table` / stock HashFind guard | Soft Cmp Soft `HashFind(Fs->hash_table)` **OK**. Soft Call remat `Fs&&Fs->hash_table` + Soft Call Soft `HashFind(Fs->hash_table)` **OK** (`+docinithashfind`) — Soft AOT `RVEmitAbsImm64` for IC_FS/IC_MOV_FS (PC-rel to external Compiler `&Fs` hung Soft Call Load). Plant Soft Cmp: `RVCmpWireAsmHash`→`RVExePubInternFsGsIn(cmp.asm_hash)` + lite `CTask` BST (`hash_table` required). MakeDocNest Soft Cmp+Call OK (DocPlain-only; Soft Cd/__DIR__ Soft Cmp Invalid lval) |
| Soft Kernel `doldoc` glbl name | Soft tip uses Soft-local `g_doldoc` — Soft Call Load of Soft `doldoc` would shadow Kernel Fs; Kernel `doldoc.hash` Soft Cmp+Call **early** via Soft Call `RVDocDolDocHashGet` after host DocInit (`+docinitkernhash`); Soft Call HashFind remat Soft tip Soft Cmp (`+docinitkernhashfindcmp`) |
| Soft `HashTableNew` Soft Cmp+Call | Soft Cmp+Call **restored early** after DocEd Soft Call (`+docinithashtablenew`; `HashTableNew(size,0)` — 1-arg Soft import Soft Call hang). Soft Call before Menu Soft Call budget / Fs remat Soft Call zone. Soft `DefineLstLoad`/`HashLstAdd` Soft Cmp+Call **early** (`+docinitdeflstload`/`+docinithashlstadd`; Soft `RVCmpExportOne(HashLstAdd)`; Soft Call `HashLstAdd` return-count Soft tip — Soft Call `HashFind` after Soft CALL_IMPORT remats `ht` Soft-fail r=3). Soft `g_doldoc.hash` Soft Cmp+Call **early** (`+docinithash`; Soft Call HashLstAdd return-count Soft tip — Soft Call HashFind remat Soft glbl.hash Soft-fail r=3). Kernel `doldoc.hash` Soft Cmp+Call **early** (`+docinitkernhash`; Soft Call `RVDocDolDocHashGet` after host DocInit). Soft Call HashFind remat Soft tip (`+docinitkernhashfind`) Soft Cmp staged. Soft `#include` guest DocInit Soft Call DocInit **OK** (`+docinitinc`; Soft Call MemSet/Bts/DefineLoad/HashFind+Fs Soft `g_doldoc`; Soft `DefineLoad` export). Soft `#include` unmodified stock `DocInit_RV` (bare Kernel `doldoc` into Soft asm_hash) still open |
| Soft missing other KernelA `#define`s | `TRUE`/`FALSE`/… still absent unless Soft-included or planted into loaded `cmp.asm_hash` |
| `class` with member arrays / globals | Soft tip `CDolDocGlbls`+const-index plant OK; Kernel `CMenuEntry` Bool `pad[6]` Soft Cmp+Call **OK** (`+cmenuboolpad`) |
| Nested `#include "Menu_RV"` → AdamLite Call | **OK** if Load→Call **before** flat Menu Load |
| Guest `FileWrite` inside AdamLite.BIN | **OK** as Count→local then multi-STR `FileWrite` (CALL_IMPORT restores SP after `_RV_HC_CALL`). Guest plants LITE.TXT |
| Local `U8 name[32]` | guest Cmp **OK** |
| Local `U8 *p="lit"; return 1` | guest Cmp **OK** |
| `*"lit"` / `return *p` / ident walk | guest Cmp+Call **OK** (`CmpU8StarType`: host AOT `type+1` was +1 byte; also prior pack `PREC<<16+i` → ic 0x4000). Ident walk still soft |
| Glbl `U8[]` elem after StrCpy | Cmp OK; Call soft-fail r=0 (ABS_ADDR / REG_RAX=x0 — separate) |
| Span `DirMk("A:/Span")` | phase3 Soft Call **OK** (`DrvUnlock` Yield only if live peer). Span smoke still soft-skips live DirMk (Doc Print under put_doc) |
| Guest index Lex (`Menu_RV_Guest_Lex`) | wrap **folded**; flat Guest_Lex Soft Cmp **OK** (`+guestlex`; ASCII-only; `\t`/UTF-8 hang) |
| Lex+Guest fold wrap (`LiteLexFold`) | Soft Cmp **OK** (`+lexfold`) when Guest/Lex green |
| Flat Guest (+Width) | Soft Cmp **OK** (`flat Menu_RV OK`); Soft Call Count/Width **OK** (`+flatcnt+flatwidth` via LiteGuestTiny); tip `+menuwidth` |
| Guest I64 `CRVLiteMenu` / `CAlloc(sizeof)` | Soft Cmp+Call **OK** (`+cmenu+cmenucall`); Guest now product layout |
| Soft product `CMenu`/`CMenuEntry` (Bool `pad[]`) | Soft Cmp+Call tip (`+cmenuu8pad+cmenubool+cmenuboolpad+cmenuprod`); `MENU_RV_GUEST_CMP` gated Guest vs CmpCtrl |
| Soft product MenuEntryWidth / MenuNewHand / MenuFpOk | Soft Cmp+Call tip (`+prodentrywidth+menunewhand+menufpok+menufpokcall`); IMM `0x20000` + bit31 `0x80001000` + local `good` Soft CALL remat OK (`IC_BR_AND_ZERO` emit) |
| Soft `MenuLexI64Soft` / `MenuNewSubCmp` (planted SoftLex) | Soft Cmp+Call tip (`+menulexi64soft+menulexi64softcall+menunewsubcmp+menunewsubcmpcall`; Soft-Call-safe `g_lex_fp=1`; Soft glbl `g_lex_ret` across SoftLexPlant Soft Call — live local a0 clobber was Soft Call r=1); `RVRematLeaOrAddrArg` PC-rel for in-module `&glbl` |
| Soft `MenuNewCmp` / `MenuNewCmpCtrl` (planted CmpCtrl fps) | Soft Cmp+Call tip (`+menunewcmp+menunewcmpcall+menunewcmpctrl+menunewcmpctrlcall`; `g_fp_*=1` SoftMenuFpsWired + SoftCmpCtrlNew/SoftLexPlant/SoftCmpCtrlDel + `g_lex_ret`; no DRAM Soft Call); keep `MENU_RV_GUEST_CMP` until Soft Call MenuNewCmpCtrl tip proves |
| Soft PopUp planted fps / lite Ok+Resolve | Soft Cmp **OK** (`+popupsoftfp`; SoftPopUpFpOk/FpsWired + SoftPopUpOkSoft/ResolveSoft; Soft-Call-safe `g_fp_*=1`) |
| Soft PopUp Soft Win + planted fps join | Soft Cmp+Call **OK** (`+popupsoftwinfp+popupsoftwinfpcall`; Soft Ok/Resolve Soft Win gated on SoftPopUpFpsWired; Soft-Call-safe `g_fp_*=1`) |
| Rich host `Menu_RV` PopUp / DocTerm | WinMgr PopUp/DocTerm still Guest-gated (`win_*.elf`; MenuNewCmpCtrl Soft Cmp planted fps green; Soft PopUp Soft Win+fps join Soft Cmp+Call green) |
| UART Ctrls_RV Soft Call (DemoInstall+queue+click) | **Cmp+Call OK** (`+ctrlssoft`): MakeAdam Ctrls tip; stamps Fs addr/sig; no FB DrawCtrls |
| UART Gr Soft Call (DCNew+Fill+Plot+Blot) | **Cmp+Call OK** (`+grsoft`): offscreen 8×8 dst + **2×2** blot + GrPeek (RED+ink); no interactive FB. Host AOT fix: INTERNAL `U32i` shadowed KW → `_extern` skipper dropped scalar base (`U32` raw RT_I64); local `U32 *` peels used 8-byte ld/sd. Lexer KEYWORD prefer + `ScalarTypeForSize` on local/global `U32*` |
| UART WinMgr lite/tick/Task/Spawn + PopUp CRV + StartOS Soft Call | Soft Cmp+Call **OK** (`+winmgrlite`…`+startossoft`) — `DocInit_RV` warm-return before Fs HashFind |
| UART Ctrls Soft Call (StartOS wave) + late Soft Call wave | StartOS-wave Ctrls Soft Call **OK** (`+ctrlssoft`); late Soft Call wave soft-skip (`+latesoftcallskip`) — Guest_Lex/Menu/Doc Soft Calls soft-skipped to prove StartOS Load Kernel.BIN |

**Next 3 steps (order):**

1. Soft product Menu_RV subsets Soft Cmp **landed**
   (`+prodentrywidth+menunewhand+menufpok+menulexi64soft+menunewsubcmp+menunewcmp+menunewcmpctrl`;
   Soft Call EntryWidth/NewHand/MenuFpOk OK (`+menufpokcall`; BR_AND_ZERO + remat);
   Soft Call LexI64Soft / NewSubCmp / MenuNewCmp / MenuNewCmpCtrl via Soft glbl
   `g_lex_ret` across SoftLexPlant Soft Call (`+menulexi64softcall+menunewsubcmpcall+menunewcmpcall+menunewcmpctrlcall`
   when tip green — was Soft Call r=1 live local a0 clobber / soft-skips). Soft
   `MenuNewCmpCtrl` planted CmpCtrl fps Soft Cmp **green** — keep `MENU_RV_GUEST_CMP`
   for WinMgr PopUp/DocTerm until Soft Call MenuNewCmpCtrl tip green (do not drop
   for live host fps yet). Soft Call arg `max` spill across LexOk still blocked
   (`IC_BODY_SIZE` 0x83; keep entry `lim`). Post-DocTermNew WinMgr/StartOS/Ctrls Soft
   Calls **restored** (`DocInit_RV` warm-return); late Soft Call wave still soft-skipped
   (`+latesoftcallskip`). Soft PopUp planted fps / lite Soft Cmp **green**
   (`+popupsoftfp`). Soft PopUp Soft Win + planted fps join Soft Cmp+Call **green**
   (`+popupsoftwinfp+popupsoftwinfpcall`). Next tip: Soft PopUp Fp Soft Call, or
   unhang late Soft Call wave / Soft PopUp/DocTerm Guest-gate drop after MenuNewCmpCtrl Soft Call.
2. Finish G9 residual: RedSea probe `A:/Kernel/Kernel.BIN` FileFind+Load+`KernelEntry`
   handoff **landed** (host `pack_tosb` seed; Runtime prefers seed; `make kernel-thin-loader-smoke`
   proves mount→Load→Call without Cmp); **reloc heap Load** of virtio RedSea `Compiler.BIN`
   landed; default ELF `.compiler_bin` **dropped**. SoftCall **ExeSoft** landed
   (RedSea `LoadProbe`→HashFind→Call→`'KB'`; ExeFile-shaped, no Cmp). SoftCall
   **MakeSoft** landed (product `A:/MakeOS/Tiny.BIN`→`MakeOSProbe=42`→`'KN'`;
   StartOS-shaped product Load). SoftCall **SeedSoft** landed (product
   `A:/Runtime/Seed.BIN`→`RuntimeSeedInit=42`→`'KR'`; StartOS Seed tip; F()+imm). SoftCall
   **SvcSoft** landed (product `A:/Runtime/Svc.BIN`→`RuntimeSvcProbe=42`→`'KC'`; F()→F()). SoftCall
   **KernSoft** landed (product `A:/Runtime/Kern.BIN`→`KernInit=42`→`'KK'`; arg+call+add).
   SoftCall **StartSoft** landed (Seed→Svc→Kern multi-BIN→`'KU'`; StartOS-shaped sequence).
   SoftCall **AdamSoft** landed (product `A:/Adam/StartOS.BIN`→`StartOSProbe=1`→`'KA'`;
   phase3 StartOS Load→Call needle; no DocTerm/Menu). SoftCall **DateSoft** landed
   (KDate YearStartDate/Struct2Date↔Date2Struct + Goldfish RTC Now→`'KG'`; past
   `KThinDateStubs`; packs Kernel_RV KDate shape into RedSea Kernel.BIN). SoftCall
   **QSortSoft** landed (QSortI64 ascending+sorted+singleton→`'KO'`; past
   `KThinQSortStubs`; packs Kernel_RV QSort.HC I64/DirEntry shape into RedSea
   Kernel.BIN; `'KQ'` remains TrapIRQ).    SoftCall **KeyDevSoft** landed (PutKey/PutS
   priority chain + KeyDevRem + CtrlAltCBSet lite→`'KW'`; past `KThinKeyDevStubs`;
   packs Kernel_RV KeyDev.HC StdOut shape into RedSea Kernel.BIN; no SCROLL Yield/
   KDRaw/Msg).    SoftCall **ExceptSoft** landed (SysTry/SysUntry queue + throw walk +
   PutExcept catch flag→`'KZ'`; past thin PutExcept stub; packs Kernel_RV KExcept.HC
   try/throw/catch HolyC shape into RedSea Kernel.BIN; no x86 TestExcept/TakeExcept
   asm unwind). SoftCall **MemSoft** landed (HeapCtrl hash-bucket Free→reuse +
   MSize + CAlloc + StrNew→`'KH'`; past `KThinMemStubs`; packs Kernel_RV
   HeapCtrl/MAllocFree HolyC shape into RedSea Kernel.BIN; no MemPag/PageTables/
   BlkPool/x86 `_MALLOC`).    SoftCall **StrUtilSoft** landed (path-normalize
   SUF_REM_LEADING|TRAILING|CTRL_CHARS + TO_UPPER/TO_LOWER/REM_SPACES/SINGLE_SPACE
   + MStrUtil copy-out→`'SU'`; past `KThinStrUtilStubs`; packs Kernel_RV StrA/StrB
   HolyC shape into RedSea Kernel.BIN; no Spaces2Tabs/T2S/ScaleIndent/char_bmp). SoftCall
   **FifoSoft** landed (FifoU8/I64 New/Ins/Rem/Peek/Flush/Cnt/Del→`'SF'`; past MapFat
   Fifo stubs; Serial MakeSerialDev gated empty — InputFilterTask wall kept; packs
   Kernel_RV KDataTypes.HC Fifo HolyC shape into RedSea Kernel.BIN; no x86 PUSHFD/CLI).
   SoftCall **QueVectSoft** landed (QueVectU8 New/Put/Get/Del + multi-node grow +
   min_idx→`'QV'`; past MapFat QueVect stubs; SoftCall-local CNT=8, stock algorithm;
   packs Kernel_RV KDataTypes.HC QueVect HolyC shape into RedSea Kernel.BIN; Lex needs
   QueVect).    SoftCall **RandSoft** landed (Seed(n) nontimer LCG + RandI16/U16/I32/U32/I64/U64
   →`'RN'`; past MapFat Rand* stubs; SoftCall-local seed — no Fs/GetTSC; Seed(0) soft-tick
   xor; F64 Rand() deferred; packs Kernel_RV KMathB.HC Rand HolyC shape into RedSea
   Kernel.BIN).    SoftCall **ScanFlagsSoft** landed (LstMatch exact + ScanFlags +/- bit
   set/clear + StrPrintFlags reverse→`'SC'`; past MapFat ScanFlags/StrPrintFlags stubs;
   SoftCall-lite stack buf — no MAlloc; unknown flag returns FALSE — no throw;
   LMF_IGNORE_CASE/ambiguous deferred; packs Kernel_RV StrA/StrB ScanFlags HolyC shape
   into RedSea Kernel.BIN). SoftCall **CompressSoft** landed (CompressBuf/ExpandBuf
   Arc roundtrip→`'CM'`; past thin Compress gate; SoftCall-local ARC_BITS=9 — stock 12
   ~96 KiB BSS won't fit SoftCall; HolyC BFieldOr/Ext — no asm; no throw; packs
   Kernel_RV Compress.HC Arc HolyC shape into RedSea Kernel.BIN). SoftCall
   **KLoadSoft** landed (LoadPass1 IMM32_EXPORT + IET_IMM_I64 LoadOneImport resolve
   + IET_ABS_ADDR U64+=module_base→`'LD'`; past JumpSoft/ExeSoft export-only;
   SoftCall-lite synthetic patch table — import group stops before ABS/MAIN; no
   FileRead/ExtDft/CODE_HEAP/DATA_HEAP/MAIN Call; no throw; packs Kernel_RV
   KLoad.HC LoadPass1 HolyC shape into RedSea Kernel.BIN). SoftCall
   **MakeMemSoft** landed (BlkPoolInit/Add + MemPagAlloc/Free + MemPagTaskAlloc/Free
   →`'MM'`; past `KThinMemStubs` MemPag/BlkPool NULLs; MemSoft already owns HeapCtrl;
   FREE_PAG_HASH=0x100 stock-sized free_pag_hash + mid-slot[16] prove; Hash2Soft owns
   free_pag_hash2 SoftCall-lite; no CLI/LBts;
   PhysMemSoft owns PageTables/MemPhysical/BlkPoolsInit lite; packs Kernel_RV
   MemPag/BlkPool HolyC shape into RedSea Kernel.BIN). SoftCall **PhysMemSoft**
   landed (BlkPoolsInit synthetic E820→extend code_bp+data_bp + MemPageTable PTE
   slot + Mem32DevIns/Init/Alloc/Free + BIOSTotalMem + Scale2Mem→`'PM'`; past
   MakeMemSoft; SoftCall-local PTE[16] — no x86 SYS_INIT_PAGE_TABLES asm / Sv39;
   no Mem64Dev/UncachedAlias/InvlPg; no real BIOS E820; no CLI/LBts; packs
   Kernel_RV BlkPoolsInit+MemPageTable+MemPhysical HolyC shape into RedSea
   Kernel.BIN). SoftCall **LoadMainSoft** landed (IET_CODE_HEAP ArenaAlloc+I32
   patch+HashAdd + LoadPass2 IET_MAIN Call + FileRead SOFTFW.OK→CODE_HEAP
   LoadPass1→`'LM'`; past KLoadSoft import+ABS; SoftCall-lite — DataHeapSoft owns
   ExtDft.Z / DATA_HEAP / ZEROED_*; A:/Kernel/ CDir full (8 slots) so no new FileWrite;
   packs Kernel_RV KLoad.HC CODE_HEAP+MAIN+FileRead HolyC shape into RedSea
   Kernel.BIN). SoftCall **Hash2Soft** landed (MemPag free_pag_hash2 Bsr round
   power-of-two + EXTRA_HASH2_PAGS=2 Free→hash2→Alloc reuse→`'H2'`; past
   MakeMemSoft stock FREE_PAG_HASH=0x100; FREE_PAG_HASH2=55 stock 64-MEM_PAG_BITS;
   SoftCall-local HASH2_FREE_PAG_HASH=8 threshold — stock 0x100 hash2 trigger needs
   ≥130-pag arena (~65 KiB) deferred w/ ARC_BITS=12; no CLI/LBts;
   packs Kernel_RV MemPag.HC free_pag_hash2 HolyC shape into RedSea Kernel.BIN).
   SoftCall **DataHeapSoft** landed (IET_DATA_HEAP ArenaAlloc+I64 patch+HashAdd +
   ZEROED_CODE/DATA_HEAP CAlloc MemSet + ExtDft.Z stack dft→`'DH'`; past LoadMainSoft
   CODE_HEAP+MAIN; SoftCall-lite — no MAlloc ExtDft/CatPrint; identity ExtDft of
   SOFTFW.OK→FileRead Load shape; A:/Kernel/ CDir full so no new FileWrite;
   LoadAbsSoft owns full Load() FileNameAbs+align; packs Kernel_RV KLoad.HC
   DATA_HEAP+ZEROED_* + DskStrA ExtDft HolyC shape into RedSea Kernel.BIN). SoftCall
   **LoadAbsSoft** landed (FileNameAbs drive-abs+cur_dir join + FileExtRem +
   HTT_MODULE HashGenericAdd `fbuf+2` leading `/` + MAllocAligned
   module_align_bits min-16 + LoadPass copy/Pass1 + ExtDft+FileNameAbs+FileRead
   LoadProbe→aligned LoadPass+MODULE+export Find→`'LA'`; past DataHeapSoft ExtDft.Z;
   SoftCall-lite — no throw; DirAbsSoft owns FUF_Z_OR_NOT_Z/DirNameAbs parents/MAlloc
   ExtDft; no MAllocAligned
   back-ptr into ArenaAlloc; **SynAlign.BIN composed** (`A:/Kernel/`+`SynAlign`+`.BIN`
   chars — host AOT can drop `.` from dotted path literals; historical SoftCall
   `code=-30` / SoftCall `r=-55`); packs Kernel_RV KLoad.HC Load()+LoadPass
   FileNameAbs/align/MODULE + DskStrA FileNameAbs HolyC shape into RedSea Kernel.BIN;
   **thin SoftCall stay + phase3 SoftCall gate green** w/ DataHeapSoft/MakeMemSoft/Hash2Soft). SoftCall
   **DirAbsSoft** landed (DirNameAbs `..`/`.` parents + FileNameAbs-via-DirNameAbs +
   ToggleZorNotZ + FileFind Z-or-not-Z alt + ArenaAlloc ExtDft→`'DN'`; past LoadAbsSoft;
   SoftCall-lite — no ~ home / FUF_SCAN_PARENTS Cd walk; no throw; packs Kernel_RV
   DskStrA DirNameAbs/FileNameAbs/ExtDft + DskFind ToggleZ HolyC shape into RedSea
   Kernel.BIN). SoftCall **StartOSSoft** landed (DirAbs-resolve
   `A:/Kernel/../Adam/StartOS.BIN` → AdamSoft StartOSProbe=1 → StartSoft Seed→Svc→Kern
   →`'SO'`; past DirAbsSoft; **StartOS Load without Mac `phase3.elf` Cmp scaffold** —
   product BINs only; no guest Cmp / DocTerm/Menu; packs phase3 StartOS Load ownership into
   thin SoftCall). SoftCall **ExePutSSoft** landed (CmpCtrl New/buf_ptr + LexGetChar +
   I64 +/- ExePutS `"40+2;"`→42 →`'EP'`; past StartOSSoft; SoftCall-lite — no LexStmt2Bin/
   Prs/Opt/emit/fun-def; packs Compiler CMain ExePutS + Lex CmpCtrl HolyC shape SoftCall-lite
   into RedSea Kernel.BIN). SoftCall **CmpSoft** landed (SoftCall-compose TOSB `li a0,42;ret`
   + REL64 `CmpSoftProbe` → FileWrite `A:/MakeOS/SoftCmp.BIN` → Load+HashFind+Call→42 →`'CC'`;
   past ExePutSSoft; SoftCall-lite hand-emit MakeOS CmpWrite — no Compiler_RV; shrinks phase3
   MakeOS Cmp scaffold toward thin SoftCall). SoftCall **LexStmtSoft** landed (CmpCtrl Lex I64 +/- →
   emit RV `addi a0` + `ret` into BSS → FenceI → Call `"40+2;"`→42 →`'LB'`; past CmpSoft;
   SoftCall-lite LexStmt2Bin/emit — no PrsStmt/OptPass/COC/fun-def; packs Compiler CMain
   LexStmt2Bin JIT HolyC shape SoftCall-lite into RedSea Kernel.BIN). SoftCall **PrsOptSoft** landed
   (PrsExpr I64 +-* RPN IC → OptPass constant-fold → emit RV `addi a0` + `ret` → FenceI → Call
   `"6*7;"`→42 / `"2+5*8;"`→42 →`'PO'`; past LexStmtSoft; SoftCall-lite — no PrsStmt/OptPass012/
   COC/fun-def; paren+IC-beyond-fold owned by ParenSoft; keeps LexStmtSoft/ExePutSSoft green;
   packs Compiler Prs/Opt tip SoftCall-lite into RedSea Kernel.BIN). SoftCall **ParenSoft** landed
   (PrsFactor `'(' Expr ')'` + EmitIC RPN→RV `addi`/`add`/`sub`/`mul` without OptPass fold →
   FenceI → Call `"(2+5)*8;"`→56 / `"2+(5*8);"`→42 →`'PN'`; past PrsOptSoft; SoftCall-lite —
   no fun-def/PrsStmt/COC/full Compiler.BIN Load; keeps PrsOptSoft/LexStmtSoft/ExePutSSoft green;
   packs Compiler PrsFactor paren + IC emit SoftCall-lite into RedSea Kernel.BIN). SoftCall
   **IdentSoft** landed (LexIdent + soft local plant + `IC_LOCAL` in PrsFactor → OptPass fold +
   EmitIC `addi` → FenceI → Call `"x+2;"`/`"x+y;"`→42 with `x=40`,`y=2` planted →`'ID'`; past
   ParenSoft; SoftCall-lite — no fun-def/COC/full Compiler.BIN Load; AssignSoft owns
   PrsStmt assign; keeps ParenSoft/PrsOptSoft/LexStmtSoft/ExePutSSoft green; packs Compiler
   local/ident IC tip SoftCall-lite into RedSea Kernel.BIN). SoftCall
   **AssignSoft** landed (PrsStmt assign fragment: `ident=Expr;`* `Expr;` plants locals from
   source → OptPass fold + EmitIC → FenceI → Call `"x=40;x+2;"`/`"x=40;y=2;x+y;"`→42 →`'AS'`;
   past IdentSoft; SoftCall-lite — no fun-def/COC/full Compiler.BIN Load; FunDefSoft owns
   fun-def tip; keeps IdentSoft/ParenSoft/PrsOptSoft/LexStmtSoft/ExePutSSoft green; packs
   Compiler PrsStmt assign tip SoftCall-lite into RedSea Kernel.BIN). SoftCall
   **FunDefSoft** landed (fun-def SoftCall-lite: `I64 name(){return Expr;}` + `name();` →
   OptPass fold + EmitIC → FenceI → Call `"I64 F(){return 40+2;}F();"`/`"I64 F(){return 6*7;}F();"`→42
   →`'FD'`; past AssignSoft; SoftCall-lite — FunBodySoft owns args/locals-in-fun/multi-stmt; FunCallSoft
   owns multi-arg/call-Expr; no COC/full Compiler.BIN Load; keeps AssignSoft/IdentSoft/ParenSoft/PrsOptSoft/LexStmtSoft/
   ExePutSSoft green; packs Compiler PrsFun + return + Call tip SoftCall-lite into RedSea
   Kernel.BIN).    SoftCall **FunBodySoft** landed (multi-stmt + locals-in-fun + SoftCall-lite
   single I64 arg plant-at-call LexI64 — no ABI/a0: `"I64 F(){x=40;return x+2;}F();"` /
   `"I64 F(I64 a){return a+2;}F(40);"`→42 fold+IC emit →`'FB'`; past FunDefSoft; SoftCall-lite —
   FunCallSoft owns multi-arg/call-Expr; AbiSoft owns ABI/a0 frame; no COC/full Compiler.BIN Load; keeps FunDefSoft/AssignSoft
   green; packs Compiler PrsFun body + arg tip SoftCall-lite into RedSea Kernel.BIN).    SoftCall
   **FunCallSoft** landed (multi-arg + call-Expr plant-at-call SoftCall-lite — temp IC fold so body
   IC preserved; AbiSoft owns ABI/a0 frame: `"I64 F(I64 a,I64 b){return a+b;}F(40,2);"` /
   `"I64 F(I64 a){return a+2;}F(38+2);"`→42 fold+IC emit →`'FC'`; past FunBodySoft; SoftCall-lite —
   no COC / full Compiler.BIN Load; keeps FunBodySoft/FunDefSoft green;
   packs Compiler PrsFun multi-arg + call Expr tip SoftCall-lite into RedSea Kernel.BIN). SoftCall
   **AbiSoft** landed (ABI / runtime local stores a0 frame SoftCall-lite — prologue `sd a0/a1,0/8(sp)`
   + body `ld` from frame + HolyC `fp(arg)` Call so a0 arrives at runtime; no plant-at-call:
   `"I64 F(I64 a){return a+2;}F(40);"` / `"I64 F(I64 a,I64 b){return a+b;}F(38+2,6-4);"` /
   `"I64 F(I64 a){x=2;return a+x;}F(40);"`→42 IC emit →`'AB'`; past FunCallSoft; SoftCall-lite —
   CocSoft owns COC multi-stmt emit; keeps FunCallSoft/FunBodySoft green; packs Compiler PrsFun
   ABI frame tip SoftCall-lite into RedSea Kernel.BIN). SoftCall **CocSoft** landed (COC multi-stmt
   emit SoftCall-lite — ASSIGN IC → runtime `sd` + LOCAL `ld` from frame, not SoftCall plant-fold:
   `"I64 F(){x=40;return x+2;}F();"` / `"I64 F(){x=40;x=x+2;return x;}F();"` /
   `"I64 F(I64 a){x=a+2;return x;}F(40);"`→42 COC emit →`'CO'`; past AbiSoft; SoftCall-lite —
   BrSoft owns if/while BR; keeps AbiSoft/FunCallSoft/FunBodySoft green; packs
   Compiler COCCompile multi-stmt tip SoftCall-lite into RedSea Kernel.BIN).    SoftCall
   **BrSoft** landed (if/while BR SoftCall-lite — `BR_ZERO`/`JMP`/`LABEL` ICs → runtime
   taken/not-taken paths, not SoftCall plant-fold of body:
   `"I64 F(){x=0;if(1)x=42;return x;}F();"` / `"I64 F(){x=42;if(0)x=0;return x;}F();"` /
   `"I64 F(){x=40;while(x-42)x=x+1;return x;}F();"`→42 BR emit →`'BR'`; past CocSoft; SoftCall-lite —
   ElseSoft owns else; keeps CocSoft/AbiSoft/FunCallSoft/FunBodySoft green; packs
   Compiler PrsStmt if/while BR tip SoftCall-lite into RedSea Kernel.BIN).    SoftCall
   **ElseSoft** landed (if/else SoftCall-lite — then `JMP` join + else `LABEL`/`ASSIGN` +
   join `LABEL` → runtime taken then vs else, not SoftCall plant-fold:
   `"I64 F(){x=0;if(1)x=42;else x=0;return x;}F();"` /
   `"I64 F(){x=0;if(0)x=0;else x=42;return x;}F();"`→42 else emit →`'EL'`; past BrSoft;
   SoftCall-lite — ForSoft owns for; keeps BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft
   green; packs Compiler PrsIf else tip SoftCall-lite into RedSea Kernel.BIN). SoftCall
   **ForSoft** landed (for SoftCall-lite — init/cond/step + body `ASSIGN` → `LABEL`/`BR_ZERO`/`JMP`
   runtime loop, not SoftCall plant-fold:
   `"I64 F(){for(x=40;x-42;x=x+1)y=0;return x;}F();"`→42 for emit →`'FR'`; past ElseSoft;
   SoftCall-lite — CmpBrSoft owns relational cmp-BR; keeps ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft
   green; packs Compiler PrsFor tip SoftCall-lite into RedSea Kernel.BIN). SoftCall
   **CmpBrSoft** landed (relational cmp → BR SoftCall-lite — `<`/`>`/`<=`/`>=`/`==`/`!=` IC →
   0/1 + `BR_ZERO` runtime taken/not-taken, not SoftCall plant-fold / truthy-only:
   `"I64 F(){x=0;if(x<1)x=42;return x;}F();"` /
   `"I64 F(){x=42;if(x<1)x=0;return x;}F();"` /
   `"I64 F(){for(x=0;x<6;x=x+1)y=0;return x*7;}F();"`→42 cmp-BR emit →`'CB'`; past ForSoft;
   SoftCall-lite — CmpSrcSoft owns multi-fun slice Load; keeps ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft
   green; packs Compiler PrsExpr relational tip SoftCall-lite into RedSea Kernel.BIN). SoftCall
   **CmpSrcSoft** landed (host-AOT multi-fun compound slice SoftCall Load — SoftCmpSrcF+SoftCmpSrcG
   → SoftCmpSrcProbe→42; SoftCmpSrc.BIN 1328 B ≤ SoftCall Load 2 KiB; not SoftCall-lite multi-fun Lex —
   SoftCall-lite PrsCmpSrc hung ExePutSSoft via host AOT 32 B entry thunk / PCrel miss to KernelUart:
   SoftCall Load SoftCmpSrc.BIN SoftCmpSrcProbe →`'CS'`; past CmpBrSoft; SoftCall-lite — PrsSrcSoft owns
   larger Prs SoftCall Load; keeps
   CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`
   green; packs multi-fun host-AOT slice SoftCall Load into RedSea toward drop phase3.elf). SoftCall
   **PrsSrcSoft** landed (host-AOT Prs-shaped glbl+multi-fun fold SoftCall Load — SoftPrsAdd/SoftPrsMul
   + soft_prs_x → SoftPrsFold→ SoftPrsSrcProbe→42; SoftPrsSrc.BIN 1904 B ≤ SoftCall Load 2 KiB;
   Lex digit SoftCall Load ~2.7 KiB over cap; SoftCall-lite PrsCmpSrc hung ExePutSSoft:
   SoftCall Load SoftPrsSrc.BIN SoftPrsSrcProbe →`'PR'`; past CmpSrcSoft; SoftCall-lite — LexSrcSoft owns
   LexStmt2Bin SoftCall Load; keeps
   CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`
   green; packs Prs fold host-AOT slice SoftCall Load into RedSea toward drop phase3.elf). SoftCall
   **LexSrcSoft** landed (host-AOT LexStmt2Bin-shaped digit+op peel SoftCall Load — SoftLexStmt2Bin
   + SoftLexStmt2BinCall → SoftLexSrcProbe→42; SoftLexSrc.BIN 2000 B ≤ SoftCall Load 2 KiB;
   while digit SoftCall Load ~2.7 KiB over cap, shrunk fixed peel:
   SoftCall Load SoftLexSrc.BIN SoftLexSrcProbe →`'LX'`; past PrsSrcSoft; SoftCall-lite — IcSrcSoft owns
   IC plant+emit SoftCall Load; keeps
   PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`
   green; packs LexStmt2Bin host-AOT slice SoftCall Load into RedSea toward drop phase3.elf). SoftCall
   **IcSrcSoft** landed (host-AOT IC plant+emit SoftCall Load beyond Lex peel — SoftIcEmit IMM40/IMM2/ADD
   plant → RV addi/addi/add/ret + FenceI + Call → SoftIcSrcProbe→42; SoftIcSrc.BIN 2016 B ≤ SoftCall Load 2 KiB;
   host AOT `<<20` bit-pack SoftCall Load over cap, SoftCall tip fixed encodings:
   SoftCall Load SoftIcSrc.BIN SoftIcSrcProbe →`'IC'`; past LexSrcSoft; SoftCall-lite — MulSrcSoft owns
   MUL IC SoftCall Load; keeps
   LexSrcSoft/PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`/`'LX'`
   green; packs IC plant+emit host-AOT slice SoftCall Load into RedSea toward drop phase3.elf). SoftCall
   **MulSrcSoft** landed (host-AOT MUL IC plant+emit SoftCall Load beyond IMM/ADD SoftIcSrc — SoftMulEmit
   IMM6/IMM7/MUL plant → RV addi/addi/mul/ret + FenceI + Call → SoftMulSrcProbe→42; SoftMulSrc.BIN 2016 B ≤ SoftCall Load 2 KiB;
   MUL+SUB SoftCall Load over cap (SUB own Load); host AOT `<<20` bit-pack SoftCall Load over cap, SoftCall tip fixed encodings:
   SoftCall Load SoftMulSrc.BIN SoftMulSrcProbe →`'MU'`; past IcSrcSoft; SoftCall-lite — SubSrcSoft owns
   SUB IC SoftCall Load; keeps
   IcSrcSoft/LexSrcSoft/PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`/`'LX'`/`'IC'`
   green; packs MUL IC plant+emit host-AOT slice SoftCall Load into RedSea toward drop phase3.elf). SoftCall
   **SubSrcSoft** landed (host-AOT SUB IC plant+emit SoftCall Load beyond IMM/MUL SoftMulSrc — SoftSubEmit
   IMM44/IMM2/SUB plant → RV addi/addi/sub/ret + FenceI + Call → SoftSubSrcProbe→42; SoftSubSrc.BIN 2016 B ≤ SoftCall Load 2 KiB;
   MUL+SUB one SoftCall Load BIN over cap (own Load slice); host AOT `<<20` bit-pack SoftCall Load over cap, SoftCall tip fixed encodings:
   SoftCall Load SoftSubSrc.BIN SoftSubSrcProbe →`'SB'`; past MulSrcSoft; SoftCall multi-blk
   RedSea FileFind/FileWrite (`.` size) unblocks MakeOS past 6 Soft*.BIN+Tiny (CmpSoft SoftCmp.BIN
   FileWrite); SoftCall-lite — OptSrcSoft owns OptPass fold SoftCall Load; keeps
   MulSrcSoft/IcSrcSoft/LexSrcSoft/PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`/`'LX'`/`'IC'`/`'MU'`
   green; packs SUB IC plant+emit host-AOT slice SoftCall Load into RedSea toward drop phase3.elf). SoftCall
   **OptSrcSoft** landed (host-AOT OptPass fold SoftCall Load beyond IMM/SUB SoftSubSrc — SoftOptFoldEmit
   IMM6/IMM7/MUL plant → fold IMM42 → RV addi+ret + FenceI + Call → SoftOptSrcProbe→42; SoftOptSrc.BIN 1904 B ≤ SoftCall Load 2 KiB;
   SoftCall tip fixed encodings (not SoftMulSrc mul emit):
   SoftCall Load SoftOptSrc.BIN SoftOptSrcProbe →`'OP'`; past SubSrcSoft; SoftCall-lite — CocSrcSoft owns
   COC SoftCall Load; keeps
   SubSrcSoft/MulSrcSoft/IcSrcSoft/LexSrcSoft/PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`/`'LX'`/`'IC'`/`'MU'`/`'SB'`
   green; packs OptPass fold host-AOT slice SoftCall Load into RedSea toward drop phase3.elf). SoftCall
   **CocSrcSoft** landed (host-AOT COC multi-stmt ASSIGN SoftCall Load beyond OptPass fold SoftOptSrc —
   SoftCocEmit IMM/ASSIGN plant → RV addi+sd+ld+ret + FenceI + Call → tip return Expr +2 → SoftCocSrcProbe→42;
   SoftCocSrc.BIN 2048 B ≤ SoftCall Load 2 KiB; full frame SoftCall Load over cap, SoftCall tip SoftIcSrc-sized
   4-word encodings + tip +2 wrap (not SoftOptSrc fold-to-imm):
   SoftCall Load SoftCocSrc.BIN SoftCocSrcProbe →`'OC'`; past OptSrcSoft; SoftCall-lite — BrSrcSoft owns
   BR SoftCall Load; keeps
   OptSrcSoft/SubSrcSoft/MulSrcSoft/IcSrcSoft/LexSrcSoft/PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`/`'LX'`/`'IC'`/`'MU'`/`'SB'`/`'OP'`
   green; packs COC ASSIGN host-AOT slice SoftCall Load into RedSea toward drop phase3.elf). SoftCall
   **BrSrcSoft** landed (host-AOT BR SoftCall Load beyond COC ASSIGN SoftCocSrc —
   SoftBrEmit IMM/BR_ZERO plant → RV addi+beqz+addi+ret + FenceI + Call → tip return Expr +2 → SoftBrSrcProbe→42;
   SoftBrSrc.BIN 2032 B ≤ SoftCall Load 2 KiB; SoftCall tip SoftIcSrc-sized 4-word encodings + tip +2 wrap
   (not SoftCocSrc sd/ld; SoftCall-lite `'BR'` remains BrSoft — Load needle `'BS'`):
   SoftCall Load SoftBrSrc.BIN SoftBrSrcProbe →`'BS'`; past CocSrcSoft; SoftCall-lite — SoftElseSrc SoftCall Load
   owns next; keeps
   CocSrcSoft/OptSrcSoft/SubSrcSoft/MulSrcSoft/IcSrcSoft/LexSrcSoft/PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`/`'LX'`/`'IC'`/`'MU'`/`'SB'`/`'OP'`/`'OC'`
   green; packs BR SoftCall Load host-AOT slice into RedSea toward drop phase3.elf). SoftCall
   **ElseSrcSoft** landed (host-AOT if/else JMP join SoftCall Load beyond BR SoftBrSrc —
   SoftElseEmit IMM/BR_ZERO/JMP plant → RV addi+beqz+SoftCall-lite JMP+addi42+ret + FenceI + Call → SoftElseSrcProbe→42;
   SoftElseSrc.BIN 2032 B ≤ SoftCall Load 2 KiB; SoftCocSrc tip wrap SoftOptSrc addi42 (SoftCall-lite JMP=`beq x0,x0`;
   SoftCall-lite `'EL'` remains ElseSoft — Load needle `'ES'`):
   SoftCall Load SoftElseSrc.BIN SoftElseSrcProbe →`'ES'`; past BrSrcSoft; SoftCall-lite — SoftForSrc SoftCall Load
   or thunk-safe SoftCall-lite glbl+fun / inter-fun CALL own next; keeps
   BrSrcSoft/CocSrcSoft/OptSrcSoft/SubSrcSoft/MulSrcSoft/IcSrcSoft/LexSrcSoft/PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`/`'LX'`/`'IC'`/`'MU'`/`'SB'`/`'OP'`/`'OC'`/`'BS'`
   green; packs if/else JMP SoftCall Load host-AOT slice into RedSea toward drop phase3.elf). SoftCall
   **ForSrcSoft** landed (host-AOT for-loop SoftCall Load beyond if/else SoftElseSrc —
   SoftForEmit IMM/COND/BR_ZERO/STEP/JMP-back IC slot plant → RV addi40+addi t0,-42+beqz+addi1+JMP back+ret
   + FenceI + Call → runtime count 40→42 → SoftForSrcProbe→42;
   SoftForSrc.BIN 2032 B ≤ SoftCall Load 2 KiB; const-folded IC slot indices keep the tip inside
   the 2 KiB cap — an extra `ic` compare pushes the slice to 2064 B (SoftCall-lite `'FR'` remains
   ForSoft — Load needle `'FS'`):
   SoftCall Load SoftForSrc.BIN SoftForSrcProbe →`'FS'`; past ElseSrcSoft; SoftCall-lite — thunk-safe
   SoftCall-lite **glbl+fun** / **inter-fun CALL IC** own next; keeps
   ElseSrcSoft/BrSrcSoft/CocSrcSoft/OptSrcSoft/SubSrcSoft/MulSrcSoft/IcSrcSoft/LexSrcSoft/PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`/`'LX'`/`'IC'`/`'MU'`/`'SB'`/`'OP'`/`'OC'`/`'BS'`/`'ES'`
   green; packs for-loop SoftCall Load host-AOT slice into RedSea toward drop phase3.elf). SoftCall
   **CallIcSoft** landed (**thunk-safe SoftCall-lite inter-fun CALL IC** past ForSrcSoft `'FS'` — the
   first tip past `'FS'` that is SoftCall-**lite** again, not a Load slice: `KernelPrsCallFunDefSoft`
   parses `(I64 name(){return Expr;})+ name();` and plants each def before the next one parses, so a
   later body naming an earlier fun emits a real RV `jal ra` (`KERNEL_IC_CALL` → `KernelEmitJalSoft`
   J-type) under a ra frame (`KernelEmitCallICSoft`: `addi sp,-16`/`sd ra`/…/`ld ra`/`addi sp,16`/`ret`)
   — **not** a plant-time fold: `KernelOptPassSoft` rejects `IC_CALL`, so the CALL cannot fold.
   `"I64 G(){return 40;}I64 F(){return G()+2;}F();"` / `G()*7` / `G()-2` →42 →`'CL'`, plus the
   single-def `"I64 F(){return 40+2;}F();"` shape to prove `IC_CALL` is additive to the lite Prs tip.
   `IC_CALL` is **leftmost-only** (a real `jal` clobbers a0..a7, so the lite RPN reg stack must be
   empty — `2+G()` is rejected, `G()+2` is not).
   **Host AOT entry-thunk budget held**: Kernel.BIN 450208 → **456960** B (+6752) and ExePutSSoft
   `'EP'` stayed green, so the SoftCall-lite growth that hung `'EP'` at PrsCmpSrc did **not** recur —
   no ≤2 KiB Load-slice fallback was needed. RedSea stays **18 files** (no new BIN).
   Needle `'CL'` (0x434C); past ForSrcSoft; SoftCall-lite — **glbl memory**
   (`lui`/`addi` abs + `ld`/`sd`) landed on top of it as `'GM'`; keeps
   ForSrcSoft/ElseSrcSoft/BrSrcSoft/CocSrcSoft/OptSrcSoft/SubSrcSoft/MulSrcSoft/IcSrcSoft/LexSrcSoft/PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'EP'`/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`/`'LX'`/`'IC'`/`'MU'`/`'SB'`/`'OP'`/`'OC'`/`'BS'`/`'ES'`/`'FS'`
   green; packs the Compiler `PrsCall`/`ICCall` tip SoftCall-lite into RedSea Kernel.BIN toward drop phase3.elf). SoftCall
   **GlblMemSoft** landed (**SoftCall-lite glbl memory** past CallIcSoft `'CL'` — the second
   consecutive SoftCall-**lite** tip past `'FS'`, again no Load slice, and the **last lite-Cmp
   primitive** that was missing: `KernelPrsGlblFunDefSoft` parses
   `(I64 g;)* (I64 name(){ (g=Expr;)* return Expr; })+ name();`. Each `I64 g;` plants real
   Kernel.BIN storage (`kernel_soft_glbls[slot].val`) and hands the emitter its **address**, never
   its value; `KERNEL_IC_GLBL` / `KERNEL_IC_GLBL_ASSIGN` materialize that absolute address in the
   emitted code via `KernelEmitAbsAddrSoft` and then `ld`/`sd` through it — `lui`+`addi`, plus
   `slli`/`srli 32` to drop the `lui` sign fill, because the thin embed lands Kernel.BIN at
   `0x81000000` and RV64 `lui` sign-extends `imm20<<12` (so the 16 B zero-extend form is the one
   actually exercised, not the 8 B one). `KernelEmitICBodySoft` pass 0 sizes the sequence from the
   address so label offsets stay exact; `GLBL_ASSIGN` parks the address in **t0**, which is never
   part of the a0..a7 lite RPN stack. **Not** a plant-time fold, proven three ways:
   `KernelOptPassSoft` rejects `IC_GLBL`/`IC_GLBL_ASSIGN` (default `else` → no-fold), so the glbl
   can never be constant-folded; `"I64 g;I64 G(){g=40;return 0;}I64 F(){return G()+g+2;}F();"` →42
   makes **G's store outlive its frame** and be loaded by **F** after the `jal ra` returns; and
   HolyC reads the same storage back (`kernel_soft_glbls[0].val == 40` / `== 42`) after each call,
   which is only possible if the emitted `sd` hit real RAM. Also green:
   `"I64 g;I64 F(){g=40;return g+2;}F();"`, two-glbl `"I64 g;I64 h;…g+h"` (distinct addresses),
   read-modify-write `"I64 g;I64 F(){g=6;g=g*7;return g;}F();"` (second `ld` must see the first
   `sd`), and the no-glbl `"I64 F(){return 40+2;}F();"` shape proving glbl memory is additive.
   `PrsFactor` only reaches the glbl table **after** `LocalFind` misses, so every earlier
   SoftCall-lite tip keeps its exact behaviour.
   **Host AOT entry-thunk budget held again**: Kernel.BIN 456960 → **468000** B (+11040) and
   ExePutSSoft `'EP'` stayed green, so no ≤2 KiB Load-slice fallback was needed. RedSea stays
   **18 files** (no new BIN).
   Needle `'GM'` (0x474D); past CallIcSoft; SoftCall-lite — **glbl+fun are now both real**, so the
   next tip is the first **real guest Cmp attempt without Mac `phase3.elf`**; keeps
   CallIcSoft/ForSrcSoft/ElseSrcSoft/BrSrcSoft/CocSrcSoft/OptSrcSoft/SubSrcSoft/MulSrcSoft/IcSrcSoft/LexSrcSoft/PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'EP'`/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`/`'LX'`/`'IC'`/`'MU'`/`'SB'`/`'OP'`/`'OC'`/`'BS'`/`'ES'`/`'FS'`/`'CL'`
   green; packs the Compiler `CHashGlblVar`/`ICGlbl` tip SoftCall-lite into RedSea Kernel.BIN toward drop phase3.elf). SoftCall
   **GuestCmpSoft** landed (**first real guest Cmp** past GlblMemSoft `'GM'` — the tip where the
   source being compiled stops being a string baked into Kernel.BIN. `A:/Compiler/SoftGlbl.HC`
   is Compiler_RV-shaped HolyC (doc header, `I64 g_rv_asm_exports;` / `g_rv_asm_pass` /
   `g_rv_asm_errs` decls, three fun defs and a trailing `RvAsmExportsSum();`) seeded onto the
   RedSea image and **nowhere else**. At runtime Kernel.BIN `FileFind`s it, `KernelSrcRead` walks
   its clus run **multi-blk** (851 B = two sectors — `KernelFileRead` stops at one sector, and
   `KernelLoad` would reject it for having no `CBinFile` signature), the lite Lex skips the `//`
   header, `KernelPrsGlblFunDefSoft` Cmps the glbl decls + fun defs, and the emitted code is
   Called →42. `Sum`→`Add`→`Init` is a genuine **three-deep `jal ra` chain** whose glbl stores
   cross both returns, so the value only survives because `IC_GLBL_ASSIGN`/`IC_GLBL` hit real
   Kernel.BIN data. **Proven off-disk three ways, not asserted:** (1) the board prints
   `GuestCmp src sz=851 sum=95CA2E1F` — a rolling `*31` hash over exactly the bytes it consumed —
   and `run_kernel_thin_loader_smoke.sh` recomputes both host-side from the seed file and greps
   for the literal line, so a stale/truncated/substituted read cannot pass; (2) the smoke gates
   that **no guest ident** (`RvAsmExportsSum`/`RvAsmExportsInit`/`g_rv_asm_*`) appears anywhere in
   `build/Kernel.BIN` — verified: Kernel.BIN carries only the *path* string, the image carries the
   *source*; (3) HolyC reads `kernel_soft_glbls[0..2].val` back as 40/2/0 after the Call.
   **Lex tip:** `KernelLexSkipSpaceSoft` now skips stock `//`-to-EOL comments, so guest source can
   carry a real doc header; `/` is not an operator anywhere in the lite Prs, so a lone `/` still
   falls through to the caller's error path and every earlier seed is unaffected.
   **Caps raised:** `KERNEL_SOFT_IDENT_MAX` 8→**24** (real Compiler_RV names like
   `g_rv_asm_exports` do not fit in 7 chars), `KERNEL_SOFT_FUN_MAX` 2→**4**,
   `KERNEL_SOFT_GLBL_MAX` 2→**4**, `KERNEL_SOFT_FUN_CODE` 192→**512** (the three bodies emit
   96+56+96 = **248 B**, over the old 192 B). `KERNEL_PRS_IC_MAX` **stays 32** — the deepest guest
   body is 7 IC, so it was never the binding cap.
   **Host AOT entry-thunk budget did not strain — measured, not assumed:** Kernel.BIN
   468000 → **474480** B (+6480) with `'EP'` green, and a throwaway 8/8/4096/64 build
   (**478832** B) also ran the whole chain green with zero FAILED. So the thunk budget is **not**
   what bounds this tip and no ≤2 KiB Load-slice fallback was needed; the 456960 B "budget held"
   watermark noted on CallIcSoft is stale. RedSea goes **18 → 19 files** (5 root dirs — the new
   `Compiler/` holds the guest source, not a BIN); MakeOS multi-blk FileFind/FileWrite packing
   unchanged.
   Needle `'GC'` (0x4743); past GlblMemSoft; keeps
   GlblMemSoft/CallIcSoft/ForSrcSoft/ElseSrcSoft/BrSrcSoft/CocSrcSoft/OptSrcSoft/SubSrcSoft/MulSrcSoft/IcSrcSoft/LexSrcSoft/PrsSrcSoft/CmpSrcSoft/CmpBrSoft/ForSoft/ElseSoft/BrSoft/CocSoft/AbiSoft/FunCallSoft/FunBodySoft/`'EP'`/`'FB'`/`'FC'`/`'AB'`/`'CO'`/`'BR'`/`'EL'`/`'FR'`/`'CB'`/`'CS'`/`'PR'`/`'LX'`/`'IC'`/`'MU'`/`'SB'`/`'OP'`/`'OC'`/`'BS'`/`'ES'`/`'FS'`/`'CL'`/`'GM'`
   green. **What this does and does not claim:** SoftCall now reads guest HolyC off the disk,
   Cmps it and Calls it with no Mac `phase3.elf` in that path — but only for the
   `(I64 g;)* (I64 name(){ (g=Expr;)* return Expr; })+ name();` grammar. The **grammar is the wall**,
   exactly as predicted: no locals (**since fixed — see GuestLocalSoft**), no `if`/`while`/`for` (**since fixed — see GuestFlowSoft**),
   no args (**since fixed — see GuestArgSoft**), no types besides `I64`
   (**pointers/byte memory since fixed — see GuestPtrSoft**), no
   `#include`/`#define`, one call per Expr and leftmost only (`jal` clobbers a0..a7; **since
   sharpened to "the lite stack holds exactly this call's args" — see GuestArgSoft**), and the file
   must fit the 2 KiB SoftCall Load budget. No real `Compiler/*.HC` file parses yet.
   SoftCall
   **GuestLocalSoft** landed (**frame locals inside a glbl-fun body** past GuestCmpSoft `'GC'` —
   the `KernelPrsCocFunDefSoft` statement loop folded into the glbl grammar, so a body is now
   `(I64 l[,l]*; | g=Expr; | l=Expr;)* return Expr;`. Each `I64 l;` plants an sp slot at
   8, 16, … through `KernelLocalPlantAbiSoft`, and every use is a real `IC_ASSIGN` `sd` /
   `IC_LOCAL` `ld` off `sp` — reusing `IC_ASSIGN` and `KernelSoftFrameSizeSoft` **unchanged**.
   Emission moves from `KernelEmitCallICSoft` to a new `KernelEmitGlblICSoft`:
   `addi sp,-frame; sd ra,0(sp); body; ld ra,0(sp); addi sp,frame; ret`, with locals starting at
   8 so they never alias the saved `ra`, and `frame` clamped to 16 so **no-local bodies emit
   byte-identical code to the old CallIC layout** — that is why every earlier `'GM'`/`'CL'` shape
   stays green. Locals reset per body, so the callee's slot 0 is a *different address* from the
   caller's. **Proof they are real frame slots, not folds:** (1) `KernelLocalValSoft` poisons any
   local with `abi_off >= 0`, so the plant-time fold path in `KernelEmitICBodySoft` cannot fire —
   folding is structurally impossible, not merely unobserved; (2) the frame test
   `I64 g;I64 G(){I64 t;t=1;g=7;return t;}I64 F(){I64 t,u;t=41;u=G();return t+u;}F();` →**42**,
   where `G` writes its own `t` (same slot index, lower frame) between `F`'s `sd` and `F`'s `ld` —
   shared/static storage would return 2; (3) the board **disassembles what it just planted** and gates on the encodings — exactly one
   `addi sp,sp,-32`, plus `sd rs2,8(sp)`/`sd rs2,16(sp)` and `ld rd,8(sp)`/`ld rd,16(sp)` — printing
   `GuestLocal disasm pro=1 sd8_16=21 ld8_16=21`, which the smoke greps literally, and asserts the
   entry body's slot offsets are exactly **8 and 16** with `frame=32`. Off-disk fragment:
   `A:/Compiler/SoftLocal.HC` (912 B, two sectors, `PrsLib_RV`-shaped — one `I64 g_rv_prs_depth;`
   glbl, `RvPrsFrameLeaf` and `RvPrsFrameSum` each declaring `I64 mark`), seeded onto the image
   and **nowhere else**, carrying the same three gates as `'GC'`: the board prints
   `GuestLocal src sz=912 sum=457A892F` (rolling `*31` over consumed bytes, recomputed host-side
   from the seed file and grepped literally), the smoke gates that **no guest ident**
   (`RvPrsFrameSum`/`RvPrsFrameLeaf`/`g_rv_prs_depth`) appears in `build/Kernel.BIN`, and HolyC
   reads `kernel_soft_glbls[0].val` back as 7 after the Call. Undeclared idents still error
   (`-10`) and a body local may not shadow a glbl (`-26`) — both gated.
   **Caps unchanged — headroom measured, not assumed:** `IDENT_MAX` 24, `FUN_MAX` 4,
   `GLBL_MAX` 4, `LOCAL_MAX` 4, `FUN_CODE` 512, `PRS_IC_MAX` 32 all held; the board prints
   `GuestLocal code=104/512 frame=32 locals=2 slots=8,16`, i.e. the off-disk fragment emits
   **104 of 512 B** (**80% FUN_CODE headroom**) and uses 2 of 4 locals, 1 of 4 glbls, 2 of 4 funs,
   7 of 32 IC. Kernel.BIN 474480 → **482448** B (+7968) with `'EP'` green; RedSea **19 → 20 files**
   (the new guest source joins `Compiler/`); MakeOS multi-blk FileFind/FileWrite packing unchanged.
   Needle `'GL'` (0x474C); past GuestCmpSoft; keeps `'GC'`/`'GM'`/`'CL'` and the whole lite chain
   green.
   SoftCall
   **GuestFlowSoft** landed (**`if`/`while`/`for` inside the merged glbl-fun body** past
   GuestLocalSoft `'GL'` — increment (b) of the grammar wall). A body is now
   `Stmt* return Expr;` with
   `Stmt = I64 l[,l]*; | Asg; | if(Expr)Asg;[else Asg;] | while(Expr)Asg; | for(Asg;Expr;Asg)Asg;`
   and `Asg = (local|glbl) = Expr`. Control flow reuses the `IC_BR_ZERO` / `IC_JMP` / `IC_LABEL`
   machinery the COC path already proved — **no new IC codes and no emitter change**; the two-pass
   label resolution in `KernelEmitICBodySoft` is per emit call, so the label budget is **per fun,
   not per file**, which is why `KERNEL_SOFT_LABEL_MAX` = 8 did not have to move. The statement
   loop's inline assign path was factored into one shared `KernelPrsGlblAsgSoft(cc, ic, n, term)`
   that every `for` init/step, every branch body and every ordinary statement goes through, so a
   branch body stores through exactly the same `IC_ASSIGN` / `IC_GLBL_ASSIGN` — and an undeclared
   target *inside* an `if` still errors `-10`, gated. **Proof the branches are real runtime control
   flow, not folds:** (1) `KernelLocalValSoft` still poisons frame locals, so a cond reading one
   cannot be folded — structurally, not by observation; (2) the board **disassembles what it just
   planted**: `beq` (opcode `0x63`) is the only branch form the lite Cmp emits and bit 31 of the
   encoding is `imm[12]`, so it counts **three `beqz a0` conds** (`for`, `while`, `if`), **two
   backward `beq x0,x0`** (the `for` and `while` back edges) and **one forward** (the `else` join),
   printing `GuestFlow disasm br=3 jb=2 jf=1`, which the smoke greps literally — a plant-time fold
   would emit none of them; (3) the fragment's trip count is a glbl written by a *different* fun,
   so it cannot be a compile-time constant: a throwaway `g_rv_opt_ic_n = 6` build returned 49
   instead of 42 and the smoke went red, confirming the gate bites. Off-disk fragment:
   `A:/Compiler/SoftFlow.HC` (1231 B, three sectors, `OptPass_RV`-shaped — `I64 g_rv_opt_ic_n;`
   and `I64 g_rv_opt_hits;` plus `RvOptPassScan` sweeping the IC array with a `for`
   (`5*7 = 35`, writing its hit count back out to BIN data), `RvOptPassPeel` draining `7 → 5 → 3 → 1`
   with a `while` and classifying the residue with an `if`/`else`, and `RvOptPassFold` summing
   `35 + 7 = 42` across two `jal ra`), seeded onto the image and **nowhere else**, carrying the same
   three gates as `'GC'`/`'GL'`: the board prints `GuestFlow src sz=1231 sum=BD06626D` (rolling
   `*31` over consumed bytes, recomputed host-side from the seed file and grepped literally), the
   smoke gates that **no guest ident** (`RvOptPassScan`/`RvOptPassPeel`/`RvOptPassFold`/
   `g_rv_opt_ic_n`/`g_rv_opt_hits`) appears in `build/Kernel.BIN`, and HolyC reads
   `kernel_soft_glbls[1].val` back as **35** after the Call. Every branch is load-bearing: a dead
   `for` body leaves 0, a dead `while` body leaves 7 so the `else` misses — either way the answer
   is not 42.
   **Caps unchanged — headroom measured, not assumed:** `IDENT_MAX` 24, `FUN_MAX` 4, `GLBL_MAX` 4,
   `LOCAL_MAX` 4, `FUN_CODE` 512, `PRS_IC_MAX` 32 and **`LABEL_MAX` 8** all held; the board now
   prints per-body watermarks, `GuestFlow code=308/512 ic=25/32 lb=4/8`, i.e. the off-disk fragment
   emits **308 of 512 B** (**40% FUN_CODE headroom**) and uses 25 of 32 IC, **4 of 8 labels**,
   2 of 4 locals, 2 of 4 glbls, 3 of 4 funs. `PRS_IC_MAX` (25/32) is now the tightest cap, not
   labels. Kernel.BIN 482448 → **492864** B (+10416) with `'EP'` green; RedSea **20 → 21 files**;
   MakeOS multi-blk FileFind/FileWrite packing unchanged.
   Needle `'GF'` (0x4746); past GuestLocalSoft; keeps `'GL'`/`'GC'`/`'GM'`/`'CL'` and the whole
   lite chain green.
   SoftCall
   **GuestPtrSoft** landed (**first non-`I64` typed values — a `U8 *` cursor and byte-width
   memory** past GuestFlowSoft `'GF'` — increment (c) of the grammar wall). A file scope is now
   `(I64 g; | U8 *p; | U8 b[N];)*` and an assign target is now
   `(local|glbl|ptr) = Expr | *Factor = Expr`. Three things are new. A `U8 b[N];` decl plants a
   **real byte buffer** in Kernel.BIN storage and its name **decays to that buffer's address** —
   `IC_GLBL_ADDR`, an absolute materialize with *no* `ld`, so the value on the lite RPN stack is a
   pointer rather than a cell read. `*p` is `IC_LOAD_U8` (`lbu rd,0(rd)`) and `*p = Expr;` is
   `IC_STORE_U8` (`sb rs2,0(rs1)`), both reading/writing whatever address the pointer names **at
   run time**. Deref goes through the one shared `KernelPrsGlblAsgSoft`, so a `*p = ...` inside an
   `if` or a `for` body is byte-identical to the store a top-level statement emits, and prefix `*`
   in `KernelPrsFactorSoft` is purely additive — every earlier tip fed a leading `*` to
   `KernelLexI64Soft` and failed. **Proof this is real typed memory, not a fold:** (1)
   `KernelPrsGlblFunDefSoft` — the grammar every off-disk fragment
   goes through — **never calls `KernelOptPassSoft` at all**; it hands IC straight to
   `KernelEmitGlblICSoft`, so there is no constant folder in this path. Even where one is consulted
   (the earlier lite-Cmp tips), its RPN evaluator has **no arm** for `IC_GLBL_ADDR` / `IC_LOAD_U8` /
   `IC_STORE_U8` and poisons on sight, exactly as it already does for `IC_GLBL`. Structural, not
   observational; (2) **byte width is load-bearing** — `298` stored
   through `*p` reads back as **42**, which no I64 cell could do, and an I64 path would emit `ld`,
   not `lbu`; (3) the board **disassembles what it just planted** and prints
   `GuestPtr disasm lbu=2 sb=3 abs=16` — two `lbu rd,0(rs1)` (the `for` cond and the accumulate),
   three `sb rs2,0(rs1)` (the seeded bytes) and sixteen `srli x,x,32`, one per
   `lui`/`addi`/`slli`/`srli` absolute-address materialize — which the smoke greps literally; (4)
   after the Call HolyC reads the **same storage** the emitted RISC-V wrote, gating
   `kernel_soft_glbls[0].arr[0..2] == 20,22,0`, `kernel_soft_glbls[2].val == 42` and the cursor
   parked exactly one past the last text byte on the NUL. Off-disk fragment:
   `A:/Compiler/SoftPtr.HC` (1588 B, four sectors, `Lex.HC`-shaped — `U8 g_rv_lex_buf[8];`,
   `U8 *g_rv_lex_ptr;`, `I64 g_rv_lex_sum;` plus `RvLexSeedText` writing `20,22,0` through the
   cursor, `RvLexWalkText` running `for (p = buf; *p; p = p + 1) n = n + *p;` — the single most
   recurrent shape in `Lex.HC` / `PrsLib_RV.HC` — and `RvLexTokScan` summing `0 + 42` across two
   `jal ra`), seeded onto the image and **nowhere else**, carrying the same three gates as
   `'GC'`/`'GL'`/`'GF'`: the board prints `GuestPtr src sz=1588 sum=D05AD406` (rolling `*31` over
   consumed bytes, recomputed host-side from the seed file and grepped literally) and the smoke
   gates that **no guest ident** (`RvLexSeedText`/`RvLexWalkText`/`RvLexTokScan`/`g_rv_lex_buf`/
   `g_rv_lex_ptr`/`g_rv_lex_sum`) appears in `build/Kernel.BIN`. **Negative control run:** flipping
   the seeded `20` to `19` in the fragment made the board answer 41, printed a different
   `sum=54C2885C`, and turned the smoke red with `SoftCall GuestPtrSoft FAILED`; reverting restored
   byte-identical source (`sha256 f4b2124a…`), `sum=D05AD406` and green.
   **One cap raised, headroom measured:** `FUN_CODE` **512 → 1024** — the walk pays **16 B per glbl
   touch** (`lui`/`addi`/`slli`/`srli` on a `0x8xxxxxxx` RAM cell), which is what the extra room
   buys. `IDENT_MAX` 24, `FUN_MAX` 4, `GLBL_MAX` 4, `LOCAL_MAX` 4, `LABEL_MAX` 8 and
   **`PRS_IC_MAX` 32 all held**. The board prints per-body watermarks:
   `GuestPtr code=496/1024 ic=22/32 lb=2/8`, i.e. the off-disk fragment emits **496 of 1024 B**
   (**52% FUN_CODE headroom**) and uses 22 of 32 IC, 2 of 8 labels, 1 of 4 locals, 3 of 4 glbls,
   3 of 4 funs. `PRS_IC_MAX` stays the tightest cap in the chain at **25/32** (still `'GF'`, not
   this tip). New glbl storage: `KERNEL_SOFT_GLBL_ARR` = 16 B per slot.
   Kernel.BIN 492864 → **506400** B (+13536) with `'EP'` green; RedSea **21 → 22 files**;
   MakeOS multi-blk FileFind/FileWrite packing unchanged.
   Needle `'GP'` (0x4750); past GuestFlowSoft; keeps `'GF'`/`'GL'`/`'GC'`/`'GM'`/`'CL'` and the
   whole 26-needle lite chain green (zero FAILED, zero skip).
   SoftCall
   **GuestArgSoft** landed (**function arguments and calls that pass them** past GuestPtrSoft
   `'GP'` — increment (d), the dominant blocker of the `'GP'` survey). A fun def is now
   `I64 name(Params){ … }` with `Params = <empty> | I64 a [, I64 b]`, and a call is
   `name(Expr[, Expr])`. Args are **real RISC-V a0/a1**, not a plant-at-call value: at the call
   site each arg `Expr` is appended to the caller's own IC stream ahead of the `IC_CALL`, so the
   lite RPN walk — which allocates `a(sp)` for stack depth `sp` — leaves arg 1 in **a0** and arg 2
   in **a1** by construction, and the callee prologue spills them into **its own** frame at
   `8(sp)` / `16(sp)` via `KernelLocalPlantAbiSoft`, from which every body reference is the
   ordinary `IC_LOCAL` `ld` that `'GL'` already proved. Only `KernelEmitGlblICSoft` grew (two
   conditional `sd`), and `nargs == 0` emits nothing, so every earlier tip is **byte-identical** —
   `GuestFlow code=308` and `GuestPtr code=496` are unchanged across this tip.
   **The jal-clobber rule is now exact instead of "leftmost".** `jal` clobbers a0..a7, so the old
   `if (sp) return -24` becomes `if (sp != callee.nargs) return -24`: at the call the lite stack
   must hold *this call's arguments and nothing else*. That accepts `G(1) + 2`, `H(G(20), 2)`
   (G's result is already in a0 when a1 is loaded) and `G(G(40))`, and rejects `2 + G(1)` and
   `H(40, G(2))` (G's `jal` would clobber the 40 already sitting in a0) — both with a compile
   error, never a silent mis-emit. Arg evaluation itself is clobber-free for free: arg *k* starts
   at stack depth *k−1*, so it can only allocate `a(k−1)` upward and can never overwrite an
   earlier arg; the only way to reach a0 again is a nested call, which the rule above catches.
   **Proof this is real register passing, not a fold:** (1) `KernelPrsGlblFunDefSoft` **never calls
   `KernelOptPassSoft`**, and where a folder is consulted at all its RPN evaluator has no arm for
   `IC_CALL` and `KernelLocalValSoft` poisons abi-offset locals on sight — so neither the callee
   body nor the call site has a fold path. Structural, not observational; (2) the fragment calls
   **one helper from two sites with different values**, so a folded, fixed-arg or a1-ignoring
   callee gives 30 or 38 instead of 34; (3) the board **disassembles what it just planted** and
   prints `GuestArg disasm jal=3 pro=1 set=2` — three `jal ra`, one
   `sd ra,0(sp); sd a0,8(sp); sd a1,16(sp)` spill prologue and two
   `addi a0,x0,imm; addi a1,x0,imm; jal ra` call setups. The two arg gates are matched as
   **three-word sequences**, not single encodings, because a lone `sd a0,8(sp)` is exactly what an
   ordinary frame-local store looks like; the smoke greps the line literally; (4) HolyC reads back
   `kernel_soft_glbls[0].val == 34` — the total the two differently argued calls actually banked —
   plus `KernelFunNArgsSoft(0..2) == 2,0,0`. In-BIN gates also pin the rejections
   (`-15` wrong arity, `-18` non-leftmost call, `-76` arg shadowing a glbl, `-74` non-`I64` arg,
   `-79` an entry declaring args, since HolyC Calls the entry as `fp()`), and Cmp
   **verbatim `Compiler/Test_RV.HC AddNumbers(I64 x, I64 y){return x + y;}`** — the first stock
   Compiler_RV function the lite Prs can compile, reachable only with this tip.
   Off-disk fragment: `A:/Compiler/SoftArg.HC` (1181 B, three sectors, `OptPass_RV.HC`-shaped —
   `RvIcOpCost(I64 code, I64 wide)` costing an IC slot, called `(2, 1)` and `(8, 0)` by
   `RvIcOpSum`, banked in `g_rv_ic_cost` and totalled by `RvIcOpTally`), seeded onto the image and
   **nowhere else**, carrying the same three gates as `'GC'`/`'GL'`/`'GF'`/`'GP'`: the board prints
   `GuestArg src sz=1181 sum=65E574BB` (rolling `*31` over consumed bytes, recomputed host-side
   from the seed file and grepped literally) and the smoke gates that **no guest ident**
   (`RvIcOpCost`/`RvIcOpSum`/`RvIcOpTally`/`g_rv_ic_cost`) appears in `build/Kernel.BIN`.
   **Negative control run:** swapping the second call's args from `(8, 0)` to `(0, 8)` — same byte
   count, same two values, different registers — made the board answer 22, printed a different
   `sum=CDF591AB`, and turned the smoke red with `SoftCall GuestArgSoft FAILED`; reverting restored
   byte-identical source (`sha256 680e8bd6…`), `sum=65E574BB` and green. That control fails **only**
   if a0 and a1 are genuinely distinct and ordered.
   **No cap raised, headroom measured:** `KERNEL_SOFT_ARG_MAX` stays **2**, and `FUN_CODE` 1024,
   `PRS_IC_MAX` 32, `IDENT_MAX` 24, `FUN_MAX` 4, `GLBL_MAX` 4, `LOCAL_MAX` 4, `LABEL_MAX` 8 all
   held. The board prints per-body watermarks: `GuestArg code=200/1024 ic=15/32 lb=1/8`, i.e. the
   off-disk fragment emits **200 of 1024 B** (80% FUN_CODE headroom) and uses 15 of 32 IC, 1 of 8
   labels, 3 of 4 locals (two args plus one body local — the tightest of this tip), 1 of 4 glbls,
   3 of 4 funs. `PRS_IC_MAX` remains the tightest cap in the chain at **25/32**, still from `'GF'`.
   Kernel.BIN 506400 → **515680** B (+9280) with `'EP'` green; RedSea **22 → 23 files**;
   MakeOS multi-blk FileFind/FileWrite packing unchanged.
   Needle `'GA'` (0x4741); past GuestPtrSoft; keeps `'GP'`/`'GF'`/`'GL'`/`'GC'`/`'GM'`/`'CL'` and
   the whole 27-needle lite chain green (zero FAILED, zero skip).
   **Remaining grammar wall — re-surveyed after `'GA'` at *function* granularity, same extractor
   and same blocker vocabulary as the `'GP'` survey so the two histograms are comparable.** Across
   the **225 top-level functions** in the ten `Compiler/*RV*.HC` files (225 not 220: the `'GP'`
   survey's extractor missed five), **1 now compiles** — `Test_RV.HC AddNumbers(I64 x, I64 y)`,
   up from 0, and it is Cmp'd verbatim as an in-BIN gate above. The blockers move as follows
   (before → after this tip): calls with args **203 (90%) → 174 (77%)**, now only those passing
   **more than 2**; fun args **207 (92%) → 162 (72%)**, now only those declaring **more than 2**;
   non-`I64` type **221 (98%)** unchanged; `&` address-of 95 (42%); braced multi-statement bodies
   92 (41%); local array / initialized decl 70 (31%); hex literals 61 (27%); `&&`/`||` 54 (24%);
   `->` member 43 (19%); `+=`/`++` 27 (12%); string literals 26 (12%). (The `'GP'` write-up quoted
   non-`I64` at 43% because it counted only the return type of a subset; counting return type *and*
   argument types, as here, it is 98% and always was.) **The dominant remaining blocker is the
   non-`I64` return type** — 212 of 225 functions return `U0`, `Bool`, `U32` or a `C*` pointer —
   with arity a clear second. Measured arity sweep over the same corpus, so the next tip can be
   sized rather than guessed: raising the glbl-fun arg cap from 2 to **3** takes fun-args-blocked
   162 → 129 and calls 174 → 165; to **4**, fun args 162 → **63** and calls 174 → 138; to 6, fun
   args 50 and calls 104. Going to 4 is structurally one extra `sd` per arg in the prologue plus a
   `LOCAL_MAX` raise (4 args would leave no body-local slots today), because the RPN already hands
   out `a(k)` for arg *k*; it was **not** taken here since the fragment does not need it and the
   off-disk gate only proves what the fragment exercises. Revised dependency order: (e) **`U0` and
   other non-`I64` return types** (the wall now, and cheap for `U0`: no value on the RPN stack at
   `ret`); (f) **arity 4 + braced `{}` bodies + hex literals**; (g) `class` decls and `->` member
   offsets (the deep one — 1094 `->` in `OptPass_RV.HC` alone); (h) string literals into a `U8`
   pool, now that byte storage and `lbu`/`sb` exist; (i) non-leftmost `IC_CALL` — spilling a0..a7
   around the `jal` instead of today's `if (sp != nargs) return -24`, which is what
   `return F() + G();` needs. **Stretch not taken, and why:** hex literals look cheap but are not
   *useful* cheap — `IC_IMM` is capped at `addi`'s ±2048, and nearly every hex literal in
   `Compiler/*RV*.HC` is a wide mask or address, so hex without wide-immediate materialization
   would parse and then refuse to emit. Braced bodies are cheap (a `{ Asg; … }` wrapper around the
   one shared `KernelPrsGlblAsgSoft` the branch bodies already call) but would ship without the
   byte-level disassembly gate and off-disk fragment this lane requires per capability, so both
   are left to their own tip. Honest bottom line: **no unmodified `Compiler/*_RV.HC` file parses
   yet, and exactly one unmodified function inside one does.**
   **SoftCall `GuestTypeSoft` (`'GT'`, 0x4754) — non-`I64` return and argument types, arity 4.**
   Takes items (e) and (f) of the `'GA'` dependency order above, so the "arity 4 not taken here"
   note is now spent. `CKernelFunSoft` gains `rtype` plus a packed `argt`, giving the lite Prs a
   declared type per fun and per argument over `I64` / `U0` / `Bool` / `U32` / `U8 *` / `C8 *`.
   The epilogue narrows whatever the body left in `a0` — `Bool` to `sltu a0,x0,a0`, `U32` to
   `slli`+`srli` 32 (zero-extend, *not* `srai`), `I64` and pointers to nothing — and the prologue
   narrows each incoming argument the same way right after spilling it, so a `U32` parameter is
   truncated in the callee rather than trusted from the caller. `U0` funs get their own
   `IC_CALL_U0`: a `U0` call is a **statement** that leaves the RPN stack empty, a bare `return;`
   is accepted, and a `U0` call in value position is refused at compile time. `KERNEL_SOFT_ARG_MAX`
   goes **2 → 4**, spilling real **a0..a3**, with a new `KERNEL_SOFT_ABI_ARG_MAX` 2 pinning the
   legacy `'AB'`-era emitters so their encodings do not move; `LOCAL_MAX` **4 → 8** (four args left
   no body-local slots) and `FUN_MAX` **4 → 8**.
   **Off-disk proof.** `A:/Compiler/SoftType.HC` (1969 B, `sz=1969 sum=DBDFCA7B`, recomputed
   host-side and grepped for absence of every guest identifier in `build/Kernel.BIN`) is shaped
   after the `BackLib_RV` emitters: a four-argument `U0` banks `imm*8 + rs1*4 + rd*2 + op` so each
   argument register carries a distinct weight and **any a0..a3 permutation gives a different
   answer** — (1,2,3,4) is 26, (4,3,2,1) is 49; a `Bool` returns `298-0` and must read **1**, where
   no narrowing shows up as 298 and a byte-wide one as 42; a `U32` evaluates `1024*1024*1024*k`,
   where `k=4` must truncate to 0 and `k=2` must stay **positive** (an `srai` slip makes it
   negative); and a `U8 *` hands an address back across a real `jal ra` to be stored through.
   **Byte-level gates.** Two disassembly lines, both matched as **three-word sequences** through a
   new `KernelSoftScanSeq3Soft`, because every single instruction here is ambiguous in isolation —
   a lone `sltu a0,x0,a0` is also how a `!=` tail ends, and a lone `slli`/`srli` pair is also how
   an absolute address is materialized: `GuestType disasm bool=1 u32=1 nov=1` pins **return** width
   (Bool narrow, U32 narrow, and `nov` = the `U0` epilogue carrying *no* value), and
   `GuestType disasm arg4=1 set4=1 u32a=1` pins **arity** (the a2/a3 prologue spill, the call-side
   a0..a3 setup, and argument-side narrowing).
   **Negative controls, both red.** (1) `srli` → `srai` in the U32 narrower — one funct7 bit, a
   pure *width* change that leaves every instruction count identical — turned the smoke red with
   `SoftCall GuestTypeSoft FAILED`. (2) Permuting the guest call's actuals (1,2,3,4) → (4,3,2,1) —
   same bytes, same four values, different registers — moved the printed sum to `C49B69BF` and also
   went red. Both reverted to byte-identical sources (`sha256 e82da998…` for the kernel probe,
   `80ea02e8…` for the guest fragment) and green. Those controls fail **only** if the narrowing is
   real and a0..a3 are genuinely distinct and ordered.
   **Caps and measured headroom.** `code=692/1024 ic=25/32 lb=2/8` and `caps lc=6/8 fun=7/8
   glbl=4/4`: the fragment emits **692 of 1024 B** (32% `FUN_CODE` headroom), 25 of 32 IC, 2 of 8
   labels, 6 of 8 locals, 7 of 8 funs, 4 of 4 glbls. After the first harvest run `FUN_CODE` and
   `GLBL_MAX` were **trimmed back** to measured usage rather than left over-provisioned, and
   `PRS_IC_MAX` held at 32 — still the tightest cap in the chain at **25/32**, unchanged since
   `'GF'`. `nargs == 0` paths stay byte-identical, and the SoftCall multi-blk RedSea
   FileFind/FileWrite MakeOS packing is unmoved. Kernel.BIN 515680 → **530752** B (+15072) with
   `'EP'` green; RedSea **23 → 24 files**; the whole 28-needle lite chain stays green (zero FAILED,
   zero skip).
   **Remaining grammar wall — re-surveyed after `'GT'` at function granularity.** The extractor was
   rebuilt for this tip and additionally models two rules the `'GA'` survey silently ignored: the
   lite `PrsExpr` is `AddExpr [relop AddExpr]`, so HolyC's chained range form (`0 <= sh <= 63`) has
   no arm, and a call only resolves against a callee the lite Prs has **already planted** out of the
   same source. Over the **227 top-level functions** in the ten `Compiler/*RV*.HC` files the tip
   moves the histogram substantially — non-`I64` type **98% → 82%**, fun args **71% → 28%**, calls
   with args **77% → 61%** — and the measured arity sweep confirms **4 is the knee** (5 buys only
   28% → 27%, and 27% still remains at 8). But the honest headline is that **exactly 1 of 227 still
   compiles verbatim**, unchanged: `Test_RV.HC AddNumbers`. Types and arity were not the binding
   constraint. What binds now is **structure**: **90% call a callee the lite Prs has not planted**
   and 59% land in the `other` bucket (bitwise ops, `switch`, divide, mid-body `return`, wide
   types), with braced multi-statement bodies 41%, local array / initialized decls 47%, `&`
   address-of 36%, hex 28%, `&&`/`||` 25%, `->` 21%, strings 13%. So the revised order is
   (j) **multi-fun unit intake** — plant a whole unit's funs before Cmp'ing bodies, which is what
   the 90% needs and is now the single highest-leverage tip; (k) braced `{}` bodies and local
   initialized decls; (l) `class` decls and `->` offsets; (m) string literals; (n) non-leftmost
   `IC_CALL`. Honest bottom line, still: **no unmodified `Compiler/*_RV.HC` file parses, and exactly
   one unmodified function inside one does** — this tip bought type and arity *coverage*, not a
   second compiling function.
   **BlkDev SoftCall skipped:** RedSea+virtio ENTER
   already SoftCalled; full `MakeBlkDev` (~177 KiB FAT/ATA/ISO/Dir*) won't fit SoftCall
   seed (~252 KiB w/ PhysMem → ~253 KiB w/ LoadMain → ~277 KiB w/ Hash2 → ~288 KiB w/
   DataHeap → ~305 KiB w/ FREE_PAG stock bumps → ~316 KiB w/ LoadAbs → ~326 KiB w/
   DirAbs+StartOSSoft → ~336 KiB w/ ExePutSSoft+CmpSoft → ~339 KiB (346800) w/ LexStmtSoft →
   ~345 KiB (353232) w/ PrsOptSoft → ~350 KiB (358720) w/ ParenSoft → ~356 KiB (364960) w/ IdentSoft →
   ~361 KiB (369584) w/ AssignSoft → ~368 KiB (377216) w/ FunDefSoft → ~373 KiB (381808) w/ FunBodySoft →
   ~376 KiB (384960) w/ FunCallSoft → ~391 KiB (400320) w/ AbiSoft → ~403 KiB (412688) w/ CocSoft →
   ~411 KiB (421360) w/ BrSoft → ~416 KiB (425904) w/ ElseSoft → ~423 KiB (433088) w/ ForSoft →
   ~432 KiB (442048) w/ CmpBrSoft → ~433 KiB (443312) w/ CmpSrcSoft Load → ~434 KiB (444032) w/ PrsSrcSoft Load → ~434 KiB (444736) w/ LexSrcSoft Load → ~435 KiB (445456) w/ IcSrcSoft Load → ~436 KiB (446176) w/ MulSrcSoft Load → ~436 KiB (446640) w/ SubSrcSoft Load + SoftCall multi-blk FileFind/FileWrite → ~437 KiB (447360) w/ OptSrcSoft Load → ~438 KiB (448064) w/ CocSrcSoft Load → ~438 KiB (448768) w/ BrSrcSoft Load → ~439 KiB (449488) w/ ElseSrcSoft Load → ~440 KiB (450208) w/ ForSrcSoft Load → ~446 KiB (456960) w/ CallIcSoft SoftCall-lite inter-fun CALL IC → ~457 KiB (468000) w/ GlblMemSoft SoftCall-lite glbl memory → ~463 KiB (474480) w/ GuestCmpSoft first real guest Cmp read off RedSea → ~471 KiB (482448) w/ GuestLocalSoft frame locals in a glbl-fun body → ~481 KiB (492864) w/ GuestFlowSoft if/while/for in that body → ~495 KiB (506400) w/ GuestPtrSoft `U8 *` cursor + `lbu`/`sb` byte memory → ~504 KiB (515680) w/ GuestArgSoft fun args + real a0/a1 calls).
   Display SoftCall skipped (x86 VGA).
   **FB/WinMgr SoftCall skipped:**
   `RVWinMgr.HC` ~120 KiB + `RVGr.HC` ~53 KiB src — won't pack SoftCall-lite.
   **Compress ARC_BITS=12 SoftCall skipped:** stock `CArcCtrl` compress+hash tables
   ~96 KiB BSS (~288→~384 KiB SoftCall seed) — won't fit; SoftCall-local ARC_BITS=9
   stays. Hash2 stock FREE_PAG_HASH=0x100 trigger (needs ≥130-pag arena) deferred with it.
   **SoftCall seed ceiling (honest):** RedSea InitLite+SoftCall Kernel.BIN is ~481 KiB (492864) after
   DirAbs+StartOSSoft+ExePutSSoft+CmpSoft+LexStmtSoft+PrsOptSoft+ParenSoft+IdentSoft+AssignSoft+FunDefSoft+FunBodySoft+FunCallSoft+AbiSoft+CocSoft+BrSoft+ElseSoft+ForSoft+CmpBrSoft+CmpSrcSoft+PrsSrcSoft+LexSrcSoft+IcSrcSoft+MulSrcSoft+SubSrcSoft+OptSrcSoft+CocSrcSoft+BrSrcSoft+ElseSrcSoft+ForSrcSoft Load + CallIcSoft + GlblMemSoft + GuestCmpSoft + GuestLocalSoft + GuestFlowSoft SoftCall-lite + SoftCall multi-blk FileFind/FileWrite; embed @`0x81000000` stays viable, but **BlkDev remainder /
   Display / FB+WinMgr / ARC_BITS=12 (~+96 KiB BSS) / full Compiler.BIN (~1.1 MiB +97 imports)** will
   not pack SoftCall-lite — SoftCall arena is 64 KiB and KernelLoad caps at 2 KiB; bigger SoftCall
   heap alone does **not** land Compiler.BIN Load (~1.1 MiB); SoftCall-lite multi-fun Lex past
   CmpBrSoft is blocked (host AOT 32 B entry thunk breaks ExePutSSoft when SoftCall-lite PrsCmpSrc
   is packed); further Compiler_RV ownership must ship as product BINs Load'd by SoftCall (StartOS
   + SoftCmp + SoftCmpSrc + SoftPrsSrc + SoftLexSrc + SoftIcSrc + SoftMulSrc + SoftSubSrc + SoftOptSrc + SoftCocSrc + SoftBrSrc + SoftElseSrc + SoftForSrc chain already does; CallIcSoft, GlblMemSoft, GuestCmpSoft, GuestLocalSoft and GuestFlowSoft show SoftCall-lite still has thunk headroom — a throwaway 8/8/4096/64 cap build reached 478832 B with `'EP'` green, so the 456960 B watermark is stale and the *grammar*, not the thunk, now bounds guest Cmp). **StartOS SoftCall Load chain complete**
   (Seed+Svc+Kern + StartSoft + Adam SoftCall + **StartOSSoft** full StartOS Load without
   phase3.elf Cmp); **SoftCall-lite ExePutS/CmpCtrl + MakeOS CmpWrite + LexStmt2Bin/emit + Prs/Opt fold + paren/IC emit + local/ident IC + PrsStmt assign + fun-def/return/Call + multi-stmt/locals-in-fun/single-arg + multi-arg/call-Expr + ABI/a0 frame + COC multi-stmt ASSIGN emit + if/while BR + if/else + for + relational cmp-BR landed; multi-fun + Prs fold + LexStmt2Bin peel + IC plant+emit + MUL IC + SUB IC + OptPass fold + COC ASSIGN + BR + if/else JMP + for-loop SoftCall Load via SoftCall Load slices (not SoftCall-lite Lex)**
   (ExePutSSoft→`'EP'` + CmpSoft→`'CC'` + LexStmtSoft→`'LB'` + PrsOptSoft→`'PO'` + ParenSoft→`'PN'` + IdentSoft→`'ID'` + AssignSoft→`'AS'` + FunDefSoft→`'FD'` + FunBodySoft→`'FB'` + FunCallSoft→`'FC'` + AbiSoft→`'AB'` + CocSoft→`'CO'` + BrSoft→`'BR'` + ElseSoft→`'EL'` + ForSoft→`'FR'` + CmpBrSoft→`'CB'` + CmpSrcSoft→`'CS'` + PrsSrcSoft→`'PR'` + LexSrcSoft→`'LX'` + IcSrcSoft→`'IC'` + MulSrcSoft→`'MU'` + SubSrcSoft→`'SB'` + OptSrcSoft→`'OP'` + CocSrcSoft→`'OC'` + BrSrcSoft→`'BS'` + ElseSrcSoft→`'ES'` + ForSrcSoft→`'FS'` + CallIcSoft→`'CL'` + GlblMemSoft→`'GM'` + GuestCmpSoft→`'GC'` + GuestLocalSoft→`'GL'` + GuestFlowSoft→`'GF'`); **KDate + QSort + KeyDev + Except +
   Mem + StrUtil + Fifo + QueVect + Rand + ScanFlags + Compress + KLoad + MakeMem +
   PhysMem + LoadMain + Hash2 + DataHeap + LoadAbs + DirAbs SoftCall ownership landed**.
   **All lite-Cmp primitives are now present** (Lex ident/I64 → Prs paren/`*`/`+`/`-`/relational →
   OptPass fold → IC emit → frame locals + ABI args + COC multi-stmt + `if`/`else`/`while`/`for` BR
   + inter-fun CALL `jal ra` + **glbl memory** `lui`/`addi` abs + `ld`/`sd`), so the lite compiler
   can finally express Compiler_RV-shaped source: true globals plus several functions that call
   each other, rather than plant-value locals inside one body — and as of `'GC'` that source is
   **read off RedSea**, not baked into Kernel.BIN. **Next tip (concrete):** grow the grammar, not
   the budget. `'GC'` settled the budget question — 8/8/4096/64 caps still boot green at 478832 B,
   so the entry thunk is not the lever; what blocks a real `Compiler/*.HC` file is what
   `KernelPrsGlblFunDefSoft` still refuses. Increments **(a)** frame locals (`'GL'`) and
   **(b)** `if`/`while`/`for` in that merged body (`'GF'`) are **done**, and `LABEL_MAX` 8 never
   had to move because labels are body scoped. Remaining, in dependency order: **(c)**
   **typed/pointer values — `U8 *`, `U16`/`U32`, member access — and string literals**, which a
   survey of the ten `Compiler/*RV*.HC` files says is the real gate (non-`I64`/pointer types in
   10/10, string literals in 9/10, `#include`/`#define` in 3/10); **(d)** typed/multi args on glbl
   funs so a callee is more than `()`; **(e)** non-leftmost `IC_CALL` — spill a0..a7 around `jal`
   instead of `if (sp) return -24` — which is what `return F() + G();` needs. **Control flow is
   no longer the lever**: more of it (`&&`/`||`, braced bodies, `break`) buys no new real file.
   Only after (c)–(e) is it worth pointing the reader at a genuine
   unmodified `Compiler/*_RV.HC` slice. Keep the honesty gates `'GC'` introduced (printed
   `sz`+`sum` recomputed host-side from the seed file, plus the no-guest-ident-in-`Kernel.BIN`
   grep) so "guest Cmp" can never silently degrade back to an in-BIN literal.
   Otherwise pack remaining tiny SoftCall-lite leftovers
   (FUF_SCAN_PARENTS / `~` home) if still SoftCall-budgeted.
   Not FB/WinMgr SoftCall; not TrapPlic; not ARC_BITS=12 SoftCall; not full Compiler.BIN SoftCall Load;
   not SoftCall-lite multi-fun Lex (ExePutSSoft hang — CallIcSoft's small additive IC_CALL is the thunk-safe shape; a full multi-fun Lex is not).
   **Blockers (honest):** full `Kernel_RV.PRJ` still will not fit this SoftCall seed —
   BlkDev remainder/Display/FB/WinMgr remain phase3-ELF or thin-stubbed (PhysMem
   SoftCall-lite landed; stock x86 PageTables asm / Sv39 / Mem64Dev / real E820
   still phase3; MakeMem stock FREE_PAG_HASH=0x100 landed; Hash2 stock FREE_PAG_HASH2=55
   landed — SoftCall-local HASH2_FREE_PAG_HASH=8 threshold still SoftCall-lite; KLoad SoftCall-lite landed;
   LoadMain+DataHeap+LoadAbs+DirAbs+StartOSSoft SoftCall-lite landed — stock FUF_SCAN_PARENTS / `~` home
   DirNameAbs still phase3; Compress SoftCall-lite landed; stock ARC_BITS=12 / full Compress.HC
   still phase3 — SoftCall BSS won't fit); ExePutSSoft+CmpSoft+LexStmtSoft+PrsOptSoft+ParenSoft+IdentSoft+AssignSoft+FunDefSoft+FunBodySoft+FunCallSoft+AbiSoft+CocSoft+BrSoft+ElseSoft+ForSoft+CmpBrSoft SoftCall-lite + CmpSrcSoft+PrsSrcSoft+LexSrcSoft+IcSrcSoft+MulSrcSoft+SubSrcSoft+OptSrcSoft+CocSrcSoft+BrSrcSoft+ElseSrcSoft+ForSrcSoft Load landed —
   **full Compiler_RV COC + Compiler.BIN Load still phase3** (SoftCall 64 KiB arena / 2 KiB Load
   ceiling; SoftCall-lite multi-fun Lex blocked — CmpSrcSoft 1328 B + PrsSrcSoft 1904 B + LexSrcSoft 2000 B + IcSrcSoft 2016 B + MulSrcSoft 2016 B + SubSrcSoft 2016 B + OptSrcSoft 1904 B + CocSrcSoft 2048 B + SoftBrSrc 2032 B + SoftElseSrc 2032 B + SoftForSrc 2032 B host-AOT SoftCall Load slices);
   TrapPlic SoftCall hangs (do not retry); DocInit/Menu Soft tip remat
   fights are siblings; **phase3.elf still required for full guest Cmp** (Compiler Load+ExePutS +
   MakeOS/Runtime Cmp of real sources) until SoftCall/thin owns real Cmp without Mac AOT scaffold.
   **Do not** retry TrapPlic SoftCall; avoid DocInit/Menu Soft tip fights.
3. Only then attempt guest Cmp of DolDoc subset / real `MakeAdam_RV` — do **not** claim
   P6 until on-target Load runs DocTerm+WinMgr without Mac AOT of `win_*.elf` as DoD.

