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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_erlog.c -- THE EXCEPTION AND RESET LOG.
//
// Five functions. The ER log is the record that survives a reset: a fixed array of twenty
// entries in the reset area, each one saying what happened and what the system did about it.
// Where the system log is a ring of text for a human, this is a ring of RECORDS for the ground
// -- and CFE_ES_RunExceptionScan is the one place in cFE that decides, unprompted, to restart
// the processor.
//
// THE DECISION IN CFE_ES_RunExceptionScan IS THE POINT OF THE FILE, and NASA writes out the
// reasoning: "the default exception handling is to restart the processor/system. There is an
// option to only restart the specific app needs, but this must be 'opt-in', that is, the app
// was created initially with this option, and the exception is also traced back to that app.
// If either is not possible for whatever reason then the restart action (default) should be
// taken, as this gets the highest assurance that the system will be returned to a coherent
// state." Every failure along the way therefore falls through to the processor reset.
//
// THIS FILE INCLUDES NOTHING. docs/HOLYC_STRUCT_LIMITS.md #13: a unit that re-includes a
// sibling the driver has already read loses everything after that line, silently.
//
// REQUIRED INCLUDE ORDER, which the driver provides:
//     cfe_es_global.HC   ES's state and the ER log record types
//     cfe_es_resource.HC the record tables and their accessors
//     cfe_es_api.HC      the locks, WriteToSysLog, GetTaskInfo, RestartApp
// and it comes BEFORE cfe_es_task.HC, not after: CFE_ES_WriteERLogCmd takes the address of
// this file's two background-writer callbacks, and an address-of needs the definition.
#ifndef CFE_ES_ERLOG_HC
#define CFE_ES_ERLOG_HC
// --- cfe_es_log.h ----------------------------------------------------------------------------
// The sentinel for "this entry has no PSP context attached". NASA's comment on the caller says
// why the APP id uses a different one: "passing 0xFFFFFFFF as the appid avoids confusion with
// actual appid 0".
#define CFE_ES_ERLOG_NO_CONTEXT 0
// --- cfe_es_api_typedefs.h -------------------------------------------------------------------
// NASA's comment: "Application only was reset (extend the PSP enumeration here)". It is
// CFE_PSP_RST_TYPE_MAX, one past the last real PSP reset type, so the ResetType field can carry
// a disposition the PSP has no name for.
#define CFE_ES_APP_RESTART 3
// --- cfe_psp.h -------------------------------------------------------------------------------
#define CFE_PSP_RST_SUBTYPE_EXCEPTION 6
// --- default_cfe_es_extern_typedefs.h --------------------------------------------------------
#define CFE_ES_LogEntryType_APPLICATION 2
// Also repeated from cfe_es_task.HC, guarded, for the include-order reason above.
#ifndef CFE_ES_ExceptionAction_RESTART_APP
#define CFE_ES_ExceptionAction_RESTART_APP  0
#define CFE_ES_ExceptionAction_PROC_RESTART 1
#endif
// --- cfe_es_eventids.h -----------------------------------------------------------------------
// Three of the fifty-five cfe_es_task.HC carries. They are repeated here, guarded, because
// THIS FILE COMES FIRST in the driver's include order: cfe_es_task.c takes the ADDRESS of two
// functions defined here, and a HolyC address-of needs the definition, not a declaration.
#ifndef CFE_ES_ERLOG2_EID
#define CFE_ES_ERLOG2_EID 20
#endif
#ifndef CFE_ES_ERLOG2_ERR_EID
#define CFE_ES_ERLOG2_ERR_EID 56
#endif
#ifndef CFE_ES_FILEWRITE_ERR_EID
#define CFE_ES_FILEWRITE_ERR_EID 74
#endif
// --- what this file needs from elsewhere -----------------------------------------------------
// The PSP's exception interface, four calls, none of them translated: the PSP is the board.
U32 CFE_PSP_Exception_GetCount();
I32 CFE_PSP_Exception_GetSummary(U32 *ContextLogId, U32 *TaskId, U8 *ReasonBuf, U32 ReasonSize);
I32 CFE_PSP_Exception_CopyContext(U32 ContextLogId, U8 *ContextBuf, U32 ContextSize);
// Declared here, defined below -- RunExceptionScan calls the WithContext form.
I32 CFE_ES_WriteToERLogWithContext(U32 EntryType, U32 ResetType, U32 ResetSubtype, U8 *Description, U32 AppId, U32 PspContextId);
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE TIME IS TAKEN BEFORE THE LOCK, deliberately: NASA's comment is "Snapshot the time before
// locking (different subsystem)". CFE_TIME_GetTime takes TIME's own lock, and taking two
// subsystem locks in sequence is how a deadlock gets built.
//
// THE INDEX IS REPAIRED, NOT TRUSTED. An ERLogIndex at or past the end is silently reset to 0
// before use -- this log lives in the reset area, which is exactly the memory a processor reset
// does not clear, so a corrupted index is a thing that can arrive from a previous life.
I32 CFE_ES_WriteToERLogWithContext(U32 EntryType, U32 ResetType, U32 ResetSubtype, U8 *Description, U32 AppId, U32 PspContextId)
{
  U32 LogIdx;
  CFE_ES_ERLog_MetaData_t *EntryPtr;
  CFE_TIME_SysTime PendingTime;
  /*
   * Snapshot the time before locking (different subsystem)
   */
  PendingTime = CFE_TIME_GetTime();
  /*
   * Ensure that description string is not NULL.
   */
  if (Description == NULL) {
    Description = "No Description String Given.";
  }
  /*
   * This routine needs to lock in case it is called
   * from concurrent threads
   */
  CFE_ES_LockSharedData("CFE_ES_WriteToERLogWithContext", 79);
  /*
  ** Try to clean up an invalid ER log index variable.
  */
  if (CFE_ES_Global.ResetDataPtr->ERLogIndex >= CFE_PLATFORM_ES_ER_LOG_ENTRIES) {
    CFE_ES_Global.ResetDataPtr->ERLogIndex = 0;
  }
  LogIdx = CFE_ES_Global.ResetDataPtr->ERLogIndex;
  /*
  ** Now that the Local Index variable is set, increment the index for the next entry.
  */
  CFE_ES_Global.ResetDataPtr->ERLogIndex++;
  if (CFE_ES_Global.ResetDataPtr->ERLogIndex >= CFE_PLATFORM_ES_ER_LOG_ENTRIES) {
    CFE_ES_Global.ResetDataPtr->ERLogIndex = 0;
  }
  /*
  ** Clear out the log entry we are about to use.
  */
  EntryPtr = &CFE_ES_Global.ResetDataPtr->ERLog[LogIdx];
  MemSet(EntryPtr, 0, sizeof(CFE_ES_ERLog_MetaData_t));
  /*
  ** Fill out the log fields
  */
  EntryPtr->BaseInfo.LogEntryType = EntryType;
  EntryPtr->BaseInfo.ResetType = ResetType;
  EntryPtr->BaseInfo.ResetSubtype = ResetSubtype;
  EntryPtr->BaseInfo.BootSource = CFE_ES_Global.ResetDataPtr->ResetVars.BootSource;
  EntryPtr->BaseInfo.ProcessorResetCount = CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount;
  EntryPtr->BaseInfo.MaxProcessorResetCount = CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount;
  /*
  ** Copy the ES Reset variables to the log (before they are modified by the log entry).
  */
  MemCpy(&EntryPtr->BaseInfo.DebugVars, &CFE_ES_Global.DebugVars, sizeof(CFE_ES_DebugVariables_t));
  /*
  ** Time Stamp the log entry with the system time
  */
  EntryPtr->BaseInfo.TimeCode = PendingTime;
  /*
  ** Copy the Description string to the log.
  */
  StrNCpy(EntryPtr->BaseInfo.Description, Description, CFE_ES_ERLOG_DESCRIPTION_MAX_LENGTH - 1);
  EntryPtr->BaseInfo.Description[CFE_ES_ERLOG_DESCRIPTION_MAX_LENGTH - 1] = 0;
  /*
   * Store the context info (if any)
   */
  EntryPtr->AppID = AppId;
  EntryPtr->PspContextId = PspContextId;
  /*
  ** Increment the number of ER log entries made
  */
  CFE_ES_Global.ResetDataPtr->ERLogEntries++;
  /*
   * Shared data update is complete
   */
  CFE_ES_UnlockSharedData("CFE_ES_WriteToERLogWithContext", 145);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_WriteToERLog(U32 EntryType, U32 ResetType, U32 ResetSubtype, U8 *Description)
{
  /* passing 0xFFFFFFFF as the appid avoids confusion with actual appid 0 */
  return CFE_ES_WriteToERLogWithContext(EntryType, ResetType, ResetSubtype, Description, CFE_ES_APPID_UNDEFINED, CFE_ES_ERLOG_NO_CONTEXT);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE RETURN VALUE IS "THIS WAS THE LAST RECORD", not "this succeeded". FS's background writer
// calls this once per record and stops when it says so, which is why the out-of-range branch
// hands back a NULL buffer AND true.
//
// A MISSING PSP CONTEXT IS NOT AN ERROR, and NASA says so: "errors here are OK - just means
// there is no context available. Record a size of 0 in the log file." The entry still goes in
// the file, with ContextSize 0.
Bool CFE_ES_BackgroundERLogFileDataGetter(U8 *Meta, U32 RecordNum, U8 **Buffer, I64 *BufSize)
{
  CFE_ES_BackgroundLogDumpGlobal_t *BgFilePtr;
  CFE_ES_ERLog_FileEntry_t *FileBufferPtr;
  CFE_ES_ERLog_MetaData_t *EntryPtr;
  I32 PspStatus;
  BgFilePtr = Meta;
  FileBufferPtr = &BgFilePtr->EntryBuffer;
  if (RecordNum < CFE_PLATFORM_ES_ER_LOG_ENTRIES) {
    EntryPtr = &CFE_ES_Global.ResetDataPtr->ERLog[RecordNum];
    /* First wipe the buffer before re-use */
    MemSet(FileBufferPtr, 0, sizeof(CFE_ES_ERLog_FileEntry_t));
    CFE_ES_LockSharedData("CFE_ES_BackgroundERLogFileDataGetter", 193);
    /* The basic info comes directly from the ES log */
    FileBufferPtr->BaseInfo = EntryPtr->BaseInfo;
    /*
     * The context info, if available, comes from the PSP.
     * This returns the actual size of the context info, or <0 on error.
     */
    PspStatus = CFE_PSP_Exception_CopyContext(EntryPtr->PspContextId, FileBufferPtr->Context, CFE_PLATFORM_ES_ER_LOG_MAX_CONTEXT_SIZE);
    if (PspStatus > 0) {
      FileBufferPtr->ContextSize = PspStatus;
    } else {
      /*
       * errors here are OK - just means there is no context available.
       * Record a size of 0 in the log file.
       */
      FileBufferPtr->ContextSize = 0;
    }
    CFE_ES_UnlockSharedData("CFE_ES_BackgroundERLogFileDataGetter", 218);
    /*
     * Export data to caller for actual write
     */
    *Buffer = FileBufferPtr;
    *BufSize = sizeof(CFE_ES_ERLog_FileEntry_t);
  } else {
    *Buffer = NULL;
    *BufSize = 0;
  }
  /* Check for EOF (last entry)  */
  return (RecordNum >= (CFE_PLATFORM_ES_ER_LOG_ENTRIES - 1));
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// NASA'S OWN NOTE ON WHERE THIS RUNS: "this runs in the context of ES background task (file
// writer background job)". It is a callback the FS writer invokes, not a command handler, so
// there is no command counter to move -- the event IS the report.
//
// THE TWO WRITE ERRORS SHARE ONE EVENT with CFE_ES_FileWriteByteCntErr's, and the wording
// differs by one word: this one says "actual=%u" where cfe_es_task.c's says "status=0x%08x".
// Same event id, two texts.
U0 CFE_ES_BackgroundERLogFileEventHandler(U8 *Meta, U32 Event, I32 Status, U32 RecordNum, I64 BlockSize, I64 Position)
{
  CFE_ES_BackgroundLogDumpGlobal_t *BgFilePtr;
  BgFilePtr = Meta;
  /* Note that this runs in the context of ES background task (file writer background job) */
  switch (Event) {
    case CFE_FS_FileWriteEvent_COMPLETE :
    CFE_EVS_SendEvent(CFE_ES_ERLOG2_EID, CFE_EVS_EventType_DEBUG, "%s written:Size=%lu", BgFilePtr->FileWrite.FileName, Position);
    break;
    case CFE_FS_FileWriteEvent_HEADER_WRITE_ERROR :
    case CFE_FS_FileWriteEvent_RECORD_WRITE_ERROR :
    CFE_EVS_SendEvent(CFE_ES_FILEWRITE_ERR_EID, CFE_EVS_EventType_ERROR, "File write,byte cnt err,file %s,request=%u,actual=%u", BgFilePtr->FileWrite.FileName, BlockSize, Status);
    break;
    case CFE_FS_FileWriteEvent_CREATE_ERROR :
    CFE_EVS_SendEvent(CFE_ES_ERLOG2_ERR_EID, CFE_EVS_EventType_ERROR, "Error creating file %s, RC = %d", BgFilePtr->FileWrite.FileName, Status);
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
// THE ONE PLACE IN cFE THAT RESETS THE PROCESSOR WITHOUT BEING TOLD TO, and the whole function
// is the argument for doing it. Every path that cannot POSITIVELY identify an app that opted
// in to app-only restart falls through to a PSP reset -- a PSP error, a task id of 0, a
// GetTaskInfo failure, an app record that does not match, an ExceptionAction that is not
// RESTART_APP. NASA states the rule: "this gets the highest assurance that the system will be
// returned to a coherent state."
//
// THE do/while IS A RETRY WITH ONE STEP. An app restart that is REFUSED sets ResetType back to
// 0 and the loop runs again -- which, with ResetType 0, now takes the processor-reset branch.
// So "restart the app" degrades to "reset the processor" rather than to "do nothing", and the
// reason string is rewritten to say so.
//
// AND THE SYSLOG LINE IS DELIBERATE DUPLICATION: "writes to the ES ER log actually do not get
// propagated to the debug console. so by writing to SysLog here it becomes visible in both
// places."
//
// MAX PROCESSOR RESETS ESCALATES TO POWER-ON. The count is in the reset area, so it survives
// the processor reset it is counting -- which is what makes the escalation possible at all.
Bool CFE_ES_RunExceptionScan(U32 ElapsedTime, U8 *Arg)
{
  I32 Status;
  I32 PspStatus;
  U32 PspContextId;
  U8 ReasonString[CFE_ES_ERLOG_DESCRIPTION_MAX_LENGTH];
  CFE_ES_TaskInfo_t EsTaskInfo;
  U32 ExceptionTaskID = OS_OBJECT_ID_UNDEFINED;
  U32 ResetType;
  U32 LogType;
  CFE_ES_AppRecord_t *AppRecPtr;
  if (CFE_PSP_Exception_GetCount() == 0) {
    /* no exceptions pending, nothing to do */
    return FALSE;
  }
  /*
   * Note a reset type of 0 is not defined by the PSP -
   * the real values are all nonzero
   */
  ResetType = 0;
  MemSet(&EsTaskInfo, 0, sizeof(CFE_ES_TaskInfo_t));
  PspStatus = CFE_PSP_Exception_GetSummary(&PspContextId, &ExceptionTaskID, ReasonString, CFE_ES_ERLOG_DESCRIPTION_MAX_LENGTH);
  if (PspStatus != CFE_PSP_SUCCESS) {
    /* reason string is not available - populate with something for the PspStatus*/
    StrPrintN(ReasonString, CFE_ES_ERLOG_DESCRIPTION_MAX_LENGTH, "Unknown - CFE_PSP_ExceptionGetSummary() error %ld", PspStatus);
    PspContextId = 0;
    ExceptionTaskID = OS_OBJECT_ID_UNDEFINED;
  }
  /*
   * Note that writes to the ES ER log actually do not get propagated to the debug console.
   * so by writing to SysLog here it becomes visible in both places.
   */
  CFE_ES_WriteToSysLog("%s: ExceptionID 0x%lx in TaskID %lu: %s\n", "CFE_ES_RunExceptionScan", PspContextId, ExceptionTaskID, ReasonString);
  /*
   * If task ID is 0, this means it was a system level exception and
   * not associated with a specific task.
   *
   * Otherwise, if it was related to a task, determine the associated AppID
   * so the exception action can be checked.
   *
   * NOTE: the default exception handling is to restart the processor/system.
   * There is an option to only restart the specific app needs, but this must
   * be "opt-in", that is, the app was created initially with this option, and
   * the exception is also traced back to that app.  If either is not possible
   * for whatever reason then the restart action (default) should be taken, as
   * this gets the highest assurance that the system will be returned to a coherent
   * state.
   */
  if (OS_ObjectIdDefined(ExceptionTaskID)) {
    Status = CFE_ES_GetTaskInfo(&EsTaskInfo, CFE_ES_TaskId_FromOSAL(ExceptionTaskID));
    /*
     * The App ID was found, now see if the ExceptionAction is set for a reset
     *
     * NOTE: if anything in this logic fails and the app which caused the exception is not
     * positively identified, then this will just follow the default case of PSP reset.
     */
    if (Status == CFE_SUCCESS) {
      AppRecPtr = CFE_ES_LocateAppRecordByID(EsTaskInfo.AppId);
      CFE_ES_LockSharedData("CFE_ES_RunExceptionScan", 368);
      if (CFE_ES_AppRecordIsMatch(AppRecPtr, EsTaskInfo.AppId) && AppRecPtr->StartParams.ExceptionAction == CFE_ES_ExceptionAction_RESTART_APP) {
        /*
         * Log the Application reset
         */
        ResetType = CFE_ES_APP_RESTART;
      }
      CFE_ES_UnlockSharedData("CFE_ES_RunExceptionScan", 377);
    }
  }
  do {
    /*
     * If no disposition is identified yet, then trigger a PSP reset.
     * Need to determine if a processor or poweron reset is needed.
     */
    if (ResetType == 0) {
      if (CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount >= CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount) {
        CFE_ES_WriteToSysLog("%s: Maximum Processor Reset count reached (%u)", "CFE_ES_RunExceptionScan", CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount);
        ResetType = CFE_PSP_RST_TYPE_POWERON;
      } else {
        CFE_ES_WriteToSysLog("%s: Processor Reset count not reached (%u/%u)", "CFE_ES_RunExceptionScan", CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount, CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount);
        /*
        ** Update the reset variables
        */
        CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount++;
        CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset = TRUE;
        ResetType = CFE_PSP_RST_TYPE_PROCESSOR;
      }
    }
    if (ResetType == CFE_ES_APP_RESTART) {
      LogType = CFE_ES_LogEntryType_APPLICATION;
    } else {
      LogType = CFE_ES_LogEntryType_CORE;
    }
    CFE_ES_WriteToERLogWithContext(LogType, ResetType, CFE_PSP_RST_SUBTYPE_EXCEPTION, ReasonString, EsTaskInfo.AppId, PspContextId);
    if (ResetType == CFE_ES_APP_RESTART) {
      /*
       * Restart the App. This call is just a request
       * to ES, but the request could fail.  If that happens,
       * proceed to a processor reset.
       */
      Status = CFE_ES_RestartApp(EsTaskInfo.AppId);
      if (Status != CFE_SUCCESS) {
        ResetType = 0;
        StrPrintN(ReasonString, CFE_ES_ERLOG_DESCRIPTION_MAX_LENGTH, "App Restart Failed");
      }
    } else {
      /* normally this will not return */
      CFE_PSP_Restart(ResetType);
    }
  } while (ResetType == 0);
  return TRUE;
  /* returning true because there was an exception to deal with */
}
#endif
