# Translating NASA's core Flight System into HolyC

Goal: cFS running on the HiFive Unmatched as **HolyC source compiled by this tree's own
compiler** — not C objects linked beside the blob.

That constraint is the whole plan. It rules out the easy route (cFS is C; this tree already links
C next to HolyC, and `riscv64-unknown-elf-gcc` ships a 2.6 MB newlib) and replaces it with a
translation problem. Worth being clear about the trade: linking the C would be weeks, translating
is months. What you buy is a system with one language, one compiler, and no libc — and a very hard
workout for the compiler, which is arguably the point.

## Three layers, three strategies

cFS is designed to be ported by implementing OSAL (tasks, queues, semaphores, timers, files,
console) and the PSP (board startup, reset type, exceptions, watchdog, non-volatile store). cFE and
the apps are meant to be taken as-is. That maps cleanly onto three different jobs:

| layer | strategy | why |
|---|---|---|
| OSAL implementation | **hand-write in HolyC** | it is the platform layer; translated C would be wrong here even if it worked |
| PSP | **hand-write in HolyC** | board-specific by definition, and this port already has the pieces |
| cFE core (ES, SB, EVS, TIME, TBL) | **transpile** from the real C | this is the volume and the heritage; hand-translation loses both |
| apps (SCH, HS, DS, LC, CI/TO) | **transpile** | same, and they are the reason to run cFS at all |

Hand-writing the bottom two and transpiling the top two is the only split that is both honest and
finite. Hand-translating cFE is 100k+ lines and would drift from upstream the day it finished.

## The language gap, measured rather than assumed

Compiled against this tree's compiler just now, because these decide how much a transpiler has to
do:

| construct | status | consequence |
|---|---|---|
| `switch` fallthrough | **works like C** (`case 1:` falling into `case 2:` returns 3) | the biggest silent-breakage risk is simply absent |
| function-like `#define` with args | **works** (`ADD(2,3) + SQ(4)*256` == 0x1005) | most cFS macros survive translation untouched |
| `union` | exists (`KernelA.HH` documents HolyC unions) | CCSDS header overlays translate directly |
| `typedef`, `enum`, `const`, file-scope `static` | absent | transpiler must flatten: typedefs to real types, enums to `#define`, drop qualifiers |
| C types (`int`, `unsigned long`, `char`) | absent | mechanical rewrite to `I32`/`U64`/`U8`; **width bugs land here**, so it is the first thing to test |
| `volatile` | absent | largely moot: this compiler does no meaningful optimisation (its codegen is a stack machine), but say so rather than relying on it silently |
| `va_list` varargs | different model (HolyC has variadics, e.g. `Print`) | `CFE_EVS_SendEvent` and every `snprintf` need a shim, not a translation |
| libc | none | `string.h`, `snprintf`, `malloc` become HolyC: `MemCpy`/`StrCpy` exist, `snprintf` does not |
| `$` in string literals | **DolDoc markup** | a translated format string containing `$` changes meaning. Escape at translation time |

## The idea that makes this tractable: a differential oracle

A transpiler and a compiler can each be wrong, and their bugs look identical from the outside. So
never trust the translation — test it:

1. compile the **original C** unit on the host and run it,
2. compile the **transpiled HolyC** with `holyc-riscv` and run it under QEMU,
3. require identical output.

This tree already has exactly that shape in `tests/exec/oracle_manifest.tsv` — 113 cases that
compile HolyC, run it under QEMU and compare a single value. Extending it to "same program, two
languages, same answer" is the natural generalisation, and it catches transpiler bugs and compiler
bugs with one mechanism. Every translated cFE unit gets an entry.

## The compiler is on the critical path, and today proved it

Transpiled C will exercise paths hand-written HolyC never touches: deep expressions, dense
`switch`, unions, 32-bit wraparound, tables of function pointers. This tree found a live
miscompilation today — `ptr = <constant> + offset` scaled the offset by the pointee size, which had
been silently writing the wrong QSPI register for weeks and zeroing the wrong PLIC register — and
that was found only because a verb measured something and disagreed with its own decode.

So the plan must include compiler hardening as a first-class phase, not a hope. The gate that
works is the one used for that fix: snapshot every platform image, change the compiler, rebuild,
and require byte-identical output except where you can explain the difference.

## Phases, each with the property its gate asserts

**P0 — the translation spike.** Transpile *one* self-contained cFE file by hand and get it running
under QEMU with a differential oracle against the original C. Pick something with real substance
and no OS dependencies: the CCSDS message-header accessors are ideal. *Gate:* the same set of
header get/set calls produces byte-identical packet bytes in C and in HolyC. This is one day of
work and it tells you more about feasibility than any further planning.

**P1 — the transpiler.** Built on an existing C front end (libclang or pycparser), not a
hand-rolled parser: the preprocessor alone is a year of work. Emits HolyC plus an oracle case per
unit. *Gate:* the transpiler reproduces the P0 file byte-for-byte against the hand translation.

**P2 — OSAL and PSP in HolyC.** All OSAL entry points present; unimplemented ones return
`OS_ERR_NOT_IMPLEMENTED` rather than lying. Real from the start: console on the SiFive UART, clock
on CLINT `mtime` (**1 MHz**, measured), tasks on the existing cooperative `RVTaskSwitch`
scheduler, queues, and interrupts-off critical sections (single core, so that is honest and cheap).
PSP: reset type from a signature in retained DRAM, exceptions onto the existing trap dispatcher.
*Gate:* cFE Executive Services starts and Event Services logs one event, over the UART.

**P3 — Software Bus and two apps.** *Gate:* two apps exchange a message through a pipe, asserting
the message ID and pipe depth, not merely that something arrived.

**P4 — the command and telemetry link.** CCSDS over the UART first. Then over **raw Ethernet with a
custom ethertype**, which needs no IP stack and reuses `EthTx`/`EthRx` exactly as they are.
*Gate:* a ground-side script decodes a real telemetry packet captured off the wire by a different
machine — the standard of proof the Ethernet work used, not "the controller accepted it".

**P5 — Table Services and files.** OSAL's file API onto the in-memory filesystem, tables baked into
the image. Writable storage is separate: the SD driver here is deliberately read-only because that
card holds the bootloader and a working Linux, so persistence wants a second card.

**P6 — preemption.** OSAL's task model is priority-preemptive; this port is cooperative. The tick
already re-arms `mtimecmp`; what is missing is switching *from* the trap handler, plus priorities.
*Gate:* the property cooperative mode cannot satisfy — a task that never yields does not starve the
others. Write this gate now so it fails before P6 and passes after.

## What this port already brings, all of it measured

| cFS needs | what exists | evidence |
|---|---|---|
| microsecond clock | CLINT `mtime` at 1 MHz | 3,128,544 ticks across a 3 s gap |
| periodic tick | `HolyRVPreemptInit`; dispatcher re-arms `mtimecmp` | `bootstrap/holy_rt.h` |
| context switch | `RVTaskSwitch` (ra, sp, s0–s11) | `Kernel/KBootRV.HC` |
| exception handling | trap dispatcher, frozen frame, recover trampoline, debugger pane | `RVTrapRecoverArm` |
| command/telemetry link | Ethernet transmits **and** receives, both verified on the wire | `docs/UNMATCHED_DEVICES.md` |
| wall-clock epoch | battery-backed RTC in the PMIC | `Rtc` verb |
| CDS across a processor reset | **DRAM retains contents across a warm reset** | the `0xff` heap-control-block bug |

That last row is the happiest accident here. cFE's Critical Data Store is specified as data that
survives a processor reset but not a power cycle, and this board's DDR does exactly that — the
discovery that cost a day of debugging is the behaviour cFE wants.

## Risks, stated plainly

- **Scale is the whole risk.** Everything else is detail. If the transpiler does not work, this
  becomes hand-translation and should be abandoned in favour of linking the C.
- **Two wrongs that look alike.** A transpiler bug and a compiler bug are indistinguishable without
  the differential oracle. Build the oracle before the transpiler.
- **Width and sign.** C's `int` promotions versus explicit `I32`/`U32` is where silent numeric
  divergence will live. Make the P0 gate byte-exact, not approximately equal.
- **Cooperative non-conformance** through P2–P5: priorities advisory, `OS_TaskDelay` a floor, one
  runaway app starves all. Write that in the code, not only here.
- **Upstream drift.** A transpiler keeps you able to re-import; hand edits to generated HolyC
  destroy that. Treat generated files as build output.
- **Single core.** Harts 0 and 2–4 are parked. Fine for cFS; note it rather than discovering it.

## What to do first

P0, then stop and decide. One hand-translated CCSDS header unit with a byte-exact differential
oracle answers the only question that matters — whether translated cFS behaves identically — before
a transpiler or a line of OSAL exists.
