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
// The SOFTWARE BUS's declarations: the types from cFE modules/sb/fsw/src/cfe_sb_priv.h and the
// command and telemetry formats from modules/sb/config/default_cfe_sb_msgdefs.h and
// _msgstruct.h, plus the constants that dimension them. No SB function is translated here.
//
// WHY THIS FILE IS FIRST. SB is the module every other one is stubbed against:
// CFE_SB_TransmitMsg, CFE_SB_CreatePipe, CFE_SB_Subscribe and CFE_SB_ReceiveBuffer appear as
// recording stubs in the differential driver for config, fs, ta, evs and time. Translating SB
// turns those stubs into COMPARED CODE across the whole transcript rather than only its own,
// which is the largest single thing left that improves what the existing gates can see. The
// types have to exist before any of it, and CFE_SB_Global_t pulls in eleven of them.
//
// THE BUFFER DESCRIPTOR IS THE SHAPE TO UNDERSTAND. CFE_SB_BufferD_t is a header followed by a
// VARIABLY SIZED message, and NASA says so in a comment: "Changing the size of this structure
// may require the memory pool block sizes to change." Every buffer SB hands out is one of these
// with Content last, allocated from a single 512 KiB static partition, and the tracking Link at
// the front is how a buffer is on exactly one of two lists -- in-transit or issued-for-zero-copy
// -- without a separate table.
#ifndef CFE_SB_GLOBAL_HC
#define CFE_SB_GLOBAL_HC
#include "cfe_sb_decl.HC"             // CFE_SB_Buffer and CFE_SB_Qos_t, the public SB types
#include "cfe_sb_msgid.HC"            // CFE_SB_MsgId and its constructors
#include "cfe_msg_sechdr_fc.HC"       // CFE_MSG_CommandHeader / CFE_MSG_TelemetryHeader
#include "cfe_evs.HC"                 // CFE_EVS_BinFilter_t, which EventFilters is an array of
#include "cfe_sbr_route_unsorted.HC"  // CFE_SBR_RouteId
#include "cfe_fs_api.HC"              // CFE_FS_FileWriteMetaData_t, the background file state
// OS_OBJECT_TYPE_USER, which CFE_SB_PIPEID_BASE's offset is measured from. NASA reaches it by
// including osapi.h through cfe_sb_module_all.h; this port does NOT, because pulling
// os_shared_idmap.HC into the cFE side drags osapi_errors.HC and its backend error-name table
// with it -- the boundary cfe_ta_task.HC states as "the cFE side must not pull in OSAL's
// implementation". Guarded, so when OSAL IS in the include graph its own value wins and this one
// is never used; check_constants.py compares the number against NASA's header either way. Same
// arrangement cfe_ta_task.HC uses for the OS_EVENT_* codes.
#ifndef OS_OBJECT_TYPE_USER
#define OS_OBJECT_TYPE_USER 0x10
#endif
// --- cfe_sb_internal_cfg.h / cfe_sb_interface_cfg.h: what dimensions SB -----------------------
// CFE_PLATFORM_SB_MAX_PIPES is 64 and CFE_MISSION_SB_MAX_PIPES is 32, and they are NOT the same
// number by accident: the platform one sizes SB's own pipe table, the mission one sizes the
// PipeDepthStats array inside a telemetry packet, because the packet's layout is part of the
// ground interface and cannot change with a platform's pipe count.
#define CFE_PLATFORM_SB_MAX_PIPES            64
#define CFE_MISSION_SB_MAX_PIPES             32
#define CFE_PLATFORM_SB_MAX_MSG_IDS          256
#define CFE_PLATFORM_SB_MAX_DEST_PER_PKT     16
#define CFE_PLATFORM_SB_BUF_MEMORY_BYTES     524288
#define CFE_MISSION_SB_SUB_ENTRIES_PER_PKT   20
#define CFE_SB_MAX_CFG_FILE_EVENTS_TO_FILTER 8
#define CFE_SB_MAIN_LOOP_ERR_DLY             1000
// --- cfe_sb_priv.h: the state flags, each a pair ----------------------------------------------
// These are NASA's own #defines rather than enums, and they come in pairs on purpose: SB stores
// a one-or-zero in a uint8 field and these name both ends of it, so a reader never has to decide
// whether 0 means "off" or "unset".
#define CFE_SB_INACTIVE         0
#define CFE_SB_ACTIVE           1
#define CFE_SB_MSG_GLOBAL       0
#define CFE_SB_MSG_LOCAL        1
#define CFE_SB_SEND_ZEROCOPY    0
#define CFE_SB_SEND_ONECOPY     1
#define CFE_SB_NOT_IN_USE       0
#define CFE_SB_IN_USE           1
#define CFE_SB_DISABLE          0
#define CFE_SB_ENABLE           1
#define CFE_SB_DENIED           0
#define CFE_SB_GRANTED          1
#define CFE_SB_DO_NOT_INCREMENT 0
#define CFE_SB_INCREMENT_TLM    1
// --- cfe_sb_priv.h: the internal error codes, which are NOT CFE_Status_t ----------------------
// Four small negative numbers SB uses between its own functions. They are deliberately not
// cFE status codes: nothing outside SB sees them.
#define CFE_SB_PIPE_OVERFLOW -1
#define CFE_SB_PIPE_WR_ERR   -2
#define CFE_SB_USECNT_ERR    -3
#define CFE_SB_FILE_IO_ERR   -5
// --- cfe_sb_priv.h: the recursion-stop bit map -----------------------------------------------
// One bit per event that SB's own send path can raise. Sending an event goes THROUGH SB, so an
// error reported while sending an error would recurse; these bits are what stops it, per task.
#define CFE_SB_SEND_NO_SUBS_EID_BIT   0
#define CFE_SB_GET_BUF_ERR_EID_BIT    1
#define CFE_SB_MSGID_LIM_ERR_EID_BIT  2
#define CFE_SB_Q_FULL_ERR_EID_BIT     3
#define CFE_SB_Q_WR_ERR_EID_BIT       4
#define CFE_SB_SEND_BAD_ARG_EID_BIT   5
#define CFE_SB_SEND_INV_MSGID_EID_BIT 6
#define CFE_SB_MSG_TOO_BIG_EID_BIT    7
// --- cfe_core_resourceid_basevalues.h: where a pipe id starts ---------------------------------
// CFE_SB_InitPipeTbl's whole body is `LastPipeId = CFE_ResourceId_FromInteger(CFE_SB_PIPEID_BASE)`,
// so this number is the pipe-id space. cfe_resourceid.HC owns MAKE_BASE; the offset is NASA's.
#define CFE_RESOURCEID_SB_PIPEID_RESOURCE_BASE_OFFSET (OS_OBJECT_TYPE_USER + 6)
#define CFE_SB_PIPEID_BASE CFE_RESOURCEID_MAKE_BASE(CFE_RESOURCEID_SB_PIPEID_RESOURCE_BASE_OFFSET)
// --- default_cfe_sb_msgdefs.h: the command payloads -------------------------------------------
class CFE_SB_WriteFileInfoCmd_Payload_t
{
  U8 Filename[CFE_MISSION_MAX_PATH_LEN];
  // Path and Filename of data to be loaded
};
// A route is a MsgId and PipeId pair, which is why one payload serves both Enable and Disable.
class CFE_SB_RouteCmd_Payload_t
{
  CFE_SB_MsgId MsgId;
  U32 Pipe;
  // CFE_SB_PipeId_t
  U8 Spare;
  // Spare byte to make command even number of bytes
  U8 _pad0[3];
  // C rounds the payload to 12; HolyC classes are packed. check_padding.py measures it.
};
// --- default_cfe_sb_msgdefs.h: the telemetry payloads -----------------------------------------
// TWELVE uint8 COUNTERS IN A ROW, then two uint16, and the order is the ground interface. A
// counter inserted or reordered here is a telemetry packet that decodes wrong on the ground
// while every gate that looks at code passes -- which is what check_structs and check_padding
// are for.
class CFE_SB_HousekeepingTlm_Payload_t
{
  U8 CommandCounter;
  U8 CommandErrorCounter;
  U8 NoSubscribersCounter;
  U8 MsgSendErrorCounter;
  U8 MsgReceiveErrorCounter;
  U8 InternalErrorCounter;
  U8 CreatePipeErrorCounter;
  U8 SubscribeErrorCounter;
  U8 PipeOptsErrorCounter;
  U8 DuplicateSubscriptionsCounter;
  U8 GetPipeIdByNameErrorCounter;
  U8 DeletePipeErrorCounter;
  U16 PipeOverflowErrorCounter;
  U16 MsgLimitErrorCounter;
  U32 MemPoolHandle;
  // CFE_ES_MemHandle_t
  U32 MemInUse;
  U32 UnmarkedMem;
  // CFE_PLATFORM_SB_BUF_MEMORY_BYTES minus peak memory in use
};

class CFE_SB_PipeDepthStats_t
{
  U32 PipeId;
  // CFE_SB_PipeId_t
  U16 MaxQueueDepth;
  U16 CurrentQueueDepth;
  U16 PeakQueueDepth;
  U16 Spare;
  // NASA's own, to keep the entry aligned
};
// The pipe information written to a FILE, and NASA's comment says why it is a separate type from
// the internal CFE_SB_PipeD_t: earlier cFE wrote the internal object straight out, which put
// pointers into a ground file and tied the file format to the implementation. This one can stay
// still while the internal one changes.
class CFE_SB_PipeInfoEntry_t
{
  U32 PipeId;
  U32 AppId;
  U8 PipeName[CFE_MISSION_MAX_API_LEN];
  U8 AppName[CFE_MISSION_MAX_API_LEN];
  U16 MaxQueueDepth;
  U16 CurrentQueueDepth;
  U16 PeakQueueDepth;
  U16 SendErrors;
  U8 Opts;
  U8 Spare[3];
  // NASA's own padding, to a multiple of four
};

class CFE_SB_StatsTlm_Payload_t
{
  U32 MsgIdsInUse;
  U32 PeakMsgIdsInUse;
  U32 MaxMsgIdsAllowed;
  U32 PipesInUse;
  U32 PeakPipesInUse;
  U32 MaxPipesAllowed;
  U32 MemInUse;
  U32 PeakMemInUse;
  U32 MaxMemAllowed;
  U32 SubscriptionsInUse;
  U32 PeakSubscriptionsInUse;
  U32 MaxSubscriptionsAllowed;
  U32 SBBuffersInUse;
  U32 PeakSBBuffersInUse;
  U32 MaxPipeDepthAllowed;
  CFE_SB_PipeDepthStats_t PipeDepthStats[CFE_MISSION_SB_MAX_PIPES];
};

class CFE_SB_RoutingFileEntry_t
{
  CFE_SB_MsgId MsgId;
  U32 PipeId;
  U8 State;
  // Route enabled or disabled
  U8 _pad0[1];
  // C aligns MsgCnt to 2
  U16 MsgCnt;
  U8 AppName[CFE_MISSION_MAX_API_LEN];
  U8 PipeName[CFE_MISSION_MAX_API_LEN];
};

class CFE_SB_MsgMapFileEntry_t
{
  CFE_SB_MsgId MsgId;
  U16 Index;
  // CFE_SB_RouteId_Atom_t -- the RAW index, not a route id
  U8 _pad0[2];
  // C rounds to 8 for the 4-aligned MsgId
};
// The subscription report, sent when subscription reporting is on. NASA's comment says it exists
// primarily for the Software Bus Networking application.
class CFE_SB_SingleSubscriptionTlm_Payload_t
{
  U8 SubType;
  U8 _pad0[3];
  // C aligns MsgId to 4
  CFE_SB_MsgId MsgId;
  CFE_SB_Qos_t Qos;
  U8 _pad1[2];
  // C aligns Pipe to 4
  U32 Pipe;
};

class CFE_SB_SubEntries_t
{
  CFE_SB_MsgId MsgId;
  CFE_SB_Qos_t Qos;
  U8 _pad0[2];
  // C aligns Pipe to 4
  U32 Pipe;
};
// The complete subscription list, sent as a SERIES of packets: there are normally more
// subscriptions than fit in one, so PktSegment counts up to TotalSegments.
class CFE_SB_AllSubscriptionsTlm_Payload_t
{
  U32 PktSegment;
  U32 TotalSegments;
  U32 Entries;
  CFE_SB_SubEntries_t Entry[CFE_MISSION_SB_SUB_ENTRIES_PER_PKT];
};
// --- default_cfe_sb_msgstruct.h: the command and telemetry packets ----------------------------
// SEVEN COMMANDS WITH NO PAYLOAD, each given its own typedef rather than sharing one. NASA's
// comment says why: it follows the command-handler convention, so every handler takes a distinct
// type and the dispatcher's sizeof checks are per-command rather than per-shape.
class CFE_SB_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_SB_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_SB_EnableSubReportingCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_SB_DisableSubReportingCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_SB_SendSbStatsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_SB_SendPrevSubsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_SB_SendHkCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_SB_WriteRoutingInfoCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_SB_WriteFileInfoCmd_Payload_t Payload;
};

class CFE_SB_WritePipeInfoCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_SB_WriteFileInfoCmd_Payload_t Payload;
};

class CFE_SB_WriteMapInfoCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_SB_WriteFileInfoCmd_Payload_t Payload;
};

class CFE_SB_EnableRouteCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_SB_RouteCmd_Payload_t Payload;
};

class CFE_SB_DisableRouteCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_SB_RouteCmd_Payload_t Payload;
};

class CFE_SB_HousekeepingTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_SB_HousekeepingTlm_Payload_t Payload;
};

class CFE_SB_StatsTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_SB_StatsTlm_Payload_t Payload;
};

class CFE_SB_SingleSubscriptionTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_SB_SingleSubscriptionTlm_Payload_t Payload;
};

class CFE_SB_AllSubscriptionsTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_SB_AllSubscriptionsTlm_Payload_t Payload;
};
// --- cfe_sb_priv.h: the buffer descriptor and the pipe --------------------------------------
// THE TRACKING LINK. Every buffer descriptor carries one, and it is how a buffer belongs to
// exactly one of two lists -- in-transit, or issued to an app for zero-copy -- with the list
// heads living in CFE_SB_Global as bare links rather than as a separate table. A buffer on
// neither list is one SB has lost track of, which is what CFE_SB_TrackingListReset establishes
// at init: a list whose head points at itself is empty.
class CFE_SB_BufferLink_t
{
  CFE_SB_BufferLink_t *Next;
  CFE_SB_BufferLink_t *Prev;
};
// THE BUFFER DESCRIPTOR, and NASA's warning about it is worth repeating: "Changing the size of
// this structure may require the memory pool block sizes to change." Content is VARIABLY SIZED
// and last; the block sizes in cfe_platformcfg_tables.HC are chosen around this header.
//
// DestRouteId, AppId and MsgId are not all meaningful at once, which the C says in prose and the
// type cannot: MsgId is set while in transit and AppId is not, because a message in transit may
// be queued to several apps; AppId is set while a zero-copy buffer is owned by one app and MsgId
// is not, because at allocation time the message id is not yet known.
class CFE_SB_BufferD_t
{
  CFE_SB_BufferLink_t Link;
  CFE_SBR_RouteId DestRouteId;
  U8 _pad0[2];
  // C aligns AppId to 4; HolyC classes are packed
  U32 AppId;
  // CFE_ES_AppId_t
  CFE_SB_MsgId MsgId;
  U8 _pad1[4];
  // C aligns the two size_t that follow to 8
  I64 AllocatedSize;
  // size_t -- the WHOLE descriptor, header included
  I64 ContentSize;
  // size_t -- the message currently in it
  U16 UseCount;
  // active references, not a boolean: a message queued to three pipes has three
  U8 _pad2[6];
  CFE_SB_Buffer Content;
  // variably sized, keep last
};

class CFE_SB_PipeD_t
{
  U32 PipeId;
  U32 AppId;
  U32 SysQueueId;
  // osal_id_t
  U8 Opts;
  U8 Spare;
  // NASA's own
  U16 SendErrors;
  U16 MaxQueueDepth;
  U16 CurrentQueueDepth;
  U16 PeakQueueDepth;
  U8 _pad0[2];
  // C aligns LastBuffer to 8
  CFE_SB_BufferD_t *LastBuffer;
};
// NASA writes this member as CFE_ES_STATIC_POOL_TYPE(CFE_PLATFORM_SB_BUF_MEMORY_BYTES), which is
// an ANONYMOUS union of an alignment member and Data[524288]. HolyC has no anonymous member
// type, so the union is NAMED here -- and the alignment member is omitted, which needs saying:
// its only purpose is to force the C struct's ALIGNMENT, the union's SIZE is Data's size either
// way, and a packed HolyC class expresses alignment as padding that check_padding.py measures
// against NASA's real offsets. Keeping a `long double` member would make this worse rather than
// better: it is 16 bytes on the RISC-V target and 8 on the host the oracle's C half compiles
// for, so it is the one shape where the two sides of this gate could not agree.
union CFE_SB_MemPartition_t
{
  U8 Data[CFE_PLATFORM_SB_BUF_MEMORY_BYTES];
};

class CFE_SB_MemParams_t
{
  U32 PoolHdl;
  // CFE_ES_MemHandle_t
  U8 _pad0[4];
  // C aligns the 16-byte-aligned partition
  CFE_SB_MemPartition_t Partition;
};
// --- cfe_sb_priv.h: the MESSAGE TRANSACTION ---------------------------------------------------
// WHAT A TRANSACTION IS. Sending a message is not one operation: SB has to find every pipe
// subscribed to the message id, try each one, and then report -- and a failure on the fourth
// pipe must not undo the first three or stop the fifth. CFE_SB_MessageTxn_State_t is the record
// of one such fan-out: the set of pipes, how many of them failed, the FIRST event id worth
// reporting, and one status for the whole thing. Receiving uses the same type with a single
// pipe in the set, which is why the type is "MessageTxn" and not "TransmitTxn".
//
// THE TWO WRAPPER TYPES ARE WHERE THE PIPE SET LIVES. CFE_SB_MessageTxn_State_t holds a POINTER
// to the set; CFE_SB_TransmitTxn_State_t supplies storage for up to
// CFE_PLATFORM_SB_MAX_DEST_PER_PKT of them and CFE_SB_ReceiveTxn_State_t for exactly one. That
// is how one state machine serves both directions without allocating, and it is also why
// CFE_SB_MessageTxn_Init clears `offsetof(CFE_SB_TransmitTxn_State_t, DestSet)` rather than
// sizeof(*TxnPtr) -- it zeroes the common header and deliberately leaves the destination array
// alone.
#define CFE_SB_MessageTxn_TimeoutMode_POLL  0
// do not block
#define CFE_SB_MessageTxn_TimeoutMode_PEND  1
// block indefinitely
#define CFE_SB_MessageTxn_TimeoutMode_TIMED 2
// block for a limited time
// CFE_SB_ReceiveBuffer's immediate-status option, beside CFE_SB_PEND_FOREVER in cfe_sb_decl.HC.
#define CFE_SB_POLL 0
// One pipe within a transaction, and its own outcome. PendingEventId and OsStatus are PER PIPE
// because the fan-out's whole point is that one destination failing says nothing about another.
class CFE_SB_PipeSetEntry_t
{
  U32 PipeId;
  // CFE_SB_PipeId_t
  U32 SysQueueId;
  // osal_id_t
  U16 PendingEventId;
  U8 _pad0[2];
  // C aligns OsStatus to 4
  I32 OsStatus;
};

class CFE_SB_MessageTxn_State_t
{
  Bool IsTransmit;
  Bool IsEndpoint;
  U16 NumPipes;
  U16 MaxPipes;
  U16 NumPipeErrs;
  U16 TransactionEventId;
  U8 _pad0[2];
  // C aligns TimeoutMode, a 4-byte enum, to 4
  I32 TimeoutMode;
  // CFE_SB_MessageTxn_TimeoutMode_t, a C enum
  I32 UserTimeoutParam;
  U8 _pad1[4];
  // C aligns AbsTimeout to 8
  OS_time_t AbsTimeout;
  I32 Status;
  // CFE_Status_t
  U8 _pad2[4];
  // C aligns ContentSize to 8
  I64 ContentSize;
  // size_t
  CFE_SB_MsgId RoutingMsgId;
  U8 _pad3[4];
  // C aligns the two pointers to 8
  U8 *RefMemPtr;
  // kept for reporting only; never dereferenced
  CFE_SB_PipeSetEntry_t *PipeSet;
};

class CFE_SB_TransmitTxn_State_t
{
  CFE_SB_MessageTxn_State_t MessageTxn_State;
  CFE_SB_PipeSetEntry_t DestSet[CFE_PLATFORM_SB_MAX_DEST_PER_PKT];
};

class CFE_SB_ReceiveTxn_State_t
{
  CFE_SB_MessageTxn_State_t MessageTxn_State;
  CFE_SB_PipeSetEntry_t Source;
};
// typedef bool (*CFE_SB_MessageTxn_PipeHandler_t)(CFE_SB_MessageTxn_State_t *,
//                                                 CFE_SB_PipeSetEntry_t *, void *);
// HolyC has no typedef, so it is spelled out at the one parameter that takes it --
// CFE_SB_MessageTxn_ProcessPipes.
// --- cfe_sb_priv.h: the background file writer -----------------------------------------------
// One route's worth of destinations, held while the route-info file is written a record at a
// time. The background writer runs outside SB's task, so this has to live in the global.
class CFE_SB_BackgroundRouteInfoBuffer_t
{
  U32 NumDestinations;
  CFE_SB_RoutingFileEntry_t DestEntries[CFE_PLATFORM_SB_MAX_DEST_PER_PKT];
};
// ONE holding area REUSED by all three file types -- route info, pipe info and message map --
// which is why it is a union and not three members.
union CFE_SB_BackgroundFileBuffer_t
{
  CFE_SB_BackgroundRouteInfoBuffer_t RouteInfo;
  CFE_SB_PipeInfoEntry_t PipeInfo;
  CFE_SB_MsgMapFileEntry_t MsgMapInfo;
};

class CFE_SB_BackgroundFileStateInfo_t
{
  CFE_FS_FileWriteMetaData_t FileWrite;
  // FS state data -- must be first, and NASA says so
  CFE_SB_BackgroundFileBuffer_t Buffer;
  U8 _pad0[4];
  // TAIL padding: FileWrite is 8-aligned, so C rounds 956 up to 960
};
// --- cfe_sb_priv.h: CFE_SB_Global_t ----------------------------------------------------------
// StopRecurseFlags is PER TASK, one word each, and that is the detail that makes the
// recursion-stop bits above work: SB's send path can raise an event, sending an event goes
// through SB, and a per-task flag word is what lets the second entry know it is the second.
class CFE_SB_Global_t
{
  U32 SharedDataMutexId;
  // osal_id_t
  U32 SubscriptionReporting;
  U32 AppId;
  // CFE_ES_AppId_t
  U32 StopRecurseFlags[OS_MAX_TASKS];
  // PER TASK, and that is what makes the recursion-stop bits above work
  U8 _pad0[4];
  // C aligns PipeTbl to 8: a pipe descriptor ends with a pointer
  CFE_SB_PipeD_t PipeTbl[CFE_PLATFORM_SB_MAX_PIPES];
  CFE_SB_HousekeepingTlm_t HKTlmMsg;
  CFE_SB_StatsTlm_t StatTlmMsg;
  U32 CmdPipe;
  // CFE_SB_PipeId_t
  U8 _pad1[4];
  CFE_SB_MemParams_t Mem;
  CFE_SB_AllSubscriptionsTlm_t PrevSubMsg;
  CFE_EVS_BinFilter_t EventFilters[CFE_SB_MAX_CFG_FILE_EVENTS_TO_FILTER];
  CFE_SB_Qos_t Default_Qos;
  U8 _pad2[2];
  // C aligns LastPipeId to 4
  U32 LastPipeId;
  // CFE_ResourceId_t
  U8 _pad3[4];
  // C aligns BackgroundFile to 8
  CFE_SB_BackgroundFileStateInfo_t BackgroundFile;
  CFE_SB_BufferLink_t InTransitList;
  // buffers SB owns
  CFE_SB_BufferLink_t ZeroCopyList;
  // buffers issued to apps for zero-copy
};
// NASA defines the object in cfe_sb_init.c. It is here for the reason cfe_time_global.HC records:
// HolyC has no usable forward declaration for a variable, and several SB units read it before
// the file that would define it appears in the include order.
CFE_SB_Global_t CFE_SB_Global;
#endif
