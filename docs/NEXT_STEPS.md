# What is left

Written 2026-09-18, at the end of the session that built the register sidebar, merged the CSR
decoders, widened the freeze and added the newline rule. Ordered by what is *wrong* first, then
by what was asked for and is only half done, then by size. Companion to
[MACHINE_STATE_SURVEY.md](MACHINE_STATE_SURVEY.md), which is the inventory this draws from.

---

See also [VERIFICATION_PLAN.md](VERIFICATION_PLAN.md) — property testing, fuzzing and the two
or three places where a weakest-precondition argument is worth the trouble. Its first two steps
(fuzz the host compiler; generate instructions from the catalog and check them against GNU `as`)
are cheap enough to slot in beside any of the tiers below.

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

### 1.4 AsmDoc motivation covers 178 of 244 instructions

`AsmClasses` / `AsmClass` and the REPL's `p <class>` now exist, so a family can be worked
through one instruction at a time — which makes the missing motivation entries more visible, not
less. The classes are curated lists in `Kernel/RVExplore.HC`.

The structure is done and adding one is a single line. The remaining 66 are writing, not
engineering.

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

### 3.2 No full suite run in a long while

`make ci` / `qemu-integration` has not run in roughly 25 commits. Everything here was verified by
the affected smokes — the asm REPL UI, both trap-frame smokes, hc_repl, repl-exepubs, the
oracles (88 rv64, 62 rv32), the assembler differentials — but not by the whole thing at once.

### 3.3 Small

- `templeos-riscv/build/` is untracked and noisy in `git status`; it wants a `.gitignore` line.
- The branch is 110+ commits ahead of `github/archive` and has never been pushed.
- `.gitignore`'s `debug_*` matches case-insensitively on this filesystem, which silently swallowed
  a documentation file for a whole session. Worth a narrower pattern.

---

## If you want a recommendation

0.1 first, because it is a correctness bug in the surface everything else is added to, and it is
cheap to find. Then 1.1, because the newline rule in the REPL is the thing you would feel every
time you typed. Then 1.3, because it ends the recurring "I do not see X" — everything is on a
page, and the page has a name.
