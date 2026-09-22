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

### 3.1c The seven reds behind kernel-span, triaged

`qemu-integration` stops at the first failure, so `kernel-span` had been hiding everything after
it. With span fixed, all 85 targets were run (the 28 after psalmody individually, since psalmody
then became the new blocker): **22 of those 28 pass, 6 fail**, plus psalmody itself.

Attribution matters more than the count here, because twice this session a "pre-existing" claim
turned out to be wrong. Each of these was checked rather than assumed.

| red | cause | mine? |
|---|---|---|
| `kernel-win-interactive` | `win_compiler.PRJ` was missing `RVAsmRepl.HC`/`RVDbgCore.HC` | from `a4a9e7e` — FIXED |
| `kernel-win-serial-smoke` | same | same — FIXED |
| ~~`repl-9p-smoke`~~ | retired image's feature set — PORTED, green | no |
| ~~`dump-changes-smoke`~~ | same — PORTED, green | no |
| `kernel-psalmody-smoke` | servant needs the guest compiler | no |
| `kernel-phase3-smoke` | false -85 fixed; now fails in guest Cmp on Menu_RV_Guest_Lex | no |
| `kernel-thin-loader-smoke` | `SoftLexSrc.BIN` 2128 > 2 KiB loader cap | no |

**The win pair** was a real bug and is fixed. `RVExePubs.HC` plants `AsmStep` and `Dr` by
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

0.1 first, because it is a correctness bug in the surface everything else is added to, and it is
cheap to find. Then 1.1, because the newline rule in the REPL is the thing you would feel every
time you typed. Then 1.3, because it ends the recurring "I do not see X" — everything is on a
page, and the page has a name.
