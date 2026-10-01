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

// 1:1 HolyC translation of cFE modules/evs/fsw/src/cfe_evs_task.c -- THE EVS TASK: its early
// init, its message loop, and the twenty ground commands. This is the largest of EVS's six
// sources (1,485 lines) and the one that makes the module a task rather than a library.
//
// INCLUDE cfe_evs_global.HC, cfe_evs_utils.HC and cfe_evs_log.HC FIRST, and cfe_evs.HC before
// the command handlers that call CFE_EVS_Register.
//
// WHERE CFE_EVS_Global LIVES. NASA defines it here and declares it extern in cfe_evs_task.h;
// this translation defines it in cfe_evs_global.HC, beside its type, because HolyC has no usable
// forward declaration for a variable and the three files included before this one all use it.
// That is the module's one placement deviation and it is recorded at both ends.
//
// THE RESET AREA. CFE_EVS_EarlyInit asks the PSP for the reset area and takes the EVS log out of
// it, which means it needs the WHOLE of CFE_ES_ResetData_t -- it compares the area's size against
// `sizeof(CFE_ES_ResetData_t)` and panics if it is short. So eight ES and TIME typedefs are
// declared below. They are types, not code: no ES function is translated here, and
// check_padding.py verifies every offset and every size against NASA's own compiler.
#ifndef CFE_EVS_TASK_HC
#define CFE_EVS_TASK_HC
// --- cfe_evs_task.h ---------------------------------------------------------------------------
#define CFE_EVS_PIPE_DEPTH 32
#define CFE_EVS_PIPE_NAME  "EVS_CMD_PIPE"
#define CFE_EVS_NO_MASK    0
// Local to cfe_evs_task.c: the delay before a PSP panic, so the syslog line can be read.
#define CFE_EVS_PANIC_DELAY 500
// --- cfe_perfids.h ----------------------------------------------------------------------------
#define CFE_MISSION_EVS_MAIN_PERF_ID 2
// --- cfe_evs_internal_cfg.h, through CFE_PLATFORM_EVS_CFGVAL ----------------------------------
#define CFE_PLATFORM_EVS_PORT_DEFAULT            0x0001
#define CFE_PLATFORM_EVS_DEFAULT_LOG_MODE        1
#define CFE_PLATFORM_EVS_DEFAULT_MSG_FORMAT_MODE CFE_EVS_MsgFormat_LONG
#define CFE_PLATFORM_EVS_START_TASK_PRIORITY     61
#define CFE_PLATFORM_EVS_START_TASK_STACK_SIZE   8192
// --- cfe_error.h ------------------------------------------------------------------------------
#define CFE_EVS_RESET_AREA_POINTER 0xC2000005(I32)
// --- cfe_psp.h --------------------------------------------------------------------------------
#define CFE_PSP_SUCCESS            0
#define CFE_PSP_PANIC_MEMORY_ALLOC 3
#define CFE_PSP_PANIC_STARTUP_SEM  5
#define CFE_PSP_RST_TYPE_POWERON   2
// --- cfe_evs_fcncodes.h, through CFE_EVS_CCVAL ------------------------------------------------
// Each of these appears in an event message as "CC = %lu", so a wrong one is a wrong number in
// downlinked telemetry. check_constants.py compares all twenty-one against NASA's header.
#define CFE_EVS_NOOP_CC                   0
#define CFE_EVS_RESET_COUNTERS_CC         1
#define CFE_EVS_ENABLE_EVENT_TYPE_CC      2
#define CFE_EVS_DISABLE_EVENT_TYPE_CC     3
#define CFE_EVS_SET_EVENT_FORMAT_MODE_CC  4
#define CFE_EVS_ENABLE_APP_EVENT_TYPE_CC  5
#define CFE_EVS_DISABLE_APP_EVENT_TYPE_CC 6
#define CFE_EVS_ENABLE_APP_EVENTS_CC      7
#define CFE_EVS_DISABLE_APP_EVENTS_CC     8
#define CFE_EVS_RESET_APP_COUNTER_CC      9
#define CFE_EVS_SET_FILTER_CC             10
#define CFE_EVS_ENABLE_PORTS_CC           11
#define CFE_EVS_DISABLE_PORTS_CC          12
#define CFE_EVS_RESET_FILTER_CC           13
#define CFE_EVS_RESET_ALL_FILTERS_CC      14
#define CFE_EVS_ADD_EVENT_FILTER_CC       15
#define CFE_EVS_DELETE_EVENT_FILTER_CC    16
#define CFE_EVS_WRITE_APP_DATA_FILE_CC    17
#define CFE_EVS_WRITE_LOG_DATA_FILE_CC    18
#define CFE_EVS_SET_LOG_MODE_CC           19
#define CFE_EVS_CLEAR_LOG_CC              20
// --- cfe_es_api_typedefs.h --------------------------------------------------------------------
// CFE_ES_APPID_C(CFE_RESOURCEID_UNDEFINED); the wrap is the identity with the SIMPLE resourceid
// variant this port uses, as cfe_evs_utils.HC records.
#define CFE_ES_APPID_UNDEFINED 0

// --- the reset area's types ------------------------------------------------------------------
// CFE_ES_ResetData_t and the eight ES and TIME typedefs under it moved to their own file: the
// TIME module needs CFE_TIME_ResetVars_t and CFE_ES_ResetData_t too, and two files declaring the
// same class is not something HolyC can guard per-class. One guarded header, included by both.
#include "cfe_es_resetdata.HC"

// --- default_cfe_evs_msgdefs.h: the command payloads -----------------------------------------
// CFE_EVS_LogFileCmd_Payload_t and CFE_EVS_SetLogMode_Payload_t are in cfe_evs_log.HC, which is
// included before this file; the rest are here.
class CFE_EVS_AppDataCmd_Payload_t
{
  U8 AppDataFilename[CFE_MISSION_MAX_PATH_LEN]; // Filename where application data is written
};

class CFE_EVS_SetEventFormatMode_Payload_t
{
  U8 MsgFormat; // CFE_EVS_MsgFormat_Enum_t -- a uint8 typedef, not a C enum
  U8 Spare;     // Pad to even byte
};

class CFE_EVS_BitMaskCmd_Payload_t
{
  U8 BitMask; // BitMask to use in the command
  U8 Spare;   // Pad to even byte
};

class CFE_EVS_AppNameCmd_Payload_t
{
  U8 AppName[CFE_MISSION_MAX_API_LEN];
};

class CFE_EVS_AppNameEventIDCmd_Payload_t
{
  U8 AppName[CFE_MISSION_MAX_API_LEN];
  U16 EventID;
};

class CFE_EVS_AppNameBitMaskCmd_Payload_t
{
  U8 AppName[CFE_MISSION_MAX_API_LEN];
  U8 BitMask;
  U8 Spare; // Pad to even byte
};

class CFE_EVS_AppNameEventIDMaskCmd_Payload_t
{
  U8 AppName[CFE_MISSION_MAX_API_LEN];
  U16 EventID;
  U16 Mask;
};

// --- default_cfe_evs_msgstruct.h: the twenty-two command messages -----------------------------
// The four with no payload are a bare command header. CFE_EVS_WriteLogDataFileCmd_t and
// CFE_EVS_SetLogModeCmd_t are in cfe_evs_log.HC, beside the handlers that take them.
class CFE_EVS_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_EVS_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_EVS_ClearLogCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_EVS_SendHkCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_EVS_WriteAppDataFileCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_AppDataCmd_Payload_t Payload;
};

class CFE_EVS_SetEventFormatModeCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_SetEventFormatMode_Payload_t Payload;
};

class CFE_EVS_EnablePortsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_BitMaskCmd_Payload_t Payload;
};

class CFE_EVS_DisablePortsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_BitMaskCmd_Payload_t Payload;
};

class CFE_EVS_EnableEventTypeCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_BitMaskCmd_Payload_t Payload;
};

class CFE_EVS_DisableEventTypeCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_BitMaskCmd_Payload_t Payload;
};

class CFE_EVS_EnableAppEventsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_AppNameCmd_Payload_t Payload;
};

class CFE_EVS_DisableAppEventsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_AppNameCmd_Payload_t Payload;
};

class CFE_EVS_ResetAppCounterCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_AppNameCmd_Payload_t Payload;
};

class CFE_EVS_ResetAllFiltersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_AppNameCmd_Payload_t Payload;
};

class CFE_EVS_ResetFilterCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_AppNameEventIDCmd_Payload_t Payload;
};

class CFE_EVS_DeleteEventFilterCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_AppNameEventIDCmd_Payload_t Payload;
};

class CFE_EVS_EnableAppEventTypeCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_AppNameBitMaskCmd_Payload_t Payload;
};

class CFE_EVS_DisableAppEventTypeCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_AppNameBitMaskCmd_Payload_t Payload;
};

class CFE_EVS_AddEventFilterCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_AppNameEventIDMaskCmd_Payload_t Payload;
};

class CFE_EVS_SetFilterCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_AppNameEventIDMaskCmd_Payload_t Payload;
};
// --- what this file needs from elsewhere -------------------------------------------------------
// ES, PSP, SB and the config module. None of those is translated yet, so each is DECLARED here
// and supplied by whoever links -- the same arrangement cfe_fs_priv.HC and cfe_ta_task.HC record,
// and tools/blob_imports.py is what makes sure a missing one is not silently filled by the host
// C runtime.
I32 CFE_ES_GetAppID(U32 *AppIdPtr);
I32 CFE_ES_GetAppName(U8 *AppName, U32 AppId, I64 BufferLength);
I32 CFE_ES_GetAppIDByName(U32 *AppIdPtr, U8 *AppName);
I32 CFE_ES_AppID_ToIndex(U32 AppID, U32 *Idx);
I32 CFE_ES_GetResetType(U32 *ResetSubtypePtr);
U0 CFE_ES_PerfLogEntry(U32 Marker);
U0 CFE_ES_PerfLogExit(U32 Marker);
U0 CFE_ES_ExitApp(U32 ExitStatus);
U0 CFE_ES_IncrementTaskCounter();
I32 CFE_ES_WaitForSystemState(U32 MinSystemState, U32 TimeOutMilliseconds);
I32 CFE_PSP_GetResetArea(U64 *PtrToResetArea, U32 *SizeOfResetArea);
U0 CFE_PSP_Panic(I32 ErrorCode);
I32 CFE_SB_CreatePipe(U32 *PipeIdPtr, U16 Depth, U8 *PipeName);
I32 CFE_SB_Subscribe(CFE_SB_MsgId MsgId, U32 PipeId);
I32 CFE_SB_ReceiveBuffer(CFE_SB_Buffer **BufPtr, U32 PipeId, I32 TimeOut);
U0 CFE_SB_TimeStampMsg(CFE_MSG_Message *MsgPtr);
I32 OS_MutSemCreate(U32 *sem_id, U8 *sem_name, U32 options);
I32 OS_TaskDelay(U32 millisecond);
U0 CFE_Config_GetVersionString(U8 *Buffer, I64 Size, U8 *Component, U8 *SrcVersion, U8 *CodeName,
                               U8 *LastOffcl);
// cfe_evs_dispatch.c, the conditional source, which is translated beside this one and included
// after it: TaskMain calls into it.
U0 CFE_EVS_ProcessCommandPacket(CFE_SB_Buffer *SBBufPtr);
// Defined at the bottom of this file and used by cfe_evs_utils.HC, which is included BEFORE it.
// The declaration there is what the call sites bind to; this one is NASA's, in NASA's place.
Bool CFE_EVS_GetTypeEnable(U16 EventType);

// THE GLOBAL BELONGS HERE AND IS NOT HERE. NASA defines CFE_EVS_Global at this point in
// cfe_evs_task.c and declares it extern in cfe_evs_task.h; the translation defines it in
// cfe_evs_global.HC instead, because HolyC has no usable forward declaration for a variable and
// cfe_evs_utils.HC, cfe_evs_log.HC and cfe_evs.HC all use it before this file is read. The note
// at the top of cfe_evs_global.HC has the measurement. One definition either way.

// NASA declares this `static CFE_EVS_AppDataFile_t AppDataFile` INSIDE
// CFE_EVS_WriteAppDataFileCmd -- static, so not on the stack, and it is 136 bytes which is why.
// HolyC has no function-static; file scope is the faithful equivalent, as the differential
// driver records for the same construct elsewhere.
CFE_EVS_AppDataFile_t AppDataFile;

I32 CFE_EVS_EarlyInit()
{
  I32 OsStatus;
  I32 Status;
  I32 PspStatus;
  U32 resetAreaSize = 0;
  U64 resetAreaAddr;
  CFE_ES_ResetData_t *CFE_EVS_ResetDataPtr = NULL;

  MemSet(&CFE_EVS_Global, 0, sizeof(CFE_EVS_Global_t));

  // Initialize housekeeping packet
  CFE_MSG_Init(&CFE_EVS_Global.EVS_TlmPkt.TelemetryHeader.Msg,
               CFE_SB_ValueToMsgId(CFE_EVS_HK_TLM_MID), sizeof(CFE_EVS_HousekeepingTlm_t));

  // Elements stored in the hk packet that have non-zero default values
  CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode = CFE_PLATFORM_EVS_DEFAULT_MSG_FORMAT_MODE;
  CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort = CFE_PLATFORM_EVS_PORT_DEFAULT;
  CFE_EVS_Global.EVS_TlmPkt.Payload.LogMode = CFE_PLATFORM_EVS_DEFAULT_LOG_MODE;

  CFE_EVS_Global.EVS_EventBurstMax = CFE_PLATFORM_EVS_MAX_APP_EVENT_BURST;

  // Get a pointer to the CFE reset area from the BSP
  PspStatus = CFE_PSP_GetResetArea(&resetAreaAddr, &resetAreaSize);

  // Panic on error
  if (PspStatus != CFE_PSP_SUCCESS) {
    // Can't log evs messages without the reset area
    Status = CFE_EVS_RESET_AREA_POINTER;
    CFE_ES_WriteToSysLog("CFE_EVS_EarlyInit: Call to CFE_PSP_GetResetArea failed, RC=0x%08x\n",
                         PspStatus);

    // Delay to allow message to be read
    OS_TaskDelay(CFE_EVS_PANIC_DELAY);

    CFE_PSP_Panic(CFE_PSP_PANIC_MEMORY_ALLOC);
  } else if (resetAreaSize < sizeof(CFE_ES_ResetData_t)) {
    // Got the pointer but the size is wrong
    Status = CFE_EVS_RESET_AREA_POINTER;
    CFE_ES_WriteToSysLog("CFE_EVS_EarlyInit: Unexpected size from CFE_PSP_GetResetArea: expected "
                         "= 0x%08lX, actual = 0x%08lX\n",
                         sizeof(CFE_ES_ResetData_t), resetAreaSize);

    // Delay to allow message to be read
    OS_TaskDelay(CFE_EVS_PANIC_DELAY);

    CFE_PSP_Panic(CFE_PSP_PANIC_MEMORY_ALLOC);
  } else {
    CFE_EVS_ResetDataPtr = resetAreaAddr;
    // Save pointer to the EVS portion of the CFE reset area
    CFE_EVS_Global.EVS_LogPtr = &CFE_EVS_ResetDataPtr->EVS_Log;

    // Create semaphore to serialize access to event log
    OsStatus = OS_MutSemCreate(&CFE_EVS_Global.EVS_SharedDataMutexID, "CFE_EVS_DataMutex", 0);

    if (OsStatus != OS_SUCCESS) {
      CFE_ES_WriteToSysLog("CFE_EVS_EarlyInit: OS_MutSemCreate failed, RC=%ld\n", OsStatus);

      // Delay to allow message to be read
      OS_TaskDelay(CFE_EVS_PANIC_DELAY);

      CFE_PSP_Panic(CFE_PSP_PANIC_STARTUP_SEM);
      Status = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    } else {
      // Convert to CFE success type
      Status = CFE_SUCCESS;
    }

    // Report log as enabled
    CFE_EVS_Global.EVS_TlmPkt.Payload.LogEnabled = TRUE;

    // Clear event log if power-on reset or bad contents
    if (CFE_ES_GetResetType(NULL) == CFE_PSP_RST_TYPE_POWERON) {
      CFE_ES_WriteToSysLog("CFE_EVS_EarlyInit: Event Log cleared following power-on reset\n");
      EVS_ClearLog();
      CFE_EVS_Global.EVS_LogPtr->LogMode = CFE_PLATFORM_EVS_DEFAULT_LOG_MODE;
    } else if (CFE_EVS_Global.EVS_LogPtr->LogMode != CFE_EVS_LogMode_OVERWRITE &&
                   CFE_EVS_Global.EVS_LogPtr->LogMode != CFE_EVS_LogMode_DISCARD ||
               CFE_EVS_Global.EVS_LogPtr->LogFullFlag != FALSE &&
                   CFE_EVS_Global.EVS_LogPtr->LogFullFlag != TRUE ||
               CFE_EVS_Global.EVS_LogPtr->Next >= CFE_PLATFORM_EVS_LOG_MAX) {
      CFE_ES_WriteToSysLog(
          "CFE_EVS_EarlyInit: Event Log cleared, n=%d, c=%d, f=%d, m=%d, o=%d\n",
          CFE_EVS_Global.EVS_LogPtr->Next, CFE_EVS_Global.EVS_LogPtr->LogCount,
          CFE_EVS_Global.EVS_LogPtr->LogFullFlag, CFE_EVS_Global.EVS_LogPtr->LogMode,
          CFE_EVS_Global.EVS_LogPtr->LogOverflowCounter);
      EVS_ClearLog();
      CFE_EVS_Global.EVS_LogPtr->LogMode = CFE_PLATFORM_EVS_DEFAULT_LOG_MODE;
    } else {
      CFE_ES_WriteToSysLog(
          "CFE_EVS_EarlyInit: Event Log restored, n=%d, c=%d, f=%d, m=%d, o=%d\n",
          CFE_EVS_Global.EVS_LogPtr->Next, CFE_EVS_Global.EVS_LogPtr->LogCount,
          CFE_EVS_Global.EVS_LogPtr->LogFullFlag, CFE_EVS_Global.EVS_LogPtr->LogMode,
          CFE_EVS_Global.EVS_LogPtr->LogOverflowCounter);
    }
  }

  return Status;
}

I32 CFE_EVS_CleanUpApp(U32 Id)
{
  I32 Status = CFE_SUCCESS;
  EVS_AppData_t *AppDataPtr;
  U32 AppID;

  AppID = CFE_ResourceId_FromInteger(Id);

  // Query and verify the caller's AppID
  AppDataPtr = EVS_GetAppDataByID(AppID);
  if (AppDataPtr == NULL) {
    Status = CFE_EVS_APP_ILLEGAL_APP_ID;
  } else if (EVS_AppDataIsMatch(AppDataPtr, AppID)) {
    EVS_AppDataSetFree(AppDataPtr);
  }

  return Status;
}

U0 CFE_EVS_TaskMain()
{
  I32 Status;
  CFE_SB_Buffer *SBBufPtr;

  CFE_ES_PerfLogEntry(CFE_MISSION_EVS_MAIN_PERF_ID);

  Status = CFE_EVS_TaskInit();

  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_EVS_TaskMain: Application Init Failed,RC=0x%08X\n", Status);
    CFE_ES_PerfLogExit(CFE_MISSION_EVS_MAIN_PERF_ID);
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

    CFE_ES_PerfLogExit(CFE_MISSION_EVS_MAIN_PERF_ID);

    // Pend on receipt of packet
    Status = CFE_SB_ReceiveBuffer(&SBBufPtr, CFE_EVS_Global.EVS_CommandPipe,
                                  CFE_SB_PEND_FOREVER);

    CFE_ES_PerfLogEntry(CFE_MISSION_EVS_MAIN_PERF_ID);

    if (Status == CFE_SUCCESS) {
      // Process cmd pipe msg
      CFE_EVS_ProcessCommandPacket(SBBufPtr);
    } else {
      CFE_ES_WriteToSysLog("CFE_EVS_TaskMain: Error reading cmd pipe,RC=0x%08X\n", Status);
    }
  }

  // while loop exits only if CFE_SB_ReceiveBuffer returns error
  CFE_ES_ExitApp(CFE_ES_RunStatus_CORE_APP_RUNTIME_ERROR);
}

I32 CFE_EVS_TaskInit()
{
  I32 Status;
  U32 AppID;
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];

  // Query and verify the AppID
  Status = CFE_ES_GetAppID(&AppID);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_EVS_TaskInit: Call to CFE_ES_GetAppID Failed:RC=0x%08X\n", Status);
    return Status;
  }

  // Register EVS task for event services
  Status = CFE_EVS_Register(NULL, 0, CFE_EVS_EventFilter_BINARY);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_EVS_TaskInit: Call to CFE_EVS_Register Failed:RC=0x%08X\n", Status);
    return Status;
  }

  // Create software bus command pipe
  Status = CFE_SB_CreatePipe(&CFE_EVS_Global.EVS_CommandPipe, CFE_EVS_PIPE_DEPTH,
                             CFE_EVS_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_EVS_TaskInit: Call to CFE_SB_CreatePipe Failed:RC=0x%08X\n", Status);
    return Status;
  }

  // Subscribe to command and telemetry requests coming in on the command pipe
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_EVS_CMD_MID), CFE_EVS_Global.EVS_CommandPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_EVS_TaskInit: Subscribing to Cmds Failed:RC=0x%08X\n", Status);
    return Status;
  }

  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_EVS_SEND_HK_MID),
                            CFE_EVS_Global.EVS_CommandPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_EVS_TaskInit: Subscribing to HK Request Failed:RC=0x%08X\n", Status);
    return Status;
  }

  // Write the AppID to the global location, now that the rest of initialization is done
  CFE_EVS_Global.EVS_AppID = AppID;
  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "CFE_EVS",
                              CFE_SRC_VERSION, CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);
  EVS_SendEvent(CFE_EVS_STARTUP_EID, CFE_EVS_EventType_INFORMATION, "cFE EVS Initialized: %s",
                VersionString);

  return CFE_SUCCESS;
}
I32 CFE_EVS_NoopCmd(CFE_EVS_NoopCmd_t *data)
{
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];
  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "CFE_EVS",
                              CFE_SRC_VERSION, CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);
  EVS_SendEvent(CFE_EVS_NOOP_EID, CFE_EVS_EventType_INFORMATION, "No-op Cmd Rcvd: %s",
                VersionString);
  return CFE_SUCCESS;
}

I32 CFE_EVS_ClearLogCmd(CFE_EVS_ClearLogCmd_t *data)
{
  EVS_ClearLog();
  return CFE_SUCCESS;
}

I32 CFE_EVS_SendHkCmd(CFE_EVS_SendHkCmd_t *data)
{
  U32 i, j;
  EVS_AppData_t *AppDataPtr;
  CFE_EVS_AppTlmData_t *AppTlmDataPtr;

  // Copy hk variables that are maintained in the event log
  CFE_EVS_Global.EVS_TlmPkt.Payload.LogFullFlag = CFE_EVS_Global.EVS_LogPtr->LogFullFlag;
  CFE_EVS_Global.EVS_TlmPkt.Payload.LogMode = CFE_EVS_Global.EVS_LogPtr->LogMode;
  CFE_EVS_Global.EVS_TlmPkt.Payload.LogOverflowCounter =
      CFE_EVS_Global.EVS_LogPtr->LogOverflowCounter;

  // Write event state data for registered apps to telemetry packet
  AppDataPtr = CFE_EVS_Global.AppData;
  AppTlmDataPtr = CFE_EVS_Global.EVS_TlmPkt.Payload.AppData;
  i = 0;
  j = 0;
  while (j < CFE_MISSION_ES_MAX_APPLICATIONS && i < CFE_PLATFORM_ES_MAX_APPLICATIONS) {
    if (EVS_AppDataIsUsed(AppDataPtr)) {
      AppTlmDataPtr->AppID = EVS_AppDataGetID(AppDataPtr);
      AppTlmDataPtr->AppEnableStatus = AppDataPtr->ActiveFlag;
      AppTlmDataPtr->AppMessageSentCounter = AppDataPtr->EventCount;
      AppTlmDataPtr->AppMessageSquelchedCounter = AppDataPtr->SquelchedCount;

      ++j;
      ++AppTlmDataPtr;
    }
    ++AppDataPtr;
    i++;
  }

  // Clear unused portion of event state data in telemetry packet
  //
  // UPSTREAM NOTE: this loop does NOT advance AppTlmDataPtr, so it writes the SAME entry
  // CFE_MISSION_ES_MAX_APPLICATIONS - j times and every slot after the first unused one keeps
  // whatever the previous housekeeping cycle left there. Live in a stock build, invisible until
  // an app unregisters. Translated as written -- see docs/CFS_UPSTREAM_NOTES.md #10.
  for (i = j; i < CFE_MISSION_ES_MAX_APPLICATIONS; i++) {
    AppTlmDataPtr->AppID = CFE_ES_APPID_UNDEFINED;
    AppTlmDataPtr->AppEnableStatus = FALSE;
    AppTlmDataPtr->AppMessageSentCounter = 0;
    AppTlmDataPtr->AppMessageSquelchedCounter = 0;
  }

  CFE_SB_TimeStampMsg(&CFE_EVS_Global.EVS_TlmPkt.TelemetryHeader.Msg);

  CFE_SB_TransmitMsg(&CFE_EVS_Global.EVS_TlmPkt.TelemetryHeader.Msg, TRUE);

  return CFE_STATUS_NO_COUNTER_INCREMENT;
}

I32 CFE_EVS_ResetCountersCmd(CFE_EVS_ResetCountersCmd_t *data)
{
  // Status of commands processed by EVS task
  CFE_EVS_Global.EVS_TlmPkt.Payload.CommandCounter = 0;
  CFE_EVS_Global.EVS_TlmPkt.Payload.CommandErrorCounter = 0;

  // EVS telemetry counters
  CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter = 0;
  CFE_EVS_Global.EVS_TlmPkt.Payload.MessageTruncCounter = 0;
  CFE_EVS_Global.EVS_TlmPkt.Payload.UnregisteredAppCounter = 0;

  EVS_SendEvent(CFE_EVS_RSTCNT_EID, CFE_EVS_EventType_DEBUG, "Reset Counters Command Received");

  // NOTE: Historically the reset counters command does _NOT_ increment the command counter

  return CFE_STATUS_NO_COUNTER_INCREMENT;
}

I32 CFE_EVS_SetFilterCmd(CFE_EVS_SetFilterCmd_t *data)
{
  CFE_EVS_AppNameEventIDMaskCmd_Payload_t *CmdPtr = &data->Payload;
  EVS_BinFilter_t *FilterPtr;
  I32 Status;
  EVS_AppData_t *AppDataPtr;
  U8 LocalName[OS_MAX_API_NAME];

  // Copy appname from command, ensures NULL termination
  CFE_SB_MessageStringGet(LocalName, CmdPtr->AppName, NULL, OS_MAX_API_NAME,
                          CFE_MISSION_MAX_API_LEN);

  // Retrieve application data
  Status = EVS_GetApplicationInfo(&AppDataPtr, LocalName);

  if (Status == CFE_SUCCESS) {
    FilterPtr = EVS_FindEventID(CmdPtr->EventID, AppDataPtr->BinFilters);

    if (FilterPtr != NULL) {
      // Set application filter mask
      FilterPtr->Mask = CmdPtr->Mask;

      EVS_SendEvent(CFE_EVS_SETFILTERMSK_EID, CFE_EVS_EventType_DEBUG,
                    "Set Filter Mask Command Received with AppName=%s, EventID=0x%08x, "
                    "Mask=0x%04x",
                    LocalName, CmdPtr->EventID, CmdPtr->Mask);
    } else {
      EVS_SendEvent(CFE_EVS_ERR_EVTIDNOREGS_EID, CFE_EVS_EventType_ERROR,
                    "%s Event ID %d not registered for filtering: CC = %lu ", LocalName,
                    CmdPtr->EventID, CFE_EVS_SET_FILTER_CC);

      Status = CFE_EVS_EVT_NOT_REGISTERED;
    }
  } else if (Status == CFE_EVS_APP_NOT_REGISTERED) {
    EVS_SendEvent(CFE_EVS_ERR_APPNOREGS_EID, CFE_EVS_EventType_ERROR,
                  "%s not registered with EVS: CC = %lu", LocalName, CFE_EVS_SET_FILTER_CC);
  } else if (Status == CFE_EVS_APP_ILLEGAL_APP_ID) {
    EVS_SendEvent(CFE_EVS_ERR_ILLAPPIDRANGE_EID, CFE_EVS_EventType_ERROR,
                  "Illegal application ID retrieved for %s: CC = %lu", LocalName,
                  CFE_EVS_SET_FILTER_CC);
  } else {
    EVS_SendEvent(CFE_EVS_ERR_NOAPPIDFOUND_EID, CFE_EVS_EventType_ERROR,
                  "Unable to retrieve application ID for %s: CC = %lu", LocalName,
                  CFE_EVS_SET_FILTER_CC);
  }

  return Status;
}
I32 CFE_EVS_EnablePortsCmd(CFE_EVS_EnablePortsCmd_t *data)
{
  CFE_EVS_BitMaskCmd_Payload_t *CmdPtr = &data->Payload;
  I32 ReturnCode = CFE_SUCCESS;

  // Need to check for an out of range bitmask, since oue bit masks are only 4 bits
  if (EVS_IsInvalidBitMask(CmdPtr->BitMask, CFE_EVS_ENABLE_PORTS_CC)) {
    ReturnCode = CFE_EVS_INVALID_PARAMETER;
  } else {
    // Process command data
    CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort |= CmdPtr->BitMask;

    EVS_SendEvent(CFE_EVS_ENAPORT_EID, CFE_EVS_EventType_DEBUG,
                  "Enable Ports Command Received with Port Bit Mask = 0x%02x", CmdPtr->BitMask);
  }

  return ReturnCode;
}

I32 CFE_EVS_DisablePortsCmd(CFE_EVS_DisablePortsCmd_t *data)
{
  CFE_EVS_BitMaskCmd_Payload_t *CmdPtr = &data->Payload;
  I32 ReturnCode = CFE_SUCCESS;

  // Need to check for an out of range bitmask, since oue bit masks are only 4 bits
  if (EVS_IsInvalidBitMask(CmdPtr->BitMask, CFE_EVS_DISABLE_PORTS_CC)) {
    ReturnCode = CFE_EVS_INVALID_PARAMETER;
  } else {
    // Process command data
    CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort &= ~CmdPtr->BitMask;

    EVS_SendEvent(CFE_EVS_DISPORT_EID, CFE_EVS_EventType_DEBUG,
                  "Disable Ports Command Received with Port Bit Mask = 0x%02x", CmdPtr->BitMask);
  }

  return ReturnCode;
}

I32 CFE_EVS_EnableEventTypeCmd(CFE_EVS_EnableEventTypeCmd_t *data)
{
  U32 i;
  CFE_EVS_BitMaskCmd_Payload_t *CmdPtr = &data->Payload;
  I32 ReturnCode = CFE_SUCCESS;
  EVS_AppData_t *AppDataPtr;

  // Need to check for an out of range bitmask, since our bit masks are only 4 bits
  if (EVS_IsInvalidBitMask(CmdPtr->BitMask, CFE_EVS_ENABLE_EVENT_TYPE_CC)) {
    ReturnCode = CFE_EVS_INVALID_PARAMETER;
  } else {
    AppDataPtr = CFE_EVS_Global.AppData;
    for (i = 0; i < CFE_PLATFORM_ES_MAX_APPLICATIONS; i++) {
      // Make sure application is registered for event services
      if (EVS_AppDataIsUsed(AppDataPtr)) {
        EVS_SetTypes(AppDataPtr, CmdPtr->BitMask, TRUE);
      }
      ++AppDataPtr;
    }

    EVS_SendEvent(CFE_EVS_ENAEVTTYPE_EID, CFE_EVS_EventType_DEBUG,
                  "Enable Event Type Command Received with Event Type Bit Mask = 0x%02x",
                  CmdPtr->BitMask);
  }

  return ReturnCode;
}

I32 CFE_EVS_DisableEventTypeCmd(CFE_EVS_DisableEventTypeCmd_t *data)
{
  U32 i;
  CFE_EVS_BitMaskCmd_Payload_t *CmdPtr = &data->Payload;
  I32 ReturnCode = CFE_SUCCESS;
  EVS_AppData_t *AppDataPtr;

  // Need to check for an out of range bitmask, since our bit masks are only 4 bits
  if (EVS_IsInvalidBitMask(CmdPtr->BitMask, CFE_EVS_DISABLE_EVENT_TYPE_CC)) {
    ReturnCode = CFE_EVS_INVALID_PARAMETER;
  } else {
    AppDataPtr = CFE_EVS_Global.AppData;
    for (i = 0; i < CFE_PLATFORM_ES_MAX_APPLICATIONS; i++) {
      // Make sure application is registered for event services
      if (EVS_AppDataIsUsed(AppDataPtr)) {
        EVS_SetTypes(AppDataPtr, CmdPtr->BitMask, FALSE);
      }
      ++AppDataPtr;
    }

    EVS_SendEvent(CFE_EVS_DISEVTTYPE_EID, CFE_EVS_EventType_DEBUG,
                  "Disable Event Type Command Received with Event Type Bit Mask = 0x%02x",
                  CmdPtr->BitMask);
  }

  return ReturnCode;
}

I32 CFE_EVS_SetEventFormatModeCmd(CFE_EVS_SetEventFormatModeCmd_t *data)
{
  CFE_EVS_SetEventFormatMode_Payload_t *CmdPtr = &data->Payload;
  I32 Status;

  if (CmdPtr->MsgFormat == CFE_EVS_MsgFormat_SHORT ||
      CmdPtr->MsgFormat == CFE_EVS_MsgFormat_LONG) {
    CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode = CmdPtr->MsgFormat;

    EVS_SendEvent(CFE_EVS_SETEVTFMTMOD_EID, CFE_EVS_EventType_DEBUG,
                  "Set Event Format Mode Command Received with Mode = 0x%02x", CmdPtr->MsgFormat);
    Status = CFE_SUCCESS;
  } else {
    EVS_SendEvent(CFE_EVS_ERR_ILLEGALFMTMOD_EID, CFE_EVS_EventType_ERROR,
                  "Set Event Format Mode Command: Invalid Event Format Mode = 0x%02x",
                  CmdPtr->MsgFormat);
    Status = CFE_EVS_INVALID_PARAMETER;
  }

  return Status;
}
I32 CFE_EVS_EnableAppEventTypeCmd(CFE_EVS_EnableAppEventTypeCmd_t *data)
{
  CFE_EVS_AppNameBitMaskCmd_Payload_t *CmdPtr = &data->Payload;
  EVS_AppData_t *AppDataPtr;
  I32 Status;
  U8 LocalName[OS_MAX_API_NAME];

  // Copy appname from command, ensures NULL termination
  CFE_SB_MessageStringGet(LocalName, CmdPtr->AppName, NULL, OS_MAX_API_NAME,
                          CFE_MISSION_MAX_API_LEN);

  // Retrieve application data
  Status = EVS_GetApplicationInfo(&AppDataPtr, LocalName);

  if (Status == CFE_SUCCESS) {
    // Need to check for an out of range bitmask, since our bit masks are only 4 bits
    if (EVS_IsInvalidBitMask(CmdPtr->BitMask, CFE_EVS_ENABLE_APP_EVENT_TYPE_CC)) {
      Status = CFE_EVS_INVALID_PARAMETER;
    } else {
      EVS_SetTypes(AppDataPtr, CmdPtr->BitMask, TRUE);
    }
  } else if (Status == CFE_EVS_APP_NOT_REGISTERED) {
    EVS_SendEvent(CFE_EVS_ERR_APPNOREGS_EID, CFE_EVS_EventType_ERROR,
                  "%s not registered with EVS: CC = %lu", LocalName,
                  CFE_EVS_ENABLE_APP_EVENT_TYPE_CC);
  } else if (Status == CFE_EVS_APP_ILLEGAL_APP_ID) {
    EVS_SendEvent(CFE_EVS_ERR_ILLAPPIDRANGE_EID, CFE_EVS_EventType_ERROR,
                  "Illegal application ID retrieved for %s: CC = %lu", LocalName,
                  CFE_EVS_ENABLE_APP_EVENT_TYPE_CC);
  } else {
    EVS_SendEvent(CFE_EVS_ERR_NOAPPIDFOUND_EID, CFE_EVS_EventType_ERROR,
                  "Unable to retrieve application ID for %s: CC = %lu", LocalName,
                  CFE_EVS_ENABLE_APP_EVENT_TYPE_CC);
  }

  if (Status == CFE_SUCCESS) {
    EVS_SendEvent(CFE_EVS_ENAAPPEVTTYPE_EID, CFE_EVS_EventType_DEBUG,
                  "Enable App Event Type Command Received with AppName = %s, EventType Bit Mask "
                  "= 0x%02x",
                  LocalName, CmdPtr->BitMask);
  }

  return Status;
}

I32 CFE_EVS_DisableAppEventTypeCmd(CFE_EVS_DisableAppEventTypeCmd_t *data)
{
  EVS_AppData_t *AppDataPtr;
  CFE_EVS_AppNameBitMaskCmd_Payload_t *CmdPtr = &data->Payload;
  I32 Status;
  U8 LocalName[OS_MAX_API_NAME];

  // Copy appname from command, ensures NULL termination
  CFE_SB_MessageStringGet(LocalName, CmdPtr->AppName, NULL, OS_MAX_API_NAME,
                          CFE_MISSION_MAX_API_LEN);

  // Retrieve application data
  Status = EVS_GetApplicationInfo(&AppDataPtr, LocalName);

  if (Status == CFE_SUCCESS) {
    // Need to check for an out of range bitmask, since our bit masks are only 4 bits
    if (EVS_IsInvalidBitMask(CmdPtr->BitMask, CFE_EVS_DISABLE_APP_EVENT_TYPE_CC)) {
      Status = CFE_EVS_INVALID_PARAMETER;
    } else {
      EVS_SetTypes(AppDataPtr, CmdPtr->BitMask, FALSE);
    }
  } else if (Status == CFE_EVS_APP_NOT_REGISTERED) {
    // UPSTREAM NOTE: the stray comma after "EVS" is NASA's, and it is in this handler only --
    // every other copy of this line reads "not registered with EVS: CC". Kept, because the
    // transcript compares the characters.
    EVS_SendEvent(CFE_EVS_ERR_APPNOREGS_EID, CFE_EVS_EventType_ERROR,
                  "%s not registered with EVS,: CC = %lu", LocalName,
                  CFE_EVS_DISABLE_APP_EVENT_TYPE_CC);
  } else if (Status == CFE_EVS_APP_ILLEGAL_APP_ID) {
    EVS_SendEvent(CFE_EVS_ERR_ILLAPPIDRANGE_EID, CFE_EVS_EventType_ERROR,
                  "Illegal application ID retrieved for %s: CC = %lu", LocalName,
                  CFE_EVS_DISABLE_APP_EVENT_TYPE_CC);
  } else {
    EVS_SendEvent(CFE_EVS_ERR_NOAPPIDFOUND_EID, CFE_EVS_EventType_ERROR,
                  "Unable to retrieve application ID for %s: CC = %lu", LocalName,
                  CFE_EVS_DISABLE_APP_EVENT_TYPE_CC);
  }

  if (Status == CFE_SUCCESS) {
    EVS_SendEvent(CFE_EVS_DISAPPENTTYPE_EID, CFE_EVS_EventType_DEBUG,
                  "Disable App Event Type Command Received with AppName = %s, EventType Bit Mask "
                  "= 0x%02x",
                  LocalName, CmdPtr->BitMask);
  }

  return Status;
}

I32 CFE_EVS_EnableAppEventsCmd(CFE_EVS_EnableAppEventsCmd_t *data)
{
  EVS_AppData_t *AppDataPtr;
  CFE_EVS_AppNameCmd_Payload_t *CmdPtr = &data->Payload;
  I32 Status;
  U8 LocalName[OS_MAX_API_NAME];

  // Copy appname from command, ensures NULL termination
  CFE_SB_MessageStringGet(LocalName, CmdPtr->AppName, NULL, OS_MAX_API_NAME,
                          CFE_MISSION_MAX_API_LEN);

  // Retrieve application data
  Status = EVS_GetApplicationInfo(&AppDataPtr, LocalName);

  if (Status == CFE_SUCCESS) {
    AppDataPtr->ActiveFlag = TRUE;

    EVS_SendEvent(CFE_EVS_ENAAPPEVT_EID, CFE_EVS_EventType_DEBUG,
                  "Enable App Events Command Received with AppName = %s", LocalName);
  } else if (Status == CFE_EVS_APP_NOT_REGISTERED) {
    EVS_SendEvent(CFE_EVS_ERR_APPNOREGS_EID, CFE_EVS_EventType_ERROR,
                  "%s not registered with EVS: CC = %lu", LocalName,
                  CFE_EVS_ENABLE_APP_EVENTS_CC);
  } else if (Status == CFE_EVS_APP_ILLEGAL_APP_ID) {
    EVS_SendEvent(CFE_EVS_ERR_ILLAPPIDRANGE_EID, CFE_EVS_EventType_ERROR,
                  "Illegal application ID retrieved for %s: CC = %lu", LocalName,
                  CFE_EVS_ENABLE_APP_EVENTS_CC);
  } else {
    EVS_SendEvent(CFE_EVS_ERR_NOAPPIDFOUND_EID, CFE_EVS_EventType_ERROR,
                  "Unable to retrieve application ID for %s: CC = %lu", LocalName,
                  CFE_EVS_ENABLE_APP_EVENTS_CC);
  }

  return Status;
}

I32 CFE_EVS_DisableAppEventsCmd(CFE_EVS_DisableAppEventsCmd_t *data)
{
  EVS_AppData_t *AppDataPtr;
  CFE_EVS_AppNameCmd_Payload_t *CmdPtr = &data->Payload;
  I32 Status;
  U8 LocalName[OS_MAX_API_NAME];

  // Copy appname from command, ensures NULL termination
  CFE_SB_MessageStringGet(LocalName, CmdPtr->AppName, NULL, OS_MAX_API_NAME,
                          CFE_MISSION_MAX_API_LEN);

  // Retrieve application data
  Status = EVS_GetApplicationInfo(&AppDataPtr, LocalName);

  if (Status == CFE_SUCCESS) {
    AppDataPtr->ActiveFlag = FALSE;

    EVS_SendEvent(CFE_EVS_DISAPPEVT_EID, CFE_EVS_EventType_DEBUG,
                  "Disable App Events Command Received with AppName = %s", LocalName);
  } else if (Status == CFE_EVS_APP_NOT_REGISTERED) {
    EVS_SendEvent(CFE_EVS_ERR_APPNOREGS_EID, CFE_EVS_EventType_ERROR,
                  "%s not registered with EVS: CC = %lu", LocalName,
                  CFE_EVS_DISABLE_APP_EVENTS_CC);
  } else if (Status == CFE_EVS_APP_ILLEGAL_APP_ID) {
    EVS_SendEvent(CFE_EVS_ERR_ILLAPPIDRANGE_EID, CFE_EVS_EventType_ERROR,
                  "Illegal application ID retrieved for %s: CC = %lu", LocalName,
                  CFE_EVS_DISABLE_APP_EVENTS_CC);
  } else {
    // NASA prefixes this one with the command name and the other three do not.
    EVS_SendEvent(CFE_EVS_ERR_NOAPPIDFOUND_EID, CFE_EVS_EventType_ERROR,
                  "Disable App Events Command: Unable to retrieve application ID for %s: CC = %lu",
                  LocalName, CFE_EVS_DISABLE_APP_EVENTS_CC);
  }

  return Status;
}
I32 CFE_EVS_ResetAppCounterCmd(CFE_EVS_ResetAppCounterCmd_t *data)
{
  EVS_AppData_t *AppDataPtr;
  CFE_EVS_AppNameCmd_Payload_t *CmdPtr = &data->Payload;
  I32 Status;
  U8 LocalName[OS_MAX_API_NAME];

  // Copy appname from command, ensures NULL termination
  CFE_SB_MessageStringGet(LocalName, CmdPtr->AppName, NULL, OS_MAX_API_NAME,
                          CFE_MISSION_MAX_API_LEN);

  // Retrieve application data
  Status = EVS_GetApplicationInfo(&AppDataPtr, LocalName);

  if (Status == CFE_SUCCESS) {
    AppDataPtr->EventCount = 0;
    AppDataPtr->SquelchedCount = 0;

    EVS_SendEvent(CFE_EVS_RSTEVTCNT_EID, CFE_EVS_EventType_DEBUG,
                  "Reset Event Counter Command Received with AppName = %s", LocalName);
  } else if (Status == CFE_EVS_APP_NOT_REGISTERED) {
    EVS_SendEvent(CFE_EVS_ERR_APPNOREGS_EID, CFE_EVS_EventType_ERROR,
                  "%s not registered with EVS: CC = %lu", LocalName,
                  CFE_EVS_RESET_APP_COUNTER_CC);
  } else if (Status == CFE_EVS_APP_ILLEGAL_APP_ID) {
    EVS_SendEvent(CFE_EVS_ERR_ILLAPPIDRANGE_EID, CFE_EVS_EventType_ERROR,
                  "Illegal application ID retrieved for %s: CC = %lu", LocalName,
                  CFE_EVS_RESET_APP_COUNTER_CC);
  } else {
    EVS_SendEvent(CFE_EVS_ERR_NOAPPIDFOUND_EID, CFE_EVS_EventType_ERROR,
                  "Reset Event Counter Command: Unable to retrieve application ID for %s: CC = "
                  "%lu",
                  LocalName, CFE_EVS_RESET_APP_COUNTER_CC);
  }

  return Status;
}

I32 CFE_EVS_ResetFilterCmd(CFE_EVS_ResetFilterCmd_t *data)
{
  CFE_EVS_AppNameEventIDCmd_Payload_t *CmdPtr = &data->Payload;
  EVS_BinFilter_t *FilterPtr;
  I32 Status;
  EVS_AppData_t *AppDataPtr;
  U8 LocalName[OS_MAX_API_NAME];

  // Copy appname from command, ensures NULL termination
  CFE_SB_MessageStringGet(LocalName, CmdPtr->AppName, NULL, OS_MAX_API_NAME,
                          CFE_MISSION_MAX_API_LEN);

  // Retrieve application data
  Status = EVS_GetApplicationInfo(&AppDataPtr, LocalName);

  if (Status == CFE_SUCCESS) {
    FilterPtr = EVS_FindEventID(CmdPtr->EventID, AppDataPtr->BinFilters);

    if (FilterPtr != NULL) {
      FilterPtr->Count = 0;

      EVS_SendEvent(CFE_EVS_RSTFILTER_EID, CFE_EVS_EventType_DEBUG,
                    "Reset Filter Command Received with AppName = %s, EventID = 0x%08x",
                    LocalName, CmdPtr->EventID);
    } else {
      // No trailing space here; CFE_EVS_SetFilterCmd's copy of this line has one.
      EVS_SendEvent(CFE_EVS_ERR_EVTIDNOREGS_EID, CFE_EVS_EventType_ERROR,
                    "%s Event ID %d not registered for filtering: CC = %lu", LocalName,
                    CmdPtr->EventID, CFE_EVS_RESET_FILTER_CC);

      Status = CFE_EVS_EVT_NOT_REGISTERED;
    }
  } else if (Status == CFE_EVS_APP_NOT_REGISTERED) {
    EVS_SendEvent(CFE_EVS_ERR_APPNOREGS_EID, CFE_EVS_EventType_ERROR,
                  "%s not registered with EVS: CC = %lu", LocalName, CFE_EVS_RESET_FILTER_CC);
  } else if (Status == CFE_EVS_APP_ILLEGAL_APP_ID) {
    EVS_SendEvent(CFE_EVS_ERR_ILLAPPIDRANGE_EID, CFE_EVS_EventType_ERROR,
                  "Illegal application ID retrieved for %s: CC = %lu", LocalName,
                  CFE_EVS_RESET_FILTER_CC);
  } else {
    EVS_SendEvent(CFE_EVS_ERR_NOAPPIDFOUND_EID, CFE_EVS_EventType_ERROR,
                  "Unable to retrieve application ID for %s: CC = %lu", LocalName,
                  CFE_EVS_RESET_FILTER_CC);
  }

  return Status;
}

I32 CFE_EVS_ResetAllFiltersCmd(CFE_EVS_ResetAllFiltersCmd_t *data)
{
  EVS_AppData_t *AppDataPtr;
  CFE_EVS_AppNameCmd_Payload_t *CmdPtr = &data->Payload;
  I32 Status;
  U32 i;
  U8 LocalName[OS_MAX_API_NAME];

  // Copy appname from command, ensures NULL termination
  CFE_SB_MessageStringGet(LocalName, CmdPtr->AppName, NULL, OS_MAX_API_NAME,
                          CFE_MISSION_MAX_API_LEN);

  // Retrieve application data
  Status = EVS_GetApplicationInfo(&AppDataPtr, LocalName);

  if (Status == CFE_SUCCESS) {
    for (i = 0; i < CFE_PLATFORM_EVS_MAX_EVENT_FILTERS; i++) {
      AppDataPtr->BinFilters[i].Count = 0;
    }

    EVS_SendEvent(CFE_EVS_RSTALLFILTER_EID, CFE_EVS_EventType_DEBUG,
                  "Reset All Filters Command Received with AppName = %s", LocalName);
  } else if (Status == CFE_EVS_APP_NOT_REGISTERED) {
    EVS_SendEvent(CFE_EVS_ERR_APPNOREGS_EID, CFE_EVS_EventType_ERROR,
                  "%s not registered with EVS: CC = %lu", LocalName,
                  CFE_EVS_RESET_ALL_FILTERS_CC);
  } else if (Status == CFE_EVS_APP_ILLEGAL_APP_ID) {
    EVS_SendEvent(CFE_EVS_ERR_ILLAPPIDRANGE_EID, CFE_EVS_EventType_ERROR,
                  "Illegal application ID retrieved for %s: CC = %lu", LocalName,
                  CFE_EVS_RESET_ALL_FILTERS_CC);
  } else {
    EVS_SendEvent(CFE_EVS_ERR_NOAPPIDFOUND_EID, CFE_EVS_EventType_ERROR,
                  "Unable to retrieve application ID for %s: CC = %lu", LocalName,
                  CFE_EVS_RESET_ALL_FILTERS_CC);
  }

  return Status;
}
I32 CFE_EVS_AddEventFilterCmd(CFE_EVS_AddEventFilterCmd_t *data)
{
  CFE_EVS_AppNameEventIDMaskCmd_Payload_t *CmdPtr = &data->Payload;
  EVS_BinFilter_t *FilterPtr;
  I32 Status;
  EVS_AppData_t *AppDataPtr;
  U8 LocalName[OS_MAX_API_NAME];

  // Copy appname from command, ensures NULL termination
  CFE_SB_MessageStringGet(LocalName, CmdPtr->AppName, NULL, OS_MAX_API_NAME,
                          CFE_MISSION_MAX_API_LEN);

  // Retrieve application data
  Status = EVS_GetApplicationInfo(&AppDataPtr, LocalName);

  if (Status == CFE_SUCCESS) {
    // Check to see if this event is already registered for filtering
    FilterPtr = EVS_FindEventID(CmdPtr->EventID, AppDataPtr->BinFilters);

    // FilterPtr != NULL means that this Event ID was found as already being registered
    if (FilterPtr != NULL) {
      EVS_SendEvent(CFE_EVS_EVT_FILTERED_EID, CFE_EVS_EventType_ERROR,
                    "Add Filter Command:AppName = %s, EventID = 0x%08x is already registered for "
                    "filtering",
                    LocalName, CmdPtr->EventID);

      Status = CFE_EVS_EVT_NOT_REGISTERED;
    } else {
      // now check to see if there is a free slot
      FilterPtr = EVS_FindEventID(CFE_EVS_FREE_SLOT, AppDataPtr->BinFilters);

      if (FilterPtr != NULL) {
        // Add Filter Contents
        FilterPtr->EventID = CmdPtr->EventID;
        FilterPtr->Mask = CmdPtr->Mask;
        FilterPtr->Count = 0;

        EVS_SendEvent(CFE_EVS_ADDFILTER_EID, CFE_EVS_EventType_DEBUG,
                      "Add Filter Command Received with AppName = %s, EventID = 0x%08x, Mask = "
                      "0x%04x",
                      LocalName, CmdPtr->EventID, CmdPtr->Mask);
      } else {
        EVS_SendEvent(CFE_EVS_ERR_MAXREGSFILTER_EID, CFE_EVS_EventType_ERROR,
                      "Add Filter Command: number of registered filters has reached max = %d",
                      CFE_PLATFORM_EVS_MAX_EVENT_FILTERS);

        Status = CFE_EVS_APP_FILTER_OVERLOAD;
      }
    }
  } else if (Status == CFE_EVS_APP_NOT_REGISTERED) {
    EVS_SendEvent(CFE_EVS_ERR_APPNOREGS_EID, CFE_EVS_EventType_ERROR,
                  "%s not registered with EVS: CC = %lu", LocalName,
                  CFE_EVS_ADD_EVENT_FILTER_CC);
  } else if (Status == CFE_EVS_APP_ILLEGAL_APP_ID) {
    EVS_SendEvent(CFE_EVS_ERR_ILLAPPIDRANGE_EID, CFE_EVS_EventType_ERROR,
                  "Illegal application ID retrieved for %s: CC = %lu", LocalName,
                  CFE_EVS_ADD_EVENT_FILTER_CC);
  } else {
    EVS_SendEvent(CFE_EVS_ERR_NOAPPIDFOUND_EID, CFE_EVS_EventType_ERROR,
                  "Unable to retrieve application ID for %s: CC = %lu", LocalName,
                  CFE_EVS_ADD_EVENT_FILTER_CC);
  }

  return Status;
}

I32 CFE_EVS_DeleteEventFilterCmd(CFE_EVS_DeleteEventFilterCmd_t *data)
{
  CFE_EVS_AppNameEventIDCmd_Payload_t *CmdPtr = &data->Payload;
  EVS_BinFilter_t *FilterPtr;
  I32 Status;
  EVS_AppData_t *AppDataPtr;
  U8 LocalName[OS_MAX_API_NAME];

  // Copy appname from command, ensures NULL termination
  CFE_SB_MessageStringGet(LocalName, CmdPtr->AppName, NULL, OS_MAX_API_NAME,
                          CFE_MISSION_MAX_API_LEN);

  // Retrieve application data
  Status = EVS_GetApplicationInfo(&AppDataPtr, LocalName);

  if (Status == CFE_SUCCESS) {
    FilterPtr = EVS_FindEventID(CmdPtr->EventID, AppDataPtr->BinFilters);

    if (FilterPtr != NULL) {
      // Clear Filter Contents
      FilterPtr->EventID = CFE_EVS_FREE_SLOT;
      FilterPtr->Mask = CFE_EVS_NO_MASK;
      FilterPtr->Count = 0;

      EVS_SendEvent(CFE_EVS_DELFILTER_EID, CFE_EVS_EventType_DEBUG,
                    "Delete Filter Command Received with AppName = %s, EventID = 0x%08x",
                    LocalName, CmdPtr->EventID);
    } else {
      EVS_SendEvent(CFE_EVS_ERR_EVTIDNOREGS_EID, CFE_EVS_EventType_ERROR,
                    "%s Event ID %d not registered for filtering: CC = %lu", LocalName,
                    CmdPtr->EventID, CFE_EVS_DELETE_EVENT_FILTER_CC);
      Status = CFE_EVS_EVT_NOT_REGISTERED;
    }
  } else if (Status == CFE_EVS_APP_NOT_REGISTERED) {
    EVS_SendEvent(CFE_EVS_ERR_APPNOREGS_EID, CFE_EVS_EventType_ERROR,
                  "%s not registered with EVS: CC = %lu", LocalName,
                  CFE_EVS_DELETE_EVENT_FILTER_CC);
  } else if (Status == CFE_EVS_APP_ILLEGAL_APP_ID) {
    EVS_SendEvent(CFE_EVS_ERR_ILLAPPIDRANGE_EID, CFE_EVS_EventType_ERROR,
                  "Illegal application ID retrieved for %s: CC = %lu", LocalName,
                  CFE_EVS_DELETE_EVENT_FILTER_CC);
  } else {
    EVS_SendEvent(CFE_EVS_ERR_NOAPPIDFOUND_EID, CFE_EVS_EventType_ERROR,
                  "Unable to retrieve application ID for %s: CC = %lu", LocalName,
                  CFE_EVS_DELETE_EVENT_FILTER_CC);
  }

  return Status;
}
I32 CFE_EVS_WriteAppDataFileCmd(CFE_EVS_WriteAppDataFileCmd_t *data)
{
  I32 Result;
  U32 FileHandle = OS_OBJECT_ID_UNDEFINED;
  I32 OsStatus;
  I32 BytesWritten;
  U32 EntryCount = 0;
  U32 i;
  CFE_FS_Header_t FileHdr;
  EVS_AppData_t *AppDataPtr;
  CFE_EVS_AppDataCmd_Payload_t *CmdPtr = &data->Payload;
  U8 LocalName[OS_MAX_PATH_LEN];

  // Copy the commanded filename into local buffer to ensure size limitation and to allow for
  // modification
  Result = CFE_FS_ParseInputFileNameEx(LocalName, CmdPtr->AppDataFilename, OS_MAX_PATH_LEN,
                                       CFE_MISSION_MAX_PATH_LEN,
                                       CFE_PLATFORM_EVS_DEFAULT_APP_DATA_FILE,
                                       CFE_FS_GetDefaultMountPoint(
                                           CFE_FS_FileCategory_BINARY_DATA_DUMP),
                                       CFE_FS_GetDefaultExtension(
                                           CFE_FS_FileCategory_BINARY_DATA_DUMP));

  if (Result != CFE_SUCCESS) {
    EVS_SendEvent(CFE_EVS_ERR_CRDATFILE_EID, CFE_EVS_EventType_ERROR,
                  "Write App Data Command Error: CFE_FS_ParseInputFileNameEx() = 0x%08X", Result);
  } else {
    // Create Application Data File
    OsStatus = OS_OpenCreate(&FileHandle, LocalName,
                             OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE, OS_WRITE_ONLY);

    if (OsStatus != OS_SUCCESS) {
      EVS_SendEvent(CFE_EVS_ERR_CRDATFILE_EID, CFE_EVS_EventType_ERROR,
                    "Write App Data Command Error: OS_OpenCreate = %ld, filename = %s", OsStatus,
                    LocalName);
      Result = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }
  }

  // UPSTREAM NOTE: a cFE status compared against OS_SUCCESS, the same slip cfe_evs_log.HC
  // records at the same point in the sibling command. Both are 0, so it is right by coincidence
  // of value rather than by type. docs/CFS_UPSTREAM_NOTES.md #9.
  if (Result == OS_SUCCESS) {
    // Result will be overridden if everything works
    Result = CFE_EVS_FILE_WRITE_ERROR;

    // Initialize cFE file header
    CFE_FS_InitHeader(&FileHdr, "EVS Application Data File", CFE_FS_SubType_EVS_APPDATA);

    // Write cFE file header to the App File
    BytesWritten = CFE_FS_WriteHeader(FileHandle, &FileHdr);

    if (BytesWritten == sizeof(CFE_FS_Header_t)) {
      AppDataPtr = CFE_EVS_Global.AppData;
      for (i = 0; i < CFE_PLATFORM_ES_MAX_APPLICATIONS; i++) {
        // Only have data for apps that are registered
        if (EVS_AppDataIsUsed(AppDataPtr)) {
          // Clear application file data record
          MemSet(&AppDataFile, 0, sizeof(CFE_EVS_AppDataFile_t));

          // Copy application data to application file data record
          CFE_ES_GetAppName(AppDataFile.AppName, EVS_AppDataGetID(AppDataPtr), OS_MAX_API_NAME);
          AppDataFile.ActiveFlag = AppDataPtr->ActiveFlag;
          AppDataFile.EventCount = AppDataPtr->EventCount;
          AppDataFile.EventTypesActiveFlag = EVS_EventArrayToBitMask(AppDataPtr);
          AppDataFile.SquelchedCount = AppDataPtr->SquelchedCount;

          // Copy application filter data to application file data record
          MemCpy(AppDataFile.Filters, AppDataPtr->BinFilters,
                 CFE_PLATFORM_EVS_MAX_EVENT_FILTERS * sizeof(EVS_BinFilter_t));

          // Write application data record to file
          OsStatus = OS_write(FileHandle, &AppDataFile, sizeof(CFE_EVS_AppDataFile_t));

          if (OsStatus == sizeof(CFE_EVS_AppDataFile_t)) {
            EntryCount++;
          } else {
            EVS_SendEvent(CFE_EVS_ERR_WRDATFILE_EID, CFE_EVS_EventType_ERROR,
                          "Write App Data Command Error: At entry = %d, OS_write = %ld, filename "
                          "= %s",
                          EntryCount, OsStatus, LocalName);
            break;
          }
        }
        ++AppDataPtr;
      }

      // Process command handler success result
      if (i == CFE_PLATFORM_ES_MAX_APPLICATIONS) {
        EVS_SendEvent(CFE_EVS_WRDAT_EID, CFE_EVS_EventType_DEBUG,
                      "Write App Data Command: %d application data entries written to %s",
                      EntryCount, LocalName);
        Result = CFE_SUCCESS;
      }
    }

    OS_close(FileHandle);
  }

  return Result;
}

I64 CFE_EVS_EventTypeToArrayIndex(U16 EventType)
{
  return EventType - 1;
}

U0 CFE_EVS_SetTypeEnable(U16 EventType, Bool State)
{
  U32 AppId;
  EVS_AppData_t *AppDataPtr;
  I64 Index;

  // Get App ID
  CFE_ES_GetAppID(&AppId);

  // Use App ID to get AppDataPtr
  AppDataPtr = EVS_GetAppDataByID(AppId);

  // Convert to an array index
  Index = CFE_EVS_EventTypeToArrayIndex(EventType);

  // Bounds and null check. NASA writes sizeof(AppDataPtr->EventTypesActive); a `sizeof` of a
  // member reached through a pointer does not parse in HolyC (HOLYC_STRUCT_LIMITS.md #9), so the
  // bound is named. The array is Bool[CFE_EVS_NUM_EVENT_TYPES] and a Bool is one byte, so the
  // count and the size are the same number -- check_padding keeps them that way.
  if (AppDataPtr != NULL && Index < CFE_EVS_NUM_EVENT_TYPES) {
    // Reset event squelch counter
    AppDataPtr->SquelchTokens = CFE_PLATFORM_EVS_MAX_APP_EVENT_BURST * 1000;
    AppDataPtr->EventTypesActive[Index] = State;
  }
}

Bool CFE_EVS_GetTypeEnable(U16 EventType)
{
  U32 AppId;
  EVS_AppData_t *AppDataPtr;
  I64 Index;

  // Get App ID
  CFE_ES_GetAppID(&AppId);

  // Use App ID to get AppDataPtr
  AppDataPtr = EVS_GetAppDataByID(AppId);

  // Convert to an array index
  Index = CFE_EVS_EventTypeToArrayIndex(EventType);

  // Bounds and null check -- see the note in CFE_EVS_SetTypeEnable about the named bound
  if (AppDataPtr != NULL && Index < CFE_EVS_NUM_EVENT_TYPES) {
    return AppDataPtr->EventTypesActive[Index];
  }

  return FALSE;
}
#endif
