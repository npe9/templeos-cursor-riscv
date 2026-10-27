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
// STORED COMMAND'S ENGINE -- the 1:1 translation of NASA's fsw/src/sc_cmds.c, 764 lines and
// eleven functions. **This is the file that actually sends the stored commands.** Everything
// gated before it loads tables, sorts them and decides what is next; this is where an ATS entry
// becomes a message on the software bus.
//
// ### THE WAKEUP IS A RATE LIMITER, AND THE LOOP'S EXIT CONDITION IS A COUNTER THAT DID NOT MOVE
//
// `SC_WakeupCmd` runs at most `SC_MAX_CMDS_PER_WAKEUP` (8) commands per wakeup, so a thousand-
// command ATS whose times have all passed drains over 125 wakeups instead of flooding the bus in
// one. The loop is not a `for` over 8, though -- it is
//
//     while (SC_OperData.NumCmdsWakeup < SC_MAX_CMDS_PER_WAKEUP) {
//         CurrentNumCmds = SC_OperData.NumCmdsWakeup;
//         ... try the ATP, then maybe the RTP ...
//         if (CurrentNumCmds == SC_OperData.NumCmdsWakeup) break;
//     }
//
// **the counter is both the budget and the progress flag.** `SC_ProcessAtpCmd` increments it
// only when it actually issues something, so "nothing happened this pass" and "the budget is
// spent" are the same variable read two ways. The RTP is tried only when the ATP did nothing,
// which is the priority rule: a due ATS command beats a due RTS command every time.
//
// AND IT IS RESET TO ZERO AT THE END, not at the start. The counter is SC_OperData's, so it
// persists between calls -- the reset is what makes the next wakeup a fresh budget, and a reader
// looking for the initialisation at the top will not find it.
//
// ### A SWITCH COMMAND *INSIDE* AN ATS IS EXECUTED IN PLACE, NOT SENT
//
// `SC_ProcessAtpCmd` tests for `SC_SWITCH_ATS_CC` on `SC_CMD_MID` and calls `SC_InlineSwitch`
// directly -- NASA's comment calls it "the only exception to the way stored commands are sent
// out". The reason is in that comment too: a switch from the GROUND waits for the next second so
// two overlapping ATSs cannot duplicate commands, and a switch from INSIDE an ATS must not wait,
// because the ATS issuing it is the one being switched away from.
//
// ### `AbortATS` IS SET BY THREE ARMS AND DELIBERATELY NOT BY A FOURTH
//
// A distribution failure, a command-number mismatch, and a checksum failure when
// `ContinueAtsOnFailureFlag` is false all abort. A command whose STATUS is not LOADED does not --
// NASA's comment says why: "The command could be marked as EXECUTED if we already jumped back in
// time". So the one failure that looks most like corruption is the one that is survivable, and
// the three that look like data errors are fatal to the ATS.
//
// ### THE HOUSEKEEPING BIT MASKS ARE SIZED BY A sizeof RATIO, AND THE NUMBER IS NOT WHAT IT LOOKS
//
// `SC_BITS_PER_HKTLM_WORD` reads like "bits in a uint16" and is **4** in this configuration:
//
//     SC_BITS_PER_HKTLM_OCTET = SC_NUMBER_OF_RTS / sizeof(RtsDisabledStatus)       = 4 / 2 = 2
//     SC_BITS_PER_HKTLM_WORD  = sizeof(RtsDisabledStatus[0]) * SC_BITS_PER_HKTLM_OCTET = 2 * 2 = 4
//
// It is really "total bits x element size / array size", which comes out right for any
// configuration -- 16 for the default 64 RTSs, 4 for this build's four -- and says so nowhere.
// **Both numbers were measured, not derived**, because getting them wrong puts every RTS status
// bit in the wrong place in a telemetry packet and nothing else would notice.
//
// NASA's `SC_HKTLM_MEMBER_SIZE(x)` is `sizeof(((SC_HkTlm_Payload_t *)0)->x)` -- a sizeof through
// a null pointer, which HolyC cannot spell. The two values are written as the literals the
// measurement produced, with the derivation above them.
//
// ### AND THE TABLE-ID RANGES ARE ADJACENT, WHICH MAKES AN OFF-BY-ONE SILENT
//
// ATS ids are 1..2, APPEND is 3, RTS ids are 4..7, and RTS_INFO is 8. Every `else if` in
// `SC_ManageTableCmd` is a half-open range butting directly against the next one, so a `<=` where
// NASA writes `<` would not fall through to the error arm -- it would manage the WRONG TABLE.
// The bounds are kept character for character.
#ifndef SC_CMDS_HC
#define SC_CMDS_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// sc_cfg.HC, sc_tbl.HC, sc_msg.HC, sc_global.HC, sc_events.HC, sc_utils.HC, sc_rtsrq.HC,
// sc_atsrq.HC, sc_loads.HC, sc_state.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13.
//
// It calls into every one of them and nothing calls back, so it is the top of SC's internals and
// there is no cycle. sc_dispatch.c, which is not gated yet, is what calls the five command
// handlers here.

// --- sc_cmds.h's twelve prototypes -------------------------------------------------------------
I32 SC_ManageTableCmd(SC_ManageTableCmd_t *Cmd);
U0 SC_ManageRtsTable(I32 ArrayIndex);
U0 SC_ManageAtsTable(I32 ArrayIndex);
U0 SC_ManageTable(I32 type, I32 ArrayIndex);
I32 SC_NoopCmd(SC_NoopCmd_t *Cmd);
I32 SC_ResetCountersCmd(SC_ResetCountersCmd_t *Cmd);
U0 SC_SendHkPacket();
I32 SC_SendHkCmd(SC_SendHkCmd_t *Cmd);
I32 SC_WakeupCmd(SC_WakeupCmd_t *Cmd);
U0 SC_ProcessAtpCmd();
U0 SC_ProcessRtpCommand();

// --- sc_cmds.h's SC_TableType, and why the three names are left bare --------------------------
//
// NASA's enum is `{ ATS, RTS, APPEND }` -- three of the most generic identifiers in the whole
// port, in a header every SC source includes. They are kept BARE because check_constants compares
// the translation's values against NASA's by name, and renaming them would be a silent
// divergence rather than a tidy-up. Nothing else in Kernel/Cfs defines any of the three; that was
// checked rather than assumed.
#define ATS    0
#define RTS    1
#define APPEND 2

// --- the housekeeping bit-mask geometry -------------------------------------------------------
//
// MEASURED, not derived -- see the file header for the ratio these come out of and why the names
// mislead. `SC_HKTLM_MEMBER_SIZE` itself is a sizeof through a null pointer and has no HolyC
// spelling, so the two values it feeds are written as literals.
#define SC_BITS_PER_HKTLM_OCTET 2
#define SC_BITS_PER_HKTLM_WORD  4

// NASA's macro, kept as a macro, with ONE forced change.
//
// **THE INNER PARENTHESES ROUND `s % SC_BITS_PER_HKTLM_WORD` ARE LOAD-BEARING HERE AND REDUNDANT
// IN C** -- `<<` is the TIGHTEST binary operator in HolyC and looser than `%` in C, so
// `1 << s % 4` means `(1 << s) % 4` here and `1 << (s % 4)` there. Same shape that silently
// disabled an HS application monitor; check_shift_parens refuses the unparenthesised form, and
// NASA's parentheses are kept character for character.
//
// **THE BODY IS AN EXPRESSION, BECAUSE A HolyC FUNCTION-LIKE MACRO CANNOT CONTAIN A STATEMENT.**
// Bisected rather than guessed -- four bodies compiled in isolation:
//
//     f[s] = v;                                    OK
//     if (v) f[s] = 1;                             error: Expected ';' or ','
//     if (v) f[s] = 1; else f[s] = 0;              error: Expected ';' or ','
//     { if (v) f[s] = 1; else f[s] = 0; }          error: Expected ';' or ','
//
// So NASA's `do { if (v) ... else ... } while (0)` fails twice over: HolyC has no `do`/`while`
// wrapper AND no `if` inside a macro. An assignment is the only shape available.
//
// The single assignment below is NASA's if/else exactly: clear the bit, then or it back in when
// `v` is true. **Checked against a C twin of NASA's own macro rather than reasoned about** --
// both print `mask=65530` for alternating bits over a pre-set 0xFFFF word, and `allset=65535`.
//
// The ternary's `v` is parenthesised because the call sites pass an expression
// (`RtsInfoPtr->RtsStatus == SC_Status_EXECUTING`), and the shift parentheses are NASA's and are
// load-bearing in HolyC -- both reasons are above.
//
// A consequence worth stating: this expansion is a single expression, so unlike the bare
// `if`/`else` it would have become, it is safe as the unbraced body of another `if`. The
// limitation forced a form that is better behaved than the one it replaced.
#define SC_SET_HKTLM_RTS_MASK(f, s, v)                                                            \
  f[s / SC_BITS_PER_HKTLM_WORD] = (f[s / SC_BITS_PER_HKTLM_WORD] &                                \
                                   ~(1 << (s % SC_BITS_PER_HKTLM_WORD))) |                        \
                                  ((v) ? (1 << (s % SC_BITS_PER_HKTLM_WORD)) : 0)

/*******************************************************************************/
// Issue the ATS command that is due, if one is.
//
// THREE CONDITIONS GUARD THE WHOLE FUNCTION and NASA lists them in a comment: the next time must
// have arrived, the processor must be the ATP, and the ATP must be EXECUTING. The time test is
// `!SC_CompareAbsTime(NextCmdTime, CurrentTime)` -- a NEGATED strictly-greater, i.e. "next <=
// current", which is the one place in SC where the strictness of that comparison decides whether
// a command fires this second or the next.
U0 SC_ProcessAtpCmd()
{
  U16 AtsIndex; /* ATS selection index */
  U16 CmdIndex; /* ATS command index */
  I32 Result;
  Bool AbortATS = FALSE;
  SC_AtsEntry_t *EntryPtr;
  CFE_SB_MsgId MessageID;
  I16 CommandCode = 0;
  Bool ChecksumValid;
  SC_AtsCmdEntryOffsetRecord_t *CmdOffsetRec; /* ATS entry location in table */
  SC_AtsCmdStatusEntry_t *StatusEntryPtr;

  MessageID = CFE_SB_InvalidMsgId();

  /*
   ** The following conditions must be met before the ATS command will be
   ** executed:
   ** 1.) The next time is <= the current time
   ** 2.) The next processor number = ATP
   ** 3.) The atp is currently EXECUTING
   */

  if (SC_OperData.AtsCtrlBlckAddr->AtpState == SC_Status_EXECUTING &&
      !SC_CompareAbsTime(SC_AppData.NextCmdTime[SC_Process_ATP], SC_AppData.CurrentTime)) {
    /*
     ** Get a pointer to the next ats command
     */
    AtsIndex = SC_AtsNumToIndex(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum); /* remember 0..1 */
    CmdIndex = SC_CommandNumToIndex(SC_OperData.AtsCtrlBlckAddr->CmdNumber);
    CmdOffsetRec = SC_GetAtsEntryOffsetForCmd(AtsIndex, CmdIndex);
    EntryPtr = SC_GetAtsEntryAtOffset(AtsIndex, CmdOffsetRec->Offset);
    StatusEntryPtr = SC_GetAtsStatusEntryForCommand(AtsIndex, CmdIndex);
    /*
     ** Make sure the command has not been executed, skipped or has any other bad status
     */
    if (StatusEntryPtr->Status == SC_Status_LOADED) {
      /*
       ** Make sure the command number matches what the command
       ** number is supposed to be
       */
      if (SC_IDNUM_EQUAL(EntryPtr->Header.CmdNumber, SC_CommandIndexToNum(CmdIndex))) {
        /*
         * Check the checksum on the command
         * If this feature is disabled, just skip and assume valid
         * Note that the checksum will be re-computed when the message is sent.
         */
        ChecksumValid = SC_AppData.EnableHeaderUpdate;
        if (!SC_AppData.EnableHeaderUpdate) {
          /* If header update is NOT enabled, confirm this table entry has a valid checksum already */
          CFE_MSG_ValidateChecksum(&EntryPtr->Msg.Msg, &ChecksumValid);
        }
        if (ChecksumValid) {
          /*
           ** Count the command for the rate limiter
           */
          SC_OperData.NumCmdsWakeup++;

          /*
           **  First check to see if the command is a switch command,
           **  if it is, then execute the command now instead of sending
           **  it out on the Software Bus (this is the only exception to
           **  way stored commands are sent out).
           **  A switch command located within an ATS is handled differently
           **  than a switch command by the ground controller. If the switch
           **  command is by the ground controller, SC waits until the next
           **  second to prevent overlapping of two ATSs from duplicating
           **  commands. If the Switch command is located within an ATS,
           **  SC immediately executes the switch command.
           */

          CFE_MSG_GetMsgId(&EntryPtr->Msg.Msg, &MessageID);
          CFE_MSG_GetFcnCode(&EntryPtr->Msg.Msg, &CommandCode);

          if (CommandCode == SC_SWITCH_ATS_CC && CFE_SB_MsgIdToValue(MessageID) == SC_CMD_MID) {
            /*
             ** call the ground switch module
             */
            if (SC_InlineSwitch()) {
              /*
               ** Increment the counter and update the status for
               ** this command
               */
              StatusEntryPtr->Status = SC_Status_EXECUTED;
              SC_OperData.HkPacket.Payload.AtsCmdCtr++;
            } else { /* the switch failed for some reason */

              StatusEntryPtr->Status = SC_Status_FAILED_DISTRIB;
              SC_OperData.HkPacket.Payload.AtsCmdErrCtr++;
              SC_OperData.HkPacket.Payload.LastAtsErrSeq = SC_OperData.AtsCtrlBlckAddr->CurrAtsNum;
              SC_OperData.HkPacket.Payload.LastAtsErrCmd = SC_OperData.AtsCtrlBlckAddr->CmdNumber;

            } /* end if */
          } else {
            Result = CFE_SB_TransmitMsg(&EntryPtr->Msg.Msg, SC_AppData.EnableHeaderUpdate);

            if (Result == CFE_SUCCESS) {
              /* The command sent OK */
              StatusEntryPtr->Status = SC_Status_EXECUTED;
              SC_OperData.HkPacket.Payload.AtsCmdCtr++;
            } else { /* the command had Software Bus problems */
              StatusEntryPtr->Status = SC_Status_FAILED_DISTRIB;
              SC_OperData.HkPacket.Payload.AtsCmdErrCtr++;
              SC_OperData.HkPacket.Payload.LastAtsErrSeq = SC_OperData.AtsCtrlBlckAddr->CurrAtsNum;
              SC_OperData.HkPacket.Payload.LastAtsErrCmd = SC_OperData.AtsCtrlBlckAddr->CmdNumber;

              CFE_EVS_SendEvent(SC_ATS_DIST_ERR_EID, CFE_EVS_EventType_ERROR,
                                "ATS Command Distribution Failed, Cmd Number: %u, SB returned: 0x%08X",
                                SC_IDNUM_AS_UINT(EntryPtr->Header.CmdNumber), Result);

              /* Mark this ATS for abortion */
              AbortATS = TRUE;
            }
          }
        } else { /* the checksum failed */
          /*
           ** Send an event message to report the invalid command status
           */
          CFE_EVS_SendEvent(SC_ATS_CHKSUM_ERR_EID, CFE_EVS_EventType_ERROR,
                            "ATS Command Failed Checksum: Command #%u Skipped",
                            SC_IDNUM_AS_UINT(EntryPtr->Header.CmdNumber));
          /*
           ** Increment the ATS error counter
           */
          SC_OperData.HkPacket.Payload.AtsCmdErrCtr++;

          /*
           ** Update the last ATS error information structure
           */
          SC_OperData.HkPacket.Payload.LastAtsErrSeq = SC_OperData.AtsCtrlBlckAddr->CurrAtsNum;
          SC_OperData.HkPacket.Payload.LastAtsErrCmd = SC_OperData.AtsCtrlBlckAddr->CmdNumber;

          /* update the command status index table */
          StatusEntryPtr->Status = SC_Status_FAILED_CHECKSUM;

          if (SC_OperData.HkPacket.Payload.ContinueAtsOnFailureFlag == FALSE) {
            /* Mark this ATS for abortion */
            AbortATS = TRUE;
          }
        } /* end checksum test */
      } else { /* the command number does not match */
        /*
         ** Send an event message to report the invalid command status
         */

        CFE_EVS_SendEvent(SC_ATS_MSMTCH_ERR_EID, CFE_EVS_EventType_ERROR,
                          "ATS Command Number Mismatch: Command Skipped, expected: %u received: %u",
                          SC_IDNUM_AS_UINT(SC_CommandIndexToNum(CmdIndex)),
                          SC_IDNUM_AS_UINT(EntryPtr->Header.CmdNumber));
        /*
         ** Increment the ATS error counter
         */
        SC_OperData.HkPacket.Payload.AtsCmdErrCtr++;

        /*
         ** Update the last ATS error information structure
         */
        SC_OperData.HkPacket.Payload.LastAtsErrSeq = SC_OperData.AtsCtrlBlckAddr->CurrAtsNum;
        SC_OperData.HkPacket.Payload.LastAtsErrCmd = SC_OperData.AtsCtrlBlckAddr->CmdNumber;

        /* update the command status index table */
        StatusEntryPtr->Status = SC_Status_SKIPPED;

        /* Mark this ATS for abortion */
        AbortATS = TRUE;
      } /* end if  the command number does not match */
    } else /* command isn't marked as loaded */
    {
      /*
       ** Send an event message to report the invalid command status
       */
      // **`& 0xFF` AND NOT `(unsigned long)`, WHICH IS WHAT NASA WRITES.** Status is a `U8`, and
      // HolyC limit #28 makes a widening cast of a narrow lvalue widen the LOAD -- it would read
      // eight bytes starting at this one-byte field. The mask is exactly what C's
      // `(unsigned long)` of a uint8 means. tools/cfs/check_narrow_cast.py refuses the cast form.
      CFE_EVS_SendEvent(SC_ATS_SKP_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Invalid ATS Command Status: Command Skipped, Status: %lu",
                        StatusEntryPtr->Status & 0xFF);
      /*
       ** Increment the ATS error counter
       */
      SC_OperData.HkPacket.Payload.AtsCmdErrCtr++;

      /*
       ** Update the last ATS error information structure
       */
      SC_OperData.HkPacket.Payload.LastAtsErrSeq = SC_OperData.AtsCtrlBlckAddr->CurrAtsNum;
      SC_OperData.HkPacket.Payload.LastAtsErrCmd = SC_OperData.AtsCtrlBlckAddr->CmdNumber;

      /* Do Not Mark this ATS for abortion. The command could be marked as EXECUTED
         if we already jumped back in time */

    } /* end if */

    if (AbortATS == TRUE) {
      CFE_EVS_SendEvent(SC_ATS_ABT_ERR_EID, CFE_EVS_EventType_ERROR, "ATS %c Aborted", SC_IDX_AS_CHAR(AtsIndex));

      /* Stop the ATS from executing */
      SC_KillAts();
      SC_OperData.AtsCtrlBlckAddr->SwitchPendFlag = FALSE;
    } else {
      /*
      ** Get the next ATS command set up to execute
      */
      SC_GetNextAtsCommand();
    }

  } /* end if next ATS command time */
}

/*******************************************************************************/
// Issue the RTS command that is due, if one is.
//
// **THE RTP'S CLOCK IS A WAKEUP COUNT, NOT A TIME**, and the comparison says so: `NextCmdTime
// [SC_Process_RTP] <= SC_AppData.CurrentWakeupCount`. The same `NextCmdTime[2]` array holds an
// absolute time in slot 0 and a counter in slot 1 -- sc_state.HC's header sets that out, and this
// is the function where the second slot is read as what it is.
//
// AND THE RATE LIMITER IS INCREMENTED BEFORE THE COMMAND IS TRIED, with NASA's comment "even if
// the command fails". So a failing RTS command still costs one of the eight, which is what stops
// a broken RTS spinning the wakeup loop.
U0 SC_ProcessRtpCommand()
{
  SC_RtsEntry_t *EntryPtr; /* a pointer to an RTS entry header */
  U16 RtsIndex;            /* the RTS index for the cmd */
  U16 CmdOffset;           /* the location of the cmd    */
  I32 Result;
  Bool ChecksumValid;
  SC_RtsInfoEntry_t *RtsInfoPtr;

  /*
   ** The following conditions must be met before a RTS command is executed:
   ** 1.) The next command wakeup count must be <= the current wakeup count
   ** 2.) The next processor number must be SC_Process_RTP
   ** 3.) The RTS number in the RTP control block must be valid and
   ** 4.) the RTS must be EXECUTING
   */
  /* convert the RTS number so that it can be directly indexed into the table*/
  RtsIndex = SC_RtsNumToIndex(SC_OperData.RtsCtrlBlckAddr->CurrRtsNum);
  if (!SC_RtsIndexIsValid(RtsIndex)) {
    return;
  }

  RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);

  if (SC_AppData.NextCmdTime[SC_Process_RTP] <= SC_AppData.CurrentWakeupCount &&
      RtsInfoPtr->RtsStatus == SC_Status_EXECUTING) {
    /*
     ** Count the command for the rate limiter
     ** even if the command fails
     */
    SC_OperData.NumCmdsWakeup++;

    /*
     ** Get the Command offset within the RTS
     */
    CmdOffset = RtsInfoPtr->NextCommandPtr;

    /*
     ** Get a pointer to the RTS entry using the RTS number and the offset
     */
    EntryPtr = SC_GetRtsEntryAtOffset(RtsIndex, CmdOffset);

    ChecksumValid = SC_AppData.EnableHeaderUpdate;
    if (!SC_AppData.EnableHeaderUpdate) {
      /* If header update is NOT enabled, confirm this table entry has a valid checksum already */
      CFE_MSG_ValidateChecksum(&EntryPtr->Msg.Msg, &ChecksumValid);
    }
    if (ChecksumValid) {
      /*
       ** Try Sending the command on the Software Bus
       */

      Result = CFE_SB_TransmitMsg(&EntryPtr->Msg.Msg, SC_AppData.EnableHeaderUpdate);

      if (Result == CFE_SUCCESS) {
        /* the command was sent OK */
        SC_OperData.HkPacket.Payload.RtsCmdCtr++;
        RtsInfoPtr->CmdCtr++;

        /*
         ** Get the next command.
         */
        SC_GetNextRtsCommand();
      } else { /* the software bus return code was bad */

        /*
         ** Send an event message to report the invalid command status
         */
        CFE_EVS_SendEvent(SC_RTS_DIST_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RTS %03u Command Distribution Failed: RTS Stopped. SB returned 0x%08X",
                          SC_IDNUM_AS_UINT(SC_OperData.RtsCtrlBlckAddr->CurrRtsNum), Result);

        SC_OperData.HkPacket.Payload.RtsCmdErrCtr++;
        RtsInfoPtr->CmdErrCtr++;
        SC_OperData.HkPacket.Payload.LastRtsErrSeq = SC_OperData.RtsCtrlBlckAddr->CurrRtsNum;
        SC_OperData.HkPacket.Payload.LastRtsErrCmd = CmdOffset;

        /*
         ** Stop the RTS from executing
         */
        SC_KillRts(RtsIndex);

      } /* end if */
    } else { /* the checksum failed */

      /*
       ** Send an event message to report the invalid command status
       */
      CFE_EVS_SendEvent(SC_RTS_CHKSUM_ERR_EID, CFE_EVS_EventType_ERROR,
                        "RTS %03u Command Failed Checksum: RTS Stopped",
                        SC_IDNUM_AS_UINT(SC_OperData.RtsCtrlBlckAddr->CurrRtsNum));
      /*
      ** Update the RTS command error counter and last RTS error info
      */
      SC_OperData.HkPacket.Payload.RtsCmdErrCtr++;
      RtsInfoPtr->CmdErrCtr++;
      SC_OperData.HkPacket.Payload.LastRtsErrSeq = SC_OperData.RtsCtrlBlckAddr->CurrRtsNum;
      SC_OperData.HkPacket.Payload.LastRtsErrCmd = CmdOffset;

      /*
       ** Stop the RTS from executing
       */
      SC_KillRts(RtsIndex);
    } /* end if */
  }   /* end if */
}

/*******************************************************************************/
// Fill the housekeeping packet from live state and send it.
//
// THE FREE-BYTES FIELD IS THE ONLY PLACE SC PUBLISHES A BUFFER SIZE IN BYTES, and it computes it
// the long way -- `(SC_ATS_BUFF_SIZE32 * SC_BYTES_IN_WORD) - (AtsSize * SC_BYTES_IN_WORD)` rather
// than multiplying the difference. Kept; the arithmetic is identical and the shape is NASA's.
// Note it uses `* 4`, which is the multiplier upstream note #25 says `SC_UpdateAppend`'s
// housekeeping byte count should have used and does not.
U0 SC_SendHkPacket()
{
  U16 i;
  SC_AtsInfoTable_t *AtsInfoPtr;
  SC_RtsInfoEntry_t *RtsInfoPtr;

  /*
   ** fill in the free bytes in each ATS
   */
  for (i = 0; i < SC_NUMBER_OF_ATS; ++i) {
    AtsInfoPtr = SC_GetAtsInfoObject(SC_ATS_IDX_C(i));

    SC_OperData.HkPacket.Payload.AtpFreeBytes[i] =
        (SC_ATS_BUFF_SIZE32 * SC_BYTES_IN_WORD) - (AtsInfoPtr->AtsSize * SC_BYTES_IN_WORD);
  }

  /*
   **
   ** fill in the ATP Control Block information
   **
   */

  SC_OperData.HkPacket.Payload.CurrAtsId = SC_IDNUM_AS_UINT(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum);

  SC_OperData.HkPacket.Payload.AtpState = SC_OperData.AtsCtrlBlckAddr->AtpState;
  SC_OperData.HkPacket.Payload.AtpCmdNumber = SC_IDNUM_AS_UINT(SC_OperData.AtsCtrlBlckAddr->CmdNumber);
  SC_OperData.HkPacket.Payload.SwitchPendFlag = SC_OperData.AtsCtrlBlckAddr->SwitchPendFlag;

  SC_OperData.HkPacket.Payload.NextAtsTime = SC_AppData.NextCmdTime[SC_Process_ATP];

  /*
   ** Fill out the RTP control block information
   */

  SC_OperData.HkPacket.Payload.NumRtsActive = SC_OperData.RtsCtrlBlckAddr->NumRtsActive;
  SC_OperData.HkPacket.Payload.RtsNum = SC_OperData.RtsCtrlBlckAddr->CurrRtsNum;
  SC_OperData.HkPacket.Payload.NextRtsWakeupCnt = SC_AppData.NextCmdTime[SC_Process_RTP];

  /*
   ** Fill out the RTS status bit mask
   ** First clear out the status mask
   */
  MemSet(SC_OperData.HkPacket.Payload.RtsExecutingStatus, 0,
         sizeof(SC_OperData.HkPacket.Payload.RtsExecutingStatus));
  MemSet(SC_OperData.HkPacket.Payload.RtsDisabledStatus, 0,
         sizeof(SC_OperData.HkPacket.Payload.RtsDisabledStatus));

  for (i = 0; i < SC_NUMBER_OF_RTS; i++) {
    RtsInfoPtr = SC_GetRtsInfoObject(SC_RTS_IDX_C(i));

    SC_SET_HKTLM_RTS_MASK(SC_OperData.HkPacket.Payload.RtsDisabledStatus, i, RtsInfoPtr->DisabledFlag);
    SC_SET_HKTLM_RTS_MASK(SC_OperData.HkPacket.Payload.RtsExecutingStatus, i,
                          RtsInfoPtr->RtsStatus == SC_Status_EXECUTING);
  } /* end for */

  /* send the status packet */
  CFE_SB_TimeStampMsg(&SC_OperData.HkPacket.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&SC_OperData.HkPacket.TelemetryHeader.Msg, TRUE);
}

/*******************************************************************************/
// The housekeeping request, which does one thing nobody would expect from its name.
//
// **IT IS WHERE THE AUTO-START RTS IS LAUNCHED.** `SC_AppData.AutoStartRTS` is set at init, and
// the FIRST housekeeping request after that enables the RTS if it is loaded, sends the start
// command, and then clears AutoStartRTS so it can never fire twice. So SC's power-on sequence
// depends on something else asking it for telemetry -- there is no other trigger.
I32 SC_SendHkCmd(SC_SendHkCmd_t *Cmd)
{
  SC_RtsInfoEntry_t *RtsInfoPtr;

  /* set during init to power on or processor reset auto-exec RTS */
  if (SC_RtsNumIsValid(SC_AppData.AutoStartRTS)) {
    RtsInfoPtr = SC_GetRtsInfoObject(SC_RtsNumToIndex(SC_AppData.AutoStartRTS));

    /* make sure the selected auto-exec RTS is enabled */
    if (RtsInfoPtr->RtsStatus == SC_Status_LOADED) {
      RtsInfoPtr->DisabledFlag = FALSE;
    }

    /* send ground cmd to have SC start the RTS */
    SC_AutoStartRts(SC_AppData.AutoStartRTS);

    /* only start it once */
    SC_AppData.AutoStartRTS = SC_RTS_NUM_NULL;
  }

  /* request from health and safety for housekeeping status */
  SC_SendHkPacket();

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Reset the eight counters, and NOT the two "last error" records.
//
// `LastAtsErrSeq`, `LastAtsErrCmd`, `LastRtsErrSeq` and `LastRtsErrCmd` survive a reset, so after
// clearing the counters the packet still names the last failure. Deliberate or not, it is what a
// ground operator sees, and it is the kind of asymmetry a translation is tempted to tidy.
I32 SC_ResetCountersCmd(SC_ResetCountersCmd_t *Cmd)
{
  CFE_EVS_SendEvent(SC_RESET_INF_EID, CFE_EVS_EventType_INFORMATION, "Reset counters command");

  SC_OperData.HkPacket.Payload.CmdCtr = 0;
  SC_OperData.HkPacket.Payload.CmdErrCtr = 0;
  SC_OperData.HkPacket.Payload.AtsCmdCtr = 0;
  SC_OperData.HkPacket.Payload.AtsCmdErrCtr = 0;
  SC_OperData.HkPacket.Payload.RtsCmdCtr = 0;
  SC_OperData.HkPacket.Payload.RtsCmdErrCtr = 0;
  SC_OperData.HkPacket.Payload.RtsActiveCtr = 0;
  SC_OperData.HkPacket.Payload.RtsActiveErrCtr = 0;

  return CFE_SUCCESS;
}

/*******************************************************************************/
// The wakeup: SC's heartbeat, and the rate limiter. See the file header on why the loop's exit
// test and its budget are the same counter.
I32 SC_WakeupCmd(SC_WakeupCmd_t *Cmd)
{
  U32 CurrentNumCmds;
  SC_AppData.CurrentWakeupCount++;

  /*
   * Time to execute a command in the SC memory
   */
  while (SC_OperData.NumCmdsWakeup < SC_MAX_CMDS_PER_WAKEUP) {
    CurrentNumCmds = SC_OperData.NumCmdsWakeup;

    /*
     *  Check to see if there is an ATS switch Pending, if so service it.
     */
    if (SC_OperData.AtsCtrlBlckAddr->SwitchPendFlag == TRUE) {
      SC_ServiceSwitchPend();
    }

    SC_ProcessAtpCmd();

    if (CurrentNumCmds == SC_OperData.NumCmdsWakeup) {
      SC_GetNextRtsTime();

      SC_ProcessRtpCommand();
    }

    /*
     * No commands could be processed
     */
    if (CurrentNumCmds == SC_OperData.NumCmdsWakeup) {
      break;
    }
  }

  SC_OperData.NumCmdsWakeup = 0;

  return CFE_SUCCESS;
}

/*******************************************************************************/
// No-op, which prints SC's version and is the only place the four version numbers are read.
I32 SC_NoopCmd(SC_NoopCmd_t *Cmd)
{
  SC_OperData.HkPacket.Payload.CmdCtr++;
  CFE_EVS_SendEvent(SC_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION, "No-op command. Version %d.%d.%d.%d",
                    SC_MAJOR_VERSION, SC_MINOR_VERSION, SC_REVISION, SC_MISSION_REV);

  return CFE_SUCCESS;
}

/*******************************************************************************/
// cFE Table Services' periodic "manage this table" request.
//
// **THE RANGES ARE ADJACENT AND THE BOUNDS ARE EXACT** -- see the file header. ATS 1..2, APPEND 3,
// RTS 4..7, then four singleton dump-only tables and the two ATS command-status tables. A `<=`
// where NASA writes `<` manages the next table along rather than falling into the error arm.
//
// AND THE DUMP-ONLY TABLES SKIP THE RELEASE/RE-ACQUIRE DANCE: NASA's comment "No need to release
// dump only table pointer" appears four times, because SC never holds a pointer into those --
// cFE writes them and SC only tells cFE when it may.
I32 SC_ManageTableCmd(SC_ManageTableCmd_t *Cmd)
{
  I32 ArrayIndex;
  I32 TableID = Cmd->Payload.Parameter;

  /* Manage selected table as appropriate for each table type */
  if (TableID >= SC_TBL_ID_ATS_0 && TableID < SC_TBL_ID_ATS_0 + SC_NUMBER_OF_ATS) {
    ArrayIndex = TableID - SC_TBL_ID_ATS_0;
    SC_ManageAtsTable(ArrayIndex);
  } else if (TableID == SC_TBL_ID_APPEND) {
    SC_ManageTable(APPEND, -1);
  } else if (TableID >= SC_TBL_ID_RTS_0 && TableID < SC_TBL_ID_RTS_0 + SC_NUMBER_OF_RTS) {
    ArrayIndex = TableID - SC_TBL_ID_RTS_0;
    SC_ManageRtsTable(ArrayIndex);
  } else if (TableID == SC_TBL_ID_RTS_INFO) {
    /* No need to release dump only table pointer */
    CFE_TBL_Manage(SC_OperData.RtsInfoHandle);
  } else if (TableID == SC_TBL_ID_RTP_CTRL) {
    /* No need to release dump only table pointer */
    CFE_TBL_Manage(SC_OperData.RtsCtrlBlckHandle);
  } else if (TableID == SC_TBL_ID_ATS_INFO) {
    /* No need to release dump only table pointer */
    CFE_TBL_Manage(SC_OperData.AtsInfoHandle);
  } else if (TableID == SC_TBL_ID_ATP_CTRL) {
    /* No need to release dump only table pointer */
    CFE_TBL_Manage(SC_OperData.AtsCtrlBlckHandle);
  } else if (TableID >= SC_TBL_ID_ATS_CMD_0 && TableID < SC_TBL_ID_ATS_CMD_0 + SC_NUMBER_OF_ATS) {
    /* No need to release dump only table pointer */
    ArrayIndex = TableID - SC_TBL_ID_ATS_CMD_0;
    CFE_TBL_Manage(SC_OperData.AtsCmdStatusHandle[ArrayIndex]);
  } else {
    /* Invalid table ID */
    CFE_EVS_SendEvent(SC_TABLE_MANAGE_ID_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Table manage command packet error: table ID = %d", TableID);
  }

  // No success/informational event is sent for this command intentionally, to avoid the risk of flooding.

  return CFE_SUCCESS;
}

/*******************************************************************************/
// **THE TWO WRAPPERS CHECK ONLY THE UPPER BOUND.** `ArrayIndex >= SC_NUMBER_OF_RTS` is the whole
// test; a negative index would pass it. It cannot be negative here -- SC_ManageTableCmd computes
// it as `TableID - SC_TBL_ID_RTS_0` inside a range check that already established TableID is at
// least SC_TBL_ID_RTS_0 -- so the guard is a second line of defence that only covers one side.
// Kept as written; noted because the two functions are otherwise identical and a reader comparing
// them will look for the difference.
U0 SC_ManageRtsTable(I32 ArrayIndex)
{
  /* validate array index */
  if (ArrayIndex >= SC_NUMBER_OF_RTS) {
    CFE_EVS_SendEvent(SC_TABLE_MANAGE_RTS_INV_INDEX_ERR_EID, CFE_EVS_EventType_ERROR,
                      "RTS table manage error: invalid RTS index %d", ArrayIndex);
    return;
  }

  SC_ManageTable(RTS, ArrayIndex);
}

/*******************************************************************************/
U0 SC_ManageAtsTable(I32 ArrayIndex)
{
  /* validate array index */
  if (ArrayIndex >= SC_NUMBER_OF_ATS) {
    CFE_EVS_SendEvent(SC_TABLE_MANAGE_ATS_INV_INDEX_ERR_EID, CFE_EVS_EventType_ERROR,
                      "ATS table manage error: invalid ATS index %d", ArrayIndex);
    return;
  }

  SC_ManageTable(ATS, ArrayIndex);
}

/*******************************************************************************/
// Release, manage, re-acquire -- and reload if cFE says the table changed.
//
// **`TblAddr` IS A POINTER TO A POINTER, AND THAT IS THE POINT OF THE FUNCTION.** The three table
// kinds live in three differently-shaped members of SC_OperData, and the switch takes the ADDRESS
// of the right one so the single `*TblAddr = TblPtrNew` below writes whichever it is. NASA's
// comment on that line is the one worth keeping: "CFE_TBL_GetAddress() sets this to NULL if it
// fails" -- so a failed re-acquire leaves SC with a null table pointer rather than a stale one,
// which is why every accessor in sc_global.HC can be read as trusting its buffer.
//
// THE `APPEND` CASE IS THE `default` CASE. `case APPEND:` and `default:` share a body, so an
// out-of-range type manages the append table rather than doing nothing -- and `SC_ManageTableCmd`
// only ever passes the three, so it cannot happen from there.
//
// AND TWO RETURN CODES ARE NOT ERRORS: `CFE_SUCCESS` and `CFE_TBL_ERR_NEVER_LOADED`. NASA's
// comment says "Ignore successful dump or validate and cmds before first activate" -- a table
// that has never been loaded is the normal state at startup, and treating it as an error would
// make SC noisy for the whole of its first few seconds.
U0 SC_ManageTable(I32 type, I32 ArrayIndex)
{
  I32 Result;
  I16 TblHandle;
  U32 **TblAddr;
  U8 *TblPtrNew;

  switch (type) {
    case ATS:
      TblHandle = SC_OperData.AtsTblHandle[ArrayIndex];
      TblAddr = &SC_OperData.AtsTblAddr[ArrayIndex];
      break;
    case RTS:
      TblHandle = SC_OperData.RtsTblHandle[ArrayIndex];
      TblAddr = &SC_OperData.RtsTblAddr[ArrayIndex];
      break;
    case APPEND:
    default:
      TblHandle = SC_OperData.AppendTblHandle;
      TblAddr = &SC_OperData.AppendTblAddr;
      break;
  }

  /* Release table data pointer */
  CFE_TBL_ReleaseAddress(TblHandle);

  /* Allow cFE to manage table */
  CFE_TBL_Manage(TblHandle);

  /* Re-acquire table data pointer */
  Result = CFE_TBL_GetAddress(&TblPtrNew, TblHandle);
  *TblAddr = TblPtrNew; /* Note that CFE_TBL_GetAddress() sets this to NULL if it fails */
  if (Result == CFE_TBL_INFO_UPDATED) {
    /* Process new table data */
    if (type == ATS) {
      SC_LoadAts(SC_ATS_IDX_C(ArrayIndex));
    } else if (type == RTS) {
      SC_LoadRts(SC_RTS_IDX_C(ArrayIndex));
    } else {
      SC_UpdateAppend();
    }
  } else if (Result != CFE_SUCCESS && Result != CFE_TBL_ERR_NEVER_LOADED) {
    /* Ignore successful dump or validate and cmds before first activate. */
    if (type == ATS) {
      CFE_EVS_SendEvent(SC_TABLE_MANAGE_ATS_ERR_EID, CFE_EVS_EventType_ERROR,
                        "ATS table manage process error: ATS = %u, Result = 0x%X",
                        SC_IDNUM_AS_UINT(SC_AtsIndexToNum(SC_ATS_IDX_C(ArrayIndex))), Result);
    } else if (type == RTS) {
      CFE_EVS_SendEvent(SC_TABLE_MANAGE_RTS_ERR_EID, CFE_EVS_EventType_ERROR,
                        "RTS table manage process error: RTS = %u, Result = 0x%X",
                        SC_IDNUM_AS_UINT(SC_RtsIndexToNum(SC_RTS_IDX_C(ArrayIndex))), Result);
    } else {
      CFE_EVS_SendEvent(SC_TABLE_MANAGE_APPEND_ERR_EID, CFE_EVS_EventType_ERROR,
                        "ATS Append table manage process error: Result = 0x%X", Result);
    }
  }
} /* End SC_ManageTable() */

#endif
