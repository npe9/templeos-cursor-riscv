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
// LIMIT CHECKER'S MISSION-SPECIFIC CODE -- the 1:1 translation of NASA's fsw/src/lc_custom.c.
// Two functions, 96 lines, and it is the first LC source because nothing in LC calls into it
// except through a table value.
//
// ### THIS FILE IS A TEMPLATE, AND TRANSLATING A TEMPLATE 1:1 MEANS KEEPING ITS EMPTINESS
//
// NASA's header calls this "mission specific code, including the custom function template".
// LC_CustomFunction is the entry point for every watchpoint whose OperatorID is LC_OPER_CUSTOM,
// and NASA's body is a switch whose THREE LABELS ALL FALL INTO ONE ARM:
//
//     case 0x0000:
//     case 0x0001:
//     default:
//         CFE_EVS_SendEvent(LC_CFCALL_ERR_EID, ... "Unexpected LC_CustomFunction call: WP = %d");
//
// so the two numbered cases are DEAD LABELS -- every watchpoint index, including 0 and 1, reaches
// the same error event and the function returns LC_WATCH_FALSE. That is not a defect: it is a stub
// a mission replaces, and the two labels are there to show where. Kept exactly, because a
// translation that "tidied" the switch into an unconditional event would delete the instruction.
//
// A CONSEQUENCE FOR THE EXERCISE, WORTH STATING NOW: a custom watchpoint can only ever evaluate
// FALSE in this configuration, so every LC_OPER_CUSTOM path through lc_watch.c ends in one event
// and one result. There is no way to drive a custom operator to TRUE without writing mission code,
// which this port does not have and must not invent.
//
// ### AND LC_ExecuteRTS IS THE FIRST TIME AN APP IN THIS PORT COMMANDS ANOTHER APP
//
// MD read memory, MM wrote it, CS checksummed it -- all three only ever REPORTED. LC_ExecuteRTS
// builds a command and transmits it to LC_RTS_REQ_MID, which is Stored Command's pipe, with
// LC_RTS_REQ_CC as the function code. Both are INTERFACE configuration (lc_cfg.HC) rather than
// internal, because they name a different application's command and a mission that renumbers SC
// has to retarget LC.
//
// NOTE WHAT IT DOES **NOT** DO: it does not check the return of CFE_SB_TransmitMsg, and it returns
// void. So a transmit that fails -- no subscriber, a full pipe -- is invisible to LC, and the
// actionpoint that fired still counts a successful RTS execution in RTSExecCount. NASA's, and the
// shape docs/ records as "a return value saying I handled it is not evidence output was emitted":
// here there is not even a return value to ignore.
#ifndef LC_CUSTOM_HC
#define LC_CUSTOM_HC

#include "lc_tbldefs.HC"
#include "lc_eventids.HC"
#include "lc_msg.HC"

/*******************************************************************************/
// Initiate an RTS request.
//
// `sizeof(RTSRequest)` IS WRITTEN AS `sizeof(LC_RTSRequestCmd_t)` -- the same substitution every
// app in this port makes, because docs/HOLYC_STRUCT_LIMITS.md #16 records that `sizeof` through a
// local's name resolves differently from the type's. The two are the same 12 bytes and the type is
// what CFE_MSG_Init needs to be told.
U0 LC_ExecuteRTS(U16 RTSId)
{
  LC_RTSRequestCmd_t RTSRequest;

  MemSet(&RTSRequest, 0, sizeof(LC_RTSRequestCmd_t));

  CFE_MSG_Init(&RTSRequest.CommandHeader.Msg, CFE_SB_ValueToMsgId(LC_RTS_REQ_MID),
               sizeof(LC_RTSRequestCmd_t));
  CFE_MSG_SetFcnCode(&RTSRequest.CommandHeader.Msg, LC_RTS_REQ_CC);

  RTSRequest.Payload.RTSId = RTSId;

  CFE_SB_TransmitMsg(&RTSRequest.CommandHeader.Msg, TRUE);

  return;
}

/*******************************************************************************/
// Mission specific custom function entry point.
//
// THE THREE LABELS ARE NASA'S AND TWO OF THEM ARE DEAD. See the note at the top of this file: this
// is a template, the numbered cases mark where a mission puts its watchpoint, and every index
// reaches the same event today.
//
// THREE OF THE FOUR PARAMETERS ARE UNUSED, which is also NASA's: ProcessedWPData is the value LC
// already read and masked out of the packet, BufPtr is the whole message in case a mission needs
// more of it, and WDTCustomFuncArg is the per-watchpoint argument from the definition table --
// NASA's comment offers it as an alternative to switching on WatchIndex. All three are here so a
// mission filling this in has them, and so check_signatures compares four parameters against
// NASA's four.
U8 LC_CustomFunction(U16 WatchIndex, U32 ProcessedWPData, CFE_SB_Buffer *BufPtr,
                     U32 WDTCustomFuncArg)
{
  U8 EvalResult = LC_WATCH_FALSE;

  /*
  ** This function is the entry point for all watchpoints where
  ** the OperatorID in the watchpoint definition table entry
  ** is set to LC_OPER_CUSTOM.
  **
  ** For this reason The first step would normally be to
  ** switch on the WatchIndex to figure out what watchpoint got
  ** us here. As an alternate, a mission may choose to use the
  ** WDTCustomFuncArg for this instead.
  */
  switch (WatchIndex) {
    case 0x0000:
    case 0x0001:
    default:
      CFE_EVS_SendEvent(LC_CFCALL_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Unexpected LC_CustomFunction call: WP = %d", WatchIndex);
      break;
  } // end WatchIndex switch

  return EvalResult;
}

#endif
