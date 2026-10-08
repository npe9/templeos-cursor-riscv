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
| `sb` | 6,086 | **6,086** | complete — all seven unconditional sources plus `msg_id_util`; the EDS dispatcher is the alternative |
| `config` | 782 | **489** | get/set/lookup/eds complete; `init.c` (241) and its objtab wait for the build-generated GLOBAL_CONFIGDATA |
| `es` | 12,734 | **13,044 (100%)** | ALL SEVENTEEN SOURCES. `crc`, `generic_pool`, `syslog`, `mempool`, `resource`, `api`, `task`, `erlog`, `backgroundtask`, `objtab`, `perf`, `dispatch`, `appctrl`, `apps`, `cds`, `cds_mempool`, `startupscript`, `start` -- so `CFE_ES_Main`, cFE's own boot sequence, runs in the differential: five system states in order, the core object table walked twice, and the startup script parsed from a staged file. Plus the module's STATE (`cfe_es_global.HC`) and its twenty-two ground message formats (`cfe_es_msg.HC`). The driver's simulated bump allocator is GONE -- every allocation in the transcript runs NASA's real pool, and with `api.c` gated "who is calling" comes out of ES's own app and task tables rather than out of a stub |
| `tbl` | 7,780 | 0 | after `es` |
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
| `sb` | 7 | 5,278 | **100%** — all seven sources |
| `fs` | 3 | 1,249 | **100%** |
| `ta` | 2 | 892 | **100%** (plus `cfe_ta_dispatch.c`, 159, which is conditional — see below) |
| `evs` | 5 | 2,787 | **100%** (six of six; the `_dispatch` one is conditional — see below) |
| `time` | 5 | 4,383 | **100%** (plus `cfe_time_dispatch.c`, 294, which is conditional — see below) |
| `tbl` | 15 | 7,780 | 0% |
| `es` | 17 | 12,734 | **100%** (13,044 lines with `dispatch`, which is the conditional one -- CMake picks it when EDS is off, which is this configuration) |

#### `evs`: the first module whose TEXT is the comparison

All six of EVS's sources are gated, **2,787 lines, 100%**: `cfe_evs_utils.c` (650),
`cfe_evs_log.c` (277), `cfe_evs.c` (336), `cfe_evs_task.c` (1,485), `cfe_evs_dispatch.c` (326,
the conditional one — `CMakeLists.txt` picks it when EDS is off, which is this configuration) and
`cfe_evs_objtab.c` (39). That makes EVS the seventh module at 100% and the largest so far.

Wiring it in removed the `CFE_EVS_SendEvent` stub, so the transcript went 363 → 466 lines, and
what those lines carry is different in kind from everything before them. `EVS_SendViaPorts`
formats the packet payload and prints it, so the comparison now includes

```
EVS Port1 1980-001-00:00:44.52768 23130/1/CFE_EVS 2: s=name u=7 d=-3 x=0000beef
EVS Port1 1980-001-00:00:44.52768 23130/1/CFE_EVS 18: Set Task Affinity for CFE_ES: Type = 1, mask = 0x0000000000000001, from O/S = 0x0000000000000001
EVS Port1 1980-001-00:00:44.52768 23130/1/CFE_EVS 11: Task Info file written to /ram/tasks.dat, Entries=64, FileSize=2116
```

— the first formatted strings in this port that are INSIDE the byte-identical comparison rather
than beside it. Every one of `ta`'s twenty event strings is now compared against NASA's own
output, which also closed a deviation: `cfe_ta_task.HC` used to take the id, the type and a
plain string, leaving the wording outside. It now passes NASA's arguments.

The variadic seam is what makes that possible. `EVS_GenerateEventTelemetry` formats with
`vsnprintf` into the 122-byte payload; HolyC has no `va_list`, but a variadic function there
receives an implicit `(argc, argv)` pair, which is exactly the triple `StrPrintNV` takes. One
extra parameter, recorded in `check_signatures.py`'s `DEVIATIONS`.

Four things came out of that seam, and three of them were silent:

- **`StrPrintN` took five arguments and `EVS_SendViaPorts` formats six.** A HolyC default
  argument is a call-site expression, so the sixth was simply not passed and `nargs = 5` made
  `StrPrintNV` stop short: every port line read `(null)` where NASA's read the event. The arity
  is now eight and written down as a ceiling.
- **`EVS_SendEvent` was called from four places above its own definition.** A HolyC call site
  builds `(argc, argv)` only if it already knows the callee is variadic, and a forward call does
  not. It reached `StrPrintNV` as `nargs=1, args=NULL` and faulted on a load from address 0.
- **`CFE_EVS_SendEvent` was declared NON-variadic in `cfe_ta_task.HC`** and defined variadic in
  `cfe_evs.HC`. No gate could see it: `check_signatures` compares definitions and both
  definitions were right. This is what `check_variadic.py` exists for.
- **`%016llX` was masked to 32 bits.** `tests/exec/cases/e_strprint_hex.hc` catches it; the
  transcript does not, and that was measured rather than assumed — see the controls below.

`StrPrintNV` grew `%x`, `%X`, `ll` and field widths for EVS, and writing the oracle for those
found two more real bugs: `%06d` of -42 produced `000-42` where C writes `-00042` (C puts the
sign before zero padding and after space padding, and the first version padded first in both
cases), and `%llu` above 2^63 printed 17 digits instead of 20, because `uv /= base` emits a
SIGNED divide for a `U64` while the `uv % base` on the line above it does not
(`docs/HOLYC_STRUCT_LIMITS.md` #11). `tests/exec/cases/e_strprint_hex.hc` pins the whole set, and
its expected value is not a hash of the HolyC formatter — it is the number the same fold computes
over C's `snprintf` output, line by line.

#### And the other deviation of the same shape: CFE_ES_WriteToSysLog

`CFE_ES_WriteToSysLog` is variadic in NASA's C and every call site passes `__func__` plus a
format string. The translation took a plain string, with the enclosing function's name written
into the literal and the VALUES dropped, so the transcript printed a bare `syslog` and pinned
only *which paths log*. That was defensible while there was no formatter. There is one now.

All 25 call sites in the gated sources pass NASA's arguments, both oracle halves format, and the
transcript is 477 lines. Writing the function's name into the literal is not an approximation:
`__func__` expands to exactly that name, so the characters are the same and the comparison covers
them. Fifteen distinct log lines are now compared, including the only one in the translation
that formats three arguments:

```
syslog CFE_FS_LockSharedData: SharedData Mutex Take Err Stat=-12,App=17185,Function=take_fails
syslog CFE_TA_SetStartupAffinity: Set Startup Affinity for task (CFE_ES) could not Get Task Affinity, Status = -2
syslog CFE_EVS_Register: Filter limit truncated to 8
```

Restoring the arguments also exposed how little of this the driver reached. Seven of the
twenty-five sites had no path to them at all, so the arguments would have been translated and
never read — the same finding as the squelch clamp, three more times:

| site | what was missing | now |
|---|---|---|
| `CFE_FS_EarlyInit`, `LockSharedData`, `UnlockSharedData` | `OS_MutSemCreate/Take/Give` always succeeded | `fs_mut_*_rc` steer all three |
| `CFE_TA_SetStartupAffinity` ×2 | the OS never failed inside the loop | `ta_getaff_rc` / `ta_setaff_rc` during a startup call |

What is still unreached, and stays that way because contorting the driver would be worse than
saying so: `CFE_TA_TaskMain`'s two lines (it is a message loop), and four in `CFE_TA_TaskInit`
that sit behind `CFE_TA_Register`, which fails first in this driver because EVS is not registered
when `ta` runs. Those four are reachable only by standing EVS up before the `ta` block, which
would change what the `ta` block is testing.

#### Finishing EVS: three more things no gate could see

The last three sources took the transcript to **657 lines** and found three defects, each in a
different gate's blind spot.

**1. A `static` local is a global under the bare name.** `cfe_ta_dispatch.c` and
`cfe_evs_dispatch.c` both cache their message ids in function-local statics, and both call them
`CMD_MID` and `SEND_HK_MID` — every cFE dispatcher does. HolyC's `static` becomes a global under
the bare name, so the second declaration landed on the first's entry and `CFE_TA_TaskPipe`
faulted on `ld a0,0(a0)` after `li a0,0`. `parser.c`'s own comment at the site says *"treat as
globals scoped to function"* and the call it makes does not scope anything.
`docs/HOLYC_STRUCT_LIMITS.md` #12; worked around by prefixing EVS's pair, and the compiler fix
lands separately because it is a `parser.c` change.

**2. A status code compared as a positive 64-bit literal.** NASA writes
`#define CFE_EVS_APP_NOT_REGISTERED ((CFE_Status_t)0xc2000002)`. The translation dropped the
cast, so the macro was `3254779906` while the `I32` holding the status was `-1040187390`, and
`Status == CFE_EVS_APP_NOT_REGISTERED` was simply false. Six per-app commands took their final
`else` and reported "Unable to retrieve application ID" where NASA reports "not registered with
EVS" — the right status returned, the wrong event sent. Twenty-nine status defines now carry
`(I32)`, which is NASA's own spelling.

That fix then broke `check_constants.py` SILENTLY: `0xC2000002(I32)` does not match its
`#define` pattern, so the 26 casts stopped being compared and the count fell 310 → 284 with no
complaint. A `#define` the tool cannot parse is one it never sees, and an unseen constant passes.
The pattern now includes the cast suffix and `literal()` applies it.

And the sweep itself was wrong the first time, which is the part worth keeping. The rule applied
was "every `#define` whose value has the high bit set", and that is not the rule: four of the
twenty-nine are UNSIGNED upstream — `OS_OBJECT_ID_RESERVED` is `((osal_id_t){0xFFFFFFFF})`,
`CFE_RESOURCEID_RESERVED` wraps a `uint32`, and the two OSAL magic numbers are plain hex. Casting
those made `OS_OBJECT_ID_RESERVED` equal to `-1`, and the OSAL transcript's entire id-allocation
block went from `alloc1 rc=0 id=0x10001` to `alloc1 rc=-1 id=0x0`. The real rule is NASA's own:
cast exactly what NASA casts to `CFE_Status_t` or `int32`, which is 23 of the 29, checked by
reading each upstream `#define` rather than by looking at the value. **The cFS gate was green
while OSAL's was red** — the two transcripts cover different trees, and only running both caught
it.

**3. `modules/*/config` was missing from the NASA struct scan — and that is where every message
struct lives.** A translated class whose NASA counterpart is not found has no pair, so
`check_structs` and `check_padding` skip it *in silence*. Every command and telemetry payload in
the port was in that hole. One of them was wrong: `CFE_EVS_SetLogMode_Payload_t` carried
`LogMode` as a `U16` because the comment said "a uint16 typedef", and `CFE_EVS_LogMode_Enum_t` is
a `uint8` — which made the command one byte too long and the dispatcher rejected it on length.
Adding the directory took both gates from **81 classes to 134**.

The control is the clearest one in this file:

| state | `check_padding` says |
|---|---|
| wrong `LogMode`, old scan | `134`→ no: **81 classes have NASA's byte layout** — PASS |
| wrong `LogMode`, `config` added | FAIL, `CFE_EVS_SetLogModeCmd_t` 10 vs 11 |
| right `LogMode`, `config` added | 134 classes — PASS |

A gate that reports a number and a pass, on a struct it never looked at, is the failure mode
every tool in `tools/cfs` is written against; this one had it for fifty-three classes.

#### What the negative controls on these lines actually found

Four mutations, each aimed at one of the new assertions:

| mutation | gate | fired |
|---|---|---|
| `EVS_SendEvent`'s prototype loses its `...` | `check_variadic` | yes, on 23 call sites |
| a non-variadic NASA function given a `...` | `check_variadic` | yes |
| the log ring wraps one entry late (`>=` → `>`) | transcript | yes, on `next` and `first` |
| the squelch floor doubled | transcript | **NO**, first time |
| one restored syslog argument set to 0 | transcript | yes, on that argument |
| `EVS_CMD_MID` renamed back to `CMD_MID` | — | **crash**, not a gate: it is a compiler limit |
| the `(I32)` cast dropped from one status | transcript | yes |
| `LogMode` back to `U16` | `check_padding` | yes — and **NO** before `config` was in the scan |
| `%llX` masked back to 32 bits | transcript | **NO** — `e_strprint_hex` caught it |

The squelch control is the one worth keeping. The driver sent five events into a budget of
three, so the token count walked 2000, 1000, 0, -1000, -2000 and **never reached
`LOWER_THRESHOLD`**: the clamp was translated, looked exercised, and was not. Eight events reach
-3000 and stay there, and the control then fires on exactly those two lines. A control that
passes is a finding about the driver, not a pass.

The `%llX` control is the division between the two gates working as intended: this configuration
has one core, so the affinity mask fits in 32 bits and the truncation agrees with C — right up
to the first machine with more than four of them.

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

**ONE THING THIS GATE CANNOT COMPARE, AND IT IS STRUCTURAL.** A NASA diagnostic that prints a
POINTER is outside the method. `cfe_sb_init.c`'s pool-create failure logs

```c
CFE_ES_WriteToSysLog("%s: PoolCreate failed for SB Buffers, gave adr 0x%lx,size %d,stat=0x%x\n",
                     __func__, (unsigned long)CFE_SB_Global.Mem.Partition.Data, ...);
```

and that `%lx` is the partition's ADDRESS. This gate runs NASA's C on the host and the
translation under QEMU, in different address spaces, so the two transcripts cannot agree however
correct both sides are — and NASA's C is compiled UNMODIFIED here, so the format is not ours to
change. The consequence is narrow and worth stating plainly: **that one failure path is not
driven**, and `check_coverage` still requires the function to exist and `check_signatures` still
requires its shape. The mutex-failure path beside it IS driven, because its diagnostic carries
only an integer. Any future path whose log prints an address or a `__func__`-derived pointer has
the same limit.

Fourteen properties are gated independently, because each is blind to what the others catch:

| check | what it proves | what it cannot see |
|---|---|---|
| `check_coverage.py` | every function in a gated NASA source exists in the translation, less the ones a VERIFIED `#if` excludes -- **including the ones whose parameter list wraps**, which for a long time it did not | its arity, its types, its body |
| `check_signatures.py` | arity and pointer-ness match NASA's, per parameter | return types; anything named `*_Impl` |
| `check_seam.py` | the `OS_*_Impl` declarations match NASA's headers, **return type included** | whether a backend obeys them |
| `check_structs.py` | a translated `class` has NASA's fields, in NASA's order | field TYPES, and where the fields actually sit |
| `check_padding.py` | a translated `class` has NASA's BYTE LAYOUT — every offset and the size | whether anything reads those fields correctly |
| `check_fnptr_members.py` | a function-pointer MEMBER has NASA's return kind and parameter count | the parameter TYPES, and the type of any other member |
| `check_constants.py` | every number the translation spells out has NASA's value, INCLUDING the ones NASA spells as enumerators | whether anything uses it, or uses it correctly |
| `check_variadic.py` | a variadic function's declarations agree with NASA's and with each other, and none is called before one is seen | whether the ARGUMENTS at a call site are the right ones |
| `check_wired.py` | every translated file is REACHABLE from a driver, or listed with a reason | whether anything in it is actually called |
| `check_lock_sites.py` | every `CFE_*_{Lock,Unlock}SharedData` call carries NASA's own `__func__` and `__LINE__`, grouped by enclosing function | any other literal at any other call site |
| `check_manifest.py` | everything gated is in NASA's build; reports the covered fraction | nothing about the code itself |
| `check_in_blob.py` | every translated function has an ADDRESS in a driver's binary | whether it is correct, or ever called |
| `check_struct_copy.py` | NO FILE IN `Kernel` copies a class into an array slot or through a bare pointer, with **every right-hand side resolved to a declared type** and an unresolved one a FAILURE | whether the copy is reached, and the two destination forms it has MEASURED to be safe |
| the transcript | behaviour, byte for byte against NASA's own C | anything nothing calls |

`check_struct_copy.py` is the newest, and it exists because the compiler loses twelve bytes of
a twelve-byte struct without saying so. `arr[i] = s` and `*p = s` copy only the first EIGHT
BYTES of a class; `var = s`, `var.member = s` and `ptr->member = s` are whole
(docs/HOLYC_STRUCT_LIMITS.md #21). `cfe_es_perf.c`'s capture path stored a performance log
entry that way and **the hardware timestamp never arrived** -- every entry of every capture had
a zero timestamp, which is the one thing a performance log is for. Nothing else here could see
it: the layout matched, the signatures matched, the function was in the blob. The defect is in
the STORE, not in any declaration, so only the transcript noticed. The gate reads the class
list out of the tree rather than carrying one, and was shown against NASA's own line -- and
against the same line WRAPPED, because it matches statements rather than lines and the
formatter wraps at about 96 characters.

**And then it missed the second instance, which is the more useful story.** `cfe_es_appctrl.c`
copies a departing app's 344-byte start parameters through a bare pointer so they can be used
to start it again; the gate reported `none of them a class copy` with a reassuring count while
that line was present. Three holes, all the same hole: a pointer declaration (`CFE_ES_AppRecord_t
*AppRecPtr`) was not recognised as a declaration at all, an unresolvable base name was skipped
*without being counted*, and resolution stopped at the base rather than following `x->member`
through the class body it had already parsed. There was a fourth: the failure path printed an
undefined variable, so the gate would have raised `NameError` instead of reporting a finding --
it had been driven to failure once, before its matcher moved from lines to statements, and never
again. It now parses declarations with pointer depth (locals, parameters, comma-separated
declarator lists, function-pointer declarators), follows member accesses through the class
bodies including the `.HH` headers where the kernel declares most of its classes, and treats an
unresolved right-hand side as a failure with the name printed. All four failure modes are
driven on purpose.

Two of its rules are now MEASUREMENTS rather than arithmetic, because
`tests/exec/cases/e_struct_copy_into_slot.hc` runs them: `arr[i].member = s` is a whole copy
although its address is computed, and a class *narrower* than the store is written at its own
width without touching the neighbouring slots. The second is why the one exemption is allowed --
`CFE_SBR_MSGMAP[hash] = RouteId`, a 2-byte class in an array of them, which an 8-byte store
would have corrupted three slots at a time.

**`check_coverage.py` had the same shape of hole, found while this one was being fixed.** Its C
pattern was applied one line at a time, and NASA's style aligns parameter names in a column, so
any definition spread over several lines was outside the set it compared. Thirty-nine of them:
four in `cfe_es_appctrl.c`, plus `CFE_EVS_SendEventWithAppID`, `CFE_SB_SubscribeFull`,
`EVS_GenerateEventTelemetry`, `CFE_ES_CreateChildTask` and thirty-one more. Every one was
already translated -- the gate was not wrong about what it compared, it was quiet about what it
could not see -- and the count went from 494 to **533** the moment it could. The HolyC side
needed no change: its pattern runs over the whole file with `re.M`, and `[^;]` matches a
newline where `.` would not.

**It is the one gate that is not about the translation.** This is a compiler defect, and
`arr[i] = someStruct` is an ordinary idiom, so it scans all of `Kernel` -- 249 indexed or
dereferenced assignments across 322 files -- not just `Kernel/Cfs`. The rest of the kernel was
already clean; the only instance anywhere was the one the transcript caught.

`check_in_blob.py` is the first gate that opens the BINARY. Every other
one on the list reads source text -- `check_coverage` counts definitions, `check_signatures`
compares parameter lists, `check_constants` reads `#define`s, `check_lock_sites` reads literals
at call sites -- so a file can be included, parse cleanly, pass all of them and contribute
NOTHING. That is limit #13 in `docs/HOLYC_STRUCT_LIMITS.md`, and it has happened twice:
`cfe_time_api.HC` lost all forty-six of its functions to a re-included sibling, and
`cfe_es_task.HC` lost all twenty-eight the same way. **Both times what noticed was luck** --
once the import trailer, because something happened to CALL a missing function; once a
compiler error five hundred lines away, because the file happened to owe the driver a type. A
file of ground-command handlers offers neither tell: nothing calls them and nothing needs a
type from them. Planting the re-include back makes this gate name the file, the count and the
first and last function missing, while every other gate still passes.

`check_lock_sites.py` exists because HolyC has no `__func__` and no
`__LINE__`. NASA writes `CFE_ES_LockSharedData(__func__, __LINE__)`, and BOTH arguments reach
the transcript when the mutex take fails. The translation writes them out as literals -- which
turns them into ordinary constants, and a constant nobody compares drifts. All 117 of them were
written as 0, and nothing in the list above could see it: `check_signatures` compares types,
`check_constants` reads `#define`s, and a literal argument at a call site is neither. It took a
probe that forced the mutex to fail -- `Line=748` on NASA's side against `Line=0` on the
translation's -- for it to show at all.

`check_wired.py` closes a hole the other ten share by construction: all of
them are driven from `SRC_C`, the list of NASA sources the smoke script compiles, so they
measure the translation only where the C half names a counterpart. A `.HC` file that is
complete, parses, and is included by NOBODY is invisible to every one of them except
`check_padding`, which scans the tree. `cfe_sb_api.HC` spent one commit in exactly that state.
A file is now either in a driver's include closure or in `UNWIRED_OK` with a reason, and both
directions fail: a stale entry for a file that IS wired now is as much a failure as an unlisted
one. Its own first run found the hole one level up — the driver roots were hardcoded, two of
them, and there are three.

`check_constants.py` exists because HolyC has neither `enum` nor CMake: the
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

## TBL'S CORE IS ONE CALL CYCLE, and the way in is a trade-off curve, not a single answer

`tools/cfs/module_deps.py` builds a module's cross-source call graph and reduces it to
strongly connected components. tbl's core is one component of eight sources, 3,900 lines.

**A cycle is not a wall, and the calibration run proved it.** Run `--fresh` (pretend nothing is
gated) and **ES comes back as a TWELVE-source cycle** — and ES was gated one source at a time,
with stubs deleted in batches later. EVS is genuinely acyclic: seven singletons. So the tool
discriminates, and what it reports is the SHAPE; the cost of an incremental path through a
cycle is the stand-ins it forces.

**`--cuts` prices that path.** For each number of stand-ins, it enumerates every subset and
reports the SMALLEST group that price buys:

| stand-ins | lines | group |
|---|---|---|
| 3 | 194 | `accdesc` |
| 4 | **1027** | **`loadbuff` + `regrec`** |
| 5 | 694 | `passthru_codec` + `regrec` |
| 6 | 430 | `transaction` |
| 2 | 3338 | six of the eight |

Ranking by stand-in count alone crowns a 3,619-line group because it happens to need one stub,
which is useless advice. The curve is the output; the judgement is the reader's.

**And the judgement is per edge: is the stand-in a SEAM, or upstream LOGIC?**

| gating this first | needs stand-ins for | verdict |
|---|---|---|
| `cfe_es_apps.c` | `StartAppTask`, `AppCreate`, `CleanUpApp` — things the driver supplies anyway | stubs were right |
| `cfe_tbl_regrec.c` **alone** | `CFE_TBL_LocateLoadBufferByID`, `CFE_TBL_GetNextLocalBufferId` | stubs are **wrong** |
| `loadbuff` + `regrec` **together** | `AcquireGlobalLoadBuff`, `ForeachAccessDescriptor`, `TxnAddEvent`, `SendTransactionEvents` | stubs are fine |

Those two regrec needs are not a seam: both implement a buffer-id **serial encoding** — a
category field separating the shared load buffers from a table's own dedicated one, packed into
the resource id. Copying that into the differential driver puts upstream logic where no gate
compares it against NASA, which is worse than a stub because it *looks like a translation*.
**Gating loadbuff and regrec as a pair makes both of them real**, and the four stand-ins that
remain are all thin: a mutex-and-delegate wrapper, a list walk, a record-append, and the EVS
seam. Same cycle, 1,027 lines instead of 3,900 — a difference invisible without enumerating.

So the order is `accdesc` (**done**), then `loadbuff + regrec`, then the rest, then the three
large consumers `api.c`, `task_cmds.c`, `load.c`.

**One decision to make BEFORE writing `loadbuff + regrec`, not during it.** Of its four
stand-ins, `CFE_TBL_ForeachAccessDescriptor` must be written FAITHFULLY — an eight-line walk
of the handle list — and not as a call counter. With `accdesc` gated,
`CFE_TBL_LocateAccDescByHandle` is real, so that walk calls only gated code and costs nothing;
it was not available two commits ago. If it is stubbed as a counter instead, the
`CheckInactiveBufferHelper` path is never entered, and with it
`CFE_TBL_GetInactiveBufferExclusive`'s locked-buffer branch — the one that refuses to reuse a
buffer another app still holds — becomes unreachable and the exercise asserts nothing about
it. That is the recorded trap of a fault-injection knob vanishing with the stub, and it is
cheapest to avoid by deciding now. `CFE_TBL_AcquireGlobalLoadBuff` is the same story once
loadbuff lands: `FindNextSharedBufferId` and `LocateLoadBufferByID` both become real. Everything outside the cycle is
already done: `handlelink.c`, `dumpctl.c`, `objtab.c`, and the whole type foundation.

### THE LAST TWO SOURCES, SURVEYED AND PRICED

`internal.c` and `registry.c` are all that remain of the cycle, and the order is not close:

| gate first | stand-ins | lines | of those, NEW |
|---|---|---|---|
| **`internal.c`** | 2 | 1,256 | **0** — both already in the driver |
| `registry.c` | 9 | 431 | 9, and several are LOGIC not seams |

`registry.c` would need stand-ins for `ValidateTableName`, `ValidateTableOptions`,
`ValidateTableSize` and the handle-list surgery (`HandleListInsertLink`/`RemoveLink`) — all
upstream logic, the trap this plan already records twice. `internal.c` needs only
`CFE_TBL_TxnFindRegByName` and `CFE_TBL_TxnLockRegistry`, both already written faithfully.

**`internal.c` has ZERO missing dependencies.** Of its 72 external calls, 71 are already
translated; the one gap is `CFE_TBL_HandleID_AsInt`, a typed-id wrapper that collapses onto
`CFE_ResourceId_ToInteger` under `check_header_inlines`'s existing rule.

**Gating it DELETES two stand-ins** — `CFE_TBL_ForeachAccessDescriptor` and
`CFE_TBL_AcquireGlobalLoadBuff` both live there — so expect the witness-moves-with-the-stub
dance a third time. `tbl_foreach_visits` disappears; what replaces it is whatever the real
`CFE_TBL_UpdateInternal` and `CFE_TBL_CleanUpApp` paths produce.

Constants resolved while surveying, so nobody repeats it:

```
CFE_TBL_ERR_NO_BUFFER_AVAIL    0xCC00000F   CFE_TBL_INFO_NO_UPDATE_PENDING 0x4C000017
CFE_TBL_INFO_TABLE_LOCKED      0x4C000018   CFE_TBL_ERR_INVALID_SIZE       0xCC000003
CFE_TBL_ERR_INVALID_OPTIONS    0xCC000025   CFE_TBL_INFO_RECOVERED_TBL     0x4C000027
CFE_STATUS_INCORRECT_STATE     0xC8000009   CFE_ES_CDS_ALREADY_EXISTS      0x4400000D
CFE_TBL_FAIL_NOTIFY_SEND_ERR_EID  89        CFE_MISSION_TBL_MAX_NAME_LENGTH  16
CFE_TBL_OPT_BUFFER_MSK 0x1  DBL_BUFFER 0x1  LD_DMP_MSK 0x2  DUMP_ONLY 0x2
CFE_TBL_OPT_USR_DEF_MSK 0x4 USR_DEF_ADDR 0x6  CRITICAL_MSK 0x8  CRITICAL 0x8
```

Two translation notes found in the reading. `CFE_TIME_ZERO_VALUE` is a C compound literal
(`(CFE_TIME_SysTime_t){0, 0}`) and becomes two field assignments. And `CFE_TBL_EarlyInit` is
the function `cfe_tbl_objtab.HC` currently stubs — gating this source makes the object table's
first hook real, which is the point of the whole module.

### THE CYCLE IS GONE (2026-10-05)

Both are gated, and `module_deps.py tbl` now prints **nine sources, every one a singleton with
no CALL CYCLE tag**. The eight-source component that shaped this whole section dissolved the
moment `internal.c` and `registry.c` landed, so what is left can be gated one source at a time
in whatever order suits — the tool's own topological listing is:

| next | lines | note |
|---|---|---|
| ~~`cfe_tbl_dump.c`~~ | ~~589~~ | **GATED** — zero stand-ins; it also found the `size_t` signedness defect below |
| ~~`cfe_tbl_load.c`~~ | ~~952~~ | **GATED** — zero stand-ins. Its exercise builds the table file byte by byte, for the reason in the uninitialised-header section |
| ~~`cfe_tbl_api.c`~~ | ~~1,107~~ | **GATED** — zero stand-ins. Exercised as a LIFECYCLE from the real startup path, and it found the `(I32)` sweep below |
| ~~`cfe_tbl_task_cmds.c`~~ | ~~1,115~~ | **GATED** — zero stand-ins |
| ~~`cfe_tbl_dispatch.c`~~ | ~~275~~ | **GATED** — `CFE_TBL_TaskPipe` is real, so tbl has NO stand-ins left anywhere |
| ~~`cfe_tbl_task.c`~~ | ~~218~~ | **GATED** — `CFE_TBL_TaskMain` is real, so tbl is the first module whose object table names three real functions |
| `cfe_tbl_dispatch.c` | 276 | the non-EDS branch, and LAST: it is blocked behind `task_cmds.c`. One thin stand-in (`CFE_TBL_TaskPipe`) covers it meanwhile |
| `cfe_tbl_load.c` | 953 | |
| `cfe_tbl_api.c` | 1,107 | the public API, 24 functions |
| `cfe_tbl_task_cmds.c` | 1,115 | |

(`cfe_tbl_eds_codec.c` and `cfe_tbl_eds_dispatch.c` are listed too and are correctly absent —
`CFE_EDS_ENABLED` is 0 in this configuration and `check_manifest.py` owns that call.)

**tbl IS DONE: 7,780 of 7,780 lines, 100%** of its fifteen unconditional sources, plus both
non-EDS conditionals (`passthru_codec.c` and `dispatch.c`). The two remaining files are the EDS
variants, which `CFE_EDS_ENABLED` excludes in this configuration and `check_manifest.py` reports
as correctly absent. **No stand-ins remain anywhere in tbl.**

And the whole module is exercised rather than merely compiled: the commands go in through the
real `CFE_TBL_TaskPipe` as messages, so the dispatcher's twelve-row table, its length check and
its three-way error are under test along with the ten handlers beneath them. `registry.c` cost **zero** new stand-ins in the end
and DELETED four: of its 43 external calls 37 were already translated and the other six are id
macros that collapse onto `CFE_ResourceId_IsDefined` / `_Equal` / the identity. The nine-stand-in
price in the table above was real when it was measured and is the clearest demonstration of the
point this section opens with — **a cycle's cost is a function of what is already gated, not a
property of the graph.**

STILL GATED BUT NOT YET EXERCISED, so nobody mistakes 49% for 49% tested:
`CFE_TBL_CleanUpApp`, `CFE_TBL_RestoreTableDataFromCDS`,
`CFE_TBL_UpdateCriticalTblCDS`, `CFE_TBL_RegisterWithCriticalTableRegistry`,
`CFE_TBL_GetWorkingBuffer`, `CFE_TBL_UpdateInternal`, `CFE_TBL_SendNotificationMsg`,
`CFE_TBL_SetupTableBuffers`, `CFE_TBL_AllocateTableLoadBuffer`. `check_in_blob` proves they
have addresses; nothing proves they run.

`CFE_TBL_EarlyInit` is OFF that list as of the same day: it runs three times in the transcript
now (fresh CDS, already-existing CDS, and a mutex that refuses), and ES being 100% gated meant
the 512 KiB partition really is carved up and the critical registry really does round-trip
through the CDS. **Six of the eleven fields the first draft printed were VACUOUS** --
`CFE_RESOURCEID_UNDEFINED` is 0 in this configuration, so "every registry record is free" and
"every critical slot holds the BAD handle" read the same whether the code ran or not, and the
poison-first trick is unavailable because EarlyInit's first act is to zero the whole global.
They were cut. What is left is only what EarlyInit makes NON-zero, plus one content witness:
seed `CritReg[5]` with 0x5151, push it to the CDS, and the next EarlyInit brings it back
AFTER the loop that set every slot to BAD -- so `crit5=0x5151 critbad=31` is the proof the
recovery arm ran, which the return value cannot give because all three CDS outcomes return
CFE_SUCCESS.

A stand-in was improved for it: `OS_MutSemCreate` handed back the SAME id for every call, so
EarlyInit's two mutexes were indistinguishable and a translation that stored one into the
other's field produced a correct-looking transcript. It now returns `0x3000 + n`. Driven as a
control: the swap now fails with `reg=12316 wrk=0`.

### THE TOOL WAS MISSING AN EDGE KIND, AND THE ORDERING ABOVE IS THE SECOND VERSION

`module_deps.py` built its graph from CALLS — `name(`. A function reached as a **reference**,
its bare name taken as an address, was invisible. That is not a corner case: the whole content
of `cfe_tbl_dispatch.c` is `CFE_TBL_CmdHandlerTbl[]`, fourteen
`CFE_TBL_ENTRY(..., CFE_TBL_LoadCmd, ...)` rows naming handlers that live in
`cfe_tbl_task_cmds.c`, and not one of them is spelled with a following paren. So the tool
reported dispatch.c as ready and listed it THIRD in a seven-source ordering, ahead of the
source it cannot be gated without.

Fixed: a bare `CFE_\w+` not followed by `(` is now an edge too, tagged `[&ref]` in the
per-edge listing so a reader can see which kind it is. dispatch.c moves to last, where it
belongs.

**Recalibrated against the finished modules, which is the only way to trust it.** `es --fresh`
now reports a **14**-source cycle where it reported 12 before — so the reference edges found
two more real dependencies in a module that is 100% gated, and the point this section opens
with holds twice over: ES was gated one source at a time out of a cycle the tool calls
inseparable. `tbl --fresh` still reports the same 8-source cycle it always did, which matches
what actually happened.

The caveat this section already records — a stand-in is functions, but a subset may also need
a TYPE it does not define — is the same shape as this bug: a dependency the graph does not
model. Assume there are more.

### A HIGH-BIT STATUS CONSTANT WITHOUT `(I32)` MAKES ITS COMPARISON DEAD CODE

Every cFE error code has the top bit set. `0xCC000002` as a bare HolyC literal is a POSITIVE
64-bit value -- 3,422,552,066 -- and compared against an `I32` status variable, which the
compiler sign-extends to -872,415,230, it is **not equal**. So

```c
if (Status == CFE_TBL_ERR_INVALID_NAME)     /* never taken */
```

The port's convention already handled this: `cfe_evs_task.HC` and `cfe_es_resource.HC` write
theirs as `0xC2000002(I32)` -- a postfix HolyC cast -- and have eleven live comparisons each.
**Thirty constants across ten `cfe_tbl_*.HC` files were written without it.** A local lapse, not
a new idea, swept in one commit.

**Only ONE of the thirty had a comparison that exercised it**, and the symptom was one missing
line out of two thousand: `CFE_TBL_Share`'s "Table '%s' not found in Registry" syslog appeared
on the C side and not the HolyC side, with both halves agreeing on the returned status. The
other twenty-nine were latent -- they will matter the first time `task_cmds.c` or an app
compares against one.

**How to apply:** when translating a `#define` whose value has the high bit set and whose type
is a status, the `(I32)` is not decoration. `grep -rn '^#define.*0x[89A-F]' Kernel/Cfs` finds
the ones that lack it; no gate compares a macro's TYPE, only its value, and
`check_constants.py` normalises both spellings to the same signed number so it cannot see the
difference.

### A SIGNEDNESS DEFECT THE GATES COULD NOT SEE: `size_t` IS UNSIGNED

`CFE_SB_MessageStringSet`'s two size parameters are `size_t` in NASA's source and were `I64` in
the translation. **Three tbl call sites pass `-1` for SourceMaxSize, meaning "no limit"** --
as a `size_t` that is SIZE_MAX, so the copy runs to the NUL. Signed, `SourceMaxSize > 0` is
false on the first test and **nothing is copied at all**.

Latent for the whole port, because no gated caller had passed a negative until
`cfe_tbl_dump.c`. A full scan of cFS finds exactly three such call sites and all three are this
function: dump.c, task_cmds.c and api.c.

`check_signatures` could not see it and still cannot: it maps `size_t`, `CFE_MSG_Size_t` and
`I64` to one `SZ` token, so **the signedness of a size has never been compared**. What found it
was the differential transcript -- `last=/ram/dump.tbl` on the C side against `last=` on the
HolyC side.

Fixed by declaring the two parameters `U64`, which needed a `U64` rule in the gate. **Adding
that rule immediately broke two pairs of signatures that had been AGREEING AS TWO BLANKS**:

| pair | NASA | translation | why it "matched" |
|---|---|---|---|
| `CFE_ES_InitializeFileSystems_{CheckFreeSpace,ReformatVolume}` | `cpuaddr` | `U64` | neither had a rule |
| `OS_{Symbol,ModuleSymbol}Lookup_Impl` | `cpuaddr *` | `U64 *` | neither had a rule |

Both are correct translations; the gate had simply never looked at them. `cpuaddr` and
`cpusize` now have rules, in both the value and pointer forms. **An unrecognised type on both
sides is not a match, it is two gaps of the same shape** -- the same lesson as the
function-pointer edge above, found the same way, within the hour.

### NASA WRITES TWO WORDS OF UNINITIALISED STACK INTO EVERY TABLE DUMP FILE

`CFE_TBL_WriteSnapshotToFile` does

```c
CFE_TBL_CombinedFileHdr_t FileHeader;
memset(&FileHeader, 0, sizeof(CFE_TBL_File_Hdr_t));   /* NOT sizeof(FileHeader) */
```

A `CombinedFileHdr_t` is `CFE_FS_Header_t Std` (64 bytes) followed by `CFE_TBL_File_Hdr_t Tbl`
(52). Clearing 52 bytes **from the front** clears part of `Std` and **none of `Tbl`**. Then
`CFE_FS_InitHeader` overwrites all of `Std`, and the code assigns `Tbl.NumBytes` and
`Tbl.TableName` — but **nothing ever assigns `Tbl.Reserved` or `Tbl.Offset`**.
`CFE_TBL_EncodeHeadersToFile` writes `sizeof(CFE_TBL_File_Hdr_t)` bytes, so both go into the
file.

Measured, by printing the written bytes:

```
C   tbl_dmphdr resv=00000001 off=8d30a184      <- 0x8d30a184 looks like a pointer fragment
HC  tbl_dmphdr resv=00000000 off=00000000
```

The transcript asserted `bytes=148` and nothing about the file's CONTENT, so this was invisible
until the bytes were printed. **It is upstream behaviour, faithfully translated**, and the
translation happening to write zeros is luck, not correctness.

**WHY IT MATTERS FOR `cfe_tbl_load.c`, WHICH IS NEXT.** `CFE_TBL_ReadHeaders` reads `Offset`
and `CFE_TBL_LoadFromFile` decides where the data lands from it. So the obvious exercise --
dump a table, load it back -- is **nondeterministic across the two halves**, and it would
present as a translation bug in load.c's offset handling with the cause two sources away.
**Build the load exercise from a header constructed explicitly**, byte by byte, not from one
round-tripped through a dump.

The transcript now asserts `NumBytes` and `TableName` instead -- the fields that ARE
initialised, which also pin the big-endian byte swap -- with the two garbage fields named in
the comment and deliberately not compared.

### AN OPEN CRASH IN THE C REFERENCE: CFE_SB_DeletePipe

`CFE_SB_DeletePipe` on the pipe `CFE_TBL_TaskInit` creates **segfaults the C oracle**, in
`CFE_SB_GetDestPtr` reading address `0x809` — a MsgId being walked as a pointer. This is
NASA's code compiled natively, not the translation.

The same `CFE_SB_DeletePipe` works earlier in the same transcript (`api_del`), so something
about the route state TaskInit's two `CFE_SB_Subscribe` calls leave behind differs. **Not
diagnosed.** It is recorded here because `dump.c`, `load.c` and `api.c` all create and delete
pipes, and the next exercise that reaches for it would rediscover this from scratch.

It also cost a wrong diagnosis worth remembering: the crash was first blamed on the POWER ON
RESET that `CFE_TBL_TaskMain`'s init-failure path drives, and moving the reset to the end of
the block did not help. An lldb backtrace put the fault before the reset, in DeletePipe itself.
Block-buffered stdout is why the log looked like it stopped 500 lines earlier.

**Run the tool before planning any module's order**, including the apps — and run it `--fresh`
against a finished module first, because a result you cannot calibrate is a number you should
not plan on. One caveat it does not model: a stand-in is functions, but a subset may also need
a TYPE it does not define (both groups above need `CFE_TBL_TxnState_t`). A type is cheap — it
is declared in a `_decl.HC` and `check_padding` then measures it against NASA — but it is not
free, and the tool will not mention it.

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

#### `time`: 100%, and a preprocessor directive that was never evaluated

`cfe_time_tone.c` (1,333), `cfe_time_task.c` (1,234), `cfe_time_dispatch.c` (294) and
`cfe_time_objtab.c` (38) complete the module. The transcript goes 657 → **728 lines**, and the 48
new ones are TIME's own behaviour rather than TIME seen through someone else's housekeeping —
which is what it was before. That gap is worth naming: `cfe_time_api.c` and `cfe_time_utils.c`
had been gated for coverage, signatures, constants and byte layout while the only things CALLING
them were `CFE_SB_TimeStampMsg` and a handful of rendered timestamps. Six of the nine properties
were green on a module nothing drove.

The new block drives it directly, and the local clock is a variable in the driver
(`evs_psp_ns`), so every number is determined. Three tone interrupts — one that establishes the
previous latch, one a clean second later, one only half a second later — then `ToneSend` building
the time-at-the-tone packet, `ToneData` accepting it, the IDENTICAL pair being rejected by
NASA's two function-static `PrevTime1`/`PrevTime2`, both 1Hz child-task loops run to their own
`OS_BinSemTake` failure, flywheel entry by `START_FLY` and the time-at-tone roll-forward by
`LATCH_FLY`, the synch callback through a function pointer, and the dispatcher's two levels of
routing including a wrong length, an unknown command code and an unknown message id.

**THE ONE THAT MATTERS MOST: `#if <expr>` IS UNCONDITIONALLY TRUE IN THIS COMPILER.** The three
new sources carry 35 configuration directives and the first version of the translation kept them.
`host/lexer.c` evaluates only a literal `0`, so every one of them was compiled in — the time-CLIENT
branches and the three external-source branches included — and the blob referenced
`CFE_TIME_SetDelay`, `CFE_TIME_SetSignal`, `CFE_TIME_SetSource`, `OS_GetLocalMET` and
`OS_SelectTone`, none of which this port builds. **The blob's import trailer caught it and nothing
else would have**, because each of those is a name a C runtime could plausibly bind. The same
directive makes `#define _CFG_HEAP_DBG FALSE` a no-op in `Kernel/KernelA.HH`, so this kernel runs
with 48-byte `CMemUsed` headers where its configuration asks for 16 — **measured both ways**, not
inferred, because the thing in question is how this compiler reads text.
`docs/HOLYC_STRUCT_LIMITS.md` #15 has the mechanism, the gate, the two measured layouts and what
to establish a baseline for before implementing it.

**Three defects the gates found on the way in, each in a different gate's blind spot:**

- `CFE_TIME_SynchCallbackRegEntry_t.Ptr` was `U0 (*)()` and NASA's is `int32 (*)(void)`. A
  function pointer is eight bytes either way, so `check_structs` and `check_padding` agreed;
  `check_signatures` reads function PARAMETERS, not the types of class members. What refused it
  was the C compiler, on the oracle's side, when the driver assigned a real callback.
- `int16` on NASA's side and `I16` on the translation's **both normalised to nothing**, so they
  matched by being equally invisible — and so would a parameter whose width or signedness was
  wrong. Both have a token now, and the three `*Impl` helpers in `cfe_time_task.c` turned red:
  NASA's `Direction` there is `CFE_TIME_AdjustDirection_Enum_t`, a **uint8**, while
  `cfe_time_utils.c` really does declare `int16`. The translation had written `I16` in all five by
  analogy.
- The driver's own tone steps were 100× too large. One second is 10,000,000 ticks, not
  1,000,000,000, because a tick is 100 ns — so every tone fell outside the validation window and
  came back INVALID, which reads exactly like a translation defect and was arithmetic in the
  test.

HolyC has no `static` on a FUNCTION either (distinct from #12, which was about a static LOCAL):
the compiler refuses the declaration, so `cfe_time_task.c`'s five `TaskInit_*` helpers lose the
keyword and have unit scope instead of file scope, which is the deviation `cfe_evs_utils.HC`'s
`EVS_*` helpers already carry.

#### `time`: how the first half landed, and the two gates that had to grow to take it

`cfe_time_api.c` (737) and `cfe_time_utils.c` (1,041) are gated — 1,778 of 4,383 lines. The
remaining three are `cfe_time_task.c` (1,234), `cfe_time_tone.c` (1,333) and `cfe_time_objtab.c`
(38). `api` and `utils` are translatable without the other two because all three
`CFE_PLATFORM_TIME_CFG_SRC_*` switches are 0 in this configuration, so `api`'s calls into `tone`
are compiled out and `utils` has no dependency on either.

Wiring it in removed the last two stubs that were already INSIDE the comparison:
`CFE_TIME_GetTime` and `CFE_TIME_Print`. Every `1980-001-00:00:00.00000` in the transcript is now
rendered by translated code — and `CFE_TIME_Print` is the module's one real deviation, because
NASA's calls `gmtime_r` and `strftime` and this port has no libc. The calendar conversion is
written out: a proleptic-Gregorian leap rule, a year-at-a-time walk from the UNIX epoch, and a
fixed-width decimal writer. `%j` is a day of YEAR, so no month table is needed. What makes that
safe to claim is that the C half of the oracle still calls glibc's, on every timestamp in 657
lines.

**Two gates had to grow, and both growths immediately found something.**

`check_coverage.py` reported six functions absent that are absent on BOTH sides — whole-function
`#if` bodies this configuration does not build. It now has a `CONFIG_EXCLUDED` list, and the
guard of every entry is EVALUATED with the host C preprocessor: an entry whose macro is true is a
FAILURE, so the list cannot become a place to hide a function that really is missing. Pinning one
entry to `CFE_PLATFORM_TIME_CFG_SERVER` (which is 1) makes the gate red, as it should.

`check_constants.py` could not see an ENUMERATOR. Its probe wrapped every name in `#ifdef`, which
is false for an enum member, so every constant NASA spells as an enumerator came back undefined,
was classified as "a name this port invented", and was never compared. That is **160 of 601
names**, and the bug it hid is the sharpest in this file:

```
OS_TIME_TICK_RESOLUTION_NS   translation 1            NASA 100
OS_TIME_TICKS_PER_SECOND     translation 1000000000   NASA 10000000
```

A tick is 100 nanoseconds, not one. `os_shared_clock.HC` said one for several commits and it cost
nothing, because nothing divided by it — until `CFE_TIME_LatchClock` did, and the transcript
printed `00:00:01` against `00:01:40`. The tool now retries the undefined set as EXPRESSIONS, and
the retry is a BISECT rather than a parse of clang's diagnostics: parsing was the first attempt
and it silently did nothing, because clang stops after nineteen errors and not every failure is
an "undeclared identifier". The compared count went 373 → **552** over four steps -- the enum pass, then evaluating the
parenthesised `#define`s with the TRANSLATION's own numbers (compiling them as C would prove
nothing: C's headers would supply NASA's value for every name inside, so the answer would come
back NASA's by construction), then making that expansion recursive for the fifteen-deep
`OS_*_BASE` chain. Three expressions still resist and are printed on every run. Three more wrong
numbers fell out immediately:

```
CFE_ES_RunStatus_CORE_APP_INIT_ERROR      5  NASA: 8
CFE_ES_RunStatus_CORE_APP_RUNTIME_ERROR   6  NASA: 9
CFE_ES_SystemState_CORE_READY             2  NASA: 3
```

All three are passed to `CFE_ES_ExitApp` and `CFE_ES_WaitForSystemState`, which the driver stubs,
so the transcript was never going to see them.

**And one compiler bug the transcript caught that nothing else could.** `CFE_TIME_UnixToCalendar`
incremented its year with `Y++`, and the increment was silently dropped — every year treated as
365 days, so the walk from 1970 ended where it started and `CFE_TIME_Print` returned `1970-003`.

The cause is `docs/HOLYC_STRUCT_LIMITS.md` #14: HolyC lets an x86 instruction be written bare at
statement start, `parser.c` recognised one by its SHAPE — an all-upper-case name whose next token
was not one of `( = ; . -> , )` — and `Y` is all upper case, so `Y++;` was an opcode with an
operand and the whole line was skipped with a clean exit. It affects **locals only**, measured
with five one-function probes against the pre-fix compiler: a global has a hash entry and never
reaches that branch, which is why `CFG_ARR[0] = 11;` has been in this very oracle for several
commits with a byte-identical transcript. Nothing in this kernel names a LOCAL in capitals and
cFS does it exactly once — this function. Fixed in the compiler, and the translation is back to
NASA's exact spelling with the reason recorded at the site.

What is worth carrying forward is that **the transcript was the only thing that could have found
it.** Six of the nine properties look at shape — a name exists, an arity matches, an offset is
right — and all six were green, because the declaration and the layout were never wrong. The
seventh ran the code and compared a string against glibc's, and the string was a plausible date.

---

## The apps layer, and why MD goes first

The eleven cFE core modules and OSAL are at 100%. The next layer up is the cFS *apps* — the
mission software that sits on top of cFE. They are separate NASA repositories, so the first
question was which one, and the survey rejected one outright.

**SCH is not translatable against this cFE.** It makes 17 calls into the cFE **6.x** API that
Draco removed: `CFE_SB_SendMsg`, `CFE_SB_RcvMsg`, `CFE_SB_InitMsg`, `CFE_SB_GetMsgId`,
`CFE_SB_GetCmdCode`, `CFE_SB_GetTotalMsgLength`, `CFE_ES_RegisterApp`. The app was abandoned at
tag 2.2.2 with no Draco-era branch. A 1:1 translation would not compile, and supplying the old
API would be hand-written compatibility code rather than a translation of anything — the one
thing this project does not do. CS, LC, MM and MD all have **zero** old-API hits.

**MD (Memory Dwell) is the first app.** 2,401 lines across seven sources, API-current, and it
leans hard on the `tbl` module that just reached 100% — four dwell tables registered, validated,
loaded and updated through `CFE_TBL_*`. It has the same `md_dispatch.c` / `md_eds_dispatch.c`
EDS-conditional pair `check_manifest` already understands. Pinned in `tools/cfs/fetch.sh` at
`65eb7b3b` on the dev branch, for the same reason cFE is pinned there: cFE here is 7.0.1+dev,
dated one day *after* this MD commit, and MD's v7.0.1 tag predates both.

Of MD's 36 distinct cFE/OSAL calls, **exactly three** have no counterpart in the tree:
`CFE_PSP_MemRead8`, `CFE_PSP_MemRead16` and `CFE_PSP_MemRead32`. Everything else — including
`CFE_TBL_GetAddress`, `CFE_TBL_GetStatus`, `CFE_TBL_ReleaseAddress`, `CFE_PSP_MemValidateRange`,
`OS_SymbolLookup` and the `CFE_MSG_PTR` macro — is already present.

### The blocking design decision: dwell addresses in the transcript

MD's whole job is to read arbitrary memory addresses and telemeter the contents, so the question
of whether an address can reach the transcript had to be answered before writing a line. Two
answers, and they differ:

- **The dwell packet does not carry addresses.** `MD_DwellPkt_Payload_t` is `TableId`,
  `AddrCount`, `ByteCount`, `Rate`, `Signature` and `Data[]` — the dwelled *bytes*. The resolved
  addresses live only in `MD_DwellControlEntry_t.ResolvedAddress`, which is internal state.
- **NASA's own event text does.** `md_cmds.c` prints `"Jam Cmd rejected because address 0x%08X
  is not in a valid range"` and two alignment variants, straight from `ResolvedAddr`. A `cpuaddr`
  formatted into an event string is compared character for character by the transcript, and a
  host process and a QEMU guest will never agree on a real one. This is the third time an address
  has threatened the transcript (`Addr 0x10458D610`, `last=Addr 0x102F99610` were the first two).

The fix is not to normalise the transcript — it is to choose addresses the two halves agree on.
`MD_ResolveSymAddr` returns `SymAddr->Offset` **verbatim** as the address when `SymName` is the
empty string, with no symbol lookup at all. So a dwell entry written with an empty `SymName` and
`Offset = 0x00010000` resolves to exactly `0x00010000` on both halves, and NASA's `0x%08X` prints
the same eight characters on both.

That makes the dwell window **simulated hardware**, which is the pattern the driver already uses
for the other 22 `CFE_PSP_*` functions:

- A fixed literal base, the same constant in both halves, naming a window that is not a real
  address on either.
- `CFE_PSP_MemRead8/16/32` resolve an address inside that window to an index into a
  driver-owned buffer with a known fill pattern, so the dwell `Data[]` bytes are deterministic
  and identical. An address outside the window is an error, which is a path worth exercising.
- `CFE_PSP_MemValidateRange` accepts exactly that window — it is already a driver stub with a
  settable return code and a call counter, so the invalid-range event is reachable on purpose.
- `OS_SymbolLookup` is translated and its `_Impl` is a driver seam, so the non-empty-`SymName`
  branch is reachable both ways: resolving to the window, and failing deterministically to
  produce `"symbolic address '%s' couldn't be resolved"`.

### MD_INTERFACE_SIGNATURE_OPTION is a trap, not a switch

`MD_INTERFACE_SIGNATURE_OPTION` guards a conditional **member** — `char Signature[...]` — in
three structures (`MD_DwellTableLoad_t`, `MD_DwellPkt_Payload_t`, `MD_DwellPacketControl_t`), a
whole command payload type (`MD_CmdSetSignature_Payload_t`), and a command code. It resolves
through `MD_INTERFACE_CFGVAL(SIGNATURE_OPTION)` to `DEFAULT_MD_INTERFACE_SIGNATURE_OPTION`,
which is **1**, so the member is present in this configuration.

Which is the dangerous case. `docs/HOLYC_STRUCT_LIMITS.md` #19 records that `#if <expr>` is
unconditionally true in HolyC unless the operand is a literal `0` — so the HolyC half would take
the `== 1` branch *whatever the value was*. Here it happens to be the right branch, and the two
sides would agree **by accident**: nothing would fail, and the agreement would not mean the
configuration had been read. Every one of these `#if`s is therefore hand-resolved to the branch
this configuration takes, with the value stated at the site, the same way the other config
exclusions are recorded. `MD_INTERFACE_ENFORCE_DWORD_ALIGN` is 1 and gets the same treatment —
note that its `#if ... == 0` branch in `md_cmds.c` is the one with NASA's own stale `Jam->` typo
where the live branch says `Msg->`, which is itself evidence that branch is never compiled.

### config/ ships two header sets — and the obvious worry about that is wrong

`vendor/MD/config/` holds both `default_md_*.h` and `eds_md_*.h`, and the first thing written
here was that they declare the same type names with different layouts, so a gate scanning
`config/` as a bare directory could pair an MD class against the EDS header and report a match
for the wrong struct. **Measured, that is false.** All 52 `eds_*.h` across `vendor/cFE` and
`vendor/MD` declare *zero* structs: each is a one-line forwarder to a generated header
(`md_eds_typedefs.h` and its kin) that CMake emits only under `CFE_EDS_ENABLED`, and which is
in no source tree here. `default_md_tblstruct.h` is 58 lines and `eds_md_tblstruct.h` is 26, but
the 26 are a licence header and an `#include`.

So the collision was never possible, and the reason is that the EDS headers have no types — not
that anything filters them. `check_structs.py` skips them anyway, labelled in the file as a
no-op guard against a configuration this port does not build, precisely so nobody later reads
that filter as evidence a wrong pairing was prevented. A guard believed to protect something it
cannot is the same vacuous shape as a gate that passes on what it cannot find.

### The manifest has three groups, not one

MD's `CMakeLists.txt` builds two different products. `add_cfe_app` takes five unconditional
sources plus the EDS pair; `add_cfe_tables` takes `md_dw01.c` .. `md_dw04.c`, 280 lines that are
compiled and then run through `elf2cfetbl` to emit `.tbl` load files. Those four are not app
code — they contain no functions, just a file-scope aggregate initialiser and a
`CFE_TBL_FILEDEF` macro — so they are a separate manifest group that does **not** count toward
app coverage, with the reason stated. (A file-scope aggregate initialiser is also something
HolyC does not have; if they are ever translated they become runtime fill functions, the shape
`cfe_platformcfg_tables.HC` already uses for `CFE_PlatformConfigTablesInit`.)

### Widening the gates is where the blind spot gets made

Eight gates are hard-wired to `Kernel/Cfs/{cfe,osal}` and `vendor/{cFE,osal}`. Widening all of
them before any MD exists in the tree would report exactly what they reported yesterday — a
vacuous green, of which `gate-blindspot-unpaired-types.md` already has fourteen. So MD is
translated **leaf first** (`md_utils.c`, 224 lines) and each gate is widened with that file as
its subject and a real mutation driven through it.

Three widenings fail completely silently if done wrong:

| gate | what "widened but blind" looks like |
|---|---|
| `check_constants` | `NAME` is `^(CFE_\|OS_\|OSAL_)\w+$`. Without `MD_`, no MD constant is even a candidate and the count does not move. |
| `check_padding` | `CSRC`/`HDRS` are explicit lists. Not added is not measured, and nothing complains. |
| `check_structs` | MD classes land in the unpaired bucket, which prints as a number in a line that is easy to skim. |

`module_deps.py --fresh` is run on MD before picking the source order: CMake's `APP_SRC_FILES`
order is a build-order hint, not the dependency graph.

### md_utils.c is gated, and five mutations say the transcript sees it

**2,167 transcript lines identical**, up from 2,149 — eighteen new lines, byte-identical on the
first run. Nine functions: `MD_TableIsInMask`, `MD_UpdateDwellControlInfo`, `MD_ValidEntryId`,
`MD_ValidAddrRange`, `MD_ValidTableId`, `MD_ValidFieldLength`, `MD_Verify32Aligned`,
`MD_Verify16Aligned`, `MD_ResolveSymAddr`.

Every address in the exercise is a literal constant, which is what makes the block possible at
all: `MD_ResolveSymAddr` returns `Offset` verbatim for an empty `SymName`, so `md_resolve_off 1
1048640` is `0x00100040` on both halves rather than a host pointer against a guest one.

Five mutations driven through `md_utils.HC`, each reverted:

| mutation | what the transcript said |
|---|---|
| shift unconditionally (drop the `TableId == 1` guard) | `md_mask 1 1000` → `0000`, and two more lines |
| `MD_Verify32Aligned` drops the **size** branch | `md_a32 1001` → `1011` — only the `(8, 6)` case |
| sum `Length` as 1 per entry instead of its width | `md_dwell_sum 0 3 7 60` → `3 3 60` |
| failure branch of `MD_ResolveSymAddr` writes the caller's variable | `md_resolve_fail 0 57005` → `0 0` |
| drop `FieldLength == 4` | `md_fieldlen 111010` → `111000` |

The fourth is the one worth keeping. **Its return value did not change** — `0` before and after,
because the function did still report failure. What caught it was the second field: the
caller's `ResolvedAddr` still holding `0xDEAD`. A control that had only compared the boolean
would have passed on a function that silently clobbers its output parameter.

The size branch is the second: NASA checks the address *and then the size*, so `(8, 6)` must be
rejected on the size alone. An exercise that only ever moved the address would never have
distinguished the two arms.

### Three gate defects this one 224-line file found

**1. `check_padding` measured 358 classes while `check_structs` compared 380, and said OK.** The
HC directory list was spelled out in seven gates; `Kernel/Cfs/md` joined one of them.
`check_padding` holds a guard for exactly this — *"the two struct gates must cover the SAME
set"* — and it could not fire, because `pairs` is built by pairing `check_structs`' NASA structs
against `check_padding`'s **own** class list, so both sides of the comparison were the same 358
and the 22 unmeasured MD classes were invisible to it. **A cross-check between two tools is
worth only the inputs they do not share.** The list now lives once, in `tools/cfs/cfs_dirs.py`,
imported by all eight. `check_wired.py` stays as it is on purpose: it *walks* `Kernel/Cfs`, which
is why it was the gate that caught `md_*.HC` being unreachable from any driver — it had no list
to forget to update.

**2. `check_structs`' field regex could not read a subscript on the next line.** NASA writes

```c
    char MD_TableName[MD_INTERFACE_NUM_DWELL_TABLES]
                     [CFE_MISSION_TBL_MAX_NAME_LENGTH + 1];
```

and the subscript group allowed no whitespace between the brackets, so NASA's side came back one
field short and the gate reported **the translation** as carrying an extra member it correctly
has. Fourth time that regex has blamed the translation for a spelling it could not read, and the
first found by an app: nothing in cFE or OSAL wraps a declaration that way, which is why the fix
is byte-for-byte invisible across the 358 classes already being compared.

**3. `check_constants`' name filter made every MD constant a non-candidate.** `NAME` was
`^(CFE_|OS_|OSAL_)\w+$`. Without `MD_`, the compared count would not have moved by one and
nothing would have said so. Now 1,267 compared, up from 1,248 — nineteen MD constants — with no
MD name in the "NASA does not define" bucket, which is the bucket that *passes*.

That third one closes limit #19 for MD, which matters more than the count. `#if <expr>` is
unconditionally true in HolyC, so the hand-resolved `MD_INTERFACE_SIGNATURE_OPTION == 1` and
`MD_INTERFACE_ENFORCE_DWORD_ALIGN == 1` branches would stay silently correct even if NASA
changed the value. They are now *anchored*: both names exist as constants this gate compares
against NASA's header, and driving each to the wrong value fails the gate —

```
MD_INTERFACE_SIGNATURE_FIELD_LENGTH          md_msg.HC: 31   NASA: 32
MD_INTERFACE_ENFORCE_DWORD_ALIGN             md_msg.HC: 0    NASA: 1
```

### Two seams, both supplied rather than translated

`OS_SymbolLookup` is a stub in both halves of this driver. The cFE translation sees OSAL only
through its API — the case includes OSAL's module *types* (`osapi_module_decl.HC`) and none of
its code, which is what `check_seam` exists to keep true — and `osapi-module.c` *is* translated
and *is* gated, by `run_osal_xlat_smoke.sh`. Supplying it here is what makes
`MD_ResolveSymAddr`'s symbol branch reachable at all; `md_sym_rc` picks success or failure.

`CFE_PSP_MemValidateRange` was already a driver stub with a settable return code **and a call
counter**, and the counter is the part that earns its place: `MD_ValidAddrRange` is a one-line
wrapper, so a stub returning a constant would satisfy both booleans on its own. `calls=2` is
what says the call was really made.

### MD's manifest, and what the percentage does not include

```
    MD            5 uncond   2115 lines     224 gated ( 11%)
        add_cfe_tables: 4 file(s), 280 lines -- a .tbl build product,
        not app code (no functions; a file-scope initialiser and CFE_TBL_FILEDEF).
```

`md_dw01.c` .. `md_dw04.c` are compiled and then run through `elf2cfetbl` to emit `.tbl` load
files. Folding them into the denominator would make one percentage mean two things, and dropping
them silently would be the usual mistake, so they are a separate reported group.

### And `config/` needed the same shim treatment cFE got

MD's sources include `md_msgids.h`, `md_msgstruct.h`, `md_tbldefs.h` and twelve more that exist
nowhere: CMake generates a one-line forwarder per header choosing between the `default_` and
`eds_` set. Fifteen of them are now in `vendor/shim` beside the 73 cFE ones, each a single
`#include "default_md_*.h"`, which *is* the configuration decision — `CFE_EDS_ENABLED` is off.

---

## Two gate holes the first app exposed, neither of them about MD

### Every struct-pointer parameter in cFS was interchangeable

`check_signatures` normalised `CFE_\w+_t *` to `PTRNUM` on NASA's side and `CFE_\w+ *` to
`PTRNUM` on the translation's. Both rules throw the **struct's identity** away, and they do it on
both sides at once, so the two always agreed. Three mutations, all of which the gate passed
while reporting "783 signatures match":

| mutation | gate said |
|---|---|
| `CFE_TBL_ValidateTableName`'s `CFE_TBL_TableConfig_t *` → a different struct pointer | 783 match |
| `MD_ResolveSymAddr`'s `MD_SymAddr_t *` → `MD_DwellControlEntry_t *` | 783 match |
| `MD_ResolveSymAddr`'s `MD_SymAddr_t *` → the struct **by value** | 783 match |

The third is the worst and names the mechanism: there was no `MD_` rule in *either* type list, so
an MD pointer normalised to the **empty string** on both sides and even pointer-ness was gone —
a struct passed by value matching NASA's `const T *`. Two unrecognised types agreeing as two
blanks, the same shape as the `cpuaddr` gap this gate was patched for before, and the fifteenth
instance of it in `gate-blindspot-unpaired-types`.

The fix generates one rule per NASA struct or union — 738 of them, from
`check_structs.nasa_structs()` — mapping `T *` to a token that **keeps T's name**, dropping a
trailing `_t` so NASA's `CFE_MSG_TelemetryHeader_t` and the translation's class
`CFE_MSG_TelemetryHeader` still agree (HolyC has no typedef, so that suffix carries no
information). All three mutations now fail. Six names already had a dedicated pointer rule
because the two sides legitimately differ — `CFE_MSG_Message_t`, `OS_time_t`,
`OS_object_token_t`, `CFE_ES_MemPoolBuf_t`, `CFE_ES_StackPointer_t` and `osal_id_t`, which is a
struct in NASA's headers but an opaque id the translation spells `U32` — and those are exempt.

Two recorded deviations had to be rewritten, which is the DEVIATIONS mechanism doing its job:
it refuses a deviation string that no longer describes the code. `EVS_GenerateEventTelemetry`'s
recorded signature *began with a comma* — `,NUM,NUM,PTRNUM,PTRB,` — because its first two
parameters, `EVS_AppData_t *` and `CFE_TIME_SysTime_t *`, were two of those blanks.

And the residual blindness, measured rather than assumed: 446 of the translation's pointer
parameters now carry a struct name; 631 keep a generic token and are byte, void or scalar
pointers with no struct identity to carry. Of the 386 classes the translation declares, exactly
**six** cannot be named — and five are the five `check_structs` already reports as having no NASA
counterpart at all. The sixth was a type name inside a *comment* that my survey regex picked up.
So what is still blind is what another gate is already shouting about.

### The oracle was defining five globals that gated NASA sources also define

`CFE_ES_Global`, `CFE_SB_Global`, `CFE_EVS_Global`, `CFE_TBL_Global` and `CFE_TIME_Global` were
each defined **twice** — once in `tests/cfs/oracle_ccsdspri.c` and once in NASA's own
implementation file. `CFE_TBL_Global_t CFE_TBL_Global;` with no initialiser is a *tentative
definition* in C, and two of them in two translation units **merge silently**: the link succeeds
and nothing says which object the exercise is reading.

Each one carried a comment promising it would go away when its source was gated. All five
sources are gated. The comments were the only enforcement, and a comment is not a gate, so
`tools/cfs/check_oracle_globals.py` now is one — it derives each driver's oracle from the host
compile line rather than taking a list, so a new driver cannot be added without it being
checked. Removing all five left the transcript at exactly 2,167 lines, which *confirms* they
were merging rather than diverging; had the oracle's copy been a distinct object, the number
would have moved.

It also has a deadline built in: `MD_AppData` sits in the oracle now, and the gate will refuse
it the moment `md_app.c` is gated, four sources away.

**Four more stale claims fell out of the same look.** The oracle still said `cfe_es_api.c`,
`cfe_es_task.c`, `cfe_sb_task.c` and `cfe_es_apps.c` were "not gated yet"; all four are in
`SRC_C`. Worth checking rather than assuming, because the dangerous version of that rot is a
`static` stub in the oracle shadowing a function a gated source now defines — the C half would
call its stub while the HolyC half called the real translation, and the transcript would compare
two different functions. Measured: **zero** such stubs, static or otherwise. The stubs were
genuinely deleted when the sources landed; only the prose rotted.

### md_dwell_pkt.c, and the simulated memory MD reads

**2,185 transcript lines**, up from 2,167 — eighteen more, byte-identical on the first run. Four
functions: `MD_DwellLoop`, `MD_GetDwellData`, `MD_SendDwellPkt`, `MD_StartDwellStream`.

This is the file that needed the hardware, and the three missing symbols are now supplied the way
the driver already supplies twenty-two other `CFE_PSP_*` functions:

- `MD_SIM_WINDOW_BASE` is `0x00100000`, the **same literal in both halves**, naming a 256-byte
  window that is not a real address on either. `md_sim_mem[i] = 0x40 + i`, so a read at offset
  `0x10` is `0x50` and a 4-byte read there is `50 51 52 53` — ascending and impossible to confuse.
- `CFE_PSP_MemRead8/16/32` map an address in that window onto the buffer, and **assemble the
  bytes explicitly, little end first**, rather than casting the buffer to a `uint16`/`uint32`.
  `MD_GetDwellData` copies the low `NumBytes` of the value straight into the dwell packet, so the
  packet's contents depend on that choice and an assumption there would be an assumption about
  the transcript.
- An address outside the window returns `CFE_PSP_INVALID_MEM_ADDR`, which is how the three
  per-width error returns are reached on purpose.
- **`CFE_PSP_MemValidateRange` is deliberately left alone.** It is the settable stub that ES's and
  TBL's pool paths already drive, and making it window-aware would change behaviour for every
  existing caller — with the existing transcript lines as the only thing that would notice. The
  bounds check lives in the read functions instead, so the seam is additive.

NASA writes `(uint8 *)&MemReadVal` and `(uint16 *)&MemReadVal` at the call sites, and the casts
need no spelling in HolyC — not through laxness but because the **callee's** declared parameter
type decides the width. Measured with a four-line probe: preset `MemReadVal` to `0xFFFFFFFF`,
call the `U8 *` form, read back `0xFFFFFFAB`. One byte written, three untouched, which is exactly
what NASA's cast buys.

#### The dwell bytes are read back with their neighbours

`MD_GetDwellData`'s write is `memcpy(&Data[TblPtr->PktOffset], &MemReadVal, NumBytes)` — a 1-, 2-
or 4-byte store at a **variable offset**. That is the shape of both codegen bugs this project has
recorded: an 8-byte store emitted for a narrow one, and a wild store for a deep variable index. So
`Data[]` is poisoned with `0xEE` before each write and the bytes on *both sides* of the written
region are printed:

```
md_get w=1 st=0 off=5 reads=1 data=EEEEEEEE50EEEEEEEEEE
md_get w=2 st=0 off=6 reads=1 data=EEEEEEEE5051EEEEEEEE
md_get w=4 st=0 off=8 reads=1 data=EEEEEEEE50515253EEEE
```

A store that is too wide shows up as a *missing* `0xEE`, not as a value that happens to look
right. Same move as `tbl_neigh` in the tbl work.

#### Three behaviours the exercise pins that a status check would miss

**The write cursor advances even when the read fails.** `TblPtr->PktOffset += NumBytes` sits
*outside* the success branch, so a rejected address still moves it — and for the invalid width 3,
by three bytes that were never read:

```
md_get_err w=1 st=-1 off=5 untouched=1
md_get_err w=3 st=-4 off=7 untouched=1
```

**The signature is copied with `strncpy`, padding and all — and the first version of this test
asserted nothing.** `CfsStr.HC`'s `StrNCpy` reproduces `strncpy` exactly: zero-fill to the end of
the field, no terminator when the source is longer than `n`. The transcript prints the Signature
bytes *past* the NUL, on the theory that a `MemCpy` would carry whatever followed the source
string and only those bytes would show it.

Driven as a mutation, **that passed.** `StrNCpy` → `MemCpy` left the transcript byte-identical,
because the source field had been `memset` to zero by the setup and a verbatim copy of zeros is
indistinguishable from a zero-fill. The control passing is what said so: the *setup* was doing
the work, not the code. One byte of poison past the terminator in the source
(`T->Signature[5] = 0x7A`) makes the difference observable — `strncpy` still zero-fills the
destination, a `memcpy` carries the `0x7A` across — and the baseline transcript does not move,
because `strncpy` was always zero-filling. This is the sixth instance in this project of a
green assertion that a real mutation walked straight through.

**A zero-rate table is never processed, and that guard is load-bearing rather than defensive.**
With every `Delay` zero, `MD_DwellLoop`'s `while (Countdown == 0)` reloads `Countdown` from the
last entry's delay after sending — zero again — and spins forever. `Rate > 0` is the only thing
between this app and a hang, which is why `md_zerorate st=0 rate=0 cd=1 reads=0` asserts the table
was skipped *and* that no read happened.

The packet is read out of `MD_AppData` rather than off the bus: `CFE_SB_TimeStampMsg` puts a time
in the header, which cannot be compared across a host process and a QEMU guest, and the payload is
what MD is responsible for. `size=62` is `sizeof(MD_DwellPkt_t) - 25*4 + 6` — the packet shrinking
to the bytes actually dwelled.

#### And MD's read errors are an anonymous enum with no module prefix

`md_dwell_pkt.h` spells them `ONE_BYTE_MEM_ADDR_READ_ERR`, `TWO_BYTE_MEM_ADDR_READ_ERR`,
`FOUR_BYTE_MEM_ADDR_READ_ERR` and `INVALID_DWELL_ADDR_LEN` — NASA's own naming, matching none of
`check_constants`' `^(CFE_|OS_|OSAL_|MD_)\w+$`. All four are values `MD_GetDwellData` returns and
the transcript compares, and all four would have been non-candidates: 1,272 compared now, up from
1,267. They are listed by name rather than by loosening the pattern, because the pattern is what
keeps port-local constants out of a gate with no business judging them.

#### Six mutations, and the two that taught something

| mutation | transcript |
|---|---|
| the narrow store becomes a 4-byte one | `data=EEEEEEEE50EEEEEEEEEE` → `...50000000EEEE` |
| `PktOffset` advances only on success | `md_get_err w=1 st=-1 off=5` → `off=4` |
| `strncpy` → `MemCpy` (after fixing the test) | `sig=445730000000` → `44573000007A` |
| the packet size loses NASA's subtraction | `size=62` → `size=162` |
| the already-full branch reloads from entry 0 | `md_full cd=7` → `cd=5` |
| the `Rate > 0` guard removed | **526,875 lines of diff** — it spins, as predicted |

The first is the one the neighbour read-back was built for. `st`, `off` and `reads` are
**identical** across a store that wrote four bytes where one was asked for; only the poison
turning `EE`→`00` saw it.

The third is the one that found a defect in my own test — see above. It passed on the first
attempt because the source field was zero-filled.

#### And the send path was never running

The `Rate > 0` mutation printed half a million lines, and buried in them was EVS text from the
*unmutated* reference: `Send Err:Invalid MsgId(0x0)in msg`. The exercise had `memset` the dwell
packet and never called `CFE_MSG_Init`, so **every `CFE_SB_TransmitMsg` was rejected for an
invalid MsgId** — identically on both halves, so the transcript was satisfied while
`MD_SendDwellPkt`'s send did nothing. `MD_SendDwellPkt` returns `void`, so there was no status
to notice it by. Found by reading output a mutation happened to produce, which is not a method.

Fixed the way `md_app.c` does it — `CFE_MSG_Init` with `MD_DWELL_PKT_MID_BASE` (0x891, now a
constant `check_constants` compares against NASA's expansion) — and witnessed with SB's own
`NoSubscribersCounter`, which `CFE_SB_TransmitMsg` increments on a **valid** MsgId with no
subscribers and leaves alone on a rejected one. The event text changed from `Invalid MsgId(0x0)`
to `No subscribers for MsgId 0x891`, which is the send actually happening.

Two things about that witness are worth keeping:

- **It wrapped.** `NoSubscribersCounter` is a `uint8` and stood at 254, so the unmasked delta
  printed `4294967042`. A witness that wraps is not a witness; it is masked to 8 bits.
- **It reads 2 per dwell packet, and I predicted 1.** My reasoning was that
  `cfe_sb_priv.c`'s `CFE_SB_SEND_NO_SUBS_EID` request bit made the event a per-route one-shot.
  It is not: both sends to 0x891 raise an event and both move the counter by 2 — once for the
  dwell packet, once because EVS *transmits the event packet itself* over SB
  (`cfe_evs_utils.c:498`) on MsgId 0x809, which also has no subscribers. Verified rather than
  assumed: 0x809 accounts for 113 of the 119 no-subscriber lines in the transcript. A second
  witness at the already-full send is what falsified the prediction, so both stay.

### md_dwell_tbl.c — where MD meets Table Services, and the resource table that was full

Eight functions: the validation callback the ground's table load is checked by, the three
functions under it, the copy into working state, and three ground-commanded editors that go
through `CFE_TBL_GetAddress` / `CFE_TBL_Modified` / `CFE_TBL_ReleaseAddress`.

This is **the first thing in the port to use tbl from the outside.** Everything tbl-related up to
now was tbl's own code exercised from inside its module; here an app registers a table, the
ground loads it, tbl calls back into `MD_TableValidationFunc`, and MD edits the buffer in place
through a handle. That was the stated reason for choosing MD first, and this is the file that
cashes it.

#### Four `#if`s hand-resolved, and one is a shape HolyC cannot express at all

Limit #19 — `#if <expr>` is unconditionally true — means every one of these would take its first
branch whatever the value was. Both switches are 1 here and both values are **anchored** by
`check_constants` comparing them against NASA's header, which is what makes hand-resolving a
measurement rather than a guess.

The one worth naming: `MD_INTERFACE_SIGNATURE_OPTION` wraps an `else if` **clause in the middle
of an if/else chain**. A preprocessor conditional around one arm of a chain has no HolyC spelling
even if `#if` worked, so the arm is simply written out. The same switch also wraps a mid-function
*declaration* (`uint16 StringLength;`), hoisted to the top.

`MD_INTERFACE_ENFORCE_DWORD_ALIGN` selects 32-bit alignment checking over 16-bit for a 4-byte
dwell. Its dead `== 0` arm still says `Jam->Payload` where the live code says `Msg->` — evidence
in NASA's own tree that the branch is never compiled.

#### The check order is the thing worth pinning

`MD_ValidTableEntry` validates resolve → range → length → alignment, and the exercise pins the
order with two lines that differ only in the PSP's answer:

```
mdt_entry_range -1073741820     (0xC0000004 MD_INVALID_ADDR_ERROR)
mdt_entry_len3  -1073741819     (0xC0000005 MD_INVALID_LEN_ERROR)
```

Both are a dwell of length 3 — an invalid width. At a *bad* address the range check fires first;
at a good one the length check does. A translation that reordered the chain would still return
"an error" for both, and only the pair together can tell.

Also pinned: the enable-flag check beating the signature check when both are wrong
(`mdt_ena_beats_sig`); `MD_CheckTableEntries` reporting the **first** bad index while continuing
to count past it, which is NASA's own "Keep counting good,bad,unused, don't exit immediately";
and `MD_CopyUpdatedTbl` copying entry 4 — *past* the terminator — because NASA's loop runs all 25
rows regardless.

#### The MemPool table was at ten of ten

`CFE_TBL_EarlyInit` here failed with **"No free MemPool slots available"**, every handle came back
as `CFE_TBL_BAD_TABLE_HANDLE`, and all six assertions collapsed into one repeated error code —
the exact failure the tbl section already recorded, from the same cause. The table is a
**fixed-size resource shared between exercises**: `EarlyInit` is called six times in this oracle
and only one section gives its pool back.

**The discrimination is the interesting part.** All ten slots held a 524,288-byte pool, and
`CFE_PLATFORM_SB_BUF_MEMORY_BYTES` and `CFE_PLATFORM_TBL_BUF_MEMORY_BYTES` are *both* 512 KiB — so
a size test would have deleted SB's buffer pool and silently broken the dwell packet's transmit
in the next block. Reclaiming by `BaseAddr` against `CFE_TBL_Global.Buf.Partition` frees exactly
two, and `md_sent` still reads 2, which is the check that the reclaim was surgical. The count is
printed and the addresses are not, because a `cpuaddr` cannot be compared across a host process
and a QEMU guest.

**This fixes the symptom, and the cause is still there.** Five of the six `EarlyInit` calls
above still leak their pool; MD's block reclaims what it needs and gives its own back. Fixing the
five properly means capturing each pool id and deleting it at the end of its own section, the way
`tbl_early pooldel=0 0` already does — five sections of code this work did not write, each
gaining a transcript line. Worth doing; not worth bundling into an app translation. Until then,
`md_sent 2` is the guard that this reclaim took nothing that mattered, and the count
`mdt_poolgc freed=2` is the guard that it took something.

Three wrong turns on the way there, each corrected by measuring rather than reasoning:

- An unguarded `rb->Signature` dereference segfaulted when `GetAddress` returned no pointer —
  and the segfault **truncated stdout mid-line**, so the diagnostic read `"No"` instead of
  `"No free MemPool slots available"`. The block-buffering lesson, again: fix the crash first,
  then read the message.
- I theorised the platform block-size config array had been wiped, since `PoolCreateEx`'s other
  failure path prints a message starting the same way. Measured: `n=17`, intact.
- I expected the three editors to work on a freshly registered table. cFE correctly answers
  `CFE_TBL_ERR_NEVER_LOADED` until the ground loads it, so the exercise loads first — which is
  also what the ground actually does.

#### The readback is what makes the #26 deviation an assertion

`MD_UpdateTableDwellEntry` takes `MD_SymAddr_t` **by value** in NASA's declaration — 72 bytes
against HolyC's 8-byte limit — so the translation takes a pointer. The deviation is recorded, and
`check_struct_copy` refuses the by-value form outright, but neither of those proves the data
arrives. The readback does:

```
mdt_upd_dwell st=0 get=0 len=4 dly=9 off=1048624 sym=SYM_IN_ENTRY
```

`SymName` lives at offset 8 and beyond. A by-value call in HolyC would have delivered `Offset`
and garbage for the name, so `sym=SYM_IN_ENTRY` is the whole 72 bytes arriving — read back
through a *second* `GetAddress`, not from the pointer the editor already released.

#### Six mutations, and the one that was invisible until the exercise grew

| mutation | transcript |
|---|---|
| the validation chain reordered: length before range | `mdt_entry_range -1073741820` → `-1073741819` |
| `MD_CheckTableEntries` records the **last** bad index | `firstbad=1` → `firstbad=2`, plus a second entry-error event |
| `MD_ReadDwellTable` sums `Delay` into the size output | `size=6` → `size=3` |
| `MD_CopyUpdatedTbl` stops at the terminator | `a4=1048640` → `a4=0` |
| the dwell entry copies only the `Offset` | `sym=SYM_IN_ENTRY` → `sym=` |
| `CFE_TBL_Modified` deleted | **nothing** — see below |

The first is the pair the exercise was designed around: the reordered chain changes `INVALID_ADDR`
to `INVALID_LEN` for the *bad-address* case while the good-address case is unchanged, so only the
two lines together localise it.

The fifth is worth keeping as a demonstration rather than a test: copying only the `Offset` is
**exactly what HolyC's by-value truncation would have done** to this function, and `sym=` is what
the transcript would have shown. Limit #26 is not hypothetical here.

**And the sixth passed.** Deleting `CFE_TBL_Modified` from `MD_UpdateTableEnabledField` left the
transcript byte-identical — because the readback reads the same buffer the editor wrote and does
not care whether Table Services was *told* about it. All three editors call `Modified`, so the
call was unexercised in all three.

`CFE_TBL_Modified`'s only comparable effect is `RegRecPtr->Status.IsModified` (its other effect,
`TimeOfLastUpdate`, is a time and cannot cross the two halves). So the exercise now resolves the
registry record and reads that flag, clearing it first so the readback asserts *this* call rather
than whatever ran before — `mod=1` on all three lines.

Getting there corrected one more assumption: `CFE_TBL_FindTableInRegistry` returns a **resource
id**, not an array index. It came back as `0x1c0001`, which indexes nothing, and
`CFE_TBL_Global.Registry[0x1c0001]` is far out of bounds. `CFE_TBL_LocateRegRecByName` is the
right accessor and needs no index arithmetic at all — which also satisfies the tbl section's own
rule against hard-coded registry indices, recorded there as a mistake it made seven times.

### md_cmds.c — the six ground commands, and nine assertions that said nothing

Noop, ResetCounters, StartDwell, StopDwell, JamDwell, SetSignature. Twenty-three event ids,
which is most of what an operator ever sees from this app.

**Every command writes two places**, and that is the shape of the file: MD keeps working state in
`MD_AppData.MD_DwellTables` and the ground's copy in a Table Services buffer, so each handler
updates the control structure *and* calls one of `md_dwell_tbl.c`'s three editors. The editors can
fail independently, so a command can **partly succeed** — which is why `Status` and the two
counters move separately, and why the exercise prints all three on most lines.

#### The partial failure is reachable because three handles are deliberately unregistered

`md_cmds`' block **reuses** the table the `md_dwell_tbl` block registered rather than calling
`CFE_TBL_EarlyInit` again — nothing between them memsets `CFE_TBL_Global`, and another `EarlyInit`
would take a MemPool slot from a table that was at 10/10 before this transcript reclaimed two.
Occupancy is printed once as a tripwire (`mdc_pools 9/10`), so if it ever fills again that line
says so immediately instead of six assertions cascading into `-1` handles.

Handles 1..3 are left unregistered, and that is what reaches the interesting arm:

```
mdc_start1  st=0            cc=1 ec=0 ena=1 cd=1 cur=0 off=0
mdc_start12 st=-872415231   cc=1 ec=1 ena2=1
```

A mask of `0x0003` succeeds for table 1 and fails for table 2 — *"failed for 1 of 2 tables"* —
and `ena2=1` is the asymmetry worth pinning: **the control structure is updated for table 2
anyway**, because NASA writes it before calling the editor. Only the Table Services copy is
missed. `cc` does not advance and `ec` does.

#### `FieldLength 0` is a command, not an error, and its consequence is silent

`MD_ValidFieldLength` accepts **0**, so a Jam with `FieldLength 0` is the "null out this entry"
command. Status is success either way, and nulling an entry *terminates the table there*:

```
mdc_jam_ok   ... n=3 size=8 rate=11
mdc_jam_null ... n=1 size=2 rate=2  e2len=0 e3len=4
```

`MD_UpdateDwellControlInfo` stops at the first zero `Length`, so all three derived totals collapse
while entry 3 still holds a live 4-byte dwell. Nothing but the totals shows it.

#### Nine of my assertions printed what a no-op would print

`MD_JamDwellCmd` sets `Status = CFE_SUCCESS` at the top, and an argument rejection only clears
`AllInputsValid` — the bookkeeping at the end increments `CommandErrorCounter` and leaves `Status`
untouched. So **every rejection returns 0**, and the first version of this block printed the
status alone for four argument checks and five validity rejections: nine lines that a function
which did nothing would have satisfied exactly.

Each now carries the error counter, and the values are monotonic and distinct —
`ec=4,5,6,7,8,9,10,11,12` — so each line asserts *that* rejection rather than the pair. **The
counter is the signal; the status is not.**

#### Two NASA details the translation has to carry

`sizeof` through `->`. `md_cmds.c` writes `sizeof(Msg->Payload.DwellAddress.SymName)`, and
`docs/HOLYC_STRUCT_LIMITS.md` #16 records that `sizeof` through an arrow **does not parse** — it
fails as a bare `0:1: error: parse error` with no line number, which took a six-way bisect to
localise. The dot form on the adjacent line parses and is left alone. Both sizes resolve to
`CFE_MISSION_MAX_PATH_LEN`, which is written out, the same way the port handles NASA's other
unreachable `sizeof`s.

**And NASA passes a partially-initialised struct by value.** `NewDwellAddress` is a local
`MD_SymAddr_t`, and the `FieldLength == 0` branch sets only `.Offset` and `.SymName[0]` before
handing all 72 bytes to `MD_UpdateTableDwellEntry` — the rest is uninitialised stack, copied into
the Table Services buffer. Same family as the uninitialised dump header recorded above. It is
harmless to the app, which only reads `SymName` as a string, and it means **the exercise must read
it as a string too**: a byte dump past the NUL cannot be compared across a host process and a
QEMU guest.

#### And the call-site hole in the #26 gate, measured rather than assumed

`check_struct_copy` refuses a by-value class parameter in a **definition**, which is where
`MD_UpdateTableDwellEntry` declares one. `md_cmds.c` has two **call sites** passing that 72-byte
struct, and a missing `&` there is invisible to the gate: dropping it left the gate reporting 89
parameters and OK.

The transcript catches it loudly, not quietly — a 35-line diff including `CFE_TBL_GetAddress: Bad
AppId=1114113`, because the struct's bytes bleed into the next argument register. So the call-site
risk is left to the transcript, with that measurement written into the gate's own header so the
next reader knows which half of the problem it covers.

#### Six mutations, and the second vacuity in the same block

| mutation | transcript |
|---|---|
| `StartDwell` leaves `Countdown` at 0 | `cd=1` → `cd=0` |
| `StartDwell` counts a partly-failed command as good | `cc=1 ec=1` → `cc=2 ec=0`, and event 56 becomes event 12 — 38 lines |
| `StopDwell` forgets to disable the control structure | `ena=0` → `ena=1` |
| the null jam leaves `Delay` alone | **nothing** — see below |
| `SetSignature` checks the table id before the length | event 49 becomes event 47, nothing else moves |
| the Jam bookkeeping counts a rejected command as good | `ec=4,5,6…` → `ec=3,3,3…` — 28 lines |

Two of these only move an **event id**: reordering `SetSignature`'s checks leaves the status and
both counters untouched, so the event text is the only witness. That is the second time in this
app a check-ordering bug is visible in nothing else.

**And the fourth passed.** The null-out command zeroes `Length`, `Delay` and `ResolvedAddress`,
and the block asserted the three totals `MD_UpdateDwellControlInfo` derives from the table.
Deleting `DwellEntryPtr->Delay = 0;` left the transcript byte-identical — because the summariser
**stops at the first entry whose `Length` is zero**, so the instant the null write lands, that
entry's `Delay` is never read again by anything. `Rate` was 2 either way.

A total is a projection, and a projection discards. Asserting the output of a function that reads
a *subset* of the state says nothing about the rest — and "the totals changed correctly" reads
like strong evidence, which is what makes it dangerous. The block now reads `e2len`, `e2dly` and
`e2addr`, the fields the code actually writes. The giveaway question, worth asking of any
assertion built on a computed value: **does the function producing it read the field my code just
wrote?** Here it provably stopped before reaching it.

That is the second vacuous assertion this one file produced — the nine `st=0` rejection lines
were the first — and both were found by a control passing rather than by review.

### module_deps reported MD's order backwards, and seven modules with it

`md_app.c` calls `MD_TaskPipe`, which lives in `md_dispatch.c` — so `md_dispatch.c` has to be
gated *before* `md_app.c`. The tool said the opposite: `md_dispatch.c` last, and the cycle
reported as `md_app.c ↔ md_eds_dispatch.c`.

The cause is one line. `owner[n] = b` kept whichever source was scanned **last**, and every
CMake-conditional pair defines the same symbols:

| pair | shared symbol |
|---|---|
| `md_dispatch.c` / `md_eds_dispatch.c` | `MD_TaskPipe` |
| `cfe_X_dispatch.c` / `cfe_X_eds_dispatch.c` | `CFE_X_TaskPipe`, `ProcessCommandPacket` |
| `cfe_msg_msgid_v1.c` / `_v2.c` | six accessors |
| `cfe_config_eds_disabled.c` / `_enabled.c` | `CFE_Config_EdsState` |

`_eds_` and `_v2` sort **after** the plain name, so the loser was always the file the
configuration actually builds. Every edge onto one of those symbols pointed at a source that is
not in the build. What it cost, besides MD's order:

- **config** came back as a 2-source cycle that **only exists through the EDS variant** — it is
  acyclic in this configuration.
- **es** named `cfe_es_eds_dispatch.c` in a 14-source cycle; it is `cfe_es_dispatch.c`.
- **evs** reported `cfe_evs_eds_dispatch.c + task`; it is `cfe_evs_dispatch.c + task`.
- **sb** and **ta** likewise named the EDS file.

Ownership now resolves by **what the configuration builds** — the driver's `SRC_C` first, then
CMake's unconditional list, with a genuine ambiguity printed and marked `AMBIGUOUS`. Not by a
name pattern, which would not have caught msg's `v1`/`v2` pair. `SRC_C` is consulted even under
`--fresh`, because `--fresh` pretends nothing has been *translated* yet, which is a different
question from which branch of the build is under test.

**What did not move is the anchor:** tbl's 8-source cycle, time's 3 and sbr's 2. None of those
runs through a dispatch file, so none was ever mis-attributed — and tbl's 8 is the number the
plan above was written against.

**And the docstring that justifies trusting the tool had gone stale twice.** It said ES was a
*twelve*-source cycle (the `[&ref]` edge fix made it 14) and that *"EVS, by contrast, is fully
acyclic: seven singletons in dependency order"* — which was never true in the configuration this
port builds. Both corrected, with the note that a calibration claim is a measurement with a date
on it, not a property.

The corrected order for MD's remaining work: **`md_app.c` and `md_dispatch.c` are a genuine
2-source cycle of 775 lines**, and are gated together, the same shape as every cFE module's
task/dispatch pair and the same decision tbl's 8-source cycle got.

### md_app.c and md_dispatch.c — the last two, gated together, and MD is complete

A **cycle**: `MD_AppMain` calls `MD_TaskPipe` from the dispatcher, and the dispatcher's switch
calls `MD_SendHkCmd` from the app. 775 lines that go in together, the same shape as every cFE
module's task/dispatch pair — and `module_deps.py` only said so once its owner map stopped
attributing `MD_TaskPipe` to the EDS variant.

With these, **MD is 100%: six sources, 2,288 lines, no stand-ins**, and the first cFS app in the
port is complete.

#### `check_oracle_globals` collected on a deadline it was given four commits early

`MD_AppData` is defined in `md_app.c`. Until this commit the oracle supplied it, because NASA's
source was not gated — and the note said a C tentative definition in two translation units
*merges silently*. The gate written for that moment did exactly what it was for:

```
FAIL check-oracle-globals — the oracle defines a global that a GATED NASA source also defines.
    tests/cfs/oracle_ccsdspri.c defines MD_AppData, and so does md_app.c
```

#### The hang, and why reasoning lost twice to one stack trace

`MD_AppMain` hung. Three attempts to explain it:

1. **The transcript blamed the wrong block.** Output is block-buffered, so the last visible line
   was `mdt_reg` — three sections earlier — making it look as though `CFE_TBL_Load` had started
   hanging in a block that had worked minutes before. A flushed `fprintf(stderr, …)` before each
   call named `MD_AppMain`. That is the recorded "read a block-buffered log" lesson, paid again.
2. **I assumed the loop was spinning.** `MD_AppMain` treats `CFE_SB_TIME_OUT` as "no action", so
   on a real pipe with a 1000 ms timeout nothing ends it — a plausible story. Pre-setting the
   app's `ControlReq` didn't help, because `CFE_ES_RunLoop` reaches its control check only after
   a record lookup. A direct `MD_AppInit()` call then showed it was **already failing as
   intended** (`0xCA000005`, the duplicate pipe), so the loop was being skipped correctly and my
   model was simply wrong.
3. **`sample` on the live process named it in one line:** `CFE_ES_ExitApp → OS_TaskDelay`.

`CFE_ES_ExitApp` calls `OS_TaskExit` for a **CORE** app and otherwise waits to be deleted by ES,
which never happens in a single-process driver. Three other sections of the oracle already set
`AppTable[1].Type = CFE_ES_AppType_CORE` for precisely this reason — the answer was in the file
the whole time, and two rounds of inference did not find it.

**The ordering that makes the loop skip is kept, because it is better than a shortcut.** Calling
`MD_InitSoftwareBusServices` first takes `MD_CMD_PIPE`, so `AppInit`'s `CreatePipe` refuses the
duplicate, `AppInit` fails, and `RunLoop`'s *first* test — on the caller's own `RunStatus`,
before any lock or lookup — ends the loop before it runs once. Each init function is then
exercised on its success path directly and its failure path through `AppMain`.

#### `exits=0` is not a witness, and the block says so

For a CORE app with `APP_ERROR` — rather than one of the `CORE_APP_*_ERROR` statuses —
`CFE_ES_ExitApp` **refuses** and logs `Cannot Exit CORE Application`. So the exit counter reads
zero, which is also exactly what "never called" looks like. The syslog line is what proves
`ExitApp` was reached, and that is written at the site rather than left for a reader to assume
the zero meant something.

#### Two honest results the run produced by itself

**`/cf/md_dw01.tbl` exists on the driver's RAM disk and is a dump of a different table.** An
earlier section wrote it. So `CFE_TBL_Load` answers `CFE_TBL_ERR_FILE_FOR_WRONG_TABLE` and NASA's
init loop stops at the *first* table — one handle set, the fourth name empty. NASA's event 102
names the offending file and the table it actually belongs to. Deterministic on both halves,
because the same code produces the file on both.

**And my own block broke the one before it.** Placed before `md_cmds`, this block's
`CFE_TBL_EarlyInit` cleared the registry that `md_cmds`' editors depend on, and every one of them
answered `CFE_TBL_ERR_NEVER_LOADED` — a 54-line diff that was entirely self-inflicted. It belongs
last among the MD blocks. The fix then went wrong twice more: the move anchored on
`cfe_time_objtab.c ---`, which occurs more than once, so the block landed *before*
`md_dwell_tbl`; moving it again from there left the order fully scrambled. Restored both halves
from backups, verified line counts and block order, and re-inserted once against an anchor that
occurs exactly once. **Anchor uniqueness is the requirement — `s.index` on a repeated marker
picks the wrong one silently**, which is the `parser-edit-safety` lesson in a new guise.

#### The four routing branches each have a witness that only moves if that branch ran

```
mdd_pipe_wakeup reads=1      the dwell loop read one address through the simulated window
mdd_pipe_hk     valid=77     MD_SendHkCmd copied the command counter into the packet
mdd_pipe_cmd    cc=1 ec=0    the ground command reached the switch
mdd_pipe_badmid cc=0 ec=1    an unknown id moves the error counter and nothing else
```

That group is also the **static-local collision check**. `MD_TaskPipe` caches its three MsgIds in
statics named `CMD_MID`, `SEND_HK_MID` and `WAKE_UP_MID` — the same names `cfe_es_dispatch`,
`cfe_evs_dispatch` and `cfe_ta_dispatch` already use, and those three collided once when a HolyC
static local became a global under its bare name (limit #12). MD is the **fourth** user of those
names in one translation unit. If that scoping had regressed, MD's cache would hold a cFE
module's id and these four lines would route to the wrong handler. The routing *is* the check.

One line reads oddly and is correct: `mdd_cc1 cc=0`. `MD_ResetCountersCmd` zeroes **both**
counters, so the one command whose success looks like nothing happened is the reset.

#### Six mutations, all caught

| mutation | transcript |
|---|---|
| `InitControlStructures` leaves `Countdown` at 0 | `cd=1,1,1,1` → `cd=0,0,0,0` |
| the HK enable mask drops the per-table shift | `mask=0x0005` → `0x0001` |
| the HK packet's MsgId is never initialised | `hkmid=0x0890` → `0x0000`, and the send becomes `Invalid MsgId(0x0)` |
| `VerifyCmdLength` does not count the bad command | `ec=1` → `ec=0` |
| the dispatcher's NOOP case falls through to RESET | `cc=1` → `cc=0`, with `Reset Counters Cmd Received` appearing twice |
| the pipe router never fills its MsgId cache | all four branches become `Invalid command pipe message ID: 0x00001892` |

The last is the static-local check resolving. With the cache unfilled every route falls through
to the unknown-id arm, which is what shows the cache fill is load-bearing — and so, from the
clean run, that MD's three statics are correctly scoped despite being the fourth user of those
names in one translation unit.

The third is worth noting for the shape rather than the value: an uninitialised MsgId does not
merely change a printed field, it turns the HK transmit into `Send Err:Invalid MsgId(0x0)` — the
same silent-rejection failure that `md_dwell_pkt`'s exercise had for real before `CFE_MSG_Init`
was added there. Twice in one app, the thing that makes a send observable is the MsgId.

---

## MM (Memory Manager) is the second app, and the prefix list that was wrong four times

MD is done, so the next app. Of the three API-current candidates, **MM at 4,085 lines is the
smallest and the best fit**: it is the *other* memory app. MD only ever reads memory; MM pokes,
fills, loads from a file and dumps to one — so the simulated memory window MD established
already answers its hardest design question, and MM needs the **write** half of it.

Pinned at `0a767de5` and vendored, with 14 shim headers. Its missing symbols are all the
established patterns:

| missing | pattern |
|---|---|
| `CFE_PSP_MemWrite8/16/32` | the write counterparts of MD's reads, same window |
| `CFE_PSP_EepromWrite8/16/32`, `WriteEnable/Disable` | a second simulated region |
| `CFE_ES_MEMADDRESS_C`, `_TO_PTR` | macros written out |
| `OS_FILESTAT_SIZE` | an OSAL accessor macro |

Nine gated sources, 3,739 unconditional lines plus `mm_dispatch.c`.

### The prefix list in module_deps was wrong four times, so there is no longer one

`module_deps.py` matched call and reference edges with a hard-coded prefix alternation. It had
already been `CFE_\w+` (which found **nothing** inside MD — five independent singletons in pure
size order) and then `(?:CFE|MD)_\w+`. MM arrived and reported **ten clean singletons with no
edges at all**, for exactly the same reason, in exactly the same confident shape.

A hard-coded alternation is a list someone has to remember to extend, and the failure is silent.
So the pattern is now simply `[A-Za-z_]\w*` — any identifier. That is safe and strictly better,
because **a name only becomes an edge when one of this module's own sources defines it**:
`owner` is built from `defines()` over those sources and nothing else, so every libc call, every
local, and every cFE API the module merely consumes falls out at that lookup.

**Removing it corrected a cFE module too.** EVS's private helpers are named `EVS_SendEvent`,
`EVS_AddLog` and `EVS_GenerateEventTelemetry` — **no `CFE_` prefix** — so those edges were never
counted. EVS reported a 2-source cycle; its real cycle is **five**: `cfe_evs.c`,
`cfe_evs_dispatch.c`, `cfe_evs_log.c`, `cfe_evs_task.c` and `cfe_evs_utils.c`.

Measured across all twelve modules, EVS is the **only** answer that changed. es's 14, sb's 4,
tbl's 8, time's 3 and 2, sbr's 2, ta's 2 and md's 2 are byte-identical — which is what makes the
EVS correction trustworthy rather than alarming, and tbl's 8 remains the number this plan was
written against.

### MM's order, and why it has no app/dispatch cycle

```
mm_utils → mm_mem8 → mm_mem16 → mm_mem32 → mm_dump → mm_load → mm_cmds → mm_dispatch → mm_app
```

Fully acyclic, no stand-ins at any step. `mm_app` comes **last**, after `mm_dispatch` —
`mm_app.c` calls `MM_TaskPipe`, and `mm_dispatch.c` calls only `mm_cmds.c` and `mm_utils.c`.
That is the difference from MD: `MM_SendHkCmd` lives in `mm_cmds.c` rather than in the app, so
there is nothing for the dispatcher to call back into.

### `mm_utils.c` is gated — and `%p` had never been printed before

582 lines, eight functions, no stand-ins. Transcript **2,378 → 2,497**. Four new HolyC files
(`mm_eventids.HC`, `mm_perfids.HC`, `mm_msg.HC`, `mm_global.HC`, `mm_utils.HC`), 30 new classes,
33 new constants.

**The finding is a conversion, not a function.** Six of `mm_utils.c`'s events render the address
with `"Addr = %p"`. `Kernel/Cfs/CfsStr.HC`'s `StrPrintNV` did not implement `%p`, and
*no previously gated NASA source used it* — 1,384 conversions across 89 sources, 18 distinct
forms, and not one `%p`. Its unhandled-conversion path emits the two characters literally and
**does not consume the argument**, so every argument after it on the line shifts by one. That is
the same hazard the note on `'z'` in `CfsStr.HC` records from `cfe_sb_api.c`'s `"%zu"`, and it
would have hit six events at once.

So `%p` is implemented, in the host C library's spelling (`0x` then lowercase hex, full 64 bits,
no width), and **`tools/cfs/check_formats.py`** is the new static gate: it extracts every
conversion from every string literal in the gated sources and refuses one `StrPrintNV` does not
implement — reading the supported set **out of the formatter** (`*Fmt == '…'`) rather than
carrying a second list that could rot away from it. It also refuses the flags and precisions the
formatter cannot parse (`-`, `+`, `#`, `.`), because those fail the same way. Driven both ways:
with `%p` removed from the formatter it names all ten call sites; with it present, 1,423
conversions in 90 sources, 19 forms, clean.

One honest limit: C leaves `%p` of a **null** pointer implementation-defined, and the two
mainstream libcs disagree (`0x0` against `(nil)`). That is a difference between *hosts*, not
between halves, so the translation follows this host and **no exercise passes address zero
through `%p`**. Written at both the formatter and the exercise.

### The app directories were the NASA-side copy of the bug `cfs_dirs.py` fixed

`cfs_dirs.py` exists because eight gates each carried their own spelling of the *translation's*
directories, and `check_padding` silently measured 358 classes while `check_structs` measured
380. Adding `Kernel/Cfs/mm` to it moved `check_structs` from 380 to **410**, exactly the 30 MM
classes — the count is the check that the edit took.

Then the same shape appeared one level over: `check_structs.NASA_DIRS` and
`check_padding.INC` **each had their own hand-written copy of MD's three app directories**
(`vendor/MD/fsw/src`, `fsw/inc`, `config`), and `check_manifest` its own `APPS` list. Unify one
and the other goes on being two. So `cfs_dirs.py` now owns `APPS` and `app_dirs()`, and a third
app is one edit in one file.

### An empty signature token, caught only because the other side was recognised

`check_signatures` reported:

```
mm_utils.c: MM_VerifyPeekPokeParams: NASA (SZ,,SZ)  translation (SZ,NUM,SZ)
```

The blank is `MM_MemType_Enum_t`, which the type table did not know — and *an unrecognised type
normalises to nothing*. This is the `gate-blindspot` shape again: two unrecognised types **agree
as two blanks**, and the only reason this one failed is that the translation's side *was*
recognised (`U32` → `NUM`). Had the translation also used a name the table does not know, the
pair would have matched on nothing.

The rule added is deliberately *not* the one the six `OS_*` enums use. Those map to `SZ` because
the translation spells them `I64`; `MM_MemType_Enum_t` is a four-byte unsigned enum **and also a
struct member** in six of MM's payloads, where four bytes is the layout `check_padding`
measures — so the translation spells it `U32` everywhere and the C maps to `NUM`.

### The two validators are walked as a grid, because NASA's comment says they have to be

`MM_VerifyLoadDumpParams` takes a memory type *and* which command is asking, and NASA's own
comment says the `VerifyType` chains have **no `else` on purpose**: an unreached
(MemType, VerifyType) pair must leave `MaxSize` at 0 and be rejected by the size check at the
end. A list of hand-picked calls cannot assert that. So the exercise walks **7 memory types × 6
verification types** and prints one line per row, then pins each limit with a MaxSize /
MaxSize+1 pair, then the alignment arms — including MEM8's **absence** of one, which is the cell
that says the three near-identical arms were not written as one.

The size for the grid is **16 bytes**, chosen because it is above
`MM_INTERNAL_MAX_DUMP_INEVENT_BYTES` (15) and below every other limit: the DumpInEvent column
rejects while the other four accept, so the grid distinguishes five different `MaxSize` values
instead of agreeing that everything is small enough.

### A witness of my own that asserted nothing, and the reason it was silent

`MM_SegmentBreak` stamps the performance log, delays, and stamps it again. The first version of
the witness printed the millisecond total — and `MM_INTERNAL_PROCESSOR_CYCLE` is **0** in this
configuration, so it was a zero against a zero. `evs_delays` counts *calls* for that reason.

The second version read `Perf->MetaData.DataCount` after `CFE_ES_StartPerfDataCmd`, and printed
`n=0 e0=0x0 e1=0x0` **with no event to say why**: `StartPerfDataCmd` does not touch the filter
mask (only a power-on reset initialises it), the es block earlier in the same driver both zeroes
the whole Perf area and drives `CFE_ES_SetPerfFilterMaskCmd`, and `StartPerfDataCmd`'s own
acknowledgement is a `DEBUG` event that this configuration filters out. Both halves agreed, and
they agreed about nothing. The mask is now set explicitly, and the line reads
`n=2 e0=0x0000001f e1=0x8000001f` — which pins the marker *and* says both stamps ran, where a
delay count alone would survive dropping `PerfLogExit`.

### Eighteen mutations, and the one that was invisible

| mutation | what the transcript said |
|---|---|
| `MM_ResetHk` clears the whole FileName buffer, not just `[0]` | `fn1=89` → `fn1=0` |
| `MM_ResetHk` also clears the command counter | `cc=11` → `cc=0` |
| `MM_SegmentBreak` drops its performance-log EXIT stamp | `n=2 e1=0x8000001f` → `n=1 e1=0x0` |
| it stamps the APPMAIN marker instead of SEGBREAK | `e0=0x1f` → `e0=0x1e` |
| `MM_Verify32Aligned` checks the address but not the SIZE | `mmu_a32 1001` → `1011`, and MEM32's load accepts a 6-byte region |
| `MM_Verify16Aligned` the same | `mmu_a16 1001` → `1011`, and MEM16's accepts 3 |
| the MEM8 peek arm demands two bytes | the whole diagonal shifts: `m8=0` at width 8 becomes `-40`, at 16 becomes `0` |
| the MEM32 size event prints `SizeInBytes` where NASA prints `SizeInBits` | `Data Size = 8` → `1`, `16` → `2` |
| the RAM `VerifyType` chain gains an `else` | the DumpInEvent cell ACCEPTS 16, and `wid201` accepts 201 |
| MEM8 load/dump gains an alignment check | `m8=0` → `-3` |
| MEM16's memory-type name is written `MEM32` | `MemType = MEM16` → `MEM32` in the event |
| the zero-length rejection is dropped | `zero=-1` → `zero=0` |
| `MM_ResolveSymAddr` writes the address even when the lookup FAILED | `mmu_resolve_fail -1 57005` → `57037` |
| it stops NUL-terminating the end of the name | `len=63 last=0` → `len=64 last=65` |
| the file CRC folds in the whole BUFFER, not the bytes read | `0x00002439` → `0x0000c14b` |
| the file CRC is written even on a read error | `0xa5a5a5a5` → `0x00000000` |
| the formatter drops `%p`'s `0x` prefix | `Addr = 0x100001` → `100001`, in 14 events |
| **the formatter renders `%p` in UPPER case** | **nothing — INVISIBLE** |

The last one is the point. Every address in the block was `0x001000xx`, whose digits are all
0–4, so the *case* of `%p`'s hex digits was not asserted anywhere: a formatter that printed
`0xABCDEF` would have passed, and the first MM address with a letter digit would have broken a
transcript nobody had touched. One call was added at `0x00ABCDEF` — every letter digit, and odd,
so the 16-bit alignment check rejects it and the event prints it — and the mutation now shows
`0xabcdef` → `0xABCDEF`. Transcript 2,494 → **2,497**.

It is the same shape as the three `%08X` cases this port has already found: a conversion agrees
for as long as the VALUES it is given cannot tell the two renderings apart.

### The gate that looked at none of it: 68 MM constants, and a count that read like a pass

`check_constants` had its prefix filter written out by hand — `^(CFE_|OS_|OSAL_|MD_)\w+$`. MM
arrived with about 130 constants resolved by hand or by a `cpp` probe (60 event ids, 5
performance ids, three MsgIds, 40 configuration values, the 14 `MM_LastAction_*`, the six
`MM_MemType_*`, the five `MM_VERIFY_*`) and **the gate looked at none of them**.

The tell was the count: it moved 1,313 → **1,346**, and six of those 33 were the `CFE_PSP_*` and
`OS_*` defines `mm_utils.HC` itself added. Everything else was include-graph expansion. A gate
whose number goes *up* while its coverage of the new work is zero is the hardest shape to see,
and it is the `module_deps` prefix list over again — four times there, once here. The filter is
now built from `cfs_dirs.APPS`, so a third app is one edit in one file.

Then a second layer: with `MM_` in scope, 1,346 → 1,407 but the "NASA does not define this"
bucket went **35 → 104**. Sixty-eight MM names — *every* event id, *every* performance id and all
three MsgIds — because `mm_eventids.h`, `mm_perfids.h` and `mm_msgids.h` were not in the probe's
header list, and **a constant the probe cannot SEE is indistinguishable from one this port
invented**. `MM_INTERNAL_*` and `MM_INTERFACE_*` *were* compared, reachable through `mm_app.h`,
which is exactly what made the gap look like a pass.

With the five headers added: **1,476 constants compared**, and the not-defined bucket back to its
pre-MM 35. Driven on purpose — `MM_PSP_WRITE_ERR_EID` typed as 58 and `MM_HK_TLM_MID` as `0x888`
both fail by name and value. This matters because the transcript reaches exactly six MM event
ids (19, 21–25) and **zero** MsgIds: a wrong MsgId would have stayed silent until `mm_dispatch`
lands, which is the failure MD hit twice.

### And `check_formats` was wired into one of the three drivers that share the formatter

It arrived with MM and went into `run_cfs_xlat_smoke.sh`, whose source list contains no OSAL at
all — while `run_osal_xlat_smoke.sh` and `run_osal_printf_smoke.sh` compile the same
`StrPrintNV`. Both are now gated too (34 conversions over 24 sources, 11 over the printf
module's two), and both were clean, which is the point: a gate covering one of three users of
the thing it checks is the "empty output is the blind spot" shape this project keeps finding.

The single exemption in that gate — `cfe_time_api.c`'s `"%Y-%j-%H:%M:%S"`, which goes to
`strftime` and not to a printf — was first written with a **false reason**: that the call site
was inside `CFE_TIME_PrintUtc`, "`#if`'d out of this port, and check_coverage records that
exclusion". Measured, the function is `CFE_TIME_Print`, it is *not* excluded (the three
exclusions in that file are `CFE_TIME_ExternalGPS`, `_MET` and `_Time`), and it *is* translated
with its own recorded deviation. The exemption holds; the reason given for it did not. Corrected
in place, with the correction kept, because a stale exemption reason that is a false claim about
NASA is already on this project's list.

### `mm_mem8.c` — the first source in the port that WRITES memory

306 lines, three functions, no stand-ins. Transcript **2,497 → 2,521**. MM is 2 of 9 sources,
888 of 3,739 lines (24%).

MD only ever read memory, so the simulated window grew a write half:
`CFE_PSP_MemWrite8/16/32` over the same `MD_SIM_WINDOW_BASE`, plus two knobs. `md_sim_writes`
counts **stores**, because MM computes `BytesProcessed` from its own segment arithmetic and never
from the stores — a fill that stored nothing would report 250 anyway. `md_sim_wfail_at` fails one
store by offset, which is the only way into `MM_PSP_WRITE_ERR_EID` *and* therefore the only way
to reach the short arm that turns a partial move into `CFE_PSP_ERROR`.

The window is 256 bytes, so **250** is the exercise size: two segments (200 + 50), which is the
smallest number that drives both the shortened last segment and the `MM_SegmentBreak` between
them. The break is witnessed by the performance log's entry count, not by the delay.

#### One event in this file cannot be compared at all, and a mutation proved it

`MM_PSP_READ_ERR_EID`'s text is `"PSP read memory error: RC=0x%08X, Src=%p, Tgt=%p, Type=MEM8"`,
and `Tgt` is `&ioBuffer8[i]` — **a real pointer into `MM_AppData.DumpBuffer`**, not an address the
ground supplied. Every other address in MM's event text is a constant that came from a command
and is the same number on both halves; this one is wherever the linker put `MM_AppData`.

That is not a judgement call: two mutations reached the branch by accident and the diff shows
`Tgt=0x80a39710` on the HolyC side against the oracle's own value. So the exercise drives the
other three error events in the file and not this one, and both halves say why. It is the first
place in the port where NASA's own telemetry text is outside what a differential can assert.

#### The formatter was reading 64 bits where C reads 32, and `%u` found it

The halves diverged on one line:

```
- OS_read error received: RC = 0x00000000 Expected = 4294967295        (NASA's C)
+ OS_read error received: RC = 0x00000000 Expected = 18446744073709551615  (HolyC)
```

`mm_mem8.c` prints `(unsigned int)SegmentSize` with `"%u"`. **C's `%u` reads an `unsigned int` —
32 bits** — and `StrPrintNV` masked to 32 bits only for `base == 16`. The note beside that line
already said the length modifier decides the width; it was implemented for `%x` and not for `%u`,
which is exactly as narrow and for the same reason.

Fixed properly rather than at the call site: without a length modifier, `%u`/`%x`/`%X` now mask to
32 bits and **`%d` sign-extends from 32**, which is C's argument-promotion rule. The narrowing has
to happen *before* the sign is taken, or `%d` of a value whose low 32 bits are negative comes out
positive. This cannot break an agreeing line — a line that agrees today agrees because C read 32
bits and the value fit.

`%d`'s half had nothing driving it, so `run_osal_printf_smoke.sh` — the gate that exists to
compare this formatter — gained one line that renders **one** value six ways:

```
w -1 4294967295 ffffffff 8589934591 8589934591 1ffffffff
```

Six distinct renderings of `0x1FFFFFFFF`, which is what makes the line an assertion rather than a
decoration.

#### NASA declares `BytesRemaining` signed in the load and unsigned in the dump

`int32` in `MM_LoadMem8FromFile`, `uint32` in `MM_DumpMem8ToFile` and `MM_FillMem8`. Nothing in
the first version of the exercise could see the difference. The input that makes it observable is
a file header claiming `0xFFFFFFFF` bytes:

| | `BytesRemaining` | `BytesRemaining < 200` | the event says |
|---|---|---|---|
| load | `int32` → **-1** | true (signed) | `Expected = 4294967295` |
| dump | `uint32` → 4294967295 | false | `Expected = 200` |

Two numbers in two events, and they are the only thing in the transcript that says the two
declarations differ. Both mutations — "tidy the load up to unsigned" and "make the dump signed" —
now fail. The dump's case is forced to fail on the **write**, with no room in the file, rather
than being allowed to run off the end of the 256-byte window: running off it reaches the
uncomparable read event above.

#### Fourteen mutations: twelve caught, and two that are PROVABLE NO-OPS

Twelve failed the transcript. The two that did not are not gaps in the exercise — they are
semantically equivalent, and the argument is short enough to check:

> Both mutations swap `BytesProcessed == NumOfBytes` for `PSP_Status == CFE_PSP_SUCCESS` as the
> guard on the housekeeping update. `BytesProcessed` is incremented by `SegmentSize` in exactly
> the branch that decrements `BytesRemaining` by `SegmentSize`, so
> `BytesProcessed + BytesRemaining == NumOfBytes` is invariant at the top of every iteration. The
> loop exits only when `BytesRemaining == 0`. The two error paths force `BytesRemaining = 0`
> *without* adding to `BytesProcessed`, and **both of them also leave `PSP_Status` non-success**.
> So a normal exit has `BytesProcessed == NumOfBytes` and success; an error exit has neither. The
> two guards cannot disagree.

NASA spells the same condition two ways in two adjacent functions, which looks like an
inconsistency and is not an observable one. Recorded rather than driven, because a mutation that
cannot change behaviour is not evidence of a missing assertion — and calling it one would be the
[vacuous-assertion] mistake in reverse.

### `mm_mem16.c` and `mm_mem32.c` — the width twins, and what three near-identical files buy

320 lines each, three functions each, no stand-ins. Transcript **2,521 → 2,541**. MM is 5 of 9
sources, 1,528 of 3,739 lines (41%).

NASA writes the byte, word and dword paths as three near-copies rather than one parameterised
loop, and the usual reaction to that is to factor it. **The exercise is built to show why not.**
It does not repeat `mem8`'s cases; it drives the four things that differ, every one of which is
behaviour a merge would destroy:

| | mem8 | mem16 | mem32 |
|---|---|---|---|
| the loop counts | **bytes** (200/segment) | **elements** (100) | **elements** (50) |
| fill rounds the length to | nothing to round | a multiple of **2**, with its own event | a multiple of **4**, with its own event |
| fill pattern | truncated to `0xDD` | truncated to `0xCCDD` | **not truncated** — `0xAABBCCDD` |
| the load's write-error event says | `RC=0xFFFFFFEB` | `RC=0xFFFFFFFF` | `RC=-21` |

The last row is the sharpest. All three print the same PSP failure, and all three print it
differently: `mem8` renders the real code as unsigned hex, `mem16` **overwrites `PSP_Status` with
`CFE_PSP_ERROR` before reporting it** so the ground never sees what the PSP actually said, and
`mem32` prints the real code with `"RC=%d"` and a signed cast. Three files, three renderings, one
error. Four mutations cover it — and each one turns one rendering into another, which is exactly
what "harmonising the three files" would do.

`md_sim_writes` is what makes the first row assertable. Every byte count MM reports comes from its
own segment arithmetic, never from the stores, so `writes=125` for a 250-byte `mem16` load and
`writes=62` for a 248-byte `mem32` load are the only evidence the loops divide by the width at
all. The byte-counting mutation on each runs off the 256-byte window and is caught twice over.

#### The rounding is also what makes mem8's two no-op mutations real

`mm_mem8`'s commit recorded a proof that swapping the housekeeping guard from
`BytesProcessed == NumOfBytes` to `PSP_Status == CFE_PSP_SUCCESS` cannot change behaviour there.
**In mem16 and mem32 it can, and the odd-length fill is the input that does it**: the rounding
reduces `BytesRemaining`, the fill completes successfully, and `BytesProcessed` can then never
equal the *commanded* `NumOfBytes` — so NASA's guard fails while the status says success. An
odd-length fill therefore warns, writes the aligned part, **leaves housekeeping alone and returns
an error**, all four at once. Both mutations now fail where their mem8 twins were no-ops, which is
the confirmation that the mem8 proof was about mem8 and not about the guard.

#### The translation was generated, and then checked by diffing itself

`mm_mem16.HC` and `mm_mem32.HC` were produced from `mm_mem8.HC` by substitution and then edited
for the four differences — which is how NASA's own three files read, and is the only honest way to
keep 960 lines of near-copies consistent. **The check is a diff of the diffs**: the structural
difference between the port's three HolyC files has to be the same shape as the structural
difference between NASA's three C files. It caught one leftover in `mm_mem32.HC` — a
`CFE_PSP_MemWrite32` still declared taking a `U16` — which no gate here looks at, because the PSP
is not a translated module and its declaration is local to the file.

#### A witness of mine that two values could both satisfy

The first version put the `fs_data` fill once at the top of the block. But the **dumps write into
`fs_data`**, and what they write is `md_sim_fill`'s own pattern — so the `mem32` load read a stale
file whose bytes were `0x40 + i`, which is exactly what the window already contained. `m0=40`
would have been satisfied equally by the load working and by it never running. The file is
refilled with a `0x80 + i` pattern before every load now, and the lines read `m0=80`.

### `mm_dump.c` — and the paths where the simulated window stops working

368 lines, four functions, no stand-ins. Transcript **2,541 → 2,574**. MM is 6 of 9 sources,
1,896 of 3,739 lines (51%).

**The window was never the point; the PSP indirection was.** Every MM path so far reached memory
through `CFE_PSP_MemRead*`/`MemWrite*`, which is what let the port use a *window of literal
addresses* — the same constant on a host process and a QEMU guest. `MM_DumpMemToFile` does

```c
memcpy(ioBuffer, SourcePtr, SegmentSize);
```

and `MM_FillDumpInEventBuffer`'s RAM/EEPROM arm does the same. A literal `0x00100000` there is a
wild pointer. Those two paths are therefore exercised against a **real driver-owned array**, and
the cost lands on one field: `MM_DumpMemToFile` sets
`HkTlm.Payload.Address = FileHeader->SymAddress.Offset`, which is now wherever the linker put
that array — a different number on each half.

**The answer is to print a COMPARISON, not the value.** The line says
`addr_ok=1`, which is `Address == (cpuaddr)mmd_src`: true on both halves, and still false if the
field is set from the wrong place. The mutation that reports `NumOfBytes` there turns it to 0.
That is a better tool than omitting the field, and it generalises — any uncomparable value can be
asserted against something the driver knows.

Which events are drivable is now a list rather than a discovery:

| | drivable | why |
|---|---|---|
| `MM_PeekMem`'s two | **yes** | goes through the PSP, so its `Addr = %p` is a window constant |
| `MM_DumpMemToFile`'s one | **yes** | no `%p` at all |
| `MM_WriteFileHeaders`' two | **yes** | no `%p` |
| `MM_FillDumpInEventBuffer`'s three | **no** | each prints `Tgt=%p`, the caller's buffer |

The four success arms of the last one *are* driven, and the read counts separate them: a 8-byte
request is **2** PSP reads as MEM32, **4** as MEM16 and **8** as MEM8.

#### HolyC's `switch` falls through exactly like C's — measured, not assumed

`MM_FillDumpInEventBuffer` has `case MM_MemType_RAM: case MM_MemType_EEPROM:` sharing one body,
and the repo already contained a claim that HolyC's switch falls through "like C" — in a comment,
with nothing driving it. Probed both shapes before translating:

```
case 1: case 2: r = 99;     →  pick(1)=99  pick(2)=99     (empty label reaches the next)
case 1: r += 10; case 2: r += 100;  →  fall(1)=110        (non-empty case falls in too)
```

So the two labels translate verbatim. And it is load-bearing: the mutation that deletes the
`EEPROM` label makes that command return `CFE_PSP_ERROR` with an all-zero buffer.

#### NASA writes one byte of stack into every dump file

`MM_WriteFileHeaders` writes `sizeof(MM_LoadDumpFileHeader_t)` — **88 bytes**, and the struct's
last byte is tail padding after `Spare[3]`. So byte 151 of every MM dump file is whatever was on
the caller's stack. This is the same defect `dumpfile-uninitialised-header` records in cFE's table
dump, in a second app. **Both halves of the differential zero the header before calling**, which
is the driver's choice and not NASA's, and the exercise says so where it prints `pad151=0` — a
zero there is evidence about the driver, not about the translation.

Two more of NASA's own choices the exercise pins, because nothing else would:

- `MM_DumpMemToFile` resets `OS_Status = OS_SUCCESS` **inside** the loop. `OS_write` returns a
  byte count, so without that line a successful dump returns 50 (the last segment's size) and
  every caller's `== CFE_SUCCESS` fails. Driven: `st=0` becomes `st=50`.
- both of `MM_WriteFileHeaders`' error arms replace the status with `OS_ERR_INVALID_SIZE`
  **before** printing it, so the ground sees `-40` and cannot tell a failed write from a short
  one. Driven: the event reads `RC = 10` instead.

And `MM_PeekMem` initialises `PSP_Status` to `CFE_PSP_ERROR_NOT_IMPLEMENTED`, not to an error — so
a width no arm recognises returns **-27** and reports `MemType=MEM0`, the one status in MM that
means *no branch ran*. NASA's comment says `MM_VerifyPeekPokeParams` makes that unreachable;
calling `MM_PeekMem` directly is the only way a translation of it gets checked at all.

Fifteen mutations, fifteen caught.

### `mm_load.c` — a second simulated device, and an UPSTREAM DEFECT kept verbatim

492 lines, six functions, no stand-ins. Transcript **2,574 → 2,634**. MM is 7 of 9 sources,
2,388 of 3,739 lines (64%).

#### MM_FillMem does not fill with the pattern, and the translation keeps it that way

```c
uint8 *FillBuffer = (uint8 *)&MM_AppData.FillBuffer[0];
for (i = 0; i < (MM_INTERNAL_MAX_FILL_DATA_SEG / sizeof(uint32)); i++)
    FillBuffer[i] = CmdPtr->Payload.FillPattern;
```

`FillBuffer` is a **byte** pointer; the loop runs `200 / 4 = 50` times. So a 200-byte fill segment
gets the pattern's low byte in its first **fifty** bytes and keeps whatever
`MM_AppData.FillBuffer` held in the other 150. The intent was plainly
`((uint32 *)FillBuffer)[i] = FillPattern` — 50 words, 200 bytes, pattern throughout.

**It is translated verbatim.** The port's whole claim is to be NASA's software; a translation that
quietly behaved better would be a different program wearing the same name. So the exercise prints
the boundary instead, into an array poisoned with `0xBB`:

```
mml_fill      perf=0 s0=DD s49=DD s50=00 s199=00 s200=BB
mml_fill_2seg perf=2 bp=250 s200=DD s249=DD
```

Bytes 0–49 carry `0xDD`; bytes 50–199 are **zero** — `MM_AppData.FillBuffer`'s untouched BSS — and
byte 200 is still the poison because the fill stopped there. The second line is the specific
signature of the defect across two segments: `DD` in 0–49, `00` in 50–199, `DD` again in 200–249,
because the 50-byte last segment copies `FillBuffer[0..49]`, which *are* the pattern.

Two mutations cover it, and the first is the one that matters: **"fix it the natural way"** —
writing through a `U32 *` — gives `s49=CC s50=BB s199=AA`, the pattern cycling as words. That is
what NASA meant, and the transcript refuses it. Recorded as an upstream finding, not a port
decision; it belongs upstream as a bug report.

#### EEPROM is a second device, so it gets a second window

A RAM poke goes through `CFE_PSP_MemWrite*`; an EEPROM poke goes through `CFE_PSP_EepromWrite*`,
which on real hardware unlocks the part, programs it and waits. So the driver supplies
`MM_EEP_WINDOW_BASE = 0x00200000`, deliberately far from the RAM window — **an address meant for
one and sent to the other must be refused, not quietly work.** A shared array would have made
`mml_poke_eep_wrongregion` succeed and nothing in the port would have noticed.

Three things follow from EEPROM being a different device, and the exercise pins all three:

- **performance-log stamps**: `MM_PokeEeprom` has them, `MM_PokeMem` does not — `perf=6` for three
  EEPROM pokes against `perf=0` for three RAM ones. In `MM_LoadMemFromFile` and `MM_FillMem` they
  are **conditional on the memory type**, the only markers in MM taken only sometimes: the same
  call gives `perf=4` for EEPROM and `perf=2` for RAM.
- **one error event per width** (`MM_OS_EEPROMWRITE8/16/32_ERR_EID`) where RAM has one for all.
- **the success event prints the data at the commanded width**: the same `0xAABBCCDD` reads
  `0xDD`, `0xCCDD` and `0xAABBCCDD` from EEPROM, and always `0x%08X` from RAM.

`MM_ReadFileHeaders` is exercised as a **round trip through `MM_WriteFileHeaders`** — write the
pair, read it back, compare the fields. Either alone would pass against a wrong offset.

#### Three invisible mutations, three different causes

Fifteen mutations. Three came back unchanged, and the three reasons are all different:

1. **the 16-bit poke reporting one byte** — a real gap: the exercise printed housekeeping once
   after all three pokes, which reads only the 32-bit arm's byte count. Fixed by capturing the
   count after **each** call (`mml_poke_bp 1,2,4`).
2. **`MM_PokeEeprom` updating housekeeping on failure** — a real gap: nothing read housekeeping
   after a *failed* poke. Fixed with `mml_poke_eep_failhk`, which must still show the previous
   successful poke's address.
3. **moving `DataSize = 32` after the write** — *a no-op by construction*. The assignment is
   inside the case arm either way, and the event is after the switch. **And the mutation was
   written because of a false claim in my own comment**, which said `MM_PokeMem` sets
   `BytesProcessed` and `DataSize` before the write "so they are correct in the ERROR event too --
   the peek sets them only on success". Measured: the peek sets `DataSize` unconditionally too,
   and `BytesProcessed` is a local that reaches housekeeping only on success in **both**. Neither
   placement is observable. The comment is corrected in place and says how it was found; the
   mutation was replaced with one that *deletes* `DataSize = 32`, which turns the error event into
   `MemType=MEM0`.

A mutation that cannot change behaviour is not evidence of a missing assertion — but a mutation
written to prove a claim, that turns out to be a no-op, **is** evidence the claim was wrong.

### `mm_cmds.c` — fourteen commands, a second upstream defect, and HolyC limit #27

1,116 lines, fourteen functions, no stand-ins — MM's largest source and the only caller of every
other MM file. Transcript **2,634 → 2,737**. MM is 8 of 9 sources, 3,504 of 3,739 lines (94%).

#### HolyC limit #27: a class DECLARATION INITIALISER carries only its first 8 bytes

**The same copy is whole as a statement and truncated as an initialiser.** One extra line of
source changes the semantics:

| | |
|---|---|
| `S d; d = p->m;` | **whole** |
| `S d = p->m;` | **first 8 bytes, silently** |

Found by a transcript divergence. NASA's `MM_FillMemCmd` writes
`MM_SymAddr_t DestSymAddress = Msg->Payload.DestSymAddress;` where the other four handlers in the
same file declare and then assign — so **one of five broke**. `MM_SymAddr_t`'s first eight bytes
are its `Offset`, so the offset survived and the 64-byte `SymName` did not; `MM_ResolveSymAddr`
then saw a non-empty name in uninitialised stack, took the symbol-lookup branch, and the fill
went to `md_sym_addr + Offset`. **The command was built correctly and the address was wrong**,
which is the hardest shape to chase — a probe in the driver printed
`sz=288 n0=0 off=1048640 mt=3 nb=16`, i.e. *the setup is right*, before the copy came under
suspicion.

Two wrong guesses on the way, both worth recording because they are the obvious ones:

- that `sizeof` of a **union variable** was short. It *is* — `sizeof(t)` where `t` is a union
  variable returns the **first member's** size, not the union's — but the driver uses
  `sizeof(TypeName)`, which is correct. A real compiler defect that was not this one.
- that a plain class assignment from a pointed-at member was truncated. Probed all four
  assignment forms: all whole.

Pinned by `tests/exec/cases/e_class_decl_init.hc` → `0x7429`, which calls a `warm()` function
first to leave `0xAA` in the frame the probes reuse — a declaration has no chance to be zeroed,
and a run where the uncopied bytes happened to be zero would look like a successful copy.
**Refused by `check_struct_copy.py`, which exempts by SIZE and not by site**: eight bytes or less
is copied whole, so the seventeen existing sites (all `CFE_SB_MsgId`, `CFE_SBR_RouteId`,
`OS_time_t`, `CFE_TIME_SysTime` — 4 or 8 bytes) pass, and a type the gate cannot measure is a
failure. Driven: putting NASA's form back names the file, the line and `MM_SymAddr_t is 72 bytes`.

#### The memory type decides whether a command is comparable at all

Five handlers print the resolved address in their success event, and that splits them:

- **MEM8/MEM16/MEM32** go through `CFE_PSP_Mem{Read,Write}*`, so the address is a literal window
  constant and the event is identical on both halves. **Every success path is driven that way.**
- **RAM/EEPROM** `memcpy` to or from the address, so it must be real memory and the event cannot
  be compared. Those paths were driven through `mm_dump.c` and `mm_load.c` directly, where the
  housekeeping address is asserted by comparison.

**One success path is outside the differential entirely**: `MM_LoadMemWIDCmd`. Its memory type is
hard-coded to RAM — an EEPROM programming cycle cannot be done with interrupts off — and it ends
in `memcpy((void *)DestAddress, ...)`, so the address is necessarily real and the event prints it.
Its three error paths are driven; the success path is not, and both halves say so.

`MM_DumpMemToFileCmd` and `MM_LoadMemFromFileCmd` are driven as **one round trip**: the dump
writes the headers, the data, seeks back, computes the CRC over what it wrote and rewrites the
headers; the load then verifies that same CRC. Three mutations in that pair — never rewriting the
headers, seeking past one header instead of two, and not seeking back after the CRC — all turn
`Loaded 32 bytes` into a CRC failure. Either function alone would have passed against a wrong
offset.

#### The second upstream defect: a failed fill counts as a success

```c
if (Status == CFE_PSP_SUCCESS) { ... } else {
    MM_AppData.HkTlm.Payload.CommandCounter++;      /* the SUCCESS counter */
}
```

**And which input reaches it took measuring; the first answer written down was wrong.** The note
said an unaligned length does it, because `mm_mem16/32` round the length down and then fail their
own housekeeping guard — but `MM_VerifyLoadDumpParams` checks the alignment of the **size** as
well as the address for those types, so an unaligned fill is refused one level earlier and lands
in the *outer* else, which counts correctly. (The rounding warning in `mm_mem16/32` is defensive
code this command path cannot reach at all — which also retires a claim made two commits ago.)

The route that does reach it is a **PSP write failure**: `MM_FillMem8/16/32` return
`CFE_PSP_ERROR` when a store is refused, which on hardware is a fill that ran off a region. So a
fill that wrote part of its range and then failed moves MM's **success** counter and sends **no
event at all** — the ground sees a command that worked. Driven with the window's store-failure
knob: `mmc_fill_wfail cc=1 ec=0 m69=5A m70=86`.

#### Twenty-one mutations, twenty caught, and a third provable no-op

Two came back unchanged and both were my fault, not the exercise's:

- `MM_PokeCmd` counting a failed poke as a success — a **real gap**: every poke in the exercise
  either worked or failed in the *verifier*, so nothing reached the worker and failed there. A
  poke outside the window (the verifier accepts it, `CFE_PSP_MemWrite32` refuses) closes it.
- `MemCpy` instead of `snprintf` for the symbol-dump file name — **a no-op by construction**:
  `snprintf` of a 12-character name writes exactly the 13 bytes `MemCpy` would, and *neither*
  zero-fills. (`strncpy`/`StrNCpy` does; `snprintf`/`StrPrintN` does not. MM uses both, and the
  two `fn20=` assertions in this port's exercises are on opposite sides of that.) Replaced with a
  bound of 5, which truncates the name.

And one that is a **provable no-op**, the third in MM: `MM_FillMemCmd`'s success path tests
`LastAction == MM_LastAction_FILL` rather than the status, and the two cannot disagree — the
generic `MM_FillMem` is void and always writes `LastAction`, and each width fill returns success
**exactly** when it writes it. NASA's defensive guard cannot be false here. Recorded, not driven.

### A gate that had been wrong for months, found because a count went DOWN

Adding `mm_cmds.c`'s exercise moved `check_variadic` from **1,936 declarations to 1,850** — and
it still **passed**, because its property is "no declaration *disagrees* with NASA" and a
declaration it cannot see cannot disagree.

Four gates each carried their own `strip_comments`, and three of them removed **block** comments
first:

```python
re.sub(r'/\*.*?\*/', ..., flags=re.S)   # first
re.sub(r'//[^\n]*',  ..., )             # second
```

That order makes a `/*` **inside a line comment** a real block-comment opener. The cFS driver has
had

```
// Kernel/Cfs/**.HC and nothing else, so the four names this exercise needs
```

at line 562 since the kernel-include note was written — and `Kernel/Cfs/**.HC` contains `/*`. It
was harmless **for one reason only: there was no `*/` anywhere after it in the file.** Then an
exercise six thousand lines later added `mmc_c.Wid.Payload.Crc = 0; /* deliberately wrong */`,
the stale opener paired with that closer, and everything between became whitespace. The driver's
matched declarations went from 177 to 36.

The fix is one pass with an alternation, so whichever opener comes first in the text wins:

```python
re.sub(r'//[^\n]*|/\*.*?\*/', blank, txt, flags=re.S)
```

`re.sub` scans left to right and tries the alternatives in order at each position, so a `//`
comment is consumed whole — including any `/*` inside it — before a block comment can start.
It lives in **`tools/cfs/cfs_text.py`**, imported by all four gates, and **carries its own driven
control** (a `/*` inside a `//` comment must not eat the following code; line numbers must not
move; a multi-line block comment must keep its newlines) which the smoke script runs. Newlines
are preserved and every other comment character becomes a space — a superset of what the four
callers needed, because `check_struct_copy` needs line numbers to survive and `check_variadic`
counts newlines to turn an offset into a line.

`check_struct_copy`'s copy already had the right order, which is the fourth time in this project
that two implementations of one rule have disagreed and only one was right. **The counts after
the fix: 1,936 declarations and 1,613 names consistent, up from 1,850 and 1,591.** The three
other gates' numbers did not move, which is what says the unification changed only the thing it
was meant to.

#### And the complement of that grep: ten gates read source and never strip comments

`grep -ln 'def strip_comments'` found the four copies. It cannot find a gate that **should**
strip and does not — so:

```
$ grep -L strip_comments tools/cfs/check_*.py
check_coverage.py  check_formats.py  check_in_blob.py  check_manifest.py  check_lock_sites.py
check_constants.py  check_seam.py  check_oracle_globals.py  check_signatures.py  check_wired.py
```

`check_formats.py` is the one that matters most, because it was written this same session and
scans **every string literal** — a format string in a comment is not a format string, and a NASA
doc comment containing something like `%q` would have failed the gate on a conversion the
compiler never sees. **Measured before applying the fix**, because the shared stripper is not
string-aware and a real format string containing `//` would be blanked by it: across the 96 gated
sources, 773 literals contain a `%`, **zero** are comment-only and **zero** code strings
disappear. So the change is a no-op today and closes the exposure; the measurement is in the
function's docstring.

The other nine are not done and are **not** claimed to be. Their exposure differs by kind and the
distinction is the useful part:

- `check_coverage`, `check_signatures` scan for function **definitions** in NASA's `.c`. One
  inside a comment would be reported as *missing from the translation* — a **false failure**,
  loud, not a silent pass. Lower risk, still wrong.
- `check_constants` scans `#define`s and `check_lock_sites` scans lock calls with `__func__` and
  `__LINE__`. Both could count a commented-out line, and both would then compare it — the
  `check_constants` direction is a false failure, the `check_lock_sites` direction could be
  either.
- `check_seam`, `check_wired`, `check_manifest`, `check_in_blob`, `check_oracle_globals` read
  names, paths and build files rather than code bodies; the exposure is small but not zero.

Each needs the same before-and-after measurement that `check_formats` got, which is its own
piece of work rather than a line to add on trust.

### `mm_dispatch.c` and `mm_app.c` — **MM is 100%**

472 lines, five functions, no stand-ins. Transcript **2,737 → 2,803**. MM is **9 of 9 sources,
3,976 of 3,976 gated lines (100%)** — the port's **second complete cFS application**.

The two go in together but they are **acyclic**, unlike MD's pair: `mm_app.c` calls `MM_TaskPipe`
and `mm_dispatch.c` calls only `mm_cmds.c` and `mm_utils.c`, because `MM_SendHkCmd` lives in
`mm_cmds.c` rather than in the app. So the include order alone resolves them, and
`module_deps.py` said so before a line was written.

**MD's `AppMain` lesson applied rather than re-derived.** The loop treats `CFE_SB_TIME_OUT` as "no
action", so on a real pipe with a 1000 ms timeout nothing ends it. Calling `MM_AppInit` directly
first takes `MM_CMD_PIPE`, so `AppMain`'s `CreatePipe` refuses the duplicate, `RunStatus` becomes
`APP_ERROR`, and `CFE_ES_RunLoop`'s first test — on the caller's own status, before any record
lookup — skips the loop. And the app must be a **CORE** app for `ExitApp` to return: for a CORE
app with `APP_ERROR` it *refuses* and logs `Cannot Exit CORE Application`, which is the witness,
because a zero exit count is also what "never called" looks like.

All thirteen command codes are driven in one loop, **with the expected length taken from `sizeof`
rather than written out** — the switch's expected length *is* a `sizeof`, and a hand-copied number
would be a second opinion about the layout. Each is sent with a zero payload, so the ones that
act on memory are refused by their own validator — and **none of those refusals prints an
address**, which is the only reason thirteen commands fit in one comparable loop.

#### MM_AppInit clears the housekeeping payload three times, and two of them are dead

Two mutations came back invisible — "do not zero the command counters" and "do not call
`MM_ResetHk`" — and rather than assume redundancy, it was **demonstrated in two more runs**:

| mutation | result |
|---|---|
| 9. drop the explicit counter zeroing | invisible |
| 11. drop the `MM_ResetHk()` call | invisible |
| **15. drop BOTH, keep `CFE_MSG_Init`** | **invisible** |
| **16. also drop `CFE_MSG_Init`'s own `MemSet`** | **the transcript breaks** |

`CFE_MSG_Init(ptr, msgid, sizeof(MM_HkTlm_t))` does `memset(MsgPtr, 0, Size)` over the **whole
packet, header and payload** — which NASA's own comment at the call site says ("clear user data
area"). The explicit zeroing is two statements *before* it and is overwritten; `MM_ResetHk` is
after it and writes the same zeros. Both are dead. **Translated verbatim**, as always, and
recorded here rather than tidied.

That is the fourth provable no-op in MM, and the shape is now familiar enough to name: **NASA's
defensive writes**. Three of the four are a field cleared twice or a guard that cannot be false.
They are not bugs and they are not assertions this exercise is missing; the useful output is
knowing which is which.

Mutation 5 is worth one more line because it is an independent confirmation: deleting the `NOOP`
case's `break` makes a NOOP command **also run RESET**, exactly as it would in C. HolyC's `switch`
really does fall through, measured twice now by two different routes.

#### Score, MM end to end

| | |
|---|---|
| sources | 9 of 9, **100%** (3,739 unconditional lines) |
| transcript | 2,378 → **2,803** byte-identical lines |
| mutations driven | **102**, of which **95 caught**, 4 provable no-ops, 3 real exercise gaps (all closed) |
| upstream defects found and kept verbatim | **2** (`MM_FillMem`'s byte-pointer fill loop; `MM_FillMemCmd` counting a failed fill as a success) |
| HolyC limits found | **1** (#27, a class declaration initialiser) |
| gate defects found | **3** (`check_constants`' prefix list, the `check_structs`/`check_padding` app-directory duplication, the comment stripper) |
| simulated hardware added | the RAM window's **write** half, a second **EEPROM** region, the EEPROM bank lock, `OS_SymbolTableDump`, a size from `OS_stat`, a failing `OS_read` |
| branches outside the differential, stated | **4** (`MM_PSP_READ_ERR_EID` ×2 files, `MM_LoadMemWIDCmd`'s success path, `MM_FillDumpInEventBuffer`'s three read errors) |

---

## CS (Checksum) is the third app, and the first with a shape that cannot go in one source at a time

Every cFE module is 100% and both apps are 100%, so `check_manifest --cfe` says the next target is
a third app — not a module. Of the four the survey found API-current (CS, LC, MM, MD), two are
done. Both remaining ones were measured rather than recalled:

| | sources | lines | distinct cFE/OSAL calls | **missing from the tree** |
|---|---|---|---|---|
| **CS** (Checksum) | 10 + the EDS pair | 5,765 | 55 | **2** |
| **LC** (Limit Checker) | 7 + the EDS pair | ~4,200 | 34 | **0** |

LC needs *nothing* new, which makes it the easier one. **CS is the right one anyway**, for a
reason that is about what the port can then demonstrate rather than about cost:

**CS completes the memory trio.** MD reads memory, MM writes it, and **CS is the app that notices
when the writing was not intended.** `docs/BENCHTOP_SAT_BOM.md` already says the radiation
experiment should stay in software — "deliberately flip bytes in a checksummed region and watch
the checksum app detect it" — and the simulated window MM built is exactly the place to flip them.
Translating CS gives the port its first pair of apps that work *against* each other, which is
worth more than two independent apps.

Its two missing symbols are both small: `CFE_ES_MEMADDRESS_TO_PTR` is a macro already written out
for MM, and `CFE_PSP_GetKernelTextSegmentInfo` is one new simulated PSP function — the sibling of
`CFE_PSP_GetCFETextSegmentInfo`, which the driver already supplies. Pinned at `795e387f` on the
dev branch, dated **one day before** the cFE pin, exactly the relationship MD's and MM's have.

### The shape, and why it is harder than either previous app

`module_deps.py CS --fresh` reports **two call cycles**, which neither MD (one 2-source cycle at
the end) nor MM (fully acyclic) had:

```
 2980 lines  cs_compute.c, cs_table_processing.c, cs_utils.c   <-- CYCLE of 3
  307 lines  cs_init.c
 2931 lines  cs_app.c, cs_app_cmds.c, cs_cmds.c, cs_dispatch.c,
             cs_eeprom_cmds.c, cs_memory_cmds.c, cs_table_cmds.c  <-- CYCLE of 7
```

**But the edges say the cycles are thin, and that is the useful part.** Listing them one by one
(the question the `module-deps-before-ordering` note says to ask per edge — is the stand-in a
*seam* or *upstream logic*?):

- **the 3-cycle is closed by three calls out of `cs_utils.c`**: `CS_ComputeApp` and
  `CS_ComputeTables` in `cs_compute.c`, and `CS_HandleTableUpdate` in `cs_table_processing.c`.
  Everything else in the group points *into* `cs_utils`. All three are real logic, not seams.
- **the 7-cycle is closed by exactly TWO functions**: `CS_UpdateCDS` (in `cs_app.c`, called by all
  five command files) and `CS_AppPipe` (in `cs_dispatch.c`, called by `cs_app.c`). The other forty
  edges are a dispatcher calling its own handlers — a tree, not a cycle.

So **no step needs a stand-in**, which keeps the apps' record intact:

```
   1.  cs_utils + cs_compute + cs_table_processing     2,980 lines, together
   2.  cs_init                                           307 lines
   3.  cs_app + cs_dispatch + cs_app_cmds + cs_cmds
       + cs_eeprom_cmds + cs_memory_cmds + cs_table_cmds 2,931 lines, together
```

Three steps instead of nine, and two of them are larger than anything in MD or MM. That is a
consequence of CS's design rather than of the plan: `cs_utils.c` is a 1,168-line pile of helpers
that both of its neighbours need *and* that calls back into both of them, and `cs_dispatch.c` and
`cs_app.c` are joined by a single CDS write.

`cs_init.c` is third in the topological order and second here because it depends on the 3-cycle
(seven table-processing functions and one `cs_utils` helper) and the 7-cycle depends on **it** —
`cs_app.c` needs `CS_InitAllTables`, `CS_InitSegments` and `CS_SbInit`.

**And the ambiguity the tool flagged is the one it has flagged twice before**: `CS_AppPipe` is
defined in both `cs_dispatch.c` and `cs_eds_dispatch.c`, and the edge goes to the one this
configuration builds. `check_manifest.py` already understands that pair for MD and MM.

### CS's shared vocabulary — 57 classes, and the two idioms the whole app rests on

Four files, no implementation yet: `Kernel/Cfs/cs/cs_eventids.HC` (155 ids), `cs_perfids.HC` (one),
`cs_msg.HC` (the two config headers, the two enums, the six table-entry types, the 43 wire
messages) and `cs_global.HC` (`CS_TableWrapper_t`, `CS_AppData_t`, the global, and `cs_app.h`'s
eighteen inline accessors). Measured against NASA's own compiler before a line of CS logic
exists:

```
cfs-structs   410 → 467   (+57, every CS class)
cfs-padding   410 → 467   (+57), 88 → 91 carry explicit padding
cfs-constants 1480 → 1725 (+245), and "NASA does not define" back to 35
cfs-fnptr      18 → 19
cfs-inblob   1269 → 1292
cfs-xlat      2803, unchanged — nothing is exercised yet
```

**All 57 layouts matched on the first probe**, including the two the advisor flagged as new in
kind: `CS_Def_Tables_Table_Entry_t` is **42 bytes, align 2** and `CS_Def_App_Table_Entry_t` is
**22**, the port's first odd-sized classes. A `uint16` followed by a 40-character name packs
exactly, and `CS_AppData` holds an array of 24 of each — so the stride is 42, not 48. A port that
rounded the entry up would place `DefaultAppDefTable` 144 bytes later and the CDS image would stop
matching NASA's, silently.

Three tail/interior pads had to be written out, all three measured rather than reasoned:
`CS_Res_Tables_Table_Entry_t` needs **6 bytes** after its 40-char name (74 → 80, for the leading
`uint64`), `CS_TableWrapper_t` needs **4** after its two `CFE_TBL_Handle_t`s, and `CS_AppData_t`
needs five separate gaps (2, 4, 4, 4, and 4 of tail).

#### The count that rose in the wrong bucket, for the second time

Adding CS to `cfs_dirs.APPS` made `check_constants` compare 1,571 — up from 1,480, which looks
like progress. The other number went **35 → 189**: 154 names filed as *"NASA does not define
this"*. Every CS event id, the performance id, the four MsgIds and the forty command codes. The
cause is the one already written beside MM's five probe headers: `cs_app.h` reaches the
`CS_INTERNAL_*` and `CS_INTERFACE_*` values, so the *compared* count moved and the gate passed,
while a name the probe cannot **see** is indistinguishable from a name this port invented. Six
headers later it is 1,725 and 35 — the baseline exactly.

This is the same shape as `gate-blindspot-unpaired-types` and it has now cost two measurements.
The rule it earns: **after teaching a gate about a new directory, read every bucket, not the one
with the pass in it.**

#### The two idioms, measured before 3,000 lines depend on them

`tests/exec/cases/e_tbl_wrapper_idiom.hc` → `0000000503a0b300`. CS works almost entirely through a
`CS_TableWrapper_t *tw` rather than naming one of its six checksum types, and two compiler
behaviours carry that design — neither of which would fail loudly:

- **A pointer difference scaled by the pointee.** NASA's `CS_GetTableId` is `return tw -
  CS_AppData.Tbl;` — the table id recovered by subtracting the array base. HolyC scales it, so
  `&Tbl[5]` gives **5**. The negative control casts both sides to `U8 *` and gets **200** (byte 3
  reads `0xC8`), *and* carries into the next field, which is what makes the two answers
  distinguishable rather than merely different.
- **An indirect call through an arrow member.** `CS_CallTableUpdateHandler` is
  `tw->UpdateHandler(tw)`. This is the *neighbour* of the open limit recorded as
  `holyc-call-arrow-member` — there the arrow is applied to a call's **result**, here a function
  pointer is read through `->` and called in one expression — so it was worth a measurement rather
  than an assumption. Each handler writes `0xA0 | id` or `0xB0 | id` into the object it was
  handed, so the transcript says **which** pointer arrived, not just that something ran.

Three negative controls, three caught: the unscaled difference, the two handlers swapped
(`a0b3` → `b0a3`), and the `NULL` guard removed — which **hangs**, because four of CS's six
wrappers have no update handler at all and `CS_CallTableUpdateHandler` is called for every one.

#### What CS reads, and why that is the one new hazard

MD printed addresses and MM wrote through the PSP. **CS calls `CFE_ES_CalculateCRC(addr, size,
...)` with a raw pointer** — the first app in this port that dereferences memory directly — so the
bytes at that address have to be identical in the native oracle and in the RISC-V guest or the
checksum differs and nothing says why. All six checksum types resolve into driver-owned buffers:

| | where the bytes come from | agreed? |
|---|---|---|
| EEPROM table | `StartAddress` from the def table, which the driver writes | yes, by construction |
| Memory table | same | yes |
| cFE core segment | `CFE_PSP_GetCFETextSegmentInfo` | **already** a fixed 7-byte string, for this reason |
| OS core segment | `CFE_PSP_GetKernelTextSegmentInfo` — the one new simulated PSP function | will be its sibling |
| Tables table | `CFE_TBL_GetAddress`, both halves loading identical content | yes, if the def table names no CS results table |
| App table | `CFE_ES_GetAppInfo`'s `CodeAddress`/`CodeSize` | driver buffer |

The addresses themselves still differ between the halves, and that is fine — a CRC over equal
bytes is equal wherever the bytes live. What is not fine is **printing** one, so the exercises use
the technique `mm_utils.c` forced: print a comparison against the pointer the driver handed over,
never the pointer.

#### One thing read ahead, because it changes `cs_init.c`'s shape

`CS_InitAllTables` fills `CS_AppData.Tbl` from a **`static const` array of designated
initialisers** holding `&CS_AppData.HkPacket.Payload.<member>` addresses and function pointers,
then copies one into place per type with `*tw = TABLE_INITIALIZERS[TableId]` — a 112-byte struct
copy through a bare pointer, which is HolyC limit #21. So step 2 lands squarely on two recorded
shapes at once: `generated-table-init-order` (a static C table becomes a runtime fill, and a
reader that runs before the fill sees zeros, silently) and the 8-byte truncation. Both are known;
noting them here so the file is written for them rather than debugged into them.

### Step 1 exercised — 2803 → 3052, and 65 of 71 functions actually run

Four blocks, each its own function on both halves: `cs_block_utils`, `cs_block_compute`,
`cs_block_tblproc`, `cs_block_child`. Transcript **2803 → 3052** byte-identical.

**The count `check_coverage` cannot give.** It reports every function present and is blind to
whether a single line executes, so here is the split by hand:

| | functions | driven | not driven |
|---|---|---|---|
| `cs_utils.c` | 33 | 33 | — |
| `cs_compute.c` | 16 | 13 | `CS_GetTableAddr`, `CS_ReleaseTableAddr`, `CS_RefreshTableHandleAndAddress` |
| `cs_table_processing.c` | 22 | 19 | `CS_RegisterResultTable`, `CS_RegisterDefinitionTable`, `CS_TableInit` |
| | **71** | **65** | **6** |

**The denominator was wrong when this table was first written, and finding out why found a gate
blind spot.** It said 68, taken from `check_coverage`'s count moving 852 → 920 — and that gate
MISSES A DEFINITION WHOSE RETURN TYPE IS ON ITS OWN LINE, which is what clang-format does when a
signature will not fit:

    CFE_Status_t
    CS_TableInit(CS_TableWrapper_t *tw, const char *F, CFE_TBL_CallbackFuncPtr_t CallBack)
    {

The name's line then has no type prefix and the pattern requires one. **Fifteen of NASA's
definitions are in that shape** across cFE, MD and CS — `CS_ComputeEepromMemory`,
`CS_RefreshTableHandleAndAddress`, `CS_TableInit`, `CFE_TBL_WriteHeaders`, `CFE_ResourceId_FindNext`
and ten more — so this gate never required any of them to exist. `check_signatures` has the same
gap from the same cause (`[ \t]+` between the type and the name) and so never compared their
signatures; `CS_TableInit`'s third parameter is a **function pointer**, which is the kind of
parameter that gate exists to check. **Neither gate caught the other's gap, because both share the
assumption** — a cross-check is worth only the inputs the two tools do not share, which is the
fifth entry under that heading in this project's notes. All fifteen happen to be translated, which
is luck and not evidence.

**All six undriven functions are on one path: registering CS's own tables with cFE table
services.** Nothing reaches them until a table of CS's exists, and creating one is
`CS_InitAllTables` — `cs_init.c`, step 2. The *failure* half of that path IS driven: with the eight
wrapper handles set to `CFE_TBL_BAD_TABLE_HANDLE`, `CS_HandleTableUpdate` takes its error arm,
`CS_RefreshTableData` answers `CS_ERR_NOT_FOUND`, and `CS_ComputeTables` logs and gives up — which
is not filler, because "the table CS was told to watch is not registered any more" is most of what
CS has to survive.

#### The wrappers are hand-built, field for field, on both halves

`CS_InitAllTables` is step 2, so `cs_setup()` mirrors NASA's `TABLE_INITIALIZERS` by hand with
eight driver arrays standing in for the buffers table services will allocate. Two deliberate
differences from NASA's list, both stated at the site:

- **`MaxBytesPerCycle` is set.** `cs_app.c` sets it, and that is step 3. At zero
  `CS_DoChecksumChunk` clamps every cycle to zero bytes, `CurrOffset` never advances,
  `CS_IsChecksumComplete` is never true — and the three recompute child tasks' `while
  (!DoneWithEntry)` **does not terminate.** A QEMU timeout that looks exactly like a codegen bug.
  It is set to 64, *below* either source buffer, so chunking and resume-from-`ByteOffset` are what
  the transcript sees rather than a single-shot CRC.
- **The eight table handles are explicitly `CFE_TBL_BAD_TABLE_HANDLE`.** NASA leaves them zero and
  lets registration fill them in. **Zero is a valid cFE table handle**, and MD has registered
  tables by the time this runs — so a wrapper left at zero would make `CS_SetDefEntryState`'s
  `CFE_TBL_Modified` mark one of *MD's dwell tables* as changed.

And `cs_setup` prints `handlers=1111`: whether each of the four `UpdateHandler` members is
non-NULL. Each is a file-scope reference to a function, which is precisely what limit #22 zeroes
when some other frame grows — and here the symptom would **not** be `mepc=0`.
`CS_CallTableUpdateHandler` guards with `if (tw->UpdateHandler)`, so a zeroed member makes it
quietly do nothing, the results tables never fill, and the transcript differs somewhere downstream
with no hint why. One line converts that into a named failure where it happened.

#### An event that prints an address is still drivable — close the port

`CS_OneShotChildTask`'s finish event renders `Address: 0x%08X`, so it is the fourth kind of event
in this port that cannot cross the differential. MM's answer was to leave such branches undriven.
The better answer, used here: save `CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort`, clear it, call,
restore. The event is still built, filtered, counted and transmitted — every line of
`EVS_SendEvent` runs — and only the human-readable copy is suppressed. `MessageSendCounter` is the
witness that it fired (`csh_oneshot_sent 2`), and the `No subscribers for MsgId 0x809` line that
follows comes from SB rather than the port, so it is still compared.

**And the one-shot's answer is compared against the table path's.** The same 200 bytes are then run
through `CS_ComputeEepromMemory` and `csh_oneshot_agrees 1` asserts the two agree. A one-shot that
disagreed with the background walk would be useless, and nothing else in CS says they must match.

#### Three assertions that are about what a function does NOT do

- `CS_ProcessNewEepromMemoryDefinitionTable`'s `memset` is the whole safety property: a ground
  table load that **removes** a region must stop CS checksumming it. The results entries are
  poisoned with `0xDEAD0000 + k` first, and the line reads both the slot that was kept and two
  slots that had to be wiped.
- `CS_ProcessNewAppDefinitionTable` copies the state and the **name only** — no address, no size,
  because an app's code address is looked up every cycle. Checked by poisoning `StartAddress` and
  asserting it is **zero** afterwards, which is the opposite of the EEPROM handler's check.
- `CS_InitializeDefaultTables` clears only `Name[0]`, not the whole name. Read at `Name[0]` **and**
  `Name[1]`, so a translation that cleared the whole buffer would pass a weaker check and fail
  this one.

#### Two traps paid for again

`CS_CheckRecomputeOneshot`'s call is hoisted out of the print on both halves — **fourth** time in
this port. C evaluates every argument before printing anything, so an argument that sends an event
emits its line first, while HolyC's `S()`/`D()` pair prints the label and takes the event
mid-line. Reading `CommandErrorCounter` in the same call would be worse: its order against the
call that increments it is unspecified in C.

And `cs_block_compute` had to **move**. Defined beside `cs_setup()`, it referenced driver state
declared 400 lines further down — six undeclared identifiers in C, and worse on the HolyC side,
where a name the compiler has not seen is not always an error. Both CS blocks now sit immediately
before `main()`, after all the simulated OSAL and PSP state.

### The mutations — 53 driven, and every no-op was worth having

Two batches plus three controls. Batch one was written from NASA's sources aiming at the behaviours
the four blocks assert: a check that the assertions **bite**, biased toward covered code by
construction. Batch two asked the opposite question.

```
batch 1   38 applied, 0 anchors lost   35 caught, 3 no-op
batch 2   15 applied, 0 anchors lost   14 as predicted, 1 not
control    3 attempts                   1 valid
```

#### Batch one's three no-ops were three different things

| | |
|---|---|
| **25** `CS_RefreshAppSizeAndAddr` does not try the LIBRARY table | **a real exercise gap** |
| **37** `CS_HandleTableUpdate` treats `INFO_UPDATED` as a failure | **correctly unreachable** in step 1 |
| **38** "a global rename -- the no-op control" | **a worthless control** |

**25, and the second attempt is the finding.** The block drove a real app (`CFE_EVS`, so the
fallback is never reached) and a name that is neither (`NO_SUCH_APP`, so it runs and fails — same
answer). The first fix named `ESLIB`, the library the ES resource block creates, and *still* came
back `CS_ERR_NOT_FOUND`: that block **frees its three records when it is done** —
`rs_freed app=1 lib=1 ctr=1`, right there in the transcript. Borrowing another block's fixture is
`shared-fixture-resource-exhaustion` one step along: not "the table is full" but "the thing I was
pointing at is gone". The block now registers `CSLIB` itself and frees it.

**37 is not a gap and the no-op is the proof.** With no table loaded, the second
`CFE_TBL_GetAddress` answers plain `CFE_SUCCESS`, so the one branch in CS that calls an update
handler outside registration cannot be reached while the eight wrapper handles are invalid. Step 2's
exercise loads a registered table and reaches it.

#### Batch two measured the driven/undriven split instead of reasoning about it

Seven mutations were placed **inside the six functions this document claims are not driven**. Each
one *must* be a no-op; if any changed the transcript the claim was reasoning dressed as
measurement. **All seven came back no-op** — `CS_GetTableAddr`, `CS_ReleaseTableAddr`,
`CS_RefreshTableHandleAndAddress`, `CS_RegisterResultTable`, `CS_RegisterDefinitionTable`,
`CS_TableInit`, and `CS_HandleTableUpdate`'s unregister loop.

**And the one wrong prediction was a second gap.** Deleting
`CS_ProcessNewTablesDefinitionTable`'s `CS_CheckResTableNameMatch` branch changed nothing: the two
names driven were a *definition* table of CS's and somebody else's table, never a **results** table
of CS's. The two branches differ in a way worth pinning — the DEF match aims the wrapper's
`ResTblPtr` at the entry, the RES match does **not**, it only takes the handle and claims
ownership. Closed, and the assertion is both halves of that:

```
cst_proc_tbl_res name10=[CFE_EVS.ResEepromTbl] owner10=1 state10=1
cst_proc_tbl_res_noptr 1
```

#### The no-op control took three attempts, and the first two are the lesson

- a **comment typo** (what #38 actually was) proves the file recompiled and nothing else;
- a **symbol rename** of a NASA function — `CS_IsChecksumComplete` across all seven occurrences — is
  **refused by `check_coverage`**, which exists to notice exactly that. The tell is `catch` with
  **zero** transcript diff lines: a gate refusal, not a behaviour change. So "a global rename is a
  no-op control" no longer describes this project; the gates grew and they object on purpose;
- a **local variable rename** (`Loop` → `Idx` in one function) is the one that works. No gate reads
  a local, so it measures the harness rather than the gates. NO-OP, as it must be.

### Step 2's exercise was weak, and 14 mutations said so

`cs_init.HC` got its own batch. The first run was **6 caught, 8 no-op** — one the control, seven the
same mistake seven times: the block asserted that things **happened** and never **what was written**.

| no-op | why it slipped through |
|---|---|
| the background cycle is never subscribed | nothing asked SB what CS listens to |
| the housekeeping packet is sized wrong | nothing read the packet's size |
| the EEPROM type gets the MEMORY default table | both defaults are all-zero; only the ADDRESS distinguishes them |
| the TABLES type gets `DefStateOffset` 8 instead of 0 | nothing read the descriptor fields |
| an error is reported for a type with no event id | **no table init ever failed** |
| a failed type is not disabled | its state was **already** DISABLED |
| the OS segment points at the cFE one | the sizes were read, the BYTES were not |

The fixes assert the written values: `CFE_SB_GetDestPtr` on each of four routes
(`cmd=1 hk=1 bg=1 other=0`, the fourth being a MsgId CS must **not** be on), `CFE_MSG_GetSize` on
the housekeeping packet (**80**, not 64), a `csi_tbl_desc` line per type carrying `DefEntrySize`,
`ResEntrySize`, `DefStateOffset` and a **comparison** that `DefaultDefinitionPtr` names the right
array, and a CRC of the OS code segment so the two segment **addresses** are pinned and not just
their sizes.

#### The failing-init arm took three attempts, and I was wrong twice

- **Draft one** exhausted TBL's memory pool. It printed `rc=0` — the knob does not reach that path —
  and the comment beside it *claimed the four types had failed*. They had not. The transcript said
  so and I nearly did not read it.
- **Draft two** moved a single call to the end of the block. Also `rc=0`: the **second**
  `CS_InitAllTables` succeeds.
- What fails is the **third**, and not because of any knob here: the second leaves a `CFE_TBL_Load`
  pending on each single-buffer table — CS never calls `CFE_TBL_Manage`, so nothing completes it —
  and the next load answers `CFE_TBL_ERR_LOAD_IN_PROGRESS`, `0xCC000012`. Both calls are printed,
  because otherwise a reader cannot tell which call the four events belong to.

#### One of the seven is a PROVABLE no-op, and its neighbour is what proves it

`if (ErrorEventID != 0)` can never be false when it is evaluated. `CS_TableInit` returns
`CFE_SUCCESS` immediately for a NULL filename, and `TABLE_FILENAME_MAP` is NULL for exactly the two
types whose event id is zero — so only the four types that *have* an id can reach that block. A
mutation replacing the guard with `TRUE` is a no-op and will stay one.

**It is still a real guard**, and the mutation that shows what it guards is its neighbour: giving a
code-segment type a filename in `TABLE_FILENAME_MAP` **is caught**, because that type can then fail
and would try to send event id 0. The guard and the NULL filename are one mechanism stated twice,
which is why only one of the two mutations bites. Recorded at the site in `cs_init.HC`.

#### And one was vacuous for the oldest reason in this project

"A failed type is not disabled" stayed a no-op after the failing init existed, because by that point
**every state was already DISABLED** — the first init loads each table from memory, which disables
it — so writing `DISABLED` again changed nothing. The assertion was reading a value that was there
for another reason. The four states are now forced **ENABLED** immediately before the failing call.
Poison-first, which is the rule this project keeps relearning.

### Step 3 — the five command files, the dispatcher and the app: **CS is 100%**

2,924 lines, 49 functions, gated in one commit because `CS_AppPipe` and `CS_UpdateCDS` close a
seven-source cycle. Transcript **3228 → 3861** byte-identical, and with it **all 150 of CS's
functions RUN**. Third app, no stand-ins, nothing unexercised.

**SEVEN exercise blocks, one per NASA source.** Limit #22 is the reason — step 1's first draft wrote
one block inline in `main()` and grew that frame enough to make a file-scope `&function` initialiser
read as zero 1,900 transcript lines earlier. Seven small frames cost nothing and make a bisect name
a file.

**They run AFTER `cs_block_init` and none of them may read what it left.** `cs_block_init`
deliberately ends with a `CS_InitAllTables` that FAILED, which is the only way to reach `cs_init.c`'s
error arms, so every wrapper it leaves is in a failed state. Each step-3 block starts from
`cs_setup()`. The rule recorded earlier — *`cs_block_init` must stay last because a later
`cs_setup()` orphans its eight registered cFE tables* — remains true and is now harmless, because
nothing after it reads them.

#### The sticky-flag hazard, stated before it could bite

`RecomputeInProgress` and `OneShotInProgress` are what every busy-path arm needs set, and
`CS_CheckRecomputeOneshot` reads them — so a flag left TRUE makes **dozens** of later handlers take
their refuse path, both halves agree, and the transcript grows while asserting nothing. This driver's
`OS_TaskCreate` never calls the entry function, so a **successful** recompute leaves the flag TRUE
with no child to clear it. Every line that can set a flag PRINTS BOTH, and the blocks reset through
`cs_setup()` between groups. Two arms are then reached *because* of it: the busy arms need no
hand-set flag at all.

#### All four upstream defects are WITNESSED, in pairs one number apart

```
csec_report_nobase cc=1 state_after=1      <- #13 a REPORT command re-enabled a DISABLED entry
csmc_report_nobase cc=1 state_after=2      <-     the Memory twin, same three lines, no write

... EEPROM Entry ID 0 failed: child task in use   <- #14 commanded id was 7
... Memory Entry ID 7 failed: child task in use   <-     the twin assigns outside the `if`

... CFE_ES_CreateChildTask returned:  0xC8000005  <- #16 the EEPROM text
... ES_CreateChildTask returned:  0xC8000005      <-     the Memory text, prefix DROPPED
... OneShot checkum failed, ...                   <- #16 and a spelling nobody greps for
```

#15 — the two busy events that print **uninitialised stack** — cannot cross the differential for the
same reason an event printing a real pointer cannot, so both are driven with the EVS output port
closed and `MessageSendCounter` as the witness. Leaving them undriven, which is what MM did with its
uncomparable events, would leave the defect unproven as well as unexercised.

#### The generated twins, and the identifier gate they produced

`cs_memory_cmds.HC` was generated from `cs_eeprom_cmds.HC` and `cs_app_cmds.HC` from
`cs_table_cmds.HC`, by explicit name maps, because NASA's sources are line-for-line twins. Their
EXERCISES are generated the same way, and the property that makes it worth doing is that the two must
differ in **exactly** the places upstream differs and nowhere else — three places for the first pair,
**none at all** for the second, which was measured: normalising the type words to one token and
diffing `cs_table_cmds.c` against `cs_app_cmds.c` leaves only whitespace, four banner widths and
three `/* command verification variables */` comments. Not one statement. Finding nothing is evidence
only because the same method found five real lines next door.

**And a name map got one word wrong.** `cs_app_cmds.HC:132` assigned
`CS_AppData.RecomputeTablesEntryPtr` where NASA assigns `RecomputeAppEntryPtr`, so CS's app recompute
handed its child task a NULL pointer. **Every gate passed** — the function exists, its signature
matches, both members exist with NASA's layout, every literal is NASA's, the call agrees — and the
HolyC compiler accepted the pointer type mismatch because a cast there RELABELS rather than converts.
The C compiler never saw it: the oracle compiles NASA's C, not the translation. One character in the
transcript caught it, `ptr=1` against `ptr=0`, and only because that line printed the pointer as a
comparison.

So `tools/cfs/check_members.py` now compares, **per function**, every name after a `.` or `->` with
the names NASA's own body for that function uses. Members are the one part of this translation that
is never renamed, which is what makes it possible.

```
cfs-members: 3932 member references across 1042 functions are all members NASA's own body touches
             (45 allowed by a named macro expansion; 35 members NASA touches and the translation
              does not, NOT yet gated)
```

The 45 are five names, each keyed on its **cause** in NASA's body rather than on the name
(`CFE_MSG_PTR` → `.Msg`, `OS_FILESTAT_SIZE` → `.FileSize`, `= { 0 }` / `CFE_TIME_ZERO_VALUE` →
`.Seconds`, `.Subseconds`, `.ticks`), so the same member is still refused where the macro is absent.
Strings are blanked first — `CFE_SB_LockSharedData("cfe_sb_task.c", 310)` otherwise contributes a
member named `c`, five times.

The other direction is 35 cases and they are **not** defects: the first examined is
`CFE_TIME_SetSourceCmd`'s `CommandCounter++` inside `#if (CFE_PLATFORM_TIME_CFG_SOURCE == true)`,
false in this configuration and correctly omitted. Gating it needs NASA's `#if` blocks evaluated.

#### The sibling gate: NASA's own wording

Writing up #16 is what exposed a second hole of the same shape. `check_formats` reads the
CONVERSIONS out of a format string and says nothing about the text around them — and the differential
cannot see that text either, because the two halves are compared to **each other** and both print the
translation's wording. A dropped word, a changed capital, a singular made plural: all pass.

`tools/cfs/check_strings.py` closes it — every literal in the translation must appear **verbatim** in
the NASA source it came from.

```
cfs-strings: 1522 literals verbatim in the NASA source they were translated from
             (1452 paired, 43 via __func__, 26 elsewhere in NASA, 1 exempt)
```

Four normalisations with reasons: C adjacent-literal concatenation folded, printf **length
modifiers** dropped on both sides (`%ld` compares equal to `%d` because StrPrintNV implements none —
but `%d` against `%u` still FAILS), `\'` equal to `'`, and `__func__` substitution anchored to
`Name:` or `Name()` so it cannot match any literal starting with any word.

**Its first full run found a 1:1 violation of my own.** `mm_mem32.HC` printed `Reducing from %u to
%u` where NASA prints `%d to %d` — because the twin `mm_mem16.c` uses `%u` and I had quietly made
NASA's two inconsistent siblings consistent. It is unreachable through the command path (upstream
note #12), so no exercise will ever print it: the transcript is UNCHANGED after the fix, which is the
confirmation that only a static gate could have found it. And a second, `cfe_sb_init.HC` writing
`0x%X` for NASA's `0x%lx` — upper-case hex for lower, the same invisible class as the `%P` note.

The control is the most sympathetic edit a translator can make: **fixing NASA's `OneShot checkum`
typo**, which the gate refuses by name and line.

#### The forty command codes go through `CS_AppPipe`

Direct calls are what the five command blocks do, and they leave `CS_ProcessCmd`,
`CS_VerifyCmdLength` and the forty switch arms UNRUN while `check_coverage` stays green — it is blind
to execution. So all forty are dispatched, each with **its own** correct length from a table
generated out of NASA's own switch: 8 bytes for a bare header, 12 for an EntryID command, 48 for a
name command, and one length for all forty would make thirty-nine take the error arm and look routed.

The **cross-app** assertion a per-app exercise cannot make: MD's dispatcher is driven again *after*
CS's has warmed its three static MsgId caches. CS is the sixth set in one translation unit to name a
static local `CMD_MID`; for one commit all six collided, because a HolyC static local became a global
under its bare name. `csd_md_still_routes cc=1 ec=0` is the only line in the suite that would notice
a regression there.

#### Upstream note #17, and a class of defect no gate here looks for

`CS_VerifyCmdLength` is defined with external linkage in `cs_dispatch.c` and declared in **no**
header — `cs_dispatch.h` declares its two neighbours from the same file and not it. Found by the
oracle failing to compile. Second instance of note #3's shape, in a different repository, and in both
cases a function a test wants first.

Worth stating as a gap rather than a curiosity: **every gate in `tools/cfs` starts from a DEFINITION
and asks whether the translation matches. None starts from a definition and asks whether anyone can
call it.** A header-completeness check would find this class in bulk.

#### Three drafts of the app block, each green and each wrong

1. `csd_bkgnd tbl=0 ent=0` as the background-cycle **route** witness. `CS_DISABLE_ALL_CS_CC` is one
   of the forty dispatched above it, so `ChecksumState` was DISABLED by the time the route was
   tested: the cycle skipped its whole body and printed exactly what *the route went nowhere* prints.
   A route witness that reads the same when the route works and when it does not is not a witness.
2. `csap_init_tables 11 11 11 11 11 11` from `CFE_TBL_HANDLE_IS_VALID`. `CFE_TBL_BAD_TABLE_HANDLE` is
   **-1** and zero is a perfectly good handle — the trap `cs_setup`'s own comment warns about — so the
   two code-segment types, which register nothing, printed `11` like the four real ones. The VALUES
   distinguish them: `0/0 0/0 2/1 4/3 6/5 8/7`.
3. A CDS planted with `OSCSState` ENABLED, to witness the warm boot *through* `CS_AppInit`. Every
   `CS_*_POWERON_STATE` is 1 here, so a planted ENABLED is indistinguishable from the default — and
   the four TABLE states cannot witness a restore at all, because `CS_InitAllTables` DISABLES each one
   when its table loads from memory. The two **code-segment** states are the only ones that can:
   nothing overwrites them. Planted DISABLED, and `csap_init_states ... os=2 cfe=2` is the proof.

#### `CS_AppMain`'s clean-exit event is reachable, and `CFE_TBL_EarlyInit` is not repeatable

The two termination events are a pair: APP_ERROR takes the ERROR arm with RunStatus **and** the last
Result, anything else takes the INFORMATION arm with RunStatus alone. Every other app block in this
port drives only the first, and MD's records that pre-setting `ControlReq` *did NOT work*.

It works. MD's note is true **there** for a different reason: MD's AppInit was failing, so APP_ERROR
was written over the control request's value before `CFE_ES_RunLoop` ever looked. The lever is
RunLoop's **second** test, on the app RECORD's `ControlReq`, which writes the request into
`*RunStatus` and returns false. With an AppInit that SUCCEEDS,
`App terminating, RunStatus:0x00000002` is in the transcript beside `RunStatus:0x00000003,
RC:0xCA000005`.

That needs **one** AppInit to succeed and there is only one available. A draft called `CS_AppInit()`
directly for the success path and wanted a second successful one inside `CS_AppMain` — which needs the
table registry cleared again, and the second `CFE_TBL_EarlyInit` printed `No free MemPool slots
available`, allocated nothing, and every table registration answered `0xC4000001`. Each EarlyInit
leaks its two pools and `CFE_PLATFORM_ES_MAX_MEMORY_POOLS` is finite. So AppMain does the only
successful init and the witnesses are read out of the global it leaves behind.

#### A vacuous POISON, which is a new shape

`sed -i '' '131s/RecomputeAppEntryPtr/.../'` — off by one. Line 131 was a different assignment, **sed
matched nothing, the file was unchanged**, and the gate under test passed. That reads exactly like
*the gate is blind to the defect it was written for*, and it nearly sent me back to rewrite the gate.
The control on line 132 fails and names the function.

The rule: **a control must be shown to have CHANGED something.** Print the poisoned line back before
believing a passing gate. Every other entry in this document's vacuity list is about an assertion
that looked at nothing; this is the first where the *poison* was the vacuous half.
