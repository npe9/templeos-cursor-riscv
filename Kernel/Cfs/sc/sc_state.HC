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
// STORED COMMAND'S "WHAT RUNS NEXT" LAYER -- the 1:1 translation of NASA's fsw/src/sc_state.c,
// 341 lines and three functions. Small, and it decides everything SC does: which RTS has the
// floor, where that RTS's next command is, and which ATS entry comes after the current one.
//
// ### THE FIRST `int16` LOCAL IN THE PORT, AND THE ONLY "MUST be SIGNED" COMMENT IN ANY VENDOR TREE
//
//     int16 i;   /* loop counter MUST be SIGNED !*/
//     for (i = SC_NUMBER_OF_RTS - 1; i >= 0; i--)
//
// A grep for that comment across all of `vendor/` returns exactly one line, and it is here. The
// loop runs DOWNWARDS and terminates by going negative; with an unsigned counter `i--` at 0 is
// 65535, `i >= 0` stays true, and SC hangs in the function whose job is to pick the next RTS --
// presenting as "SC does nothing" rather than as a type error.
//
// **`I16` had never been used as a local anywhere in this translation**, so it was measured first:
// `tests/exec/cases/e_i16_signed_countdown.hc` pins the descending loop (64 iterations, ending at
// -1), the `(U16)` of that -1, sign extension on widening, signed 16-bit overflow, and -- as a
// value rather than as a hang -- the unsigned twin that NASA's comment is about. Two of its four
// mutations fail; the two that pass are written into the case, one of them because an earlier
// version of its header claimed it failed.
//
// **AND THE DIRECTION IS NOT COSMETIC.** The body's test is `<=`:
//
//     if (RtsInfoPtr->NextCommandTgtWakeup <= NextWakeupCnt)
//
// so a LATER candidate at an equal wakeup count replaces an earlier one -- and because the walk is
// backwards, "later" means a LOWER RTS number. That is how "lower number RTSs get higher
// priority" is implemented: not by a priority field, but by the pairing of a descending loop with
// a non-strict comparison. Reverse the loop or tighten the comparison to `<` and ties go to the
// highest-numbered RTS instead, silently.
//
// ### `NextCmdTime[2]` IS A TIME IN ONE SLOT AND A COUNT IN THE OTHER
//
// NASA's own declaration says so: "The overall next command time for ATP (0) and command wakeup
// count for RTP (1)". So `SC_AppData.NextCmdTime[SC_Process_ATP]` is an absolute time tag and
// `SC_AppData.NextCmdTime[SC_Process_RTP]` is a wakeup counter, in one `uint32[2]` under one name.
// Both are compared against their own reference by the scheduler in sc_cmds.c, which is why
// nothing breaks -- but a reader who takes the array's name for its contents has it half wrong,
// and `SC_MAX_WAKEUP_CNT` is the "nothing to do" sentinel for BOTH slots.
//
// ### `SC_GetNextRtsCommand` MEASURES THE SAME LENGTH TWICE AND SUBTRACTS THE HEADER BACK OFF
//
// It reads the CURRENT command's size to step past it, then the NEXT command's size to validate
// it -- and both times it adds `SC_RTS_HEADER_SIZE` immediately, so every subsequent test has to
// take it off again:
//
//     if ((CmdLength - SC_RTS_HEADER_SIZE) >= (SC_PACKET_MIN_SIZE))
//     if ((CmdLength - SC_RTS_HEADER_SIZE) <= SC_PACKET_MAX_SIZE)
//
// Three uses, two of which undo the addition. Kept verbatim because the arithmetic is identical
// either way and the shape is NASA's; noted because the second read's `CmdLength` is NOT the first
// read's and the variable is reused, so a reader tracking one value through the function is
// tracking two.
//
// **A ZERO LENGTH IS NOT AN ERROR HERE.** `(CmdLength - SC_RTS_HEADER_SIZE) >= SC_PACKET_MIN_SIZE`
// failing means "no more commands": the RTS is stopped and an INFORMATION event is sent, the same
// one as running off the end of the buffer. The two error arms below it -- too long, and runs past
// the end -- do bump `RtsCmdErrCtr` and record `LastRtsErrCmd`. So three of the four ways an RTS
// ends share one `SC_KillRts` call and differ only in what they report.
//
// ### AND SC_Status_STARTING EXISTS FOR ONE SECOND
//
// `SC_GetNextAtsCommand`'s `else if` arm does nothing but promote STARTING to EXECUTING. NASA's
// comment explains it: an inline ATS switch that lands in a second with no commands to run leaves
// the new ATS in STARTING, and this is where it begins. One assignment, and without it a switched
// ATS would never run.
#ifndef SC_STATE_HC
#define SC_STATE_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// sc_cfg.HC, sc_tbl.HC, sc_msg.HC, sc_global.HC, sc_events.HC, sc_utils.HC, sc_rtsrq.HC,
// sc_atsrq.HC, sc_loads.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13.
//
// It calls SC_KillRts (sc_rtsrq.c) and SC_KillAts (sc_atsrq.c) and is called by sc_cmds.c, so it
// sits below both request layers and above the scheduler. No cycle: nothing in rtsrq or atsrq
// calls back into here.

// --- sc_state.h's three prototypes -------------------------------------------------------------
U0 SC_GetNextRtsTime();
U0 SC_GetNextRtsCommand();
U0 SC_GetNextAtsCommand();

// --- the file-local #define --------------------------------------------------------------------
//
// NASA writes `((SC_RtsIndex_t) {-1})` -- a compound literal, which HolyC cannot spell. The index
// types are uint16 wrappers, so this is `(-1)(U16)` = 65535, and `SC_RtsIndexIsValid` rejects it
// because 65535 is not below SC_NUMBER_OF_RTS. e_i16_signed_countdown.hc pins both halves of that:
// the cast's value, and the rejection.
#define SC_INVALID_RTS_INDEX SC_IDX_FROM_UINT(-1)

/*******************************************************************************/
// Pick the RTS whose next command is due soonest, lowest RTS number winning ties.
U0 SC_GetNextRtsTime()
{
  I16 i;                /* loop counter MUST be SIGNED !*/
  U16 NextRts;          /* the next rts to schedule */
  U32 NextWakeupCnt;    /* the next wakeup count for the RTS */
  SC_RtsInfoEntry_t *RtsInfoPtr;

  NextRts = SC_INVALID_RTS_INDEX;
  NextWakeupCnt = SC_MAX_WAKEUP_CNT;

  /*
   ** Go through the table backwards to account for the RTS priority
   ** Lower number RTSs get higher priority
   ** Backward processing ensures selection of the lowest RTS number
   ** when multiple RTSs have the same next command wakeup count
   */
  for (i = SC_NUMBER_OF_RTS - 1; i >= 0; i--) {
    RtsInfoPtr = SC_GetRtsInfoObject(SC_RTS_IDX_C(i));
    if (RtsInfoPtr->RtsStatus == SC_Status_EXECUTING) {
      if (RtsInfoPtr->NextCommandTgtWakeup <= NextWakeupCnt) {
        NextWakeupCnt = RtsInfoPtr->NextCommandTgtWakeup;
        NextRts = SC_RTS_IDX_C(i);
      } /* end if */
    }   /* end if */
  }     /* end for */

  if (!SC_RtsIndexIsValid(NextRts)) {
    SC_OperData.RtsCtrlBlckAddr->CurrRtsNum = SC_RTS_NUM_NULL;
    SC_AppData.NextCmdTime[SC_Process_RTP] = SC_MAX_WAKEUP_CNT;
  } else {
    SC_OperData.RtsCtrlBlckAddr->CurrRtsNum = SC_RtsIndexToNum(NextRts);
    SC_AppData.NextCmdTime[SC_Process_RTP] = NextWakeupCnt;
  } /* end if */
}

/*******************************************************************************/
// Step the executing RTS's pointer past the command just issued and validate the next one.
//
// FOUR OUTCOMES, THREE OF WHICH STOP THE RTS -- see the file header. The `CmdLength` variable
// holds two different commands' sizes in the course of the function.
U0 SC_GetNextRtsCommand()
{
  U16 RtsIndex;
  U16 CmdOffset;
  U16 PendingOffset;
  SC_RtsEntry_t *EntryPtr;
  I64 CmdLength = 0;
  SC_RtsInfoEntry_t *RtsInfoPtr;

  /*
   ** Make sure that the RTP is executing some RTS
   */
  RtsIndex = SC_RtsNumToIndex(SC_OperData.RtsCtrlBlckAddr->CurrRtsNum);
  if (SC_RtsIndexIsValid(RtsIndex)) {
    RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);

    /*
     ** Find out if the RTS is EXECUTING or just STARTED
     */
    if (RtsInfoPtr->RtsStatus == SC_Status_EXECUTING) {
      /*
       ** Get the information needed to find the next command
       */
      CmdOffset = RtsInfoPtr->NextCommandPtr;
      EntryPtr = SC_GetRtsEntryAtOffset(RtsIndex, CmdOffset);

      CFE_MSG_GetSize(&EntryPtr->Msg.Msg, &CmdLength);
      CmdLength += SC_RTS_HEADER_SIZE;

      /*
       ** calculate the new command offset and new command length
       ** Cmd Length is in bytes, so we convert it to words
       ** (plus 1 to round byte len up to word len)
       */

      CmdOffset = SC_EntryOffsetAdvance(CmdOffset, CmdLength);
      /*
       ** if the end of the buffer is not reached.
       ** This check is made to make sure that at least the minimum
       ** Sized packet fits in the buffer. It assures we are not reading
       ** bogus length info from other data.
       */

      /* If at least the header for a command plus the RTS header can fit in the buffer */
      if (SC_IDX_WITHIN_LIMIT(CmdOffset, 1 + SC_RTS_BUFF_SIZE32 - SC_RTS_HDR_WORDS)) {
        /*
         ** Get the next RTS command
         */
        EntryPtr = SC_GetRtsEntryAtOffset(RtsIndex, CmdOffset);

        /*
         ** get the length of the new command
         */
        CFE_MSG_GetSize(&EntryPtr->Msg.Msg, &CmdLength);
        CmdLength += SC_RTS_HEADER_SIZE;

        /*
         ** Check to see if the command length is less than the size of a header.
         ** This indicates that there are no more commands
         */

        if ((CmdLength - SC_RTS_HEADER_SIZE) >= (SC_PACKET_MIN_SIZE)) {
          /*
           ** Check to see if the command length is too big
           ** If it is , then there is an error with the command
           */
          if ((CmdLength - SC_RTS_HEADER_SIZE) <= SC_PACKET_MAX_SIZE) {
            /*
             ** Last Check is to check to see if the command
             ** runs off of the end of the buffer
             ** (plus 1 to round byte len up to word len)
             */
            PendingOffset = SC_EntryOffsetAdvance(CmdOffset, CmdLength);
            if (SC_IDX_WITHIN_LIMIT(PendingOffset, 1 + SC_RTS_BUFF_SIZE32)) {
              /*
               ** Everything passed!
               ** Update the proper next command wakeup count for that RTS
               */
              RtsInfoPtr->NextCommandTgtWakeup = SC_ComputeAbsWakeup(EntryPtr->Header.WakeupCount);

              /*
               ** Update the appropriate RTS info table current command pointer
               */
              RtsInfoPtr->NextCommandPtr = CmdOffset;
            } else { /* the command runs past the end of the buffer */

              /*
               ** Having a command that runs off of the end of the buffer
               ** is an error condition, so record it
               */
              SC_OperData.HkPacket.Payload.RtsCmdErrCtr++;
              RtsInfoPtr->CmdErrCtr++;
              SC_OperData.HkPacket.Payload.LastRtsErrSeq = SC_OperData.RtsCtrlBlckAddr->CurrRtsNum;
              SC_OperData.HkPacket.Payload.LastRtsErrCmd = CmdOffset;

              /*
               ** Stop the RTS from executing
               */
              SC_KillRts(RtsIndex);
              CFE_EVS_SendEvent(SC_RTS_LNGTH_ERR_EID, CFE_EVS_EventType_ERROR,
                                "Cmd Runs passed end of table, RTS %03u Aborted",
                                SC_IDNUM_AS_UINT(SC_OperData.RtsCtrlBlckAddr->CurrRtsNum));

            } /* end if the command runs off the end of the buffer */
          } else { /* the command length is too large */

            /* update the error information */
            SC_OperData.HkPacket.Payload.RtsCmdErrCtr++;
            RtsInfoPtr->CmdErrCtr++;
            SC_OperData.HkPacket.Payload.LastRtsErrSeq = SC_OperData.RtsCtrlBlckAddr->CurrRtsNum;
            SC_OperData.HkPacket.Payload.LastRtsErrCmd = CmdOffset;

            /* Stop the RTS from executing */
            SC_KillRts(RtsIndex);
            // NASA'S `(uint16)SC_RTS_HEADER_SIZE` IS A CAST OF THE CONSTANT, NOT OF THE RESULT.
            // SC_RTS_HEADER_SIZE is 4, so the cast changes nothing and the subtraction happens in
            // the size type; `(unsigned int)` on the outside is what %u takes. Both casts are
            // dropped because HolyC's %u narrows to 32 bits exactly as C's `unsigned int` does --
            // see the arm in Kernel/Cfs/CfsStr.HC that masks for %u and %x alike.
            CFE_EVS_SendEvent(SC_RTS_CMD_LNGTH_ERR_EID, CFE_EVS_EventType_ERROR,
                              "Invalid Length Field in RTS Command, RTS %03u Aborted. Length: %u, Max: %d",
                              SC_IDNUM_AS_UINT(SC_OperData.RtsCtrlBlckAddr->CurrRtsNum),
                              CmdLength - SC_RTS_HEADER_SIZE, SC_PACKET_MAX_SIZE);

          } /* end if the command length is invalid */
        } else { /* The command length is zero indicating no more cmds */
          /*
           **  This is not an error condition, so stop the RTS
           */

          /* Stop the RTS from executing */
          SC_KillRts(RtsIndex);
          if (SC_RtsNumHasEvent(SC_OperData.RtsCtrlBlckAddr->CurrRtsNum)) {
            CFE_EVS_SendEvent(SC_RTS_COMPL_INF_EID, CFE_EVS_EventType_INFORMATION,
                              "RTS %03u Execution Completed",
                              SC_IDNUM_AS_UINT(SC_OperData.RtsCtrlBlckAddr->CurrRtsNum));
          }
        }
      } else { /* The end of the RTS buffer has been reached... */
        /* Stop the RTS from executing */
        SC_KillRts(RtsIndex);
        if (SC_RtsNumHasEvent(SC_OperData.RtsCtrlBlckAddr->CurrRtsNum)) {
          CFE_EVS_SendEvent(SC_RTS_COMPL_INF_EID, CFE_EVS_EventType_INFORMATION,
                            "RTS %03u Execution Completed",
                            SC_IDNUM_AS_UINT(SC_OperData.RtsCtrlBlckAddr->CurrRtsNum));
        }

      } /* end if */

    } /* end if the RTS status is EXECUTING */

  } /* end if the RTS number is valid */
}

/*******************************************************************************/
// Advance the ATP to the next command in time order, or finish the ATS.
U0 SC_GetNextAtsCommand()
{
  U16 AtsIndex;   /* ats array index */
  U16 TimeIndex;  /* a time index pointer */
  SC_AtsCmdEntryOffsetRecord_t *CmdOffsetRec;
  SC_AtsEntry_t *EntryPtr;
  SC_AtsInfoTable_t *AtsInfoPtr;
  SC_AtsCmdNumRecord_t *AtsCmdNumRec;
  U16 CurrCmdIndex;

  if (SC_OperData.AtsCtrlBlckAddr->AtpState == SC_Status_EXECUTING) {
    /*
     ** Get the information that is needed to find the next command
     */
    AtsIndex = SC_AtsNumToIndex(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum);
    TimeIndex = SC_OperData.AtsCtrlBlckAddr->TimeIndexPtr;
    AtsInfoPtr = SC_GetAtsInfoObject(AtsIndex);
    SC_IDX_INCREMENT(TimeIndex);

    /*
     ** Check to see if there are more ATS commands
     */
    if (SC_IDX_WITHIN_LIMIT(TimeIndex, AtsInfoPtr->NumberOfCommands)) {
      /* get the information for the next command in the ATP control block */
      AtsCmdNumRec = SC_GetAtsCommandNumAtSeq(AtsIndex, TimeIndex);
      CurrCmdIndex = SC_CommandNumToIndex(AtsCmdNumRec->CmdNum);

      SC_OperData.AtsCtrlBlckAddr->TimeIndexPtr = TimeIndex;
      SC_OperData.AtsCtrlBlckAddr->CmdNumber = AtsCmdNumRec->CmdNum;

      /* update the next command time */
      CmdOffsetRec = SC_GetAtsEntryOffsetForCmd(AtsIndex, CurrCmdIndex);

      EntryPtr = SC_GetAtsEntryAtOffset(AtsIndex, CmdOffsetRec->Offset);

      SC_AppData.NextCmdTime[SC_Process_ATP] = SC_GetAtsEntryTime(&EntryPtr->Header);
    } else { /* the end is near... of the ATS buffer that is */

      /* stop the ATS */
      SC_KillAts();
      CFE_EVS_SendEvent(SC_ATS_COMPL_INF_EID, CFE_EVS_EventType_INFORMATION, "ATS %c Execution Completed",
                        SC_IDX_AS_CHAR(AtsIndex));

      /* stop any switch that is pending */
      /* because we just ran out of commands and are stopping the ATS */
      /* and for the safe switch pend, that is a no-no */
      SC_OperData.AtsCtrlBlckAddr->SwitchPendFlag = FALSE;

    } /* end if */
  } else if (SC_OperData.AtsCtrlBlckAddr->AtpState == SC_Status_STARTING) {
    /*
     ** The SC_Status_STARTING state is entered when an ATS inline
     ** switch has occurred and there are no commands to
     ** execute in the same second that the switch occurs.
     ** The state is transitioned here to SC_Status_EXECUTING to
     ** commence execution of the new ATS on the next wakeup
     ** command processing cycle.
     */
    SC_OperData.AtsCtrlBlckAddr->AtpState = SC_Status_EXECUTING;

  } /* end if ATS is EXECUTING*/
}

#endif
