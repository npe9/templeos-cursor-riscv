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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_regrec.c AND the twenty
// `static inline` accessors of cfe_tbl_regrec.h -- THE REGISTRY RECORD IS THE TABLE.
//
// One of 128 records, and everything else in tbl points at one: an access descriptor is a
// handle to it, a load buffer is owned by it, a critical-table entry mirrors it into the CDS.
// The record holds three things that are easy to confuse, and the accessors below exist to
// keep them apart:
//
//   Config   what the app ASKED FOR at registration -- name, size, double-buffered,
//            dump-only, user-defined address, the validation callback. Never changes.
//   Status   what is TRUE NOW -- which buffer is active, which load is in progress, when it
//            was last updated, whether it has been modified since.
//   Buffers  the table's own dedicated pair, used only by a double-buffered table.
//
// THREE BUFFER QUESTIONS, THREE ANSWERS, and getting them mixed up is the bug this file is
// shaped to prevent. GetActiveBuffer is what readers see. GetLoadInProgressBuffer is what a
// load is filling. GetInactiveBuffer is where the NEXT load should go -- the in-progress one
// if there is one, else the previous buffer of a double-buffered table.
//
// AND GetInactiveBufferExclusive IS THE ONE THAT CAN REFUSE. Before handing back a table's
// other buffer it walks every access descriptor on the table asking "is anyone still holding
// this?", because an app that called CFE_TBL_GetAddress and has not released it is still
// reading those bytes. If one is, the load does not get a buffer and the ground is told which
// app is holding it. That walk is CFE_TBL_ForeachAccessDescriptor and
// CFE_TBL_CheckInactiveBufferHelper is the callback.
//
// PAIRED WITH cfe_tbl_loadbuff.c, which defines the buffer-id encoding this file asks about.
// The two are mutually recursive and were gated in one step for that reason.
#ifndef CFE_TBL_REGREC_HC
#define CFE_TBL_REGREC_HC
#ifndef CFE_TBL_NOT_OWNED
#define CFE_TBL_NOT_OWNED CFE_ES_APPID_UNDEFINED
#endif
// valresult.h's "nothing pending". The load-buffer id predicates live in cfe_tbl_global.HC
// beside the other id macros, because cfe_tbl_loadbuff.HC needs them too and is included
// first.
#ifndef CFE_TBL_NO_VALIDATION_PENDING
#define CFE_TBL_NO_VALIDATION_PENDING CFE_TBL_VALRESULTID_UNDEFINED
#endif
// --- FORWARD DECLARATION ACROSS THE CYCLE --------------------------------------------------
// The one name this file needs from a source still inside tbl's call cycle. It walks the
// table's access-descriptor list; the driver defines it FAITHFULLY rather than as a counter,
// because a walk of zero descriptors would make CFE_TBL_GetInactiveBufferExclusive's
// locked-buffer branch below unreachable and the exercise would assert nothing about it.
U0 CFE_TBL_ForeachAccessDescriptor(CFE_TBL_RegistryRec_t *RegRecPtr,
                                   U0 (*Func)(CFE_TBL_AccessDescriptor_t *, U8 *), U8 *Arg);
#ifndef CFE_ES_CDS_BAD_HANDLE
#define CFE_ES_CDS_BAD_HANDLE CFE_RESOURCEID_UNDEFINED
#endif

// cfe_tbl_regrec.c's own file-scope type. NASA's comment: "Local/private structure used in
// conjunction with CFE_TBL_CheckInactiveBufferHelper".
class CFE_TBL_CheckInactiveBuffer_t
{
  CFE_TBL_LoadBuff_t *BufferPtr;
  U32 LockingAppId; // CFE_ES_AppId_t
  // A TRAILING PAD, the THIRD in the tbl types. LockingAppId ends at 12 and the pointer makes
  // the class 8-byte aligned, so C rounds to 16. Every member offset matched without it:
  // a trailing pad is invisible to all of them and shows up only in sizeof -- which is what
  // the memset of CheckStat clears before the walk. CFE_TBL_Global_t's comment predicted this
  // recurring and it now has twice.
  U8 _pad0[4];
};

// --- cfe_tbl_regrec.h: the twenty accessors -------------------------------------------------
Bool CFE_TBL_RegRecIsMatch(CFE_TBL_RegistryRec_t *RegRecPtr, U32 RegId)
{
  return RegRecPtr != NULL && CFE_ResourceId_Equal(RegRecPtr->RegId, RegId);
}

U32 CFE_TBL_RegRecGetID(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return RegRecPtr->RegId;
}

Bool CFE_TBL_RegRecIsUsed(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return CFE_ResourceId_IsDefined(RegRecPtr->RegId);
}

U0 CFE_TBL_RegRecSetUsed(CFE_TBL_RegistryRec_t *RegRecPtr, U32 PendingId)
{
  RegRecPtr->RegId = PendingId;
}

U0 CFE_TBL_RegRecSetFree(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  RegRecPtr->RegId = CFE_TBL_REGID_UNDEFINED;
}

CFE_TBL_TableConfig_t *CFE_TBL_RegRecGetConfig(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return &RegRecPtr->Config;
}

// DEVIATION, and it is a HolyC limit not a choice. NASA returns CFE_TBL_CallbackFuncPtr_t,
// which is `int32 (*)(void *)`. HolyC cannot DECLARE a function whose return type is a
// function pointer -- `I32 (*GetFn(R *r))(U8 *)` is a parse error -- so the value comes back
// as a plain pointer and the caller casts. The pointer VALUE is identical either way, which
// is the part that has to stay true. docs/HOLYC_STRUCT_LIMITS.md #24.
U8 *CFE_TBL_RegRecGetValidationFunc(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  CFE_TBL_TableConfig_t *Cfg = CFE_TBL_RegRecGetConfig(RegRecPtr); // limit 17, see below
  return Cfg->ValidationFuncPtr;
}

U8 *CFE_TBL_RegRecGetName(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return RegRecPtr->Config.Name;
}

I64 CFE_TBL_RegRecGetSize(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return RegRecPtr->Config.Size;
}

I64 CFE_TBL_RegRecIsLoadInProgress(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return CFE_TBL_LOADBUFFID_IS_VALID(RegRecPtr->Status.NextBufferId);
}

U32 CFE_TBL_RegRecGetLoadInProgress(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return RegRecPtr->Status.NextBufferId;
}

U0 CFE_TBL_RegRecSetLoadInProgress(CFE_TBL_RegistryRec_t *RegRecPtr, U32 NextBufferId)
{
  RegRecPtr->Status.NextBufferId = NextBufferId;
}

U0 CFE_TBL_RegRecClearLoadInProgress(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  RegRecPtr->Status.NextBufferId = CFE_TBL_LOADBUFFID_UNDEFINED;
}

U8 *CFE_TBL_RegRecGetLastFileLoaded(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return RegRecPtr->Status.LastFileLoaded;
}

CFE_TIME_SysTime CFE_TBL_RegRecGetLastUpdateTime(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return RegRecPtr->Status.TimeOfLastUpdate;
}

Bool CFE_TBL_RegRecIsTableLoaded(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return CFE_TBL_LOADBUFFID_IS_VALID(RegRecPtr->Status.ActiveBufferId);
}

Bool CFE_TBL_RegRecIsModified(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return RegRecPtr->Status.IsModified;
}

CFE_TBL_LoadBuff_t *CFE_TBL_GetActiveBuffer(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return CFE_TBL_LocateLoadBufferByID(RegRecPtr->Status.ActiveBufferId);
}

// THE PREVIOUS BUFFER IS REMEMBERED, and that is what makes a double-buffered table's next
// load free: activating a buffer pushes the old active one to Prev, which is then the obvious
// place for the load after that.
U0 CFE_TBL_SetActiveBuffer(CFE_TBL_RegistryRec_t *RegRecPtr, CFE_TBL_LoadBuff_t *BuffPtr)
{
  RegRecPtr->Status.PrevBufferId = RegRecPtr->Status.ActiveBufferId;
  RegRecPtr->Status.ActiveBufferId = CFE_TBL_LoadBufferGetID(BuffPtr);
}

CFE_TBL_LoadBuff_t *CFE_TBL_GetPreviousBuffer(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  return CFE_TBL_LocateLoadBufferByID(RegRecPtr->Status.PrevBufferId);
}

/*----------------------------------------------------------------
 *
 * Local helper function, not invoked outside this unit
 * Intended to be used with CFE_TBL_ForeachAccessDescriptor()
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_CheckInactiveBufferHelper(CFE_TBL_AccessDescriptor_t *AccDescPtr, U8 *Arg)
{
  CFE_TBL_CheckInactiveBuffer_t *StatPtr = Arg;
  CFE_TBL_LoadBuff_t *AccBuffPtr;
  AccBuffPtr = CFE_TBL_LocateLoadBufferByID(AccDescPtr->BufferIndex);
  /* Check if it refers to this memory blob (even if the ID is different) and it is locked */
  if (AccBuffPtr == StatPtr->BufferPtr && AccDescPtr->LockFlag)
    StatPtr->LockingAppId = AccDescPtr->AppId;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_InitRegistryRecord(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  MemSet(RegRecPtr, 0, sizeof(CFE_TBL_RegistryRec_t));
  CFE_TBL_RegRecClearLoadInProgress(RegRecPtr);
  // FOUR FIELDS SET EXPLICITLY, and the honest note is that IN THIS CONFIGURATION they are
  // all zero anyway: CFE_RESOURCEID_UNDEFINED is 0 and the SIMPLE resourceid mode makes every
  // wrapper the identity, so the memset above already covers them. They are translated
  // because NASA writes them, and they are not redundant in general -- the EDS and STRICT
  // resourceid modes wrap an id in a struct, where "undefined" need not be an all-zero
  // object. The transcript shows them as 0 for exactly that reason; what it does prove is
  // that Init ran at all, because the record is filled with 0x5A first.
  RegRecPtr->OwnerAppId = CFE_TBL_NOT_OWNED;
  RegRecPtr->PendingValId = CFE_TBL_NO_VALIDATION_PENDING;
  RegRecPtr->CDSHandle = CFE_ES_CDS_BAD_HANDLE;
  RegRecPtr->DumpControlId = CFE_TBL_NO_DUMP_PENDING;
  CFE_TBL_HandleLinkInit(&RegRecPtr->AccessList);
}

// THE NEXT TWO ARE IN THE OPPOSITE ORDER TO NASA'S SOURCE, for the reason recorded in
// cfe_tbl_accdesc.HC: CFE_TBL_GetNextRegId takes the ADDRESS of CFE_TBL_CheckRegistrySlotUsed
// and HolyC resolves `&function` against the definition. Ordering only.

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_CheckRegistrySlotUsed(U32 CheckId)
{
  CFE_TBL_RegistryRec_t *RegRecPtr;
  /*
  ** Note - The pointer here should never be NULL because the ID should always be
  ** within the expected range, but if it ever is NULL, this should return true
  ** such that the caller will _not_ attempt to use the record.
  */
  RegRecPtr = CFE_TBL_LocateRegRecByID(CheckId);
  return RegRecPtr == NULL || CFE_TBL_RegRecIsUsed(RegRecPtr);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U32 CFE_TBL_GetNextRegId()
{
  // MAX_NUM_HANDLES, NOT MAX_NUM_TABLES, and that is NASA's code not a slip here: the search
  // is bounded by 256 while the registry is 128 entries. ToIndex takes the modulo, so the
  // extra turns revisit the same records; the effect is a longer worst-case scan, not a wrong
  // answer. Kept verbatim.
  return CFE_ResourceId_FindNext(CFE_TBL_Global.LastRegId, CFE_PLATFORM_TBL_MAX_NUM_HANDLES,
                                 &CFE_TBL_CheckRegistrySlotUsed);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_RegId_ToIndex(U32 RegId, U32 *Idx)
{
  return CFE_ResourceId_ToIndex(RegId, CFE_TBL_REGID_BASE, CFE_PLATFORM_TBL_MAX_NUM_TABLES,
                                Idx);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_RegistryRec_t *CFE_TBL_LocateRegRecByName(U8 *Name)
{
  CFE_TBL_RegistryRec_t *RegRecPtr;
  U32 i;
  /*
  ** Search the Registry table for an app with a matching name.
  */
  for (i = 0; i < CFE_PLATFORM_TBL_MAX_NUM_TABLES; ++i) {
    RegRecPtr = &CFE_TBL_Global.Registry[i];
    if (CFE_TBL_RegRecIsUsed(RegRecPtr) && !StrCmp(Name, CFE_TBL_RegRecGetName(RegRecPtr)))
      break;
  }
  if (i >= CFE_PLATFORM_TBL_MAX_NUM_TABLES)
    RegRecPtr = NULL;
  return RegRecPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_RegistryRec_t *CFE_TBL_LocateRegRecByID(U32 RegId)
{
  CFE_TBL_RegistryRec_t *RegRecPtr;
  U32 Idx;
  if (CFE_TBL_RegId_ToIndex(RegId, &Idx) == CFE_SUCCESS)
    RegRecPtr = &CFE_TBL_Global.Registry[Idx];
  else
    RegRecPtr = NULL;
  return RegRecPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_LoadBuff_t *CFE_TBL_GetInactiveBuffer(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  CFE_TBL_LoadBuff_t *BuffPtr;
  /* In all cases, if the NextBufferId is set and it checks out, use it */
  /* This applies to single and double buffered tables */
  BuffPtr = CFE_TBL_GetLoadInProgressBuffer(RegRecPtr);
  if (BuffPtr == NULL) {
    /* If this is a double buffered table, then get the previous buffer */
    BuffPtr = CFE_TBL_GetPreviousBuffer(RegRecPtr);
  }
  /* then return the pointer to it */
  return BuffPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_LoadBuff_t *CFE_TBL_GetSelectedBuffer(CFE_TBL_RegistryRec_t *RegRecPtr,
                                              U16 BufferSelect)
{
  CFE_TBL_LoadBuff_t *Result;
  switch (BufferSelect) {
    case CFE_TBL_BufferSelect_INACTIVE:
      Result = CFE_TBL_GetInactiveBuffer(RegRecPtr);
      break;
    case CFE_TBL_BufferSelect_ACTIVE:
      Result = CFE_TBL_GetActiveBuffer(RegRecPtr);
      break;
    default:
      /* Event is not sent here, it should be sent by the caller */
      Result = NULL;
      break;
  }
  return Result;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_LoadBuff_t *CFE_TBL_GetLoadInProgressBuffer(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  U32 BuffId;
  CFE_TBL_LoadBuff_t *LoadBuffPtr;
  BuffId = CFE_TBL_RegRecGetLoadInProgress(RegRecPtr);
  LoadBuffPtr = CFE_TBL_LocateLoadBufferByID(BuffId);
  if (!CFE_TBL_LoadBuffIsMatch(LoadBuffPtr, BuffId)) {
    LoadBuffPtr = NULL;
    /*
    ** This should not occur, but if the buffers are mis-managed somehow,
    ** the reference could be stale.  The situation could occur if the load
    ** was started but not activated (i.e. nobody called CFE_TBL_Update)
    ** and was somehow the global load buffer was dropped.  Now the reference
    ** in the local "load in progress" points to a shared/global load buff
    ** that no longer exists.
    */
    if (CFE_TBL_LOADBUFFID_IS_VALID(BuffId)) {
      /* This will clear the stale ref, restoring normalcy */
      CFE_TBL_RegRecClearLoadInProgress(RegRecPtr);
      /* but it implies something went awry with the load, so report it */
      CFE_ES_WriteToSysLog("WARNING: Cleared stale load in progress on table %s",
                           CFE_TBL_RegRecGetName(RegRecPtr));
    }
  }
  return LoadBuffPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_LoadBuff_t *CFE_TBL_GetInactiveBufferExclusive(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  CFE_TBL_LoadBuff_t *LoadBuffPtr;
  CFE_TBL_CheckInactiveBuffer_t CheckStat;
  U32 PendingId;
  MemSet(&CheckStat, 0, sizeof(CFE_TBL_CheckInactiveBuffer_t));
  PendingId = CFE_TBL_GetNextLocalBufferId(RegRecPtr);
  LoadBuffPtr = CFE_TBL_LocateLoadBufferByID(PendingId);
  /* If the load buffer already matches, it means its already reserved */
  if (LoadBuffPtr != NULL && !CFE_TBL_LOADBUFFID_EQ(LoadBuffPtr->LoadBufferId, PendingId)) {
    /* If it does not match, then need to check if it can be reserved now */
    if (CFE_TBL_LoadBuffIsUsed(LoadBuffPtr)) {
      /* Scan the access descriptor table to determine if anyone is still using the inactive
      ** buffer */
      CheckStat.BufferPtr = LoadBuffPtr;
      CFE_TBL_ForeachAccessDescriptor(RegRecPtr, &CFE_TBL_CheckInactiveBufferHelper,
                                      &CheckStat);
    }
    if (CFE_ResourceId_IsDefined(CheckStat.LockingAppId)) {
      LoadBuffPtr = NULL;
      CFE_ES_WriteToSysLog("%s: Inactive Buff Locked for '%s' by AppId=%lu\n",
                           "CFE_TBL_GetInactiveBufferExclusive",
                           CFE_TBL_RegRecGetName(RegRecPtr),
                           CFE_ResourceId_ToInteger(CheckStat.LockingAppId));
    } else {
      /* If buffer is free, then claim it */
      CFE_TBL_LoadBuffSetUsed(LoadBuffPtr, PendingId, CFE_TBL_RegRecGetID(RegRecPtr));
    }
  }
  return LoadBuffPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_RegRecResetLoadInfo(CFE_TBL_RegistryRec_t *RegRecPtr, U8 *DataSource,
                               CFE_TIME_SysTime UpdateTime)
{
  StrNCpy(RegRecPtr->Status.LastFileLoaded, DataSource, OS_MAX_PATH_LEN - 1);
  RegRecPtr->Status.LastFileLoaded[OS_MAX_PATH_LEN - 1] = 0;
  RegRecPtr->Status.TimeOfLastUpdate = UpdateTime;
  RegRecPtr->Status.IsModified = FALSE;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_RegRecSetModifiedFlag(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  RegRecPtr->Status.TimeOfLastUpdate = CFE_TIME_GetTime();
  RegRecPtr->Status.IsModified = TRUE;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_SetupTableRegistryRecord(CFE_TBL_RegistryRec_t *RegRecPtr, U32 OwnerAppId,
                                    CFE_TBL_TableConfig_t *ReqCfg)
{
  CFE_TBL_LoadBuff_t *InitialBuffPtr;
  /* Keep note of the app that registered this table */
  RegRecPtr->OwnerAppId = OwnerAppId;
  /* Save the Callback function pointer */
  RegRecPtr->Config.ValidationFuncPtr = ReqCfg->ValidationFuncPtr;
  /* Save Table Name in Registry (note that the string length was already validated) */
  StrNCpy(RegRecPtr->Config.Name, ReqCfg->Name, CFE_TBL_MAX_FULL_NAME_LEN);
  /* Save the EDS ID */
  RegRecPtr->Config.EdsId = ReqCfg->EdsId;
  /* Set the initial active buffer.  This is only applicable if it is a dump only table
  ** that is using an internal buffer - otherwise it needs to be loaded and the
  ** active buffer will be set at that time. */
  if (ReqCfg->DumpOnly && !ReqCfg->UserDefAddr)
    InitialBuffPtr = CFE_TBL_GetInactiveBufferExclusive(RegRecPtr);
  else
    InitialBuffPtr = NULL;
  if (InitialBuffPtr != NULL)
    CFE_TBL_SetActiveBuffer(RegRecPtr, InitialBuffPtr);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_RegRecIsPendingActivation(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  CFE_TBL_LoadBuff_t *LoadBuffPtr;
  Bool Result;
  Result = FALSE;
  /* The next buffer index is set when there is a pending buffer */
  LoadBuffPtr = CFE_TBL_LocateLoadBufferByID(RegRecPtr->Status.NextBufferId);
  if (CFE_TBL_LoadBuffIsMatch(LoadBuffPtr, RegRecPtr->Status.NextBufferId)) {
    /* it is only pending activation if it is validated */
    Result = LoadBuffPtr->IsValid && LoadBuffPtr->ActivateReq;
  }
  return Result;
}
#endif
