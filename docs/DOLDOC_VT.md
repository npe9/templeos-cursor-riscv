# DolDoc on a VT100 / curses terminal

**Status: runtime verified under QEMU.** `make kernel-vt-smoke` is green —
`VT: first=2373 idle=0 after=41` — so the diff/flush loop holds its two design
properties on target: an idle present costs exactly 0 bytes, and a one-line edit costs
41 against a 2373-byte full paint. No raw control byte escapes `RVVtPutGlyph`.
`Kernel/RVDocVT.HC` builds clean against the full kernel project (1.8 MB blob) via
`tests/exec/cases/kernel_vt_present.hc`. The presenter is included by the test case,
not by `Kernel_RV.PRJ`, so an ordinary kernel build does not pull it in. Still
unproven: anything about a *real* terminal — see Known problems on row count, and
Next steps for what the smoke does not cover. Everything below about the *existing*
tree was read out of the source.

Related: [CONSOLE.md](CONSOLE.md) · [REPL.md](REPL.md) · [UART.md](UART.md) ·
[BOARD_FB.md](../templeos-riscv/BOARD_FB.md)

---

## The short version

**Don't write a DolDoc renderer. Write a second presenter for a grid that already
exists.**

The obvious approach — walk a `CDoc` entry list and print text — throws away
DocRecalc's layout, every window border, the menus, and the hypertext. It is also
unnecessary, because TempleOS never rendered DolDoc to pixels directly in the first
place. It renders to a **character cell grid with per-cell colour**, which is
exactly what a VT100 is.

The framebuffer is one consumer of that grid. A terminal is another.

```
  DolDoc entries ──DocRecalc──► laid-out entries (x, y, attr)
                                        │
                            RVDocDrawWin │ RVTextChar(x, y, ch | attr<<8)
                                        ▼
                          rv_winmgr.text_base   ← every window, border,
                          U32 cell grid            menu, PopUp, FileMgr
                                        │
                    ┌───────────────────┴───────────────────┐
                    ▼                                       ▼
        RVGrPaintDC glyph loop                      RVVtPresent()   ← new
        cells → 8×8 glyphs → framebuffer            cells → ANSI → UART
```

Everything above the grid is untouched. `DocRecalc` lays entries out the same way,
links and trees stay live, and `RVWinMgrLiteInit()` — which already exists — runs
the whole stack headless at 80×25 with no framebuffer at all.

## What the tree already provides

| Piece | Where | State |
|---|---|---|
| DolDoc core (entry stream, `DocRecalc`, links, trees, `DocEd`) | `Kernel/RVDoc.HC` (~121 KB) | Working |
| Entry-list → cell grid | `RVDocDrawWin` in `Kernel/RVWinMgr.HC:1352` | Working |
| The cell grid itself | `rv_winmgr.text_base`, `RVTextChar` at `RVWinMgr.HC:798` | Working |
| Headless 80×25, no FB | `RVWinMgrLiteInit()` at `RVWinMgr.HC:666` | Working |
| Click/activate by cell coordinate | `RVDocFindAt` + `RVDocActivate` | Working |
| VT100 output primitives | `bootstrap/seed/term.hc` — `TermGoto` / `TermFg` / `TermInverse` / … | Working (REPL image) |
| VT100 **input** parsing → TempleOS scan codes | `term.hc` `TermParseByte` / `TermHandleCsi` / `TermMapKey` / `TermKeyGetHoly` | Working (REPL image) |
| Cells → ANSI | — | **Missing.** This is the whole gap. |

## Cell encoding (read from `RVGrPaintDC`)

```
ch = cell & 255            index into sys_font_std — NOT ASCII below 0x20
fg = (cell >> 8)  & 15     ST_COLORS
bg = (cell >> 12) & 15
ATTRF_INVERT               swap fg/bg
ATTRF_SEL                  fg ^= 15, bg ^= 15
```

Three translations get you to ANSI:

**Colour.** TempleOS orders `BLUE=1, GREEN=2, CYAN=3, RED=4`; ANSI has
`RED=1, GREEN=2, YELLOW=3, BLUE=4`. So 1↔4 and 3↔6 swap, and bit 3 selects the
bright plane (SGR 90/100 instead of 30/40). `term.hc`'s `TermSgrColor` already does
exactly this and is correct.

**Attributes.** `ATTRF_INVERT` → SGR 7. `ATTRF_SEL` → xor both nibbles (or SGR 7 if
you would rather the terminal own selection).

**Glyphs.** This is the only real mismatch. TempleOS's font puts box-drawing glyphs
at **0x02–0x0D**, where a terminal expects control codes. From `RVTextBorder`
(`RVWinMgr.HC:828`), `bc[2+solid]` is horizontal, `bc[4+solid]` vertical,
`bc[6+solid]` top-left, `8` top-right, `10` bottom-left, `12` bottom-right, with
`solid` = focused:

| Code | 0x02 | 0x03 | 0x04 | 0x05 | 0x06 | 0x07 | 0x08 | 0x09 | 0x0A | 0x0B | 0x0C | 0x0D |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Unicode | ─ | ═ | │ | ║ | ┌ | ╔ | ┐ | ╗ | └ | ╚ | ┘ | ╝ |
| ASCII fallback | `-` | `-` | `\|` | `\|` | `+` | `+` | `+` | `+` | `+` | `+` | `+` | `+` |

`0x20`–`0x7E` pass through. Anything else becomes a space — never a raw control
byte, which would otherwise let a stray cell reprogram the operator's terminal.

## Bandwidth is the design constraint

Correctness here is easy; making it usable over a serial line is not. 80×25 is 2000
cells. A full repaint that emits a colour escape per cell is ~24 KiB, which at
115200 baud (~11.5 KiB/s) is **over two seconds per frame**. That is the difference
between a working console and a useless one, so the presenter is built around
avoiding it:

- **Shadow + diff.** Keep a copy of what the terminal is already showing; emit only
  cells that changed. An idle frame costs **zero bytes**.
- **Attribute runs.** Emit an SGR only when fg/bg/inverse actually change, not per
  cell, and pack the whole change into one `ESC [ 0;fg;bg[;7] m`.
- **Cursor runs.** Emit `CSI row;colH` only when the next cell is not where the
  cursor already sits. Overwriting a gap of ≤4 unchanged cells is cheaper than
  re-addressing around it, so short gaps do not break a run.

A one-line edit then costs ~80 characters plus a couple of escapes — roughly 120 B,
about 10 ms. `RVVtPresent()` returns the byte count so a smoke can assert this
directly: an idle present must be 0, and a one-line edit must be far below a full
repaint. That assertion is the real regression gate; without it the design silently
decays back to full repaints.

## Input and hypertext

The input half is already done and is the part people usually expect to be hard.
`term.hc` parses CSI sequences and `TermMapKey` / `TermKeyGetHoly` turn them into
**TempleOS scan codes** — the same values `DocPutKey` already consumes. Arrow keys,
Home/End/Delete and function keys route straight in.

DolDoc's hypertext survives because activation is already coordinate-based:
`RVDocFindAt(doc, dx, dy)` → `RVDocActivate(doc, e)` is what `RVDocClickAtWin` calls.
So a terminal gets links two ways, and they share that path:

- **Keyboard (recommended default).** Tab / Shift-Tab walk `DOCT_LINK` entries in
  the recalc'd list, drawing the focused one with `ATTRF_SEL`; Enter activates it.
  This is how `lynx` works, it needs no terminal capability, and it makes links
  discoverable on a hardware VT100.
- **Mouse (opt-in).** `CSI ?1000h` enables xterm reporting; a click decodes to a
  cell, which is already the exact input `RVDocClickAtWin` takes.

## Known problems

**Row count.** `MakeAdam_RV.PRJ` compiles Adam with `TEXT_ROWS 48` / `TEXT_COLS 80`,
and `RVWinMgrLiteInit` fixes 80×25. A real terminal is usually 80×24. Nothing here
scales a 48-row layout into 24 rows. The honest options are to drive the grid from
the terminal's reported size (`term.hc` `TermQuery` already asks) and let DocRecalc
lay out to it, or to letterbox and scroll. Guessing wrong shows up as a doc that is
half off-screen, so this should be settled before the first demo rather than after.

**Sprites.** `DOCT_SPRITE` / `DOCT_INS_BIN` are vector art; there is no sensible cell
rendering. Reserve their bounding box and show a placeholder. Half-block or braille
rendering is possible later but is not the first cut.

**Image layering.** `term.hc` lives in the REPL image (`bootstrap/seed/`), while the
grid lives in the kernel image (`Kernel/`). They are not linked together, which is
why `RVDocVT.HC` carries its own small ANSI emitter and its own copy of the ST_COLORS
map rather than calling `TermSgrColor`. That duplication is deliberate but it is
duplication: if the colour map changes in one place it must change in both. A
shared header would be better if these images ever converge.

**Terminal capability.** UTF-8 box drawing and colour are constructor flags
(`RVVtInit(utf8, color)`), not probes. `term.hc` has real probing (`TermProbe` /
`TermQuery`); the kernel side does not, so today it must be told.

## Next steps

1. ~~Run `make kernel-vt-smoke`.~~ **Done — green.** The runtime is now proven, and
   both design gates hold:

   ```
   VT: first=2373 idle=0 after=41
   ```

   An idle present costs exactly 0 bytes and a one-line edit costs 41 against a
   2373-byte full paint, so the shadow diff is doing its job. No raw control byte
   escaped `RVVtPutGlyph`.

   Getting there needed a real port fix, not a test tweak: `KDbg.HC` `ChkOnStk`
   dereferenced `task->stk` without checking it, and in the bare AOT exec harness
   `Fs` is a static `CTask` with `stk == NULL`. x86 tolerated the load at address 8;
   RISC-V faults, and since `tests/exec/harness/crt0.S` installs no `mtvec` the fault
   trapped to 0 and spun — a silent hang with no output at all. See
   `tests/scratch/vt_smoke_hang_note.md`.

   Two gotchas for anything else driving the WinMgr from the bare AOT harness: a
   kernel service needs `RVKernelInit()` before `RVWinMgrLiteInit()`, and `Fs` there
   has no task stack unless the case builds one (the FB cases do, via
   `RVWinSmokeAdamBoot` → `TaskInit`).
2. Settle the row-count question against a real 80×24 terminal (see Known problems).
3. ~~Only then wire keyboard link navigation~~ — **input now works**: `make
   kernel-vt-repl` is an interactive DolDoc REPL on a real terminal (menu bar, Term
   window, typed input echoed into the DolDoc body, command output rendered inside the
   window). Keystrokes go to `RVWinTermPutChar`, and the grid is composed by calling
   `RVWinMgrWallPaper` + `RVWinMgrComposeWins` directly — `RVWinMgrRefresh` itself
   bails without a framebuffer. See `tests/scratch/vt_repl_note.md`.
   ~~and wiring `RVWinSerialEval = &ExePutS`~~ — **done**: `make kernel-vt-holyc` is the
   full desktop with the real compiler and real DolDoc, sized to your terminal. It
   reuses `kernel-win-interactive`'s split-AOT units and adds a third link-time flag
   unit; the framebuffer is sized from the wanted text grid (`RVGrInit(cols*8, rows*8)`)
   so the desktop composes at terminal size. Note the monolithic shortcut does **not**
   work — `Compiler/RVExePubs.HC`'s `extern U8 doldoc` is a cross-unit construct that
   collides with `Kernel/RVDoc.HC`'s real definition and leaves `DocInit` dereferencing
   0. See `tests/scratch/vt_holyc_doldoc_note.md`.
   Still to do: Tab-to-link (`RVDocFindAt` + `RVDocActivate` already take a cell
   coordinate), and the pre-existing compound-statement crash (`I64 i=7; i*6;`).
4. Decide whether `RVDocVT.HC` should join `Kernel_RV.PRJ` proper. It costs a 32 KiB
   shadow grid (`RV_VT_CELLS_MAX`), which is real on a size-constrained thin image —
   the reason it is test-case-included today rather than in the kernel project.
