# Real HolyC eval + real DolDoc through the VT presenter — why the obvious build fails

Goal: `kernel-vt-repl` currently gives `RVWinSerialDispatch`'s built-ins over a plain
text window body. Wanted: `RVWinSerialEval = &ExePutS` (arbitrary HolyC) and a
DolDoc-backed window so `$FG,RED$` is **interpreted**, not printed literally.

Both are reachable — `CRVWin` already has a `CDoc *doc` field and `RVDocTermWire(doc)`
wires put/display/border — but the straightforward build does not work, for a reason
worth writing down.

## What was tried

A single case including everything monolithically:

```c
#include "/Kernel/Kernel_RV.PRJ"
#include "/Compiler/RISCVRegs.HH"
#include "/Compiler/Compiler_RV_Body.PRJ"   // <- for ExePutS
#include "/Kernel/RVDocVT.HC"
```

plus the Adam-boot preamble (heap, CBlkPool, CHeapCtrl, TaskInit, Gs) that the compiler
and `DocNew` both require. It compiles — 3.0 MB blob vs 1.9 MB without the compiler —
and then dies immediately:

```
TRAP mcause=0x...05 (load-fault) mepc=0x809495b0 mtval=0x0 blob+0x1495b0
TRAP halted
```

`HOLYC_MAP` resolves `blob+0x1495b0` to **`DocInit +0x14`**, and the disassembly is
unambiguous:

```
li   a0,0          # the ADDRESS of a global resolved to 0
ld   a0,0(a0)      # deref -> fault
bnez a0, ...
```

`Adam/DolDoc/DocInit_RV.HC:47` opens with `if (doldoc.hash && HashFind(...))`, so the
global whose address is zero is **`doldoc`**.

## Cause: a split-AOT-only declaration compiled monolithically

Two declarations of the same name, with different types, in two units:

| Where | Declaration |
|---|---|
| `Kernel/RVDoc.HC:60` | `CDolDocGlbls doldoc;` — the real definition |
| `Compiler/RVExePubs.HC:19` | `extern U8 doldoc;` — with the comment *"Kernel doldoc abs addr (Compiler unit)"* |

The `extern` is **correct for the split-AOT build**, where the Compiler is a separate
unit and the address is resolved at `--link` time by absolute address. Compile both
into **one** translation unit and the extern collides with the definition; the extern
has no storage, so its address is 0 and every `doldoc` reference from that point on
dereferences null.

This is the same class as the `LogMuxEmit` bug in `uart_mux_dataloss_note.md`: **a
construct that is valid only under a particular build topology, used under a different
one.** The `#ifndef HOLYC_AOT_NO_COMPILER_BODY` in `kernel_win_interactive.hc` implies
the monolithic path is supported — it is not, for anything that calls `DocInit`, and
`RVWinMgrInit` (FB) calls it at `RVWinMgr.HC:786` just as `RVWinMgrLiteInit` does. In
practice `kernel-win-interactive` is always built the split way (`build/aot/win/`), so
nothing exercises the monolithic branch and the breakage is invisible.

## The correct path, and the one complication

`kernel-win-interactive` already has real `ExePutS` **and** real DolDoc. It is built as
`build/aot/win/{kernel,compiler,flag_i|flag_hold}.bin → link`, where the only
difference between the two variants is a ~1 KB **flag unit** returning an I64
(`RVWinHoldFlag()`), selected at link time. That is a designed extension point: a third
`win_flag_vt.hc` returning 2, a `hold == 2` branch running a VT present loop instead of
`RVWinMgrRun(0)`, plus Makefile rules mirroring the existing `_I` / `_HOLD` pair.

**The complication that stopped this from being mechanical:** the `hold` branch happens
*after* the full FB desktop is built, and that desktop is **100x75** (`cols=100
rows=75`, see `kernel-win-smoke`'s banner). A VT presenter needs the grid to match the
terminal — 80x24. Windows are created at 100x75 coordinates before the branch, so a VT
mode cannot simply retarget `rv_winmgr.rows/cols` the way `kernel_vt_repl.hc` does; the
window layout would have to be rebuilt, or the case restructured so geometry is chosen
before the desktop is composed rather than after.

7500 cells also sits close to `RV_VT_CELLS_MAX` (8192), so the shadow grid survives
100x75 but has little headroom.

## Done — `make kernel-vt-holyc`

Built the flag-unit route. The geometry problem turned out to be much smaller than it
looked: `RVWinMgrInit` derives the text grid as `rv_fb.width/FONT_WIDTH x
rv_fb.height/FONT_HEIGHT`, and `RVGrInit(width, height)` already took explicit
dimensions. So there was no need to restructure the desktop — **size the framebuffer
from the terminal** (80x24 -> 640x192, FONT is 8x8) and the desktop composes at
terminal size on its own. Only the variant decision had to move ahead of `RVGrInit`.

| Piece | What |
|---|---|
| `tests/exec/aot/win_flag_vt.hc` | `RVWinHoldFlag()` returns 2, plus `RVWinVtCols/Rows` |
| `win_flag_i.hc` / `win_flag_hold.hc` | same two geometry symbols returning 0 — the shared Kernel unit calls them, so the link must resolve them whichever flag unit is selected |
| `kernel_win_interactive.hc` | `#include RVDocVT.HC`; `hold`/`vt_*` resolved before `RVGrInit`; `RVWinVtRun()` present loop; `hold == 2` branch |
| Makefile | `flag_vt.bin` / `win_vt.blob.bin` / `win_vt.elf` mirroring the `_I` / `_HOLD` pair |
| `run_kernel_vt_holyc.sh` | rewrites the flag unit's two numbers to the caller's terminal, **only when they change** (an unconditional write re-triggers the ~30s unit rebuild every launch) |

Incremental build: **11 seconds**. Verified working:

```
> 3+4;
ans=7
> "hi from holyc\n";
hi from holyc
```

with `ExePutS probe ans=2` and `ExePutS 40+2 ans=42` in the banner — the real compiler,
not the dig-down built-ins. The Term is maximized on entry because the demo desktop
tiles three windows, leaving the prompt ~19 columns wide at 80 cols.

## Known defects, none introduced here

**Compound statements crash.** `I64 i=7; i*6;` drops into the crash monitor with
`illegal instruction, insn@mepc=0` (jump to null / freed JIT). Single expressions and
string statements are fine.

This is **pre-existing**, and `kernel-win-interactive` already gates it — it fails on
"Cd;FileMgr compound ... pick_hits did not increase". Verified by reverting the case
and rebuilding: baseline fails the same assertion with the same `res=0` and no pick
hits, and the two logs are byte-identical apart from that one failure block.

Worth noting what the diff exposed: baseline reports `pick_hits=2181325440` — an
**uninitialized read**. Adding `RVDocVT.HC`'s 32 KiB shadow grid shifted the BSS enough
to make it deterministically `0`. Same failure either way, but the garbage value means
there is a real uninitialized-memory bug in that path, independent of the compound
crash.

**A stray `x` prefixes the first typed line** (`> x2+3;`). Appears in every run, so it
is the case's own key injection leaking into the prompt rather than terminal input.

## Gate status (all three pre-existing red)

| Target | Failure | Same before my change? |
|---|---|---|
| `kernel-win-interactive` | compound ExePutS pick, `res=0` | yes — logs identical apart from the garbage-vs-0 value |
| `kernel-win-serial-smoke` | missing `PopUpPickFile ok` | yes — byte-identical log |
| `kernel-win-smoke` | render hash mismatch | yes — stale pin, `RVGr.HC` in flight |

## The four VT targets

| Target | What |
|---|---|
| `kernel-vt-smoke` | gated: idle present must cost 0 bytes |
| `kernel-vt-demo` | static frame, holds — for checking geometry on a real terminal |
| `kernel-vt-repl` | interactive, dig-down built-ins, plain-text body, no compiler |
| `kernel-vt-holyc` | **real HolyC ExePutS + real DolDoc**, full desktop, terminal-sized |
