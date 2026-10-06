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
| ~~`cfe_tbl_task.c`~~ | ~~218~~ | **GATED** — `CFE_TBL_TaskMain` is real, so tbl is the first module whose object table names three real functions |
| `cfe_tbl_dispatch.c` | 276 | the non-EDS branch, and LAST: it is blocked behind `task_cmds.c`. One thin stand-in (`CFE_TBL_TaskPipe`) covers it meanwhile |
| `cfe_tbl_load.c` | 953 | |
| `cfe_tbl_api.c` | 1,107 | the public API, 24 functions |
| `cfe_tbl_task_cmds.c` | 1,115 | |

(`cfe_tbl_eds_codec.c` and `cfe_tbl_eds_dispatch.c` are listed too and are correctly absent —
`CFE_EDS_ENABLED` is 0 in this configuration and `check_manifest.py` owns that call.)

tbl is at **4,608 of 7,780 lines, 59%**. `registry.c` cost **zero** new stand-ins in the end
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
