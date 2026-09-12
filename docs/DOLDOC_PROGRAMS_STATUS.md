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

`NullCase.HC` prints the case-0 body for all 20 loop iterations. Root cause is
exact: **`IC_SWITCH` and `IC_NOBOUND_SWITCH` are stubbed in the RV backend**
(`Compiler/OptPass_RV.HC:1044` — a bare `break;` with a `TODO: extract table info
from ic_data`). The guest emits no dispatch, so control falls straight into the
first case body. Everything upstream is correct: `PrsSwitch` (`Compiler/PrsStmt.HC:578`)
builds the jump table (`mc_jt->jmp_table[range]`, default-filled then case labels
at `val-lo`) and patches `value-lo`/`range` into the `IC_SUB`/`IC_IMM` pair;
case-value parsing handles null cases (`case:` → 0 then `++`). Host AOT switch works
via `ICSwitch` (`Compiler/OptPass789A.HC:1012`; `tests/exec/cases/e_subswitch_break.hc`
→ 0x7f passes).

Implementing it on RV means porting `ICSwitch`: bounds-check `(u64)(value-lo) >=
range → default`, load `jmp_table[value-lo]` (a table of resolved label addresses
emitted into the code image — the label-address relocation is the substantive part;
`IC_GET_LABEL` at `OptPass_RV.HC:1291` already resolves single label addresses to
build on), then an indirect jump. This is the next concrete target for "stock
programs working" and is a bounded codegen feature, not a hunt.

## Reproduction

`tests/scripts/gen_stock_doldoc_probe.hc.txt` is the generated seed+run block. To
re-measure: inject it before `RVWinVtRun()` in `tests/exec/cases/kernel_win_interactive.hc`,
call `RVStockMeasure();` after the `VtDemo.DD` `FileWrite`, `make build/exec/win_vt.elf`,
boot under `qemu-system-riscv64 -M virt -nographic`, and read the `STOCKDD`/`STOCKPROG`
lines. Revert the harness afterwards (it is a committed gate input).
