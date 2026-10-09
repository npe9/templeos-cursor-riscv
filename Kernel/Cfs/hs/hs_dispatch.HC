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
// HEALTH & SAFETY'S DISPATCHER -- the 1:1 translation of NASA's fsw/src/hs_dispatch.c, 447 lines
// and fifteen functions: one length checker, one command-code switch, one message-id router and
// twelve verify-then-call wrappers.
//
// ### THE INVALID-COMMAND-CODE EVENT REPORTS A MESSAGE ID IT NEVER READ
//
// docs/CFS_UPSTREAM_NOTES.md #24. HS_AppProcessGroundCmd declares
//
//     CFE_SB_MsgId_t MessageID = CFE_SB_INVALID_MSG_ID;   /* Init to invalid value */
//
// calls **CFE_MSG_GetFcnCode only**, and then in its `default` arm prints
//
//     "Invalid command code: ID = 0x%08lX, CC = %d", CFE_SB_MsgIdToValue(MessageID), CommandCode
//
// MessageID is written exactly once -- by that initialiser -- and read exactly once, by this
// event. **So the id in the text is always the sentinel**, never the id of the command that
// arrived. The command code is right; the field in front of it is a constant dressed as data.
//
// THIS IS HS ALONE AMONG SIX. HK, LC, CS, MD and MM all call CFE_MSG_GetMsgId in the default arm
// before reporting -- HK's line is literally `CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);`
// immediately above its CFE_EVS_SendEvent -- and MD and MM sidestep it by not printing an id at
// all. Only HS prints one and does not fetch it. Measured across all six dispatchers, not
// assumed.
//
// It is harmless in flight (an invalid command code can only have arrived on HS_CMD_MID, so a
// ground operator can infer the id) and it is kept verbatim, because the fix is a line of NASA's
// code that is not there. The exercise drives a bad command code so the sentinel appears in the
// transcript rather than being asserted about.
//
// ### THE LENGTH CHECKER DECIDES WHO IS TO BLAME FROM THE MESSAGE ID
//
// HS has ONE length checker where HK has two, and it does HK's job with an `if` instead:
//
//     if (CFE_SB_MsgIdToValue(MessageID) == HS_SEND_HK_MID)   -> HS_HKREQ_LEN_ERR_EID, no count
//     else                                                    -> HS_CMD_LEN_ERR_EID,  CmdErrCount++
//
// NASA's comment states the reasoning: "We only increment the error counter for ground commands
// and not internal messages." Same policy as HK and LC, third implementation of it -- HK used two
// functions, LC one function with three arms, HS one function with a message-id test. So this
// port now records the same requirement expressed three different ways in three apps, and the
// gates compare each against its own upstream rather than against each other.
//
// **AND THE TWO EVENT TEXTS DIFFER ONLY IN THEIR FIRST WORDS**: "Invalid HK request msg length:"
// versus "Invalid msg length:", with identical field lists after. Kept exactly; a ground decoder
// keyed on the prefix is the only thing that can tell them apart besides the event id.
//
// ### THE TWELVE WRAPPERS ARE IDENTICAL AND NONE OF THEM HAS AN `else`
//
// Every one is: take sizeof its own command type, call HS_VerifyMsgLength, call the handler on
// success. **There is no else anywhere**, which is correct here and is NOT how HK does it --
// HK_NoopVerifyDispatch bumps CommandErrorCounter in an `else` because HK_VerifyCmdLength does
// not count for itself. HS_VerifyMsgLength counts inside itself, so an `else` here would double
// count. One policy, two placements, and putting it in the checker is what makes HS's wrappers
// contentless.
//
// They are written out one by one regardless, because the `sizeof` in each names a DIFFERENT
// TYPE -- eleven of which are byte-for-byte identical 8-byte command headers. Collapsing them
// into a table of (code, size, handler) would be smaller and would make every length check
// indistinguishable, which is the one thing these functions exist to keep apart.
//
// ### HS_AppProcessGroundCmd HAS NO PROTOTYPE IN ANY HEADER
//
// It is `void HS_AppProcessGroundCmd(const CFE_SB_Buffer_t *BufPtr)` with external linkage,
// declared nowhere -- not in hs_dispatch.h, not in hs_app.h, not anywhere under fsw/. It is
// defined above its only caller in the same file, so C never needs the declaration. The
// translation declares it below with the rest, which is a difference of FORM only: HolyC needs
// the name in scope, and a forward declaration cannot change linkage the way a `static` one
// would (docs/ records that trap from the cFS stub work).
#ifndef HS_DISPATCH_HC
#define HS_DISPATCH_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// hs_cfg.HC, hs_msg.HC, hs_tbl.HC, hs_global.HC, hs_eventids.HC, hs_utils.HC, hs_sysmon.HC,
// hs_monitors.HC, hs_cmds.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13.

// --- hs_dispatch.h's prototypes, plus the one function NASA declares nowhere ------------------
Bool HS_VerifyMsgLength(CFE_MSG_Message *MsgPtr, I64 ExpectedLength);
U0 HS_AppProcessGroundCmd(CFE_SB_Buffer *BufPtr);
U0 HS_AppPipe(CFE_SB_Buffer *BufPtr);
U0 HS_SendHkVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_NoopVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_ResetVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_EnableAppMonVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_DisableAppMonVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_EnableEventMonVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_DisableEventMonVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_EnableAlivenessVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_DisableAlivenessVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_EnableCpuHogVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_DisableCpuHogVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_ResetResetsPerformedVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HS_SetMaxResetsVerifyDispatch(CFE_SB_Buffer *BufPtr);

/*******************************************************************************/
// Verify a message's length, and decide from its id whether the error is a ground operator's.
// See the file header: one checker doing what HK needs two functions for.
Bool HS_VerifyMsgLength(CFE_MSG_Message *MsgPtr, I64 ExpectedLength)
{
  Bool result = TRUE;
  I64 ActualLength = 0;
  U16 CommandCode = 0;
  CFE_SB_MsgId MessageID;

  MessageID = CFE_SB_InvalidMsgId();

  /*
  ** Verify the message packet length...
  */

  CFE_MSG_GetSize(MsgPtr, &ActualLength);
  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(MsgPtr, &MessageID);
    CFE_MSG_GetFcnCode(MsgPtr, &CommandCode);

    if (CFE_SB_MsgIdToValue(MessageID) == HS_SEND_HK_MID) {
      /*
      ** For a bad HK request, just send the event. We only increment
      ** the error counter for ground commands and not internal messages.
      */
      CFE_EVS_SendEvent(HS_HKREQ_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Invalid HK request msg length: ID = 0x%08lX, CC = %d, Len = %d, Expected = %d",
                        CFE_SB_MsgIdToValue(MessageID), CommandCode, ActualLength, ExpectedLength);
    } else {
      /*
      ** All other cases, increment error counter
      */
      CFE_EVS_SendEvent(HS_CMD_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Invalid msg length: ID = 0x%08lX, CC = %d, Len = %d, Expected = %d",
                        CFE_SB_MsgIdToValue(MessageID), CommandCode, ActualLength, ExpectedLength);
      HS_AppData.CmdErrCount++;
    }

    result = FALSE;
  }

  return result;
}

/*******************************************************************************/
// Route a ground command by its command code. Twelve arms and a default.
U0 HS_AppProcessGroundCmd(CFE_SB_Buffer *BufPtr)
{
  CFE_SB_MsgId MessageID; /* Init to invalid value */
  U16 CommandCode = 0;

  MessageID = CFE_SB_InvalidMsgId();

  CFE_MSG_GetFcnCode(&BufPtr->Msg, &CommandCode);

  switch (CommandCode) {
    case HS_NOOP_CC:
      HS_NoopVerifyDispatch(BufPtr);
      break;

    case HS_RESET_CC:
      HS_ResetVerifyDispatch(BufPtr);
      break;

    case HS_ENABLE_APP_MON_CC:
      HS_EnableAppMonVerifyDispatch(BufPtr);
      break;

    case HS_DISABLE_APP_MON_CC:
      HS_DisableAppMonVerifyDispatch(BufPtr);
      break;

    case HS_ENABLE_EVENT_MON_CC:
      HS_EnableEventMonVerifyDispatch(BufPtr);
      break;

    case HS_DISABLE_EVENT_MON_CC:
      HS_DisableEventMonVerifyDispatch(BufPtr);
      break;

    case HS_ENABLE_ALIVENESS_CC:
      HS_EnableAlivenessVerifyDispatch(BufPtr);
      break;

    case HS_DISABLE_ALIVENESS_CC:
      HS_DisableAlivenessVerifyDispatch(BufPtr);
      break;

    case HS_RESET_RESETS_PERFORMED_CC:
      HS_ResetResetsPerformedVerifyDispatch(BufPtr);
      break;

    case HS_SET_MAX_RESETS_CC:
      HS_SetMaxResetsVerifyDispatch(BufPtr);
      break;

    case HS_ENABLE_CPU_HOG_CC:
      HS_EnableCpuHogVerifyDispatch(BufPtr);
      break;

    case HS_DISABLE_CPU_HOG_CC:
      HS_DisableCpuHogVerifyDispatch(BufPtr);
      break;

    default:
      // UPSTREAM #24: THERE IS NO CFE_MSG_GetMsgId CALL HERE, so MessageID still holds the
      // sentinel its initialiser gave it and the "ID =" field of this event is a constant. HS is
      // the only one of the port's six dispatchers that prints an id it did not read. Kept.
      CFE_EVS_SendEvent(HS_CC_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Invalid command code: ID = 0x%08lX, CC = %d",
                        CFE_SB_MsgIdToValue(MessageID), CommandCode);

      HS_AppData.CmdErrCount++;
      break;

  } /* end CommandCode switch */
}

/*******************************************************************************/
// Route a command-pipe message by its message id. Two known ids and an error arm.
//
// HS'S `else` ARM IS AN ERROR, not data -- unlike HK's and LC's, whose routers end by treating an
// unrecognised id as telemetry to process. HS's command pipe carries only HS_CMD_MID and
// HS_SEND_HK_MID; the event stream arrives on a SEPARATE PIPE that HS_ProcessMain reads with its
// own loop, which is why nothing data-shaped can reach here.
U0 HS_AppPipe(CFE_SB_Buffer *BufPtr)
{
  // NASA initialises both to CFE_SB_MSGID_RESERVED, which is 0, and a HolyC static local is
  // zero-initialised -- the same arrangement HK's, LC's and CS's dispatchers record.
  static CFE_SB_MsgId CMD_MID;
  static CFE_SB_MsgId SEND_HK_MID;

  CFE_SB_MsgId MessageID;

  MessageID = CFE_SB_InvalidMsgId();

  /* cache the local MID Values here, this avoids repeat lookups */
  if (!CFE_SB_IsValidMsgId(CMD_MID)) {
    CMD_MID = CFE_SB_ValueToMsgId(HS_CMD_MID);
    SEND_HK_MID = CFE_SB_ValueToMsgId(HS_SEND_HK_MID);
  }

  CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);

  if (CFE_SB_MsgId_Equal(MessageID, SEND_HK_MID)) {
    /*
    ** Housekeeping telemetry request
    */
    HS_SendHkVerifyDispatch(BufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, CMD_MID)) {
    /*
    ** HS application commands...
    */
    HS_AppProcessGroundCmd(BufPtr);
  } else {
    /*
    ** Unrecognized Message ID
    */
    // COUNTED BEFORE THE EVENT, where HK counts after. No consequence; noted because the two
    // files are otherwise the same shape and a reader comparing them will see it.
    HS_AppData.CmdErrCount++;
    CFE_EVS_SendEvent(HS_MID_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Invalid command pipe message ID: 0x%08lX", CFE_SB_MsgIdToValue(MessageID));
  } /* end MessageID if */
}

/*******************************************************************************/
// The twelve wrappers. Each takes the sizeof ITS OWN command type -- see the file header on why
// eleven identical length checks are eleven functions -- and none has an `else`, because
// HS_VerifyMsgLength counts the error itself.

/*******************************************************************************/
// Housekeeping request. THE ONE WRAPPER WHOSE FAILURE IS NOT COUNTED, and that is decided inside
// HS_VerifyMsgLength by the message id rather than here.
U0 HS_SendHkVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_SendHkCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_SendHkCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 HS_NoopVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_NoopCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_NoopCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 HS_ResetVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_ResetCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_ResetCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 HS_EnableAppMonVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_EnableAppMonCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_EnableAppMonCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 HS_DisableAppMonVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_DisableAppMonCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_DisableAppMonCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 HS_EnableEventMonVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_EnableEventMonCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_EnableEventMonCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 HS_DisableEventMonVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_DisableEventMonCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_DisableEventMonCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 HS_EnableAlivenessVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_EnableAlivenessCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_EnableAlivenessCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 HS_DisableAlivenessVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_DisableAlivenessCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_DisableAlivenessCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 HS_EnableCpuHogVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_EnableCpuHogCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_EnableCpuHogCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 HS_DisableCpuHogVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_DisableCpuHogCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_DisableCpuHogCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 HS_ResetResetsPerformedVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_ResetResetsPerformedCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_ResetResetsPerformedCmd(BufPtr);
  }
}

/*******************************************************************************/
// THE ONLY WRAPPER WHOSE sizeof IS NOT 8: HS_SetMaxResetsCmd_t carries a payload, so this is the
// one length check in the file that can distinguish a correct command from an empty one.
U0 HS_SetMaxResetsVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HS_SetMaxResetsCmd_t);

  /*
  ** Verify message packet length
  */
  if (HS_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    HS_SetMaxResetsCmd(BufPtr);
  }
}

#endif
