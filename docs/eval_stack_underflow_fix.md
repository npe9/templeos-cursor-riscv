# Eval-stack underflow: `ret` into `a0` (root cause + fix)

## Symptom
REPL input that *declares* a variable (`I64 i=7;`, `for(U32 i=0;i<10;i++) ...`) crashed with
`mcause=2 illegal instruction`, `insn@mepc=0`. Plain expressions (`2+3*4;`) were fine.

## Proof of mechanism
gdb breakpoint on the faulting address showed `pc == ra == a0 == 0x82625fd8`, `sp` exactly at
`PrsVarInit`'s entry sp. `pc == ra` with `ra` unchanged is the signature of `ret`
(`jalr x0, ra, 0`) — not a call. So `PrsVarInit` returned to whatever `a0` held: an eval-stack
push had overwritten its own saved `ra` at the frame base.

Call chain from the stack (resolved through the per-unit maps at their `align8(raw_n)` bases):
`PrsStmt+0x3ec8` → `PrsGlblVarLst+0x33e0` → `PrsGlblInit+0x260` → `PrsVarInit`.

## Two independent defects

### 1. `IC_DEREF` leaked an eval slot (parser.c)
Every binary producer pushes its result. `IC_DEREF` loads through `a0` and pushes the loaded
value *without* popping the address slot underneath. `DerefDroppingAddressSlot()` exists to emit
the compensating `IC_EVAL_DROP`, but its producer whitelist named only
`IC_ADD / IC_PUSH_ARG / IC_IMM_I64 / IC_DEREF`. **`IC_SUB` was missing**, so `(p - 128)->m`
leaked one slot each time. Visible in the objdump of `PrsVarInit`:

```
80a46ea0: sub  a0,t0,t1     ; computed address
80a46ea4: addi sp,sp,-8     ; push ADDRESS
80a46ea8: sd   a0,0(sp)
80a46eac: ld   a0,0(a0)     ; deref
80a46eb0: addi sp,sp,-8     ; push VALUE — address slot never popped
```

Fixed by extending the list to every arithmetic/bitwise producer (`SUB MUL DIV MOD AND OR XOR
SHL SHR USHR`). Still incomplete by design — see "Remaining" below.

### 2. `IC_END_EXP` trusted a static depth counter (compiler.c)
`IC_END_EXP` emitted `addi sp, sp, stack_depth*8`. `stack_depth` is a *static* count that agrees
with runtime only along a single path. A branch that skips leaked pushes reaches the join with a
different real depth, so the pop ran **past the frame base**; the next push then landed on the
saved `ra`. Observed concretely in `PrsVarInit`:

```
80a46fe4: addi sp,sp,-8    ; push 1 slot
80a46fe8: sd   a0,0(sp)
80a46fec: ld   a0,0(sp)
80a46ff0: addi sp,sp,24    ; pop THREE
```

Fixed by restoring `sp` from the frame pointer — `addi sp, s0, -(frame_size + flags*8)` — which
is exact and path-insensitive. `IC_LEAVE` already used this form.

Guards that turned out to be necessary:
- `cur_frame = -1` for frameless JIT fragments (`LexExpression2Bin` emits no `IC_ENTER`; `s0`
  there belongs to the caller), and reset at `IC_LEAVE`.
- **`flags_depth`**: `IC_PUSHFD` parks `mstatus` on `sp` and `IC_POPFD` pops it, neither tracked
  in `stack_depth`, and the pair legitimately spans statement boundaries. Blindly resetting `sp`
  to the frame base discarded that slot; `Spawn` then did `ld t0,0(sp); csrw mstatus,t0` with the
  wrong word and faulted at `Spawn+0xa84`. The restore subtracts the parked slots.
- Applied only when `stack_depth > 0`. Over-popping is fatal (clobbers saved `ra`);
  under-popping is harmless because `IC_LEAVE` already restores `sp` from `s0`.

## Remaining
`DerefDroppingAddressSlot`'s whitelist is still a hand-list. `IcNetStack()` (compiler.c) already
classifies producers exhaustively; the list still misses the comparisons, `IC_FADD…`, `IC_PP_`,
`IC_CALL*`, non-`FRAME_SLOT` `IC_ASSIGN`, `IC_STR_CONST`, `IC_MOV`, `IC_FN_ADDR`, `IC_PC`,
`IC_ADDR` — so `(*fp)()->m`, `arr[i++]->m`, `(a<b?p:q)->m` still leak a slot. With the END_EXP
fix those leaks are no longer *fatal* (sp is reset from `s0` at each statement), so this is
cleanup rather than a blocker.

## `for(U32 i=0; ...)` is not a codegen bug
It reports `Missing ';' at ")"`. That is faithful stock behaviour: `PrsFor` parses the init with a
bare `PrsStmt(cc,try_cnt)`, and `PrsStmt`'s declaration path falls through to its own `while(TRUE)`
and parses the *next* statement — so the init swallows the condition and PrsFor's own `;` check
fires. Verified by tagging each `LexExcept(cc,"Missing ';' at")` site: the guest raised the tag
belonging to `PrsFor`. Stock TempleOS sources always declare the loop variable first.

Note a host/guest divergence: our host compiler *accepts* the C99 form.

## Gate status after the fix
PASS: `compliance`, `exec-oracle` (84/84), `kernel-vt-smoke`, `kernel-boot-smoke`,
`kernel-plat-matrix` (11/11), `repl-holyc-regression`, `mux-smoke`, idle boot clean.

Still red, and red before this work too: `kernel-win-interactive`, `kernel-win-serial-smoke`,
`kernel-win-smoke` (hash mismatch).

## Known-remaining, separate from this bug
- Implicit-Print `"fmt",args;` in a loop prints the last iteration's value
  (`for(j=0;j<3;j++) "A%d\n",j;` → `A2 A2 A2`) — the known varargs-ABI defect.
- A null-pointer store fault in `SPutChar+0x2c0` / `MemCpy+0x8` (`sb` through a zero base,
  `mtval=0`) that turns up after a few REPL lines. Separate defect, not eval-stack related.
- A `for` statement's `ans=` is garbage (the statement has no value); `ans` after the loop body's
  variable is correct (`for(j=0;j<3;j++) j;` then `j;` → 3).

---

# Follow-ups fixed in the same session

## 1. `for(U32 i=0; …)` now works (`CMPF_ONE_STMT`)
Stock `PrsFor` parses the init with a bare `PrsStmt(cc,try_cnt)`, and `PrsStmt`'s declaration path
falls through to its own `while(TRUE)` and parses the *next* statement — so the init swallowed the
loop condition and `PrsFor`'s own `;` check fired. That is stock TempleOS behaviour (confirmed
against `git show HEAD:Compiler/PrsStmt.HC`, and localized at runtime by temporarily tagging each
`LexExcept(cc,"Missing ';' at")` site — the guest raised `PrsFor`'s tag).

Our *host* compiler already accepted the C99 form, so host and guest disagreed. Closed the gap in
favour of the host: new `CMPF_ONE_STMT` (CompilerA.HH) makes `PrsStmt` return after a declaration,
and `PrsFor` passes it. Verified in the guest: `for(U32 k=0;k<5;k++) k;` then `k;` → 5.

## 2. Multi-dimensional array MEMBERS (`ndims` on `CMemberLst`)
`CMemberLst` had `is_array`/`elem_size` but no `ndims`/`dim_stride`, which a local `Symbol` and a
`CHashGlblVar` both carry. So a partial subscript of a member 2-D array stepped one *element* and
then dereferenced:

| expression | before | after |
|---|---|---|
| `g_flat[3]` (plain global `U8[4][96]`) | row address ✓ | ✓ |
| `g_r.rows[2]` (member `U8[4][96]`) | **0** (loaded a byte) | row address ✓ |

Fixed by recording dims on the member at class-parse time, using `dim_stride[level]` for the
subscript stride, and treating a bare partial subscript as a row ADDRESS (`CCF_RAX`). A variable
index needed one more thing: `cc->last_member` is re-bound while parsing the index expression, so
it is now snapshotted next to `saved_symbol`/`saved_global`.

Regression test: `tests/exec/cases/e_arr2d_member_row.hc` → `0x3f` (in the oracle manifest).

## 3. The idle crash: a ~109-bytes-per-`Print` heap leak
`RVWinMgr.HC:1229` does `StrPrint(rv_winmgr.wallpaper_tasks[n], …)` where the member is
`U8 wallpaper_tasks[4][96]`. Bug 2 made that argument **NULL**, so it became `StrPrint(NULL,…)` →
`StrPrintJoin(dst=NULL,…)` → `MAlloc(STR_LEN)` for a buffer nobody ever freed.

Measured with gdb: `MAlloc` climbed past 24,000 calls while `Free` stayed frozen at 1,941, and
`heap_next` advanced linearly. The 64 MB arena (`0x82000400` → framebuffer at `0x86100000`) drained
in ~60–90 s, `MAlloc` returned NULL, and `SPutChar` used it unchecked → `MemCpy(NULL,…)` store
fault. After the fix `heap_next` is flat across 42,000 `Print` calls and a 170 s idle boot is clean.

Also hardened `Kernel/KBootRV.HC`'s stand-in allocator while in there (necessary, not sufficient —
it did not stop the leak on its own):
- **split** an oversized free chunk instead of handing the whole thing to a small request;
- `Free` now decrements `the_heap->used_u8s`, which previously only ever grew.

## 4. HolyC varargs from the REPL (`Print("%d", x)` printed an address)
The guest compiles a variadic call the TempleOS way: push the fixed args, then `argc`, then the
vararg **values** (stack-aliased `argv`). The host-compiled kernel `Print` wants the RISC-V ABI
`a0=fmt, a1=argc, a2=argv` where **argv is a POINTER** to the first vararg slot. Measured at the
kernel `Print` entry from a REPL call: `a1=1` (correct) but `a2=0x2a` — the value 42 itself. So
`StrPrintJoin` did `ld` from address 42 and took a load access fault (`mtval=0x2a`).

`IC_CALL_IMPORT` already handled this. ExePub funs (`Print`, `Cd`, `FileMgr`) arrive as `IC_CALL`
/ `IC_CALL_EXTERN`, which share `RVEmitCallArgRemat` — and that helper had no notion of varargs.
Two things were needed:

1. **Identifying the callee as variadic.** `IC_CALL`'s `ic_data` is `tmpf->exe_addr`, an *address*,
   not a `CHashFun` — passing it as one was garbage. `IC_CALL_START` carries `tmpf` but OptPass789A
   rewrites that field into a register mask. So `PrsFunCall` now stamps the argc push with a new
   `ICF_RV_VA_ARGC` (KernelA.HH, bit 33 — bits 21-26 are the float sub-fields), and the backend
   pre-scans for it: `va_argv_slot = argc_slot + 1`.
2. **Pointing argv at the right slot.** The FP-relative formula the IMPORT path uses needs the real
   frame size, which is 0 for a JIT'd REPL snippet — a scratch-RAM probe caught it emitting `FP-24`
   where the slot was `FP-144`. `sp` is exact at that point (the arg block is live and nothing in
   the remat sequence moves it), so argv is now `sp + arg_slot*8`.

Verified in the REPL: `Print("EX %d\n",42)` → `EX 42`; `I64 q=7; Print("VA %d\n",q)` → `VA 7`;
`Print("TWO %d %d\n",7,9)` → `TWO 7 9`; `for(U32 i=0;i<4;i++) "H %d\n",i;` → `H 0 H 1 H 2 H 3`.

## Gate status
PASS: `compliance`, `exec-oracle` (85/85), `kernel-vt-smoke`, `kernel-boot-smoke`,
`kernel-plat-matrix`, `repl-holyc-regression`, `mux-smoke`, 170 s idle boot clean.
Still red and red before this work: `kernel-win-interactive`, `kernel-win-serial-smoke`,
`kernel-win-smoke`.

## Open, not diagnosed
Function-pointer calls from the REPL (`U0 (*fp)(); fp=<addr>; (*fp)();`) fault with a *load*
access fault before jumping, identically for valid and invalid targets — the funptr global itself
is wrong. See `docs/fault_examples.md`.
