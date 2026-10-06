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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_dump.c -- A DUMP IS THREE PHASES
// SEPARATED IN TIME, and that is the only thing worth understanding about this file.
//
//   1. ALLOCATE   CFE_TBL_AllocateDumpCtrlBlock picks a dump control block and records WHICH
//                 buffer is to be dumped. Nothing is copied.
//   2. SNAPSHOT   CFE_TBL_ExecuteDumpSnapshot copies the chosen buffer into a shared load
//                 buffer and stamps it with the time. Still nothing is written to a file.
//   3. WRITE      CFE_TBL_TableDumpExecuteBackground, called from the background task, writes
//                 the snapshot to disk and frees both buffers.
//
// WHY THE SPLIT EXISTS: a dump must not block the caller on file I/O, and for a DUMP-ONLY
// table the snapshot must happen when the OWNER says so, not when the command arrives. So
// CFE_TBL_PrepareDumpSnapshotBuffer branches on exactly that -- a dump-only table gets
// State = CFE_TBL_DUMP_PENDING and the registry record remembers the block, while a normal
// table has its snapshot taken immediately. Either way phase 3 is deferred.
//
// AND THE FILE EXISTENCE CHECK IS ONLY FOR THE EVENT ID. CFE_TBL_WriteSnapshotToFile opens the
// dump file read-only first, purely to decide between OVERWRITE_DUMP_INF and WRITE_DUMP_INF.
// NASA's own comment says so. It is not a safety check and nothing branches on it.
#ifndef CFE_TBL_DUMP_HC
#define CFE_TBL_DUMP_HC
// cfe_tbl_eventids.h -- the eleven this file raises
#ifndef CFE_TBL_OVERWRITE_DUMP_INF_EID
#define CFE_TBL_OVERWRITE_DUMP_INF_EID 13
#endif
#ifndef CFE_TBL_WRITE_DUMP_INF_EID
#define CFE_TBL_WRITE_DUMP_INF_EID 14
#endif
#ifndef CFE_TBL_NO_WORK_BUFFERS_ERR_EID
#define CFE_TBL_NO_WORK_BUFFERS_ERR_EID 60
#endif
#ifndef CFE_TBL_CREATING_DUMP_FILE_ERR_EID
#define CFE_TBL_CREATING_DUMP_FILE_ERR_EID 62
#endif
#ifndef CFE_TBL_WRITE_CFE_HDR_ERR_EID
#define CFE_TBL_WRITE_CFE_HDR_ERR_EID 63
#endif
#ifndef CFE_TBL_WRITE_TBL_IMG_ERR_EID
#define CFE_TBL_WRITE_TBL_IMG_ERR_EID 65
#endif
#ifndef CFE_TBL_TOO_MANY_DUMPS_ERR_EID
#define CFE_TBL_TOO_MANY_DUMPS_ERR_EID 76
#endif
#ifndef CFE_TBL_DUMP_PENDING_ERR_EID
#define CFE_TBL_DUMP_PENDING_ERR_EID 77
#endif
#ifndef CFE_TBL_DUMP_ENCODE_FAIL_EID
#define CFE_TBL_DUMP_ENCODE_FAIL_EID 105
#endif
#ifndef CFE_TBL_BAD_ARGUMENT
#define CFE_TBL_BAD_ARGUMENT 0xCC00002D(I32)
#endif
// cfe_tbl_extern_typedefs.h: the two headers a table file always carries together. NASA's own
// comment -- "This struct just combines the two and makes for an easier item to pass around,
// simplifying APIs".
class CFE_TBL_CombinedFileHdr_t
{
  CFE_FS_Header_t Std;
  CFE_TBL_File_Hdr_t Tbl;
};
// cfe_tbl_dump.c's own file-local context type: what the event helper needs that the
// transaction does not carry.
class CFE_TBL_DumpContext_t
{
  U8 *FileName;
  U8 *RequestedTableName;
};
// THE LOCAL ANONYMOUS UNION OF CFE_TBL_WriteHeaders, named because HolyC has no anonymous one.
// NASA's reason for it is in the comment at the assignment: "This is needed because the FS API
// call (possibly) modifies the buffer during write" -- so the caller's header is copied into a
// scratch big enough for either header before being handed to CFE_FS_WriteHeader.
union CFE_TBL_DumpHdrBuffer_t
{
  CFE_FS_Header_t Std;
  CFE_TBL_File_Hdr_t Tbl;
};
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_WriteHeaders(CFE_TBL_TxnState_t *Txn, U32 FileDescriptor, CFE_TBL_CombinedFileHdr_t *FileHeader)
{
  I32 Status;
  CFE_TBL_DumpHdrBuffer_t Buffer;
  /* Initialize the standard cFE File Header for the Dump File */
  /* This is needed because the FS API call (possibly) modifies the buffer during write */
  // `Buffer.Std = FileHeader->Std` is a CLASS ASSIGNMENT BY VALUE, which this port writes as an
  // explicit copy -- the same convention cfe_tbl_passthru_codec.HC uses, and the one
  // tools/cfs/check_struct_copy.py enforces.
  MemCpy(&Buffer.Std, &FileHeader->Std, sizeof(CFE_FS_Header_t));
  /* Output the Standard cFE File Header to the Dump File */
  Status = CFE_FS_WriteHeader(FileDescriptor, &Buffer.Std);
  if (Status != sizeof(CFE_FS_Header_t)) {
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_WRITE_CFE_HDR_ERR_EID, Status, sizeof(CFE_FS_Header_t));
    Status = CFE_TBL_ERR_ACCESS;
  } else {
    Status = CFE_TBL_EncodeHeadersToFile(Txn, FileDescriptor, &FileHeader->Tbl);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnOpenTableDumpFile(CFE_TBL_TxnState_t *Txn, U8 *Filename, U32 *FileDescOut, CFE_TBL_CombinedFileHdr_t *FileHeader)
{
  I32 ReturnCode;
  I32 OsStatus;
  U32 FileDescriptor = OS_OBJECT_ID_UNDEFINED;
  /* Create a new dump file, overwriting anything that may have existed previously */
  OsStatus = OS_OpenCreate(&FileDescriptor, Filename, OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE, OS_WRITE_ONLY);
  if (OsStatus != OS_SUCCESS) {
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_CREATING_DUMP_FILE_ERR_EID, OsStatus, 0);
    ReturnCode = CFE_TBL_ERR_ACCESS;
    FileDescriptor = OS_OBJECT_ID_UNDEFINED;
  } else {
    ReturnCode = CFE_TBL_WriteHeaders(Txn, FileDescriptor, FileHeader);
    if (ReturnCode != CFE_SUCCESS) {
      OS_close(FileDescriptor);
      FileDescriptor = OS_OBJECT_ID_UNDEFINED;
    }
  }
  *FileDescOut = FileDescriptor;
  return ReturnCode;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_WriteSnapshotToFile(CFE_TBL_DumpControl_t *DumpCtlPtr)
{
  I32 Status;
  I32 OsStatus;
  Bool FileExistedPrev;
  CFE_TBL_CombinedFileHdr_t FileHeader;
  U32 FileDescriptor = OS_OBJECT_ID_UNDEFINED;
  U8 *DumpFilename;
  U8 *DumpDataAddr;
  I64 DumpDataSize;
  CFE_TBL_TxnState_t Txn;
  CFE_TBL_TxnInit(&Txn, FALSE);
  DumpFilename = DumpCtlPtr->DumpBufferPtr->DataSource;
  DumpDataAddr = CFE_TBL_LoadBuffGetReadPointer(DumpCtlPtr->DumpBufferPtr);
  DumpDataSize = CFE_TBL_LoadBuffGetContentSize(DumpCtlPtr->DumpBufferPtr);
  // THE memset IS sizeof(CFE_TBL_File_Hdr_t), NOT sizeof(FileHeader), AND THAT IS NASA'S CODE.
  // The combined header is Std followed by Tbl, so clearing File_Hdr_t bytes from the front
  // clears part of Std and NONE of Tbl. It is harmless only because CFE_FS_InitHeader
  // immediately overwrites all of Std and the two Tbl fields that matter are assigned below --
  // NumBytes and TableName. Reserved and Offset are left as whatever was on the stack. Kept
  // verbatim because this is a 1:1 translation; flagged because it reads like a bug.
  /* Clear Header of any garbage before copying content */
  MemSet(&FileHeader, 0, sizeof(CFE_TBL_File_Hdr_t));
  /* Initialize the standard cFE File Header for the Dump File */
  CFE_FS_InitHeader(&FileHeader.Std, "Table Dump Image", CFE_FS_SubType_TBL_IMG);
  FileHeader.Std.TimeSeconds = DumpCtlPtr->DumpBufferPtr->FileTime.Seconds;
  FileHeader.Std.TimeSubSeconds = DumpCtlPtr->DumpBufferPtr->FileTime.Subseconds;
  /* Initialize the Table Image Header for the Dump File */
  StrNCpy(FileHeader.Tbl.TableName, DumpCtlPtr->TableName, CFE_MISSION_TBL_MAX_FULL_NAME_LEN - 1);
  FileHeader.Tbl.NumBytes = DumpDataSize;
  /* Check to see if the dump file already exists */
  /* NOTE: this is only relevant for sending a success event later, it changes the EID */
  OsStatus = OS_OpenCreate(&FileDescriptor, DumpFilename, OS_FILE_FLAG_NONE, OS_READ_ONLY);
  if (OsStatus == OS_SUCCESS) {
    FileExistedPrev = TRUE;
    OS_close(FileDescriptor);
  } else {
    FileExistedPrev = FALSE;
  }
  /* Create a new dump file, overwriting anything that may have existed previously */
  Status = CFE_TBL_TxnOpenTableDumpFile(&Txn, DumpFilename, &FileDescriptor, &FileHeader);
  if (Status == CFE_SUCCESS) {
    /* Output the requested data to the dump file */
    /* Output the active table image data to the dump file */
    OsStatus = OS_write(FileDescriptor, DumpDataAddr, DumpDataSize);
    if (OsStatus != DumpDataSize) {
      CFE_TBL_TxnAddEvent(&Txn, CFE_TBL_WRITE_TBL_IMG_ERR_EID, OsStatus, 0);
      Status = CFE_TBL_ERR_ACCESS;
    }
    /* We are done outputting data to the dump file.  Close it. */
    OS_close(FileDescriptor);
  }
  /* If everything went well, report happiness and update global TLM data */
  if (Status == CFE_SUCCESS) {
    /* The whole check of file existence is to give a different EID for overwrite vs first
     * write */
    if (FileExistedPrev)
      CFE_TBL_TxnAddEvent(&Txn, CFE_TBL_OVERWRITE_DUMP_INF_EID, 0, 0);
    else
      CFE_TBL_TxnAddEvent(&Txn, CFE_TBL_WRITE_DUMP_INF_EID, 0, 0);
    /* Save file information statistics for housekeeping telemetry */
    // sizeof(...LastFileDumped) is CFE_MISSION_MAX_PATH_LEN, which is NOT the same constant as
    // OS_MAX_PATH_LEN -- the first draft used the latter. And the -1 is NASA's: SourceMaxSize is
    // a size_t, so -1 is SIZE_MAX, i.e. "copy to the NUL". See the note at
    // CFE_SB_MessageStringSet, whose two sizes had to become U64 for that to work.
    CFE_SB_MessageStringSet(CFE_TBL_Global.HkPacket.Payload.LastFileDumped, DumpFilename, CFE_MISSION_MAX_PATH_LEN, -1);
  }
  CFE_TBL_SendTableDumpEvents(&Txn, DumpFilename, DumpCtlPtr->TableName);
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ExecuteDumpSnapshot(CFE_TBL_DumpControl_t *DumpCtrlPtr)
{
  I32 Status;
  CFE_TBL_TxnState_t Txn;
  CFE_TBL_LoadBuff_t *SourceBufPtr;
  CFE_TBL_TxnInit(&Txn, FALSE);
  SourceBufPtr = CFE_TBL_LocateLoadBufferByID(DumpCtrlPtr->SourceBuffId);
  if (CFE_TBL_LoadBuffIsMatch(SourceBufPtr, DumpCtrlPtr->SourceBuffId)) {
    Txn.RegRecPtr = CFE_TBL_LoadBuffGetRegRecFromId(DumpCtrlPtr->SourceBuffId);
    Txn.RegId = CFE_TBL_RegRecGetID(Txn.RegRecPtr);
    /* Copy the contents of the active buffer to the assigned dump buffer */
    /* NOTE: In a "passthru" implementation, it is not possible for the encoding to fail,
     * this always succeeds.  In an implementation where it does do an encode, then it
     * is not the type of failure where trying again later might improve the result.
     * We need to just accept the error and move on to eventually free the dump ctrl buffer. */
    DumpCtrlPtr->EncodeStatus = CFE_TBL_EncodeOutputData(&Txn, SourceBufPtr, DumpCtrlPtr->DumpBufferPtr);
    /* Save the current time so that the header in the dump file can have the correct time */
    DumpCtrlPtr->DumpBufferPtr->FileTime = CFE_TIME_GetTime;
    /* Notify the Table Services Application that the dump buffer is ready to be written to a
     * file */
    DumpCtrlPtr->State = CFE_TBL_DUMP_PERFORMED;
    DumpCtrlPtr->SourceBuffId = CFE_TBL_LOADBUFFID_UNDEFINED;
    Status = CFE_SUCCESS;
  } else {
    Status = CFE_TBL_ERR_INVALID_HANDLE;
  }
  CFE_TBL_TxnFinish(&Txn);
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_PrepareDumpSnapshotBuffer(CFE_TBL_TxnState_t *Txn, U32 DumpCtrlId, U8 *DumpFilename)
{
  I32 Status;
  CFE_TBL_LoadBuff_t *WorkingBufferPtr;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_DumpControl_t *DumpCtrlPtr;
  CFE_TBL_TableConfig_t *CfgPtr;
  /* Allocate a shared memory buffer for storing the data to be dumped */
  /* Note this uses a different lock than the registry lock */
  WorkingBufferPtr = CFE_TBL_AcquireGlobalLoadBuff(CFE_TBL_TxnRegId(Txn));
  if (WorkingBufferPtr == NULL) {
    Status = CFE_TBL_ERR_NO_BUFFER_AVAIL;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_NO_WORK_BUFFERS_ERR_EID, Status, 0);
  } else {
    // NASA PASSES THE FULL SIZE HERE, NOT SIZE-1, so a path exactly OS_MAX_PATH_LEN long is
    // copied unterminated -- strncpy's documented sharp edge, and the reason CfsStr.HC's
    // StrNCpy reproduces it rather than being "fixed".
    StrNCpy(WorkingBufferPtr->DataSource, DumpFilename, OS_MAX_PATH_LEN);
    /* Now associate it with the Dump Control block */
    RegRecPtr = CFE_TBL_TxnRegRec(Txn);
    DumpCtrlPtr = CFE_TBL_LocateDumpCtrlByID(DumpCtrlId);
    if (!CFE_TBL_DumpCtrlBlockIsMatch(DumpCtrlPtr, DumpCtrlId)) {
      /* This is unexpected, it appears the dump was aborted in the meantime */
      Status = CFE_TBL_ERR_INVALID_HANDLE;
    } else {
      DumpCtrlPtr->DumpBufferPtr = WorkingBufferPtr;
      // HOISTED, limit 17: `CFE_TBL_RegRecGetConfig(RegRecPtr)->DumpOnly` resolves the arrow
      // against the FIRST ARGUMENT's class and the compiler refuses.
      CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr);
      if (CfgPtr->DumpOnly) {
        /* Dump Only tables need to synchronize their dumps with the owner's execution */
        DumpCtrlPtr->State = CFE_TBL_DUMP_PENDING;
        RegRecPtr->DumpControlId = CFE_TBL_DumpCtrlBlockGetId(DumpCtrlPtr);
        /* Consider the command completed successfully */
        Status = CFE_SUCCESS;
      } else {
        /* Do the dump right now (note this is only the memcpy, write to file still deferred) */
        Status = CFE_TBL_ExecuteDumpSnapshot(DumpCtrlPtr);
      }
      /* If application requested notification by message, then do so */
      CFE_TBL_SendNotificationMsg(RegRecPtr);
    }
    /* If leaving here unsuccessfully, then release the buffer that was obtained */
    if (Status != CFE_SUCCESS)
      CFE_TBL_LoadBuffSetFree(WorkingBufferPtr);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_AllocateDumpCtrlBlock(CFE_TBL_TxnState_t *Txn, U32 *DumpCtrlIdOut, U16 BufferSelect)
{
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *SelectedBufferPtr;
  U32 PendingDumpId;
  I32 Status;
  CFE_TBL_DumpControl_t *DumpCtrlPtr;
  DumpCtrlPtr = NULL;
  SelectedBufferPtr = NULL;
  /* Obtain a pointer to registry information about specified table */
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  if (RegRecPtr == NULL) {
    Status = CFE_TBL_ERR_INVALID_HANDLE;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_NO_SUCH_TABLE_ERR_EID, Status, 0);
  } else if (CFE_TBL_DUMPCTRLID_IS_VALID(RegRecPtr->DumpControlId)) {
    /* A dump is already in progress */
    Status = CFE_TBL_INFO_DUMP_PENDING;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_DUMP_PENDING_ERR_EID, Status, 0);
  } else {
    /* Determine what data is to be dumped */
    SelectedBufferPtr = CFE_TBL_GetSelectedBuffer(RegRecPtr, BufferSelect);
    if (SelectedBufferPtr == NULL) {
      /* Use deferred event reporting while registry is locked */
      Status = CFE_TBL_BAD_ARGUMENT;
      CFE_TBL_TxnAddEvent(Txn, CFE_TBL_ILLEGAL_BUFF_PARAM_ERR_EID, Status, BufferSelect);
    }
  }
  // NOTE WHAT HAPPENS TO `Status` IF THE BUFFER IS GOOD: it is NOT set in the else-branch
  // above, and the block below assigns it. So every path that reaches the second `if` with a
  // non-NULL buffer overwrites Status, and every path that does not has already set it. That is
  // why this reads as two statements rather than one if/else chain.
  /* If there is a valid source buffer to dump, find a dump ctrl block to track progress */
  if (SelectedBufferPtr != NULL) {
    /* Find a free Dump Control Block */
    PendingDumpId = CFE_TBL_GetNextDumpCtrlBlock();
    DumpCtrlPtr = CFE_TBL_LocateDumpCtrlByID(PendingDumpId);
    if (DumpCtrlPtr == NULL) {
      Status = CFE_TBL_ERR_NO_BUFFER_AVAIL;
      CFE_TBL_TxnAddEvent(Txn, CFE_TBL_TOO_MANY_DUMPS_ERR_EID, Status, 0);
    } else {
      /* Reserve the block */
      MemSet(DumpCtrlPtr, 0, sizeof(CFE_TBL_DumpControl_t));
      /* Capture important context info to the dump control block */
      DumpCtrlPtr->SourceBuffId = CFE_TBL_LoadBufferGetID(SelectedBufferPtr);
      CFE_SB_MessageStringSet(DumpCtrlPtr->TableName, CFE_TBL_RegRecGetName(RegRecPtr), CFE_TBL_MAX_FULL_NAME_LEN, CFE_TBL_MAX_FULL_NAME_LEN);
      CFE_TBL_DumpCtrlBlockSetUsed(DumpCtrlPtr, PendingDumpId);
      CFE_TBL_Global.LastDumpCtrlBlockId = PendingDumpId;
      Status = CFE_SUCCESS;
    }
  }
  if (DumpCtrlPtr != NULL)
    *DumpCtrlIdOut = CFE_TBL_DumpCtrlBlockGetId(DumpCtrlPtr);
  else
    *DumpCtrlIdOut = CFE_TBL_DUMPCTRLID_UNDEFINED;
  return Status;
}
/*----------------------------------------------------------------
 *
 * Local helper function for sending events
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_SendDumpEventHelper(CFE_TBL_TxnEvent_t *Event, CFE_TBL_TxnEventContext_t *Ctxt)
{
  CFE_TBL_DumpContext_t *DumpCtxt;
  U16 EventType;
  U8 EventString[CFE_MISSION_EVS_MAX_MESSAGE_LENGTH];
  U8 CallerString[CFE_MISSION_MAX_API_LEN + 8];
  DumpCtxt = Ctxt->OperationDataPtr;
  /* The majority of the events are errors, but this can be reset later to demote to info/debug
   */
  EventType = CFE_EVS_EventType_ERROR;
  EventString[0] = 0;
  switch (Event->EventId) {
    case CFE_TBL_NO_WORK_BUFFERS_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "No working buffers available");
    break;
    case CFE_TBL_TOO_MANY_DUMPS_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Too many table dumps have been requested");
    break;
    case CFE_TBL_ILLEGAL_BUFF_PARAM_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Cmd had illegal buffer parameter (0x%08X)", Event->EventData2);
    break;
    case CFE_TBL_DUMP_PENDING_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "A dump is already pending");
    break;
    case CFE_TBL_WRITE_CFE_HDR_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Error writing cFE File Header, Status=0x%08X", Event->EventData1);
    break;
    case CFE_TBL_WRITE_TBL_HDR_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Error writing cFE TBL Header, Status=%d", Event->EventData1);
    break;
    case CFE_TBL_CREATING_DUMP_FILE_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Error creating dump file, Status=%d", Event->EventData1);
    break;
    case CFE_TBL_WRITE_TBL_IMG_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Error writing Tbl image, Status=%d", Event->EventData1);
    break;
    case CFE_TBL_OVERWRITE_DUMP_INF_EID :
    EventType = CFE_EVS_EventType_INFORMATION;
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Successfully overwrote table dump");
    break;
    case CFE_TBL_WRITE_DUMP_INF_EID :
    EventType = CFE_EVS_EventType_INFORMATION;
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Successfully dumped table");
    break;
  }
  // AN UNRECOGNISED EVENT ID IS DECLINED, NOT REPORTED. The empty string is the signal, and
  // returning false is how CFE_TBL_SendTransactionEvents learns this helper does not own the
  // event -- the mechanism that lets each operation register its own helper.
  if (EventString[0] == 0)
    return FALSE;
  if (Ctxt->CallerName[0] == 0) {
    /* Empty name indicates it was initiated via ground command */
    StrPrintN(CallerString, CFE_MISSION_MAX_API_LEN + 8, "command");
  } else {
    /* non-Empty name means it was initiated by another app via API */
    StrPrintN(CallerString, CFE_MISSION_MAX_API_LEN + 8, "app=%s", Ctxt->CallerName);
  }
  /* Finally send the actual event by appending all the info we have */
  CFE_EVS_SendEventWithAppID(Event->EventId, EventType, CFE_TBL_Global.TableTaskAppId, "%s by %s,table=%s,file=%s:%s", Ctxt->Operation, CallerString, DumpCtxt->RequestedTableName, DumpCtxt->FileName, EventString);
  return TRUE;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_SendTableDumpEvents(CFE_TBL_TxnState_t *Txn, U8 *FileName, U8 *RequestedTableName)
{
  CFE_TBL_DumpContext_t Ctxt;
  MemSet(&Ctxt, 0, sizeof(CFE_TBL_DumpContext_t));
  if (FileName != NULL) {
    Ctxt.FileName = FileName;
  } else {
    /* do not leave it null/blank */
    Ctxt.FileName = "[none]";
  }
  if (RequestedTableName != NULL) {
    Ctxt.RequestedTableName = RequestedTableName;
  } else {
    /* do not leave it null/blank */
    Ctxt.RequestedTableName = "[unknown]";
  }
  CFE_TBL_SendTransactionEvents(Txn, "Dump", &CFE_TBL_SendDumpEventHelper, &Ctxt);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_TableDumpExecuteBackground()
{
  U32 i;
  CFE_TBL_DumpControl_t *DumpCtrlPtr;
  /* Check to see if there are any dump-only table dumps pending */
  for (i = 0; i < CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS; i++) {
    DumpCtrlPtr = &CFE_TBL_Global.DumpControlBlocks[i];
    if (CFE_TBL_DumpCtrlBlockIsUsed(DumpCtrlPtr) && DumpCtrlPtr->State == CFE_TBL_DUMP_PERFORMED) {
      /* only write the file if the snapshot was successful */
      if (DumpCtrlPtr->EncodeStatus == CFE_SUCCESS) {
        CFE_TBL_WriteSnapshotToFile(DumpCtrlPtr);
      } else {
        CFE_EVS_SendEvent(CFE_TBL_DUMP_ENCODE_FAIL_EID, CFE_EVS_EventType_ERROR, "Table Dump encoding failed, status=%d", DumpCtrlPtr->EncodeStatus);
      }
      /* Free the shared working buffer */
      CFE_TBL_LoadBuffSetFree(DumpCtrlPtr->DumpBufferPtr);
      /* Free the Dump Control Block for later use */
      CFE_TBL_DumpCtrlBlockSetFree(DumpCtrlPtr);
    }
  }
}
#endif
