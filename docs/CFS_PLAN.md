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
| OSAL **shared layer** (`src/os/shared`) | **translate 1:1** | corrected claim -- see below; it makes no OS calls at all |
| OSAL **backend** (the `OS_*_Impl` seam) | **hand-write in HolyC** | this is the ~4,000 lines that actually touch the machine |
| PSP | **hand-write in HolyC** | board-specific by definition, and this port already has the pieces |
| cFE core (ES, SB, EVS, TIME, TBL) | **transpile** from the real C | this is the volume and the heritage; hand-translation loses both |
| apps (SCH, HS, DS, LC, CI/TO) | **transpile** | same, and they are the reason to run cFS at all |

Hand-writing the bottom two and transpiling the top two is the only split that is both honest and
finite. Hand-translating cFE is 100k+ lines and would drift from upstream the day it finished.

### Correction: OSAL is not one layer, and most of it is not hand-written

This table used to read "OSAL implementation -- hand-write in HolyC", on the reasoning that a
platform layer cannot be translated. That was wrong, and measuring it is what showed the error.

OSAL is already split by NASA into two halves that meet at a seam:

  - `src/os/shared/` -- the portable layer. It makes **zero** direct OS calls. Every place it
    would touch the machine, it calls one of **128** `OS_*_Impl` functions. It is the id map, the
    name tables, the locking discipline and the argument checking, and it is the large half.
  - `src/os/<posix|vxworks|rtems>/` -- three complete backends implementing that same seam. They
    are what is genuinely platform-specific, and a fourth one for this kernel is the hand-written
    work.

So the shared layer is translated 1:1 like cFE, and is under the same differential oracle: a
recording-stub backend returning fixed values makes it testable with no OS underneath at all,
because the shared layer never asks for one. Only the backend is hand-written, and it is written
against a seam with three reference implementations to check it against.


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

This tree already has exactly that shape in `tests/exec/oracle_manifest.tsv` — 114 cases that
compile HolyC, run it under QEMU and compare a single value. Extending it to "same program, two
languages, same answer" is the natural generalisation, and it catches transpiler bugs and compiler
bugs with one mechanism. Every translated cFE unit gets an entry.

## Where the translation actually stands

Everything below runs in one gate, `make cfs-xlat-smoke` (`tests/scripts/run_cfs_xlat_smoke.sh`),
which is in `make ci`. It asserts three different things, because each is blind to what the
others catch:

1. **Completeness** — every function defined in a gated NASA `.c` exists in the translation.
   72 functions across 21 sources today. The transcript cannot see this: a function nobody calls
   is linked from NASA's source on the C side, absent on the HolyC side, and the diff stays
   empty. `CFE_MSG_GetNextSequenceCount` was missing exactly that way for four commits, while
   two commit messages called the module complete.
2. **Behaviour** — **135 transcript lines required to be byte-identical** between NASA's
   unmodified C compiled natively and the HolyC translation run under QEMU.
3. **Linkage** — an empty import trailer, so no call silently resolves to the C runtime. An
   undefined prototype compiles clean and binds to whatever the linker finds; measured, a
   missing `Abs` left the gate reporting 88 identical lines while the call ran C code.
Growing the source list and the transcript together is how this advances — one file, one set of
lines, one diff, one negative control.

**~2,454 lines of NASA C, out of 41,765 in cFE's flight source.** The honest denominator matters:

| cFE module | NASA lines | translated | note |
|---|---|---|---|
| `msg` | 1,491 | **1,065** | all 8 unconditional sources plus the two v1/pri variants — complete for this configuration |
| `resourceid` | 228 | **228** | complete, SIMPLE variant |
| `sb` | 6,086 | **432** | `cfe_sb_msg_id_util.c` and `cfe_sb_util.c` complete; api/priv/task are the other 5,650 |
| `config` | 782 | **489** | get/set/lookup/eds complete; `init.c` (241) and its objtab wait for the build-generated GLOBAL_CONFIGDATA |
| `es` `tbl` `time` `evs` `fs` `ta` | 32,643 | 0 | blocked on OSAL |
| `sbr` | 535 | **434** | complete for the default HASH map; `map_direct` is the alternative |

Translated units live in `Kernel/Cfs/cfe/`, one HolyC file per C file, NASA's copyright retained,
with the generated headers each one needs inlined and attributed in a comment.

**The translated module is now load-bearing, not test-only.** `Kernel/Cfs/CfsSb.HC` — the
hand-written simulated spacecraft's software bus — builds every packet with `CFE_MSG_Init`,
`CFE_MSG_SetSequenceCount` and `CFE_MSG_OriginationAction`, so what goes on its bus is a
conformant CCSDS space packet because NASA's code put it there. Its message ids are real CCSDS
stream ids (`0x0800|apid` telemetry, `0x1800|apid` command, which is cFE's own stock mapping).
`make kernel-cfs-smoke` asserts that with `ccsds_ok` and `cmdcsum_ok`. Every behavioural counter
was unchanged across that swap.

**What is NOT here at all:** the cFS *applications*. `tools/cfs/fetch.sh` clones exactly three
repositories — cFE, osal, PSP. SCH, LC, HS, CS, DS, SC, MM, MD, FM, CF and SBN are each separate
NASA repositories and none is vendored. The app layer in `Kernel/Cfs/CfsApps.HC` is hand-written
to the same architecture; it is not a translation of anything, and it says so.

### OSAL, measured the same way

**ALL 9,447 lines of NASA's shared layer, gated** (100%, 25 of 25 sources), computed by
`tools/cfs/check_manifest.py` on every gate run rather than counted here. The denominator is the portable half
only; the three vendored backends (posix 4,598, vxworks 3,984, rtems 3,543) are reference
implementations of the seam, not things to translate.

The 9,447 is `OSAL_SRCLIST` in `vendor/osal/CMakeLists.txt`: **25** sources, built unconditionally.
`osapi-debug.c` is a 26th file in the directory and is appended to that list only when
`OSAL_CONFIG_DEBUG_PRINTF` is set, which this configuration does not set. An earlier version of
this table counted it, giving 9,523 — the same mistake made once already with cFE's `msg` module,
where the directory has more sources than the build uses. The denominator comes from the build
recipe, not from `ls`.

| OSAL shared source | NASA lines | gated | note |
|---|---|---|---|
| `osapi-idmap.c` | 1,501 | **yes** | the keystone: every other module allocates through it |
| `osapi-rwlock.c` | 322 | **yes** | |
| `osapi-condvar.c` | 312 | **yes** | `TimedWait` takes an absolute time, unlike its siblings |
| `osapi-binsem.c` | 277 | **yes** | |
| `osapi-queue.c` | 274 | **yes** | Get and Put reject on OPPOSITE sides of `max_size` |
| `osapi-task.c` | 461 | **yes** | the delete hook, and the priority store the backend can veto |
| `osapi-printf.c` | 336 | **yes** | the console ring buffer; gated separately, see below |
| `osapi-mutex.c` | 256 | **yes** | |
| `osapi-countsem.c` | 249 | **yes** | the template the other four were generated from |
| `osapi-errors.c` | 164 | **yes** | |
| `osapi-clock.c` | 161 | **yes** | |
| `osapi-version.c` | 77 | **yes** | |
| `osapi-heap.c` | 53 | **yes** | |
| `osapi-filesys.c` | 788 | **yes** | path translation, the mount-point prefix trap, and the mount/unmount flag arithmetic |
| `osapi-sockets.c` | 773 | **yes** | the stream_state machine, and TYPE vs STATE error codes |
| `osapi-file.c` | 685 | **yes** | `OS_cp`'s short-write retry loop; path translation at the backend boundary |
| `osapi-time.c` | 548 | **yes** | the circular timer ring, and one-shot vs repeating |
| `osapi-timebase.c` | 538 | **yes** | the callback thread, driven by a scripted sync function |
| `osapi-module.c` | 472 | **yes** | the empty static symbol table, and which error survives a failed lookup |
| `osapi-common.c` | 460 | **yes** | the integration point: `OS_API_Init` calls every other module's initialiser, which is why it went last |
| `osapi-dir.c` `-select.c` `-task-affinity.c` `-network.c` `-shell.c` | 740 | no | |
| `osapi-debug.c` | 76 | **n/a** | NOT in this configuration: `OSAL_SRCLIST` appends it only under `OSAL_CONFIG_DEBUG_PRINTF`, which is `#undef` here — which is also why `OS_DEBUG` is a no-op and pre-init `OS_printf` output is silently discarded |

#### Why printf needs its own gate

`osapi-printf.c` is gated by `tests/scripts/run_osal_printf_smoke.sh`, not by the main OSAL
gate, and the reason is a genuine limit rather than convenience.

The main gate stubs `OS_printf` to print a fixed `bugcheck` marker, because OSAL's `BUGCHECK`
logs through it:

    BUGREPORT("\n**BUG** %s():%d:check '%s' FAILED --> %s\n\n", __func__, __LINE__, #cond, #errcode)

HolyC has no `__func__`, no `__LINE__` and no stringification, so the translation keeps the check
and the return and does not reproduce the wording. That marker is load-bearing: it is the only
thing distinguishing a `BUGCHECK` (which logs) from an `ARGCHECK` (which is silent) when both
return a code, and a negative control on exactly that distinction has fired before.

Once `osapi-printf.c` is in the build, `OS_printf` is NASA's real one and the stub cannot exist —
one definition per program. The C side would emit the full `**BUG**` text where HolyC emits
nothing comparable, and every marker line would diverge over C preprocessor machinery rather
than over the translation.

So the second gate is **scoped**: it links `osapi-printf.c` and `osapi-idmap.c`, drives the
console ring buffer directly, and its driver never triggers a `BUGCHECK`. In particular it never
calls `OS_printf(NULL)` — `BUGCHECK_VOID` would call `BUGREPORT`, which calls `OS_printf`, which
is the function under test. 16 transcript lines, and what they pin is the ring buffer: the
all-or-nothing write, the wraparound, the overflow counter, the `PrintfEnabled` gate, the
pre-`OS_API_Init` discard, and truncation at `OS_BUFFER_SIZE`.

Two numbers there are derived rather than observed. The buffer is
`(sizeof("") + OS_BUFFER_SIZE) * OS_BUFFER_MSG_DEPTH` = `(1 + 172) * 100` = **17,300** bytes,
and the transcript prints it. And the fill loop runs 400 times, not 200: at 71 bytes a message
the ring takes about 244 writes to fill, and at 200 the loop ran out first — the overflow path
was never reached, `ovf=0`, and the all-or-nothing check underneath it was measuring nothing. A
control that cannot fire is worse than no control, so the bound comes from the buffer size.

`OS_printf`'s formatting goes through `StrPrintNV`, the `(fmt, argc, argv)` form — the same
triple TempleOS's own `StrPrintJoin` takes, which is what a HolyC variadic receives.

#### What the OSAL transcript does NOT cover, stated rather than implied

- ~~**`OS_ShellOutputToFile`'s lock mode.**~~ Closed: `osapi-file.c` now provides real streams,
  so `f_shell` drives the call down its success path with an open file descriptor.
- **`flags |= OS_ADD_TASK_FLAGS`** in `OS_TaskCreate`. `OS_ADD_TASK_FLAGS` is 0 in this
  configuration, so deleting the line entirely prints the same `fl=0x11`.
- **`OS_ModuleUnload`'s static/dynamic guard.** It calls `OS_ModuleUnload_Impl` only for a
  `DYNAMIC` module, because a `STATIC` one is a placeholder with no file behind it. Nothing can
  create a static module in this configuration -- the static symbol table is empty -- so the
  guard cannot be exercised and removing it would not fail the gate.
- ~~**Struct field parity.**~~ Closed by `tools/cfs/check_structs.py`, which found two more
  omissions the moment it ran: the mutex record was missing `last_owner` and the rwlock record
  `last_writer`, and with them the entire ownership-tracking logic in `OS_MutSemGive`/`Take`
  and the rwlock give/take paths. All four earlier checks passed on that code.

#### `Kernel/Cfs/**` is exempt from the HolyC formatter

`tests/scripts/holyc_fmt_paths.sh` enforces `holyc-riscv --fmt` over 487 files and **none** of
them is under `Kernel/Cfs/`. That is worth stating because it is a real gap in a large body of
code — about 7,000 translated lines — and because there is a defensible reason for it: the
formatter reflows code, and a 1:1 translation is read side by side with NASA's C, so keeping
NASA's line structure is worth more here than house style. If that exemption is ever removed,
expect the whole translation to reflow in one commit.

The oracle DRIVERS under `tests/exec/cases/` are NOT exempt, and three of them had drifted out
of format while being appended to all day. Formatting them changed `osal_xlat_errors.hc` by 149
lines, so all three gates were re-run afterwards: 135, 316 and 16 identical lines, unchanged.

#### Driving a `while (1)` in a transcript

`OS_TimeBase_CallbackThread` never returns on its own: it calls the time base's sync function,
walks the ring of timers, and loops. It is testable anyway, because **the sync function belongs
to the caller**. The driver's version hands back a scripted tick count and, when the script
runs out, clears the global record's `active_id` — which is precisely the condition the thread
checks each pass to notice it was deleted, and its only exit.

That also made the DEADLOCK GUARD reachable. Every function in `osapi-time.c` refuses when
`OS_ObjectIdToType_Impl(OS_TaskGetId_Impl())` says the caller is a TIMEBASE, because a timer
callback already holds the timebase lock. The stub `OS_TaskRegister_Impl` was given the
behaviour a real OS has — it makes `OS_TaskGetId_Impl` return the registered id — so the
callback thread genuinely looks like a timebase from the inside, and `cbt_guard rc=-35`
records the refusal.

What the transcript pins: `cbt_fired t1=3 t2=1 t3=6` over four ticks of 3. **t2 fires exactly
once** — it is the one-shot, set with a positive `wait_time` and a zero `interval_time`, so
`wait_time` never goes positive again and the "only fire when it crossed from positive"
condition holds. Getting that wrong is what the compound-assignment compiler bug did, and it
showed up here as t2 firing three times.

The ring order is dumped after every change (`ring3 first=3 -> 2 -> 1`), because a wrong splice
shows up as a short walk or a wrong order rather than as an error code, and deleting the middle
of a three-timer ring must leave `3 -> 1`.

One number here is derived rather than observed: `OS_Milli2Ticks`'s overflow branch **cannot be
reached** at 100 ticks/sec, since the largest possible result is `0xFFFFFFFF * 100 / 1000` =
429,496,730, well under `INT_MAX`. The driver raises the tick rate for that one call; otherwise
the line would be a test that can never fail.

#### The shared layer is complete

Every source in `OSAL_SRCLIST` is translated and gated: **25 of 25, 9,447 of 9,447 lines**.
`tools/cfs/check_manifest.py` computes that on every gate run, so it cannot drift.

`osapi-common.c` was deliberately last. Its `OS_API_Init` calls every other module's
initialiser and its `OS_CleanUpObject` calls every module's delete, so each module finished
before it removed a stub from it — by the time it was written, there were none left.

**Include position is load-bearing, and not free.** `osapi_idmap.HC` includes
`osapi_common.HC`, because idmap needs `OS_SharedGlobalVars` and `OS_NotifyEvent` — which puts
the whole of common very early, long before the modules `OS_API_Init` drives. That works
because the compiler patches forward references through the blob's import slots, filling each
from the definition's own address once the unit is complete. Moving it later does **not** work:
the AOT entry chunk is emitted first and performs those patch-ups, so a definition appearing
after it is never wired and the program returns without ever reaching `main`. Splitting the
file in two was tried and reverted — every placement of the second half traded one set of
unresolved imports for another. The blob's empty-import-trailer assertion is what made each
attempt fail loudly instead of silently.

One consequence worth stating: the separately-scoped printf gate links only `osapi-printf.c`
and `osapi-idmap.c`, but inherits `OS_API_Init`'s whole call graph through that same include.
It stubs the thirty functions rather than linking the modules, because linking them would make
it a copy of the main gate and lose the one thing it exists for — a real `OS_printf`, which
cannot coexist with the fixed `bugcheck` marker the main gate depends on.

### cFE, measured the same way

`tools/cfs/check_manifest.py --cfe` runs in the cFE gate and reports every module from its own
CMakeLists, splitting sources by `if()` depth so a conditional one is listed with its guard
rather than counted as always-built:

| module | uncond. sources | lines | gated |
|---|---|---|---|
| `msg` | 8 | 962 | **100%** |
| `resourceid` | 2 | 228 | **100%** |
| `sbr` | 1 | 33 | **100%** (its map and route sources are conditional; the HASH default is gated) |
| `config` | 5 | 697 | **100%** |
| `sb` | 7 | 5,278 | 4% |
| `fs` | 3 | 1,249 | **100%** |
| `ta` | 2 | 892 | **100%** (plus `cfe_ta_dispatch.c`, 159, which is conditional — see below) |
| `evs` | 5 | 2,787 | 0% (three of six sources translated; see below) |
| `time` | 5 | 4,383 | 0% |
| `tbl` | 15 | 7,780 | 0% |
| `es` | 17 | 12,734 | 0% |

#### `evs`: translated but not yet gated, and why that is said out loud

Three of EVS's six sources are translated — `cfe_evs_utils.c` (650), `cfe_evs_log.c` (277) and
`cfe_evs.c` (336), 1,263 lines — and the manifest above still reports **0%**, because the
manifest counts what the TRANSCRIPT covers and no EVS source is in the gate's source list yet.
That is the honest number and it stays there until the driver integration lands.

What *is* verified: coverage (21 of 21 functions), signatures (23, with one recorded
deviation), `check_structs` and `check_padding` (71 classes) and `check_constants` (267 values).
Five of the eight properties. The missing three are the transcript, and they are missing for a
specific reason rather than for lack of effort: wiring EVS in **removes the `CFE_EVS_SendEvent`
stub**, so every `evs eid=N type=N` line the `ta` module currently emits becomes a real event —
filtered, squelched, logged and formatted — and both sides of the oracle change together. That
is the point of translating EVS, and it is a change to be made deliberately rather than at the
end of a long session.

The variadic seam is what makes it possible at all. `EVS_GenerateEventTelemetry` formats the
event text with `vsnprintf` into the 122-byte packet payload — the text *is* the message — so
for the first time a formatted string is inside the byte-identical comparison instead of beside
it. HolyC has no `va_list`, but a variadic function there receives an implicit `(argc, argv)`
pair, which is exactly the triple `StrPrintNV` takes. One extra parameter, recorded in
`check_signatures.py`'s `DEVIATIONS`.

`StrPrintNV` grew `%x`, `%X` and field widths for it, and writing the oracle for those found a
real bug: `%06d` of -42 produced `000-42` where C writes `-00042`. C puts the sign before zero
padding and after space padding, and the first version padded first in both cases.
`tests/exec/cases/e_strprint_hex.hc` pins the whole set, and its expected value is not a hash of
the HolyC formatter — it is the number the same fold computes over C's `snprintf` output.

#### A conditional source can hide behind a 100%

`ta` is the first module where the percentage above is not the whole story.
`modules/ta/CMakeLists.txt` picks its dispatcher with

```cmake
if (CFE_EDS_ENABLED)  cfe_ta_eds_dispatch.c   else  cfe_ta_dispatch.c
```

so `cfe_ta_dispatch.c` (159 lines) **is** in this configuration's build, and
`check_manifest.py` counts only depth-0 sources — conditional ones are listed with their guard
for a person to judge, which is the right default and is why the denominator stopped being
wrong twice before. But `CFE_TA_TaskMain` calls `CFE_TA_TaskPipe`, which lives in that file.
Translating the two unconditional sources would have reported `ta 100%` with a task whose
message loop dispatches to nothing.

It is translated and gated, and the manifest line shows it as `GATED` under its guard. Any
module with a conditional source needs the same read: the percentage covers the unconditional
ones and the lines underneath it are not decoration.

#### How `config` got from 61% to 100%: build-system emulation, not translation

Its last two sources were never blocked on translation effort. They needed build output:

- `cfe_config_init.c` reads `GLOBAL_CONFIGDATA`, whose tables CMake emits per target —
  `tools/cfs/gen_target_config.py`.
- It uses the `CFE_CONFIGID_*` id macros from the generated `cfe_config_ids.h` —
  `tools/cfs/gen_configid_table.py`, which now emits them in the HolyC half too.
- It calls `CFE_Config_SetupPlatformConfigInfo`, **declared in `cfe_config_external.h` and
  defined nowhere in the tree**.

The third one is the interesting one, and the answer was not to write a generator.
**cFE ships the generator**: `modules/config/tool/` is a native C program, compiled for the
build host rather than the target, that emits the array contents and the entry list, and
`modules/config/cmake/cfe_platform_cfg.c.in` is the template they go into.
`tools/cfs/gen_platform_config.py` compiles and runs NASA's own tool and fills NASA's own
template, so the C the oracle links is not a reimplementation of cFE's build — it IS cFE's
build, driven by something other than CMake. Only the HolyC half is this port's, and it carries
the resolved integers because HolyC has no `cfe_platform_cfg.h` to expand the macro names from.

In this configuration the tool emits **three** array entries, not five:
`CFE_PLATFORM_TBL_VALID_SCID` and `_PRID` have a count of 0 and an empty list is skipped. A
hand-written generator would have emitted two empty arrays and nothing would have noticed.

Two bugs came out of it, one upstream and one mine, and they are the same bug:
`CFE_Config_SetArrayValue` and `CFE_Config_SetString` retain the pointer and copy nothing.
NASA's template declares each array descriptor `static const` for that reason; my generator
reused one local and all three ids pointed at the same dead stack slot (`NumElements` read back
as 2,156,050,768). Three lines away in NASA's own code, `CFE_Config_SetupBasicBuildInfo` stores
a **local** `VersionString` into `CFE_CONFIGID_CORE_VERSION_DESCRIPTION` and has the same defect
— see `docs/CFS_UPSTREAM_NOTES.md` #8, where it is measured.

Eight properties are gated independently, because each is blind to what the others catch:

| check | what it proves | what it cannot see |
|---|---|---|
| `check_coverage.py` | every function in a gated NASA source exists in the translation | its arity, its types, its body |
| `check_signatures.py` | arity and pointer-ness match NASA's, per parameter | return types; anything named `*_Impl` |
| `check_seam.py` | the `OS_*_Impl` declarations match NASA's headers, **return type included** | whether a backend obeys them |
| `check_structs.py` | a translated `class` has NASA's fields, in NASA's order | field TYPES, and where the fields actually sit |
| `check_padding.py` | a translated `class` has NASA's BYTE LAYOUT — every offset and the size | whether anything reads those fields correctly |
| `check_constants.py` | every number the translation spells out has NASA's value | whether anything uses it, or uses it correctly |
| `check_manifest.py` | everything gated is in NASA's build; reports the covered fraction | nothing about the code itself |
| the transcript | behaviour, byte for byte against NASA's own C | anything nothing calls |

`check_constants.py` is the newest and exists because HolyC has neither `enum` nor CMake: the
translation re-states hundreds of numbers by hand — event ids, message ids, bit masks, array
bounds, error codes — and nothing above looked at one. A wrong array *bound* surfaces in
`check_padding` because it sizes a struct; a wrong *message id* that nothing routes, or an event
id no branch reaches, is invisible to every gate including the transcript. Its first run found
five of ninety wrong in the EVS declarations: three message ids, a buffer length guessed as
`MAX_MESSAGE_LENGTH + 30` where NASA writes `+ OS_MAX_API_NAME + 19`, and
`CFE_MISSION_ES_MAX_APPLICATIONS` (16) confused with `CFE_PLATFORM_ES_MAX_APPLICATIONS` (32) —
the mission limit sizes the array that goes out in telemetry, which is an interface a ground
system parses.

Its own first negative control did not fire, and fixing that is most of what the tool is.
Changing a message id by one still passed, because the probe's header list could not see
`CFE_EVS_HK_TLM_MID` at all and the name landed in a "NASA does not define it" bucket that was
merely *counted*. A name NASA defines somewhere in the vendor tree but the probe cannot see is
now a FAILURE naming the file, which immediately surfaced six more. The bucket that remains is
genuine: a C enumerator is not a `#define`, so `CFE_EVS_EventType_ERROR` exists only here and
there is nothing to compare it against.

Each of these was added because something got through the ones that already existed.
`CFE_MSG_GetNextSequenceCount` was missing for four commits with the transcript green;
`OS_MutSemCreate` lost a parameter with coverage green; `OS_TaskDetach_Impl` was declared
returning `U0` where NASA's header says `int32`, which only the host C compiler noticed, and
only because the oracle happens to include that header.

`check_padding.py` is the newest and had the largest first harvest: **17 of 53** translated
classes did not have NASA's layout, and all six gates above were green. HolyC classes are fully
packed — no inter-member padding, no alignment, no tail padding — which is authentic TempleOS
and is not what a C compiler does, so a class can have NASA's fields in NASA's order and still
not be NASA's struct. Four of the seventeen were not padding at all but members at the wrong
WIDTH, which padding over would have buried: `OS_lock_mode_t`, `OS_module_type_t` and
`CFE_ConfigType_t` are C **enums**, four bytes, and had been translated as `I64`. The token one
cascaded into every struct that embeds an `OS_object_token_t`.

The C side of that gate is the real host compiler's `offsetof` and `sizeof` from NASA's own
headers. The HolyC side is a model — sum the member sizes — because running the HolyC compiler
would mean building and booting a blob per struct, so the model's premise is pinned separately
as `tests/exec/cases/e_class_packing.hc`. A wrong model fails toward approving a mismatch, which
is why it does not get to be an assumption. The same reasoning put the fs classes' real `sizeof`
and offsets into the transcript as well: that is the compiled layout under the strongest gate
here, where `check_padding.py` is a model on one side.

### The C library is TempleOS's, not a private copy of libc

For a while the translation carried `cfe_xlat_libc.HC`: HolyC reimplementations of `memset`,
`memcpy`, `strcmp`, `strncpy`, `memchr` and a mini `snprintf`. That was a mistake, and the
reason it was a mistake is that TempleOS already has all of it. Confirmed by grepping the stock
distro rather than assumed, its set is

    MemCpy MemSet MemRep StrCpy StrLen StrCmp StrNCmp StrMatch StrPrint StrPrintJoin StrNew StrOcc

and `Kernel/StrPrint.HC` is a 934-line formatter handling `, " / % 0 b B c C d D e f F g h l n p
P q Q r s S t T u x X z Z` — a superset of what cFS uses — driven by the same `argc`/`argv`
varargs convention a hand-rolled `vsnprintf` would have needed.

So the translation calls TempleOS's functions directly. The mapping is exact, not approximate,
and each was checked rather than assumed:

| NASA's C | TempleOS | why it is safe |
|---|---|---|
| `memset(d,c,n)` | `MemSet` | `RVMemSet(dst,dat,size)` — C's argument order, returns `dst` |
| `memcpy(d,s,n)` | `MemCpy` | `RVMemCpy(dst,src,size)` — likewise |
| `strlen(s)` | `StrLen` | `RVStrLen` |
| `strcmp(a,b)` | `StrCmp` | **sign**-compatible: `_STRCMP` (`Kernel/StrA.HC:85`) holds `st2` in RSI and `st1` in RDI and `JA -> -1`, so `st1 < st2` is negative. The magnitude is only ever ±1, never a byte difference; every cFS call site compares against zero, so they agree there, and a future call site wanting the difference must not use it |

Three have no TempleOS equivalent anywhere in the distro and are written in `Kernel/Cfs/CfsStr.HC`
as additions in TempleOS style, not as renames of something that existed: `MemChr` (the bounded
"is there a NUL in the first n bytes" test, which `StrLen` cannot do because on an unterminated
buffer `StrLen` is what runs off the end — which is why NASA uses `memchr` here), `StrNCpy`
(C's semantics including the sharp edges, because the call sites depend on them), and
`StrPrintN`, a size-bounded formatter.

`StrPrintN` follows **C's** conversions rather than TempleOS's, deliberately: the format strings
it is handed are NASA's own, verbatim, because they are part of the translated source. Handing
`"%ld"` to TempleOS's `StrPrint` would be handing it a string it does not speak, and rewriting
the format strings would mean the translation no longer says what NASA wrote. So the spelling is
TempleOS and the conversions are C, because the input is C. TempleOS's own `StrPrint`/
`StrPrintJoin` are the right thing in the kernel, but neither is size-bounded and
`StrPrintJoin` allocates.

The standalone oracle harness has no kernel linked — that is the point of it — so it supplies
`MemSet`, `MemCpy`, `StrCmp` and `StrLen` itself, with the kernel's semantics reproduced
exactly, `StrCmp`'s ±1 included: a harness that returned a byte difference would be validating
behaviour that does not ship. These names are in `bootstrap/holy_rt_names.h`, so without those
definitions they would bind silently to the host C runtime; the gate's empty-import-trailer
assertion is what catches that, and both gates kept their exact line counts (135 and 154)
across the change, which is the evidence the rename changed no behaviour.

Things noticed in NASA's source along the way are in `docs/CFS_UPSTREAM_NOTES.md`, reproduced
rather than fixed, each pinned by the transcript.

**What the translation has cost the compiler so far**, in `docs/HOLYC_STRUCT_LIMITS.md`: cFS is
the first code in this tree to pass structs around by value, and it found three limits in an
afternoon. Returning a class larger than 8 bytes was silent corruption and is now a compile
error (`make struct-refusals-check` pins both sides of that boundary). `*dst = *src` on a large
class copies only 8 bytes and is still open — a fix was attempted and reverted because it broke
member stores. And one local-array anomaly is recorded as *not characterised*, because four
reduction attempts failed to reproduce it and saying otherwise would be guessing.

The config module's key set is generated, not invented: `tools/cfs/gen_configid_table.py` does
`configure_file`'s job from NASA's own `config_ids_base.cmake`, `config_ids_dynamic.cmake` and
templates, emitting both the C a real build compiles and the HolyC half, so the two cannot
disagree about which ids exist — a disagreement the transcript could not have caught, since a
missing id prints nothing on either side.

What the excluded `msg` sources are: `ccsdsext`, `initdefaulthdr_priext` and `msgid_v2` are
selected only when `MISSION_INCLUDE_CCSDSEXT_HEADER` is set, which this port does not set. That
is from `modules/msg/CMakeLists.txt`, which is also the file that caught a premature "module
finished" claim — the directory listing and the build recipe do not agree, and only one of them
decides what a build contains.

**Three findings the oracle produced that no amount of reading would have:**

1. A HolyC cast on an *lvalue* relabels the storage rather than converting the value, so
   translating C's `(uint32)byte` as `byte(U32)` reads four bytes instead of one. One transcript
   line out of 65, on a plausible-looking number.
2. An I32-returning function's value was not converted to its declared type, so a negative status
   compared as positive. Found because cFE returns `0xCA00000D` as an `int32` and the two sides
   printed different signs. Fixed in the compiler, behind a twelve-image byte diff.
3. `ptr = <constant> + offset` scaled the offset by the pointee size — a live miscompilation that
   had been writing the wrong QSPI register for weeks.

Each is a *compiler or translation* defect that presents exactly like the other, which is the
whole argument for the oracle.

Every unit also gets a **negative control**: deliberately break it, confirm the gate fails, put it
back. A gate that has never failed is not known to work. The controls run so far are recorded in
the commit messages rather than automated, which is a gap.

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

## The target is not sample_app

The goal is a small coherent spacecraft — sensing, navigation, payload, onboard storage,
autonomous fault response, telemetry — not the `sample_app`/`ci_lab`/`to_lab` bundle. That changes
what the platform layer has to provide, because the real apps lean on parts of cFE that a demo
never touches. Mapped against what this port actually has today:

| app | what it demands of the platform | status here |
|---|---|---|
| **SCH** scheduler | a periodic tick with low jitter, and real task accounting | tick exists; **cooperative scheduling means minor frames will jitter** — this is the app that forces P6 earliest |
| **SC / SCA** stored command | absolute spacecraft time, and **files** for ATS/RTS tables | TIME can come from CLINT `mtime` plus the battery RTC; files now exist over 9P |
| **LC** limit checker | TBL plus SB; little else | cheap once TBL works |
| **HS** health & safety | per-app execution counters, task introspection, watchdog servicing | **the weakest fit**: detecting "an app stopped running" needs real task accounting, which cooperative scheduling does not give |
| **CS** checksum | memory ranges and file checksums from the PSP | good fit, and `Dump`/`Peek` already exist for the corruption experiments |
| **MM / MD** memory manager, dwell | commandable memory **write** | reads exist (`Peek`, `PeekU32`, `PeekU64`, `Dump`); there is deliberately **no Poke**, and MM means revisiting that on purpose |
| **FM** file manager | the OSAL file API | unlocked by 9P |
| **DS** data storage | writable files, and ideally ones that survive link loss | 9P works but is host-dependent; a real recorder eventually wants local storage |
| **SBN** software bus network | a datagram link between nodes | **nearly free now** — see below |
| **CF / BP** DTN | bundle protocol library | large, and last |

Two entries there are load-bearing and worth saying plainly. **HS and SCH are what make cooperative
scheduling untenable**, not a stylistic objection: HS exists to notice that an app stopped
executing, and SCH exists to run things on time. Both are meaningless without preemption and per-
task accounting. So P6 is not optional polish for this target — it moves up.

And **MM is a safety decision, not a feature**. `Kernel/RVPeekUi.HC` has no `Poke` on purpose, and
`Kernel/Drv/RVSifiveI2c.HC` is read-only with an allow-list because pin 2 of the PMIC powers the
board off. An app whose whole job is commandable memory and device writes has to reopen both of
those deliberately, with the reasoning written down, not by quietly adding a write path.

## SBN is nearly free, and it is the most interesting piece

`Kernel/NineP/NinePEth.HC` is already a request/response datagram transport over a custom
ethertype, with peer discovery by broadcast and tag-matched retry. SBN over a second ethertype is
the same pattern with a different payload. That makes the multi-node experiment — Unmatched as one
flight computer, an STM32 as another — reachable much sooner than the sensor work, and it needs no
IP stack.

## Revised order, and why it differs from the obvious one

The instinct to skip `sample_app` is right. But of the five targets, **FDIR should come first, not
last**, because it is the only one that needs no new driver at all:

1. **FDIR with synthetic apps** — HS + LC + SC, with fake sensor apps publishing on the software
   bus. Inject the whole fault list (app stops publishing, app hangs, queue fills, value out of
   limits) with no GNSS, no IMU and no SDR attached. This exercises cFE harder than any sensor
   app, and every fault is reproducible, which a real sensor's failure is not.
2. **Recorder (DS)** — the second thing that needs no new hardware, now that files exist.
3. **IMU over I²C** — first real sensor, and the first time the read-only I²C decision has to be
   revisited.
4. **GNSS over UART** — needs UART1 at `0x10011000`; whether it is on a header on this board is
   **unverified** and should be checked before planning around it, since UART0 is the console.
5. **SDR and FPGA over PCIe** — largest by far: the iATU work is milestone 1b and has not started.
   Everything else should be working before this begins.

The EPS node in the sketch has no direct path on this board: the FU740 has no CAN, so it would be
an external controller over I²C, SPI or UART, or another cFS node behind SBN.

## An honest note on scale

Sensing → navigation → payload → storage → autonomy → telemetry, translated into HolyC, on a port
that got its ethernet working today, is a multi-year project. That is not an argument against it.
It is an argument for the ordering above: every step from FDIR through the recorder produces
something demonstrable on its own, and none of them is blocked on the two hardest pieces
(preemption and PCIe). The fastest way to learn whether the whole thing is real is still P0 — one
translated CCSDS header unit with a byte-exact differential oracle.

## What to do first

P0, then stop and decide. One hand-translated CCSDS header unit with a byte-exact differential
oracle answers the only question that matters — whether translated cFS behaves identically — before
a transpiler or a line of OSAL exists.
