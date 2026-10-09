# Notes on NASA cFS upstream, found while translating it

Things noticed in NASA's source while doing the 1:1 HolyC translation. Nothing here is changed in
the translation -- a 1:1 port reproduces what upstream does, including what looks wrong -- but
the differential oracle pins each one, so if upstream changes, `make cfs-xlat-smoke` fails and
names the line.

## 1. CFE_SB_CmdTopicIdToMsgId returns a telemetry id for instance 0

cFE pinned at 546a0025 (vendor/cFE), file modules/sb/fsw/src/cfe_sb_msg_id_util.c.

```c
CFE_SB_MsgId_Atom_t CFE_SB_CmdTopicIdToMsgId(uint16 TopicId, uint16 InstanceNum)
{
    if (InstanceNum == 0)
        MsgIdValue = CFE_SB_GlobalTlmTopicIdToMsgId(TopicId);   /* <-- Tlm, in the Cmd function */
    else
        MsgIdValue = CFE_PLATFORM_CMD_TOPICID_TO_MIDV(TopicId);
    return MsgIdValue;
}
```

The sibling `CFE_SB_TlmTopicIdToMsgId` has the identical instance-0 branch, also calling
`CFE_SB_GlobalTlmTopicIdToMsgId`. So both the command and the telemetry mapping resolve to the
same global-telemetry base for instance 0.

## Why it is not merely cosmetic

With the stock non-EDS mapping (modules/core_api/config/default_cfe_core_api_msgid_mapping.h and
default_cfe_core_api_base_msgid_values.h):

| base | value |
|---|---|
| DEFAULT_CFE_PLATFORM_CMD_MID_BASE | 0x1800 |
| DEFAULT_CFE_PLATFORM_TLM_MID_BASE | 0x0800 |
| DEFAULT_GLOBAL_CMD_MID_BASE | 0x1860 |
| DEFAULT_GLOBAL_TLM_MID_BASE | 0x0860 |

so for a topic id T:

    CFE_SB_CmdTopicIdToMsgId(T, 0)  ->  0x0860 | T     (a TELEMETRY stream id)
    expected, by symmetry           ->  0x1860 | T

In the cFS v1 message-id format the id *is* the CCSDS stream id, so bit 0x1000 is the packet TYPE.
Returning 0x0860|T for a command topic yields an id whose type bit says telemetry.

## Supporting evidence that this is a copy-paste slip, not intent

1. `CFE_SB_GlobalCmdTopicIdToMsgId` is defined in the same file and declared publicly in
   cfe_sb.h:1008, but in the non-EDS build nothing calls it. Its only reference anywhere is from
   modules/core_api/config/eds_cfe_core_api_msgid_mapping.h:56, i.e. the EDS path.
2. The EDS implementation of the same two functions (modules/sb/fsw/src/cfe_sb_eds_msg_id_util.c)
   keeps command and telemetry firmly distinct -- Listener vs Publisher components through
   CFE_MissionLib_MapListenerComponent / MapPublisherComponent.
3. The `#ifndef CFE_PLATFORM_CMD_TOPICID_TO_MIDV / #define ... 0` fallbacks at the top of the file
   are dead in a stock build, because the default mapping header defines all four. So the wrong
   value is reachable rather than masked by a zero default.

## Reachability: LATENT, not live in a stock build

Checked, because the severity turns on it entirely:

- In-tree, nothing calls `CFE_SB_CmdTopicIdToMsgId` directly except the `CFE_SB_LocalCmd...`
  wrapper, which passes `CFE_PSP_GetProcessorId()`.
- cmake/sample_defs/targets.cmake sets `cpu1_PROCESSORID 1` and `cpu2_PROCESSORID 2`, and
  cmake/global_functions.cmake:316-318 defaults an unset PROCESSORID to the target id, which
  starts at 1. So the instance-0 branch is not taken on a stock build.

It is reachable two ways: a mission that configures PROCESSORID 0, and any application calling
`CFE_SB_CmdTopicIdToMsgId(topic, 0)` directly -- it is public API, declared in cfe_sb.h:964, and
the header documents instance 0 as the reserved "global" value, so passing it is the documented
way to ask for a global command topic. That is exactly the call that returns a telemetry id.

## Still not verified

- Whether upstream already has an issue or fix for this; the vendored checkout is squashed to a
  single commit, so `git log -L` on the line returns only that commit and says nothing about when
  the line was written. Worth searching the nasa/cFE tracker before reporting it.

## What this port does about it

Nothing: the HolyC translation reproduces it exactly, with a comment, because it is a 1:1
translation. The differential oracle holds both languages to the same answer. These four lines
are in the pinned transcript, produced by NASA's own C:

    topic_cmd  i0=0x0865 i1=0x1805
    topic_tlm  i0=0x0865 i1=0x0805
    topic_glob c=0x1865 t=0x0865
    topic_locl c=0x1805 t=0x0805

`topic_cmd i0` is the defect: 0x0865 where 0x1865 was meant. `topic_glob c` shows the correct
value exists -- `CFE_SB_GlobalCmdTopicIdToMsgId` computes it -- and nothing in the non-EDS build
ever calls it. If upstream fixes this, `topic_cmd i0` becomes 0x1865, the C and the translation
disagree, and the gate says which line.

## 2. CFE_SB_MessageStringGet does not null-check its source

`modules/sb/fsw/src/cfe_sb_util.c`: `CFE_SB_MessageStringGet` checks `DestStringPtr` but not
`SourceStringPtr`, and then dereferences the source in the default-string test
(`SourceMaxSize == 0 || *SourceStringPtr == 0`). The `||` short-circuits, so a NULL source with
`SourceMaxSize == 0` is safe, but NULL with a nonzero size faults. Its sibling
`CFE_SB_MessageStringSet` does check both. Translated as written; the oracle exercises only the
paths that are safe to exercise in both languages.

## 3. OS_ConsoleWrite is a public function with no declaration anywhere

`src/os/shared/src/osapi-printf.c` defines

    int32 OS_ConsoleWrite(osal_id_t console_id, const char *Str)

with external linkage, directly under a banner comment reading

    /*
     *********************************************************************************
     *          PUBLIC API (application-callable functions)
     *********************************************************************************
     */

and it is declared in **no** header — checked across the whole of `src/os` (`inc/`,
`shared/inc/`, every backend). So a caller outside the module has to write its own prototype,
which is exactly what `tests/osal/oracle_printf.c` does and says so at the declaration.

It is not a latent bug the way finding 1 is — nothing in-tree calls it from outside
`osapi-printf.c`, where the definition precedes every use — but it means the function is either
public and under-declared, or internal and should be `static`. Reproduced, not fixed: the
translation keeps it non-static so the two sides have the same linkage.

## 4. OS_DeleteAllObjects leaves rwlocks and filesystems behind

`OS_CleanUpObject` in `src/os/shared/src/osapi-common.c` switches on the object type and
deletes it. It has cases for TASK, QUEUE, BINSEM, COUNTSEM, MUTEX, MODULE, TIMEBASE, TIMECB,
STREAM, DIR and CONDVAR — and **none for RWLOCK or FILESYS**. Both fall to `default: break`.

`OS_DeleteAllObjects` loops until a pass deletes nothing, so the leftovers do not even extend
the loop; it simply returns with them still there. `OS_API_Teardown` then sets the shutdown
flag, after which nothing can be created *or iterated*, so the leftovers become unreachable
rather than cleaned.

The gated transcript shows it directly:

    c_delall  before=12 after=3
    c_left    rwlock=1 filesys=2 task=0 queue=0

A filesystem arguably should outlive a teardown — it is closer to a mount than to a resource.
A read/write lock is harder to justify: it is the same kind of object as a mutex, and mutexes
*are* deleted. `OS_OBJECT_TYPE_OS_RWLOCK` is one of the newer types, and the switch looks like
it was simply not extended with it.

Reproduced, not fixed. If upstream adds the cases, `c_left` changes and the gate says so.

## 5. CFE_FS_ExtractFilenameFromPath rejects a path whose only separator is the first byte

`modules/fs/fsw/src/cfe_fs_api.c` finds the last `/` and then tests

```c
if (DirMarkIdx > 0)
```

not `>= 0`. So `"/name"` — a file at the root of a virtual mount, whose only separator is at
index 0 — returns `CFE_FS_INVALID_PATH` and leaves the output buffer untouched, where
`"/a/name"` returns `"name"`. Every other shape works: no separator at all is also
`INVALID_PATH`, and a trailing separator gives an empty filename and `CFE_SUCCESS`.

The gated transcript has all four:

    fs_xf       rc=0          [ci_lab.so]     /cf/apps/ci_lab.so
    fs_xf_bare  rc=-973078526 []              bare.txt, no separator
    fs_xf_root  rc=-973078526 []              /name, separator at index 0
    fs_xf_trail rc=0          []              /a/b/, empty filename

Whether this is intent is unclear. The function's doxygen says only "Extracts the filename from
a given path", and a cFS deployment puts files under `/cf` or `/ram`, so a root-level file may
simply never occur. Reproduced, not fixed: a translation that wrote `>= 0` would be more useful
and would no longer be NASA's.

## 6. The separator component reads one byte before checking that any input is left

Also in `cfe_fs_api.c`, `CFE_FS_ParseInputFileName_SeparatorComponent`:

```c
while (*Ctxt->InputPtr == Ctxt->ComponentTerm && Ctxt->InputLen > 0)
```

The dereference is evaluated first and the length check second. It cannot underflow —
`InputLen > 0` is still in the condition, so the decrement never runs at zero — but with the
`CFE_FS_ParseInputFileNameEx` form that takes an `InputBuffer` and an `InputBufSize` rather
than a NUL-terminated string, it can read one byte past the caller's buffer. With a terminated
string the byte it reads is the NUL, which is why this is invisible in normal use.

Reproduced in the order NASA wrote it, with a comment at the site. Swapping the two halves
would be the fix and would also be a behaviour change this port is not entitled to make.

## 7. fs/CMakeLists.txt lists two of its three sources twice

```cmake
set(fs_SOURCES
    fsw/src/cfe_fs_api.c
    fsw/src/cfe_fs_priv.c
    fsw/src/cfe_fs_api.c      # again
    fsw/src/cfe_fs_priv.c     # again
    fsw/src/cfe_fs_objtab.c
)
```

Harmless — CMake compiles each source once per target regardless — and noted only because it is
exactly the shape that would fool a manifest parser into reporting five sources where there are
three. `tools/cfs/check_manifest.py` deduplicates, and it reports `fs 3 uncond 1249 lines`.

## 8. The core version description is a pointer into dead stack

`CFE_Config_SetupBasicBuildInfo` in `modules/config/fsw/src/cfe_config_init.c` builds the
version string into a **local array** and stores it:

```c
char VersionString[CFE_CFG_MAX_VERSION_STR_LEN];
...
CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "cFE", CFE_SRC_VERSION,
                            CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);
CFE_Config_SetString(CFE_CONFIGID_CORE_VERSION_DESCRIPTION, VersionString);
```

and `CFE_Config_SetString` copies nothing:

```c
Entry->ActualType      = CFE_ConfigType_STRING;
Entry->Datum.AsPointer = Ptr;
```

So from the moment `CFE_Config_SetupBasicBuildInfo` returns,
`CFE_CONFIGID_CORE_VERSION_DESCRIPTION` holds a pointer into a dead stack frame. Every other
string the registry holds is a literal or a pointer into `GLOBAL_CONFIGDATA`, both of which
have static storage; this is the only one that does not.

Measured, with NASA's unmodified C in the oracle, reading the id a few calls later:

    [cFE v7.0.1+de251(Draco) DEV BUILD, based on v7.0.1, EDS disa]

where the string written was

    [cFE v7.0.1+dev1 (Draco) DEV BUILD, based on v7.0.1, EDS disabled]

`"v7.0.1+dev1 "` has become `"v7.0.1+de251"` and the tail is cut: the frame was reused. The
value is whatever happens to be on the stack, so it is not reproducible across machines, which
is why this one id is **excluded from the differential transcript** — both sides would print
different garbage and the gate would fail for a reason that has nothing to do with the
translation. What the transcript does assert is that the id was SET at all, i.e. that it does
not read back as the registry's `"[unknown]"` fallback.

It matters in flight: `ES_NOOP` and the `CFE_ES_HousekeepingTlm` version fields read this id.
cFE's own generated platform table shows the right pattern three lines away —
`cfe_platform_cfg.c.in` declares each array descriptor `static const` precisely because
`CFE_Config_SetArrayValue` retains the pointer. The fix would be a `static` on
`VersionString`, and it is NASA's to make.

Reproduced, not fixed. (The translation hit the same hazard independently: the first version of
`tools/cfs/gen_platform_config.py` reused one local descriptor for all three arrays, and the
transcript read `NumElements` as 2156050768.)

## 9. CFE_EVS_WriteLogDataFileCmd guards a cFE status with OS_SUCCESS

`modules/evs/fsw/src/cfe_evs_log.c` builds `Result` from `CFE_FS_ParseInputFileNameEx` (a cFE
status) and from `CFE_STATUS_EXTERNAL_RESOURCE_FAIL`, and then tests it against OSAL's success
code:

```c
Result = CFE_FS_ParseInputFileNameEx(...);
...
    Result = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
...
if (Result == OS_SUCCESS)      /* <- OS_SUCCESS, not CFE_SUCCESS */
```

Both are 0, so the guard is correct — by coincidence of value rather than by type. It is the
only place in EVS that mixes the two namespaces, and every other comparison on the same
variable in the same function uses `CFE_SUCCESS`. Reproduced as written, with a comment at the
site: changing it would be a readability fix this port is not entitled to make, and if upstream
ever gave the two codes different values the transcript would be the thing that noticed.

## 10. CFE_EVS_SendHkCmd's "clear unused" loop never advances the pointer

`modules/evs/fsw/src/cfe_evs_task.c` fills the housekeeping packet's per-app array by walking
`AppTlmDataPtr` forward over the registered apps, and then clears the rest of the array:

```c
    for (i = 0, j = 0; j < CFE_MISSION_ES_MAX_APPLICATIONS && i < CFE_PLATFORM_ES_MAX_APPLICATIONS; i++)
    {
        if (EVS_AppDataIsUsed(AppDataPtr))
        {
            ...
            ++j;
            ++AppTlmDataPtr;        /* <- advances here */
        }
        ++AppDataPtr;
    }

    /* Clear unused portion of event state data in telemetry packet */
    for (i = j; i < CFE_MISSION_ES_MAX_APPLICATIONS; i++)
    {
        AppTlmDataPtr->AppID                      = CFE_ES_APPID_UNDEFINED;
        AppTlmDataPtr->AppEnableStatus            = false;
        AppTlmDataPtr->AppMessageSentCounter      = 0;
        AppTlmDataPtr->AppMessageSquelchedCounter = 0;
                                    /* <- and NOT here */
    }
```

The second loop writes the same entry `CFE_MISSION_ES_MAX_APPLICATIONS - j` times. Every slot
after the first unused one keeps whatever the previous housekeeping cycle left in it, so once an
app unregisters its `AppID`, enable status and counters stay in the downlinked packet
indefinitely — a ground display reading the array sees apps that are gone.

It is not caught by the first loop's bound, because the two loops share `i` but only the first
one uses it as the AppData index; `j` is the count of entries actually written.

**Live, not latent.** The command is the periodic housekeeping request, so this runs every cycle
in a stock build. It is invisible as long as no app ever unregisters, which is the normal case
and is presumably why it has survived.

Translated as written, with a comment at the site. The differential transcript is what makes
that safe to say: both sides reproduce the stale entries identically, and a port that "fixed" it
would differ from the flight software it claims to be.

## 11. MM_FillMem does not fill with the commanded pattern past 50 bytes

MM pinned at `0a767de5` (vendor/MM), file `fsw/src/mm_load.c`.

```c
uint8 *FillBuffer = (uint8 *)&MM_AppData.FillBuffer[0];

/* Create a scratch buffer with one fill segment */
for (i = 0; i < (MM_INTERNAL_MAX_FILL_DATA_SEG / sizeof(uint32)); i++)
{
    FillBuffer[i] = CmdPtr->Payload.FillPattern;      /* <-- a BYTE pointer, 50 iterations */
}
```

`FillBuffer` is a **byte** pointer and the loop runs `200 / 4 = 50` times. So the scratch segment
gets the pattern's low byte in its first **fifty** bytes and keeps whatever
`MM_AppData.FillBuffer` held in the other **150**. The intent is plainly
`((uint32 *)FillBuffer)[i] = FillPattern` — 50 words, 200 bytes, pattern throughout — and the
`sizeof(uint32)` in the bound is what says so.

**This is the generic fill**, taken for `MM_MemType_RAM` and `MM_MemType_EEPROM`; the three
width-specific fills (`MM_FillMem8/16/32`) write the pattern correctly through the PSP and are
unaffected.

### Reachability: LIVE, on the default configuration

`MM_FillMemCmd` dispatches RAM and EEPROM fills straight to it. A ground `MM_FILL_MEM_CC` of more
than 50 bytes to a RAM address leaves the tail holding stale buffer contents — on the first fill
after boot that is BSS zero, and afterwards it is **the previous fill's pattern**, because the
scratch buffer is in `MM_AppData` and is never cleared.

### What the differential pins

Into an array poisoned with `0xBB`, a 200-byte fill of `0xAABBCCDD`:

```
mml_fill      perf=0 s0=DD s49=DD s50=00 s199=00 s200=BB
mml_fill_2seg perf=2 bp=250 s200=DD s249=DD
```

The second line is the signature across two segments: `DD` in 0–49, `00` in 50–199, and `DD`
again in 200–249 — because the 50-byte last segment copies `FillBuffer[0..49]`, which *are* the
pattern. The mutation that **fixes it the natural way**, writing through a `uint32 *`, gives
`s49=CC s50=BB s199=AA` and the transcript refuses it.

Translated verbatim. `MM_AppData.HkTlm.Payload.BytesProcessed` reports the full commanded length
either way, so telemetry does not show it.

## 12. MM_FillMemCmd counts a failed fill as a successful command

Same pin, file `fsw/src/mm_cmds.c`.

```c
if (Status == CFE_PSP_SUCCESS) {
    if (MM_AppData.HkTlm.Payload.LastAction == MM_LastAction_FILL) {
        MM_AppData.HkTlm.Payload.CommandCounter++;
        CFE_EVS_SendEvent(MM_FILL_INF_EID, ...);
    } else {
        MM_AppData.HkTlm.Payload.CommandErrorCounter++;
    }
} else {
    MM_AppData.HkTlm.Payload.CommandCounter++;        /* <-- the SUCCESS counter */
}
```

The `else` is the **failure** arm of the status check and it moves `CommandCounter`, not
`CommandErrorCounter`, and sends **no event at all**. Every sibling handler in the file
(`MM_PokeCmd`, `MM_PeekCmd`, `MM_LoadMemFromFileCmd`, …) increments the error counter there.

### Reachability: LIVE, and the route is not the obvious one

`MM_FillMem8/16/32` return `CFE_PSP_ERROR` when a `CFE_PSP_MemWrite*` is refused — on hardware, a
fill that ran off the end of a valid region. So a fill that wrote **part** of its range and then
failed reports a command that worked.

It is **not** reached by an unaligned length, which is the first guess: `MM_VerifyLoadDumpParams`
checks the alignment of the **size** as well as the address for MEM16 and MEM32, so an unaligned
fill is refused one level earlier and lands in the outer `else`, which counts correctly. A
consequence worth stating on its own: **the rounding warning in `mm_mem16.c` and `mm_mem32.c`
(`MM_FILL_MEM16/32_ALIGN_WARN_INF_EID`) is unreachable through the command path** and only fires
if those functions are called directly.

### What the differential pins

A MEM8 fill of 16 bytes with the simulated PSP refusing the store at offset 70:

```
mmc_fill_wfail cc=1 ec=0 m69=5A m70=86
```

Six bytes written, the seventh refused, the success counter moved and no event sent. The mutation
that changes it to `CommandErrorCounter++` gives `cc=0 ec=1`.

Translated verbatim.

## 13. CS_ReportBaselineEntryIDEepromCmd RE-ENABLES the entry it was asked to report

`vendor/CS/fsw/src/cs_eeprom_cmds.c:119`, inside the `CS_StateValid(State)` arm:

```c
if (CS_StateValid(State))
{
    ResultsEntry->State = CS_ChecksumState_ENABLED;   /* <-- in a REPORT command */

    if (ResultsEntry->ComputedYet == true)
    { ... "Report baseline of EEPROM Entry %d is 0x%08X" ... }
```

A report command is a read. This one writes. Ask a **disabled** EEPROM region for its baseline and
it comes back **enabled**, and the background checksum walk resumes over a region the ground had
switched off — which is the whole point of the disable command.

### Why it is a slip and not a convention

`CS_ReportBaselineEntryIDMemoryCmd` (`cs_memory_cmds.c:159`) is the same function with "EEPROM"
replaced by "Memory" throughout — the two files are twins, and this port's `cs_memory_cmds.HC` was
*generated* from `cs_eeprom_cmds.HC` by a name map precisely because they are. **The Memory twin
does not have the line.** Normalising the type words to one token and diffing the two NASA sources
against each other leaves five lines; this is one of them. So the repository itself contains the
counter-example: either the write belongs in a report command for both memory types or for
neither.

There is a second assignment of the same shape at `cs_eeprom_cmds.c:278` — but that one is in
`CS_EnableEntryIDEepromCmd`, where enabling is the command.

### Reachability: LIVE, one command, no preconditions

`CS_ReportBaselineEntryIDEepromCmd` is reachable from the ground with CC
`CS_REPORT_BASELINE_EEPROM_CC` and an entry id. No child task, no table state, nothing to set up.
Any entry whose `State` passes `CS_StateValid` — that is, `ENABLED` **or** `DISABLED` — is
rewritten to `ENABLED`.

### What this port does about it

Nothing. Translated verbatim, with the note at the site.

## 14. CS_RecomputeBaselineEepromCmd's busy event always reports Entry ID 0

`cs_eeprom_cmds.c:164` declares `uint16 EntryID = 0;` and `:171` assigns it **inside** the
`RecomputeInProgress == false && OneShotInProgress == false` arm. The `else` arm at `:238` prints
it:

```c
else
{
    /*send event that we can't start another task right now */
    CFE_EVS_SendEvent(CS_RECOMPUTE_EEPROM_CHDTASK_ERR_EID, ...,
                      "Recompute baseline of EEPROM Entry ID %d failed: child task in use",
                      EntryID);          /* <-- never assigned on this path */
```

So the one event whose job is to tell the operator *which* recompute was rejected always says
**Entry ID 0**. Command entry 7 while a recompute is running and the log says entry 0 was refused.

Again the Memory twin is the counter-example: `cs_memory_cmds.c:166` assigns `EntryID` **outside**
the `if`, so its busy event reports the real id. Same five-line diff as #13.

Milder than an uninitialised read only because the declaration initialises to zero — which is also
why this one is directly witnessable in the differential (see #15 for the ones that are not).

Reachability: LIVE. Two commands, the second during the first.

## 15. Two CS busy events send UNINITIALISED STACK to the ground

`CS_RecomputeBaselineTableCmd` (`cs_table_cmds.c:203`) and `CS_RecomputeBaselineAppCmd`
(`cs_app_cmds.c:203`) are #14's shape with a **name** instead of an id, and a name has no
initialiser:

```c
char Name[CFE_TBL_MAX_FULL_NAME_LEN];           /* uninitialised */

if (RecomputeInProgress == false && OneShotInProgress == false)
{
    strncpy(Name, CmdPtr->Payload.Name, ...);   /* the only write, INSIDE the if */
    ...
}
else
{
    CFE_EVS_SendEvent(CS_RECOMPUTE_TABLES_CHDTASK_ERR_EID, ...,
                      "Tables recompute baseline for table %s failed: child task in use", Name);
```

On the busy path `Name` has never been written, so the event text is `%s` over whatever the frame
held — up to 40 bytes for the table command (`CFE_TBL_MAX_FULL_NAME_LEN`) and 20 for the app one
(`OS_MAX_API_NAME`), with no guarantee of a terminator inside the array at all. Same family as #8
and as the two words of stack cFE writes into the header of every table dump
(`dumpfile-uninitialised-header`), and the EEPROM/Memory twins are the better-behaved version:
they print an id, which is at least an initialised zero.

### What the differential can and cannot pin

An event whose text contains uninitialised stack cannot cross a differential for the same reason
an event containing a real pointer cannot — the host frame and the RISC-V frame hold different
rubbish. So these two are driven with the EVS output port closed
(`evs-port-close-for-uncomparable-events`): clear
`CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort`, send, assert `MessageSendCounter` moved, restore.
That proves the arm ran and the event was emitted without comparing a byte of the text. #14, by
contrast, prints an initialised zero and is compared in full — the transcript carries the literal
`Entry ID 0` that is the defect.

Translated verbatim, both of them, with the note at both sites.

## 16. Four CS event texts the ground parses are wrong in ways only text can be

Collected rather than given a note each, because they share a cause — these strings were written by
copying a sibling and editing it:

| Site | Text | Should be |
|---|---|---|
| `cs_memory_cmds.c:213` | `ES_CreateChildTask returned:` | `CFE_ES_CreateChildTask` — the prefix is dropped, and the EEPROM twin at `:214` has it |
| `cs_eeprom_cmds.c:214`, `cs_memory_cmds.c:213` | `returned:␣␣0x%08X` | one space; the other five `CreateChildTask returned:` texts in CS have one |
| `cs_cmds.c:550` | `OneShot checkum failed` | `checksum` |

The fourth is #14's `Entry ID %d`, counted there.

None of this changes a byte of flight behaviour, and all of it changes what a ground display
greps for. A telemetry decoder keyed on `"CFE_ES_CreateChildTask returned: "` finds six of CS's
seven child-task failures and silently misses the memory one.

Translated verbatim. **No gate compared these character for character** when they were written:
`check_formats.py` parses the *conversions* out of a format string and checks that
`StrPrintNV` implements every form, which says nothing about the literal text around them. The
double space and the dropped prefix were found by a one-off check run while generating
`cs_memory_cmds.HC` from its twin — every quoted string in the generated file had to appear
verbatim in NASA's own `cs_memory_cmds.c`. That check is worth being a gate rather than a habit,
and is listed as such in `docs/CFS_PLAN.md`.

## 17. CS_VerifyCmdLength is a public function with no declaration anywhere

The second instance of #3's shape, in a different repository and found the same way -- by a caller
outside the module failing to compile.

`CS/fsw/src/cs_dispatch.c:43` defines

    bool CS_VerifyCmdLength(const CFE_MSG_Message_t *msg, size_t ExpectedLength)

with external linkage. `cs_dispatch.h` declares its two neighbours from the same file --
`CS_AppPipe` at :54 and `CS_ProcessCmd` at :66 -- and **not** this one. Nothing else in CS declares
it either.

So the function is either public and under-declared, or internal and should be `static`. As with
#3 it is not a latent bug in a stock build: the only callers are in `cs_dispatch.c` itself, below
the definition. It becomes one the moment a unit test or a second dispatcher wants it, which is
precisely what happened here -- `tests/cfs/oracle_ccsdspri.c` has to write its own prototype to
exercise the function, and says so at the declaration.

Reproduced, not fixed: `Kernel/Cfs/cs/cs_dispatch.HC` keeps it non-static so the two sides have
the same linkage. check_signatures compares the DEFINITION, which exists in both, so no gate had
anything to object to.

AND THE PATTERN IS WORTH THE SECOND ENTRY RATHER THAN A FOOTNOTE ON THE FIRST. Two of the three
cFS repositories read so far have a function in this state, in both cases one that a test would
want first. It is the kind of thing a header-completeness check would find in bulk; nothing in
`tools/cfs` does that today, because every gate here starts from a DEFINITION and asks whether the
translation matches, never from a definition and asks whether anyone can call it.

## 18. LC_CopyBytesWithSwap is a public function with no declaration anywhere

The third instance of note 3's shape, and the second of note 17's. `lc_watch.c` defines

```c
void LC_CopyBytesWithSwap(LC_MultiType_t *DestBuffer, const uint8 *SrcPtr, LC_MultiType_t *SwapMap,
                          uint32 NumBytes)
```

with **external linkage**, and `lc_watch.h` declares its neighbours `LC_GetSizedWPData` and
`LC_WPOffsetValid` and not this one. Its only caller is in the same file.

### Why it matters here

It is the byte-swapping copy that implements every one of LC's eight big- and little-endian
watchpoint types, and the swap map is the whole mechanism — a 4-byte `LC_MultiType_t` holding
`0x00010203` or `0x03020100`, indexed with `& 3`. From `LC_GetSizedWPData`'s output alone you
cannot tell a byte-reversing copy from an identity one unless the input has four distinct bytes
AND you know which types are supposed to reverse. So the exercise calls it directly, and
`tests/cfs/oracle_ccsdspri.c` carries its own prototype with this note beside it.

### The pattern across three repositories

`OS_ConsoleWrite` (osal), `CS_VerifyCmdLength` (CS), `LC_CopyBytesWithSwap` (LC). **Three of the
four cFS repositories read so far have at least one non-static function that no header declares**,
and in all three cases it is a function a test wants. The gate that would find these in bulk still
does not exist: every checker in `tools/cfs` starts from a definition and asks whether the
translation matches it, never asks whether anything outside the file can call it.

## 19. HK_TableInit reports a copy-table GetAddress failure and then returns success

`hk_app.c`'s `HK_TableInit` ends with eight cFE calls, each with its own event and an early
return. The seventh is

```c
Status = CFE_TBL_GetAddress((void *)(&HK_AppData.CopyTablePtr), HK_AppData.CopyTableHandle);
/* Status should be CFE_TBL_INFO_UPDATED because we loaded it above */
if (Status != CFE_TBL_INFO_UPDATED)
{
    CFE_EVS_SendEvent(HK_CPTBL_GADR_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Getting Adr for Cpy Tbl,RC=0x%08X", (unsigned int)Status);
    return Status;
}
```

The comment is right about the expectation: after a successful `CFE_TBL_Load` the address call
should answer `CFE_TBL_INFO_UPDATED`. The test is right too. **The `return Status` is the
problem.** `CFE_TBL_INFO_UPDATED` is a positive informational code, so the one status that is NOT
`CFE_TBL_INFO_UPDATED` and NOT an error is `CFE_SUCCESS` — zero. On that path `HK_TableInit`
sends `HK_CPTBL_GADR_ERR_EID` and returns **0**.

Its caller is

```c
Status = HK_TableInit();
if (Status != CFE_SUCCESS)
{
    /* Specific failure is detailed in function HK_TableInit */
    return Status;
}
```

which does not fire. So `HK_AppInit` continues, sends `HK_INIT_INF_EID` ("HK Initialized."), and
returns success — with `HK_ProcessNewCopyTable` **never called**. HK then runs with a
`CopyTablePtr` that was never processed: no output packets built, no input subscriptions made, a
`RuntimeTablePtr` full of zeroes. Every later walk of the runtime table finds `OutputPktAddr`
null and skips, so HK reports a clean startup and combines nothing. The only trace is one ERROR
event followed immediately by an INFORMATION event claiming success.

The two adjacent `GetAddress` calls have **opposite success conditions** — the copy table's tests
for `CFE_TBL_INFO_UPDATED`, the runtime table's two lines below tests for `CFE_SUCCESS` — which is
what makes the slip easy to miss on a read.

### Reachability

Driven by the differential: see `hkap_tableinit_getaddr_success` in the exercise. The lever is a
copy table whose address call answers `CFE_SUCCESS` rather than `CFE_TBL_INFO_UPDATED`, which
happens whenever the table has already been fetched since its last update.

### What this port does about it

Keeps it. The translation has NASA's test and NASA's `return Status`, with the consequence stated
at the site in `Kernel/Cfs/hk/hk_app.HC`. A port that returned `HK_ERROR` there would be a
behaviour change disguised as a translation.

## 20. HK's data-present flag comments are transposed

`hk_utils.h`:

```c
#define HK_DATA_NOT_PRESENT (0) /**< \brief Input MsgId present in output msg */
#define HK_DATA_PRESENT     (1) /**< \brief Input MsgId not present */
```

`NOT_PRESENT` is documented as "present" and `PRESENT` as "not present". The **values are right**
and every use in `hk_utils.c` is correct — `HK_ProcessIncomingHkData` writes `HK_DATA_PRESENT`
after a successful copy, `HK_CheckForMissingData` tests for `HK_DATA_NOT_PRESENT`,
`HK_SetFlagsToNotPresent` clears to `HK_DATA_NOT_PRESENT`. Only the two doc comments are swapped.

Harmless to the code and worth recording because the names and the comments disagree, so a reader
resolving the ambiguity in favour of the comment gets HK's missing-data logic exactly backwards.
Noted in `Kernel/Cfs/hk/hk_tbl.HC` beside the definitions, with the names called out as the truth.

## 21. HK accepts a copy table whose output offsets destroy the output packet's own header

`HK_CopyTableEntry_t.OutputOffset` is measured from the **start of the output packet, headers
included** -- the same convention LC's `WatchpointOffset` uses for its input. So an entry with
`OutputOffset = 0` writes over the CCSDS header that `HK_ProcessNewCopyTable` put there with
`CFE_MSG_Init`.

`HK_ValidateHkCopyTable` does not notice. Its four checks are: both message ids set, the input
tail inside `HK_MAX_COMBINED_PACKET_SIZE`, and the output tail inside the same limit. **Nothing
compares an output offset against the header size.** So the table loads cleanly.

### What then happens is silent

```
hks_clobber_val rc=0            the validator accepts it
hks_clobber pres=1 sent_delta=0 the copy ran; the packet was never sent
```

`HK_SendCombinedHkPacket` finds the output packet by reading its id back out of its own header
with `CFE_MSG_GetMsgId` and comparing against the id the ground asked for. Once the header is
overwritten with telemetry bytes the comparison cannot match, so the walk finds nothing and sends
`HK_UNKNOWN_COMBINED_PACKET_EID` -- an **INFORMATION** event saying the packet "is not found in
current HK Copy Table".

From the ground that reads as: a copy table that loaded without complaint, a combined packet that
never arrives, and one information-level event per request as the only clue. The data is being
copied the whole time, into a buffer nothing will ever transmit.

### Why this is upstream and not a translation artefact

It was found by writing the exercise's copy table with offsets 0 and 4, which is the natural
choice if you think of `OutputOffset` as an offset into the payload. Every send line read
`sent=0`. The translation is faithful; the table was wrong, and HK's own validator is what should
have said so.

A mission is protected only by its copy table being generated correctly -- NASA's own
`hk_cpy_tbl.tbl` starts its offsets at the header size. The check that would catch a hand-edited
one is three lines in `HK_ValidateHkCopyTable` and is not there.

### What this port does about it

Keeps it, and drives it: `hks_clobber_val` / `hks_clobber` in the exercise are that table and its
consequence, so the behaviour is pinned rather than described.

## 22. HS's message header carries HK's include guard, so one of the two is silently skipped

`vendor/HS/config/default_hs_msg.h` opens with

```c
#ifndef DEFAULT_HK_MSG_H
#define DEFAULT_HK_MSG_H
```

**HK's guard, not HS's** — copy-pasted from `vendor/HK/config/default_hk_msg.h`, which uses the
same name. Of every header in the six app repositories read so far, it is the only one whose guard
names a different component. (Checked, not assumed: a sweep of all of HS's `config/` and `fsw/inc/`
headers reports exactly this one.)

### The consequence depends on build layout, which is why NASA has not seen it

In NASA's build HK and HS are separate CMake targets. No translation unit includes both, so
whichever guard is defined first is the only one that was ever going to be defined and nothing is
lost.

**This port compiles every application into ONE translation unit**, and that is the configuration
that exposes it. With `hk_msg.h` included first — which happens naturally, HK being the fifth app
and HS the sixth — `DEFAULT_HK_MSG_H` is already defined when `hs_msg.h` arrives, so
`default_hs_msg.h` is skipped in its entirety and

```
error: use of undeclared identifier 'HS_BITS_PER_APPMON_ENABLE'
```

appears in both `default_hs_msgstruct.h` and `hs_app.h`, where it is an array bound:

```c
uint32 AppMonEnables[((HS_MAX_MONITORED_APPS - 1) / HS_BITS_PER_APPMON_ENABLE) + 1];
```

So `HS_AppData_t` and `HS_HkTlm_Payload_t` have a member with no bound and neither structure can be
declared at all. It is a hard compile error rather than a silent miscompile, which is the one
piece of luck in it.

### How this port handles it

`vendor/shim/hs_msg.h` clears the guard before including NASA's header:

```c
#undef DEFAULT_HK_MSG_H
#include "default_hs_msg.h"
```

That is exact rather than a compromise, because **the two headers are disjoint**: HK's only
re-includes three HK headers, HS's defines one constant and includes three HS headers. HK's three
sub-headers carry their own guards, so a later `hk_msg.h` that gets skipped loses nothing.

`vendor/shim` is the right place — it stands in for the headers CMake would generate, so the
accommodation sits beside the other build-system substitutions and NASA's source is untouched.

### Why it is worth reporting upstream

Any mission that builds cFS as a unity build, or that includes both apps' public headers from one
file (a ground-system decoder generated from the message structures, say), hits this. The fix is
one word.
