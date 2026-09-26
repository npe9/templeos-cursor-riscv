# Getting the demo corpus to 100%, and what 100% has to mean

204 files under `Demo/`. As of the survey that `docs/DEMO_SURVEY.md` records, 158 reach L1-OK.
This is the plan for the rest — written after a day of finding that the easy ways to move this
number all make the port worse.

## 0. The metric is wrong, and fixing it is step one

`L1-OK` means: compiles, links into a real image, boots, runs its top-level code, reaches the end.
It does **not** mean the demo did its job. Three times in one session that gap produced a "fix"
that was a regression:

| tempting move | what it would have scored | what it would actually do |
|---|---|---|
| add `Adam/AExts.HC` (names `DocMax`, `View`; collides with nothing) | up to 5 demos L0-FAIL → L1-OK | 89 `extern`s, **zero bodies** → 89 import slots stubbed to return 0 |
| let statements name `asm{}` labels, so `Call(_HELLO_WORLD)` compiles | 2 demos L0-FAIL → L1-OK | that label is in an x86 block the assembler drops; the call reaches a stub returning 0 |
| translate `Demo/Asm/DivByHand.HC` and stop at L1-OK | 1 demo L0-FAIL → L1-OK | **it did**, while dividing everything to zero — `_extern _LABEL` did not bind |

The third was caught only because the translation was checked by computing `123456/10` instead of
by reading the survey.

### Measured, not argued: at least 6 of the 158 are L1-OK with their whole point missing

Of the twelve demos whose `asm{}` blocks are x86, **eight are L1-OK** — and only the two that were
translated and checked by computation actually do anything:

| demo | survey | reality |
|---|---|---|
| `Asm/DivByHand` | L1-OK | **works** — translated, 7 assertions |
| `Asm/MulByHand` | L1-OK | **works** — translated, 8 assertions |
| `Asm/AsmHelloWorld` | L1-OK | block dropped; `_HELLO_WORLD` is **not in the map at all** |
| `Asm/PutDec` | L1-OK | block dropped |
| `Asm/AsmAndC1`, `Asm/AsmAndC2` | L1-OK | blocks dropped |
| `Lectures/FixedPointAdvanced`, `Lectures/Optimization` | L1-OK | blocks dropped |

`HOLYC_ASM_SKIPS=1` on `AsmHelloWorld` prints
`Demo/Asm/AsmHelloWorld.HC:22: asm{} block _HELLO_WORLD`, and `HOLYC_MAP` contains zero occurrences
of that symbol. The demo scores L1-OK because the survey compiles with `RV_NO_DEMO_AUTORUN`, which
guards off the one statement that would have used it. Nothing is left to fail.

Six is a floor, not a total — that is only the demos whose blocker happened to be assembly. The same
shape applies anywhere a demo's payload sits behind the guarded statement.

**Corollary, and the reason this plan leads with the metric:** a day of real fixes (the
`_extern _LABEL` binding that 117 declarations depend on, `la`, the RISC-V print helpers, two demos
translated) moved the survey from 158 to **158**. DivByHand was L1-OK before the fix while dividing
everything to zero, and L1-OK after while dividing correctly. The number cannot see the difference,
in either direction.

So:

**Rule for this whole plan: a demo counts as done when a test asserts what it computes or draws,
not when the survey says L1-OK.** The survey is a triage tool. It compiles with
`RV_NO_DEMO_AUTORUN` defined, which guards off the top-level statement — for many demos that
statement is the only call, so the survey never runs the thing it is reporting on.

Concretely: every demo moved by this plan gets a row in `tests/exec/oracle_manifest.tsv` that
checks a value, or a `tests/scripts/*_smoke.sh` that greps output. `docs/DEMO_SURVEY.md` keeps the
L1 columns for triage; the manifest is the scoreboard.

## 1. What is actually blocking the 46, by cause

From `docs/DEMO_SURVEY.md` plus this session's measurements. Ordered by cost-to-fix, cheapest
first, because each tier unblocks the next.

| # | blocker | demos | kind of work |
|---|---|---|---|
| 1 | a real-bodied `Adam/`/`tos/` file is not in `Kernel_RV.PRJ` | ~12, **plus the 7 below** | add + gate, screened |
| 2 | `asm{}` cannot emit data (`DU8`/`DU64`) | 4 | assembler feature |
| 3 | `asm{}` allows only ONE `call` per block | 8 | compiler-internals fix |
| 4 | a sibling file of the same program defines it | 2 | harness: compile the program, not the file |
| 5 | genuinely absent from the tree | 5 | write it, or declare out of scope |
| 6 | x86-only concepts | 2–3 | **out of scope, and say so** |
| 7 | other compile errors (parse error, constant array size) | ~11 | one compiler bug each |

Items overlap — 17 demos have a missing symbol *and* another error — so the counts do not sum to
46. The dependency order is what matters.

**The `Argument N omitted` family is NOT a compiler bug — it is tier 1 wearing a different error
message.** That error fires at `host/parser.c:1447` when the callee has no declaration in scope, so
its defaults are unknown; the wording even says "has no declaration here to take a default from".
Where the seven callees actually live:

| callee | demos | defined in | status |
|---|---|---|---|
| `Touch` | 2 | `Adam/ABlkDev/ADskA.HC` | already screened for tier 1 |
| `Sort` | 1 | `Adam/Opt/Utils/StrUtils.HC` | already screened for tier 1 |
| `InSetMs` | 1 | `Adam/InFile.HC` | already screened for tier 1 |
| `PopUpRangeI64` | 1 | `Adam/DolDoc/DocPopUp.HC` | collides on 8 `PopUp*` names — lift the one function |
| `JukeSongsPuppet` | 2 | `tos/Apps/Psalmody/JukePuppet.HC` | not screened |

So four of those seven demos are already covered by files in the tier 1 table, and no compiler work
is needed for any of them. That removes a whole tier from this plan and makes tier 1 the clear first
move: it is now worth roughly 12 + 7 demos rather than 12, for the same effort.

(Worth noticing how this was found: by reading what the error actually *says* before believing the
survey's grouping of it. The survey bucketed these as their own blocker because they have their own
message.)

## 2. Tier 1 — files that are already screened (do this first)

Two screens, both necessary, and `tools/check_prj_collisions.py` now runs both:

1. **Collisions.** A second body for one name wins silently.
2. **Bodies.** A candidate that is only `extern` declarations defines nothing and, because the PRJ
   compiles with `OPTf_EXTERNS_TO_IMPORTS`, turns every name into a stub returning 0.

Already screened and clear:

| file | cost | unblocks |
|---|---|---|
| `Adam/Opt/Boot/BootRAM.HC` | nothing missing | `OnceDemo` |
| `Adam/InFile.HC` | nothing missing | `InFile/InSetIP` |
| `Adam/Opt/Utils/StrUtils.HC` | 1 phantom (`DocInsDoc`, only its own `Words()` reaches it) | `Sort`, `LongLines` |
| `Adam/ABlkDev/ADskA.HC` | `DocD` not in the closure | `Touch` (2 demos) |
| `Adam/Gr/GrDC.HC` | `GrBitMap4ToBitMap8` has **no body anywhere** | `DCScrnCapture`, `StadiumGen` |

Procedure per file: collisions → bodies → add → compile → `tools/blob_imports.py` to see exactly
which names the addition left unresolved → decide whether each phantom is acceptable and record why
→ the 8-target layout gate → a manifest row that checks what the demo computes.

## 3. Tier 2 — `DU*` data in an `asm{}` block

Blocks 4 demos and is the smaller of the two assembler gaps. `la rd,label` already landed, so the
*address* side is solved; what is missing is emitting the bytes.

The instruction array is word-oriented (`RvI2`, one 32-bit word per entry, emitted as `IC_RAW_RV`),
so the implementation is: parse `DU8`/`DU16`/`DU32`/`DU64` operands (string literals and integer
constants), accumulate a byte buffer, then emit `ceil(n/4)` words. Padding is harmless because the
data is reached by `la` + `lb` and is NUL-terminated inside the buffer. Put the data after a `ret`
so it is never executed — which is what the demos already do.

Test it the way `la` was tested: `la` a pointer to the block's own string, load bytes, compare
against the expected characters, and check the emitted words by disassembly.

## 4. Tier 3 — more than one `call` per `asm{}` block

Blocks 8 demos, the largest single group, and it is a compiler-internals change.

**Cause, measured.** Asm `call` emits `IC_CALL`; `host/compiler.c`'s `IC_CALL` case is
`EmitCallArgsAndInvoke`, which loads arguments into `a0`-`a7` from the compiler's **stack-depth
model** and then adjusts that model. With zero modelled arguments it leaves `a0` alone, which is why
one call works; but the model still moves, so a second call in a raw block computes from a state the
raw instructions never maintained. Symptom: `li a0,0x1234` before a second `call` printed the *first*
call's argument again, then trapped.

**Fix.** An asm-only call that skips the argument machinery: `EmitLabelAddr` (already used by
`IC_FN_ADDR`) materialises a label address, so it is that into a scratch register plus `jalr ra,rs`.
Needs its own IC or a flag on `IC_CALL`, and its own gate — `kernel-phase3-smoke` and `repl-cmp`
especially, since they are the heaviest users of the normal call path.

## 5. Tier 4 — the harness compiles the wrong unit

2 demos. A TempleOS program is often one translation unit: a Home account's `MakeHome.HC` includes
`TOSExt`, `TOSCfg`, `TOSMisc`, `TOSDistro` in order. `tools/survey_demo_one.sh` compiles one file,
so siblings' symbols are missing. Fix the harness, not the demos: when a directory has a
`Make*.HC`, compile that instead and report the program's status. This is bookkeeping, and it makes
the survey honest rather than moving any code.

## 6. Tier 5 — genuinely absent, and tier 6 — out of scope

Absent from the tree (5): `SYS_KERNEL_END` and `TOS_DBG_DISTRO` (link symbols — `SYS_KERNEL_END` is
also one of the 13 dropped x86 constructs, so it lands with that work), `F_UNARY_MINUS_INT`,
`_BUZZ_FIZZ` (the demo's own label, tier 2+3), `STC`.

**Out of scope, and the plan should say so rather than quietly counting them as failures:**

- `Demo/Lectures/Ring3.HC` needs `INT_TO_RING0` — x86 privilege rings. RISC-V has M/S/U modes and
  no analogue of that call.
- `Demo/Asm/AsmAndC3.HC` needs `STC` — set the x86 carry flag. RISC-V has no flags register.
- `Demo/MagicPairs.HC` does not compile on x86 TempleOS either (recorded in the survey).

So **the honest ceiling is 201–203 of 204**, not 204, and a plan that promises 204 is promising to
fake three of them. State the ceiling; report against it.

## 7. Tier 7 — the remaining compiler bugs

~13 demos, one bug each, and each needs the same treatment the `_extern _LABEL` fix got: find the
smallest case that reproduces it, fix it, and prove the fix by making the case fail first.

Known shapes, from the survey's blocker table: `Expected constant array size` (6 demos — likely one
cause, a constant expression the folder does not handle), `parse error` (5), unknown class member
(4), and the `Argument N omitted, but 'X' has no declaration here to take a default from` family
(7 demos across `Touch`, `JukeSongsPuppet`, `Sort`, `PopUpRangeI64`, `InSetMs`) — that last one is
a single mechanism and may be one fix for all seven.

## 8. Order, and why

1. **Tier 1** — the 5 screened files, plus `JukePuppet.HC` screened and `PopUpRangeI64` lifted out
   of `DocPopUp.HC`. Worth ~19 demos, not ~12, now that the argument-default family is known to be
   the same cause. Cheapest work in the plan and it exercises the two-screen procedure.
2. **`Expected constant array size`** — 6 demos, plausibly one cause in the constant folder.
3. **Tier 2** — `DU*`. Unblocks 4 and completes the asm-data story `la` started.
4. **Tier 3** — asm multi-call. Unblocks 8, the largest group, but the riskiest change.
5. **Tier 4** — harness unit fix. 2 demos, no code risk.
6. **Tier 5/6** — write the few that are missing; formally scope out the x86-only ones.

Tiers 2 and 3 together also finish the 10 untranslated x86-asm demos, which is why they sit in the
middle rather than last: they are the only route to that group, and `DivByHand`/`MulByHand` are
already done and prove the translation pattern.

## 9. How to not fool ourselves on the way

- Every moved demo gets a value-checking test. No demo counts on survey status alone.
- Before adding a file: collisions, then bodies, then `tools/blob_imports.py` on the result.
- After any change that touches the seam or the compiler: `make -k qemu-integration`, not a
  targeted gate. A targeted gate chosen for "what the change drives" cannot see what the change
  drove that you did not know about — that is how a `RVJiffies` move passed 11/11 and broke
  sleeping tasks.
- When a negative control passes, suspect the harness. Two gates in this repo reported success
  without looking: `--absent` parsed one argument of five, and a Makefile prerequisite referenced a
  variable assigned 67 lines later so it expanded to empty. `make -n` catches the second in a second.
