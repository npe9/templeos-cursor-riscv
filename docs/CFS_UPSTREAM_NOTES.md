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
