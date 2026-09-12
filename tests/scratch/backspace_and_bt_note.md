# Backspace, and making `bt` name the caller

Two fixes from driving `kernel-vt-holyc` as a real terminal rather than a byte stream.

## 1. Backspace did nothing — DEL vs BS

`RVWinSerialPoll` accepted `ch == 8 || ch == 127`. `RVWinTermPutChar` and
`RVWinAdamPutChar` — the entry points the VT loop feeds — accepted only `8`. A
VT100/xterm Backspace key sends **DEL (0x7F)**, which then fell through to the
printable test `ch >= 32 && ch < 127`, was excluded there too, and was silently
dropped. Three functions in one file, two of them wrong.

Second half of the bug: the handler truncated `w->body` only. A **doc-backed** window
renders from its `CDoc`, not from `body`, so on `kernel-vt-holyc` the erased character
would have stayed on screen even once the key was accepted. `RVWinBodyPutChar`
(`RVWinMgr.HC:3041`) already pairs the truncation with `DocEdBackspace(w->doc)`; that
pairing is now used in both PutChar entry points.

Verified: `3+9`, DEL, DEL, `+4;` → `3+4;` → `ans=7`.

Suspected but **disproved**: `DocEdBackspace` opens with `DocCaptureUndo`, which does an
**unchecked `CAlloc`** followed by `DocSave` (a whole-document snapshot) on every
backspace — a clean heap-exhaustion story for the `MemCpy` fault seen around the same
time. Hammered it: 6 rounds of 40 characters typed and deleted, then evaluate. No
crash.

Two corrections to that theory, both worth recording because they narrow where the
real `MemCpy` fault lives:

- **`DocSave` is not a candidate.** It already guards its own allocation
  (`res = MAlloc(...); if (!res) { unlock; return NULL; }`). An earlier read missed the
  guard because the grep pattern matched the allocation but not the check — a good
  argument for reading the surrounding lines rather than trusting a filtered view.
- **A failed `CAlloc` in `DocCaptureUndo` faults differently.** The next store is
  `u->time_stamp = GetTSC`, an `sd` at a small offset — not the observed
  `sb t0,0(a0)` *inside* `MemCpy`. So it cannot be the crash that was reported.

Fixed anyway, since it was genuinely unchecked: a failed snapshot now drops the undo
entry and returns FALSE instead of dereferencing null. Undo is a convenience; losing
one when the heap is tight is correct, crashing the REPL is not.

The reported `MemCpy` fault therefore remains **unexplained**. With `bt` fixed (below),
the next occurrence names its caller, which is the missing piece.

## 2. `bt` printed one frame because nothing froze ra

`holy_rt.h` said so itself: *"RVCrashMon trap path freezes mcause/mepc/mtval only — not
fp/ra."* So a crash told you **where** it faulted and never **who called it** — useless
for the common case, a fault inside a shared leaf like `MemCpy` or `StrLen` where the
question is who passed the bad pointer.

`HolyTrapVector` already spills `ra`, `t0` and `t1` before calling the dispatcher, so
three stores into globals were enough:

```
"la t0, holy_crash_ra\n sd ra,0(t0)\n"
"la t0, holy_crash_fp\n sd s0,0(t0)\n"
"addi t1, sp, 128\n"
"la t0, holy_crash_sp\n sd t1,0(t0)\n"
```

`ra` is the valuable one. A fault inside a **leaf** traps before that function has saved
`ra`, so `ra` still holds its caller.

### Why there is no real frame walk

The obvious next step — chase the frame-pointer chain — does not work here, and the
reason is worth recording. A survey of eight random functions in the win kernel unit:

```
RVWinMgrBorderCharsInit  addi sp,sp,-16   ... addi s0,sp,16
RVVtClear                addi sp,sp,-16   ... addi s0,sp,16
CtrlAltT                 addi sp,sp,-24   ... addi s0,sp,24
ViewAnglesDel            addi sp,sp,-32   ... addi s0,sp,32
JobResScan               addi sp,sp,-56   ... addi s0,sp,56
Str2Date                 addi sp,sp,-120  ... addi s0,sp,120
```

The prologue is `addi sp,sp,-N / sd ra,0(sp) / sd s0,8(sp) / addi s0,sp,N`, so `ra`
lives at `s0-N` with **N varying per function**. This is not the standard RISC-V ABI
layout (`ra` at `s0-8`), so there is no fixed offset to chase and the guest has no
symbol table to recover N from. An earlier guess of "`ra = *(s0-32)`" was wrong — it
happened to hold for the two functions first disassembled, both of which had N=32.

`sp` is no help either: this codegen uses the stack as an expression machine
(`addi sp,sp,-8 / sd a0,0(sp)` for temporaries), so `sp` moves within a function.

So deeper frames come from a **conservative stack scan** — every word between the
trapped `sp` and `fp` that looks like a code address — explicitly labelled as such,
stale entries included. That is honest and useful; a fake frame walk would be neither.

### Verified against a known answer

```c
U0 LeafBoom(U8 *dst) { *dst = 'x'; }
U0 KnownCaller()     { LeafBoom(NULL); }
```

```
  #0 00000000809a9634            -> LeafBoom   +0x44
  #1 00000000809a966c  <- ra at trap   -> KnownCaller +0x1c
  -- stack scan (may include stale frames) --
     00000000809a966c
     0000000080ac18a0             <- a false positive, as documented
```

`#1` names the caller. The `bt` output also now prints the `HOLYC_MAP` recipe, so the
hex is actionable without going and looking it up.

## Risk

`HolyTrapVector` is linked into **every** `tests/exec` image, so this is the widest-blast
change in the session. It is additive — three stores to globals, in registers already
spilled — but "additive" is an argument, not evidence; the regression run is the
evidence.

## Follow-up: `holy_crash_in_code` was far too wide

The first version tested `a >= 0x80000000 && a < 0x87000000`, which includes the guest
heap (`0x82000400..0x86000000`). Every heap pointer sitting on the stack was therefore
reported as a candidate frame. On a real crash that meant **11 entries, 9 of them
noise**, with the two genuine frames buried.

Now bounded by the actual blob (`_binary_blob_bin_start`/`_end`) plus the small harness
text below it. Same crash, after:

```
(mepc not in code range)
mepc=0000000082625fd8
#1 0000000082625fd8  (ra not in code range — already clobbered)
-- stack scan --
   0000000080a4998c   ->  PrsVarInit2   +0xe4c
   0000000080a632a8   ->  PrsGlblVarLst +0x2f10
```

Two frames, and the two "not in code range" lines now *state* the diagnosis — a return
into non-code with a clobbered `ra` — instead of leaving it to be inferred from hex.

Lesson worth keeping: a range check written for "is this plausibly an address" is not
the same as "is this code", and the difference is the entire signal-to-noise ratio of a
conservative scan. Regression-clean: `exec-oracle`, `kernel-vt-smoke`,
`kernel-boot-smoke`, `kernel-plat-matrix` all pass.
