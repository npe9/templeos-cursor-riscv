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
// STORED COMMAND'S DISPATCHER -- the 1:1 translation of NASA's fsw/src/sc_dispatch.c, 275 lines
// and three functions. The seventh of SC's eight sources, and the last before sc_app.c.
//
// Three message ids come in on one pipe (wakeup, send-hk, ground command) and seventeen command
// codes come in on the third of them. Every handler it reaches is already gated and already
// exercised, so what this file adds is the one assertion none of them can make on its own:
// **that the right handler ran for this command code.**
//
// ### IT IS NOT HS's NOTE #24, AND THAT WAS CHECKED RATHER THAN ASSUMED
//
// `docs/CFS_UPSTREAM_NOTES.md` #24 is HS's dispatcher printing a message id it never fetched, so
// its invalid-command-code event always reported the sentinel. SC's `SC_ProcessCommand` calls
// **both** `CFE_MSG_GetMsgId` and `CFE_MSG_GetFcnCode` at the top, before the switch, so its
// `default` arm prints a real id. SC is in the "fetch it and print it" group with HK, LC and CS.
//
// ### `SC_VerifyCmdLength` COUNTS AN ERROR ONLY FOR THE GROUND-COMMAND MESSAGE ID
//
//     Result = false;
//     if (CFE_SB_MsgIdToValue(MessageID) == SC_CMD_MID)
//         SC_OperData.HkPacket.Payload.CmdErrCtr++;
//
// So a wrong-length **wakeup** or **send-hk** message logs `SC_CMD_LEN_ERR_EID` and leaves
// `CmdErrCtr` alone, while a wrong-length ground command both logs and counts. The telemetry
// counter is therefore "bad GROUND commands", not "bad messages" -- which is defensible, and is
// invisible unless the two cases are driven side by side. Both are.
//
// ### AND ONE COMMAND CODE OUT OF SEVENTEEN HAS AN `else`
//
//     case SC_START_RTS_CC:
//         if (SC_VerifyCmdLength(...)) { SC_StartRtsCmd(...); }
//         else { SC_OperData.HkPacket.Payload.RtsActiveErrCtr++; }
//
// Sixteen cases do nothing on a length failure beyond what SC_VerifyCmdLength already did; START
// RTS also bumps `RtsActiveErrCtr`. **So one malformed START_RTS moves TWO counters** -- CmdErrCtr
// from the verifier and RtsActiveErrCtr from here -- and no other command code behaves that way.
// The group form `SC_START_RTS_GRP_CC` does NOT have the `else`, which makes it an asymmetry
// inside the pair as well.
//
// It reads as deliberate: a failed RTS start is the one length error that denies the ground an
// action it asked for, and SC counts those separately. Kept verbatim, driven, and printed beside
// a sixteenth-case comparison so the difference is a transcript line.
//
// ### THE THREE MESSAGE IDS ARE CACHED IN STATIC LOCALS, WHICH IS NOW THE PORT'S NORMAL IDIOM
//
// NASA writes `static CFE_SB_MsgId_t CMD_MID = CFE_SB_MSGID_RESERVED;` and fills all three on the
// first call. CFE_SB_MSGID_RESERVED is 0 and a HolyC static local is zero-initialised, so the
// initialiser is dropped and the lazy fill is kept -- the same arrangement every cFE dispatcher
// and HK's, LC's and CS's carry. docs/HOLYC_STRUCT_LIMITS.md #12 is why it is worth stating: a
// static local once became a GLOBAL under its bare name, so `CMD_MID` here and `CMD_MID` in four
// other dispatchers collapsed into one variable. Fixed, and this is the fifth file to rely on it.
#ifndef SC_DISPATCH_HC
#define SC_DISPATCH_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// sc_cfg.HC, sc_tbl.HC, sc_msg.HC, sc_global.HC, sc_events.HC, sc_utils.HC, sc_rtsrq.HC,
// sc_atsrq.HC, sc_loads.HC, sc_state.HC, sc_cmds.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13.
//
// It calls twenty handlers across sc_cmds.c, sc_atsrq.c and sc_rtsrq.c and nothing calls back, so
// it sits at the top of SC with only sc_app.c above it.

// --- sc_dispatch.h's three prototypes ----------------------------------------------------------
Bool SC_VerifyCmdLength(CFE_MSG_Message *Msg, I64 ExpectedLength);
U0 SC_ProcessRequest(CFE_SB_Buffer *BufPtr);
U0 SC_ProcessCommand(CFE_SB_Buffer *BufPtr);

/*******************************************************************************/
// Compare a command's actual length against the one its handler expects.
//
// THE EVENT PRINTS FOUR FIELDS AND THE COUNTER MOVES FOR ONE MESSAGE ID -- see the file header.
Bool SC_VerifyCmdLength(CFE_MSG_Message *Msg, I64 ExpectedLength)
{
  CFE_SB_MsgId MessageID;
  I16 CommandCode = 0;
  Bool Result = TRUE;
  I64 ActualLength = 0;

  MessageID = CFE_SB_InvalidMsgId();

  CFE_MSG_GetSize(Msg, &ActualLength);

  /* Verify the command packet length */
  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(Msg, &MessageID);
    CFE_MSG_GetFcnCode(Msg, &CommandCode);

    CFE_EVS_SendEvent(SC_CMD_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Invalid msg length: ID = 0x%08lX, CC = %d, Len = %d, Expected = %d",
                      CFE_SB_MsgIdToValue(MessageID), CommandCode, ActualLength, ExpectedLength);
    Result = FALSE;
    if (CFE_SB_MsgIdToValue(MessageID) == SC_CMD_MID) {
      SC_OperData.HkPacket.Payload.CmdErrCtr++;
    }
  }
  return Result;
}

/*******************************************************************************/
// Route one message off the command pipe by its message id.
//
// THE WAKEUP AND SEND-HK ARMS VERIFY A LENGTH; THE GROUND-COMMAND ARM DOES NOT. `SC_ProcessCommand`
// verifies per command code instead, because each of the seventeen has its own expected size --
// there is no single length a ground command must have.
U0 SC_ProcessRequest(CFE_SB_Buffer *BufPtr)
{
  // NASA initialises all three to CFE_SB_MSGID_RESERVED, which is 0, and a HolyC static local is
  // zero-initialised -- the same arrangement every cFE dispatcher in this port records.
  static CFE_SB_MsgId CMD_MID;
  static CFE_SB_MsgId SEND_HK_MID;
  static CFE_SB_MsgId WAKEUP_MID;

  CFE_SB_MsgId MessageID;

  MessageID = CFE_SB_InvalidMsgId();

  /* cache the local MID Values here, this avoids repeat lookups */
  if (!CFE_SB_IsValidMsgId(CMD_MID)) {
    CMD_MID = CFE_SB_ValueToMsgId(SC_CMD_MID);
    SEND_HK_MID = CFE_SB_ValueToMsgId(SC_SEND_HK_MID);
    WAKEUP_MID = CFE_SB_ValueToMsgId(SC_WAKEUP_MID);
  }

  CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);

  if (CFE_SB_MsgId_Equal(MessageID, WAKEUP_MID)) {
    if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_WakeupCmd_t))) {
      SC_WakeupCmd(BufPtr(SC_WakeupCmd_t *));
    }
  } else if (CFE_SB_MsgId_Equal(MessageID, SEND_HK_MID)) {
    if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_SendHkCmd_t))) {
      SC_SendHkCmd(BufPtr(SC_SendHkCmd_t *));
    }
  } else if (CFE_SB_MsgId_Equal(MessageID, CMD_MID)) {
    /* request from the ground */
    SC_ProcessCommand(BufPtr);
  } else {
    CFE_EVS_SendEvent(SC_MID_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid command pipe message ID: 0x%08lX",
                      CFE_SB_MsgIdToValue(MessageID));

    SC_OperData.HkPacket.Payload.CmdErrCtr++;
  }
}

/*******************************************************************************/
// Route a ground command by its function code: seventeen cases and a default.
//
// **BOTH THE MESSAGE ID AND THE FUNCTION CODE ARE FETCHED BEFORE THE SWITCH**, which is what keeps
// the default arm's event honest -- see the file header on HS's note #24.
//
// EVERY CASE IS THE SAME FOUR LINES except SC_START_RTS_CC, which has an `else`. The repetition is
// NASA's and is kept: a table-driven rewrite would be shorter and would stop the differential from
// pinning each case against its own expected size.
U0 SC_ProcessCommand(CFE_SB_Buffer *BufPtr)
{
  I16 CommandCode = 0;
  CFE_SB_MsgId MessageID;

  MessageID = CFE_SB_InvalidMsgId();

  CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);
  CFE_MSG_GetFcnCode(&BufPtr->Msg, &CommandCode);

  switch (CommandCode) {
    case SC_NOOP_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_NoopCmd_t))) {
        SC_NoopCmd(BufPtr(SC_NoopCmd_t *));
      }
      break;

    case SC_RESET_COUNTERS_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_ResetCountersCmd_t))) {
        SC_ResetCountersCmd(BufPtr(SC_ResetCountersCmd_t *));
      }
      break;

    case SC_START_ATS_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_StartAtsCmd_t))) {
        SC_StartAtsCmd(BufPtr(SC_StartAtsCmd_t *));
      }
      break;

    case SC_STOP_ATS_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_StopAtsCmd_t))) {
        SC_StopAtsCmd(BufPtr(SC_StopAtsCmd_t *));
      }
      break;

    case SC_START_RTS_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_StartRtsCmd_t))) {
        SC_StartRtsCmd(BufPtr(SC_StartRtsCmd_t *));
      } else {
        // **THE ONE `else` IN SEVENTEEN CASES.** SC_VerifyCmdLength has already bumped CmdErrCtr
        // for this message id, so a malformed START_RTS moves TWO counters where every other
        // command code moves one -- including its own group form below. See the file header.
        SC_OperData.HkPacket.Payload.RtsActiveErrCtr++;
      }
      break;

    case SC_STOP_RTS_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_StopRtsCmd_t))) {
        SC_StopRtsCmd(BufPtr(SC_StopRtsCmd_t *));
      }
      break;

    case SC_DISABLE_RTS_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_DisableRtsCmd_t))) {
        SC_DisableRtsCmd(BufPtr(SC_DisableRtsCmd_t *));
      }
      break;

    case SC_ENABLE_RTS_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_EnableRtsCmd_t))) {
        SC_EnableRtsCmd(BufPtr(SC_EnableRtsCmd_t *));
      }
      break;

    case SC_SWITCH_ATS_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_SwitchAtsCmd_t))) {
        SC_SwitchAtsCmd(BufPtr(SC_SwitchAtsCmd_t *));
      }
      break;

    case SC_JUMP_ATS_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_JumpAtsCmd_t))) {
        SC_JumpAtsCmd(BufPtr(SC_JumpAtsCmd_t *));
      }
      break;

    case SC_CONTINUE_ATS_ON_FAILURE_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_ContinueAtsOnFailureCmd_t))) {
        SC_ContinueAtsOnFailureCmd(BufPtr(SC_ContinueAtsOnFailureCmd_t *));
      }
      break;

    case SC_APPEND_ATS_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_AppendAtsCmd_t))) {
        SC_AppendAtsCmd(BufPtr(SC_AppendAtsCmd_t *));
      }
      break;

    case SC_MANAGE_TABLE_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_ManageTableCmd_t))) {
        SC_ManageTableCmd(BufPtr(SC_ManageTableCmd_t *));
      }
      break;

    case SC_START_RTS_GRP_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_StartRtsGrpCmd_t))) {
        SC_StartRtsGrpCmd(BufPtr(SC_StartRtsGrpCmd_t *));
      }
      break;

    case SC_STOP_RTS_GRP_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_StopRtsGrpCmd_t))) {
        SC_StopRtsGrpCmd(BufPtr(SC_StopRtsGrpCmd_t *));
      }
      break;

    case SC_DISABLE_RTS_GRP_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_DisableRtsGrpCmd_t))) {
        SC_DisableRtsGrpCmd(BufPtr(SC_DisableRtsGrpCmd_t *));
      }
      break;

    case SC_ENABLE_RTS_GRP_CC:
      if (SC_VerifyCmdLength(&BufPtr->Msg, sizeof(SC_EnableRtsGrpCmd_t))) {
        SC_EnableRtsGrpCmd(BufPtr(SC_EnableRtsGrpCmd_t *));
      }
      break;

    default:
      CFE_EVS_SendEvent(SC_CC_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid Command Code: MID =  0x%08lX CC =  %d",
                        CFE_SB_MsgIdToValue(MessageID), CommandCode);
      SC_OperData.HkPacket.Payload.CmdErrCtr++;
      break;
  } /* end switch */
}

#endif
