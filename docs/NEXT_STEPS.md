# What is left

## START HERE (handoff, 2026-09-24)

Tiers 0-3 and 3.5 are closed. The suite ran **85 pass / 0 fail at `7312388`** (serial, 2h33m) to
re-establish the baseline, then **86 pass / 0 fail on the UNCOMMITTED working tree at that same
`7312388`** (2h31m). Two sweep results, one SHA -- the second one is the nine changed files
listed below, not the commit. The extra target is `kernel-win-serial-smoke`, which reaches
`RVExePubs` through `Compiler_RV.PRJ` and so is exposed to these changes without being in
`qemu-integration`.

**The live thread from the previous handoff is CLOSED, and the Track B milestone is DONE.** The
whole DocInitStock ladder is green -- A4c, A1, A2, A3, A4a, A4b, A4, A, B, C, D **and rung E,
the unmodified stock `#include` of `Adam/DolDoc/DocInit_RV.HC`**, which now both compiles under
the guest compiler and runs correctly.

### What was actually wrong: TWO bugs in series

Neither one alone explains the symptoms, which is why the previous handoff's one-line fix was
tried and reverted twice.

**1. The guest compiler could not carry a planted global's address at all.**
`Compiler/OptPass_RV.HC`'s `IC_ADDR_IMPORT` was `RVLi(reg, tmpi->ic_data)` -- and `ic_data` is
the `CHashGlblVar` ITSELF, with no relocation registered. Emitted code used the address of the
hash entry as the address of the global, so A2/A3's stores wrote into the compiler's own heap
and the NEXT compile (A4a) KTRAPed. Compare x86 (`OptPass789A.HC:124`), which emits a
placeholder and hangs an `IET_IMM_U32` record on `tmpg->ie_lst`.

Fixed in two places:

- `Compiler/OptPass_RV.HC` -- emit `auipc r,0; ld r,12(r); jal x0,12; .dword 0` plus an
  `IET_IMM_I64` record at the `.dword`, exactly as `IC_CALL_IMPORT` does for a callee slot.
  Leave `tmpie->aot` NULL or `CMain.HC`'s imports writer adds `aot->rip2` a second time.
- `Compiler/PrsLib.HC` + `PrsExp.HC` -- `PrsGlblImportAlias` makes a PER-COMPILE import alias
  in `cc->htc.glbl_hash_table`. **The record can never hang on the plant itself**:
  `AsmResolve.HC:134` iterates `glbl_hash_table->body[i]` and never follows `->next`, and the
  plant lives in `cmp.asm_hash`, which outlives every compile. That is why
  `tmpg->flags = GVF_ALIAS | GVF_IMPORT` on the plant is structurally dead. Do not try it again.

**2. The address the plant was handing out was a MODULE-LOCAL DUMMY.**
`Compiler/RVExePubs.HC` had `extern U8 doldoc;` for the standalone build. In
`Compiler_RV.PRJ`, `OPTf_EXTERNS_TO_IMPORTS` is ON only around the `KernelB/C.HH` includes, so
that extern did NOT become an import -- it created module-local storage, and `&doldoc` was an
address inside the loaded Compiler module. Measured `0x823C9B90` against a true `0x80A709C0`.

Fixed the way `Fs`/`Gs`/`blkdev`/`char_bmp_*` already do it: `rv_cmp_doldoc`, a pointer the
kernel fills at Load through `RV_CMP_DOLDOC_OFF` (`tools/gen_cmp_imports.py` ->
`Kernel/RVCmpRtPatch.HH`, written in the wiring block at `Kernel/RVPhase3.HC`). When it is
unwired, `RVExePubInternDolDocIn` **refuses to plant** instead of planting a wrong address.

### The proof, and the tools that produced it

- **A4c returns `0x80A709C8`, which is `&doldoc.dft_de_flags` exactly.** A4c was moved ahead of
  A1 in the ladder and should stay there: it is the only rung that checks against ground truth,
  and A2/A3 STORE through the address under test, so they must not run first.
- **`PHASE3_KEEP=1`** keeps the smoke's work dir, and **`tools/read_tosb.py`** dumps a BIN's
  patch table and code words off the guest's own RedSea image. That is what showed the BIN was
  already correct (`IMM_I64 doldoc -> rip 36`, pointing at the `.dword`) while the value it
  received was not -- separating the compiler from the plant in one run.
- **A control run is worth its wall clock.** Stashing only the three compiler-side files, with
  the plant wiring still applied, is what proved an A2 wedge was mine and not pre-existing. The
  claim in the old notes that "A1-A4 Soft Cmp all pass" was not evidence; it predated too much.
- `grep -a`. The phase3 UART capture is not UTF-8, so plain `grep` silently matches nothing and
  looks exactly like "the marker is not there".

### The bug I introduced and fixed, because the shape will recur

The per-compile alias first cleared `GVF_ALIAS`. `HashDel` (`Kernel/KHashB.HC:77`) frees a
`HTT_GLBL_VAR`'s `data_addr` **unless `GVF_ALIAS` is set**, and also `LinkedLstDel`s `dim.next`
and `HashDel`s `fun_ptr`. So every compile's `HashTableDel` called `Free()` on the kernel's
static `doldoc` and released two pointers it shared with the plant. The wedge then appeared two
rungs later, at the third compile, with nothing wrong at the site of the bug. **An alias entry
must own nothing.**

### What is next, in order

1. **Do NOT simply "fix" the eight remaining seeds' `HashFind` arity. It was TRIED and
   REVERTED on 2026-09-24.** They declare `import I64 HashFind(U8 *needle, I64 table, I64 mask)`
   with three parameters, while the real one is `HashFind(needle, table, mask, instance = 1)`
   and returns NULL outright when `instance <= 0` -- so a 3-arg import leaves `a3` holding junk
   and every lookup fails. That really was the whole of rung E's old `r=3`, and adding the
   fourth parameter to `phase3_LiteDocInitStock.HC` alone took rung E green.

   Adding it to the other eight turns rungs **A, B and C from OK to `r=3`**, because those
   rungs were passing *because* the lookup was broken. Each has stock DocInit's idempotent
   warm path at the top:

   ```
   if (doldoc.hash && HashFind("TX", doldoc.hash, DHT_DOC_CMD)) return;
   ```

   With a working `HashFind` that guard fires and the body correctly does nothing -- but rung
   **A4 `MemSet`s `doldoc.dft_de_flags` to zero** earlier in the ladder and never restores it,
   so the warm path returns leaving `dft_de_flags[DOCT_TEXT]` at 0 and each self-test's
   `!= DOCEF_TAG` check fails. The rungs assert state that the warm path deliberately does not
   re-establish.

   So this is a LADDER-ORDER problem, not an arity problem. Fixing it properly means one of:
   have A4 restore what it wipes; move the wiping rungs after the A-E rungs; or relax those
   three self-tests to accept the warm path. Pick one, then fix all nine seeds together.

2. Then DolDoc itself: with stock `DocInit` running in the guest, the next question is what
   `RVDocPrsDollarCmd` does with a real `doldoc.hash`.

### Gates added 2026-09-24, and what they cost

- **The picture is now proved to reach the SCREEN.** Every pixel assertion here used to be
  `RVFbHash`, an FNV-1a over `rv_fb.pixels` — the guest's own COMPOSE buffer, as its comment
  admits. `tools/fb_scanout_hash.py` screendumps a live QEMU over QMP and hashes the display
  surface in the guest's U32 layout (X=0; PPM has no X byte), so the two are comparable.
  `kernel-fb-smoke` and `kernel-win-smoke` require them equal. Proof it bites: remove
  `RVFbPresent()` from the fb demo and the compose hash is UNCHANGED at `0x28921CB5` while the
  scanout reads `0xAB6D151D`. `--png` writes the scanout out — **look at it**; a hash says the
  picture is stable, never that it is right.
- **A regression floor over the phase3 smoke's 266 optional needles**
  (`tests/exec/fixtures/phase3_soft_needles.txt`). They were all `soft_extra`: appended to the
  OK line, required by nothing. Superset test — new stages are free, a stage that silently
  stops running fails. Re-record with `PHASE3_RERECORD=1`, and say why in the commit.
- **Three smokes stopped billing a fixed timeout.** phase3 1825s → 62s, fb 42s → 4s, win
  42s → 4s, because each now waits for its completion line instead of running `timeout N qemu`
  to the cap. If you add a smoke, do not let the timeout become the runtime.

Suite: **86 pass / 0 fail at `acbd441`**, clean tree, 2h18m.

### What the scanout PNG shows, and the one thing it revealed

Three windows on the blue field — Adam (red border), DocTerm (green), and HOME.DD rendering a
live DolDoc with coloured links, an expanded `+] Adam` tree and a collapsed node — plus the
status and hint bars. It looks like TempleOS.

It also shows **overlapping text runs in the two top windows**, which no hash would ever have
reported. That is consistent with the known compositor gap: `win_z_buf` is filled
(`RVWinMgr.HC:3503`, `:3541`) but **read by nothing** — `GrPlot0` (`Kernel/RVGr.HC:672`) clips
only to `dc->clip_*` — and `RVWinMgrDrawIts` (`:1791`) iterates array index, not z order. Wire
z into the clip test and iterate in z order; then re-shoot the PNG and compare.

### Overlapping windows composite by Z now — and a trap found on the way

`RVWinMgrDrawIts` walked windows in ARRAY INDEX order, so a window at a higher index painted
straight over one in front of it; the per-window rect clip cannot catch that, since it only
knows the window's own bounds. Nothing could see it: the DocTerm desktop tiles its windows and
sets `draw_it = NULL`. `tests/exec/cases/kernel_win_zorder.hc` (`make kernel-win-zorder-smoke`)
builds the overlap on purpose — front window at the LOWER array index, focused, so it has the
higher z — and reads the overlap pixel. Before the fix: `got=0x00FF00` (the BACK window's
colour). After: `0xFF00FF`. DrawIts now paints back-to-front by z.

**The per-cell `win_z_buf` clip in `GrPlot0` is still NOT done, and here is the trap.** It
needs the DC to carry the z context (`RVGr` is included before `RVWinMgr`, so `GrPlot0` cannot
see `rv_winmgr`) — i.e. new fields on `CRVDC`. **Growing `CRVDC` by 32 bytes changes what the
Blot demo renders**, moving 688 of 480 000 pixels and taking `kernel-demo-blot-smoke` from
`0x43186381` to `0xE1F4B00D`.

That is not a z bug. It was isolated to pure layout: four `I64 probe_pad` fields, no logic
whatsoever, reproduce `0xE1F4B00D` exactly. **`Demo/Graphics/Blot.HC`'s render depends on heap
layout — probably uninitialised memory under its flood fill — so its pinned hash is not a
function of the code alone and will break on any change that shifts an allocation size.** Fix
that before adding fields to `CRVDC`, or the clip's first symptom will be an unrelated red.

Worth knowing regardless: the before/after PNGs are what settled this in minutes
(`tools/fb_scanout_hash.py --png`). Both Blot renders are two blue lines on black, which is
itself suspicious for a demo whose job is a flood-filled blot — that is a separate thread.

### Driving stock games: what works, and two traps

Two games are gated end to end — `kernel-game-input-smoke` (Halogen, keyboard) and
`kernel-game-mouse-smoke` (MassSpring, mouse). Both run the game's OWN loop. The pattern that
works: `Spawn` the game as a CTask, post `TaskMsg` events, and **sample while it is alive**.

**Trap 1 — measure before the epilogue.** `MassSpringDemo` ends with `CleanUp`, which QueDels
every mass and spring. Run the loop and count afterwards and you get 0/0, which reads as "the
clicks did nothing". Running it as a task gives a point to measure from.

**Trap 2 — a sleeping task needs REAL TIME, not Yields.** BattleLines `Sleep(40)`s each turn.
6000 `Yield`s in the driver run in microseconds, so the task stays asleep and the simulation
appears frozen. `Sleep(100)` x N in the driver makes it tick. MassSpring hid this because it
blocks on `GetMsg`, which a posted message satisfies at once.

**`ScanChar` works — it waits for the key RELEASE.** An earlier note here said it does not
receive `TaskMsg(MSG_KEY_DOWN)`. That was wrong. `Kernel/SerialDev/Message.HC:110` takes the
down and then blocks in `GetMsg` until a `MSG_KEY_UP` with a NON-ZERO ASCII arrives, so posting
only the down wedges the game and posting a down/up PAIR works: BattleLines' `'2'` flips
`tap_mode`. (The definition was invisible to `grep` without `-a` — that file carries binary.)

**BattleLines is gated now** (`kernel-game-scanchar-smoke`): the key reaches its own switch and
the trooper lands somewhere different with the pointer inside its tap radius than with it far
away. Two things learned while getting there: the pointer exactly ON a trooper is the one
degenerate spot (`d==0` fails the `(d && d<R^2)` guard, so nothing happens), and the tap
intensity is `((R^2-d)^2)^2`, which throws a trooper to x=566015508.

That last one is NOT a bug — checked, don't re-chase it. The arithmetic was run in isolation
against hand-computed values and is exact: `SqrI64(50)=2500`, `SqrI64(2100)=4410000`,
`intensity=19448100000000`, `intensity*dx/d=-972405000000`. The tap profile is simply enormous
near the centre and gentle at the radius edge, so a pointer 20px from a trooper really does
launch it. The smoke pins divergence, not magnitudes.

### The next ScanChar game crashes: JobsHndlr on a fresh spawned task

`Demo/Graphics/Lines.HC` (`while (!ScanChar) { GrLine…; Sleep(1); }`) is the obvious next game
— it compiles, and any key stops it. Driven as a spawned task it takes a load fault at
`JobsHndlr +0x21c`, `mtval=0x18`, WITH NO MESSAGES POSTED AT ALL.

Localised: `JobsHndlr` does `tmpc = task->srv_ctrl.next_waiting` and then `tmpc->job_code`, and
`offset(CJob.job_code)` is exactly 0x18 — so `next_waiting` is NULL, i.e. that task's job
control was never QueInit'd. Both TaskInits (`KTask.HC:184` and `KThinTaskStubs.HC`) do call
`JobCtrlInit(&task->srv_ctrl)`, and neither has an early return that skips it, so the
contradiction is unresolved. The parent cannot even print the field: the task runs and faults
during Spawn, before the next statement.

Why BattleLines and MassSpring survive the same treatment: both have long prologues
(MenuPush/SettingsPush/PopUpOk/Init) before their first ScanChar/GetMsg, so something in there
warms the queue. Lines' prologue is a single DCAlias. That contrast is the lever — diff what
PopUpOk touches against a bare spawn.



`ms.pos` is published now (`RVWinMgrPublishMs`) but is CELL-granular, so it lands on multiples
of 8. Whether that is enough for BattleLines/Whap is untested.

### Standing rule this session earned again

Every red here was **a failure path that reported success**, or a measurement read one stage
downstream of its cause. `gen_cmp_imports.py` ran under `|| true` in the phase3 smoke, which
would have left `RVCmpRtPatch.HH` stale and patched the module at the wrong offsets without a
word; that is now a hard failure. **Inspect the artifact at every stage it passes through
before blaming the stage that produced it** -- `tools/read_tosb.py` exists to make that cheap.

## Tier 0 — things that are wrong now

### 0.1 ~~A planted pub delivers only its first argument~~ — FIXED, and it was not that

The diagnosis was wrong. Multi-argument pubs are fine; a call NESTED in an argument list
corrupted the arguments around it, in guest codegen, for any REPL code. The backend walked back
to the nearest `IC_CALL_START` to find a call's arguments and found the inner call's. Fixed in
`Compiler/OptPass_RV.HC` with a nesting-aware walk; `ArgEcho` in the smoke locks both spellings.

#### The original entry, for the record

`PgAt(root, va, levels)` called from the REPL arrives as `(root, 0, 0)`, with or without
declared defaults. Found while testing the page-table walker; `PtWalk` exists only to make that
call from inside the image instead.

It affects every multi-argument pub: `Dm`, `D`, `Da`, `PgAt`. One-argument pubs (`Csr`, `Lk`,
`Fd`, `Pg`) are fine, which is why it went unnoticed — everything exercised until now took one
argument or none.

Start at `RVExePubAddArg` / `RVExePubFunNew` in `Compiler/RVExePubs.HC` and compare what they
build against what the guest compiler's call path expects for a `CHashFun` with `arg_cnt > 1`.
**This is the biggest hole in the REPL's API and should go first** — until it is fixed, no new
function taking more than one argument can be trusted.

### 0.2 ~~`Regs;` corrupts the freeze (seed image)~~ — FIXED, spill moved to +0x400

`RegsDumpHc` (`bootstrap/seed/csr.hc:1556`) spills ten CSRs to `0x87000400`..`0x448` — which is
`TRAP_SNAP_X` slots x0..x9. Typing `Regs;` after a fault overwrites the low ten registers of the
freeze that `_X0.._X9` and `DbgX` then read back. Small: give the spill its own address.

### 0.3 ~~`TrapFaultDump` prints uninitialised stack as `ra`~~ — FIXED, frame[1]

`bootstrap/seed/trap.hc:535` prints `frame[0]`, but `TrapCtxSave` puts x1 at offset 8 and never
writes slot 0. One-line fix; the value has been wrong in every fault dump.

### 0.4 ~~Trace advances by 4 through compressed instructions~~ — FIXED, follows the real width

`t` in the asm REPL adds 4 to the cursor whatever the instruction was, so a 2-byte RVC
instruction lands the cursor mid-instruction and the next disassembly is garbage. The
disassembler already knows the width — return it from `AsmUiInsnText` instead of assuming.

---

## Tier 1 — asked for, only half done

### 1.1 ~~The newline rule is not in the REPL~~ — DONE

`HOLYC_NL_SEMI=1` works in the host compiler, which is what compiles source files. The REPL is
the *guest* compiler (`Compiler/`), and it has none of it — so at the prompt `40+2` still needs
its semicolon, which is where the BCPL rule would be felt most. Port `NewlineEndsStatement` into
the guest lexer, where the same five conditions apply.

### 1.2 ~~The newline rule is off by default~~ — DONE, and the 36 were one rule

All 36 were the same shape: a TYPE NAME alone at the end of a line, with the declarator under it
(`U32` then `char_bmp_alpha[16]= {...}`, pages of them in Kernel/StrA.HC). A type cannot end a
statement, and the lexer had already resolved the identifier, so it asks what it was rather than
guessing. Zero errors after that, and the whole kernel image compiles BYTE-IDENTICAL with the
rule on — which is what earned it the default. `HOLYC_NL_SEMI=0` turns it off.

### 1.3 ~~The pane cannot show everything at once~~ — DONE, the pane is paged

It packs WHOLE blocks starting at the current page and wrapping around, taking each only if it
fits entirely: nothing is ever cut, everything is reachable by cycling (`n` in the asm REPL,
`Pane(n)` at the prompt), and a taller terminal simply shows more blocks rather than a different
layout. The headings carry the hint, so a block that is off the page still says how to reach it.

### 1.4 ~~AsmDoc motivation~~ — DONE, 244 of 244

`AsmClasses` / `AsmClass` and the REPL's `p <class>` now exist, so a family can be worked
through one instruction at a time — which makes the missing motivation entries more visible, not
less. The classes are curated lists in `Kernel/RVExplore.HC`.

Complete: 220 example records cover all 244 catalog entries through the dot-folding fallback,
with no orphans either way, and `make asm-catalog-check` holds it there.

Validating a third batch of 89 turned up two defects in the tables themselves, which is the
argument for VERIFICATION_PLAN P3 in miniature:

- **`fence`'s record contained a `;`**, which is the RECORD SEPARATOR. Its documented semantics
  was silently truncated at `succ-set`, and the tail became a phantom 244th record whose
  mnemonic was ` masks use letters i/o/r/w`. `AsmComplete` with an empty word — Tab straight
  after a bare `?`, the "show me everything" path — matched and listed it.
- **The two tables disagreed on spelling.** The catalog carries the assembler's own form
  (`faddd`, `fmvdx`) while the examples table and anything a person types carry the canonical one
  (`fadd.d`, `fmv.d.x`), so each table could only be reached by the spelling it happened to use.
  `RVAsmDocMnEqFold` now retries ignoring dots and underscores, as a FALLBACK after an exact
  match fails, so an exact spelling still wins.

`jal` was also missing from the catalog outright while `jalr` was present, so `?` never offered
one of the two core control-flow instructions. The second batch covered the word-width family, the rest of the loads and stores,
the CSR read-modify-writes, the atomics, the double-precision arithmetic and comparisons, the
compressed forms and the system instructions. What is left is mostly aliases and the rarer
encodings, where the motivation is often "this is the same as X with the operands swapped".

---

## Tier 2 — survey leftovers

### 2.1 ~~Generic CSR-by-number reader~~ — DONE, by writing the instruction

`CsrNum(n)` builds `csrr a0, n` + `ret` into a scratch array, fences, and calls it, so all 4096
numbers are reachable and `Csr("0x301")` works. An unimplemented CSR faults and this REPL
recovers to the prompt, which is itself the answer; the comment says not to call it from a trap
handler.

### 2.2 Float registers in the seed image's freeze — TRIED, BACKED OUT, and worth knowing why

A single `fsd` in that image's trap path breaks it: 51 assertions fail and the session stops
part way, while the identical stub with the store removed passes. It is not the address (two
different ones fail), not the base register (`t6` and `a0` both fail), and not the call (an empty
stub in the same place is fine) — it is executing an FP store there, despite the `mstatus.FS`
guard that works in the C runtime.

So that image writes flag=0 at `0x87000F00` and a reader knows its float block belongs to
nobody. Before trying again, find out what the hc_repl image actually does with the FPU at trap
time — `bootstrap/hc_repl/start.hc` sets FS=Initial, so the guard should be passing and the
store should be legal, and one of those two things is not true.

### 2.3 ~~Trace through control flow~~ — DONE for conditional branches and direct jumps

`t` reads the two registers the branch names out of the context, decides, says TAKEN or not, and
moves the cursor. `ret` ends the trace. A jump through a register still needs `t 0x<target>`.

It also refuses instructions that write a register the stepper does not carry — ra, gp, tp, s0.
The first attempt at tracing a real function faulted on `addi s0, sp, 0x20` in the prologue,
which took the prompt's own frame pointer with it.

~~**Still open:** carrying ra and s0 in the context~~ — DONE. They are parked at `ASM_RA_SAVE`
and `ASM_S0_SAVE` and restored exactly the way `sp` is, which is required rather than tidy: the
wrapper is CALLED, so loading the context's ra over the return address strands it, and s0 is the
calling HolyC frame pointer. `AsmUiInCtx` no longer refuses them, so a prologue steps. The
asm-repl smoke now asserts `addi ra,ra,5`, `addi s0,s0,9` and a real `sd ra,8(sp)`, so this is
tested rather than reasoned. gp and tp are deliberately still not carried — nothing a person
steps writes them and they address the runtime's own globals.

---

## Tier 3 — housekeeping, and two decisions that are yours

### 3.1 ~~Two pre-existing reds~~ — both cleared this session

- ~~`fmt-check` red across 40 files~~ — DONE. Reformatted in its own commit, with the kernel
  image byte-identical before and after, so the commit is provably whitespace.
- ~~`kernel-gr` against a stale golden hash~~ — DONE. All six pinned render hashes were read at
  HEAD and in a worktree at `d207eda` and came out identical, which proved the goldens stale
  rather than the renderer broken; gr, cdc, netofdots and blot were re-recorded.

### 3.1b ~~kernel-span hangs~~ — FIXED, and it was the save dialog after all

`PopUp(buf, parent)` waits for its servant with `JobResGet`'s
`while (!Bt(&rqst->flags,JOBf_DONE)) Yield;`. `main` in `tests/exec/cases/kernel_span_demo.hc`
runs its whole setup section *deliberately without* `RVYieldInit` — the comment at the top of
that region says so, because the GetMsg needles there work off pre-queued messages. So `Yield`
switches to nobody, the servant never runs, the job is never DONE, and the wait spins forever at
the first `PopUpFileName`. Everything the smoke asserts is downstream of that one call, which is
why the failure looked like "no output at all". One line fixes it: bring the scheduler up after
the pre-queued-message work and before the popup.

**How the earlier diagnosis went wrong, because the method was the real bug.** The entry that stood here
said the hang was inside `SpanBridge1Init` and that the save dialog was ruled out. Both were
wrong, and the marker bisection that "proved" it was reading a truncated view: the smoke prints
`head -40` of a run whose output is mostly DolDoc scenery, so markers past that line were invisible
and their absence was read as "never reached". Running the image directly and reading the *whole*
capture shows the last line is `PopUpFileName DocPopUp begin` — the original theory, discarded on
bad evidence. It also cost two files' worth of instrumentation in the stock tree
(`Kernel/RVDoc.HC`, `tos/Apps/Span/SpanBridge.HC`) that turned out to be innocent.

The lesson worth keeping: **when a smoke fails, read the full capture before placing a single
marker.** A filtered view is a claim about the output, not the output.

Two things this turned up that are still open:

- `PopUp`'s parent path returns `raw=0` rather than the servant's string; `PopUpFileName` only
  succeeds because its parent-side `FileNameForm` fallback runs. The servant ExePutS path
  (`FileNameForm(...)` resolved as `HTT_FUN` in the servant hash) is still unproven.
- `JobResGet` has no timeout. In an image where the scheduler may not be up, an un-runnable
  servant is an unconditional hang with no diagnostic. A bounded wait that returns 0 and says so
  would have made this a one-minute bug.

### 3.1b-bis — ~~`kernel-span-smoke` IS RED AGAIN~~ — **FIXED** (`10a0a07`), one thing still open

3.1b above says span was fixed by bringing the scheduler up before `PopUpFileName` (`c15a5f7`).
It is red again, and worse than before: the guest now produces **no output at all** before

```
TRAP mcause=0x07 (store-fault) mepc=0x808d54dc mtval=0x0  blob+0xd54dc
```

`blob+0xd54dc` decodes to `0x00b50023` = `sb a1,0(a0)` at **`MemSet+4`**, preceded by
`beqz a2,+20` (the size==0 early out). So the destination is NULL with a non-zero count:
**something calls `MemSet(NULL, x, n>0)` before span prints its first line.**

**It is NOT from the 2026-09-22 session.** The span blob compiled at `HEAD` and at `59f91ec^`
(`ea17b55`) are **byte-identical**, same length and same MD5 — which also demonstrates that the
`KernelC.HH` declarations added in `59f91ec` perturb kernel codegen not at all, despite that
header being included by every kernel build.

So the regression is somewhere in the **24 commits `c15a5f7..ea17b55`**, and the full suite had
not run across any of them. Ten of those touch code the span image links:

```
4976126 b1dc1e0 bb3b2aa 8147b17 6471e75 07bda3e ad7fb16 e9d7a0f 758d06e aea9631
```

**Already ruled out: the FS change journal** (`8147b17`), which was the obvious suspect because
`FsJournalInit` sets `fsj_write_fn = &FsJournalWrite` and so puts the journal on EVERY
`FileWrite`, and it is present in the span image. But `CFsJRec.path` is an inline
`U8 path[FSJ_PATH]`, not a pointer, and `FsJCopyPath` is a hand-rolled byte loop — no `MemSet`
and no null destination. Look elsewhere.

**BISECTED and DIAGNOSED (still unfixed).** `git bisect run` over `c15a5f7..ea17b55` with a
70s QEMU window (the fault is immediate and silent, so the smoke's 300s wall is wasted on every
bad commit) names **`6471e75` as the first bad commit** — the SAME commit that broke
`Compiler_RV.PRJ` and so kept phase3 and the win pair red. One commit caused every red in the
tree.

The mechanism, read out under `riscv64-elf-gdb` (`-S -s`, breakpoints on raw addresses, since
the blob carries no ELF symbols — `$ra` at a breakpoint is how you get a caller here):

```
MemSet(NULL, 0, 0xa0)           <- a2=0xa0 == sizeof(CDrv), which identifies the call site
  <- DrvMakeFreeSlot    `res=&blkdev.drvs[i]; MemSet(res,0,sizeof(CDrv));`
  <- BlkDevAdd          drv_let = 'A'  (a0=0x41)
  <- the RAM-disk mount path
```

and at that breakpoint the globals read:

```
blkdev.blkdevs   = 0x82000430   <- SET (the first heap chunk)
blkdev.drvs      = 0x0
blkdev.let_to_drv[0] = 0x0,  [1] = 0x0
```

**`RVBlkDevTablesInit` (`Kernel/KBootRV.HC:265`) is not atomic, and its guard tests the wrong
thing.** It opens `if (blkdev.blkdevs) return;` and then assigns `blkdevs`, `drvs` and
`let_to_drv` in that order. Execution reached the `blkdevs` store and got no further — `drvs`
AND `let_to_drv[1]` are both zero, and if only the `drvs` store had been lost then
`let_to_drv[1]` would read `0xa0` (`&NULL[1]`), not 0. So the function stopped between its first
and second `CAlloc`, leaving `blkdevs` set. From then on **every** later call early-returns on
the guard, and `blkdev.drvs` is NULL for the life of the image — including inside
`RVMountRAMDisk`, which does call `RVBlkDevTablesInit` and is entitled to assume it worked.

Two things, and the first is done:

1. ~~**Make the init idempotent per-field**~~ — DONE in `10a0a07`. Each field is guarded
   separately, so a half-completed run no longer latches and the next caller finishes the job.
   **`kernel-span-smoke` is GREEN** for the first time since `6471e75`. Verified against eleven
   images that DO mount drives (`kernel-fs`, `redsea`, `dir`, `blk`, `home`, `selfboot`, `load`,
   `fsshell`, `win-serial`, `doctext`, `ode`), where the change is a no-op.
2. ~~**STILL OPEN: what stops it between the two `CAlloc`s.**~~ — **ANSWERED, and it is much
   worse than an ordering bug. Nothing stops it: `RVBlkDevTablesInit` never allocated anything,
   because `blkdev.blkdevs` was ALREADY non-NULL when it was first called. It was non-NULL
   because `Fs->cur_dir = StrNew("/Apps/Span")` in `Cd` had written a STRING POINTER into it.
   See 3.1b-ter.** The text below is what I believed before reading it out, kept because the
   inference was wrong in an instructive way.

   **STILL OPEN (as previously believed):** All three writers of
   `blkdev.blkdevs` (`KBootRV.HC`, `DskAddDev.HC:240`, `DskVirtioRV.HC:248`) assign `drvs` on
   the very next line, so something is unwinding — a throw out of `CAlloc`, or the init running
   on a task that dies. **That is still the real bug.** (1) only stopped it being permanent and
   silent; the image is still doing something surprising at boot, and the next thing it
   interrupts may not be as recoverable. A breakpoint on the second `CAlloc` call site, or a
   `try`/`catch` around the pair that reports rather than swallows, is where to start.

**Why (1) was worth landing even though (2) is the real bug.** A table that reports itself
initialised while half built misleads everyone downstream — it is what made this look like a
`MemSet` bug, and what sent this session hunting through the FS journal. The failure is now
recoverable and, when (2) recurs, it will show up as something other than a wild store into
address 0.

This is the SAME NULL `blkdev.drvs` as the psalmody crash fixed in `45d3fe2`, in a fifth
location — reached through `Mount` rather than task reap, and so not covered by those guards.

### 3.1b-ter — THE REAL BUG: `__task` is 80 bytes and the kernel's `CTask` is not

**`Fs` points at an 80-byte allocation while kernel code writes through it at offsets up to
`sizeof(CTask)`. Every AOT-compiled kernel image has this. It is silent, it corrupts whatever
global the linker happened to place next, and which global that is changes with the layout —
which is why an unrelated 9p commit "caused" a span failure.**

`host/compiler.c:239`:

```c
const char *names[4] = { "__try_top", "__task", "Fs", "Gs" };
...
g->size = i == 1 ? 80 : 8;   // __task: CTask (except_ch, catch_except, except_callers[8])
```

The host compiler bootstraps a MINIMAL `CTask` — just enough for `Fs->except_ch` and the throw
machinery — and reserves **80 bytes (0x50)**. `Fs` is then pointed at it. But the kernel sources
define the REAL `CTask` (`Kernel/KernelA.HH:3280`), which is over a kilobyte, and every
`Fs->member` in kernel code compiles against THAT layout. Counting its members by hand:

```
0x00 addr   0x08 task_signature+win_inhibit   0x10 wake_jiffy   0x18 task_flags+display_flags
0x20 code_heap   0x28 data_heap   0x30 put_doc   0x38 display_doc   0x40 border_doc
0x48 win_left  0x50 win_right  0x58 win_top  0x60 win_bottom  0x68 cur_dv  0x70 cur_dir
```

`cur_dir` is at **0x70 — 0x20 bytes PAST the end of the 80-byte `__task`.**

Read out of a live span image, which is how this was found rather than guessed:

```
Fs (global @0x80ab1ae0) = 0x80a83550   == __task
blkdev                  = 0x80a835c0   == __task + 0x70
Cd -> StrNew("/Apps/Span") -> 0x82000430      (MAlloc#1, the first heap chunk: 0xb bytes)
=> Fs->cur_dir = 0x82000430   lands on   &blkdev.blkdevs
```

So `blkdev.blkdevs` held a pointer to the STRING `"/Apps/Span"`. `RVBlkDevTablesInit`'s
`if (blkdev.blkdevs) return;` saw non-NULL, returned, and `blkdev.drvs` was never allocated —
hence `MemSet(NULL,0,sizeof(CDrv))` in `DrvMakeFreeSlot`. Every link in the chain checks out.

**Why `6471e75` is the "first bad commit".** It did not introduce this. It added
`ninep_client`, which the linker placed at `__task + 0x50`, and that shifted `blkdev` to
`__task + 0x70` — exactly where `Fs->cur_dir` writes. Before it, the stray store landed on
something that did not matter. **A bisect over a layout-sensitive bug names the commit that
re-aimed the damage, not the one that caused it.** Worth remembering the next time a bisect
gives an answer that makes no sense against the diff.

**`10a0a07` did NOT fix this** — it made `kernel-span-smoke` green by letting a later caller
allocate `drvs` while `blkdev.blkdevs` still pointed at `"/Apps/Span"`. That green was masking
live corruption. It is kept because a half-completed init should not latch its own guard
regardless, but the ACTUAL fix is the reserve below, and span is now green for the right
reason.

**FIXED** in `982853e` + `c62421a` + `4405a89`: `TASK_BLOCK_RESERVE` in `host/compiler.c` now
reserves **1280** bytes (the real `CTask` measures **1192**), and `AotCheckTaskBlockReserve()`
fails the compile if a future `CTask` outgrows it. Verified under gdb — `blkdev.blkdevs` and
`.drvs` are both 0 at `RVMountRAMDisk` entry, where `blkdevs` previously held the string — and
by a clean full suite at `4405a89`: **84 pass, 1 fail**.

**The first attempt reserved 8 KiB and that was wrong**, in a way worth recording: the
reservation is emitted as **DATA in every blob**, not as free BSS. 8 KiB pushed
`SoftCmpSrc.BIN` from 2128 to 9504 bytes, over `kernel-thin-loader`'s 4 KiB `SoftCall Load`
cap (it failed in ONE SECOND, which is what gave it away), and broke `kernel-phase3` too. A
five-smoke sanity subset had passed and missed both. The size was then MEASURED rather than
guessed a second time — a temporary env-gated print of `t->size`, removed again.

`Kernel/RVCmpRtPatch.HH` is regenerated by this: every offset moved by exactly 0x4b0
(1280-80), and those are the addresses the kernel uses to patch globals inside the LOADED
`Compiler.BIN`. It has to travel with the reserve change or the loaded compiler gets the wrong
`Fs`/`blkdev`.

The options considered, for the record — (1) and (3) were taken:

1. **Reserve enough for the real `CTask`** — raise the 80 to something that covers it (it is
   >1 KiB; a round 4 KiB is cheap BSS and leaves headroom). Safe, one line, wastes a little
   space in every image.
2. **Re-size `__task` when the kernel's own `class CTask` is parsed**, so the reservation
   tracks the real definition instead of a magic number. Correct, but the bootstrap stub is
   created before parsing, so `__task` would have to be re-placed or forward-referenced.
3. **Make it loud instead of silent** — have the AOT refuse, or warn, when a `Fs->` access
   resolves past the reserved `__task` size. This is the one that would have caught it on day
   one, and is worth doing alongside either of the above.

Note (3) especially: the cost here was not the bug, it was that it was *invisible*. It presented
as a `MemSet` fault in a demo, survived a bisect pointing at an unrelated 9p commit, and took a
watchpoint, a `CAlloc` trace, a `MAlloc` trace and a `StrNew` trace to reach.

### 3.1c The seven reds behind kernel-span, triaged

`qemu-integration` stops at the first failure, so `kernel-span` had been hiding everything after
it. With span fixed, all 85 targets were run (the 28 after psalmody individually, since psalmody
then became the new blocker): **22 of those 28 pass, 6 fail**, plus psalmody itself.

Attribution matters more than the count here, because twice this session a "pre-existing" claim
turned out to be wrong. Each of these was checked rather than assumed.

| red | cause | mine? |
|---|---|---|
| ~~`kernel-win-interactive`~~ | FIXED TWICE: `win_compiler.PRJ` missing `RVAsmRepl.HC`/`RVDbgCore.HC`, then re-broken by the SAME `&NinepSmoke` that took phase3 — green 2026-09-22 | `a4a9e7e`, then `6471e75` |
| ~~`kernel-win-serial-smoke`~~ | same, same | same |
| ~~`repl-9p-smoke`~~ | retired image's feature set — PORTED, green | no |
| ~~`dump-changes-smoke`~~ | same — PORTED, green | no |
| ~~`kernel-psalmody-smoke`~~ | GREEN (`58f088a`). NULL `blkdev.*` derefs fixed, then the real cause: the image mounted nothing, so the app's `PopUpPickDir` resolved `~` into `throw('Drv')`. Demo now does `RVMountRAMDisk` + `RVHomeBringUp` like its sibling | no |
| ~~`kernel-phase3-smoke`~~ | a STALE `Compiler.BIN` the smoke swallowed a failed build for — FIXED, see 3.5 | **yes**, from `6471e75` |
| ~~`kernel-span-smoke`~~ | listed as fixed in 3.1b but RED again — real cause was `__task` reserving 80 bytes for a 1192-byte `CTask`, so `Fs->cur_dir` overwrote `blkdev.blkdevs`. FIXED in the host compiler, see 3.1b-ter | no |
| ~~`kernel-thin-loader-smoke`~~ | GREEN. The cap decision was already made: `fd2bf56` raised the `SoftCall Load` buffer to 4 KiB on 2026-09-21. This row predates it | no |

**The win pair broke twice for the same REASON and it is worth saying once.** `RVExePubs.HC`
plants functions by ADDRESS, so every name it takes a `&` of must be resolvable in whatever unit
includes it. First time (`a4a9e7e`) the missing ones were `AsmStep`/`Dr` and the fix was adding
`RVAsmRepl.HC`/`RVDbgCore.HC` to `win_compiler.PRJ`. Second time (`6471e75`, and it went
unnoticed for a day) the missing ones were `&NinepSmoke` and eight journal names, and the fix
was declaring them in `Kernel/KernelC.HH` — the same root cause that kept phase3 red, because
`win_compiler.PRJ` and `Compiler_RV.PRJ` both include `RVExePubs.HC` without the Kernel bodies.
Verified by putting the pre-fix `KernelC.HH` back and recompiling the win unit: two
`Undefined variable` at `RVExePubs.HC:1324`. **Anything added to `RVExePubs` from now on should
be checked against `Compiler_RV.PRJ` AND `win_compiler.PRJ`, not only the in-image Body.**

The first fix, for the record. `RVExePubs.HC` plants `AsmStep` and `Dr` by
ADDRESS, so the files defining them must be in the unit and ahead of it —
`Compiler_RV_Body.PRJ` does exactly that and the win unit was never updated to match, so it died
on `Undefined variable` at `&AsmStep`.

**~~`repl-9p-smoke` and `dump-changes-smoke`~~ — BOTH PORTED AND GREEN.** They shared one root
cause: `NinepSmoke`, `DumpChanges`, `FsLog`, `FsReplay` and `FsChanges` lived only in the thin
JIT image retired in `080f729`, while both smokes drive `build/repl-holyc.elf`, which
Makefile:271 aliases to the guest Compiler_RV image. `strings` found those names in no built
image. Ported rather than retired, which turned up five real bugs a copy would have missed:

- **`NinePClientWritePathEx` never existed.** `NinePClientWritePath` is single-component and its
  own comment pointed at an `Ex` form that had never been written, so the seed's `NinepWritePath`
  was the only thing in the tree that could create parent directories — nested 9p writes died
  with that image. Implemented in `Kernel/NineP/NinePClient.HC`.
- **The 9p client ignored the negotiated version.** Found by standing up a real Inferno Styx
  server (`listen -A tcp!127.0.0.1!6703 {export / &}`; `styxlisten` needs Keyring built in,
  `listen.dis` does not) and speaking our exact wire format at it: we send `9P2000.L`, it answers
  `9P2000`, and `Tlopen` then gets NO REPLY. `NinePClientVersion` checked type, tag and msize and
  never read the version string, so against any plain-9P2000 server it believed it had `.L` and
  stalled. Now recorded in `CNinePClient.dialect`.
- **`$` is DolDoc markup.** `"A$$B\n"` prints just `A` on this image, so the `$`-delimited dump
  protocol emitted NOTHING at the prompt while working in a standalone image whose `Print` goes
  straight to the UART. Markers now format into a buffer and write delimiters with `PutChars`.
- **Pub arity.** A planted pub carries exactly the arguments it declares; a one-argument pub for
  three-parameter `FsChanges` fed it register garbage.
- **`addrs[36]` and `addrs[37]` were never filled.** The `FileRead`/`FileWrite` pubs are written
  out in `RVExePubsWire` and guarded by `if (addrs[N])`, and nothing ever assigned those slots —
  so the prompt had no route to the filesystem and `FileWrite` returned 0. It looked exactly like
  a broken disk; a boot probe called from kernel code returned `write=3 find=1` and settled it.

The smokes also needed two changes belonging to the retired image rather than the feature:
`ans=` is decimal in the guest Compiler_RV REPL (hex was the thin JIT's), and the input must be
PACED or the line editor drops and reorders characters.

**`kernel-phase3-smoke` — the `r=-85` was a FALSE failure, and fixing it uncovered a hang.**
`KernelCallIcSoft`'s first statement is `if (KernelForSrcSoft() != 0x4653) return -1;`, and
`KernelForSrcSoft` returns -2 when `A:/MakeOS/SoftForSrc.BIN` is absent. Every other probe in
that sequence is wrapped in a `KernelFileFind` skip guard; `CallIcSoft` and `GlblMemSoft` were
not, so they ran unconditionally right after `ForSrcSoft` had been skipped for exactly that
missing file. The inter-function CALL IC logic they exist to test therefore NEVER EXECUTED — the
smoke reported a compiler failure it had not performed. Both are guarded now.

With the guard it clears the whole probe chain and runs on for **367 guest lines**, failing at
the very end of the P6 bisect:

```
RVPhase3: P6 bisect — Guest_Lex index hand Lex Cmp...
    ERROR: Missing expression
```

Every earlier stage passes — class member StrCpy, tiny Guest Cmp, flat Menu_RV_Guest, Lex stub.
So what is left is the GUEST COMPILER failing to compile `Menu_RV_Guest_Lex`, not anything to do
with the filesystem or the probe chain.

**Fixed since:** `Adam/Menu_RV_Guest_Lex.HC` used `continue`, which is a HOST-COMPILER
EXTENSION — `Compiler/CompilerA.HH` says so outright: `#define KW_CONTINUE 48 // RV: host AOT
parity; TempleOS HolyC has no continue`. That file is staged to disk and compiled BY THE GUEST,
so it has to stay inside the language both compilers share. The host accepted it, the guest said
`Missing expression at "continue"`, and that was the whole `Guest_Lex` failure. Rewritten with
an inverted condition; the guest now gets through `Guest_Lex && Soft Cmp` and
`Guest_Lex while(1) Soft Cmp`, and the run goes from 367 guest lines to **682**.

Found by testing candidate constructs straight at the REPL prompt, which runs the same guest
compiler through `ExePutS` — four shapes compiled, the fifth reproduced the exact error. No
rebuild per candidate.

**`continue` is now IMPLEMENTED in the guest compiler** (`Compiler/PrsStmt.HC`), which was the
frontier the probe marked. Smaller than it looked: the keyword was already registered
(`Compiler/AsmInit.HC`, index 48) so the lexer knew it, and only the parser case was missing.
A global with save/restore around each loop body rather than another `PrsStmt` parameter, and
the target differs per loop — `while` re-tests the condition, `do` gets a label after the body,
and `for` must land on the STEP or it hangs instead of miscounting. Verified at the REPL in all
three forms (each returns 3), and gated on exec-oracle's 88 cases plus both REPL smokes.

**phase3 still stops at the Menu Skip probe, and the remaining difference is WHICH COMPILER.**
The same `RVMenuSkipCont` source with `continue` compiles clean at the REPL prompt, which runs
the in-image `Compiler_RV` through `ExePutS`. phase3's `RVPhase3CmpWrite` instead calls through
`rv_phase3_loaded_cmp` — a `Compiler.BIN` LOADED FROM THE REDSEA DISK at runtime. Both are built
from the same sources in the same run (the smoke refreshes `build/Compiler.BIN` from
`Compiler_RV.PRJ` before staging the image), so the next question is why the loaded one behaves
differently from the in-image one: a stale copy on the image, a relocation issue, or a genuine
difference in the loaded path.

**The truncation is not the timeout — the error REPORTER hangs.** `PHASE3_TIMEOUT=900` and
`=1800` both end at exactly 682 guest lines with the same half-written
`Missing expression at ` and no token, preceded by a run of `p?? p?? p??` garbage that looks
like a source-context print going wrong. So the loaded compiler hits an error in the Menu Skip
source and then WEDGES while reporting it.

Localised by reading `Compiler/CExcept.HC`. `LexExcept` does: `Raw(ON)` + "Note: Still in boot
phase." (seen), `PrintErr(str)` -> "Missing expression at " (seen, and the last thing that comes
out), then `AdamErr` only `if (!IsRaw)` — which `Raw(ON)` has just made false, so it is skipped —
then `LexPutPos(cc)`, then `throw`. `LexPutPos` calls `LexPutToken(cc)` and then
`LexPutLine(cc, cc->lex_include_stk->line_start)`, and BOTH walk source text. So the wedge is in
one of those two, which is consistent with a source buffer that is not NUL-terminated (the Soft
Cmp compiles from a string staged to disk) or a pointer that did not survive the relocation the
disk-loaded `Compiler.BIN` goes through.

Next step is to instrument the loaded compiler's `LexPutPos` — the in-image one can be driven
straight from the REPL for comparison, since the same source compiles there without error.

That second half is the more serious bug, and it is what actually keeps phase3 red. A failed
Soft Cmp is supposed to return non-zero so `RVPhase3CmpWrite` prints its BLOCKED message and the
sequence carries on — every other probe in the ladder does exactly that. Instead the guest stops
dead, so no expectation after this point can ever be met no matter what else is fixed. Worth
attacking before the underlying parse difference, because a compiler whose error path hangs will
hide the next finding too.

**The original frontier probe, for the record.** `Kernel/RVPhase3.HC:2040` says
`// Soft tip: stock Menu Skip shape (U8* while + continue) — needs KW_CONTINUE`, and that stage
compiles a snippet containing `continue` on purpose, to mark the feature that is not implemented
yet. So finishing phase3 means IMPLEMENTING `continue` in the guest compiler.

Sketch, from reading how `break` works. `Compiler/PrsStmt.HC:1149` is:

```
case KW_BREAK:
  Lex(cc);
  if (!lb_break) LexExcept(cc,"'break' not allowed\n");
  ICAdd(cc,IC_JMP,lb_break,0);
```

`lb_break` is threaded as a PARAMETER through `PrsStmt(cc,try_cnt,lb_break)` and
`PrsIf(cc,try_cnt,lb_break)`. `continue` needs the same treatment with a second label, and the
target is not the same for every loop: `while` continues at the condition, but `for` must jump
to the STEP, not the top, or the loop never advances. So each loop publishes its own
continue-label and the signature carries both. Mechanical, but it touches the statement parser
of the compiler everything else is built on, so it wants its own session and its own
byte-identical check.

**Read `/tmp/phase3_uart_final.txt`, not the make output.** The smoke writes the complete guest
capture there (`PHASE3_UART_OUT`), while `make` shows only the lines the smoke chose to print. I
spent a cycle concluding this "hangs in `KernelFileFind` on `A:/Compiler/SoftLocal.HC`" purely
because the make output stopped there — markers placed either side of that call both appear in
the full capture, at lines 90 and 91. That is the SAME mistake as the kernel-span misdiagnosis
at the top of this file, made again at the other end of the same session.

Two more things this leaves open:

- **Nothing currently exercises `CallIcSoft`/`GlblMemSoft`.** The eleven `Soft*Src.BIN` are
  staged only on the thin-loader smoke's disk, while the sequence that consumes them runs in
  phase3, whose image carries none. Staging them on phase3's RedSea image would restore real
  coverage. Note the ordering trap: phase3 runs BEFORE thin-loader in `qemu-integration`, so it
  could only ever have found those files left over from an earlier run.

**`kernel-thin-loader-smoke`** is also a decision, not a bug. `kernel_lex_src_probe.hc` has not
changed since `a15ae20`; it grew past the cap because CODEGEN grew, and the 2 KiB is a real
limit on what `SoftCall Load` accepts, not a test assertion to bump. Shrink the probe or raise
the loader's capacity.

### 3.2 ~~No full suite run in a long while~~ — DONE. **85 pass, 0 fail at `58f088a`**

**The whole suite is green.** All 85 `qemu-integration` targets, run individually, at
`58f088a` with the tree frozen for the entire sweep (HEAD committed 06:53, suite 07:35–09:59,
working tree clean throughout), so this describes `HEAD` exactly.

Nothing is red. That includes every target this session touched — `kernel-phase3-smoke` (949s),
`kernel-span-smoke` (302s), `kernel-psalmody-smoke` (122s), `kernel-thin-loader-smoke` (92s),
the win trio — and the two gates that matter most for the `__task` layout change:
`exec-oracle`'s 88 execution cases (774s) and `kernel-gr-smoke`'s six pinned render hashes.

Where it started, for scale: this file opened the session describing **seven reds**, with
`kernel-phase3-smoke` red for eleven days behind a diagnosis that turned out to be built on a
stale binary. Three of those seven rows were already wrong — two fixed, one newly broken — and
only running all 85 could tell them apart.

#### The previous run — **84 pass, 1 fail at `4405a89`**

**Re-run clean after the `__task` fix**, with the tree frozen for the whole run (HEAD committed
20:35, suite 20:36–22:55, working tree clean throughout), so this one describes `HEAD` exactly:

```
FAIL     122s  kernel-psalmody-smoke        <- the only red; designed throw('Drv'), see 3.1c
```

Everything else passes, including `kernel-span-smoke` (302s) for the first time since
`6471e75`, `kernel-phase3-smoke` (939s), `kernel-thin-loader-smoke` (93s), the win trio,
`exec-oracle`'s 88 cases and `kernel-gr-smoke`'s pinned render hashes — the last two being the
gates that matter most for a change that moves every AOT image's data layout.

*(An earlier attempt at this re-run was DISCARDED at 77/85 rather than reported: I edited
`host/compiler.c` while it was in flight, so its later targets rebuilt against a different
compiler and the results were mixed. Do not edit sources during a sweep — I had avoided exactly
that earlier in the same session and then did it anyway.)*

#### The previous run — **83 pass, 2 fail at `4d17bf7`**

All 85 `qemu-integration` targets, run INDIVIDUALLY so one red could not hide the rest
(`qemu-integration` itself stops at the first failure, which is how `kernel-span` hid everything
behind it last time). ~2h40m wall clock.

**Read the commit in that heading.** The sweep finished at 14:06 and `45d3fe2` (four kernel
source files) landed after it, so 83/2 describes the tree at `4d17bf7`, NOT `HEAD`. The three
commits during the run were docs-only, so the result is valid for the code it saw. `45d3fe2` was
then spot-checked against the targets that execute `PopUp` or the drive-letter path —
`kernel-fs`, `kernel-redsea`, `kernel-dir`, `kernel-win-serial`, `kernel-doctext`, `kernel-ode`,
`kernel-win-smoke`, `kernel-win-interactive`: all pass; plus `psalmody` and `span`, which are
the two reds below. That is a spot check, not a sweep.

*(Saying this because the session's own lesson — [[artifact-is-not-proof-of-build]] — is that an
artifact is not evidence the tool that makes it ran. A suite result is likewise not evidence
about a tree that changed after it ran, and a bare "DONE, 83 pass" invites exactly that
misreading a month from now.)*

```
FAIL     303s  kernel-span-smoke
FAIL     122s  kernel-psalmody-smoke
```

The psalmody failure recorded here is the OLD one (`mcause=5 mtval=0x60`); it predates
`45d3fe2`, which fixed that deref and two others. At `HEAD` psalmody fails later and
differently — see 3.1c.

**Everything else passed**, including the three this session fixed — `kernel-phase3-smoke`
(949s), `kernel-win-interactive` (162s), `kernel-win-serial-smoke` (91s) — in a clean
from-scratch sweep rather than a targeted re-run.

**The 3.1c triage table was wrong in three places**, all now corrected there:

- the win pair and phase3 are green (this session's `KernelC.HH` fix);
- **`kernel-thin-loader-smoke` is green** and was NOT an open decision. The table framed it as
  "`SoftLexSrc.BIN` 2128 > 2 KiB loader cap — shrink the probe or raise the cap". That decision
  had ALREADY been made and shipped in `fd2bf56` ("thin-loader: raise the SoftCall Load buffer
  to 4 KiB", 2026-09-21), which is in HEAD's history. The row simply predates it;
- `kernel-span-smoke` is red while listed as fixed — see 3.1b-bis.

The lesson is the one this file keeps relearning in a new costume: **a table of reds decays, and
nothing tells you which rows went stale.** Two rows had been fixed and one had broken, and the
only thing that distinguished them was running all 85.

### 3.3 Small

- `templeos-riscv/build/` is untracked and noisy in `git status`; it wants a `.gitignore` line.
- The branch is 110+ commits ahead of `github/archive` and has never been pushed.
- `.gitignore`'s `debug_*` matches case-insensitively on this filesystem, which silently swallowed
  a documentation file for a whole session. Worth a narrower pattern.

---

## Tier 3.5 — ~~instrument the loaded compiler's error path~~ — DONE, and it was a STALE BINARY

The wedge is gone. `kernel-phase3-smoke` ran **682 → 832 guest lines**, the `Menu Skip Soft Cmp`
stage now compiles AND calls (`SkipCont='x'`), and no `LexExcept` fires at all. There was no
relocation bug, no unterminated source buffer, and no difference between the two compilers.
One of them was simply OLDER THAN THE SOURCE UNDER TEST.

### What was actually wrong

`Compiler_RV.PRJ` — the standalone unit that becomes the disk-loaded `Compiler.BIN` — had been
RED since `6471e75` (2026-09-21 17:37). The 9p/journal port added pubs that `RVExePubs` plants
BY ADDRESS (`&NinepSmoke`, `&FsChanges`, `&FsLog`, `&FsReplay`, `&DumpChanges`, `&Recover`,
`&FsRecover`, `&FsEpoch`, `&Rename`), and that unit compiles WITHOUT the Kernel bodies, so it
died on `Undefined variable`. Exactly the shape that took the win pair red in `a4a9e7e` — and
the entry at 3.1c even says so: *"`RVExePubs.HC` plants `AsmStep` and `Dr` by ADDRESS, so the
files defining them must be in the unit and ahead of it."* The same trap, one file later.

The smoke then **swallowed** it:

```
if HOLYC_INCLUDE_ROOT=... "$COMPILER" .../Compiler_RV.PRJ -o .../compiler_rv.blob.bin >/dev/null 2>&1; then
  :
fi
if [ -f .../compiler_rv.blob.bin ] && [ -f .../compiler_rv.map ]; then
  .../pack_compiler_bin.sh ... || true
fi
```

A failed build leaves the previous blob on disk, and the pack step happily repacked it.
`build/compiler_rv.blob.bin` was dated **2026-09-21 15:17**; `continue` landed **2026-09-22
07:36**. So for a day phase3 loaded a compiler that had never heard of `continue`, while the
in-image `Compiler_RV_Body` was rebuilt from source on every run. That is the whole of
"the disk-loaded compiler rejects source the in-image one accepts".

Fixed in `59f91ec`: the nine names are declared in `Kernel/KernelC.HH` the way `FileRead` is at
line 373, so the standalone unit resolves them as imports and the Kernel supplies the real
addresses at Load time. Both smokes now hard-fail instead of swallowing, and phase3 additionally
asserts that `build/Compiler.BIN` is newer than every `Compiler/` source — the next variant of
this is a build that succeeds while the pack step quietly does not.

### What the previous entry got wrong, and why

Its premise was a single sentence: *"Both are built from the same sources in the same run (the
smoke refreshes `build/Compiler.BIN` from `Compiler_RV.PRJ` before staging the image)."* The
smoke does attempt that refresh. It just does not check whether it worked. **Every conclusion
downstream of that sentence — relocation, `line_start` with no NUL, `LexPutToken` vs
`LexPutLine` — was reasoning about a binary nobody had rebuilt.**

This is the THIRD entry in this file to be wrong for the same underlying reason: a claim read off
output that was not what it appeared to be. `kernel-span` read a `head -40`; the
`KernelFileFind` hang read the `make` output instead of the full capture; this one read a
build log that was routed to `/dev/null`. The lesson generalises past "read the whole capture":
**an artifact is not evidence that the tool which was supposed to produce it ran.** Check the
mtime, or make the producer fail loudly.

Two smaller corrections to the record:

- The `p?? p?? p??` run before the ERROR line was not "a source-context print going wrong". It
  is `PrintErr`'s own prefix — `Kernel/StrPrint.HC:920` formats
  `"%,p %,p %,p %,p " ST_ERR_ST "%s"` with four `Caller` frames. Expected noise.
- The in-image control (`1+;` at the REPL of `build/repl-holyc.elf`) takes the **non-Raw**
  branch: `sys_run_level` has `RLf_ADAM_SERVER` there, so `LexExcept` never calls `Raw(ON)` and
  `LexPutPos` goes through `PutFileLink`/`AdamErr` instead. phase3 takes the `IsRaw` branch. The
  two paths are not the same, so a clean REPL recovery never proved anything about phase3.

### Still open, in the order they now matter

**RESOLVED 2026-09-24 — see START HERE.** The diagnosis below is right about the symptom and
wrong about the cure: it was TWO bugs in series, and the proposed one-line flag change cannot
work (`AsmResolve` never drains a record hung on an `cmp.asm_hash` entry). A4c now returns
ground truth and rungs A1-D pass. The entry is kept because the eliminations in it hold.

**a-ROOT CAUSE (2026-09-23, final for this session): a PLANTED GLOBAL resolves
MODULE-RELATIVE in guest-compiled BINs, and A1-A3 were FALSE PASSES.**

Proved read-only by rung A4c, which returns the decayed address and writes nothing:

```
kernel &doldoc.dft_de_flags = 0x80A708A0
guest  returned             = 0x832F3018     <- heap/module region
```

`Compiler/PrsExp.HC` ~910, AOT path, routes a global three ways -- `GVF_IMPORT` ->
`IC_ADDR_IMPORT`, `GVF_DATA_HEAP` -> `IC_HEAP_GLBL`, else ->
`ICAdd(cc,IC_ABS_ADDR,tmpg->data_addr_rip,tmpc)`. The plant
(`Compiler/RVExePubs.HC:449,1171`) sets `tmpg->flags = GVF_ALIAS` and fills `data_addr`
but never `data_addr_rip`, so it falls to the ABS_ADDR branch, gets patched with
`module_base` at Load, and points inside the module. A4 then `MemSet`s 344 bytes over its
own code with that pointer, which is the entire "hang".

**A1-A3 have been passing against the wrong memory.** They only check SELF-CONSISTENCY --
store then read back, or non-zero -- which a uniformly wrong base satisfies. This is not a
hypothesis: the experiment below corrected the address and **A1 immediately began failing
honestly** with `r=2` (`!doldoc.hash`), because the real `doldoc.hash` is 0 there while the
module bytes it used to read were not. A ladder whose rungs compare a value with itself can
be green all the way up a wall that is not there.

**ATTEMPTED FIX, REVERTED, and worth repeating properly.** Marking the plant
`GVF_ALIAS | GVF_IMPORT` at both sites routes it through `IC_ADDR_IMPORT`, which
`LoadOneImport` already resolves for `HTT_GLBL_VAR` by name to `->data_addr` -- the
machinery is all there. Result: A1 failed honestly (above), A2 and A3 still passed, and
**A4a then KTRAPed during Soft Cmp** -- the guest compiler itself faults while compiling
against an import-flagged planted global. So the direction is right and the emit path is
not ready for it. Next session: find why `IC_ADDR_IMPORT` on a planted `HTT_GLBL_VAR`
faults the compiler, fix that, then re-apply the two-site flag change and run the full
suite, expecting A1 to need a real fix rather than its old false pass.

**a-CORRECTION #2 (2026-09-23, supersedes both notes below): the BIN on DISK is COMPLETE.
`Load` loses the body. It is not a codegen bug and not a parser bug.**

Ran phase3 keeping the disk image, then read the BIN as guest `Cmp` wrote it, before `Load`
ever touched it. The code at `0x2578a4`, immediately followed by the export name
`RVDocInitA4SelfTest` so it is unambiguously this BIN, decodes to a whole function:

```
e7 80 02 00   jalr ra,0(t0)      <- the call
13 01 84 fd   addi sp,s0,-40
13 01 81 01   addi sp,sp,24
13 05 10 00   li   a0,1          <- return 1
83 30 01 00   ld   ra,0(sp)
03 34 81 00   ld   s0,8(sp)
13 01 01 01   addi sp,sp,16
67 80 00 00   ret
```

Corroborating: scanning the whole disk for the `addi sp,sp,-16; sd ra,0(sp)` prologue finds
**118 occurrences and not one is followed by zeros**. There is no "empty function" anywhere on
that disk. The zeros exist only in the LOADED image.

So `62bbf70`'s "guest codegen bug -- the BIN's function body is empty" is WRONG, and so is the
whole parser hunt that followed from it. **Look at `Load` / `LoadOneImport` in
`Kernel/KLoad.HC`**, and at why A4 specifically loses its body when A4b (also an import call,
plain global array) does not -- the difference is the relocation/patch entries the two BINs
carry, which is squarely loader territory.

Cheap next probe, in the same style that produced this: the on-disk BIN and the loaded image
can both be dumped, so diff them. If the loaded copy is truncated at a fixed offset, the copy
loop is wrong; if it is patched to zeros, a relocation is writing over code.

**Method note, because this is the third wrong turn in this entry alone.** "The loaded image is
zeros" was a real measurement, and I generalised it to "the compiler emitted nothing" without
checking the artifact one step upstream. Reading the BIN off the disk cost ONE run and
invalidated two commits' worth of reasoning. **When an artifact looks wrong, inspect it at
every stage it passes through before blaming the stage that produced it.**

The superseded notes follow, kept because the eliminations in them still hold (A4a and A4b are
good rungs, and the `argv` site really is the wrong site):

**a-CORRECTION (2026-09-23): A4 is a guest CODEGEN bug, and my first parser lead was wrong.**
The loaded A4 image is an 8-byte prologue followed by zeros, while guest Cmp reports
`Errs:0 Warns:0 Code:A8` -- it saved `ra`, knew a call was coming, and emitted no body. Read
out of a live guest under gdb; see `62bbf70`.

Triangulated by two new rungs so the trigger is pinned, not described:

| rung | shape | result |
|---|---|---|
| A4a | `sizeof` on the planted member, no call | OK |
| A4b | import call, plain global array argument | OK |
| A4  | import call, PLANTED MEMBER array as argument | empty body |

A3 (indexed store into the same member) also passes, so the plant's size/dims/stride are fine.
What A4 uniquely needs is the member's ADDRESS -- array decay -- as a call argument.

**`875367a` named `PrsExp.HC` ~805/~828 and its hardcoded `StrCmp(tmpm->str,"argv")`
exception as the candidate. That is the WRONG SITE.** Those lines are the `IC_RBP`
local-variable member path; `doldoc` is a global, so `doldoc.dft_de_flags` goes through the
`um_join` / `.` case at ~1027 instead, which behaves the opposite way -- it KEEPS `CCF_ARRAY`
and materialises the address:

```
tmpc1 = tmpm->member_class+1;
ICAdd(cc,IC_IMM_I64,tmpm->offset,tmpc1);
cc->flags &= ~(CCF_RAX|CCF_ARRAY|CCF_FUN_EXP);
if (tmpm->dim.next) { *_tmpad=tmpm->dim.next; cc->flags|=CCF_ARRAY; }   // stays SET
ICAdd(cc,IC_ADD,0,tmpc1);
```

So the `argv` exception is not on this path at all. Correcting it here rather than leaving it
because a plausible-but-wrong lead is exactly what this file keeps paying for -- the same
mistake as the `FilesFindMatch` symbol and the `RVExePubInternDolDocIn` note.

**The next step needs INSTRUMENTATION, not more reading.** Three plausible sites have now been
read and two eliminated by argument alone, which is how the last three wrong diagnoses in this
file were produced. `Kernel/RVPhase3.HC` already carries machinery for exactly this
(`RVPhase3DumpOpt6IdentFus`, the `PrsIdent DEREF.cls_raw` / `AsgIdent pt` / `Opt6Fus` dumps):
add one that dumps the IC stream for the A4 argument expression, and let the compiler say what
it emitted instead of inferring it from source.

**Fast-loop warning.** The REPL does NOT work for this, though the `continue` frontier was
cracked that way. `build/repl-holyc.elf` has no planted `doldoc` (member reads echo and never
evaluate) and rejects the `import` with "import not needed", because `MemSet` is already a
real symbol there. That precedent was plain language constructs; this needs a planted global
AND an import, and only phase3 has both.

**a. The A4 hang — the new frontier, at 832 guest lines.** The `DocInitStock` ladder gets rungs
A1–A4 through Soft Cmp and A1–A3 through Soft Call, then wedges after printing
`A4 (sizeof member decay) Soft Cmp OK.` Identical output at `PHASE3_TIMEOUT=600` and `=1500`, so
it is a wedge, not a slow compile. It is a LATE wave by design, placed after the StartOS needles
precisely so a rung hang cannot cost them — so it does not keep the smoke red. The comment in
`Kernel/RVPhase3.HC` that blamed `RVExePubInternDolDocIn` for an A2 failure has been corrected;
A2 was the stale binary too.

**ANSWERED (2026-09-23), and it was neither of the two suspects below.** `24f893e` reports
`Load` and `Call` separately (and removes two silent `return`s where a failed Load looked
identical to a hang). A4 prints `Load OK; Call...` and then stops, so `Load` and the signature
are fine. **But it is not a hang at all.** Sampling the spinning guest under gdb -- attach to
`:1234` mid-run and read `$pc`, three times, all identical -- gives:

```
=> 0x820cf694:  j 0x820cf694                          <- park loop, jump to self
   MCAUSE=0x2 (illegal instruction) MEPC=0x832b0008 MTVAL=0x0
   0x832b0000: unimp unimp unimp unimp                <- zeros, not code
```

Control reached `0x832b0008`, which holds ZEROS, took an illegal-instruction trap, and the
handler parked forever. `ra == mepc`, so it is a return or jump into a non-code address: **the
A4 export is not resolving to loaded code.** Why that address is wrong when `Load` reports OK
and the signature checks out is the open question, and it is a different question from the one
this entry started with.

**The park is the real lesson.** It is why this read as a hang through an entire investigation,
and it is the same shape as everything else in this file: silence that looks like progress.
**Fix that first** -- phase3's trap path should print `mcause`/`mepc`/`mtval` the way
`tests/exec/harness/crt0.S` already does instead of spinning in `j .`. Every future phase3
crash then names itself, and this entry would have been one line instead of a day.

The original caution, which was right to make but resolved the other way:

**Do not call this "the A4 Soft Call hang" yet — that is the assumption this file keeps making.**
`RVPhase3DocInitStockRung` does `Load(bin,...)`, THEN checks the signature, THEN the guarded
call. The last output is from before all three, so the wedge is in `Load` or in the call, and
nothing so far distinguishes them. One UART marker between `Load` and `RVPhase3CallExport`
settles it, and it should be placed before any theory is built on either.

Two suspects, one for each side of that marker:

- **`Load`.** A4 is the FIRST rung whose BIN carries an import (`import U8 *MemSet(...)`); A1–A3
  have none at all. So A4 is also the first time Load has to resolve an import for a rung. The
  ladder does `RVCmpExportOne("MemSet", &MemSet)` up front, so the name should be there — but
  "should be" is what needs checking, and it is a clean A3/A4 difference that has nothing to do
  with the rung's stated subject.
- **The call, via array-member decay.** `sizeof(doldoc.dft_de_flags)` is guarded exactly
  (`!= 8 * DOCT_TYPES_NUM` returns 2), and the plant in `Compiler/RVExePubs.HC` does set both
  `m->size = 8*43` and `RVExePubMemberDim(m, 43)`, so a wrong `sizeof` would soft-fail with
  `r=2` rather than hang. That leaves `MemSet(doldoc.dft_de_flags, 0, ...)` — the array member
  DECAYING to an address as a `CALL_IMPORT` argument. If the guest emits a LOAD of the member
  instead of its ADDRESS, MemSet gets a stored value as its destination and writes 344 bytes
  somewhere wild. A3 proves the member's base address is right for a const-index store, so
  decay-as-argument is the untested part.

**b. The error reporter's hang was never demonstrated against a fresh compiler.** The markers
placed in `LexExcept`/`LexPutPos` for this session fired ZERO times, because no compile error
occurred. So the claim "its error reporter hangs instead of returning" is UNRECONFIRMED, not
disproved — the concern stands (a reporter that wedges hides the next finding), but there is
currently no reproduction. The way to settle it is a phase3 probe that compiles deliberately
invalid text and asserts the stage returns BLOCKED; that is a better gate than the accidental
one we had, and it is a separate piece of work.

**c. The `*_SEED` family is not emitted by the image any more.** `EXPECT_STARTOS_SEED`
("`RVPhase3: StartOS RedSea seed (no ELF FileWrite).`") was in the HARD gate chain from
`3bd4279` (2026-09-11) onward while nothing in the tree emits it — `RVPhase3.HC:894` FileWrites
`A:/Adam/StartOS.PRJ` unconditionally rather than preferring the staged RedSea seed. That alone
made this smoke unconditionally red regardless of guest behaviour. It is now soft, alongside
every one of its siblings (`ADAMCORE_SEED`, `MAKEOS_SEED`, `RUNTIME_*_SEED`), which are all
equally unemitted; the live hard proof of that stage is `EXPECT_STARTOS_BIN`. **Open question:**
whether the seed-preference path should come back at all. The seed file
(`tests/exec/seeds/phase3_StartOS.HC`) and the kernel's own `src` are byte-identical, so the
message only ever proved provenance — "the ELF did not have to carry it".

**d. Nothing exercises `CallIcSoft`/`GlblMemSoft`** — unchanged from before. The eleven
`Soft*Src.BIN` are staged only on the thin-loader smoke's disk, while the sequence consuming
them runs in phase3, whose image carries none, and phase3 runs BEFORE thin-loader in
`qemu-integration` — so it could only ever have found them left over from an earlier run.
Staging them on phase3's RedSea image restores real coverage.

---

## Tier 4 — later projects

### 4.1 Run the JIT on Linux and macOS

[HOSTED_JIT.md](HOSTED_JIT.md). The JIT only ever runs bare metal, where every hard platform
question is either answered by us or does not arise. Running it as an ordinary userspace process
forces it through real ABIs and APIs instead: SysV and AAPCS64, Darwin arm64 passing variadic
arguments on the STACK (and HolyC is varargs-heavy), `MAP_JIT` and
`pthread_jit_write_protect_np` on Apple Silicon, `sys_icache_invalidate` in place of `fence.i`,
signals and `ucontext` in place of `mtvec`, and an `mmap` address in place of `jit.hc`'s
hardcoded `JIT_BASE 0x84000000`.

Two things it buys beyond the ABI exercise: it takes QEMU out of the inner loop, which is what
makes the generators in [VERIFICATION_PLAN.md](VERIFICATION_PLAN.md) affordable at the case
counts that make them worth running; and it gives the multi-arch seam a native referee, since an
AArch64 backend can be checked against this machine rather than against an emulator's model of
it. Staged H0..H4, with the 88 existing execution oracles as a conformance suite that does not
have to be written.

---

## If you want a recommendation

**`kernel-psalmody-smoke` — two NULL derefs FIXED (`45d3fe2`); what is left is not a bug in
the kernel.** After the guards the run advances twice and ends at `throw('Drv')` from
`Let2Drv`: `Let2Let('~')` now returns `blkdev.boot_drv_let`, which is 0 in an image that mounts
nothing, so no letter is in `'A'..'Z'` and the designed error path fires. That is a
diagnosable throw where there were two wild stores into low memory. Finishing the smoke is a
DEMO/IMAGE question — psalmody drives a drive-dependent popup path (`PopUpPickDir`) in a
driveless image — so either give the image a drive or have the demo not take that path.

The diagnosis below is kept because the METHOD is the reusable part.

**How it was found: `PopUp` derefs `blkdev.drvs` without checking it.**
Re-checked against a fresh compiler it fails differently from the table's old note ("servant
needs the guest compiler"): `mcause=5` load-fault, `mtval=0x60`, at `blob+0x6bc28`, right after
`PopUpPickDir DocPopUp begin`. Localised to a single instruction:

```
0x6bc1c  ld   t0,0(sp)      ; pop base
0x6bc24  add  a0,t0,t1      ; base + member offset
0x6bc28  ld   a0,0(a0)      ; <-- mcause=5, mtval=0x60
```

`a0` is exactly `0x60`, so the base was NULL and the member offset was `0x60`. That is
`Kernel/Job.HC:421`, in the soft-reap loop `PopUp` runs after `Kill(task,FALSE)`:

```
for (i=0;i<DRVS_NUM;i++) {
  dv=&blkdev.drvs[i];
  if (dv->owning_task==task) {      // <-- offsetof(CDrv,owning_task) == 0x60
```

`CBlkDevGlbls.drvs` is a POINTER (`CDrv *drvs`), not an inline array, and it is only ever
allocated by a mount/boot path — `CAlloc(sizeof(CDrv)*DRVS_NUM)` in `DskAddDev.HC:241`,
`DskVirtioRV.HC:249`, `KBootRV.HC:271`. The psalmody image mounts nothing, so `blkdev.drvs`
stays NULL and `&blkdev.drvs[0]` is NULL. Counting the CDrv members by hand puts `owning_task`
at 0x60, which is `mtval` exactly. `blkdev.blkdevs` in the loop immediately below it is a
pointer too and has the same exposure.

The fix is a guard on each loop. Note what it is guarding: the comment above says
*"Orphaned Drv/BlkDev locks -> FilesFind DrvLock Yield forever"*, so the loop was added to cure
a hang and introduced a null deref for every image WITHOUT drives.

**Watch the flags when you reproduce this.** The smoke compiles with `HOLYC_NO_TIER2=1`
(`run_kernel_psalmody_smoke.sh:36`). A map regenerated without it has a completely different
layout and resolves `blob+0x6bc28` to `FilesFindMatch` — a real function, a plausible story, and
entirely wrong. The instruction at that offset was `li a0,0`, which cannot fault; that mismatch
is what caught it. **Disassemble the faulting word and check it is actually a load before
trusting any symbol.**

(`kernel-thin-loader-smoke` is the other red and remains a DECISION — shrink the probe or raise
the 2 KiB `SoftCall Load` cap — not a bug.)

**Start at 3.5(a), the A4 Soft Call hang**, if you want to keep pushing phase3: it is the live
frontier at 832 guest lines and it is a wedge rather than a slow compile, so it is reproducible
in one run. **Or start at 3.5(b)**, the unreconfirmed error-reporter hang, by writing the
deliberately-invalid-source probe — that turns a thing we merely believe into something gated,
and a reporter that wedges would hide finding (a) too.

Before either, **3.2 — run the full suite.** It has not run in ~25 commits, and this session is
the argument for it: the thing that kept phase3 red was a unit that stopped building a day
earlier and said nothing. A green smoke is not evidence that its inputs were rebuilt.

The previous recommendation stood here: *"Start at Tier 3.5. It is the only red left, it is
reduced to two named functions with a working control."* Both halves of that were wrong — the
two named functions were innocent, and the "working control" took a different branch. It is
kept as a reminder of how confident a wrong diagnosis can read.

The original recommendation, from when this file was written: 0.1 first, because it is a
correctness bug in the surface everything else is added to, and it is cheap to find. Then 1.1,
because the newline rule in the REPL is the thing you would feel every time you typed. Then 1.3,
because it ends the recurring "I do not see X" — everything is on a page, and the page has a
name. All three are done.
