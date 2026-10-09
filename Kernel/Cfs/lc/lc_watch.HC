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
// LIMIT CHECKER'S WATCHPOINT PROCESSING -- the 1:1 translation of NASA's fsw/src/lc_watch.c,
// 1,134 lines and twelve functions. This is the packet path: a subscribed message arrives, LC finds
// which watchpoints read it, pulls a value out at a byte offset, and compares.
//
// ### THE FLOAT COMPARISON IS WHY Kernel/Cfs/CfsF32.HC EXISTS
//
// NASA's LC_FloatCompare declares `float WPFloat, CompareFloat, Diff` and does ALL of its
// arithmetic in single precision. HolyC has F64 and no F32 -- host/lexer.c's keywords are
// Bool F64 I16 I32 I64 I8 U0 U16 U32 U64 U8 -- so the translation uses CfsF32.HC, which is pinned
// bit-for-bit against IEEE-754 by tests/exec/cases/e_f32_bits.hc. Per operator:
//
//   LE, LT, GT, GE   decode both operands to F64 and compare. EXACT: float32 embeds in F64
//                    exactly and monotonically, so the order of any two values is preserved.
//   EQ, NE           |a - b| is computed in F64 (where it is exact) and then ROUNDED TO FLOAT32,
//                    because NASA's `Diff` is a float and the C rounds it. The tolerance is
//                    rounded the same way: `F64ToF32Bits(LC_FLOAT_TOLERANCE)` is 0x15F79688, which
//                    is `(float)1.0e-25` -- checked, not assumed.
//
// Skipping the rounding was tempting: by Sterbenz's lemma `a - b` is exact in float32 whenever the
// operands are within a factor of two, which is the entire near-equal regime a tolerance tests. It
// would have agreed almost always. "Almost always" is not 1:1.
//
// AND NaN/Inf ARE TESTED ON THE BIT PATTERN. NASA uses isnan() and deliberately lets infinities
// through -- its comment says "comparisons with infinite numbers will behave as they should so we
// don't try to catch those (we would rather they generate watchpoint violations)". The pattern test
// is a mask and a compare: no dependence on how a host's isnan() treats a signalling NaN, and no
// risk of raising an exception by loading the value.
//
// NASA ALSO DEFINES FALLBACK isnan/isfinite MACROS and they are INERT here: lc_watch.c includes
// <math.h>, so the `#ifndef` substitutes never fire. That matters, because the fallback
// `isfinite(x)` is `((x) > -FLT_MAX && (x) < FLT_MAX)` -- which is FALSE for +/-FLT_MAX itself, so
// on a platform without math.h a comparison value of exactly FLT_MAX would be rejected as
// infinite. The translation matches what the C ACTUALLY does, which is the real isfinite.
//
// ### WHAT THE HASH TABLE BUYS, AND NASA'S OWN BOUND ON IT
//
// NASA's comment on LC_GetHashTableIndex is worth keeping whole: a cFE MessageID's high five bits
// of sixteen are version, packet type and secondary-header flags, so only 2048 values identify a
// telemetry packet; with a 256-entry table indexed by the low eight bits, "no single hash table
// entry will have more than 8 elements in its linked list". That 8 is the reason
// LC_CheckMsgForWPs can walk the bucket with an unbounded `while` and still be bounded.
//
// ### LC_CopyBytesWithSwap IS AN ENDIAN SWAP DRIVEN BY A DATA TABLE, NOT BY A BRANCH
//
//     DestPtr[NumBytes] = SrcPtr[SwapMapPtr[NumBytes] & 0x3];
//
// where the swap map is a U32 holding 0x00010203 for big endian or 0x03020100 for little. So the
// map's bytes ARE the permutation, read in the host's own byte order -- which means the same
// constant means different things on a big- and little-endian CPU, and that is exactly the point:
// LC_32BIT_BE_VAL produces a byte-reversing copy on a little-endian host and an identity copy on a
// big-endian one. The `& 0x3` bounds the index whatever the map holds.
//
// IT IS ALSO WHY A 16-BIT SWAP READS A 16-BIT MAP: ConvBuffer.Unsigned16 is set and only two bytes
// are copied, so the two bytes of the map that matter are the two the host puts first.
#ifndef LC_WATCH_HC
#define LC_WATCH_HC

#include "/Kernel/Cfs/CfsF32.HC"
// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// the above, plus CfsF32.HC and lc_action.HC
//
// **THIS UNIT DOES NOT INCLUDE ITS SIBLINGS** -- docs/HOLYC_STRUCT_LIMITS.md #13. Re-including a
// guarded file the driver has already read makes the compiler skip EVERYTHING AFTER THAT LINE in
// the including file, with no diagnostic and exit status 0.
//
// LC USED TO INCLUDE THEM AND GOT AWAY WITH IT, which is the part worth recording: these includes
// were here from LC's first commit and every function was in the binary. Adding two dead
// constants to lc_watch.HC -- LC_IEEE_EXPONENT_MASK and LC_IEEE_FRACTION_MASK, with a comment
// block above them -- tipped it over, and check_in_blob reported fifteen functions missing from
// lc_cmds.HC and lc_utils.HC. The trigger is text, not structure, so "it works today" was never
// evidence of anything. HK's files were written without sibling includes for this reason; LC's
// now match.

// NASA's fsw/src/lc_watch.h -- the four byte-permutation maps. See the note above on why a single
// constant means different permutations on different hosts.
#define LC_16BIT_BE_VAL 0x0001
#define LC_16BIT_LE_VAL 0x0100
#define LC_32BIT_BE_VAL 0x00010203
#define LC_32BIT_LE_VAL 0x03020100

// Called downwards: LC_CreateHashTable -> LC_AddWatchpoint, LC_CheckMsgForWPs -> LC_WPOffsetValid
// and LC_ProcessWP, LC_ProcessWP -> LC_GetSizedWPData and LC_OperatorCompare, LC_OperatorCompare
// -> the three comparisons, and LC_GetSizedWPData -> LC_CopyBytesWithSwap. NASA's prototypes are
// in lc_watch.h; HolyC is single-pass, so they are here.
LC_WatchPtList_t *LC_AddWatchpoint(CFE_SB_MsgId MessageID);
Bool LC_WPOffsetValid(U16 WatchIndex, CFE_SB_Buffer *BufPtr);
U0 LC_ProcessWP(U16 WatchIndex, CFE_SB_Buffer *BufPtr, CFE_TIME_SysTime Timestamp);
Bool LC_GetSizedWPData(U16 WatchIndex, U8 *WPDataPtr, U32 *SizedDataPtr);
U8 LC_OperatorCompare(U16 WatchIndex, U32 ProcessedWPData);
U8 LC_SignedCompare(U16 WatchIndex, I32 WPValue, I32 CompareValue);
U8 LC_UnsignedCompare(U16 WatchIndex, U32 WPValue, U32 CompareValue);
U8 LC_FloatCompare(U16 WatchIndex, LC_MultiType_t *WPMultiType, LC_MultiType_t *CompareMultiType);
U0 LC_CopyBytesWithSwap(LC_MultiType_t *DestBuffer, U8 *SrcPtr, LC_MultiType_t *SwapMap,
                        U32 NumBytes);

/*******************************************************************************/
// Convert a MessageID to a hash table index.
//
// NASA'S WHOLE COMMENT IS KEPT because it is the argument for the bound, not a description of the
// code.
U32 LC_GetHashTableIndex(CFE_SB_MsgId MessageID)
{
  /*
  **   The purpose of a hash function is to take the input value
  ** and convert it to an index into the hash table. Assume that
  ** the range of input values is much different (larger) than
  ** the number of entries in the hash table. Then multiple input
  ** values must resolve to the same output table index. This is ok
  ** because each entry in the hash table is a linked list of all
  ** the inputs with the same hash function result.
  **
  **   This particular hash function takes advantage of knowledge
  ** regarding the format of the input values (cFE MessageID). By
  ** ignoring the bits that define version number, packet type and
  ** secondary header (high 5 bits of 16) we are left with the bits
  ** (mask = 0x7FF) that can identify 2048 unique input telemetry
  ** packets. Also, by using a fixed hash table size of 256 entries
  ** and using only the lower 8 bits of the bitmask as the result
  ** of the hash function, no single hash table entry will have more
  ** than 8 elements in its linked list.
  */
  return CFE_SB_MsgIdToValue(MessageID) & LC_HASH_TABLE_MASK;
}

/*******************************************************************************/
// Build the watchpoint hash table from the watchpoint definition table.
//
// IT UNSUBSCRIBES FIRST, from every MsgId the PREVIOUS table named, and it does so by walking
// MessageLinks[0..MessageIDsCount) -- the link pool -- rather than the hash table. Same set, and
// the pool is contiguous.
//
// AND THERE IS AN OPTIMISED PATH FOR A RUN OF WATCHPOINTS ON ONE MsgId: if this entry's MsgId
// equals the last one's, the new link is appended directly to the list WatchPtLink already points
// at, skipping the hash lookup entirely. A definition table sorted by MsgId -- which is how a
// mission would write one -- therefore costs one lookup per MsgId rather than one per watchpoint.
U0 LC_CreateHashTable()
{
  LC_WatchPtList_t *WatchPtLink;
  CFE_SB_MsgId LastMessageID;
  CFE_SB_MsgId MessageID;
  I32 MessageLinkIndex;
  I32 WatchPtTblIndex;
  I32 Result;

  /* Un-subscribe to any MessageID's referenced in previous Watchpoint Definition Table */
  for (MessageLinkIndex = 0; MessageLinkIndex < LC_OperData.MessageIDsCount; MessageLinkIndex++) {
    MessageID = LC_OperData.MessageLinks[MessageLinkIndex].MessageID;

    Result = CFE_SB_Unsubscribe(MessageID, LC_OperData.CmdPipe);
    if (Result != CFE_SUCCESS) {
      CFE_EVS_SendEvent(LC_UNSUB_WP_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error unsubscribing watchpoint: MID=0x%08lX, RC=0x%08X",
                        CFE_SB_MsgIdToValue(MessageID), Result);
    }
  }

  /* Initialize hash table structures */
  MemSet(LC_OperData.HashTable, 0, sizeof(LC_MessageList_t *) * LC_HASH_TABLE_ENTRIES);
  MemSet(LC_OperData.MessageLinks, 0, sizeof(LC_MessageList_t) * LC_MAX_WATCHPOINTS);
  MemSet(LC_OperData.WatchPtLinks, 0, sizeof(LC_WatchPtList_t) * LC_MAX_WATCHPOINTS);

  LC_OperData.MessageIDsCount = 0;
  LC_OperData.WatchpointCount = 0;

  LastMessageID = CFE_SB_InvalidMsgId();
  WatchPtLink = NULL;

  /* Process each entry in the Watchpoint Definition Table */
  for (WatchPtTblIndex = 0; WatchPtTblIndex < LC_MAX_WATCHPOINTS; WatchPtTblIndex++) {
    /* Skip unused watchpoint table entries */
    if (LC_OperData.WDTPtr[WatchPtTblIndex].DataType != LC_DATA_WATCH_NOT_USED) {
      MessageID = LC_OperData.WDTPtr[WatchPtTblIndex].MessageID;

      /* Use optimized code path if same MessageID as last watchpoint */
      if (CFE_SB_MsgId_Equal(LastMessageID, MessageID) && WatchPtLink != NULL) {
        /* WatchPtLink points to last link in list for this Message ID */
        WatchPtLink->Next = &LC_OperData.WatchPtLinks[LC_OperData.WatchpointCount++];

        /* Add new link to end of list, point to new last link */
        WatchPtLink = WatchPtLink->Next;
      } else {
        /* May add message list link and subscribe to MessageID */
        WatchPtLink = LC_AddWatchpoint(MessageID);
      }

      /* Set watchpoint table index for this entry in list */
      WatchPtLink->WatchIndex = WatchPtTblIndex;

      LastMessageID = MessageID;
    }
  }

  return;
}

/*******************************************************************************/
// Add one watchpoint entry to the hash table, subscribing if this MsgId is new.
//
// A SUBSCRIBE FAILURE IS AN EVENT AND NOTHING ELSE -- NASA's comment is "Signal the error, but
// continue". So a watchpoint whose MsgId could not be subscribed stays in the table, keeps its
// link, and simply never evaluates, because no message will ever arrive for it. Its WatchResult
// stays whatever it was. That is a real operational state with no telemetry of its own beyond the
// event.
LC_WatchPtList_t *LC_AddWatchpoint(CFE_SB_MsgId MessageID)
{
  LC_MessageList_t *MessageLink;
  LC_WatchPtList_t *WatchPtLink;
  Bool NeedSubscription;
  I32 HashTableIndex;
  I32 Result;

  /* Hash function converts MessageID into hash table index */
  HashTableIndex = LC_GetHashTableIndex(MessageID);

  /* Subscribe only for first reference to each MessageID */
  NeedSubscription = FALSE;

  /* Each hash table entry is a linked list of MessageID's with same hash result */
  if (LC_OperData.HashTable[HashTableIndex] == NULL) {
    /* Get next unused MessageID linked list entry */
    MessageLink = &LC_OperData.MessageLinks[LC_OperData.MessageIDsCount++];

    /* Set first (and only) link in this hash table entry linked list */
    LC_OperData.HashTable[HashTableIndex] = MessageLink;

    /* Set the MessageID for this link */
    MessageLink->MessageID = MessageID;

    /* Subscribe to first link in list */
    NeedSubscription = TRUE;
  } else {
    /* Get start of linked list (all MID's with same hash result) */
    MessageLink = LC_OperData.HashTable[HashTableIndex];

    /* Find the link for this MessageID */
    while (!CFE_SB_MsgId_Equal(MessageLink->MessageID, MessageID)) {
      if (MessageLink->Next == NULL) {
        /* Reached end of list without finding MessageID */
        MessageLink->Next = &LC_OperData.MessageLinks[LC_OperData.MessageIDsCount++];
        MessageLink = MessageLink->Next;

        /* Add link with this MessageID (will exit loop) */
        MessageLink->MessageID = MessageID;

        /* Subscribe to new link in list */
        NeedSubscription = TRUE;
      } else {
        /* Try the next link in the list */
        MessageLink = MessageLink->Next;
      }
    }
  }

  /* Subscribe only once to each MessageID */
  if (NeedSubscription) {
    Result = CFE_SB_Subscribe(MessageID, LC_OperData.CmdPipe);
    if (Result != CFE_SUCCESS) {
      /* Signal the error, but continue */
      CFE_EVS_SendEvent(LC_SUB_WP_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error subscribing watchpoint: MID=0x%08lX, RC=0x%08X",
                        CFE_SB_MsgIdToValue(MessageID), Result);
    }
  }

  /* MessageLink points to the link for this MessageID */
  if (MessageLink->WatchPtList == NULL) {
    /* Get next unused watchpoint linked list entry */
    WatchPtLink = &LC_OperData.WatchPtLinks[LC_OperData.WatchpointCount++];

    /* Set the start (and only) link in the watchpoint link list */
    MessageLink->WatchPtList = WatchPtLink;
  } else {
    /* Find the end of the watchpoint linked list */
    WatchPtLink = MessageLink->WatchPtList;

    while (WatchPtLink->Next != NULL) {
      WatchPtLink = WatchPtLink->Next;
    }

    /* Add the new watchpoint link to the end of the list */
    WatchPtLink->Next = &LC_OperData.WatchPtLinks[LC_OperData.WatchpointCount++];
    WatchPtLink = WatchPtLink->Next;
  }

  /* Return pointer to last link in watchpoint linked list */

  return WatchPtLink;
}

/*******************************************************************************/
// Handle a message that may feed watchpoints.
//
// THE TIMESTAMP FALLS BACK TO THE CURRENT TIME, and the test for "no timestamp" is both fields
// zero -- so a packet genuinely stamped at the epoch is indistinguishable from an unstamped one and
// gets the current time instead. NASA's.
//
// AND AN UNREFERENCED MsgId IS AN **INFORMATION** EVENT ON EVERY ARRIVAL. LC subscribes only to
// MsgIds its table names, so this should be unreachable -- NASA's comment on the enclosing test is
// "Should be true - else wouldn't subscribe to MessageID". It becomes reachable the moment a
// definition table is reloaded with fewer watchpoints while packets are already in the pipe, and
// then it is one event per packet.
U0 LC_CheckMsgForWPs(CFE_SB_MsgId MessageID, CFE_SB_Buffer *BufPtr)
{
  CFE_TIME_SysTime Timestamp;
  LC_MessageList_t *MessageList;
  LC_WatchPtList_t *WatchPtList;
  Bool WatchPtFound = FALSE;

  Timestamp.Seconds = 0;
  Timestamp.Subseconds = 0;

  /* Do nothing if disabled at the application level */
  if (LC_AppData.CurrentLCState != LC_STATE_DISABLED) {
    /* Use message timestamp - if none, use current time */
    CFE_MSG_GetMsgTime(&BufPtr->Msg, &Timestamp);

    if (Timestamp.Seconds == 0 && Timestamp.Subseconds == 0) {
      Timestamp = CFE_TIME_GetTime();
    }

    /* Performance Log (start time counter) */
    CFE_ES_PerfLogEntry(LC_WDT_SEARCH_PERF_ID);

    /* Get start of linked list (all MID's with same hash result) */
    MessageList = LC_OperData.HashTable[LC_GetHashTableIndex(MessageID)];

    /* NULL when list is empty or end of list */
    while (MessageList != NULL) {
      /* Compare this linked list entry for matching MessageID */
      if (CFE_SB_MsgId_Equal(MessageList->MessageID, MessageID)) {
        /* Stop the search - we found it */
        break;
      }

      /* Max of 8 links per design */
      MessageList = MessageList->Next;
    }

    /* Should be true - else wouldn't subscribe to MessageID */
    if (MessageList != NULL) {
      /* Get linked list of WP's that reference MessageID */
      WatchPtList = MessageList->WatchPtList;

      /* NULL when list is empty or end of list */
      while (WatchPtList != NULL) {
        WatchPtFound = TRUE;

        /* Verify that WP packet offset is within actual packet */
        if (LC_WPOffsetValid(WatchPtList->WatchIndex, BufPtr) == TRUE) {
          LC_ProcessWP(WatchPtList->WatchIndex, BufPtr, Timestamp);
        }

        /* No limit to how many WP's can reference one MessageID */
        WatchPtList = WatchPtList->Next;
      }
    }

    /* Performance Log (stop time counter) */
    CFE_ES_PerfLogExit(LC_WDT_SEARCH_PERF_ID);

    if (WatchPtFound == TRUE) {
      LC_AppData.MonitoredMsgCount++;
    } else {
      /* MessageID with no defined watchpoints */
      CFE_EVS_SendEvent(LC_MID_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Msg with unreferenced message ID rcvd: ID = 0x%08lX",
                        CFE_SB_MsgIdToValue(MessageID));
    }
  }

  return;
}

/*******************************************************************************/
// Process a single watchpoint against one received message.
//
// THE DATA POINTER IS THE BUFFER PLUS A TABLE-SUPPLIED BYTE OFFSET -- `((uint8 *)BufPtr) +
// WatchpointOffset` -- so the offset is from the START of the message INCLUDING its headers, and
// LC_WPOffsetValid is the only thing between an uploaded table and a read past the packet. The
// cast to a byte pointer is what makes the arithmetic byte-wise rather than scaled; in HolyC the
// same cast is needed for the same reason, because pointer arithmetic scales by the pointee.
//
// AND THE STALE COUNTDOWN IS RELOADED ON **EVERY** TRUE OR FALSE, not only on a transition: a
// watchpoint that keeps evaluating goes stale only if it stops being evaluated. An ERROR or STALE
// result sets the countdown to ZERO instead, so an errored watchpoint is immediately stale rather
// than aging out.
U0 LC_ProcessWP(U16 WatchIndex, CFE_SB_Buffer *BufPtr, CFE_TIME_SysTime Timestamp)
{
  U8 *WPDataPtr;
  U8 PreviousResult;
  U8 WPEvalResult;
  U32 SizedWPData;
  U32 MaskedWPData;
  U32 StaleCounter;
  Bool SizedDataValid;

  /*
  ** Setup the pointer and get the massaged data
  */
  WPDataPtr = BufPtr(U8 *) + LC_OperData.WDTPtr[WatchIndex].WatchpointOffset;

  SizedDataValid = LC_GetSizedWPData(WatchIndex, WPDataPtr, &SizedWPData);
  if (SizedDataValid == TRUE) {
    /*
    ** Get the last evaluation result for this watchpoint
    */
    PreviousResult = LC_OperData.WRTPtr[WatchIndex].WatchResult;

    /*
    ** Apply the defined bitmask for this watchpoint and then
    ** call the mission defined custom function or do our own
    ** relational comparison.
    */
    MaskedWPData = SizedWPData & LC_OperData.WDTPtr[WatchIndex].BitMask;

    if (LC_OperData.WDTPtr[WatchIndex].OperatorID == LC_OPER_CUSTOM) {
      WPEvalResult = LC_CustomFunction(WatchIndex, MaskedWPData, BufPtr,
                                       LC_OperData.WDTPtr[WatchIndex].CustomFuncArgument);
    } else {
      WPEvalResult = LC_OperatorCompare(WatchIndex, MaskedWPData);
    }

    /*
    ** Update the watch result
    */
    LC_OperData.WRTPtr[WatchIndex].WatchResult = WPEvalResult;

    /*
    ** Update the watchpoint statistics based on the evaluation
    ** result
    */
    LC_OperData.WRTPtr[WatchIndex].EvaluationCount++;

    if (WPEvalResult == LC_WATCH_TRUE) {
      LC_OperData.WRTPtr[WatchIndex].CumulativeTrueCount++;
      LC_OperData.WRTPtr[WatchIndex].ConsecutiveTrueCount++;
      StaleCounter = LC_OperData.WDTPtr[WatchIndex].ResultAgeWhenStale;
      LC_OperData.WRTPtr[WatchIndex].CountdownToStale = StaleCounter;

      if (PreviousResult == LC_WATCH_FALSE || PreviousResult == LC_WATCH_STALE) {
        LC_OperData.WRTPtr[WatchIndex].LastFalseToTrue.DataType =
            LC_OperData.WDTPtr[WatchIndex].DataType;

        LC_OperData.WRTPtr[WatchIndex].FalseToTrueCount++;

        LC_OperData.WRTPtr[WatchIndex].LastFalseToTrue.Value = MaskedWPData;

        LC_OperData.WRTPtr[WatchIndex].LastFalseToTrue.Timestamp.Seconds = Timestamp.Seconds;

        LC_OperData.WRTPtr[WatchIndex].LastFalseToTrue.Timestamp.Subseconds =
            Timestamp.Subseconds;
      }
    } else if (WPEvalResult == LC_WATCH_FALSE) {
      LC_OperData.WRTPtr[WatchIndex].ConsecutiveTrueCount = 0;
      StaleCounter = LC_OperData.WDTPtr[WatchIndex].ResultAgeWhenStale;
      LC_OperData.WRTPtr[WatchIndex].CountdownToStale = StaleCounter;

      if (PreviousResult == LC_WATCH_TRUE || PreviousResult == LC_WATCH_STALE) {
        LC_OperData.WRTPtr[WatchIndex].LastTrueToFalse.DataType =
            LC_OperData.WDTPtr[WatchIndex].DataType;

        LC_OperData.WRTPtr[WatchIndex].LastTrueToFalse.Value = MaskedWPData;

        LC_OperData.WRTPtr[WatchIndex].LastTrueToFalse.Timestamp.Seconds = Timestamp.Seconds;

        LC_OperData.WRTPtr[WatchIndex].LastTrueToFalse.Timestamp.Subseconds =
            Timestamp.Subseconds;
      }
    } else {
      /*
      ** WPEvalResult is STALE or ERROR
      */
      LC_OperData.WRTPtr[WatchIndex].CountdownToStale = 0;
    }
  } /* end SizedDataValid if */

  return;
}

/*******************************************************************************/
// Perform a watchpoint relational comparison: pick the comparison by data type.
//
// TWO SWITCHES ON THE SAME DataType, AND THE FIRST IS A TRUNCATION. NASA's comment says why:
// "The ProcessedWPData has been already normalized to be 32 bits wide and in the native CPU byte
// order. For actual comparison, it needs to be truncated back down to the same size as the
// reference value."
//
// SO THE UNION IS WRITTEN THROUGH ONE MEMBER AND READ THROUGH ANOTHER, deliberately: the byte
// case writes .Unsigned8 and the signed path reads .Signed8, which is how the SIGN EXTENSION
// happens. The local union is never fully initialised and does not need to be -- only the member
// that was written is ever read, and for the 8- and 16-bit cases the write and the read are the
// same bytes.
U8 LC_OperatorCompare(U16 WatchIndex, U32 ProcessedWPData)
{
  U8 EvalResult;
  LC_MultiType_t WatchpointValue;
  LC_MultiType_t ComparisonValue;

  /*
   * The "ProcessedWPData" has been already normalized to be
   * 32 bits wide and in the native CPU byte order.  For actual
   * comparison, it needs to be truncated back down to the same
   * size as the reference value.
   */
  switch (LC_OperData.WDTPtr[WatchIndex].DataType) {
    case LC_DATA_WATCH_UBYTE:
    case LC_DATA_WATCH_BYTE:
      WatchpointValue.Unsigned8 = ProcessedWPData & 0xFF;
      break;

    case LC_DATA_WATCH_WORD_BE:
    case LC_DATA_WATCH_WORD_LE:
    case LC_DATA_WATCH_UWORD_BE:
    case LC_DATA_WATCH_UWORD_LE:
      WatchpointValue.Unsigned16 = ProcessedWPData & 0xFFFF;
      break;

    case LC_DATA_WATCH_DWORD_BE:
    case LC_DATA_WATCH_DWORD_LE:
    case LC_DATA_WATCH_UDWORD_BE:
    case LC_DATA_WATCH_UDWORD_LE:
    case LC_DATA_WATCH_FLOAT_BE:
    case LC_DATA_WATCH_FLOAT_LE:
    default:
      WatchpointValue.Unsigned32 = ProcessedWPData;
      break;
  }

  // NASA uses memcpy of sizeof(LC_MultiType_t) rather than a struct assignment -- its `SAD`
  // comment says "preserving bitwise representation". Four bytes either way; MemCpy keeps the
  // intent, and docs/HOLYC_STRUCT_LIMITS.md #21 is the reason this port never assumes a struct
  // assignment through a pointer copies everything.
  MemCpy(&ComparisonValue, &LC_OperData.WDTPtr[WatchIndex].ComparisonValue,
         sizeof(LC_MultiType_t));

  /*
  ** Handle the comparison appropriately depending on the data type
  ** Any endian difference was handled when the watchpoint
  ** data was extracted from the SB message
  */
  switch (LC_OperData.WDTPtr[WatchIndex].DataType) {
    /*
    ** Signed integer types will get sign extended
    */
    case LC_DATA_WATCH_BYTE:
      EvalResult = LC_SignedCompare(WatchIndex, WatchpointValue.Signed8, ComparisonValue.Signed8);
      break;

    case LC_DATA_WATCH_WORD_BE:
    case LC_DATA_WATCH_WORD_LE:
      EvalResult =
          LC_SignedCompare(WatchIndex, WatchpointValue.Signed16, ComparisonValue.Signed16);
      break;

    case LC_DATA_WATCH_DWORD_BE:
    case LC_DATA_WATCH_DWORD_LE:
      EvalResult =
          LC_SignedCompare(WatchIndex, WatchpointValue.Signed32, ComparisonValue.Signed32);
      break;

    /*
    ** Unsigned integer types will get zero extended
    */
    case LC_DATA_WATCH_UBYTE:
      EvalResult =
          LC_UnsignedCompare(WatchIndex, WatchpointValue.Unsigned8, ComparisonValue.Unsigned8);
      break;

    case LC_DATA_WATCH_UWORD_BE:
    case LC_DATA_WATCH_UWORD_LE:
      EvalResult =
          LC_UnsignedCompare(WatchIndex, WatchpointValue.Unsigned16, ComparisonValue.Unsigned16);
      break;

    case LC_DATA_WATCH_UDWORD_BE:
    case LC_DATA_WATCH_UDWORD_LE:
      EvalResult =
          LC_UnsignedCompare(WatchIndex, WatchpointValue.Unsigned32, ComparisonValue.Unsigned32);
      break;

    /*
    ** Floating point values are handled separately
    */
    case LC_DATA_WATCH_FLOAT_BE:
    case LC_DATA_WATCH_FLOAT_LE:
      EvalResult = LC_FloatCompare(WatchIndex, &WatchpointValue, &ComparisonValue);
      break;

    default:
      /*
      ** This should have been caught before now, but we'll
      ** handle it just in case we ever get here.
      */
      CFE_EVS_SendEvent(LC_WP_DATATYPE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "WP has undefined data type: WP = %d, DataType = %d", WatchIndex,
                        LC_OperData.WDTPtr[WatchIndex].DataType);

      EvalResult = LC_WATCH_ERROR;
      break;
  }

  return EvalResult;
}

/*******************************************************************************/
// Perform a watchpoint SIGNED integer comparison.
//
// THE SIGNEDNESS IS CARRIED BY THE PARAMETER TYPES AND NOTHING ELSE. This function and its
// unsigned twin below are otherwise identical -- same six operators, same default arm, same event
// -- so the only thing that makes `<=` mean what it should is that one takes I32 and the other
// U32. docs/ records a case where exactly that was lost in translation; here HolyC has both types
// and check_signatures compares them against NASA's.
U8 LC_SignedCompare(U16 WatchIndex, I32 WPValue, I32 CompareValue)
{
  U8 EvalResult;
  U8 OperatorID;

  OperatorID = LC_OperData.WDTPtr[WatchIndex].OperatorID;

  switch (OperatorID) {
    case LC_OPER_LE:
      EvalResult = (WPValue <= CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    case LC_OPER_LT:
      EvalResult = (WPValue < CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    case LC_OPER_EQ:
      EvalResult = (WPValue == CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    case LC_OPER_NE:
      EvalResult = (WPValue != CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    case LC_OPER_GT:
      EvalResult = (WPValue > CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    case LC_OPER_GE:
      EvalResult = (WPValue >= CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    default:
      /*
      ** This should have been caught before now, but we'll
      ** handle it just in case we ever get here.
      */
      CFE_EVS_SendEvent(LC_WP_OPERID_ERR_EID, CFE_EVS_EventType_ERROR,
                        "WP has invalid operator ID: WP = %d, OperID = %d", WatchIndex,
                        OperatorID);

      EvalResult = LC_WATCH_ERROR;
      break;
  }

  return EvalResult;
}

/*******************************************************************************/
// Perform a watchpoint UNSIGNED integer comparison. The signed twin above, with U32 parameters.
U8 LC_UnsignedCompare(U16 WatchIndex, U32 WPValue, U32 CompareValue)
{
  U8 EvalResult;
  U8 OperatorID;

  OperatorID = LC_OperData.WDTPtr[WatchIndex].OperatorID;

  switch (OperatorID) {
    case LC_OPER_LE:
      EvalResult = (WPValue <= CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    case LC_OPER_LT:
      EvalResult = (WPValue < CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    case LC_OPER_EQ:
      EvalResult = (WPValue == CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    case LC_OPER_NE:
      EvalResult = (WPValue != CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    case LC_OPER_GT:
      EvalResult = (WPValue > CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    case LC_OPER_GE:
      EvalResult = (WPValue >= CompareValue) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
      break;

    default:
      /*
      ** This should have been caught before now, but we'll
      ** handle it just in case we ever get here.
      */
      CFE_EVS_SendEvent(LC_WP_OPERID_ERR_EID, CFE_EVS_EventType_ERROR,
                        "WP has invalid operator ID: WP = %d, OperID = %d", WatchIndex,
                        OperatorID);

      EvalResult = LC_WATCH_ERROR;
      break;
  }

  return EvalResult;
}

/*******************************************************************************/
// Perform a floating point comparison. THE ONE FUNCTION IN LC THAT HolyC CANNOT EXPRESS DIRECTLY.
//
// NASA declares three `float`s and lets C do the work. Here the operands are 32-bit BIT PATTERNS
// out of the union, and Kernel/Cfs/CfsF32.HC supplies the two conversions. See the note at the top
// of this file for which operators are exact for free and which needed the rounding; in short:
//
//   LE/LT/GT/GE   decode to F64 and compare -- exact, because the embedding is monotonic.
//   EQ/NE         |a-b| in F64 (exact), then ROUNDED TO FLOAT32, because NASA's `Diff` is a float.
//                 The tolerance is rounded the same way, which is what `(float)LC_FLOAT_TOLERANCE`
//                 means; F64ToF32Bits(1.0e-25) is 0x15F79688, and that was checked against C.
//
// THE NaN GUARD IS NASA'S AND SO IS LETTING INFINITIES THROUGH. Its comment: "NAN comparisons
// don't work and can generate floating point exceptions. By contrast comparisons with infinite
// numbers will behave as they should so we don't try to catch those (we would rather they generate
// watchpoint violations)." Testing the pattern rather than the value means nothing is loaded into
// a floating-point register to ask the question, so the exception NASA is avoiding cannot happen
// at all.
U8 LC_FloatCompare(U16 WatchIndex, LC_MultiType_t *WPMultiType, LC_MultiType_t *CompareMultiType)
{
  U8 EvalResult;
  U8 OperatorID;
  U32 WPBits;
  U32 CompareBits;
  U32 ToleranceBits;
  F64 WPFloat;
  F64 CompareFloat;
  F64 Diff;

  OperatorID = LC_OperData.WDTPtr[WatchIndex].OperatorID;

  // NASA memcpy's four bytes out of each union into a `float`; here the four bytes ARE the value
  // and the conversion is explicit.
  WPBits = WPMultiType->Unsigned32;
  CompareBits = CompareMultiType->Unsigned32;

  /*
  ** Before we do any comparison, check the watchpoint value for
  ** a floating point NAN (not-a-number). NAN comparisons don't
  ** work and can generate floating point exceptions. By contrast
  ** comparisons with infinite numbers will behave as they should
  ** so we don't try to catch those (we would rather they generate
  ** watchpoint violations).
  **
  ** The comparison (threshold) value comes from the Watchpoint
  ** Definition Table (WDT) and any weird values should get nailed
  ** during table validation.
  */
  if (!F32BitsIsNaN(WPBits)) {
    WPFloat = F32BitsToF64(WPBits);
    CompareFloat = F32BitsToF64(CompareBits);

    switch (OperatorID) {
      case LC_OPER_LE:
        EvalResult = (WPFloat <= CompareFloat) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
        break;

      case LC_OPER_LT:
        EvalResult = (WPFloat < CompareFloat) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
        break;

      case LC_OPER_EQ:
        Diff = (WPFloat > CompareFloat) ? (WPFloat - CompareFloat) : (CompareFloat - WPFloat);
        // NASA's `Diff` is a float, so the difference is rounded to single precision before the
        // comparison, and so is the tolerance. Both roundings are explicit here.
        Diff = F32BitsToF64(F64ToF32Bits(Diff));
        ToleranceBits = F64ToF32Bits(LC_FLOAT_TOLERANCE);
        EvalResult = (Diff <= F32BitsToF64(ToleranceBits)) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
        break;

      case LC_OPER_NE:
        Diff = (WPFloat > CompareFloat) ? (WPFloat - CompareFloat) : (CompareFloat - WPFloat);
        Diff = F32BitsToF64(F64ToF32Bits(Diff));
        ToleranceBits = F64ToF32Bits(LC_FLOAT_TOLERANCE);
        EvalResult = (Diff > F32BitsToF64(ToleranceBits)) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
        break;

      case LC_OPER_GT:
        EvalResult = (WPFloat > CompareFloat) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
        break;

      case LC_OPER_GE:
        EvalResult = (WPFloat >= CompareFloat) ? LC_WATCH_TRUE : LC_WATCH_FALSE;
        break;

      default:
        /*
        ** This should have been caught before now, but we'll
        ** handle it just in case we ever get here.
        */
        CFE_EVS_SendEvent(LC_WP_OPERID_ERR_EID, CFE_EVS_EventType_ERROR,
                          "WP has invalid operator ID: WP = %d, OperID = %d", WatchIndex,
                          OperatorID);

        EvalResult = LC_WATCH_ERROR;
        break;
    } /*  end of switch  */
  }   /* end LC_WPIsNAN if */
  else {
    CFE_EVS_SendEvent(LC_WP_NAN_ERR_EID, CFE_EVS_EventType_ERROR,
                      "WP data value is a float NAN: WP = %d, Value = 0x%08X", WatchIndex, WPBits);

    EvalResult = LC_WATCH_ERROR;
  }

  return EvalResult;
}

/*******************************************************************************/
// Will a defined watchpoint offset read past the end of the received message?
//
// THE UNDEFINED-DATA-TYPE ARM RETURNS EARLY AND SETS THE RESULT TO ERROR, so a watchpoint with a
// bad type is marked errored here AND again in LC_GetSizedWPData -- both of which the caller can
// reach. That is NASA's belt and braces on a table the ground uploaded.
//
// AND THE OVERFLOW TEST IS `(Offset + NumOfDataBytes) > MsgLength` IN UNSIGNED ARITHMETIC. Offset
// is a U32 from the table and unbounded, so a value near 0xFFFFFFFF wraps and the test PASSES --
// after which the read is from BufPtr plus almost four gigabytes. Latent upstream: LC_ValidateWDT
// does not bound WatchpointOffset either, so nothing in LC rejects it. Reported rather than fixed,
// and the translation keeps the arithmetic exactly so the behaviour is the same.
Bool LC_WPOffsetValid(U16 WatchIndex, CFE_SB_Buffer *BufPtr)
{
  I64 MsgLength = 0;
  U32 Offset;
  U32 NumOfDataBytes = 0;
  Bool OffsetValid = TRUE;
  CFE_SB_MsgId MessageID = CFE_SB_InvalidMsgId();

  /*
  ** Check the message length against the watchpoint
  ** offset and data type to make sure we won't
  ** try to read past it.
  */
  switch (LC_OperData.WDTPtr[WatchIndex].DataType) {
    case LC_DATA_WATCH_BYTE:
    case LC_DATA_WATCH_UBYTE:
      NumOfDataBytes = 1; // sizeof(uint8)
      break;

    case LC_DATA_WATCH_WORD_BE:
    case LC_DATA_WATCH_WORD_LE:
    case LC_DATA_WATCH_UWORD_BE:
    case LC_DATA_WATCH_UWORD_LE:
      NumOfDataBytes = 2; // sizeof(uint16)
      break;

    case LC_DATA_WATCH_DWORD_BE:
    case LC_DATA_WATCH_DWORD_LE:
    case LC_DATA_WATCH_UDWORD_BE:
    case LC_DATA_WATCH_UDWORD_LE:
      NumOfDataBytes = 4; // sizeof(uint32)
      break;

    case LC_DATA_WATCH_FLOAT_BE:
    case LC_DATA_WATCH_FLOAT_LE:
      // sizeof(float) -- FOUR, and written as four because HolyC has no F32 to take the size of.
      // The width is the WIRE width of the datum, which is what this function is about, so it is
      // 4 regardless of what the comparison is later done in.
      NumOfDataBytes = 4;
      break;

    default:
      /*
      ** This should have been caught before now, but we'll
      ** handle it just in case we ever get here.
      */
      CFE_EVS_SendEvent(LC_WP_DATATYPE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "WP has undefined data type: WP = %d, DataType = %d", WatchIndex,
                        LC_OperData.WDTPtr[WatchIndex].DataType);

      LC_OperData.WRTPtr[WatchIndex].WatchResult = LC_WATCH_ERROR;
      LC_OperData.WRTPtr[WatchIndex].CountdownToStale = 0;

      return FALSE;
      break;
  } /* end switch */

  CFE_MSG_GetSize(&BufPtr->Msg, &MsgLength);

  Offset = LC_OperData.WDTPtr[WatchIndex].WatchpointOffset;

  if (Offset + NumOfDataBytes > MsgLength) {
    OffsetValid = FALSE;

    CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);

    CFE_EVS_SendEvent(LC_WP_OFFSET_ERR_EID, CFE_EVS_EventType_ERROR,
                      "WP offset error: MID = 0x%08lX, WP = %d, Offset = %d, DataSize = %d, MsgLen = %d",
                      CFE_SB_MsgIdToValue(MessageID), WatchIndex, Offset, NumOfDataBytes,
                      MsgLength);

    LC_OperData.WRTPtr[WatchIndex].WatchResult = LC_WATCH_ERROR;
    LC_OperData.WRTPtr[WatchIndex].CountdownToStale = 0;
  }

  return OffsetValid;
}

/*******************************************************************************/
// Copy one watchpoint datum and byteswap it in the same pass.
//
// THE PERMUTATION IS DATA, NOT A BRANCH. See the note at the top of this file: the swap map is a
// U32 whose BYTES are the source indices, read in the host's own byte order, so one constant means
// a reversing copy on one endianness and an identity copy on the other. `& 0x3` bounds the index
// whatever the map holds.
//
// THE LOOP COUNTS DOWN AND PRE-DECREMENTS, so it copies indices NumBytes-1 .. 0 and stops; a
// NumBytes of zero copies nothing rather than wrapping, which matters because the parameter is
// unsigned.
U0 LC_CopyBytesWithSwap(LC_MultiType_t *DestBuffer, U8 *SrcPtr, LC_MultiType_t *SwapMap,
                        U32 NumBytes)
{
  U8 *DestPtr;
  U8 *SwapMapPtr;

  DestPtr = DestBuffer(U8 *);
  SwapMapPtr = SwapMap(U8 *);
  while (NumBytes > 0) {
    --NumBytes;
    DestPtr[NumBytes] = SrcPtr[SwapMapPtr[NumBytes] & 0x3];
  }
}

/*******************************************************************************/
// Read the watchpoint datum out of the message at its own width, fixing endianness and sign.
//
// EVERY ARM NORMALISES TO A U32 IN HOST ORDER, and the sign extension is done by writing one union
// member and reading another: `TempBuffer.Signed8 = *WPDataPtr; *SizedDataPtr =
// TempBuffer.Signed8;` extends an 8-bit signed value to 32 bits because the READ is through the
// signed member. The unsigned arms simply assign.
//
// THE BYTE ARMS DO NOT SWAP, because one byte has no order -- so LC has no LC_DATA_WATCH_BYTE_BE.
// Everything wider pairs a map constant with a width.
Bool LC_GetSizedWPData(U16 WatchIndex, U8 *WPDataPtr, U32 *SizedDataPtr)
{
  Bool Success = TRUE;
  LC_MultiType_t ConvBuffer;
  LC_MultiType_t TempBuffer;

  ConvBuffer.Unsigned32 = 0;
  TempBuffer.Unsigned32 = 0;

  /*
  ** Get the watchpoint data value (which may be on a misaligned
  ** address boundary) and put it into an unsigned 32 properly
  ** handling endian and sign extension issues
  */
  switch (LC_OperData.WDTPtr[WatchIndex].DataType) {
    case LC_DATA_WATCH_BYTE:
      TempBuffer.Signed8 = *WPDataPtr;
      *SizedDataPtr = TempBuffer.Signed8; /* Extend signed 8 bit value to 32 bits */
      break;

    case LC_DATA_WATCH_UBYTE:
      *SizedDataPtr = *WPDataPtr; /* Extend unsigned 8 bit value to 32 bits */
      break;

    case LC_DATA_WATCH_WORD_BE:
      ConvBuffer.Unsigned16 = LC_16BIT_BE_VAL;
      LC_CopyBytesWithSwap(&TempBuffer, WPDataPtr, &ConvBuffer, 2);
      *SizedDataPtr = TempBuffer.Signed16; /* Extend signed 16 bit value to 32 bits */
      break;

    case LC_DATA_WATCH_WORD_LE:
      ConvBuffer.Unsigned16 = LC_16BIT_LE_VAL;
      LC_CopyBytesWithSwap(&TempBuffer, WPDataPtr, &ConvBuffer, 2);
      *SizedDataPtr = TempBuffer.Signed16; /* Extend signed 16 bit value to 32 bits */
      break;

    case LC_DATA_WATCH_UWORD_BE:
      ConvBuffer.Unsigned16 = LC_16BIT_BE_VAL;
      LC_CopyBytesWithSwap(&TempBuffer, WPDataPtr, &ConvBuffer, 2);
      *SizedDataPtr = TempBuffer.Unsigned16; /* Extend unsigned 16 bit value to 32 bits */
      break;

    case LC_DATA_WATCH_UWORD_LE:
      ConvBuffer.Unsigned16 = LC_16BIT_LE_VAL;
      LC_CopyBytesWithSwap(&TempBuffer, WPDataPtr, &ConvBuffer, 2);
      *SizedDataPtr = TempBuffer.Unsigned16; /* Extend unsigned 16 bit value to 32 bits */
      break;

    case LC_DATA_WATCH_DWORD_BE:
    case LC_DATA_WATCH_UDWORD_BE:
    case LC_DATA_WATCH_FLOAT_BE:
      ConvBuffer.Unsigned32 = LC_32BIT_BE_VAL;
      LC_CopyBytesWithSwap(&TempBuffer, WPDataPtr, &ConvBuffer, 4);
      *SizedDataPtr = TempBuffer.Unsigned32; /* Straight copy - no extension (signed or unsigned) */
      break;

    case LC_DATA_WATCH_DWORD_LE:
    case LC_DATA_WATCH_UDWORD_LE:
    case LC_DATA_WATCH_FLOAT_LE:
      ConvBuffer.Unsigned32 = LC_32BIT_LE_VAL;
      LC_CopyBytesWithSwap(&TempBuffer, WPDataPtr, &ConvBuffer, 4);
      *SizedDataPtr = TempBuffer.Unsigned32; /* Straight copy - no extension (signed or unsigned) */
      break;

    default:
      /*
      ** This should have been caught before now, but we'll
      ** handle it just in case we ever get here.
      */
      CFE_EVS_SendEvent(LC_WP_DATATYPE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "WP has undefined data type: WP = %d, DataType = %d", WatchIndex,
                        LC_OperData.WDTPtr[WatchIndex].DataType);

      LC_OperData.WRTPtr[WatchIndex].WatchResult = LC_WATCH_ERROR;
      LC_OperData.WRTPtr[WatchIndex].CountdownToStale = 0;

      Success = FALSE;
      *SizedDataPtr = 0;
      break;
  } /* end switch */

  /*
  ** Return success flag
  */
  return Success;
}

/*******************************************************************************/
// Validate the watchpoint definition table (WDT).
//
// FOUR CHECKS IN AN else-if CHAIN plus a float branch, so only the first failure per entry is
// named -- and only the FIRST BAD ENTRY IN THE TABLE gets a detailed event, guarded by
// `TableResult == CFE_SUCCESS`. The same shape LC_ValidateADT and CS's four validators have.
//
// THE FLOAT BRANCH IS WHERE isnan AND isfinite WERE, and the translation tests the BIT PATTERN:
//
//     if (isnan(FloatValue))        -> F32BitsIsNaN(Bits)
//     else if (!isfinite(FloatValue)) -> F32BitsIsInf(Bits)
//
// The second substitution is exact ONLY BECAUSE THE NaN CHECK COMES FIRST: real `!isfinite` is
// true for NaN as well as for infinities, so on its own it is not "is infinite" -- but a NaN has
// already been taken by the arm above, so what is left for it is exactly the two infinities.
// Stated because the equivalence depends on the order and would break if the arms were swapped.
//
// IT DOES NOT BOUND WatchpointOffset, which is the latent issue noted on LC_WPOffsetValid: an
// offset near 0xFFFFFFFF passes validation here and then wraps the unsigned overflow test there.
I32 LC_ValidateWDT(U8 *TableData)
{
  LC_WDTEntry_t *TableArray = TableData;

  I32 EntryResult = LC_WDTVAL_ERR_NONE;
  I32 TableResult = CFE_SUCCESS;
  I32 TableIndex;

  U8 DataType;
  U8 OperatorID;
  CFE_SB_MsgId MessageID;
  U32 PrintableBits;
  U32 FloatBits;

  I32 GoodCount = 0;
  I32 BadCount = 0;
  I32 UnusedCount = 0;

  /*
  ** Verify each entry in the pending watchpoint definition table
  */
  for (TableIndex = 0; TableIndex < LC_MAX_WATCHPOINTS; TableIndex++) {
    DataType = TableArray[TableIndex].DataType;
    OperatorID = TableArray[TableIndex].OperatorID;
    MessageID = TableArray[TableIndex].MessageID;

    if (DataType == LC_DATA_WATCH_NOT_USED) {
      /*
      ** Unused table entry
      */
      UnusedCount++;
    } else if (DataType != LC_DATA_WATCH_BYTE && DataType != LC_DATA_WATCH_UBYTE &&
               DataType != LC_DATA_WATCH_WORD_BE && DataType != LC_DATA_WATCH_WORD_LE &&
               DataType != LC_DATA_WATCH_UWORD_BE && DataType != LC_DATA_WATCH_UWORD_LE &&
               DataType != LC_DATA_WATCH_DWORD_BE && DataType != LC_DATA_WATCH_DWORD_LE &&
               DataType != LC_DATA_WATCH_UDWORD_BE && DataType != LC_DATA_WATCH_UDWORD_LE &&
               DataType != LC_DATA_WATCH_FLOAT_BE && DataType != LC_DATA_WATCH_FLOAT_LE) {
      /*
      ** Invalid data type
      */
      BadCount++;
      EntryResult = LC_WDTVAL_ERR_DATATYPE;
    } else if (OperatorID != LC_OPER_LT && OperatorID != LC_OPER_LE && OperatorID != LC_OPER_NE &&
               OperatorID != LC_OPER_EQ && OperatorID != LC_OPER_GE && OperatorID != LC_OPER_GT &&
               OperatorID != LC_OPER_CUSTOM) {
      /*
      ** Invalid operator
      */
      BadCount++;
      EntryResult = LC_WDTVAL_ERR_OPER;
    } else if (!CFE_SB_IsValidMsgId(MessageID)) {
      /*
      ** Bad message ID
      */
      BadCount++;
      EntryResult = LC_WDTVAL_ERR_MID;
    } else if (DataType == LC_DATA_WATCH_FLOAT_BE || DataType == LC_DATA_WATCH_FLOAT_LE) {
      // NASA memcpy's the four bytes into a `float`; here they stay a bit pattern and the two
      // predicates read it directly. See the note above on why testing the pattern is exact.
      FloatBits = TableArray[TableIndex].ComparisonValue.Unsigned32;

      /*
      ** Check the floating point comparison value for
      ** NAN (not-a-number) or infinite values
      */
      if (F32BitsIsNaN(FloatBits)) {
        BadCount++;
        EntryResult = LC_WDTVAL_ERR_FPNAN;
      } else if (F32BitsIsInf(FloatBits)) {
        BadCount++;
        EntryResult = LC_WDTVAL_ERR_FPINF;
      } else {
        /*
        ** We passed all checks for this floating point entry
        */
        GoodCount++;
      }
    } else {
      /*
      ** We passed all checks for this non-floating point entry
      */
      GoodCount++;
    }

    /*
    ** Generate detailed event for "first" error
    */
    if (EntryResult != LC_WDTVAL_ERR_NONE && TableResult == CFE_SUCCESS) {
      if (EntryResult == LC_WDTVAL_ERR_FPNAN || EntryResult == LC_WDTVAL_ERR_FPINF) {
        PrintableBits = TableArray[TableIndex].ComparisonValue.Unsigned32;
        CFE_EVS_SendEvent(LC_WDTVAL_FPERR_EID, CFE_EVS_EventType_ERROR,
                          "WDT verify float err: WP = %d, Err = %d, ComparisonValue = 0x%08X",
                          TableIndex, EntryResult, PrintableBits);
      } else {
        CFE_EVS_SendEvent(LC_WDTVAL_ERR_EID, CFE_EVS_EventType_ERROR,
                          "WDT verify err: WP = %d, Err = %d, DType = %d, Oper = %d, MID = 0x%08lX",
                          TableIndex, EntryResult, DataType, OperatorID,
                          CFE_SB_MsgIdToValue(MessageID));
      }

      TableResult = EntryResult;
    }
  } /* end TableIndex for */

  /*
  ** Generate informational event with error totals
  */
  CFE_EVS_SendEvent(LC_WDTVAL_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "WDT verify results: good = %d, bad = %d, unused = %d", GoodCount, BadCount,
                    UnusedCount);

  return TableResult;
}


// --- CONSTANTS NASA'S HEADER DECLARES AND NO SOURCE USES -------------------------------------
//
// Dead upstream: a grep across every .c in the repository finds no use of either IEEE mask -- this port's float handling goes through Kernel/Cfs/CfsF32.HC's bit helpers, and NASA's masks are dead in its own code too. They are translated anyway
// because they are part of the header's declared interface and cost nothing, which is the answer
// that needs no judgement -- and because tools/cfs/check_defines.py now refuses a #define that is
// nowhere in the translation. That gate was written after a case-sensitive grep silently dropped
// EIGHT of HS's event ids; these nineteen are what it found on its first run, across six years of
// this port's history.
#define LC_IEEE_EXPONENT_MASK 0x7F800000
#define LC_IEEE_FRACTION_MASK 0x007FFFFF

#endif
