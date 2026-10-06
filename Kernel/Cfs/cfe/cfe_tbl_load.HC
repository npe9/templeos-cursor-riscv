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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_load.c -- SIXTEEN FUNCTIONS, AND A
// LOAD IS THE MOST GUARDED OPERATION IN TABLE SERVICES. Nothing else in cFS checks this many
// things before touching memory.
//
// THE FILE PATH, IN ORDER, AND EVERY STEP CAN REFUSE:
//
//   open           long name? inaccessible?
//   std header     short read? wrong content id? wrong subtype? wrong spacecraft? wrong CPU?
//   tbl header     decoded by the codec
//   loadable?      right table name? zero length? partial load on a never-loaded table?
//   content        does it fit the buffer? short read? EXTRA data past what the header claims?
//   metadata       file time, CRC, IsValid seeded from whether a validation func exists
//
// THE EXTRA-BYTE READ IS THE ONE WORTH POINTING AT. After reading exactly NumBytes, the code
// tries to read ONE MORE byte; if that succeeds the file has more data than its header claims
// and the load is refused. A length check alone would have accepted it.
//
// TWO EVENT HELPERS, AND THE SECOND FALLS THROUGH TO THE FIRST. CFE_TBL_SendLoadFileEventHelper
// handles the events that need the FILE HEADER in their text; anything it does not recognise it
// hands to CFE_TBL_SendLoadBasicEventHelper rather than declining. So a file load can raise a
// basic event, but a non-file load can never raise a file one -- the asymmetry is the design.
//
// AND TWO EVENT IDS FOR ONE FAILURE, which NASA flags itself: a validation function returning a
// POSITIVE value raises CFE_TBL_LOAD_VAL_ERR_EID and a NEGATIVE one raises
// CFE_TBL_VALIDATION_ERR_EID. Their comment says "It is not entirely clear why there are two
// different EIDs here ... This is historical behavior and it has been preserved." So is this.
#ifndef CFE_TBL_LOAD_HC
#define CFE_TBL_LOAD_HC
// cfe_tbl_eventids.h -- the twenty this file raises
#ifndef CFE_TBL_FILE_LOADED_INF_EID
#define CFE_TBL_FILE_LOADED_INF_EID 12
#endif
#ifndef CFE_TBL_LOAD_ABORT_INF_EID
#define CFE_TBL_LOAD_ABORT_INF_EID 21
#endif
#ifndef CFE_TBL_LOAD_SUCCESS_INF_EID
#define CFE_TBL_LOAD_SUCCESS_INF_EID 35
#endif
#ifndef CFE_TBL_FILE_ACCESS_ERR_EID
#define CFE_TBL_FILE_ACCESS_ERR_EID 53
#endif
#ifndef CFE_TBL_FILE_STD_HDR_ERR_EID
#define CFE_TBL_FILE_STD_HDR_ERR_EID 54
#endif
#ifndef CFE_TBL_FILE_TYPE_ERR_EID
#define CFE_TBL_FILE_TYPE_ERR_EID 58
#endif
#ifndef CFE_TBL_FILE_SUBTYPE_ERR_EID
#define CFE_TBL_FILE_SUBTYPE_ERR_EID 59
#endif
#ifndef CFE_TBL_FILE_INCOMPLETE_ERR_EID
#define CFE_TBL_FILE_INCOMPLETE_ERR_EID 71
#endif
#ifndef CFE_TBL_ZERO_LENGTH_LOAD_ERR_EID
#define CFE_TBL_ZERO_LENGTH_LOAD_ERR_EID 73
#endif
#ifndef CFE_TBL_PARTIAL_LOAD_ERR_EID
#define CFE_TBL_PARTIAL_LOAD_ERR_EID 74
#endif
#ifndef CFE_TBL_FILE_TOO_BIG_ERR_EID
#define CFE_TBL_FILE_TOO_BIG_ERR_EID 75
#endif
#ifndef CFE_TBL_LOADING_A_DUMP_ONLY_ERR_EID
#define CFE_TBL_LOADING_A_DUMP_ONLY_ERR_EID 79
#endif
#ifndef CFE_TBL_LOAD_VAL_ERR_EID
#define CFE_TBL_LOAD_VAL_ERR_EID 93
#endif
#ifndef CFE_TBL_LOAD_TYPE_ERR_EID
#define CFE_TBL_LOAD_TYPE_ERR_EID 94
#endif
#ifndef CFE_TBL_UPDATE_ERR_EID
#define CFE_TBL_UPDATE_ERR_EID 95
#endif
#ifndef CFE_TBL_VALIDATION_ERR_EID
#define CFE_TBL_VALIDATION_ERR_EID 96
#endif
#ifndef CFE_TBL_SPACECRAFT_ID_ERR_EID
#define CFE_TBL_SPACECRAFT_ID_ERR_EID 97
#endif
#ifndef CFE_TBL_PROCESSOR_ID_ERR_EID
#define CFE_TBL_PROCESSOR_ID_ERR_EID 98
#endif
#ifndef CFE_TBL_LOAD_IN_PROGRESS_ERR_EID
#define CFE_TBL_LOAD_IN_PROGRESS_ERR_EID 100
#endif
#ifndef CFE_TBL_LOAD_FILENAME_LONG_ERR_EID
#define CFE_TBL_LOAD_FILENAME_LONG_ERR_EID 101
#endif
#ifndef CFE_TBL_LOAD_TBLNAME_MISMATCH_ERR_EID
#define CFE_TBL_LOAD_TBLNAME_MISMATCH_ERR_EID 102
#endif
// osapi-error.h -- the one OSAL error this file distinguishes from the rest. Defined here and
// not taken from Kernel/Cfs/osal/osapi_errors.HC because the cFS driver does not include the
// OSAL tree; cfe_sb_api.HC does the same for OS_ERR_NAME_TAKEN. check_constants.py compares the
// value against NASA's either way.
#ifndef OS_FS_ERR_PATH_TOO_LONG
#define OS_FS_ERR_PATH_TOO_LONG -103
#endif
// cfe_tbl_api_typedefs.h / cfe_error.h -- the statuses
#ifndef CFE_TBL_ERR_DUMP_ONLY
#define CFE_TBL_ERR_DUMP_ONLY 0xCC000010(I32)
#endif
#ifndef CFE_TBL_ERR_ILLEGAL_SRC_TYPE
#define CFE_TBL_ERR_ILLEGAL_SRC_TYPE 0xCC000011(I32)
#endif
#ifndef CFE_TBL_ERR_LOAD_IN_PROGRESS
#define CFE_TBL_ERR_LOAD_IN_PROGRESS 0xCC000012(I32)
#endif
#ifndef CFE_TBL_ERR_BAD_CONTENT_ID
#define CFE_TBL_ERR_BAD_CONTENT_ID 0xCC000016(I32)
#endif
#ifndef CFE_TBL_ERR_BAD_SUBTYPE_ID
#define CFE_TBL_ERR_BAD_SUBTYPE_ID 0xCC00001B(I32)
#endif
#ifndef CFE_TBL_ERR_NO_STD_HEADER
#define CFE_TBL_ERR_NO_STD_HEADER 0xCC00001D(I32)
#endif
#ifndef CFE_TBL_ERR_FILENAME_TOO_LONG
#define CFE_TBL_ERR_FILENAME_TOO_LONG 0xCC00001F(I32)
#endif
#ifndef CFE_TBL_ERR_FILE_FOR_WRONG_TABLE
#define CFE_TBL_ERR_FILE_FOR_WRONG_TABLE 0xCC000020(I32)
#endif
#ifndef CFE_TBL_ERR_LOAD_INCOMPLETE
#define CFE_TBL_ERR_LOAD_INCOMPLETE 0xCC000021(I32)
#endif
#ifndef CFE_TBL_ERR_PARTIAL_LOAD
#define CFE_TBL_ERR_PARTIAL_LOAD 0xCC000023(I32)
#endif
#ifndef CFE_TBL_ERR_BAD_SPACECRAFT_ID
#define CFE_TBL_ERR_BAD_SPACECRAFT_ID 0xCC000028(I32)
#endif
#ifndef CFE_TBL_ERR_BAD_PROCESSOR_ID
#define CFE_TBL_ERR_BAD_PROCESSOR_ID 0xCC000029(I32)
#endif
#ifndef CFE_STATUS_VALIDATION_FAILURE
#define CFE_STATUS_VALIDATION_FAILURE 0xC8000007(I32)
#endif
// cfe_tbl_api_typedefs.h: CFE_TBL_SrcEnum_t. FILE is 0 so a zeroed request means "from a file",
// which is why CFE_TBL_ValidateLoadRequest has to test for BOTH legal values rather than just
// rejecting a known-bad one.
#ifndef CFE_TBL_SRC_FILE
#define CFE_TBL_SRC_FILE    0
#endif
#ifndef CFE_TBL_SRC_ADDRESS
#define CFE_TBL_SRC_ADDRESS 1
#endif
// cfe_tbl_load.c's own file-local context type: what the file-event helper needs that the
// transaction does not carry.
class CFE_TBL_LoadFileContext_t
{
  U8 *LoadFilename;
  CFE_TBL_CombinedFileHdr_t *FileHdr;
};
Bool CFE_TBL_SendLoadBasicEventHelper(CFE_TBL_TxnEvent_t *Event, CFE_TBL_TxnEventContext_t *Ctxt);
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnOpenTableLoadFile(CFE_TBL_TxnState_t *Txn, U8 *Filename, U32 *FileDescOut, CFE_TBL_CombinedFileHdr_t *TblFileHeader)
{
  I32 Status;
  I32 OsStatus;
  U32 FileDescriptor;
  FileDescriptor = OS_OBJECT_ID_UNDEFINED;
  /* Try to open the specified table file */
  OsStatus = OS_OpenCreate(&FileDescriptor, Filename, OS_FILE_FLAG_NONE, OS_READ_ONLY);
  if (OsStatus == OS_FS_ERR_PATH_TOO_LONG) {
    /* Traditionally there was a dedicated EID for long file names, keeping it */
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_LOAD_FILENAME_LONG_ERR_EID, OsStatus, 0);
    Status = CFE_TBL_ERR_FILENAME_TOO_LONG;
  } else if (OsStatus != OS_SUCCESS) {
    /* Catch any other OSAL error, probably related to file existence or access */
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_FILE_ACCESS_ERR_EID, OsStatus, 0);
    Status = CFE_TBL_ERR_ACCESS;
  } else {
    /* CFE_TBL_ReadHeaders() - if successful, it leaves the file desc positioned at the table
     * data */
    Status = CFE_TBL_ReadHeaders(Txn, FileDescriptor, TblFileHeader);
    /* If unsuccessful, then close the file descriptor */
    if (Status != CFE_SUCCESS) {
      OS_close(FileDescriptor);
      FileDescriptor = OS_OBJECT_ID_UNDEFINED;
    }
  }
  /* Always export the file descriptor.  It will be undefined on failure,
   * or a valid file descriptor on success, positioned at the file data */
  *FileDescOut = FileDescriptor;
  return Status;
}
/*----------------------------------------------------------------
 *
 * Internal helper function
 * Checks a user-supplied ID against the configured acceptable list
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_ValidateTableHeaderId(U32 ConfigId, U32 RefId)
{
  CFE_Config_ArrayValue AcceptList;
  U32 *ListPtr;
  U32 Idx;
  // AN EMPTY LIST ACCEPTS EVERYTHING, which is the whole point of the final expression: the
  // spacecraft-id and processor-id checks are OPTIONAL and a mission that configures no list
  // gets no check. Note the loop variable is read AFTER the loop -- `Idx < NumElements` is true
  // only if the `break` fired.
  //
  // CFE_Config_GetArrayValue RETURNS A STRUCT BY VALUE in the C and HolyC has no struct-return
  // ABI, so the translation takes a destination pointer. Recorded deviation; see
  // cfe_config.HC and docs/HOLYC_STRUCT_LIMITS.md.
  CFE_Config_GetArrayValue(ConfigId, &AcceptList);
  /* Verify ID contained in table file header [optional] */
  ListPtr = AcceptList.ElementPtr;
  for (Idx = 0; Idx < AcceptList.NumElements; ++Idx) {
    if (RefId == *ListPtr)
      break;
    ++ListPtr;
  }
  return AcceptList.NumElements == 0 || Idx < AcceptList.NumElements;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ReadHeaders(CFE_TBL_TxnState_t *Txn, U32 FileDescriptor, CFE_TBL_CombinedFileHdr_t *FileHeader)
{
  I32 Status;
  /* Once the file is open, read the headers to determine the target Table */
  Status = CFE_FS_ReadHeader(&FileHeader->Std, FileDescriptor);
  /* Verify successful read of standard cFE File Header */
  if (Status != sizeof(CFE_FS_Header_t)) {
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_FILE_STD_HDR_ERR_EID, Status, sizeof(CFE_FS_Header_t));
    Status = CFE_TBL_ERR_NO_STD_HEADER;
  } else if (FileHeader->Std.ContentType != CFE_FS_FILE_CONTENT_ID) {
    Status = CFE_TBL_ERR_BAD_CONTENT_ID;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_FILE_TYPE_ERR_EID, Status, FileHeader->Std.ContentType);
  } else if (FileHeader->Std.SubType != CFE_FS_SubType_TBL_IMG) {
    Status = CFE_TBL_ERR_BAD_SUBTYPE_ID;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_FILE_SUBTYPE_ERR_EID, Status, FileHeader->Std.SubType);
  } else if (!CFE_TBL_ValidateTableHeaderId(CFE_CONFIGID_PLATFORM_TBL_VALID_SCID, FileHeader->Std.SpacecraftID)) {
    /* Verify Spacecraft ID contained in table file header [optional] */
    Status = CFE_TBL_ERR_BAD_SPACECRAFT_ID;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_SPACECRAFT_ID_ERR_EID, Status, FileHeader->Std.SpacecraftID);
  } else if (!CFE_TBL_ValidateTableHeaderId(CFE_CONFIGID_PLATFORM_TBL_VALID_PRID, FileHeader->Std.ProcessorID)) {
    /* Verify Processor ID contained in table file header [optional] */
    Status = CFE_TBL_ERR_BAD_PROCESSOR_ID;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_PROCESSOR_ID_ERR_EID, Status, FileHeader->Std.ProcessorID);
  } else {
    Status = CFE_TBL_DecodeHeadersFromFile(Txn, FileDescriptor, &FileHeader->Tbl);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ValidateFileIsLoadable(CFE_TBL_TxnState_t *Txn, CFE_TBL_File_Hdr_t *TblFileHeader)
{
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  /*
   * Note, this function only needs to validate the file itself.  The config+state of the table
   * (RegRecPtr) has already been checked and it is already known to be in a state that permits
   * loading in general.
   */
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  if (RegRecPtr == NULL) {
    /* it should not be possible to get here in FSW, but UT can trigger this, so handle it */
    Status = CFE_TBL_ERR_INVALID_HANDLE;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_NO_SUCH_TABLE_ERR_EID, Status, 0);
  } else if (StrCmp(CFE_TBL_RegRecGetName(RegRecPtr), TblFileHeader->TableName) != 0) {
    Status = CFE_TBL_ERR_FILE_FOR_WRONG_TABLE;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_LOAD_TBLNAME_MISMATCH_ERR_EID, Status, 0);
  } else if (TblFileHeader->NumBytes == 0) {
    /* Loading an empty file is not valid; this suggests some form of data error / missing
     * header */
    Status = CFE_TBL_ERR_NO_TBL_HEADER;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_ZERO_LENGTH_LOAD_ERR_EID, Status, 0);
  } else if (TblFileHeader->Offset > 0 && !CFE_TBL_RegRecIsTableLoaded(RegRecPtr)) {
    /* Partial loads can only occur on previously loaded tables. */
    Status = CFE_TBL_ERR_PARTIAL_LOAD;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_PARTIAL_LOAD_ERR_EID, Status, 0);
  } else {
    Status = CFE_TBL_ValidateCodecLoadSize(Txn, TblFileHeader);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_LoadContentFromFile(CFE_TBL_TxnState_t *Txn, U32 FileDescriptor, I64 Offset, I64 NumBytes)
{
  I64 ActualBytes;
  U8 ExtraByte;
  U8 *DestPtr;
  I32 OsStatus;
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *WorkingBufferPtr;
  I64 LoadTailSize;
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  WorkingBufferPtr = CFE_TBL_AcquireCodecBuffer(RegRecPtr);
  if (WorkingBufferPtr == NULL) {
    Status = CFE_TBL_ERR_NO_BUFFER_AVAIL;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_NO_WORK_BUFFERS_ERR_EID, Status, 0);
    return Status;
  }
  /* Confirm that the data about to be loaded will fit */
  LoadTailSize = Offset + NumBytes;
  if (LoadTailSize > CFE_TBL_LoadBuffGetAllocSize(WorkingBufferPtr)) {
    Status = CFE_TBL_ERR_FILE_TOO_LARGE;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_FILE_TOO_BIG_ERR_EID, LoadTailSize, CFE_TBL_LoadBuffGetAllocSize(WorkingBufferPtr));
  } else {
    /* Find where this goes in the memory buffer */
    DestPtr = CFE_TBL_LoadBuffGetWritePointer(WorkingBufferPtr);
    DestPtr += Offset;
    /* Now actually read the data, and confirm that the end of the file data lines up as
     * expected */
    OsStatus = OS_read(FileDescriptor, DestPtr, NumBytes);
    if (OsStatus >= OS_SUCCESS)
      ActualBytes = OsStatus;
    /* status code conversion (size) */
    else ActualBytes = 0;
    if (ActualBytes != NumBytes) {
      Status = CFE_TBL_ERR_LOAD_INCOMPLETE;
      CFE_TBL_TxnAddEvent(Txn, CFE_TBL_FILE_INCOMPLETE_ERR_EID, OsStatus, NumBytes);
    } else {
      // THE ONE-BYTE READ PAST THE END IS THE REAL CHECK. A header that claims fewer bytes than
      // the file holds would pass every length test above; the only way to catch it is to try
      // to read one more byte and refuse if it arrives.
      /* Check to see if the file is too large (ie - more data than header claims) */
      OsStatus = OS_read(FileDescriptor, &ExtraByte, 1);
      if (OsStatus >= OS_SUCCESS)
        ActualBytes = OsStatus;
      /* status code conversion (size) */
      else ActualBytes = 0;
      /* If successfully read another byte, then file must have too much data */
      if (ActualBytes == 1) {
        Status = CFE_TBL_ERR_FILE_TOO_LARGE;
        CFE_TBL_TxnAddEvent(Txn, CFE_TBL_FILE_TOO_BIG_ERR_EID, OsStatus, 0);
      } else {
        CFE_TBL_LoadBuffSetContentSize(WorkingBufferPtr, LoadTailSize);
        Status = CFE_TBL_DecodeInputData(Txn, WorkingBufferPtr, CFE_TBL_GetLoadInProgressBuffer(RegRecPtr));
      }
    }
  }
  CFE_TBL_ReleaseCodecBuffer(WorkingBufferPtr);
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_SetMetaDataFromFileHeader(CFE_TBL_TxnState_t *Txn, U8 *Filename, CFE_FS_Header_t *StdHeader)
{
  CFE_TBL_LoadBuff_t *WorkingBufferPtr;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  WorkingBufferPtr = CFE_TBL_GetLoadInProgressBuffer(RegRecPtr);
  /* This function should not be called unless there is a working buffer, to do so
   * is a calling error.  This verification avoids warnings from static analysis */
  if (WorkingBufferPtr != NULL) {
    StrNCpy(WorkingBufferPtr->DataSource, Filename, OS_MAX_PATH_LEN - 1);
    WorkingBufferPtr->DataSource[OS_MAX_PATH_LEN - 1] = '\0';
    /* Save file creation time for later storage into Registry */
    WorkingBufferPtr->FileTime.Seconds = StdHeader->TimeSeconds;
    WorkingBufferPtr->FileTime.Subseconds = StdHeader->TimeSubSeconds;
    /* Compute the CRC on the specified table buffer */
    CFE_TBL_LoadBuffRecomputeCRC(WorkingBufferPtr);
    /* Initialize validation flag with true if no Validation Function is required to be
     * called */
    WorkingBufferPtr->IsValid = CFE_TBL_RegRecGetValidationFunc(RegRecPtr) == NULL;
    /* It is not ready to be activated until the Activate command is issued */
    WorkingBufferPtr->ActivateReq = FALSE;
  }
}
/*----------------------------------------------------------------
 *
 * Local helper function for sending events
 * This function handles general events that are _not_ related to a file header
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_SendLoadBasicEventHelper(CFE_TBL_TxnEvent_t *Event, CFE_TBL_TxnEventContext_t *Ctxt)
{
  U16 EventType;
  U8 EventString[CFE_MISSION_EVS_MAX_MESSAGE_LENGTH];
  /* The majority of the events are errors, but this can be reset later to demote to info/debug
   */
  EventType = CFE_EVS_EventType_ERROR;
  EventString[0] = 0;
  switch (Event->EventId) {
    case CFE_TBL_NO_SUCH_TABLE_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Unable to locate in Table Registry");
    break;
    case CFE_TBL_HANDLE_ACCESS_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "No access to Tbl Handle");
    break;
    case CFE_TBL_NO_WORK_BUFFERS_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "No working buffers available, stat=0x%lx", Event->EventData1);
    break;
    case CFE_TBL_LOADING_A_DUMP_ONLY_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Attempted to load DUMP-ONLY table");
    break;
    case CFE_TBL_LOAD_IN_PROGRESS_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Load already in progress");
    break;
    case CFE_TBL_LOAD_TYPE_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Attempted to load from illegal source type=%d", Event->EventData2);
    break;
    case CFE_TBL_LOAD_VAL_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Validation func return code invalid (Stat=%lx)", Event->EventData1);
    break;
    case CFE_TBL_VALIDATION_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Validation func reports table invalid (Stat=%lx)", Event->EventData1);
    break;
  }
  if (EventString[0] == 0)
    return FALSE;
  /* Finally send the actual event by appending all the info we have */
  CFE_EVS_SendEventWithAppID(Event->EventId, EventType, CFE_TBL_Global.TableTaskAppId, "%s,app=%s,tbl=%s:%s", Ctxt->Operation, Ctxt->CallerName, Ctxt->TableName, EventString);
  return TRUE;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_SendTableLoadEvents(CFE_TBL_TxnState_t *Txn)
{
  CFE_TBL_SendTransactionEvents(Txn, "Load", &CFE_TBL_SendLoadBasicEventHelper, NULL);
}
/*----------------------------------------------------------------
 *
 * Local helper function for sending events
 * This function handles events that may be related to a file header
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_SendLoadFileEventHelper(CFE_TBL_TxnEvent_t *Event, CFE_TBL_TxnEventContext_t *Ctxt)
{
  CFE_TBL_LoadFileContext_t *LoadFileCtxt;
  U16 EventType;
  U8 EventString[CFE_MISSION_EVS_MAX_MESSAGE_LENGTH];
  LoadFileCtxt = Ctxt->OperationDataPtr;
  /* The majority of the events are errors, but this can be reset later to demote to info/debug
   */
  EventType = CFE_EVS_EventType_ERROR;
  EventString[0] = 0;
  switch (Event->EventId) {
    case CFE_TBL_NO_SUCH_TABLE_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Tbl Hdr has invalid name: '%s'", LoadFileCtxt->FileHdr->Tbl.TableName);
    break;
    case CFE_TBL_FILE_TOO_BIG_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "File has more data than Tbl Hdr indicates (%d)", LoadFileCtxt->FileHdr->Tbl.NumBytes);
    break;
    case CFE_TBL_FILE_INCOMPLETE_ERR_EID :
    /* A file whose header claims has 'x' amount of data but it only has 'y' */
    /* is considered a fatal error during a load process                     */
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Incomplete load into working buffer");
    break;
    case CFE_TBL_LOAD_TBLNAME_MISMATCH_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "File for wrong table '%s'", LoadFileCtxt->FileHdr->Tbl.TableName);
    break;
    case CFE_TBL_LOAD_EXCEEDS_SIZE_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Cannot load %u at off %u", LoadFileCtxt->FileHdr->Tbl.NumBytes, LoadFileCtxt->FileHdr->Tbl.Offset);
    break;
    case CFE_TBL_ZERO_LENGTH_LOAD_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Table header indicates no data in file");
    break;
    case CFE_TBL_PARTIAL_LOAD_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "partial load for uninitialized table");
    break;
    case CFE_TBL_FILE_STD_HDR_ERR_EID :
    /* unsuccessful read of standard cFE File Header */
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Unable to read std header, Status = 0x%08x", Event->EventData1);
    break;
    case CFE_TBL_FILE_TBL_HDR_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Unable to read tbl header, Status = 0x%08x", Event->EventData1);
    break;
    case CFE_TBL_FILE_TYPE_ERR_EID :
    /* file type is not a cFE compatible file */
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "not a cFE file type, ContentType = 0x%08x", LoadFileCtxt->FileHdr->Std.ContentType);
    break;
    case CFE_TBL_FILE_SUBTYPE_ERR_EID :
    /* The SubType is not a Table Image File */
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "File subtype is wrong. Subtype = 0x%08x", LoadFileCtxt->FileHdr->Std.SubType);
    break;
    case CFE_TBL_SPACECRAFT_ID_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Invalid Spacecraft ID (0x%08X)", LoadFileCtxt->FileHdr->Std.SpacecraftID);
    break;
    case CFE_TBL_PROCESSOR_ID_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Invalid Processor ID (0x%08X)", LoadFileCtxt->FileHdr->Std.ProcessorID);
    break;
    case CFE_TBL_FILE_ACCESS_ERR_EID :
    /* Error opening specified file */
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Unable to open, Status = %ld", Event->EventData1);
    break;
    case CFE_TBL_FILE_LOADED_INF_EID :
    /* This one is success, not an error */
    EventType = CFE_EVS_EventType_INFORMATION;
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Successful load into working buffer");
    break;
    case CFE_TBL_LOAD_FILENAME_LONG_ERR_EID :
    StrPrintN(EventString, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH, "Filename invalid");
    break;
  }
  // IT FALLS THROUGH TO THE BASIC HELPER RATHER THAN DECLINING, which is the asymmetry: a FILE
  // load can raise a basic event, but a non-file load can never raise a file one.
  if (EventString[0] == 0) {
    /* A file load can generate some of the basic events too */
    return CFE_TBL_SendLoadBasicEventHelper(Event, Ctxt);
  }
  /* Finally send the actual event by appending all the info we have */
  CFE_EVS_SendEventWithAppID(Event->EventId, EventType, CFE_TBL_Global.TableTaskAppId, "%s,app=%s,file=%s,tbl=%s:%s", Ctxt->Operation, Ctxt->CallerName, LoadFileCtxt->LoadFilename, Ctxt->TableName, EventString);
  return TRUE;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_SendTableLoadFileEvents(CFE_TBL_TxnState_t *Txn, U8 *Filename, CFE_TBL_CombinedFileHdr_t *FileHdr)
{
  CFE_TBL_LoadFileContext_t Ctxt;
  MemSet(&Ctxt, 0, sizeof(CFE_TBL_LoadFileContext_t));
  Ctxt.FileHdr = FileHdr;
  if (Filename != NULL) {
    Ctxt.LoadFilename = Filename;
  } else {
    Ctxt.LoadFilename = "[none]";
  }
  CFE_TBL_SendTransactionEvents(Txn, "LoadFile", &CFE_TBL_SendLoadFileEventHelper, &Ctxt);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnLoadFromFile(CFE_TBL_TxnState_t *Txn, U8 *Filename)
{
  I32 Status;
  CFE_TBL_CombinedFileHdr_t Header;
  U32 FileDescriptor;
  /* just in case, clear out the header */
  MemSet(&Header, 0, sizeof(CFE_TBL_CombinedFileHdr_t));
  /* open the file and sanity check it.  If successful, this will output a valid
   * file descriptor (still open) that is positioned at the file data, along with
   * populating the fields within Header.  If unsuccessful, nothing else to do. */
  Status = CFE_TBL_TxnOpenTableLoadFile(Txn, Filename, &FileDescriptor, &Header);
  if (Status == CFE_SUCCESS) {
    /* NOTE: the FileDescriptor is valid and must be closed before leaving */
    /* check the sanity of the headers against the registry record */
    Status = CFE_TBL_ValidateFileIsLoadable(Txn, &Header.Tbl);
    if (Status == CFE_SUCCESS)
      Status = CFE_TBL_LoadContentFromFile(Txn, FileDescriptor, Header.Tbl.Offset, Header.Tbl.NumBytes);
    /* Done with the file now -- must always close the file regardless of what happened */
    OS_close(FileDescriptor);
  }
  /* If all the above worked out, then set the meta info in the load buffer */
  if (Status == CFE_SUCCESS) {
    CFE_TBL_SetMetaDataFromFileHeader(Txn, Filename, &Header.Std);
    /* Determine the final status code to return to the caller.  This may be an "alternate
     * success" code, in the case that the file was not complete.  These should be
     * removed/deprecated because they are confusing, but preserving for now for backward
     * compatibility.  */
    Status = CFE_TBL_CodecGetFinalStatus(Txn, &Header.Tbl);
  }
  /* Send any events associated with this table load */
  /* Note that many of these require the Header context, which is local,
   * so send events before it goes out of scope */
  CFE_TBL_SendTableLoadFileEvents(Txn, Filename, &Header);
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_TxnLoadFromSourceAddr(CFE_TBL_TxnState_t *Txn, U8 *Address)
{
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *WorkingBufferPtr;
  CFE_TBL_TableConfig_t *CfgPtr;
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  WorkingBufferPtr = CFE_TBL_GetLoadInProgressBuffer(RegRecPtr);
  /*
   * Note, on dump only tables, the buffer pointer isn't set until the first load,
   * whereas on normal (non-dump only) tables, the buffer pointer is always set as
   * part of registration and thus can never be NULL at this point (in fact, checking
   * for NULL would result in a non-reachable branch in the test cases).
   */
  // HOISTED, limit 17: `CFE_TBL_RegRecGetConfig(RegRecPtr)->DumpOnly` resolves the arrow against
  // the FIRST ARGUMENT's class and the compiler refuses.
  CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr);
  if (CfgPtr->DumpOnly) {
    /* for dump-only, the data is not copied - just use the user-supplied addr directly */
    CFE_TBL_LoadBuffSetExternalBlock(WorkingBufferPtr, Address, CFE_TBL_RegRecGetSize(RegRecPtr));
  } else {
    /* When the source is a block of memory, it is assumed to be a complete load */
    CFE_TBL_LoadBuffCopyData(WorkingBufferPtr, Address, CFE_TBL_RegRecGetSize(RegRecPtr));
  }
  /* If success, then initialize the rest of the pending buffer info */
  StrPrintN(WorkingBufferPtr->DataSource, OS_MAX_PATH_LEN, "Addr 0x%08lX", Address);
  // CFE_TIME_ZERO_VALUE is a C compound literal, `(CFE_TIME_SysTime_t){0, 0}`, which HolyC has
  // no spelling for; the two fields are assigned instead.
  WorkingBufferPtr->FileTime.Seconds = 0;
  WorkingBufferPtr->FileTime.Subseconds = 0;
  /* Compute the CRC on the specified table buffer */
  CFE_TBL_LoadBuffRecomputeCRC(WorkingBufferPtr);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_AbortLoad(CFE_TBL_RegistryRec_t *RegRecPtr)
{
  /* The ground has aborted the load, free the working buffer for another attempt */
  CFE_TBL_DiscardWorkingBuffer(RegRecPtr);
  CFE_EVS_SendEvent(CFE_TBL_LOAD_ABORT_INF_EID, CFE_EVS_EventType_INFORMATION, "Table Load Aborted for '%s'", CFE_TBL_RegRecGetName(RegRecPtr));
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ValidateLoadRequest(CFE_TBL_TxnState_t *Txn, U32 SrcType)
{
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_TableConfig_t *CfgPtr;
  Status = CFE_SUCCESS;
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  if (RegRecPtr == NULL) {
    /* it should not be possible to get here in FSW, but UT can trigger this, so handle it */
    Status = CFE_TBL_ERR_INVALID_HANDLE;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_NO_SUCH_TABLE_ERR_EID, Status, 0);
  } else if (CFE_TBL_RegRecIsLoadInProgress(RegRecPtr)) {
    /* Loads by an Application are not allowed if a table load is already in progress */
    Status = CFE_TBL_ERR_LOAD_IN_PROGRESS;
    CFE_TBL_TxnAddEvent(Txn, CFE_TBL_LOAD_IN_PROGRESS_ERR_EID, Status, 0);
  } else {
    // HOISTED, limit 17, three times in this chain -- NASA reads
    // CFE_TBL_RegRecGetConfig(RegRecPtr)->DumpOnly and ->UserDefAddr inline.
    CfgPtr = CFE_TBL_RegRecGetConfig(RegRecPtr);
    if (CfgPtr->DumpOnly) {
      // A DUMP-ONLY TABLE CAN BE LOADED EXACTLY ONCE, AND ONLY FROM AN ADDRESS. The first
      // condition is the interesting one: it must be a USER-DEFINED-ADDRESS table AND not yet
      // loaded, which is how a dump-only table is given the pointer to the app's own data
      // exactly once at startup.
      /* Dump-only tables have additional restrictions */
      if (!CfgPtr->UserDefAddr || CFE_TBL_RegRecIsTableLoaded(RegRecPtr)) {
        Status = CFE_TBL_ERR_DUMP_ONLY;
        CFE_TBL_TxnAddEvent(Txn, CFE_TBL_LOADING_A_DUMP_ONLY_ERR_EID, Status, 0);
      } else if (SrcType != CFE_TBL_SRC_ADDRESS) {
        /* dump only tables can only be loaded from an address, not a file */
        Status = CFE_TBL_ERR_ILLEGAL_SRC_TYPE;
        CFE_TBL_TxnAddEvent(Txn, CFE_TBL_LOAD_TYPE_ERR_EID, Status, SrcType);
      }
    } else if (SrcType != CFE_TBL_SRC_ADDRESS && SrcType != CFE_TBL_SRC_FILE) {
      /* For normal loads the source must be an address or a file */
      Status = CFE_TBL_ERR_ILLEGAL_SRC_TYPE;
      CFE_TBL_TxnAddEvent(Txn, CFE_TBL_LOAD_TYPE_ERR_EID, Status, SrcType);
    }
  }
  if (Status == CFE_SUCCESS) {
    /* Obtain a working buffer (either the table's dedicated buffer or one of the shared
     * buffers) */
    /* Note -- this is just to reserve the buffer right now.  It stores the ID of the reserved
     * buffer as the "load in progress" buffer -- we do not need a direct pointer to it here,
     * only confirm that it has been reserved so when a future step needs it, it is ready to go.
     */
    Status = CFE_TBL_GetWorkingBuffer(NULL, RegRecPtr);
    if (Status != CFE_SUCCESS)
      CFE_TBL_TxnAddEvent(Txn, CFE_TBL_NO_WORK_BUFFERS_ERR_EID, Status, 0);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_ValidateLoadInProgress(CFE_TBL_TxnState_t *Txn, I32 LoadStatus)
{
  I32 Status;
  I32 (*ValidationFunc)(U8 *);
  CFE_TBL_RegistryRec_t *RegRecPtr;
  CFE_TBL_LoadBuff_t *WorkingBufferPtr;
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  WorkingBufferPtr = CFE_TBL_GetLoadInProgressBuffer(RegRecPtr);
  ValidationFunc = CFE_TBL_RegRecGetValidationFunc(RegRecPtr);
  /* If the data was successfully loaded, then validate its contents */
  if (WorkingBufferPtr == NULL) {
    /* Not expected -- this is a problem */
    LoadStatus = CFE_TBL_ERR_NEVER_LOADED;
  } else {
    if (ValidationFunc == NULL) {
      /* no validation is assumed success */
      Status = CFE_SUCCESS;
    } else {
      Status = ValidationFunc(CFE_TBL_LoadBuffGetReadPointer(WorkingBufferPtr));
    }
    /*
     * Anything other than CFE_SUCCESS (0) is considered a failure to validate
     *
     * It is not entirely clear why there are two different EIDs here,
     * depending on whether the validation function returned a positive or negative value.
     * This is historical behavior and it has been preserved.
     */
    if (Status > CFE_SUCCESS) {
      CFE_TBL_TxnAddEvent(Txn, CFE_TBL_LOAD_VAL_ERR_EID, Status, 0);
      Status = CFE_STATUS_VALIDATION_FAILURE;
    }
    if (Status < CFE_SUCCESS) {
      CFE_TBL_TxnAddEvent(Txn, CFE_TBL_VALIDATION_ERR_EID, Status, 0);
      /* Zero out the buffer to remove any bad data */
      CFE_TBL_LoadBuffClearData(WorkingBufferPtr);
      LoadStatus = Status;
    }
    /* Validation status implies ready to activate */
    WorkingBufferPtr->IsValid = Status == CFE_SUCCESS;
    WorkingBufferPtr->ActivateReq = WorkingBufferPtr->IsValid;
  }
  return LoadStatus;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_LoadFinish(CFE_TBL_TxnState_t *Txn, I32 LoadStatus)
{
  I32 Status;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  Bool FirstTime;
  U16 EventType;
  RegRecPtr = CFE_TBL_TxnRegRec(Txn);
  if (RegRecPtr != NULL) {
    /*
     * Note that the load status can be an INFO code, which is not CFE_SUCCESS but
     * still is considered successful (these are positive values)
     */
    if (LoadStatus < CFE_SUCCESS) {
      /* If something failed during the load, then drop the working buffer */
      CFE_TBL_DiscardWorkingBuffer(RegRecPtr);
    } else {
      /* Check if this is the initial table load */
      FirstTime = !CFE_TBL_RegRecIsTableLoaded(RegRecPtr);
      /* Note - this call to will also discard the working buffer if it is successful */
      Status = CFE_TBL_UpdateInternal(CFE_TBL_TxnHandle(Txn), RegRecPtr, CFE_TBL_TxnAccDesc(Txn));
      if (Status != CFE_SUCCESS) {
        CFE_EVS_SendEventWithAppID(CFE_TBL_UPDATE_ERR_EID, CFE_EVS_EventType_ERROR, CFE_TBL_Global.TableTaskAppId, "%s: Failed to update '%s' (Stat=%u)", CFE_TBL_TxnAppNameCaller(Txn), CFE_TBL_RegRecGetName(RegRecPtr), Status);
        /* Something went wrong - Use this status code */
        LoadStatus = Status;
      } else {
        // THE FIRST LOAD IS DEBUG, EVERY LATER ONE IS INFORMATION -- hoisted out of the call
        // because HolyC has no conditional expression in an argument position. NASA's reason is
        // in the comment: every table in the system loads once at startup, so making the first
        // one INFORMATION would flood the event log at exactly the worst moment.
        /* The first time a table is loaded, the event message is DEBUG */
        /* to help eliminate a flood of events during a startup         */
        if (FirstTime)
          EventType = CFE_EVS_EventType_DEBUG;
        else
          EventType = CFE_EVS_EventType_INFORMATION;
        CFE_EVS_SendEventWithAppID(CFE_TBL_LOAD_SUCCESS_INF_EID, EventType, CFE_TBL_Global.TableTaskAppId, "Successfully loaded '%s' from '%s'", CFE_TBL_RegRecGetName(RegRecPtr), CFE_TBL_RegRecGetLastFileLoaded(RegRecPtr));
        /* Save the index of the table for housekeeping telemetry */
        CFE_TBL_Global.LastTblUpdated = CFE_TBL_TxnRegId(Txn);
      }
    }
  }
  return LoadStatus;
}
#endif
