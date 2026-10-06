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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_accdesc.c AND the five
// `static inline` accessors of cfe_tbl_accdesc.h -- THE HANDLE AN APP HOLDS.
//
// AN ACCESS DESCRIPTOR IS ONE APP'S VIEW OF ONE TABLE. The registry record IS the table; the
// descriptor is a handle to it, and there is one per (app, table) pair, because two apps
// sharing a table each need their own notion of which buffer they last saw and whether they
// currently hold it locked. CFE_TBL_Handle_t, the thing an application stores and passes back
// to every CFE_TBL_* call, is an index into CFE_TBL_Global.Handles -- 256 of them.
//
// THE DESCRIPTORS FOR ONE TABLE ARE A LINKED LIST, threaded through each descriptor's Link
// field and anchored at the registry record's AccessList. That is why unregistering a table
// does NOT free it: CFE_TBL_TxnReleaseAccDesc marks the record un-owned and removes one link,
// and the memory goes back only when the LAST link is gone. NASA's comment at that line is the
// rationale -- "This allows Applications to continue to use the data until they acknowledge
// that the table has been removed."
//
// THREE STAND-INS, all in the differential driver on both halves, all from cfe_tbl_registry.c
// which is inside tbl's eight-source call cycle: CFE_TBL_TxnLockRegistry,
// CFE_TBL_TxnUnlockRegistry and CFE_TBL_TxnRemoveAccessLink. tools/cfs/module_deps.py --cuts
// prices this group at exactly those three, which is why accdesc is the way into the cycle.
// The first two are a counted lock -- the count is what makes the lock re-entrant within one
// transaction -- and the driver's OS_MutSemTake stub counts, so the transcript witnesses them.
#ifndef CFE_TBL_ACCDESC_HC
#define CFE_TBL_ACCDESC_HC
#ifndef CFE_TBL_ERR_HANDLES_FULL
#define CFE_TBL_ERR_HANDLES_FULL 0xCC00000B(I32)
#endif

// --- cfe_tbl_accdesc.h: the five accessors --------------------------------------------------
U32 CFE_TBL_AccDescGetHandle(CFE_TBL_AccessDescriptor_t *AccDescPtr)
{
  return AccDescPtr->HandleId;
}

Bool CFE_TBL_AccDescIsMatch(CFE_TBL_AccessDescriptor_t *AccDescPtr, U32 TblHandle)
{
  return AccDescPtr != NULL && CFE_ResourceId_Equal(AccDescPtr->HandleId, TblHandle);
}

Bool CFE_TBL_AccDescIsUsed(CFE_TBL_AccessDescriptor_t *AccDescPtr)
{
  return CFE_ResourceId_IsDefined(AccDescPtr->HandleId);
}

U0 CFE_TBL_AccDescSetUsed(CFE_TBL_AccessDescriptor_t *AccDescPtr, U32 PendingId)
{
  AccDescPtr->HandleId = PendingId;
}

U0 CFE_TBL_AccDescSetFree(CFE_TBL_AccessDescriptor_t *AccDescPtr)
{
  // BOTH ids, and the AppId matters as much as the handle: a freed descriptor that kept its
  // AppId would still look like it belonged to someone to anything scanning the table.
  AccDescPtr->HandleId = CFE_TBL_HANDLEID_UNDEFINED;
  AccDescPtr->AppId = CFE_ES_APPID_UNDEFINED;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_InitAccessDescriptor(CFE_TBL_AccessDescriptor_t *AccessDescPtr)
{
  MemSet(AccessDescPtr, 0, sizeof(CFE_TBL_AccessDescriptor_t));
  CFE_TBL_HandleLinkInit(&AccessDescPtr->Link);
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_Handle_ToIndex(U32 TblHandle, U32 *Idx)
{
  return CFE_ResourceId_ToIndex(TblHandle, CFE_TBL_HANDLE_BASE,
                                CFE_PLATFORM_TBL_MAX_NUM_HANDLES, Idx);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_AccessDescriptor_t *CFE_TBL_LocateAccDescByHandle(U32 TblHandle)
{
  CFE_TBL_AccessDescriptor_t *AccDescPtr;
  U32 Idx;
  if (CFE_TBL_Handle_ToIndex(TblHandle, &Idx) == CFE_SUCCESS) {
    AccDescPtr = &CFE_TBL_Global.Handles[Idx];
  } else {
    AccDescPtr = NULL;
  }
  return AccDescPtr;
}

// THE TWO BELOW ARE IN THE OPPOSITE ORDER TO NASA'S SOURCE, and that is the one deviation in
// this file. `CFE_TBL_GetNextTableHandle` takes the ADDRESS of
// `CFE_TBL_CheckAccessDescriptorSlotUsed`, and HolyC resolves `&function` against the
// DEFINITION, not a prototype -- C gets away with the other order because accdesc.h declares
// it. Ordering only; no semantic change. cfe_tbl_dumpctl.c needed no such swap because NASA
// happens to define its pair the convenient way round.
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_CheckAccessDescriptorSlotUsed(U32 CheckId)
{
  CFE_TBL_AccessDescriptor_t *AccDescPtr;
  AccDescPtr = CFE_TBL_LocateAccDescByHandle(CheckId);
  return AccDescPtr == NULL || CFE_TBL_AccDescIsUsed(AccDescPtr);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U32 CFE_TBL_GetNextTableHandle()
{
  return CFE_ResourceId_FindNext(CFE_TBL_Global.LastHandle,
                                 CFE_PLATFORM_TBL_MAX_NUM_HANDLES,
                                 &CFE_TBL_CheckAccessDescriptorSlotUsed);
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnAllocateAccDesc(CFE_TBL_TxnState_t *Txn)
{
  I32 Status;
  CFE_TBL_AccessDescriptor_t *AccDescPtr;
  U32 PendingId;
  CFE_TBL_TxnLockRegistry(Txn);
  PendingId = CFE_TBL_GetNextTableHandle();
  AccDescPtr = CFE_TBL_LocateAccDescByHandle(PendingId);
  if (AccDescPtr == NULL) {
    Txn->AccDescPtr = NULL;
    Txn->Handle = CFE_TBL_HANDLEID_UNDEFINED;
    Status = CFE_TBL_ERR_HANDLES_FULL;
  } else {
    CFE_TBL_InitAccessDescriptor(AccDescPtr);
    CFE_TBL_AccDescSetUsed(AccDescPtr, PendingId);
    Txn->AccDescPtr = AccDescPtr;
    Txn->Handle = CFE_TBL_AccDescGetHandle(AccDescPtr);
    CFE_TBL_Global.LastHandle = PendingId;
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
U0 CFE_TBL_TxnReleaseAccDesc(CFE_TBL_TxnState_t *Txn)
{
  CFE_TBL_RegistryRec_t *RegRecPtr;
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  /* Verify that the application unregistering the table owns the table */
  if (CFE_ResourceId_Equal(RegRecPtr->OwnerAppId, CFE_TBL_TxnAppId(Txn))) {
    /* Mark table as free, although, technically, it isn't free until the */
    /* linked list of Access Descriptors has no links in it.              */
    /* NOTE: Allocated memory is freed when all Access Links have been    */
    /*       removed.  This allows Applications to continue to use the    */
    /*       data until they acknowledge that the table has been removed. */
    /* Mark it as "un-owned" only -- this is not free yet */
    RegRecPtr->OwnerAppId = CFE_ES_APPID_UNDEFINED;
  }
  /* Remove the Access Descriptor Link from linked list */
  CFE_TBL_TxnRemoveAccessLink(Txn);
  /* Return the Access Descriptor to the pool */
  CFE_TBL_AccDescSetFree(CFE_TBL_TxnAccDesc(Txn));
}
#endif
