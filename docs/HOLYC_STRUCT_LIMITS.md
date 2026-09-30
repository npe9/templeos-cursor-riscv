# Structs by value: what this compiler does, and what it does not

Three limits found in one afternoon by translating NASA cFS, which is the first code in this tree
to move structs around by value at all. Each has a reproduction you can run; two are open.

Nothing in `Kernel/`, `Adam/` or `Compiler/` is affected today — every `*a = *b` in the tree is a
scalar copy, and the only by-value class returns are 8 bytes or smaller. These bite new code, and
they bit the cFS translation immediately.

## 1. Returning a class larger than 8 bytes — DIAGNOSED (was silent corruption)

There is no struct-return ABI. A `return` loads the value into `a0` with one `ld` and the caller
stores it with one `sd`. That is exactly right for a class of 8 bytes or fewer and silently
truncates everything larger.

    class S4  { U32 a; };              returns correctly
    class S8  { U32 a; U32 b; };       returns correctly
    class S12 { U32 a; U32 b; U32 c; } third field lost
    class S16 { I64 a; I64 b; };       second field lost; if it held a pointer, the first use
                                       faults -- observed as a load from 0x7a00000079, which is
                                       the two fields packed and used as an address

The RISC-V ABI wants `a0`+`a1` for up to 16 bytes and a hidden destination pointer beyond that.
Neither is implemented. `host/parser.c` has a `return_class` field on every function that is set
to NULL and never read, which is the shape of the missing feature.

**What was done:** the compiler now REFUSES such a return with a diagnostic naming the class and
its size, instead of miscompiling it. Nothing correct depended on the old behaviour, because the
old behaviour never produced a right answer. It does flag one piece of stock TempleOS --
`CDirEntry MGFind(...)` in `Adam/Opt/Utils/Merge.HC`, returning a ~100-byte class by value. That
file is in no host build (`MakeUtils.HC` includes it, and nothing in any `.PRJ` includes
`MakeUtils`), so it has been quietly uncompilable-correctly all along and now says so.

**Still open:** implementing the ABI. Until then, return a pointer or take a destination argument.
`CFE_Config_GetArrayValue` in `Kernel/Cfs/cfe/cfe_config.HC` is the one signature in the cFS
translation that deviates from NASA's for this reason, and it says so at the call site.

## 2. `*dst = *src` on a class larger than 8 bytes copies only 8 — OPEN

    class S16 { I64 a; I64 b; };
    U0 CopyDeref(S16 *dst, S16 *src) { *dst = *src; }   // copies a, leaves b untouched

Local-to-local `y = x` is fine: `ParseAssignment` emits `IC_BLOCK_COPY` for it. The test that
selects that path (`host/parser.c`, "Whole-struct assignment") requires the left side to be a
class INSTANCE -- `!pointed_to_type && !is_array` -- so a dereferenced pointer falls through to
the ordinary single-store path.

**A fix was attempted and reverted.** Extending the condition to "LHS ends in an `IC_DEREF`" also
caught `Entry->Datum.AsPointer = Ptr`, because a member store through a pointer also ends in a
deref and also leaves the ENCLOSING 16-byte class in `last_expr_class`. That block-copied sixteen
bytes where a single pointer store belonged and broke `CFE_Config_SetString`. Adding
`!cc->last_member` did not discriminate the two. The real fix needs the type of the LHS
EXPRESSION, not of whatever class was last seen; `last_expr_class` is not that.

**Workaround in use:** copy field by field. `CFE_Config_GetArrayValue` does, with a comment.

## 3. Indexed access to a local array reading zero in some frames — OPEN, not characterised

In one function -- `U32 a[3]; U32 ARR[3]; I64 b[3];` in `main`, three elements assigned per
source line -- `a` and `b` read back correctly and `ARR` read back as zero, with the addresses of
all three correct and 16 bytes apart. Reduced attempts did NOT reproduce it: two `U32[3]` locals
work, three arrays work, mixed sizes work, a trailing scalar works. So the trigger is something
narrower that this note does not yet name, and the reproduction above is the only one in hand.

It is recorded rather than chased because the cFS oracle did not need a stack array there: the C
declares `static const uint32 ARR[3]`, which is not on the stack, so the faithful HolyC is a
file-scope array and that is what the transcript uses.

**If you hit "an array reads back zero and its address looks right", start here.**

## 4. Indexing a parenthesised `&array[N]` expression is off by one — OPEN

    class Rec { I64 a; I64 b; };
    Rec tbl[10];
    #define SLICE (&tbl[4])

    tbl[6].a     -> 6      correct
    base = &tbl[4]; base[2].a -> 6      correct
    SLICE[2].a   -> 5      WRONG, and silently so

Taking the base into a local variable first is correct; indexing the parenthesised expression
directly is not. The mechanism is not characterised here — only the measurement, which is
reproducible with the snippet above.

This is how OSAL's `OS_OBJECT_TABLE_GET(OS_global_count_sem_table, token)` went wrong. That macro
expands to `&tbl[OS_ObjectIndexFromToken(&tok)]` where the table itself is
`(&OS_common_table[OS_COUNTSEM_BASE])`, so the record came back one slot low, its `name_entry`
was NULL, and `strncpy` faulted on it. Nothing announced the off-by-one; the fault was two steps
downstream.

**Every `OS_global_*_table` in this port is such a macro.** They are all used through a local
base pointer for this reason, and any new one must be too.
