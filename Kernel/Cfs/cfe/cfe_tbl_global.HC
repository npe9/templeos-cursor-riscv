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
// TABLE SERVICES' STATE AND THE TYPES IT IS BUILT FROM -- the translation of NASA's
// cfe_tbl_task.h, cfe_tbl_regrec.h, cfe_tbl_accdesc.h, cfe_tbl_loadbuff.h,
// cfe_tbl_valresult.h, cfe_tbl_dumpctl.h and cfe_tbl_handlelink.h, plus the global instance.
//
// WHAT TABLE SERVICES IS, in one paragraph, because the types only make sense with it: an app
// registers a TABLE -- a named block of memory with a size, and optionally a validation
// function -- and then asks for its address when it wants to read it. The ground can load a new
// copy of that block from a file, validate it, and activate it, and the app sees the change the
// next time it asks. So every table has at least one BUFFER, a REGISTRY RECORD describing it,
// and one ACCESS DESCRIPTOR per app that shares it.
//
// THE REGISTRY RECORD IS THE TABLE and the access descriptor is a HANDLE TO IT. One table may
// be shared by many apps, so the descriptors for a table are kept on a linked list threaded
// through CFE_TBL_HandleLink_t -- which is why that type is two ids rather than two pointers:
// the list lives inside a fixed array and the links are indices, so it survives being written
// to a critical data store and read back.
//
// THE 512 KiB IS REAL. CFE_TBL_BufParams_t carries the whole table buffer pool as a static
// member, so CFE_TBL_Global_t is 592,056 bytes -- by far the largest object in this port, and
// 89 percent of it is that pool. tools/cfs/check_padding.py measures all of it.
//
// A TABLE CAN BE CRITICAL, which means its contents go to the CDS and survive a processor
// reset. That is what CFE_TBL_CritRegRec_t is: a SECOND registry, in non-volatile storage,
// holding just enough to find the table's data again after the volatile registry is gone.
//
// This file follows the arrangement cfe_es_global.HC, cfe_sb_global.HC and cfe_evs_global.HC
// all record: NASA defines CFE_TBL_Global in cfe_tbl_task.c, and the translation defines it
// here beside its type, so a global does not move when a different implementation file happens
// to be translated first.
#ifndef CFE_TBL_GLOBAL_HC
#define CFE_TBL_GLOBAL_HC
// --- cfe_tbl_mission_cfg.h / cfe_tbl_internal_cfg.h -----------------------------------------
#ifndef CFE_TBL_MAX_FULL_NAME_LEN
#define CFE_TBL_MAX_FULL_NAME_LEN 40
#endif
#define CFE_PLATFORM_TBL_MAX_NUM_HANDLES        256
#define CFE_PLATFORM_TBL_MAX_NUM_TABLES         128
#define CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES    32
#define CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS 4
#define CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS    10
#define CFE_PLATFORM_TBL_BUF_MEMORY_BYTES       524288
#define CFE_PLATFORM_TBL_MAX_DBL_TABLE_SIZE     16384
#define CFE_PLATFORM_TBL_MAX_SNGL_TABLE_SIZE    16384
// ZERO MEANS "DO NOT CHECK", for both of these. cfe_tbl_load.c compares a loaded file's
// spacecraft and processor id against a list this long, and a count of zero disables the check
// -- which is this configuration's choice.
#define CFE_PLATFORM_TBL_VALID_SCID_COUNT 0
#define CFE_PLATFORM_TBL_VALID_PRID_COUNT 0
// --- cfe_tbl_task.h: the mutexes and the command pipe ---------------------------------------
#define CFE_TBL_MUT_REG_NAME    "TBL_REG_MUT"
#define CFE_TBL_MUT_REG_VALUE   0
#define CFE_TBL_MUT_WORK_NAME   "TBL_WRK_MUT"
#define CFE_TBL_MUT_WORK_VALUE  0
#define CFE_TBL_TASK_PIPE_NAME  "TBL_CMD_PIPE"
#define CFE_TBL_TASK_PIPE_DEPTH 12
// --- cfe_core_resourceid_basevalues.h: the five id spaces tbl owns --------------------------
// Five separate id types, because five different arrays are indexed independently: a validation
// request, a dump-control block, a load buffer, an access descriptor (a HANDLE) and a registry
// record. Mixing two of them up is what the resource-id scheme exists to prevent.
#ifndef CFE_RESOURCEID_TBL_VALRESULTID_BASE_OFFSET
#define CFE_RESOURCEID_TBL_VALRESULTID_BASE_OFFSET (OS_OBJECT_TYPE_USER + 8)
#define CFE_RESOURCEID_TBL_DUMPCTRLID_BASE_OFFSET  (OS_OBJECT_TYPE_USER + 9)
#define CFE_RESOURCEID_TBL_LOADBUFFID_BASE_OFFSET  (OS_OBJECT_TYPE_USER + 10)
#define CFE_RESOURCEID_TBL_ACCESSID_BASE_OFFSET    (OS_OBJECT_TYPE_USER + 11)
#define CFE_RESOURCEID_TBL_REGID_BASE_OFFSET       (OS_OBJECT_TYPE_USER + 12)
#endif
#ifndef CFE_TBL_VALRESULTID_BASE
#define CFE_TBL_VALRESULTID_BASE \
  CFE_RESOURCEID_MAKE_BASE(CFE_RESOURCEID_TBL_VALRESULTID_BASE_OFFSET)
#define CFE_TBL_DUMPCTRLID_BASE \
  CFE_RESOURCEID_MAKE_BASE(CFE_RESOURCEID_TBL_DUMPCTRLID_BASE_OFFSET)
#define CFE_TBL_LOADBUFFID_BASE \
  CFE_RESOURCEID_MAKE_BASE(CFE_RESOURCEID_TBL_LOADBUFFID_BASE_OFFSET)
#define CFE_TBL_HANDLE_BASE CFE_RESOURCEID_MAKE_BASE(CFE_RESOURCEID_TBL_ACCESSID_BASE_OFFSET)
#define CFE_TBL_REGID_BASE  CFE_RESOURCEID_MAKE_BASE(CFE_RESOURCEID_TBL_REGID_BASE_OFFSET)
#endif
// Every one of the five undefined values is CFE_RESOURCEID_UNDEFINED; the wrappers are the
// identity in this port, as they are for every other resource id.
#define CFE_TBL_HANDLEID_UNDEFINED      CFE_RESOURCEID_UNDEFINED
#define CFE_TBL_REGID_UNDEFINED         CFE_RESOURCEID_UNDEFINED
#define CFE_TBL_LOADBUFFID_UNDEFINED    CFE_RESOURCEID_UNDEFINED
#define CFE_TBL_VALRESULTID_UNDEFINED   CFE_RESOURCEID_UNDEFINED
#define CFE_TBL_DUMPCTRLID_UNDEFINED    CFE_RESOURCEID_UNDEFINED
// NASA's own alias, used where a registry record says "no dump is pending on this table".
#define CFE_TBL_NO_DUMP_PENDING CFE_TBL_DUMPCTRLID_UNDEFINED
// --- cfe_tbl_dumpctl.h / cfe_tbl_valresult.h: the two three-state enums ---------------------
// Both run FREE -> PENDING -> PERFORMED, and both are the handshake between the ground and the
// owning app: Table Services marks a request PENDING, the app notices it the next time it calls
// CFE_TBL_Manage, and the result comes back PERFORMED.
#define CFE_TBL_DUMP_FREE      0
#define CFE_TBL_DUMP_PENDING   1
#define CFE_TBL_DUMP_PERFORMED 2
#define CFE_TBL_VALIDATION_FREE      0
#define CFE_TBL_VALIDATION_PENDING   1
#define CFE_TBL_VALIDATION_PERFORMED 2

/*******************************************************************************/
// cfe_tbl_handlelink.h. TWO IDS, NOT TWO POINTERS, and that is the point: the access
// descriptors live in a fixed array, so the list is threaded with indices and stays valid
// across anything that copies or relocates the array.
class CFE_TBL_HandleLink_t
{
  U32 Next; // CFE_TBL_HandleId_t
  U32 Prev; // CFE_TBL_HandleId_t
};

/*******************************************************************************/
// cfe_tbl_loadbuff.h. A buffer is where a table's bytes actually are -- the active copy, the
// inactive copy a load is being staged into, or one of the four shared working buffers that
// single-buffered tables take turns with.
//
// THE CRC AND THE FILE TIME TRAVEL WITH THE BYTES, which is what lets a loaded buffer be
// validated and reported on before it is activated.
class CFE_TBL_LoadBuff_t
{
  U32 LoadBufferId; // CFE_TBL_LoadBuffId_t
  U32 OwnerRegId;   // CFE_TBL_RegId_t
  U8 *BufferPtr;    // void *, the table's bytes
  I64 AllocationSize;
  I64 ContentSize;
  CFE_TIME_SysTime FileTime;
  U32 Crc;
  Bool IsValid;
  Bool ActivateReq;
  // NO PADDING HERE: DataSource is at 46, immediately after the two flags. The Crc before them
  // is 4-byte aligned and a char array needs no alignment, so C packs them -- measured by
  // check_padding, which read 48 against NASA's 46 when this carried a habitual _pad0[2].
  U8 DataSource[OS_MAX_PATH_LEN];
  // DataSource ends at 110 and the struct carries a pointer, so C rounds the whole thing to 112.
  U8 _pad1[2];
};

/*******************************************************************************/
// cfe_tbl_accdesc.h. ONE PER APP PER TABLE. A table shared by three apps has three of these,
// all pointing at the same registry record, and each remembers whether ITS app has seen the
// latest update -- which is what makes CFE_TBL_GetAddress able to answer "the table changed
// since you last looked" per app rather than globally.
class CFE_TBL_AccessDescriptor_t
{
  U32 HandleId; // CFE_TBL_HandleId_t
  U32 AppId;    // CFE_ES_AppId_t
  U32 RegIndex; // CFE_TBL_RegId_t
  CFE_TBL_HandleLink_t Link;
  Bool LockFlag;
  Bool Updated;
  U8 _pad0[2];
  U32 BufferIndex; // CFE_TBL_LoadBuffId_t
};

/*******************************************************************************/
// cfe_tbl_valresult.h. A validation REQUEST and its answer in one record: Table Services fills
// in the table name and which buffer to check, the owning app runs its own validation function
// and writes Result back.
class CFE_TBL_ValidationResult_t
{
  U32 ValId; // CFE_TBL_ValidationResultId_t
  U32 State; // CFE_TBL_ValidationState_t, a 4-byte enum
  I32 Result;
  U32 CrcOfTable;
  // TWO BYTES, not four: CFE_TBL_BufferSelect_Enum_t is a uint16 rather than a C enum, so
  // TableName starts at the odd offset 18. check_padding named the width.
  U16 BufferSelect; // CFE_TBL_BufferSelect_Enum_t
  U8 TableName[CFE_TBL_MAX_FULL_NAME_LEN];
  U8 _pad0[2];
};

/*******************************************************************************/
// cfe_tbl_dumpctl.h. The same handshake for a DUMP-ONLY table: those are never loaded, so the
// only way to see their contents is to ask the owning app to copy them out at a moment of its
// choosing.
class CFE_TBL_DumpControl_t
{
  U32 BlockId; // CFE_TBL_DumpCtrlId_t
  I32 EncodeStatus;
  U32 State; // CFE_TBL_DumpState_t
  U8 _pad0[4];
  CFE_TBL_LoadBuff_t *DumpBufferPtr;
  U32 SourceBuffId; // CFE_TBL_LoadBuffId_t
  U8 TableName[CFE_TBL_MAX_FULL_NAME_LEN];
  U8 _pad1[4];
};

/*******************************************************************************/
// cfe_tbl_regrec.h, split into three as NASA splits it: what the OWNER asked for (Config), what
// has HAPPENED to the table since (Status), and how the owner wants to be TOLD (Notify).
class CFE_TBL_TableConfig_t
{
  U8 Name[CFE_TBL_MAX_FULL_NAME_LEN];
  I64 Size;
  I32 (*ValidationFuncPtr)(U8 *); // CFE_TBL_CallbackFuncPtr_t
  Bool DoubleBuffered;
  Bool DumpOnly;
  Bool UserDefAddr;
  Bool Critical;
  U32 EdsId;
};

class CFE_TBL_TableStatus_t
{
  U32 ActiveBufferId; // CFE_TBL_LoadBuffId_t
  U32 PrevBufferId;
  U32 NextBufferId;
  // CFE_TIME_SysTime IS TWO uint32 AND SO 4-BYTE ALIGNED, not 8 -- it lands at offset 12 with no
  // padding before it, and LastFileLoaded then starts at the odd offset 21. Both were wrong here
  // first, by assuming a time stamp wants 8-byte alignment.
  CFE_TIME_SysTime TimeOfLastUpdate;
  Bool IsModified;
  U8 LastFileLoaded[OS_MAX_PATH_LEN];
  U8 _pad0[3];
};
// AN OWNER CAN ASK TO BE SENT A COMMAND when its table needs managing, which is how an app that
// is not polling CFE_TBL_Manage finds out: Table Services sends the message below on its behalf.
class CFE_TBL_TableUpdateNotify_t
{
  Bool Enabled;
  U8 _pad0[1];
  U16 FcnCode; // CFE_MSG_FcnCode_t
  U32 MsgId;   // CFE_SB_MsgId_t
  U32 Param;
};

/*******************************************************************************/
// THE TABLE ITSELF. Two buffers always -- a double-buffered table owns both, a single-buffered
// one uses Buffers[0] and borrows a working buffer for a load -- plus the list head for every
// app sharing it and the ids of any validation or dump in flight.
class CFE_TBL_RegistryRec_t
{
  U32 RegId;      // CFE_TBL_RegId_t
  U32 OwnerAppId; // CFE_ES_AppId_t
  CFE_TBL_LoadBuff_t Buffers[2];
  CFE_TBL_HandleLink_t AccessList;
  U32 PendingValId;  // CFE_TBL_ValidationResultId_t
  U32 DumpControlId; // CFE_TBL_DumpCtrlId_t
  U32 CDSHandle;     // CFE_ES_CDSHandle_t
  U8 _pad0[4];
  CFE_TBL_TableConfig_t Config;
  CFE_TBL_TableStatus_t Status;
  CFE_TBL_TableUpdateNotify_t Notify;
  U8 _pad1[4]; // NASA's struct is 424; Notify ends at 420 and the whole record aligns to 8
};

/*******************************************************************************/
// cfe_tbl_task.h. THE CRITICAL REGISTRY -- a SECOND registry, in the critical data store, with
// just enough in it to find a critical table's data again after a processor reset has taken the
// volatile one. The CDS handle is the link; the name is how a re-registering app is matched to
// what survived.
class CFE_TBL_CritRegRec_t
{
  U32 CDSHandle; // CFE_ES_CDSHandle_t
  CFE_TIME_SysTime FileTime;
  CFE_TIME_SysTime TimeOfLastUpdate;
  U8 LastFileLoaded[OS_MAX_PATH_LEN];
  U8 Name[CFE_TBL_MAX_FULL_NAME_LEN];
  Bool TableLoadedOnce;
  U8 _pad0[3]; // the record carries 4-byte members, so C rounds 125 up to 128
};

/*******************************************************************************/
// cfe_tbl_task.h. The registry as the GROUND sees it -- a shortened record written one per
// table into a dump file, so it is a reporting format rather than state.
class CFE_TBL_RegDumpRec_t
{
  // EIGHT BYTES: CFE_ES_MemOffset_t is 64-bit in this configuration, so Size alone moves every
  // member after it -- which is what check_padding said, offset by offset, when this was a U32.
  // It is also why DumpRecord inside the state struct below needs 8-byte alignment.
  U64 Size; // CFE_ES_MemOffset_t
  CFE_TIME_SysTime TimeOfLastUpdate;
  U32 NumUsers;
  I32 LoadInProgress;
  CFE_TIME_SysTime FileTime;
  U32 Crc;
  Bool ValidationFunc;
  Bool TableLoadedOnce;
  Bool LoadPending;
  Bool DumpOnly;
  Bool DoubleBuffered;
  U8 Name[CFE_TBL_MAX_FULL_NAME_LEN];
  U8 LastFileLoaded[OS_MAX_PATH_LEN];
  U8 OwnerAppName[OS_MAX_API_NAME];
  Bool CriticalTable;
  U8 _pad0[2]; // the 64-bit Size at offset 0 makes the whole record 8-aligned: 166 rounds to 168
};

/*******************************************************************************/
// cfe_tbl_task.h. The background registry dump's state. NASA's comment on the first member is a
// requirement, not a note -- "FS state data - must be first" -- because CFE_FS's background
// writer is handed a pointer to this and reads the metadata through it.
class CFE_TBL_RegDumpStateInfo_t
{
  CFE_FS_FileWriteMetaData_t FileWrite;
  Bool FileExisted;
  // SEVEN, not three: DumpRecord starts with a 64-bit CFE_ES_MemOffset_t, so it is 8-byte
  // aligned and lands at 128 rather than 124.
  U8 _pad0[7];
  CFE_TBL_RegDumpRec_t DumpRecord;
};

/*******************************************************************************/
// cfe_tbl_task.h. 512 KiB OF TABLE BUFFER, which is 89 percent of CFE_TBL_Global_t. NASA writes
// the member as CFE_ES_STATIC_POOL_TYPE(CFE_PLATFORM_TBL_BUF_MEMORY_BYTES), an anonymous union
// of an alignment member and Data[]; the union is NAMED here and the alignment member omitted,
// for the reasons cfe_sb_global.HC records in full at its own identical member -- chiefly that a
// `long double` is 16 bytes on this target and 8 on the host the oracle's C half compiles for,
// which is the one shape the two halves of check_padding could not agree about.
union CFE_TBL_MemPartition_t
{
  U8 Data[CFE_PLATFORM_TBL_BUF_MEMORY_BYTES];
};

class CFE_TBL_BufParams_t
{
  U32 PoolHdl; // CFE_ES_MemHandle_t
  U8 _pad0[4]; // C aligns the 16-byte-aligned partition
  CFE_TBL_MemPartition_t Partition;
};

/*******************************************************************************/
// cfe_tbl_task.h. The whole of the Table Service's state, 592,056 bytes of it -- NASA's comment
// says the point is to keep it "a single block of memory", and 524,288 of those bytes are Buf's
// table buffer pool.
//
// EVERY PAD HERE WAS MEASURED, by an offsetof probe over NASA's own header, not reasoned about:
//   NumValRequests ends at 5 and LastTblUpdated (a 4-byte CFE_TBL_RegId_t) wants 8 -> 3 bytes.
//   HkPacket ends at 316 and TblRegPacket wants 4-byte alignment      -> 4 bytes.
//   CritRegHandle ends at 564 and LoadBuffs is 8-byte aligned          -> 4 bytes.
//   LastDumpCtrlBlockId ends at 592052 and the class is 8-byte aligned -> 4 trailing bytes.
// The last one is the one that is easy to lose: a trailing pad is invisible to every member
// offset and shows up only in sizeof, which is what CFE_TBL_EarlyInit memsets.
class CFE_TBL_Global_t
{
  // Task command interface counters
  U8 CommandCounter;
  U8 CommandErrorCounter;

  // Table Validation Result counters
  U8 SuccessValCounter;
  U8 FailedValCounter;
  U8 NumValRequests;
  U8 _pad0[3];

  // Ground Interface Information
  U32 LastTblUpdated; // CFE_TBL_RegId_t
  U32 HkTlmTblRegId;  // CFE_TBL_RegId_t

  // Task housekeeping and diagnostics telemetry packets
  CFE_TBL_HousekeepingTlm_t HkPacket;
  U8 _pad1[4];
  CFE_TBL_TableRegistryTlm_t TblRegPacket;
  CFE_TBL_NotifyCmd_t NotifyMsg;

  // Task operational data (not reported in housekeeping)
  U32 CmdPipe; // CFE_SB_PipeId_t

  // Task initialization data (not reported in housekeeping)
  U32 TableTaskAppId; // CFE_ES_AppId_t

  U16 ValidationCounter;
  //   ValidationCounter ends at 550 and RegistryMutex (a 4-byte osal_id_t) wants 552 -> 2 bytes.
  // A FIFTH measured pad, and the one the list above was missing: a U16 between a U32 and a U32
  // leaves a hole on both sides of itself and only one of them is obvious.
  U8 _pad2[2];

  // Registry Access Mutex and Load Buffer Semaphores
  U32 RegistryMutex; // osal_id_t
  U32 WorkBufMutex;  // osal_id_t
  U32 CritRegHandle; // CFE_ES_CDSHandle_t
  U8 _pad3[4];
  CFE_TBL_LoadBuff_t LoadBuffs[CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS];

  // Registry Data
  CFE_TBL_AccessDescriptor_t Handles[CFE_PLATFORM_TBL_MAX_NUM_HANDLES];
  CFE_TBL_RegistryRec_t Registry[CFE_PLATFORM_TBL_MAX_NUM_TABLES];
  CFE_TBL_CritRegRec_t CritReg[CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES];
  CFE_TBL_BufParams_t Buf;
  CFE_TBL_ValidationResult_t ValidationResults[CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS];
  CFE_TBL_DumpControl_t DumpControlBlocks[CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS];

  // Registry dump state info (background job)
  CFE_TBL_RegDumpStateInfo_t RegDumpState;

  U32 LastHandle;               // CFE_ResourceId_t
  U32 LastRegId;                // CFE_ResourceId_t
  U32 LastLoadBuffId;           // CFE_ResourceId_t
  U32 LastValidationResultId;   // CFE_ResourceId_t
  U32 LastDumpCtrlBlockId;      // CFE_ResourceId_t
  U8 _pad4[4];
};
// NASA defines the instance in cfe_tbl_task.c; the translation defines it here beside its type,
// for the reason cfe_es_global.HC records at its own instance.
CFE_TBL_Global_t CFE_TBL_Global;
#endif
