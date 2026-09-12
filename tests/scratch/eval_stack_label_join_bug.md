# ROOT CAUSE: `sp` desynchronises at label joins, clobbering saved `ra`

This is the defect behind `I64 i=7;` / `for(U32 i=0;…)` crashing the guest HolyC REPL,
and behind `Print("%d", x)` printing a fixed garbage value. Found by watchpoint, not
inference. **Not fixed** — the fix breaks multi-pass size convergence; see below.

## The defect

`host/compiler.c`, `case IC_LABEL`:

```c
case IC_LABEL:
  { CLabel *lb = (CLabel*)ic->ic_data; if (lb->sd_set) stack_depth_pass = lb->sd; O1SlotClear(); }
```

and at every branch:

```c
lb->sd = stack_depth_pass; lb->sd_set = true;   // "the taken path reaches lb at this depth"
```

The eval stack **is** `sp` (`addi sp,sp,-8` / `sd a0,0(sp)` per temporary). A branch
records the depth it will arrive with; the label then *adopts* that depth in the
MODEL — and emits **nothing** to move the real `sp`. When the fall-through path
reaches the label at a different depth, the model resyncs and the hardware `sp` does
not. From that point the two disagree.

The frame saves the return address at the bottom:

```
addi sp,sp,-192
sd   ra,0(sp)        <- ra at sp+0, i.e. AT the frame base
```

so once `sp` has drifted one slot high, the next push writes over the saved `ra`. The
function returns into whatever that value was — usually a heap pointer, hence
`mcause=2 illegal instruction, insn@mepc=0` at a heap address.

**Scale:** instrumenting the emitter to report label joins whose fall-through depth
differs from `lb->sd` reports **1038 of them in the win Compiler unit alone**.

## The evidence

Software watchpoint (literal address — see the methodology note below) on
`PrsVarInit`'s saved `ra`:

```
PrsVarInit frame: sp=0x87eff2e8  saved_ra=0x80a4970c
Old value = 0x80a4970c  ->  New value = 24
WROTE at PrsVarInit+0x534:
   li   a0,24
   addi sp,sp,-8      <- eval-stack push
   sd   a0,0(sp)      <- lands on 0x87eff2e8 == the frame base == saved ra
```

For that store to hit the frame base, `sp` must have been `base+8` before the `addi` —
i.e. one pop too many had already happened.

Corroborating, by scratch-RAM markers read with `md` at the `crash>` prompt:
`PrsVarInit` runs its whole body (`MemCpy(dst,&r,8)` with `dst=0x82625fd0`, `r=7`, all
markers set through its final `*_dst=dst`) and then dies in its **epilogue** — the
`ld ra,0(sp)` reloads the clobbered value. `PrsVarInit2` is entered with a correct
`ra=0x80a4998c` and never reaches its epilogue.

## Why the obvious fix does not land yet

Emit the missing reconciliation at `IC_LABEL`:

```c
if (stack_depth_pass != lb->sd)
  EmitAddImm(..., RV_SP, RV_SP, (stack_depth_pass - lb->sd) * 8);  // stack grows down
stack_depth_pass = lb->sd;
```

This is correct in principle and does emit, but the multi-pass sizing loop stops
converging:

```
HOLYC AOT: emit size 1788784 != sized 1793344 (pass 2) — label/call mismatch
```

`lb->sd` / `lb->sd_set` persist across passes, so the sizing pass and the emit pass
compute different reconciliations. Clearing `sd_set` for every label/branch IC at the
top of each pass did **not** change those numbers, so the divergence is elsewhere in
the pass machinery — that is the piece still to solve.

Belt-and-braces alternative, also not straightforward: move `ra`/`s0` off `sp+0` to the
top of the frame (standard RISC-V ABI puts `ra` at `s0-8`). Here locals are already
addressed as negative offsets from `s0`, so the whole frame layout would have to shift.

## Methodology note — the mistake that cost the most

`watch *(unsigned long*)$sp` in gdb watches an **expression** containing `$sp`. When
`addi sp,sp,-8` moves `sp`, the expression starts reading a different address and gdb
reports it as a value change. That produced a confident, wrong "found it" that had to be
retracted. Watching a **literal address** (`watch *(unsigned long*)0x87eff2e8`, with
`set can-use-hw-watchpoints 0` so it stops synchronously in batch mode) is what actually
finds stack corruption.

Two other traps from the same hunt: `Print` from inside the compiler is invisible
(mirrored into the DolDoc, and the crash beats the next present — use scratch RAM plus
`md`), and compiler-unit symbol resolution needs the linker's `raw_n` rule
(`align8(file_size - 16 - n_imports*32)`), not the raw file size — using the latter
mislabelled every address by 0x4d0.
