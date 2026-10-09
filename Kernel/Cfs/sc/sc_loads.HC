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
// STORED COMMAND'S LOADERS AND VALIDATORS -- the 1:1 translation of NASA's fsw/src/sc_loads.c,
// 893 lines and fifteen functions. **SC's largest source and the other half of its call cycle**:
// gating it retires the SC_ProcessAppend stand-in the previous commit left in both drivers.
//
// This is where SC's variable-length command stream is actually parsed. Everything else in the app
// walks indices this file builds.
//
// ### `SC_VerifyAtsEntry` RETURNS THREE DIFFERENT KINDS OF THING IN ONE `int32`
//
//     CFE_SUCCESS (0)   "no more entries" -- end of buffer, or a command number of zero
//     SC_ERROR    (-1)  the entry is invalid; an event has been sent
//     anything > 0      **the entry's SIZE IN WORDS**, and the caller must advance by it
//
// So `SC_VerifyAtsTable`'s loop has to test for 0 and -1 separately before treating the value as a
// length, and it does. That works only because a valid entry is always at least
// SC_ATS_HDR_NOPKT_WORDS + 1 = three words, so a real size can never collide with either sentinel.
// A reader who takes `Result == CFE_SUCCESS` for "the entry was fine" has it exactly backwards:
// success means STOP.
//
// ### THE DUPLICATE TEST STORES AN INDEX, NOT A FLAG
//
// `SC_SetAtsDupTest(CmdNumber, EntryIndex)` records WHERE each command number was first seen, so
// the rejection event can say `dup index = %d`. That is why SC_DUP_TEST_UNUSED is **-1** and not
// 0: buffer index 0 is a perfectly good place for the first command, so zero cannot mean "unused".
// A `bool` array here would have cost the diagnostic.
//
// ### UPSTREAM: `SC_UpdateAppend` COMPUTES THE SAME BYTE COUNT TWO WAYS, ONE LINE APART
//
//     SC_OperData.HkPacket.Payload.AppendByteCount = EntryIndex * SC_BYTES_IN_ATS_APPEND_ENTRY;
//     ...
//     CFE_EVS_SendEvent(..., "... byte count = %d", (int)EntryIndex * SC_BYTES_IN_WORD);
//
// `EntryIndex` is a count of **32-bit words** -- every `EntryIndex +=` in the function adds
// `SC_ATS_HDR_NOPKT_WORDS + CommandWords`, and CommandWords is `(bytes + 3) / 4`. So the byte count
// is `EntryIndex * 4`, which is what the EVENT prints. **The housekeeping field is multiplied by
// SC_BYTES_IN_ATS_APPEND_ENTRY, which is 2**, so the telemetry point reports HALF the real size
// while the event beside it reports all of it. `SC_VerifyAtsTable`'s event uses `* 4` too, so two
// of the three byte counts in this file agree and the one in the packet does not.
//
// Kept verbatim; docs/CFS_UPSTREAM_NOTES.md #25 sets out the evidence, including the memcpy in
// SC_ProcessAppend that settles which of the two numbers is the real byte count. **IT IS NOT
// DRIVEN YET** -- SC has no exercise block, so nothing in the transcript comes from this function,
// and the note says so rather than implying a run.
//
// ### AND SC_Insert's SORT DEPENDS ON 16-BIT WRAPAROUND, WHICH WAS MEASURED BEFORE IT WAS WRITTEN
//
// `TimeBufIndex = SC_SEQUENCE_IDX_C(ListLength - 1)` is `(uint16)(-1)` = 65535 on an empty list, so
// the loop does not run; then `SC_IDX_INCREMENT(TimeBufIndex)` must take 65535 back to **0** to
// place the first element. And inside the loop `SC_IDX_DECREMENT` must take 0 to 65535 -- NASA's
// comment says "back up to previous list entry (ok if -1)".
//
// That is uint16 lvalue arithmetic in C, and HolyC's U16 was MEASURED to do the same before this
// file was written: `tests/exec/cases/e_u16_wrap_insert.hc` pins `++` on 65535, `--` on 0,
// `= len - 1` from a U32 zero, and the `(U16)` cast of -1, against values printed by a C twin, and
// then runs this sort in miniature. Three of its four mutations fail as required.
//
// **AND THE FOURTH DID NOT, WHICH IS WORTH KNOWING HERE.** Widening the sort's own index to I64
// changes nothing, because every mask in the walk comes from one of SC's casts --
// `SC_SEQUENCE_IDX_C` on the way in and `SC_IDX_AS_UINT` inside the guard -- and not from the
// declared type of TimeBufIndex. So SC_Insert is more robust than it reads: it is the four
// isolated forms that carry the claim, not the sort. The case says so in its own header.
//
// ### THE REMAINING SIX CALL-ARROW HOISTS ARE HERE, AND ONE IS A **WRITE**
//
// Hoists 7 through 12 of 12. Five are reads; the pair at NASA's sc_loads.c:308-309 is
//
//     SC_GetAtsCommandNumAtSeq(AtsIndex, NextIndex)->CmdNum =
//         SC_GetAtsCommandNumAtSeq(AtsIndex, TimeBufIndex)->CmdNum;
//
// -- a STORE through the arrow as well as a load. The open HolyC defect resolves the arrow against
// the first argument's class, these accessors take scalars, and the result is an access through
// zero: a read through zero traps, a write through zero corrupts. Both sides are hoisted.
#ifndef SC_LOADS_HC
#define SC_LOADS_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// sc_cfg.HC, sc_tbl.HC, sc_msg.HC, sc_global.HC, sc_events.HC, sc_utils.HC, sc_atsrq.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13.
//
// It calls exactly ONE function from sc_atsrq.HC -- SC_BeginAts, in SC_ProcessAppend's restart arm
// -- which is the other direction of the call cycle. With this file gated the cycle is closed and
// no stand-in remains.

// --- sc_loads.h's prototypes -------------------------------------------------------------------
Bool SC_ParseRts(U32 *Buffer32);
U0 SC_BuildTimeIndexTable(U16 AtsIndex);
U0 SC_Insert(U16 AtsIndex, U16 NewCmdIndex, U32 ListLength);
U0 SC_InitAtsTables(U16 AtsIndex);
I32 SC_VerifyAtsTable(U32 *Buffer32, I32 BufferWords);
I32 SC_VerifyAtsEntry(U32 *Buffer32, I32 EntryIndex, I32 BufferWords);
U0 SC_LoadAts(U16 AtsIndex);
I32 SC_ValidateAts(U8 *TableData);
I32 SC_ValidateAppend(U8 *TableData);
U0 SC_UpdateAppend();
U0 SC_ProcessAppend(U16 AtsIndex);
U0 SC_LoadRts(U16 RtsIndex);
I32 SC_ValidateRts(U8 *TableData);

// --- the two `static inline` helpers NASA declares in the .c rather than a header --------------
I32 SC_GetAtsDupTest(U16 CmdId);
U0 SC_SetAtsDupTest(U16 CmdId, I32 Val);

/*******************************************************************************/
// The duplicate-test array, indexed by command INDEX and holding a buffer INDEX -- see the file
// header on why the sentinel is -1.
I32 SC_GetAtsDupTest(U16 CmdId)
{
  return SC_OperData.AtsDupTestArray[SC_IDX_AS_UINT(SC_CommandNumToIndex(CmdId))];
}

U0 SC_SetAtsDupTest(U16 CmdId, I32 Val)
{
  SC_OperData.AtsDupTestArray[SC_IDX_AS_UINT(SC_CommandNumToIndex(CmdId))] = Val;
}

/*******************************************************************************/
// Parse a loaded ATS buffer into the offset and status tables.
//
// **THE WALK IS THE APP.** Each entry is a header plus a variable-length command, so the only way
// to find entry N is to have walked entries 0..N-1 -- which is why this builds a table of offsets
// and why every later access goes through it.
//
// FOUR WAYS TO STOP, and only one is an error-free end: a command number of zero (the normal
// terminator), an invalid command number, an entry that cannot hold even the smallest command, and
// running exactly to the end of the buffer. NASA's comment on the last is worth keeping -- it
// explains why no `>=` test is needed there.
U0 SC_LoadAts(U16 AtsIndex)
{
  U16 AtsCmdNum;         /* current ats entry command number */
  U16 AtsEntryIndex;     /* index into the load for current ats entry */
  U16 PendingEntryIndex; /* index into the load for current ats entry */
  SC_AtsEntry_t *EntryPtr; /* a pointer to an ats entry */
  I64 MessageSize = 0;
  I32 Result = CFE_SUCCESS;
  Bool StillProcessing = TRUE;
  SC_AtsInfoTable_t *AtsInfoPtr;
  SC_AtsCmdStatusEntry_t *StatusEntryPtr;
  SC_AtsCmdEntryOffsetRecord_t *CmdOffsetRec; /* ATS entry location in table */

  /* validate ATS array index */
  if (!SC_AtsIndexIsValid(AtsIndex)) {
    CFE_EVS_SendEvent(SC_LOADATS_INV_INDEX_ERR_EID, CFE_EVS_EventType_ERROR,
                      "ATS load error: invalid ATS index %d", SC_IDX_AS_UINT(AtsIndex));
    return;
  }

  /*
   ** Initialize all structures
   */
  SC_InitAtsTables(AtsIndex);

  /* initialize pointers and counters */
  AtsInfoPtr = SC_GetAtsInfoObject(AtsIndex);
  AtsEntryIndex = SC_ENTRY_OFFSET_FIRST;

  while (StillProcessing) {
    /*
     ** Make sure that the pointer as well as the primary packet
     ** header fit in the buffer, so a G.P fault is not caused.
     */
    if (SC_IDX_WITHIN_LIMIT(AtsEntryIndex, SC_ATS_BUFF_SIZE32)) {
      /* get a pointer to the ats command in the table */
      EntryPtr = SC_GetAtsEntryAtOffset(AtsIndex, AtsEntryIndex);

      /* get the next command number from the buffer */
      AtsCmdNum = EntryPtr->Header.CmdNumber;

      if (SC_IDNUM_IS_NULL(AtsCmdNum)) {
        /* end of the load reached */
        Result = CFE_SUCCESS;
        break;
      }

      if (!SC_AtsCommandNumIsValid(AtsCmdNum)) {
        /* the cmd number is invalid */
        Result = SC_ERROR;
        break;
      }

      /* make sure the CmdPtr can fit in a whole Ats Cmd Header at the very least */
      if (!SC_IDX_WITHIN_LIMIT(AtsEntryIndex, 1 + (SC_ATS_BUFF_SIZE32 - SC_ATS_HDR_WORDS))) {
        /* even the smallest command will not fit in the buffer */
        Result = SC_ERROR;
        break;
      }

      StatusEntryPtr = SC_GetAtsStatusEntryForCommand(AtsIndex, SC_CommandNumToIndex(AtsCmdNum));
      CmdOffsetRec = SC_GetAtsEntryOffsetForCmd(AtsIndex, SC_CommandNumToIndex(AtsCmdNum));

      // **THE DUPLICATE CHECK IS THIS `if`, AND IT READS AS A LENGTH CHECK.** A command number
      // already seen in this load has status LOADED rather than EMPTY, so the `else` below --
      // whose comment says "the cmd number is invalid" -- is actually the DUPLICATE arm. NASA's
      // comment is wrong about which condition it is under; the behaviour is right either way.
      if (StatusEntryPtr->Status == SC_Status_EMPTY) {
        /* get message size */
        CFE_MSG_GetSize(&EntryPtr->Msg.Msg, &MessageSize);

        /* if the length of the command is valid */
        if (MessageSize >= SC_PACKET_MIN_SIZE && MessageSize <= SC_PACKET_MAX_SIZE) {
          /* get the length of the entry in WORDS (plus 1 to round byte len up to word len) */
          PendingEntryIndex = SC_EntryOffsetAdvance(AtsEntryIndex, MessageSize + SC_ATS_HEADER_SIZE);

          /* if the command does not run off of the end of the buffer */
          if (SC_IDX_WITHIN_LIMIT(PendingEntryIndex, 1 + SC_ATS_BUFF_SIZE32)) {
            /* set the command pointer in the command index table */
            /* CmdNum starts at one....                          */

            CmdOffsetRec->Offset = AtsEntryIndex;

            /* set the command status to loaded in the command status table */
            StatusEntryPtr->Status = SC_Status_LOADED;

            /* increment the number of commands loaded */
            AtsInfoPtr->NumberOfCommands++;

            /* increment the ats_entry index to the next ats entry */
            AtsEntryIndex = PendingEntryIndex;
          } else { /* the command runs off the end of the buffer */
            Result = SC_ERROR;
            StillProcessing = FALSE;
          } /* end if */
        } else { /* the command length was invalid */
          Result = SC_ERROR;
          StillProcessing = FALSE;
        } /* end if */
      } else { /* the cmd number is invalid */
        Result = SC_ERROR;
        StillProcessing = FALSE;
      } /* end if */
    } else {
      /*
       ** We encountered a load exactly as long as the buffer.
       ** AtsEntryIndex cannot exceed SC_ATS_BUFF_SIZE32 here.
       ** A command pointer over the end of the buffer will be
       ** identified above before AtsEntryIndex is incremented.
       ** Consequently this block does not require verifying
       ** AtsEntryIndex >= SC_ATS_BUFF_SIZE32.
       */

      Result = CFE_SUCCESS;
      StillProcessing = FALSE;
    } /*end else */
  }   /* end while */

  /*
   **   Now the commands are parsed through, need to build the tables
   **   if the load was a success, need to build the tables
   */
  /* if the load finished without errors and there was at least one command */
  if (Result == CFE_SUCCESS && AtsInfoPtr->NumberOfCommands > 0) {
    /* record the size of the load in the ATS info table */
    AtsInfoPtr->AtsSize = SC_IDX_AS_UINT(AtsEntryIndex); /* size in 32-bit WORDS */

    /* build the time index table */
    SC_BuildTimeIndexTable(AtsIndex);
  } else { /* there was an error */
    // **A FAILED LOAD WIPES THE TABLE RATHER THAN LEAVING A PARTIAL ONE.** SC_InitAtsTables was
    // already called at the top, so this second call discards whatever the partial walk had
    // recorded -- which is why a rejected ATS load leaves NumberOfCommands at 0 and not at the
    // count reached before the bad entry.
    SC_InitAtsTables(AtsIndex);
  } /* end if */
}

/*******************************************************************************/
// Build the time-sorted command list for an ATS: clear every slot, then insert each in-use command
// in turn.
//
// **IT CLEARS AND INSERTS IN THE SAME LOOP**, which is only safe because SC_Insert never looks
// above `ListLength` -- slot i is cleared on iteration i, and the insertion for iteration i can
// only touch slots 0..i. A separate clearing pass would be equivalent; one pass is NASA's.
U0 SC_BuildTimeIndexTable(U16 AtsIndex)
{
  I32 i;
  I32 ListLength;
  U16 CmdIdx;
  SC_AtsCmdNumRecord_t *AtsCmdNumRec;
  SC_AtsCmdEntryOffsetRecord_t *CmdOffsetRec; /* THE HOIST -- see below */

  /* validate ATS array index */
  if (!SC_AtsIndexIsValid(AtsIndex)) {
    CFE_EVS_SendEvent(SC_BUILD_TIME_IDXTBL_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Build time index table error: invalid ATS index %u", SC_IDX_AS_UINT(AtsIndex));
    return;
  }

  /* initialize sorted list length */
  ListLength = 0;

  /* initialize sorted list contents */
  for (i = 0; i < SC_MAX_ATS_CMDS; i++) {
    AtsCmdNumRec = SC_GetAtsCommandNumAtSeq(AtsIndex, SC_SEQUENCE_IDX_C(i));
    AtsCmdNumRec->CmdNum = SC_INVALID_CMD_NUMBER;

    /* add in-use command entries to time sorted list */
    CmdIdx = SC_COMMAND_IDX_C(i);
    // **CALL-ARROW HOIST 7 OF 12.**
    CmdOffsetRec = SC_GetAtsEntryOffsetForCmd(AtsIndex, CmdIdx);
    if (!SC_IDX_EQUAL(CmdOffsetRec->Offset, SC_ENTRY_OFFSET_INVALID)) {
      SC_Insert(AtsIndex, CmdIdx, ListLength);
      ListLength++;
    }
  }
}

/*******************************************************************************/
// Insert one command into the time-sorted list, shifting later entries up.
//
// **THE SORT IS STABLE AND THAT IS WHY `SC_CompareAbsTime` IS STRICTLY GREATER.** The loop moves a
// list entry only when `ListCmdTime > NewCmdTime`, so an entry with the SAME time stops the walk
// and the new command lands after it -- which keeps equal-time commands in the order the ground
// uploaded them. A `>=` here would reverse them.
//
// AND IT RELIES ON 16-BIT WRAPAROUND TWICE -- see the file header, where it is measured.
U0 SC_Insert(U16 AtsIndex, U16 NewCmdIndex, U32 ListLength)
{
  SC_AtsEntryHeader_t *EntryHeader; /* ATS table entry pointer */
  U32 NewCmdTime = 0;               /* new command execution time */
  U32 ListCmdTime;                  /* list entry execution time */
  U16 CmdIndex;                     /* ATS command index (cmd num - 1) */
  U16 TimeBufIndex;
  U16 NextIndex;
  SC_AtsCmdEntryOffsetRecord_t *CmdOffsetRec; /* ATS entry location in table */
  SC_AtsCmdNumRecord_t *AtsCmdNumRec;
  SC_AtsEntry_t *AtsEntry;      /* THE HOISTS -- see below */
  SC_AtsCmdNumRecord_t *SrcRec;
  SC_AtsCmdNumRecord_t *DstRec;

  /* validate ATS array index */
  if (!SC_AtsIndexIsValid(AtsIndex)) {
    CFE_EVS_SendEvent(SC_INSERTATS_INV_INDEX_ERR_EID, CFE_EVS_EventType_ERROR,
                      "ATS insert error: invalid ATS index %u", SC_IDX_AS_UINT(AtsIndex));
    return;
  }

  /* get execution time for new list entry */
  // NOTE THE GUARD: on an EMPTY list NewCmdTime stays 0 and the entry's real time is never read.
  // It does not matter, because the loop below does not run either -- but it means the first
  // command inserted is placed without its time being looked at at all.
  if (ListLength > 0) {
    /* first get the entry index in the selected ATS table for the new command */
    CmdOffsetRec = SC_GetAtsEntryOffsetForCmd(AtsIndex, NewCmdIndex);
    /* then get a pointer to the ATS entry */
    // **CALL-ARROW HOIST 8 OF 12.**
    AtsEntry = SC_GetAtsEntryAtOffset(AtsIndex, CmdOffsetRec->Offset);
    EntryHeader = &AtsEntry->Header;
    /* then get the execution time from the ATS entry for the new command */
    NewCmdTime = SC_GetAtsEntryTime(EntryHeader);
  }

  /* start at last element in the sorted by time list */
  // 65535 WHEN ListLength IS 0 -- the (U16) cast masks, so the loop below does not run. See the
  // file header.
  TimeBufIndex = SC_SEQUENCE_IDX_C(ListLength - 1);

  while (SC_IDX_WITHIN_LIMIT(TimeBufIndex, ListLength)) {
    /* first get the cmd index for this list entry */
    // **CALL-ARROW HOIST 9 OF 12.**
    AtsCmdNumRec = SC_GetAtsCommandNumAtSeq(AtsIndex, TimeBufIndex);
    CmdIndex = SC_CommandNumToIndex(AtsCmdNumRec->CmdNum);
    /* then get the entry index from the ATS table */
    CmdOffsetRec = SC_GetAtsEntryOffsetForCmd(AtsIndex, CmdIndex);
    /* then get a pointer to the ATS entry data */
    // **CALL-ARROW HOIST 10 OF 12.**
    AtsEntry = SC_GetAtsEntryAtOffset(AtsIndex, CmdOffsetRec->Offset);
    EntryHeader = &AtsEntry->Header;
    /* then get cmd execution time from the ATS entry */
    ListCmdTime = SC_GetAtsEntryTime(EntryHeader);

    /* compare time for this list entry to time for new cmd */
    if (SC_CompareAbsTime(ListCmdTime, NewCmdTime)) {
      /* new cmd will execute before this list entry */

      /* move this list entry to make room for new cmd */
      NextIndex = TimeBufIndex;
      SC_IDX_INCREMENT(NextIndex);

      // **CALL-ARROW HOISTS 11 AND 12 OF 12, AND THE DESTINATION IS A WRITE.** NASA writes
      //     SC_GetAtsCommandNumAtSeq(AtsIndex, NextIndex)->CmdNum =
      //         SC_GetAtsCommandNumAtSeq(AtsIndex, TimeBufIndex)->CmdNum;
      // A read through zero traps; a STORE through zero corrupts whatever is at zero. Both sides
      // hoisted, source first so the order of evaluation is the one C guarantees here.
      SrcRec = SC_GetAtsCommandNumAtSeq(AtsIndex, TimeBufIndex);
      DstRec = SC_GetAtsCommandNumAtSeq(AtsIndex, NextIndex);
      DstRec->CmdNum = SrcRec->CmdNum;

      /* back up to previous list entry (ok if -1) */
      SC_IDX_DECREMENT(TimeBufIndex);
    } else {
      /* new cmd will execute at same time or after this list entry */
      break;
    }
  }

  /*
  ** TimeBufIndex is now one slot before the target slot...
  **   if new cmd time is earlier than all other entries
  **     then TimeBufIndex is -1 and all others have been moved
  **   else only entries with later times have been moved
  ** In either case, there is an empty slot next to TimeBufIndex
  */
  SC_IDX_INCREMENT(TimeBufIndex);

  AtsCmdNumRec = SC_GetAtsCommandNumAtSeq(AtsIndex, TimeBufIndex);
  AtsCmdNumRec->CmdNum = SC_CommandIndexToNum(NewCmdIndex);
}

/*******************************************************************************/
// Clear an ATS's three parallel tables and its info entry.
//
// **ONE LOOP WRITES THREE TABLES INDEXED THREE DIFFERENT WAYS** -- a COMMAND index for the status
// and offset tables and a SEQUENCE index for the time-sorted list. They are all `i` here because
// all three arrays are SC_MAX_ATS_CMDS long, so the distinction sc_tbl.HC's header describes costs
// nothing on this line and everything on a line that mixes them up.
U0 SC_InitAtsTables(U16 AtsIndex)
{
  I32 i;
  SC_AtsInfoTable_t *AtsInfoPtr;
  SC_AtsCmdStatusEntry_t *StatusEntryPtr;
  SC_AtsCmdEntryOffsetRecord_t *CmdOffsetRec;
  SC_AtsCmdNumRecord_t *AtsCmdNumRec;

  /* validate ATS array index */
  if (!SC_AtsIndexIsValid(AtsIndex)) {
    CFE_EVS_SendEvent(SC_INIT_ATSTBL_INV_INDEX_ERR_EID, CFE_EVS_EventType_ERROR,
                      "ATS table init error: invalid ATS index %u", SC_IDX_AS_UINT(AtsIndex));
    return;
  }

  /* loop through and set the ATS tables to zero */
  for (i = 0; i < SC_MAX_ATS_CMDS; i++) {
    StatusEntryPtr = SC_GetAtsStatusEntryForCommand(AtsIndex, SC_COMMAND_IDX_C(i));
    CmdOffsetRec = SC_GetAtsEntryOffsetForCmd(AtsIndex, SC_COMMAND_IDX_C(i));
    AtsCmdNumRec = SC_GetAtsCommandNumAtSeq(AtsIndex, SC_SEQUENCE_IDX_C(i));

    CmdOffsetRec->Offset = SC_ENTRY_OFFSET_INVALID;
    StatusEntryPtr->Status = SC_Status_EMPTY;
    AtsCmdNumRec->CmdNum = SC_INVALID_CMD_NUMBER;
  }

  /* initialize the pointers and counters   */
  AtsInfoPtr = SC_GetAtsInfoObject(AtsIndex);
  AtsInfoPtr->AtsSize = 0;
  AtsInfoPtr->NumberOfCommands = 0;
}

/*******************************************************************************/
// Initialise an RTS's info entry after a table load.
//
// **IT DOES NOT PARSE ANYTHING**, despite the name pairing with SC_LoadAts. An RTS runs in buffer
// order, so there is no index to build -- the whole function is six assignments. And **it leaves
// the RTS DISABLED**: a freshly loaded RTS cannot be started until the ground enables it, which is
// the opposite of a freshly loaded ATS.
U0 SC_LoadRts(U16 RtsIndex)
{
  SC_RtsInfoEntry_t *RtsInfoPtr;

  /* validate RTS array index */
  if (SC_RtsIndexIsValid(RtsIndex)) {
    /* Clear out the RTS info table */
    RtsInfoPtr = SC_GetRtsInfoObject(RtsIndex);

    RtsInfoPtr->RtsStatus = SC_Status_LOADED;
    RtsInfoPtr->UseCtr = 0;
    RtsInfoPtr->CmdCtr = 0;
    RtsInfoPtr->CmdErrCtr = 0;
    RtsInfoPtr->NextCommandTgtWakeup = 0;
    RtsInfoPtr->NextCommandPtr = SC_ENTRY_OFFSET_FIRST;

    /* Make sure the RTS is disabled */
    RtsInfoPtr->DisabledFlag = TRUE;
  } else {
    CFE_EVS_SendEvent(SC_LOADRTS_INV_INDEX_ERR_EID, CFE_EVS_EventType_ERROR,
                      "RTS table init error: invalid RTS index %u", SC_IDX_AS_UINT(RtsIndex));
    return;
  }
} /* SC_LoadRts */

/*******************************************************************************/
// cFE's validation callback for an ATS table. Two lines, and the second is the whole reason the
// verifier takes a size: the append table uses the same code with a different bound.
I32 SC_ValidateAts(U8 *TableData)
{
  I32 Result;

  /* Common ATS table verify function needs size of this table */
  Result = SC_VerifyAtsTable(TableData(U32 *), SC_ATS_BUFF_SIZE32);

  return Result;
}

/*******************************************************************************/
// Walk an RTS buffer checking every command's message id and length.
//
// **THE TERMINATOR IS AN INVALID MESSAGE ID WITH A ZERO WAKEUP COUNT**, and the pair matters: an
// invalid id with a NON-zero wakeup count is an error, because a real terminator is all zeroes.
// So a buffer that was partly overwritten with garbage is rejected where a cleanly short one is
// accepted.
//
// AND THE "LOOKS EMPTY" TEST AT THE END READS ONE RAW WORD. When the remaining space cannot hold
// even a minimum command, NASA tests `Buffer32[i] == 0` -- the raw word, not a field -- to tell
// "the load ended tidily" from "there is data here that cannot fit". `i` is at most
// SC_RTS_BUFF_SIZE32 - 1 at that point, so the read is in bounds.
Bool SC_ParseRts(U32 *Buffer32)
{
  U16 i;
  Bool Done;
  Bool Error;
  SC_RtsEntry_t *EntryPtr;
  I64 CmdSize = 0;
  U16 IndexDelta;
  CFE_SB_MsgId MessageID;

  MessageID = CFE_SB_InvalidMsgId();

  i = 0;
  Done = FALSE;
  Error = FALSE;
  while (Error == FALSE && Done == FALSE) {
    /*
     ** Check to see if a minimum command fits within an RTS
     */
    if (i <= SC_RTS_BUFF_SIZE32 - SC_RTS_HDR_WORDS) {
      /*
       ** Cast a header to the RTS buffer current location
       ** and get the size of the packet
       */
      EntryPtr = &Buffer32[i](SC_RtsEntry_t *);

      CFE_MSG_GetSize(&EntryPtr->Msg.Msg, &CmdSize);

      /* Add header size, round up to boundary, convert to index delta  */
      // `sizeof(Buffer32[0])` IN NASA, WHICH IS sizeof(uint32) = 4. HolyC's sizeof of an indexed
      // expression is not worth relying on, and the constant is the same thing spelled plainly.
      IndexDelta = (CmdSize + SC_RTS_HEADER_SIZE + SC_ROUND_UP_BYTES) / sizeof(U32);

      CFE_MSG_GetMsgId(&EntryPtr->Msg.Msg, &MessageID);

      if (!CFE_SB_IsValidMsgId(MessageID)) {
        if (EntryPtr->Header.WakeupCount == 0) {
          Done = TRUE; /* assumed end of file */
        } else {
          CFE_EVS_SendEvent(SC_RTS_INVLD_MID_ERR_EID, CFE_EVS_EventType_ERROR,
                            "RTS cmd loaded with invalid MID at %d", i);
          Error = TRUE; /* invalid message id */
        }
      } else {
        /* check to see if the length field in the RTS is valid */
        if (CmdSize < SC_PACKET_MIN_SIZE || CmdSize > SC_PACKET_MAX_SIZE) {
          CFE_EVS_SendEvent(SC_RTS_LEN_ERR_EID, CFE_EVS_EventType_ERROR,
                            "RTS cmd loaded with invalid length at %d, len: %d", i, CmdSize);

          Error = TRUE; /* Length error */
        }

        else if (i + IndexDelta > SC_RTS_BUFF_SIZE32) {
          CFE_EVS_SendEvent(SC_RTS_LEN_BUFFER_ERR_EID, CFE_EVS_EventType_ERROR,
                            "RTS cmd at %d runs off end of buffer", i);
          Error = TRUE; /* command runs off of the end of the buffer */
        }

        // EXACTLY FULL IS SUCCESS, one more word is an error -- the `==` arm above the `>` arm.
        else if (i + IndexDelta == SC_RTS_BUFF_SIZE32) {
          Done = TRUE;
        } else { /* command fits in buffer */

          i += IndexDelta;

        } /* end if */

      } /* endif */
    } else { /* command does not fit in the buffer */

      /*
       ** If it looks like there is data, reject the load,
       ** if it looks empty then we are done
       */
      if (Buffer32[i] == 0) {
        Done = TRUE;
      } else {
        CFE_EVS_SendEvent(SC_RTS_LEN_TOO_LONG_ERR_EID, CFE_EVS_EventType_ERROR,
                          "RTS cmd loaded won't fit in buffer at %d", i);
        Error = TRUE;
      }
    } /* endif */

  } /* endwhile */

  /*
   ** finished, report results
   */

  /* If Error was true   , then SC_ParseRts must return false    */
  return !Error;
}

/*******************************************************************************/
// cFE's validation callback for an RTS table.
I32 SC_ValidateRts(U8 *TableData)
{
  U32 *TableDataPtr;
  I32 Result = CFE_SUCCESS;

  TableDataPtr = TableData(U32 *);

  /*
   ** make a rough check on the first command to see if there is
   ** something in the buffer
   */
  if (SC_ParseRts(TableDataPtr) == FALSE) {
    /* event message is put out by Parse RTS */
    Result = SC_ERROR;
  }

  return Result;
}

/*******************************************************************************/
// cFE's validation callback for the append table -- **the same verifier as the ATS, with a
// different bound**. SC_APPEND_BUFF_SIZE32 is 2000 against the ATS's 4000.
I32 SC_ValidateAppend(U8 *TableData)
{
  I32 Result;

  /* Common ATS table verify function needs size of this table */
  Result = SC_VerifyAtsTable(TableData(U32 *), SC_APPEND_BUFF_SIZE32);

  return Result;
}

/*******************************************************************************/
// Count the entries in a newly loaded append table and record its size.
//
// **UPSTREAM #25 IS THE TWO LINES NEAR THE END**: the housekeeping byte count is `EntryIndex * 2`
// and the event's is `EntryIndex * 4`, for the same quantity in the same call. EntryIndex is in
// 32-bit words, so the event is right. See the file header.
//
// AND NOTE IT STOPS SILENTLY ON EVERY ERROR. An invalid command number, a bad length and an entry
// that overruns the buffer all just end the count -- no event, no error return -- because this runs
// after cFE has already VALIDATED the table through SC_ValidateAppend. So the counting walk trusts
// what the validating walk checked, and the two walks are separate code.
U0 SC_UpdateAppend()
{
  SC_AtsEntry_t *EntryPtr;
  I64 CommandBytes = 0;
  I32 CommandWords;
  I32 EntryIndex = 0;
  I32 EntryCount = 0;
  Bool StillProcessing = TRUE;

  /* Count Append ATS table entries and get total size */
  while (StillProcessing) {
    if (EntryIndex >= SC_APPEND_BUFF_SIZE32) {
      /* End of Append ATS table buffer */
      StillProcessing = FALSE;
    } else {
      EntryPtr = &SC_OperData.AppendTblAddr[EntryIndex](SC_AtsEntry_t *);

      if (!SC_AtsCommandNumIsValid(EntryPtr->Header.CmdNumber)) {
        /* End of valid command numbers */
        StillProcessing = FALSE;
      } else {
        CFE_MSG_GetSize(&EntryPtr->Msg.Msg, &CommandBytes);
        CommandWords = (CommandBytes + SC_ROUND_UP_BYTES) / SC_BYTES_IN_WORD;

        if (CommandBytes < SC_PACKET_MIN_SIZE || CommandBytes > SC_PACKET_MAX_SIZE) {
          /* Entry command packet must have a valid length */
          StillProcessing = FALSE;
        } else if (EntryIndex + SC_ATS_HDR_NOPKT_WORDS + CommandWords > SC_APPEND_BUFF_SIZE32) {
          /* Entry command packet must fit within ATS append table buffer */
          StillProcessing = FALSE;
        } else {
          /* Compute buffer index for next Append ATS table entry */
          EntryIndex += SC_ATS_HDR_NOPKT_WORDS + CommandWords;
          EntryCount++;
        }
      }
    }
  }

  /* Results will also be reported in HK */
  SC_OperData.HkPacket.Payload.AppendLoadCount++;
  SC_OperData.HkPacket.Payload.AppendEntryCount = EntryCount;
  // **UPSTREAM #25: `* 2` HERE AND `* 4` IN THE EVENT BELOW.** EntryIndex counts 32-bit words, so
  // this telemetry point is half the real byte count. Kept verbatim.
  SC_OperData.HkPacket.Payload.AppendByteCount = EntryIndex * SC_BYTES_IN_ATS_APPEND_ENTRY;
  SC_AppData.AppendWordCount = EntryIndex;

  CFE_EVS_SendEvent(SC_UPDATE_APPEND_EID, CFE_EVS_EventType_INFORMATION,
                    "Update Append ATS Table: load count = %d, command count = %d, byte count = %d",
                    SC_OperData.HkPacket.Payload.AppendLoadCount, EntryCount,
                    EntryIndex * SC_BYTES_IN_WORD);
}

/*******************************************************************************/
// Copy the append table onto the end of an ATS and rebuild its index.
//
// **THIS IS THE FUNCTION THE PREVIOUS COMMIT STOOD IN FOR**, and the stand-in did nothing -- so
// SC_AppendAtsCmd's success event reported an append that had not happened. With this file gated
// the cycle is closed and the stand-in is gone from both drivers.
//
// A REPLACED COMMAND IS NOT A NEW ONE: the `if (Status == EMPTY)` is what keeps NumberOfCommands
// from double-counting a command number the append overwrites. So an append can REPLACE commands
// as well as add them, and the count only moves for the additions.
//
// AND IT RESTARTS A RUNNING ATS. If the appended-to ATS is the one executing, SC_BeginAts is called
// with offset 0, which re-walks and re-skips -- NASA's comment explains that this discards both the
// already-executed old entries and any new entries whose time has passed. That is the one place in
// SC where a table load changes what is currently running.
U0 SC_ProcessAppend(U16 AtsIndex)
{
  SC_AtsEntry_t *EntryPtr;
  I64 CommandBytes = 0;
  U16 EntryIndex;
  I32 i;
  U16 CmdIndex;
  SC_AtsInfoTable_t *AtsInfoPtr;
  SC_AtsCmdStatusEntry_t *StatusEntryPtr;
  SC_AtsCmdEntryOffsetRecord_t *CmdOffsetRec;

  /* validate ATS array index */
  if (!SC_AtsIndexIsValid(AtsIndex)) {
    CFE_EVS_SendEvent(SC_PROCESS_APPEND_INV_INDEX_ERR_EID, CFE_EVS_EventType_ERROR,
                      "ATS process append error: invalid ATS index %u", SC_IDX_AS_UINT(AtsIndex));
    return;
  }

  /* save index of free area at end of ATS table data */
  AtsInfoPtr = SC_GetAtsInfoObject(AtsIndex);
  EntryIndex = SC_ENTRY_OFFSET_C(AtsInfoPtr->AtsSize);

  /* copy Append table data to end of ATS table data */
  MemCpy(SC_GetAtsEntryAtOffset(AtsIndex, EntryIndex), SC_OperData.AppendTblAddr,
         SC_AppData.AppendWordCount * SC_BYTES_IN_WORD);

  /* update size of ATS table data */
  AtsInfoPtr->AtsSize += SC_AppData.AppendWordCount;

  /* add appended entries to ats process tables */
  for (i = 0; i < SC_OperData.HkPacket.Payload.AppendEntryCount; i++) {
    /* get pointer to next appended entry */
    EntryPtr = SC_GetAtsEntryAtOffset(AtsIndex, EntryIndex);

    /* convert base one cmd number to base zero index */
    CmdIndex = SC_CommandNumToIndex(EntryPtr->Header.CmdNumber);

    StatusEntryPtr = SC_GetAtsStatusEntryForCommand(AtsIndex, CmdIndex);
    CmdOffsetRec = SC_GetAtsEntryOffsetForCmd(AtsIndex, CmdIndex);

    /* count only new commands, not replaced commands */
    if (StatusEntryPtr->Status == SC_Status_EMPTY) {
      AtsInfoPtr->NumberOfCommands++;
    }

    /* update array of pointers to ats entries */
    CmdOffsetRec->Offset = EntryIndex;
    StatusEntryPtr->Status = SC_Status_LOADED;

    /* update entry index to point to the next entry */
    CFE_MSG_GetSize(&EntryPtr->Msg.Msg, &CommandBytes);
    EntryIndex = SC_EntryOffsetAdvance(EntryIndex, CommandBytes + SC_ATS_HEADER_SIZE);
  }

  /* rebuild time sorted list of commands */
  SC_BuildTimeIndexTable(AtsIndex);

  /* did we just append to an ats that was executing? */
  if (SC_OperData.AtsCtrlBlckAddr->AtpState == SC_Status_EXECUTING &&
      SC_IDNUM_EQUAL(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum, SC_AtsIndexToNum(AtsIndex))) {
    /*
    ** re-start the ats -- this will go thru the process of skipping
    **  past due entries (all of the old entries that had already
    **  been executed and all of the new entries with an old time)
    */
    if (SC_BeginAts(AtsIndex, 0)) {
      SC_OperData.AtsCtrlBlckAddr->AtpState = SC_Status_EXECUTING;
    }
  }

  /* notify cFE that we have modified the ats table */
  CFE_TBL_Modified(SC_OperData.AtsTblHandle[SC_IDX_AS_UINT(AtsIndex)]);
}

/*******************************************************************************/
// Verify a whole ATS (or append) buffer, entry by entry.
//
// **THE LOOP TESTS THE RETURN THREE WAYS** -- see the file header on SC_VerifyAtsEntry's tri-state
// int32. And note the duplicate-test array is cleared HERE, once per table, so the duplicate check
// is per-load rather than global.
I32 SC_VerifyAtsTable(U32 *Buffer32, I32 BufferWords)
{
  I32 Result = CFE_SUCCESS;
  I32 BufferIndex = 0;
  I32 CommandCount = 0;
  I32 i;

  Bool StillProcessing = TRUE;

  /* Initialize all command numbers as unused */
  for (i = 0; i < SC_MAX_ATS_CMDS; i++) {
    SC_SetAtsDupTest(SC_CommandIndexToNum(SC_COMMAND_IDX_C(i)), SC_DUP_TEST_UNUSED);
  }

  while (StillProcessing) {
    /* Verify the ATS table entry at the current buffer index */
    Result = SC_VerifyAtsEntry(Buffer32, BufferIndex, BufferWords);

    if (Result == SC_ERROR) {
      /* Entry at current buffer index is invalid */
      StillProcessing = FALSE;
    } else if (Result == CFE_SUCCESS) {
      /* No more entries -- end of buffer or cmd num = 0 */
      StillProcessing = FALSE;
    } else {
      /* Result is size (in words) of this entry */
      BufferIndex += Result;
      CommandCount++;
    }
  }

  if (Result == CFE_SUCCESS) {
    if (CommandCount == 0) {
      /* Table must contain at least one valid entry */
      Result = SC_ERROR;

      CFE_EVS_SendEvent(SC_VERIFY_ATS_MPT_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Verify ATS Table error: table is empty");
    } else {
      // `* 4` HERE, against SC_UpdateAppend's `* 2` for the same kind of quantity -- upstream #25.
      CFE_EVS_SendEvent(SC_VERIFY_ATS_EID, CFE_EVS_EventType_INFORMATION,
                        "Verify ATS Table: command count = %d, byte count = %d", CommandCount,
                        BufferIndex * SC_BYTES_IN_WORD);
    }
  }

  return Result;
}

/*******************************************************************************/
// Verify one ATS entry. **Returns 0 for "stop", -1 for "bad", or the entry's word size** -- see the
// file header.
//
// NASA'S TWO COMMENTS IN HERE ARE WORTH KEEPING FOR WHAT THEY ADMIT. The first says the `>=` in the
// bounds test is unreachable given the caller's logic and is there "to protect against our own
// potential coding errors". The second explains that reading the command number before the bounds
// are fully known is safe because the command number is the FIRST element of the structure -- which
// is true, and is load-bearing, and is the kind of thing that stops being true if someone reorders
// SC_AtsEntryHeader_t.
I32 SC_VerifyAtsEntry(U32 *Buffer32, I32 EntryIndex, I32 BufferWords)
{
  SC_AtsEntry_t *EntryPtr;
  I64 CommandBytes = 0;
  I32 CommandWords;
  I32 Result = CFE_SUCCESS;

  EntryPtr = &Buffer32[EntryIndex](SC_AtsEntry_t *);

  /*
  ** Verify the ATS table entry located at the indicated buffer offset
  */
  if (EntryIndex >= BufferWords) {
    /*
    ** The process logic will prevent the index from ever exceeding
    **  the size of the buffer due to bad table data content.  Still,
    **  we must include the "greater than" in the test above to
    **  protect against our own potential coding errors.
    */

    /* All done -- end of ATS buffer */
    Result = CFE_SUCCESS;
  } else if (SC_IDNUM_IS_NULL(EntryPtr->Header.CmdNumber)) {
    /*
    ** If there is at least one word remaining in the buffer then it
    **  is OK to test the command number without fear of accessing
    **  past the end of valid data because the command number is the
    **  first element in an ATS entry structure.
    */

    /* All done -- end of in-use portion of buffer */
    Result = CFE_SUCCESS;
  } else if (!SC_AtsCommandNumIsValid(EntryPtr->Header.CmdNumber)) {
    /* Error -- invalid command number */
    Result = SC_ERROR;

    CFE_EVS_SendEvent(SC_VERIFY_ATS_NUM_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Verify ATS Table error: invalid command number: buf index = %d, cmd num = %u",
                      EntryIndex, SC_IDNUM_AS_UINT(EntryPtr->Header.CmdNumber));
  } else if (EntryIndex + SC_ATS_HDR_WORDS > BufferWords) {
    /* Error -- not enough room for smallest possible ATS entry */
    Result = SC_ERROR;

    CFE_EVS_SendEvent(SC_VERIFY_ATS_END_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Verify ATS Table error: buffer full: buf index = %d, cmd num = %u, buf words = %d",
                      EntryIndex, SC_IDNUM_AS_UINT(EntryPtr->Header.CmdNumber), BufferWords);
  } else {
    /* Start with the byte length of the command packet */
    CFE_MSG_GetSize(&EntryPtr->Msg.Msg, &CommandBytes);

    /* Convert packet byte length to word length (round up odd bytes) */
    CommandWords = (CommandBytes + SC_ROUND_UP_BYTES) / SC_BYTES_IN_WORD;

    if (CommandBytes < SC_PACKET_MIN_SIZE || CommandBytes > SC_PACKET_MAX_SIZE) {
      /* Error -- invalid command packet byte length */
      Result = SC_ERROR;

      CFE_EVS_SendEvent(SC_VERIFY_ATS_PKT_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Verify ATS Table error: invalid length: buf index = %d, cmd num = %u, pkt len = %d",
                        EntryIndex, SC_IDNUM_AS_UINT(EntryPtr->Header.CmdNumber), CommandBytes);
    } else if (EntryIndex + SC_ATS_HDR_NOPKT_WORDS + CommandWords > BufferWords) {
      /* Error -- packet must fit within buffer */
      Result = SC_ERROR;

      CFE_EVS_SendEvent(SC_VERIFY_ATS_BUF_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Verify ATS Table error: buffer overflow: buf index = %d, cmd num = %u, pkt len = %d",
                        EntryIndex, SC_IDNUM_AS_UINT(EntryPtr->Header.CmdNumber), CommandBytes);
    } else if (SC_GetAtsDupTest(EntryPtr->Header.CmdNumber) != SC_DUP_TEST_UNUSED) {
      /* Entry with duplicate command number is invalid */
      Result = SC_ERROR;

      CFE_EVS_SendEvent(SC_VERIFY_ATS_DUP_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Verify ATS Table error: dup cmd number: buf index = %d, cmd num = %u, dup index = %d",
                        EntryIndex, SC_IDNUM_AS_UINT(EntryPtr->Header.CmdNumber),
                        SC_GetAtsDupTest(EntryPtr->Header.CmdNumber));
    } else {
      /* Compute length (in words) for this ATS table entry */
      Result = SC_ATS_HDR_NOPKT_WORDS + CommandWords;

      /* Mark this ATS command ID as in use at this table index */
      SC_SetAtsDupTest(EntryPtr->Header.CmdNumber, EntryIndex);
    }
  }

  return Result;
}

#endif
