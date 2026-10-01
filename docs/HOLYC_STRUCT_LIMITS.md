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

## 5. Compound assignment to a narrow struct field — FIXED

`x op= y` used to be emitted as a 64-bit read-modify-write whatever the destination's width.
On a 4-byte field that reads and writes 8 bytes, so the field NEXT to it takes part in the
arithmetic.

It hid well, because it only shows when the operation crosses bit 31:

| written | destination | neighbour |
|---|---|---|
| `a += 5` (a=10, b=20) | 15 | 20 — looks correct, the addend does not carry |
| `a *= 2` (a=10, b=20) | 20 | **40** — multiplied too |
| `a -= 3` (a=0, b=7) | -3 | **6** — the borrow came out of it |

The plain `=` path had computed the real store width for a long time (see the comment in
`ParseAssignment` about MMIO and the SiFive test finisher); every compound path passed
`RT_I64` instead. The fix gives them the same derivation, in `CompoundStoreType()`, and
narrows the load and the store in `EmitCompoundAssign` while leaving the arithmetic 64-bit.

Found by the cFS OSAL timer translation rather than by reasoning: `OS_TimeBase_CallbackThread`
does `timecb->wait_time -= tick_time` on an `int32` whose neighbour is `interval_time`, so a
ONE-SHOT timer — the one whose `interval_time` is 0 — had its interval borrowed to -1 and
fired on every later tick instead of once. The differential gate reported it as `t2` firing 3
times where NASA's own C fired it once.

Pinned by `tests/exec/cases/e_compound_assign_width.hc`, which returns 20070903 with the fix
and 40060803 without it.

## 6. Calling a function pointer held in a class member — FIXED

`x.fn(a)` and `p->fn(a)` did not work, and the two halves of the failure were not equally
visible:

| written | before |
|---|---|
| `m.fn(5);` | `error: Expected ';' or ','` |
| `r = m.fn(5);` | `error: Expected ';' or ','` |
| `if (m.fn(5)) ...` | `error: parse error` |
| `return m.fn(5);` | **compiled, and yielded the POINTER VALUE** |

Three parse errors cannot ship. The fourth can: measured at `0x8080007c`, the callee's address
inside the blob, where `6` was correct, with no diagnostic at all.

The cause was that a function-pointer member is indistinguishable from a plain `I64` member once
it is parsed — `raw_type` is `RT_I64` and `pointed_to_type` is 0 for both — so the postfix parser
took the load. `CMemberLst` now carries `is_func_ptr`, and the `.`/`->` cases call
`ParseFnPtrMemberCall` when the member holds a code address and a `(` follows.

The emitted shape is the one the `(*p)(args)` path already used, one IC shorter at the front.
`IC_CALL_INDIRECT` wants the code address on TOP of the eval stack, above the pushed arguments,
but the member access has already produced the pointer by the time the `(` is seen — it is
UNDER arguments that have not been parsed yet. So the pointer is parked in a frame slot, the
arguments are evaluated on top of it, and the pointer is reloaded last.

The frame slot cost a second fix. A local's offset is a `HOLY_LOCAL_MARKER` until the function's
frame size is known, and the two passes that resolve markers keyed on `IC_LEA`. An
`ICF_FRAME_SLOT` `IC_ASSIGN` is the other carrier, so the store landed at `s0 - 2^40` and the
first probe trapped on an illegal instruction after jumping to whatever the wild slot held.
`IcHoldsLocalMarker()` now names both.

Not supported, deliberately: `T (**fn)(...)` (a pointer to a function-pointer member) and arrays
of function-pointer members. Neither parses as a member declarator in the first place, so there
is no half-support to remove — an array of callbacks is written as an array of a one-member
wrapper class, which is what OSAL's event-handler table does.

Why it was worth a compiler change rather than a workaround: `Kernel/Cfs/osal` had been copying
the member to a local typed variable at four sites and saying so in a comment, and cFE's `fs`
module alone calls `Meta->OnEvent` in four places and `Meta->GetData` in one, with `es`, `tbl`
and `evs` using the same callback-table shape. A workaround repeated across every remaining
module is a deviation from NASA's source multiplied out.

Pinned by `tests/exec/cases/e_fnptr_member_call.hc`, which packs nine forms into one value.

## 7. Classes are fully packed — BY DESIGN, and it matters

There is no inter-member padding, no alignment and no tail padding:

```
class X { U8 a; U32 b; };     // sizeof 5, b at offset 1   (C: sizeof 8, b at 4)
class Y { U32 a; U8 b; };     // sizeof 5                  (C: sizeof 8)
```

This is authentic TempleOS and the kernel depends on it; it is not a defect. It becomes a
problem only when a class is supposed to mirror a C struct, which is the whole of the NASA cFS
translation. `tools/cfs/check_padding.py` is the gate: the C side is the real host compiler's
`offsetof`/`sizeof` from NASA's own headers, the HolyC side is a model that sums member sizes,
and the model's premise is itself pinned as `tests/exec/cases/e_class_packing.hc`.

Its first run found **17 of 53** translated classes wrong. Four were not padding at all but
members at the wrong WIDTH, which padding over would have buried:

| member | NASA | was |
|---|---|---|
| `OS_object_token_t.lock_mode` | `OS_lock_mode_t`, a C enum — 4 | `I64` — 8 |
| `OS_module_internal_record_t.module_type` | `OS_module_type_t`, a C enum — 4 | `I64` |
| `CFE_Config_ValueEntry.ActualType` | `CFE_ConfigType_t`, a C enum — 4 | `I64` |
| `OS_SockAddrData_t` (a union) | 32, rounded up from a 28-byte buffer | 28 |

A C enum whose enumerators fit in `int` is four bytes, so an enum-typed member is `I32`. The
token one cascaded: it made every `OS_object_token_t` 24 bytes against NASA's 20 and shifted
`OS_object_iter_t` and `OS_timecb_internal_record_t` with it.

The remaining thirteen are padding, written as `U8 _pad0[4];` members. `check_structs.py` skips
a member matching `_pad\d*` so the two gates do not fight: one owns field membership and order,
the other owns the bytes.

## 8. An array member cannot appear in an aggregate initializer — OPEN

```
class E { I32 Number; U8 _pad0[4]; U8 *Name; };
E T[1] = {{-15, 0, "abc"}};        // parse error
```

With `U32 _pad0;` instead of the array, the same initializer compiles and the values land
correctly. So it is the array MEMBER in the initializer that does not parse, not the count of
elements or the zero.

Found while padding `OS_ErrorTable_Entry` for limit #7: OSAL's error-name table is 42 rows of
positional initializers, and NASA's C skips the padding silently because it uses the field
order, not designated initializers. The translation has to write the `0`. The padding member is
therefore a scalar at that one site, with a comment saying why it differs from the `U8 _pad0[N]`
used everywhere else.

The failure was loud but only at the gate, not at the compiler: the first attempt kept
`U8 _pad0[4]` and left the 42 rows alone, so the string pointer landed in the padding and
`OS_StatusToString` returned `OS_UNKNOWN(-15)` for every code in the table. Four transcript
lines, and the parse of the initializer had silently taken the second element as `_pad0`.
