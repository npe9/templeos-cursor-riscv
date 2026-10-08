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
// LIMIT CHECKER'S ACTIONPOINT PROCESSING -- the 1:1 translation of NASA's fsw/src/lc_action.c,
// 728 lines and five functions. This is where LC DECIDES, and the decision is a reverse-Polish
// expression over watchpoint results.
//
// ### AN ACTIONPOINT IS A STACK MACHINE, AND LC_WATCH_FALSE BEING ZERO IS LOAD-BEARING
//
// LC_EvaluateRPN walks a 20-entry U16 array. Each item is either a WATCHPOINT NUMBER -- pushed as
// that watchpoint's current result -- or one of five operators: LC_RPN_AND, OR, XOR, NOT and
// EQUAL, which are 0xFFF1..0xFFF5. Since a watchpoint number is bounded by LC_MAX_WATCHPOINTS
// (176), the operators cannot collide with an index, and the `default:` arm is what recognises an
// index at all.
//
// THE FOUR-VALUED LOGIC IS THE INTERESTING PART. A watchpoint result is FALSE, TRUE, ERROR or
// STALE, and every operator has to say what it does with the last two. NASA's choice is a
// PRIORITY: for AND, a single FALSE wins outright (false AND anything is false), then ERROR, then
// STALE, then TRUE. For OR, a single TRUE wins, then ERROR, then STALE. So ERROR and STALE
// PROPAGATE, but only when the result is not already determined by an ordinary operand -- which is
// the same short-circuit a two-valued AND would do, extended.
//
// XOR AND NOT CANNOT SHORT-CIRCUIT, so both check ERROR and STALE first and then compute
// arithmetically: `(Operand1 != Operand2)` and `(Operand1 == LC_WATCH_FALSE)`. THIS IS WHY
// lc_tbldefs.h SAYS LC_WATCH_FALSE "must be zero for RPN evaluation" AND LC_WATCH_TRUE "must be
// one" -- those two lines produce a C boolean, 0 or 1, and it is pushed straight back on the stack
// as a watch result. Change either constant and the two operators are silently wrong; nothing
// would fail to compile.
//
// ### POP_RPN_DATA IS A TERNARY WITH TWO DIFFERENT TYPES, AND IT TRANSLATES VERBATIM
//
//     #define POP_RPN_DATA ((StackPtr <= 0) ? (IllegalRPN = true) : (RPNStack[--StackPtr]))
//
// used as `Operand2 = POP_RPN_DATA;`. On underflow it SETS THE ERROR FLAG AND EVALUATES TO 1,
// which is LC_WATCH_TRUE -- so the operand is garbage, and that is harmless only because
// IllegalRPN ends the loop before the garbage is used. NASA's, and worth stating because it reads
// like a bug.
//
// It was CHECKED rather than assumed: tests/exec/cases pinned the shape and this compiler gives
// 9, 7, 1 and a set flag for a two-element stack popped three times -- C's answer exactly,
// including the mixed-type arms and the side effect inside the condition. No rewrite needed.
//
// ### AND THE GROUND UPLOADS PART OF A FORMAT STRING
//
// When an actionpoint fails and LC is active, the event it sends uses the ADT entry's OWN
// EventText as the format, with LC_AP_EVENT_TAIL_STR appended:
//
//     snprintf(EventText, ..., "%s %s", LC_OperData.ADTPtr[APNumber].EventText,
//              LC_AP_EVENT_TAIL_STR);
//     CFE_EVS_SendEvent(EventID, EventType, EventText, APNumber, ConsecutiveFailCount, RTSId);
//
// The THREE CONVERSIONS are LC's, in the tail (": AP = %d, FailCount = %d, RTS = %d"), so a
// mission cannot change their number. But the PREFIX is table data, and a `%` in it shifts every
// argument -- the hazard docs/ records as "an unknown printf conversion SHIFTS every later
// argument". LC_ValidateADT checks the default state, the RTS id, the fail count, the event type
// and the RPN syntax, and does NOT look at EventText. Upstream, latent, and not this port's to
// fix.
//
// IT ALSO MEANS check_strings AND check_formats CANNOT SEE THIS EVENT. The format is not a literal
// at the call site, so the gate that compares every literal against NASA's has nothing to compare
// and the gate that reads conversions has nothing to read. The only thing that pins it is a
// transcript.
#ifndef LC_ACTION_HC
#define LC_ACTION_HC

#include "lc_global.HC"
#include "lc_eventids.HC"
#include "lc_custom.HC"

// NASA's fsw/src/lc_action.h. The three conversions LC appends to every actionpoint-failure event.
#define LC_AP_EVENT_TAIL_STR ": AP = %d, FailCount = %d, RTS = %d"

// THREE FORWARD DECLARATIONS, because this file calls DOWNWARDS three times and HolyC is
// single-pass: LC_SampleAPs calls LC_SampleSingleAP, which calls LC_EvaluateRPN, and
// LC_ValidateADT calls LC_ValidateRPN. NASA needs none of them -- its prototypes are in
// lc_action.h -- so these are the translation's, and they are DECLARATIONS of functions this same
// file defines rather than stand-ins for anything.
//
// WHY THEY ARE WRITTEN RATHER THAN RELIED ON: the file compiled without them, which is the
// dangerous part. An unresolved call in this compiler can become an IMPORT, and
// docs/ records that a missing symbol is then filled by the C runtime with only the blob's
// HOFYIMP1 trailer to show it. check_in_blob is what proves each of the five is DEFINED here --
// it opens the binary and asks for an address -- but a declaration is what makes the intent
// explicit at the call site instead of leaving it to a gate.
U0 LC_SampleSingleAP(U16 APNumber);
U8 LC_EvaluateRPN(U16 APNumber);
I32 LC_ValidateRPN(U16 *RPNPtr, I32 *IndexValue, I32 *StackDepthValue);

/*******************************************************************************/
// Sample one or all actionpoints.
//
// IT VALIDATES ONLY THE **STARTING** INDEX'S STATE AND THEN LOOPS TO EndIndex. So a range whose
// first actionpoint is unused or permanently off is refused whole, and a range whose first is fine
// samples every later one regardless -- LC_SampleSingleAP filters each individually. NASA's, and
// the asymmetry is the reason the error event names StartIndex rather than a range.
U0 LC_SampleAPs(U16 StartIndex, U16 EndIndex)
{
  U16 TableIndex;
  U8 CurrentAPState;

  /*
  ** Make sure the current state of the starting actionpoint
  ** in the sample is valid for a sample request
  */
  CurrentAPState = LC_OperData.ARTPtr[StartIndex].CurrentState;

  if (CurrentAPState != LC_ACTION_NOT_USED && CurrentAPState != LC_APSTATE_PERMOFF) {
    /*
     ** Sample selected actionpoints
     */
    for (TableIndex = StartIndex; TableIndex <= EndIndex; TableIndex++) {
      LC_SampleSingleAP(TableIndex);
    }
  } else {
    /*
    **  Actionpoint isn't currently operational
    */
    CFE_EVS_SendEvent(LC_APSAMPLE_CURR_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Sample AP error, invalid current AP state: AP = %d, State = %d", StartIndex,
                      CurrentAPState);
  }

  return;
}

/*******************************************************************************/
// Sample a single actionpoint.
//
// THE THREE EVENT-RATE LIMITS ARE PER-ACTIONPOINT AND CUMULATIVE, not per-second: a pass-to-fail
// event is sent while PassToFailCount is still <= MaxPassFailEvents, so an actionpoint that
// oscillates goes quiet FOREVER after its budget, not for a while. Same for fail-to-pass and for
// the passive-failure event. That is a deliberate choice about a bus with no room for chatter, and
// it means a late failure can be silent -- CumulativeEventMsgsSent is the only record that the
// budget was spent.
//
// AND AN ACTIONPOINT THAT FIRES GOES PASSIVE. `CurrentState = LC_APSTATE_PASSIVE` before the RTS
// is requested, so one failure arms one RTS and the ground has to re-activate. That is the whole
// safety argument for letting a table fire a stored command.
U0 LC_SampleSingleAP(U16 APNumber)
{
  U8 CurrentAPState;
  U8 PreviousResult;
  U8 CurrentResult;
  U8 EventText[CFE_MISSION_EVS_MAX_MESSAGE_LENGTH];

  /*
  ** We only do the sample if the actionpoint is active
  ** or passive. Other states are ignored since this
  ** routine is called in a loop to process ALL actionpoints.
  */
  CurrentAPState = LC_OperData.ARTPtr[APNumber].CurrentState;

  if (CurrentAPState == LC_APSTATE_ACTIVE || CurrentAPState == LC_APSTATE_PASSIVE) {
    /*
    ** Evaluate the actionpoint and update the results
    ** as needed
    */
    LC_AppData.APSampleCount++;

    PreviousResult = LC_OperData.ARTPtr[APNumber].ActionResult;

    CurrentResult = LC_EvaluateRPN(APNumber);

    LC_OperData.ARTPtr[APNumber].ActionResult = CurrentResult;

    /*****************************************
    ** If actionpoint fails current evaluation
    ******************************************/
    if (CurrentResult == LC_ACTION_FAIL) {
      LC_OperData.ARTPtr[APNumber].ConsecutiveFailCount++;
      LC_OperData.ARTPtr[APNumber].CumulativeFailCount++;

      if (PreviousResult == LC_ACTION_PASS) {
        /*
        **  We failed this time, but we passed last time
        */
        LC_OperData.ARTPtr[APNumber].PassToFailCount++;

        /*
        **  Send only a limited number of Pass to Fail events
        */
        if (LC_OperData.ARTPtr[APNumber].PassToFailCount <=
            LC_OperData.ADTPtr[APNumber].MaxPassFailEvents) {
          CFE_EVS_SendEvent(LC_AP_PASSTOFAIL_INF_EID, CFE_EVS_EventType_INFORMATION,
                            "AP state change from PASS to FAIL: AP = %d", APNumber);
          LC_OperData.ARTPtr[APNumber].CumulativeEventMsgsSent++;
        }
      }

      if (LC_OperData.ARTPtr[APNumber].ConsecutiveFailCount >=
          LC_OperData.ADTPtr[APNumber].MaxFailsBeforeRTS) {
        /*
        ** We have failed enough times to request the RTS
        */
        if (CurrentAPState == LC_APSTATE_ACTIVE) {
          /*
          ** Actions go to passive after they've failed
          */
          LC_OperData.ARTPtr[APNumber].CurrentState = LC_APSTATE_PASSIVE;

          if (LC_AppData.CurrentLCState == LC_STATE_ACTIVE) {
            /*
            ** If the LC application state is active, request the
            ** specified RTS be executed
            */
            LC_ExecuteRTS(LC_OperData.ADTPtr[APNumber].RTSId);

            LC_OperData.ARTPtr[APNumber].CumulativeRTSExecCount++;

            LC_AppData.RTSExecCount++;

            /*
            ** Copy event text specific to this action and
            ** add our trailer with AP specific info making
            ** sure we won't exceed our character buffer.
            */
            StrPrintN(EventText, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "%s %s",
                      LC_OperData.ADTPtr[APNumber].EventText, LC_AP_EVENT_TAIL_STR);

            CFE_EVS_SendEvent(LC_OperData.ADTPtr[APNumber].EventID,
                              LC_OperData.ADTPtr[APNumber].EventType, EventText, APNumber,
                              LC_OperData.ARTPtr[APNumber].ConsecutiveFailCount,
                              LC_OperData.ADTPtr[APNumber].RTSId);

            LC_OperData.ARTPtr[APNumber].CumulativeEventMsgsSent++;
          } else {
            /*
            ** The LC application state is passive so we don't
            ** do the RTS request. We bump the passive RTS execution
            ** counter and send out a generic event message
            */
            LC_AppData.PassiveRTSExecCount++;

            CFE_EVS_SendEvent(LC_PASSIVE_FAIL_DBG_EID, CFE_EVS_EventType_DEBUG,
                              "AP failed while LC App passive: AP = %d, FailCount = %d, RTS = %d",
                              APNumber, LC_OperData.ARTPtr[APNumber].ConsecutiveFailCount,
                              LC_OperData.ADTPtr[APNumber].RTSId);
          }
        } else {
          /*
          ** The actionpoint failed while the actionpoint state is passive
          */
          LC_OperData.ARTPtr[APNumber].PassiveAPCount++;
          LC_AppData.PassiveRTSExecCount++;

          /*
          **  Send only a limited number of AP is Passive events
          */
          if (LC_OperData.ARTPtr[APNumber].PassiveAPCount <=
              LC_OperData.ADTPtr[APNumber].MaxPassiveEvents) {
            CFE_EVS_SendEvent(LC_AP_PASSIVE_FAIL_INF_EID, CFE_EVS_EventType_INFORMATION,
                              "AP failed while passive: AP = %d, FailCount = %d, RTS = %d",
                              APNumber, LC_OperData.ARTPtr[APNumber].ConsecutiveFailCount,
                              LC_OperData.ADTPtr[APNumber].RTSId);
            LC_OperData.ARTPtr[APNumber].CumulativeEventMsgsSent++;
          }
        }
      } /* end (ConsecutiveFailCount >= MaxFailsBeforeRTS) if */
    }   /* end (CurrentResult == LC_ACTION_FAIL) if */

    /******************************************
    ** If actionpoint passes current evaluation
    *******************************************/
    else if (CurrentResult == LC_ACTION_PASS) {
      if (PreviousResult == LC_ACTION_FAIL) {
        /*
        **  We passed this time, but we failed last time
        */
        LC_OperData.ARTPtr[APNumber].FailToPassCount++;

        /*
        **  Send only a limited number of Fail to Pass events
        */
        if (LC_OperData.ARTPtr[APNumber].FailToPassCount <=
            LC_OperData.ADTPtr[APNumber].MaxFailPassEvents) {
          CFE_EVS_SendEvent(LC_AP_FAILTOPASS_INF_EID, CFE_EVS_EventType_INFORMATION,
                            "AP state change from FAIL to PASS: AP = %d", APNumber);
          LC_OperData.ARTPtr[APNumber].CumulativeEventMsgsSent++;
        }
      }
      /*
      ** Clear consecutive failure counter for this AP
      */
      LC_OperData.ARTPtr[APNumber].ConsecutiveFailCount = 0;
    }

    /*
    ** If actionpoint is not measured or has gone stale
    */
    else if (CurrentResult == LC_ACTION_STALE) {
      /*
      ** Make sure the consecutive fail count is zeroed
      */
      LC_OperData.ARTPtr[APNumber].ConsecutiveFailCount = 0;
    } else {
      /*
      ** We got back a LC_ACTION_ERROR result, send event
      */
      CFE_EVS_SendEvent(LC_ACTION_ERROR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "AP evaluated to error: AP = %d, Result = %d", APNumber, CurrentResult);
    }
  } /* end CurrentAPState if */

  return;
}

/*******************************************************************************/
// Evaluate the Reverse Polish Notation (RPN) equation for an actionpoint.
//
// See the note at the top of this file for the four-valued logic and for POP_RPN_DATA.

/*
 * StackPtr is an index into an array RPNStack (see LC_EvaluateRPN)
 * which contains values to be used in an RPN function.  This macro
 * validates the StackPtr to confirm that another operand is present
 * in the RPMStack array, then returns the next element.
 */
#define POP_RPN_DATA ((StackPtr <= 0) ? (IllegalRPN = TRUE) : (RPNStack[--StackPtr]))
U8 LC_EvaluateRPN(U16 APNumber)
{
  Bool Done;
  Bool IllegalRPN;
  Bool IllegalOperand;
  U8 EvalResult = LC_ACTION_ERROR;
  I32 RPNEquationPtr;
  I32 StackPtr;
  U16 RPNData;
  U16 RPNStack[LC_MAX_RPN_EQU_SIZE];
  U16 Operand1;
  U16 Operand2;

  StackPtr = 0;
  RPNEquationPtr = 0;
  IllegalRPN = FALSE;
  IllegalOperand = FALSE;
  Done = FALSE;

  /*
  ** Keep going till we're done or till we get an error
  */
  while (Done == FALSE && IllegalRPN == FALSE && IllegalOperand == FALSE) {
    /*
    **  Pick off each piece of the RPN equation and handle
    **  one at a time
    */
    RPNData = LC_OperData.ADTPtr[APNumber].RPNEquation[RPNEquationPtr++];

    /*
    **  The data is either an RPN operator or a watchpoint number
    */
    switch (RPNData) {
      /*
      **  If the data is an RPN operator then each operand is
      **  either a watchpoint evaluation result or it is the
      **  result of a previous RPN operation
      */
      case LC_RPN_AND:
        Operand2 = POP_RPN_DATA;
        Operand1 = POP_RPN_DATA;
        if (Operand1 == LC_WATCH_FALSE || Operand2 == LC_WATCH_FALSE) {
          RPNStack[StackPtr++] = LC_WATCH_FALSE;
        } else if (Operand1 == LC_WATCH_ERROR || Operand2 == LC_WATCH_ERROR) {
          RPNStack[StackPtr++] = LC_WATCH_ERROR;
        } else if (Operand1 == LC_WATCH_STALE || Operand2 == LC_WATCH_STALE) {
          RPNStack[StackPtr++] = LC_WATCH_STALE;
        } else {
          RPNStack[StackPtr++] = LC_WATCH_TRUE;
        }
        break;

      case LC_RPN_OR:
        Operand2 = POP_RPN_DATA;
        Operand1 = POP_RPN_DATA;
        if (Operand1 == LC_WATCH_TRUE || Operand2 == LC_WATCH_TRUE) {
          RPNStack[StackPtr++] = LC_WATCH_TRUE;
        } else if (Operand1 == LC_WATCH_ERROR || Operand2 == LC_WATCH_ERROR) {
          RPNStack[StackPtr++] = LC_WATCH_ERROR;
        } else if (Operand1 == LC_WATCH_STALE || Operand2 == LC_WATCH_STALE) {
          RPNStack[StackPtr++] = LC_WATCH_STALE;
        } else {
          RPNStack[StackPtr++] = LC_WATCH_FALSE;
        }
        break;

      case LC_RPN_XOR:
        Operand2 = POP_RPN_DATA;
        Operand1 = POP_RPN_DATA;
        if (Operand1 == LC_WATCH_ERROR || Operand2 == LC_WATCH_ERROR) {
          RPNStack[StackPtr++] = LC_WATCH_ERROR;
        } else if (Operand1 == LC_WATCH_STALE || Operand2 == LC_WATCH_STALE) {
          RPNStack[StackPtr++] = LC_WATCH_STALE;
        } else {
          // (Operand1 != Operand2) is a 0 or 1 pushed straight back as a watch result -- which is
          // only correct because LC_WATCH_FALSE is 0 and LC_WATCH_TRUE is 1. See the top of file.
          RPNStack[StackPtr++] = Operand1 != Operand2;
        }
        break;

      case LC_RPN_NOT:
        Operand1 = POP_RPN_DATA;
        if (Operand1 == LC_WATCH_ERROR) {
          RPNStack[StackPtr++] = LC_WATCH_ERROR;
        } else if (Operand1 == LC_WATCH_STALE) {
          RPNStack[StackPtr++] = LC_WATCH_STALE;
        } else {
          RPNStack[StackPtr++] = Operand1 == LC_WATCH_FALSE;
        }
        break;

      case LC_RPN_EQUAL:
        EvalResult = POP_RPN_DATA;
        if (EvalResult == LC_WATCH_ERROR || EvalResult == LC_WATCH_STALE) {
          IllegalOperand = TRUE;
        } else if (StackPtr == 0) {
          Done = TRUE;
        } else {
          IllegalRPN = TRUE;
        }
        break;

      /*
      **  If the data is a watchpoint number then the operand is
      **  the current value of that watchpoint result
      */
      default:
        if (RPNData < LC_MAX_WATCHPOINTS) {
          RPNStack[StackPtr++] = LC_OperData.WRTPtr[RPNData].WatchResult;
        } else {
          IllegalRPN = TRUE;
        }
        break;
    } /* end switch */

    /*
    ** If still not done and have no errors - check for the end of the buffer
    */
    if (Done == FALSE && IllegalRPN == FALSE && IllegalOperand == FALSE) {
      if (RPNEquationPtr >= LC_MAX_RPN_EQU_SIZE) {
        IllegalRPN = TRUE;
      }
    }
  } /* end while */

  if (IllegalRPN == TRUE) {
    CFE_EVS_SendEvent(LC_INVALID_RPN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "AP has illegal RPN expression: AP = %d, LastOperand = %d, StackPtr = %d",
                      APNumber, RPNEquationPtr - 1, StackPtr);

    EvalResult = LC_ACTION_ERROR;
  } else if (EvalResult == LC_WATCH_ERROR) {
    EvalResult = LC_ACTION_ERROR;
  } else if (EvalResult == LC_WATCH_STALE) {
    EvalResult = LC_ACTION_STALE;
  } else if (EvalResult == LC_WATCH_FALSE) {
    EvalResult = LC_ACTION_PASS;
  } else if (EvalResult == LC_WATCH_TRUE) {
    EvalResult = LC_ACTION_FAIL;
  }

  return EvalResult;
}

/*******************************************************************************/
// Validate the actionpoint definition table (ADT).
//
// FIVE CHECKS IN AN else-if CHAIN, SO ONLY THE FIRST FAILURE PER ENTRY IS NAMED -- and the chain
// order IS the diagnosis: an unused entry short-circuits everything, then the default state, the
// RTS id, the fail count, the event type, and only then the RPN syntax. An entry with a bad state
// AND a bad RPN reports the state.
//
// AND ONLY THE **FIRST BAD ENTRY IN THE WHOLE TABLE** GETS A DETAILED EVENT: `TableResult ==
// CFE_SUCCESS` guards it, and TableResult is set from the first failure onwards. Every later bad
// entry still counts toward BadCount, so the summary event is the only way to learn there was more
// than one. The same shape CS's four table validators have.
//
// IT DOES NOT VALIDATE EventText, which is the latent upstream issue noted at the top of this
// file: that string becomes part of a printf format.
I32 LC_ValidateADT(U8 *TableData)
{
  LC_ADTEntry_t *TableArray = TableData;

  I32 EntryResult = LC_ADTVAL_ERR_NONE;
  I32 TableResult = CFE_SUCCESS;
  I32 TableIndex;

  U8 DefaultState;
  U16 RTSId;
  U16 MaxFailsBeforeRTS;
  U16 EventType;

  U16 *RPNPtr;
  I32 RPNIndex = 0;
  I32 RPNStackDepth = 0;

  I32 GoodCount = 0;
  I32 BadCount = 0;
  I32 UnusedCount = 0;

  /*
  ** Verify each entry in the pending actionpoint definition table
  */
  for (TableIndex = 0; TableIndex < LC_MAX_ACTIONPOINTS; TableIndex++) {
    DefaultState = TableArray[TableIndex].DefaultState;
    RTSId = TableArray[TableIndex].RTSId;
    MaxFailsBeforeRTS = TableArray[TableIndex].MaxFailsBeforeRTS;
    RPNPtr = TableArray[TableIndex].RPNEquation;
    EventType = TableArray[TableIndex].EventType;

    if (DefaultState == LC_APSTATE_NOT_USED) {
      /*
      ** Unused table entry
      */
      UnusedCount++;
    } else if (DefaultState != LC_APSTATE_ACTIVE && DefaultState != LC_APSTATE_PASSIVE &&
               DefaultState != LC_APSTATE_DISABLED && DefaultState != LC_APSTATE_PERMOFF) {
      /*
      ** Invalid default state
      */
      BadCount++;
      EntryResult = LC_ADTVAL_ERR_DEFSTATE;
    } else if (RTSId > LC_MAX_VALID_ADT_RTSID) {
      /*
      ** Bad RTS ID (limit set by configuration parameter,
      ** see lc_platform_cfg.h)
      */
      BadCount++;
      EntryResult = LC_ADTVAL_ERR_RTSID;
    } else if (MaxFailsBeforeRTS == 0) {
      /*
      ** Bad fail count
      */
      BadCount++;
      EntryResult = LC_ADTVAL_ERR_FAILCNT;
    } else if (EventType != CFE_EVS_EventType_DEBUG &&
               EventType != CFE_EVS_EventType_INFORMATION &&
               EventType != CFE_EVS_EventType_ERROR && EventType != CFE_EVS_EventType_CRITICAL) {
      /*
      ** Invalid event type
      */
      BadCount++;
      EntryResult = LC_ADTVAL_ERR_EVTTYPE;
    } else {
      /*
      ** Validate reverse polish equation syntax
      */
      EntryResult = LC_ValidateRPN(RPNPtr, &RPNIndex, &RPNStackDepth);

      if (EntryResult != LC_ADTVAL_ERR_NONE) {
        BadCount++;
      } else {
        GoodCount++;
      }
    }

    /*
    ** Generate detailed event for "first" error
    */
    if (EntryResult != LC_ADTVAL_ERR_NONE && TableResult == CFE_SUCCESS) {
      if (EntryResult == LC_ADTVAL_ERR_RPN) {
        CFE_EVS_SendEvent(LC_ADTVAL_RPNERR_EID, CFE_EVS_EventType_ERROR,
                          "ADT verify RPN err: AP = %d, Index = %d, StackDepth = %d", TableIndex,
                          RPNIndex, RPNStackDepth);
      } else {
        CFE_EVS_SendEvent(LC_ADTVAL_ERR_EID, CFE_EVS_EventType_ERROR,
                          "ADT verify err: AP = %d, Err = %d, State = %d, RTS = %d, FailCnt = %d, EvtType = %d",
                          TableIndex, EntryResult, DefaultState, RTSId, MaxFailsBeforeRTS,
                          EventType);
      }

      TableResult = EntryResult;
    }
  } /* end TableIndex for */

  /*
  ** Generate informational event with error totals
  */
  CFE_EVS_SendEvent(LC_ADTVAL_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "ADT verify results: good = %d, bad = %d, unused = %d", GoodCount, BadCount,
                    UnusedCount);

  return TableResult;
}

/*******************************************************************************/
// Validate a reverse polish notation (RPN) equation.
//
// IT COUNTS STACK DEPTH WITHOUT EVALUATING ANYTHING, which is the whole trick: a watchpoint id
// pushes (+1), AND/OR/XOR consume two and produce one (-1), NOT consumes one and produces one (0,
// hence the EMPTY else-if arm NASA left with only a comment in it), and the expression is valid
// exactly when LC_RPN_EQUAL is reached with a depth of 1.
//
// THE EMPTY ARM IS TRANSLATED AS AN EMPTY ARM. `else if (BufferItem == LC_RPN_NOT) { }` does
// nothing and must: folding it into the final else would make NOT an invalid symbol, and deleting
// it would make NOT a watchpoint id. Its emptiness is the specification.
//
// AND THE TWO OUT-PARAMETERS ARE WRITTEN ONLY ON FAILURE, which is why LC_ValidateADT's RPNIndex
// and RPNStackDepth are declared once OUTSIDE its loop and never reset: on a good entry they keep
// whatever the last BAD entry left, and the detailed event that reads them is only ever sent for
// the first failure. Correct, and only by that coincidence.
I32 LC_ValidateRPN(U16 *RPNPtr, I32 *IndexValue, I32 *StackDepthValue)
{
  I32 Result;
  I32 BufferIndex;
  I32 StackDepth;
  U16 BufferItem;

  /*
  ** Each equation consists only of watchpoint ID numbers
  ** and polish symbols (and, or, equal, etc).
  **
  ** Each watchpoint ID increases the stack depth and
  ** each polish symbol (except "not" which has no
  ** effect) decreases the stack depth.
  **
  ** The stack depth must never become negative and the
  ** depth must equal 1 when the "=" symbol is found.
  **
  ** The last symbol in the equation is assumed to be
  ** the "=" symbol, and the test does not examine any
  ** further data.
  */
  StackDepth = 0;
  BufferItem = 0;

  for (BufferIndex = 0; BufferIndex < LC_MAX_RPN_EQU_SIZE; BufferIndex++) {
    BufferItem = RPNPtr[BufferIndex];

    if (BufferItem == LC_RPN_AND || BufferItem == LC_RPN_OR || BufferItem == LC_RPN_XOR) {
      /*
      ** Depth test will fail if we haven't already counted 2
      ** watchpoint ID values
      */
      StackDepth--;
    } else if (BufferItem == LC_RPN_NOT) {
      /*
      ** Depth test will fail if this is 1st symbol
      */
    } else if (BufferItem == LC_RPN_EQUAL) {
      /*
      ** Equation ends when LC_RPN_EQUAL is found
      */
      break;
    } else if (BufferItem < LC_MAX_WATCHPOINTS) {
      /*
      ** Valid watchpoint ID
      */
      StackDepth++;
    } else {
      /*
      ** Not a valid polish symbol or watchpoint ID
      */
      break;
    }

    /*
    ** Must have more watchpoint ID's than polish symbols
    */
    if (StackDepth <= 0) {
      break;
    }
  }

  /*
  ** Check for valid Reverse Polish Notation equation
  */
  if (BufferItem == LC_RPN_EQUAL && StackDepth == 1) {
    Result = LC_ADTVAL_ERR_NONE;
  } else {
    Result = LC_ADTVAL_ERR_RPN;

    /*
    ** Provide additional error information
    */
    *IndexValue = BufferIndex;
    *StackDepthValue = StackDepth;
  }

  return Result;
}

#endif
