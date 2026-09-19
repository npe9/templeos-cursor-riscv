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

### 1.4 AsmDoc motivation covers 72 of 244 instructions

`AsmClasses` / `AsmClass` and the REPL's `p <class>` now exist, so a family can be worked
through one instruction at a time — which makes the missing motivation entries more visible, not
less. The classes are curated lists in `Kernel/RVExplore.HC`.

The structure is done and adding one is a single line. The remaining 172 are writing, not
engineering. The second batch covered the word-width family, the rest of the loads and stores,
the CSR read-modify-writes, the atomics, the double-precision arithmetic and comparisons, the
compressed forms and the system instructions. What is left is mostly aliases and the rarer
encodings, where the motivation is often "this is the same as X with the operands swapped".

---

## Tier 2 — survey leftovers

### 2.1 Generic CSR-by-number reader

Still if-chains; ~4000 numbers unreachable. Generate the switch from a table so the name→number
map, the reader and `AsmDoc`'s CSR list cannot drift. See MACHINE_STATE_SURVEY.md §2.

### 2.2 Float registers in the seed image's freeze

The C runtime saves f0..f31 at a trap; `bootstrap/seed/trap.hc` still saves none, so in that
image the pane's "(as last stepped)" label is the whole fix rather than half of it.

### 2.3 Trace through control flow

`t` lists branches and steps over them. Evaluating the condition against the context and moving
the cursor would make it a real single-stepper for compiled code — the registers are all there,
it is arithmetic on the ones the branch names.

---

## Tier 3 — housekeeping, and two decisions that are yours

### 3.1 Two pre-existing reds, unchanged since before this session

- `fmt-check` is red across 40 files. Running `make fmt` touches all of them; it wants a
  deliberate "yes, reformat the tree" rather than being buried in a feature commit.
- `kernel-gr` compares against a stale golden hash (`want 0x6EF34074 / got 0x2C881662`). Both
  were confirmed pre-existing by rebuilding at `a61c792`.

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
