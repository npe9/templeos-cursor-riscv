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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_dispatch.c -- THE COMMAND DISPATCHER,
// non-EDS variant.
//
// Three functions and a twenty-four-way switch. This is the file CMakeLists picks when EDS is
// off, which is this configuration; cfe_es_eds_dispatch.c is the alternative and
// check_manifest reports both.
//
// IT IS WHERE EVERY GROUND COMMAND'S LENGTH IS CHECKED, once, in one place: a handler never
// sees a message of the wrong size. That is why CFE_ES_VerifyCmdLength bumps the error counter
// itself -- the handler it guards is not called, so nothing else would.
//
// AND IT IS WHY cfe_es_msg.HC's TWENTY-TWO TYPES EXIST AS SEPARATE CLASSES. The six
// no-argument commands are identical in layout, and NASA still gives each its own name
// precisely so this switch can name the right one per case; check_padding measures all of them
// against NASA's compiler, which is what makes a sizeof here trustworthy.
//
// THIS FILE INCLUDES NOTHING. docs/HOLYC_STRUCT_LIMITS.md #13.
//
// REQUIRED INCLUDE ORDER, which the driver provides:
//     cfe_es_msg.HC    the twenty-two command formats whose sizeof this switch takes
//     cfe_es_perf.HC   the four perf command handlers
//     cfe_es_task.HC   the other twenty, and CFE_ES_SendHkCmd
#ifndef CFE_ES_DISPATCH_HC
#define CFE_ES_DISPATCH_HC
// --- cfe_es_fcncodes.h: the twenty-four ground command codes --------------------------------
// NOTE THEY ARE NOT CONTIGUOUS IN COMMAND ORDER: QUERY_ALL_TASKS is 24 and
// OVER_WRITE_SYS_LOG is 18, because codes are assigned when a command is ADDED and never
// renumbered -- a ground system built against an older cFE keeps working. check_constants.py
// compares every one against NASA's header.
#define CFE_ES_NOOP_CC                  0
#define CFE_ES_RESET_COUNTERS_CC        1
#define CFE_ES_RESTART_CC               2
#define CFE_ES_START_APP_CC             4
#define CFE_ES_STOP_APP_CC              5
#define CFE_ES_RESTART_APP_CC           6
#define CFE_ES_RELOAD_APP_CC            7
#define CFE_ES_QUERY_ONE_CC             8
#define CFE_ES_QUERY_ALL_CC             9
#define CFE_ES_CLEAR_SYS_LOG_CC         10
#define CFE_ES_WRITE_SYS_LOG_CC         11
#define CFE_ES_CLEAR_ER_LOG_CC          12
#define CFE_ES_WRITE_ER_LOG_CC          13
#define CFE_ES_START_PERF_DATA_CC       14
#define CFE_ES_STOP_PERF_DATA_CC        15
#define CFE_ES_SET_PERF_FILTER_MASK_CC  16
#define CFE_ES_SET_PERF_TRIGGER_MASK_CC 17
#define CFE_ES_OVER_WRITE_SYS_LOG_CC    18
#define CFE_ES_RESET_PR_COUNT_CC        19
#define CFE_ES_SET_MAX_PR_COUNT_CC      20
#define CFE_ES_DELETE_CDS_CC            21
#define CFE_ES_SEND_MEM_POOL_STATS_CC   22
#define CFE_ES_DUMP_CDS_REGISTRY_CC     23
#define CFE_ES_QUERY_ALL_TASKS_CC       24
// --- cfe_es_eventids.h ----------------------------------------------------------------------
#ifndef CFE_ES_MID_ERR_EID
#define CFE_ES_MID_ERR_EID 21
#define CFE_ES_CC1_ERR_EID 22
#define CFE_ES_LEN_ERR_EID 23
#endif
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// IT COUNTS THE ERROR ITSELF, which is the one thing to notice: the handler it guards is not
// called on a bad length, so if this did not bump CommandErrorCounter nothing would and the
// ground would see a command silently vanish.
//
// THE MESSAGE ID AND CODE ARE ONLY FETCHED ON FAILURE, because the event needs them and the
// success path does not.
Bool CFE_ES_VerifyCmdLength(CFE_MSG_Message *MsgPtr, I64 ExpectedLength)
{
  Bool result = TRUE;
  I64 ActualLength = 0;
  U16 FcnCode = 0;
  CFE_SB_MsgId MsgId = CFE_SB_InvalidMsgId;
  CFE_MSG_GetSize(MsgPtr, &ActualLength);
  /*
   ** Verify the command packet length
   */
  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(MsgPtr, &MsgId);
    CFE_MSG_GetFcnCode(MsgPtr, &FcnCode);
    CFE_EVS_SendEvent(CFE_ES_LEN_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid msg length: ID = 0x%X,  CC = %u, Len = %u, Expected = %u", CFE_SB_MsgIdToValue(MsgId), FcnCode, ActualLength, ExpectedLength);
    result = FALSE;
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  }
  return result;
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 *
 *-----------------------------------------------------------------*/
// TWENTY-FOUR CASES AND ONE DEFAULT, and the default's event quotes CFE_ES_CMD_MID rather than
// the message's own id -- it got here because the id already matched, so the only new
// information is the command code.
U0 CFE_ES_ProcessGroundCmd(CFE_SB_Buffer *SBBufPtr)
{
  U16 CommandCode = 0;
  CFE_MSG_GetFcnCode(&SBBufPtr->Msg, &CommandCode);
  switch (CommandCode) {
    case CFE_ES_NOOP_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_NoopCmd_t))) {
      CFE_ES_NoopCmd(SBBufPtr);
    }
    break;
    case CFE_ES_RESET_COUNTERS_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_ResetCountersCmd_t))) {
      CFE_ES_ResetCountersCmd(SBBufPtr);
    }
    break;
    case CFE_ES_RESTART_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_RestartCmd_t))) {
      CFE_ES_RestartCmd(SBBufPtr);
    }
    break;
    case CFE_ES_START_APP_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_StartAppCmd_t))) {
      CFE_ES_StartAppCmd(SBBufPtr);
    }
    break;
    case CFE_ES_STOP_APP_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_StopAppCmd_t))) {
      CFE_ES_StopAppCmd(SBBufPtr);
    }
    break;
    case CFE_ES_RESTART_APP_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_RestartAppCmd_t))) {
      CFE_ES_RestartAppCmd(SBBufPtr);
    }
    break;
    case CFE_ES_RELOAD_APP_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_ReloadAppCmd_t))) {
      CFE_ES_ReloadAppCmd(SBBufPtr);
    }
    break;
    case CFE_ES_QUERY_ONE_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_QueryOneCmd_t))) {
      CFE_ES_QueryOneCmd(SBBufPtr);
    }
    break;
    case CFE_ES_QUERY_ALL_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_QueryAllCmd_t))) {
      CFE_ES_QueryAllCmd(SBBufPtr);
    }
    break;
    case CFE_ES_QUERY_ALL_TASKS_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_QueryAllTasksCmd_t))) {
      CFE_ES_QueryAllTasksCmd(SBBufPtr);
    }
    break;
    case CFE_ES_CLEAR_SYS_LOG_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_ClearSysLogCmd_t))) {
      CFE_ES_ClearSysLogCmd(SBBufPtr);
    }
    break;
    case CFE_ES_WRITE_SYS_LOG_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_WriteSysLogCmd_t))) {
      CFE_ES_WriteSysLogCmd(SBBufPtr);
    }
    break;
    case CFE_ES_OVER_WRITE_SYS_LOG_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_OverWriteSysLogCmd_t))) {
      CFE_ES_OverWriteSysLogCmd(SBBufPtr);
    }
    break;
    case CFE_ES_CLEAR_ER_LOG_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_ClearERLogCmd_t))) {
      CFE_ES_ClearERLogCmd(SBBufPtr);
    }
    break;
    case CFE_ES_WRITE_ER_LOG_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_WriteERLogCmd_t))) {
      CFE_ES_WriteERLogCmd(SBBufPtr);
    }
    break;
    case CFE_ES_START_PERF_DATA_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_StartPerfDataCmd_t))) {
      CFE_ES_StartPerfDataCmd(SBBufPtr);
    }
    break;
    case CFE_ES_STOP_PERF_DATA_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_StopPerfDataCmd_t))) {
      CFE_ES_StopPerfDataCmd(SBBufPtr);
    }
    break;
    case CFE_ES_SET_PERF_FILTER_MASK_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_SetPerfFilterMaskCmd_t))) {
      CFE_ES_SetPerfFilterMaskCmd(SBBufPtr);
    }
    break;
    case CFE_ES_SET_PERF_TRIGGER_MASK_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_SetPerfTriggerMaskCmd_t))) {
      CFE_ES_SetPerfTriggerMaskCmd(SBBufPtr);
    }
    break;
    case CFE_ES_RESET_PR_COUNT_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_ResetPRCountCmd_t))) {
      CFE_ES_ResetPRCountCmd(SBBufPtr);
    }
    break;
    case CFE_ES_SET_MAX_PR_COUNT_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_SetMaxPRCountCmd_t))) {
      CFE_ES_SetMaxPRCountCmd(SBBufPtr);
    }
    break;
    case CFE_ES_DELETE_CDS_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_DeleteCDSCmd_t))) {
      CFE_ES_DeleteCDSCmd(SBBufPtr);
    }
    break;
    case CFE_ES_SEND_MEM_POOL_STATS_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_SendMemPoolStatsCmd_t))) {
      CFE_ES_SendMemPoolStatsCmd(SBBufPtr);
    }
    break;
    case CFE_ES_DUMP_CDS_REGISTRY_CC :
    if (CFE_ES_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_ES_DumpCDSRegistryCmd_t))) {
      CFE_ES_DumpCDSRegistryCmd(SBBufPtr);
    }
    break;
    default:
    CFE_EVS_SendEvent(CFE_ES_CC1_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid ground command code: ID = 0x%X, CC = %d", CFE_ES_CMD_MID, CommandCode);
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    break;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE TWO MESSAGE IDS ARE CACHED IN STATIC LOCALS, zero-initialised, which is NASA's
// CFE_SB_MSGID_RESERVED (0) -- the same arrangement cfe_evs_dispatch.HC and cfe_ta_dispatch.HC
// record, and for one commit the shared names CMD_MID and SEND_HK_MID collided across all
// three because a HolyC static local became a global under its bare name. The compiler scopes
// them properly now (docs/HOLYC_STRUCT_LIMITS.md #12), so the translation says what NASA says.
U0 CFE_ES_TaskPipe(CFE_SB_Buffer *SBBufPtr)
{
  static CFE_SB_MsgId CMD_MID;
  static CFE_SB_MsgId SEND_HK_MID;
  CFE_SB_MsgId MessageID = CFE_SB_InvalidMsgId;
  /* cache the local MID Values here, this avoids repeat lookups */
  if (!CFE_SB_IsValidMsgId(CMD_MID)) {
    CMD_MID = CFE_SB_ValueToMsgId(CFE_ES_CMD_MID);
    SEND_HK_MID = CFE_SB_ValueToMsgId(CFE_ES_SEND_HK_MID);
  }
  CFE_MSG_GetMsgId(&SBBufPtr->Msg, &MessageID);
  if (CFE_SB_MsgId_Equal(MessageID, SEND_HK_MID)) {
    /*
    ** Housekeeping telemetry request
    */
    CFE_ES_SendHkCmd(SBBufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, CMD_MID)) {
    /*
    ** ES task ground commands
    */
    CFE_ES_ProcessGroundCmd(SBBufPtr);
  } else {
    CFE_EVS_SendEvent(CFE_ES_MID_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid command pipe message ID: 0x%X", CFE_SB_MsgIdToValue(MessageID));
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  }
}
#endif
