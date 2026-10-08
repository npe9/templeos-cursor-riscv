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
// LIMIT CHECKER'S COMMANDS -- the 1:1 translation of NASA's fsw/src/lc_cmds.c, 691 lines and
// twelve functions. The other half of LC's only call cycle: this file calls
// LC_PerformMaintenance in lc_utils.c, which calls LC_ResetResultsAP and LC_ResetResultsWP here.
//
// ### THE HOUSEKEEPING PACKER IS THE DENSEST CODE IN LC
//
// LC_SendHkCmd packs 176 watchpoint results at TWO BITS each and 176 actionpoint
// state-and-result pairs at FOUR BITS each, and both loops pack in REVERSE INDEX ORDER within a
// byte:
//
//   watchpoints    Shift = 6 - (i * 2) for i in 0..3, index TableIndex + 3 - i
//                  so WP TableIndex+3 lands in bits 7-6 and TableIndex+0 in bits 1-0
//   actionpoints   Shift = 6 - (i * 4) for i in 0..1, index TableIndex + 1 - i, then Shift -= 2
//                  so AP TableIndex+1 takes bits 7-4 (state 7-6, result 5-4) and +0 takes 3-0
//
// THE PACKED CODES ARE NOT THE TABLE VALUES. LC_WATCH_STALE is 0xFF in a results-table entry and
// LC_HKWR_STALE is 0x03 in the packet, so every arm is a translation; a `default:` maps anything
// unexpected to the ERROR code rather than passing it through. LC_APSTATE_PERMOFF and
// LC_APSTATE_NOT_USED both map to LC_HKAR_STATE_NOT_USED, which NASA says in a comment --
// "Permanantly disabled actionpoints get reported as unused" -- so a ground display cannot tell
// those two apart from this packet alone.
//
// AND ActiveAPs IS COUNTED AS A SIDE EFFECT OF THE PACKING LOOP: it is zeroed before, and
// incremented only in the LC_APSTATE_ACTIVE arm. So the count and the packed bytes cannot
// disagree, which is worth more than a separate pass would be.
//
// ### ResetStatsCmd INVERTS THE SENSE ITS NAME SUGGESTS
//
// LC_ResetResultsAP and LC_ResetResultsWP take `bool ResetStatsCmd`, and when it is TRUE -- i.e.
// this IS a reset-statistics command -- they do NOT touch the live state or the most recent
// result. NASA's comments say it plainly: "reset AP stats command does not modify AP state or most
// recent test result". The FALSE case is a table reload, which resets everything including the
// state back to the definition table's DefaultState.
//
// So the flag means "preserve what is live", and the two callers are a ground command (TRUE) and
// LC_ManageTables after a new table load (FALSE).
#ifndef LC_CMDS_HC
#define LC_CMDS_HC

#include "lc_global.HC"
#include "lc_eventids.HC"
#include "lc_action.HC"
#include "lc_watch.HC"
#include "lc_utils.HC"

// NASA's macro. It exists to cast a raw buffer pointer to the right command type and take its
// payload's address in one step; HolyC's casts relabel, so the same expression works.
#define LC_GET_CMD_PAYLOAD(ptr, type) (&(ptr)(type *)->Payload)

// Called downwards within this file.
U0 LC_ResetCounters();

/*******************************************************************************/
// Sample actionpoints request -- LC's clock, sent by a scheduler.
//
// THE "SAMPLE ALL" WILDCARD IS A PAIR, not a single value: both StartIndex and EndIndex must be
// LC_ALL_ACTIONPOINTS. NASA calls it "special heritage values". Anything else is a range, checked
// as start <= end AND end < LC_MAX_ACTIONPOINTS -- so a start beyond the table is caught only
// through end, which must be >= start.
//
// AND UpdateAge IS WHAT MAKES A RESULT GO STALE. The ageing loop runs over ALL 176 watchpoints
// regardless of which actionpoints were sampled, decrements each non-zero CountdownToStale, and
// marks the result STALE on the transition to zero. So staleness is driven by how often this
// command arrives, not by the clock -- a watchpoint whose packet stopped arriving ages out only
// while something keeps sampling.
//
// IT IS ALSO GATED ON ValidSampleCmd, so a sample command with a bad range ages nothing. The two
// effects are deliberately coupled.
U0 LC_SampleAPReq(CFE_SB_Buffer *BufPtr)
{
  LC_SampleAP_Payload_t *LC_SampleAP;
  U16 WatchIndex;
  Bool ValidSampleCmd = FALSE;

  LC_SampleAP = LC_GET_CMD_PAYLOAD(BufPtr, LC_SampleAPCmd_t);

  /*
  ** Ignore AP sample requests if disabled at the application level
  */
  if (LC_AppData.CurrentLCState != LC_STATE_DISABLED) {
    /*
    ** Range check the actionpoint array index arguments
    */
    if (LC_SampleAP->StartIndex == LC_ALL_ACTIONPOINTS &&
        LC_SampleAP->EndIndex == LC_ALL_ACTIONPOINTS) {
      /*
      ** Allow special "sample all" heritage values
      */
      LC_SampleAPs(0, LC_MAX_ACTIONPOINTS - 1);
      ValidSampleCmd = TRUE;
    } else if (LC_SampleAP->StartIndex <= LC_SampleAP->EndIndex &&
               LC_SampleAP->EndIndex < LC_MAX_ACTIONPOINTS) {
      /*
      ** Start is less or equal to end, and end is within the array
      */
      LC_SampleAPs(LC_SampleAP->StartIndex, LC_SampleAP->EndIndex);
      ValidSampleCmd = TRUE;
    } else {
      /*
      ** At least one actionpoint array index is out of range
      */
      CFE_EVS_SendEvent(LC_APSAMPLE_APNUM_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Sample AP error: invalid AP number, start = %d, end = %d",
                        LC_SampleAP->StartIndex, LC_SampleAP->EndIndex);
    }

    /*
    ** Optionally update the age of watchpoint results
    */
    if (LC_SampleAP->UpdateAge != 0 && ValidSampleCmd) {
      for (WatchIndex = 0; WatchIndex < LC_MAX_WATCHPOINTS; WatchIndex++) {
        if (LC_OperData.WRTPtr[WatchIndex].CountdownToStale > 0) {
          LC_OperData.WRTPtr[WatchIndex].CountdownToStale--;

          if (LC_OperData.WRTPtr[WatchIndex].CountdownToStale == 0) {
            LC_OperData.WRTPtr[WatchIndex].WatchResult = LC_WATCH_STALE;
          }
        }
      }
    }
  }
}

/*******************************************************************************/
// Housekeeping request: fill the packet, send it, then do the background maintenance.
//
// IT RETURNS LC_PerformMaintenance()'s STATUS, so the housekeeping command is also how LC's
// tables get managed and its CDS written -- and a table error on that path becomes this command's
// return value. See the note at the top of this file for the bit packing.
I32 LC_SendHkCmd(LC_SendHkCmd_t *msg)
{
  U16 TableIndex;
  U16 HKIndex;
  U8 ByteData = 0;
  U8 Shift;
  U8 TempByteData;
  U8 i;

  LC_HkTlm_Payload_t *PayloadPtr;

  /* Update HK variables */
  PayloadPtr = &LC_OperData.HkPacket.Payload;

  PayloadPtr->CmdCount = LC_AppData.CmdCount;
  PayloadPtr->CmdErrCount = LC_AppData.CmdErrCount;
  PayloadPtr->APSampleCount = LC_AppData.APSampleCount;
  PayloadPtr->MonitoredMsgCount = LC_AppData.MonitoredMsgCount;
  PayloadPtr->RTSExecCount = LC_AppData.RTSExecCount;
  PayloadPtr->PassiveRTSExecCount = LC_AppData.PassiveRTSExecCount;
  PayloadPtr->CurrentLCState = LC_AppData.CurrentLCState;
  PayloadPtr->WPsInUse = LC_OperData.WatchpointCount;

  /* Clear out the active actionpoint count, it will get recomputed below */
  PayloadPtr->ActiveAPs = 0;

  /* Update packed watch results (4 watch results in one 8-bit byte) */
  for (TableIndex = 0; TableIndex < LC_MAX_WATCHPOINTS; TableIndex += 4) {
    HKIndex = TableIndex / 4;

    /* Pack in the results 2-bits at a time to ByteData */
    for (i = 0; i < 4; i++) {
      Shift = 6 - (i * 2);
      switch (LC_OperData.WRTPtr[TableIndex + 3 - i].WatchResult) {
        case LC_WATCH_STALE:
          TempByteData = LC_HKWR_STALE << Shift;
          break;

        case LC_WATCH_FALSE:
          TempByteData = LC_HKWR_FALSE << Shift;
          break;

        case LC_WATCH_TRUE:
          TempByteData = LC_HKWR_TRUE << Shift;
          break;

        /* We should never get an undefined watch result, but set an error result if we do */
        case LC_WATCH_ERROR:
        default:
          TempByteData = LC_HKWR_ERROR << Shift;
          break;
      }

      /* Directly assign 1st result, but logical OR the 2nd, 3rd and 4th results */
      if (i == 0)
        ByteData = TempByteData;
      else
        ByteData |= TempByteData;
    }

    /* Update housekeeping watch results array */
    PayloadPtr->WPResults[HKIndex] = ByteData;
  }

  /* Update packed action results (2 action state/result pairs (4 bits each) in one 8-bit byte) */
  for (TableIndex = 0; TableIndex < LC_MAX_ACTIONPOINTS; TableIndex += 2) {
    HKIndex = TableIndex / 2;

    /* Pack in 1st and 2nd actionpoints, current state */
    for (i = 0; i < 2; i++) {
      Shift = 6 - (i * 4);
      switch (LC_OperData.ARTPtr[TableIndex + 1 - i].CurrentState) {
        case LC_APSTATE_NOT_USED:
          TempByteData = LC_HKAR_STATE_NOT_USED << Shift;
          break;

        case LC_APSTATE_ACTIVE:
          TempByteData = LC_HKAR_STATE_ACTIVE << Shift;
          PayloadPtr->ActiveAPs++;
          break;

        case LC_APSTATE_PASSIVE:
          TempByteData = LC_HKAR_STATE_PASSIVE << Shift;
          break;

        case LC_APSTATE_DISABLED:
          TempByteData = LC_HKAR_STATE_DISABLED << Shift;
          break;

        /*
        ** Permanantly disabled actionpoints get reported as unused. We should
        ** never get an undefined action state, but set to NOT_USED if we do.
        */
        case LC_APSTATE_PERMOFF:
        default:
          TempByteData = LC_HKAR_STATE_NOT_USED << Shift;
          break;
      }

      /* Directly assign 1st state, but logical OR the 2nd state */
      if (i == 0)
        ByteData = TempByteData;
      else
        ByteData |= TempByteData;

      /* Pack in 1st and 2nd actionpoints, action result */
      Shift -= 2;
      switch (LC_OperData.ARTPtr[TableIndex + 1 - i].ActionResult) {
        case LC_ACTION_STALE:
          ByteData |= LC_HKAR_STALE << Shift;
          break;

        case LC_ACTION_PASS:
          ByteData |= LC_HKAR_PASS << Shift;
          break;

        case LC_ACTION_FAIL:
          ByteData |= LC_HKAR_FAIL << Shift;
          break;

        /* We should never get an undefined action result, but set an error result if we do */
        case LC_ACTION_ERROR:
        default:
          ByteData |= LC_HKAR_ERROR << Shift;
          break;
      }
    }

    /* Update housekeeping action results array */
    PayloadPtr->APResults[HKIndex] = ByteData;
  }

  /* Timestamp and send housekeeping packet */
  CFE_SB_TimeStampMsg(&LC_OperData.HkPacket.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&LC_OperData.HkPacket.TelemetryHeader.Msg, TRUE);

  return LC_PerformMaintenance();
}

/*******************************************************************************/
// No-op, which answers with the version. The only place LC's four build numbers appear.
I32 LC_NoopCmd(LC_NoopCmd_t *msg)
{
  LC_AppData.CmdCount++;

  CFE_EVS_SendEvent(LC_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "No-op command: Version %d.%d.%d.%d", LC_MAJOR_VERSION, LC_MINOR_VERSION,
                    LC_REVISION, LC_MISSION_REV);

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Reset counters command.
//
// IT DOES INCREMENT NOTHING AND IT DOES NOT ZERO CmdCount AFTER THE EVENT -- the helper zeroes
// both counters and the command does not bump CmdCount afterwards, so the count after a reset is
// zero rather than one. CS's equivalent has the same property and NASA's reason is the same: the
// reset's own command should not appear in the count it just cleared.
I32 LC_ResetCountersCmd(LC_ResetCountersCmd_t *msg)
{
  LC_ResetCounters();

  CFE_EVS_SendEvent(LC_RESET_INF_EID, CFE_EVS_EventType_INFORMATION, "Reset counters command");

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Zero the six housekeeping counters. NOT the watchpoint or actionpoint statistics, which have
// their own commands, and NOT CurrentLCState.
U0 LC_ResetCounters()
{
  LC_AppData.CmdCount = 0;
  LC_AppData.CmdErrCount = 0;

  LC_AppData.APSampleCount = 0;
  LC_AppData.MonitoredMsgCount = 0;
  LC_AppData.RTSExecCount = 0;
  LC_AppData.PassiveRTSExecCount = 0;
}

/*******************************************************************************/
// Set the application's state.
//
// LC_STATE_FROM_CDS IS NOT ACCEPTED, which is the point of it being a separate value: it is what
// LC_STATE_WHEN_CDS_RESTORED can be configured to, meaning "whatever the CDS said", and
// lc_tbldefs.h calls it "Used for reset processing, not valid state". So the switch lists the
// three real states and everything else -- including FROM_CDS -- is an error.
I32 LC_SetLCStateCmd(LC_SetLCStateCmd_t *msg)
{
  LC_SetLCState_Payload_t *CmdPtr = &msg->Payload;

  switch (CmdPtr->NewLCState) {
    case LC_STATE_ACTIVE:
    case LC_STATE_PASSIVE:
    case LC_STATE_DISABLED:
      LC_AppData.CurrentLCState = CmdPtr->NewLCState;
      LC_AppData.CmdCount++;

      CFE_EVS_SendEvent(LC_LCSTATE_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Set LC state command: new state = %d", CmdPtr->NewLCState);
      break;

    default:
      CFE_EVS_SendEvent(LC_LCSTATE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Set LC state error: invalid state = %d", CmdPtr->NewLCState);

      LC_AppData.CmdErrCount++;
      break;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Set one actionpoint's state, or all of them.
//
// AN UNUSED OR PERMANENTLY-OFF ACTIONPOINT CANNOT BE COMMANDED, and NASA says why: they "can only
// be changed by a table load". The single-index path reports that as an error; the ALL path
// silently SKIPS them.
//
// AND THE ALL PATH ALWAYS REPORTS SUCCESS. `CmdSuccess = TRUE` is unconditional there, so a
// "set all actionpoints active" against a table where every entry is unused still increments
// CmdCount and sends the success event having changed nothing. NASA's, and the asymmetry with the
// single-index path -- which checks before claiming -- is worth noticing rather than smoothing.
I32 LC_SetAPStateCmd(LC_SetAPStateCmd_t *msg)
{
  LC_SetAPState_Payload_t *CmdPtr = &msg->Payload;
  U32 TableIndex;
  U8 CurrentAPState;
  Bool ValidState = TRUE;
  Bool CmdSuccess = FALSE;

  /*
  ** Do a sanity check on the new actionpoint state
  ** specified.
  */
  switch (CmdPtr->NewAPState) {
    case LC_APSTATE_ACTIVE:
    case LC_APSTATE_PASSIVE:
    case LC_APSTATE_DISABLED:
      break;

    default:
      ValidState = FALSE;
      CFE_EVS_SendEvent(LC_APSTATE_NEW_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Set AP state error: AP = %d, Invalid new state = %d", CmdPtr->APNumber,
                        CmdPtr->NewAPState);

      LC_AppData.CmdErrCount++;
      break;
  }

  /*
  ** Do the rest based on the actionpoint ID we were given
  */
  if (ValidState == TRUE) {
    if (CmdPtr->APNumber == LC_ALL_ACTIONPOINTS) {
      /*
      ** Set all actionpoints to the new state except those that are not
      ** used or set permanently off
      */
      for (TableIndex = 0; TableIndex < LC_MAX_ACTIONPOINTS; TableIndex++) {
        CurrentAPState = LC_OperData.ARTPtr[TableIndex].CurrentState;

        if (CurrentAPState != LC_APSTATE_NOT_USED && CurrentAPState != LC_APSTATE_PERMOFF) {
          LC_OperData.ARTPtr[TableIndex].CurrentState = CmdPtr->NewAPState;
        }
      }

      /*
      ** Set flag that we succeeded
      */
      CmdSuccess = TRUE;
    } else {
      if (CmdPtr->APNumber < LC_MAX_ACTIONPOINTS) {
        TableIndex = CmdPtr->APNumber;
        CurrentAPState = LC_OperData.ARTPtr[TableIndex].CurrentState;

        if (CurrentAPState != LC_APSTATE_NOT_USED && CurrentAPState != LC_APSTATE_PERMOFF) {
          /*
          ** Update state for single actionpoint specified
          */
          LC_OperData.ARTPtr[TableIndex].CurrentState = CmdPtr->NewAPState;

          CmdSuccess = TRUE;
        } else {
          /*
          ** Actionpoints that are not used or set permanently
          ** off can only be changed by a table load
          */
          CFE_EVS_SendEvent(LC_APSTATE_CURR_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Set AP state error: AP = %d, Invalid current AP state = %d",
                            CmdPtr->APNumber, CurrentAPState);

          LC_AppData.CmdErrCount++;
        }
      } else {
        /*
        **  Actionpoint number is out of range
        **  (it's zero based, since it's a table index)
        */
        CFE_EVS_SendEvent(LC_APSTATE_APNUM_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Set AP state error: Invalid AP number = %d", CmdPtr->APNumber);

        LC_AppData.CmdErrCount++;
      }
    }

    /*
    ** Update the command counter and send out event if command
    ** executed
    */
    if (CmdSuccess == TRUE) {
      LC_AppData.CmdCount++;

      CFE_EVS_SendEvent(LC_APSTATE_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Set AP state command: AP = %d, New state = %d", CmdPtr->APNumber,
                        CmdPtr->NewAPState);
    }
  } /* end ValidState if */

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Set one actionpoint permanently off -- the only irreversible command in LC.
//
// TWO GUARDS, AND BOTH MATTER. It refuses LC_ALL_ACTIONPOINTS outright (NASA: "This command can't
// be invoked for all actionpoints"), and it refuses any actionpoint that is not ALREADY DISABLED
// -- so turning one off permanently takes two commands in order, and neither can be done by
// accident. Only a table load can bring it back.
I32 LC_SetAPPermOffCmd(LC_SetAPPermOffCmd_t *msg)
{
  LC_SetAPPermOff_Payload_t *CmdPtr = &msg->Payload;
  U32 TableIndex;
  U8 CurrentAPState;

  if (CmdPtr->APNumber == LC_ALL_ACTIONPOINTS || CmdPtr->APNumber >= LC_MAX_ACTIONPOINTS) {
    /*
    **  Invalid actionpoint number
    **  (This command can't be invoked for all actionpoints)
    */
    CFE_EVS_SendEvent(LC_APOFF_APNUM_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Set AP perm off error: Invalid AP number = %d", CmdPtr->APNumber);

    LC_AppData.CmdErrCount++;
  } else {
    TableIndex = CmdPtr->APNumber;
    CurrentAPState = LC_OperData.ARTPtr[TableIndex].CurrentState;

    if (CurrentAPState != LC_APSTATE_DISABLED) {
      /*
      ** Actionpoints can only be turned permanently off if
      ** they are currently disabled
      */
      CFE_EVS_SendEvent(LC_APOFF_CURR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Set AP perm off error, AP NOT Disabled: AP = %d, Current state = %d",
                        CmdPtr->APNumber, CurrentAPState);

      LC_AppData.CmdErrCount++;
    } else {
      /*
      ** Update state for actionpoint specified
      */
      LC_OperData.ARTPtr[TableIndex].CurrentState = LC_APSTATE_PERMOFF;

      LC_AppData.CmdCount++;

      CFE_EVS_SendEvent(LC_APOFF_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Set AP permanently off command: AP = %d", CmdPtr->APNumber);
    }
  } /* end CmdPtr -> APNumber else */

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Reset one actionpoint's statistics, or all of them.
I32 LC_ResetAPStatsCmd(LC_ResetAPStatsCmd_t *msg)
{
  LC_ResetAPStats_Payload_t *CmdPtr = &msg->Payload;
  Bool CmdSuccess = FALSE;

  /* arg may be one or all AP's */
  if (CmdPtr->APNumber == LC_ALL_ACTIONPOINTS) {
    LC_ResetResultsAP(0, LC_MAX_ACTIONPOINTS - 1, TRUE);
    CmdSuccess = TRUE;
  } else if (CmdPtr->APNumber < LC_MAX_ACTIONPOINTS) {
    LC_ResetResultsAP(CmdPtr->APNumber, CmdPtr->APNumber, TRUE);
    CmdSuccess = TRUE;
  } else {
    /* arg is out of range (zero based table index) */
    LC_AppData.CmdErrCount++;

    CFE_EVS_SendEvent(LC_APSTATS_APNUM_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Reset AP stats error: invalid AP number = %d", CmdPtr->APNumber);
  }

  if (CmdSuccess == TRUE) {
    LC_AppData.CmdCount++;

    CFE_EVS_SendEvent(LC_APSTATS_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Reset AP stats command: AP = %d", CmdPtr->APNumber);
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Reset selected actionpoint statistics.
//
// SEE THE NOTE AT THE TOP OF THIS FILE ON ResetStatsCmd: TRUE means a ground command and PRESERVES
// the live state and the most recent result; FALSE means a table reload and resets those too,
// putting CurrentState back to the DEFINITION table's DefaultState.
//
// THE LOOP IS `<=` ON UNSIGNED INDICES, so a single-actionpoint reset passes the same index as
// start and end and runs once. A StartIndex greater than EndIndex runs zero times rather than
// wrapping, because the test is evaluated first -- which is what makes the one-element call safe.
U0 LC_ResetResultsAP(U32 StartIndex, U32 EndIndex, Bool ResetStatsCmd)
{
  U32 TableIndex;

  /* reset selected entries in actionpoint results table */
  for (TableIndex = StartIndex; TableIndex <= EndIndex; TableIndex++) {
    if (!ResetStatsCmd) {
      /* reset AP stats command does not modify AP state or most recent test result */
      LC_OperData.ARTPtr[TableIndex].ActionResult = LC_ACTION_STALE;
      LC_OperData.ARTPtr[TableIndex].CurrentState = LC_OperData.ADTPtr[TableIndex].DefaultState;
    }

    LC_OperData.ARTPtr[TableIndex].PassiveAPCount = 0;
    LC_OperData.ARTPtr[TableIndex].FailToPassCount = 0;
    LC_OperData.ARTPtr[TableIndex].PassToFailCount = 0;

    LC_OperData.ARTPtr[TableIndex].ConsecutiveFailCount = 0;
    LC_OperData.ARTPtr[TableIndex].CumulativeFailCount = 0;
    LC_OperData.ARTPtr[TableIndex].CumulativeRTSExecCount = 0;
    LC_OperData.ARTPtr[TableIndex].CumulativeEventMsgsSent = 0;
  }
}

/*******************************************************************************/
// Reset one watchpoint's statistics, or all of them. The actionpoint twin above.
I32 LC_ResetWPStatsCmd(LC_ResetWPStatsCmd_t *msg)
{
  LC_ResetWPStats_Payload_t *CmdPtr = &msg->Payload;
  Bool CmdSuccess = FALSE;

  /* arg may be one or all WP's */
  if (CmdPtr->WPNumber == LC_ALL_WATCHPOINTS) {
    LC_ResetResultsWP(0, LC_MAX_WATCHPOINTS - 1, TRUE);
    CmdSuccess = TRUE;
  } else if (CmdPtr->WPNumber < LC_MAX_WATCHPOINTS) {
    LC_ResetResultsWP(CmdPtr->WPNumber, CmdPtr->WPNumber, TRUE);
    CmdSuccess = TRUE;
  } else {
    /* arg is out of range (zero based table index) */
    LC_AppData.CmdErrCount++;

    CFE_EVS_SendEvent(LC_WPSTATS_WPNUM_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Reset WP stats error: invalid WP number = %d", CmdPtr->WPNumber);
  }

  if (CmdSuccess == TRUE) {
    LC_AppData.CmdCount++;

    CFE_EVS_SendEvent(LC_WPSTATS_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Reset WP stats command: WP = %d", CmdPtr->WPNumber);
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Reset selected watchpoint statistics.
//
// THE PRESERVED FIELDS DIFFER FROM THE ACTIONPOINT TWIN'S: here a reload clears WatchResult AND
// CountdownToStale, because a watchpoint's "state" IS its countdown. There is no DefaultState to
// restore -- a watchpoint has no commandable state at all, which is why LC has no
// LC_SET_WP_STATE_CC.
//
// AND IT ZEROES BOTH TRANSITION RECORDS' VALUE AND TIMESTAMP BUT NOT THEIR DataType. So after a
// statistics reset the two LC_WRTTransition_t entries report a zero value at time zero with
// whatever data type the last real transition had. NASA's; the DataType is only meaningful
// alongside a Value, and nothing reads one without the other.
U0 LC_ResetResultsWP(U32 StartIndex, U32 EndIndex, Bool ResetStatsCmd)
{
  U32 TableIndex;

  /* reset selected entries in watchpoint results table */
  for (TableIndex = StartIndex; TableIndex <= EndIndex; TableIndex++) {
    if (!ResetStatsCmd) {
      /* reset WP stats command does not modify most recent test result */
      LC_OperData.WRTPtr[TableIndex].WatchResult = LC_WATCH_STALE;
      LC_OperData.WRTPtr[TableIndex].CountdownToStale = 0;
    }

    LC_OperData.WRTPtr[TableIndex].EvaluationCount = 0;
    LC_OperData.WRTPtr[TableIndex].FalseToTrueCount = 0;
    LC_OperData.WRTPtr[TableIndex].ConsecutiveTrueCount = 0;
    LC_OperData.WRTPtr[TableIndex].CumulativeTrueCount = 0;

    LC_OperData.WRTPtr[TableIndex].LastFalseToTrue.Value = 0;
    LC_OperData.WRTPtr[TableIndex].LastFalseToTrue.Timestamp.Seconds = 0;
    LC_OperData.WRTPtr[TableIndex].LastFalseToTrue.Timestamp.Subseconds = 0;

    LC_OperData.WRTPtr[TableIndex].LastTrueToFalse.Value = 0;
    LC_OperData.WRTPtr[TableIndex].LastTrueToFalse.Timestamp.Seconds = 0;
    LC_OperData.WRTPtr[TableIndex].LastTrueToFalse.Timestamp.Subseconds = 0;
  }
}

#endif
