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
// LIMIT CHECKER'S DISPATCHER -- the 1:1 translation of NASA's fsw/src/lc_dispatch.c, 362 lines
// and eleven functions. Seven command codes, three message ids, and one `else` arm that is not an
// error.
//
// ### THE `else` ARM IS THE WATCHPOINT PATH, AND NO OTHER APP IN THIS PORT WORKS THAT WAY
//
// MD, MM and CS all end their pipe router with "invalid command pipe message ID" and an error
// counter. LC ends with
//
//     else { LC_CheckMsgForWPs(MessageID, BufPtr); }
//
// because LC subscribes to every MsgId its watchpoint table names, so anything that is not one of
// its own three ids IS data. NASA's comment: "All other message ID's should be monitor packets."
// That inverts the usual default: an unrecognised id here is the normal case, and the diagnostic
// for a genuinely unknown one is LC_MID_INF_EID down in lc_watch.c -- an INFORMATION event, per
// packet.
//
// ### TWO SETS OF STATIC MsgId CACHES IN ONE FILE
//
// LC_AppPipe caches three (CMD_MID, SEND_HK_MID, SAMPLE_AP_MID) and LC_VerifyMsgLength caches two
// of the same three AGAIN, independently, with its own `if (!CFE_SB_IsValidMsgId(...))` fill. So
// this single file holds TWO sets, and with cfe_es_dispatch, cfe_evs_dispatch, cfe_ta_dispatch,
// cfe_sb_dispatch, cfe_tbl_dispatch, cfe_time_dispatch, md_dispatch, mm_dispatch and cs_dispatch
// already in the same translation unit, LC takes the count of distinct `static` locals named
// SEND_HK_MID past ten.
//
// THAT MATTERS BECAUSE OF docs/HOLYC_STRUCT_LIMITS.md #12: a HolyC static local once became a
// GLOBAL under its bare name, and every one of those collided into one variable. It is fixed, and
// this is now the densest test of the fix in the tree -- two caches in one file that must stay
// distinct from each other as well as from nine other files'.
//
// ### AND A BAD LENGTH ON AN INTERNAL MESSAGE IS NOT COUNTED
//
// LC_VerifyMsgLength has three arms for the same failure. A bad HK request and a bad actionpoint
// sample each get their own event id and NO counter increment; everything else gets the generic
// event AND LC_AppData.CmdErrCount++. NASA's comment says why: "We only increment the error
// counter for ground commands and not internal messages."
//
// So a scheduler sending a malformed wakeup forever is visible only as a stream of events, and
// the housekeeping packet's error count stays clean -- which is the right choice for a counter a
// ground operator reads as "how many of MY commands were wrong".
#ifndef LC_DISPATCH_HC
#define LC_DISPATCH_HC

#include "lc_global.HC"
#include "lc_eventids.HC"
#include "lc_cmds.HC"
#include "lc_watch.HC"

/*******************************************************************************/
// Verify a message's length, and charge the error to the ground only if the ground sent it.
//
// THE TWO STATICS ARE ZERO-INITIALISED, which is NASA's CFE_SB_MSGID_RESERVED (0) -- the same
// arrangement every dispatcher in this tree uses, and the guard is on SEND_HK_MID alone so both
// are filled together or not at all.
Bool LC_VerifyMsgLength(CFE_MSG_Message *msgPtr, I64 ExpectedLength)
{
  Bool result = TRUE;
  U16 CommandCode = 0;
  I64 ActualLength = 0;
  CFE_SB_MsgId MsgId = CFE_SB_InvalidMsgId();

  /* Static MID values for efficient comparison */
  static CFE_SB_MsgId SEND_HK_MID;
  static CFE_SB_MsgId SAMPLE_AP_MID;

  /* Cache the local MID Values here, this avoids repeat lookups */
  if (!CFE_SB_IsValidMsgId(SEND_HK_MID)) {
    SEND_HK_MID = CFE_SB_ValueToMsgId(LC_SEND_HK_MID);
    SAMPLE_AP_MID = CFE_SB_ValueToMsgId(LC_SAMPLE_AP_MID);
  }

  CFE_MSG_GetSize(msgPtr, &ActualLength);

  /*
  ** Verify the message packet length...
  */
  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(msgPtr, &MsgId);
    CFE_MSG_GetFcnCode(msgPtr, &CommandCode);

    if (CFE_SB_MsgId_Equal(MsgId, SEND_HK_MID)) {
      /*
      ** For a bad HK request, just send the event. We only increment
      ** the error counter for ground commands and not internal messages.
      */
      CFE_EVS_SendEvent(LC_HKREQ_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Invalid HK request msg length: ID = 0x%08lX, CC = %d, Len = %d, Expected = %d",
                        CFE_SB_MsgIdToValue(MsgId), CommandCode, ActualLength, ExpectedLength);
    } else if (CFE_SB_MsgId_Equal(MsgId, SAMPLE_AP_MID)) {
      /*
      ** Same thing as previous for a bad actionpoint sample request
      */
      CFE_EVS_SendEvent(LC_APSAMPLE_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Invalid AP sample msg length: ID = 0x%08lX, CC = %d, Len = %d, Expected = %d",
                        CFE_SB_MsgIdToValue(MsgId), CommandCode, ActualLength, ExpectedLength);
    } else {
      /*
      ** All other cases, increment error counter
      */
      CFE_EVS_SendEvent(LC_CMD_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Invalid msg length: ID = 0x%08lX, CC = %d, Len = %d, Expected = %d",
                        CFE_SB_MsgIdToValue(MsgId), CommandCode, ActualLength, ExpectedLength);
      LC_AppData.CmdErrCount++;
    }

    result = FALSE;
  }

  return result;
}

/*******************************************************************************/
// NINE VERIFY-AND-DISPATCH WRAPPERS, one per command plus the two internal messages. Each is three
// lines: take the expected length from the command's own TYPE, verify, call. NASA keeps them as
// separate functions rather than folding the length into the switch -- which is what makes each
// command's length a property of its type rather than of the dispatcher, and is why the switch
// below has no sizeof in it at all.
U0 LC_SampleAPVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(LC_SampleAPCmd_t);

  /*
  ** Verify message packet length
  */
  if (LC_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    LC_SampleAPReq(BufPtr);
  }
}

/*******************************************************************************/
// Housekeeping request. NASA's comment on the call site in LC_AppPipe calls this "the only routine
// that can return a critical error indicator" -- LC_SendHkCmd returns LC_PerformMaintenance's
// status -- and this wrapper DISCARDS it, because its own return is void. So a table error that
// LC_PerformMaintenance called fatal reaches no further than here.
U0 LC_SendHkVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(LC_SendHkCmd_t);

  /*
  ** Verify message packet length
  */
  if (LC_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    LC_SendHkCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 LC_NoopVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(LC_NoopCmd_t);

  if (LC_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    LC_NoopCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 LC_ResetCountersVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(LC_ResetCountersCmd_t);

  if (LC_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    LC_ResetCountersCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 LC_SetLCStateVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(LC_SetLCStateCmd_t);

  if (LC_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    LC_SetLCStateCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 LC_SetAPStateVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(LC_SetAPStateCmd_t);

  if (LC_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    LC_SetAPStateCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 LC_SetAPPermOffVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(LC_SetAPPermOffCmd_t);

  if (LC_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    LC_SetAPPermOffCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 LC_ResetAPStatsVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(LC_ResetAPStatsCmd_t);

  if (LC_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    LC_ResetAPStatsCmd(BufPtr);
  }
}

/*******************************************************************************/
U0 LC_ResetWPStatsVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(LC_ResetWPStatsCmd_t);

  if (LC_VerifyMsgLength(&BufPtr->Msg, ExpectedLength)) {
    LC_ResetWPStatsCmd(BufPtr);
  }
}

/*******************************************************************************/
// Process LC ground commands: seven cases and a default.
//
// EVERY ARM IS ONE CALL and the length check lives in the callee, so this switch is purely
// routing. The default arm is the only place in LC that reports an unknown COMMAND CODE -- an
// unknown MESSAGE ID is data, not an error, which is the inversion noted at the top of this file.
U0 LC_AppProcessCmd(CFE_SB_Buffer *BufPtr)
{
  CFE_SB_MsgId MessageID = CFE_SB_InvalidMsgId();
  U16 CommandCode = 0;

  CFE_MSG_GetFcnCode(&BufPtr->Msg, &CommandCode);

  switch (CommandCode) {
    case LC_NOOP_CC:
      LC_NoopVerifyDispatch(BufPtr);
      break;

    case LC_RESET_CC:
      LC_ResetCountersVerifyDispatch(BufPtr);
      break;

    case LC_SET_LC_STATE_CC:
      LC_SetLCStateVerifyDispatch(BufPtr);
      break;

    case LC_SET_AP_STATE_CC:
      LC_SetAPStateVerifyDispatch(BufPtr);
      break;

    case LC_SET_AP_PERM_OFF_CC:
      LC_SetAPPermOffVerifyDispatch(BufPtr);
      break;

    case LC_RESET_AP_STATS_CC:
      LC_ResetAPStatsVerifyDispatch(BufPtr);
      break;

    case LC_RESET_WP_STATS_CC:
      LC_ResetWPStatsVerifyDispatch(BufPtr);
      break;

    default:
      CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);
      CFE_EVS_SendEvent(LC_CC_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Invalid command code: ID = 0x%08lX, CC = %d",
                        CFE_SB_MsgIdToValue(MessageID), CommandCode);
      LC_AppData.CmdErrCount++;
      break;
  }
}

/*******************************************************************************/
// Process one command-pipe message. THREE IDS AND A DEFAULT THAT IS THE DATA PATH.
//
// THE ORDER OF THE THREE TESTS IS SAMPLE_AP FIRST, then SEND_HK, then CMD -- which is the
// frequency order on a real bus, since a scheduler sends the sample request far more often than
// the ground sends anything. The `else` is more frequent still, and costs three comparisons to
// reach.
//
// ITS THREE STATICS ARE A SECOND, INDEPENDENT CACHE from LC_VerifyMsgLength's two. See the note at
// the top of this file for why that is the densest test of HolyC limit #12's fix in the tree.
U0 LC_AppPipe(CFE_SB_Buffer *BufPtr)
{
  static CFE_SB_MsgId CMD_MID;
  static CFE_SB_MsgId SEND_HK_MID;
  static CFE_SB_MsgId SAMPLE_AP_MID;

  CFE_SB_MsgId MessageID = CFE_SB_InvalidMsgId();

  /* Cache the local MID values here, this avoids repeat lookups */
  if (!CFE_SB_IsValidMsgId(CMD_MID)) {
    CMD_MID = CFE_SB_ValueToMsgId(LC_CMD_MID);
    SEND_HK_MID = CFE_SB_ValueToMsgId(LC_SEND_HK_MID);
    SAMPLE_AP_MID = CFE_SB_ValueToMsgId(LC_SAMPLE_AP_MID);
  }

  CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);

  if (CFE_SB_MsgId_Equal(MessageID, SAMPLE_AP_MID)) {
    /*
    ** Sample actionpoints request
    */
    LC_SampleAPVerifyDispatch(BufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, SEND_HK_MID)) {
    /*
    ** Housekeeping telemetry request
    ** (only routine that can return a critical error indicator)
    */
    LC_SendHkVerifyDispatch(BufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, CMD_MID)) {
    /*
    ** LC application commands...
    */
    LC_AppProcessCmd(BufPtr);
  } else {
    /*
    ** All other message ID's should be monitor
    ** packets
    */
    LC_CheckMsgForWPs(MessageID, BufPtr);
  }
}

#endif
