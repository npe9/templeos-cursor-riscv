/************************************************************************
 * NASA Docket No. GSC-18,924-1, and identified as "Core Flight
 * System (cFS) Stored Command Application (SC)"
 *
 * Copyright (c) 2021 United States Government as represented by the
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
// STORED COMMAND'S ATS REQUESTS -- the 1:1 translation of NASA's fsw/src/sc_atsrq.c, 742 lines and
// ten functions: start, stop, switch (three ways), jump, continue-on-failure and append.
//
// ### TWO NEARLY IDENTICAL THIRTY-LINE LOOPS THAT DIFFER IN ONE `if`, AND THE DIFFERENCE IS REAL
//
// `SC_BeginAts` and `SC_JumpAtsCmd` both walk the time-sorted index marking everything before a
// target time as skipped. The loops are the same line for line except here:
//
//     SC_BeginAts     StatusEntryPtr->Status = SC_Status_SKIPPED;   /* unconditional */
//
//     SC_JumpAtsCmd   if (StatusEntryPtr->Status == SC_Status_LOADED)   /* ONLY if loaded */
//                     { StatusEntryPtr->Status = SC_Status_SKIPPED; NumSkipped++; }
//
// NASA's comment on the second says why: "if the command has any other status, SC_Status_SKIPPED,
// SC_Status_EXECUTED, etc, then leave the status alone." **So a JUMP preserves each command's
// history and a START overwrites it** -- which is correct, because a start is a fresh run and a
// jump moves the clock within a run that is already in progress.
//
// That is exactly the kind of difference a translation that factored the two loops into one
// helper would have had to choose between, and the choice would have been invisible. They are two
// loops here because they are two loops upstream.
//
// ### THREE WAYS TO SWITCH ATS, AND THEY DISAGREE ON TWO THINGS EACH
//
//                          offset to SC_BeginAts   AtpState afterwards   counts a command?
//   SC_SwitchAtsCmd        (does not start)        unchanged             yes, CmdCtr++
//   SC_ServiceSwitchPend   **1**                   EXECUTING             no
//   SC_InlineSwitch        **0**                   **STARTING**          yes, CmdCtr++
//
// The ground command only SETS A PENDING FLAG; the other two do the work. And the one-second
// offset in SC_ServiceSwitchPend is deliberate -- NASA: "This prevents commands that were executed
// the same second that this command was received from being repeated." SC_InlineSwitch does not
// need it because it runs when there is nothing left to execute in the current second, which is
// the whole distinction between the two.
//
// `SC_Status_STARTING` exists for exactly one caller, which sc_tbl.HC's enum comment records as
// "used when an inline switch is executed".
//
// ### `SC_AppData.NextCmdTime[2]` IS INDEXED BY AN ENUM WHOSE THIRD MEMBER IS 255
//
// Every reference here is `NextCmdTime[SC_Process_ATP]`, and SC_Process_ATP is 0 and
// SC_Process_RTP is 1 -- so the enum doubles as the array index and the two agree. But
// `SC_Process_NONE` is **0xFF** (see sc_msg.HC), so any code that indexed this array with a
// process value that might be NONE would read 253 elements past it. Nothing in this file does;
// recorded because the array is two long, the enum is three wide, and nothing in the types says
// so.
//
// ### AND FOUR OF THE TWELVE CALL-ARROW SITES ARE HERE
//
// Hoists 3, 4, 5 and 6 of 12 -- two in SC_BeginAts and two in SC_JumpAtsCmd, the same pair in each
// of the twin loops. See sc_global.HC's header for the open HolyC defect.
#ifndef SC_ATSRQ_HC
#define SC_ATSRQ_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// sc_cfg.HC, sc_tbl.HC, sc_msg.HC, sc_global.HC, sc_events.HC, sc_utils.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13.
//
// **AND IT NEEDS ONE FUNCTION FROM sc_loads.c, WHICH IS NOT GATED YET.** `SC_ProcessAppend` is the
// single edge of the two-source call cycle `module_deps --cuts SC` reports, and the driver
// supplies a STAND-IN for it until sc_loads.c lands. The stand-in is UPSTREAM LOGIC, not a seam:
// it does nothing, so SC_AppendAtsCmd's success arm below reports an append that did not happen.
// That is stated at the call site and the exercise must not claim to drive the append.

// --- sc_atsrq.h's prototypes -------------------------------------------------------------------
I32 SC_StartAtsCmd(SC_StartAtsCmd_t *Cmd);
I32 SC_StopAtsCmd(SC_StopAtsCmd_t *Cmd);
Bool SC_BeginAts(U16 AtsIndex, U16 TimeOffset);
U0 SC_KillAts();
I32 SC_SwitchAtsCmd(SC_SwitchAtsCmd_t *Cmd);
U0 SC_ServiceSwitchPend();
Bool SC_InlineSwitch();
I32 SC_JumpAtsCmd(SC_JumpAtsCmd_t *Cmd);
I32 SC_ContinueAtsOnFailureCmd(SC_ContinueAtsOnFailureCmd_t *Cmd);
I32 SC_AppendAtsCmd(SC_AppendAtsCmd_t *Cmd);

// --- sc_loads.h's, which this file calls across the cycle --------------------------------------
U0 SC_ProcessAppend(U16 AtsIndex);

/*******************************************************************************/
// Start an ATS from the ground. Four nested conditions, and the innermost one delegates to
// SC_BeginAts -- which can still fail by skipping every command, in which case **the event came
// from SC_BeginAts and NASA's comment says so**: this arm only counts the error.
I32 SC_StartAtsCmd(SC_StartAtsCmd_t *Cmd)
{
  U16 AtsNum;   /* ATS ID */
  U16 AtsIndex; /* ATS array index */
  SC_AtsInfoTable_t *AtsInfoPtr;

  AtsNum = Cmd->Payload.AtsNum;

  /* validate ATS ID */
  if (SC_AtsNumIsValid(AtsNum)) {
    /* convert ATS ID to array index */
    AtsIndex = SC_AtsNumToIndex(AtsNum);
    AtsInfoPtr = SC_GetAtsInfoObject(AtsIndex);

    /* make sure that there is no ATS running on the ATP */
    if (SC_OperData.AtsCtrlBlckAddr->AtpState == SC_Status_IDLE) {
      /* make sure the specified ATS is ready */
      if (AtsInfoPtr->NumberOfCommands > 0) {
        /* start the ats */
        if (SC_BeginAts(AtsIndex, 0)) {
          /* finish the ATP control block .. */
          SC_OperData.AtsCtrlBlckAddr->AtpState = SC_Status_EXECUTING;

          /* increment the command request counter */
          SC_OperData.HkPacket.Payload.CmdCtr++;

          CFE_EVS_SendEvent(SC_STARTATS_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                            "ATS %c Execution Started", SC_IDX_AS_CHAR(AtsIndex));
        } else { /* could not start the ats, all commands were skipped */
          /* event message was sent from SC_BeginAts */
          /* increment the command request error counter */
          /* SC_OperData.AtsCtrlBlckAddr->AtpState is updated in SC_KillAts */
          SC_OperData.HkPacket.Payload.CmdErrCtr++;

        } /* end if */
      } else { /* the ats didn't have any commands in it */

        CFE_EVS_SendEvent(SC_STARTATS_CMD_NOT_LDED_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Start ATS Rejected: ATS %c Not Loaded", SC_IDX_AS_CHAR(AtsIndex));

        /* increment the command request error counter */
        SC_OperData.HkPacket.Payload.CmdErrCtr++;

      } /* end if */
    } else { /* the ATS is being used */

      CFE_EVS_SendEvent(SC_STARTATS_CMD_NOT_IDLE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Start ATS Rejected: ATP is not Idle");
      /* increment the command request error counter */
      SC_OperData.HkPacket.Payload.CmdErrCtr++;

    } /* end if */
  } else { /* the specified ATS id is not valid */

    CFE_EVS_SendEvent(SC_STARTATS_CMD_INVLD_ID_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Start ATS %u Rejected: Invalid ATS ID", SC_IDNUM_AS_UINT(AtsNum));

    /* increment the command request error counter */
    SC_OperData.HkPacket.Payload.CmdErrCtr++;

  } /* end if */

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Stop the running ATS.
//
// **CmdCtr++ IS UNCONDITIONAL AND SC_KillAts IS CALLED EITHER WAY**, so stopping when nothing is
// running is a SUCCESSFUL command that reports "There is no ATS running to stop" as an
// INFORMATION event. Same shape as sc_rtsrq.c's group commands. And `Result` is initialised to
// SC_ERROR and only ever compared against CFE_SUCCESS -- it is a two-state flag spelled as a
// status, which is why the `if` below reads oddly.
I32 SC_StopAtsCmd(SC_StopAtsCmd_t *Cmd)
{
  I32 Result = SC_ERROR;

  /*
   ** Check if the ATS ID is valid
   */
  if (SC_AtsNumIsValid(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum)) {
    Result = CFE_SUCCESS;
  }

  if (Result == CFE_SUCCESS) {
    CFE_EVS_SendEvent(SC_STOPATS_CMD_INF_EID, CFE_EVS_EventType_INFORMATION, "ATS %c stopped",
                      SC_IDX_AS_CHAR(SC_AtsNumToIndex(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum)));
  } else {
    CFE_EVS_SendEvent(SC_STOPATS_NO_ATS_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "There is no ATS running to stop");
  }

  /* Stop the ATS from executing */
  SC_KillAts();

  /* clear the global switch pend flag */
  SC_OperData.AtsCtrlBlckAddr->SwitchPendFlag = FALSE;

  SC_OperData.HkPacket.Payload.CmdCtr++;

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Arm an ATS: skip every command whose time has already passed, and point the control block at
// the first one that has not. **The twin of SC_JumpAtsCmd's loop, differing in one `if`** -- see
// the file header.
//
// THE `continue` ON AN INVALID COMMAND INDEX IS WHAT MAKES A CORRUPT TIME-INDEX SURVIVABLE: an
// entry whose CmdNum is out of range is stepped over rather than dereferenced, so one bad word in
// the sorted index costs one command instead of the whole ATS.
Bool SC_BeginAts(U16 AtsIndex, U16 TimeOffset)
{
  SC_AtsEntryHeader_t *Entry;                 /* ATS table entry pointer */
  SC_AtsCmdEntryOffsetRecord_t *CmdOffsetRec; /* ATS entry location in table */
  U32 ListCmdTime = 0;                        /* list entry execution time */
  U16 TimeIndex;                              /* the current time buffer index */
  U16 CmdIndex;                               /* ATS command index */
  Bool ReturnCode;
  U32 TimeToStartAts; /* the REAL time to start the ATS */
  U16 CmdsSkipped = 0;
  SC_AtsInfoTable_t *AtsInfoPtr;
  SC_AtsCmdStatusEntry_t *StatusEntryPtr;
  SC_AtsCmdNumRecord_t *CmdNumRec; /* THE HOISTS -- see below */
  SC_AtsEntry_t *AtsEntry;

  /* validate ATS array index */
  if (!SC_AtsIndexIsValid(AtsIndex)) {
    CFE_EVS_SendEvent(SC_BEGINATS_INVLD_INDEX_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Begin ATS error: invalid ATS index %u", SC_IDX_AS_UINT(AtsIndex));
    return FALSE;
  }

  AtsInfoPtr = SC_GetAtsInfoObject(AtsIndex);
  TimeToStartAts = SC_ComputeAbsTime(TimeOffset);

  /*
   ** Loop through the commands until a time tag is found that
   ** has a time greater than or equal to the current time OR
   ** all of the commands have been skipped
   */
  TimeIndex = SC_SEQUENCE_IDX_FIRST; /* pointer into the time index table */
  CmdIndex = SC_COMMAND_IDX_C(0);    /* updated in loop */

  while (SC_IDX_WITHIN_LIMIT(TimeIndex, AtsInfoPtr->NumberOfCommands)) {
    /* first get the cmd index at this list entry */
    // **CALL-ARROW HOIST 3 OF 12.**
    CmdNumRec = SC_GetAtsCommandNumAtSeq(AtsIndex, TimeIndex);
    CmdIndex = SC_CommandNumToIndex(CmdNumRec->CmdNum);
    if (!SC_AtsCommandIndexIsValid(CmdIndex)) {
      SC_IDX_INCREMENT(TimeIndex);
      continue;
    }

    /* then get the entry index from the cmd index table */
    CmdOffsetRec = SC_GetAtsEntryOffsetForCmd(AtsIndex, CmdIndex);
    /* then get a pointer to the ATS entry data */
    // **CALL-ARROW HOIST 4 OF 12.**
    AtsEntry = SC_GetAtsEntryAtOffset(AtsIndex, CmdOffsetRec->Offset);
    Entry = &AtsEntry->Header;
    /* then get cmd execution time from the ATS entry */
    ListCmdTime = SC_GetAtsEntryTime(Entry);

    /* compare ATS start time to this list entry time */
    if (SC_CompareAbsTime(TimeToStartAts, ListCmdTime)) {
      /* start time is greater than this list entry time */
      StatusEntryPtr = SC_GetAtsStatusEntryForCommand(AtsIndex, CmdIndex);

      // UNCONDITIONAL, unlike SC_JumpAtsCmd's -- see the file header.
      StatusEntryPtr->Status = SC_Status_SKIPPED;
      CmdsSkipped++;
      SC_IDX_INCREMENT(TimeIndex);
    } else {
      /* start time is less than or equal to this list entry */
      break;
    }
  }

  /*
   ** Check to see if the whole ATS was skipped
   */
  if (!SC_IDX_WITHIN_LIMIT(TimeIndex, AtsInfoPtr->NumberOfCommands)) {
    CFE_EVS_SendEvent(SC_ATS_SKP_ALL_ERR_EID, CFE_EVS_EventType_ERROR,
                      "All ATS commands were skipped, ATS stopped");

    /* stop the ats */
    SC_KillAts();

    ReturnCode = FALSE;
  } else { /* there is at least one command to execute */

    /*
     ** Initialize the ATP Control Block.
     */
    /* leave the atp state alone, it will be updated by the caller */
    SC_OperData.AtsCtrlBlckAddr->CurrAtsNum = SC_AtsIndexToNum(AtsIndex);
    SC_OperData.AtsCtrlBlckAddr->CmdNumber = SC_CommandIndexToNum(CmdIndex);
    SC_OperData.AtsCtrlBlckAddr->TimeIndexPtr = TimeIndex;

    /* send an event for number of commands skipped */
    // A **DEBUG** EVENT, so by default a start that silently discarded hundreds of commands says
    // nothing a ground operator sees. The count is in the text and the text is filtered.
    CFE_EVS_SendEvent(SC_ATS_ERR_SKP_DBG_EID, CFE_EVS_EventType_DEBUG,
                      "ATS started, skipped %d commands", CmdsSkipped);
    /*
     ** Set the next command time for the ATP
     */
    SC_AppData.NextCmdTime[SC_Process_ATP] = ListCmdTime;

    ReturnCode = TRUE;

  } /* end if */

  return ReturnCode;
}

/*******************************************************************************/
// Stop the ATP and clear its state.
//
// **THE USE COUNTER IS GUARDED BY `AtpState != IDLE`**, so stopping an already-stopped ATS does
// not inflate AtsUseCtr -- unlike SC_StopAtsCmd's CmdCtr, which is not guarded at all. Two
// counters in the same call path, one careful and one not.
U0 SC_KillAts()
{
  U16 AtsIndex;
  SC_AtsInfoTable_t *AtsInfoPtr;

  /*
   * Check if the ATS ID is valid
   */
  AtsIndex = SC_AtsNumToIndex(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum);
  if (SC_AtsIndexIsValid(AtsIndex) &&
      SC_OperData.AtsCtrlBlckAddr->AtpState != SC_Status_IDLE) {
    /* Increment the ats use counter */
    AtsInfoPtr = SC_GetAtsInfoObject(AtsIndex);

    AtsInfoPtr->AtsUseCtr++;
  }
  /*
   ** Reset the state in the atp control block
   */
  SC_OperData.AtsCtrlBlckAddr->AtpState = SC_Status_IDLE;

  // PARKED AT THE MAXIMUM, the same idiom SC_KillRts uses for its wakeup count -- the stopped
  // ATP's next command can never come due. See sc_msg.HC on SC_MAX_TIME.
  /* reset the time of the next ats command */
  SC_AppData.NextCmdTime[SC_Process_ATP] = SC_MAX_TIME;
}

/*******************************************************************************/
// The GROUND switch command, which **only sets a pending flag** -- the work happens later in
// SC_ServiceSwitchPend. See the file header's table of the three switch paths.
I32 SC_SwitchAtsCmd(SC_SwitchAtsCmd_t *Cmd)
{
  U16 NewAtsIndex; /* the index of the ats to switch to*/
  SC_AtsInfoTable_t *AtsInfoPtr;

  /* make sure that an ATS is running on the ATP */
  if (SC_AtsNumIsValid(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum) &&
      SC_OperData.AtsCtrlBlckAddr->AtpState == SC_Status_EXECUTING) {
    /* get the ATS to switch to */
    NewAtsIndex = SC_ToggleAtsIndex();
    AtsInfoPtr = SC_GetAtsInfoObject(NewAtsIndex);

    /* Now check to see if the new ATS has commands in it */
    if (AtsInfoPtr->NumberOfCommands > 0) {
      /* set the global switch pend flag */
      SC_OperData.AtsCtrlBlckAddr->SwitchPendFlag = TRUE;

      /* update the command counter */
      SC_OperData.HkPacket.Payload.CmdCtr++;

      CFE_EVS_SendEvent(SC_SWITCH_ATS_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Switch ATS is Pending");
    } else { /* the other ATS does not have any commands in it */

      CFE_EVS_SendEvent(SC_SWITCH_ATS_CMD_NOT_LDED_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Switch ATS Failure: Destination ATS Not Loaded");

      /* update command error counter */
      SC_OperData.HkPacket.Payload.CmdErrCtr++;

      SC_OperData.AtsCtrlBlckAddr->SwitchPendFlag = FALSE;

    } /* end if */
  } else { /* the ATP is not currently executing any commands */

    CFE_EVS_SendEvent(SC_SWITCH_ATS_CMD_IDLE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Switch ATS Rejected: ATP is idle");

    /* update the command error counter */
    SC_OperData.HkPacket.Payload.CmdErrCtr++;

    SC_OperData.AtsCtrlBlckAddr->SwitchPendFlag = FALSE;

  } /* end if */

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Perform a pending switch, once the current ATS's next command has come due.
//
// **IT STARTS THE NEW ATS WITH A ONE-SECOND OFFSET**, and NASA says why: "This prevents commands
// that were executed the same second that this command was received from being repeated." That
// one `1` is the difference between this path and SC_InlineSwitch's `0`.
//
// AND IT COUNTS NO COMMAND AT ALL -- neither CmdCtr nor CmdErrCtr -- because the command was
// already counted when SC_SwitchAtsCmd set the flag. So a switch that FAILS here (destination
// empty, or every command skipped) leaves the ground's success count standing.
U0 SC_ServiceSwitchPend()
{
  U16 NewAtsIndex; /* the ats index that we are switching to */
  U16 OldAtsIndex; /* the ats index we are switching from */
  SC_AtsInfoTable_t *AtsInfoPtr;

  /*
   **  See if it is time to switch the ATS
   */
  if (SC_CompareAbsTime(SC_AppData.NextCmdTime[SC_Process_ATP], SC_AppData.CurrentTime)) {
    /* make sure that an ATS is still running on the ATP */
    if (SC_OperData.AtsCtrlBlckAddr->AtpState == SC_Status_EXECUTING) {
      /* get the ATS number to switch to and from */
      OldAtsIndex = SC_AtsNumToIndex(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum);
      NewAtsIndex = SC_ToggleAtsIndex();
      AtsInfoPtr = SC_GetAtsInfoObject(NewAtsIndex);

      /* Now check to see if the new ATS has commands in it */
      if (AtsInfoPtr->NumberOfCommands > 0) {
        /* stop the current ATS */
        SC_KillAts();

        /*
         ** Start the new ATS: Notice that we are starting the new
         ** ATS with a one second offset from the current second,
         ** This prevents commands that were executed the same
         ** second that this command was received from being repeated.
         */
        if (SC_BeginAts(NewAtsIndex, 1)) {
          SC_OperData.AtsCtrlBlckAddr->AtpState = SC_Status_EXECUTING;

          CFE_EVS_SendEvent(SC_ATS_SERVICE_SWTCH_INF_EID, CFE_EVS_EventType_INFORMATION,
                            "ATS Switched from %c to %c", SC_IDX_AS_CHAR(OldAtsIndex),
                            SC_IDX_AS_CHAR(NewAtsIndex));

        } /* end if */
      } else { /* the other ATS does not have any commands in it */

        CFE_EVS_SendEvent(SC_SERVICE_SWITCH_ATS_CMD_LDED_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Switch ATS Failure: Destination ATS is empty");
      } /* end if */
    } else { /* the ATP is not currently executing any commands */
      /* this should only happen if the switch flag gets */
      /* corrupted some how                              */

      CFE_EVS_SendEvent(SC_ATS_SERVICE_SWITCH_IDLE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Switch ATS Rejected: ATP is idle");
    } /* end if */

    /* in any case, this flag will need to be cleared */
    SC_OperData.AtsCtrlBlckAddr->SwitchPendFlag = FALSE;

  } /* end if */
}

/*******************************************************************************/
// Switch immediately, with NO time offset, and leave the ATP in **SC_Status_STARTING** -- the one
// state that exists for this one caller. See the file header.
//
// NOTE IT DOES NOT CHECK THAT AN ATS IS RUNNING. SC_SwitchAtsCmd and SC_ServiceSwitchPend both
// test AtpState first; this one goes straight to SC_ToggleAtsIndex, which reads
// `AtsCtrlBlckAddr->CurrAtsNum` whatever it holds. Its only caller is the ATS processor, which
// cannot reach it with an idle ATP -- the same "promises nothing on its own" shape
// SC_ToggleAtsIndex has in sc_utils.HC.
Bool SC_InlineSwitch()
{
  U16 NewAtsIndex; /* the index of the ats to switch to*/
  U16 OldAtsIndex; /* the index of the ats to switch from*/
  Bool ReturnCode; /* return code for function */
  SC_AtsInfoTable_t *AtsInfoPtr;

  /* figure out which ATS to switch to */
  NewAtsIndex = SC_ToggleAtsIndex();

  /* Save the ATS number to switch FROM */
  OldAtsIndex = SC_AtsNumToIndex(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum);

  /* Now check to see if the new ATS has commands in it */
  AtsInfoPtr = SC_GetAtsInfoObject(NewAtsIndex);
  if (AtsInfoPtr->NumberOfCommands > 0) {
    /*
     ** Stop the current ATS
     */
    SC_KillAts();

    /*
     ** Start up the other ATS
     */
    if (SC_BeginAts(NewAtsIndex, 0)) {
      SC_OperData.AtsCtrlBlckAddr->AtpState = SC_Status_STARTING;

      CFE_EVS_SendEvent(SC_ATS_INLINE_SWTCH_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "ATS Switched from %c to %c", SC_IDX_AS_CHAR(OldAtsIndex),
                        SC_IDX_AS_CHAR(NewAtsIndex));

      /*
       **  Update the command counter and return code
       */
      SC_OperData.HkPacket.Payload.CmdCtr++;
      ReturnCode = TRUE;
    } else { /* all of the commands in the new ats were skipped */

      /*
       ** update the command error counter
       */
      SC_OperData.HkPacket.Payload.CmdErrCtr++;
      ReturnCode = FALSE;

    } /* end if */
  } else { /* the other ATS does not have any commands in it */
    CFE_EVS_SendEvent(SC_ATS_INLINE_SWTCH_NOT_LDED_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Switch ATS Failure: Destination ATS Not Loaded");
    /*
     ** update the ATS error counter
     */
    SC_OperData.HkPacket.Payload.CmdErrCtr++;
    ReturnCode = FALSE;

  } /* end if */

  /* clear out the global ground-switch pend flag */
  SC_OperData.AtsCtrlBlckAddr->SwitchPendFlag = FALSE;

  return ReturnCode;
}

/*******************************************************************************/
// Move the running ATS's clock forward. **The twin of SC_BeginAts's loop, and the one `if` that
// differs is the whole point** -- see the file header: a jump marks a command SKIPPED only if it
// was LOADED, preserving the history a start would overwrite.
I32 SC_JumpAtsCmd(SC_JumpAtsCmd_t *Cmd)
{
  SC_AtsEntryHeader_t *Entry;                 /* ATS table entry pointer */
  SC_AtsCmdEntryOffsetRecord_t *CmdOffsetRec; /* ATS entry location in table */
  U32 JumpTime;                               /* the time to jump to in the ATS */
  U32 ListCmdTime;                            /* list entry execution time */
  U16 AtsIndex;                               /* index of the ATS that is running */
  U16 TimeIndex;                              /* the current time buffer index */
  U16 CmdIndex;                               /* ATS command index (cmd num - 1) */
  U8 TimeBuffer[CFE_TIME_PRINTED_STRING_SIZE];
  CFE_TIME_SysTime NewTime;
  U16 NumSkipped;
  SC_AtsInfoTable_t *AtsInfoPtr;
  SC_AtsCmdStatusEntry_t *StatusEntryPtr;
  SC_AtsCmdNumRecord_t *CmdNumRec; /* THE HOISTS -- see below */
  SC_AtsEntry_t *AtsEntry;

  if (SC_OperData.AtsCtrlBlckAddr->AtpState == SC_Status_EXECUTING) {
    JumpTime = Cmd->Payload.NewTime;
    AtsIndex = SC_AtsNumToIndex(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum);
    AtsInfoPtr = SC_GetAtsInfoObject(AtsIndex);

    /*
     ** Loop through the commands until a time tag is found
     ** that has a time greater than or equal to the current time OR
     ** all of the commands have been skipped
     */
    TimeIndex = SC_SEQUENCE_IDX_FIRST;
    CmdIndex = SC_COMMAND_IDX_C(0); /* updated in loop */
    NumSkipped = 0;

    while (SC_IDX_WITHIN_LIMIT(TimeIndex, AtsInfoPtr->NumberOfCommands)) {
      /* first get the cmd index at this list entry */
      // **CALL-ARROW HOIST 5 OF 12.**
      CmdNumRec = SC_GetAtsCommandNumAtSeq(AtsIndex, TimeIndex);
      CmdIndex = SC_CommandNumToIndex(CmdNumRec->CmdNum);
      if (!SC_AtsCommandIndexIsValid(CmdIndex)) {
        SC_IDX_INCREMENT(TimeIndex);
        continue;
      }

      /* then get the entry index from the cmd index table */
      CmdOffsetRec = SC_GetAtsEntryOffsetForCmd(AtsIndex, CmdIndex);
      /* then get a pointer to the ATS entry data */
      // **CALL-ARROW HOIST 6 OF 12.**
      AtsEntry = SC_GetAtsEntryAtOffset(AtsIndex, CmdOffsetRec->Offset);
      Entry = &AtsEntry->Header;
      /* then get cmd execution time from the ATS entry */
      ListCmdTime = SC_GetAtsEntryTime(Entry);

      /* compare ATS jump time to this list entry time */
      if (SC_CompareAbsTime(JumpTime, ListCmdTime)) {
        /* jump time is greater than this list entry time */

        /*
        ** If the ATS command is loaded and ready to run, then
        **  mark the command as being skipped
        **  if the command has any other status, SC_Status_SKIPPED, SC_Status_EXECUTED,
        **   etc, then leave the status alone.
        */
        StatusEntryPtr = SC_GetAtsStatusEntryForCommand(AtsIndex, CmdIndex);
        // **THE ONE `if` THAT SC_BeginAts DOES NOT HAVE.** See the file header.
        if (StatusEntryPtr->Status == SC_Status_LOADED) {
          StatusEntryPtr->Status = SC_Status_SKIPPED;
          NumSkipped++;
        }

        SC_IDX_INCREMENT(TimeIndex);
      } else {
        /* jump time is less than or equal to this list entry */
        CFE_EVS_SendEvent(SC_JUMPATS_CMD_LIST_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "Jump Cmd: Jump time less than or equal to list entry %u",
                          SC_IDX_AS_UINT(CmdIndex));
        break;
      }
    }

    /*
     ** Check to see if the whole ATS was skipped
     */
    if (!SC_IDX_WITHIN_LIMIT(TimeIndex, AtsInfoPtr->NumberOfCommands)) {
      CFE_EVS_SendEvent(SC_JUMPATS_CMD_STOPPED_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Jump Cmd: All ATS commands were skipped, ATS stopped");

      SC_OperData.HkPacket.Payload.CmdErrCtr++;

      /* stop the ats */
      SC_KillAts();
    } else { /* there is at least one command to execute */

      /*
       ** Update the ATP Control Block entries.
       */
      // **NOTE WHAT IS NOT UPDATED: `CurrAtsNum`.** SC_BeginAts sets it; a jump does not, because
      // a jump stays within the ATS that is already running. Two of the three fields, deliberately.
      SC_OperData.AtsCtrlBlckAddr->CmdNumber = SC_CommandIndexToNum(CmdIndex);
      SC_OperData.AtsCtrlBlckAddr->TimeIndexPtr = TimeIndex;

      /*
       ** Set the next command time for the ATP
       */
      SC_AppData.NextCmdTime[SC_Process_ATP] = ListCmdTime;

      SC_OperData.HkPacket.Payload.CmdCtr++;

      /* print out the date in a readable format */
      NewTime.Seconds = ListCmdTime;
      NewTime.Subseconds = 0;

      // NASA writes `(char *)&TimeBuffer`, taking the address OF AN ARRAY -- the same address as
      // the array itself, with a different type, which the cast then discards. HolyC has no
      // pointer-to-array type and the array name is already the address, so the name is passed.
      CFE_TIME_Print(TimeBuffer, NewTime);

      CFE_EVS_SendEvent(SC_JUMP_ATS_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Next ATS command time in the ATP was set to %s", TimeBuffer);
      if (NumSkipped > 0) {
        /* We skipped come commands, but not all of them */
        CFE_EVS_SendEvent(SC_JUMP_ATS_SKIPPED_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "Jump Cmd: Skipped %d ATS commands", NumSkipped);
      }

    } /* end if */
  }

  else { /*  There is not a running ATS */

    CFE_EVS_SendEvent(SC_JUMPATS_CMD_NOT_ACT_ERR_EID, CFE_EVS_EventType_ERROR,
                      "ATS Jump Failed: No active ATS");
    SC_OperData.HkPacket.Payload.CmdErrCtr++;

  } /* end if */

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Set whether an ATS keeps running after a command fails.
//
// **THE ONLY SC COMMAND THAT VALIDATES ITS PAYLOAD AGAINST AN EXPLICIT PAIR OF VALUES** -- not a
// range, not a bound, but `!= TRUE && != FALSE`. So 2 is rejected where every other SC command
// would have taken it. The field is a uint8 from the ground, so 254 of its 256 values are refused.
I32 SC_ContinueAtsOnFailureCmd(SC_ContinueAtsOnFailureCmd_t *Cmd)
{
  U8 State;

  State = Cmd->Payload.ContinueState;

  if (State != SC_AtsCont_TRUE && State != SC_AtsCont_FALSE) {
    SC_OperData.HkPacket.Payload.CmdErrCtr++;

    CFE_EVS_SendEvent(SC_CONT_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Continue ATS On Failure command  failed, invalid state: %lu", State);
  } else {
    SC_OperData.HkPacket.Payload.ContinueAtsOnFailureFlag = State;

    SC_OperData.HkPacket.Payload.CmdCtr++;

    CFE_EVS_SendEvent(SC_CONT_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Continue-ATS-On-Failure command, State: %lu", State);
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Append the uploaded append table to an existing ATS. **FOUR REJECTIONS AND ONE EARLY `return`**
// -- the invalid-ATS case returns immediately while the other three fall through the else-chain,
// which is the only `return` in the middle of an SC command handler.
//
// AND THE FIT CHECK IS IN 32-BIT WORDS: `AtsSize + AppendWordCount > SC_ATS_BUFF_SIZE32`, which is
// 4000 and not the configured 8000 -- see sc_cfg.HC on SC's three word units.
I32 SC_AppendAtsCmd(SC_AppendAtsCmd_t *Cmd)
{
  U16 AtsIndex; /* index (not ID) of target ATS */
  SC_AtsInfoTable_t *AtsInfoPtr;

  if (!SC_AtsNumIsValid(Cmd->Payload.AtsNum)) {
    /* invalid target ATS selection */
    SC_OperData.HkPacket.Payload.CmdErrCtr++;

    CFE_EVS_SendEvent(SC_APPEND_CMD_ARG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Append ATS error: invalid ATS ID = %u", SC_IDNUM_AS_UINT(Cmd->Payload.AtsNum));

    return CFE_SUCCESS;
  }

  /* create base zero array index from base one ID value */
  AtsIndex = SC_AtsNumToIndex(Cmd->Payload.AtsNum);
  AtsInfoPtr = SC_GetAtsInfoObject(AtsIndex);

  if (AtsInfoPtr->NumberOfCommands == 0) {
    /* target ATS table is empty */
    SC_OperData.HkPacket.Payload.CmdErrCtr++;

    CFE_EVS_SendEvent(SC_APPEND_CMD_TGT_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Append ATS %c error: ATS table is empty", SC_IDX_AS_CHAR(AtsIndex));
  } else if (SC_OperData.HkPacket.Payload.AppendEntryCount == 0) {
    /* append table is empty */
    SC_OperData.HkPacket.Payload.CmdErrCtr++;

    CFE_EVS_SendEvent(SC_APPEND_CMD_SRC_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Append ATS %c error: Append table is empty", SC_IDX_AS_CHAR(AtsIndex));
  } else if (AtsInfoPtr->AtsSize + SC_AppData.AppendWordCount > SC_ATS_BUFF_SIZE32) {
    /* not enough room in ATS buffer for Append table data */
    SC_OperData.HkPacket.Payload.CmdErrCtr++;

    CFE_EVS_SendEvent(SC_APPEND_CMD_FIT_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Append ATS %c error: ATS size = %d, Append size = %d, ATS buffer = %d",
                      SC_IDX_AS_CHAR(AtsIndex), AtsInfoPtr->AtsSize, SC_AppData.AppendWordCount,
                      SC_ATS_BUFF_SIZE32);
  } else {
    /* store ATS selection from most recent ATS Append command */
    SC_OperData.HkPacket.Payload.AppendCmdArg = Cmd->Payload.AtsNum;

    // **THIS CALL IS THE CYCLE EDGE, AND IT IS A STAND-IN UNTIL sc_loads.c IS GATED.**
    // SC_ProcessAppend is the function that actually copies the append buffer into the ATS and
    // recomputes its timing. The driver's stand-in does NOTHING, so the success event below
    // reports an append that did not happen -- which is UPSTREAM LOGIC missing, not a seam, and
    // the exercise must not claim to drive this arm until sc_loads.HC lands.
    /* copy append data and re-calc timing data */
    SC_ProcessAppend(AtsIndex);

    /* increment command success counter */
    SC_OperData.HkPacket.Payload.CmdCtr++;

    CFE_EVS_SendEvent(SC_APPEND_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Append ATS %c command: %d ATS entries appended", SC_IDX_AS_CHAR(AtsIndex),
                      SC_OperData.HkPacket.Payload.AppendEntryCount);
  }

  return CFE_SUCCESS;
}

#endif
