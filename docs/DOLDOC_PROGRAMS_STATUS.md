# Stock DolDoc files and programs on win_vt (baseline 2026-09-12)

Measured on `build/exec/win_vt.elf` (the VT DocTerm REPL) after the console
tail-follow fix (commit a7ed68f). Stock content was seeded into the guest RAM
RedSea FS by escaping each host file into a HolyC string literal (`$`→`$$` so the
DolDoc source lexer stores a single `$`), `FileWrite`-ing it, then rendering via
`Cat` (DolDoc) or running via the REPL eval path `RVWinSerialHolyC` (programs).

## DolDoc files — WORKING

Stock `tos/Doc/*.DD` files seed into the guest FS and render with markup
**interpreted, not printed literally**:
- Five small files (God, Date, Start, Que, CompilerOverview) round-trip byte-exact
  and render prose with `$FG`/`$LK`/`$ID` consumed (Que.DD shows "A Queue is a bunch
  of MAlloc()ed chunks of mem linked together in a circle").
- `DemoIndex.DD` (7194 bytes, a **tree/link index**) round-trips byte-exact and
  renders with 0 literal `$TR` and 0 literal `$LK` — trees and links are parsed into
  doc entries (DocLoad reported 24 entries), no fault.

`RVDoc.HC` implements the rich commands too (TREE, BTTN, INVERT, super/subscript,
underline, blink). The stock `.DD` files in this tree are pure text with no trailing
`CDocBin` blob, so `DocLoad` only parses the `$`-command markup, which the DocTerm
now lays out and scrolls correctly.

## Programs — PARTIAL

Run through the guest compiler (`RVWinSerialHolyC` → `ExePutS`, whole-buffer):

| Program | Result |
|---------|--------|
| `Demo/ForLoop.HC` | CORRECT — `for sum 0..4 = 10`, `for (;i<4;i++) sum = 6`; C-style and empty-init for loops, string-statement `"fmt",args;` Print all work |
| `Demo/NullCase.HC` | CORRECT (after the RV `IC_SWITCH` fix below) — Zero/One/Two/Three/Ten/Eleven, each once |
| `Demo/SubSwitch.HC` | CORRECT — `Zero [One] Two [Three] Four [Five]`; sub-switch `start:`/`end:` blocks (IC_SUB_CALL) work |
| `Demo/Directives.HC` | FAILS on `__DATE__` — not an RV regression: the host lexer only implements `__LINE__`/`__FILE__`/`__DIR__` too, and `Demo/Directives.HC` needs `__DATE__`/`__TIME__`, which are unimplemented on both. The guest also lacks `__LINE__`/`__FILE__`/`__DIR__` (host parity would add those three) |
| `Demo/Templates/Registry1.HC` | FAILS — `RegDft` is a missing runtime function (registry not ported); a runtime gap, not a compiler bug |

### FIXED: guest `switch` dispatch (was stubbed in the RV backend)

`Demo/NullCase.HC` originally printed the case-0 body for all 20 iterations because
`IC_SWITCH`/`IC_NOBOUND_SWITCH` were **stubbed** in the RV backend
(`Compiler/OptPass_RV.HC` — a bare `break;`). No dispatch was emitted, so control fell
straight into the first case.

Fixed by `ICSwitchRV` (`Compiler/BackC_RV.HC`): the value is already normalized to
`value-lo` by `PrsSwitch`, so it bounds-checks `(u64)index >= range` to the default
label, then loads the target from the jump table PC-relatively. The table
(`CMT_JMP_TABLE`, `OptPass_RV.HC`) now stores each entry as a **delta from the table
base** (`label_off - cm->addr`); `ICSwitchRV` computes the table address with
`auipc/addi` and adds the loaded delta, so the whole switch is position-independent
(the REPL JIT runs from a MAlloc'd code heap). The sequence is fixed-size every pass
(offset 0 + clear `ICF_CODE_FINAL` while a label is unresolved) so pass 7-9 sizing
does not oscillate.

Verified: `switch` in a loop dispatches correctly (`0→case0, 1→default, 2→case2,
out-of-range→default`), null-case auto-increment and sparse cases work
(`0→0,1→1,2..9→default,10→10,11→11`), and stock `Demo/NullCase.HC` and
`Demo/ForLoop.HC` both run correctly. All win gates and `repl-holyc-regression`
stay green.

## Reproduction

`tests/scripts/gen_stock_doldoc_probe.hc.txt` is the generated seed+run block. To
re-measure: inject it before `RVWinVtRun()` in `tests/exec/cases/kernel_win_interactive.hc`,
call `RVStockMeasure();` after the `VtDemo.DD` `FileWrite`, `make build/exec/win_vt.elf`,
boot under `qemu-system-riscv64 -M virt -nographic`, and read the `STOCKDD`/`STOCKPROG`
lines. Revert the harness afterwards (it is a committed gate input).


## Runtime library ports (REPL-callable)

Runtime functions become callable from the REPL by planting them as `HTT_FUN`
`CHashFun`s (not `RVCmpExportOne`, which only registers an `HTF_IMM` address the
parser cannot call). The harness (`kernel_win_interactive.hc`) fills a `pubs[]`
array of kernel `&Func` addresses and `RVExePubsWireAddrs` (`Compiler/RVExePubs.HC`)
plants each with a return/arg signature. Pointer returns/args use `i64t` (the caller
casts) since no struct classes are planted.

Ported so far (verified callable from the REPL, all win gates + serial-smoke green):
- **Query/util:** `FilesFind`, `DirTreeDel`, `StrFind`, `ScanFlags`, `Define`, `Now`,
  `Str2Date`, `Date2Struct`.
- **Allocator + string foundations:** `MAlloc`, `CAlloc`, `Free`, `StrNew`, `Str2I64`
  (these were NOT callable before — only `HTF_IMM` address constants; programs that
  allocate need them as real calls).
- **printf-family (varargs):** `MStrPrint`, `StrPrint`, `DocPrint` (planted with the
  `Ff_DOT_DOT_DOT` + `argc`/`argv` shape that `Print` uses).
- **mem + doc objects:** `MemCpy`, `MemSet` (the RV implementations under stock names),
  `DocNew`, `DocDel`, `DocClear`.

21 runtime functions in total are now REPL-callable. Still deferred: graphics
(`GrRect`/`GrLine`/`GrPrint` — need the FB/DC runtime), sound (`Snd`/`Play`),
side-effecting FS/task (`Cd`/`DirMk`/`Del`/`Spawn`), and the interactive message loop
(`GetMsg`/`Msg`). Registry (`ARegistry.HC`) needs compiling into the image first.

Compiler intrinsics already cover math/bit/Que/`StrLen`/`ToUpper`/`ToI64` etc. via
`RVExePubInternsIn`, so those never needed planting.

Deliberately left out: blocking-input functions (`GetChar`/`GetI64`/`GetF64` — they
would wedge the VT present loop), side-effecting ones (`Spawn`, `Ed`), and registry
(`ARegistry.HC` is not compiled into the image — a build-inclusion question, not a
planting one). `__DATE__`/`__TIME__` lexer directives remain unimplemented on host
and guest alike.


## Struct types in the REPL (lite classes)

Runtime functions that return/take structs (e.g. `FilesFind`→`CDirEntry*`) are now
ergonomic: `RVExePubCDirEntryLiteIn` (`Compiler/RVExePubs.HC`) plants a lite `CDirEntry`
class — members `next`, `full_name`, `name`, `size`, `attr` at their real `offset()`s,
inserted with `RVExePubMemberPlant` (which matches `MemberFind`'s BST). Same pattern as
the existing `CTaskLite`/`CDolDocGlblsLite` classes; wired into both class-planting
sites (`cmp.asm_hash` and `Fs->hash_table`). `CDateStruct` is planted the same way
(value type — its `size` lets `CDateStruct ds;` reserve the stack slot), so
`Date2Struct(&ds,Now); ds.hour/ds.min/ds.sec/ds.year` works (verified `19:47:14 yr=2026`).

Verified end-to-end — the stock file-iteration idiom runs from the REPL:
`d0=de=FilesFind("A:/*"); while (de) { n++; de=de->next; }` counts entries and
`d0->full_name` reads the path. All win gates + repl-holyc-regression green.

Discovered gap (separate from porting): the guest compiler does not parse the ternary
`?:` operator (`x?a:b` gives "Missing ')'"). Common enough to be worth a later fix; use
`if` in the meantime.
