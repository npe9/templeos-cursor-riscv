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
// HOUSEKEEPING'S DISPATCHER -- the 1:1 translation of NASA's fsw/src/hk_dispatch.c, 242 lines and
// eight functions.
//
// ### HK'S `else` ARM IS DATA, LIKE LC'S -- AND FOR A DIFFERENT REASON
//
// HK_AppPipe ends with
//
//     else { HK_ProcessIncomingHkData(BufPtr); }
//
// so a message that is none of HK's three own ids is a telemetry packet to be combined. LC has
// the same shape (lc_dispatch.HC records it as the only app in the port whose router ends in
// data) and now HK makes two -- but the reason differs in a way worth stating. LC subscribes to
// the ids its WATCHPOINT TABLE names, so an unknown id is a configuration error it reports with
// LC_MID_INF_EID. HK subscribes to the ids its COPY TABLE names, and HK_ProcessIncomingHkData
// sends **no event at all** when nothing matches -- it is a silent walk of 128 entries.
//
// SO AN UNSUBSCRIBED PACKET ARRIVING AT HK IS INVISIBLE. There is no counter and no event; the
// only trace is the CPU spent on the walk. That is a deliberate difference from LC and it is why
// the dispatch exercise asserts on HK's COUNTERS not moving rather than on an event appearing.
//
// ### TWO LENGTH CHECKERS, AND THE DIFFERENCE IS WHO GETS BLAMED
//
// HK_VerifyCmdLength and HK_VerifyMsgLength do the same comparison and differ in three ways:
//
//                          event id            prints CC?   caller counts the error?
//   HK_VerifyCmdLength     HK_CMD_LEN_ERR_EID  yes          YES, in the wrapper
//   HK_VerifyMsgLength     HK_MSG_LEN_ERR_EID  no           no
//
// A GROUND COMMAND gets HK_VerifyCmdLength and its wrapper bumps CommandErrorCounter in the
// `else`; an INTERNAL message (the housekeeping request and the send-combined-packet request,
// both sent by a scheduler) gets HK_VerifyMsgLength and nothing is counted. The reasoning is LC's
// -- a counter a ground operator reads as "how many of MY commands were wrong" should not move
// because a scheduler is misconfigured -- but HK implements it with TWO FUNCTIONS where LC used
// one function with three arms.
//
// AND HK_VerifyMsgLength'S EVENT USES %u WHERE HK_VerifyCmdLength'S USES %d for the same two
// numbers. Both are kept exactly: the lengths are a size_t cast to `unsigned int` in one and to
// `int` in the other, in adjacent functions, and harmonising them is the 1:1 violation
// docs/ records as the %u/%d drift that only a text gate can see.
//
// ### THE SEND-COMBINED-PACKET COMMAND IS NOT COUNTED EITHER WAY
//
// HK_SendCombinedPktVerifyDispatch and HK_SendHkVerifyDispatch have NO `else`. A bad length on
// either produces the event and nothing more -- not even an error counter -- while
// HK_NoopVerifyDispatch and HK_ResetCountersVerifyDispatch both have one. So of HK's four
// dispatch wrappers, exactly the two that handle internal messages are silent about failure.
#ifndef HK_DISPATCH_HC
#define HK_DISPATCH_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// hk_global.HC, hk_eventids.HC, hk_utils.HC, hk_cmds.HC
//
// **THIS UNIT DOES NOT INCLUDE ITS SIBLINGS**, and that is not style -- it is
// docs/HOLYC_STRUCT_LIMITS.md #13. Re-including a guarded file the driver has already read makes
// the compiler skip EVERYTHING AFTER THAT LINE in the including file, with no diagnostic and exit
// status 0. A first draft of this file did include them and check_in_blob caught the result: all
// eight functions defined here, every static gate passing, and not one of them in the binary.
//
// The trigger is a `#if` appearing in a COMMENT inside the skipped region, and HK has two of them
// -- hk_cfg.HC and hk_utils.HC both quote NASA's HK_DISCARD_INCOMPLETE_COMBO directive, which is
// the one place in this port where that directive matters enough to write out. So HK is unusually
// exposed to #13 and the workaround is applied here rather than relied on by luck.

// --- hk_dispatch.h's prototypes --------------------------------------------------------------
I32 HK_VerifyCmdLength(CFE_SB_Buffer *BufPtr, I64 ExpectedLength);
I32 HK_VerifyMsgLength(CFE_SB_Buffer *BufPtr, I64 ExpectedLength);
U0 HK_SendCombinedPktVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HK_SendHkVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HK_NoopVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HK_ResetCountersVerifyDispatch(CFE_SB_Buffer *BufPtr);
U0 HK_AppProcessCmd(CFE_SB_Buffer *BufPtr);
U0 HK_AppPipe(CFE_SB_Buffer *BufPtr);

// --- hk_cmds.h's, which this file calls ------------------------------------------------------
I32 HK_SendCombinedPktCmd(HK_SendCombinedPktCmd_t *BufPtr);
I32 HK_SendHkCmd(HK_SendHkCmd_t *BufPtr);
I32 HK_NoopCmd(HK_NoopCmd_t *BufPtr);
I32 HK_ResetCountersCmd(HK_ResetCountersCmd_t *BufPtr);

/*******************************************************************************/
// Verify a GROUND COMMAND's length. The event prints the command code; the caller counts the
// error. See the file header for the three ways this differs from HK_VerifyMsgLength.
I32 HK_VerifyCmdLength(CFE_SB_Buffer *BufPtr, I64 ExpectedLength)
{
  I32 Status = HK_SUCCESS;
  CFE_SB_MsgId MessageID;
  U16 CommandCode = 0;
  I64 ActualLength = 0;

  MessageID = CFE_SB_InvalidMsgId(); /* Init to invalid value */

  CFE_MSG_GetSize(&BufPtr->Msg, &ActualLength);

  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);
    CFE_MSG_GetFcnCode(&BufPtr->Msg, &CommandCode);

    CFE_EVS_SendEvent(HK_CMD_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Cmd Msg with Bad length Rcvd: ID = 0x%08lX, CC = %d, Exp Len = %d, Len = %d",
                      CFE_SB_MsgIdToValue(MessageID), CommandCode, ExpectedLength, ActualLength);

    Status = HK_BAD_MSG_LENGTH_RC;
  }

  return Status;
}

/*******************************************************************************/
// Verify an INTERNAL message's length. No command code in the event, no counter, and the two
// lengths print with %u where the command version uses %d -- NASA's own inconsistency, kept.
I32 HK_VerifyMsgLength(CFE_SB_Buffer *BufPtr, I64 ExpectedLength)
{
  I32 Status = HK_SUCCESS;
  CFE_SB_MsgId MessageID;
  I64 ActualLength = 0;

  MessageID = CFE_SB_InvalidMsgId(); /* Init to invalid value */

  CFE_MSG_GetSize(&BufPtr->Msg, &ActualLength);

  if (ExpectedLength != ActualLength) {
    CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);

    CFE_EVS_SendEvent(HK_MSG_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Msg with Bad length Rcvd: ID = 0x%08lX, Exp Len = %u, Len = %u",
                      CFE_SB_MsgIdToValue(MessageID), ExpectedLength, ActualLength);

    Status = HK_BAD_MSG_LENGTH_RC;
  }

  return Status;
}

/*******************************************************************************/
// Send a combined housekeeping packet. NO `else`: a bad length is the event and nothing else.
U0 HK_SendCombinedPktVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  if (HK_VerifyMsgLength(BufPtr, sizeof(HK_SendCombinedPktCmd_t)) == HK_SUCCESS) {
    HK_SendCombinedPktCmd(BufPtr);
  }
}

/*******************************************************************************/
// The housekeeping request. Also no `else`.
U0 HK_SendHkVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  if (HK_VerifyMsgLength(BufPtr, sizeof(HK_SendHkCmd_t)) == HK_SUCCESS) {
    HK_SendHkCmd(BufPtr);
  }
}

/*******************************************************************************/
// No-op. THIS one has the `else` that counts the error, because it is a ground command.
U0 HK_NoopVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HK_NoopCmd_t);

  if (HK_VerifyCmdLength(BufPtr, ExpectedLength) == HK_SUCCESS) {
    HK_NoopCmd(BufPtr);
  } else {
    HK_AppData.CommandErrorCounter++;
  }
}

/*******************************************************************************/
// Reset counters. Same shape as the no-op.
U0 HK_ResetCountersVerifyDispatch(CFE_SB_Buffer *BufPtr)
{
  I64 ExpectedLength = sizeof(HK_ResetCountersCmd_t);

  if (HK_VerifyCmdLength(BufPtr, ExpectedLength) == HK_SUCCESS) {
    HK_ResetCountersCmd(BufPtr);
  } else {
    HK_AppData.CommandErrorCounter++;
  }
}

/*******************************************************************************/
// Route a ground command by its function code.
//
// TWO ARMS AND A `default:`, AND HK_NOOP_CC IS **ZERO** -- so a zero-filled buffer routes to the
// no-op rather than to the error arm. Every other app in this port has enough command codes that
// a stray zero lands on a real handler too, but HK is the first where the switch is small enough
// to make that obvious: reaching `default:` at all requires setting the function code on purpose.
U0 HK_AppProcessCmd(CFE_SB_Buffer *BufPtr)
{
  CFE_SB_MsgId MessageID;
  U16 CommandCode = 0;

  MessageID = CFE_SB_InvalidMsgId(); /* Init to invalid value */

  CFE_MSG_GetFcnCode(&BufPtr->Msg, &CommandCode);

  switch (CommandCode) {
    case HK_NOOP_CC:
      HK_NoopVerifyDispatch(BufPtr);
      break;

    case HK_RESET_COUNTERS_CC:
      HK_ResetCountersVerifyDispatch(BufPtr);
      break;

    default:
      CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);
      CFE_EVS_SendEvent(HK_CC_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Cmd Msg with Invalid command code Rcvd -- ID = 0x%08lX, CC = %d",
                        CFE_SB_MsgIdToValue(MessageID), CommandCode);
      HK_AppData.CommandErrorCounter++;
      break;
  }
}

/*******************************************************************************/
// Route a pipe message by its message id. The `else` arm is DATA -- see the file header.
//
// THREE STATIC MsgId CACHES, filled on the first call. The same pattern lc_dispatch.c uses twice
// in one file; here there is one set, and with cfe_es_dispatch, cfe_evs_dispatch, cfe_ta_dispatch,
// cfe_sb_dispatch, cfe_tbl_dispatch, cfe_time_dispatch, md_dispatch, mm_dispatch, cs_dispatch and
// lc_dispatch already in this translation unit, HK takes the count of distinct `static` locals
// named SEND_HK_MID past eleven -- which docs/HOLYC_STRUCT_LIMITS.md #12 makes worth counting,
// because a static local once became a GLOBAL under its bare name and every one of those
// collided into a single variable. Fixed, and this is now the densest test of the fix.
U0 HK_AppPipe(CFE_SB_Buffer *BufPtr)
{
  // NASA initialises all three to CFE_SB_MSGID_RESERVED, which is 0, and a HolyC static local is
  // zero-initialised -- the same arrangement every cFE dispatcher in this port records.
  static CFE_SB_MsgId CMD_MID;
  static CFE_SB_MsgId SEND_HK_MID;
  static CFE_SB_MsgId SEND_COMBINED_PKT_MID;

  CFE_SB_MsgId MessageID;

  MessageID = CFE_SB_InvalidMsgId();

  /* cache the local MID Values here, this avoids repeat lookups */
  if (!CFE_SB_IsValidMsgId(CMD_MID)) {
    CMD_MID = CFE_SB_ValueToMsgId(HK_CMD_MID);
    SEND_HK_MID = CFE_SB_ValueToMsgId(HK_SEND_HK_MID);
    SEND_COMBINED_PKT_MID = CFE_SB_ValueToMsgId(HK_SEND_COMBINED_PKT_MID);
  }

  CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);

  if (CFE_SB_MsgId_Equal(MessageID, SEND_HK_MID)) {
    /* Send out HK's housekeeping data */
    HK_SendHkVerifyDispatch(BufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, SEND_COMBINED_PKT_MID)) {
    HK_SendCombinedPktVerifyDispatch(BufPtr);
  } else if (CFE_SB_MsgId_Equal(MessageID, CMD_MID)) {
    /*
    ** HK application commands...
    */
    HK_AppProcessCmd(BufPtr);
  } else {
    /* Incoming housekeeping data from other Subsystems...       */
    HK_ProcessIncomingHkData(BufPtr);
  }
}

#endif
