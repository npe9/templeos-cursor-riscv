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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_registry.c -- THE ELEVEN
// TRANSACTION STEPS THAT TOUCH THE REGISTRY. Everything here takes a CFE_TBL_TxnState_t and
// nothing here sends an event directly: that is the division cfe_tbl_transaction.c sets up and
// this file is the half that reaches into CFE_TBL_Global.Registry under the lock.
//
// THE LOCK IS COUNTED, AND THAT IS WHAT MAKES IT RE-ENTRANT. CFE_TBL_TxnLockRegistry takes the
// real mutex only on the transition from zero, and Unlock gives it only on the return to zero,
// so a step that locks can safely call another step that locks. CFE_TBL_TxnAllocateRegistryEntry
// does exactly that, and CFE_TBL_TxnCheckDuplicateRegistration calls it from inside its own
// logic. Without the count the second take would deadlock.
//
// THE THREE WAYS A DUPLICATE REGISTRATION ENDS, which is the most interesting thing in the
// file. Register a name that already exists and the answer depends on WHO owns it and WHETHER
// the size matches:
//
//   another app owns it           CFE_TBL_ERR_DUPLICATE_NOT_OWNED  -- refused
//   you own it, different size    CFE_TBL_ERR_DUPLICATE_DIFF_SIZE  -- refused, and NASA's own
//                                 comment says why: the old table is probably shared and
//                                 probably still being read, so "someone else will need to
//                                 clean up this mess"
//   you own it, same size         CFE_TBL_WARN_DUPLICATE           -- ACCEPTED, re-using the
//                                 existing buffers and handing back the existing handle
//
// So re-registering your own table at the same size is a supported no-op, not an error, and
// that is the only path that returns a warning rather than a status.
//
// AND THE LAST ACCESSOR OUT FREES THE TABLE. CFE_TBL_TxnRemoveAccessLink unlinks one
// descriptor, and then asks whether the registry record now has NO owner and NO remaining
// access links -- if so it discards the working buffer, deallocates the table's own buffers and
// returns the record to the pool. Note the order of the two tests: an unowned table with
// readers still attached is left alone, which is how an app can keep reading a table whose
// owner has already unregistered it.
#ifndef CFE_TBL_REGISTRY_HC
#define CFE_TBL_REGISTRY_HC
#ifndef CFE_TBL_ERR_REGISTRY_FULL
#define CFE_TBL_ERR_REGISTRY_FULL 0xCC000006(I32)
#endif
#ifndef CFE_TBL_ERR_DUPLICATE_DIFF_SIZE
#define CFE_TBL_ERR_DUPLICATE_DIFF_SIZE 0xCC00000C(I32)
#endif
#ifndef CFE_TBL_ERR_DUPLICATE_NOT_OWNED
#define CFE_TBL_ERR_DUPLICATE_NOT_OWNED 0xCC00000D(I32)
#endif
#ifndef CFE_TBL_WARN_DUPLICATE
#define CFE_TBL_WARN_DUPLICATE 0x4C000007
#endif
#ifndef CFE_TBL_INFO_VALIDATION_PENDING
#define CFE_TBL_INFO_VALIDATION_PENDING 0x4C000019
#endif
#ifndef CFE_TBL_INFO_UPDATE_PENDING
#define CFE_TBL_INFO_UPDATE_PENDING 0x4C000004
#endif
#ifndef CFE_TBL_INFO_DUMP_PENDING
#define CFE_TBL_INFO_DUMP_PENDING 0x4C000024
#endif
// cfe_tbl_resource.h spells it CFE_RESOURCEID_TEST_DEFINED, which the translation writes as
// CFE_ResourceId_IsDefined -- the same collapse cfe_tbl_valresult.HC makes for its own id
// space. Guarded on ITS OWN NAME: a group guard keyed on the first of several names is
// all-or-nothing and has silently left two constants undefined before (limit 22's note).
#ifndef CFE_TBL_DUMPCTRLID_IS_VALID
#define CFE_TBL_DUMPCTRLID_IS_VALID(x) CFE_ResourceId_IsDefined(x)
#endif
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_TxnLockRegistry(CFE_TBL_TxnState_t *Txn)
{
  if (Txn->RegLockCount == 0)
    CFE_TBL_LockRegistry();
  ++Txn->RegLockCount;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_TxnUnlockRegistry(CFE_TBL_TxnState_t *Txn)
{
  if (Txn->RegLockCount > 0) {
    --Txn->RegLockCount;
    if (Txn->RegLockCount == 0)
      CFE_TBL_UnlockRegistry();
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnCheckConfig(CFE_TBL_TxnState_t *Txn, CFE_TBL_TableConfig_t *ReqCfg, U8 *BaseName, U16 TblOptionFlags, I64 Size, I32 (*ValidationFuncPtr)(U8 *))
{
  I32 Status;
  /* There is no way to check the validity of this pointer (NULL is OK) */
  ReqCfg->ValidationFuncPtr = ValidationFuncPtr;
  // THE FOUR VALIDATORS IN ORDER, AND THE ORDER IS LOAD-BEARING. Options must be decoded before
  // the size can be checked, because the size limit depends on whether the table was asked to
  // be double-buffered -- which is a field CFE_TBL_ValidateTableOptions writes into this same
  // ReqCfg. Swap the two and a 16 KiB double-buffered table is measured against the
  // single-buffered limit.
  /* Generate the full application-specific table name (this also detects errors) */
  Status = CFE_TBL_ValidateTableName(ReqCfg, BaseName, CFE_TBL_TxnAppNameCaller(Txn));
  if (Status != CFE_SUCCESS) {
    /* Table name failed sanity check */
    CFE_ES_WriteToSysLog("%s: bad table name: '%s' (0x%lx)\n", "CFE_TBL_TxnCheckConfig", BaseName, Status);
  } else {
    /*
     * This initializes all the boolean fields in the Requested Options struct.
     * Note that this stage these are only the _requested_ table options.  They
     * will become the _actual_ table options as they are properly configured later.
     */
    Status = CFE_TBL_ValidateTableOptions(ReqCfg, TblOptionFlags);
    if (Status != CFE_SUCCESS) {
      /* Table cannot be critial/double buffered or must be dump-only and wasn't specified as
       * so */
      CFE_ES_WriteToSysLog("%s: bad TblOptionFlags combination for '%s' (0x%lx)\n", "CFE_TBL_TxnCheckConfig", BaseName, TblOptionFlags);
    } else {
      /* Table size validation depends on whether double buffered was requested */
      Status = CFE_TBL_ValidateTableSize(ReqCfg, Size);
      if (Status != CFE_SUCCESS) {
        CFE_ES_WriteToSysLog("%s: Table '%s' has invalid size (%lu)\n", "CFE_TBL_TxnCheckConfig", BaseName, Size);
      } else {
        Status = CFE_TBL_ValidateCodecConfig(ReqCfg);
      }
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
I32 CFE_TBL_TxnRemoveAccessLink(CFE_TBL_TxnState_t *Txn)
{
  I32 Status = CFE_SUCCESS;
  CFE_TBL_AccessDescriptor_t *AccDescPtr = CFE_TBL_TxnAccDesc(Txn);
  CFE_TBL_RegistryRec_t *RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  CFE_TBL_TableConfig_t *CfgPtr;
  /*
   * NOTE: In all cases where this is invoked, the registry should
   * already be locked under the transaction object
   */
  CFE_TBL_HandleListRemoveLink(RegRecPtr, AccDescPtr);
  // UNOWNED AND UNREAD, IN THAT ORDER. An unowned table with readers still attached is left
  // alone -- that is how an app keeps reading a table whose owner already unregistered it.
  /* If this was the last Access Descriptor for this table, we can free the memory buffers as
   * well */
  if (!CFE_ResourceId_IsDefined(RegRecPtr->OwnerAppId) && !CFE_TBL_HandleLinkIsAttached(&RegRecPtr->AccessList)) {
    // HOISTED, limit 17: `CFE_TBL_RegRecGetConfig(RegRecPtr)->UserDefAddr` resolves the arrow
    // against the FIRST ARGUMENT's class and refuses. The pointer is identical.
    CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr);
    /* Only free memory that we have allocated.  If the image is User Defined, then don't
     * bother */
    if (!CfgPtr->UserDefAddr) {
      /* If there was a working buffer, release it.  This does nothing if there was no
       * working/load buffer. */
      CFE_TBL_DiscardWorkingBuffer(RegRecPtr);
      /* Free memory directly allocated to buffers for this table (non-shared). */
      CFE_TBL_DeallocateAllBuffers(RegRecPtr);
    }
    /* Return the Access Descriptor to the pool */
    CFE_TBL_RegRecSetFree(RegRecPtr);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnGetTableAddress(CFE_TBL_TxnState_t *Txn, U8 **TblPtr)
{
  I32 Status;
  CFE_TBL_AccessDescriptor_t *AccDescPtr = CFE_TBL_TxnAccDesc(Txn);
  CFE_TBL_RegistryRec_t *RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  CFE_TBL_LoadBuff_t *ActiveBuffPtr;
  /* If table is unowned, then owner must have unregistered it when we weren't looking */
  if (!CFE_ResourceId_IsDefined(RegRecPtr->OwnerAppId)) {
    Status = CFE_TBL_ERR_UNREGISTERED;
    *TblPtr = NULL;
    CFE_ES_WriteToSysLog("%s: App(%lu) attempt to access unowned Tbl Handle=%lu\n", "CFE_TBL_TxnGetTableAddress", CFE_TBL_TxnAppIdAsULong(Txn), CFE_TBL_TxnHandleAsULong(Txn));
  } else if (!CFE_TBL_RegRecIsTableLoaded(RegRecPtr)) {
    Status = CFE_TBL_ERR_NEVER_LOADED;
    *TblPtr = NULL;
  } else {
    // THE LOCK FLAG IS WHAT MAKES A RETURNED POINTER SAFE. The caller is handed the ACTIVE
    // buffer's address, and LockFlag plus the recorded BufferIndex say "this app is reading
    // this specific blob" -- so if the buffer becomes inactive mid-read nobody overwrites it
    // until CFE_TBL_ReleaseAddress clears the flag. That is the whole concurrency model.
    /* Table Registry Entry is valid */
    /* Save the buffer we are using in the access descriptor */
    /* This is used to ensure that if the buffer becomes inactive while */
    /* we are using it, no one will modify it until we are done */
    ActiveBuffPtr = CFE_TBL_GetActiveBuffer(RegRecPtr);
    /* Lock the table and return the current pointer */
    AccDescPtr->LockFlag = TRUE;
    AccDescPtr->BufferIndex = CFE_TBL_LoadBufferGetID(ActiveBuffPtr);
    *TblPtr = CFE_TBL_LoadBuffGetReadPointer(ActiveBuffPtr);
    /* Return any pending warning or info status indicators */
    Status = CFE_TBL_TxnGetNextNotification(Txn);
    /* Clear Table Updated Notify Bit so that caller only gets it once */
    AccDescPtr->Updated = FALSE;
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnFindRegByName(CFE_TBL_TxnState_t *Txn, U8 *TblName)
{
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  RegRecPtr = CFE_TBL_LocateRegRecByName(TblName);
  if (RegRecPtr == NULL) {
    Status = CFE_TBL_ERR_INVALID_NAME;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_NO_SUCH_TABLE_ERR_EID, Status, 0);
  } else {
    Txn->RegId = CFE_TBL_RegRecGetID(RegRecPtr);
    Txn->RegRecPtr = RegRecPtr;
    Status = CFE_SUCCESS;
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnAllocateRegistryEntry(CFE_TBL_TxnState_t *Txn)
{
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  U32 PendingId;
  CFE_TBL_TxnLockRegistry(Txn);
  /* Search Registry for free entry */
  PendingId = CFE_TBL_GetNextRegId();
  RegRecPtr = CFE_TBL_LocateRegRecByID(PendingId);
  /* Check to make sure there was a handle available */
  if (RegRecPtr == NULL) {
    Txn->RegRecPtr = NULL;
    Txn->RegId = CFE_TBL_REGID_UNDEFINED;
    Status = CFE_TBL_ERR_REGISTRY_FULL;
  } else {
    /* Initialize the Registry Record */
    CFE_TBL_InitRegistryRecord(RegRecPtr);
    CFE_TBL_RegRecSetUsed(RegRecPtr, PendingId);
    Txn->RegRecPtr = RegRecPtr;
    Txn->RegId = CFE_TBL_RegRecGetID(RegRecPtr);
    CFE_TBL_Global.LastRegId = PendingId;
    Status = CFE_SUCCESS;
  }
  CFE_TBL_TxnUnlockRegistry(Txn);
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnCheckDuplicateRegistration(CFE_TBL_TxnState_t *Txn, U8 *TblName, I64 Size)
{
  I32 Status = CFE_SUCCESS;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  U32 ThisAppId;
  /* Check for duplicate table name */
  Status = CFE_TBL_TxnFindRegByName(Txn, TblName);
  /* Check to see if table is already in the registry */
  if (Status == CFE_SUCCESS) {
    /* Get pointer to Registry Record Entry to speed up processing */
    RegRecPtr = CFE_TBL_TxnRegRec(Txn);
    ThisAppId = CFE_TBL_TxnAppId(Txn);
    /* If this app previously owned the table, then allow them to re-register */
    if (CFE_ResourceId_Equal(RegRecPtr->OwnerAppId, ThisAppId)) {
      /* If the new table is the same size as the old, then no need to reallocate memory */
      if (Size != CFE_TBL_RegRecGetSize(RegRecPtr)) {
        /* If the new size is different, the old table must be deleted but this */
        /* function can't do that because it is probably shared and is probably */
        /* still being accessed. Someone else will need to clean up this mess.  */
        Status = CFE_TBL_ERR_DUPLICATE_DIFF_SIZE;
        CFE_ES_WriteToSysLog("%s: Attempt to register existing table ('%s') with different size(%d!=%d)\n", "CFE_TBL_TxnCheckDuplicateRegistration", TblName, Size, CFE_TBL_RegRecGetSize(RegRecPtr));
      } else {
        /* Fill in the correct handle (already existing) */
        Status = CFE_TBL_FindAccessDescriptorForSelf(Txn);
        if (Status == CFE_SUCCESS) {
          /* Warn calling application that this is a duplicate registration */
          Status = CFE_TBL_WARN_DUPLICATE;
        }
      }
    } else {
      /* Duplicate named table owned by another Application */
      Status = CFE_TBL_ERR_DUPLICATE_NOT_OWNED;
      CFE_ES_WriteToSysLog("%s: App(%lu) Registering Duplicate Table '%s' owned by App(%lu)\n", "CFE_TBL_TxnCheckDuplicateRegistration", CFE_ResourceId_ToInteger(ThisAppId), TblName, CFE_ResourceId_ToInteger(RegRecPtr->OwnerAppId));
    }
  } else {
    /* Table not already in registry */
    /* Locate empty slot in table registry */
    Status = CFE_TBL_TxnAllocateRegistryEntry(Txn);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_TxnConnectAccessDescriptor(CFE_TBL_TxnState_t *Txn)
{
  /* Initialize the Table Access Descriptor */
  CFE_TBL_AccessDescriptor_t *AccDescPtr = CFE_TBL_TxnAccDesc(Txn);
  CFE_TBL_RegistryRec_t *RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  AccDescPtr->LockFlag = FALSE;
  AccDescPtr->AppId = CFE_TBL_TxnAppId(Txn);
  AccDescPtr->RegIndex = CFE_TBL_TxnRegId(Txn);
  CFE_TBL_TxnLockRegistry(Txn);
  // THE MISMATCH ARM IS NOT DEAD CODE. RegRecIsMatch re-checks that the registry record still
  // carries the id the transaction recorded, under the lock -- if the table was freed and
  // reallocated in between, the descriptor is connected to nothing and is simply marked
  // not-updated rather than being linked into a list that no longer describes it.
  /* Check current state of table in order to set Notification flags properly */
  if (CFE_TBL_RegRecIsMatch(RegRecPtr, AccDescPtr->RegIndex)) {
    AccDescPtr->Updated = !RegRecPtr->Config.DumpOnly && CFE_TBL_RegRecIsTableLoaded(RegRecPtr);
    CFE_TBL_HandleListInsertLink(RegRecPtr, AccDescPtr);
  } else {
    AccDescPtr->Updated = FALSE;
  }
  CFE_TBL_TxnUnlockRegistry(Txn);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnGetTableStatus(CFE_TBL_TxnState_t *Txn)
{
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  // THREE PENDING THINGS, AND THE PRIORITY IS THE ORDER OF THE TESTS. Validation beats update
  // beats dump, and only ONE is ever reported -- so a table with both a pending validation and
  // a pending dump answers VALIDATION_PENDING and the caller learns about the dump next time.
  /* Perform validations prior to performing any updates */
  if (CFE_TBL_VALRESULTID_IS_VALID(RegRecPtr->PendingValId))
    Status = CFE_TBL_INFO_VALIDATION_PENDING;
  else if (CFE_TBL_RegRecIsPendingActivation(RegRecPtr))
    Status = CFE_TBL_INFO_UPDATE_PENDING;
  else if (CFE_TBL_DUMPCTRLID_IS_VALID(RegRecPtr->DumpControlId))
    Status = CFE_TBL_INFO_DUMP_PENDING;
  else
    Status = CFE_SUCCESS;
  return Status;
}
#endif
