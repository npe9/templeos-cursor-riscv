# Triggering RISC-V traps from the HolyC REPL

Type these at the `>` prompt of the win_vt REPL.

**A fault returns you to the prompt**, it does not drop you into the monitor:

```
> *0x0(U32 *);
*** fault in that line - back at the prompt (`crash` for the monitor)
    mcause=5 (load access fault) mepc=8262EA90 mtval=00000000
> 2+3*4;
ans=14                        <- session survived
```

The REPL arms a one-shot recovery point (`RVTrapRecoverArm`) before each line;
the trap dispatcher resumes there instead of entering `crash>`. Type `crash` to
enter the monitor deliberately, or `fault` to trap into it. The monitor prints
`mcause` / `mepc` / `mtval` and accepts `md 0x<addr> <n>` (**hex** address with
the `0x`, **decimal** length), `mw`, `regs`, `bt`, `dump`, `go`, `reboot`.

## HolyC typecasts are POSTFIX

This is the thing that bites first. `*(U32*)0x0` is C; HolyC rejects it with
`Use TempleOS postfix typecasting`. The cast goes *after* the value:

```
*(U32*)0x0;      // WRONG — "Use TempleOS postfix typecasting at U32"
*0x0(U32 *);     // right
```

## Verified on this build

| mcause | Name | REPL line |
|---|---|---|
| 5 | Load access fault | `*0x0(U32 *);` |
| 7 | Store access fault | `*0x0(U32 *) = 1;` |
| 2 | Illegal instruction | `fault` — a crash-monitor command, not HolyC |

Each was run individually against `build/exec/win_vt.elf` and produced exactly
the cause listed.

## Setting `sepc` (and why `asm {}` won't do it yet)

`CSRW SEPC,T0` is the instruction you want. You cannot run it from the prompt
today, because **inline `asm {}` blocks do not execute in the REPL** — the JIT'd
snippet jumps to 0 instead. Every asm block gives the same signature:

```
asm { EBREAK };                    -> mcause=1 @ mepc=0   (should be 3)
asm { ECALL };                     -> mcause=1 @ mepc=0   (should be 11)
asm { LI T1,1; JALR ZERO,0(T1) };  -> mcause=1 @ mepc=0   (should be 0)
asm { csrw sepc,t0 };              -> mcause=1 @ mepc=0   (should not fault)
```

An `asm { sret }` that reports `mcause=1 mepc=0` is therefore **not** SRET
jumping to an unset `sepc` — it is this bug. (SRET *is* legal from M-mode and
would jump to `sepc`, which is why the result looks plausible.)

`asm {}` **now executes in the REPL.** Two bugs had to be fixed together, which is why
neither alone showed any improvement:

1. **`PrsKeyWord` classifies but does not consume.** At `case KW_ASM:` the token is still
   `asm` (`TK_IDENT` = `0x100`). The in-function / JIT arm called `CmpJoin(cc,CMPF_ASM_BLK)`
   on that same token, so `CmpJoin` re-entered `PrsStmt`, hit `KW_ASM` again and recursed
   until the stack died — measured as `PrsStmt` never returning *and* never throwing. Fixed
   by passing `CMPF_LEX_FIRST`, which is exactly what that flag is for.
2. **`CmpJoin`'s JIT path had no `CMPF_ASM_BLK` handling** — it funnelled into `PrsStmt`,
   which parses the body as HolyC. Fixed by routing it to `PrsAsmBlk`. (The AOT side never
   hit this: top-level AOT `asm{}` goes straight to `PrsAsmBlk` in the `KW_ASM` arm.)

Verified — a trapping instruction inside `asm{}` now reports its true cause:

| line | result |
|---|---|
| `asm { EBREAK; RET };` | `mcause=3 (breakpoint)` |
| `asm { NOP; EBREAK };` | `mcause=3` — the `NOP` ran first |
| `asm { LI A0,9; EBREAK };` | `mcause=3` — the `LI` ran first |

### Setting `sepc` — verified

| line | result |
|---|---|
| `asm { CSRW SEPC,T1; EBREAK };` | `mcause=3` — CSRW ran, then the breakpoint |
| `asm { LI T1,1; CSRW SEPC,T1; SRET };` | jumps to `sepc` (=1) → instruction access fault |

`SRET` is legal from M-mode and sets `pc = sepc`, privilege = `mstatus.SPP`. Because it drops
privilege, that fault lands in the `crash>` monitor rather than the REPL prompt — the one-shot
recovery point cannot resume across a privilege change.

A bare block no longer needs a hand-written terminator. A top-level `asm {…}` is executed
immediately via `Call()`, and a blob that is called must return, so the compiler now appends a
`RET` to exactly that case (`CMPF_ASM_CALLED`). It is not appended to in-function asm, where an
extra `RET` would return early from the enclosing function, nor to a definition-only blob with
`::` exports, which is never called. If the block already ends in a `RET` or a jump, the
appended one is simply unreachable.

Before that, `asm {addi t1,t0,1}` reported `mcause=2` exactly one instruction past the block —
the instruction *succeeding*, then execution falling into the zero padding (all-zero is the
defined illegal encoding). Note `srw` is not a mnemonic — a typo is parsed as a label and
answers `Expecting ':'`.

## Root cause of every `asm{}` failure: sub_switch codegen

`asm{}` in the REPL failed for one reason, and it was not in the assembler at all — it was the
**host compiler's `start:` / `end:` sub_switch codegen**, which `PrsStmt`'s keyword switch uses
heavily. Two separate bugs, both in `host/parser.c`:

1. **The `end:` block fell through into the next case body.** A `break` out of a sub_switch
   jumps to `sub_end`, which is emitted at `end:` — and then simply ran whatever case followed.
   Minimal repro: `switch(2)` with `start: r+=1; case 2: r+=20; break; case 3: r+=30; break;
   end: case 4: r=40; break;` returned **40** instead of **21**. Fixed by jumping to the
   switch end (or the enclosing group) after the `end:` block.
2. **`start:` groups did not nest.** The parser tracked a single open group in `cur_sub`, so an
   inner `start:` overwrote the outer one and the outer group's `sub_end` label was never
   defined — every `break` inside it jumped to an **unresolved label**. `PrsStmt` has exactly
   that shape (`start: case KW_ASM: … start: case KW_LOCK:`), which is why `asm{}` died right
   at its `break`, *after* the arm had completed. Fixed with a proper group stack, plus
   defining any still-open group's label at the switch end.

Regression test: `tests/exec/cases/e_subswitch_break.hc` → `0x7F` (covers the entry block,
break-exits-switch, cases after `end:`, and nested groups).

This is a general HolyC correctness fix — any `switch` using `start:`/`end:` was affected, not
just the asm path.

### Working now

| line | result |
|---|---|
| `asm {addi t1,t0,1}` | runs, no fault, no terminator needed |
| `asm {csrw sepc,t1}` | runs, no fault |
| `asm { NOP; RET };` | runs, no fault (explicit RET still fine) |
| `asm { EBREAK; RET };` | `mcause=3` |
| `asm { LI T1,1; JALR ZERO,0(T1) };` | transfers control and traps |
| `I64 Nine() { asm { LI A0,9 }; } Nine;` | `ans=9` |
| `I64 Ten() { I64 v; asm { LI A0,10 }; v=5; return 7; } Ten;` | `ans=7` — no early return |

(The `WARNING: Function should return val` on that last one is expected — the asm sets `a0`
directly rather than using a HolyC `return`.)

## Not currently reachable from the REPL

- **`Call(addr)`** answers `Undefined identifier`. It is genuinely not exported to the REPL —
  `RVExePubsWireAddrs` registers only Print, PutChars, Regs, Reg, Dir, Ls, Pwd, Cd, Help, Man;
  `RVCmpImports` registers `Call` for the *compiler unit*, which the REPL does not chain to.
  (It previously returned a silent `ans=0`; that was the sub_switch miscompilation swallowing
  the error, and the honest diagnostic only appeared once that was fixed.) Use
  `asm { LI T1,<addr>; JALR ZERO,0(T1) };` instead.

- **Function-pointer globals are mis-declared.** `U0 (*fp)();` creates a **U0 variable** named
  `fp`, not a function pointer — the following `fp=0x1000;` answers
  `WARNING: Assign U0` then `ERROR`. So the failure is in the top-level *declarator* parse, not
  in the call. The host compiler handles the same shapes correctly (`I64 (*g_fp)(); g_fp=&Target;
  (*g_fp)();` returns the right value), so this is guest-side only. Not diagnosed further.

## Notes for real silicon

- **QEMU virt fixes up misaligned load/store in hardware**, so causes 4 and 6
  generally do not fire under QEMU even from a genuinely odd address. They are
  reachable on VisionFive2 / Milk-V Mars. Under QEMU use an *unmapped* address
  (causes 5/7) for a deterministic data fault.
- **Cause 0 needs an odd address.** With the C extension (`-march=rv64imafdc`) a
  2-byte-aligned target is legal, so only a genuinely odd PC traps.
- **Cause 2 is the reliable bad-jump signal**: an all-zero word is a defined
  illegal instruction on RISC-V, so a jump into zeroed memory traps immediately.
  That is what the monitor's `fault` command uses.

## Memory map worth knowing

| Region | Range |
|---|---|
| Monitor's accepted DRAM window (`md`) | `0x80000000`–`0x88000000` |
| Blob load base (kernel unit) | `0x80800000` |
| Heap arena | `0x82000400`–`0x86000000` |
| Framebuffer | `0x86100000` |
| Stack base (`CONFIG_STACK_BASE`, grows DOWN) | `0x87F00000` — **not** scratch |

To resolve an address from `bt`, subtract the unit base (kernel unit is
`0x80800000`; later units sit at `align8(raw_n)` of the previous one) and look
the offset up in `build/aot/win/{kernel,compiler}.map`.

## REPL survival: `^C` and fault recovery

A fault returns you to the prompt (`RVTrapRecoverArm` — see above), and **`^C` now breaks a
wedged evaluation**:

```
> I64 w; w=0; while(1) w++;
^C — interrupted, back at the prompt
> I64 w; w=0; while(1) { asm { WFI }; w++; }
^C — interrupted, back at the prompt
```

The polled UART path can never see the `^C` while an evaluation is wedged, so the 16550 RX
interrupt is enabled and the break is hooked in the ISR: on `^C` with a recovery point armed it
sets a request, and the trap dispatcher `mret`s into the recovery trampoline instead of back
into the loop. `wfi` wakes on an interrupt, so a parked core is interruptible too.

Non-break characters must reach the **kernel's** `RVUartSoftRx` ring (what `RVUartTryGet`
reads), not the runtime's separate `holy_urx` ring — otherwise the ISR silently eats
keystrokes. They go through a sink registered with `RVSetRxSink`.

The recovery point is armed around the whole of `RVWinSerialDispatch`, not just evaluated
statements, and disarmed on every exit (the trampoline restores `ra/sp/fp` captured at the arm,
so leaving it armed past that frame would jump into a dead frame).

## `csrs` — CSR dump

`csrs` (or `csr`) prints machine + supervisor CSRs and the counters, direct like `regs` with no
JIT in the path:

```
Machine:     mstatus misa mie mip mtvec mscratch mepc mcause mtval mhartid medeleg mideleg mcounteren
Supervisor:  sstatus satp sie sip stvec sepc scause stval
Counters:    cycle time instret
```
plus the decoded `mcause` line.

### Fixed: `regs` and `csrs` stalled the REPL (RX interrupt raced the poller)

Symptom: both printed their full, correct output and then the REPL stopped accepting input.

Cause: enabling the 16550 RX interrupt (for `^C`) left the **ISR and the polled reader both
live on the same FIFO**. The ISR drains RX into the runtime's ring; every REPL consumer polls
the hardware through `RVUartTryGet`, and the VT loop
(`tests/exec/cases/kernel_win_interactive.hc`) has its own `ch = RVUartTryGet;` as well. Chars
the ISR took were never seen by either, so keystrokes vanished — and the more the kernel
printed, the more interrupts fired and the more often the ISR won. That is why it looked like
"`regs` hangs after a big dump" while `help` and `bt` were fine.

Fix: make the two mutually exclusive. The RX interrupt is enabled **only while a dispatched
command is running** — exactly the window in which nothing is polling — and turned off again
before returning to the input pump, with the runtime ring drained into the kernel's soft ring
in normal (non-interrupt) context on the way out. `RVUartTryGet` also checks that ring first as
a safety net for any other consumer.

Verified: `regs` and `csrs` both return — alone, after an `asm{}`, after a `Reg()`, and as
`Regs;` — and `^C` still breaks a wedged evaluation. Note `regs` is *slow*: ~20 s for its ~40
lines, because every printed line recomposes and re-presents the whole window. A prompt that
seems dead after `Regs;` is usually just still drawing.

Also expected, not a bug: registers do not persist between REPL statements. After
`asm {addi t6,t0,3}`, `Reg("t6")` reads 0 because `Reg` snapshots the registers *when it runs*,
and t6 was clobbered long before. To observe a value computed in asm, store it and dump it:

```
> asm { LI T0,0x87000000; LI T1,0x1234; SD T1,0(T0) }
> md 0x87000000 16
87000000: 34 12 00 00 ...
```

Diagnosis note, because two earlier readings in this file were wrong: sampling `mepc` under
gdb showed PCs in `RVVtPresent`/`RVTextRect`/`RVTextChar`, which looked like a rendering
livelock. It was not — those are simply the main VT loop, which was running normally the whole
time. The system was alive; only input was lost. `sp=0x87eff608` (2552 bytes used) had already
ruled out stack exhaustion. The decisive test was disabling `RVUartIrqInit()`: both commands
returned immediately, which pinned it to the interrupt rather than to anything in `regs`/`csrs`.
