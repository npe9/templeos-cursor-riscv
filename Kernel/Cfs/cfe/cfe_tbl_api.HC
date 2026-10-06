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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_api.c -- THE PUBLIC API. Nineteen
// functions, and this is the file an application actually calls: Register, Share, Load, Update,
// GetAddress, Validate, Manage, GetInfo, Modified.
//
// EVERY ONE OF THEM IS A TRANSACTION, and the transaction is what carries the access check.
// CFE_TBL_TxnStartFromHandle / FromName resolve the caller and the table, take the registry
// lock, and refuse if the caller does not have the context the operation requires --
// ACCESSOR_APP to read, OWNER_APP to load or update, OTHER_APP to share. So the body of each
// function below is short: the hard part happened in the first line.
//
// AND THE HANDLE IS NOT THE ID. An application holds a CFE_TBL_Handle_t, which is an int16;
// internally everything is a CFE_TBL_HandleId_t, which is a based resource id. The two macros
// that convert are the whole reason CFE_TBL_HandleToID and CFE_TBL_HandleFromID exist:
//
//   CFE_TBL_HANDLE_IMPORT(x)   id   = x + CFE_TBL_HANDLE_BASE
//   CFE_TBL_HANDLE_EXPORT(x)   int16 = AsInt(id) - CFE_TBL_HANDLE_BASE
//
// THIS CONFIGURATION TAKES THE BACKWARD-COMPATIBLE BRANCH. cfe_tbl_internal.h offers two
// definitions of each, chosen by CFE_OMIT_DEPRECATED_6_8 -- a pass-through pair and the
// subtract/add pair above. The symbol is NOT defined here (measured with a probe, not assumed),
// so an app's handle really is the low 16 bits and the macros really do arithmetic. A port that
// flipped that switch would change every handle an app sees.
//
// CFE_TBL_Manage IS A LOOP OVER CFE_TBL_GetStatus, which is the one piece of control flow in
// the file: it asks what the table needs, does that one thing, and goes round again -- but only
// VALIDATION loops. A dump or an update sets FinishedManaging and returns, because a dump-only
// table cannot then be updated and an update is the last thing that can happen.
#ifndef CFE_TBL_API_HC
#define CFE_TBL_API_HC
// cfe_tbl_eventids.h
#ifndef CFE_TBL_VALIDATION_INF_EID
#define CFE_TBL_VALIDATION_INF_EID 36
#endif
#ifndef CFE_TBL_UPDATE_SUCCESS_INF_EID
#define CFE_TBL_UPDATE_SUCCESS_INF_EID 37
#endif
#ifndef CFE_TBL_REGISTER_ERR_EID
#define CFE_TBL_REGISTER_ERR_EID 90
#endif
#ifndef CFE_TBL_SHARE_ERR_EID
#define CFE_TBL_SHARE_ERR_EID 91
#endif
#ifndef CFE_TBL_UNREGISTER_ERR_EID
#define CFE_TBL_UNREGISTER_ERR_EID 92
#endif
// cfe_tbl_api_typedefs.h / cfe_error.h
#ifndef CFE_TBL_INFO_NO_VALIDATION_PENDING
#define CFE_TBL_INFO_NO_VALIDATION_PENDING 0x4C00001A
#endif
#ifndef CFE_TBL_WARN_NOT_CRITICAL
#define CFE_TBL_WARN_NOT_CRITICAL 0x4C000026
#endif
#ifndef CFE_TBL_INFO_NO_DUMP_PENDING
#define CFE_TBL_INFO_NO_DUMP_PENDING 0x4C00002E
#endif
// CFE_TBL_BAD_TABLE_HANDLE and CFE_TBL_HANDLE_IS_VALID are in cfe_tbl_internal.HC beside the
// EXPORT/IMPORT pair, with the note about which branch of cfe_tbl_api_typedefs.h applies.
// cfe_tbl_api_typedefs.h: what CFE_TBL_GetInfo fills in. check_padding measures it against
// NASA's 104 bytes.
class CFE_TBL_Info_t
{
  I64 Size;
  U32 NumUsers;
  CFE_TIME_SysTime FileTime;
  U32 Crc;
  CFE_TIME_SysTime TimeOfLastUpdate;
  Bool TableLoadedOnce;
  Bool DumpOnly;
  Bool DoubleBuffered;
  Bool UserDefAddr;
  Bool Critical;
  U8 LastFileLoaded[CFE_MISSION_MAX_PATH_LEN];
  U8 _pad0[3];
};
I32 CFE_TBL_ReleaseAddress(I16 TblHandle);
I32 CFE_TBL_Update(I16 TblHandle);
I32 CFE_TBL_Validate(I16 TblHandle);
I32 CFE_TBL_GetStatus(I16 TblHandle);
I32 CFE_TBL_DumpToBuffer(I16 TblHandle);
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_Register(I16 *TblHandlePtr, U8 *Name, I64 Size, U16 TblOptionFlags, I32 (*TblValidationFuncPtr)(U8 *))
{
  CFE_TBL_TxnState_t Txn;
  CFE_TBL_RegistryRec_t *RegRecPtr = NULL;
  CFE_TBL_CritRegRec_t *CritRegRecPtr = NULL;
  I32 Status;
  CFE_TBL_TableConfig_t TableCfg;
  if (TblHandlePtr == NULL || Name == NULL)
    return CFE_TBL_BAD_ARGUMENT;
  MemSet(&TableCfg, 0, sizeof(CFE_TBL_TableConfig_t));
  /* Check to make sure calling application is legit */
  Status = CFE_TBL_TxnInit(&Txn, TRUE);
  if (Status == CFE_SUCCESS) {
    Status = CFE_TBL_TxnCheckConfig(&Txn, &TableCfg, Name, TblOptionFlags, Size, TblValidationFuncPtr);
  } else {
    /* Application ID was invalid */
    /* Only possiblity is that calling Application ID was invalid */
    CFE_ES_WriteToSysLog("%s: Bad AppId(%lu), status=%lx\n", "CFE_TBL_Register", CFE_TBL_TxnAppIdAsULong(&Txn), Status);
  }
  /* If input parameters appear acceptable, register the table */
  if (Status == CFE_SUCCESS) {
    /* Lock Registry for update.  This prevents two applications from        */
    /* trying to register/share tables at the same location at the same time */
    CFE_TBL_TxnLockRegistry(&Txn);
    Status = CFE_TBL_TxnCheckDuplicateRegistration(&Txn, TableCfg.Name, TableCfg.Size);
    /* In error conditions or if this is a duplicate registration, no further work is required */
    if (Status == CFE_SUCCESS) {
      /* Search Access Descriptor Array for free Descriptor */
      Status = CFE_TBL_TxnAllocateAccDesc(&Txn);
    }
    /* If no errors, initialize the table registry entry and return the index to the caller as
     * the handle */
    if (Status == CFE_SUCCESS) {
      /* Get pointer to Registry Record Entry to speed up processing */
      RegRecPtr = CFE_TBL_TxnRegRec(&Txn);
      Status = CFE_TBL_SetupTableBuffers(RegRecPtr, &TableCfg);
    }
    /* If memory allocation was successful, register with table services and the CDS (if
     * applicable) */
    if (Status == CFE_SUCCESS) {
      CFE_TBL_SetupTableRegistryRecord(RegRecPtr, CFE_TBL_TxnAppId(&Txn), &TableCfg);
      CFE_TBL_TxnConnectAccessDescriptor(&Txn);
      /* If the table is a critical table, allocate space for it in the Critical Data Store */
      /* OR locate its previous incarnation there and extract its previous contents */
      if (TableCfg.Critical) {
        /* Register a CDS under the table name and determine if the table already exists there
         */
        Status = CFE_ES_RegisterCDSEx(&RegRecPtr->CDSHandle, TableCfg.Size, TableCfg.Name, TRUE);
        if (Status == CFE_ES_CDS_ALREADY_EXISTS)
          Status = CFE_TBL_RestoreTableDataFromCDS(RegRecPtr);
        /* Don't need to register with Critical Table Registry if table data was recovered */
        if (Status == CFE_SUCCESS) {
          CFE_TBL_RegisterWithCriticalTableRegistry(CritRegRecPtr, RegRecPtr, TableCfg.Name);
        } else if (Status != CFE_TBL_INFO_RECOVERED_TBL) {
          CFE_ES_WriteToSysLog("%s: Failed to register '%s.%s' as a CDS (ErrCode=0x%08X)\n", "CFE_TBL_Register", CFE_TBL_TxnAppNameCaller(&Txn), Name, Status);
          /* Notify caller that although they asked for it to be critical, it isn't */
          Status = CFE_TBL_WARN_NOT_CRITICAL;
        }
      }
      // OWNERSHIP IS CLAIMED LAST, DELIBERATELY. NASA's comment says why: an UNOWNED registry
      // entry is not checked for a name match, so until this line runs no other API can find
      // the half-built table -- which is what lets Share and GetAddress skip the registry lock
      // entirely.
      /* The last step of the registration process is claiming ownership.    */
      /* By making it the last step, other APIs do not have to lock registry */
      /* to share the table or get its address because registry entries that */
      /* are unowned are not checked to see if they match names, etc.        */
      RegRecPtr->OwnerAppId = CFE_TBL_TxnAppId(&Txn);
    }
    /* Unlock Registry for update */
    CFE_TBL_TxnUnlockRegistry(&Txn);
  }
  /* On Error conditions, notify ground of screw up */
  if (Status < 0) {
    /* Make sure the returned handle is invalid when an error occurs */
    *TblHandlePtr = CFE_TBL_BAD_TABLE_HANDLE;
    CFE_EVS_SendEventWithAppID(CFE_TBL_REGISTER_ERR_EID, CFE_EVS_EventType_ERROR, CFE_TBL_Global.TableTaskAppId, "%s Failed to Register table '%s', Status=0x%08X", CFE_TBL_TxnAppNameCaller(&Txn), Name, Status);
  } else {
    *TblHandlePtr = CFE_TBL_HANDLE_EXPORT(CFE_TBL_TxnHandle(&Txn));
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_Share(I16 *TblHandlePtr, U8 *TblName)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  if (TblHandlePtr == NULL || TblName == NULL)
    return CFE_TBL_BAD_ARGUMENT;
  /* locate the subject table in the registry */
  Status = CFE_TBL_TxnStartFromName(&Txn, TblName, CFE_TBL_TxnContext_OTHER_APP);
  if (Status == CFE_SUCCESS) {
    /* Search Access Descriptor Array for free Descriptor */
    Status = CFE_TBL_TxnAllocateAccDesc(&Txn);
    if (Status == CFE_SUCCESS) {
      /* associate the access descriptor with the subject table */
      CFE_TBL_TxnConnectAccessDescriptor(&Txn);
    }
    CFE_TBL_TxnFinish(&Txn);
  }
  /* On Error conditions, notify ground of screw up */
  if (Status < CFE_SUCCESS) {
    /* Make sure the returned handle is invalid when an error occurs */
    *TblHandlePtr = CFE_TBL_BAD_TABLE_HANDLE;
    if (Status == CFE_TBL_ERR_INVALID_NAME)
      CFE_ES_WriteToSysLog("%s: Table '%s' not found in Registry\n", "CFE_TBL_Share", TblName);
    CFE_EVS_SendEventWithAppID(CFE_TBL_SHARE_ERR_EID, CFE_EVS_EventType_ERROR, CFE_TBL_Global.TableTaskAppId, "%s Failed to Share '%s', Status=0x%08X", CFE_TBL_TxnAppNameCaller(&Txn), TblName, Status);
  } else {
    *TblHandlePtr = CFE_TBL_HANDLE_EXPORT(CFE_TBL_TxnHandle(&Txn));
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_Unregister(I16 TblHandle)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  /* Verify that this application has the right to perform operation */
  Status = CFE_TBL_TxnStartFromHandle(&Txn, CFE_TBL_HANDLE_IMPORT(TblHandle), CFE_TBL_TxnContext_ACCESSOR_APP);
  if (Status == CFE_SUCCESS) {
    /* Release the access descriptor and clean up refs */
    CFE_TBL_TxnReleaseAccDesc(&Txn);
    CFE_TBL_TxnFinish(&Txn);
  } else {
    CFE_ES_WriteToSysLog("%s: App(%lu) does not have access to Tbl Handle=%lu\n", "CFE_TBL_Unregister", CFE_TBL_TxnAppIdAsULong(&Txn), CFE_TBL_TxnHandleAsULong(&Txn));
  }
  /* On Error conditions, notify ground of screw up */
  if (Status < 0) {
    CFE_EVS_SendEventWithAppID(CFE_TBL_UNREGISTER_ERR_EID, CFE_EVS_EventType_ERROR, CFE_TBL_Global.TableTaskAppId, "%s Failed to Unregister '?', Status=0x%08X", CFE_TBL_TxnAppNameCaller(&Txn), Status);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_Load(I16 TblHandle, U32 SrcType, U8 *SrcDataPtr)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  Bool LoadWasAttempted;
  LoadWasAttempted = FALSE;
  if (SrcDataPtr == NULL)
    return CFE_TBL_BAD_ARGUMENT;
  /* Verify access rights and get a valid Application ID for calling App */
  Status = CFE_TBL_TxnStartFromHandle(&Txn, CFE_TBL_HANDLE_IMPORT(TblHandle), CFE_TBL_TxnContext_OWNER_APP);
  if (Status == CFE_SUCCESS) {
    /* As all ops are confined to this registry entry alone, release the lock */
    CFE_TBL_TxnUnlockRegistry(&Txn);
    /* Perform a sanity check on the table state */
    Status = CFE_TBL_ValidateLoadRequest(&Txn, SrcType);
  }
  if (Status == CFE_SUCCESS) {
    /* Now do the actual loading */
    if (SrcType == CFE_TBL_SRC_FILE) {
      /* Load the data from the file into the specified buffer */
      Status = CFE_TBL_TxnLoadFromFile(&Txn, SrcDataPtr);
    } else {
      /* The source data is an address (note SrcType was validated earlier) */
      Status = CFE_TBL_TxnLoadFromSourceAddr(&Txn, SrcDataPtr);
    }
    LoadWasAttempted = TRUE;
    if (Status >= CFE_SUCCESS)
      Status = CFE_TBL_ValidateLoadInProgress(&Txn, Status);
  }
  /* Send any events from validation (should be none if things went well) */
  CFE_TBL_SendTableLoadEvents(&Txn);
  CFE_TBL_TxnFinish(&Txn);
  // THE LoadWasAttempted FLAG IS NOT BOOKKEEPING, IT IS A SAFETY INTERLOCK. NASA's comment
  // says exactly what it protects against: CFE_TBL_LoadFinish may DROP the working buffer, so
  // a call that was refused because a PREVIOUS load is still in progress must not reach it --
  // it would cancel that other load.
  /* Perform the table update to complete the load (this also cleans up, if failure case) */
  /* Note this may drop the working buffer, so only do this if we actually attempted to load
   * the table during THIS call (for example, if this call was rejected due to a previous load
   * already in progress, do not do this, because it will end up canceling the previous load) */
  if (LoadWasAttempted)
    Status = CFE_TBL_LoadFinish(&Txn, Status);
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_Update(I16 TblHandle)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  U32 HandleId;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_AccessDescriptor_t *AccessDescPtr;
  RegRecPtr = NULL;
  AccessDescPtr = NULL;
  HandleId = CFE_TBL_HANDLE_IMPORT(TblHandle);
  /* Verify access rights and get a valid Application ID for calling App */
  Status = CFE_TBL_TxnStartFromHandle(&Txn, HandleId, CFE_TBL_TxnContext_OWNER_APP);
  if (Status == CFE_SUCCESS) {
    /* Get pointers to pertinent records in registry and handles */
    AccessDescPtr = CFE_TBL_TxnAccDesc(&Txn);
    RegRecPtr = CFE_TBL_TxnRegRec(&Txn);
    Status = CFE_TBL_UpdateInternal(HandleId, RegRecPtr, AccessDescPtr);
    CFE_TBL_TxnFinish(&Txn);
    if (Status != CFE_SUCCESS)
      CFE_ES_WriteToSysLog("%s: App(%lu) fail to update Tbl '%s' (Stat=0x%08X)\n", "CFE_TBL_Update", CFE_TBL_TxnAppIdAsULong(&Txn), CFE_TBL_RegRecGetName(RegRecPtr), Status);
  } else {
    CFE_ES_WriteToSysLog("%s: App(%lu) does not have access to Tbl Handle=%lu\n", "CFE_TBL_Update", CFE_TBL_TxnAppIdAsULong(&Txn), CFE_TBL_TxnHandleAsULong(&Txn));
  }
  /* On Error conditions, notify ground of screw up */
  if (Status < 0) {
    /*
     * Note that (Status < 0) specifically matches ERROR, not WARNING codes. The
     * CFE_TBL_UpdateInternal() function currently only produces two possible codes (aside from
     * CFE_SUCCESS) and both of these are defined as warnings, not errors.  Therefore, its
     * impossible to reach this code with RegRecPtr != NULL.
     */
    CFE_EVS_SendEventWithAppID(CFE_TBL_UPDATE_ERR_EID, CFE_EVS_EventType_ERROR, CFE_TBL_Global.TableTaskAppId, "%s Failed to update table, Status=0x%08X", CFE_TBL_TxnAppNameCaller(&Txn), Status);
  } else {
    /* If there was a warning (ie - Table is currently locked), then do not issue a message */
    if (Status == CFE_SUCCESS) {
      CFE_EVS_SendEventWithAppID(CFE_TBL_UPDATE_SUCCESS_INF_EID, CFE_EVS_EventType_INFORMATION, CFE_TBL_Global.TableTaskAppId, "%s Successfully Updated '%s'", CFE_TBL_TxnAppNameCaller(&Txn), CFE_TBL_RegRecGetName(RegRecPtr));
      /* Save the index of the table for housekeeping telemetry */
      CFE_TBL_Global.LastTblUpdated = AccessDescPtr->RegIndex;
    }
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_GetAddress(U8 **TblPtr, I16 TblHandle)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  if (TblPtr == NULL)
    return CFE_TBL_BAD_ARGUMENT;
  /* Assume failure at returning the table address */
  *TblPtr = NULL;
  Status = CFE_TBL_TxnStartFromHandle(&Txn, CFE_TBL_HANDLE_IMPORT(TblHandle), CFE_TBL_TxnContext_ACCESSOR_APP);
  if (Status == CFE_SUCCESS) {
    Status = CFE_TBL_TxnGetTableAddress(&Txn, TblPtr);
    /* NOTE: GetAddressInternal calls GetNextNotification which may not */
    /*       be equal to CFE_SUCCESS and still not be an error.         */
    /*       Therefore, a write to the SysLog is unnecessary.           */
    CFE_TBL_TxnFinish(&Txn);
  } else {
    CFE_ES_WriteToSysLog("%s: Bad AppId=%lu\n", "CFE_TBL_GetAddress", CFE_TBL_TxnAppIdAsULong(&Txn));
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ReleaseAddress(I16 TblHandle)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  CFE_TBL_AccessDescriptor_t *AccDescPtr;
  /* Verify that this application has the right to perform operation */
  Status = CFE_TBL_TxnStartFromHandle(&Txn, CFE_TBL_HANDLE_IMPORT(TblHandle), CFE_TBL_TxnContext_ACCESSOR_APP);
  if (Status == CFE_SUCCESS) {
    // HOISTED, limit 17: `CFE_TBL_TxnAccDesc(&Txn)->LockFlag = false` resolves the arrow
    // against the FIRST ARGUMENT's class and the compiler refuses. The pointer is identical.
    /* Clear the lock flag */
    AccDescPtr = CFE_TBL_TxnAccDesc(&Txn);
    AccDescPtr->LockFlag = FALSE;
    /* Return any pending warning or info status indicators */
    Status = CFE_TBL_TxnGetNextNotification(&Txn);
    /* NOTE: GetNextNotification may not return CFE_SUCCESS  */
    /*       and still not be an error.                      */
    /*       Therefore, a write to the SysLog is unnecessary.*/
    CFE_TBL_TxnFinish(&Txn);
  } else {
    CFE_ES_WriteToSysLog("%s: App(%lu) does not have access to Tbl Handle=%lu\n", "CFE_TBL_ReleaseAddress", CFE_TBL_TxnAppIdAsULong(&Txn), CFE_TBL_TxnHandleAsULong(&Txn));
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_GetAddresses(U8 ***TblPtrs, U16 NumTables, I16 *TblHandles)
{
  CFE_TBL_TxnState_t Txn;
  I32 FinalStatus;
  U16 i;
  I32 Status;
  U32 HandleId;
  if (TblPtrs == NULL || TblHandles == NULL)
    return CFE_TBL_BAD_ARGUMENT;
  /* Assume failure at returning the table addresses */
  for (i = 0; i < NumTables; i++)
    *TblPtrs[i] = NULL;
  // THE FIRST NON-SUCCESS IS KEPT, NOT THE LAST, and the loop keeps going anyway -- so a
  // caller asking for five addresses gets whatever each table could give plus the status of
  // the first one that complained. Only a bad APP ID breaks out early, because that is the one
  // failure that cannot get better on the next table.
  FinalStatus = CFE_SUCCESS;
  for (i = 0; i < NumTables; i++) {
    HandleId = CFE_TBL_HANDLE_IMPORT(TblHandles[i]);
    Status = CFE_TBL_TxnStartFromHandle(&Txn, HandleId, CFE_TBL_TxnContext_ACCESSOR_APP);
    if (Status == CFE_SUCCESS) {
      Status = CFE_TBL_TxnGetTableAddress(&Txn, TblPtrs[i]);
      CFE_TBL_TxnFinish(&Txn);
    }
    if (FinalStatus == CFE_SUCCESS)
      FinalStatus = Status;
    if (Status == CFE_ES_ERR_RESOURCEID_NOT_VALID) {
      CFE_ES_WriteToSysLog("%s: Bad AppId=%lu\n", "CFE_TBL_GetAddresses", CFE_TBL_TxnAppIdAsULong(&Txn));
      break;
    }
  }
  return FinalStatus;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ReleaseAddresses(U16 NumTables, I16 *TblHandles)
{
  I32 Status = CFE_SUCCESS;
  U16 i;
  if (TblHandles == NULL)
    return CFE_TBL_BAD_ARGUMENT;
  // EVERY HANDLE IS RELEASED EITHER WAY. The if/else looks like it might skip the call once
  // something has failed and it does not -- both arms call CFE_TBL_ReleaseAddress; only the
  // STATUS is dropped after the first failure. Releasing fewer than asked would leak locks.
  for (i = 0; i < NumTables; i++) {
    /* Continue to get the return status until one returns something other than CFE_SUCCESS */
    if (Status == CFE_SUCCESS) {
      Status = CFE_TBL_ReleaseAddress(TblHandles[i]);
    } else {
      /* Don't bother getting the status of other tables once one has returned */
      /* a non CFE_SUCCESS value.                                              */
      CFE_TBL_ReleaseAddress(TblHandles[i]);
    }
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_Validate(I16 TblHandle)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *BuffPtr;
  CFE_TBL_ValidationResult_t *ResultPtr;
  U8 *LogTagStr;
  I32 (*ValidationFunc)(U8 *);
  ResultPtr = NULL;
  BuffPtr = NULL;
  LogTagStr = "(none)";
  /* Verify that this application has the right to perform operation */
  Status = CFE_TBL_TxnStartFromHandle(&Txn, CFE_TBL_HANDLE_IMPORT(TblHandle), CFE_TBL_TxnContext_OWNER_APP);
  if (Status == CFE_SUCCESS) {
    /* Get pointers to pertinent records in registry and handles */
    RegRecPtr = CFE_TBL_TxnRegRec(&Txn);
    /* Identify the image to be validated, starting with the Inactive Buffer */
    ResultPtr = CFE_TBL_CheckValidationRequest(&RegRecPtr->PendingValId);
    if (ResultPtr != NULL) {
      /* note "inactive" here refers to the NEXT (i.e. load in progress) buffer */
      /* one cannot validate the PREVIOUS buffer of a double-buffered table */
      if (ResultPtr->BufferSelect == CFE_TBL_BufferSelect_INACTIVE) {
        LogTagStr = "inactive";
        BuffPtr = CFE_TBL_GetLoadInProgressBuffer(RegRecPtr);
      } else {
        LogTagStr = "active";
        BuffPtr = CFE_TBL_GetActiveBuffer(RegRecPtr);
      }
    }
    ValidationFunc = CFE_TBL_RegRecGetValidationFunc(RegRecPtr);
    CFE_TBL_TxnFinish(&Txn);
    if (ResultPtr != NULL) {
      if (BuffPtr == NULL) {
        /* No buffer, it cannot be valid */
        ResultPtr->Result = -1;
      } else {
        if (ValidationFunc == NULL) {
          /* no validation function, assume its OK */
          ResultPtr->Result = 0;
        } else {
          /* Save the result of the Validation function for the Table Services Task */
          ResultPtr->Result = ValidationFunc(CFE_TBL_LoadBuffGetReadPointer(BuffPtr));
        }
        /* A return value of 0 indicates it is valid */
        BuffPtr->IsValid = ResultPtr->Result == 0;
      }
      /* Allow buffer to be activated after passing validation */
      if (ResultPtr->Result == 0) {
        CFE_EVS_SendEventWithAppID(CFE_TBL_VALIDATION_INF_EID, CFE_EVS_EventType_INFORMATION, CFE_TBL_Global.TableTaskAppId, "%s validation successful for %s '%s'", CFE_TBL_TxnAppNameCaller(&Txn), LogTagStr, CFE_TBL_RegRecGetName(RegRecPtr));
      } else {
        // THE TWO ARGUMENTS ARE IN THIS ORDER IN NASA'S SOURCE AND THE FORMAT STRING DISAGREES
        // WITH THEM. "%s validation failed for %s '%s'" is fed AppName, then the table NAME,
        // then the log TAG -- so the message reads "... failed for CFE_TBL.Tbl 'inactive'",
        // with the two swapped relative to the success message immediately above. Kept
        // verbatim, because this is a 1:1 translation and the transcript compares the text.
        CFE_EVS_SendEventWithAppID(CFE_TBL_VALIDATION_ERR_EID, CFE_EVS_EventType_ERROR, CFE_TBL_Global.TableTaskAppId, "%s validation failed for %s '%s', Status=0x%08X", CFE_TBL_TxnAppNameCaller(&Txn), CFE_TBL_RegRecGetName(RegRecPtr), LogTagStr, ResultPtr->Result);
        if (ResultPtr->Result > 0)
          CFE_ES_WriteToSysLog("%s: App(%lu) Validation func return code invalid (Stat=0x%08X) for '%s'\n", "CFE_TBL_Validate", CFE_ResourceId_ToInteger(CFE_TBL_Global.TableTaskAppId), ResultPtr->Result, CFE_TBL_RegRecGetName(RegRecPtr));
      }
      /* Once validation is complete, set flags to indicate response is ready */
      ResultPtr->State = CFE_TBL_VALIDATION_PERFORMED;
      /* Since the validation was successfully performed (although maybe not a successful
       * result) */
      /* return a success status */
      Status = CFE_SUCCESS;
    } else {
      Status = CFE_TBL_INFO_NO_VALIDATION_PENDING;
    }
  } else {
    CFE_ES_WriteToSysLog("%s: App(%lu) does not have access to Tbl Handle=%lu\n", "CFE_TBL_Validate", CFE_TBL_TxnAppIdAsULong(&Txn), CFE_TBL_TxnHandleAsULong(&Txn));
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_Manage(I16 TblHandle)
{
  I32 Status = CFE_SUCCESS;
  Bool FinishedManaging = FALSE;
  // ONLY VALIDATION LOOPS. A dump or an update sets FinishedManaging and returns -- a dump-only
  // table cannot then be updated, and an update is the last thing that can happen to a table in
  // one Manage call. Validation goes round again because a table can have a validation request
  // AND an update pending, and the update must not be applied before the validation says yes.
  while (!FinishedManaging) {
    /* Determine if the table has a validation or update that needs to be performed */
    Status = CFE_TBL_GetStatus(TblHandle);
    if (Status == CFE_TBL_INFO_VALIDATION_PENDING) {
      /* Validate the specified Table */
      Status = CFE_TBL_Validate(TblHandle);
      if (Status != CFE_SUCCESS) {
        /* If an error occurred during Validate, then do not perform any more managing */
        FinishedManaging = TRUE;
      }
    } else if (Status == CFE_TBL_INFO_DUMP_PENDING) {
      /* Dump the specified Table */
      Status = CFE_TBL_DumpToBuffer(TblHandle);
      /* After a Dump, always assume we are done (Dumps are on DumpOnly tables and cannot be
       * "Updated") */
      FinishedManaging = TRUE;
    } else if (Status == CFE_TBL_INFO_UPDATE_PENDING) {
      /* Update the specified Table */
      Status = CFE_TBL_Update(TblHandle);
      /* If the update performed nominally, let the caller know the table has changed */
      if (Status == CFE_SUCCESS)
        Status = CFE_TBL_INFO_UPDATED;
      /* After an Update, always assume we are done and return Update Status */
      FinishedManaging = TRUE;
    } else {
      FinishedManaging = TRUE;
    }
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_GetStatus(I16 TblHandle)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  /* Verify that this application has the right to perform operation */
  Status = CFE_TBL_TxnStartFromHandle(&Txn, CFE_TBL_HANDLE_IMPORT(TblHandle), CFE_TBL_TxnContext_ACCESSOR_APP);
  if (Status == CFE_SUCCESS) {
    Status = CFE_TBL_TxnGetTableStatus(&Txn);
    CFE_TBL_TxnFinish(&Txn);
  } else {
    CFE_ES_WriteToSysLog("%s: App(%lu) does not have access to Tbl Handle=%lu\n", "CFE_TBL_GetStatus", CFE_TBL_TxnAppIdAsULong(&Txn), CFE_TBL_TxnHandleAsULong(&Txn));
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_GetInfo(CFE_TBL_Info_t *TblInfoPtr, U8 *TblName)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status = CFE_SUCCESS;
  I32 NumAccessDescriptors = 0;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *ActiveBufPtr;
  CFE_TBL_TableConfig_t *CfgPtr;
  if (TblInfoPtr == NULL || TblName == NULL)
    return CFE_TBL_BAD_ARGUMENT;
  Status = CFE_TBL_TxnStartFromName(&Txn, TblName, CFE_TBL_TxnContext_UNDEFINED);
  /* If we found the table, then extract the information from the Registry */
  if (Status == CFE_SUCCESS) {
    /* Get pointer to Registry Record Entry to speed up processing */
    RegRecPtr = CFE_TBL_TxnRegRec(&Txn);
    // HOISTED, limit 17, four times: NASA reads CFE_TBL_RegRecGetConfig(RegRecPtr)->field
    // inline for each of the four option flags.
    CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr);
    /* Return table characteristics */
    TblInfoPtr->Size = CFE_TBL_RegRecGetSize(RegRecPtr);
    TblInfoPtr->DoubleBuffered = CfgPtr->DoubleBuffered;
    TblInfoPtr->DumpOnly = CfgPtr->DumpOnly;
    TblInfoPtr->UserDefAddr = CfgPtr->UserDefAddr;
    TblInfoPtr->Critical = CfgPtr->Critical;
    TblInfoPtr->TableLoadedOnce = CFE_TBL_RegRecIsTableLoaded(RegRecPtr);
    /* Return information on last load and update */
    TblInfoPtr->TimeOfLastUpdate = CFE_TBL_RegRecGetLastUpdateTime(RegRecPtr);
    /* If the table was never loaded, the active buffer can be NULL */
    ActiveBufPtr = CFE_TBL_GetActiveBuffer(RegRecPtr);
    if (ActiveBufPtr != NULL) {
      TblInfoPtr->FileTime = ActiveBufPtr->FileTime;
      TblInfoPtr->Crc = ActiveBufPtr->Crc;
    } else {
      // CFE_TIME_ZERO_VALUE is a C compound literal, `(CFE_TIME_SysTime_t){0, 0}`, which HolyC
      // has no spelling for; the two fields are assigned instead.
      TblInfoPtr->FileTime.Seconds = 0;
      TblInfoPtr->FileTime.Subseconds = 0;
      TblInfoPtr->Crc = 0;
    }
    CFE_SB_MessageStringSet(TblInfoPtr->LastFileLoaded, CFE_TBL_RegRecGetLastFileLoaded(RegRecPtr), CFE_MISSION_MAX_PATH_LEN, -1);
    if (CFE_TBL_RegRecIsModified(RegRecPtr))
      CFE_TBL_MarkNameAsModified(TblInfoPtr->LastFileLoaded, CFE_MISSION_MAX_PATH_LEN);
    // NASA PASSES AN int32* WHERE THE HELPER TAKES uint32*, which is its own code and is kept.
    // The count cannot exceed 256, so the signedness never shows.
    CFE_TBL_ForeachAccessDescriptor(RegRecPtr, &CFE_TBL_CountAccessDescHelper, &NumAccessDescriptors);
    TblInfoPtr->NumUsers = NumAccessDescriptors;
    CFE_TBL_TxnFinish(&Txn);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_DumpToBuffer(I16 TblHandle)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_DumpControl_t *DumpCtrlPtr;
  Status = CFE_TBL_TxnStartFromHandle(&Txn, CFE_TBL_HANDLE_IMPORT(TblHandle), CFE_TBL_TxnContext_ACCESSOR_APP);
  if (Status == CFE_SUCCESS) {
    RegRecPtr = CFE_TBL_TxnRegRec(&Txn);
    DumpCtrlPtr = CFE_TBL_LocateDumpCtrlByID(RegRecPtr->DumpControlId);
    if (CFE_TBL_DumpCtrlBlockIsMatch(DumpCtrlPtr, RegRecPtr->DumpControlId)) {
      Status = CFE_TBL_ExecuteDumpSnapshot(DumpCtrlPtr);
    } else {
      Status = CFE_TBL_INFO_NO_DUMP_PENDING;
      if (CFE_TBL_DUMPCTRLID_IS_VALID(RegRecPtr->DumpControlId)) {
        /* this means that the dump request has gone stale (no longer pending/matching) */
        /* Clear it out */
        RegRecPtr->DumpControlId = CFE_TBL_DUMPCTRLID_UNDEFINED;
      }
    }
    CFE_TBL_TxnFinish(&Txn);
    if (Status == CFE_TBL_INFO_NO_DUMP_PENDING && DumpCtrlPtr != NULL) {
      /* A stale request is not expected, so log that it happened */
      CFE_ES_WriteToSysLog("%s: App(0x%lx) had stale dump request pending on 0x%lx (dropped)\n", "CFE_TBL_DumpToBuffer", CFE_TBL_TxnAppIdAsULong(&Txn), CFE_TBL_TxnHandleAsULong(&Txn));
    }
  } else {
    CFE_ES_WriteToSysLog("%s: App(%lx) does not have access to Tbl Handle=0x%lx\n", "CFE_TBL_DumpToBuffer", CFE_TBL_TxnAppIdAsULong(&Txn), CFE_TBL_TxnHandleAsULong(&Txn));
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Local helper function, not invoked outside this unit
 * Intended to be used with CFE_TBL_ForeachAccessDescriptor()
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_NotifyOtherAppHelper(CFE_TBL_AccessDescriptor_t *AccessDescPtr, U8 *Arg)
{
  CFE_TBL_TxnState_t *Txn = Arg;
  /* Only notify *OTHER* applications that the contents have changed */
  if (!CFE_ResourceId_Equal(AccessDescPtr->AppId, CFE_TBL_TxnAppId(Txn)))
    AccessDescPtr->Updated = TRUE;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_Modified(I16 TblHandle)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *ActiveBufPtr;
  CFE_TBL_TableConfig_t *CfgPtr;
  /* Verify that this application has the right to perform operation */
  Status = CFE_TBL_TxnStartFromHandle(&Txn, CFE_TBL_HANDLE_IMPORT(TblHandle), CFE_TBL_TxnContext_ACCESSOR_APP);
  if (Status == CFE_SUCCESS) {
    /* Get pointers to pertinent records in registry and handles */
    RegRecPtr = CFE_TBL_TxnRegRec(&Txn);
    ActiveBufPtr = CFE_TBL_GetActiveBuffer(RegRecPtr);
    /* If the table was never loaded, the active buffer will be NULL */
    if (ActiveBufPtr != NULL) {
      /* Keep a record of change for the ground operators reference */
      CFE_TBL_RegRecSetModifiedFlag(RegRecPtr);
      /* Update CRC on contents of table */
      CFE_TBL_LoadBuffRecomputeCRC(ActiveBufPtr);
      /* Only notify *OTHER* applications that the contents have changed */
      CFE_TBL_ForeachAccessDescriptor(RegRecPtr, &CFE_TBL_NotifyOtherAppHelper, &Txn);
    }
    CFE_TBL_TxnFinish(&Txn);
    // HOISTED, limit 17. Note also that this read happens AFTER CFE_TBL_TxnFinish has released
    // the registry lock, which is NASA's own ordering.
    CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr);
    /* If the table is a critical table, update the appropriate CDS with the new data */
    if (CfgPtr->Critical)
      CFE_TBL_UpdateCriticalTblCDS(RegRecPtr);
  } else {
    CFE_ES_WriteToSysLog("%s: App(%lu) does not have access to Tbl Handle=%lu\n", "CFE_TBL_Modified", CFE_TBL_TxnAppIdAsULong(&Txn), CFE_TBL_TxnHandleAsULong(&Txn));
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_NotifyByMessage(I16 TblHandle, CFE_SB_MsgId MsgId, U16 CommandCode, U32 Parameter)
{
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr = NULL;
  /* Verify that this application has the right to perform operation */
  Status = CFE_TBL_TxnStartFromHandle(&Txn, CFE_TBL_HANDLE_IMPORT(TblHandle), CFE_TBL_TxnContext_ACCESSOR_APP);
  if (Status == CFE_SUCCESS) {
    /* Get pointers to pertinent records in registry and handles */
    RegRecPtr = CFE_TBL_TxnRegRec(&Txn);
    // THE TRANSACTION ALLOWED AN ACCESSOR IN AND THIS CHECKS FOR THE OWNER AGAIN. Not
    // redundant: ACCESSOR_APP is satisfied by anyone holding a handle, and only the OWNER may
    // choose where the notification goes.
    /* Verify that the calling application is the table owner */
    if (CFE_ResourceId_Equal(RegRecPtr->OwnerAppId, CFE_TBL_TxnAppId(&Txn))) {
      RegRecPtr->Notify.MsgId = MsgId;
      RegRecPtr->Notify.FcnCode = CommandCode;
      RegRecPtr->Notify.Param = Parameter;
      RegRecPtr->Notify.Enabled = TRUE;
    } else {
      Status = CFE_TBL_ERR_NO_ACCESS;
    }
    CFE_TBL_TxnFinish(&Txn);
  }
  if (Status != CFE_SUCCESS)
    CFE_ES_WriteToSysLog("%s: App=%lu Handle=%lu status code=%lx\n", "CFE_TBL_NotifyByMessage", CFE_TBL_TxnAppIdAsULong(&Txn), CFE_TBL_TxnHandleAsULong(&Txn), Status);
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U32 CFE_TBL_HandleToID(I16 TblHandle)
{
  U32 Result;
  if (CFE_TBL_HANDLE_IS_VALID(TblHandle))
    Result = CFE_TBL_HANDLE_IMPORT(TblHandle);
  else
    Result = CFE_TBL_HANDLEID_UNDEFINED;
  return Result;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I16 CFE_TBL_HandleFromID(U32 TblId)
{
  I16 Result;
  if (CFE_ResourceId_IsDefined(TblId))
    Result = CFE_TBL_HANDLE_EXPORT(TblId);
  else
    Result = CFE_TBL_BAD_TABLE_HANDLE;
  return Result;
}
#endif
