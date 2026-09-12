# `I64 i=7;` crashes the guest HolyC REPL — a declaration *initializer* bug

Narrowed with the `bt` added in `backspace_and_bt_note.md`. Pre-existing; already gated
(it is why `kernel-win-interactive` fails its "Cd;FileMgr compound ExePutS pick" check).

## The symptom is narrower than it looked

Tested one statement per line against `make kernel-vt-holyc`:

| input | result |
|---|---|
| `3+4;` | ok, `ans=7` |
| `I64 i;` | **ok** |
| `I64 i=7;` | **CRASH** |
| `I64 i=7; i*6;` | CRASH |

So it is **not** a compound-statement bug — the compound case just happened to contain a
declaration. And it is **not** declarations in general: `I64 i;` parses and runs. It is
specifically a declaration **with an initializer**.

Two earlier theories, both wrong and both worth recording so they are not re-tried:

- *"ExePutS calls a NULL `machine_code`."* `LexStmt2Bin` can return NULL as well as the
  `INVALID_PTR` sentinel, and `ExePutS` only guarded the latter. Guarding NULL is
  correct defensively (kept), but it did **not** fix this — the crash survived it.
- *"Compound statements aren't supported."* Disproved by `I64 i=7;` crashing alone.

## Where it faults

```
mcause=2 (illegal instruction)  mepc=0x82625fd8  insn@mepc=0
```

`mepc` is in the **heap** (`0x82000400..0x86000000`), not the blob, and the instruction
word there is **zero** — freed, zeroed JIT code being executed. The stack scan's one
blob-range address resolves to **`PrsVarInit2`** (`Compiler/PrsVar.HC`).

That points at the nested call inside parsing, `PrsVar.HC:97`:

```c
r = Call(machine_code);
if (!(cc->flags & CCF_HAS_MISC_DATA) || pass == 1)
  Free(machine_code);
```

`PrsVarInit2` compiles the initializer expression to a block and **calls it while still
parsing the declaration** — a different path from `ExePutS`'s own
`Call(machine_code)`, which works fine (`3+4;`). `I64 i;` never reaches this code,
which is exactly why it survives.

## What has NOT been established

Whether the block is freed before the call, allocated in a region that is later reused,
or whether `Call` on this target needs I-cache maintenance that the RV port does not
do. The disassembly shows the *destination* is zeroed at the time of the jump; it does
not show who zeroed it.

The next cheap step is `md` at `mepc` from the crash prompt immediately after the fault
versus a fresh boot, to see whether the block was ever populated. That distinguishes
"freed and reused" from "never written / wrong address".

## Not fixed here, deliberately

`PrsVarInit2` and the `CCF_HAS_MISC_DATA` lifetime contract are shared compiler code —
`repl-cmp`, `phase3`, the win images and `exec-oracle` all run through it. A blind
change risks leaks or worse across every one of those. The diagnosis is the deliverable;
the fix wants someone who knows what invariant that flag is meant to carry.

## Workaround — split the declaration from the assignment

Confirmed working:

```
> I64 i;      ans=0
> i=7;        ans=7
> i*6;        ans=42
```

So variables, globals, assignment and later use are all **fine**. The damage is
confined to the inline-initializer form. That also sharpens the diagnosis: whatever
`PrsVarInit2` does to evaluate `= 7` during parsing is the only broken step — the
storage it allocates is sound, because `i` survives and reads back correctly
afterwards.

`U8 *s;` is likewise accepted, so this is not type-specific.
