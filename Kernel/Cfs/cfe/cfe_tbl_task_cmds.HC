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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_task_cmds.c -- THE GROUND COMMANDS.
// Ten handlers plus the housekeeping packer, the registry packer and the two background-dump
// callbacks. This is what an operator's commands actually reach.
//
// EVERY HANDLER RETURNS CFE_SUCCESS, AND THAT IS THE DESIGN. CFE_TBL_TranslateCmdProcRet is the
// whole convention: a handler decides whether to bump the command counter, the error counter or
// neither, and then the STATUS it returns says only "there is nothing left for the dispatcher
// to do". NASA's comment spells it out -- "the status code should be CFE_SUCCESS because there
// is nothing more to do - even if the command itself had failed". So a failed command is not a
// failed return; it is an incremented error counter and an event.
//
//   CFE_TBL_CmdProcRet_INC_ERR_CTR   -1   bump CommandErrorCounter
//   CFE_TBL_CmdProcRet_INC_CMD_CTR    0   bump CommandCounter
//   CFE_TBL_CmdProcRet_DONT_INC_CTR   1   bump neither (the reset command)
//
// EVERY HANDLER ALSO ASSUMES FAILURE FIRST. `CmdProcRet = INC_ERR_CTR` is the first statement of
// nine of the ten, and success has to be reached explicitly. A path that forgets to set it
// counts as an error, which is the right default for a ground command.
//
// AND EVERY STRING FROM THE GROUND GOES THROUGH CFE_SB_MessageStringGet FIRST, into a local,
// because a command packet's name field is NOT guaranteed to be NUL-terminated. That call is the
// only thing standing between a malformed uplink and a buffer walk.
//
// THE REGISTRY DUMP IS A BACKGROUND JOB, not a loop here: CFE_TBL_DumpRegistryCmd fills in a
// request and hands it to CFE_FS_BackgroundFileDumpRequest, and the two callbacks below --
// CFE_TBL_DumpRegistryGetter and CFE_TBL_DumpRegistryEventHandler -- run later in the ES
// background task, NOT in the TBL task. NASA's comment says why the handler must use
// CFE_EVS_SendEventWithAppID rather than CFE_EVS_SendEvent: in that context the "current app"
// is ES, so the event would be misattributed.
#ifndef CFE_TBL_TASK_CMDS_HC
#define CFE_TBL_TASK_CMDS_HC
// cfe_tbl_task_cmds.h: the three-valued return the handlers speak. Negative, zero and positive
// rather than an ordinary 0/1/2 enum, which is why CFE_TBL_TranslateCmdProcRet tests for two of
// the three and leaves the rest alone.
#ifndef CFE_TBL_CmdProcRet_INC_ERR_CTR
#define CFE_TBL_CmdProcRet_INC_ERR_CTR  -1
#define CFE_TBL_CmdProcRet_INC_CMD_CTR  0
#define CFE_TBL_CmdProcRet_DONT_INC_CTR 1
#endif
// cfe_tbl_eventids.h -- the seventeen this file raises
#ifndef CFE_TBL_NOOP_INF_EID
#define CFE_TBL_NOOP_INF_EID 10
#endif
#ifndef CFE_TBL_RESET_INF_EID
#define CFE_TBL_RESET_INF_EID 11
#endif
#ifndef CFE_TBL_OVERWRITE_REG_DUMP_INF_EID
#define CFE_TBL_OVERWRITE_REG_DUMP_INF_EID 15
#endif
#ifndef CFE_TBL_VAL_REQ_MADE_INF_EID
#define CFE_TBL_VAL_REQ_MADE_INF_EID 16
#endif
#ifndef CFE_TBL_LOAD_PEND_REQ_INF_EID
#define CFE_TBL_LOAD_PEND_REQ_INF_EID 17
#endif
#ifndef CFE_TBL_TLM_REG_CMD_INF_EID
#define CFE_TBL_TLM_REG_CMD_INF_EID 18
#endif
#ifndef CFE_TBL_WRITE_REG_DUMP_INF_EID
#define CFE_TBL_WRITE_REG_DUMP_INF_EID 22
#endif
#ifndef CFE_TBL_CDS_DELETED_INFO_EID
#define CFE_TBL_CDS_DELETED_INFO_EID 38
#endif
#ifndef CFE_TBL_FAIL_HK_SEND_ERR_EID
#define CFE_TBL_FAIL_HK_SEND_ERR_EID 56
#endif
#ifndef CFE_TBL_WRITE_TBL_REG_ERR_EID
#define CFE_TBL_WRITE_TBL_REG_ERR_EID 68
#endif
#ifndef CFE_TBL_LOAD_ABORT_ERR_EID
#define CFE_TBL_LOAD_ABORT_ERR_EID 69
#endif
#ifndef CFE_TBL_IN_REGISTRY_ERR_EID
#define CFE_TBL_IN_REGISTRY_ERR_EID 82
#endif
#ifndef CFE_TBL_NOT_CRITICAL_TBL_ERR_EID
#define CFE_TBL_NOT_CRITICAL_TBL_ERR_EID 83
#endif
#ifndef CFE_TBL_NOT_IN_CRIT_REG_ERR_EID
#define CFE_TBL_NOT_IN_CRIT_REG_ERR_EID 84
#endif
#ifndef CFE_TBL_CDS_NOT_FOUND_ERR_EID
#define CFE_TBL_CDS_NOT_FOUND_ERR_EID 85
#endif
#ifndef CFE_TBL_CDS_DELETE_ERR_EID
#define CFE_TBL_CDS_DELETE_ERR_EID 86
#endif
#ifndef CFE_TBL_CDS_OWNER_ACTIVE_ERR_EID
#define CFE_TBL_CDS_OWNER_ACTIVE_ERR_EID 87
#endif
// cfe_tbl_internal_cfg.h
#ifndef CFE_PLATFORM_TBL_DEFAULT_REG_DUMP_FILE
#define CFE_PLATFORM_TBL_DEFAULT_REG_DUMP_FILE "/ram/cfe_tbl_reg.log"
#endif
/*----------------------------------------------------------------
 *
 * Internal helper function
 * Not invoked outside of this unit
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TranslateCmdProcRet(I32 ReturnCode)
{
  I32 Status;
  /*
   * In the context of command handlers, the status should indicate if there
   * is any notification or cleanup yet to perform.  If all related events have
   * been sent and all counters have been incremented, then the status code
   * should be CFE_SUCCESS because there is nothing more to do - even if the command
   * itself had failed.
   */
  Status = CFE_SUCCESS;
  if (ReturnCode == CFE_TBL_CmdProcRet_INC_CMD_CTR) {
    /* No errors detected and increment command counter */
    CFE_TBL_Global.CommandCounter++;
  } else if (ReturnCode == CFE_TBL_CmdProcRet_INC_ERR_CTR) {
    /* Error detected in (or while processing) message, increment command error counter */
    CFE_TBL_Global.CommandErrorCounter++;
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_SendHkCmd(CFE_TBL_SendHkCmd_t *data)
{
  I32 Status;
  no_warn data;
  /*
  ** Collect housekeeping data from Table Services
  */
  CFE_TBL_GetHkData();
  /*
  ** Send housekeeping telemetry packet
  */
  CFE_SB_TimeStampMsg(&CFE_TBL_Global.HkPacket.TelemetryHeader.Msg);
  Status = CFE_SB_TransmitMsg(&CFE_TBL_Global.HkPacket.TelemetryHeader.Msg, TRUE);
  if (Status != CFE_SUCCESS)
    CFE_EVS_SendEvent(CFE_TBL_FAIL_HK_SEND_ERR_EID, CFE_EVS_EventType_ERROR, "Unable to send Hk Packet (Status=0x%08X)", Status);
  /* If a table's registry entry has been requested for telemetry, then pack it and send it */
  if (CFE_TBL_REGID_IS_VALID(CFE_TBL_Global.HkTlmTblRegId)) {
    CFE_TBL_GetTblRegData();
    /*
    ** Send Table Registry Info Packet
    */
    CFE_SB_TimeStampMsg(&CFE_TBL_Global.TblRegPacket.TelemetryHeader.Msg);
    CFE_SB_TransmitMsg(&CFE_TBL_Global.TblRegPacket.TelemetryHeader.Msg, TRUE);
    /* Once the data has been sent, clear the index so that we don't send it again and again */
    CFE_TBL_Global.HkTlmTblRegId = CFE_TBL_REGID_UNDEFINED;
  }
  // THE HOUSEKEEPING WAKEUP IS WHAT DRIVES A DUMP TO DISK. NASA calls it "a convenient time";
  // it is the only caller of CFE_TBL_TableDumpExecuteBackground in flight code, so a dump
  // requested by CFE_TBL_DumpCmd is written when the next HK request arrives and not before.
  /* this wakeup is a convenient time to process pending table dumps */
  CFE_TBL_TableDumpExecuteBackground();
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_GetHkData()
{
  U32 i;
  U16 Count;
  CFE_TBL_ValidationResult_t *ValPtr;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *LoadBuffPtr;
  /* Copy command counter data */
  CFE_TBL_Global.HkPacket.Payload.CommandCounter = CFE_TBL_Global.CommandCounter;
  CFE_TBL_Global.HkPacket.Payload.CommandErrorCounter = CFE_TBL_Global.CommandErrorCounter;
  CFE_TBL_Global.HkPacket.Payload.FailedValCounter = CFE_TBL_Global.FailedValCounter;
  CFE_TBL_Global.HkPacket.Payload.NumLoadPending = 0;
  CFE_TBL_Global.HkPacket.Payload.MemPoolHandle = CFE_TBL_Global.Buf.PoolHdl;
  /* Determine the number of tables currently registered and Number of Load Pending Tables */
  Count = 0;
  for (i = 0; i < CFE_PLATFORM_TBL_MAX_NUM_TABLES; i++) {
    RegRecPtr = &CFE_TBL_Global.Registry[i];
    if (CFE_TBL_RegRecIsUsed(RegRecPtr)) {
      ++Count;
      if (CFE_TBL_RegRecIsLoadInProgress(RegRecPtr))
        CFE_TBL_Global.HkPacket.Payload.NumLoadPending++;
    }
  }
  CFE_TBL_Global.HkPacket.Payload.NumTables = Count;
  // AND THE FREE COUNT IS THE COMPLEMENT OF THE USED COUNT, not a count of free ones -- so a
  // buffer in a state the loop does not recognise is reported as FREE. Worth knowing when
  // reading telemetry.
  /* Determine the number of free shared buffers */
  Count = 0;
  for (i = 0; i < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; i++) {
    LoadBuffPtr = &CFE_TBL_Global.LoadBuffs[i];
    if (CFE_TBL_LoadBuffIsUsed(LoadBuffPtr))
      ++Count;
  }
  CFE_TBL_Global.HkPacket.Payload.NumFreeSharedBufs = CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS - Count;
  // THE VALIDATION SEARCH IS A while(TRUE) WITH TWO EXITS AND IT LEAVES ValPtr MEANINGFUL. The
  // bound check comes FIRST and sets ValPtr to NULL before breaking, so falling off the end is
  // distinguishable from finding one. Written this way rather than as a for-loop because the
  // found POINTER is what the block below needs, not the index.
  /* Locate a completed, but unreported, validation request */
  i = 0;
  ValPtr = NULL;
  while (TRUE) {
    if (i >= CFE_PLATFORM_TBL_MAX_NUM_VALIDATIONS) {
      ValPtr = NULL;
      break;
    }
    ValPtr = &CFE_TBL_Global.ValidationResults[i];
    if (CFE_TBL_ValidationResultIsUsed(ValPtr) && ValPtr->State == CFE_TBL_VALIDATION_PERFORMED)
      break;
    ++i;
  }
  if (ValPtr != NULL) {
    CFE_TBL_Global.HkPacket.Payload.LastValCrc = ValPtr->CrcOfTable;
    CFE_TBL_Global.HkPacket.Payload.LastValStatus = ValPtr->Result;
    CFE_TBL_Global.HkPacket.Payload.ActiveBuffer = ValPtr->BufferSelect == CFE_TBL_BufferSelect_ACTIVE;
    /* Keep track of the number of failed and successful validations */
    if (ValPtr->Result == CFE_SUCCESS)
      CFE_TBL_Global.SuccessValCounter++;
    else
      CFE_TBL_Global.FailedValCounter++;
    CFE_SB_MessageStringSet(CFE_TBL_Global.HkPacket.Payload.LastValTableName, ValPtr->TableName, CFE_MISSION_TBL_MAX_FULL_NAME_LEN, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    CFE_TBL_Global.ValidationCounter++;
    /* Free the Validation Response Block for next time */
    ValPtr->Result = 0;
    ValPtr->CrcOfTable = 0;
    ValPtr->TableName[0] = '\0';
    ValPtr->BufferSelect = CFE_TBL_BufferSelect_INACTIVE;
    CFE_TBL_ValidationResultSetFree(ValPtr);
  }
  CFE_TBL_Global.HkPacket.Payload.ValidationCounter = CFE_TBL_Global.ValidationCounter;
  CFE_TBL_Global.HkPacket.Payload.SuccessValCounter = CFE_TBL_Global.SuccessValCounter;
  CFE_TBL_Global.HkPacket.Payload.FailedValCounter = CFE_TBL_Global.FailedValCounter;
  CFE_TBL_Global.HkPacket.Payload.NumValRequests = CFE_TBL_Global.NumValRequests;
  RegRecPtr = CFE_TBL_LocateRegRecByID(CFE_TBL_Global.LastTblUpdated);
  /* Check to make sure the Registry Entry is still valid */
  if (CFE_TBL_RegRecIsMatch(RegRecPtr, CFE_TBL_Global.LastTblUpdated)) {
    /* Get the time at the last table update */
    CFE_TBL_Global.HkPacket.Payload.LastUpdateTime = CFE_TBL_RegRecGetLastUpdateTime(RegRecPtr);
    /* Get the table name used for the last table update */
    CFE_SB_MessageStringSet(CFE_TBL_Global.HkPacket.Payload.LastUpdatedTable, CFE_TBL_RegRecGetName(RegRecPtr), CFE_MISSION_TBL_MAX_FULL_NAME_LEN, -1);
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_GetTblRegData()
{
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *BuffPtr;
  CFE_TBL_TableConfig_t *CfgPtr;
  CFE_TBL_LockRegistry();
  RegRecPtr = CFE_TBL_LocateRegRecByID(CFE_TBL_Global.HkTlmTblRegId);
  if (CFE_TBL_RegRecIsMatch(RegRecPtr, CFE_TBL_Global.HkTlmTblRegId)) {
    CFE_TBL_Global.TblRegPacket.Payload.Size = CFE_TBL_RegRecGetSize(RegRecPtr);
    BuffPtr = CFE_TBL_GetActiveBuffer(RegRecPtr);
    /* The active buffer may be NULL if the table has never been loaded */
    if (BuffPtr != NULL) {
      CFE_TBL_Global.TblRegPacket.Payload.ActiveBufferAddr = CFE_TBL_LoadBuffGetReadPointer(BuffPtr);
      CFE_TBL_Global.TblRegPacket.Payload.FileTime = BuffPtr->FileTime;
      CFE_TBL_Global.TblRegPacket.Payload.Crc = BuffPtr->Crc;
    } else {
      CFE_TBL_Global.TblRegPacket.Payload.ActiveBufferAddr = 0;
    }
    BuffPtr = CFE_TBL_GetInactiveBuffer(RegRecPtr);
    /* the inactive buffer is typically NULL in a single-buffer table */
    if (BuffPtr != NULL) {
      CFE_TBL_Global.TblRegPacket.Payload.InactiveBufferAddr = CFE_TBL_LoadBuffGetReadPointer(BuffPtr);
    } else {
      CFE_TBL_Global.TblRegPacket.Payload.InactiveBufferAddr = 0;
    }
    // HOISTED, limit 17: NASA reads CFE_TBL_RegRecGetConfig(RegRecPtr)->field inline for the
    // three option flags below.
    CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr);
    CFE_TBL_Global.TblRegPacket.Payload.ValidationFuncPtr = CFE_TBL_RegRecGetValidationFunc(RegRecPtr);
    CFE_TBL_Global.TblRegPacket.Payload.TimeOfLastUpdate = CFE_TBL_RegRecGetLastUpdateTime(RegRecPtr);
    CFE_TBL_Global.TblRegPacket.Payload.TableLoadedOnce = CFE_TBL_RegRecIsTableLoaded(RegRecPtr);
    CFE_TBL_Global.TblRegPacket.Payload.LoadPending = CFE_TBL_RegRecIsPendingActivation(RegRecPtr);
    CFE_TBL_Global.TblRegPacket.Payload.DumpOnly = CfgPtr->DumpOnly;
    CFE_TBL_Global.TblRegPacket.Payload.DoubleBuffered = CfgPtr->DoubleBuffered;
    CFE_TBL_Global.TblRegPacket.Payload.Critical = CfgPtr->Critical;
    CFE_SB_MessageStringSet(CFE_TBL_Global.TblRegPacket.Payload.Name, CFE_TBL_RegRecGetName(RegRecPtr), CFE_MISSION_TBL_MAX_FULL_NAME_LEN, -1);
    CFE_SB_MessageStringSet(CFE_TBL_Global.TblRegPacket.Payload.LastFileLoaded, CFE_TBL_RegRecGetLastFileLoaded(RegRecPtr), CFE_MISSION_MAX_PATH_LEN, -1);
    CFE_ES_GetAppName(CFE_TBL_Global.TblRegPacket.Payload.OwnerAppName, RegRecPtr->OwnerAppId, CFE_MISSION_MAX_API_LEN);
  }
  CFE_TBL_UnlockRegistry();
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_NoopCmd(CFE_TBL_NoopCmd_t *data)
{
  I32 CmdProcRet;
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];
  no_warn data;
  /* No-op commands always succeed */
  CmdProcRet = CFE_TBL_CmdProcRet_INC_CMD_CTR;
  /* Acknowledge receipt of NOOP with Event Message */
  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "CFE_TBL", CFE_SRC_VERSION, CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);
  CFE_EVS_SendEvent(CFE_TBL_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION, "No-op Cmd Rcvd: %s", VersionString);
  return CFE_TBL_TranslateCmdProcRet(CmdProcRet);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ResetCountersCmd(CFE_TBL_ResetCountersCmd_t *data)
{
  I32 CmdProcRet;
  no_warn data;
  // THE ONLY HANDLER THAT USES DONT_INC_CTR, for the obvious reason: it has just zeroed the
  // counters and bumping one would leave CommandCounter at 1 after a reset.
  /* Reset counter commands never increment the counter */
  CmdProcRet = CFE_TBL_CmdProcRet_DONT_INC_CTR;
  CFE_TBL_Global.CommandCounter = 0;
  CFE_TBL_Global.CommandErrorCounter = 0;
  CFE_TBL_Global.SuccessValCounter = 0;
  CFE_TBL_Global.FailedValCounter = 0;
  CFE_TBL_Global.NumValRequests = 0;
  CFE_TBL_Global.ValidationCounter = 0;
  CFE_EVS_SendEvent(CFE_TBL_RESET_INF_EID, CFE_EVS_EventType_DEBUG, "Reset Counters command");
  return CFE_TBL_TranslateCmdProcRet(CmdProcRet);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_LoadCmd(CFE_TBL_LoadCmd_t *data)
{
  I32 CmdProcRet;
  CFE_TBL_LoadCmd_Payload_t *CmdPtr;
  CFE_TBL_CombinedFileHdr_t Header;
  U32 FileDescriptor;
  I32 Status;
  U8 LoadFilename[OS_MAX_PATH_LEN];
  CFE_TBL_TxnState_t Txn;
  /* just in case, clear out the header */
  MemSet(&Header, 0, sizeof(CFE_TBL_CombinedFileHdr_t));
  CmdProcRet = CFE_TBL_CmdProcRet_INC_ERR_CTR;
  /* Assume failure */
  CmdPtr = &data->Payload;
  /* Make sure all strings are null terminated before attempting to process them */
  CFE_SB_MessageStringGet(LoadFilename, CmdPtr->LoadFilename, NULL, OS_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN);
  CFE_TBL_TxnInit(&Txn, TRUE);
  /* Try to open the specified table file */
  Status = CFE_TBL_TxnOpenTableLoadFile(&Txn, LoadFilename, &FileDescriptor, &Header);
  if (Status == CFE_SUCCESS) {
    // THE TABLE NAME COMES OUT OF THE FILE, NOT THE COMMAND. A load command names only a FILE;
    // which table it lands in is whatever the file's header says. NASA's comment notes the
    // header reader has already NUL-terminated it, which is why it can be passed straight on.
    /* Locate specified table in registry (wrapped in a lock) */
    /* NOTE: The header reading code ensures null term on the table name string, so its OK to
     * pass direct */
    CFE_TBL_TxnLockRegistry(&Txn);
    Status = CFE_TBL_TxnFindRegByName(&Txn, Header.Tbl.TableName);
    if (Status == CFE_SUCCESS) {
      /* Perform a sanity check on the table state */
      Status = CFE_TBL_ValidateLoadRequest(&Txn, CFE_TBL_SRC_FILE);
    }
    CFE_TBL_TxnUnlockRegistry(&Txn);
    if (Status == CFE_SUCCESS)
      Status = CFE_TBL_ValidateFileIsLoadable(&Txn, &Header.Tbl);
    if (Status == CFE_SUCCESS) {
      /* Read the file content into the working buffer */
      Status = CFE_TBL_LoadContentFromFile(&Txn, FileDescriptor, Header.Tbl.Offset, Header.Tbl.NumBytes);
    }
    /* Done with the file now -- must always close the file regardless of what happened */
    OS_close(FileDescriptor);
  }
  /* If all the above worked out, then set the meta info in the load buffer */
  if (Status == CFE_SUCCESS)
    CFE_TBL_SetMetaDataFromFileHeader(&Txn, LoadFilename, &Header.Std);
  CFE_TBL_TxnFinish(&Txn);
  if (Status == CFE_SUCCESS) {
    /* Save file information statistics for housekeeping telemetry */
    CFE_SB_MessageStringSet(CFE_TBL_Global.HkPacket.Payload.LastFileLoaded, LoadFilename, CFE_MISSION_MAX_PATH_LEN, OS_MAX_PATH_LEN);
    CFE_SB_MessageStringSet(CFE_TBL_Global.HkPacket.Payload.LastTableLoaded, Header.Tbl.TableName, CFE_MISSION_TBL_MAX_FULL_NAME_LEN, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    /* Increment successful command completion counter */
    CmdProcRet = CFE_TBL_CmdProcRet_INC_CMD_CTR;
    /* Report the successful event */
    CFE_TBL_TxnAddEvent(&Txn, CFE_TBL_FILE_LOADED_INF_EID, 0, 0);
  }
  // NOTE THE EVENT IS QUEUED **AFTER** CFE_TBL_TxnFinish, which is NASA's code: TxnFinish drops
  // the registry lock but does not clear the event list, so the success event added above is
  // still sent by the call below. The ordering looks wrong and is not.
  /* Send any events associated with this table load */
  CFE_TBL_SendTableLoadFileEvents(&Txn, LoadFilename, &Header);
  return CFE_TBL_TranslateCmdProcRet(CmdProcRet);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_DumpCmd(CFE_TBL_DumpCmd_t *data)
{
  I32 CmdProcRet;
  CFE_TBL_TxnState_t Txn;
  CFE_TBL_DumpCmd_Payload_t *CmdPtr = &data->Payload;
  U8 DumpFilename[OS_MAX_PATH_LEN];
  U8 TableName[CFE_TBL_MAX_FULL_NAME_LEN];
  I32 Status;
  U32 DumpCtrlId;
  CmdProcRet = CFE_TBL_CmdProcRet_INC_ERR_CTR;
  /* Assume failure */
  /* Make sure all strings are null terminated before attempting to process them */
  CFE_SB_MessageStringGet(DumpFilename, CmdPtr->DumpFilename, NULL, OS_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN);
  CFE_SB_MessageStringGet(TableName, CmdPtr->TableName, NULL, CFE_TBL_MAX_FULL_NAME_LEN, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  /* Before doing anything, lets make sure the table that is to be dumped exists */
  /* Note - if successful, this returns with the registry in a locked state */
  Status = CFE_TBL_TxnStartFromName(&Txn, TableName, CFE_TBL_TxnContext_UNDEFINED);
  if (Status != CFE_SUCCESS) {
    /* Table could not be found in Registry */
    CFE_EVS_SendEvent(CFE_TBL_NO_SUCH_TABLE_ERR_EID, CFE_EVS_EventType_ERROR, "Unable to locate '%s' in Table Registry", TableName);
  } else {
    /* Reserve a dump control block and populate it with the details */
    Status = CFE_TBL_AllocateDumpCtrlBlock(&Txn, &DumpCtrlId, CmdPtr->ActiveTableFlag);
    /* Done modifying registry for now */
    CFE_TBL_TxnUnlockRegistry(&Txn);
    if (Status == CFE_SUCCESS) {
      /* Complete the process */
      Status = CFE_TBL_PrepareDumpSnapshotBuffer(&Txn, DumpCtrlId, DumpFilename);
    }
    CFE_TBL_TxnFinish(&Txn);
  }
  /* Translate return code */
  if (Status == CFE_SUCCESS)
    CmdProcRet = CFE_TBL_CmdProcRet_INC_CMD_CTR;
  /* Send any events associated with this table dump */
  CFE_TBL_SendTableDumpEvents(&Txn, DumpFilename, TableName);
  return CFE_TBL_TranslateCmdProcRet(CmdProcRet);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ValidateCmd(CFE_TBL_ValidateCmd_t *data)
{
  I32 CmdProcRet;
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  CFE_TBL_ValidateCmd_Payload_t *CmdPtr = &data->Payload;
  U8 TableName[CFE_TBL_MAX_FULL_NAME_LEN];
  CFE_TBL_ValidationResult_t *ValResultPtr;
  Bool CreatedRequest;
  CmdProcRet = CFE_TBL_CmdProcRet_INC_ERR_CTR;
  /* Assume failure */
  ValResultPtr = NULL;
  CreatedRequest = FALSE;
  /* Make sure all strings are null terminated before attempting to process them */
  CFE_SB_MessageStringGet(TableName, CmdPtr->TableName, NULL, CFE_TBL_MAX_FULL_NAME_LEN, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  /* Before doing anything, lets make sure the table that is to be dumped exists */
  Status = CFE_TBL_TxnStartFromName(&Txn, TableName, CFE_TBL_TxnContext_UNDEFINED);
  if (Status == CFE_SUCCESS) {
    /* Check if there is already a validation request pending */
    ValResultPtr = CFE_TBL_TxnCheckValidationRequest(&Txn);
    if (ValResultPtr == NULL) {
      ValResultPtr = CFE_TBL_TxnSetupValidationRequest(&Txn, CmdPtr->ActiveTableFlag);
      // CreatedRequest IS FALSE WHEN THE VALIDATION ALREADY RAN. NASA's comment: the setup call
      // "might have validated directly or set up for the application to do the validation at
      // the next call to CFE_TBL_Manage()". Only the deferred case notifies the owner, because
      // in the immediate case there is nothing left for the owner to do.
      /* The above might have validated directly or set up for the application to do the
       * validation at the next call to CFE_TBL_Manage().  If it is the latter, a debug event is
       * generated to indicate that the deferred validation request is pending. */
      CreatedRequest = ValResultPtr != NULL && ValResultPtr->State != CFE_TBL_VALIDATION_PERFORMED;
    }
    CFE_TBL_TxnFinish(&Txn);
    if (ValResultPtr != NULL) {
      /* Increment Successful Command Counter */
      CmdProcRet = CFE_TBL_CmdProcRet_INC_CMD_CTR;
      /* If application requested notification by message, then do so */
      if (CreatedRequest && CFE_TBL_SendNotificationMsg(CFE_TBL_TxnRegRec(&Txn)) == CFE_SUCCESS) {
        /* Notify ground that validation request has been made */
        CFE_EVS_SendEvent(CFE_TBL_VAL_REQ_MADE_INF_EID, CFE_EVS_EventType_DEBUG, "Tbl Services issued validation request for '%s'", TableName);
      }
    }
  }
  /* Send any events associated with this table validation request */
  CFE_TBL_SendValidationEvents(&Txn);
  return CFE_TBL_TranslateCmdProcRet(CmdProcRet);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ActivateCmd(CFE_TBL_ActivateCmd_t *data)
{
  I32 CmdProcRet;
  CFE_TBL_ActivateCmd_Payload_t *CmdPtr = &data->Payload;
  U8 TableName[CFE_TBL_MAX_FULL_NAME_LEN];
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  CFE_TBL_LoadBuff_t *ActivatedBufPtr;
  CmdProcRet = CFE_TBL_CmdProcRet_INC_ERR_CTR;
  /* Assume failure */
  /* Make sure all strings are null terminated before attempting to process them */
  CFE_SB_MessageStringGet(TableName, CmdPtr->TableName, NULL, CFE_TBL_MAX_FULL_NAME_LEN, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  /* Before doing anything, lets make sure the table that is to be dumped exists */
  Status = CFE_TBL_TxnStartFromName(&Txn, TableName, CFE_TBL_TxnContext_UNDEFINED);
  if (Status == CFE_SUCCESS) {
    ActivatedBufPtr = CFE_TBL_TxnSetupActivationRequest(&Txn);
    CFE_TBL_TxnFinish(&Txn);
    /* If application requested notification by message, then do so */
    if (ActivatedBufPtr != NULL) {
      if (CFE_TBL_SendNotificationMsg(CFE_TBL_TxnRegRec(&Txn)) == CFE_SUCCESS)
        CFE_EVS_SendEvent(CFE_TBL_LOAD_PEND_REQ_INF_EID, CFE_EVS_EventType_DEBUG, "Tbl Services notifying App that '%s' has a load pending", TableName);
      /* Increment Successful Command Counter */
      CmdProcRet = CFE_TBL_CmdProcRet_INC_CMD_CTR;
    }
    // CFE_TBL_TxnFinish IS CALLED TWICE ON THIS PATH, which is NASA's code. The second call is
    // harmless -- Finish only drops a lock it still holds -- but it is not intentional
    // bookkeeping either. Kept verbatim.
    CFE_TBL_TxnFinish(&Txn);
  }
  /* Send any events associated with this table activation request */
  CFE_TBL_SendActivationEvents(&Txn);
  return CFE_TBL_TranslateCmdProcRet(CmdProcRet);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_DumpRegistryGetter(U8 *Meta, U32 RecordNum, U8 **Buffer, I64 *BufSize)
{
  CFE_TBL_RegDumpStateInfo_t *StatePtr = Meta;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *BufferPtr;
  CFE_TBL_TableConfig_t *CfgPtr;
  U32 OwnerAppId;
  U32 NumUsers;
  Bool IsValidEntry;
  IsValidEntry = FALSE;
  OwnerAppId = CFE_ES_APPID_UNDEFINED;
  if (RecordNum < CFE_PLATFORM_TBL_MAX_NUM_TABLES) {
    /* Make a pointer to simplify code look and to remove redundant indexing into registry */
    RegRecPtr = &CFE_TBL_Global.Registry[RecordNum];
    /* should lock registry while copying out data to ensure its in consistent state */
    CFE_TBL_LockRegistry();
    /* Check to see if the Registry entry is empty */
    if (CFE_TBL_RegRecIsUsed(RegRecPtr)) {
      IsValidEntry = TRUE;
      OwnerAppId = RegRecPtr->OwnerAppId;
      // HOISTED, limit 17, three times.
      CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr);
      /* Fill Registry Dump Record with relevant information */
      StatePtr->DumpRecord.Size = CFE_TBL_RegRecGetSize(RegRecPtr);
      StatePtr->DumpRecord.TimeOfLastUpdate = CFE_TBL_RegRecGetLastUpdateTime(RegRecPtr);
      StatePtr->DumpRecord.ValidationFunc = CFE_TBL_RegRecGetValidationFunc(RegRecPtr) != NULL;
      StatePtr->DumpRecord.TableLoadedOnce = CFE_TBL_RegRecIsTableLoaded(RegRecPtr);
      StatePtr->DumpRecord.LoadPending = CFE_TBL_RegRecIsPendingActivation(RegRecPtr);
      StatePtr->DumpRecord.DumpOnly = CfgPtr->DumpOnly;
      StatePtr->DumpRecord.DoubleBuffered = CfgPtr->DoubleBuffered;
      StatePtr->DumpRecord.CriticalTable = CfgPtr->Critical;
      /* Convert LoadInProgress ID into historically-compatible integer value */
      StatePtr->DumpRecord.LoadInProgress = CFE_TBL_LoadBuffIdToTlmIndex(CFE_TBL_RegRecGetLoadInProgress(RegRecPtr));
      /* Note that the active buffer may be NULL if the table was never loaded */
      BufferPtr = CFE_TBL_GetActiveBuffer(RegRecPtr);
      if (BufferPtr == NULL) {
        // CFE_TIME_ZERO_VALUE is a C compound literal; the two fields are assigned instead.
        StatePtr->DumpRecord.FileTime.Seconds = 0;
        StatePtr->DumpRecord.FileTime.Subseconds = 0;
        StatePtr->DumpRecord.Crc = 0;
      } else {
        StatePtr->DumpRecord.FileTime = BufferPtr->FileTime;
        StatePtr->DumpRecord.Crc = BufferPtr->Crc;
      }
      CFE_SB_MessageStringSet(StatePtr->DumpRecord.Name, CFE_TBL_RegRecGetName(RegRecPtr), CFE_MISSION_TBL_MAX_FULL_NAME_LEN, -1);
      CFE_SB_MessageStringSet(StatePtr->DumpRecord.LastFileLoaded, CFE_TBL_RegRecGetLastFileLoaded(RegRecPtr), CFE_MISSION_MAX_PATH_LEN, -1);
      /* Walk the access descriptor list to determine the number of users */
      NumUsers = 0;
      CFE_TBL_ForeachAccessDescriptor(RegRecPtr, &CFE_TBL_CountAccessDescHelper, &NumUsers);
      StatePtr->DumpRecord.NumUsers = NumUsers;
    }
    /* Unlock now - remainder of data gathering uses ES */
    CFE_TBL_UnlockRegistry();
  }
  /*
   * If table record had data, then export now.
   * Need to also get the App name from ES to complete the record.
   */
  if (IsValidEntry) {
    /* Determine the name of the owning application */
    if (!CFE_ResourceId_Equal(OwnerAppId, CFE_TBL_NOT_OWNED)) {
      CFE_ES_GetAppName(StatePtr->DumpRecord.OwnerAppName, OwnerAppId, CFE_MISSION_MAX_API_LEN);
    } else {
      StrNCpy(StatePtr->DumpRecord.OwnerAppName, "--UNOWNED--", CFE_MISSION_MAX_API_LEN - 1);
      StatePtr->DumpRecord.OwnerAppName[CFE_MISSION_MAX_API_LEN - 1] = 0;
    }
    /* export data to caller */
    *Buffer = &StatePtr->DumpRecord;
    *BufSize = sizeof(CFE_TBL_RegDumpRec_t);
  } else {
    /* No data to write for this record */
    *BufSize = 0;
    *Buffer = NULL;
  }
  // THE RETURN VALUE IS "IS THIS THE LAST RECORD", NOT "DID I WRITE ANYTHING". An empty
  // registry slot returns FALSE with BufSize 0, and the background writer keeps going; only the
  // LAST index ends the job. That is how a sparse registry dumps without holes.
  /* Check for EOF (last entry) */
  return RecordNum >= CFE_PLATFORM_TBL_MAX_NUM_TABLES - 1;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_DumpRegistryEventHandler(U8 *Meta, U32 Event, I32 Status, U32 RecordNum, I64 BlockSize, I64 Position)
{
  CFE_TBL_RegDumpStateInfo_t *StatePtr = Meta;
  no_warn BlockSize;
  /*
   * Note that this runs in the context of ES background task (file writer background job)
   * It does NOT run in the context of the CFE_TBL app task.
   *
   * Events should use CFE_EVS_SendEventWithAppID() rather than CFE_EVS_SendEvent()
   * to get proper association with TBL task.
   */
  switch (Event) {
    case CFE_FS_FileWriteEvent_COMPLETE :
    if (StatePtr->FileExisted) {
      CFE_EVS_SendEventWithAppID(CFE_TBL_OVERWRITE_REG_DUMP_INF_EID, CFE_EVS_EventType_DEBUG, CFE_TBL_Global.TableTaskAppId, "Successfully overwrote '%s' with Table Registry:Size=%d,Entries=%d", StatePtr->FileWrite.FileName, Position, RecordNum);
    } else {
      CFE_EVS_SendEventWithAppID(CFE_TBL_WRITE_REG_DUMP_INF_EID, CFE_EVS_EventType_DEBUG, CFE_TBL_Global.TableTaskAppId, "Successfully dumped Table Registry to '%s':Size=%d,Entries=%d", StatePtr->FileWrite.FileName, Position, RecordNum);
    }
    break;
    case CFE_FS_FileWriteEvent_RECORD_WRITE_ERROR :
    CFE_EVS_SendEventWithAppID(CFE_TBL_WRITE_TBL_REG_ERR_EID, CFE_EVS_EventType_ERROR, CFE_TBL_Global.TableTaskAppId, "Error writing Registry to '%s', Status=0x%08X", StatePtr->FileWrite.FileName, Status);
    break;
    case CFE_FS_FileWriteEvent_HEADER_WRITE_ERROR :
    CFE_EVS_SendEventWithAppID(CFE_TBL_WRITE_CFE_HDR_ERR_EID, CFE_EVS_EventType_ERROR, CFE_TBL_Global.TableTaskAppId, "Error writing cFE File Header to '%s', Status=0x%08X", StatePtr->FileWrite.FileName, Status);
    break;
    case CFE_FS_FileWriteEvent_CREATE_ERROR :
    CFE_EVS_SendEventWithAppID(CFE_TBL_CREATING_DUMP_FILE_ERR_EID, CFE_EVS_EventType_ERROR, CFE_TBL_Global.TableTaskAppId, "Error creating dump file '%s', Status=0x%08X", StatePtr->FileWrite.FileName, Status);
    break;
    default:
    /* unhandled event - ignore */
    break;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_DumpRegistryCmd(CFE_TBL_DumpRegistryCmd_t *data)
{
  I32 CmdProcRet;
  I32 Status;
  CFE_TBL_DumpRegistryCmd_Payload_t *CmdPtr = &data->Payload;
  os_fstat_t FileStat;
  CFE_TBL_RegDumpStateInfo_t *StatePtr;
  CmdProcRet = CFE_TBL_CmdProcRet_INC_ERR_CTR;
  /* Assume failure */
  StatePtr = &CFE_TBL_Global.RegDumpState;
  // A SECOND REQUEST WHILE ONE IS PENDING IS SILENTLY DROPPED -- no event, and the error
  // counter still goes up because CmdProcRet was never changed. That is the whole `if`: NASA
  // will not overwrite a request the background task has not finished with.
  /* If a reg dump was already pending, do not overwrite the current request */
  if (!CFE_FS_BackgroundFileDumpIsPending(&StatePtr->FileWrite)) {
    /*
     * Fill out the remainder of meta data.
     * This data is currently the same for every request
     */
    StatePtr->FileWrite.FileSubType = CFE_FS_SubType_TBL_REG;
    StrPrintN(StatePtr->FileWrite.Description, CFE_FS_HDR_DESC_MAX_LEN, "Table Registry");
    StatePtr->FileWrite.GetData = &CFE_TBL_DumpRegistryGetter;
    StatePtr->FileWrite.OnEvent = &CFE_TBL_DumpRegistryEventHandler;
    /*
    ** Copy the filename into local buffer with default name/path/extension if not specified
    */
    Status = CFE_FS_ParseInputFileNameEx(StatePtr->FileWrite.FileName, CmdPtr->DumpFilename, OS_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, CFE_PLATFORM_TBL_DEFAULT_REG_DUMP_FILE, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_BINARY_DATA_DUMP), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_BINARY_DATA_DUMP));
    if (Status == CFE_SUCCESS) {
      /*
       * Before submitting the background request, use OS_stat() to check if the file exists
       * already.
       *
       * This is needed because TBL services issues a different event ID in some cases if
       * it is overwriting a file vs. creating a new file.
       */
      StatePtr->FileExisted = OS_stat(StatePtr->FileWrite.FileName, &FileStat) == OS_SUCCESS;
      Status = CFE_FS_BackgroundFileDumpRequest(&StatePtr->FileWrite);
      if (Status == CFE_SUCCESS) {
        /* Increment the TBL generic command counter (successfully queued for background job) */
        CmdProcRet = CFE_TBL_CmdProcRet_INC_CMD_CTR;
      }
    }
  }
  return CFE_TBL_TranslateCmdProcRet(CmdProcRet);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_SendRegistryCmd(CFE_TBL_SendRegistryCmd_t *data)
{
  I32 CmdProcRet;
  CFE_TBL_SendRegistryCmd_Payload_t *CmdPtr = &data->Payload;
  U8 TableName[CFE_TBL_MAX_FULL_NAME_LEN];
  CFE_TBL_TxnState_t Txn;
  I32 Status;
  CmdProcRet = CFE_TBL_CmdProcRet_INC_ERR_CTR;
  /* Assume failure */
  /* Make sure all strings are null terminated before attempting to process them */
  CFE_SB_MessageStringGet(TableName, CmdPtr->TableName, NULL, CFE_TBL_MAX_FULL_NAME_LEN, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  /* Before doing anything, lets make sure the table registry entry that is to be telemetered
   * exists */
  Status = CFE_TBL_TxnStartFromName(&Txn, TableName, CFE_TBL_TxnContext_UNDEFINED);
  if (Status == CFE_SUCCESS) {
    // THIS COMMAND ONLY SETS A FLAG. The registry packet is not built or sent here -- the next
    // housekeeping request sees HkTlmTblRegId is valid, packs it, sends it, and clears the id so
    // it is sent exactly once.
    /* Change the index used to identify what data is to be telemetered */
    CFE_TBL_Global.HkTlmTblRegId = CFE_TBL_TxnRegId(&Txn);
    CFE_TBL_TxnFinish(&Txn);
    CFE_EVS_SendEvent(CFE_TBL_TLM_REG_CMD_INF_EID, CFE_EVS_EventType_DEBUG, "Table Registry entry for '%s' will be telemetered", TableName);
    /* Increment Successful Command Counter */
    CmdProcRet = CFE_TBL_CmdProcRet_INC_CMD_CTR;
  } else {
    /* Table could not be found in Registry */
    CFE_EVS_SendEvent(CFE_TBL_NO_SUCH_TABLE_ERR_EID, CFE_EVS_EventType_ERROR, "Unable to locate '%s' in Table Registry", TableName);
  }
  return CFE_TBL_TranslateCmdProcRet(CmdProcRet);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_DeleteCDSCmd(CFE_TBL_DeleteCDSCmd_t *data)
{
  I32 CmdProcRet;
  CFE_TBL_DelCDSCmd_Payload_t *CmdPtr = &data->Payload;
  U8 TableName[CFE_TBL_MAX_FULL_NAME_LEN];
  CFE_TBL_CritRegRec_t *CritRegRecPtr;
  CFE_TBL_CritRegRec_t *LocalPtr;
  U32 i;
  U32 RegIndex;
  I32 Status;
  CmdProcRet = CFE_TBL_CmdProcRet_INC_ERR_CTR;
  /* Assume failure */
  /* Make sure all strings are null terminated before attempting to process them */
  CFE_SB_MessageStringGet(TableName, CmdPtr->TableName, NULL, CFE_TBL_MAX_FULL_NAME_LEN, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  // THE TABLE MUST BE **GONE** FROM THE REGISTRY BEFORE ITS CDS CAN BE DELETED, and NASA's
  // comment says why: a table still registered implies its owner is still running, and the CDS
  // is the only copy of a critical table's contents.
  /* Before doing anything, lets make sure the table is no longer in the registry */
  /* This would imply that the owning application has been terminated and that it */
  /* is safe to delete the associated critical table image in the CDS. */
  RegIndex = CFE_TBL_FindTableInRegistry(TableName);
  CritRegRecPtr = NULL;
  if (!CFE_TBL_REGID_IS_VALID(RegIndex)) {
    /* Find table in the Critical Table Registry */
    for (i = 0; i < CFE_PLATFORM_TBL_MAX_CRITICAL_TABLES; i++) {
      LocalPtr = &CFE_TBL_Global.CritReg[i];
      if (StrNCmp(LocalPtr->Name, TableName, CFE_TBL_MAX_FULL_NAME_LEN) == 0) {
        CritRegRecPtr = LocalPtr;
        break;
      }
    }
    if (CritRegRecPtr != NULL) {
      Status = CFE_ES_DeleteCDS(TableName, TRUE);
      if (Status == CFE_ES_CDS_WRONG_TYPE_ERR) {
        CFE_EVS_SendEvent(CFE_TBL_NOT_CRITICAL_TBL_ERR_EID, CFE_EVS_EventType_ERROR, "Table '%s' is in Critical Table Registry but CDS is not tagged as a table", TableName);
      } else if (Status == CFE_ES_CDS_OWNER_ACTIVE_ERR) {
        CFE_EVS_SendEvent(CFE_TBL_CDS_OWNER_ACTIVE_ERR_EID, CFE_EVS_EventType_ERROR, "CDS '%s' owning app is still active", TableName);
      } else if (Status == CFE_ES_ERR_NAME_NOT_FOUND) {
        CFE_EVS_SendEvent(CFE_TBL_CDS_NOT_FOUND_ERR_EID, CFE_EVS_EventType_ERROR, "Unable to locate '%s' in CDS Registry", TableName);
      } else if (Status != CFE_SUCCESS) {
        CFE_EVS_SendEvent(CFE_TBL_CDS_DELETE_ERR_EID, CFE_EVS_EventType_ERROR, "Error while deleting '%s' from CDS, See SysLog.(Err=0x%08X)", TableName, Status);
      } else {
        CFE_EVS_SendEvent(CFE_TBL_CDS_DELETED_INFO_EID, CFE_EVS_EventType_INFORMATION, "Successfully removed '%s' from CDS", TableName);
        /* Free the entry in the Critical Table Registry */
        CritRegRecPtr->CDSHandle = CFE_ES_CDS_BAD_HANDLE;
        /* Increment Successful Command Counter */
        CmdProcRet = CFE_TBL_CmdProcRet_INC_CMD_CTR;
      }
    } else {
      CFE_EVS_SendEvent(CFE_TBL_NOT_IN_CRIT_REG_ERR_EID, CFE_EVS_EventType_ERROR, "Table '%s' is not found in Critical Table Registry", TableName);
    }
  } else {
    /* Table was found in Registry */
    CFE_EVS_SendEvent(CFE_TBL_IN_REGISTRY_ERR_EID, CFE_EVS_EventType_ERROR, "'%s' found in Table Registry. CDS cannot be deleted until table is unregistered", TableName);
  }
  return CFE_TBL_TranslateCmdProcRet(CmdProcRet);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_AbortLoadCmd(CFE_TBL_AbortLoadCmd_t *data)
{
  I32 CmdProcRet;
  U32 RegIndex;
  CFE_TBL_AbortLoadCmd_Payload_t *CmdPtr = &data->Payload;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  U8 TableName[CFE_TBL_MAX_FULL_NAME_LEN];
  CFE_TBL_TableConfig_t *CfgPtr;
  CmdProcRet = CFE_TBL_CmdProcRet_INC_ERR_CTR;
  /* Assume failure */
  /* Make sure all strings are null terminated before attempting to process them */
  CFE_SB_MessageStringGet(TableName, CmdPtr->TableName, NULL, CFE_TBL_MAX_FULL_NAME_LEN, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  /* Before doing anything, lets make sure the table registry entry that is to be telemetered
   * exists */
  RegIndex = CFE_TBL_FindTableInRegistry(TableName);
  if (CFE_TBL_REGID_IS_VALID(RegIndex)) {
    /* Make a pointer to simplify code look and to remove redundant indexing into registry */
    RegRecPtr = CFE_TBL_LocateRegRecByID(RegIndex);
    // THE DUMP-ONLY EXCLUSION IS NOT DEFENSIVE, IT IS NECESSARY. NASA's comment: NextBufferId
    // holds the DUMP buffer's index while a dump-only table is being dumped, so without this
    // test "abort load" on a dump-only table would abort a DUMP.
    /* Check to make sure a load was in progress before trying to abort it */
    /* NOTE: NextBufferId contains index of buffer when dumping a dump-only table */
    /* so we must ensure the table is not a dump-only table, otherwise, we would be aborting a
     * dump */
    CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr);
    if (CFE_TBL_RegRecIsLoadInProgress(RegRecPtr) && !CfgPtr->DumpOnly) {
      CFE_TBL_AbortLoad(RegRecPtr);
      /* Increment Successful Command Counter */
      CmdProcRet = CFE_TBL_CmdProcRet_INC_CMD_CTR;
    } else {
      CFE_EVS_SendEvent(CFE_TBL_LOAD_ABORT_ERR_EID, CFE_EVS_EventType_ERROR, "Cannot abort load of '%s'. No load started.", TableName);
    }
  } else {
    /* Table could not be found in Registry */
    CFE_EVS_SendEvent(CFE_TBL_NO_SUCH_TABLE_ERR_EID, CFE_EVS_EventType_ERROR, "Unable to locate '%s' in Table Registry", TableName);
  }
  return CFE_TBL_TranslateCmdProcRet(CmdProcRet);
}
#endif
