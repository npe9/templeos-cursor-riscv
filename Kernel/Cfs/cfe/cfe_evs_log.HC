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

// 1:1 HolyC translation of cFE modules/evs/fsw/src/cfe_evs_log.c -- the LOCAL EVENT LOG, a
// ring of the last 20 event packets that lives in ES's reset area and therefore survives a
// processor reset. EVS holds only a pointer to it.
//
// INCLUDE cfe_evs_global.HC and cfe_evs_utils.HC FIRST: this file calls EVS_SendEvent and the
// fs module's file API.
#ifndef CFE_EVS_LOG_HC
#define CFE_EVS_LOG_HC
// The fs module's file API and OSAL's handles. In a built port both are translated; cfe_fs_*.HC
// is included before this file, and the driver supplies the OSAL half.
#ifndef OS_OBJECT_ID_UNDEFINED
#define OS_OBJECT_ID_UNDEFINED 0
#endif
// The command payloads this file's two command handlers take. From
// modules/evs/config/default_cfe_evs_msgdefs.h and _msgstruct.h.
class CFE_EVS_LogFileCmd_Payload_t
{
  U8 LogFilename[CFE_MISSION_MAX_PATH_LEN]; // Filename where log data is to be written
};

class CFE_EVS_SetLogMode_Payload_t
{
  U16 LogMode; // CFE_EVS_LogMode_Enum_t -- a uint16 typedef, not a C enum
  U8 Spare;    // Pad to even byte
};

class CFE_EVS_WriteLogDataFileCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_LogFileCmd_Payload_t Payload;
};

class CFE_EVS_SetLogModeCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_EVS_SetLogMode_Payload_t Payload;
};

U0 EVS_AddLog(CFE_EVS_LongEventTlm_t *EVS_PktPtr)
{
  // Serialize access to event log control variables
  OS_MutSemTake(CFE_EVS_Global.EVS_SharedDataMutexID);

  if (CFE_EVS_Global.EVS_LogPtr->LogFullFlag == TRUE)
    CFE_EVS_Global.EVS_LogPtr->LogOverflowCounter++;

  // If the log is not full, _or_ if it is in OVERWRITE mode, add the event to the log
  if (CFE_EVS_Global.EVS_LogPtr->LogFullFlag == FALSE ||
      CFE_EVS_Global.EVS_LogPtr->LogMode == CFE_EVS_LogMode_OVERWRITE) {
    // Copy the event data to the next available entry in the log.
    // NASA writes sizeof(*EVS_PktPtr); `sizeof` of a dereference does not parse in HolyC
    // (HOLYC_STRUCT_LIMITS.md #9), so the type is named. check_padding keeps it the same size.
    MemCpy(&CFE_EVS_Global.EVS_LogPtr->LogEntry[CFE_EVS_Global.EVS_LogPtr->Next], EVS_PktPtr,
           sizeof(CFE_EVS_LongEventTlm_t));

    CFE_EVS_Global.EVS_LogPtr->Next++;

    if (CFE_EVS_Global.EVS_LogPtr->Next >= CFE_PLATFORM_EVS_LOG_MAX) {
      // This is important, even if we are in discard mode
      CFE_EVS_Global.EVS_LogPtr->Next = 0;
    }

    // Log count cannot exceed the number of entries in the log
    if (CFE_EVS_Global.EVS_LogPtr->LogCount < CFE_PLATFORM_EVS_LOG_MAX) {
      CFE_EVS_Global.EVS_LogPtr->LogCount++;

      if (CFE_EVS_Global.EVS_LogPtr->LogCount == CFE_PLATFORM_EVS_LOG_MAX) {
        // The full flag and log count are somewhat redundant
        CFE_EVS_Global.EVS_LogPtr->LogFullFlag = TRUE;
      }
    }
  }

  OS_MutSemGive(CFE_EVS_Global.EVS_SharedDataMutexID);
}

U0 EVS_ClearLog()
{
  // Serialize access to event log control variables
  OS_MutSemTake(CFE_EVS_Global.EVS_SharedDataMutexID);

  // Clears everything but LogMode (overwrite vs discard)
  CFE_EVS_Global.EVS_LogPtr->Next = 0;
  CFE_EVS_Global.EVS_LogPtr->LogCount = 0;
  CFE_EVS_Global.EVS_LogPtr->LogFullFlag = FALSE;
  CFE_EVS_Global.EVS_LogPtr->LogOverflowCounter = 0;

  MemSet(CFE_EVS_Global.EVS_LogPtr->LogEntry, 0,
         sizeof(CFE_EVS_LongEventTlm_t) * CFE_PLATFORM_EVS_LOG_MAX);

  OS_MutSemGive(CFE_EVS_Global.EVS_SharedDataMutexID);
}

I32 CFE_EVS_WriteLogDataFileCmd(CFE_EVS_WriteLogDataFileCmd_t *data)
{
  CFE_EVS_LogFileCmd_Payload_t *CmdPtr = &data->Payload;
  I32 Result;
  I32 LogIndex;
  I32 OsStatus;
  I32 BytesWritten;
  U32 LogFileHandle = OS_OBJECT_ID_UNDEFINED;
  U32 i;
  CFE_FS_Header_t LogFileHdr;
  U8 LogFilename[OS_MAX_PATH_LEN];

  // Copy the filename into local buffer with default name/path/extension if not specified
  Result = CFE_FS_ParseInputFileNameEx(LogFilename, CmdPtr->LogFilename, OS_MAX_PATH_LEN,
                                       CFE_MISSION_MAX_PATH_LEN,
                                       CFE_PLATFORM_EVS_DEFAULT_LOG_FILE,
                                       CFE_FS_GetDefaultMountPoint(
                                           CFE_FS_FileCategory_BINARY_DATA_DUMP),
                                       CFE_FS_GetDefaultExtension(
                                           CFE_FS_FileCategory_BINARY_DATA_DUMP));

  if (Result != CFE_SUCCESS) {
    EVS_SendEvent(CFE_EVS_ERR_CRLOGFILE_EID, CFE_EVS_EventType_ERROR,
                  "Write Log File Command Error: CFE_FS_ParseInputFileNameEx() = 0x%08X", Result);
  } else {
    // Create the log file
    OsStatus = OS_OpenCreate(&LogFileHandle, LogFilename,
                             OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE, OS_WRITE_ONLY);
    if (OsStatus != OS_SUCCESS) {
      EVS_SendEvent(CFE_EVS_ERR_CRLOGFILE_EID, CFE_EVS_EventType_ERROR,
                    "Write Log File Command Error: OS_OpenCreate = %ld, filename = %s", OsStatus,
                    LogFilename);
      Result = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }
  }

  // UPSTREAM NOTE: the guard compares a CFE status against OS_SUCCESS. Both are 0, so it is
  // correct by coincidence rather than by type, and it is the only place in EVS that mixes the
  // two namespaces. Translated as written -- see docs/CFS_UPSTREAM_NOTES.md.
  if (Result == OS_SUCCESS) {
    // Result will be overridden if everything works
    Result = CFE_EVS_FILE_WRITE_ERROR;

    // Initialize cFE file header for an event log file
    CFE_FS_InitHeader(&LogFileHdr, "cFE EVS Log File", CFE_FS_SubType_EVS_EVENTLOG);

    // Write the file header to the log file
    BytesWritten = CFE_FS_WriteHeader(LogFileHandle, &LogFileHdr);

    if (BytesWritten == sizeof(CFE_FS_Header_t)) {
      // Serialize access to event log control variables
      OS_MutSemTake(CFE_EVS_Global.EVS_SharedDataMutexID);

      // Is the log full? -- Doesn't matter if wrap mode is enabled
      if (CFE_EVS_Global.EVS_LogPtr->LogCount == CFE_PLATFORM_EVS_LOG_MAX) {
        // Start with log entry that will be overwritten next (oldest)
        LogIndex = CFE_EVS_Global.EVS_LogPtr->Next;
      } else {
        // Start with the first entry in the log (oldest)
        LogIndex = 0;
      }

      // Write all the "in-use" event log entries to the file
      for (i = 0; i < CFE_EVS_Global.EVS_LogPtr->LogCount; i++) {
        OsStatus = OS_write(LogFileHandle, &CFE_EVS_Global.EVS_LogPtr->LogEntry[LogIndex],
                            sizeof(CFE_EVS_LongEventTlm_t));

        if (OsStatus == sizeof(CFE_EVS_LongEventTlm_t)) {
          LogIndex++;

          if (LogIndex >= CFE_PLATFORM_EVS_LOG_MAX)
            LogIndex = 0;
        } else {
          break;
        }
      }

      OS_MutSemGive(CFE_EVS_Global.EVS_SharedDataMutexID);

      // Process command handler success result
      if (i == CFE_EVS_Global.EVS_LogPtr->LogCount) {
        EVS_SendEvent(CFE_EVS_WRLOG_EID, CFE_EVS_EventType_DEBUG,
                      "Write Log File Command: %d event log entries written to %s",
                      CFE_EVS_Global.EVS_LogPtr->LogCount, LogFilename);
        Result = CFE_SUCCESS;
      } else {
        EVS_SendEvent(CFE_EVS_ERR_WRLOGFILE_EID, CFE_EVS_EventType_ERROR,
                      "Write Log File Command Error: OS_write = %ld, filename = %s", OsStatus,
                      LogFilename);
      }
    } else {
      EVS_SendEvent(CFE_EVS_WRITE_HEADER_ERR_EID, CFE_EVS_EventType_ERROR,
                    "Write File Header to Log File Error: WriteHdr RC: %d, Expected: %d, "
                    "filename = %s",
                    BytesWritten, sizeof(CFE_FS_Header_t), LogFilename);
    }

    OS_close(LogFileHandle);
  }

  return Result;
}

I32 CFE_EVS_SetLogModeCmd(CFE_EVS_SetLogModeCmd_t *data)
{
  CFE_EVS_SetLogMode_Payload_t *CmdPtr = &data->Payload;
  I32 Status;

  if (CmdPtr->LogMode == CFE_EVS_LogMode_OVERWRITE || CmdPtr->LogMode == CFE_EVS_LogMode_DISCARD) {
    // Serialize access to event log control variables
    OS_MutSemTake(CFE_EVS_Global.EVS_SharedDataMutexID);
    CFE_EVS_Global.EVS_LogPtr->LogMode = CmdPtr->LogMode;
    OS_MutSemGive(CFE_EVS_Global.EVS_SharedDataMutexID);

    EVS_SendEvent(CFE_EVS_LOGMODE_EID, CFE_EVS_EventType_DEBUG,
                  "Set Log Mode Command: Log Mode = %d", CmdPtr->LogMode);

    Status = CFE_SUCCESS;
  } else {
    Status = CFE_EVS_INVALID_PARAMETER;
    EVS_SendEvent(CFE_EVS_ERR_LOGMODE_EID, CFE_EVS_EventType_ERROR,
                  "Set Log Mode Command Error: Log Mode = %d", CmdPtr->LogMode);
  }

  return Status;
}
#endif
