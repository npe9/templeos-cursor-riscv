# What the guest HolyC REPL can and cannot compile (kernel-vt-holyc / kernel-win-interactive)

Measured one statement at a time against `make kernel-vt-holyc`, which runs the real
`ExePutS` compile loop. This replaces two earlier, wronger summaries of mine
("compound statements crash", "the implicit-Print form is the problem").

## Works

| Statement | Result |
|---|---|
| `3+4;` | `ans=7` |
| `I64 i;` / `U8 *s;` / `U32 i;` | declaration without initialiser is fine |
| `i=7;` | `ans=7` |
| `i*6;` | `ans=42` — the variable reads back correctly |
| `for(i=0;i<3;i++) Print("HI\n");` | prints `HI` three times — **control flow is sound** |
| `Cat("HOME.DD");` | runs — a single literal argument to a published function works |

## Broken

| Statement | Result |
|---|---|
| `I64 i=7;` | **crash** — declaration *with* an initialiser |
| `for(U32 i=0; …)` | **crash** — same thing, the `U32 i=0` inside the header |
| `Print("HI %d\n", 42);` | **crash** — a literal vararg |
| `Print("HI %d\n", i);` | prints `HI 2158937772` — a *constant*, so `i` never arrives |
| `"HI %d\n", i;` | same garbage — the implicit-Print form is not special |

## The two failures are probably one failure

Both crashes land the same way: `mepc` inside the heap (`0x82000400..0x86000000`),
`insn@mepc = 0` — freed, zeroed JIT code being executed — and the `bt` stack scan
resolves a blob-range frame to **`PrsVarInit2 +0xe0c`**, byte-identical across the
`I64 i=7;` and `for(U32 i=0;…)` cases. `PrsGlblVarLst` appears too, which calls into it.

`PrsVarInit2` compiles the initialiser expression to a block and **calls it while still
parsing** (`Compiler/PrsVar.HC:97`). That is a different path from `ExePutS`'s own
`Call(machine_code)`, which works — `3+4;` proves it.

The varargs failure rhymes with it: an argument that must be *evaluated and passed*
either crashes (literal) or arrives as a fixed garbage value (variable). The common
shape is guest-compiled code that has to marshal a value into a call. A no-argument
call (`Print("HI\n")`) is fine; a single already-materialised pointer (`Cat("HOME.DD")`)
is fine; anything requiring an argument slot to be filled is not.

That is a hypothesis, not a conclusion — it fits every row above but has not been
traced to a single defect.

## Practical guidance

- Declare and assign separately: `I64 i;` then `i=7;`.
- Loops are fine as long as the induction variable is declared beforehand.
- **Do not trust any `%d`/`%s` output from the guest REPL** — the format string prints,
  the arguments do not. `Print("HI\n")` is safe; `Print("HI %d\n", x)` is not.

## Not fixed

`PrsVarInit2` and the varargs marshalling are shared compiler code — `repl-cmp`,
`phase3`, the win images and `exec-oracle` all run through it. `exec-oracle` (84 cases)
and `compliance` (100 cases) both pass, so whatever is wrong is specific to the
**guest-compiled** path, not the host AOT compiler. That asymmetry is the most useful
lead for whoever picks this up.

## Investigation log — what is established, and what tripped me up

Established:

- The faulting return address really is inside **`PrsVarInit2`** (`Compiler/PrsVar.HC:125-208`,
  compiled size `0x10bc`, fault at `+0xe0c` — so it fits, the attribution is sound).
- `PrsVarInit2` recurses and then calls **`PrsVarInit`** (`PrsVar.HC:1`), and *that* is the
  function holding `r = Call(machine_code)` (~line 97) — the eval-during-parse of the
  initialiser expression.
- `LexExpression2Bin` already does `COCPush`/`COCPop` around its compile, and `COCPop` frees
  only the saved `CCodeCtrl` struct, not the code buffer (`COCCompile` does its own
  `MAlloc(code_size, Fs->code_heap)`). **So a dangling-buffer-from-COCPop theory is wrong.**

Ruled out as the cause of the crash: nested-COC clobber, `COCPop` freeing the block,
`Call(NULL)` (`ExePutS` now guards it anyway; the crash survived).

Two traps that cost real time here, worth avoiding next round:

1. **I read the wrong function for a long while.** `grep -n "^U0 PrsVarInit2"` said line 123,
   and I then read lines 40-120 — which is `PrsVarInit`, a *different* function. Every
   conclusion drawn from "PrsVarInit2's Call site" during that stretch was about the wrong
   body. Check the span, not just the start line.
2. **`Print` from inside the compiler is invisible in this configuration.** Output is mirrored
   into the DolDoc, and the crash happens before the next `RVVtPresent`, so nothing reaches the
   UART. A probe placed before the faulting `Call` printed nothing and looked like "we never got
   here" when it may simply never have been shipped. Writing to fixed RAM and reading it with
   `md` at the `crash>` prompt is the right shape — though `md 0x86B00000 32` produced no dump
   either, so the crash monitor's `md` argument form needs checking first.

The next experiment, stated concretely: stash `machine_code` and `*(U32 *)machine_code` to a
fixed address immediately before `PrsVarInit`'s `Call`, and read it back **after a reboot** (or
via a host-side memory dump) rather than through the crash monitor. That distinguishes
"block was never written", "block was written then freed/zeroed", and "Call jumped somewhere
other than machine_code" — three very different bugs that currently look identical.

---

# RESOLVED DIAGNOSIS: it is stack corruption, not a bad call target

Every "jump-to-null / freed JIT" reading of this crash was wrong, mine included. The
evidence, gathered with scratch-RAM probes read back via `md` at the `crash>` prompt
(`md` works — earlier "no output" was my own grep searching uppercase hex against
lowercase output):

**1. What the illegal instruction actually is.** `mcause=2`, `insn@mepc=0`. An all-zero
word is a defined-illegal RISC-V encoding, and `mtval=0` is consistent with it. So the
CPU is executing a zeroed word — the question is only how it got there.

**2. The JIT'd code is perfect.** Probing `machine_code` immediately before the call:

```
machine_code = 0x830b7690
  word0 = 0x00700513   ->  li a0, 7
  word1 = 0x00008067   ->  ret
```

Exactly the right code for `I64 i=7;`.

**3. `PrsVarInit`'s eval-during-parse works.** Before/after markers plus a counter:
called **once**, after-marker set, returned **7**. It is not the crash site.

**4. `ExePutS`'s own `Call` loop works.** Same instrumentation: **14** calls, all with
valid code, after-marker set. Every one returned.

**5. So nothing jumps to a bad target — something RETURNS to one.** `bt` reports
`#1 ra == mepc`, and the faulting address is the variable's heap storage **+ 8**:

```
82625fb8: c0 5e 62 82   <- heap chunk: prev pointer
82625fc0: 40 00 00 00   <- size 64
82625fc8: 40 00 00 00   <- size 64
82625fd0: 07 00 00 00   <- user data = our i = 7
82625fd8: 00 00 00 00   <- mepc lands HERE
```

That region is **heap chunk metadata and user data**, not code. A saved return address
was overwritten with (storage pointer + 8), and the epilogue returned into it.

## What this redirects the hunt to

Stop looking at the compiler's call/emit path — `Call`, `COCCompile`, `CCF_NO_ABSS`, the
`__imp_Call` HOFYIMP1 slot and missing `fence.i` were all tested and are all innocent
(the `fence.i` fix was kept anyway: it is required by the ISA and matters on the board
targets, verified regression-clean).

Look instead for **whoever writes past a buffer onto a saved `ra`** during a declaration.
The strongest lead is an already-recorded defect in this tree: a narrow local array
whose `*arr = val` emits an 8-byte store and clobbers its neighbours. A local array in
the declaration path plus an oversized store lands exactly on a saved return address,
and would produce precisely this signature.

That also explains the sibling symptom — `Print("%d", x)` printing a fixed garbage value
— far better than a "varargs ABI" story: the same corruption reaches the argument area.
