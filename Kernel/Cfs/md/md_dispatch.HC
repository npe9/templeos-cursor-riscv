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
// Translation of NASA's MD/fsw/src/md_dispatch.c -- the front door. Three functions: a length
// check, a command-code switch, and the pipe router that decides which of MD's three message
// ids a buffer carries.
//
// THIS IS THE `else` BRANCH OF CFE_EDS_ENABLED. md_eds_dispatch.c is the other, and both
// define MD_TaskPipe -- which is exactly the ambiguity that made tools/cfs/module_deps.py
// report MD's dependency order backwards until its owner map learned to prefer the source the
// configuration BUILDS. check_manifest.py is the authority on which branch that is.
//
// MD_app.c AND THIS FILE ARE A CYCLE, and gating them together is not a convenience: MD_AppMain
// calls MD_TaskPipe from here, and MD_ProcessGroundCommand's switch calls six handlers of which
// MD_SendHkCmd lives in md_app.c. module_deps.py reports it as a 2-source cycle of 775 lines
// once the owner map is right, the same shape as every cFE module's task/dispatch pair.
//
// THE THREE MESSAGE IDS ARE CACHED IN STATIC LOCALS, zero-initialised, because NASA's
// CFE_SB_MSGID_RESERVED is zero -- so the declaration needs no initialiser and the first call
// fills them. The names CMD_MID and SEND_HK_MID are shared with cfe_es_dispatch.HC,
// cfe_evs_dispatch.HC and cfe_ta_dispatch.HC, and for one commit those three COLLIDED because
// a HolyC static local became a global under its bare name (docs/HOLYC_STRUCT_LIMITS.md #12,
// fixed). MD makes it the FOURTH user of those names in one translation unit, so the collision
// is re-checked here rather than assumed to stay fixed: if the scoping regressed, MD's cache
// would pick up a cFE module's id and the pipe would route a wakeup to the wrong handler.
#ifndef MD_DISPATCH_HC
#define MD_DISPATCH_HC

// The three command-pipe message ids live in md_msg.HC beside MD's two telemetry ids, because
// md_app.c subscribes to all three and is included before this file.

// md_fcncodes.h. MD_SET_SIGNATURE_CC is inside the signature `#if`, which is why a probe that
// included md_fcncodes.h without md_interface_cfg.h first could not see it.
#define MD_NOOP_CC          0
#define MD_RESET_CNTRS_CC   1
#define MD_START_DWELL_CC   2
#define MD_STOP_DWELL_CC    3
#define MD_JAM_DWELL_CC     4
#define MD_SET_SIGNATURE_CC 5

// md_eventids.h, the three ids this file raises.
#define MD_MID_ERR_EID     15
#define MD_CC_ERR_EID      16
#define MD_CMD_LEN_ERR_EID 21

/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * **/
/*                                                                            */
/* Verify command packet length                                               */
/*                                                                            */
/* * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * **/

Bool MD_VerifyCmdLength(CFE_MSG_Message *MsgPtr, I64 ExpectedLength)
{
  Bool IsValidLength;
  I64 ActualLength;
  CFE_SB_MsgId MsgId;
  U16 FcnCode;

  IsValidLength = TRUE;
  ActualLength = 0;
  // CFE_SB_INVALID_MSG_ID is CFE_SB_MSGID_C(0) in the C, a compound literal HolyC cannot
  // spell, so cfe_sb_msgid.HC makes it a function. Same value, same meaning.
  MsgId = CFE_SB_InvalidMsgId();
  FcnCode = 0;

  CFE_MSG_GetSize(MsgPtr, &ActualLength);

  /* Verify the command packet length */
  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(MsgPtr, &MsgId);
    CFE_MSG_GetFcnCode(MsgPtr, &FcnCode);

    CFE_EVS_SendEvent(MD_CMD_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Invalid Msg length: ID = 0x%X, CC = %u, Len = %u, Expected = %u",
                      CFE_SB_MsgIdToValue(MsgId), FcnCode, ActualLength, ExpectedLength);

    IsValidLength = FALSE;
    MD_AppData.CommandErrorCounter++;
  }

  return IsValidLength;
}

U0 MD_ProcessGroundCommand(CFE_SB_Buffer *BufPtr)
{
  U16 CommandCode = 0;

  CFE_MSG_GetFcnCode(&BufPtr->Msg, &CommandCode);
  switch (CommandCode) {
    case MD_NOOP_CC :
    if (MD_VerifyCmdLength(&BufPtr->Msg, sizeof(MD_NoopCmd_t))) {
      MD_NoopCmd(BufPtr);
    }
    break;
    case MD_RESET_CNTRS_CC :
    if (MD_VerifyCmdLength(&BufPtr->Msg, sizeof(MD_ResetCountersCmd_t))) {
      MD_ResetCountersCmd(BufPtr);
    }
    break;
    case MD_START_DWELL_CC :
    if (MD_VerifyCmdLength(&BufPtr->Msg, sizeof(MD_StartDwellCmd_t))) {
      MD_StartDwellCmd(BufPtr);
    }
    break;
    case MD_STOP_DWELL_CC :
    if (MD_VerifyCmdLength(&BufPtr->Msg, sizeof(MD_StopDwellCmd_t))) {
      MD_StopDwellCmd(BufPtr);
    }
    break;
    case MD_JAM_DWELL_CC :
    if (MD_VerifyCmdLength(&BufPtr->Msg, sizeof(MD_JamDwellCmd_t))) {
      MD_JamDwellCmd(BufPtr);
    }
    break;

    // NASA wraps this one case in `#if MD_INTERFACE_SIGNATURE_OPTION == 1`. A preprocessor
    // conditional around a single `case` of a switch has no HolyC spelling even if `#if`
    // worked (limit #19), and the option is 1, so the case is written out.
    case MD_SET_SIGNATURE_CC :
    if (MD_VerifyCmdLength(&BufPtr->Msg, sizeof(MD_SetSignatureCmd_t))) {
      MD_SetSignatureCmd(BufPtr);
    }
    break;

    default:
    MD_AppData.CommandErrorCounter++;
    CFE_EVS_SendEvent(MD_CC_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid ground command code %d",
                      CommandCode);
    break;
  }
}

U0 MD_TaskPipe(CFE_SB_Buffer *BufPtr)
{
  // Zero-initialised, which IS CFE_SB_MSGID_RESERVED -- see the note at the top of this file
  // about these three names and the collision that used to happen.
  static CFE_SB_MsgId CMD_MID;
  static CFE_SB_MsgId SEND_HK_MID;
  static CFE_SB_MsgId WAKE_UP_MID;

  CFE_SB_MsgId MsgId = CFE_SB_InvalidMsgId();

  /* cache the local MID Values here, this avoids repeat lookups */
  if (!CFE_SB_IsValidMsgId(CMD_MID)) {
    CMD_MID = CFE_SB_ValueToMsgId(MD_CMD_MID);
    SEND_HK_MID = CFE_SB_ValueToMsgId(MD_SEND_HK_MID);
    WAKE_UP_MID = CFE_SB_ValueToMsgId(MD_WAKEUP_MID);
  }

  CFE_MSG_GetMsgId(&BufPtr->Msg, &MsgId);

  /* Process all SB messages */
  if (CFE_SB_MsgId_Equal(MsgId, WAKE_UP_MID)) {
    /* Periodic Wakeup */
    MD_DwellLoop(BufPtr);
  } else if (CFE_SB_MsgId_Equal(MsgId, SEND_HK_MID)) {
    /* Housekeeping request */
    MD_SendHkCmd(BufPtr);
  } else if (CFE_SB_MsgId_Equal(MsgId, CMD_MID)) {
    /* Ground command */
    MD_ProcessGroundCommand(BufPtr);
  } else {
    MD_AppData.CommandErrorCounter++;
    CFE_EVS_SendEvent(MD_MID_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Invalid command pipe message ID: 0x%08lX", CFE_SB_MsgIdToValue(MsgId));
  }
}
#endif
