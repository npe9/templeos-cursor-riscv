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

### 3.1b-bis — `kernel-span-smoke` IS RED AGAIN (found 2026-09-22 by the full suite)

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

**How to finish it.** Bisect `c15a5f7..ea17b55` running `make kernel-span-smoke` (~5 min a step,
so ~5 steps). Reproduce the map with the smoke's own flags — `HOLYC_NO_TIER2=1`
(`run_kernel_span_smoke.sh:38`) — or the symbol will be wrong; see the psalmody entry below for
what that mistake looks like. Naming the CALLER is the hard part, since the blob carries no ELF
symbols and there is no backtrace; the cheapest route is a marker at the top of each init the
demo runs before its first print.

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
| `kernel-psalmody-smoke` | two NULL `blkdev.*` derefs FIXED in `45d3fe2`; now ends at `throw('Drv')` from `Let2Drv` — the DESIGNED error path, because the image has no drives. A demo/image question, no longer memory safety | no |
| ~~`kernel-phase3-smoke`~~ | a STALE `Compiler.BIN` the smoke swallowed a failed build for — FIXED, see 3.5 | **yes**, from `6471e75` |
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

### 3.2 ~~No full suite run in a long while~~ — DONE 2026-09-22: **83 pass, 2 fail at `4d17bf7`**

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

**a. The A4 hang — the new frontier, at 832 guest lines.** The `DocInitStock` ladder gets rungs
A1–A4 through Soft Cmp and A1–A3 through Soft Call, then wedges after printing
`A4 (sizeof member decay) Soft Cmp OK.` Identical output at `PHASE3_TIMEOUT=600` and `=1500`, so
it is a wedge, not a slow compile. It is a LATE wave by design, placed after the StartOS needles
precisely so a rung hang cannot cost them — so it does not keep the smoke red. The comment in
`Kernel/RVPhase3.HC` that blamed `RVExePubInternDolDocIn` for an A2 failure has been corrected;
A2 was the stale binary too.

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
