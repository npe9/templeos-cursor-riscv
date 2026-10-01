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

## 2. Assigning a class larger than 8 bytes copies only 8 when the LEFT side is not an instance — FIXED for a member LHS

    class S16 { I64 a; I64 b; };
    U0 CopyDeref(S16 *dst, S16 *src) { *dst = *src; }   // copies a, leaves b untouched

WHICH SIDE IS BROKEN, measured rather than inferred. With a 28-byte class and the same two
objects, the two directions are not alike:

    class RV   { U32 sig; I16 leap; U16 sel; U32 a; U32 b; U32 c; U32 d; U32 e; };
    class Area { U32 head; RV vars; U32 tail; };

    local = area.vars;      // LHS is a class INSTANCE -- all 28 bytes copied, correct
    area.vars = local;      // LHS is a MEMBER designator -- sig and leap arrive, `e` is 0

So it is not "a deref on the right" and not the class size on its own: it is whether the LEFT
side is a class instance. `tail` is untouched either way, so the bad case is a SHORT copy and not
an overrun -- which is why it reads as a plausible value rather than as a crash.

`ParseAssignment` emits `IC_BLOCK_COPY` only when the test at "Whole-struct assignment"
(`host/parser.c`) holds, and that test requires the left side to be a class INSTANCE --
`!pointed_to_type && !is_array` -- so a member or a dereferenced pointer falls through to the
ordinary single-store path and stores eight bytes.

**A fix was attempted and reverted** before this one. Extending the condition to "LHS ends in an
`IC_DEREF`" also caught `Entry->Datum.AsPointer = Ptr`, because a member store through a pointer
also ends in a deref and also leaves the ENCLOSING 16-byte class in `last_expr_class`. That
block-copied sixteen bytes where a single pointer store belonged and broke
`CFE_Config_SetString`.

**FIXED for a member LHS**, and the discriminator was already in the tree: `CMemberLst` carries
the member's OWN type, and for a scalar or a pointer member `member_class` is NULL. Instrumenting
the decision point across the five shapes that reach it settles it without guesswork —

| statement | `last_member` | `member_class` | `pointed_to_type` | wanted |
|---|---|---|---|---|
| `area.vars = local` | `vars`/28 | **`RV`** | 0 | copy 28 |
| `area.vars.sig = 5` | `sig`/4 | — | 0 | one store |
| `ent.Datum.AsPointer = &t` | `AsPointer`/8 | — | **4** | one store |
| `ent.Datum.AsInt = 7` | `AsInt`/8 | — | 0 | one store |
| `plain = 3` | — | — | — | one store |

`member_class != NULL` is the whole discrimination; the size, pointer, array and function-pointer
checks are belt and braces, and requiring it to EQUAL the LHS expression's class is what makes a
stale `last_member` from an earlier statement harmless.

`tests/exec/cases/e_struct_assign_member.hc` pins all five shapes, with the neighbours on both
sides of the copied member read back so a block copy of the wrong SIZE is caught too. Two
controls: removing the member branch reproduces the short copy, and dropping the `member_class`
guard fails both the case and the cfs gate -- the latter being exactly what the reverted attempt
broke.

**STILL OPEN: a bare `*dst = *src`** on a pointer-to-class. There is no member there, and the
pointee's class is not in hand at the decision point. No cFS source written so far does it:
across TIME, EVS, fs, ta, msg and config, every whole-struct assignment goes through an instance
or a member.

**No workaround needed any more** for the member form. `CFE_Config_GetArrayValue` still copies
field by field with a comment, which is harmless. The site that prompted this --
`CFE_TIME_ResetDataPtr->TimeResetVars = LocalResetVars` in `CFE_TIME_UpdateResetVars`, a 32-byte
assignment whose sibling four functions earlier goes the other way and always worked -- now
compiles to a 32-byte copy.

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
directly is not.

**The mechanism is now known, and half of it is fixed.** Parenthesising a base threw away the
container symbol, and with it the ELEMENT SIZE, so `PtrElemInfo` fell back to 8 bytes. On a
16-byte record that is half a step, which is exactly the "one slot low" above. The same fallback
made a much simpler case silently wrong:

    U8 m[16];
    (m)[1]        read EIGHT bytes from m+8, not one byte from m+1
    (m)[1] = x    stored one byte AT m+8 — out of bounds on any U8 array shorter than 16

That half is FIXED: `cc->expr_elem_size` carries the element size across the parentheses, and
`tests/exec/cases/e_paren_base_subscript.hc` pins it for `U8`, `U16`, a local pointer, and both
the read and the write. It matters beyond the snippet, because a function-like macro that
indexes its argument produces exactly that shape — OSAL's

    #define OS_CPUSET_SET(cpu, cpusetptr) ... (cpusetptr)->affinity_mask[(cpu) / 8] |= ...

is one `->member` away from it, and a hand-written `(p)[(cpu)/8]` form is not. (NASA's own macro
goes through `->affinity_mask`, which was never affected; this was found by probing it, not by
it failing.)

The CLASS half — `(&tbl[4])[2]` where the element is a 16-byte record — is still wrong, still
one slot low, and the obvious fix is not the fix. Setting the element size at the `&` site from
`cc->last_expr_class` looks right and is not: after `h.arr[1]` where `arr` is `CBig *arr[4]`,
`last_expr_class` is `CBig` while the address points at a POINTER, and taking the class size
there made `&h.arr[1] - &h.arr[0]` scale by 64 and answer 0.
`tests/exec/cases/e_member_ptr_array.hc` returned 4 instead of 0x3c and said so. The `&` site
cannot tell the two cases apart; whatever closes this has to carry the size down from the
subscript rather than reconstruct it afterwards. The workaround below stands until then.

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

## 9. `sizeof` of a dereference or a member reached through a pointer — OPEN

```
sizeof(*p)                  parse error
sizeof(Hdr->Description)    parse error
sizeof(h.Description)       works
sizeof(CFE_FS_Header_t)     works
```

So it is the `*` and the `->`, not `sizeof` itself. The dot form on a value is fine.

This one is loud when it is at the top level of a file and silent-ish when it is inside an
include: the error reported is the generic `parse error` at `0:1` of the OUTERMOST file, with no
line number anywhere near the construct. It cost a bisect twice — once on
`StrNCpy(Hdr->Description, ..., sizeof(Hdr->Description) - 1)` in `cfe_fs_api.HC`, and again on
`MemSet(cpusetptr->affinity_mask, 0, sizeof(cpusetptr->affinity_mask))` in OSAL's cpu-set
helpers, where the whole of `cfe_ta_task.HC` appeared to be unparseable because one line four
includes deeper was.

cFS writes both forms constantly, so the translation names the type or the constant instead and
says so at each site. `check_padding.py` is what keeps the named constant and the real size the
same thing.

## 10. A call to a variadic function the compiler has not seen yet — OPEN, and SILENT

A HolyC variadic function receives an implicit `(argc, argv)` pair, and the CALL SITE is what
builds it. So the call site has to know the callee is variadic — and a call to a function that is
defined further down the file, with no prototype above, does not.

```
U0 Later(U16 a, U8 *f, ...);          // with this line:    argc=1, argv valid
U0 Caller()  { Later(1, "f %s", x); }
U0 Later(U16 a, U8 *f, ...) { ... }   // without it:         argc=9, argv stale
```

Measured, with the prototype removed from a four-argument call: `argc` came out as the last
ARGUMENT's value and `argv` as a pointer left over from an earlier frame. Nothing is reported at
compile time, and nothing is reported at run time either unless the callee actually reads `argv`
— so a format string with no conversions passes, and the same call with a `%d` in it reads an
arbitrary address. In `cfe_evs_utils.HC` it reached `StrPrintNV` as `nargs=1, args=NULL` and
faulted on a load from address 0, which is the lucky outcome.

C has the same requirement, so a prototype is 1:1 with NASA's header either way. What is
different is that C's compiler says `implicit declaration of function`. Two distinct shapes to
watch for, and both were present in this tree:

- `EVS_SendEvent`, defined at the bottom of `cfe_evs_utils.HC` and called from four places above
  it. Fixed by adding NASA's own prototype.
- `CFE_EVS_SendEvent`, declared NON-VARIADIC in `cfe_ta_task.HC` (a three-parameter stub
  declaration, from when EVS was not translated) and defined VARIADIC in `cfe_evs.HC`, which is
  included later. Every TA event call went through the non-variadic declaration. This one no
  checker could see: `check_signatures.py` compares the DEFINITION's arity against NASA's, and
  the definition was right.

## 11. `uv /= base` emits a SIGNED divide for an unsigned left operand — OPEN

```
U64 uv = 0xFEDCBA9876543210;
U64 base = 10;
uv % base      ->  unsigned, correct
uv / base      ->  unsigned, correct
uv /= base     ->  SIGNED
```

The binary form and the compound form of the same operation on the same two variables disagree:
the compound assignment does not consult the left operand's type for signedness. `%` is
unaffected, in either form.

Found in `StrPrintNV`'s digit loop, where `dig[ndig++] = hexd[uv % base]` was unsigned and
`uv /= base` on the next line was not. `%llu` of a value above 2^63 printed 17 digits where C
printed 20 — and the first digit was right, because the first `%` happens before the first
divide. Nothing below 2^63 is affected, which is every value cFS prints, so this had no visible
effect and would not have had one for a long time.

Worked around by writing `uv = uv / base`. `tests/exec/cases/e_strprint_hex.hc` pins the output,
and its `%llu` line is the case that fails if the compound form comes back.

## 12. A `static` local is a GLOBAL under the bare name, so two functions collide — FIXED

```
U0 A() { static I64 n; n++;     ... }
U0 B() { static I64 n; n += 10; ... }
```

Two functions, each with its own `static I64 n`. Running this faults:

```
TRAP mcause=0x5 (load-fault) mepc=blob+0x7bc mtval=0x0
...
    li   a0,0
    ld   a0,0(a0)
```

One of the two resolves to **address 0**. `parser.c` says what it does at the site —

```c
// For static variables, treat as globals scoped to function
if (is_static) {
  bool result = ParseGlobalVariable(cc, type, var_name);
```

— and the comment claims the scoping that the call does not do: the name goes into the global
hash table bare, so the second declaration lands on the first's entry and re-aims it. The same
file already warns about exactly this hazard for ordinary globals ("A global redefined with a
different type is almost always a COLLISION"); a function-static is that collision with the same
type, which is the case that stays silent.

Found translating cFS's dispatchers. `cfe_ta_dispatch.c` and `cfe_evs_dispatch.c` both cache
their message ids in function-local statics, and **both call them `CMD_MID` and
`SEND_HK_MID`** — every cFE module's dispatcher does. With both translated, `CFE_TA_TaskPipe`
faulted; the ta copy had been clobbered by the evs one four files later.

**FIXED**, and the EVS dispatcher now carries NASA's own names again.

The scoping is made real in two halves, because `ParseFunction` has thirteen exits and HolyC has
no nested functions:

- **At the declaration**, whatever the bare name means is UNLINKED from the table and remembered,
  so `ParseGlobalVariable` always builds a FRESH object and never re-aims an existing one. That
  is also what stopped a static local hijacking a real file-scope global of the same name — the
  further-out half of the same bug, which used to orphan the *global's* address.
- **When the next function definition starts**, the previous function's statics are RETIRED: each
  is re-added under a unique key, so it stays in the table and therefore stays resolvable by
  address, laid out and initialised, while the bare name goes back to whatever it displaced.

`tests/exec/cases/e_static_local_scope.hc` pins it: the same static name in three functions, two
statics each, one of them through the `static I64 a, b;` comma path, one with an initialiser that
must run once, and a file-scope `n`/`m` pair that must still read 500/600 afterwards. Its expected
value is computed from the arithmetic, not read off a run. Commenting out the retire call makes
the case crash.

One thing it does NOT do: retire the LAST function's statics, because nothing follows them. Their
bare names stay visible to file-scope code after that function — wrong, harmless, and written
down here rather than left to be rediscovered.


## 13. Re-including an already-included guarded file can lose the rest of the including file — OPEN

```
// m.hc
#include "u.HC"        // first time: read normally
#include "p.HC"        // p.HC also does #include "u.HC"
```

When `u.HC`'s guard is already satisfied, the re-include from inside `p.HC` is skipped — and
**everything after that line in `p.HC` is skipped with it.** No diagnostic, exit status 0, and the
functions simply are not in the binary.

Measured on the real thing, not on a model: `cfe_time_api.HC` included `cfe_time_utils.HC`, which
the driver had already included, and all forty-six of the API's functions vanished.
`tools/blob_imports.py` was what noticed — `CFE_TIME_Add` appeared as an UNRESOLVED IMPORT in a
unit that visibly defines it, which is not a state that should exist. `HOLYC_MAP` then confirmed
the file contributed nothing at all, and planting three marker functions at the top, middle and
end of it showed none of them arriving.

**Bisected to four comment lines.** Cutting `cfe_time_utils.HC` at balanced-brace boundaries and
re-testing each cut narrows it to these:

```
//   CFE_TIME_SetSource   #if CFE_PLATFORM_TIME_CFG_SOURCE == true   (0 here)
//   CFE_TIME_SetSignal   #if CFE_PLATFORM_TIME_CFG_SIGNAL == true   (0 here)
//   CFE_TIME_SetDelay    #if CFE_PLATFORM_TIME_CFG_CLIENT == true   (0 here)
// All three are whole-function #if bodies in cfe_time_utils.c, so ...
```

Rewording all four so the text does not contain `#if` fixes it, deterministically and
repeatably: with them, the API contributes 0 functions; without them, 46. That makes the
conditional-skip scanner counting directives inside COMMENTS the obvious suspect — the four
unmatched `#if`s would make the skip run past the file's own `#endif` and keep going.

**NOT YET CHARACTERISED, and that is said rather than papered over.** A synthetic file with one,
and then with four, `#if`-mentioning comments does NOT reproduce it, so the obvious mechanism is
not the whole story — position in the file, interaction with the nested `#ifndef CFE_PSP_SUCCESS`,
or file length may all matter. Anyone fixing this should start from
`cfe_time_utils.HC` at commit time and the bisect harness in the session log rather than from a
small case, because the small case is what misled this diagnosis for an hour.

**Workaround in use, and it is the better style anyway:** a translated unit does not include its
siblings. `cfe_time_api.HC` states its required include order in its header comment, as every
other file in `Kernel/Cfs` does, and the driver provides it. The comments are also reworded, so
the file is not relying on that alone.

**The real cost is the SILENCE.** A file that contributes nothing, with a clean exit, is the worst
shape a compiler bug can take. What caught it was an invariant, not a test: the import trailer
must not list a name the unit defines. That check already existed for a different reason --
`docs/CFS_PLAN.md` has the measurement where it caught a silent bind to the host C runtime.

## 14. A statement starting with an ALL-UPPER-CASE variable name was discarded — FIXED

```
I64 Y = 10;
Y++;        //  discarded.  Y stays 10.
Y += 5;     //  discarded.
Y = Y + 1;  //  works.
```

HolyC lets an x86 instruction be written bare in source (`MOV U64 [RSI],R13`), and `parser.c`
recognised one at statement start by its SHAPE: an all-upper-case name whose next token is not
one of `( = ; . -> , )`. Anything else was taken for an opcode with an operand and **the whole
line was skipped**, with a note and a clean exit. `++` is not in that list, so `Y++;` was an
instruction as far as the parser was concerned.

Lower-case and mixed-case names were never affected, which is why this survived: almost nothing
in the kernel names a variable in capitals, and neither does cFS. The one that did was mine.

**What found it was not a test.** `CFE_TIME_UnixToCalendar` walks a year at a time from the UNIX
epoch with `Y++`. With the increment gone every year was 365 days, so the walk from 1970 ended
where it started and `CFE_TIME_Print` rendered `1970-003` where glibc's `strftime` renders
`1980-001`. The differential transcript compared those two strings. A plausible date, not a
crash, in the one function whose output is a packet payload.

**And it took an hour longer than it should have**, because every small reproduction disagreed
with the next: varying the loop form, the initial value, the number of locals and pre- versus
post-increment each produced a passing case, and two near-identical functions differing only in a
variable's name behaved differently. The step that settled it was DISASSEMBLING the four-line
case and counting `addi rd,rs,1` instructions -- one emitted where two were written -- and then
sweeping all twenty-six letters, which showed twenty-five failing and lower case untouched. Read
the emitted code earlier than feels necessary; a shape this odd is a parser decision, not an
arithmetic one.

**The fix has two halves:**

- every modifying operator that can follow a name is excluded: `++ -- += -= *= /= &= |= ^= <<= >>= %=`
- **a name the compiler already knows as a local is not an instruction** -- the general guard,
  and the reason a future operator added to the lexer cannot reopen this

A first version also tested `cc->lex.hash_entry->type & HTT_GLBL_VAR`. Dropping that clause
changes nothing any gate can see -- all five probes, the exec case, the refusal and
`newline-semi-smoke` are identical with and without it -- because a global never reaches the
branch in the first place. It is not in the fix. An unwitnessed clause in a parser is a
liability, not insurance, which is the same rule [[hash-gates-need-properties]] states for gates.

**Each half has a gate that fails when only that half is removed, and finding them took a
second look.** The first version of the oracle was `Y++` and its eleven siblings, and that case
passes with EITHER half present -- so it witnessed the conjunction and nothing else. Someone
could delete the symbol check later and the gate would stay green. Two cases separate them:

- `tests/exec/cases/e_upper_name_stmt.hc` declares an all-caps ARRAY and assigns through it,
  `ARR[0] = 7;`. `[` is not an operator, so it is in neither list -- only the symbol-table guard
  keeps those lines. Remove that guard alone and this case fails.
- `tests/holyc/refused/upper_name_undeclared.hc` is a bare `FOO++;` on a name nothing declared,
  and the compiler must REFUSE it. The symbol check cannot fire on an undeclared name, so only
  the operator list makes the compiler look at the line at all; remove the list alone and the
  file compiles clean with the typo discarded. Checked by `make struct-refusals-check`.

An exec oracle can only witness the symbol guard and a refusal can only witness the operator
list, because the two halves differ in exactly that: whether the name is declared. The exec case
also includes a real `CLD` statement, so a "fix" that disabled the feature would be caught.

**IT IS LOCALS ONLY, AND THAT WAS WORTH MEASURING RATHER THAN ASSUMING.** Five one-function
probes, each the smallest program that can show one shape, run against the PRE-FIX compiler:

| probe | shape | pre-fix result |
|---|---|---|
| `p_loc_inc` | `I64 Y = 10; Y++;` | **10** — broken |
| `p_loc_arr` | `I64 ARR[3]; ARR[0] = 7;` | **0x808000e8** — broken, and reading uninitialised stack |
| `p_glb_inc` | `I64 GCTR; GCTR++;` | 11 — correct |
| `p_glb_arr` | `I64 GARR[3]; GARR[0] = 7;` | 7 — correct |
| `p_glb_memb` | `P GTAB[2]; GTAB[0].a = 7;` | 7 — correct |

A GLOBAL never reached that branch: it has a hash entry, so the parser took a different route
before the shape test could see it. A LOCAL does not, which is why `Y` inside
`CFE_TIME_UnixToCalendar` was the shape that broke and why nothing else in the tree was.
`CFG_ARR[0] = 11;` has been in the cFS differential oracle for several commits with a
byte-identical transcript, `RVDisasm.HC` fills `RN[0] = "zero"` through `RN[31]`, and
`cfe_target_config.HC` writes `CFE_CORE_MODULE_LIST[0].Name` — all globals, all always correct.

**AND A FINDING THAT DID NOT SURVIVE THE MEASUREMENT, recorded because the way it failed is the
reusable part.** An audit for an all-caps name followed by a modifying operator turned up
`bootstrap/seed/vim.hc:927` -- `VN++` inside the editor's file loader -- and with that increment
discarded the loader would write every line into `VLn[0]`, leave `VN` at 0, and the `VN < 1`
guard would then replace the lot with one blank line: opening a file with content would show an
empty buffer. It was written up as a second, independent instance of the same compiler bug.

It is not one. `VN` is declared at file scope on line 8 of that file, so it is a GLOBAL, and the
table above says globals were never affected. The editor was always fine. What produced the wrong
conclusion was reasoning from the SHAPE of the source line -- all caps, followed by `++` -- which
is the same reasoning the parser was doing wrong, and applying it without checking the one
property that turned out to decide the outcome. The grep was correct and the inference from it
was not.

The remaining audit result is the real one: outside the test cases, the only affected site in the
tree was `cfe_time_api.HC`'s `Y`. Nothing in this kernel names a LOCAL in capitals.



## 15. `#if <expr>` is UNCONDITIONALLY TRUE — OPEN

```c
#define Z 0
#if Z
  r += 1;      // taken
#else
  r += 2;      // skipped
#endif
```

`host/lexer.c`'s directive handler says it outright: *"#if — only literal 0 / non-zero"*. It
looks at the first non-blank character after the directive, treats a literal `0` as false, and
treats **anything else** as true. So `#if 0` works, and

- `#if MACRO` where `MACRO` is `0` — **true**
- `#if MACRO` where `MACRO` is `FALSE` — **true**
- `#if UNDEFINED_NAME` — **true**
- `#if (MACRO == 1)` where `MACRO` is `0` — **true**

`#ifdef` and `#ifndef` are evaluated properly, and the `#else` arm is correctly skipped. That last
part is what makes this quiet rather than loud: the file compiles, one branch runs, and it is the
wrong one. There is no diagnostic.

**What it costs in the kernel, which is not a hypothetical.** `Kernel/KernelA.HH:2785`:

```c
#define _CFG_HEAP_DBG FALSE

#if _CFG_HEAP_DBG
class CMemUsed { CHeapCtrl *hc; U8 *caller1,*caller2; CMemUsed *next,*last; I64 size; U0 start; };
#else
class CMemUsed { CHeapCtrl *hc; U0 caller1,caller2;   U0 next,last;         I64 size; U0 start; };
#endif
```

The `FALSE` is ignored, so this kernel uses the DEBUG layout. **Measured both ways** with the
declarations copied verbatim into an exec case, rather than inferred from reading them — which
matters here more than usual, because the thing in question is how this compiler reads text:

| layout | `CMemUsed` | `CMemUnused` |
|---|---|---|
| what `#if _CFG_HEAP_DBG` compiles today | **48** | **40** |
| what `#if 0` compiles, i.e. NASA's `#else` | **16** | **16** |

So it is 32 and 24 bytes of header per allocation that the configuration does not ask for. The
`#else` branch also COMPILES and gives 16, which was worth checking separately: it has never been
compiled in this port's life, and it leans on four `U0` zero-size members in non-trailing
positions — the shape limit #7's fix was about. It works.

**A correction to the first version of this entry, and it is the same error twice in one day.**
It said the three matching `#if _CFG_HEAP_DBG` blocks in `Kernel/Mem/MAllocFree.HC` maintain the
debug queue that goes with the layout. **`Kernel/Mem/MAllocFree.HC` is not in the RISC-V build** —
`Kernel/Kernel_RV.PRJ` includes `Mem/MakeMem` and not it, because that file is x86 assembly. The
claim came from grepping for the directive and reasoning about what the grep found, which is
exactly how the `vim.hc` paragraph under #14 went wrong. What IS built is `KernelA.HH`, so the
class DEFINITIONS are the real consequence and the queue maintenance is not. `Adam/AMem.HC` and
`tos/Misc/OSInstall.HC` have one site each and are likewise not in this kernel's project file.

**What it cost in cFS, and how it surfaced.** `cfe_time_tone.c`, `cfe_time_task.c` and
`cfe_time_dispatch.c` between them carry 35 configuration directives, and the first version of the
translation kept them. Every one was compiled in, including the time-CLIENT branches and the three
external-source branches this port does not build, so the blob referenced `CFE_TIME_SetDelay`,
`CFE_TIME_SetSignal`, `CFE_TIME_SetSource`, `OS_GetLocalMET` and `OS_SelectTone` — none of which
exist here. **The blob's import trailer is what caught it** ([[blob-import-trailer-witness]]);
nothing else would have, because each of those names is one a C runtime could plausibly bind.

**Until it is implemented**, the translation resolves NASA's configuration directives BY HAND and
each one leaves a bracketed comment naming the guard, its value and which branch survived — so the
HolyC can still be read against the C line for line. `cfe_time_utils.HC` and every earlier TIME
file already did this; what changed is that these three had enough configuration in them to make
the silence dangerous rather than untidy.

**GATE: `tests/exec/cases/e_pp_if_known_wrong.hc`, and it is pinned to the WRONG value on
purpose.** It expects `0x457`, which is every `#if` branch taken; C would give `0x4c6`. If the
case starts failing, `#if` has been implemented and the pin should become `0x4c6` — not be made to
reproduce `0x457`. The manifest says so on the line above it. The case also includes a genuinely
true `#if 1`, so a "fix" that made every `#if` false would be caught too.

**When it is fixed, expect the kernel's heap layout to change** — `CMemUsed` 48 → 16 and
`CMemUnused` 40 → 16, measured above rather than predicted. That is the correct behaviour and it is
still a behavioural change to a running allocator, so it wants its own commit and its own
measurement rather than being folded into whatever implements the directive. Establish a GREEN
BASELINE for the targets that would witness it first — `make tos`, `kernel-fs-smoke`,
`kernel-load-smoke`, `kernel-heap-smoke` — because none of those is in the gate set this limit was
found by, and a red baseline makes the change unmeasurable in the way
`kernel-repl-exepubs-smoke` already is.
