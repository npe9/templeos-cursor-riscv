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

// The DECLARATIONS the cFE Event Services module needs, from
//
//   modules/evs/fsw/src/cfe_evs_task.h              EVS_BinFilter_t, EVS_AppData_t,
//                                                   CFE_EVS_AppDataFile_t, CFE_EVS_Global_t
//   modules/evs/config/default_cfe_evs_msgdefs.h    the packet ids and payloads
//   modules/evs/config/default_cfe_evs_extern_typedefs.h  the event type and filter enums
//   modules/core_private/fsw/inc/cfe_evs_log_typedef.h    the local event log
//   modules/evs/fsw/inc/cfe_evs_eventids.h          EVS's own event ids
//   modules/core_api/fsw/inc/cfe_error.h            the CFE_EVS_* status codes
//
// SPLIT OUT, unlike fs and ta, where the declarations sit in the file named after the .c they
// came from. EVS's types live in cfe_evs_task.h, and cfe_evs_task.c is the LAST of its six
// sources to be translated: utils, log and the public API all need the global before the file
// that declares it exists. Putting them here keeps the include order honest instead of
// pretending cfe_evs_task.HC comes first.
#ifndef CFE_EVS_GLOBAL_HC
#define CFE_EVS_GLOBAL_HC
// --- cfe_error.h: the codes EVS returns -------------------------------------------------------
#define CFE_EVS_UNKNOWN_FILTER        0xC2000001
#define CFE_EVS_APP_NOT_REGISTERED    0xC2000002
#define CFE_EVS_APP_ILLEGAL_APP_ID    0xC2000003
#define CFE_EVS_APP_FILTER_OVERLOAD   0xC2000004
#define CFE_EVS_RESET_AREA_POINTER    0xC2000005
#define CFE_EVS_EVT_NOT_REGISTERED    0xC2000006
#define CFE_EVS_FILE_WRITE_ERROR      0xC2000007
#define CFE_EVS_INVALID_PARAMETER     0xC2000008
#define CFE_EVS_NOT_IMPLEMENTED       0xC200FFFF
// --- cfe_evs_extern_typedefs.h ----------------------------------------------------------------
// CFE_EVS_EventType_Enum_t. The numbering matters twice over: the bit masks below are
// 1 << (type - 1), and EventTypesActive is indexed by (type - 1).
#define CFE_EVS_EventType_DEBUG       1
#define CFE_EVS_EventType_INFORMATION 2
#define CFE_EVS_EventType_ERROR       3
#define CFE_EVS_EventType_CRITICAL    4
#define CFE_EVS_NUM_EVENT_TYPES       4

// CFE_EVS_EventFilter_Enum_t -- one scheme, and CFE_EVS_Register rejects anything else.
#define CFE_EVS_EventFilter_BINARY 0

// CFE_EVS_MsgFormat_Enum_t
#define CFE_EVS_MsgFormat_SHORT 0
#define CFE_EVS_MsgFormat_LONG  1

// CFE_EVS_LogMode_Enum_t
#define CFE_EVS_LogMode_OVERWRITE 0
#define CFE_EVS_LogMode_DISCARD   1
// --- cfe_evs_msgdefs.h: the bit masks ---------------------------------------------------------
#define CFE_EVS_DEBUG_BIT       1 // 1 << (CFE_EVS_EventType_DEBUG - 1)
#define CFE_EVS_INFORMATION_BIT 2
#define CFE_EVS_ERROR_BIT       4
#define CFE_EVS_CRITICAL_BIT    8
#define CFE_EVS_ALL_EVENT_TYPES_MASK 0xF

#define CFE_EVS_PORT1_BIT 1
#define CFE_EVS_PORT2_BIT 2
#define CFE_EVS_PORT3_BIT 4
#define CFE_EVS_PORT4_BIT 8
#define CFE_EVS_PORT_MASK 0xF
// --- cfe_evs_internal_cfg.h / platform_cfg.h --------------------------------------------------
#define CFE_PLATFORM_EVS_MAX_EVENT_FILTERS     8
#define CFE_PLATFORM_ES_MAX_APPLICATIONS       32
// 16, NOT the 32 of CFE_PLATFORM_ES_MAX_APPLICATIONS. The platform limit sizes EVS's own
// AppData array; the MISSION limit sizes the array that goes out in TELEMETRY, because that
// is an interface a ground system parses. Getting them the same would have made the
// housekeeping packet twice its real size.
#define CFE_MISSION_ES_MAX_APPLICATIONS        16
#define CFE_MISSION_EVS_MAX_MESSAGE_LENGTH     122
#define CFE_PLATFORM_EVS_LOG_MAX               20
#define CFE_PLATFORM_EVS_PORT_DEFAULT          1
#define CFE_PLATFORM_EVS_MAX_APP_EVENT_BURST   32
#define CFE_PLATFORM_EVS_APP_EVENTS_PER_SEC    15
#define CFE_PLATFORM_EVS_DEFAULT_LOG_FILE      "/ram/cfe_evs.log"
#define CFE_PLATFORM_EVS_DEFAULT_APP_DATA_FILE "/ram/cfe_evs_app.dat"
// --- cfe_evs_task.h: limits -------------------------------------------------------------------
#define CFE_EVS_MAX_EVENT_SEND_COUNT 0xFFFF
#define CFE_EVS_MAX_FILTER_COUNT     0xFFFF
#define CFE_EVS_MAX_SQUELCH_COUNT    0xFF
#define CFE_EVS_PIPE_NAME            "EVS_CMD_PIPE"
#define CFE_EVS_PIPE_DEPTH           32
#define CFE_EVS_MAX_PORT_MSG_LENGTH  (CFE_MISSION_EVS_MAX_MESSAGE_LENGTH + OS_MAX_API_NAME + 19)
#define CFE_EVS_MSG_TRUNCATED        '$'
// --- cfe_time.h -------------------------------------------------------------------------------
#define CFE_TIME_PRINTED_STRING_SIZE 24
// --- cfe_evs_eventids.h: the events EVS itself sends ------------------------------------------
#define CFE_EVS_NOOP_EID                 0
#define CFE_EVS_STARTUP_EID              1
#define CFE_EVS_ERR_WRLOGFILE_EID        2
#define CFE_EVS_ERR_CRLOGFILE_EID        3
#define CFE_EVS_ERR_MSGID_EID            5
#define CFE_EVS_ERR_EVTIDNOREGS_EID      6
#define CFE_EVS_ERR_APPNOREGS_EID        7
#define CFE_EVS_ERR_ILLAPPIDRANGE_EID    8
#define CFE_EVS_ERR_NOAPPIDFOUND_EID     9
#define CFE_EVS_ERR_ILLEGALFMTMOD_EID    10
#define CFE_EVS_ERR_MAXREGSFILTER_EID    11
#define CFE_EVS_ERR_WRDATFILE_EID        12
#define CFE_EVS_ERR_CRDATFILE_EID        13
#define CFE_EVS_WRITE_HEADER_ERR_EID     14
#define CFE_EVS_ERR_CC_EID               15
#define CFE_EVS_RSTCNT_EID               16
#define CFE_EVS_SETFILTERMSK_EID         17
#define CFE_EVS_ENAPORT_EID              18
#define CFE_EVS_DISPORT_EID              19
#define CFE_EVS_ENAEVTTYPE_EID           20
#define CFE_EVS_DISEVTTYPE_EID           21
#define CFE_EVS_SETEVTFMTMOD_EID         22
#define CFE_EVS_ENAAPPEVTTYPE_EID        23
#define CFE_EVS_DISAPPENTTYPE_EID        24
#define CFE_EVS_ENAAPPEVT_EID            25
#define CFE_EVS_DISAPPEVT_EID            26
#define CFE_EVS_RSTEVTCNT_EID            27
#define CFE_EVS_RSTFILTER_EID            28
#define CFE_EVS_RSTALLFILTER_EID         29
#define CFE_EVS_ADDFILTER_EID            30
#define CFE_EVS_DELFILTER_EID            31
#define CFE_EVS_WRDAT_EID                32
#define CFE_EVS_WRLOG_EID                33
#define CFE_EVS_EVT_FILTERED_EID         37
#define CFE_EVS_LOGMODE_EID              38
#define CFE_EVS_ERR_LOGMODE_EID          39
#define CFE_EVS_ERR_INVALID_BITMASK_EID  40
#define CFE_EVS_ERR_UNREGISTERED_EVS_APP 41
#define CFE_EVS_FILTER_MAX_EID           42
#define CFE_EVS_LEN_ERR_EID              43
#define CFE_EVS_SQUELCHED_ERR_EID        44
// --- cfe_evs_msgdefs.h: the telemetry payloads -----------------------------------------------
class CFE_EVS_AppTlmData_t
{
  U32 AppID;                      // CFE_ES_AppId_t
  U16 AppMessageSentCounter;
  U8 AppEnableStatus;
  U8 AppMessageSquelchedCounter;
};

class CFE_EVS_HousekeepingTlm_Payload_t
{
  U8 CommandCounter;
  U8 CommandErrorCounter;
  U8 MessageFormatMode;   // short/long
  U8 MessageTruncCounter;
  U8 UnregisteredAppCounter;
  U8 OutputPort;          // mask
  U8 LogFullFlag;
  U8 LogMode;             // overwrite/discard
  U16 MessageSendCounter;
  U16 LogOverflowCounter;
  U8 LogEnabled;
  U8 Padding[3];          // NASA's own name for it: padding for a 32-bit boundary
  CFE_EVS_AppTlmData_t AppData[CFE_MISSION_ES_MAX_APPLICATIONS];
};

class CFE_EVS_PacketID_t
{
  U8 AppName[CFE_MISSION_MAX_API_LEN];
  U16 EventID;
  U16 EventType; // CFE_EVS_EventType_Enum_t, a uint16 typedef here rather than a C enum
  U32 SpacecraftID;
  U32 ProcessorID;
};

class CFE_EVS_LongEventTlm_Payload_t
{
  CFE_EVS_PacketID_t PacketID;
  U8 Message[CFE_MISSION_EVS_MAX_MESSAGE_LENGTH];
  U8 Padding[2]; // NASA's own name for it
};

class CFE_EVS_ShortEventTlm_Payload_t
{
  CFE_EVS_PacketID_t PacketID;
};

class CFE_EVS_HousekeepingTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_EVS_HousekeepingTlm_Payload_t Payload;
};

class CFE_EVS_LongEventTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_EVS_LongEventTlm_Payload_t Payload;
};

class CFE_EVS_ShortEventTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_EVS_ShortEventTlm_Payload_t Payload;
};
// --- cfe_evs_msgids.h -------------------------------------------------------------------------
#define CFE_EVS_LONG_EVENT_MSG_MID  2056
#define CFE_EVS_SHORT_EVENT_MSG_MID 2057
#define CFE_EVS_HK_TLM_MID          2049
#define CFE_EVS_CMD_MID             6145
#define CFE_EVS_SEND_HK_MID         6153
// --- cfe_evs_log_typedef.h --------------------------------------------------------------------
// The local event log lives in ES's reset area, which survives a processor reset; EVS holds a
// POINTER to it rather than the storage.
class CFE_EVS_Log_t
{
  U16 Next;               // Index of the next entry in the local event log
  U16 LogCount;           // Local Event Log counter
  U8 LogFullFlag;
  U8 LogMode;             // overwrite/discard
  U16 LogOverflowCounter;
  CFE_EVS_LongEventTlm_t LogEntry[CFE_PLATFORM_EVS_LOG_MAX];
};
// --- cfe_evs_task.h: the per-application state ------------------------------------------------
class EVS_BinFilter_t
{
  U16 EventID; // Numerical event identifier
  U16 Mask;    // Binary filter mask
  U16 Count;   // Binary filter counter
  U16 Padding; // NASA's own name for it: structure padding
};

class EVS_AppData_t
{
  U32 AppID;      // CFE_ES_AppId_t
  U32 UnregAppID; // the app a "not registered" event has already been sent for
  EVS_BinFilter_t BinFilters[CFE_PLATFORM_EVS_MAX_EVENT_FILTERS]; // Array of binary filters
  U8 ActiveFlag;  // Application event service active flag
  // INDEXED BY (EventType - 1), which is why the enum's numbering is load-bearing.
  Bool EventTypesActive[CFE_EVS_NUM_EVENT_TYPES];
  U8 _pad0[1];    // C pads here; HolyC packs. See tools/cfs/check_padding.py
  U16 EventCount; // Application event counter
  OS_time_t LastSquelchCreditableTime; // Time of last squelch token return
  I32 SquelchTokens;   // Application event squelch token counter
  U8 SquelchedCount;   // Application events squelched counter
  U8 _pad1[3];         // C rounds the struct up to its alignment; HolyC does not
};

class CFE_EVS_AppDataFile_t
{
  U8 AppName[OS_MAX_API_NAME];
  U8 ActiveFlag;
  U8 EventTypesActiveFlag;
  U16 EventCount;
  U8 SquelchedCount;
  U8 Spare[3];
  EVS_BinFilter_t Filters[CFE_PLATFORM_EVS_MAX_EVENT_FILTERS];
};

class CFE_EVS_Global_t
{
  EVS_AppData_t AppData[CFE_PLATFORM_ES_MAX_APPLICATIONS]; // state and event filters, per app
  CFE_EVS_Log_t *EVS_LogPtr; // Pointer to the EVS log in the ES Reset area
  CFE_EVS_HousekeepingTlm_t EVS_TlmPkt;
  U32 EVS_CommandPipe;       // CFE_SB_PipeId_t
  U32 EVS_SharedDataMutexID; // osal_id_t
  U32 EVS_AppID;             // CFE_ES_AppId_t
  U32 EVS_EventBurstMax;
};

CFE_EVS_Global_t CFE_EVS_Global;
#endif
