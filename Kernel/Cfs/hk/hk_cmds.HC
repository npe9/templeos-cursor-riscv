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
// HOUSEKEEPING'S FOUR COMMAND HANDLERS -- the 1:1 translation of NASA's fsw/src/hk_cmds.c, 119
// lines. The smallest command file in this port.
//
// ### ONLY ONE OF THE FOUR MOVES A COUNTER, AND IT IS NOT THE ONE YOU WOULD GUESS
//
//   HK_NoopCmd            CommandCounter++        and an INFORMATION event
//   HK_ResetCountersCmd   calls HK_ResetHkData    and an INFORMATION event -- so the counter it
//                         would have bumped is zeroed in the same call
//   HK_SendCombinedPktCmd nothing
//   HK_SendHkCmd          nothing
//
// The two send commands are INTERNAL messages a scheduler issues, not ground commands, so they
// are deliberately not counted -- the same reasoning hk_dispatch.HC records for the two length
// checkers. **So HK's CommandCounter counts exactly the no-op**, and nothing else ever
// increments it. A ground operator watching that counter sees only their own no-ops.
//
// AND HK_ResetCountersCmd DOES NOT BUMP THE COUNTER FIRST. LC's equivalent increments and then
// clears, so the right answer there is zero and a handler that reset first would print one. HK
// never increments at all: HK_ResetHkData is called and then the event is sent. Same observable
// result, different code, and the difference only shows if you look for the increment.
//
// ### HK_SendHkCmd IS WHERE HK'S OWN TELEMETRY AND ITS TABLE MAINTENANCE MEET
//
// It copies five counters into the packet, timestamps, transmits -- and then calls
// HK_CheckStatusOfTables, setting RunStatus to APP_ERROR if that fails. So **a housekeeping
// request is what processes a ground table load**: the copy table a mission uploads does not take
// effect until the next HK request arrives. HK_AppMain's timeout branch does the same thing when
// requests stop coming, which is the belt to this braces.
//
// IT ALSO REPORTS ITS OWN MEMORY POOL HANDLE in the telemetry -- NASA's comment: "Memory pool
// handle used to get mempool diags". That is a resource id rather than an address, so unlike the
// runtime table's OutputPktAddr it IS comparable across the two halves of the differential.
#ifndef HK_CMDS_HC
#define HK_CMDS_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// hk_global.HC, hk_eventids.HC, hk_utils.HC
//
// **THIS UNIT DOES NOT INCLUDE ITS SIBLINGS**, and that is not style -- it is
// docs/HOLYC_STRUCT_LIMITS.md #13. Re-including a guarded file the driver has already read makes
// the compiler skip EVERYTHING AFTER THAT LINE in the including file, with no diagnostic and exit
// status 0. A first draft of this file did include them and check_in_blob caught the result: all
// four functions defined here, every static gate passing, and not one of them in the binary.
//
// The trigger is a `#if` appearing in a COMMENT inside the skipped region, and HK has two of them
// -- hk_cfg.HC and hk_utils.HC both quote NASA's HK_DISCARD_INCOMPLETE_COMBO directive, which is
// the one place in this port where that directive matters enough to write out. So HK is unusually
// exposed to #13 and the workaround is applied here rather than relied on by luck.

// --- hk_cmds.h's prototypes ------------------------------------------------------------------
I32 HK_SendCombinedPktCmd(HK_SendCombinedPktCmd_t *BufPtr);
I32 HK_SendHkCmd(HK_SendHkCmd_t *BufPtr);
I32 HK_NoopCmd(HK_NoopCmd_t *BufPtr);
I32 HK_ResetCountersCmd(HK_ResetCountersCmd_t *BufPtr);

// --- hk_app.h's, which this file calls -------------------------------------------------------
U0 HK_ResetHkData();

/*******************************************************************************/
// Send a combined housekeeping packet: unwrap the payload and hand the MsgId to the engine.
//
// NASA CASTS THE ARGUMENT TO ITS OWN TYPE BEFORE TAKING `.Payload` --
// `&((const HK_SendCombinedPktCmd_t *)BufPtr)->Payload` -- on a parameter that is ALREADY that
// type. A redundant cast, kept, because removing it is a change to NASA's text that no gate
// would see and that would make this handler read differently from the three beside it.
I32 HK_SendCombinedPktCmd(HK_SendCombinedPktCmd_t *BufPtr)
{
  HK_SendCombinedPkt_Payload_t *CmdPtr;

  CmdPtr = &BufPtr->Payload;

  HK_SendCombinedHkPacket(CmdPtr->OutMsgToSend);

  return CFE_SUCCESS;
}

/*******************************************************************************/
// The housekeeping request: HK's own telemetry, and the table maintenance that rides on it.
// See the file header -- this is what makes a ground copy-table load take effect.
I32 HK_SendHkCmd(HK_SendHkCmd_t *BufPtr)
{
  HK_HkTlm_Payload_t *PayloadPtr;

  PayloadPtr = &HK_AppData.HkPacket.Payload;

  /* copy data into housekeeping packet */
  PayloadPtr->CommandCounter = HK_AppData.CommandCounter;
  PayloadPtr->CommandErrorCounter = HK_AppData.CommandErrorCounter;
  PayloadPtr->MissingDataCtr = HK_AppData.MissingDataCtr;
  PayloadPtr->CombinedPacketsSent = HK_AppData.CombinedPacketsSent;
  PayloadPtr->MemPoolHandle = HK_AppData.MemPoolHandle;

  /* Send housekeeping telemetry packet...        */
  // CFE_MSG_PTR(x) is NASA's &x.Msg, written out as it is elsewhere in this port.
  CFE_SB_TimeStampMsg(&HK_AppData.HkPacket.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&HK_AppData.HkPacket.TelemetryHeader.Msg, TRUE);

  /* Check for copy table load and runtime dump request */
  if (HK_CheckStatusOfTables() != HK_SUCCESS) {
    HK_AppData.RunStatus = CFE_ES_RunStatus_APP_ERROR;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// No-op. The ONLY command in HK that increments CommandCounter.
I32 HK_NoopCmd(HK_NoopCmd_t *BufPtr)
{
  CFE_EVS_SendEvent(HK_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "HK No-op command, Version %d.%d.%d.%d", HK_MAJOR_VERSION, HK_MINOR_VERSION,
                    HK_REVISION, HK_MISSION_REV);

  HK_AppData.CommandCounter++;

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Reset counters. It does NOT increment first -- see the file header.
I32 HK_ResetCountersCmd(HK_ResetCountersCmd_t *BufPtr)
{
  HK_ResetHkData();
  CFE_EVS_SendEvent(HK_RESET_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "HK Reset Counters command received");

  return CFE_SUCCESS;
}

#endif
