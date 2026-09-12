# Plan: fix the eval-stack / saved-`ra` corruption

## 1. The bug, restated from evidence

The eval stack **is** `sp`: every temporary is `addi sp,sp,-8` / `sd a0,0(sp)`.
The frame saves the return address at the *bottom* of the frame:

```
addi sp,sp,-192
sd   ra,0(sp)        <- ra AT the frame base
```

At a label, `host/compiler.c` adopts a branch's recorded depth **in the model only**:

```c
case IC_LABEL:
  { CLabel *lb = ic->ic_data; if (lb->sd_set) stack_depth_pass = lb->sd; ... }
```

No `addi sp` is emitted, so a fall-through path arriving at a different depth leaves the
real `sp` where it was. Once `sp` has drifted one slot high, the next push writes over
the saved `ra` and the function returns into the heap.

Directly observed (literal-address software watchpoint):

```
PrsVarInit frame: sp=0x87eff2e8  saved_ra=0x80a4970c
Old value = 0x80a4970c  ->  New value = 24
WROTE at PrsVarInit+0x534:   li a0,24 ; addi sp,sp,-8 ; sd a0,0(sp)
```

`1038` label joins in the win Compiler unit have a fall-through depth differing from
`lb->sd`.

## 2. How stock TempleOS does it — and why that matters

Terry did **not** use a numeric force-assign. He used a per-edge entry protocol:

| Piece | Where | Role |
|---|---|---|
| `ICF_PUSH_CMP` | `KernelA.HH:1620` | set on a branch that pushed the compare value ("for `50<i<j<=100` exps") |
| `CMF_POP_CMP` | `KernelA.HH:1706` | propagated onto the **label** by `OptPass4.HC:543` |
| displacement fix-up | `BackB.HC:603-630` | each branch's target is adjusted `+4` if that edge pushed, `+8` if it did not |

So the label carries a small **pop fix-up at its head, and each incoming edge jumps to a
different offset inside it**. Every edge arrives with the stack in the same state,
without any edge having to guess another edge's depth.

**The RV/host port implements none of this** — `grep -c PUSH_CMP host/compiler.c
host/parser.c` is `0`. `lb->sd` was invented as a substitute and is lossy: one number,
last-writer-wins, and nothing emitted.

Note the host parser also never sets `ICF_PUSH_CMP`, so the mismatches here are not
chained comparisons; they come from the host's own short-circuit / bool-elide paths
(see the comment at `host/compiler.c:1820` about OR elision rewriting an outer AND's
`BR_ZERO`).

## 3. Plan

### Phase 0 — measure before changing codegen — **DONE, results below**
Re-add the `HOLYC_WARN_STACK` reporter, extended to print **function, IC opcode,
fall-through depth, `lb->sd`, label id**. Classify the 1038:

- how many labels have genuinely >1 distinct incoming depth, versus
- how many are artifacts of `lb->sd` being a stale last-writer value.

*Gate:* do not touch emission until this distribution is known. It decides Phase 1 vs 2.

### Phase 1 — prefer fixing the generators
Replace the single `lb->sd` with a per-label record of every incoming edge's depth.
Report labels with more than one distinct depth.

If that set is small, fix the **IC generators** so both paths of a short-circuit leave
the same depth — balanced by construction, which is stock's actual invariant for
everything except the deliberate `PUSH_CMP` case. Cheapest and least invasive.

### Phase 2 — only if generators cannot be balanced: implement the protocol
Follow Terry rather than inventing:

1. Label emits a reconciliation prologue: `k` copies of `addi sp,sp,8`, where
   `k = max_depth - min_depth` over incoming edges.
2. An edge arriving at depth `d` targets `label_addr + (max_depth - d) * 4`.
3. Fall-through is just the `d = max_depth` case.

**Two hard constraints, both already learned the hard way:**

- `host/compiler.c` has **two** IC dispatch loops — the sizing pass (`stack_depth_pass`,
  ~line 2561) and the final emit pass (`stack_depth_final`, ~line 3152). They must emit
  **byte-identical** sequences or the size loop never converges
  (`emit size 1788784 != sized 1793344 (pass 2) — label/call mismatch`). Patching only
  one is what produced that error.
- Label depth state must be recomputed **deterministically each pass**, or sizing and
  emit disagree for the same reason.

A naive `addi sp, sp, (cur - lb->sd) * 8` at every label **is wrong** and was tried: it
converges once both loops match, then boots to `mepc=0x82000400` (the heap base),
because `lb->sd` means "the last branch's depth", not "the depth this join must reach".

### Phase 3 — structural hardening (do regardless of 1/2)
Move `ra`/`s0` off `sp+0` so eval-stack drift can never reach the return address —
standard RISC-V ABI keeps `ra` at `s0-8`. Not free here: locals are already addressed as
negative offsets from `s0` (`EmitIC_ENTER`, `g_o1_off[j] < 0`), so the frame layout has
to grow and locals re-base.

Value: converts a silent memory corruption into, at worst, a wrong temporary. Every
future eval-stack bug becomes debuggable instead of a mystery return into the heap.

## 4. Verification gates (run at every phase)

`make compliance` (100) · `make exec-oracle` (84) · `kernel-vt-smoke` ·
`kernel-plat-matrix` (11 boards) · `repl-holyc-regression` · `mux-smoke`

Plus the direct repro, which must go from crash to correct:

```
I64 i=7;                                  -> ans=7
i*6;                                      -> ans=42
for(U32 i=0;i<10;i++) Print("Hi %d\n",i); -> Hi 0..9   (also fixes the garbage-arg symptom)
```

## 5. Carry-forward notes (mistakes already paid for)

- gdb: `watch *(unsigned long*)$sp` watches an **expression** that moves with `sp` and
  reports false changes. Watch a **literal address**, with
  `set can-use-hw-watchpoints 0` so it stops synchronously in batch mode.
- Compiler-unit symbols resolve at `align8(raw_n)` where
  `raw_n = file_size - 16 - n_imports*32`. Using the raw file size mislabels every
  address (it cost `0x4d0` of drift and several wrong attributions here).
- `Print` from inside the compiler is invisible: it mirrors into the DolDoc and the
  crash beats the next present. Write to scratch RAM and read it with `md` at `crash>`.
- Scratch RAM: pick an address clear of the live task/stack region; `0x86B00000` sits
  just above `Gs` and perturbed at least one run.
- Rebuild the ELF after removing probes — a stale `build/exec/win_vt.elf` produced a
  crash report that looked like a new bug and was purely leftover instrumentation.

---

# Phase 0 RESULTS (win Compiler unit)

Instrumented every edge reaching a label (`HolyStackEdge`, `HOLYC_WARN_STACK=1`,
measurement only — no codegen change). 28568 edge records:

| | count |
|---|---|
| labels seen | 7931 |
| labels where every edge arrives at the **same** depth | **7425 (93.6 %)** |
| labels with divergent depths | **506 (6.4 %)** |

And the divergent ones are uniform:

- **every one is a 2-way split** — distinct-depth histogram is `{2: 506}`, nothing worse;
- **505 of 506 differ by exactly one slot** (spread 1); a single label has spread 2;
- **505 of 506 have the fall-through as the DEEP edge** (it carries the extra value);
  exactly **one** has fall-through shallow.

Depths are `[0, 1]` with kinds `{br, ft}` — one path left a value on the eval stack and
the other did not. That is precisely the case Terry annotates with `ICF_PUSH_CMP`.

## What this settles

Phase 1 (rebalance the generators) is **not** the cheap option: 506 sites, all the same
short-circuit shape. Implementing the protocol properly is both smaller and closer to
stock. Go to Phase 2.

## Phase 2, refined by the data

For each label, let `dmax`/`dmin` be the max/min incoming depth, `n = dmax - dmin`
(so `n == 1` for 505 of 506):

1. Emit `n` × `addi sp,sp,8` (4 bytes each) at the **label head**.
2. **Fall-through** enters at offset 0, executes all `n` pops, leaves at `dmin`. Correct
   for the 505 where fall-through is the deep edge.
3. A **branch** edge at depth `d` targets `label_addr + (dmax - d) * 4`, executes
   `d - dmin` pops, leaves at `dmin`. This is exactly `BackB.HC:603-630`'s `i += 4` /
   `i += 8` displacement adjustment, in RV instruction units.
4. Model depth after the label becomes `dmin` (not "whatever the last branch wrote").

**The one shallow-fall-through label** cannot use this layout — it would execute pops it
must not. Handle it by emitting a `j` over the fix-up for that case, or detect it and
report; do not silently mis-handle it.

### The structural requirement this exposes

`dmax` must be known **when the label is emitted**, which a single forward walk cannot
provide. So Phase 2 needs a **pre-pass** over the IC stream that computes per-label
min/max incoming depth, run once before emission and reused by both dispatch loops.

That also dissolves the convergence problem hit earlier: the fix-up size `n` comes from
the pre-pass, so the sizing pass and the emit pass necessarily agree — which is exactly
what `lb->sd` (a last-writer value mutated *during* the walk) could never guarantee.
