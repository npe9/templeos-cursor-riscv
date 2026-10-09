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
// HOUSEKEEPING'S COMBINING ENGINE -- the 1:1 translation of NASA's fsw/src/hk_utils.c, 762 lines
// and ten functions. This is all of HK that is not startup or dispatch.
//
// ### WHAT HK ACTUALLY DOES, IN ONE SENTENCE
//
// It copies bytes. A copy table entry says "take NumBytes from offset InputOffset of the packet
// whose id is InputMid, and put them at OutputOffset in the packet whose id is OutputMid", and
// HK_ProcessIncomingHkData is a `memcpy` inside two bounds checks. Everything else in this file
// exists to make that one memcpy safe: validate the table, build the output buffers, subscribe to
// the inputs, tear it all down when a new table arrives, and notice when an output packet is
// missing a contribution.
//
// ### THE ONE REAL BOUNDS CHECK IS ON THE **INPUT** AND IT IS SIGNED
//
// HK_ProcessIncomingHkData computes
//
//     LastByteAccessed = CpyTblEntry->InputOffset + CpyTblEntry->NumBytes;
//     if (MessageLength >= LastByteAccessed)
//
// where LastByteAccessed is an `int32` and MessageLength is a `size_t`. NASA's own declaration,
// kept: the comparison is between a signed 32-bit value and an unsigned 64-bit one, so C
// converts the int32 to size_t and a negative LastByteAccessed would become enormous and FAIL the
// test -- which is the safe direction. Both operands here come from uint16 fields so the sum
// cannot exceed 131,070 and cannot be negative; the signedness is harmless and is preserved
// because changing it is a judgement about overflow this port has no business making. See
// docs/CFS_PORT.md on unsigned-sentinel parameters for the shape where it is NOT harmless.
//
// **AND THE OUTPUT SIDE HAS NO RUNTIME CHECK AT ALL.** DestPtr is the pool buffer plus
// OutputOffset, and nothing at copy time verifies that OutputOffset + NumBytes fits in the buffer
// that was allocated. The guarantee comes from two places working together, both at table-load
// time: HK_ValidateHkCopyTable refuses any entry whose output tail exceeds
// HK_MAX_COMBINED_PACKET_SIZE, and HK_ProcessNewCopyTable sizes each output buffer to the
// FURTHEST byte any entry writes into it. So the copy is safe because the buffer was made big
// enough, not because the copy looks. That is worth stating because it means a copy table that
// reached HK_ProcessNewCopyTable WITHOUT passing the validator -- which cFE allows, since the
// validator is a registration callback that a direct HK_ProcessNewCopyTable call bypasses -- can
// write past the end of a pool buffer.
//
// ### A NEW COPY TABLE IS A THREE-PASS ALGORITHM OVER 128 ENTRIES, TWICE NESTED
//
// HK_ProcessNewCopyTable and HK_TearDownOldCopyTable are both O(n^2) walks, and the nesting is
// not laziness: output packets are SHARED. Several copy entries can name the same OutputMid, and
// they must all end up pointing at ONE buffer, sized to the furthest byte any of them writes. So
// the outer loop finds an entry that needs a buffer, an inner loop measures the packet across
// every entry that shares its id, and a third loop hands the one buffer to all of them. The
// subscription half works the same way: subscribe once per distinct InputMid, then mark every
// entry that shares it.
//
// THE SENTINEL FOR "ALREADY DONE" IS THE FIELD ITSELF. `OutputPktAddr == NULL` means "this entry
// still needs a buffer" and InputMidSubscribed means "this id is already on the pipe" -- so the
// algorithm is idempotent across the three passes without a separate visited set.
//
// ### AND THE TEAR-DOWN MATCHES POINTERS, NOT JUST IDS
//
// HK_TearDownOldCopyTable frees a buffer and then clears OutputPktAddr on every entry that has
// BOTH the same OutputMid AND the same pointer:
//
//     if (CFE_SB_MsgId_Equal(InnerDefEntry->OutputMid, MidOfThisPacket) && (InnerPktAddr == SavedPktAddr))
//
// The pointer test is the load-bearing half. Two entries can share an OutputMid and point at
// DIFFERENT buffers if a previous table load partially failed -- the pool ran out between them --
// and clearing both on the first free would leave the second buffer leaked and its entry
// dangling. NASA checks both; so does this.
#ifndef HK_UTILS_HC
#define HK_UTILS_HC

#include "hk_global.HC"
#include "hk_eventids.HC"

// --- hk_utils.h's prototypes, and hk_app.h's one that this file calls ------------------------
U0 HK_ProcessIncomingHkData(CFE_SB_Buffer *BufPtr);
I32 HK_ValidateHkCopyTable(U8 *TblPtr);
I32 HK_ProcessNewCopyTable(HK_CopyTableEntry_t *CpyTblPtr, HK_RuntimeTableEntry_t *RtTblPtr);
I32 HK_TearDownOldCopyTable(HK_CopyTableEntry_t *CpyTblPtr, HK_RuntimeTableEntry_t *RtTblPtr);
U0 HK_SendCombinedHkPacket(CFE_SB_MsgId WhichMidToSend);
I32 HK_CheckStatusOfTables();
I32 HK_CheckStatusOfCopyTable();
I32 HK_CheckStatusOfDumpTable();
I32 HK_CheckForMissingData(CFE_SB_MsgId OutPktToCheck, CFE_SB_MsgId *MissingInputMid);
U0 HK_SetFlagsToNotPresent(CFE_SB_MsgId OutPkt);

/*******************************************************************************/
// HK process incoming housekeeping data.
//
// ONE EVENT PER INPUT PACKET, NOT PER BAD ENTRY. MessageErrors counts every entry whose copy
// would have run off the end, and the event is sent once with the COUNT -- NASA's comment is
// "Send, at most, one error event per input packet". A packet matching twenty bad entries
// produces one event saying twenty, which is the only shape that does not flood the event log
// from a single misconfigured table.
U0 HK_ProcessIncomingHkData(CFE_SB_Buffer *BufPtr)
{
  HK_CopyTableEntry_t *StartOfCopyTable = HK_AppData.CopyTablePtr;
  HK_CopyTableEntry_t *CpyTblEntry = NULL;
  HK_RuntimeTableEntry_t *StartOfRtTable = HK_AppData.RuntimeTablePtr;
  HK_RuntimeTableEntry_t *RtTblEntry = NULL;
  U16 Loop = 0;
  CFE_SB_MsgId MessageID;
  U8 *DestPtr = NULL;
  U8 *SrcPtr = NULL;
  I64 MessageLength = 0;
  I32 MessageErrors = 0;
  I32 LastByteAccessed;

  MessageID = CFE_SB_InvalidMsgId();

  CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);

  /* Spin thru the entire table looking for matches */
  for (Loop = 0; Loop < HK_COPY_TABLE_ENTRIES; Loop++) {
    CpyTblEntry = &StartOfCopyTable[Loop];
    RtTblEntry = &StartOfRtTable[Loop];

    /* Does the inputMID for this table entry match what we're looking for */
    if (CFE_SB_MsgId_Equal(MessageID, CpyTblEntry->InputMid)) {
      /* Ensure that we don't reference past the end of the input packet */
      CFE_MSG_GetSize(&BufPtr->Msg, &MessageLength);
      LastByteAccessed = CpyTblEntry->InputOffset + CpyTblEntry->NumBytes;
      if (MessageLength >= LastByteAccessed) {
        /* We have a match.  Build the Source and Destination addresses
           and move the data */
        // CFE_ES_MEMADDRESS_TO_PTR is a cast in NASA's C; the field is already the address.
        DestPtr = RtTblEntry->OutputPktAddr(U8 *);
        DestPtr += CpyTblEntry->OutputOffset;
        SrcPtr = BufPtr(U8 *) + CpyTblEntry->InputOffset;

        MemCpy(DestPtr, SrcPtr, CpyTblEntry->NumBytes);

        /* Set the data present field to indicate the data is there */
        RtTblEntry->DataPresent = HK_DATA_PRESENT;
      } else {
        /* Error: copy data is past the end of the input packet */
        MessageErrors++;
      }
    }
  }

  /* Send, at most, one error event per input packet */
  if (MessageErrors != 0) {
    CFE_EVS_SendEvent(HK_ACCESSING_PAST_PACKET_END_EID, CFE_EVS_EventType_ERROR,
                      "HK table definition exceeds packet length. MID:0x%08lX, Length:%d, Count:%d",
                      CFE_SB_MsgIdToValue(MessageID), MessageLength, MessageErrors);
  }
}

/*******************************************************************************/
// HK validate the copy table contents, the callback cFE Table Services calls before a load.
//
// ### AN UNUSED ENTRY IS ONE WITH **NEITHER** MESSAGE ID SET, AND THAT IS THE WHOLE STRUCTURE
//
// The outer test is
//
//     if (CFE_SB_IsValidMsgId(EntryPtr->OutputMid) || CFE_SB_IsValidMsgId(EntryPtr->InputMid))
//
// -- an OR, so an entry is examined if EITHER id is set, and NASA's comment says why: "If the
// entry is not used, then NEITHER of the MID values should be set". A half-filled entry is
// therefore an ERROR rather than an empty slot, which is the right choice: a ground operator who
// typed an input id and forgot the output one gets a refusal instead of a silently ignored row.
//
// ### IT STOPS AT THE FIRST BAD ENTRY, AND THE EVENT CARRIES A STRING IT BUILT ITSELF
//
// Every arm fills IssueStringBuf with snprintf and breaks. So the event names ONE problem and the
// index it was at -- there is no count, unlike HK_ProcessIncomingHkData's. The two-step
// (build a string, then embed it with %s) is unusual in cFS and it is what lets four different
// failures share one event id.
//
// AND THE EVENT TEXT ENDS WITH A `\n` INSIDE THE FORMAT -- "HK Validate: %s at entry index %d\n".
// Every other event in this port ends without one, because EVS adds the line break. Upstream's,
// kept verbatim, and it shows up in the transcript as a blank line after the message.
I32 HK_ValidateHkCopyTable(U8 *TblPtr)
{
  I32 HKStatus;
  I32 i;
  HK_CopyTableEntry_t *EntryPtr;
  I64 EntryTail;
  U8 IssueStringBuf[CFE_MISSION_EVS_MAX_MESSAGE_LENGTH];

  IssueStringBuf[0] = 0;
  HKStatus = HK_SUCCESS;
  EntryPtr = TblPtr(HK_CopyTableEntry_t *);

  /* Loop thru the table and add up all the bytes copied for testing overflow scenario */
  for (i = 0; i < HK_COPY_TABLE_ENTRIES; i++) {
    /* If the entry is not used, then NEITHER of the MID values should be set */
    if (CFE_SB_IsValidMsgId(EntryPtr->OutputMid) || CFE_SB_IsValidMsgId(EntryPtr->InputMid)) {
      /* If it has an input MID but not a valid output, this is an error */
      if (!CFE_SB_IsValidMsgId(EntryPtr->OutputMid)) {
        StrPrintN(IssueStringBuf, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Invalid Output MID: 0x%lx",
                  CFE_SB_MsgIdToValue(EntryPtr->OutputMid));
        HKStatus = HK_ERROR;
        break;
      }

      /* If it has an output MID but not a valid input, this is an error */
      if (!CFE_SB_IsValidMsgId(EntryPtr->InputMid)) {
        StrPrintN(IssueStringBuf, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Invalid Input MID: 0x%lx",
                  CFE_SB_MsgIdToValue(EntryPtr->InputMid));
        HKStatus = HK_ERROR;
        break;
      }

      /* check input position */
      EntryTail = EntryPtr->InputOffset;
      EntryTail += EntryPtr->NumBytes;

      /* Check if the accumulated bytes exceed the allowed packet size, indicating an overflow */
      if (EntryTail > HK_MAX_COMBINED_PACKET_SIZE) {
        StrPrintN(IssueStringBuf, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH,
                  "Invalid input offset+size: %lu > %lu, mid 0x%lx", EntryTail,
                  HK_MAX_COMBINED_PACKET_SIZE, CFE_SB_MsgIdToValue(EntryPtr->InputMid));
        HKStatus = HK_ERROR;
        break;
      }

      /* check output position */
      EntryTail = EntryPtr->OutputOffset;
      EntryTail += EntryPtr->NumBytes;

      /* Check if the accumulated bytes exceed the allowed packet size, indicating an overflow */
      if (EntryTail > HK_MAX_COMBINED_PACKET_SIZE) {
        StrPrintN(IssueStringBuf, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH,
                  "Invalid output offset+size: %lu > %lu, mid 0x%lx", EntryTail,
                  HK_MAX_COMBINED_PACKET_SIZE, CFE_SB_MsgIdToValue(EntryPtr->OutputMid));
        HKStatus = HK_ERROR;
        break;
      }
    }

    ++EntryPtr;
  }

  /* Report any error as an event before leaving (IssueStringBuf should be filled with something). */
  if (HKStatus != HK_SUCCESS) {
    CFE_EVS_SendEvent(HK_NEWCPYTBL_HK_FAILED_EID, CFE_EVS_EventType_ERROR,
                      "HK Validate: %s at entry index %d\n", IssueStringBuf, i);
  }

  return HKStatus;
}

/*******************************************************************************/
// HK process new copy table: build the output packets and subscribe to the inputs.
//
// THE RETURN VALUE ONLY EVER REPORTS A NULL ARGUMENT. Every other failure -- a pool that ran out,
// a subscription cFE refused -- sends an event and CARRIES ON, so this returns CFE_SUCCESS after
// a table load that half worked. HK_CheckStatusOfCopyTable's comment says so explicitly: "If
// status was not success, then the copy table function received a NULL pointer argument". The
// caller cannot distinguish a clean load from a partial one, and the counters it would need are
// not kept; the events are the only record.
//
// AND THE THREE PASSES ARE DESCRIBED IN THE FILE HEADER. The nesting is because output packets
// are SHARED between entries that name the same OutputMid.
I32 HK_ProcessNewCopyTable(HK_CopyTableEntry_t *CpyTblPtr, HK_RuntimeTableEntry_t *RtTblPtr)
{
  HK_CopyTableEntry_t *StartOfCopyTable = NULL;
  HK_CopyTableEntry_t *OuterCpyEntry = NULL;
  HK_CopyTableEntry_t *InnerDefEntry = NULL;
  HK_RuntimeTableEntry_t *StartOfRtTable = NULL;
  HK_RuntimeTableEntry_t *OuterRtEntry = NULL;
  HK_RuntimeTableEntry_t *InnerRtEntry = NULL;
  I32 Loop1 = 0;
  I32 Loop2;
  CFE_SB_MsgId MidOfThisPacket;
  I32 SizeOfThisPacket;
  I32 FurthestByteFromThisEntry;
  CFE_SB_Buffer *NewPacketAddr;
  I32 Result;

  /* Ensure that the input arguments are valid */
  if (CpyTblPtr == NULL || RtTblPtr == NULL) {
    CFE_EVS_SendEvent(HK_NULL_POINTER_NEWCPY_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Null pointer detected in new copy tbl processing: CpyTbl = %p, RtTbl = %p",
                      CpyTblPtr, RtTblPtr);
    return HK_NULL_POINTER_DETECTED;
  }

  StartOfCopyTable = CpyTblPtr;
  StartOfRtTable = RtTblPtr;

  /* Loop thru the RunTime table initializing the fields */
  for (Loop1 = 0; Loop1 < HK_COPY_TABLE_ENTRIES; Loop1++) {
    OuterRtEntry = &StartOfRtTable[Loop1];

    // CFE_ES_MEMADDRESS_C is a cast in NASA's C; the field is already the address type.
    OuterRtEntry->OutputPktAddr = 0;
    OuterRtEntry->InputMidSubscribed = HK_INPUTMID_NOT_SUBSCRIBED;
    OuterRtEntry->DataPresent = HK_DATA_NOT_PRESENT;
  }

  /* Loop thru the table looking for all of the SB packets that need to be built */
  for (Loop1 = 0; Loop1 < HK_COPY_TABLE_ENTRIES; Loop1++) {
    OuterCpyEntry = &StartOfCopyTable[Loop1];
    OuterRtEntry = &StartOfRtTable[Loop1];

    /* If the both MIDs exists but the Packet Address has yet to be assigned,
       we need to build an SB packet, so compute the size */
    if (CFE_SB_IsValidMsgId(OuterCpyEntry->OutputMid) && CFE_SB_IsValidMsgId(OuterCpyEntry->InputMid)
        && OuterRtEntry->OutputPktAddr == 0) {
      /* We have a table entry that needs a SB message to be built */
      MidOfThisPacket = OuterCpyEntry->OutputMid;
      SizeOfThisPacket = 0;

      /* Spin thru entire table looking for duplicate OutputMid's.  This will let
         us find the byte offset furthest from the beginning of the packet */
      for (Loop2 = 0; Loop2 < HK_COPY_TABLE_ENTRIES; Loop2++) {
        InnerDefEntry = &StartOfCopyTable[Loop2];

        /* If this entry's MID matches the one we're looking for */
        if (CFE_SB_MsgId_Equal(InnerDefEntry->OutputMid, MidOfThisPacket)) {
          /* The byte furthest away from the section described by this entry */
          FurthestByteFromThisEntry = InnerDefEntry->OutputOffset + InnerDefEntry->NumBytes;

          /* Save the byte offset of the byte furthest from the packet start */
          if (FurthestByteFromThisEntry > SizeOfThisPacket) {
            SizeOfThisPacket = FurthestByteFromThisEntry;
          }
        }
      }

      /* Build the packet with the size computed above */
      NewPacketAddr = NULL;
      if (SizeOfThisPacket > 0) {
        Result = CFE_ES_GetPoolBuf((U8 **)&NewPacketAddr, HK_AppData.MemPoolHandle,
                                   SizeOfThisPacket);

        if (Result >= CFE_SUCCESS) {
          /* Spin thru entire table (again) looking for duplicate OutputMid's.
              This will let us assign the packet created above to all
              of the table entries that need to use it */
          for (Loop2 = 0; Loop2 < HK_COPY_TABLE_ENTRIES; Loop2++) {
            InnerDefEntry = &StartOfCopyTable[Loop2];
            InnerRtEntry = &StartOfRtTable[Loop2];

            /* If this entry's MID matches the one we're looking for */
            if (CFE_SB_MsgId_Equal(InnerDefEntry->OutputMid, MidOfThisPacket)) {
              InnerRtEntry->OutputPktAddr = NewPacketAddr(U64);
            }
          }

          /* Init the SB Packet only once regardless of how many times its in the table */
          CFE_MSG_Init(&NewPacketAddr->Msg, MidOfThisPacket, SizeOfThisPacket);
        } else {
          CFE_EVS_SendEvent(HK_MEM_POOL_MALLOC_FAILED_EID, CFE_EVS_EventType_ERROR,
                            "HK Processing New Table: ES_GetPoolBuf for size %d returned 0x%04X",
                            SizeOfThisPacket, Result);
        }
      }
    }

    /* If HK needs to subscribe to this Input packet... */
    if (OuterRtEntry->InputMidSubscribed == HK_INPUTMID_NOT_SUBSCRIBED
        && CFE_SB_IsValidMsgId(OuterCpyEntry->InputMid)) {
      Result = CFE_SB_Subscribe(OuterCpyEntry->InputMid, HK_AppData.CmdPipe);

      if (Result == CFE_SUCCESS) {
        /* Spin thru entire table (again) looking for duplicate InputMid's.
           This will let us mark each duplicate as already having been subscribed */
        for (Loop2 = 0; Loop2 < HK_COPY_TABLE_ENTRIES; Loop2++) {
          InnerDefEntry = &StartOfCopyTable[Loop2];
          InnerRtEntry = &StartOfRtTable[Loop2];

          /* If this entry's MID matches the one we're looking for */
          if (CFE_SB_MsgId_Equal(OuterCpyEntry->InputMid, InnerDefEntry->InputMid)) {
            InnerRtEntry->InputMidSubscribed = HK_INPUTMID_SUBSCRIBED;
          }
        }
      } else {
        CFE_EVS_SendEvent(HK_CANT_SUBSCRIBE_TO_SB_PKT_EID, CFE_EVS_EventType_ERROR,
                          "HK Processing New Table:SB_Subscribe for Mid 0x%08lX returned 0x%04X",
                          CFE_SB_MsgIdToValue(OuterCpyEntry->InputMid), Result);
      }
    }
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// HK tear down old copy table: free the output packets and unsubscribe from the inputs.
//
// THE POINTER COMPARISON IN THE INNER LOOP IS LOAD-BEARING -- see the file header. Two entries can
// share an OutputMid and point at DIFFERENT buffers if a previous load ran the pool out between
// them, and clearing both on the first free would leak the second and dangle its entry.
//
// AND IT DOES NOT CHECK WHETHER THE UNSUBSCRIBE WORKED. CFE_SB_Unsubscribe's return is discarded
// -- the only call in HK that ignores a cFE status -- and NASA's comment explains the reasoning
// for the loop that follows it: "We don't have to worry about leaving any Mid's subscribed since
// the entire table is getting clobbered." A failed unsubscribe therefore leaves HK receiving a
// packet no table entry describes, which HK_ProcessIncomingHkData handles as a no-match walk.
I32 HK_TearDownOldCopyTable(HK_CopyTableEntry_t *CpyTblPtr, HK_RuntimeTableEntry_t *RtTblPtr)
{
  HK_CopyTableEntry_t *StartOfCopyTable = NULL;
  HK_CopyTableEntry_t *OuterCpyEntry = NULL;
  HK_CopyTableEntry_t *InnerDefEntry = NULL;
  HK_RuntimeTableEntry_t *StartOfRtTable = NULL;
  HK_RuntimeTableEntry_t *OuterRtEntry = NULL;
  HK_RuntimeTableEntry_t *InnerRtEntry = NULL;
  I32 Loop1 = 0;
  I32 Loop2;
  CFE_SB_MsgId MidOfThisPacket;
  U8 *OutputPktAddr = NULL;
  U8 *InnerPktAddr = NULL;
  U8 *SavedPktAddr = NULL;
  I32 Result;

  /* Ensure that the input arguments are valid */
  if (CpyTblPtr == NULL || RtTblPtr == NULL) {
    CFE_EVS_SendEvent(HK_NULL_POINTER_TEARCPY_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Null pointer detected in copy tbl tear down: CpyTbl = %p, RtTbl = %p",
                      CpyTblPtr, RtTblPtr);
    return HK_NULL_POINTER_DETECTED;
  }

  StartOfCopyTable = CpyTblPtr;
  StartOfRtTable = RtTblPtr;

  /* Loop thru the table looking for all of the SB packets that need to be freed */
  for (Loop1 = 0; Loop1 < HK_COPY_TABLE_ENTRIES; Loop1++) {
    OuterCpyEntry = &StartOfCopyTable[Loop1];
    OuterRtEntry = &StartOfRtTable[Loop1];

    /* If a Packet Address has been assigned, it needs to get deleted */
    OutputPktAddr = OuterRtEntry->OutputPktAddr(U8 *);
    if (OutputPktAddr != NULL) {
      MidOfThisPacket = OuterCpyEntry->OutputMid;

      SavedPktAddr = OutputPktAddr;
      Result = CFE_ES_PutPoolBuf(HK_AppData.MemPoolHandle, OutputPktAddr);
      if (Result >= CFE_SUCCESS) {
        /* Spin thru the entire table looking for entries that used the same SB packets */
        for (Loop2 = 0; Loop2 < HK_COPY_TABLE_ENTRIES; Loop2++) {
          InnerDefEntry = &StartOfCopyTable[Loop2];
          InnerRtEntry = &StartOfRtTable[Loop2];

          InnerPktAddr = InnerRtEntry->OutputPktAddr(U8 *);
          if (CFE_SB_MsgId_Equal(InnerDefEntry->OutputMid, MidOfThisPacket)
              && InnerPktAddr == SavedPktAddr) {
            /* NULL out the table entry whose packet was freed above */
            InnerRtEntry->OutputPktAddr = 0;
          }
        }
      } else {
        CFE_EVS_SendEvent(HK_MEM_POOL_FREE_FAILED_EID, CFE_EVS_EventType_ERROR,
                          "HK TearDown: ES_putPoolBuf Err pkt:0x%08lX ret 0x%04X, hdl 0x%08lx",
                          SavedPktAddr, Result, HK_AppData.MemPoolHandle);
      }
    }

    /* If the InputMid for this Table Entry has been subscribed, it needs to
       get Unsubscribed as do any other identical InputMids throughout the table.
       We don't have to worry about leaving any Mid's subscribed since the entire table
       is getting clobbered. */
    if (OuterRtEntry->InputMidSubscribed == HK_INPUTMID_SUBSCRIBED) {
      CFE_SB_Unsubscribe(OuterCpyEntry->InputMid, HK_AppData.CmdPipe);

      /* Spin thru the entire table looking for entries that used the same SB packets */
      for (Loop2 = 0; Loop2 < HK_COPY_TABLE_ENTRIES; Loop2++) {
        InnerDefEntry = &StartOfCopyTable[Loop2];
        InnerRtEntry = &StartOfRtTable[Loop2];

        if (CFE_SB_MsgId_Equal(InnerDefEntry->InputMid, OuterCpyEntry->InputMid)) {
          InnerRtEntry->InputMidSubscribed = HK_INPUTMID_NOT_SUBSCRIBED;
        }
      }
    }
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// HK send combined output message.
//
// ### THE `#if HK_DISCARD_INCOMPLETE_COMBO == 1` BLOCK IS OMITTED, AND IT GUARDED A BARE `else`
//
// NASA writes
//
//     if (HK_CheckForMissingData(...) == HK_MISSING_DATA_DETECTED) { ...DEBUG event... }
//     #if HK_DISCARD_INCOMPLETE_COMBO == 1
//                 else
//     #endif
//                 { ...send the packet... }
//
// The directive wraps NO STATEMENT -- just the keyword `else`. With HK_DISCARD_INCOMPLETE_COMBO at
// 0, which is NASA's default (hk_cfg.HC), the `else` is excluded and the send block follows the
// `if` unconditionally. **SO A PACKET WITH MISSING DATA IS SENT ANYWAY**, after its event, and
// MissingDataCtr is the only record that it was incomplete.
//
// THIS IS THE ONE PLACE IN THE PORT WHERE HolyC LIMIT #19 WOULD HAVE INVERTED REAL BEHAVIOUR.
// `#if <expr>` is unconditionally true in this compiler, so transcribing the directive verbatim
// would have INCLUDED the `else` and made HK discard incomplete packets -- the opposite of the
// configured behaviour, with no diagnostic. The condition is decidable at translation time, so it
// is resolved here, which is docs/CFS_PORT.md's rule.
//
// ### AND IT SENDS AT MOST ONE PACKET, THEN CLEARS THE FLAGS FOR THAT PACKET ONLY
//
// The loop runs `while (Loop < HK_COPY_TABLE_ENTRIES && PacketFound == false)`, so the first
// runtime entry whose output id matches wins and the walk stops. HK_SetFlagsToNotPresent then
// clears DataPresent on every entry feeding THAT output id -- not on the whole table -- which is
// what lets two combined packets be requested at different rates without one resetting the
// other's contributions.
U0 HK_SendCombinedHkPacket(CFE_SB_MsgId WhichMidToSend)
{
  Bool PacketFound = FALSE;
  HK_RuntimeTableEntry_t *StartOfRtTable = HK_AppData.RuntimeTablePtr;
  HK_RuntimeTableEntry_t *RtTblEntry = NULL;
  I32 Loop = 0;
  CFE_SB_MsgId ThisEntrysOutMid;
  CFE_SB_MsgId InputMidMissing;
  CFE_SB_Buffer *OutBuffer = NULL;

  ThisEntrysOutMid = CFE_SB_InvalidMsgId();
  InputMidMissing = CFE_SB_InvalidMsgId();

  /* Look thru each item in this Table, but only send this packet once, at most */
  for (Loop = 0; Loop < HK_COPY_TABLE_ENTRIES && PacketFound == FALSE; Loop++) {
    RtTblEntry = &StartOfRtTable[Loop];

    /* Empty table entries are defined by NULL's in this field */
    OutBuffer = RtTblEntry->OutputPktAddr(CFE_SB_Buffer *);
    if (OutBuffer != NULL) {
      CFE_MSG_GetMsgId(&OutBuffer->Msg, &ThisEntrysOutMid);

      if (CFE_SB_MsgId_Equal(ThisEntrysOutMid, WhichMidToSend)) {
        if (HK_CheckForMissingData(ThisEntrysOutMid, &InputMidMissing) == HK_MISSING_DATA_DETECTED) {
          HK_AppData.MissingDataCtr++;

          CFE_EVS_SendEvent(HK_OUTPKT_MISSING_DATA_EID, CFE_EVS_EventType_DEBUG,
                            "Combined Packet 0x%08lX missing data from Input Pkt 0x%08lX",
                            CFE_SB_MsgIdToValue(ThisEntrysOutMid),
                            CFE_SB_MsgIdToValue(InputMidMissing));
        }
        // NASA'S `#if HK_DISCARD_INCOMPLETE_COMBO == 1 / else / #endif` IS OMITTED HERE. The
        // flag is 0, so the `else` is excluded and this block follows the `if` unconditionally:
        // an incomplete packet is still sent. See the block comment above for why resolving the
        // directive rather than copying it is the only correct option in this compiler.
        {
          /* Send the combined housekeeping telemetry packet...        */
          CFE_SB_TimeStampMsg(&OutBuffer->Msg);
          CFE_SB_TransmitMsg(&OutBuffer->Msg, TRUE);

          HK_AppData.CombinedPacketsSent++;
        }

        HK_SetFlagsToNotPresent(ThisEntrysOutMid);

        PacketFound = TRUE;
      }
    }
  }

  if (PacketFound == FALSE) {
    CFE_EVS_SendEvent(HK_UNKNOWN_COMBINED_PACKET_EID, CFE_EVS_EventType_INFORMATION,
                      "Combined HK Packet 0x%08lX is not found in current HK Copy Table",
                      CFE_SB_MsgIdToValue(WhichMidToSend));
  }
}

/*******************************************************************************/
// Check the status of HK tables and perform any necessary action.
//
// THE DUMP TABLE IS ONLY CHECKED IF THE COPY TABLE WAS CLEAN -- NASA's comment: "Only check the
// Dump Table if there were no problems with the Copy Table". So a copy table in trouble masks a
// pending runtime dump, and the ground's dump request is silently deferred until the copy table
// settles.
I32 HK_CheckStatusOfTables()
{
  I32 HKStatus;

  HKStatus = HK_CheckStatusOfCopyTable();

  /* Only check the Dump Table if there were no problems with the Copy Table */
  if (HKStatus == HK_SUCCESS) {
    HKStatus = HK_CheckStatusOfDumpTable();
  }

  return HKStatus;
}

/*******************************************************************************/
// Check the status of HK's copy table and perform any necessary action.
//
// ### THE WHOLE TABLE-LOAD SEQUENCE IS HERE, AND IT RUNS EVERY HOUSEKEEPING CYCLE
//
// This is the one function in HK that a new ground upload actually flows through, and the order
// is forced by cFE: tear down what the old table built, RELEASE THE ADDRESS (NASA's comment --
// "release address must be called for update to take"), update, take the new address, then build
// what the new table describes. Six cFE calls, each with its own event id, five of them
// CFE_EVS_EventType_CRITICAL.
//
// **HKStatus STARTS AT HK_ERROR AND IS SET TO HK_SUCCESS ONLY ON PATHS THAT FINISHED.** NASA's
// comment at the declaration is "Assume failure". That matters because the caller treats
// not-success as a reason to set RunStatus to APP_ERROR and terminate -- so every unexpected cFE
// status in here STOPS HK, and the one that does not is a validation failure:
// CFE_TBL_INFO_VALIDATION_PENDING sets HK_SUCCESS whatever CFE_TBL_Validate answered, with the
// comment "This could just be a bad table, so no reason to abort the app".
//
// So a bad table from the ground is survivable and an unexpected table-manager status is not.
// That asymmetry is HK's design and it is the most consequential thing in the file.
I32 HK_CheckStatusOfCopyTable()
{
  I32 Status;
  I32 HKStatus = HK_ERROR; /* Assume failure */

  /* Determine if the copy table has a validation or update that needs to be performed */
  Status = CFE_TBL_GetStatus(HK_AppData.CopyTableHandle);

  if (Status == CFE_TBL_INFO_VALIDATION_PENDING) {
    /* Validate the specified Table */
    Status = CFE_TBL_Validate(HK_AppData.CopyTableHandle);

    if (Status != CFE_SUCCESS) {
      CFE_EVS_SendEvent(HK_UNEXPECTED_TBLVLD_RET_EID, CFE_EVS_EventType_ERROR,
                        "Unexpected CFE_TBL_Validate return (0x%08X) for Copy Table", Status);
    }
    HKStatus = HK_SUCCESS; /* This could just be a bad table, so no reason to abort the app */
  } else if (Status == CFE_TBL_INFO_UPDATE_PENDING) {
    /* Unsubscribe to input msgs and free out pkt buffers */
    /* If the copy table pointer is bad, that's okay here because it will be re-allocated later.
       If the runtime table pointer is bad, the process new copy table call later on will
       flag the error.  So we can ignore the return status at this point.
    */
    HK_TearDownOldCopyTable(HK_AppData.CopyTablePtr, HK_AppData.RuntimeTablePtr);

    /* release address must be called for update to take. */
    Status = CFE_TBL_ReleaseAddress(HK_AppData.CopyTableHandle);

    /* Releasing the address should only return CFE_SUCCESS at this point since we
       already had an update-pending response earlier */
    if (Status == CFE_SUCCESS) {
      /* Update the copy table */
      Status = CFE_TBL_Update(HK_AppData.CopyTableHandle);

      if (Status == CFE_SUCCESS) {
        /* Get address of the newly updated copy table. */
        Status = CFE_TBL_GetAddress(&HK_AppData.CopyTablePtr, HK_AppData.CopyTableHandle);

        /* Status should only be CFE_TBL_INFO_UPDATED because we updated it above */
        if (Status == CFE_TBL_INFO_UPDATED) {
          Status = HK_ProcessNewCopyTable(HK_AppData.CopyTablePtr, HK_AppData.RuntimeTablePtr);

          if (Status == CFE_SUCCESS) {
            HKStatus = HK_SUCCESS;
          } else {
            /* If status was not success, then the copy table function received a NULL pointer argument */
            CFE_EVS_SendEvent(HK_NEWCPYTBL_HK_FAILED_EID, CFE_EVS_EventType_CRITICAL,
                              "Process New Copy Table Failed, status = 0x%08X", Status);
          }
        } else {
          CFE_EVS_SendEvent(HK_UNEXPECTED_GETADDR_RET_EID, CFE_EVS_EventType_CRITICAL,
                            "Unexpected CFE_TBL_GetAddress return (0x%08X) for Copy Table", Status);
        }
      } else {
        CFE_EVS_SendEvent(HK_UNEXPECTED_TBLUPD_RET_EID, CFE_EVS_EventType_CRITICAL,
                          "Unexpected CFE_TBL_Update return (0x%08X) for Copy Table", Status);
      }
    } else {
      CFE_EVS_SendEvent(HK_UNEXPECTED_RELADDR_RET_EID, CFE_EVS_EventType_CRITICAL,
                        "Unexpected CFE_TBL_ReleaseAddress return (0x%08X) for Copy Table", Status);
    }
  } else if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_UNEXPECTED_GETSTAT_RET_EID, CFE_EVS_EventType_CRITICAL,
                      "Unexpected CFE_TBL_GetStatus return (0x%08X) for Copy Table", Status);
  } else {
    /* Only way to get here is if Status == CFE_SUCCESS */
    HKStatus = HK_SUCCESS;
  }

  return HKStatus;
}

/*******************************************************************************/
// Check the status of HK's dump-only runtime table and perform any necessary action.
//
// THE RUNTIME TABLE IS DUMP-ONLY, so the only pending state it can have is a dump -- and
// CFE_TBL_DumpToBuffer is what copies HK's live bookkeeping, pointers and all, into the buffer
// cFE will write out. See hk_tbl.HC on what that means for the differential.
I32 HK_CheckStatusOfDumpTable()
{
  I32 Status;
  I32 HKStatus = HK_ERROR; /* Assume failure */

  /* Determine if the runtime table has a dump pending */
  Status = CFE_TBL_GetStatus(HK_AppData.RuntimeTableHandle);

  if (Status == CFE_TBL_INFO_DUMP_PENDING) {
    /* Dump the specified Table, cfe tbl manager makes copy */
    Status = CFE_TBL_DumpToBuffer(HK_AppData.RuntimeTableHandle);

    if (Status != CFE_SUCCESS) {
      CFE_EVS_SendEvent(HK_UNEXPECTED_DUMPTOBUFFER_RET_EID, CFE_EVS_EventType_CRITICAL,
                        "Unexpected CFE_TBL_DumpToBuffer return (0x%08X) for Runtime Table",
                        Status);
    } else {
      HKStatus = HK_SUCCESS;
    }
  } else if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_UNEXPECTED_GETSTAT2_RET_EID, CFE_EVS_EventType_CRITICAL,
                      "Unexpected CFE_TBL_GetStatus return (0x%08X) for Runtime Table", Status);
  } else {
    /* Only way to get here is if Status == CFE_SUCCESS */
    HKStatus = HK_SUCCESS;
  }

  return HKStatus;
}

/*******************************************************************************/
// HK check for missing combined output message data.
//
// A `do ... while` RATHER THAN A `for`, AND IT THEREFORE ALWAYS EXAMINES ENTRY 0. The loop
// condition is tested at the bottom, so even a zero-length table would read StartOfCopyTable[0]
// -- harmless here because HK_COPY_TABLE_ENTRIES is a compile-time 128, but it is NASA's shape
// and is kept.
//
// IT REPORTS THE **FIRST** MISSING CONTRIBUTION AND STOPS. The `while` tests `Status ==
// HK_NO_MISSING_DATA`, so *MissingInputMid names one input id even when several are absent, and
// the caller's event says "missing data from Input Pkt 0x..." in the singular. A combined packet
// waiting on four subsystems reports whichever is lowest in the table.
I32 HK_CheckForMissingData(CFE_SB_MsgId OutPktToCheck, CFE_SB_MsgId *MissingInputMid)
{
  I32 Loop = 0;
  I32 Status = HK_NO_MISSING_DATA;
  HK_CopyTableEntry_t *StartOfCopyTable = HK_AppData.CopyTablePtr;
  HK_CopyTableEntry_t *CpyTblEntry = NULL;
  HK_RuntimeTableEntry_t *StartOfRtTable = HK_AppData.RuntimeTablePtr;
  HK_RuntimeTableEntry_t *RtTblEntry = NULL;

  /* Loop thru each item in the runtime table until end is reached or
   * data-not-present detected */
  do {
    CpyTblEntry = &StartOfCopyTable[Loop];
    RtTblEntry = &StartOfRtTable[Loop];

    /* Empty table entries are defined by NULL's in this field */
    if (RtTblEntry->OutputPktAddr != 0 && CFE_SB_MsgId_Equal(CpyTblEntry->OutputMid, OutPktToCheck)
        && RtTblEntry->DataPresent == HK_DATA_NOT_PRESENT) {
      // MemCpy, NOT `*MissingInputMid = CpyTblEntry->InputMid`, and this one was MEASURED
      // rather than assumed. docs/HOLYC_STRUCT_LIMITS.md #21 says a class copied through a bare
      // pointer moves only its first EIGHT BYTES -- which for a 4-byte CFE_SB_MsgId means
      // writing four bytes PAST the caller's object. The table in
      // tests/exec/cases/e_struct_copy_into_slot.hc had the wide-class answer for `*ptr = s` and
      // the narrow-class answer for `arr[i] = s`, and NOTHING for the two together, so the case
      // was extended: a 2-byte class through a bare pointer zeroed the neighbour. An array slot
      // narrows the store and a bare pointer does not.
      //
      // The caller is HK_SendCombinedHkPacket's local InputMidMissing, 8-byte aligned with
      // nothing live after it, so the clobber would be invisible here -- which is exactly why it
      // is fixed rather than exempted. The next caller need not be so lucky.
      MemCpy(MissingInputMid, &CpyTblEntry->InputMid, sizeof(CFE_SB_MsgId));
      Status = HK_MISSING_DATA_DETECTED;
    }

    Loop++;

  } while (Loop < HK_COPY_TABLE_ENTRIES && Status == HK_NO_MISSING_DATA);

  return Status;
}

/*******************************************************************************/
// HK set data present flags to 'data-not-present', for ONE output packet.
//
// Called right after a combined packet is sent, so the next cycle's missing-data check starts
// clean -- and only for the entries feeding THAT output id, which is what lets two combined
// packets be requested at different rates. See HK_SendCombinedHkPacket.
U0 HK_SetFlagsToNotPresent(CFE_SB_MsgId OutPkt)
{
  I32 Loop = 0;
  HK_CopyTableEntry_t *StartOfCopyTable = HK_AppData.CopyTablePtr;
  HK_CopyTableEntry_t *CpyTblEntry = NULL;
  HK_RuntimeTableEntry_t *StartOfRtTable = HK_AppData.RuntimeTablePtr;
  HK_RuntimeTableEntry_t *RtTblEntry = NULL;

  /* Look thru each item in the runtime table until end is reached */
  for (Loop = 0; Loop < HK_COPY_TABLE_ENTRIES; Loop++) {
    CpyTblEntry = &StartOfCopyTable[Loop];
    RtTblEntry = &StartOfRtTable[Loop];

    /* Empty table entries are defined by NULL's in this field */
    if (RtTblEntry->OutputPktAddr != 0 && CFE_SB_MsgId_Equal(CpyTblEntry->OutputMid, OutPkt)) {
      RtTblEntry->DataPresent = HK_DATA_NOT_PRESENT;
    }
  }
}

#endif
