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
// 1:1 HolyC translation of cFE modules/time/fsw/src/cfe_time_dispatch.c -- TIME's MESSAGE ROUTER.
//
// THE CONDITIONAL SOURCE, like evs's and ta's. modules/time/CMakeLists.txt picks
//
//     if (CFE_EDS_ENABLED)  cfe_time_eds_dispatch.c   else  cfe_time_dispatch.c
//
// so this one is in THIS configuration's build and the EDS one is not. check_manifest.py lists it
// with its guard rather than counting it at depth 0, which is how ta's dispatcher nearly hid
// behind a 100%.
//
// TWO LEVELS OF ROUTING, and the split matters for the counters. CFE_TIME_TaskPipe switches on
// the MESSAGE ID -- the 1Hz wakeup, the housekeeping request, the tone signal, the tone data, the
// tone request and the ground-command stream -- and only the last of those goes on to
// CFE_TIME_ProcessGroundCmd, which switches on the COMMAND CODE. That is why every handler in
// cfe_time_task.HC carries NASA's comment "we only increment the command execution counter when
// processing CFE_TIME_CMD_MID commands": an unrecognised message ID is an EVENT and nothing else,
// while an unrecognised command code bumps CommandErrorCounter. A wrong LENGTH on a recognised
// command bumps it too, which is CFE_TIME_VerifyCmdLength's job.
//
// INCLUDE cfe_time_task.HC FIRST: every case below calls one of its command handlers, and
// CFE_TIME_TaskMain calls CFE_TIME_TaskPipe from here.
// THIS FILE CONTAINS NO `#if`, AND THAT IS DELIBERATE. This compiler's `#if <expr>` is
// UNCONDITIONALLY TRUE -- host/lexer.c handles only a literal `0`, so `#if (SOMETHING == 1)` is
// compiled in however SOMETHING is defined, silently. docs/HOLYC_STRUCT_LIMITS.md #15. NASA's
// configuration directives are therefore resolved BY HAND here, each one replaced by a bracketed
// comment naming the guard, its value and which branch survived, so the translation can still be
// read against the C line for line. Every other TIME file that landed before this one does the
// same thing, cfe_time_utils.HC included; what is new is that these three had enough
// configuration in them to make the silence dangerous rather than merely untidy -- written with
// the directives in place, the first version of this file referenced CFE_TIME_SetDelay,
// CFE_TIME_SetSignal, CFE_TIME_SetSource, OS_GetLocalMET and OS_SelectTone, none of which this
// configuration builds. The blob's import trailer is what caught it.
//
#ifndef CFE_TIME_DISPATCH_HC
#define CFE_TIME_DISPATCH_HC
// --- cfe_time_eventids.h: the three this file sends -------------------------------------------
#define CFE_TIME_ID_ERR_EID  26
#define CFE_TIME_CC_ERR_EID  27
#define CFE_TIME_LEN_ERR_EID 49
// --- cfe_time_fcncodes.h / default_cfe_time_fcncode_values.h ----------------------------------
// NASA spells these CFE_TIME_CCVAL(NOOP) and so on, which expands to the enumerator
// CFE_TIME_FunctionCode_NOOP. The numbers are that enum's, and check_constants.py compares every
// one of them against it -- which it could not do until it learned to see an ENUMERATOR at all
// (docs/CFS_PLAN.md: that hole hid 160 of 601 names).
#define CFE_TIME_NOOP_CC                  0
#define CFE_TIME_RESET_COUNTERS_CC        1
#define CFE_TIME_SEND_DIAGNOSTIC_CC       2
#define CFE_TIME_SET_SOURCE_CC            3
#define CFE_TIME_SET_STATE_CC             4
#define CFE_TIME_ADD_DELAY_CC             5
#define CFE_TIME_SUB_DELAY_CC             6
#define CFE_TIME_SET_TIME_CC              7
#define CFE_TIME_SET_MET_CC               8
#define CFE_TIME_SET_STCF_CC              9
#define CFE_TIME_SET_LEAP_SECONDS_CC      10
#define CFE_TIME_ADD_ADJUST_CC            11
#define CFE_TIME_SUB_ADJUST_CC            12
#define CFE_TIME_ADD_ONE_HZ_ADJUSTMENT_CC 13
#define CFE_TIME_SUB_ONE_HZ_ADJUSTMENT_CC 14
#define CFE_TIME_SET_SIGNAL_CC            15
// Local Function Prototype -- NASA's own, in NASA's place. CFE_TIME_ProcessGroundCmd is defined
// below and called from CFE_TIME_TaskPipe under it, so the order here matches the C.
U0 CFE_TIME_ProcessGroundCmd(CFE_SB_Buffer *SBBufPtr);
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Function to verify the length of incoming TIME command packets
 *
 *-----------------------------------------------------------------*/
Bool CFE_TIME_VerifyCmdLength(CFE_MSG_Message *MsgPtr, I64 ExpectedLength)
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
    CFE_EVS_SendEvent(CFE_TIME_LEN_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid msg length: ID = 0x%X,  CC = %u, Len = %u, Expected = %u", CFE_SB_MsgIdToValue(MsgId), FcnCode, ActualLength, ExpectedLength);
    result = FALSE;
    ++CFE_TIME_Global.CommandErrorCounter;
  }
  return result;
}
/*----------------------------------------------------------------
 *
 * Local Helper function
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_ProcessGroundCmd(CFE_SB_Buffer *SBBufPtr)
{
  U16 CommandCode = 0;
  CFE_MSG_GetFcnCode(&SBBufPtr->Msg, &CommandCode);
  switch (CommandCode) {
    case CFE_TIME_NOOP_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_NoopCmd_t)))
      CFE_TIME_NoopCmd(SBBufPtr);
    break;
    case CFE_TIME_RESET_COUNTERS_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_ResetCountersCmd_t)))
      CFE_TIME_ResetCountersCmd(SBBufPtr);
    break;
    case CFE_TIME_SEND_DIAGNOSTIC_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_SendDiagnosticCmd_t)))
      CFE_TIME_SendDiagnosticTlm(SBBufPtr);
    break;
    case CFE_TIME_SET_STATE_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_SetStateCmd_t)))
      CFE_TIME_SetStateCmd(SBBufPtr);
    break;
    case CFE_TIME_SET_SOURCE_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_SetSourceCmd_t)))
      CFE_TIME_SetSourceCmd(SBBufPtr);
    break;
    case CFE_TIME_SET_SIGNAL_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_SetSignalCmd_t)))
      CFE_TIME_SetSignalCmd(SBBufPtr);
    break;
    /*
    ** Time Clients process "tone delay" commands...
    */
    case CFE_TIME_ADD_DELAY_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_AddDelayCmd_t)))
      CFE_TIME_AddDelayCmd(SBBufPtr);
    break;
    case CFE_TIME_SUB_DELAY_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_SubDelayCmd_t)))
      CFE_TIME_SubDelayCmd(SBBufPtr);
    break;
    /*
    ** Time Servers process "set time" commands...
    */
    case CFE_TIME_SET_TIME_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_SetTimeCmd_t)))
      CFE_TIME_SetTimeCmd(SBBufPtr);
    break;
    case CFE_TIME_SET_MET_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_SetMETCmd_t)))
      CFE_TIME_SetMETCmd(SBBufPtr);
    break;
    case CFE_TIME_SET_STCF_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_SetSTCFCmd_t)))
      CFE_TIME_SetSTCFCmd(SBBufPtr);
    break;
    case CFE_TIME_SET_LEAP_SECONDS_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_SetLeapSecondsCmd_t)))
      CFE_TIME_SetLeapSecondsCmd(SBBufPtr);
    break;
    case CFE_TIME_ADD_ADJUST_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_AddAdjustCmd_t)))
      CFE_TIME_AddAdjustCmd(SBBufPtr);
    break;
    case CFE_TIME_SUB_ADJUST_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_SubAdjustCmd_t)))
      CFE_TIME_SubAdjustCmd(SBBufPtr);
    break;
    case CFE_TIME_ADD_ONE_HZ_ADJUSTMENT_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_AddOneHzAdjustmentCmd_t)))
      CFE_TIME_AddOneHzAdjustmentCmd(SBBufPtr);
    break;
    case CFE_TIME_SUB_ONE_HZ_ADJUSTMENT_CC :
    if (CFE_TIME_VerifyCmdLength(&SBBufPtr->Msg, sizeof(CFE_TIME_SubOneHzAdjustmentCmd_t)))
      CFE_TIME_SubOneHzAdjustmentCmd(SBBufPtr);
    break;
    default:
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_CC_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid command code -- ID = 0x%X, CC = %d", CFE_TIME_CMD_MID, CommandCode);
    break;
  }
  /* switch (CFE_TIME_CMD_MID -- command code)*/
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_TaskPipe(CFE_SB_Buffer *SBBufPtr)
{
  // Static cache for the six dynamic Message IDs. NASA initialises every one to
  // CFE_SB_MSGID_RESERVED, which is 0, and a HolyC static local is zero-initialised -- the same
  // arrangement cfe_evs_dispatch.HC and cfe_ta_dispatch.HC record, and now gated by
  // tests/exec/cases/e_static_local_class_zero.hc rather than assumed.
  //
  // THESE ARE NASA'S NAMES. Every cFE dispatcher uses the same spellings, and a HolyC `static`
  // local used to become a global under the bare name, so three files declaring CMD_MID would
  // clobber each other. The compiler scopes static locals properly now
  // (tests/exec/cases/e_static_local_scope.hc). docs/HOLYC_STRUCT_LIMITS.md #12.
  static CFE_SB_MsgId CMD_MID;
  static CFE_SB_MsgId SEND_HK_MID;
  static CFE_SB_MsgId ONEHZ_CMD_MID;
  static CFE_SB_MsgId TONE_CMD_MID;
  static CFE_SB_MsgId DATA_CMD_MID;
  static CFE_SB_MsgId SEND_CMD_MID;
  CFE_SB_MsgId MessageID = CFE_SB_InvalidMsgId;
  /* cache the local MID Values here, this avoids repeat lookups */
  if (!CFE_SB_IsValidMsgId(CMD_MID)) {
    CMD_MID = CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID);
    SEND_HK_MID = CFE_SB_ValueToMsgId(CFE_TIME_SEND_HK_MID);
    ONEHZ_CMD_MID = CFE_SB_ValueToMsgId(CFE_TIME_ONEHZ_CMD_MID);
    TONE_CMD_MID = CFE_SB_ValueToMsgId(CFE_TIME_TONE_CMD_MID);
    DATA_CMD_MID = CFE_SB_ValueToMsgId(CFE_TIME_DATA_CMD_MID);
    SEND_CMD_MID = CFE_SB_ValueToMsgId(CFE_TIME_SEND_CMD_MID);
  }
  CFE_MSG_GetMsgId(&SBBufPtr->Msg, &MessageID);
  /* Process all SB messages */
  if (CFE_SB_MsgId_Equal(MessageID, ONEHZ_CMD_MID)) {
    /*
    ** Run time state machine at 1Hz...
    */
    CFE_TIME_OneHzCmd(SBBufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, SEND_HK_MID)) {
    /*
    ** Housekeeping telemetry request...
    */
    CFE_TIME_SendHkCmd(SBBufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, DATA_CMD_MID)) {
    /*
    ** Time at the tone "data"...
    */
    CFE_TIME_ToneDataCmd(SBBufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, TONE_CMD_MID)) {
    /*
    ** Time at the tone "signal"...
    */
    CFE_TIME_ToneSignalCmd(SBBufPtr);
    // [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
  } else if (CFE_SB_MsgId_Equal(MessageID, SEND_CMD_MID)) {
    /*
    ** Request for time at the tone "data"...
    */
    CFE_TIME_ToneSendCmd(SBBufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, CMD_MID)) {
    /* Normal ground command */
    CFE_TIME_ProcessGroundCmd(SBBufPtr);
  } else {
    /*
    ** Note: we only increment the command error counter when
    **    processing CFE_TIME_CMD_MID commands...
    */
    CFE_EVS_SendEvent(CFE_TIME_ID_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid message ID -- ID = 0x%X", CFE_SB_MsgIdToValue(MessageID));
  }
}
#endif
