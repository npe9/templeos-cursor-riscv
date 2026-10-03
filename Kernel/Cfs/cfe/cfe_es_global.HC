/************************************************************************
 * NASA Docket No. GSC-19,200-1, and identified as "cFS Draco"
 *
 * Copyright (c) 2023 United States Government as represented by the
 * Administrator of the National Aeronautics and Space Administration.
 * All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License"); you may
 * not use this file except in compliance with the License. You may obtain
 * a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 ************************************************************************/
// ES'S STATE: the types of cfe_es_global.h, cfe_es_apps.h, cfe_es_cds.h, cfe_es_perf.h and the
// module's telemetry, plus the CFE_ES_Global instance itself.
//
// This is the same arrangement cfe_sb_global.HC has for SB and cfe_evs_global.HC has for EVS: a
// file of TYPES AND ONE GLOBAL, no code, so that the translated implementation files have
// something to be written against. check_structs.py and check_padding.py read every class here
// against NASA's own compiler, which is what makes a file of declarations worth having on its
// own -- 57,400 bytes of state whose layout is verified before a line of it is used.
//
// IT IS 57 KILOBYTES AND MOST OF THAT IS THE CDS. CFE_ES_CDS_Instance_t alone is 37,600 bytes,
// because the Critical Data Store registry is 512 entries of 72 bytes. The app, task and
// library tables together are under 10 KB.
//
// WHY THIS FILE COMES BEFORE ANY ES CODE: cfe_es_mempool.c's CFE_ES_LocateMemPoolRecordByID
// reads CFE_ES_Global.MemPoolTable, and there is no way to translate it without the table. The
// same is true of every other ES source, which is why all of them were blocked behind this one.
#ifndef CFE_ES_GLOBAL_HC
#define CFE_ES_GLOBAL_HC
#include "cfe_es_generic_pool.HC" // the pool record, which both the CDS and a mem pool embed
#include "cfe_es_resetdata.HC"    // CFE_ES_ResetData_t and CFE_ES_DebugVariables_t
#include "cfe_fs_api.HC"          // CFE_FS_FileWriteMetaData_t, which the log dumper embeds
// --- cfe_es_platform_cfg.h / cfe_es_mission_cfg.h --------------------------------------------
#define CFE_PLATFORM_ES_MAX_APPLICATIONS        32
#define CFE_PLATFORM_ES_MAX_LIBRARIES           10
#define CFE_PLATFORM_ES_MAX_GEN_COUNTERS        8
#define CFE_PLATFORM_ES_MAX_MEMORY_POOLS        10
#define CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES     512
#define CFE_PLATFORM_ES_ER_LOG_MAX_CONTEXT_SIZE 256
#define CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN    40
#define CFE_MISSION_ES_PERF_MAX_IDS             128
#define CFE_MISSION_ES_POOL_MAX_BUCKETS         17
// --- cfe_es_cds.h / cfe_es_erlog_typedef.h ---------------------------------------------------
#define CFE_ES_CDS_SIGNATURE_LEN            8
#define CFE_ES_ERLOG_DESCRIPTION_MAX_LENGTH 80
// --- cfe_es_apps.h: an app's and a task's startup parameters ---------------------------------
// CFE_ES_StackPointer_t is `void *` and CFE_ES_TaskPriority_Atom_t is a uint8, so this is
// 8 + 8 + 1 and C pads the tail to 8.
class CFE_ES_TaskStartParams_t
{
  I64 StackSize;
  // size_t
  U8 *StackPtr;
  // CFE_ES_StackPointer_t
  U16 Priority;
  // CFE_ES_TaskPriority_Atom_t -- SIXTEEN bits, not eight. It was U8 for one run and
  // check_padding named the width; OS_MAX_TASK_PRIORITY is 255 so a uint8 reads plausibly, and
  // the type is uint16 because OSAL's priority space is wider than cFE's uses it.
  U8 _pad0[6];
};

class CFE_ES_ModuleLoadParams_t
{
  U8 InitSymbolName[OS_MAX_API_NAME];
  U8 FileName[OS_MAX_PATH_LEN];
};

class CFE_ES_ModuleLoadStatus_t
{
  U32 ModuleId;
  // osal_id_t
  U8 _pad0[4];
  // C aligns the address that follows to 8
  U64 InitSymbolAddress;
  // cpuaddr
};

class CFE_ES_AppStartParams_t
{
  CFE_ES_ModuleLoadParams_t BasicInfo;
  U8 _pad0[4];
  // BasicInfo is 84 bytes (20 + 64, both char arrays); MainTaskInfo starts with a size_t and
  // so needs 8-alignment, which puts it at 88
  CFE_ES_TaskStartParams_t MainTaskInfo;
  U8 ExceptionAction;
  // CFE_ES_ExceptionAction_Enum_t -- ONE byte. It was U32 for one run; the enum typedefs in
  // this module are uint8 and uint32 in no pattern a reader can guess, so each one was checked.
  U8 _pad1[7];
};
// AppControlRequest is CFE_ES_RunStatus_Enum_t, a uint32, and AppTimerMsec is a SIGNED int32 --
// it counts DOWN while ES waits for an app to honour a control request, and a negative value is
// how a timeout is detected.
class CFE_ES_ControlReq_t
{
  U32 AppControlRequest;
  I32 AppTimerMsec;
};

class CFE_ES_AppRecord_t
{
  U32 AppId;
  // CFE_ES_AppId_t
  U8 AppName[OS_MAX_API_NAME];
  U32 AppState;
  // CFE_ES_AppState_Enum_t -- FOUR bytes
  U8 Type;
  // CFE_ES_AppType_Enum_t -- ONE byte, and the pair above is why each of this module's enum
  // typedefs was measured rather than assumed: they are adjacent and different widths.
  U8 _pad1[3];
  CFE_ES_AppStartParams_t StartParams;
  CFE_ES_ModuleLoadStatus_t LoadStatus;
  CFE_ES_ControlReq_t ControlReq;
  U32 MainTaskId;
  // CFE_ES_TaskId_t
  U8 _pad0[4];
};
// CFE_ES_TaskEntryFuncPtr_t is `void (*)(void)` -- the app's main, called with no arguments.
class CFE_ES_TaskRecord_t
{
  U32 TaskId;
  // CFE_ES_TaskId_t
  U8 TaskName[OS_MAX_API_NAME];
  U32 AppId;
  // CFE_ES_AppId_t
  U8 _pad1[4];
  // C aligns StartParams, whose first member is a size_t, to 8
  CFE_ES_TaskStartParams_t StartParams;
  U0 (*EntryFunc)();
  // CFE_ES_TaskEntryFuncPtr_t
  U32 ExecutionCounter;
  U8 _pad0[4];
};

class CFE_ES_LibRecord_t
{
  U32 LibId;
  // CFE_ES_LibId_t
  U8 LibName[OS_MAX_API_NAME];
  CFE_ES_ModuleLoadParams_t LoadParams;
  U8 _pad0[4];
  // C aligns LoadStatus's osal_id_t/cpuaddr pair to 8
  CFE_ES_ModuleLoadStatus_t LoadStatus;
};
// --- cfe_es_appctrl.h -------------------------------------------------------------------------
class CFE_ES_AppTableScanState_t
{
  U32 PendingAppStateChanges;
  U32 BackgroundScanTimer;
  U8 LastScanCommandCount;
  U8 _pad0[3];
};
// --- cfe_es_global.h -------------------------------------------------------------------------
class CFE_ES_GenCounterRecord_t
{
  U32 CounterId;
  // CFE_ES_CounterId_t
  U32 Counter;
  U8 CounterName[OS_MAX_API_NAME];
};

class CFE_ES_BackgroundTaskState_t
{
  U32 TaskID;
  // CFE_ES_TaskId_t
  U32 WorkSem;
  // osal_id_t -- given whenever background work is pending
  U32 NumJobsRunning;
};
// --- cfe_es_mempool.h ------------------------------------------------------------------------
// THE GENERIC POOL RECORD MUST BE FIRST AND NASA'S COMMENT SAYS SO. cfe_es_mempool.c's
// Retrieve/Commit pair casts a CFE_ES_GenPoolRecord_t * straight back to a
// CFE_ES_MemPoolRecord_t *, which is only valid because the pool is at offset 0. Moving it
// would compile and then read BaseAddr out of the middle of the bucket array.
class CFE_ES_MemPoolRecord_t
{
  CFE_ES_GenPoolRecord_t Pool;
  U32 PoolID;
  // CFE_ES_MemHandle_t -- the ID of this pool record
  U8 _pad0[4];
  // C aligns the address that follows to 8
  U64 BaseAddr;
  // cpuaddr -- start/base address of the memory block
  U32 OwnerAppID;
  // CFE_ES_AppId_t -- so ES can release the pool if the creating app exits
  U32 MutexId;
  // osal_id_t -- optional, for serializing get/put
};
// --- cfe_es_cds.h: the Critical Data Store -----------------------------------------------
// THIS IS 37,600 OF THE GLOBAL'S 57,400 BYTES, almost all of it the 512-entry registry. A CDS
// is memory that survives a processor reset, so the registry has to be large enough to name
// everything a mission might want to keep.
class CFE_ES_CDS_BlockHeader_t
{
  U32 Crc;
};

class CFE_ES_CDS_RegRec_t
{
  U32 BlockID;
  // CFE_ES_CDSHandle_t
  U8 _pad0[4];
  // C aligns the two size_t that follow to 8
  I64 BlockOffset;
  // size_t
  I64 BlockSize;
  // size_t
  U8 Name[CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN];
  Bool Table;
  U8 _pad1[7];
};
// The cache is ONE registry entry plus its descriptor and header, read or written as a unit.
// NASA's Zero[4] is a deliberate run of zeroes used to detect an uninitialised store.
// A UNION, NOT A STRUCT, and reading it as a struct made it 132 bytes against NASA's 72 and
// pushed every field of the cache after it. The CDS cache holds ONE of these shapes at a time
// depending on what is being read or written -- the signature, the registry size, the zero
// run, a block descriptor, a block header or a registry entry -- which is exactly what a union
// is for and why its size is the largest member rather than the sum.
union CFE_ES_CDS_AccessCacheData_t
{
  U8 Sig[CFE_ES_CDS_SIGNATURE_LEN];
  U32 RegistrySize;
  U32 Zero[4];
  CFE_ES_GenPoolBD_t Desc;
  CFE_ES_CDS_BlockHeader_t BlockHeader;
  CFE_ES_CDS_RegRec_t RegEntry;
};

class CFE_ES_CDS_AccessCache_t
{
  CFE_ES_CDS_AccessCacheData_t Data;
  I64 Offset;
  // size_t
  I64 Size;
  // size_t
  I32 AccessStatus;
  U8 _pad0[4];
};

class CFE_ES_CDS_Instance_t
{
  CFE_ES_GenPoolRecord_t Pool;
  CFE_ES_CDS_AccessCache_t Cache;
  U32 GenMutex;
  // osal_id_t
  U8 _pad0[4];
  I64 TotalSize;
  // size_t
  I64 DataSize;
  // size_t
  U32 LastCDSBlockId;
  // CFE_ResourceId_t
  U8 _pad1[4];
  CFE_ES_CDS_RegRec_t Registry[CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES];
};
// --- cfe_es_perf.h: the performance-log dump state machine -----------------------------------
// The perf log is the ONE log too big to write in a single pass -- NASA's comment on
// CFE_ES_BackgroundLogDumpGlobal_t says the small ones need only a pending flag and a
// filename, and that the perf log "must implement a state machine with a dedicated state data
// structure". This is that structure, and WorkCredit is the throttle.
class CFE_ES_PerfDumpGlobal_t
{
  U32 CurrentState;
  // CFE_ES_PerfDumpState_t, a 4-byte enum
  U32 PendingState;
  U8 DataFileName[OS_MAX_PATH_LEN];
  U32 FileDesc;
  // osal_id_t
  U32 WorkCredit;
  U32 StateCounter;
  U32 DataPos;
  I64 FileSize;
  // size_t -- already 8-aligned at 88; an earlier draft padded here and the gate said so
};
// --- cfe_es_erlog_typedef.h: the exception and reset log -------------------------------------
// CFE_ES_DebugVariables_t and CFE_TIME_SysTime_t come from cfe_es_resetdata.HC, which already
// declares the whole reset area -- this is the FILE form of one of its entries, which is the
// same base info plus the saved processor context.
class CFE_ES_ERLog_FileEntry_t
{
  CFE_ES_ERLog_BaseInfo_t BaseInfo;
  U32 ContextSize;
  U32 AppID;
  U8 Context[CFE_PLATFORM_ES_ER_LOG_MAX_CONTEXT_SIZE];
};

class CFE_ES_BackgroundLogDumpGlobal_t
{
  CFE_FS_FileWriteMetaData_t FileWrite;
  // FS state data - must be first
  CFE_ES_ERLog_FileEntry_t EntryBuffer;
  // Temp holding area for record to write
};
// --- default_cfe_es_extern_typedefs.h: the two public info blocks ----------------------------
// CFE_ES_AppInfo_t IS A GROUND-VISIBLE PACKET PAYLOAD and it carries THREE EXPLICIT PADDING
// FIELDS OF NASA'S OWN -- Padding1[4], Padding2 and Padding3[4]. They are NASA's fields, not
// this port's alignment, so they are named as NASA names them rather than as _pad0: a reader
// has to be able to tell a gap the C compiler made from a gap the message format specifies.
class CFE_ES_AppInfo_t
{
  U32 ResourceId;
  // CFE_ResourceId_t
  U32 Type;
  U8 Name[CFE_MISSION_MAX_API_LEN];
  U8 EntryPoint[CFE_MISSION_MAX_API_LEN];
  U8 FileName[CFE_MISSION_MAX_PATH_LEN];
  I64 StackSize;
  // CFE_ES_MemOffset_t
  U32 AddressesAreValid;
  U8 Padding1[4];
  U64 CodeAddress;
  // CFE_ES_MemAddress_t
  I64 CodeSize;
  // CFE_ES_MemOffset_t
  U64 DataAddress;
  I64 DataSize;
  U64 BSSAddress;
  I64 BSSSize;
  U64 StartAddress;
  U8 ExceptionAction;
  // CFE_ES_ExceptionAction_Enum_t
  U8 Padding2;
  U16 Priority;
  // CFE_ES_TaskPriority_Atom_t -- sixteen bits, as in CFE_ES_TaskStartParams_t. NASA's own
  // Padding2 above is what makes it land 2-aligned at 186, so there is no compiler padding here.
  U32 MainTaskId;
  // CFE_ES_TaskId_t
  U32 ExecutionCounter;
  U8 MainTaskName[CFE_MISSION_MAX_API_LEN];
  U32 NumOfChildTasks;
  U8 Padding3[4];
};

class CFE_ES_MemPoolStats_t
{
  I64 PoolSize;
  // CFE_ES_MemOffset_t
  U32 NumBlocksRequested;
  U32 CheckErrCtr;
  I64 NumFreeBytes;
  // CFE_ES_MemOffset_t
  CFE_ES_BlockStats_t BlockStats[CFE_MISSION_ES_POOL_MAX_BUCKETS];
};
// --- default_cfe_es_msgdefs.h / _msgstruct.h: ES's three telemetry packets -------------------
// THE TWO PERF MASKS ARE BITMAPS, ONE BIT PER PERFORMANCE ID. NASA writes the bound as
// CFE_MISSION_ES_PERF_MAX_IDS / 8, and the division is in the declaration rather than folded to
// 16 so that changing the id count changes the packet -- which is why it is written that way
// here too and check_padding measures the result.
class CFE_ES_HousekeepingTlm_Payload_t
{
  U8 CommandCounter;
  U8 CommandErrorCounter;
  U16 CFECoreChecksum;
  U8 CFEMajorVersion;
  U8 CFEMinorVersion;
  U8 CFERevision;
  U8 CFEMissionRevision;
  U8 OSALMajorVersion;
  U8 OSALMinorVersion;
  U8 OSALRevision;
  U8 OSALMissionRevision;
  U8 PSPMajorVersion;
  U8 PSPMinorVersion;
  U8 PSPRevision;
  U8 PSPMissionRevision;
  // ...and that is the SIXTEENTH byte, so SysLogBytesUsed is already 8-aligned and there is no
  // padding here. An earlier draft put a byte in and the gate reported every field after it
  // one off -- which is the failure this class of struct is most prone to, because a
  // ground-visible payload that is one byte long is still a payload the dispatcher accepts.
  I64 SysLogBytesUsed;
  // CFE_ES_MemOffset_t
  I64 SysLogSize;
  // CFE_ES_MemOffset_t
  U32 SysLogEntries;
  U32 SysLogMode;
  U32 ERLogIndex;
  U32 ERLogEntries;
  U32 RegisteredCoreApps;
  U32 RegisteredExternalApps;
  U32 RegisteredTasks;
  U32 RegisteredLibs;
  U32 ResetType;
  U32 ResetSubtype;
  U32 ProcessorResets;
  U32 MaxProcessorResets;
  U32 BootSource;
  U32 PerfState;
  U32 PerfMode;
  U32 PerfTriggerCount;
  U8 PerfFilterMask[CFE_MISSION_ES_PERF_MAX_IDS / 8];
  U8 PerfTriggerMask[CFE_MISSION_ES_PERF_MAX_IDS / 8];
  U32 PerfDataStart;
  U32 PerfDataEnd;
  U32 PerfDataCount;
  U32 PerfDataToWrite;
  I64 HeapBytesFree;
  // CFE_ES_MemOffset_t
  I64 HeapBlocksFree;
  // CFE_ES_MemOffset_t
  I64 HeapMaxBlockSize;
  // CFE_ES_MemOffset_t
};

class CFE_ES_HousekeepingTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_ES_HousekeepingTlm_Payload_t Payload;
};

class CFE_ES_OneAppTlm_Payload_t
{
  CFE_ES_AppInfo_t AppInfo;
};

class CFE_ES_OneAppTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_ES_OneAppTlm_Payload_t Payload;
};
// NASA's own Padding[4] again, in the packet rather than from the compiler.
// CDS REGISTRY DUMP RECORD, the on-disk format of CFE_ES_DumpCDSRegistryCmd's output. It is
// NOT the registry entry: CFE_ES_CDS_RegRec_t is ES's own and carries offsets and a mutex
// handle; this is the four fields the ground is given. ByteAlignSpare is NASA's own field, not
// this port's padding, and keeps its name.
class CFE_ES_CDSRegDumpRec_t
{
  U32 Handle;
  // CFE_ES_CDSHandle_t
  U8 _pad0[4];
  // C aligns the size_t that follows to 8
  I64 Size;
  // CFE_ES_MemOffset_t -- size, in bytes, of the CDS memory block
  Bool Table;
  // whether the CDS contains a Critical Table
  U8 Name[CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN];
  U8 ByteAlignSpare[3];
  // NASA's: "ensure structure size is multiple of 4 bytes"
  U8 _pad1[4];
  // C rounds the struct up to its 8 alignment; HolyC does not. NASA's own
  // ByteAlignSpare gets it to a multiple of FOUR; the size_t member makes the alignment EIGHT.
};

class CFE_ES_PoolStatsTlm_Payload_t
{
  U32 PoolHandle;
  // CFE_ES_MemHandle_t
  U8 Padding[4];
  CFE_ES_MemPoolStats_t PoolStats;
};
// THE NAME IS CFE_ES_MemStatsTlm_t AND THE PAYLOAD IS CFE_ES_PoolStatsTlm_Payload_t. They do
// not match, and that is NASA's, not a transcription slip: the message is named for what it
// reports and the payload for the structure it carries.
class CFE_ES_MemStatsTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_ES_PoolStatsTlm_Payload_t Payload;
};
// --- cfe_es_global.h: the task's own data, formerly a separate global ------------------------
class CFE_ES_TaskData_t
{
  U8 CommandCounter;
  U8 CommandErrorCounter;
  U8 _pad0[6];
  CFE_ES_HousekeepingTlm_t HkPacket;
  CFE_ES_OneAppTlm_t OneAppPacket;
  CFE_ES_MemStatsTlm_t MemStatsPacket;
  U32 CmdPipe;
  // CFE_SB_PipeId_t
  U8 _pad1[4];
};
// ES'S GLOBAL STATE, 57,400 bytes. NASA's comment is that this is "the regular global data that
// is not preserved on a processor reset" -- the part that IS preserved is CFE_ES_ResetData_t,
// which cfe_es_resetdata.HC already declares and which this reaches through a POINTER on the
// last line.
//
// SystemState is `volatile sig_atomic_t` in the C -- a plain int, 4 bytes -- and HolyC has no
// volatile qualifier. THAT IS FINE HERE, AND IT WAS MEASURED RATHER THAN HOPED: this compiler
// re-loads a global on every reference, so every access is already what volatile asks for. The
// IC optimizer has no common-subexpression elimination and no loop-invariant code motion, and
// every constant pass it does have skips globals by construction (ICF_GLBL_ADDR); its register
// cache is keyed by frame offset, which a global has none of.
//
// tests/scripts/check_global_reload.sh pins it: it disassembles a spin-on-global loop and
// asserts the load sits inside the loop body, with a control that fails when the value is read
// into a local first. docs/HOLYC_STRUCT_LIMITS.md #18 has the evidence. The risk is not in this
// declaration but in the compiler -- a future hoisting pass would make the missing qualifier a
// real defect, and check_padding compares this field's WIDTH and could never see it.
class CFE_ES_Global_t
{
  CFE_ES_DebugVariables_t DebugVars;
  U32 SharedDataMutex;
  // osal_id_t
  U32 PerfDataMutex;
  // osal_id_t
  I32 SystemState;
  // volatile sig_atomic_t -- see the note above
  U32 RegisteredTasks;
  CFE_ES_TaskRecord_t TaskTable[OS_MAX_TASKS];
  U32 RegisteredCoreApps;
  U32 RegisteredExternalApps;
  U32 LastAppId;
  // CFE_ResourceId_t
  U8 _pad0[4];
  CFE_ES_AppRecord_t AppTable[CFE_PLATFORM_ES_MAX_APPLICATIONS];
  U32 RegisteredLibs;
  U32 LastLibId;
  // CFE_ResourceId_t
  CFE_ES_LibRecord_t LibTable[CFE_PLATFORM_ES_MAX_LIBRARIES];
  U32 LastCounterId;
  // CFE_ResourceId_t -- and NO padding after it: CFE_ES_GenCounterRecord_t is all U32 and char,
  // so it is 4-aligned and the table starts immediately
  CFE_ES_GenCounterRecord_t CounterTable[CFE_PLATFORM_ES_MAX_GEN_COUNTERS];
  U8 _pad1[4];
  // ...whereas CDSVars begins with a size_t and does need 8
  CFE_ES_CDS_Instance_t CDSVars;
  Bool CDSIsAvailable;
  // Whether or not the CDS service is active/valid
  U8 _pad3[3];
  CFE_ES_BackgroundTaskState_t BackgroundTask;
  U32 LastMemPoolId;
  // CFE_ResourceId_t
  U8 _pad4[4];
  // CFE_ES_MemPoolRecord_t begins with the generic pool record, whose first member is a size_t
  CFE_ES_MemPoolRecord_t MemPoolTable[CFE_PLATFORM_ES_MAX_MEMORY_POOLS];
  CFE_ES_BackgroundLogDumpGlobal_t BackgroundERLogDumpState;
  CFE_ES_PerfDumpGlobal_t BackgroundPerfDumpState;
  CFE_ES_AppTableScanState_t BackgroundAppScanState;
  U8 _pad5[4];
  CFE_ES_TaskData_t TaskData;
  CFE_ES_ResetData_t *ResetDataPtr;
};
// NASA defines the instance in cfe_es_api.c. The translation defines it here, beside its type,
// for the reason cfe_sb_global.HC and cfe_evs_global.HC both record: a global whose definition
// sits in whichever implementation file happened to be translated first moves when that
// changes, and the include graph is easier to read with the state next to the types.
CFE_ES_Global_t CFE_ES_Global;
#endif
