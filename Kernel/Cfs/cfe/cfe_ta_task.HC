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

// 1:1 HolyC translation of cFE modules/ta/fsw/src/cfe_ta_task.c, together with the type and
// constant declarations the TA module needs, from
//
//   modules/ta/fsw/inc/cfe_ta_tasklist.h    the tracked-task record and its two enums
//   modules/ta/fsw/inc/cfe_ta_eventids.h    the 23 event ids
//   modules/ta/fsw/src/cfe_ta_task.h        the global, the diagnostic packet, the error codes
//   modules/ta/config/default_cfe_ta_msgdefs.h and _msgstruct.h   the command payloads
//
// TA is the first translated module that is an APP rather than a library: it has a task, a
// command pipe and a housekeeping packet. That changes what the differential oracle can reach.
//
// WHAT THE TRANSCRIPT CANNOT COVER, said plainly so nobody assumes otherwise:
//
//   CFE_TA_TaskMain is translated because check_coverage requires the name and because a port
//   that omits it has a module that exists and never runs -- but it is NOT driven. It pends
//   forever on CFE_SB_ReceiveBuffer and ends in CFE_ES_ExitApp, which does not return. Every
//   other function in this file is driven directly.
//
// WHAT THE DRIVER SUPPLIES, and why that is the same decision as everywhere else here: SB, EVS
// and ES are not translated, so the oracle gives both sides the same recording stubs.
// CFE_EVS_SendEvent USED to be the one place this file deviated: it took the event id, the type
// and a plain string, and the transcript compared the id and the type while leaving the wording
// outside. EVS is translated now, so the deviation is gone -- every call below passes NASA's own
// arguments, and the text they format is inside the byte-identical comparison.
#ifndef CFE_TA_TASK_HC
#define CFE_TA_TASK_HC
#include "../osal/os_shared_task_affinity.HC"
// --- cfe_error.h ------------------------------------------------------------------------------
#define CFE_STATUS_NO_COUNTER_INCREMENT 0x48000001
// --- osconfig.h / cfe_mission_cfg.h -----------------------------------------------------------
#ifndef OS_MAX_TASKS
#define OS_MAX_TASKS 64
#endif
#ifndef OS_MAX_API_NAME
#define OS_MAX_API_NAME 20
#endif
#define CFE_MISSION_MAX_API_LEN      20
#define CFE_MISSION_TA_MAX_NUM_CPUS  64
#define CFE_MISSION_TA_MAIN_PERF_ID  12
#define CFE_PLATFORM_ES_DEFAULT_TASK_LOG_FILE "/ram/cfe_es_taskinfo.log"
// --- cfe_ta_task.h: configuration -------------------------------------------------------------
#define CFE_TA_PIPE_NAME            "TA_CMD_PIPE"
#define CFE_TA_PIPE_DEPTH           32
#define CFE_TA_MAX_EVENT_SEND_COUNT 65535
#define CFE_TA_TASK_LOG_DESC        "TA Task Affinity Info file"
// --- cfe_ta_task.h: error codes ---------------------------------------------------------------
#define CFE_TA_APP_TASK_NOT_FOUND               -1
#define CFE_TA_APP_GET_TASK_AFFINITY_FAILED     -2
#define CFE_TA_APP_SET_TASK_AFFINITY_FAILED     -3
#define CFE_TA_APP_INVALID_TASK_AFFINITY_TYPE   -4
#define CFE_TA_APP_TASK_STARTUP_AFFINITY_FAILED -5
// --- cfe_ta_eventids.h ------------------------------------------------------------------------
#define CFE_TA_INIT_INF_EID                          1
#define CFE_TA_ERR_MSGID_EID                         2
#define CFE_TA_NOOP_INF_EID                          3
#define CFE_TA_RESET_COUNTERS_INF_EID                4
#define CFE_TA_ERR_CC_EID                            5
#define CFE_TA_LEN_ERR_EID                           6
#define CFE_TA_TASKINFO_OSCREATE_ERR_EID             7
#define CFE_TA_TASKINFO_FILENAME_ERR_EID             8
#define CFE_TA_TASKINFO_WRHDR_ERR_EID                9
#define CFE_TA_TASKINFO_WR_ERR_EID                   10
#define CFE_TA_TASKINFO_EID                          11
#define CFE_TA_SET_STARTUP_AFFINITY_INF_EID          12
#define CFE_TA_SET_STARTUP_AFFINITY_ADDED_INF_EID    13
#define CFE_TA_SET_STARTUP_AFFINITY_ERR_EID          14
#define CFE_TA_SET_AFFINITY_CMD_NOTFOUND_ERR_EID     15
#define CFE_TA_SET_AFFINITY_CMD_GET_ERR_EID          16
#define CFE_TA_SET_AFFINITY_CMD_SET_ERR_EID          17
#define CFE_TA_SET_TASK_AFFINITY_CMD_INF_EID         18
#define CFE_TA_GET_AFFINITY_CMD_NOTFOUND_ERR_EID     19
#define CFE_TA_GET_AFFINITY_CMD_GET_ERR_EID          20
#define CFE_TA_GET_TASK_AFFINITY_CMD_INF_EID         21
#define CFE_TA_GET_TASK_AFFINITY_DISCREPANCY_INF_EID 22
#define CFE_TA_CORE_INF_EID                          23
// --- cfe_evs_extern_typedefs.h: the two enums TA uses ------------------------------------------
#define CFE_EVS_EventType_DEBUG       1
#define CFE_EVS_EventType_INFORMATION 2
#define CFE_EVS_EventType_ERROR       3
#define CFE_EVS_EventType_CRITICAL    4
#define CFE_EVS_EventFilter_BINARY    0
// --- cfe_ta_fcncodes.h -------------------------------------------------------------------------
#define CFE_TA_NOOP_CC              0
#define CFE_TA_RESET_COUNTERS_CC    1
#define CFE_TA_QUERY_ALL_TASKS_CC   2
#define CFE_TA_SET_TASK_AFFINITY_CC 3
#define CFE_TA_GET_TASK_AFFINITY_CC 4
// --- cfe_ta_msgids.h ---------------------------------------------------------------------------
#define CFE_TA_HK_TLM_MID  2063
#define CFE_TA_CMD_MID     6162
#define CFE_TA_SEND_HK_MID 6163
// --- cfe_ta_platform_cfg.h ---------------------------------------------------------------------
#define CFE_PLATFORM_TA_START_TASK_PRIORITY   75
#define CFE_PLATFORM_TA_START_TASK_STACK_SIZE 16384
// --- cfe_ta_tasklist.h -------------------------------------------------------------------------
// CFE_TA_Mask_Type: where a task's affinity comes from.
#define CFE_TA_OsDefault 0 // Use O/S Default Affinity
#define CFE_TA_Mask      1 // Use User Specified Affinity Mask
#define CFE_TA_Added     2 // Was not found in list so use O/S Default Affinity

// CFE_TA_Status
#define CFE_TA_Status_Unknown 0
#define CFE_TA_Status_Ok      1
#define CFE_TA_Status_Error   2

class CFE_TA_CpuTaskAffinity_t
{
  U8 TaskName[CFE_MISSION_MAX_API_LEN];
  OS_cpuset_t CpuMask;
  OS_cpuset_t CpuFromOS;
  U8 _pad0[2]; // C pads here; HolyC packs. See tools/cfs/check_padding.py
  I32 Type;    // CFE_TA_Mask_Type, a C ENUM -- 4 bytes
  I32 Status;  // CFE_TA_Status, likewise
};
// --- cfe_ta_msgdefs.h / _msgstruct.h ----------------------------------------------------------
// The command and telemetry payloads. CFE_MSG_CommandHeader and CFE_MSG_TelemetryHeader come
// from cfe_msg_init.HC's include of the message headers.
class CFE_TA_QueryAllTasksCmd_Payload_t
{
  U8 FileName[CFE_MISSION_MAX_PATH_LEN];
};

class CFE_TA_SetTaskAffinityCmd_Payload_t
{
  U8 TaskName[CFE_MISSION_MAX_API_LEN];
  U8 AffinityMask[CFE_MISSION_TA_MAX_NUM_CPUS / 8];
};

class CFE_TA_GetTaskAffinityCmd_Payload_t
{
  U8 TaskName[CFE_MISSION_MAX_API_LEN];
};

class CFE_TA_HousekeepingTlm_Payload_t
{
  U8 CommandCounter;
  U8 CommandErrorCounter;
  U8 StartupCounter;
  U8 StartupErrorCounter;
};

class CFE_TA_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TA_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TA_SendHkCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TA_QueryAllTasksCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TA_QueryAllTasksCmd_Payload_t Payload;
};

class CFE_TA_SetTaskAffinityCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TA_SetTaskAffinityCmd_Payload_t Payload;
};

class CFE_TA_GetTaskAffinityCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TA_GetTaskAffinityCmd_Payload_t Payload;
};

class CFE_TA_HousekeepingTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_TA_HousekeepingTlm_Payload_t Payload;
};
// --- cfe_ta_task.h: the globals ----------------------------------------------------------------
class CFE_TA_DiagInfo_t
{
  U16 CoresConfigured; // Number of physical cores configured
  U16 TACoresMax;      // Maximum TA support bits
  CFE_TA_CpuTaskAffinity_t CpuTaskAffinity[OS_MAX_TASKS]; // Tracked task array
};

class CFE_TA_Global_t
{
  U8 CommandCounter;      // Commands successfully processed
  U8 CommandErrorCounter; // Commands that failed processing
  U8 StartupCounter;      // Tasks processed during startup
  U8 StartupErrorCounter; // Tasks that failed affinity assignment at startup
  CFE_TA_HousekeepingTlm_t TA_TlmPkt; // Housekeeping telemetry packet
  CFE_TA_DiagInfo_t CFE_TA_DiagInfo;  // Diagnostic packet for Query All command
  U32 TA_CommandPipe; // CFE_SB_PipeId_t, the command pipe ID
  U32 TA_AppID;       // CFE_ES_AppId_t
};
// --- what the layers around this one provide ---------------------------------------------------
// SB, EVS and ES. In a built port these are the translated modules; in the differential oracle
// the driver supplies recording stubs, the same arrangement fs has for OSAL.
// osapi-common.h's event codes, which CFE_TA_OS_EventHandler switches on. Duplicated from
// OSAL's osapi_common.HC rather than included, for the reason the whole boundary exists: the
// cFE side must not pull in OSAL's implementation.
#ifndef OS_EVENT_RESERVED
#define OS_EVENT_RESERVED           0
#define OS_EVENT_RESOURCE_ALLOCATED 1
#define OS_EVENT_RESOURCE_CREATED   2
#define OS_EVENT_RESOURCE_DELETED   3
#define OS_EVENT_TASK_STARTUP       4
#endif
// cfe_sb_api_typedefs.h. A union whose other members exist only to force the ALIGNMENT a
// message buffer needs; RawData is sizeof(CFE_MSG_Message_t).
union CFE_SB_Buffer
{
  CFE_MSG_Message Msg; // Base message type without enforced alignment
  I64 LongInt;         // Align to support Long Integer
  F64 LongDouble;      // Align to support Long Double
  U8 RawData[6];       // Allows access as opaque octet data; sizeof(CFE_MSG_Message_t)
};

#define CFE_SB_PEND_FOREVER (-1)
// THREE ENUM MEMBERS, and all three were WRONG -- 5/6/2 where NASA has 8/9/3. They are passed
// to CFE_ES_ExitApp and CFE_ES_WaitForSystemState, which the driver stubs, so the transcript
// never looked at them; and check_constants.py could not look either, because its `#ifdef` test
// cannot see an ENUMERATOR, so all three were classified as names this port invented. The tool
// now retries the undefined set as expressions and these were the first thing it caught.
#define CFE_ES_RunStatus_CORE_APP_INIT_ERROR    8
#define CFE_ES_RunStatus_CORE_APP_RUNTIME_ERROR 9
#define CFE_ES_SystemState_CORE_READY           3
#define CFE_PLATFORM_CORE_MAX_STARTUP_MSEC      30000
I32 CFE_EVS_Register(U8 *Filters, U16 NumFilteredEvents, U16 FilterScheme);
// VARIADIC, and it has to say so here: a HolyC call site builds the implicit (argc, argv) pair
// only if it already knows the callee is variadic, and this declaration is the only thing above
// TA's twenty event calls that can tell it. It was a three-parameter stub while EVS was not
// translated; cfe_evs.HC now defines the real one, included after this file, and the two
// disagreeing is invisible to every gate that compares definitions. tools/cfs/check_variadic.py.
I32 CFE_EVS_SendEvent(U16 EventID, U16 EventType, U8 *Spec, ...);
U0 CFE_ES_PerfLogEntry(U32 Marker);
U0 CFE_ES_PerfLogExit(U32 Marker);
U0 CFE_ES_ExitApp(U32 ExitStatus);
I32 CFE_ES_WaitForSystemState(U32 MinSystemState, U32 TimeOutMilliseconds);
U0 CFE_ES_IncrementTaskCounter();
I32 CFE_SB_CreatePipe(U32 *PipeIdPtr, U16 Depth, U8 *PipeName);
I32 CFE_SB_Subscribe(U32 MsgId, U32 PipeId);
I32 CFE_SB_ReceiveBuffer(CFE_SB_Buffer **BufPtr, U32 PipeId, I32 TimeOut);
U0 CFE_SB_TimeStampMsg(CFE_MSG_Message *MsgPtr);
I32 CFE_SB_TransmitMsg(CFE_MSG_Message *MsgPtr, Bool IncrementSequenceCount);
I32 OS_TaskGetIdByName(U32 *task_id, U8 *task_name);
I32 OS_GetResourceName(U32 object_id, U8 *buffer, I64 buffer_size);
I32 OS_RegisterEventHandler(I32 (*handler)(I64, U32, U8 *));
// Defined in cfe_ta_dispatch.HC, which NASA builds from a separate source selected by
// CFE_EDS_ENABLED. Declared here because CFE_TA_TaskMain calls it and comes first.
U0 CFE_TA_TaskPipe(CFE_SB_Buffer *SBBufPtr);
I32 CFE_TA_OS_EventHandler(I64 event, U32 object_id, U8 *data);
I32 CFE_TA_SetStartupAffinity(U8 *taskname);
// --- cfe_ta_task.c -----------------------------------------------------------------------------
// Task Globals
CFE_TA_Global_t CFE_TA_Global;

// The live, modifiable working array for TA
CFE_TA_CpuTaskAffinity_t CFE_TA_CpuTaskAffinity[OS_MAX_TASKS];

I32 CFE_TA_EarlyInit()
{
  CFE_TA_CpuTaskAffinity_t *TablePtr;
  U32 i;

  // Clear task global and live affinity array
  MemSet(&CFE_TA_Global, 0, sizeof(CFE_TA_Global_t));
  MemSet(CFE_TA_CpuTaskAffinity, 0, sizeof(CFE_TA_CpuTaskAffinity));

  // Query the central config database (returns const void *) and cast it
  TablePtr = CFE_Config_GetObjPointer(CFE_CONFIGID_TA_AFFINITY_TABLE);

  // If the target provided a table, copy it into live memory
  if (TablePtr != NULL) {
    for (i = 0; i < OS_MAX_TASKS; i++) {
      // Check for the empty string terminator
      if (TablePtr[i].TaskName[0] == '\0')
        break;
      // NASA writes `CFE_TA_CpuTaskAffinity[i] = TablePtr[i];` -- a 32-byte class assignment.
      // HolyC copies only EIGHT bytes for a class larger than that (HOLYC_STRUCT_LIMITS.md #2,
      // still open), so the name came through and the mask, the type and the status did not.
      // Found by the transcript, which read `mask=00 type=0` where NASA's C had `mask=01
      // type=1`. MemCpy of the same object is the same operation written out.
      MemCpy(&CFE_TA_CpuTaskAffinity[i], &TablePtr[i], sizeof(CFE_TA_CpuTaskAffinity_t));
    }
  }

  // Register TA function as the task event handler
  OS_RegisterEventHandler(&CFE_TA_OS_EventHandler);

  return CFE_SUCCESS;
}

// NOT DRIVEN BY THE ORACLE, and it cannot be: it pends forever on CFE_SB_ReceiveBuffer and
// ends in CFE_ES_ExitApp, which does not return. Translated because the module registers it as
// its TaskMain and a port that omits it has a module that exists and never runs.
U0 CFE_TA_TaskMain()
{
  I32 Status;
  CFE_SB_Buffer *SBBufPtr;

  CFE_ES_PerfLogEntry(CFE_MISSION_TA_MAIN_PERF_ID);

  Status = CFE_TA_TaskInit();

  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_TA_TaskMain: Application Init Failed,RC=0x%08X\n", Status);
    CFE_ES_PerfLogExit(CFE_MISSION_TA_MAIN_PERF_ID);
    // Note: CFE_ES_ExitApp will not return
    CFE_ES_ExitApp(CFE_ES_RunStatus_CORE_APP_INIT_ERROR);
  }

  // Wait for other apps to start.
  // It is important that the core apps are present before this starts receiving
  // messages from the command pipe, as some of those handlers might depend on
  // the other core apps.
  CFE_ES_WaitForSystemState(CFE_ES_SystemState_CORE_READY, CFE_PLATFORM_CORE_MAX_STARTUP_MSEC);

  // Main loop
  while (Status == CFE_SUCCESS) {
    // Increment the Main task Execution Counter
    CFE_ES_IncrementTaskCounter();

    CFE_ES_PerfLogExit(CFE_MISSION_TA_MAIN_PERF_ID);

    // Pend on receipt of packet
    Status = CFE_SB_ReceiveBuffer(&SBBufPtr, CFE_TA_Global.TA_CommandPipe, CFE_SB_PEND_FOREVER);

    CFE_ES_PerfLogEntry(CFE_MISSION_TA_MAIN_PERF_ID);

    if (Status == CFE_SUCCESS) {
      // Process cmd pipe msg
      CFE_TA_TaskPipe(SBBufPtr);
    } else {
      CFE_ES_WriteToSysLog("CFE_TA_TaskMain: Error reading cmd pipe,RC=0x%08X\n", Status);
    }
  } // end while

  // while loop exits only if CFE_SB_ReceiveBuffer returns error
  CFE_ES_ExitApp(CFE_ES_RunStatus_CORE_APP_RUNTIME_ERROR);
}

I32 CFE_TA_TaskInit()
{
  I32 Status;
  U32 AppID; // CFE_ES_AppId_t
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];

  // Initialize housekeeping packet
  Status = CFE_MSG_Init(&CFE_TA_Global.TA_TlmPkt.TelemetryHeader.Msg,
                        CFE_SB_ValueToMsgId(CFE_TA_HK_TLM_MID),
                        sizeof(CFE_TA_HousekeepingTlm_t));

  if (Status != CFE_SUCCESS)
    return Status;

  CFE_TA_Global.CFE_TA_DiagInfo.CoresConfigured = OS_TaskAffinityCoresConfigured();
  CFE_TA_Global.CFE_TA_DiagInfo.TACoresMax = OS_MAX_CPUS;

  // Query and verify the AppID
  Status = CFE_ES_GetAppID(&AppID);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_TA_TaskInit: Call to CFE_ES_GetAppID Failed:RC=0x%08X\n", Status);
    return Status;
  }

  // Register EVS task for event services
  Status = CFE_EVS_Register(NULL, 0, CFE_EVS_EventFilter_BINARY);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_TA_TaskInit: Call to CFE_TA_Register Failed:RC=0x%08X\n", Status);
    return Status;
  }

  // Create software bus command pipe
  Status = CFE_SB_CreatePipe(&CFE_TA_Global.TA_CommandPipe, CFE_TA_PIPE_DEPTH, CFE_TA_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_TA_TaskInit: Call to CFE_SB_CreatePipe Failed:RC=0x%08X\n", Status);
    return Status;
  }

  // Subscribe to command and telemetry requests coming in on the command pipe
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_TA_CMD_MID), CFE_TA_Global.TA_CommandPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_TA_TaskInit: Subscribing to Cmds Failed:RC=0x%08X\n", Status);
    return Status;
  }

  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_TA_SEND_HK_MID), CFE_TA_Global.TA_CommandPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_TA_TaskInit: Subscribing to HK Request Failed:RC=0x%08X\n", Status);
    return Status;
  }

  // Write the AppID to the global location, now that the rest of initialization is done
  CFE_TA_Global.TA_AppID = AppID;

  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "cFE", CFE_SRC_VERSION,
                              CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);

  CFE_EVS_SendEvent(CFE_TA_CORE_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Configured cores = %u, TA support max limit = %u",
                    OS_TaskAffinityCoresConfigured(), CFE_MISSION_TA_MAX_NUM_CPUS);

  CFE_EVS_SendEvent(CFE_TA_INIT_INF_EID, CFE_EVS_EventType_INFORMATION, "cFE TA Initialized: %s",
                    VersionString);

  return CFE_SUCCESS;
}

I32 CFE_TA_CleanUpApp(U32 AppId)
{
  // Placeholder

  return CFE_SUCCESS;
}

I32 CFE_TA_NoopCmd(CFE_TA_NoopCmd_t *data)
{
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];
  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "cFE", CFE_SRC_VERSION,
                              CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);

  CFE_EVS_SendEvent(CFE_TA_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION, "No-op Cmd Rcvd: %s",
                    VersionString);

  // This one DOES increment, unlike the reset command two functions down. An earlier version
  // of this translation left the increment out, and the transcript read cc=0 against NASA's
  // cc=1 three command dispatches later -- the second invented body the oracle caught in this
  // module, and both were tails I had not read to the end of.
  CFE_TA_Global.CommandCounter++;

  return CFE_SUCCESS;
}

I32 CFE_TA_ReportHousekeepingCmd(CFE_TA_SendHkCmd_t *data)
{
  // Copy the TA command counters to the housekeeping packet
  CFE_TA_Global.TA_TlmPkt.Payload.CommandCounter = CFE_TA_Global.CommandCounter;
  CFE_TA_Global.TA_TlmPkt.Payload.CommandErrorCounter = CFE_TA_Global.CommandErrorCounter;
  CFE_TA_Global.TA_TlmPkt.Payload.StartupCounter = CFE_TA_Global.StartupCounter;
  CFE_TA_Global.TA_TlmPkt.Payload.StartupErrorCounter = CFE_TA_Global.StartupErrorCounter;

  // Send housekeeping telemetry packet
  CFE_SB_TimeStampMsg(&CFE_TA_Global.TA_TlmPkt.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&CFE_TA_Global.TA_TlmPkt.TelemetryHeader.Msg, TRUE);

  return CFE_SUCCESS;
}

I32 CFE_TA_ResetCountersCmd(CFE_TA_ResetCountersCmd_t *data)
{
  // Clear commands processed by TA task.
  // ONLY the two command counters: the startup counters are deliberately left alone, and an
  // earlier version of this translation zeroed all four. The transcript caught it on the first
  // run -- NASA's C reported sc=9 sec=10 after the reset where this reported 0 and 0.
  CFE_TA_Global.CommandCounter = 0;
  CFE_TA_Global.CommandErrorCounter = 0;

  CFE_EVS_SendEvent(CFE_TA_RESET_COUNTERS_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Reset Counters Command Received");

  // NOTE: Historically the reset counters command does _NOT_ increment the command counter

  return CFE_STATUS_NO_COUNTER_INCREMENT;
}

I32 CFE_TA_QueryAllTasksCmd(CFE_TA_QueryAllTasksCmd_t *data)
{
  CFE_FS_Header_t FileHeader;
  U32 FileDescriptor = OS_OBJECT_ID_UNDEFINED;
  U32 EntryCount = OS_MAX_TASKS; // Set to Max Tasks
  U32 FileSize = 0;
  I32 OsStatus;
  I32 Result;
  CFE_TA_QueryAllTasksCmd_Payload_t *CmdPtr = &data->Payload;
  U8 QueryAllFilename[OS_MAX_PATH_LEN];

  // FIX: Copy the ENTIRE task affinity list array
  MemSet(CFE_TA_Global.CFE_TA_DiagInfo.CpuTaskAffinity, 0,
         sizeof(CFE_TA_Global.CFE_TA_DiagInfo.CpuTaskAffinity));

  MemCpy(CFE_TA_Global.CFE_TA_DiagInfo.CpuTaskAffinity, CFE_TA_CpuTaskAffinity,
         sizeof(CFE_TA_Global.CFE_TA_DiagInfo.CpuTaskAffinity));

  // Populate the Diag Packet Header just to be safe
  CFE_TA_Global.CFE_TA_DiagInfo.CoresConfigured = OS_TaskAffinityCoresConfigured();
  CFE_TA_Global.CFE_TA_DiagInfo.TACoresMax = CFE_MISSION_TA_MAX_NUM_CPUS;

  // Copy the commanded filename into local buffer to ensure size limitation and to allow for
  // modification
  Result = CFE_FS_ParseInputFileNameEx(QueryAllFilename, CmdPtr->FileName,
                                       sizeof(QueryAllFilename), CFE_MISSION_MAX_PATH_LEN,
                                       CFE_PLATFORM_ES_DEFAULT_TASK_LOG_FILE,
                                       CFE_FS_GetDefaultMountPoint(
                                           CFE_FS_FileCategory_BINARY_DATA_DUMP),
                                       CFE_FS_GetDefaultExtension(
                                           CFE_FS_FileCategory_BINARY_DATA_DUMP));

  if (Result == CFE_SUCCESS) {
    // Create (or truncate) TA task log data file
    OsStatus = OS_OpenCreate(&FileDescriptor, QueryAllFilename,
                             OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE, OS_WRITE_ONLY);

    if (OsStatus != OS_SUCCESS) {
      CFE_EVS_SendEvent(CFE_TA_TASKINFO_OSCREATE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Failed to write Task Info file, OS_OpenCreate RC = %ld", OsStatus);
      Result = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }
  } else {
    CFE_EVS_SendEvent(CFE_TA_TASKINFO_FILENAME_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Failed to write Task Info file, CFE_FS_ParseInputFileNameEx RC = %08x",
                      Result);
  }

  if (Result >= 0) {
    // Initialize cFE file header
    CFE_FS_InitHeader(&FileHeader, CFE_TA_TASK_LOG_DESC, CFE_FS_SubType_TA_QUERYALLTASKS);

    // Output the Standard cFE File Header to the App File
    Result = CFE_FS_WriteHeader(FileDescriptor, &FileHeader);

    if (Result != sizeof(CFE_FS_Header_t)) {
      OS_close(FileDescriptor);
      CFE_TA_Global.CommandErrorCounter++;
      CFE_EVS_SendEvent(CFE_TA_TASKINFO_WRHDR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Failed to write Task Info file, WriteHdr RC = 0x%08X", Result);
      return CFE_SUCCESS;
    }

    // Maintain statistics of amount of data written to file
    FileSize += sizeof(CFE_FS_Header_t);

    // Write the entire Diag Packet to file
    OsStatus = OS_write(FileDescriptor, &CFE_TA_Global.CFE_TA_DiagInfo,
                        sizeof(CFE_TA_DiagInfo_t));

    if (OsStatus != sizeof(CFE_TA_DiagInfo_t)) {
      OS_close(FileDescriptor);
      CFE_TA_Global.CommandErrorCounter++;
      CFE_EVS_SendEvent(CFE_TA_TASKINFO_WR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Failed to write Task Info file, Task write RC = %ld", OsStatus);
      return CFE_SUCCESS;
    }

    // Add the full size of the payload, not just one task
    FileSize += sizeof(CFE_TA_DiagInfo_t);

    OS_close(FileDescriptor);

    // Increment success counter and send event
    CFE_TA_Global.CommandCounter++;

    CFE_EVS_SendEvent(CFE_TA_TASKINFO_EID, CFE_EVS_EventType_INFORMATION,
                      "Task Info file written to %s, Entries=%d, FileSize=%d", QueryAllFilename,
                      EntryCount, FileSize);
  } else {
    CFE_TA_Global.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

// Convert from the ground payload array to the OSAL Affinity Mask
U0 CFE_TA_Cpu_Set(U8 *AffinityMask, OS_cpuset_t *cpuset)
{
  U32 i;

  OS_CPUSET_ZERO(cpuset);

  for (i = 0; i < CFE_MISSION_TA_MAX_NUM_CPUS && i < OS_MAX_CPUS &&
              i < OS_TaskAffinityCoresConfigured();
       i++) {
    if (AffinityMask[i / 8] & (1 << (i % 8)))
      OS_CPUSET_SET(i, cpuset);
  }
}

I32 CFE_TA_SetTaskAffinityCmd(CFE_TA_SetTaskAffinityCmd_t *data)
{
  CFE_TA_SetTaskAffinityCmd_Payload_t *CmdPtr = &data->Payload;
  I32 Status = CFE_SUCCESS;
  OS_cpuset_t cpuset, cpuget;
  U32 task_id = OS_OBJECT_ID_UNDEFINED;
  U32 i;
  // Create 64-bit printable variables for the event message
  U64 PrintableMask = 0;
  U64 PrintableOsMask = 0;

  // Look for the task in the task affinity list
  for (i = 0; i < OS_MAX_TASKS; i++) {
    // Reached the end of the entries, task not found
    if (StrLen(CFE_TA_CpuTaskAffinity[i].TaskName) == 0) {
      Status = CFE_TA_APP_TASK_NOT_FOUND;

      CFE_EVS_SendEvent(CFE_TA_SET_AFFINITY_CMD_NOTFOUND_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Set Task Affinity Failed, task (%s) not found", CmdPtr->TaskName);

      CFE_TA_Global.CommandErrorCounter++;
      break;
    } else if (StrCmp(CmdPtr->TaskName, CFE_TA_CpuTaskAffinity[i].TaskName) == 0) {
      // Task found in the list
      CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Ok;

      // Translate from user payload byte array to OSAL affinity struct
      CFE_TA_Cpu_Set(CmdPtr->AffinityMask, &cpuset);

      // For tasks IDs, defer to OSAL for name lookup
      Status = OS_TaskGetIdByName(&task_id, CmdPtr->TaskName);

      if (Status == OS_SUCCESS)
        Status = OS_TaskAffinitySetAffinity(task_id, cpuset);

      if (Status == OS_SUCCESS) {
        // Save the assigned cpuset natively
        CFE_TA_CpuTaskAffinity[i].CpuMask = cpuset;

        // Get the task affinity back from OSAL to verify
        Status = OS_TaskAffinityGetAffinity(task_id, &cpuget);

        if (Status == OS_SUCCESS) {
          // Save the OSAL-verified struct directly into our table
          CFE_TA_CpuTaskAffinity[i].CpuFromOS = cpuget;
          CFE_TA_CpuTaskAffinity[i].Type = CFE_TA_Mask;

          // Pack the command byte array into the printable variable. NASA guards the length
          // with a ternary; CFE_MISSION_TA_MAX_NUM_CPUS/8 is 8 here, so the guard picks 8.
          MemCpy(&PrintableMask, CmdPtr->AffinityMask, 8);

          // Copy the raw OSAL struct directly into the printable variable (up to 8 bytes).
          // sizeof(OS_cpuset_t) is 1 in this configuration, so the guard picks 1.
          MemCpy(&PrintableOsMask, &cpuget, sizeof(OS_cpuset_t));

          CFE_EVS_SendEvent(CFE_TA_SET_TASK_AFFINITY_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                            "Set Task Affinity for %s: Type = %d, mask = 0x%016llX, from O/S = "
                            "0x%016llX",
                            CFE_TA_CpuTaskAffinity[i].TaskName, CFE_TA_CpuTaskAffinity[i].Type,
                            PrintableMask, PrintableOsMask);

          CFE_TA_Global.CommandCounter++;
        } else {
          // Get Task Affinity Failed
          Status = CFE_TA_APP_GET_TASK_AFFINITY_FAILED;
          CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Error;

          CFE_EVS_SendEvent(CFE_TA_SET_AFFINITY_CMD_GET_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Set Task Affinity Failed for task (%s), could not Get Task "
                            "Affinity, Status = %d",
                            CmdPtr->TaskName, Status);

          CFE_TA_Global.CommandErrorCounter++;
        }
      } else {
        // Set Task Affinity Failed
        Status = CFE_TA_APP_SET_TASK_AFFINITY_FAILED;
        CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Error;

        CFE_EVS_SendEvent(CFE_TA_SET_AFFINITY_CMD_SET_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Set Task Affinity Failed for task (%s), could not Set Task Affinity, "
                          "Status = %d",
                          CmdPtr->TaskName, Status);

        CFE_TA_Global.CommandErrorCounter++;
      }
      break;
    }
  }

  return Status;
}

I32 CFE_TA_GetTaskAffinityCmd(CFE_TA_GetTaskAffinityCmd_t *data)
{
  CFE_TA_GetTaskAffinityCmd_Payload_t *CmdPtr = &data->Payload;
  I32 Status = CFE_SUCCESS;
  OS_cpuset_t cpuset;
  U32 task_id = OS_OBJECT_ID_UNDEFINED;
  U32 i;
  // Create 64-bit printable variable for the event message
  U64 PrintableOsMask = 0;

  // Look for the task in the task affinity list
  for (i = 0; i < OS_MAX_TASKS; i++) {
    if (StrLen(CFE_TA_CpuTaskAffinity[i].TaskName) == 0) {
      Status = CFE_TA_APP_TASK_NOT_FOUND;

      // Reached the end of the entries, task not found
      CFE_EVS_SendEvent(CFE_TA_GET_AFFINITY_CMD_NOTFOUND_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Get Task Affinity Failed, task (%s) not found", CmdPtr->TaskName);

      CFE_TA_Global.CommandErrorCounter++;
      break;
    } else if (StrCmp(CmdPtr->TaskName, CFE_TA_CpuTaskAffinity[i].TaskName) == 0) {
      // Task found in the list
      CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Ok;

      // For tasks IDs, defer to OSAL for name lookup
      Status = OS_TaskGetIdByName(&task_id, CmdPtr->TaskName);

      if (Status == OS_SUCCESS) {
        // Get the task affinity
        Status = OS_TaskAffinityGetAffinity(task_id, &cpuset);
      }

      if (Status == OS_SUCCESS) {
        // Compare table task affinity with value just read using memcmp on OS_cpuset_t
        if (MemCmp(&cpuset, &CFE_TA_CpuTaskAffinity[i].CpuFromOS, sizeof(OS_cpuset_t)) != 0) {
          CFE_EVS_SendEvent(CFE_TA_GET_TASK_AFFINITY_DISCREPANCY_INF_EID,
                            CFE_EVS_EventType_INFORMATION,
                            "Get Task Affinity: Affinity stored in TA was different than "
                            "current O/S return");

          // Put latest affinity from OS into TA internal structure
          CFE_TA_CpuTaskAffinity[i].CpuFromOS = cpuset;
        }

        // Copy the raw OSAL struct directly into the printable variable (up to 8 bytes)
        MemCpy(&PrintableOsMask, &cpuset, sizeof(OS_cpuset_t));

        CFE_EVS_SendEvent(CFE_TA_GET_TASK_AFFINITY_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "Get Task Affinity for %s: Type = %d, O/S Mask = 0x%016llX",
                          CFE_TA_CpuTaskAffinity[i].TaskName, CFE_TA_CpuTaskAffinity[i].Type,
                          PrintableOsMask);

        CFE_TA_Global.CommandCounter++;
      } else {
        // Get Task Affinity Failed
        Status = CFE_TA_APP_GET_TASK_AFFINITY_FAILED;
        CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Error;

        CFE_EVS_SendEvent(CFE_TA_GET_AFFINITY_CMD_GET_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Get Task Affinity Failed for task (%s), Status = %d",
                          CmdPtr->TaskName, Status);

        CFE_TA_Global.CommandErrorCounter++;
      }

      break;
    }
  }

  return Status;
}

I32 CFE_TA_SetStartupAffinity(U8 *taskname)
{
  I32 Status = CFE_SUCCESS;
  OS_cpuset_t cpuget;
  U32 task_id = OS_OBJECT_ID_UNDEFINED;
  U32 i;

  // For tasks IDs, defer to OSAL for name lookup
  Status = OS_TaskGetIdByName(&task_id, taskname);

  if (Status == OS_SUCCESS) {
    for (i = 0; i < OS_MAX_TASKS; i++) {
      if (StrLen(CFE_TA_CpuTaskAffinity[i].TaskName) == 0) {
        // Couldn't find the task in the task affinity table
        CFE_ES_WriteToSysLog(
            "CFE_TA_SetStartupAffinity: Set Startup Affinity - task (%s) not found in TA list, "
            "adding\n",
            taskname);

        // Add the task to the affinity table
        StrNCpy(CFE_TA_CpuTaskAffinity[i].TaskName, taskname, CFE_MISSION_MAX_API_LEN);

        // Safely zero out the newly added OS_cpuset_t structs
        OS_CPUSET_ZERO(&CFE_TA_CpuTaskAffinity[i].CpuMask);
        OS_CPUSET_ZERO(&CFE_TA_CpuTaskAffinity[i].CpuFromOS);
        CFE_TA_CpuTaskAffinity[i].Type = CFE_TA_Added;

        // Get the task affinity
        Status = OS_TaskAffinityGetAffinity(task_id, &cpuget);

        if (Status == OS_SUCCESS) {
          // Save the OS_cpuset_t directly into our table
          CFE_TA_CpuTaskAffinity[i].CpuFromOS = cpuget;
          CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Ok;
        } else {
          Status = CFE_TA_APP_GET_TASK_AFFINITY_FAILED;
          CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Error;

          CFE_ES_WriteToSysLog("CFE_TA_SetStartupAffinity: Set Startup Affinity for task (%s) could "
                                 "not Get Task Affinity, Status = %d\n",
                                 taskname, Status);
        }
        break;
      } else if (StrCmp(taskname, CFE_TA_CpuTaskAffinity[i].TaskName) == 0) {
        // Task found in the list
        CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Ok;

        if (CFE_TA_CpuTaskAffinity[i].Type == CFE_TA_OsDefault) {
          // Use the O/S default behavior
          Status = OS_TaskAffinityGetAffinity(task_id, &cpuget);

          if (Status == OS_SUCCESS) {
            CFE_TA_CpuTaskAffinity[i].CpuFromOS = cpuget;
          } else {
            Status = CFE_TA_APP_GET_TASK_AFFINITY_FAILED;
            CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Error;

            CFE_ES_WriteToSysLog("CFE_TA_SetStartupAffinity: Set Startup Affinity for task (%s) could "
                                 "not Get Task Affinity, Status = %d\n",
                                 taskname, Status);
          }
        } else if (CFE_TA_CpuTaskAffinity[i].Type == CFE_TA_Mask) {
          // Use the User defined affinity mask (directly passing OS_cpuset_t!)
          Status = OS_TaskAffinitySetAffinity(task_id, CFE_TA_CpuTaskAffinity[i].CpuMask);

          if (Status == OS_SUCCESS) {
            Status = OS_TaskAffinityGetAffinity(task_id, &cpuget);

            if (Status == OS_SUCCESS) {
              CFE_TA_CpuTaskAffinity[i].CpuFromOS = cpuget;
            } else {
              Status = CFE_TA_APP_GET_TASK_AFFINITY_FAILED;
              CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Error;

              CFE_ES_WriteToSysLog("CFE_TA_SetStartupAffinity: Set Startup Affinity for task (%s) could "
                                 "not Get Task Affinity, Status = %d\n",
                                 taskname, Status);
            }
          } else {
            Status = CFE_TA_APP_SET_TASK_AFFINITY_FAILED;
            CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Error;

            CFE_ES_WriteToSysLog("CFE_TA_SetStartupAffinity: Set Startup Affinity for task (%s) could "
                                 "not Set Task Affinity, Status = %d\n",
                                 taskname, Status);
          }
        } else {
          Status = CFE_TA_APP_INVALID_TASK_AFFINITY_TYPE;
          CFE_TA_CpuTaskAffinity[i].Status = CFE_TA_Status_Error;

          CFE_ES_WriteToSysLog("CFE_TA_SetStartupAffinity: Invalid affinity type (%d) for task (%s)\n",
                               CFE_TA_CpuTaskAffinity[i].Type, taskname);
        }
        break;
      }
    }
  }

  if (Status == CFE_SUCCESS)
    CFE_TA_Global.StartupCounter++;
  else
    CFE_TA_Global.StartupErrorCounter++;

  return Status;
}

// Task creation event handler.
// Note this overrides previously registered event handler
// Sets the kernel task name using a glibc-specific (non-posix) function.
// Calls the TA Startup Affinity function
I32 CFE_TA_OS_EventHandler(I64 event, U32 object_id, U8 *data)
{
  U8 taskname[OS_MAX_API_NAME];

  MemSet(taskname, 0, sizeof(taskname));

  switch (event) {
    case OS_EVENT_RESOURCE_ALLOCATED:
      // resource/id is newly allocated but not yet created.  Invoked within locked region.
      break;
    case OS_EVENT_RESOURCE_CREATED:
      // resource/id has been fully created/finalized.  Invoked outside locked region.
      break;
    case OS_EVENT_RESOURCE_DELETED:
      // resource/id has been deleted.  Invoked outside locked region.
      break;
    case OS_EVENT_TASK_STARTUP:
      // New task is starting. Invoked from within the task context.
      // Get the name from OSAL and propagate to the pthread/system layer
      if (OS_GetResourceName(object_id, taskname, sizeof(taskname)) == OS_SUCCESS) {
        // Assign startup affinity via a TA app function
        CFE_TA_SetStartupAffinity(taskname);
      }
      break;

    default:
      break;
  }

  return OS_SUCCESS;
}
#endif
