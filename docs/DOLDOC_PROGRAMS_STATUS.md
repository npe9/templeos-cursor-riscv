# Stock DolDoc files and programs on win_vt (baseline 2026-09-12)

Measured on `build/exec/win_vt.elf` (the VT DocTerm REPL) after the console
tail-follow fix (commit a7ed68f). Stock content was seeded into the guest RAM
RedSea FS by escaping each host file into a HolyC string literal (`$`→`$$` so the
DolDoc source lexer stores a single `$`), `FileWrite`-ing it, then rendering via
`Cat` (DolDoc) or running via the REPL eval path `RVWinSerialHolyC` (programs).

## DolDoc files — WORKING

Five stock `tos/Doc/*.DD` files (God, Date, Start, Que, CompilerOverview) seeded
and read back **byte-exact** (read == original size for all five), then `Cat`'d:
the `$FG`/`$LK`/`$ID` markup is **interpreted, not printed literally** (0 literal
`$LK`, prose renders — e.g. Que.DD shows "A Queue is a bunch of MAlloc()ed chunks
of mem linked together in a circle"). The stock `.DD` files in this tree are pure
text with no trailing `CDocBin` blob, so `DocLoad` only parses the `$`-command
markup, which the DocTerm now lays out and scrolls correctly.

## Programs — PARTIAL

Run through the guest compiler (`RVWinSerialHolyC` → `ExePutS`, whole-buffer):

| Program | Result |
|---------|--------|
| `Demo/ForLoop.HC` | CORRECT — `for sum 0..4 = 10`, `for (;i<4;i++) sum = 6`; C-style and empty-init for loops, string-statement `"fmt",args;` Print all work |
| `Demo/NullCase.HC` | WRONG — prints "Zero" 20 times instead of Zero/One/Two/Three/Ten/Eleven |

### Open: guest `switch` dispatch collapses to the first case

`NullCase.HC` proves the guest compiler's `switch` statement dispatches every value
to the first `case` (all 20 loop iterations printed the case-0 body). Case-value
PARSING is correct (`Compiler/PrsStmt.HC:663`: `case:` → 0 then `++`, `case N:` →
`N`); the defect is in the dispatch codegen emitted after the case list (the
switch-value comparison / jump table), guest-side only — host AOT switch works
(`tests/exec/cases/e_subswitch_break.hc` → 0x7f passes). This is the next concrete
target for "stock programs working".

## Reproduction

`tests/scripts/gen_stock_doldoc_probe.hc.txt` is the generated seed+run block. To
re-measure: inject it before `RVWinVtRun()` in `tests/exec/cases/kernel_win_interactive.hc`,
call `RVStockMeasure();` after the `VtDemo.DD` `FileWrite`, `make build/exec/win_vt.elf`,
boot under `qemu-system-riscv64 -M virt -nographic`, and read the `STOCKDD`/`STOCKPROG`
lines. Revert the harness afterwards (it is a committed gate input).
