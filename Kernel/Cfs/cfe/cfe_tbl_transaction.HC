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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_transaction.c -- WHO IS ALLOWED TO
// DO THIS, AND WHAT GETS SAID ABOUT IT AFTERWARDS. The type and its eight one-line accessors
// are in cfe_tbl_transaction_decl.HC, which landed earlier.
//
// EVERY PUBLIC CFE_TBL_* CALL RUNS INSIDE ONE. A transaction is started from a table NAME or
// from a HANDLE, it resolves the caller and the table, it takes the registry lock, and it
// collects EVENTS to send once the lock is released. CFE_TBL_TxnFinish drops the lock.
//
// THE ACCESS MODEL IS FOUR BITS AND ONE COMPARISON. CallContext accumulates what the caller
// IS -- TABLE_SERVICES, OWNER_APP, ACCESSOR_APP -- and the caller passes AllowedContext for
// what the operation REQUIRES. The test is
//
//     if ((AccessAllowed & AllowedContext) != AllowedContext)
//
// which is "every required bit is present", not "any". Table Services itself is the root user:
// `AccessAllowed |= ~AccessAllowed` sets every bit, so it passes any requirement. Note what
// that means -- the check is on the UNION of what you are, so an app that both owns a table
// and holds an accessor satisfies a requirement for either.
//
// AND EVENTS ARE COLLECTED, NEVER SENT UNDER THE LOCK. That is the design the whole file is
// shaped around: an operation decides what to report while holding the registry, and
// CFE_TBL_SendTransactionEvents renders them afterwards. CFE_TBL_TxnAppNameCaller enforces it
// -- if asked for the caller's name while the registry is still locked it returns the literal
// "[!LOCKED!]" rather than calling CFE_ES_GetAppName, with NASA's comment saying that string
// appearing in a log IS the bug report: "if this is seen in a log, it is a bug in the caller
// that should be fixed".
//
// NumPendingEvents COUNTS PAST THE LIMIT on purpose -- NASA: "this always increments the
// number of pending events, to make it evident if there was an overflow" -- and
// TxnProcessEvents clamps back to the limit before walking, so an overflowing transaction
// reports its first eight and the count still says there were more.
#ifndef CFE_TBL_TRANSACTION_HC
#define CFE_TBL_TRANSACTION_HC
// cfe_tbl_transaction.h's context enum
#ifndef CFE_TBL_TxnContext_UNDEFINED
#define CFE_TBL_TxnContext_UNDEFINED      0
#define CFE_TBL_TxnContext_TABLE_SERVICES 0x1
#define CFE_TBL_TxnContext_OWNER_APP      0x2
#define CFE_TBL_TxnContext_ACCESSOR_APP   0x4
#define CFE_TBL_TxnContext_OTHER_APP      0x8
#define CFE_TBL_TxnContext_ALL            0x0F
#endif
// cfe_tbl_eventids.h
#ifndef CFE_TBL_NO_SUCH_TABLE_ERR_EID
#define CFE_TBL_NO_SUCH_TABLE_ERR_EID 57
#define CFE_TBL_HANDLE_ACCESS_ERR_EID 103
#endif
// cfe_error.h
#ifndef CFE_TBL_ERR_UNREGISTERED
#define CFE_TBL_ERR_UNREGISTERED 0xCC000009
#define CFE_TBL_ERR_NO_ACCESS    0xCC000008
#define CFE_TBL_ERR_NEVER_LOADED 0xCC000005
#define CFE_TBL_ERR_INVALID_NAME 0xCC000002
#define CFE_TBL_INFO_UPDATED     0x4C00000E
#endif

// --- FORWARD DECLARATIONS ------------------------------------------------------------------
// CFE_TBL_TxnFinish is called by both Start functions and defined after them, as in NASA's
// source where cfe_tbl_transaction.h supplies the declaration. And CFE_TBL_TxnFindRegByName
// lives in cfe_tbl_registry.c, which is still inside the cycle; the driver defines it
// faithfully, because its body is twenty lines that call only gated code.
U0 CFE_TBL_TxnFinish(CFE_TBL_TxnState_t *Txn);
I32 CFE_TBL_TxnFindRegByName(CFE_TBL_TxnState_t *Txn, U8 *TblName);
// ...and from cfe_tbl_accdesc.c, which the driver includes AFTER this file because its own
// allocator needs the transaction type. Ordinary calls, so declarations suffice.
CFE_TBL_AccessDescriptor_t *CFE_TBL_LocateAccDescByHandle(U32 TblHandle);
Bool CFE_TBL_AccDescIsMatch(CFE_TBL_AccessDescriptor_t *AccDescPtr, U32 TblHandle);
Bool CFE_TBL_AccDescIsUsed(CFE_TBL_AccessDescriptor_t *AccDescPtr);
U32 CFE_TBL_AccDescGetHandle(CFE_TBL_AccessDescriptor_t *AccDescPtr);
// ...and the two still-stubbed registry lock calls, plus the list walk.
U0 CFE_TBL_TxnLockRegistry(CFE_TBL_TxnState_t *Txn);
U0 CFE_TBL_TxnUnlockRegistry(CFE_TBL_TxnState_t *Txn);
U0 CFE_TBL_ForeachAccessDescriptor(CFE_TBL_RegistryRec_t *RegRecPtr,
                                   U0 (*Func)(CFE_TBL_AccessDescriptor_t *, U8 *), U8 *Arg);

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnInit(CFE_TBL_TxnState_t *Txn, Bool CheckContext)
{
  I32 Status;
  MemSet(Txn, 0, sizeof(CFE_TBL_TxnState_t));
  /* NOTE: handle and regid are automatically made safe via memset() above */
  /* Check to make sure App ID is legit */
  if (CheckContext)
    Status = CFE_ES_GetAppID(&Txn->AppId);
  else
    Status = CFE_SUCCESS;
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U8 *CFE_TBL_TxnAppNameCaller(CFE_TBL_TxnState_t *Txn)
{
  U8 *Result;
  Result = Txn->AppNameBuffer;
  if (Txn->AppNameBuffer[0] == 0) {
    /*
    ** This should not attempt to get the name while the reg is locked.
    ** The typical things that need the name are for purposes like syslog or
    ** event sending, and these should only be done after unlocking the reg.
    */
    if (Txn->RegLockCount != 0) {
      /* If this is seen in a log, it is a bug in the caller that should be fixed */
      Result = "[!LOCKED!]";
    } else {
      CFE_ES_GetAppName(Txn->AppNameBuffer, Txn->AppId, CFE_MISSION_MAX_API_LEN);
    }
  }
  return Result;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnStartFromName(CFE_TBL_TxnState_t *Txn, U8 *TblName, U32 AllowedContext)
{
  I32 Status;
  Status = CFE_TBL_TxnInit(Txn, AllowedContext != CFE_TBL_TxnContext_UNDEFINED);
  if (Status == CFE_SUCCESS) {
    CFE_TBL_TxnLockRegistry(Txn);
    Status = CFE_TBL_TxnFindRegByName(Txn, TblName);
  }
  if (Status != CFE_SUCCESS) {
    /* If returning with an error, should also unlock the registry */
    CFE_TBL_TxnFinish(Txn);
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnStartFromHandle(CFE_TBL_TxnState_t *Txn, U32 TblHandle, U32 AllowedContext)
{
  I32 Status;
  U32 AccessAllowed;
  CFE_TBL_AccessDescriptor_t *AccDescPtr;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  AccessAllowed = 0;
  /* Sanity check on handle -- This avoids locking the registry for lookups that will certainly
  ** fail */
  if (!CFE_ResourceId_IsDefined(TblHandle)) {
    Status = CFE_TBL_ERR_INVALID_HANDLE;
  } else {
    Status = CFE_TBL_TxnInit(Txn, AllowedContext != CFE_TBL_TxnContext_UNDEFINED);
  }
  if (Status == CFE_SUCCESS) {
    Txn->Handle = TblHandle;
    /*
    ** Check if the caller is actually table services
    ** (this is like the "root user" - most/all actions allowed)
    */
    if (CFE_ResourceId_Equal(Txn->AppId, CFE_TBL_Global.TableTaskAppId)) {
      Txn->CallContext |= CFE_TBL_TxnContext_TABLE_SERVICES;
      AccessAllowed |= ~AccessAllowed; /* Set all bits */
    }
    /* Need to lock before actually looking at the descriptor */
    CFE_TBL_TxnLockRegistry(Txn);
    Txn->AccDescPtr = CFE_TBL_LocateAccDescByHandle(TblHandle);
    if (!CFE_TBL_AccDescIsMatch(Txn->AccDescPtr, TblHandle)) {
      /* Access descriptor is not good */
      Status = CFE_TBL_ERR_INVALID_HANDLE;
      CFE_TBL_TxnAddEvent(Txn, CFE_TBL_NO_SUCH_TABLE_ERR_EID, Status, 0);
    } else {
      /* Access descriptor is good - check if caller is the descriptor owner */
      AccDescPtr = Txn->AccDescPtr;
      if (CFE_ResourceId_Equal(Txn->AppId, AccDescPtr->AppId)) {
        /* The calling app owns this access descriptor */
        Txn->CallContext |= CFE_TBL_TxnContext_ACCESSOR_APP;
      }
      /* Now check the underlying registry entry */
      Txn->RegId = AccDescPtr->RegIndex;
      Txn->RegRecPtr = CFE_TBL_LocateRegRecByID(AccDescPtr->RegIndex);
      if (!CFE_TBL_RegRecIsMatch(Txn->RegRecPtr, AccDescPtr->RegIndex)) {
        /* This means the access descriptor is stale */
        Status = CFE_TBL_ERR_UNREGISTERED;
      } else {
        /* The registry record is good, check if the caller is the owner */
        RegRecPtr = Txn->RegRecPtr;
        if (CFE_ResourceId_Equal(Txn->AppId, RegRecPtr->OwnerAppId)) {
          /* The calling app owns this registry entry */
          Txn->CallContext |= CFE_TBL_TxnContext_OWNER_APP;
        }
      }
    }
    /* If the descriptors all checked out, now check the calling context is whats required */
    if (Status == CFE_SUCCESS) {
      AccessAllowed |= Txn->CallContext;
      // EVERY REQUIRED BIT, not any: the operation names what it needs and the caller must be
      // all of it. Table Services set every bit above, so it passes anything.
      if ((AccessAllowed & AllowedContext) != AllowedContext) {
        Status = CFE_TBL_ERR_NO_ACCESS;
        CFE_TBL_TxnAddEvent(Txn, CFE_TBL_HANDLE_ACCESS_ERR_EID, Status, AccessAllowed);
      }
    }
    if (Status != CFE_SUCCESS) {
      /* If returning with an error, should also unlock the registry */
      CFE_TBL_TxnFinish(Txn);
    }
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_TxnFinish(CFE_TBL_TxnState_t *Txn)
{
  if (Txn->RegLockCount != 0) {
    /* If returning with an error, must also unlock the registry */
    CFE_TBL_TxnUnlockRegistry(Txn);
    Txn->RegLockCount = 0;
  }
}

/*----------------------------------------------------------------
 *
 * Local helper function, not invoked outside this unit
 * Intended to be used with CFE_TBL_ForeachAccessDescriptor()
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_FindAccessDescHelper(CFE_TBL_AccessDescriptor_t *AccDescPtr, U8 *Arg)
{
  CFE_TBL_TxnState_t *Txn = Arg;
  /* Note that the only entries in the list will be, by definition, access descriptors that
   * point at this regrec entry.  So checking that AccDescPtr->RegIndex matches the transaction
   * subject RegId would result in an uncovered branch, it cannot be false unless the list gets
   * corrupted somehow. */
  if (CFE_TBL_AccDescIsUsed(AccDescPtr) &&
      CFE_ResourceId_Equal(AccDescPtr->AppId, CFE_TBL_TxnAppId(Txn))) {
    Txn->Handle = CFE_TBL_AccDescGetHandle(AccDescPtr);
    Txn->AccDescPtr = AccDescPtr;
  }
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_FindAccessDescriptorForSelf(CFE_TBL_TxnState_t *Txn)
{
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  /* Find the existing access descriptor for the table       */
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  CFE_TBL_ForeachAccessDescriptor(RegRecPtr, &CFE_TBL_FindAccessDescHelper, Txn);
  if (Txn->AccDescPtr == NULL)
    Status = CFE_TBL_ERR_UNREGISTERED;
  else
    Status = CFE_SUCCESS;
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnGetNextNotification(CFE_TBL_TxnState_t *Txn)
{
  I32 Status = CFE_SUCCESS;
  CFE_TBL_AccessDescriptor_t *AccDescPtr = CFE_TBL_TxnAccDesc(Txn);
  CFE_TBL_RegistryRec_t *RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  if (!CFE_TBL_RegRecIsTableLoaded(RegRecPtr)) {
    /* If the table has never been loaded, return an error code for the address */
    Status = CFE_TBL_ERR_NEVER_LOADED;
  } else if (AccDescPtr->Updated) {
    /* If the table has been updated recently, return the update status */
    Status = CFE_TBL_INFO_UPDATED;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_TxnAddEvent(CFE_TBL_TxnState_t *Txn, U16 EventId, I32 EventData1, I32 EventData2)
{
  CFE_TBL_TxnEvent_t *EvPtr;
  if (Txn->NumPendingEvents < CFE_TBL_MAX_EVENTS_PER_TXN) {
    EvPtr = &Txn->PendingEvents[Txn->NumPendingEvents];
    EvPtr->EventId = EventId;
    EvPtr->EventData1 = EventData1;
    EvPtr->EventData2 = EventData2;
  }
  /* This always increments the number of pending events, to make it evident if there was an
  ** overflow */
  ++Txn->NumPendingEvents;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U32 CFE_TBL_TxnGetEventCount(CFE_TBL_TxnState_t *Txn)
{
  return Txn->NumPendingEvents;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U32 CFE_TBL_TxnProcessEvents(CFE_TBL_TxnState_t *Txn,
                             Bool (*EventProc)(CFE_TBL_TxnEvent_t *, CFE_TBL_TxnEventContext_t *),
                             CFE_TBL_TxnEventContext_t *Ctxt)
{
  U32 i;
  U32 NumPending;
  U32 NumProc;
  NumPending = CFE_TBL_TxnGetEventCount(Txn);
  NumProc = 0;
  if (NumPending > CFE_TBL_MAX_EVENTS_PER_TXN) {
    /* this means there was an overflow */
    NumPending = CFE_TBL_MAX_EVENTS_PER_TXN;
  }
  /* Events should be processed in the same order that CFE_TBL_TxnAddEvent() was called */
  for (i = 0; i < NumPending; ++i) {
    if (EventProc(&Txn->PendingEvents[i], Ctxt))
      ++NumProc;
  }
  return NumProc;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_TxnClearEvents(CFE_TBL_TxnState_t *Txn)
{
  Txn->NumPendingEvents = 0;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_SendTransactionEvents(CFE_TBL_TxnState_t *Txn, U8 *Operation,
                                 Bool (*EventProc)(CFE_TBL_TxnEvent_t *,
                                                   CFE_TBL_TxnEventContext_t *),
                                 U8 *OperationData)
{
  CFE_TBL_TxnEventContext_t Ctxt;
  MemSet(&Ctxt, 0, sizeof(CFE_TBL_TxnEventContext_t));
  Ctxt.Operation = Operation;
  Ctxt.OperationDataPtr = OperationData;
  Ctxt.CallerName = CFE_TBL_TxnAppNameCaller(Txn);
  Ctxt.RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  if (Ctxt.RegRecPtr != NULL) {
    Ctxt.TableName = CFE_TBL_RegRecGetName(Ctxt.RegRecPtr);
  } else {
    /* do not leave it null/blank */
    Ctxt.TableName = "[unknown]";
  }
  CFE_TBL_TxnProcessEvents(Txn, EventProc, &Ctxt);
  CFE_TBL_TxnClearEvents(Txn);
}
#endif
