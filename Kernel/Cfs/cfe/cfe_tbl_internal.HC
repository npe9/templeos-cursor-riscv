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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_internal.c -- THE MODULE'S OWN
// MACHINERY: its startup, its memory, its linked lists, and its relationship with the CDS.
// 1,256 lines and thirty-two functions, the largest source in Table Services.
//
// FOUR THINGS LIVE HERE AND THEY ARE ONLY LOOSELY RELATED:
//
//   STARTUP      CFE_TBL_EarlyInit -- two mutexes, a 512 KiB memory pool, four shared load
//                buffers, and an attempt to recover the critical table registry from the CDS.
//   MEMORY       the pool allocator wrappers, and the rule that a buffer belonging to the
//                table is freed differently from one borrowed from the shared pool.
//   THE LIST     the access-descriptor chain, inserted and removed by id rather than pointer.
//   THE CDS      critical tables are mirrored into the critical data store so their contents
//                survive a processor reset, and so is the registry that describes them.
//
// WHY CRITICAL-TABLE FAILURES ARE NOT FATAL, which is the design decision most worth knowing.
// Three times in EarlyInit a CDS operation can fail, and all three are logged and swallowed:
// NASA's comment is "not being able to support Critical Tables is not the end of the world"
// and "failure to support critical tables is not a good enough reason to exit the cFE on
// start up". A vehicle with no persistent store still flies; one that refuses to boot does
// not.
//
// THE LIST IS SPLICED THROUGH A "SAFE LINK" and that is the trick in this file. A doubly
// linked list normally needs a NULL check at each end; here CFE_TBL_HandleListGetSafeLink
// turns a NULL descriptor into a pointer to the registry record's own AccessList head, so
// insert and remove are four unconditional assignments with no special case for the ends.
// The head node is part of the registry record, and the links are handle IDS rather than
// pointers so the record survives being written to the CDS and read back.
#ifndef CFE_TBL_INTERNAL_HC
#define CFE_TBL_INTERNAL_HC
// cfe_error.h
#ifndef CFE_TBL_ERR_NO_BUFFER_AVAIL
#define CFE_TBL_ERR_NO_BUFFER_AVAIL 0xCC00000F(I32)
#define CFE_TBL_INFO_NO_UPDATE_PENDING 0x4C000017
#define CFE_TBL_INFO_TABLE_LOCKED      0x4C000018
#define CFE_TBL_ERR_INVALID_SIZE 0xCC000003(I32)
#define CFE_TBL_ERR_INVALID_OPTIONS 0xCC000025(I32)
#define CFE_TBL_INFO_RECOVERED_TBL     0x4C000027
#endif
#ifndef CFE_STATUS_INCORRECT_STATE
#define CFE_STATUS_INCORRECT_STATE 0xC8000009(I32)
#endif
#ifndef CFE_ES_CDS_ALREADY_EXISTS
#define CFE_ES_CDS_ALREADY_EXISTS 0x4400000D
#endif
#ifndef CFE_TBL_FAIL_NOTIFY_SEND_ERR_EID
#define CFE_TBL_FAIL_NOTIFY_SEND_ERR_EID 89
#endif
// cfe_tbl_api_typedefs.h: the option flags a registration request carries
#ifndef CFE_TBL_OPT_BUFFER_MSK
#define CFE_TBL_OPT_BUFFER_MSK   0x0001
#define CFE_TBL_OPT_SNGL_BUFFER  0x0000
#define CFE_TBL_OPT_DBL_BUFFER   0x0001
#define CFE_TBL_OPT_LD_DMP_MSK   0x0002
#define CFE_TBL_OPT_LOAD_DUMP    0x0000
#define CFE_TBL_OPT_DUMP_ONLY    0x0002
#define CFE_TBL_OPT_USR_DEF_MSK  0x0004
#define CFE_TBL_OPT_NOT_USR_DEF  0x0000
#define CFE_TBL_OPT_USR_DEF_ADDR 0x0006
#define CFE_TBL_OPT_CRITICAL_MSK 0x0008
// CFE_TBL_OPT_DEFAULT is (SNGL_BUFFER | LOAD_DUMP), both of which are ZERO -- so the default
// options word is 0 and every flag is opt-in. check_constants compares the value.
#ifndef CFE_TBL_OPT_DEFAULT
#define CFE_TBL_OPT_DEFAULT 0x0000
#endif
#define CFE_TBL_OPT_NOT_CRITICAL 0x0000
#define CFE_TBL_OPT_CRITICAL     0x0008
#endif
#ifndef CFE_MISSION_TBL_MAX_NAME_LENGTH
#define CFE_MISSION_TBL_MAX_NAME_LENGTH 16
#endif
// --- FORWARD DECLARATIONS ------------------------------------------------------------------
// All defined later in this same file; NASA's cfe_tbl_internal.h supplies the declarations
// there. Kept in NASA's definition order rather than reordered, because unlike the `&function`
// cases in cfe_tbl_accdesc.HC these are ordinary calls and a declaration is enough.
I32 CFE_TBL_AllocateTableLoadBuffer(CFE_TBL_LoadBuff_t *LoadBuffPtr, I64 Size);
U0 CFE_TBL_NotifyTblUsersOfUpdate(CFE_TBL_RegistryRec_t *RegRecPtr);
U0 CFE_TBL_UpdateCriticalTblCDS(CFE_TBL_RegistryRec_t *RegRecPtr);
// cfe_tbl_internal.h offers TWO definitions of each of these, chosen by
// CFE_OMIT_DEPRECATED_6_8: a pass-through pair and the subtract/add pair below. The symbol is
// NOT defined in this configuration -- measured with a probe, not assumed -- so an app's
// CFE_TBL_Handle_t really is an int16 holding the low bits, and the macros really do
// arithmetic against CFE_TBL_HANDLE_BASE. A port that flipped that switch would change every
// handle an application sees. CFE_TBL_HandleID_AsInt collapses onto CFE_ResourceId_ToInteger,
// the same rule check_header_inlines already applies to the typed-id family.
#ifndef CFE_TBL_HANDLE_EXPORT
#define CFE_TBL_HANDLE_EXPORT(x) (CFE_ResourceId_ToInteger(x) - CFE_TBL_HANDLE_BASE)
#endif
#ifndef CFE_TBL_HANDLE_IMPORT
#define CFE_TBL_HANDLE_IMPORT(x) CFE_ResourceId_FromInteger((x) + CFE_TBL_HANDLE_BASE)
#endif
// cfe_tbl_api_typedefs.h, and BOTH OF THESE WERE WRONG IN THE FIRST DRAFT.
//
// CFE_TBL_BAD_TABLE_HANDLE IS -1, NOT ZERO. In the OMIT_DEPRECATED branch it is
// CFE_TBL_HANDLEID_UNDEFINED (zero); in the branch this configuration takes it is
// `((CFE_TBL_Handle_t)(-1))`. check_constants.py caught that one -- `cfe_tbl_api.HC: 0
// NASA: -1`.
//
// AND IS_VALID FOLLOWS FROM IT: `((x) != CFE_TBL_BAD_TABLE_HANDLE)`, NOT
// CFE_TBL_HandleID_IsDefined. The first draft wrote the latter, which tests against ZERO -- so
// handle 0, a perfectly good handle in this branch, would have been reported invalid and
// CFE_TBL_HandleToID(0) would have answered UNDEFINED instead of the base id. **No gate could
// see this**: it is a macro BODY, not a constant value and not a signature, so nothing compares
// it to NASA's. It was fixed by reading the header after the constant check pointed at the line
// above.
#ifndef CFE_TBL_BAD_TABLE_HANDLE
#define CFE_TBL_BAD_TABLE_HANDLE -1
#endif
#ifndef CFE_TBL_HANDLE_IS_VALID
#define CFE_TBL_HANDLE_IS_VALID(x) ((x) != CFE_TBL_BAD_TABLE_HANDLE)
#endif
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_EarlyInit()
{
  U16 i;
  U32 j;
  I32 OsStatus;
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_AccessDescriptor_t *AccessDescPtr;
  CFE_TBL_LoadBuff_t *LoadBuffPtr;
  CFE_TBL_CritRegRec_t *CritRegRecPtr;
  /* Clear task global */
  MemSet(&CFE_TBL_Global, 0, sizeof(CFE_TBL_Global));
  /* Initialize the Table Registry */
  for (i = 0; i < CFE_PLATFORM_TBL_MAX_NUM_TABLES; i++) {
    RegRecPtr = &CFE_TBL_Global.Registry[i];
    CFE_TBL_InitRegistryRecord(RegRecPtr);
  }
  /* Initialize the Table Access Descriptors nonzero values */
  for (i = 0; i < CFE_PLATFORM_TBL_MAX_NUM_HANDLES; i++) {
    AccessDescPtr = &CFE_TBL_Global.Handles[i];
    CFE_TBL_InitAccessDescriptor(AccessDescPtr);
  }
  CFE_TBL_Global.HkTlmTblRegId = CFE_TBL_REGID_UNDEFINED;
  CFE_TBL_Global.LastTblUpdated = CFE_TBL_REGID_UNDEFINED;
  /*
  ** Create table registry access mutex
  */
  OsStatus = OS_MutSemCreate(&CFE_TBL_Global.RegistryMutex, CFE_TBL_MUT_REG_NAME, CFE_TBL_MUT_REG_VALUE);
  if (OsStatus != OS_SUCCESS)
    return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  /*
  ** Create working buffer access mutex
  */
  OsStatus = OS_MutSemCreate(&CFE_TBL_Global.WorkBufMutex, CFE_TBL_MUT_WORK_NAME, CFE_TBL_MUT_WORK_VALUE);
  if (OsStatus != OS_SUCCESS)
    return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  /* Initialize memory partition and allocate shared table buffers. */
  Status = CFE_ES_PoolCreate(&CFE_TBL_Global.Buf.PoolHdl, CFE_TBL_Global.Buf.Partition.Data, sizeof(CFE_TBL_MemPartition_t));
  if (Status < 0) {
    return Status;
  } else {
    /* Initialize each of the shared load buffers */
    for (j = 0; j < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; j++) {
      LoadBuffPtr = &CFE_TBL_Global.LoadBuffs[j];
      /* Allocate memory for shared load buffers */
      Status = CFE_TBL_AllocateTableLoadBuffer(LoadBuffPtr, CFE_PLATFORM_TBL_MAX_SNGL_TABLE_SIZE);
      if (Status != CFE_SUCCESS)
        return Status;
    }
  }
  /* Try to obtain a previous image of the Critical Table Registry from the Critical Data
  ** Store */
  Status = CFE_ES_RegisterCDSEx(&CFE_TBL_Global.CritRegHandle, sizeof(CFE_TBL_CritRegRec_t) * CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES, "CFE_TBL.CritReg", TRUE);
  /* Assume for the moment that nothing is already in the CDS and zero out the Critical Table
  ** Registry */
  for (i = 0; i < CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES; i++) {
    CritRegRecPtr = &CFE_TBL_Global.CritReg[i];
    CritRegRecPtr->CDSHandle = CFE_ES_CDS_BAD_HANDLE;
  }
  // THREE WAYS THE CDS CAN LET US DOWN AND ALL THREE ARE SURVIVABLE. NASA's words: "not being
  // able to support Critical Tables is not the end of the world" and "failure to support
  // critical tables is not a good enough reason to exit the cFE on start up". Every branch
  // below ends with Status = CFE_SUCCESS.
  if (Status == CFE_ES_CDS_ALREADY_EXISTS) {
    /* Try to recover the Critical Table Registry from the CDS */
    Status = CFE_ES_RestoreFromCDS(CFE_TBL_Global.CritReg, CFE_TBL_Global.CritRegHandle);
    if (Status != CFE_SUCCESS) {
      /* Note if we were unable to recover error free Critical Table Registry from the CDS */
      CFE_ES_WriteToSysLog("%s: Failed to recover Critical Table Registry (Err=0x%08X)\n", "CFE_TBL_EarlyInit", Status);
    }
    /* Whether we recovered the Critical Table Registry or not, we are successful with
    ** initialization */
    Status = CFE_SUCCESS;
  } else if (Status != CFE_SUCCESS) {
    /* Not being able to support Critical Tables is not the end of the world */
    /* Note the problem and move on */
    CFE_ES_WriteToSysLog("%s: Failed to create Critical Table Registry (Err=0x%08X)\n", "CFE_TBL_EarlyInit", Status);
    /* Failure to support critical tables is not a good enough reason to exit the cFE on start
    ** up */
    Status = CFE_SUCCESS;
  } else {
    /* Save the initial version of the Critical Table Registry in the CDS */
    Status = CFE_ES_CopyToCDS(CFE_TBL_Global.CritRegHandle, CFE_TBL_Global.CritReg);
    if (Status != CFE_SUCCESS) {
      /* Not being able to support Critical Tables is not the end of the world */
      /* Note the problem and move on */
      CFE_ES_WriteToSysLog("%s: Failed to save Critical Table Registry (Err=0x%08X)\n", "CFE_TBL_EarlyInit", Status);
      /* Failure to support critical tables is not a good enough reason to exit the cFE on
      ** start up */
      Status = CFE_SUCCESS;
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
I32 CFE_TBL_ValidateTableName(CFE_TBL_TableConfig_t *ReqCfg, U8 *TblName, U8 *AppName)
{
  I32 Status;
  I64 Result;
  // TOO LONG AND TOO SHORT IN ONE TEST. MemChr over MAX_NAME_LENGTH finding no NUL means the
  // name does not terminate within the limit, i.e. it is too long; a leading NUL means empty.
  if (TblName[0] == 0 || MemChr(TblName, 0, CFE_MISSION_TBL_MAX_NAME_LENGTH) == NULL) {
    Status = CFE_TBL_ERR_INVALID_NAME;
  } else {
    /* Complete formation of application specific table name */
    Result = StrPrintN(ReqCfg->Name, CFE_TBL_MAX_FULL_NAME_LEN, "%s.%s", AppName, TblName);
    if (Result > CFE_TBL_MAX_FULL_NAME_LEN) {
      /* This means the name was truncated in the snprintf() call, the buffer is too small */
      Status = CFE_TBL_ERR_INVALID_NAME;
    } else {
      Status = CFE_SUCCESS;
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
U0 CFE_TBL_DiscardWorkingBuffer(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  /* If the buffer is NOT one of the buffers "owned" by this table, then it must be
   * from a shared buffer pool so it needs to be released */
  CFE_TBL_LoadBuff_t *LoadBuffPtr;
  U32 LoadInProgressId;
  LoadInProgressId = CFE_TBL_RegRecGetLoadInProgress(RegRecPtr);
  CFE_TBL_RegRecClearLoadInProgress(RegRecPtr);
  if (CFE_TBL_LoadBuffIsShared(LoadInProgressId)) {
    LoadBuffPtr = CFE_TBL_LocateLoadBufferByID(LoadInProgressId);
    if (CFE_TBL_LoadBuffIsMatch(LoadBuffPtr, LoadInProgressId))
      CFE_TBL_LoadBuffSetFree(LoadBuffPtr);
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_DeallocateBuffer(CFE_TBL_LoadBuff_t *BuffPtr)
{
  I32 Status;
  U8 *MemPtr;
  MemPtr = CFE_TBL_LoadBuffGetWritePointer(BuffPtr);
  Status = CFE_ES_PutPoolBuf(CFE_TBL_Global.Buf.PoolHdl, MemPtr);
  if (Status < 0) {
    CFE_ES_WriteToSysLog("%s: PutPoolBuf() Fail Stat=0x%08X, Hndl=0x%08lX, Buf=0x%08lX\n", "CFE_TBL_DeallocateBuffer", Status, CFE_ResourceId_ToInteger(CFE_TBL_Global.Buf.PoolHdl), MemPtr);
  }
  CFE_TBL_LoadBuffSetAllocatedBlock(BuffPtr, NULL, 0);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_DeallocateAllBuffers(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  CFE_TBL_LoadBuff_t *BuffPtr;
  I64 i;
  for (i = 0; i < 2; ++i) {
    BuffPtr = &RegRecPtr->Buffers[i];
    if (CFE_TBL_LoadBuffIsAllocated(BuffPtr)) {
      /* Free memory allocated to buffers */
      CFE_TBL_DeallocateBuffer(BuffPtr);
    }
    CFE_TBL_LoadBuffSetFree(BuffPtr);
  }
  /* If a shared buffer has been allocated to the table, then release it as well */
  CFE_TBL_DiscardWorkingBuffer(RegRecPtr);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U32 CFE_TBL_FindTableInRegistry(U8 *TblName)
{
  CFE_TBL_TxnState_t Txn;
  /* Note: there is no way for transaction setup to fail when passing false for context check */
  CFE_TBL_TxnInit(&Txn, FALSE);
  CFE_TBL_TxnFindRegByName(&Txn, TblName);
  CFE_TBL_TxnFinish(&Txn);
  /* The transaction mechanism will set this to CFE_TBL_NOT_FOUND if anything failed */
  return CFE_TBL_TxnRegId(&Txn);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_LockRegistry()
{
  I32 OsStatus;
  I32 Status;
  OsStatus = OS_MutSemTake(CFE_TBL_Global.RegistryMutex);
  if (OsStatus == OS_SUCCESS)
    Status = CFE_SUCCESS;
  else
    Status = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_UnlockRegistry()
{
  I32 OsStatus;
  I32 Status;
  OsStatus = OS_MutSemGive(CFE_TBL_Global.RegistryMutex);
  if (OsStatus == OS_SUCCESS)
    Status = CFE_SUCCESS;
  else
    Status = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_LoadBuff_t *CFE_TBL_AcquireGlobalLoadBuff(U32 PendingOwnerId)
{
  I32 OsStatus;
  U32 PendingId;
  CFE_TBL_LoadBuff_t *LoadBuffPtr;
  LoadBuffPtr = NULL;
  /* Take Mutex to make sure we are not trying to grab a working buffer that some */
  /* other application is also trying to grab. */
  OsStatus = OS_MutSemTake(CFE_TBL_Global.WorkBufMutex);
  /* Make note of any errors but continue and hope for the best */
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Internal error taking WorkBuf Mutex (Status=%ld)\n", "CFE_TBL_AcquireGlobalLoadBuff", OsStatus);
  }
  /* Determine if there are any common buffers available */
  PendingId = CFE_TBL_FindNextSharedBufferId();
  LoadBuffPtr = CFE_TBL_LocateLoadBufferByID(PendingId);
  if (LoadBuffPtr != NULL) {
    /* Claim it as ours */
    CFE_TBL_LoadBuffSetUsed(LoadBuffPtr, PendingId, PendingOwnerId);
    CFE_TBL_Global.LastLoadBuffId = PendingId;
  }
  /* Allow others to obtain a shared working buffer */
  OS_MutSemGive(CFE_TBL_Global.WorkBufMutex);
  return LoadBuffPtr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_GetWorkingBuffer(CFE_TBL_LoadBuff_t **WorkingBufferPtr, CFE_TBL_RegistryRec_t *RegRecPtr)
{
  CFE_TBL_LoadBuff_t *LoadBuffPtr;
  /* If a load is already in progress, return the previously allocated working buffer */
  LoadBuffPtr = CFE_TBL_GetLoadInProgressBuffer(RegRecPtr);
  if (LoadBuffPtr == NULL) {
    /* load was not in progress */
    if (!CFE_TBL_RegRecIsTableLoaded(RegRecPtr)) {
      /* If the table is uninitialized and the function is called by an application (rather
      ** than by the Table Services application), then use the current active buffer as the
      ** working buffer. This allows many tasks with many tables to perform the initialization
      ** without conflict over the accessibility of the shared working buffers. */
      LoadBuffPtr = CFE_TBL_GetInactiveBufferExclusive(RegRecPtr);
    } else {
      LoadBuffPtr = CFE_TBL_PrepareNewLoadBuff(RegRecPtr);
    }
    if (LoadBuffPtr != NULL) {
      /*
      ** store the resource ID (generic form) in NextBufferId - this allows
      ** it to refer to either a shared buffer or a local table buffer
      */
      CFE_TBL_RegRecSetLoadInProgress(RegRecPtr, CFE_TBL_LoadBufferGetID(LoadBuffPtr));
    }
  }
  if (WorkingBufferPtr != NULL)
    *WorkingBufferPtr = LoadBuffPtr;
  if (LoadBuffPtr == NULL)
    return CFE_TBL_ERR_NO_BUFFER_AVAIL;
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_UpdateInternal(U32 TblHandle, CFE_TBL_RegistryRec_t *RegRecPtr, CFE_TBL_AccessDescriptor_t *AccessDescPtr)
{
  I32 Status = CFE_SUCCESS;
  CFE_TBL_LoadBuff_t *NextBuffPtr;
  CFE_TBL_LoadBuff_t *LoadBuffPtr;
  CFE_TBL_TableConfig_t *CfgPtr;
  no_warn TblHandle;
  NextBuffPtr = NULL;
  LoadBuffPtr = CFE_TBL_GetLoadInProgressBuffer(RegRecPtr);
  if (LoadBuffPtr == NULL) {
    /* Question: Should calling CFE_TBL_Update on a table with no load pending */
    /* be considered an error?  Currently assuming it is not an error.         */
    Status = CFE_TBL_INFO_NO_UPDATE_PENDING;
  } else {
    /*
    ** If the load buffer is a DEDICATED buffer for this table registry (not a shared buf),
    ** then it can be simply activated by setting it active buffer ref to it.  This will
    ** always be true for double buffered tables, because they just flip-flop between two
    ** dedicated table buffers; they never use shared buffers for loading.  For single
    ** buffered tables this is also true during the first initial load, where a temp buffer
    ** is not necessary
    */
    if (CFE_TBL_LoadBuffIsPrivate(CFE_TBL_LoadBufferGetID(LoadBuffPtr), CFE_TBL_RegRecGetID(RegRecPtr))) {
      NextBuffPtr = LoadBuffPtr;
    } else {
      /*
      ** This gets a new identifier and also makes sure nobody is using the buffer
      ** via a shared table handle at this time.  The only way this can fail is
      ** if there is an active shared table reference to this buffer.
      */
      NextBuffPtr = CFE_TBL_GetInactiveBufferExclusive(RegRecPtr);
      if (NextBuffPtr == NULL) {
        Status = CFE_TBL_INFO_TABLE_LOCKED;
        CFE_ES_WriteToSysLog("%s: Unable to update locked table Handle=%lu
", "CFE_TBL_UpdateInternal", CFE_ResourceId_ToInteger(CFE_TBL_AccDescGetHandle(AccessDescPtr)));
      }
    }
  }
  if (NextBuffPtr != NULL) {
    /*
    ** To update a single buffered table requires a memcpy from working buffer,
    ** but in a double buffered table they will point to the same LoadBuff, so
    ** all the copies can be skipped (this is the advantage of double-buffering)
    */
    if (NextBuffPtr != LoadBuffPtr) {
      CFE_TBL_LoadBuffCopyData(NextBuffPtr, CFE_TBL_LoadBuffGetReadPointer(LoadBuffPtr), CFE_TBL_LoadBuffGetContentSize(LoadBuffPtr));
      /* Save source description with active buffer (Note - structs are same type, length
      ** already checked) */
      StrNCpy(NextBuffPtr->DataSource, LoadBuffPtr->DataSource, OS_MAX_PATH_LEN);
      /* Save the file creation time from the loaded file into the Table Registry */
      NextBuffPtr->FileTime = LoadBuffPtr->FileTime;
      /* Save the previously computed CRC into the new buffer */
      NextBuffPtr->Crc = LoadBuffPtr->Crc;
    }
    CFE_TBL_SetActiveBuffer(RegRecPtr, NextBuffPtr);
    CFE_TBL_RegRecResetLoadInfo(RegRecPtr, NextBuffPtr->DataSource, CFE_TIME_GetTime());
    CFE_TBL_NotifyTblUsersOfUpdate(RegRecPtr);
    /* If the table is a critical table, update the appropriate CDS with the new data */
    CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr);
    // limit 17
    if (CfgPtr->Critical)
      CFE_TBL_UpdateCriticalTblCDS(RegRecPtr);
    CFE_TBL_DiscardWorkingBuffer(RegRecPtr);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Local helper function, not invoked outside this unit
 * Intended to be used with CFE_TBL_ForeachAccessDescriptor()
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_SetUpdatedHelper(CFE_TBL_AccessDescriptor_t *AccDescPtr, U8 *Arg)
{
  no_warn Arg;
  AccDescPtr->Updated = TRUE;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_NotifyTblUsersOfUpdate(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  CFE_TBL_ForeachAccessDescriptor(RegRecPtr, &CFE_TBL_SetUpdatedHelper, NULL);
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_CleanUpApp(U32 Id)
{
  U32 i;
  CFE_TBL_TxnState_t Txn;
  CFE_TBL_DumpControl_t *DumpCtrlPtr;
  CFE_TBL_AccessDescriptor_t *AccessDescPtr;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  I32 Status;
  U32 AppId;
  AppId = CFE_ResourceId_FromInteger(Id);
  CFE_TBL_TxnInit(&Txn, FALSE);
  /* Scan Dump Requests to determine if any of the tables that */
  /* were to be dumped will be deleted */
  CFE_TBL_TxnLockRegistry(&Txn);
  for (i = 0; i < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; i++) {
    DumpCtrlPtr = &CFE_TBL_Global.DumpControlBlocks[i];
    /* Check to see if the table to be dumped is owned by the App to be deleted */
    if (CFE_TBL_DumpCtrlBlockIsUsed(DumpCtrlPtr)) {
      RegRecPtr = CFE_TBL_LoadBuffGetRegRecFromId(DumpCtrlPtr->SourceBuffId);
      if (RegRecPtr != NULL && CFE_ResourceId_Equal(RegRecPtr->OwnerAppId, AppId)) {
        /* If so, then remove the dump request */
        CFE_TBL_DumpCtrlBlockSetFree(DumpCtrlPtr);
      }
    }
  }
  CFE_TBL_TxnFinish(&Txn);
  /* Scan Access Descriptors to determine if the Application had access to any tables */
  for (i = 0; i < CFE_PLATFORM_TBL_MAX_NUM_HANDLES; i++) {
    AccessDescPtr = &CFE_TBL_Global.Handles[i];
    Status = CFE_TBL_TxnStartFromHandle(&Txn, CFE_TBL_AccDescGetHandle(AccessDescPtr), CFE_TBL_TxnContext_UNDEFINED);
    if (Status == CFE_SUCCESS) {
      /* This transaction is being performed on behalf of the appid that is now gone away */
      Txn.AppId = AppId;
      /* Check to see if the Handle belongs to the Application being deleted */
      if (CFE_ResourceId_Equal(AccessDescPtr->AppId, Txn.AppId)) {
        /* Release the access descriptor and clean up refs */
        CFE_TBL_TxnReleaseAccDesc(&Txn);
      }
      CFE_TBL_TxnFinish(&Txn);
    }
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_FindCriticalTblInfo(CFE_TBL_CritRegRec_t **CritRegRecPtr, U32 CDSHandleToFind)
{
  U32 i;
  CFE_TBL_CritRegRec_t *LocalPtr;
  /* Assume the record is never found */
  *CritRegRecPtr = NULL;
  for (i = 0; i < CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES; i++) {
    LocalPtr = &CFE_TBL_Global.CritReg[i];
    if (CFE_ResourceId_Equal(LocalPtr->CDSHandle, CDSHandleToFind)) {
      *CritRegRecPtr = LocalPtr;
      break;
    }
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_UpdateCriticalTblCDS(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  CFE_TBL_CritRegRec_t *CritRegRecPtr = NULL;
  CFE_TBL_LoadBuff_t *ActiveBufPtr;
  I32 Status;
  /* Copy an image of the updated table to the CDS for safekeeping */
  ActiveBufPtr = CFE_TBL_GetActiveBuffer(RegRecPtr);
  if (ActiveBufPtr == NULL) {
    /* cannot write a table to CDS if it was never loaded in the first place */
    Status = CFE_TBL_ERR_NEVER_LOADED;
  } else {
    Status = CFE_ES_CopyToCDS(RegRecPtr->CDSHandle, CFE_TBL_LoadBuffGetReadPointer(ActiveBufPtr));
  }
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Unable to update Critical Table '%s' in CDS (Err=0x%08X)
", "CFE_TBL_UpdateCriticalTblCDS", CFE_TBL_RegRecGetName(RegRecPtr), Status);
  } else {
    /* Locate entry in Critical Table Registry */
    CFE_TBL_FindCriticalTblInfo(&CritRegRecPtr, RegRecPtr->CDSHandle);
    if (CritRegRecPtr != NULL) {
      /* Save information related to the source of the data stored in the table in Critical
      ** Table Registry */
      CritRegRecPtr->FileTime = ActiveBufPtr->FileTime;
      StrNCpy(CritRegRecPtr->LastFileLoaded, CFE_TBL_RegRecGetLastFileLoaded(RegRecPtr), OS_MAX_PATH_LEN - 1);
      CritRegRecPtr->LastFileLoaded[OS_MAX_PATH_LEN - 1] = '\0';
      CritRegRecPtr->TimeOfLastUpdate = CFE_TBL_RegRecGetLastUpdateTime(RegRecPtr);
      CritRegRecPtr->TableLoadedOnce = CFE_TBL_RegRecIsTableLoaded(RegRecPtr);
      /* Update copy of Critical Table Registry in the CDS */
      Status = CFE_ES_CopyToCDS(CFE_TBL_Global.CritRegHandle, CFE_TBL_Global.CritReg);
      if (Status != CFE_SUCCESS) {
        CFE_ES_WriteToSysLog("%s: Unable to update Critical Table Registry in CDS (Err=0x%08X)
", "CFE_TBL_UpdateCriticalTblCDS", Status);
      }
    } else {
      CFE_ES_WriteToSysLog("%s: Error finding '%s' in Critical Table Registry
", "CFE_TBL_UpdateCriticalTblCDS", CFE_TBL_RegRecGetName(RegRecPtr));
    }
  }
  /* Don't bother notifying the caller of the problem since the active table is still
  ** legitimate */
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_SendNotificationMsg(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  I32 Status;
  /* First, determine if a message should be sent */
  if (RegRecPtr->Notify.Enabled) {
    /* Set the message ID */
    CFE_MSG_SetMsgId(&CFE_TBL_Global.NotifyMsg.CommandHeader.Msg, RegRecPtr->Notify.MsgId);
    /* Set the command code */
    CFE_MSG_SetFcnCode(&CFE_TBL_Global.NotifyMsg.CommandHeader.Msg, RegRecPtr->Notify.FcnCode);
    /* Set the command parameter */
    CFE_TBL_Global.NotifyMsg.Payload.Parameter = RegRecPtr->Notify.Param;
    CFE_SB_TimeStampMsg(&CFE_TBL_Global.NotifyMsg.CommandHeader.Msg);
    Status = CFE_SB_TransmitMsg(&CFE_TBL_Global.NotifyMsg.CommandHeader.Msg, TRUE);
    if (Status != CFE_SUCCESS) {
      CFE_EVS_SendEvent(CFE_TBL_FAIL_NOTIFY_SEND_ERR_EID, CFE_EVS_EventType_ERROR, "Manage Notification Pkt Error(Status=0x%08X)", Status);
    }
  } else {
    /* This is not really an "error" - it just means that notifications are not enabled */
    Status = CFE_STATUS_INCORRECT_STATE;
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ValidateTableSize(CFE_TBL_TableConfig_t *TableCfg, I64 Size)
{
  I32 Status;
  I64 SizeLimit;
  /* Single-buffered tables are allowed to be up to CFE_PLATFORM_TBL_MAX_SNGL_TABLE_SIZE   */
  /* Double-buffered tables are allowed to be up to CFE_PLATFORM_TBL_MAX_DBL_TABLE_SIZE    */
  if (TableCfg->DoubleBuffered)
    SizeLimit = CFE_PLATFORM_TBL_MAX_DBL_TABLE_SIZE;
  else
    SizeLimit = CFE_PLATFORM_TBL_MAX_SNGL_TABLE_SIZE;
  /* Check if the specified table size is zero, or above the maximum allowed               */
  if (Size == 0 || Size > SizeLimit) {
    Status = CFE_TBL_ERR_INVALID_SIZE;
  } else {
    Status = CFE_SUCCESS;
    TableCfg->Size = Size;
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ValidateTableOptions(CFE_TBL_TableConfig_t *TableCfg, U16 TblOptionFlags)
{
  I32 Status;
  /* This will be changed if validation fails */
  Status = CFE_SUCCESS;
  TableCfg->DoubleBuffered = (TblOptionFlags & CFE_TBL_OPT_BUFFER_MSK) == CFE_TBL_OPT_DBL_BUFFER;
  TableCfg->UserDefAddr = (TblOptionFlags & CFE_TBL_OPT_USR_DEF_MSK) == (CFE_TBL_OPT_USR_DEF_ADDR & CFE_TBL_OPT_USR_DEF_MSK);
  TableCfg->DumpOnly = (TblOptionFlags & CFE_TBL_OPT_LD_DMP_MSK) == CFE_TBL_OPT_DUMP_ONLY;
  TableCfg->Critical = (TblOptionFlags & CFE_TBL_OPT_CRITICAL_MSK) == CFE_TBL_OPT_CRITICAL;
  // THE TWO COMBINATIONS THAT ARE REFUSED, and USR_DEF_ADDR is 0x6 -- it INCLUDES the
  // dump-only bit, so asking for a user-defined address implies dump-only and the second
  // branch below can only be reached by a caller who set 0x4 without 0x2.
  /* Now check the specific combination of options that are not valid */
  if (TableCfg->DumpOnly) {
    /* Dump Only tables cannot be double-buffered, nor critical (this also applies to
    ** user-defined address) */
    if (TableCfg->DoubleBuffered || TableCfg->Critical)
      Status = CFE_TBL_ERR_INVALID_OPTIONS;
  } else if (TableCfg->UserDefAddr) {
    /* User-defined table addresses are only legal for dump-only tables */
    Status = CFE_TBL_ERR_INVALID_OPTIONS;
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_AllocateTableLoadBuffer(CFE_TBL_LoadBuff_t *LoadBuffPtr, I64 Size)
{
  I32 Status;
  U8 *MemPtr;
  /* Allocate the memory buffer(s) for the table and inactive table, if necessary */
  Status = CFE_ES_GetPoolBuf(&MemPtr, CFE_TBL_Global.Buf.PoolHdl, Size);
  if (Status < 0) {
    CFE_ES_WriteToSysLog("%s: Buf Alloc GetPool fail Stat=0x%08X MemPoolHndl=0x%08lX
", "CFE_TBL_AllocateTableLoadBuffer", Status, CFE_ResourceId_ToInteger(CFE_TBL_Global.Buf.PoolHdl));
  } else {
    Status = CFE_SUCCESS;
    CFE_TBL_LoadBuffSetAllocatedBlock(LoadBuffPtr, MemPtr, Size);
    CFE_TBL_LoadBuffClearData(LoadBuffPtr);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_MarkNameAsModified(U8 *NameBufPtr, I64 NameBufSize)
{
  // APPENDS "(*)" AND WILL OVERWRITE THE TAIL TO FIT. EndPtr is the NUL, pulled back to
  // NameBufSize-4 if the name is too long to take three more characters -- so a maximal name
  // loses its last characters rather than the marker being dropped. The marker matters more
  // than the name: it is what tells an operator the table is not what the file said.
  U8 *EndPtr;
  EndPtr = MemChr(NameBufPtr, 0, NameBufSize);
  if (EndPtr - NameBufPtr > NameBufSize - 4)
    EndPtr = &NameBufPtr[NameBufSize - 4];
  StrCpy(EndPtr, "(*)");
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_SetupTableBuffers(CFE_TBL_RegistryRec_t *RegRecPtr, CFE_TBL_TableConfig_t *ReqCfg)
{
  I32 Status;
  /* If requested a dump-only table, set that flag now.
   * NOTE: other option flags are set when that feature is actually enabled,
   * but this one does not require any special enablement other than the flag */
  RegRecPtr->Config.DumpOnly = ReqCfg->DumpOnly;
  if (ReqCfg->UserDefAddr) {
    RegRecPtr->Config.UserDefAddr = TRUE;
    /* nothing more to do when using user-defined address (no local buffer) */
    Status = CFE_SUCCESS;
  } else {
    /* Allocate the local buffer for storing table content */
    Status = CFE_TBL_AllocateTableLoadBuffer(&RegRecPtr->Buffers[0], ReqCfg->Size);
    /* Secondary only needed on double buffered tables */
    if (Status == CFE_SUCCESS && ReqCfg->DoubleBuffered) {
      Status = CFE_TBL_AllocateTableLoadBuffer(&RegRecPtr->Buffers[1], ReqCfg->Size);
      if (Status == CFE_SUCCESS) {
        /* double buffering was set up successfully */
        RegRecPtr->Config.DoubleBuffered = TRUE;
      }
    }
  }
  if (Status == CFE_SUCCESS) {
    /* Save the size of the table */
    RegRecPtr->Config.Size = ReqCfg->Size;
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_RestoreTableDataFromCDS(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  I32 Status = CFE_SUCCESS;
  CFE_TBL_CritRegRec_t *CritRegRecPtr;
  CFE_TBL_LoadBuff_t *WorkingBufferPtr;
  Status = CFE_TBL_GetWorkingBuffer(&WorkingBufferPtr, RegRecPtr);
  if (Status != CFE_SUCCESS) {
    /* Unable to get a working buffer - this error is not really */
    /* possible at this point during table registration.  But we */
    /* do need to handle the error case because if the function */
    /* call did fail, WorkingBufferPtr would be a NULL pointer. */
    CFE_ES_WriteToSysLog("%s: Failed to get work buffer for '%s' (ErrCode=0x%08X)\n", "CFE_TBL_RestoreTableDataFromCDS", CFE_TBL_RegRecGetName(RegRecPtr), Status);
  } else {
    /* CDS exists for this table - try to restore the data */
    Status = CFE_ES_RestoreFromCDS(CFE_TBL_LoadBuffGetWritePointer(WorkingBufferPtr), RegRecPtr->CDSHandle);
    if (Status != CFE_SUCCESS) {
      CFE_ES_WriteToSysLog("%s: Failed to recover '%s' from CDS (ErrCode=0x%08X)\n", "CFE_TBL_RestoreTableDataFromCDS", CFE_TBL_RegRecGetName(RegRecPtr), Status);
      /*
      ** Treat a restore from existing CDS error the same as
      ** after a power-on reset (CDS was created but is empty)
      */
      Status = CFE_SUCCESS;
    } else {
      /* Table was fully restored from existing CDS... */
      /* Try to locate the associated information in the Critical Table Registry */
      CFE_TBL_FindCriticalTblInfo(&CritRegRecPtr, RegRecPtr->CDSHandle);
      if (CritRegRecPtr != NULL && CritRegRecPtr->TableLoadedOnce) {
        StrNCpy(WorkingBufferPtr->DataSource, CritRegRecPtr->LastFileLoaded, OS_MAX_PATH_LEN - 1);
        WorkingBufferPtr->DataSource[OS_MAX_PATH_LEN - 1] = '\0';
        WorkingBufferPtr->FileTime = CritRegRecPtr->FileTime;
        CFE_TBL_SetActiveBuffer(RegRecPtr, WorkingBufferPtr);
        CFE_TBL_RegRecClearLoadInProgress(RegRecPtr);
        CFE_TBL_RegRecResetLoadInfo(RegRecPtr, CritRegRecPtr->LastFileLoaded, CritRegRecPtr->TimeOfLastUpdate);
        /* Compute the CRC on the specified table buffer */
        CFE_TBL_LoadBuffRecomputeCRC(WorkingBufferPtr);
        /* Make sure everyone who sees the table knows that it has been updated */
        CFE_TBL_NotifyTblUsersOfUpdate(RegRecPtr);
        /* Make sure the caller realizes the contents have been initialized */
        Status = CFE_TBL_INFO_RECOVERED_TBL;
      } else {
        /* If an error occurred while trying to get the previous contents registry info, */
        /* Log the error in the System Log and pretend like we created a new CDS */
        CFE_ES_WriteToSysLog("%s: Failed to recover '%s' info from CDS TblReg\n", "CFE_TBL_RestoreTableDataFromCDS", CFE_TBL_RegRecGetName(RegRecPtr));
        Status = CFE_SUCCESS;
      }
    }
  }
  /* Mark the table as critical for future reference */
  RegRecPtr->Config.Critical = TRUE;
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_RegisterWithCriticalTableRegistry(CFE_TBL_CritRegRec_t *CritRegRecPtr, CFE_TBL_RegistryRec_t *RegRecPtr, U8 *TblName)
{
  /* Find and initialize a free entry in the Critical Table Registry */
  // THE PARAMETER IS OVERWRITTEN IMMEDIATELY, which is NASA's code and not a slip here:
  // whatever the caller passed in CritRegRecPtr is discarded and replaced by the first free
  // entry. The parameter is effectively an out-value that is passed by value, so the caller
  // never sees it -- the function communicates only through the CDS and RegRecPtr.
  CFE_TBL_FindCriticalTblInfo(&CritRegRecPtr, CFE_ES_CDS_BAD_HANDLE);
  if (CritRegRecPtr != NULL) {
    CritRegRecPtr->CDSHandle = RegRecPtr->CDSHandle;
    StrNCpy(CritRegRecPtr->Name, TblName, CFE_TBL_MAX_FULL_NAME_LEN - 1);
    CritRegRecPtr->Name[CFE_TBL_MAX_FULL_NAME_LEN - 1] = '\0';
    CritRegRecPtr->LastFileLoaded[0] = '\0';
    // CFE_TIME_ZERO_VALUE is a C compound literal, `(CFE_TIME_SysTime_t){0, 0}`, which HolyC
    // has no spelling for; the two fields are assigned instead.
    CritRegRecPtr->FileTime.Seconds = 0;
    CritRegRecPtr->FileTime.Subseconds = 0;
    CritRegRecPtr->TimeOfLastUpdate.Seconds = 0;
    CritRegRecPtr->TimeOfLastUpdate.Subseconds = 0;
    CFE_ES_CopyToCDS(CFE_TBL_Global.CritRegHandle, CFE_TBL_Global.CritReg);
  } else {
    CFE_ES_WriteToSysLog("%s: Failed to find a free Crit Tbl Reg Rec for '%s'\n", "CFE_TBL_RegisterWithCriticalTableRegistry", CFE_TBL_RegRecGetName(RegRecPtr));
  }
  /* Mark the table as critical for future reference */
  RegRecPtr->Config.Critical = TRUE;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_AccessDescriptor_t *CFE_TBL_HandleListGetNext(CFE_TBL_HandleLink_t *Link)
{
  return CFE_TBL_LocateAccDescByHandle(Link->Next);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_AccessDescriptor_t *CFE_TBL_HandleListGetPrev(CFE_TBL_HandleLink_t *Link)
{
  return CFE_TBL_LocateAccDescByHandle(Link->Prev);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_HandleListGetSafeLink(CFE_TBL_RegistryRec_t *RegRecPtr, CFE_TBL_AccessDescriptor_t *AccDescPtr, CFE_TBL_HandleLink_t **PtrOut, U32 *HandleOut)
{
  // THE WHOLE TRICK OF THE LIST. A NULL descriptor -- meaning "off the end" -- is turned into
  // a pointer to the registry record's OWN AccessList head rather than being reported as
  // NULL. So Insert and Remove below are four unconditional assignments with no special case
  // for either end of the list, and the head node is simply a link that lives in the record.
  if (AccDescPtr == NULL) {
    /* Instead of returning NULL, return a pointer to the head node linkage */
    *PtrOut = &RegRecPtr->AccessList;
    *HandleOut = CFE_TBL_HANDLEID_UNDEFINED;
  } else {
    /* Return a pointer to this linkage */
    *PtrOut = &AccDescPtr->Link;
    *HandleOut = CFE_TBL_AccDescGetHandle(AccDescPtr);
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_HandleListRemoveLink(CFE_TBL_RegistryRec_t *RegRecPtr, CFE_TBL_AccessDescriptor_t *AccessDescPtr)
{
  CFE_TBL_HandleLink_t *LocalLink;
  CFE_TBL_HandleLink_t *LocalPrevPtr;
  CFE_TBL_HandleLink_t *LocalNextPtr;
  U32 LocalHandle;
  U32 PrevHandle;
  U32 NextHandle;
  CFE_TBL_HandleListGetSafeLink(RegRecPtr, AccessDescPtr, &LocalLink, &LocalHandle);
  CFE_TBL_HandleListGetSafeLink(RegRecPtr, CFE_TBL_HandleListGetNext(LocalLink), &LocalNextPtr, &NextHandle);
  CFE_TBL_HandleListGetSafeLink(RegRecPtr, CFE_TBL_HandleListGetPrev(LocalLink), &LocalPrevPtr, &PrevHandle);
  LocalPrevPtr->Next = NextHandle;
  LocalNextPtr->Prev = PrevHandle;
  no_warn LocalHandle;
  /* now that it is removed, reset the link */
  CFE_TBL_HandleLinkInit(LocalLink);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_HandleListInsertLink(CFE_TBL_RegistryRec_t *RegRecPtr, CFE_TBL_AccessDescriptor_t *AccessDescPtr)
{
  CFE_TBL_HandleLink_t *LocalLink;
  CFE_TBL_HandleLink_t *LocalPrevPtr;
  CFE_TBL_HandleLink_t *LocalNextPtr;
  U32 LocalHandle;
  U32 PrevHandle;
  U32 NextHandle;
  /* inserting at the front, so the "previous" will always be the head node (NULL) */
  CFE_TBL_HandleListGetSafeLink(RegRecPtr, AccessDescPtr, &LocalLink, &LocalHandle);
  CFE_TBL_HandleListGetSafeLink(RegRecPtr, NULL, &LocalPrevPtr, &PrevHandle);
  CFE_TBL_HandleListGetSafeLink(RegRecPtr, CFE_TBL_HandleListGetNext(LocalPrevPtr), &LocalNextPtr, &NextHandle);
  LocalLink->Next = NextHandle;
  LocalLink->Prev = PrevHandle;
  LocalPrevPtr->Next = LocalHandle;
  LocalNextPtr->Prev = LocalHandle;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_ForeachAccessDescriptor(CFE_TBL_RegistryRec_t *RegRecPtr, U0 (*Func)(CFE_TBL_AccessDescriptor_t *, U8 *), U8 *Arg)
{
  CFE_TBL_AccessDescriptor_t *AccDescPtr;
  CFE_TBL_HandleLink_t *LinkPtr;
  LinkPtr = &RegRecPtr->AccessList;
  while (TRUE) {
    AccDescPtr = CFE_TBL_HandleListGetNext(LinkPtr);
    if (AccDescPtr == NULL)
      break;
    Func(AccDescPtr, Arg);
    LinkPtr = &AccDescPtr->Link;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * Intended to be used with CFE_TBL_ForeachAccessDescriptor()
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_CountAccessDescHelper(CFE_TBL_AccessDescriptor_t *AccDescPtr, U8 *Arg)
{
  U32 *Count = Arg;
  no_warn AccDescPtr;
  ++* Count;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_ValidationResult_t *CFE_TBL_CheckValidationRequest(U32 *ValIdPtr)
{
  CFE_TBL_ValidationResult_t *ResultPtr;
  U32 ValId;
  ValId = *ValIdPtr;
  /*
  ** always clear the flag, regardless of "IsMatch" above.  If it was not a match,
  ** that means the ID was stale, and it will never be a match (ie. it was aborted somehow)
  **
  ** However, because this also acts as a flag, only write to the global if it was set to a
  ** value, do not unconditionally write undefined value here.
  */
  if (CFE_TBL_VALRESULTID_IS_VALID(ValId)) {
    *ValIdPtr = CFE_TBL_VALRESULTID_UNDEFINED;
    ResultPtr = CFE_TBL_LocateValidationResultByID(ValId);
  } else {
    ResultPtr = NULL;
  }
  if (!CFE_TBL_ValidationResultIsMatch(ResultPtr, ValId))
    ResultPtr = NULL;
  return ResultPtr;
}

// --- CONSTANTS NASA'S HEADER DECLARES AND NO SOURCE USES -------------------------------------
//
// Dead upstream: a grep across every .c in the repository finds CFE_TBL_NOT_FOUND only in comments and a doc \\retval. They are translated anyway
// because they are part of the header's declared interface and cost nothing, which is the answer
// that needs no judgement -- and because tools/cfs/check_defines.py now refuses a #define that is
// nowhere in the translation. That gate was written after a case-sensitive grep silently dropped
// EIGHT of HS's event ids; these nineteen are what it found on its first run, across six years of
// this port's history.
#define CFE_TBL_NOT_FOUND CFE_TBL_REGID_UNDEFINED

#endif
