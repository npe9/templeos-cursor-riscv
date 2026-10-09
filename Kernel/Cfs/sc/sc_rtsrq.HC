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
// STORED COMMAND'S RTS REQUESTS -- the 1:1 translation of NASA's fsw/src/sc_rtsrq.c, 619 lines and
// ten functions: four singular commands, their four group twins, the kill routine they share and
// the auto-start.
//
// ### A GROUP COMMAND THAT MODIFIES NOTHING IS STILL A SUCCESSFUL COMMAND
//
// All four group handlers have the same shape: validate the range, loop, and then
//
//     CFE_EVS_SendEvent(..._INF_EID, ..., "... Modified=%d", (int)StartCount);
//     SC_OperData.HkPacket.Payload.CmdCtr++;
//
// **`CmdCtr++` IS OUTSIDE THE LOOP AND UNCONDITIONAL.** So a Start RTS Group where every single
// RTS is disabled increments the error counter once per RTS *and* the success counter once for the
// command -- and the only evidence is `Modified=0` in the information event. The singular
// handlers do the opposite: `SC_StartRtsCmd` increments CmdCtr INSIDE its innermost success arm,
// so a rejected single start never counts as a command.
//
// That is defensible as "the command was well formed and was executed" and it means
// CmdCtr and CmdErrCtr do not add up to the number of commands received. Kept exactly; the
// exercise drives an all-disabled group so the pair of counters is in the transcript.
//
// ### `SC_KillRts` FORMS A POINTER BEFORE IT CHECKS THE INDEX
//
//     RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);     /* &RtsInfoTblAddr[RtsIndex] */
//     if (!SC_RtsIndexIsValid(RtsIndex)) { ... }      /* ... and only NOW is it checked */
//
// For an out-of-range index that computes an out-of-bounds address, which C leaves undefined even
// when the pointer is never dereferenced -- and on the invalid path it is not: the `if` catches it
// and the `else if` that reads `RtsInfoPtr->RtsStatus` is skipped. So nothing is read out of
// bounds and the only defect is the address arithmetic itself. Kept verbatim, because moving the
// call below the check would be repairing NASA rather than translating it; the exercise drives an
// invalid index so the error event is in the transcript.
//
// ### THE AUTO-START SENDS SC A COMMAND INSTEAD OF CALLING ITS OWN HANDLER
//
// `SC_AutoStartRts` builds an `SC_StartRtsCmd_t`, stamps it with SC_CMD_MID and SC_START_RTS_CC,
// and **puts it on the software bus** -- so SC's own initialisation queues a command for SC to
// receive on a later wakeup. It does not call SC_StartRtsCmd. That is what makes the auto-start
// observable to anything watching the bus, and it is why the RTS does not actually start during
// init: it starts when the command comes back round.
//
// ### AND TWO OF THE TWELVE CALL-ARROW SITES ARE HERE
//
// NASA writes `SC_GetRtsEntryAtOffset(RtsIndex, SC_ENTRY_OFFSET_FIRST)->Header` twice. That is a
// call followed by `->`, which docs/HOLYC_STRUCT_LIMITS.md records as OPEN: HolyC resolves the
// arrow against the FIRST ARGUMENT's class, these accessors take scalars, and the access SILENTLY
// LOADS THROUGH ZERO. Both are hoisted to a typed local below and marked. docs/CFS_PLAN.md counted
// twelve across SC before translation started; these are numbers 1 and 2.
#ifndef SC_RTSRQ_HC
#define SC_RTSRQ_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// sc_cfg.HC, sc_tbl.HC, sc_msg.HC, sc_global.HC, sc_events.HC, sc_utils.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13.

// --- sc_rtsrq.h's prototypes -------------------------------------------------------------------
I32 SC_StartRtsCmd(SC_StartRtsCmd_t *Cmd);
I32 SC_StartRtsGrpCmd(SC_StartRtsGrpCmd_t *Cmd);
I32 SC_StopRtsCmd(SC_StopRtsCmd_t *Cmd);
I32 SC_StopRtsGrpCmd(SC_StopRtsGrpCmd_t *Cmd);
I32 SC_DisableRtsCmd(SC_DisableRtsCmd_t *Cmd);
I32 SC_DisableRtsGrpCmd(SC_DisableRtsGrpCmd_t *Cmd);
I32 SC_EnableRtsCmd(SC_EnableRtsCmd_t *Cmd);
I32 SC_EnableRtsGrpCmd(SC_EnableRtsGrpCmd_t *Cmd);
U0 SC_KillRts(U16 RtsIndex);
U0 SC_AutoStartRts(U16 RtsNum);

/*******************************************************************************/
// Start one RTS. Four nested conditions -- valid number, not disabled, LOADED, and a first
// command whose length field is sane -- and each failure has its own event and bumps BOTH
// CmdErrCtr and RtsActiveErrCtr.
I32 SC_StartRtsCmd(SC_StartRtsCmd_t *Cmd)
{
  U16 RtsNum;                       /* rts number */
  U16 RtsIndex;                     /* rts array index */
  SC_RtsEntryHeader_t *RtsEntryPtr; /* pointer to an rts entry */
  CFE_MSG_Message *RtsEntryCmd;     /* pointer to an rts command */
  I64 CmdLength = 0;                /* the length of the 1st cmd */
  SC_RtsInfoEntry_t *RtsInfoPtr;
  SC_RtsEntry_t *RtsEntry; /* THE HOIST -- see below */

  /*
   ** Check start RTS parameters
   */
  RtsNum = Cmd->Payload.RtsNum;

  if (SC_RtsNumIsValid(RtsNum)) {
    /* convert RTS ID to RTS array index */
    RtsIndex = SC_RtsNumToIndex(RtsNum);
    RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);

    /* make sure that RTS is not disabled */
    if (RtsInfoPtr->DisabledFlag == FALSE) {
      /* the requested RTS is not being used and is not empty */
      if (RtsInfoPtr->RtsStatus == SC_Status_LOADED) {
        /*
         ** Check the command length
         */
        // **CALL-ARROW HOIST 1 OF 12.** NASA writes
        //     RtsEntryPtr = &SC_GetRtsEntryAtOffset(RtsIndex, SC_ENTRY_OFFSET_FIRST)->Header;
        // and a call followed by `->` loads through zero in HolyC -- see the file header.
        RtsEntry = SC_GetRtsEntryAtOffset(RtsIndex, SC_ENTRY_OFFSET_FIRST);
        RtsEntryPtr = &RtsEntry->Header;
        // AND THE `U8` CAST IS LOAD-BEARING, THOUGH IT LOOKS REDUNDANT HERE. NASA casts to
        // `uint8_t *` before adding SC_RTS_HEADER_SIZE so the 4 is FOUR BYTES. It happens that
        // sizeof(SC_RtsEntryHeader_t) is also 4, so dropping the cast would give the same answer
        // in this one case and a wrong one the moment the header grows. Kept.
        RtsEntryCmd = (RtsEntryPtr(U8 *) + SC_RTS_HEADER_SIZE)(CFE_MSG_Message *);

        CFE_MSG_GetSize(RtsEntryCmd, &CmdLength);

        /* Make sure the command is big enough, but not too big  */
        if (CmdLength >= SC_PACKET_MIN_SIZE && CmdLength <= SC_PACKET_MAX_SIZE) {
          /*
           **  Initialize the RTS info table entry
           */
          RtsInfoPtr->RtsStatus = SC_Status_EXECUTING;
          RtsInfoPtr->CmdCtr = 0;
          RtsInfoPtr->CmdErrCtr = 0;
          RtsInfoPtr->NextCommandPtr = SC_ENTRY_OFFSET_FIRST;
          RtsInfoPtr->UseCtr++;

          /*
           ** Get the absolute wakeup count for the RTS's next_command_tgt_wakeup
           ** using the current wakeup count and the relative wakeup count.
           */
          RtsInfoPtr->NextCommandTgtWakeup = SC_ComputeAbsWakeup(RtsEntryPtr->WakeupCount);

          /*
           ** Last, Increment some global counters associated with the
           ** starting of the RTS
           */
          SC_OperData.RtsCtrlBlckAddr->NumRtsActive++;
          SC_OperData.HkPacket.Payload.RtsActiveCtr++;
          SC_OperData.HkPacket.Payload.CmdCtr++;

          // WHETHER THIS RTS ANNOUNCES ITSELF: RTS 1..SC_LAST_RTS_WITH_EVENTS get an
          // INFORMATION event, the rest a DEBUG one. With four RTSs configured and the
          // threshold at 3, exactly one of the four is quiet -- see sc_tbl.HC.
          if (SC_RtsNumHasEvent(Cmd->Payload.RtsNum)) {
            CFE_EVS_SendEvent(SC_RTS_START_INF_EID, CFE_EVS_EventType_INFORMATION,
                              "RTS Number %03u Started", SC_IDNUM_AS_UINT(RtsNum));
          } else {
            CFE_EVS_SendEvent(SC_STARTRTS_CMD_DBG_EID, CFE_EVS_EventType_DEBUG,
                              "Start RTS #%u command", SC_IDNUM_AS_UINT(RtsNum));
          }
        } else { /* the length field of the 1st cmd was bad */
          CFE_EVS_SendEvent(SC_STARTRTS_CMD_INVLD_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Start RTS %03u Rejected: Invld Len Field for 1st Cmd in Sequence. Invld Cmd Length = %lu",
                            SC_IDNUM_AS_UINT(RtsNum), CmdLength);

          SC_OperData.HkPacket.Payload.CmdErrCtr++;
          SC_OperData.HkPacket.Payload.RtsActiveErrCtr++;

        } /* end if - check command number */
      } else { /* Cannot use the RTS now */

        CFE_EVS_SendEvent(SC_STARTRTS_CMD_NOT_LDED_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Start RTS %03u Rejected: RTS Not Loaded or In Use, Status: %lu",
                          SC_IDNUM_AS_UINT(Cmd->Payload.RtsNum), RtsInfoPtr->RtsStatus);

        SC_OperData.HkPacket.Payload.CmdErrCtr++;
        SC_OperData.HkPacket.Payload.RtsActiveErrCtr++;

      } /* end if */
    } else { /* the RTS is disabled */
      CFE_EVS_SendEvent(SC_STARTRTS_CMD_DISABLED_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Start RTS %03u Rejected: RTS Disabled", SC_IDNUM_AS_UINT(RtsNum));

      SC_OperData.HkPacket.Payload.CmdErrCtr++;
      SC_OperData.HkPacket.Payload.RtsActiveErrCtr++;
    } /* end if */
  } else { /* the rts id is invalid */
    CFE_EVS_SendEvent(SC_STARTRTS_CMD_INVALID_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Start RTS %03u Rejected: Invalid RTS ID", SC_IDNUM_AS_UINT(RtsNum));

    SC_OperData.HkPacket.Payload.CmdErrCtr++;
    SC_OperData.HkPacket.Payload.RtsActiveErrCtr++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Start a range of RTSs. See the file header: `CmdCtr++` is unconditional, so a group where
// nothing started still counts as a successful command.
I32 SC_StartRtsGrpCmd(SC_StartRtsGrpCmd_t *Cmd)
{
  U16 FirstRtsNum;
  U16 LastRtsNum;
  U16 FirstIndex; /* RTS array index */
  U16 LastIndex;
  U16 RtsIndex;
  I32 StartCount = 0;
  SC_RtsInfoEntry_t *RtsInfoPtr;
  SC_RtsEntry_t *RtsEntry; /* THE HOIST -- see below */

  FirstRtsNum = Cmd->Payload.FirstRtsNum;
  LastRtsNum = Cmd->Payload.LastRtsNum;

  /* make sure the specified group is valid */
  if (SC_RtsNumValidateRange(FirstRtsNum, LastRtsNum)) {
    /* convert RTS ID to RTS array index */
    FirstIndex = SC_RtsNumToIndex(FirstRtsNum);
    LastIndex = SC_RtsNumToIndex(LastRtsNum);

    for (RtsIndex = FirstIndex; SC_IDX_LESS_OR_EQ(RtsIndex, LastIndex);
         SC_IDX_INCREMENT(RtsIndex)) {
      RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);

      /* make sure that RTS is not disabled, empty or executing */
      if (RtsInfoPtr->DisabledFlag == FALSE) {
        if (RtsInfoPtr->RtsStatus == SC_Status_LOADED) {
          /* initialize the RTS info table entry */
          RtsInfoPtr->RtsStatus = SC_Status_EXECUTING;
          RtsInfoPtr->CmdCtr = 0;
          RtsInfoPtr->CmdErrCtr = 0;
          RtsInfoPtr->NextCommandPtr = SC_ENTRY_OFFSET_FIRST;
          RtsInfoPtr->UseCtr++;

          /* get absolute wakeup count for 1st cmd in the RTS */
          // **CALL-ARROW HOIST 2 OF 12.** NASA writes the accessor call and `->Header.WakeupCount`
          // inline as SC_ComputeAbsWakeup's argument -- see the file header.
          RtsEntry = SC_GetRtsEntryAtOffset(RtsIndex, SC_ENTRY_OFFSET_FIRST);
          RtsInfoPtr->NextCommandTgtWakeup = SC_ComputeAbsWakeup(RtsEntry->Header.WakeupCount);

          /* maintain counters associated with starting RTS */
          SC_OperData.RtsCtrlBlckAddr->NumRtsActive++;
          SC_OperData.HkPacket.Payload.RtsActiveCtr++;

          /* count the RTS that were actually started */
          StartCount++;
        } else { /* Cannot use the RTS now */
          CFE_EVS_SendEvent(SC_STARTRTSGRP_CMD_NOT_LDED_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Start RTS group error: rejected RTS ID %03u, RTS Not Loaded or In Use, Status: %lu",
                            SC_IDNUM_AS_UINT(SC_RtsIndexToNum(RtsIndex)), RtsInfoPtr->RtsStatus);

          SC_OperData.HkPacket.Payload.RtsActiveErrCtr++;

        } /* end if */
      } else { /* the RTS is disabled */
        CFE_EVS_SendEvent(SC_STARTRTSGRP_CMD_DISABLED_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Start RTS group error: rejected RTS ID %03u, RTS Disabled",
                          SC_IDNUM_AS_UINT(SC_RtsIndexToNum(RtsIndex)));

        SC_OperData.HkPacket.Payload.RtsActiveErrCtr++;

      } /* end if */
    }

    /* success */
    CFE_EVS_SendEvent(SC_STARTRTSGRP_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Start RTS group: FirstID=%u, LastID=%u, Modified=%d",
                      SC_IDNUM_AS_UINT(FirstRtsNum), SC_IDNUM_AS_UINT(LastRtsNum), StartCount);
    SC_OperData.HkPacket.Payload.CmdCtr++;
  } else { /* error */
    CFE_EVS_SendEvent(SC_STARTRTSGRP_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Start RTS group error: FirstID=%u, LastID=%u", SC_IDNUM_AS_UINT(FirstRtsNum),
                      SC_IDNUM_AS_UINT(LastRtsNum));
    SC_OperData.HkPacket.Payload.CmdErrCtr++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Stop one RTS. **NOTE IT DOES NOT CHECK WHETHER THE RTS WAS RUNNING** -- SC_KillRts does, and it
// is silent about an RTS that was already stopped, so "RTS %03u Aborted" is sent for an idle RTS
// as readily as for an executing one.
I32 SC_StopRtsCmd(SC_StopRtsCmd_t *Cmd)
{
  U16 RtsNum;   /* RTS number */
  U16 RtsIndex; /* RTS array index */

  RtsNum = Cmd->Payload.RtsNum;

  /* check the command parameter */
  if (SC_RtsNumIsValid(RtsNum)) {
    /* convert RTS ID to RTS array index */
    RtsIndex = SC_RtsNumToIndex(RtsNum);

    /* stop the rts by calling a generic routine */
    SC_KillRts(RtsIndex);

    SC_OperData.HkPacket.Payload.CmdCtr++;

    CFE_EVS_SendEvent(SC_STOPRTS_CMD_INF_EID, CFE_EVS_EventType_INFORMATION, "RTS %03u Aborted",
                      SC_IDNUM_AS_UINT(RtsNum));
  } else { /* the specified RTS is invalid */

    /* the rts id is invalid */
    CFE_EVS_SendEvent(SC_STOPRTS_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Stop RTS %03u rejected: Invalid RTS ID", SC_IDNUM_AS_UINT(RtsNum));

    SC_OperData.HkPacket.Payload.CmdErrCtr++;

  } /* end if */

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Stop a range of RTSs. **THE ONLY GROUP HANDLER THAT TESTS BEFORE ACTING** -- it counts an RTS
// only if it was EXECUTING, where the enable and disable groups test the flag and the start group
// tests the status. So `Modified=` means something different in each of the four.
I32 SC_StopRtsGrpCmd(SC_StopRtsGrpCmd_t *Cmd)
{
  U16 FirstRtsNum;
  U16 LastRtsNum;
  U16 FirstIndex; /* RTS array index */
  U16 LastIndex;
  U16 RtsIndex;
  I32 StopCount = 0;
  SC_RtsInfoEntry_t *RtsInfoPtr;

  FirstRtsNum = Cmd->Payload.FirstRtsNum;
  LastRtsNum = Cmd->Payload.LastRtsNum;

  /* make sure the specified group is valid */
  if (SC_RtsNumValidateRange(FirstRtsNum, LastRtsNum)) {
    /* convert RTS ID to RTS array index */
    FirstIndex = SC_RtsNumToIndex(FirstRtsNum);
    LastIndex = SC_RtsNumToIndex(LastRtsNum);

    for (RtsIndex = FirstIndex; SC_IDX_LESS_OR_EQ(RtsIndex, LastIndex);
         SC_IDX_INCREMENT(RtsIndex)) {
      RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);

      /* count the entries that were actually stopped */
      if (RtsInfoPtr->RtsStatus == SC_Status_EXECUTING) {
        SC_KillRts(RtsIndex);
        StopCount++;
      }
    }

    /* success */
    CFE_EVS_SendEvent(SC_STOPRTSGRP_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Stop RTS group: FirstID=%u, LastID=%u, Modified=%d",
                      SC_IDNUM_AS_UINT(FirstRtsNum), SC_IDNUM_AS_UINT(LastRtsNum), StopCount);
    SC_OperData.HkPacket.Payload.CmdCtr++;
  } else { /* error */
    CFE_EVS_SendEvent(SC_STOPRTSGRP_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Stop RTS group error: FirstID=%u, LastID=%u", SC_IDNUM_AS_UINT(FirstRtsNum),
                      SC_IDNUM_AS_UINT(LastRtsNum));
    SC_OperData.HkPacket.Payload.CmdErrCtr++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable one RTS. **NO STATE CHECK AT ALL** -- disabling an already-disabled RTS succeeds and
// reports success, and disabling an EXECUTING RTS sets the flag without stopping it. The flag only
// prevents a START; it does not interrupt a run.
I32 SC_DisableRtsCmd(SC_DisableRtsCmd_t *Cmd)
{
  U16 RtsNum;   /* RTS number */
  U16 RtsIndex; /* RTS array index */
  SC_RtsInfoEntry_t *RtsInfoPtr;

  RtsNum = Cmd->Payload.RtsNum;

  /* make sure tha specified rts is valid */
  if (SC_RtsNumIsValid(RtsNum)) {
    /* convert RTS ID to RTS array index */
    RtsIndex = SC_RtsNumToIndex(RtsNum);
    RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);

    /* disable the RTS */
    RtsInfoPtr->DisabledFlag = TRUE;

    /* update the command status */
    SC_OperData.HkPacket.Payload.CmdCtr++;

    CFE_EVS_SendEvent(SC_DISABLE_RTS_INF_EID, CFE_EVS_EventType_INFORMATION, "Disabled RTS %03u",
                      SC_IDNUM_AS_UINT(RtsNum));
  } else { /* it is not a valid RTS id */
    CFE_EVS_SendEvent(SC_DISRTS_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Disable RTS %03u Rejected: Invalid RTS ID", SC_IDNUM_AS_UINT(RtsNum));

    /* update the command error status */
    SC_OperData.HkPacket.Payload.CmdErrCtr++;
  } /* end if */

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable a range of RTSs. Counts only the ones that were ENABLED, so `Modified=` is the number
// of flags that actually changed -- unlike the singular version, which reports success either way.
I32 SC_DisableRtsGrpCmd(SC_DisableRtsGrpCmd_t *Cmd)
{
  U16 FirstRtsNum;
  U16 LastRtsNum;
  U16 FirstIndex; /* RTS array index */
  U16 LastIndex;
  U16 RtsIndex;
  I32 DisableCount = 0;
  SC_RtsInfoEntry_t *RtsInfoPtr;

  FirstRtsNum = Cmd->Payload.FirstRtsNum;
  LastRtsNum = Cmd->Payload.LastRtsNum;

  /* make sure the specified group is valid */
  if (SC_RtsNumValidateRange(FirstRtsNum, LastRtsNum)) {
    /* convert RTS ID to RTS array index */
    FirstIndex = SC_RtsNumToIndex(FirstRtsNum);
    LastIndex = SC_RtsNumToIndex(LastRtsNum);

    for (RtsIndex = FirstIndex; SC_IDX_LESS_OR_EQ(RtsIndex, LastIndex);
         SC_IDX_INCREMENT(RtsIndex)) {
      RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);

      /* count the entries that were actually disabled */
      if (RtsInfoPtr->DisabledFlag == FALSE) {
        DisableCount++;
        RtsInfoPtr->DisabledFlag = TRUE;
      }
    }

    /* success */
    CFE_EVS_SendEvent(SC_DISRTSGRP_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Disable RTS group: FirstID=%u, LastID=%u, Modified=%d",
                      SC_IDNUM_AS_UINT(FirstRtsNum), SC_IDNUM_AS_UINT(LastRtsNum), DisableCount);
    SC_OperData.HkPacket.Payload.CmdCtr++;
  } else { /* error */
    CFE_EVS_SendEvent(SC_DISRTSGRP_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Disable RTS group error: FirstID=%u, LastID=%u",
                      SC_IDNUM_AS_UINT(FirstRtsNum), SC_IDNUM_AS_UINT(LastRtsNum));
    SC_OperData.HkPacket.Payload.CmdErrCtr++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable one RTS. The mirror of the disable, with the same absence of a state check.
I32 SC_EnableRtsCmd(SC_EnableRtsCmd_t *Cmd)
{
  U16 RtsNum;   /* RTS number */
  U16 RtsIndex; /* RTS array index */
  SC_RtsInfoEntry_t *RtsInfoPtr;

  RtsNum = Cmd->Payload.RtsNum;

  /* make sure the specified rts is valid */
  if (SC_RtsNumIsValid(RtsNum)) {
    /* convert RTS ID to RTS array index */
    RtsIndex = SC_RtsNumToIndex(RtsNum);
    RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);

    /* re-enable the RTS */
    RtsInfoPtr->DisabledFlag = FALSE;

    /* update the command status */
    SC_OperData.HkPacket.Payload.CmdCtr++;

    CFE_EVS_SendEvent(SC_ENABLE_RTS_INF_EID, CFE_EVS_EventType_INFORMATION, "Enabled RTS %03u",
                      SC_IDNUM_AS_UINT(RtsNum));
  } else { /* it is not a valid RTS id */
    CFE_EVS_SendEvent(SC_ENARTS_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Enable RTS %03u Rejected: Invalid RTS ID", SC_IDNUM_AS_UINT(RtsNum));

    /* update the command error status */
    SC_OperData.HkPacket.Payload.CmdErrCtr++;

  } /* end if */

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable a range of RTSs. **AND THIS ONE COMPARES AGAINST `TRUE`** -- `DisabledFlag == true` --
// where the disable group compares against `false`. Both are NASA's and both are kept; a `Bool`
// holding any non-zero value other than 1 would behave differently in the two, which is the kind
// of asymmetry a translation must not quietly normalise.
I32 SC_EnableRtsGrpCmd(SC_EnableRtsGrpCmd_t *Cmd)
{
  U16 FirstRtsNum;
  U16 LastRtsNum;
  U16 FirstIndex; /* RTS array index */
  U16 LastIndex;
  U16 RtsIndex;
  I32 EnableCount = 0;
  SC_RtsInfoEntry_t *RtsInfoPtr;

  FirstRtsNum = Cmd->Payload.FirstRtsNum;
  LastRtsNum = Cmd->Payload.LastRtsNum;

  /* make sure the specified group is valid */
  if (SC_RtsNumValidateRange(FirstRtsNum, LastRtsNum)) {
    /* convert RTS ID to RTS array index */
    FirstIndex = SC_RtsNumToIndex(FirstRtsNum);
    LastIndex = SC_RtsNumToIndex(LastRtsNum);

    for (RtsIndex = FirstIndex; SC_IDX_LESS_OR_EQ(RtsIndex, LastIndex);
         SC_IDX_INCREMENT(RtsIndex)) {
      RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);

      /* count the entries that were actually enabled */
      if (RtsInfoPtr->DisabledFlag == TRUE) {
        EnableCount++;
        RtsInfoPtr->DisabledFlag = FALSE;
      }
    }

    /* success */
    CFE_EVS_SendEvent(SC_ENARTSGRP_CMD_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Enable RTS group: FirstID=%u, LastID=%u, Modified=%d",
                      SC_IDNUM_AS_UINT(FirstRtsNum), SC_IDNUM_AS_UINT(LastRtsNum), EnableCount);
    SC_OperData.HkPacket.Payload.CmdCtr++;
  } else { /* error */
    CFE_EVS_SendEvent(SC_ENARTSGRP_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Enable RTS group error: FirstID=%u, LastID=%u",
                      SC_IDNUM_AS_UINT(FirstRtsNum), SC_IDNUM_AS_UINT(LastRtsNum));
    SC_OperData.HkPacket.Payload.CmdErrCtr++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Stop an RTS and clear its data. Shared by the stop command, the stop group and the ATS
// processor.
//
// **THE ACCESSOR IS CALLED BEFORE THE INDEX IS VALIDATED** -- see the file header. And note what
// NASA's comment says is deliberately NOT cleared: CmdCtr, CmdErrCtr and NextCommandPtr are left
// alone "to provide information on where the rts stopped", so a stopped RTS keeps its forensics
// until the next start wipes them. That is why SC_StartRtsCmd zeroes those three rather than
// SC_KillRts.
U0 SC_KillRts(U16 RtsIndex)
{
  SC_RtsInfoEntry_t *RtsInfoPtr;

  RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);

  /* validate RTS array index */
  if (!SC_RtsIndexIsValid(RtsIndex)) {
    CFE_EVS_SendEvent(SC_KILLRTS_INV_INDEX_ERR_EID, CFE_EVS_EventType_ERROR,
                      "RTS kill error: invalid RTS index %u", SC_IDX_AS_UINT(RtsIndex));
  } else if (RtsInfoPtr->RtsStatus == SC_Status_EXECUTING) {
    /*
    ** Stop the RTS from executing
    */
    RtsInfoPtr->RtsStatus = SC_Status_LOADED;
    // PARKED AT THE MAXIMUM, not zeroed -- so the stopped RTS's next command can never come due.
    // See sc_msg.HC on SC_MAX_WAKEUP_CNT being a saturation value rather than a sentinel.
    RtsInfoPtr->NextCommandTgtWakeup = SC_MAX_WAKEUP_CNT;

    /*
    ** Note: the rest of the fields are left alone
    ** to provide information on where the
    ** rts stopped. They are cleared out when it is restarted.
    */

    // GUARDED AGAINST UNDERFLOW, and it has to be: NumRtsActive is a uint16, so a double stop
    // without this test would wrap it to 65535 and SC would believe every RTS was running.
    if (SC_OperData.RtsCtrlBlckAddr->NumRtsActive > 0) {
      SC_OperData.RtsCtrlBlckAddr->NumRtsActive--;
    }
  }
}

/*******************************************************************************/
// Start the configured auto-exec RTS after init -- BY SENDING SC A COMMAND. See the file header:
// this does not call SC_StartRtsCmd, it puts a Start RTS command on the software bus addressed to
// SC's own command message id.
U0 SC_AutoStartRts(U16 RtsNum)
{
  SC_StartRtsCmd_t CmdPkt; /* the command packet to start an RTS */
  CFE_MSG_Message *MsgPtr;

  MemSet(&CmdPkt, 0, sizeof(SC_StartRtsCmd_t));
  MsgPtr = &CmdPkt(CFE_MSG_Message *);

  /* validate RTS ID */
  if (SC_RtsNumIsValid(RtsNum)) {
    /*
     ** Format the command packet to start the first RTS
     */
    CFE_MSG_Init(MsgPtr, CFE_SB_ValueToMsgId(SC_CMD_MID), sizeof(SC_StartRtsCmd_t));

    CFE_MSG_SetFcnCode(MsgPtr, SC_START_RTS_CC);

    /*
     ** Get the RTS ID to start.
     */
    CmdPkt.Payload.RtsNum = RtsNum;

    /*
     ** Now send the command back to SC
     */
    CFE_SB_TransmitMsg(MsgPtr, TRUE);
  } else {
    CFE_EVS_SendEvent(SC_AUTOSTART_RTS_INV_ID_ERR_EID, CFE_EVS_EventType_ERROR,
                      "RTS autostart error: invalid RTS ID %u", SC_IDNUM_AS_UINT(RtsNum));
  }
}

#endif
