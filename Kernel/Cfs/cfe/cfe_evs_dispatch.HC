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

// 1:1 HolyC translation of cFE modules/evs/fsw/src/cfe_evs_dispatch.c -- EVS's MESSAGE ROUTER.
//
// THE CONDITIONAL SOURCE, like ta's. modules/evs/CMakeLists.txt picks
//
//     if (CFE_EDS_ENABLED)  cfe_evs_eds_dispatch.c   else  cfe_evs_dispatch.c
//
// so this one is in THIS configuration's build and the EDS one is not. check_manifest.py lists
// it with its guard rather than counting it at depth 0, which is how ta's dispatcher nearly hid
// behind a 100%.
//
// INCLUDE cfe_evs_task.HC FIRST: every case below calls one of its command handlers, and
// CFE_EVS_TaskMain calls CFE_EVS_ProcessCommandPacket from here.
#ifndef CFE_EVS_DISPATCH_HC
#define CFE_EVS_DISPATCH_HC
// --- cfe_error.h ------------------------------------------------------------------------------
#define CFE_STATUS_WRONG_MSG_LENGTH  0xC8000002(I32)
#define CFE_STATUS_BAD_COMMAND_CODE  0xC8000004(I32)
// Local Function Prototypes -- NASA's own, in NASA's place. Both are defined below and called
// from CFE_EVS_ProcessCommandPacket above them, so the declarations are what the call sites bind
// to; neither is variadic, so nothing here depends on tools/cfs/check_variadic.py's second
// property, but the shape is the one it exists for.
U0 CFE_EVS_ProcessGroundCommand(CFE_SB_Buffer *SBBufPtr, CFE_SB_MsgId MsgId);
Bool CFE_EVS_VerifyCmdLength(CFE_MSG_Message *MsgPtr, I64 ExpectedLength);

U0 CFE_EVS_ProcessCommandPacket(CFE_SB_Buffer *SBBufPtr)
{
  // Static cache for dynamic Message IDs. NASA initialises both to CFE_SB_MSGID_RESERVED, which
  // is 0, and a HolyC static local is zero-initialised -- the same arrangement
  // cfe_ta_dispatch.HC records.
  //
  // THESE ARE NASA'S NAMES, and for one commit they were not. cfe_ta_dispatch.c uses the same
  // pair -- every cFE dispatcher does -- and a HolyC `static` local used to become a global
  // under the bare name, so this file's declarations clobbered ta's and CFE_TA_TaskPipe faulted
  // on `ld a0,0(a0)`. The compiler scopes static locals properly now
  // (tests/exec/cases/e_static_local_scope.hc), so the prefix is gone and the translation says
  // what NASA says. docs/HOLYC_STRUCT_LIMITS.md #12.
  static CFE_SB_MsgId CMD_MID;
  static CFE_SB_MsgId SEND_HK_MID;

  CFE_SB_MsgId MessageID = CFE_SB_InvalidMsgId;

  // cache the local MID Values here, this avoids repeat lookups
  if (!CFE_SB_IsValidMsgId(CMD_MID)) {
    CMD_MID = CFE_SB_ValueToMsgId(CFE_EVS_CMD_MID);
    SEND_HK_MID = CFE_SB_ValueToMsgId(CFE_EVS_SEND_HK_MID);
  }

  CFE_MSG_GetMsgId(&SBBufPtr->Msg, &MessageID);

  // Process all SB messages
  if (CFE_SB_MsgId_Equal(MessageID, SEND_HK_MID)) {
    // Housekeeping request
    CFE_EVS_SendHkCmd(SBBufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, CMD_MID)) {
    // EVS task specific command
    CFE_EVS_ProcessGroundCommand(SBBufPtr, MessageID);
  } else {
    // Unknown command -- should never occur
    CFE_EVS_Global.EVS_TlmPkt.Payload.CommandErrorCounter++;
    EVS_SendEvent(CFE_EVS_ERR_MSGID_EID, CFE_EVS_EventType_ERROR,
                  "Invalid command packet, Message ID = 0x%08X", CFE_SB_MsgIdToValue(MessageID));
  }
}

U0 CFE_EVS_ProcessGroundCommand(CFE_SB_Buffer *SBBufPtr, CFE_SB_MsgId MsgId)
{
  // status will get reset if it passes length check
  I32 Status = CFE_STATUS_WRONG_MSG_LENGTH;
  U16 FcnCode = 0;

  CFE_MSG_GetFcnCode(&SBBufPtr->Msg, &FcnCode);

  // Process "known" EVS task ground commands
  switch (FcnCode) {
    case CFE_EVS_NOOP_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_NoopCmd_t)))
        Status = CFE_EVS_NoopCmd(SBBufPtr);
      break;
    case CFE_EVS_RESET_COUNTERS_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_ResetCountersCmd_t)))
        Status = CFE_EVS_ResetCountersCmd(SBBufPtr);
      break;
    case CFE_EVS_ENABLE_EVENT_TYPE_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_EnableEventTypeCmd_t)))
        Status = CFE_EVS_EnableEventTypeCmd(SBBufPtr);
      break;
    case CFE_EVS_DISABLE_EVENT_TYPE_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_DisableEventTypeCmd_t)))
        Status = CFE_EVS_DisableEventTypeCmd(SBBufPtr);
      break;
    case CFE_EVS_SET_EVENT_FORMAT_MODE_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_SetEventFormatModeCmd_t)))
        Status = CFE_EVS_SetEventFormatModeCmd(SBBufPtr);
      break;
    case CFE_EVS_ENABLE_APP_EVENT_TYPE_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_EnableAppEventTypeCmd_t)))
        Status = CFE_EVS_EnableAppEventTypeCmd(SBBufPtr);
      break;
    case CFE_EVS_DISABLE_APP_EVENT_TYPE_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_DisableAppEventTypeCmd_t)))
        Status = CFE_EVS_DisableAppEventTypeCmd(SBBufPtr);
      break;
    case CFE_EVS_ENABLE_APP_EVENTS_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_EnableAppEventsCmd_t)))
        Status = CFE_EVS_EnableAppEventsCmd(SBBufPtr);
      break;
    case CFE_EVS_DISABLE_APP_EVENTS_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_DisableAppEventsCmd_t)))
        Status = CFE_EVS_DisableAppEventsCmd(SBBufPtr);
      break;
    case CFE_EVS_RESET_APP_COUNTER_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_ResetAppCounterCmd_t)))
        Status = CFE_EVS_ResetAppCounterCmd(SBBufPtr);
      break;
    case CFE_EVS_SET_FILTER_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_SetFilterCmd_t)))
        Status = CFE_EVS_SetFilterCmd(SBBufPtr);
      break;
    case CFE_EVS_ENABLE_PORTS_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_EnablePortsCmd_t)))
        Status = CFE_EVS_EnablePortsCmd(SBBufPtr);
      break;
    case CFE_EVS_DISABLE_PORTS_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_DisablePortsCmd_t)))
        Status = CFE_EVS_DisablePortsCmd(SBBufPtr);
      break;
    case CFE_EVS_RESET_FILTER_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_ResetFilterCmd_t)))
        Status = CFE_EVS_ResetFilterCmd(SBBufPtr);
      break;
    case CFE_EVS_RESET_ALL_FILTERS_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_ResetAllFiltersCmd_t)))
        Status = CFE_EVS_ResetAllFiltersCmd(SBBufPtr);
      break;
    case CFE_EVS_ADD_EVENT_FILTER_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_AddEventFilterCmd_t)))
        Status = CFE_EVS_AddEventFilterCmd(SBBufPtr);
      break;
    case CFE_EVS_DELETE_EVENT_FILTER_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_DeleteEventFilterCmd_t)))
        Status = CFE_EVS_DeleteEventFilterCmd(SBBufPtr);
      break;
    case CFE_EVS_WRITE_APP_DATA_FILE_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_WriteAppDataFileCmd_t)))
        Status = CFE_EVS_WriteAppDataFileCmd(SBBufPtr);
      break;
    case CFE_EVS_SET_LOG_MODE_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_SetLogModeCmd_t)))
        Status = CFE_EVS_SetLogModeCmd(SBBufPtr);
      break;
    case CFE_EVS_CLEAR_LOG_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_ClearLogCmd_t)))
        Status = CFE_EVS_ClearLogCmd(SBBufPtr);
      break;
    case CFE_EVS_WRITE_LOG_DATA_FILE_CC:
      if (CFE_EVS_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_EVS_WriteLogDataFileCmd_t)))
        Status = CFE_EVS_WriteLogDataFileCmd(SBBufPtr);
      break;
    // default is a bad command code as it was not found above
    default:
      EVS_SendEvent(CFE_EVS_ERR_CC_EID, CFE_EVS_EventType_ERROR,
                    "Invalid command code -- ID = 0x%08x, CC = %u", CFE_SB_MsgIdToValue(MsgId),
                    FcnCode);
      Status = CFE_STATUS_BAD_COMMAND_CODE;
      break;
  }

  if (Status == CFE_SUCCESS) {
    CFE_EVS_Global.EVS_TlmPkt.Payload.CommandCounter++;
  } else if (Status < 0) { // Negative values indicate errors
    CFE_EVS_Global.EVS_TlmPkt.Payload.CommandErrorCounter++;
  }
}

Bool CFE_EVS_VerifyCmdLength(CFE_MSG_Message *MsgPtr, I64 ExpectedLength)
{
  Bool result = TRUE;
  I64 ActualLength = 0;
  U16 FcnCode = 0;
  CFE_SB_MsgId MsgId = CFE_SB_InvalidMsgId;

  CFE_MSG_GetSize(MsgPtr, &ActualLength);

  // Verify the command packet length
  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(MsgPtr, &MsgId);
    CFE_MSG_GetFcnCode(MsgPtr, &FcnCode);

    EVS_SendEvent(CFE_EVS_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                  "Invalid msg length: ID = 0x%X,  CC = %u, Len = %u, Expected = %u",
                  CFE_SB_MsgIdToValue(MsgId), FcnCode, ActualLength, ExpectedLength);
    result = FALSE;
  }

  return result;
}
#endif
