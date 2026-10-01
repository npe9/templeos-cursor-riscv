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

// 1:1 HolyC translation of cFE modules/ta/fsw/src/cfe_ta_dispatch.c.
//
// THIS SOURCE IS CONDITIONAL, and the condition is why it is translated rather than skipped.
// modules/ta/CMakeLists.txt picks between two dispatchers:
//
//     if (CFE_EDS_ENABLED)  cfe_ta_eds_dispatch.c      else  cfe_ta_dispatch.c
//
// and this port does not enable EDS, so this is the one in the build. tools/cfs/check_manifest.py
// lists conditional sources with their guard rather than counting them, which means a module can
// read 100% with a conditional source untranslated -- and CFE_TA_TaskMain CALLS CFE_TA_TaskPipe,
// which lives here. A port that stopped at the two unconditional sources would have a task whose
// message loop dispatches to nothing.
//
// Everything this file calls is already translated: the MSG accessors (cfe_msg_ccsdspri.HC and
// friends), the message-id helpers (cfe_sb_msgid.HC) and the five command handlers in
// cfe_ta_task.HC. Only CFE_EVS_SendEvent is a stub, for the reason recorded there.
#ifndef CFE_TA_DISPATCH_HC
#define CFE_TA_DISPATCH_HC
// cfe_sb_api_typedefs.h. CFE_SB_MSGID_RESERVED is the "not yet looked up" marker the static
// cache below starts at, and it is deliberately NOT the same value as CFE_SB_INVALID_MSG_ID.
// CFE_SB_MSGID_RESERVED is CFE_SB_MSGID_WRAP_VALUE(0) -- a compile-time literal of a STRUCT
// type. HolyC has no compound literal for a class, so the static cache below is initialised
// the same way cfe_sb_msgid.HC spells CFE_SB_INVALID_MSG_ID: by calling the function. The two
// values are both 0 here, and the distinction NASA draws between them is lvalue vs rvalue use,
// not value.

Bool CFE_TA_VerifyCmdLength(CFE_MSG_Message *MsgPtr, I64 ExpectedLength)
{
  Bool result = TRUE;
  I64 ActualLength = 0;  // CFE_MSG_Size_t
  U16 FcnCode = 0;       // CFE_MSG_FcnCode_t
  CFE_SB_MsgId MsgId = CFE_SB_InvalidMsgId;

  CFE_MSG_GetSize(MsgPtr, &ActualLength);

  // Verify the command packet length
  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(MsgPtr, &MsgId);
    CFE_MSG_GetFcnCode(MsgPtr, &FcnCode);

    CFE_EVS_SendEvent(CFE_TA_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Invalid msg length: ID = 0x%X,  CC = %u, Len = %u, Expected = %u");

    result = FALSE;
    CFE_TA_Global.CommandErrorCounter++; // Routing Error
  }

  return result;
}

// Internal helper routine only, not part of API.
//
// This function processes a command, verifying that it is valid and of proper length.
U0 CFE_TA_ProcessGroundCommand(CFE_SB_Buffer *SBBufPtr, CFE_SB_MsgId MsgId)
{
  U16 FcnCode = 0; // CFE_MSG_FcnCode_t

  CFE_MSG_GetFcnCode(&SBBufPtr->Msg, &FcnCode);

  // Process "known" TA task ground commands
  switch (FcnCode) {
    case CFE_TA_NOOP_CC:
      if (CFE_TA_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TA_NoopCmd_t)))
        CFE_TA_NoopCmd(SBBufPtr);
      break;

    case CFE_TA_RESET_COUNTERS_CC:
      if (CFE_TA_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TA_ResetCountersCmd_t)))
        CFE_TA_ResetCountersCmd(SBBufPtr);
      break;

    case CFE_TA_QUERY_ALL_TASKS_CC:
      if (CFE_TA_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TA_QueryAllTasksCmd_t)))
        CFE_TA_QueryAllTasksCmd(SBBufPtr);
      break;

    case CFE_TA_SET_TASK_AFFINITY_CC:
      if (CFE_TA_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TA_SetTaskAffinityCmd_t)))
        CFE_TA_SetTaskAffinityCmd(SBBufPtr);
      break;

    case CFE_TA_GET_TASK_AFFINITY_CC:
      if (CFE_TA_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TA_GetTaskAffinityCmd_t)))
        CFE_TA_GetTaskAffinityCmd(SBBufPtr);
      break;

    default:
      // Unknown command code
      CFE_EVS_SendEvent(CFE_TA_ERR_CC_EID, CFE_EVS_EventType_ERROR,
                        "Invalid command code -- ID = 0x%08x, CC = %u");

      CFE_TA_Global.CommandErrorCounter++; // Routing Error
      break;
  }
}

U0 CFE_TA_TaskPipe(CFE_SB_Buffer *SBBufPtr)
{
  // Static cache for dynamic Message IDs
  static CFE_SB_MsgId CMD_MID;
  static CFE_SB_MsgId SEND_HK_MID;

  CFE_SB_MsgId MessageID = CFE_SB_InvalidMsgId;

  // cache the local MID Values here, this avoids repeat lookups
  if (!CFE_SB_IsValidMsgId(CMD_MID)) {
    CMD_MID = CFE_SB_ValueToMsgId(CFE_TA_CMD_MID);
    SEND_HK_MID = CFE_SB_ValueToMsgId(CFE_TA_SEND_HK_MID);
  }

  CFE_MSG_GetMsgId(&SBBufPtr->Msg, &MessageID);

  // Process all SB messages using the If/Else construct per reviewer request!
  if (CFE_SB_MsgId_Equal(MessageID, SEND_HK_MID)) {
    // Housekeeping request
    CFE_TA_ReportHousekeepingCmd(SBBufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, CMD_MID)) {
    // Normal ground command
    CFE_TA_ProcessGroundCommand(SBBufPtr, MessageID);
  } else {
    // Unknown command -- should never occur
    CFE_EVS_SendEvent(CFE_TA_ERR_MSGID_EID, CFE_EVS_EventType_ERROR,
                      "Invalid command packet, Message ID = 0x%08X");

    CFE_TA_Global.CommandErrorCounter++; // Routing Error
  }
}
#endif
