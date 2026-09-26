# The x86 assembly the backend drops, and how to make it portable

`HOLYC_ASM_SKIPS=1` prints, per compile, every construct the backend dropped instead of
translating:

```sh
$ HOLYC_ASM_SKIPS=1 ./holyc-riscv case.hc -o /dev/null
note: 17 x86 construct(s) dropped — that code is NOT in the image
  Kernel/KMathA.HC:1: asm{} block _D3_NORM_SQR
  Kernel/KUtilsRV.HC:587: asm{} block
  …
```

**A dropped construct is code that is not in the image.** `host/parser.c:5229` soft-skips an
`asm{}` block it cannot assemble — deliberately, so the host AOT can compile stock files full of
x86 — so for any file containing assembly a clean compile cannot distinguish *ported* from
*silently empty*. `Adam/Gr/GrAsm.HC` is the extreme case: 410 lines, 121 x86 mnemonics, compiles
with exit 0, adds 40 bytes, defines no symbols.

## The mechanism is one function, on purpose

There are four places a construct gets dropped — two bare-opcode paths, the `$IB` missing-bin path
and the `asm{}` path — and they all call `HolyAsmSkipNote(cc, line, what, label)`.
`asm_blocks_skipped++` appears in exactly one place. That matters for more than tidiness: a count
cannot be worked through, and four independent counters cannot be turned into a worklist.

`line` is where the construct STARTS. Reading `cc->lex.line` at note time reports the CLOSING BRACE,
which made `Kernel/KUtilsRV.HC`'s failing `Abs::` block look like the `Floor::` block below it, and
reported `KMathA.HC:648` for a block that begins on line 1 — that whole 648-line file is one `asm{}`.

## The goal is portability, not RISC-V

Each dropped block implements an *operation*. The fix is to name that operation and express it once,
so every target gets it — rv64 today, rv32/AArch64/ARM32 through the `holyc_target` seam
(`host/holyc_target.h`, whose own comment reserves "op hooks for forms that are irreducibly
different per target"). Translating x86 → RISC-V instruction by instruction would leave the next
architecture exactly where this one started.

Three outcomes, and most of the list is the first:

| | fix |
|---|---|
| **Portable HolyC** | the operation has no machine-specific content; write it in HolyC once and no target needs asm |
| **`holyc_target` op hook** | irreducibly per-arch (context switch, page tables, fault CSR); one hook, one implementation per target |
| **Not applicable** | x86-only concept with no meaning elsewhere |

## The dropped-construct list — 13 in a plain `Kernel_RV.PRJ` build

Was 17: the `fabs.d` fix removed one and deleting the three all-dead files removed three more. The
rows marked DONE are kept because the reasoning is the template for the rest.

| construct | operation | fix |
|---|---|---|
| `KMathA.HC:1` `_D3_NORM_SQR` | 3-vector norm² | **DONE — file removed from `Kernel_RV.PRJ`.** 648 of its 649 lines are that one block; removing it leaves the image byte-identical (measured). `Kernel/KMathA_RV.HC` has the HolyC `D3*` |
| `KUtils.HC:1` `_MEMSET_U16` | fill 16-bit units | **DONE — removed, byte-identical.** 471 of 472 lines in the block; `Kernel/KUtilsRV.HC` has the RISC-V primitives |
| `StrA.HC:20` `PUT_HEX_U32` | format a U32 as hex | portable HolyC |
| `Mem/MAllocFree.HC:1` `_FREE` | allocator free fast path | portable HolyC |
| `KHashA.HC:1` `SYS_HASH_SINGLE_TABLE_FIND1` | hash lookup | **DONE — removed, byte-identical.** `Kernel/KHashRV.HC` is what runs |
| `SerialDev/Keyboard.HC:1` `SHIFT_KEY_SCAN_DECODE_TABLE` | **a data table written in asm** | portable data, not code |
| `Sched.HC:54` `_TASK_CONTEXT_RESTORE` | restore a task's registers | **op hook** |
| `KExcept.HC:1` `_TAKE_EXCEPT` | unwind to a handler | **op hook** |
| `Mem/PageTables.HC:1` `SYS_INIT_PAGE_TABLES` | build the initial page tables | **op hook** (x86 paging vs Sv39). NOT removable, unlike the three above: removing it changes the image by 304 bytes, because `MemPageTable` at line 199 is live HolyC outside the block — and it reads `MEM_PML3`/`MEM_PML2`, x86 four-level paging, for callers in `Mem/MemPhysical.HC:117,144`. `Kernel/KThinMemStubs.HC:170` has a second body for the same name |
| `KDbg.HC:628` `MOV_RAX_CR2` | the faulting address | **op hook** (x86 CR2 vs RISC-V `mtval`) |
| `KTask.HC:121`, `:141` | inline, unlabelled | read them; likely op hook |
| `KMain.HC:229` `SYS_KERNEL_END` | a link-time symbol | **op hook or linker symbol** — and `SYS_KERNEL_END` is one of the symbols `docs/DEMO_SURVEY.md` lists as missing, so this unblocks `Demo/AcctExample/TOS/TOSCfg.HC` |
| `SerialDev/Keyboard.HC:413`, `Mouse.HC:92` `CLD` | clear the x86 direction flag | **not applicable** — nothing to write |
| `PCIBIOS.HC:1` `SYS_PCIBIOS_SERVICE_DIR` | call the x86 PCI BIOS | **not applicable** |
| `KUtilsRV.HC:587` `Abs::` | absolute value | **OUR BUG, not stock** — see below |

## `KUtilsRV.HC:587` was ours — FIXED, and the fix taught the bigger lesson

`Kernel/KUtilsRV.HC` is the port's own native-RISC-V assembly: 59 `asm{}` blocks, 58 of which
assembled. The one that did not was `Abs::`, and the cause was `fabsd` — a **pseudo-instruction**.
`fabs.d rd,rs` *is* `fsgnjx.d rd,rs,rs` (sign-inject XOR with itself clears the sign bit); there is
no fabs.d opcode. `fneg.d` is `fsgnjn.d rd,rs,rs` and `fmv.d` is `fsgnj.d rd,rs,rs`, all three now
in `host/parser.c` in both `.d`/`.s` and dotted/undotted spellings.

**What it cost, and why nothing noticed, is the important part.** A dropped block is not a build
failure and not a link failure. The symbol leaves the blob and becomes an unresolved import in the
HOFYIMP1 trailer, and every harness that links `tests/exec/harness/oracle_out.c` — 81 of the 87
scripts in `tests/scripts` — fills that slot from the C runtime in `bootstrap/holy_rt_names.h`,
which has its own `Abs`. So the C `Abs` answered every gate *correctly*.

I wrote the obvious regression test and it passed at HEAD. Twice: the second time with opaque
non-constant arguments, to rule out constant folding. **No behavioural test in this repo can
detect a dropped asm block whose symbol the C runtime also provides.**

## The import trailer is the real worklist

`HOLYC_ASM_SKIPS` lists what was *dropped*. The blob's trailer lists what is *missing*, which is
the question that matters — and it is complete, because it is what the linker could not resolve
rather than what a heuristic noticed.

```sh
$ tools/blob_imports.py build/aot/win/win_tos.blob.bin      # the real multi-module image
$ tools/blob_imports.py blob.bin --absent Abs Sqr Floor     # exit 1 if any IS unresolved
```

Read it on the **multi-module** image. A single-unit exec blob conflates two unrelated things:
`host/aot_link.c` resolves imports across `mods[]` via `find_export`, so a symbol another unit
provides never reaches the trailer in a real link but does in a one-unit compile.

`tests/portability_seam.tsv` pins all 41 names of the linked image with a category each, and
`make portability-seam-check` fails if the set moves in either direction. Two gates:

| gate | asserts |
|---|---|
| `make blob-imports-check` | `Abs Sqr Floor Trunc Round` are resolved INSIDE the blob |
| `make portability-seam-check` | the linked image's unresolved set equals the pin, exactly |

### What the 41 turned out to be

| category | n | what it means |
|---|---|---|
| `platform` | 22 | the port layer **on purpose** — trap/IRQ/timer/task/yield primitives the C harness owns. This is the seam a new architecture must fill, and naming it is most of the portability work already done |
| `libm` | 5 | `ATan Ceil Cos Sin Tan` — a real gap, C libm standing in |
| `strmem` | 3 | `MemCmp MinI64 StrCat` — primitives that exist only as x86 asm |
| `x86-only` | 3 | `FarCall32 GetRAX SaveExceptRegs` — stubbed, correctly |
| `MISSING` | 8 | **provided by nothing at all** |

The last row is the find. Seven of the eight are called by units that ARE in the image while the
unit defining each is one the project does not include; the eighth, `GetMcause`, I cannot account
for and say so:

| name | defined in | why it is not in the image |
|---|---|---|
| `DocCollapse` | `Adam/DolDoc/DocRecalcLib.HC` | excluded deliberately — it redefines six RVDoc functions |
| `DocEntryRun` | `Adam/DolDoc/DocRun.HC` | not included |
| `DocRemSoftNewLines` | `Adam/DolDoc/DocNew.HC` | not included |
| `DocSplitTag` | `Adam/DolDoc/DocRecalc.HC` | not included |
| `EdCurU8`, `EdCursorLeft`, `EdCursorRight` | `Adam/DolDoc/DocChar.HC` | not included |
| `GetMcause` | `bootstrap/seed/csr.hc:423` | `bootstrap/seed/csr_decode.hc` — the one seed file the kernel shares — calls it at line 317, and `csr.hc` is not in the closure. See the note below: this one is a DEAD body, not a live call |

Seven DolDoc editor entry points. `bootstrap/holy_rt.h` writes a `holy_unresolved_import` stub
into each slot, so calling one prints `[unresolved import]` and **returns 0**.

Which of them is reachable is a separate question from whether it is unresolved. Of the nine DolDoc
units that call these seven, only `DocFind.HC` and `DocLink.HC` are in this project — and between
them they call **all seven**:

| call site | what silently returns 0 |
|---|---|
| `DocFind.HC:189,287,308,330,332,334` | `EdCurU8` — **used as a VALUE**, `EdCurU8(doc)==':'` |
| `DocFind.HC:300,333,335` | `EdCursorRight` |
| `DocFind.HC:211,290` | `EdCursorLeft` |
| `DocFind.HC:463` | `DocSplitTag` — find/replace splits the tag at the cursor |
| `DocFind.HC:514` | `DocRemSoftNewLines` |
| `DocLink.HC:123,125` | `DocCollapse` — the `EDf_COLLAPSE`/`EDf_UNCOLLAPSE` branch of link activation |
| `DocLink.HC:157` | `DocEntryRun` — running the entry under the cursor after `DocEd` |

`GetMcause` is the exception that shows how to read this table. Its slot exists because
`CsrDecodeMtval` at `bootstrap/seed/csr_decode.hc:308` is *compiled into* the kernel unit and calls
`GetMcause()` on its `mcause_hint < 0` branch — but nothing in the unit's 165-file closure calls
`CsrDecodeMtval` at all. **A compiled-but-never-called body still emits an import slot.** So an
unresolved import proves a compiled call site exists, not that it ever executes. The include closure
is the way to settle it: `tr ' \\' '\n\n' < build/aot/win/kernel.d` lists exactly the 165 files,
which is also what found the `csr_decode.hc` reference that greps of `Kernel/ Adam/ Compiler/ tos/`
had all missed.

The `EdCurU8` row is the sharp one. A no-op predicate is survivable; a no-op *accessor* is not.
`EdCurU8` returns the character under the cursor, and it now returns 0, so every `==':'` and
`=='{'` in `DocFind` is false and `abort_on_dbl_colon` — how DolDoc finds a `Func::` definition —
can never fire. The dig-down path cannot work, and no test says so.

Note this is **not** "the arrow keys do nothing": `DocPutKey.HC`, where cursor keys are handled, is
not in the image at all. It is find and link activation taking 0 from seven functions never linked in.

The load-time line that says all of this, `[import unresolved: NAME]`, is real and is printed —
`build/exec/asm_repl_ui.out` has it — and 68 scripts in `tests/scripts` pipe their diagnostic output
through `grep -v 'import unresolved'`. That is how it stayed invisible: not suppressed in the
pass/fail decision, but erased from the `got:` lines a human reads when a smoke fails.

These are the next portability items, and they are not assembly at all. `tools/check_prj_collisions.py`
already says how far each can go — a second body for one name wins silently, so this has to be asked
before adding any Adam unit:

| unit | collisions with the PRJ | so |
|---|---|---|
| `Adam/DolDoc/DocChar.HC` | **none** | add it — fixes `EdCurU8`, `EdCursorLeft`, `EdCursorRight` |
| `Adam/DolDoc/DocRun.HC` | **none** | add it — fixes `DocEntryRun` |
| `Adam/DolDoc/DocRecalc.HC` | 1 — `DocRecalc` vs `Kernel/RVDoc.HC` | lift `DocSplitTag` out, or reconcile `DocRecalc` |
| `Adam/DolDoc/DocNew.HC` | 7 — `DocNew DocDel DocRst DocLock DocInsEntry DocEntryDel DocEntryNewBase` all vs `RVDoc.HC` | lift `DocRemSoftNewLines` out; the unit cannot go in whole |
| `Adam/DolDoc/DocRecalcLib.HC` | 6 (already recorded in the PRJ) | lift `DocCollapse` out |

### Done: DocChar + DocRun added — and the count went UP

Both units went in, and the gate immediately made the real shape visible: four names closed
(`EdCurU8`, `EdCursorLeft`, `EdCursorRight`, `DocEntryRun`) and **seven new ones opened**, because
those two units have their own unmet dependencies. Two of the seven were tiny enough to lift
verbatim into `Kernel/RVDoc.HC` — `IsEditableText` (which `DocChar` calls 16 times) and
`DocEntryNewTag` (11 times), whose `DocEntryNewBase` already exists there with stock's signature.

Net: **41 unresolved → 42, MISSING 8 → 9.** The count went up and the severity went down, which is
the trade worth making. What was closed was a no-op *accessor* causing a hang; what is open now is
form and popup navigation:

| name | in | consequence of the stub |
|---|---|---|
| `DocFormFwd`, `DocFormBwd` | `DocForm.HC` | `U0`, and both **return immediately unless `doc->flags & DOCF_FORM`** — so for a non-form doc the stub and the real function are identical. Only form docs lose tab-between-fields |
| `DocDataFmt`, `DocDataScan` | `DocForm.HC` | form field format/parse |
| `PopUpPickLst` | `DocPopUp.HC` | the list-picker popup |

`DocForm.HC` collides on `DocForm`/`DocMenu`/`PopUpMenu` and `DocPopUp.HC` on eight `PopUp*` names,
so neither can go in whole; these five need lifting or reconciling, like `DocRemSoftNewLines` and
`DocCollapse`.

### Done: DocRemSoftNewLines and DocCollapse — the quiet two

Both `U0`, so unlike `DocSplitTag` their stubs could not trap; they were wrongness with no symptom.
`DocCollapse` (`DocLink.HC:123,125`) meant link activation with `EDf_COLLAPSE`/`EDf_UNCOLLAPSE`
never collapsed a tree widget. `DocRemSoftNewLines` (`DocFind.HC:514`, only on the
`cmd!=RSAC_ALL` interactive per-hit branch) left stale `DOCT_SOFT_NEW_LINE` entries, so re-wrap was
wrong until the next full recalc.

A `U0` gives nothing to compare, so `tests/exec/cases/e_kernel_doldoc_collapse.hc` asserts a **state
change the stub cannot produce**: `DOCEf_CHECKED_COLLAPSED` appearing on a `DOCEF_TREE` entry and
then clearing, and a hand-inserted `DOCT_SOFT_NEW_LINE` being gone from the stream afterwards. At the
parent commit it returns `0x6`, not `0xf` — and the two bits that *do* pass are the vacuous ones
(`cleared`, because the flag was never set; `soft_before==1`, which is just the setup). That is worth
noticing: half of a four-part assertion agreed with a completely broken implementation.

Placement matters here in a way the earlier lifts did not need. `DocCollapse` calls `DocRecalc`,
which `RVDoc.HC` only forward-declares partway down the file, so both went in immediately after that
declaration. An earlier placement did compile — `DocRecalc` bound anyway and never appeared in the
trailer — but depending on that is not the same as knowing it.

**41 → 39 unresolved, MISSING 8 → 6.** All six that remain are the benign form/popup group plus
`GetMcause`'s dead body.

### Done: DocSplitTag — the one that was a crash, not a no-op

`DocSplitTag` was the next item by severity, and it is the first MISSING name whose stub was
**dereferenced** rather than ignored. `Adam/DolDoc/DocFind.HC:463`:

```
doc_e = doc_marker = DocSplitTag(doc, doc->cur_entry, doc->cur_col, …);
do { if (doc_e==doc) … else doc_e->…
```

A 0 from the stub is a null pointer walked immediately. Measured at the parent commit,
`tests/exec/cases/e_kernel_doldoc_replace.hc` does not merely return a wrong value:

```
[unresolved import]
TRAP mcause=0x5 (load-fault) mepc=0x80a3130c mtval=0x18 blob+0x23130c
```

`mtval=0x18` is a field offset from 0, and `HOLYC_MAP` resolves the PC to **`EdFindReplace+0x14a4`**.
So DolDoc find-and-replace crashed the kernel, and nothing said so — the smokes do not drive it and
the load-time `[import unresolved: DocSplitTag]` line is filtered out of the diagnostics.

Lifted verbatim into `Kernel/RVDoc.HC` (its unit also defines `DocRecalc`, which `RVDoc.HC` defines,
so the unit itself still cannot go in). Every callee it needs — `MAllocIdent`, `StrNew`, `QueIns`,
`Free`, `MemCpy`, `StrLen`, `DocEntryNewBase` — was already resolved in the image; I checked each
against the trailer before lifting rather than after. `EdReplace` is the non-interactive way in
(`find_replace->pmt=FALSE`), so the test needs no popup: **42 → 41 unresolved, MISSING 9 → 8.**

**What the stub actually cost is worth stating, because it was not a degraded search.**
`EdCursorRight` is what advances `doc->cur_entry`, and `EdGoToFun`'s loop is
`while (doc->cur_entry!=doc) { ch=EdCurU8(doc); … EdCursorRight(doc); }`. A no-op there never
changes the condition: **an infinite loop**. `tests/exec/cases/e_kernel_doldoc_edcur.hc` pins it,
and at the parent commit it does not merely return a wrong value — it produces no ORACLE line at
all, after the loader prints

```
[import unresolved: EdCurU8]
…
[unresolved import]
[unresolved import]
```

one line per `EdCurU8` call, and then hangs. And `EdCurU8` returns **-1** for a non-text entry,
never 0, so the stub's 0 was not even a value the function can produce.

## How to work an item

1. `HOLYC_ASM_SKIPS=1` on a case that includes the file, to confirm it is still dropped.
2. Read the block and name the OPERATION, not the instructions.
3. Portable HolyC where possible. A `holyc_target` hook only when the operation genuinely differs
   per architecture — and then implement it for rv64 first, leaving the hook NULL elsewhere, which
   is the pattern `host/holyc_target.h` already describes.
4. Check the symbol actually appears in `HOLYC_MAP` afterwards. Compiling is not working: that is
   the whole reason this document exists.
