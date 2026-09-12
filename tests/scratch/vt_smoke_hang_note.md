# `kernel-vt-smoke` hung silently — `ChkOnStk` deref of a task with no stack

RESOLVED. Kept because the *silence* is the reusable lesson, not the one-line fix.

## Symptom

`make kernel-vt-smoke` produced the 11 `import unresolved` lines and then nothing at
all — no `VT: WinMgr lite up`, no `VT: LiteInit FAILED`, no fault message. QEMU sat
there until the 60 s timeout killed it. Every VT-specific theory (the shadow diff, the
ANSI emitter, `RVDocVT.HC` itself) was wrong; none of that code ever ran.

## Cause

`Kernel/KDbg.HC` `ChkOnStk`:

```
  if (task) {
    if (&task->stk->stk_base<=ptr<=
	  (&task->stk->stk_base)(U8 *)+task->stk->stk_size)
```

`task->stk->stk_size` is a load through `task->stk`. In the bare AOT exec harness
(`tests/exec/harness`), `Fs` is a static `CTask` living inside the blob with
`stk == NULL` and `task_signature == 0` — `RVKernelInit()` does not build a task
stack. So the load is from address `0x8`.

On x86 that address is mapped; the load returns junk and `ChkOnStk` answers FALSE.
On RISC-V it is `fault_load`. **This is a genuine port difference, not a harness
artifact.** Fixed by nesting a `if (task->stk)` guard, which preserves the original
answer (FALSE) for a stackless task rather than falling through to the heap-range
arm of the `else if`.

## Who was calling it, and whether the guard masks anything

It does not. Chased with gdb (`break *<Caller addr>`, read `$ra`, resolve through the
same `HOLYC_MAP`):

```
RVWinMgrLiteInit  ->  DocInit  ->  DefineLstLoad  ->  Caller()  ->  ChkOnStk(rbp, Fs)
```

`DocInit` is the last statement of `RVWinMgrLiteInit`, and `Kernel/KDefine.HC`
`DefineLstLoad` does

```
  tmph->src_link=MStrPrint("AD:0x%X",Caller);
```

— pure bookkeeping, recording who built the define list so DolDoc can hyperlink back
to the source. Nothing was throwing and nothing was reporting an error: the `$ra` trace
lands in `DefineLstLoad` itself, not in `throw` or `PrintWarn`. With the guard,
`Caller()` returns NULL and `src_link` becomes `"AD:0x0"` — a dead documentation
back-link for a task that has no stack to walk, which is the correct degradation.

`UnusedStk` (`KDbg.HC`, same file) reads `&task->stk->stk_base`, which is address-of
and so computes rather than loads — it does not fault on a stackless task. It returns a
garbage-large value, which both call sites (`KTask.HC:119` `>= threshold`,
`WebLogRep.HC` `< 0x200`) take the safe branch on. Left alone deliberately.

## Why it was silent rather than a crash

`tests/exec/harness/crt0.S` installs **no `mtvec`**. The load fault therefore traps to
address 0, which is not code, which faults again — `fault_fetch` at `epc=0` forever.
A hang, not a message. Confirmed in the QEMU log: one real exception followed by
3.8 million identical fetch faults.

## What actually found it, in order

1. **`qemu-system-riscv64 ... -d int,unimp,guest_errors -D log`** — no rebuild, no
   gdb. First line named it outright:
   `cause:5 desc=fault_load epc:0x80836180 tval:0x8`. A hang that is really a trap
   loop looks identical from outside; this separates them in one command.
2. **`HOLYC_MAP=file`** (already in `host/compiler.c`) — emits `offset name` per
   function. `epc - _binary_blob_bin_start = 0x36180` → `ChkOnStk +0x194`. The blob is
   `objcopy -I binary`'d in, so it has no ELF symbols and gdb gives a bare `pc`; the
   map is what makes that `pc` mean something. Sanity check that it is trustworthy:
   the neighbours resolved to `ChkPtr` / `ChkCodePtr` / `ChkOnStk` / `UnusedStk` /
   `Caller`, which is `KDbg.HC` in source order.
3. **Diffing against a working neighbour.** `kernel-win-smoke` runs the same
   `RVWinMgrLiteInit` fine — its case (`kernel_win_demo.hc`) opens with
   `RVWinSmokeAdamBoot`, which does `TaskInit(adam,0)` and so gets a real `->stk`
   (`Kernel/KTask.HC:226`). That is why the WinMgr cases never tripped this.

## Result

```
VT: first=2373 idle=0 after=41
Kernel-VT smoke: OK
```

Both design gates hold: an idle present costs exactly 0 bytes, and a one-line edit
costs 41 against a 2373-byte full paint.

## Regression check — and two other smokes this un-hung

Ten targets run with the fix, then the four failures re-run against a **stock**
`KDbg.HC` to get the baseline that did not exist beforehand (`cp` the pristine file
back, re-run, restore). Result: **no regressions**, and the guard turned out to be
load-bearing for more than VT.

| Target | stock `KDbg.HC` | with the guard |
|---|---|---|
| `kernel-boot` / `heap` / `ctask` / `fs` / `thin-loader` / `exepubs` | — | PASS |
| `kernel-vt-smoke` | silent hang | **PASS** |
| `kernel-cdc-smoke` | **silent hang** (no output, SIGTERM at timeout) | runs to completion; fails only on a stale hash pin |
| `kernel-span-smoke` | **silent hang** (no output, SIGTERM at timeout) | runs partway, prints `RVPopUpWire` + `$BG,LTCYAN$`, then no smoke line |
| `kernel-phase3-smoke` | FAIL `CallIcSoft r=-85` | FAIL, byte-identical log |
| `kernel-win-serial-smoke` | FAIL | FAIL, identical apart from build-cache noise |
| `kernel-gr` / `demo-blot` / `win` | — | FAIL, stale hash pin (they **do** run) |

The three render smokes are the genuine stale-pin category the earlier notes describe —
they execute, produce a hash, and disagree with the pin:

```
kernel-gr-smoke         want 0x6EF34074  got 0x2C881662
kernel-demo-blot-smoke  want 0xA3B0362C  got 0x43186381
kernel-win-smoke        want 0xF29CD5B3  got 0x64A56F2C
```

That is a different failure mode from a hang, and worth keeping distinct: a stale pin
still tells you the render changed; a hang tells you nothing.

`kernel-cdc-smoke` and `kernel-span-smoke` were hitting **the same `ChkOnStk` fault**,
with the same signature — no output at all, killed by the harness timeout. They were
being read as ordinary red targets. They were not: they never ran.

This matters for `crvdc_alignment_note.md`, which parked the CRVDC field-reordering
work on the grounds that the render smokes were red from stale pins and had to be
untangled first. `kernel-cdc-smoke` now produces a real hash
(`got 0x95A09C04` vs `want 0xEFB2D715`), so that blocker is partly a different
problem than it looked. **The hash was not re-pinned** — with `RVGr.HC` still in
flight, re-pinning would destroy the only signal those smokes carry.

`kernel-thin-loader-smoke` is not evidence either way: `KDbg` is inside
`#ifndef RV_THIN_LOADER` (`Kernel_RV.PRJ:106-108`), and
`tests/exec/cases/kernel_thin_loader_demo.hc:6` is the **only** case in the tree that
defines that macro — so the thin image never had `ChkOnStk` to begin with.

Every other target listed *does* compile the changed function, `kernel-phase3-smoke`
and `kernel-win-serial-smoke` included. Their logs being byte-identical before and
after is therefore real evidence of no behaviour change, not an artifact of the code
being absent.

## Left undone, deliberately

~~**`crt0.S` has no trap vector.**~~ **Done — see the section below.**

**Not a bug, noted so it is not re-investigated:** the smoke's border paints with no
top edge. `RVTextBorder(l,r,t,b,...)` draws *outside* the rect — top edge at `t-1` —
and the case passes `t=0`, so that row is clipped at y=-1. Correct for the arguments;
the case would read better as a demo with `t=1`, but changing it moves the byte
counts the smoke prints.

---

# Follow-up: the exec harness now reports faults instead of hanging

The item above was the real lesson, so it got fixed in the same session.

`tests/exec/harness/crt0.S` now installs `mtvec` before anything else runs, pointing at
a handler that reports and halts:

```
TRAP mcause=0x0000000000000005 (load-fault) mepc=0x0000000080800178 mtval=0x0000000000000008 blob+0x0000000000000178
TRAP halted
```

`trap_report` lives in `oracle_out.c` (with a cause-name table) and
`oracle_out_plat.c` (numbers only, to stay inside the sifive_e 16 KiB DTIM budget) —
those are the two files paired with this crt0, and each already carries the right
`UART_BASE`. `crt0.S` itself is never given `-DUART_BASE`, which is why the printing is
in C rather than assembly.

**`blob+0x...` is the whole point.** The blob is `objcopy -I binary`'d in and has no
ELF symbols, so a raw `mepc` names nothing. That offset drops straight into
`HOLYC_MAP=file` output. The manual version of this — read the QEMU `-d int` log,
subtract `_binary_blob_bin_start`, index the map — is what the section above describes
taking a full round. It is now one line of harness output.

## Validation

| Scope | Result |
|---|---|
| `exec-oracle` (manifest-driven, the largest consumer of this crt0) | **84 pass, 0 fail** |
| `kernel-plat-matrix` (board matrix; GAPS says skips not allowed) | **ok=11 fail=0**, no skips |
| `kernel-sifive-e-full-smoke` (16 KiB DTIM — the size risk) | PASS |
| `kernel-plat-smoke` | PASS |
| 24 `kernel-*-smoke` targets | 17 PASS; the 7 failures are the pre-existing red set, and each log is **identical** to the pre-trap-vector run |

No case anywhere emitted a TRAP line, so nothing in the tree is currently faulting —
the vector is a net-new diagnostic, not a bug detector that found more work.

## Why this is safe across 65 scripts

- A trap today is an infinite loop, so **no currently-passing target ever traps**.
  Installing a handler cannot change a green test's behaviour.
- It does not enable interrupts. `mstatus.MIE` and `mie` are untouched, so nothing
  new becomes deliverable.
- It is a floor, not a policy. `bootstrap/holy_rt.h` installs its own vector in four
  places (`RVTrapInit` / `RVPreemptInit` / `RVTrapDiag` / `RVPreemptReal`); those run
  later and win. `kernel-timer-smoke` and `kernel-preempt-smoke` exercise exactly that
  path and stay green.
- `crt0_sifive_e_boot.S` (fe310) and `crt0_smp.S` are **not** touched, so
  `oracle_out_fe310.c` never needs a `trap_report` and nothing there can fail to link.
- Every link script paired with this crt0 collects `.bss`, so the 512-byte
  `trap_stack` is placed rather than orphaned — checked for `link_exec`,
  `link_sifive_e`, `link_opentitan`, `link_visionfive2`, `link_milkv_mars`,
  `link_exepubs`, `link_sifive_e_full`.

## Deliberately not done

**The handler halts; it does not power off.** QEMU `virt` has `sifive_test` at
0x100000, so a trapped case could exit immediately instead of sitting until the
script's `timeout`. It is not worth it: this crt0 is shared with real-board builds
(visionfive2, milkv mars, icicle, opentitan), where 0x100000 is a stray MMIO poke.
`wfi` parks the vCPU, so the wait is idle, and diagnosability — not speed — was the
goal. Revisit only if a board-safe exit path appears.

---

## One gap this exposed

`Kernel/KDbg.HC` is the **first stock TempleOS file this port has modified** — every
other changed file is port-authored or a `_RV` variant. There is no registry of such
divergences: `docs/GAPS.md` is a gap-fill plan, not a per-file record, so this note is
the only place the change is explained.

That is fine for one file. If the port accumulates more x86-tolerated-but-RV-faulting
fixes — and the mechanism here (unaligned or wild loads that x86 absorbs) suggests it
will — a short `docs/STOCK_DIVERGENCES.md` listing file, function, reason and the
x86-vs-RV difference would be worth more than a scattering of scratch notes. Not
created here because one entry does not justify a registry.
