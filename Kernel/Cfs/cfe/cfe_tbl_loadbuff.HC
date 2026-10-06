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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_loadbuff.c -- WHERE A TABLE'S BYTES
// LIVE, and the id arithmetic that says which buffer an id names. The thirteen header inlines
// are in cfe_tbl_loadbuff_decl.HC, which landed first.
//
// THE SERIAL ENCODING IS THE WHOLE FILE, and it is why this source and cfe_tbl_regrec.c had to
// be gated together: regrec asks "which buffer is this id" on every load, and only this file
// knows. A load-buffer id is a resource id whose SERIAL is a position in one flat numbering of
// every buffer in the system:
//
//     serial % TOTAL_LOAD_BUFFS  ->  0 .. 3      the four SHARED buffers, category 0
//                                    4 .. 4+2N   table N's own pair, category N+1
//
// so one modulo and one comparison recover both the category and the index. TOTAL_LOAD_BUFFS
// is 4 + 128*2 = 260. A SINGLE-buffered table borrows a shared buffer for the duration of a
// load and gives it back; a DOUBLE-buffered table owns its pair outright, which is what lets
// it be updated without ever waiting for a shared one to come free.
//
// AND THE DECOMPOSE/COMPOSE PAIR IS NOT SYMMETRIC, which is the subtle part.
// SerialDecompose answers "what does this serial refer to". SerialCompose rounds its input UP
// to the next multiple of TOTAL_LOAD_BUFFS first -- `Serial += TOTAL-1; Serial -= Serial %
// TOTAL;` -- and then adds the category's offset. It is not the inverse of Decompose; it is
// "the next serial at or after this one that lands in the category I want". That is what makes
// CFE_TBL_LoadBuffIncrementSerial_Impl able to walk a category's buffers without walking every
// other table's, and it is the only reason FindNext over 260 buffers costs four steps.
//
// FOUR STAND-INS, all in the differential driver on both halves, all named by
// tools/cfs/module_deps.py --cuts for this pair: CFE_TBL_AcquireGlobalLoadBuff and
// CFE_TBL_ForeachAccessDescriptor from cfe_tbl_internal.c, CFE_TBL_SendTransactionEvents and
// CFE_TBL_TxnAddEvent from cfe_tbl_transaction.c.
#ifndef CFE_TBL_LOADBUFF_HC
#define CFE_TBL_LOADBUFF_HC
#ifndef CFE_TBL_ERR_INVALID_HANDLE
#define CFE_TBL_ERR_INVALID_HANDLE 0xCC000001(I32)
#endif
// cfe_tbl_eventids.h
#ifndef CFE_TBL_ACTIVATE_ERR_EID
#define CFE_TBL_ACTIVATE_ERR_EID           70
#define CFE_TBL_ACTIVATE_DUMP_ONLY_ERR_EID 78
#define CFE_TBL_UNVALIDATED_ERR_EID        81
#endif
// cfe_tbl_loadbuff.c's own file-scope constants
#define CFE_TBL_LOADBUFF_SHARED_CATEGORY      0
#define CFE_TBL_LOADBUFF_LOCAL_CATEGORY_START 1
#define CFE_TBL_MAX_BUFFS_PER_REG             2 // double buffering is the current max
#define CFE_TBL_TOTAL_REG_BUFFS  (CFE_PLATFORM_TBL_MAX_NUM_TABLES * CFE_TBL_MAX_BUFFS_PER_REG)
#define CFE_TBL_TOTAL_LOAD_BUFFS (CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS + CFE_TBL_TOTAL_REG_BUFFS)

// --- FORWARD DECLARATIONS ACROSS THE PAIR -------------------------------------------------
// cfe_tbl_loadbuff.c and cfe_tbl_regrec.c call each other -- that mutual recursion is exactly
// why module_deps.py says they must be gated together. In C each includes the other's header;
// HolyC has no headers, so the seven names this file needs from cfe_tbl_regrec.HC are declared
// here and defined there. Only ORDINARY CALLS cross the boundary in this direction: neither
// file takes the ADDRESS of a function in the other, which is what would force a definition
// rather than a declaration (docs/HOLYC_STRUCT_LIMITS.md, and the ordering swap in
// cfe_tbl_accdesc.HC).
CFE_TBL_TableConfig_t *CFE_TBL_RegRecGetConfig(CFE_TBL_RegistryRec_t *RegRecPtr);
U32 CFE_TBL_RegRecGetID(CFE_TBL_RegistryRec_t *RegRecPtr);
Bool CFE_TBL_RegRecIsMatch(CFE_TBL_RegistryRec_t *RegRecPtr, U32 RegId);
I32 CFE_TBL_RegId_ToIndex(U32 RegId, U32 *Idx);
CFE_TBL_RegistryRec_t *CFE_TBL_LocateRegRecByID(U32 RegId);
CFE_TBL_LoadBuff_t *CFE_TBL_GetActiveBuffer(CFE_TBL_RegistryRec_t *RegRecPtr);
CFE_TBL_LoadBuff_t *CFE_TBL_GetInactiveBufferExclusive(CFE_TBL_RegistryRec_t *RegRecPtr);
CFE_TBL_LoadBuff_t *CFE_TBL_GetLoadInProgressBuffer(CFE_TBL_RegistryRec_t *RegRecPtr);
// ...and the two stand-ins, from sources still inside the cycle. Defined in the driver.
CFE_TBL_LoadBuff_t *CFE_TBL_AcquireGlobalLoadBuff(U32 PendingOwnerId);
U0 CFE_TBL_TxnAddEvent(CFE_TBL_TxnState_t *Txn, U16 EventId, I32 EventData1, I32 EventData2);
U0 CFE_TBL_SendTransactionEvents(CFE_TBL_TxnState_t *Txn, U8 *Operation,
                                 Bool (*EventProc)(CFE_TBL_TxnEvent_t *,
                                                   CFE_TBL_TxnEventContext_t *),
                                 U8 *OperationData);

/*----------------------------------------------------------------
 *
 * Local helper function - not used outside of this unit
 * Decomposes a table buffer serial number into its index and category value
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_LoadBuffSerialDecompose(U32 Serial, U32 *CategoryOut, U32 *IdxOut)
{
  U32 Idx;
  Idx = Serial % CFE_TBL_TOTAL_LOAD_BUFFS;
  if (Idx < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS) {
    /* It is one of the global/shared load buffs */
    if (CategoryOut != NULL)
      *CategoryOut = CFE_TBL_LOADBUFF_SHARED_CATEGORY;
    if (IdxOut != NULL)
      *IdxOut = Idx;
  } else {
    /* It is one of the local per-registry buffers */
    Idx -= CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS;
    if (CategoryOut != NULL)
      *CategoryOut = CFE_TBL_LOADBUFF_LOCAL_CATEGORY_START + Idx / CFE_TBL_MAX_BUFFS_PER_REG;
    if (IdxOut != NULL)
      *IdxOut = Idx % CFE_TBL_MAX_BUFFS_PER_REG;
  }
}

/*----------------------------------------------------------------
 *
 * Local helper function - not used outside of this unit
 * Composes a serial serial number from an index and category value
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_LoadBuffSerialCompose(U32 *SerialInOut, U32 ReqCategory, U32 ReqIdx)
{
  U32 Serial;
  Serial = *SerialInOut;
  // ROUND UP to the next multiple of TOTAL_LOAD_BUFFS. This is what makes Compose "the next
  // serial at or after this one in the category I want" rather than the inverse of Decompose.
  Serial += CFE_TBL_TOTAL_LOAD_BUFFS - 1;
  Serial -= Serial % CFE_TBL_TOTAL_LOAD_BUFFS;
  if (ReqCategory >= CFE_TBL_LOADBUFF_LOCAL_CATEGORY_START) {
    /* It is one of the local per-registry buffers */
    Serial += CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS;
    Serial += (ReqCategory - CFE_TBL_LOADBUFF_LOCAL_CATEGORY_START) * CFE_TBL_MAX_BUFFS_PER_REG;
  }
  Serial += ReqIdx;
  *SerialInOut = Serial;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_LoadBuffId_ToIndex(U32 BuffId, U32 *Category, U32 *Idx)
{
  U32 Serial;
  I32 Status;
  Serial = CFE_ResourceId_ToInteger(BuffId);
  Serial -= CFE_TBL_LOADBUFFID_BASE;
  if (Serial <= CFE_RESOURCEID_MAX) {
    CFE_TBL_LoadBuffSerialDecompose(Serial, Category, Idx);
    Status = CFE_SUCCESS;
  } else {
    /* The ID value passed in is not valid */
    Status = CFE_TBL_ERR_INVALID_HANDLE;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_LoadBuff_t *CFE_TBL_LocateLoadBufferByID(U32 BufferId)
{
  CFE_TBL_LoadBuff_t *BuffPtr;
  CFE_TBL_RegistryRec_t *ParentRegRecPtr;
  // LIMIT 17: `fn(a)->member` resolves the arrow against the FIRST ARGUMENT's class, not the
  // return type, and the compiler refuses. Every CFE_TBL_RegRecGetConfig(x)->field in this
  // file is hoisted to a local for that reason -- four of them.
  CFE_TBL_TableConfig_t *ParentCfgPtr;
  U32 Idx;
  U32 Serial;
  U32 Category;
  Serial = CFE_ResourceId_ToInteger(BufferId);
  Serial -= CFE_TBL_LOADBUFFID_BASE;
  if (Serial <= CFE_RESOURCEID_MAX) {
    CFE_TBL_LoadBuffSerialDecompose(Serial, &Category, &Idx);
    /* Check if it refers to a shared load buffer or a dedicated table buffer */
    if (Category == CFE_TBL_LOADBUFF_SHARED_CATEGORY) {
      /* It refers to one of the shared/global load buffs */
      BuffPtr = &CFE_TBL_Global.LoadBuffs[Idx];
      ParentRegRecPtr = NULL;
    } else {
      /* It refers to one of the table buffs in the registry */
      /* There are (possibly) two buffers per registry entry */
      Category -= CFE_TBL_LOADBUFF_LOCAL_CATEGORY_START;
      ParentRegRecPtr = &CFE_TBL_Global.Registry[Category];
      ParentCfgPtr = CFE_TBL_RegRecGetConfig(ParentRegRecPtr);
      if (!ParentCfgPtr->DoubleBuffered) {
        /* single-buffered table is always at local index 0 */
        Idx = 0;
      }
      BuffPtr = &ParentRegRecPtr->Buffers[Idx];
    }
  } else {
    BuffPtr = NULL;
  }
  // ParentRegRecPtr IS ASSIGNED AND NEVER READ -- in NASA's source too. It is set on both
  // branches and then unused; kept because this is a 1:1 translation and removing it would be
  // a change. `no_warn` is how HolyC says so out loud.
  no_warn ParentRegRecPtr;
  return BuffPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_CheckLoadBuffSlotUsed(U32 CheckId)
{
  CFE_TBL_LoadBuff_t *BuffPtr;
  /*
  ** Note - The pointer here should never be NULL because the ID should always be
  ** within the expected range, but if it ever is NULL, this should return true
  ** such that the caller will _not_ attempt to use the record.
  */
  BuffPtr = CFE_TBL_LocateLoadBufferByID(CheckId);
  return BuffPtr == NULL || CFE_TBL_LoadBuffIsUsed(BuffPtr);
}

U32 CFE_TBL_LoadBuffIncrementSerial_Impl(U32 InSerial, U32 ReqCategory)
{
  U32 OutSerial;
  U32 ActualCategory;
  U32 Idx;
  OutSerial = InSerial + 1;
  CFE_TBL_LoadBuffSerialDecompose(OutSerial, &ActualCategory, &Idx);
  /* This must restrict itself to buffers in the same category */
  if (ActualCategory != ReqCategory)
    CFE_TBL_LoadBuffSerialCompose(&OutSerial, ReqCategory, Idx);
  if (OutSerial >= CFE_RESOURCEID_MAX) {
    /* note this does not change the actual index being referred to */
    OutSerial %= CFE_TBL_TOTAL_LOAD_BUFFS;
  }
  return OutSerial;
}

U32 CFE_TBL_LoadBuffIncrementSerial(U32 Id, U8 *Arg)
{
  CFE_TBL_LoadBuffFindNextState_t *State = Arg;
  U32 Result;
  U32 NextSerial;
  if (State->RemainingCount == 0) {
    Result = CFE_RESOURCEID_UNDEFINED;
  } else {
    --State->RemainingCount;
    NextSerial = CFE_TBL_LoadBuffIncrementSerial_Impl(CFE_ResourceId_GetSerial(Id),
                                                      State->BaseCategory);
    Result = CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + NextSerial);
  }
  return Result;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U32 CFE_TBL_FindNextSharedBufferId()
{
  CFE_TBL_LoadBuffFindNextState_t State;
  U32 PendingId;
  MemSet(&State, 0, sizeof(CFE_TBL_LoadBuffFindNextState_t));
  State.BaseCategory = CFE_TBL_LOADBUFF_SHARED_CATEGORY;
  State.RemainingCount = CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS;
  PendingId = CFE_ResourceId_FindNextEx(CFE_TBL_Global.LastLoadBuffId,
                                        &CFE_TBL_LoadBuffIncrementSerial, &State,
                                        &CFE_TBL_CheckLoadBuffSlotUsed);
  return PendingId;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_LoadBuffClearData(CFE_TBL_LoadBuff_t *BufferPtr)
{
  U8 *DestPtr = CFE_TBL_LoadBuffGetWritePointer(BufferPtr);
  if (DestPtr != NULL)
    MemSet(DestPtr, 0, CFE_TBL_LoadBuffGetAllocSize(BufferPtr));
  CFE_TBL_LoadBuffSetContentSize(BufferPtr, 0);
  BufferPtr->Crc = 0; /* Just in case the CRC of old data had been calculated */
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_LoadBuffCopyData(CFE_TBL_LoadBuff_t *BufferPtr, U8 *SourcePtr, I64 SourceSize)
{
  // THE SIZE CHECK IS THE SAFETY PROPERTY. GetWritePointer is NULL for an app-owned buffer,
  // and a source larger than the allocation is silently refused rather than truncated -- the
  // caller finds out by the ContentSize not having changed.
  U8 *DestPtr = CFE_TBL_LoadBuffGetWritePointer(BufferPtr);
  if (DestPtr != NULL && SourceSize <= CFE_TBL_LoadBuffGetAllocSize(BufferPtr)) {
    MemCpy(DestPtr, SourcePtr, SourceSize);
    CFE_TBL_LoadBuffSetContentSize(BufferPtr, SourceSize);
    BufferPtr->Crc = 0; /* Just in case the CRC of old data had been calculated */
  }
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_LoadBuffRecomputeCRC(CFE_TBL_LoadBuff_t *BufferPtr)
{
  BufferPtr->Crc = CFE_ES_CalculateCRC(CFE_TBL_LoadBuffGetReadPointer(BufferPtr),
                                       CFE_TBL_LoadBuffGetContentSize(BufferPtr), 0,
                                       CFE_MISSION_ES_DEFAULT_CRC);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U32 CFE_TBL_GetNextLocalBufferId(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  U32 PendingId;
  U32 Serial;
  U32 Idx;
  // THE TABLE'S OWN INDEX IS THE CATEGORY. A table's dedicated pair lives at category
  // index+1, so "the next local buffer for THIS table" is an increment confined to that
  // category -- which is exactly what IncrementSerial_Impl's compose branch does.
  if (CFE_TBL_RegId_ToIndex(CFE_TBL_RegRecGetID(RegRecPtr), &Idx) != CFE_SUCCESS) {
    PendingId = CFE_RESOURCEID_UNDEFINED;
  } else {
    if (CFE_TBL_LOADBUFFID_IS_VALID(RegRecPtr->Status.ActiveBufferId)) {
      PendingId = RegRecPtr->Status.ActiveBufferId;
      Serial = CFE_ResourceId_GetSerial(PendingId);
    } else {
      Serial = 0;
    }
    Serial = CFE_TBL_LoadBuffIncrementSerial_Impl(Serial,
                                                  CFE_TBL_LOADBUFF_LOCAL_CATEGORY_START + Idx);
    PendingId = CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE + Serial);
  }
  return PendingId;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_RegistryRec_t *CFE_TBL_LoadBuffGetRegRecFromId(U32 BuffId)
{
  CFE_TBL_LoadBuff_t *BuffPtr;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  BuffPtr = CFE_TBL_LocateLoadBufferByID(BuffId);
  if (!CFE_TBL_LoadBuffIsMatch(BuffPtr, BuffId)) {
    /* Buff ID is not valid */
    RegRecPtr = NULL;
  } else {
    RegRecPtr = CFE_TBL_LocateRegRecByID(BuffPtr->OwnerRegId);
    if (!CFE_TBL_RegRecIsMatch(RegRecPtr, BuffPtr->OwnerRegId)) {
      /* owner is gone ... Buffer may be stale? */
      RegRecPtr = NULL;
    }
  }
  return RegRecPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_LoadBuffIdToTlmIndex(U32 BufferId)
{
  I32 ResultIdx;
  U32 LocalIdx;
  U32 CategoryIdx;
  /*
  ** First try to interpret the ID as a shared load buffer.
  ** This relies on the internal range-checking; this will fail if the ID is not actually a
  ** shared load buffer
  */
  if (CFE_TBL_LoadBuffId_ToIndex(BufferId, &CategoryIdx, &LocalIdx) != CFE_SUCCESS) {
    /* This is for backward compatibility, where -1 meant "none" */
    ResultIdx = -1;
  } else {
    ResultIdx = LocalIdx;
    /* global load buffs (category 0) can be reported direct, but local bufs need translating */
    if (CategoryIdx != 0) {
      /* This is historical: negative numbers meant local table buffers on a double-buffered
      ** table */
      /* -3 is the first buffer (idx 0) and -2 is the second buffer (idx 1) */
      ResultIdx -= 3;
    }
  }
  return ResultIdx;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_LoadBuff_t *CFE_TBL_PrepareNewLoadBuff(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  CFE_TBL_LoadBuff_t *LoadBuffPtr;
  CFE_TBL_LoadBuff_t *ActiveBuffPtr;
  CFE_TBL_TableConfig_t *CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr); // limit 17
  if (CfgPtr->DoubleBuffered) {
    /* If the table is a double buffered table, then check to make sure the */
    /* inactive buffer has been freed by any Applications that may have been using it */
    LoadBuffPtr = CFE_TBL_GetInactiveBufferExclusive(RegRecPtr);
  } else {
    /* Single Buffered Table, these use a pool of shared temporary load buffers */
    LoadBuffPtr = CFE_TBL_AcquireGlobalLoadBuff(CFE_TBL_RegRecGetID(RegRecPtr));
  }
  if (LoadBuffPtr != NULL) {
    /* In case the file contains a partial table load, get the active buffer contents first */
    ActiveBuffPtr = CFE_TBL_GetActiveBuffer(RegRecPtr);
    /* NOTE: The Active Buffer pointer will be NULL if the table was never loaded */
    if (ActiveBuffPtr != NULL) {
      CFE_TBL_LoadBuffCopyData(LoadBuffPtr, CFE_TBL_LoadBuffGetReadPointer(ActiveBuffPtr),
                               CFE_TBL_LoadBuffGetContentSize(ActiveBuffPtr));
    }
    /* Always consider the copied buffer as unvalidated for now */
    LoadBuffPtr->IsValid = FALSE;
    LoadBuffPtr->ActivateReq = FALSE;
  }
  return LoadBuffPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_LoadBuffIsPrivate(U32 BuffId, U32 RegId)
{
  U32 Category;
  U32 BuffIdx;
  U32 RegIdx;
  Bool Result;
  Result = FALSE;
  if (CFE_TBL_LoadBuffId_ToIndex(BuffId, &Category, &BuffIdx) == CFE_SUCCESS &&
      CFE_TBL_RegId_ToIndex(RegId, &RegIdx) == CFE_SUCCESS) {
    /* 0 is the shared category, otherwise it is the reg index w/offset */
    Result = RegIdx + CFE_TBL_LOADBUFF_LOCAL_CATEGORY_START == Category;
  }
  return Result;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_LoadBuffIsShared(U32 BuffId)
{
  U32 Category;
  U32 Idx;
  Bool Result;
  Result = FALSE;
  if (CFE_TBL_LoadBuffId_ToIndex(BuffId, &Category, &Idx) == CFE_SUCCESS) {
    /* 0 is the shared category, otherwise it is the (1-based) reg index */
    Result = Category == CFE_TBL_LOADBUFF_SHARED_CATEGORY;
  }
  return Result;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_LoadBuff_t *CFE_TBL_TxnSetupActivationRequest(CFE_TBL_TxnState_t *Txn)
{
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *BufferPtr;
  CFE_TBL_TableConfig_t *CfgPtr;
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr); // limit 17
  if (CfgPtr->DumpOnly) {
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_ACTIVATE_DUMP_ONLY_ERR_EID, 0, 0);
    BufferPtr = NULL;
  } else {
    /* This only ever applies to the load in progress, one does not activate the previous
    ** buffer */
    BufferPtr = CFE_TBL_GetLoadInProgressBuffer(RegRecPtr);
    if (BufferPtr == NULL) {
      CFE_TBL_TxnAddEvent(Txn, CFE_TBL_ACTIVATE_ERR_EID, 0, 0);
    } else if (!BufferPtr->IsValid) {
      CFE_TBL_TxnAddEvent(Txn, CFE_TBL_UNVALIDATED_ERR_EID, 0, 0);
      BufferPtr = NULL;
    } else {
      /* Set the buffer as pending activation */
      BufferPtr->ActivateReq = TRUE;
    }
  }
  return BufferPtr;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_SendActivationEventHelper(CFE_TBL_TxnEvent_t *Event, CFE_TBL_TxnEventContext_t *Ctxt)
{
  U16 EventType;
  U8 EventString[CFE_MISSION_EVS_MAX_MESSAGE_LENGTH];
  /* The majority of the events are errors, but this can be reset later to demote to info/debug */
  EventType = CFE_EVS_EventType_ERROR;
  EventString[0] = 0;
  switch (Event->EventId) {
    case CFE_TBL_ACTIVATE_DUMP_ONLY_ERR_EID:
      StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH,
                "Illegal attempt to activate dump-only table");
      break;
    case CFE_TBL_ACTIVATE_ERR_EID:
      StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH,
                "Cannot activate table, No Inactive image available");
      break;
    case CFE_TBL_UNVALIDATED_ERR_EID:
      StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH,
                "Cannot activate table, Inactive image not Validated");
      break;
  }
  // AN EVENT ID THIS HELPER DOES NOT KNOW RETURNS FALSE rather than sending a blank message,
  // and the caller's event loop uses that to pass the event to the next helper. The empty
  // string IS the "not mine" signal.
  if (EventString[0] == 0)
    return FALSE;
  /* Finally send the actual event by appending all the info we have */
  CFE_EVS_SendEventWithAppID(Event->EventId, EventType, CFE_TBL_Global.TableTaskAppId,
                             "%s,app=%s,tbl=%s:%s", Ctxt->Operation, Ctxt->CallerName,
                             Ctxt->TableName, EventString);
  return TRUE;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_SendActivationEvents(CFE_TBL_TxnState_t *Txn)
{
  CFE_TBL_SendTransactionEvents(Txn, "Activate", &CFE_TBL_SendActivationEventHelper, NULL);
}
#endif
