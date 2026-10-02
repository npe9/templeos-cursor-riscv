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
// 1:1 HolyC translation of cFE modules/sb/fsw/src/cfe_sb_dispatch.c -- SB's COMMAND DISPATCHER.
//
// Three message ids reach SB's command pipe and this decides which. Two of them carry a
// function code and get their own switch; the third is the housekeeping request, which has no
// code at all. Every branch checks the packet's LENGTH before calling anything, because the
// handler reads a payload whose size it has not otherwise verified.
//
// This is the non-EDS half of a CMake either/or: cfe_sb_eds_dispatch.c is built when
// CFE_EDS_ENABLED, and check_manifest.py reports both with their guard so that choosing one is
// visible rather than assumed.
#ifndef CFE_SB_DISPATCH_HC
#define CFE_SB_DISPATCH_HC
#include "cfe_sb_task.HC" // the eleven command handlers this dispatches to
// --- cfe_sb_eventids.h ------------------------------------------------------------------------
#define CFE_SB_BAD_CMD_CODE_EID 42
#define CFE_SB_BAD_MSGID_EID    43
#define CFE_SB_LEN_ERR_EID      68
// --- default_cfe_sb_fcncodes.h ----------------------------------------------------------------
// Note the GAP: there is no command code 6. NASA's header documents it as deprecated/removed,
// and the numbers are what the ground system sends, so the hole is kept rather than closed.
#define CFE_SB_NOOP_CC                  0
#define CFE_SB_RESET_COUNTERS_CC        1
#define CFE_SB_SEND_SB_STATS_CC         2
#define CFE_SB_WRITE_ROUTING_INFO_CC    3
#define CFE_SB_ENABLE_ROUTE_CC          4
#define CFE_SB_DISABLE_ROUTE_CC         5
#define CFE_SB_WRITE_PIPE_INFO_CC       7
#define CFE_SB_WRITE_MAP_INFO_CC        8
#define CFE_SB_ENABLE_SUB_REPORTING_CC  9
#define CFE_SB_DISABLE_SUB_REPORTING_CC 10
#define CFE_SB_SEND_PREV_SUBS_CC        11

/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Verifies the length of incoming SB command packets, returns true if acceptable
 *
 *-----------------------------------------------------------------*/
Bool CFE_SB_VerifyCmdLength(CFE_MSG_Message *MsgPtr, I64 ExpectedLength)
{
  Bool result = TRUE;
  I64 ActualLength = 0; // CFE_MSG_Size_t
  U16 FcnCode = 0;      // CFE_MSG_FcnCode_t
  CFE_SB_MsgId MsgId = CFE_SB_InvalidMsgId;
  CFE_MSG_GetSize(MsgPtr, &ActualLength);
  /*
  ** Verify the command packet length
  */
  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(MsgPtr, &MsgId);
    CFE_MSG_GetFcnCode(MsgPtr, &FcnCode);
    CFE_EVS_SendEvent(CFE_SB_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Invalid msg length: ID = 0x%X,  CC = %u, Len = %u, Expected = %u",
                      CFE_SB_MsgIdToValue(MsgId), FcnCode, ActualLength, ExpectedLength);
    result = FALSE;
    ++CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter;
  }
  return result;
}

/*----------------------------------------------------------------
 *
 * Local Helper function
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_ProcessSubReportCmd(CFE_SB_Buffer *SBBufPtr)
{
  U16 FcnCode = 0; // CFE_MSG_FcnCode_t
  /* Note: Command counter not incremented for this command */
  CFE_MSG_GetFcnCode(&SBBufPtr->Msg, &FcnCode);
  switch (FcnCode) {
    case CFE_SB_SEND_PREV_SUBS_CC:
      if (CFE_SB_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_SB_SendPrevSubsCmd_t))) {
        CFE_SB_SendPrevSubsCmd(SBBufPtr);
      }
      break;
    case CFE_SB_ENABLE_SUB_REPORTING_CC:
      if (CFE_SB_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_SB_EnableSubReportingCmd_t))) {
        CFE_SB_EnableSubReportingCmd(SBBufPtr);
      }
      break;
    case CFE_SB_DISABLE_SUB_REPORTING_CC:
      if (CFE_SB_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_SB_DisableSubReportingCmd_t))) {
        CFE_SB_DisableSubReportingCmd(SBBufPtr);
      }
      break;
    default:
      CFE_EVS_SendEvent(CFE_SB_BAD_CMD_CODE_EID, CFE_EVS_EventType_ERROR,
                        "Invalid Cmd, Unexpected Command Code %u", FcnCode);
      CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter++;
      break;
  }
}

/*----------------------------------------------------------------
 *
 * Local Helper function
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_ProcessGroundCmd(CFE_SB_Buffer *SBBufPtr)
{
  U16 FcnCode = 0; // CFE_MSG_FcnCode_t
  CFE_MSG_GetFcnCode(&SBBufPtr->Msg, &FcnCode);
  switch (FcnCode) {
    case CFE_SB_NOOP_CC:
      if (CFE_SB_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_SB_NoopCmd_t))) {
        CFE_SB_NoopCmd(SBBufPtr);
      }
      break;
    case CFE_SB_RESET_COUNTERS_CC:
      if (CFE_SB_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_SB_ResetCountersCmd_t))) {
        /* Note: Command counter not incremented for this command */
        CFE_SB_ResetCountersCmd(SBBufPtr);
      }
      break;
    case CFE_SB_SEND_SB_STATS_CC:
      if (CFE_SB_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_SB_SendSbStatsCmd_t))) {
        CFE_SB_SendStatsCmd(SBBufPtr);
      }
      break;
    case CFE_SB_WRITE_ROUTING_INFO_CC:
      if (CFE_SB_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_SB_WriteRoutingInfoCmd_t))) {
        CFE_SB_WriteRoutingInfoCmd(SBBufPtr);
      }
      break;
    case CFE_SB_ENABLE_ROUTE_CC:
      if (CFE_SB_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_SB_EnableRouteCmd_t))) {
        CFE_SB_EnableRouteCmd(SBBufPtr);
      }
      break;
    case CFE_SB_DISABLE_ROUTE_CC:
      if (CFE_SB_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_SB_DisableRouteCmd_t))) {
        CFE_SB_DisableRouteCmd(SBBufPtr);
      }
      break;
    case CFE_SB_WRITE_PIPE_INFO_CC:
      if (CFE_SB_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_SB_WritePipeInfoCmd_t))) {
        CFE_SB_WritePipeInfoCmd(SBBufPtr);
      }
      break;
    case CFE_SB_WRITE_MAP_INFO_CC:
      if (CFE_SB_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_SB_WriteMapInfoCmd_t))) {
        CFE_SB_WriteMapInfoCmd(SBBufPtr);
      }
      break;
    default:
      CFE_EVS_SendEvent(CFE_SB_BAD_CMD_CODE_EID, CFE_EVS_EventType_ERROR,
                        "Invalid Cmd, Unexpected Command Code %u", FcnCode);
      CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter++;
      break;
  }
}
// The three cached message ids. NASA declares them `static` inside CFE_SB_ProcessCmdPipePkt and
// initialises them to CFE_SB_MSGID_RESERVED; in HolyC a static local is a file-scope global
// (and was, until recently, a BROKEN one -- see docs/HOLYC_STRUCT_LIMITS.md and
// holyc-static-local-collides). The initial value cannot be a compound literal either, so the
// cache starts zeroed and the `!CFE_SB_IsValidMsgId` test below fills it on the first call.
// cfe_ta_dispatch.HC does the same thing for the same reason, and records why RESERVED and
// INVALID are both zero here.
CFE_SB_MsgId CFE_SB_ProcessCmdPipePkt_CMD_MID;
CFE_SB_MsgId CFE_SB_ProcessCmdPipePkt_SEND_HK_MID;
CFE_SB_MsgId CFE_SB_ProcessCmdPipePkt_SUB_RPT_CTRL_MID;

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_ProcessCmdPipePkt(CFE_SB_Buffer *SBBufPtr)
{
  CFE_SB_MsgId MessageID = CFE_SB_InvalidMsgId;
  /* cache the local MID Values here, this avoids repeat lookups */
  if (!CFE_SB_IsValidMsgId(CFE_SB_ProcessCmdPipePkt_CMD_MID)) {
    CFE_SB_ProcessCmdPipePkt_CMD_MID = CFE_SB_ValueToMsgId(CFE_SB_CMD_MID);
    CFE_SB_ProcessCmdPipePkt_SEND_HK_MID = CFE_SB_ValueToMsgId(CFE_SB_SEND_HK_MID);
    CFE_SB_ProcessCmdPipePkt_SUB_RPT_CTRL_MID = CFE_SB_ValueToMsgId(CFE_SB_SUB_RPT_CTRL_MID);
  }
  CFE_MSG_GetMsgId(&SBBufPtr->Msg, &MessageID);
  /* Process all SB messages */
  if (CFE_SB_MsgId_Equal(MessageID, CFE_SB_ProcessCmdPipePkt_SEND_HK_MID)) {
    /* Housekeeping request */
    /* Note: Command counter not incremented for this command */
    CFE_SB_SendHKTlmCmd(SBBufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, CFE_SB_ProcessCmdPipePkt_CMD_MID)) {
    /* Normal ground command */
    CFE_SB_ProcessGroundCmd(SBBufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, CFE_SB_ProcessCmdPipePkt_SUB_RPT_CTRL_MID)) {
    /* Internal subscription sync request */
    CFE_SB_ProcessSubReportCmd(SBBufPtr);
  } else {
    /* Unknown command -- should never occur */
    CFE_EVS_SendEvent(CFE_SB_BAD_MSGID_EID, CFE_EVS_EventType_ERROR,
                      "Invalid Cmd, Unexpected Msg Id: 0x%x", CFE_SB_MsgIdToValue(MessageID));
    CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter++;
  }
}
#endif
