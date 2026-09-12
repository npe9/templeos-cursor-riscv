# CDC member-table bug — RESOLVED

Kept as a record because the trap is easy to fall into again, and because two rounds
of confident reasoning from the symptom produced two wrong theories.

## Symptom

`MakeAdam_RV.PRJ` failed with 3 errors, all `offset(CDC.end)` / `offset(CDC.start)`
in `Adam/Gr/GrDC.HC:302` and `:348` (the DCSave / DCLoad serialization span).
Probing member by member suggested 16 of `CDC`'s members were absent from
`ocls->member_lst`, in a pattern that looked type-driven — `U0` markers, class-typed
members and arrays dropped, plain `I32` kept — but with exceptions both ways
(`CDC *brush` present, `CDC *alias` missing; `I32 x0` present, `I32 cur_x` missing).

## Cause

**`Kernel/RVGr.HC:24` does `#define CDC CRVDC`.**

`CDC` resolves to the thin RV device context, not TempleOS's `CDC`. The eleven
members that "worked" — `x0`, `y0`, `width`, `width_internal`, `height`, `flags`,
`color`, `bkcolor`, `color2`, `brush`, `thick` — are *exactly* `CRVDC`'s member
list. Every member that "failed" is real-`CDC`-only. There was never a member-table
bug and never a compiler bug; stock `GrDC.HC` was asking a thin substitute class for
a serialization span it does not have.

The alias is deliberate (see the comment at `RVGr.HC:9`) — it lets stock
`Demo/Graphics` code compile against the thin DC. It just collides with stock Adam.

## Fix

`CRVDC` now declares its own `start` / `end` markers bracketing the serialisable
scalar header (`width` … `flags`), placed after `body` because a pointer must not be
serialised — it is re-derived on load.

`U0` members are zero-size, so this is layout-preserving. Confirmed with
`HOLYC_DUMP_CLASS=CRVDC`: `start` at offset 8, `end` at 60, `is_scrn` still at 60,
class size unchanged. Independently confirmed by removing the markers and observing
the `kernel-gr-smoke` render hash is identical either way.

`MakeAdam_RV.PRJ`: **3 errors → 0.** The whole stock Adam tree — Gr, Snd, WinMgr,
DolDoc, God, AutoComplete, Ctrls — now compiles against the RISC-V kernel.

Caveat worth stating: this makes `GrDC.HC` *compile*. Whether RV `DCSave` / `DCLoad`
round-trips a `CRVDC` correctly is a separate question with no test today.

## What actually found it

Two steps, after two wrong theories:

1. **`HOLYC_DUMP_CLASS=<name>`** (added to `host/parser.c`, env-gated like
   `HOLYC_TRACE`) dumps a class's member table at parse time. It showed `CDC`'s table
   was *complete* — 43 members, correct offsets, `start` at 0 size 0, `end` at 32
   size 0 — which reframed the question from "why are members missing" to "why does
   the lookup fail", and those have different fixes.
2. **Naming the class in the error.** `offset: unknown member` became
   `offset: unknown member 'end' in class 'CRVDC'`, and the answer was immediate.

Method note: the symptom was a stable, reproducible pattern, and reasoning about that
pattern produced two plausible theories (type-driven skip; positional truncation) that
each explained about half the data. Neither survived contact with the member dump. The
cheap instrumentation was worth more than either round of inference.

## Unrelated defects fixed while here

- `host/parser.c` `offset()` member walk had no NULL guard on `om->str`, while
  `HostMemberFind` guards it — a nameless member would have crashed the compiler
  rather than producing an error. Guarded.
- `host/parser.c:5227` `m->member_class = (ptr || is_array) ? mcls : mcls;` — both
  arms identical, an unfinished edit. Left alone (harmless), noted here.
