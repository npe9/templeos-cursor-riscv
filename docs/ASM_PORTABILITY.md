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
rows marked DONE are kept because the reasoning is the template for the rest. (Sixteen rows, but
two of them list two constructs each — `KTask.HC:121,:141` and the two `CLD`s — so thirteen.)

**A dropped block is not automatically a hole.** Cross-check every row against
`tests/portability_seam.tsv` before working it: if nothing the block defines appears in the
trailer, a live HolyC or RISC-V body already provides it and the x86 is simply inert. That is true
of every remaining row except the op hooks, which is why the list below is now almost entirely
"op hook" and "not applicable" — the genuinely missing code was never in this list at all, it was
in the trailer.

| construct | operation | fix |
|---|---|---|
| `KMathA.HC:1` `_D3_NORM_SQR` | 3-vector norm² | **DONE — file removed from `Kernel_RV.PRJ`.** 648 of its 649 lines are that one block; removing it leaves the image byte-identical (measured). `Kernel/KMathA_RV.HC` has the HolyC `D3*` |
| `KUtils.HC:1` `_MEMSET_U16` | fill 16-bit units | **DONE — removed, byte-identical.** 471 of 472 lines in the block; `Kernel/KUtilsRV.HC` has the RISC-V primitives |
| `StrA.HC:20` `PUT_HEX_U32` | format a U32 as hex | **already covered** — nothing it defines is in the trailer, so a live HolyC body exists. Unlike the three removed above, `StrA.HC` has 359 live lines outside the block, so the FILE stays |
| `Mem/MAllocFree.HC:1` `_FREE` | allocator free fast path | **already covered** — `Free` is not in the trailer. 381 of 465 lines are the block but 9 are live, so the file stays |
| `KHashA.HC:1` `SYS_HASH_SINGLE_TABLE_FIND1` | hash lookup | **DONE — removed, byte-identical.** `Kernel/KHashRV.HC` is what runs |
| `SerialDev/Keyboard.HC:1` `SHIFT_KEY_SCAN_DECODE_TABLE` | **a data table written in asm** | portable data, not code. Nothing unresolved, so the port supplies its own |
| `Sched.HC:54` `_TASK_CONTEXT_RESTORE` | restore a task's registers | **op hook** |
| `KExcept.HC:1` `_TAKE_EXCEPT` | unwind to a handler | **op hook** |
| `Mem/PageTables.HC:1` `SYS_INIT_PAGE_TABLES` | build the initial page tables | **op hook** (x86 paging vs Sv39). NOT removable, unlike the three above: removing it changes the image by 304 bytes, because `MemPageTable` at line 199 is live HolyC outside the block — and it reads `MEM_PML3`/`MEM_PML2`, x86 four-level paging, for callers in `Mem/MemPhysical.HC:117,144`. `Kernel/KThinMemStubs.HC:170` has a second body for the same name |
| `KDbg.HC:628` `MOV_RAX_CR2` | the faulting address | **op hook** (x86 CR2 vs RISC-V `mtval`) |
| `KTask.HC:121`, `:141` | inline, unlabelled | read them; likely op hook |
| `KMain.HC:229` `SYS_KERNEL_END` | a link-time symbol | **op hook or linker symbol** — and `SYS_KERNEL_END` is one of the symbols `docs/DEMO_SURVEY.md` lists as missing, so this unblocks `Demo/AcctExample/TOS/TOSCfg.HC` |
| `SerialDev/Keyboard.HC:413`, `Mouse.HC:92` `CLD` | clear the x86 direction flag | **not applicable** — nothing to write |
| `PCIBIOS.HC:1` `SYS_PCIBIOS_SERVICE_DIR` | call the x86 PCI BIOS | **not applicable** |
| `KUtilsRV.HC:587` `Abs::` | absolute value | **OUR BUG, not stock** — see below |

## The two lists are the same seam, seen from opposite sides

This took a while to see and it is the shape of the whole problem.

The **skip list** above says *"here is the x86 implementation of an operation, and it was dropped."*
The **import trailer** says *"here is an operation the image calls and no HolyC unit provides."*
For the op-hook rows these are the same operations, described from the two ends:

| operation | x86 side (dropped) | RISC-V side (in the trailer) | who implements it today |
|---|---|---|---|
| switch a task's context | `Sched.HC:54` `_TASK_CONTEXT_RESTORE` | `RVTaskSwitch` (called at `Kernel/KBootRV.HC:116`) | `bootstrap/holy_rt.h` |
| enter/leave a fault handler | `KExcept.HC:1` `_TAKE_EXCEPT` | `RVTrapInit`, `RVTrapRecover*` (7) | `bootstrap/holy_rt.h` + `crt0.S` |
| the faulting address | `KDbg.HC:628` `MOV_RAX_CR2` | `mtval`, via `RVTrapRecoverTval` | `bootstrap/holy_rt.h` |
| build the initial page tables | `Mem/PageTables.HC:1` `SYS_INIT_PAGE_TABLES` | — Sv39 set up in `KStartRV` | the port |

So **the factoring the port needs already exists.** It is not missing; it is just implemented in C
in the harness rather than in HolyC or RISC-V asm in the kernel, and until this document nothing
named it. `tests/portability_seam.tsv`'s 22 `platform` rows ARE that seam, enumerated and pinned:
they are precisely the list a new architecture has to satisfy, and the gate now fails if that list
changes in either direction.

That reframes the remaining work. "Translate the x86 to RISC-V" was the wrong goal for these rows —
the RISC-V side already exists and works. The question is whether each should keep living in the C
harness or move into the kernel as HolyC/asm.

**And that question is already answered.** `docs/MULTIARCH.md` and the approved retarget plan record
the decision "HolyC-only runtime (**no new per-arch C runtime**)". As things stand those 22 names
live in `bootstrap/holy_rt.h` and `tests/exec/harness/crt0.S`, so bringing up AArch64 or ARM32 would
mean writing a C runtime for each of them — exactly what that decision rules out. So the pin is not
just an inventory, it is the checklist for the next phase: each `platform` row either moves into the
kernel as HolyC/RISC-V asm, or the decision gets revisited on purpose rather than by default.
`make portability-seam-check` fails in both directions, so the list cannot drift while that happens.

### Tier 5 does not depend on tier 3, and it is where the damage is

Two corrections to my own staging, both found by checking rather than reasoning.

**It is not one group.** `RVUartIrqInit`/`RVUartIrqOff` are MMIO register writes plus `csrs mie` —
they enable interrupt *sources* and never touch the vector, so they do not depend on tier 3 at all.
`RVUartGetBuffered` reads `holy_urx`, a ring the trap handler fills, so that one genuinely is
tier-3 coupled. "Driver-shaped therefore last" was an assumption about coupling I never checked.

**The C applies one UART's register map to seven UARTs.** `HolyRVUartIrqInit` writes
`*(U8 *)(HOLY_UART_BASE + 1) = 1` for the interrupt-enable register. That is the NS16550 layout.
`Kernel/Drv/` carries seven drivers — `RVUart16550`, `RVUartSifive`, `RVUartHtif`, `RVUartIbex`,
`RVUartShakti`, `RVUartUartlite`, `RVUartStub` — and the defconfigs select 5x 16550, 3x SiFive,
1x HTIF plus the rest. On a SiFive UART, `base + 1` is not the IE register.

On top of that, four boards set `CONFIG_UART_REG_SHIFT=2` (Microchip Icicle, Milk-V Mars,
VisionFive2, XiangShan): word-spaced registers, so even on a 16550 the IER is at `base + 4` and the
C's `base + 1` pokes a byte of RBR/THR instead. The kernel has had this right all along —
`Kernel/Drv/RVUart16550.HC:22-39` has `RVUartReg`/`RVUartIn`/`RVUartOut`, which apply the shift AND
switch to U32 access when it is >= 2, with the comment "word-spaced maps often ignore byte MMIO".

**Why this is documented and not done.** Every constant needed is already in `RVAutoConf.HH`
(`CONFIG_UART_BASE`, `CONFIG_UART_IRQ`, `CONFIG_PLIC_BASE`, `CONFIG_PLIC_ENABLE_OFF`,
`CONFIG_PLIC_THRESHOLD_OFF`, `CONFIG_UART_REG_SHIFT`), the `csrs mie` idiom already exists in HolyC
at `Kernel/Drv/RVSmp.HC:57`, and `Kernel/Drv/RVUart.HC` → the generated `RVUartSelected.HH` is
already the per-board selection seam. But the placement is a real design decision: the IE write
belongs in each driver (seven of them, each with its own register map) while the PLIC lines are
shared, and it affects fourteen board configs none of which can be tested here. That is a choice to
make deliberately, not a refactor to slip into a session that has already moved four names.

### Tier 3 sized — a boot-path change, and the next real piece of work

Worth writing down before anyone starts it, because it is a different kind of job from tiers 1-2.

The kernel already **reads** mtvec — `RVWinCsrrMtvec`, `Kernel/RVDbgView.HC:454`, `Kernel/RVRegPane.HC:263`
all display it — but **never writes it**. The C owns installation end to end:
`HolyRVTrapInit` does `csrw mtvec, &HolyTrapVector` plus `csrs mstatus, MIE`, and
`tests/exec/harness/crt0.S:17` installs an earlier `trap_entry` before that, covering the window
before anything else is up. The six `RVTrapRecover*` names are accessors over globals that
`HolyTrapVector` freezes at trap entry.

So tier 3 is not "port six small functions" — it is the kernel taking ownership of the trap vector:
the save/restore, the frozen register set, and the boot-order question of what handles a fault
*before* HolyC exists. The instructions are not the obstacle (`csrw`/`csrs`/`csrr` are all in
`host/parser.c`); the sequencing is.

One detail to preserve if it moves, from the C's own comment: `ra` is frozen deliberately, because
"a fault inside a leaf (`MemCpy`, `StrLen`, a stub) traps before that function has saved `ra`, so
`ra` still holds its caller — which is the question *who passed the bad pointer?* that `mepc` alone
cannot answer." That is also the narrow-trap-frame gap the UART debugger work has open.

### The real reason to move them: the C runtime is a divergent copy of the platform description

This is a better argument than plan compliance, and it only became visible while sizing tier 2.

Every device address the C runtime uses is **hardcoded**, and the kernel already has a *generated*
equivalent in `Kernel/RVAutoConf.HH`:

| | `bootstrap/holy_rt.h` | `Kernel/RVAutoConf.HH` |
|---|---|---|
| UART base | `HOLY_UART_BASE 0x10000000` | `CONFIG_UART_BASE` |
| CLINT base | `HOLY_CLINT_BASE 0x02000000` | `CONFIG_CLINT_BASE` |
| PLIC | `HOLY_PLIC 0x0C000000` | `CONFIG_PLIC_BASE` |
| UART register stride | **no such concept** | `CONFIG_UART_REG_SHIFT` |
| timebase frequency | **no such concept** | `CONFIG_TIMEBASE_FREQ` |

`RVAutoConf.HH` is generated per board and `templeos-riscv/configs/` carries fourteen defconfigs.
The C copy is hand-frozen at QEMU virt and lacks concepts the kernel needs at all: register stride
matters where UART registers are not byte-adjacent, and the timebase frequency differs per board.

**How much it actually diverges, measured across those defconfigs — because my first statement of
this was wrong.** I claimed moving `RVJiffies` would make it "correct on Milk-V Mars, where the C
version is not". It would not: Milk-V Mars has `CONFIG_CLINT_BASE=0x02000000`, exactly what the C
hardcodes. The honest split:

| | boards that differ from the C's hardcoded value |
|---|---|
| `CLINT_BASE` | **one** — XiangShan (`0x38000000`). Every other board with a CLINT uses `0x02000000` |
| `UART_BASE` | **six or more** — AMD MicroBlaze-V `0x40600000`, HiFive Unmatched `0x10010000`, Microchip Icicle `0x20000000`, OpenTitan `0x40000000`, Shakti C `0x00011300`, XiangShan `0x310B0000` |

So the argument is real but it lands on a different tier than I first said. For **tier 2**
(`RVJiffies`) the hardcoded CLINT address is wrong on exactly one board, and the divisor is already
platform-aware because callers pass `CONFIG_TIMEBASE_FREQ / 1000` themselves. For **tier 5** (the
UART rows) the C's `HOLY_UART_BASE` is wrong on most non-QEMU boards, and it has no notion of
`CONFIG_UART_REG_SHIFT` at all.

That inverts the staging's urgency ordering, though not its dependency ordering: tier 5 was listed
last as "driver-shaped, least urgent", and by coupling it still moves last, but it is where the
duplicated board description actually bites. `Kernel/RVDocVT.HC:423` already reads `mtime` through
`CONFIG_CLINT_BASE`, so the idiom for all of them is established.

That reframes the migration: it is not tidying, and it does not depend on the multi-arch plan's
"no per-arch C runtime" decision to be worth doing. It removes a second, inferior, silently
diverging copy of the board description.

### Staging the 22, by coupling rather than by size

The C bodies are small — 5 to 28 lines each, maybe 200 lines in total — so volume is not the
obstacle. Coupling is. Grouped by what has to move together:

| tier | rows | why |
|---|---|---|
| **1 — DONE** | `SysHlt`, `Call` | one instruction each, and the assembler already had both. `HolySysHlt` is `wfi`, which `host/parser.c:4756` encodes as `0x10500073`. `HolyCall` is a `fence.i` then an indirect jump, and `fencei` is already a recognised mnemonic — the C even uses `.word 0x0000100f` by hand because `-march=rv64imafdc` omits Zifencei |
| **2 — DONE** | `RVJiffies` + `RVJiffiesInit` | the first row where moving it FIXED something — see below |
| **3 — the trap bundle, indivisible** | `RVTrapInit`, `RVTrapRecoverArm`/`Disarm`/`Cause`/`Epc`/`Ra`/`Tval` | the `Recover*` readers are bare accessors over C globals the trap vector writes. The vector moves or none of them do — sized below |
| **4 — scheduling** | `RVTaskSwitch`, `Yield`, `TaskEndNow`, `RVYieldInit`, `RVPreemptReal` | context save/restore and the preempt timer; `RVTaskSwitch` is the x86 `_TASK_CONTEXT_RESTORE`'s counterpart |
| **5 — devices, and it SPLITS** | `RVUartIrqInit`/`Off` (independent of tier 3), `RVUartGetBuffered` (tier-3 coupled), `RVVirtioPciIsrReg`, `RVCrashMon`/`Init` | I called this "least urgent" and was wrong twice over — see below |

Tiers 1 and 2 are done. Note the ordering principle differs from the DolDoc work: there, severity
ranked the list because every row was a live defect; here nothing was visibly broken, so **coupling**
ranked it.

**Tier 2 is the first row where moving it FIXED something.** The C read mtime at a hardcoded
`0x02000000+0xBFF8`. XiangShan puts its CLINT at `0x38000000`; OpenTitan and AMD MicroBlaze-V have
no CLINT at all (`# CONFIG_HAS_CLINT is not set`) and the C would read `0x02000000` regardless,
taking a fault or garbage. The HolyC version reads `CONFIG_CLINT_BASE + CONFIG_CLINT_MTIME_OFF` and
`#ifdef`s the no-CLINT case to 0. Only the address was ever frozen — the divisor was already
per-board, because every caller passes `CONFIG_TIMEBASE_FREQ / 1000` itself.

`tests/exec/cases/e_kernel_jiffies.hc` is also the first of these cases that **can** fail on a
broken implementation, because its assertions are about behaviour over time rather than a value the
C also computes correctly: uninitialised reads 0, an initialised clock is non-zero, it MOVES, and it
never moves backwards. Confirmed by pointing mtime at XiangShan's base while running on QEMU virt —
no ORACLE line. The same address that makes the C wrong on XiangShan makes XiangShan's address wrong
here, and the case catches both directions.

The precedent for the move is already in the tree and was extended twice this session:
`Kernel/KUtilsRV.HC` took `MemSet`/`MemCpy`/`StrLen`/… off the C runtime years of commits ago, then
`Exp`/`Ln`, then the libm five and the strmem three. The `platform` rows are harder — they touch
CSRs and the trap frame rather than pure computation — but the pattern and the gate are the same.

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
| `make blob-imports-check` | 13 named primitives are resolved INSIDE the blob, not taken from C |
| `make portability-seam-check` | the linked image's unresolved set equals the pin, exactly |

### What the 41 turned out to be — and where they went

The first measurement found 41. The sections below work through them; this is the scoreboard.

| category | at first | now | what it means |
|---|---|---|---|
| `platform` | 22 | **22** | the port layer **on purpose** — trap/IRQ/timer/task/yield primitives the C harness owns. This is the seam a new architecture must fill, and naming it is most of the portability work already done. Not a defect and not shrinking |
| `libm` | 5 | **0** | `ATan Ceil Cos Sin Tan` — had no HolyC body at all; now native |
| `strmem` | 3 | **0** | `MemCmp MinI64 StrCat` — now native RISC-V asm beside the nine already there |
| `x86-only` | 3 | 3 | `FarCall32 GetRAX SaveExceptRegs` — stubbed, correctly |
| `MISSING` | 8 | **6** | provided by nothing at all; the remaining six are benign, see below |
| **total** | **41** | **31** | |

Both categories that represented a *real gap* are now empty. What is left is the deliberate seam,
three x86 concepts with no meaning here, and six names whose stubs have no reachable consequence.

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

## Done: the `strmem` three — the original ask, exactly

`MemCmp`, `StrCat` and `MinI64`, written as native RISC-V `asm{}` in `Kernel/KUtilsRV.HC`. This is
the plainest instance of "translate the x86 primitive" in the whole list, because the pattern was
already there and these were the holes in it: that file holds nine such blocks — `MemSet` `MemCpy`
`StrLen` `StrCpy` `StrCmp` `StrNCmp` `StrICmp` `StrMatch` `StrIMatch` — translated off the x86 in
`Kernel/KUtils.HC`, and `MinI64` was missing beside a `MaxI64` that has been there since the port
began. Semantics match `HolyMemCmp`/`HolyStrCat`/`HolyMinI64` exactly, so no caller moves.

**34 → 31 unresolved; `strmem` is empty too.** Both real-gap categories are now closed.

`tests/exec/cases/e_kernel_strmem.hc` is aimed at the hand-written assembly rather than the happy
path: zero counts, both orders of difference, a difference past the count, appending to and of the
empty string, and `MinI64` across zero and at equality. The sharp one is **unsigned** comparison —
`0x80` must compare above `0x01`, which a signed byte load gets backwards. Mutating `lbu` to `lb`
in `MemCmp` turns `0x1fff` into `0x1fdf`: exactly that bit and no other, so the property is really
load-width-sensitive and not incidentally satisfied.

### The `x86-only` three are stubs on purpose, and one of them is checked

`SaveExceptRegs` looked alarming when traced: `Kernel/KExcept.HC:73` calls it from `SysTry`, so
**every `try` block in the image** calls a stub that does nothing. Its job on x86 is to save the
callee-saved registers into the `CExcept` for `TakeExcept` to restore — and `TakeExcept` is itself
one of the 13 dropped blocks, categorised here as an op hook.

It is nonetheless benign, and that is demonstrated rather than argued: `tests/exec/cases/e_try_catch.hc`
and `e_try_toplevel.hc` are in the permanent oracle manifest and pass, so the port's `try`/`throw`
does not depend on the x86 register unwind. Note also that `TakeExcept` and `TestExcept` never
appear in the trailer at all, unlike `SaveExceptRegs` — they are statement forms the compiler
handles, not calls. `FarCall32` is only reached from `Kernel/PCIBIOS.HC`, the x86 PCI BIOS, and
`GetRAX` has no call site.

### What decides whether a name gets a slot — NOT yet established

I wrote here that "a slot exists only where a compiled call site does." **That is false**, and the
counter-example is in this very section's subject matter. Measured against the kernel unit's
167-file include closure (`tr ' \\' '\n\n' < build/aot/win/kernel.d`):

| name | declared as | referenced in the closure? | in the trailer? |
|---|---|---|---|
| `SysHlt` | `_extern _SYS_HLT` | **no** — only `KernelB.HH:270` | **yes** |
| `GetRAX` | `_intern IC_GET_RAX` | **no** — only `KernelB.HH:252` | **yes** |
| `MaxU64` | `_intern IC_MAX_U64` | no — only `KernelB.HH:100` | **no** |
| `MinU64` | `_intern IC_MIN_U64` | no — only `KernelB.HH:102` | **no** |
| `MaxI64` | `_intern IC_MAX_I64` | yes | no — `KUtilsRV.HC` defines `MaxI64::` |
| `GetMcause` | plain HolyC | yes, from a body nothing calls | **yes** |

So a declaration alone CAN produce a slot (`SysHlt`, `GetRAX`), and two declarations of the same
`_intern` shape sitting 150 lines apart in the same header behave differently. Being defined
somewhere in the image clearly removes the slot (`MaxI64`); what decides the rest is not something
I have established, and guessing at it would be worse than saying so.

**What this changes:** treat the trailer as the authoritative list of *what the image does not
provide* — that much is solid and is what both gates rest on — but do not infer from a row that
something calls it. Check the call sites separately, in the closure, before claiming any
functional consequence. The `DocSplitTag` trap and the `EdGoToFun` hang were established that way
and stand; the earlier gloss that `GetMcause` is slotted "because a compiled-but-uncalled body
calls it" is one possible reading of an effect I cannot yet fully explain.

## Done: the `libm` five — and a bug in the gate itself

`Sin Cos Tan ATan Ceil` had **no HolyC body anywhere in the port**. The C runtime answered for all
five — including for `Kernel/KUtilsRV.HC`'s own `RVF64Sin`/`Cos`/`Tan`/`ATan`, wrappers whose entire
purpose is to hand the guest JIT a callable `Sin`, and which were therefore forwarding to C.

Now ported from `rt_sin`/`rt_atan` in `bootstrap/holy_rt.h` loop-for-loop onto the native FPU, the
same way `Exp` and `Ln` already were in that file, so results agree with what callers were getting.
`Ceil` is `-Floor(-x)` — exact, and `Floor` is already a native `fcvt.l.d` with `rdn`, so it needs no
new assembler support. **39 → 34 unresolved; the `libm` category is now empty.**

`tests/exec/cases/e_kernel_libm.hc` checks ten properties against CPython's `math` — an independent
reference, not a re-pin of the port's own output — including both `ATan` branches and the
out-of-range reduction. It passes at the parent commit too, **measured not assumed**, because C libm
is also correct; its header says so and points at the blob gate.

### The gate was lying, and only the negative control found it

Extending `check_blob_imports.sh` from five names to ten, the fail-on-purpose run at the parent
commit **passed** — at a commit where all five were provably unresolved. The cause was in
`tools/blob_imports.py`:

```python
want_absent = [a for i, a in enumerate(argv) if i and argv[i - 1] == '--absent']
```

Only the argument immediately after `--absent` satisfies that. `--absent Abs Sqr Floor Trunc Round`
checked **only `Abs`** and silently ignored four names, while the caller printed
"5 name(s) resolved". A gate that reports success without checking — the same family as the
`while read` inside a pipeline that printed FAIL and exited 0.

It shipped in the commit that introduced it and survived one whole commit afterwards. The lesson is
narrow and worth keeping: **when a negative control unexpectedly passes, suspect the harness before
believing the result.**

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

Order matters here — steps 1 and 2 are what this session learned the hard way.

1. **Start at `tests/portability_seam.tsv`, not at the skip list.** A dropped `asm{}` block whose
   symbols are absent from the trailer is INERT: a live HolyC or RISC-V body already provides them.
   Every "portable HolyC" row above turned out to be in that state. The dropped-construct list tells
   you what was thrown away; only the trailer tells you what is missing.
2. **Check the return type before assuming a stub is harmless.** `U0` cannot hurt. A pointer that
   gets dereferenced is a trap (`DocSplitTag` → `EdFindReplace`, `mcause=5`). And a no-op that is
   supposed to advance a loop variable is a hang, not a slow path (`EdCursorRight` → `EdGoToFun`).
   Severity, not count, decides the order — closing `DocChar`+`DocRun` took the total UP by three
   and was still right.
3. Read the block and name the OPERATION, not the instructions. Then ask which side of the seam it
   belongs on (see "the two lists are the same seam" above) — for the `platform` rows the RISC-V
   implementation already exists in C, so the work is moving it, not writing it.
4. Verify every callee of what you are about to lift is already resolved, BEFORE lifting. One
   `tools/blob_imports.py` run answers it, and it is cheaper than discovering it from a trap.
5. `tools/check_prj_collisions.py` before adding any Adam unit. A second body for one name wins
   silently, and five of the DolDoc units that define MISSING names collide with `Kernel/RVDoc.HC`.
6. **Prove the gate fails.** Twice this session a behavioural test passed at the parent commit
   because the C runtime is also correct — measured, not assumed, and both headers say so. Once the
   gate tool itself was broken (`--absent` checked only its first argument) and only an unexpectedly
   passing negative control revealed it. When a negative control passes, suspect the harness.
7. Re-pin against a **relinked** `win_tos.blob.bin`, deleted first. A stale blob makes the gate agree
   with a measurement that predates your change; byte-identity on an exec case does not cover it.
