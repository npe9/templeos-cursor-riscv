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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_appctrl.c -- WHERE A CONTROL REQUEST
// IS ACTUALLY CARRIED OUT.
//
// Six functions, and this is the other half of the arrangement cfe_es_api.c's RestartApp,
// ReloadApp and DeleteApp set up: each of those only STORES a request, because an app cannot
// be torn down from inside the caller's context. This file is what the background task runs
// later to do the work.
//
// AND IT DOES IT IN ONE SHAPE FOR ALL SEVEN REQUESTS, which NASA states: "All control requests
// start by deleting the app/task and all associated resources. The reload/restart requests
// will start it again, and it gets a new appID. For other requests it just leaves it deleted."
// So the only difference between them is WHICH EVENT comes out -- "Note that the specific
// event ID that gets generated is the only other difference between all these control request
// types" -- which is why the table below exists.
//
// CLEANUP FAILING DOES NOT STOP THE RESTART, and the reasoning is worth keeping: "Cleanup can
// fail for a variety of reasons, including situations where e.g. a task ID had become stale
// because the task already exited itself. In most cases these are minor errors and reflect
// problems with the consistency of the old app record. Even when this happens the cleanup
// should still do its best effort to release all relevant global data entries. So it should not
// prevent starting the new app, if a restart/reload is indicated."
//
// THIS FILE INCLUDES NOTHING. docs/HOLYC_STRUCT_LIMITS.md #13.
//
// REQUIRED INCLUDE ORDER, which the driver provides:
//     cfe_es_global.HC    CFE_ES_Global and CFE_ES_AppTableScanState_t
//     cfe_es_resource.HC  the app table's accessors
//     cfe_es_api.HC       the locks, and the run-status and app-state enums
//     cfe_es_task.HC      the twenty-two events' ids are declared there; this file adds its own
#ifndef CFE_ES_APPCTRL_HC
#define CFE_ES_APPCTRL_HC
// --- cfe_es_internal_cfg.h ------------------------------------------------------------------
#define CFE_PLATFORM_ES_APP_KILL_TIMEOUT 5
// Also named by cfe_es_backgroundtask.HC, which is included AFTER this file -- it has to be,
// because its job table takes &CFE_ES_RunAppTableScan and an address-of needs the definition.
// So this file is the one that defines the scan rate and that one guards its copy.
#ifndef CFE_PLATFORM_ES_APP_SCAN_RATE
#define CFE_PLATFORM_ES_APP_SCAN_RATE 1000
#endif
// --- cfe_error.h ----------------------------------------------------------------------------
#ifndef CFE_STATUS_NOT_IMPLEMENTED
#define CFE_STATUS_NOT_IMPLEMENTED 0xC800FFFF(I32)
#endif
// --- cfe_es_eventids.h: the fourteen this file raises ---------------------------------------
#ifndef CFE_ES_STOP_INF_EID
#define CFE_ES_STOP_INF_EID 8
#endif
#ifndef CFE_ES_RESTART_APP_INF_EID
#define CFE_ES_RESTART_APP_INF_EID  10
#define CFE_ES_RELOAD_APP_INF_EID   12
#define CFE_ES_EXIT_APP_INF_EID     13
#define CFE_ES_ERREXIT_APP_INF_EID  14
#define CFE_ES_STOP_ERR3_EID        37
#define CFE_ES_RESTART_APP_ERR3_EID 40
#define CFE_ES_RESTART_APP_ERR4_EID 41
#define CFE_ES_RELOAD_APP_ERR3_EID  44
#define CFE_ES_RELOAD_APP_ERR4_EID  45
#define CFE_ES_EXIT_APP_ERR_EID     46
#define CFE_ES_PCR_ERR1_EID         47
#define CFE_ES_PCR_ERR2_EID         48
#define CFE_ES_ERREXIT_APP_ERR_EID  33
#endif
// --- what this file needs from elsewhere ----------------------------------------------------
// cfe_es_apps.c is not gated, so both of these are stubs on both halves of the oracle.
I32 CFE_ES_CleanUpApp(U32 AppId);

/*
 * Mapping for control requests
 * Provides event details to send when the control request is processed
 */
class CFE_ES_ControlReqMapEntry_t
{
  U8 *ReqName; // printable name
  U16 CleanupErrEventID; // Event to send if cleanup failed (always an error)
  U16 StartupErrEventID; // Event to send if startup failed (always an error)
  U16 ErrorEventID;      // Generic Error Event to send (valid for abnormal requests)
  U16 NominalEventID;    // Generic Info Event to send (valid for normal requests)
};
// THE TABLE IS INDEXED BY RUN STATUS, and NASA writes it with DESIGNATED initialisers -- ten
// entries, most of them setting two of the five fields and leaving the rest zero. HolyC has
// none, so every field is positional and the zeros are written out: ReqName,
// CleanupErrEventID, StartupErrEventID, ErrorEventID, NominalEventID, in that order.
//
// THE ZEROS ARE THE LOGIC, not padding. NASA's note above the table: "The ControlReqInfo entry
// should set the ErrorEventID (only) for abnormal conditions. Normal Request conditions should
// set NominalEventID and should NOT set ErrorEventID." Every `if` below tests one of these
// fields against 0, so a field written where NASA left it zero changes which event comes out.
//
// AND SLOT 0 HAS NO NAME ON PURPOSE. CFE_ES_RunStatus_UNDEFINED is the entry
// CFE_ES_ProcessControlRequest_Finish falls back to for any out-of-range request, and a NULL
// ReqName is how the error sender knows to print "[Req%u]" instead.
//
// NASA leaves CFE_ES_RunStatus_APP_RUN's ErrorEventID commented out with a `//jphfix` marker.
// It is left commented here too: the effect is that a control request of APP_RUN -- which
// "should not show up in a control request" -- produces no event at all, and that is the
// behaviour, bug or not.
//
// AND WHAT HOLDS THE POSITIONS TO NASA'S DESIGNATORS IS A SECOND GATE, which is the only
// reason this is safe to write positionally: a designated initialiser says WHICH index each
// row is, and a positional one only says the order. The indices are CFE_ES_RunStatus_UNDEFINED
// through _CORE_APP_RUNTIME_ERROR, which this port re-states as #defines 0..9 in cfe_es_api.HC
// -- and tools/cfs/check_constants.py compares every one of them against the enumerator NASA
// actually declares, through its enumerator pass. So if NASA renumbers or inserts a run status,
// that gate fails before this table silently shifts. The ten rows themselves are driven one at
// a time by the differential transcript, which prints the event each produces.
//
// This is a `static const` LOCAL in NASA's C. It is at file scope here, under the enclosing
// function's name, which is this port's convention for one (cfe_es_syslog.HC's FRAGMENT_TAG).
CFE_ES_ControlReqMapEntry_t CFE_ES_ProcessControlRequest_Finish_CONTROL_REQ_MAP[CFE_ES_RunStatus_MAX] = {
    /* [UNDEFINED] catches all abnormal cases */
    {NULL, 0, 0, CFE_ES_PCR_ERR2_EID, 0},
    /* [APP_RUN] while "APP_RUN" is normal, it should not show up in a control request */
    /* //jphfix .ErrorEventID = CFE_ES_PCR_ERR2_EID, */
    {"Run", 0, 0, 0, 0},
    /* [APP_EXIT] */
    {"Exit", CFE_ES_EXIT_APP_ERR_EID, 0, 0, CFE_ES_EXIT_APP_INF_EID},
    /* [APP_ERROR] */
    {"ErrExit", CFE_ES_ERREXIT_APP_ERR_EID, 0, 0, CFE_ES_ERREXIT_APP_INF_EID},
    /* [SYS_EXCEPTION] -- note the NOMINAL slot holds an ERR event id, which is NASA's */
    {"Exception", 0, 0, 0, CFE_ES_PCR_ERR1_EID},
    /* [SYS_RESTART] */
    {"Restart", CFE_ES_RESTART_APP_ERR4_EID, CFE_ES_RESTART_APP_ERR3_EID, 0,
     CFE_ES_RESTART_APP_INF_EID},
    /* [SYS_RELOAD] */
    {"Reload", CFE_ES_RELOAD_APP_ERR4_EID, CFE_ES_RELOAD_APP_ERR3_EID, 0,
     CFE_ES_RELOAD_APP_INF_EID},
    /* [SYS_DELETE] */
    {"Stop", CFE_ES_STOP_ERR3_EID, 0, 0, CFE_ES_STOP_INF_EID},
    /* [CORE_APP_INIT_ERROR] */
    {"Core Init Err", 0, 0, CFE_ES_PCR_ERR2_EID, 0},
    /* [CORE_APP_RUNTIME_ERROR] */
    {"Core Runtime Err", 0, 0, CFE_ES_PCR_ERR2_EID, 0}};

/*----------------------------------------------------------------
 *
 * Local helper function
 * Sends the event after a control request error / invalid condition
 *
 *-----------------------------------------------------------------*/
// IT TOLERATES A NULL ReqName, which is the whole reason it is a separate function: the
// fallback entry for an out-of-range request has no name, and NASA's comment at the branch
// says "This event sender can tolerate ReqName being NULL (unknown)".
U0 CFE_ES_ProcessControlRequest_ErrorEvent(CFE_ES_ControlReqMapEntry_t *ControlReqInfo,
                                           U8 *AppName, U32 ControlReq)
{
  U8 ControlReqBuff[16];
  U8 *PrintableReqName;
  if (ControlReqInfo->ReqName == NULL) {
    /* This is for invalid request IDs - should never happen in operation. */
    StrPrintN(ControlReqBuff, 16, "[Req%u]", ControlReq);
    PrintableReqName = ControlReqBuff;
  } else {
    /* The request has a valid name, so use it directly */
    PrintableReqName = ControlReqInfo->ReqName;
  }
  CFE_EVS_SendEvent(ControlReqInfo->ErrorEventID, CFE_EVS_EventType_ERROR, "%s Application %s",
                    PrintableReqName, AppName);
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Sends the event after successful processing of a control request
 *
 *-----------------------------------------------------------------*/
// THE APP ID IS APPENDED ONLY IF THERE IS ONE, which is why the string is built rather than
// passed as an argument: a restart or reload has a NEW app id to report and the other five
// requests have nothing, and NASA wants one event text rather than two.
U0 CFE_ES_ProcessControlRequest_SuccessEvent(CFE_ES_ControlReqMapEntry_t *ControlReqInfo,
                                             U8 *AppName, U32 NewAppId)
{
  U8 AppIdStr[32];
  if (CFE_ResourceId_IsDefined(NewAppId)) {
    /* Additional string showing the new appid */
    StrPrintN(AppIdStr, 32, ", AppID=0x%lx", NewAppId);
  } else {
    /* No additional string */
    AppIdStr[0] = 0;
  }
  CFE_EVS_SendEvent(ControlReqInfo->NominalEventID, CFE_EVS_EventType_INFORMATION,
                    "%s Application %s Success%s.", ControlReqInfo->ReqName, AppName, AppIdStr);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// IT TAKES A COPY OF EVERYTHING IT WILL NEED AND THEN LETS GO OF THE LOCK, and NASA explains:
// "Take a local snapshot of the important app record data. This way it becomes private and can
// be accessed without concerns about other threads/tasks, EVEN AFTER THE GLOBAL DATA RECORDS
// ARE EVENTUALLY CLEARED." The caller is about to delete the very record this reads.
//
// A REQUEST OF 0 MEANS "no record matched", because CFE_ES_RunStatus_UNDEFINED is 0 and the
// snapshot is only taken inside the IsMatch. The caller then falls into the table's slot 0.
U32 CFE_ES_ProcessControlRequest_Start(U32 AppId, U8 *OrigAppNameBuf, I64 OrigAppNameSz,
                                       CFE_ES_AppStartParams_t *RestartParamPtr)
{
  CFE_ES_AppRecord_t *AppRecPtr;
  U32 PendingControlReq;
  /* Init/clear all local state variables */
  PendingControlReq = 0;
  AppRecPtr = CFE_ES_LocateAppRecordByID(AppId);
  /*
   * Take a local snapshot of the important app record data
   * This way it becomes private and can be accessed without
   * concerns about other threads/tasks, even after the global
   * data records are eventually cleared.
   */
  CFE_ES_LockSharedData("CFE_ES_ProcessControlRequest_Start", 155);
  if (CFE_ES_AppRecordIsMatch(AppRecPtr, AppId)) {
    PendingControlReq = AppRecPtr->ControlReq.AppControlRequest;
    StrNCpy(OrigAppNameBuf, AppRecPtr->AppName, OrigAppNameSz - 1);
    OrigAppNameBuf[OrigAppNameSz - 1] = 0;
    /* If a restart was requested, copy the parameters to re-use in new app */
    if (PendingControlReq == CFE_ES_RunStatus_SYS_RESTART ||
        PendingControlReq == CFE_ES_RunStatus_SYS_RELOAD) {
      // NASA writes `*RestartParamPtr = AppRecPtr->StartParams;` -- a struct copy through a
      // BARE POINTER, which copies only the first eight bytes of this 344-byte structure.
      // docs/HOLYC_STRUCT_LIMITS.md #21, pinned by
      // tests/exec/cases/e_struct_copy_into_slot.hc and refused by
      // tools/cfs/check_struct_copy.py. MemCpy is the workaround.
      MemCpy(RestartParamPtr, &AppRecPtr->StartParams, sizeof(CFE_ES_AppStartParams_t));
    }
  }
  CFE_ES_UnlockSharedData("CFE_ES_ProcessControlRequest_Start", 170);
  return PendingControlReq;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// ONE EVENT COMES OUT, AND THE TABLE PICKS WHICH. The precedence is: an ErrorEventID that is
// set ALWAYS wins (and also catches every invalid request, because those have no name); then a
// cleanup failure, but only if this request has an event for one; then a startup failure, same
// condition; then the nominal event, if there is one. NASA's note on the don't-cares is the
// part a reader needs: "The CleanupStatus is a dont-care when CleanupErrEventID is not set."
U0 CFE_ES_ProcessControlRequest_Finish(U32 ControlReq, U8 *AppName, I32 StartupStatus,
                                       I32 CleanupStatus, U32 NewAppId)
{
  CFE_ES_ControlReqMapEntry_t *ControlReqInfo;
  /*
   * NOTE: The ControlReqInfo entry should set the ErrorEventID (only) for
   * abnormal conditions.  Normal Request conditions should set NominalEventID
   * and should NOT set ErrorEventID.
   */
  if (ControlReq < CFE_ES_RunStatus_MAX) {
    ControlReqInfo = &CFE_ES_ProcessControlRequest_Finish_CONTROL_REQ_MAP[ControlReq];
  } else {
    ControlReqInfo =
        &CFE_ES_ProcessControlRequest_Finish_CONTROL_REQ_MAP[CFE_ES_RunStatus_UNDEFINED];
  }
  /* If the ErrorEventID is set, it will ALWAYS be sent */
  /* This also catches all invalid request IDs where ReqName == NULL.  */
  if (ControlReqInfo->ReqName == NULL || ControlReqInfo->ErrorEventID != 0) {
    /* This event sender can tolerate ReqName being NULL (unknown) */
    CFE_ES_ProcessControlRequest_ErrorEvent(ControlReqInfo, AppName, ControlReq);
  } else {
    /*
     * NOTE: all these event senders require that ReqName is valid/non-NULL
     * The CleanupStatus is a dont-care when CleanupErrEventID is not set
     * The StartupStatus is a dont-care when StartupErrEventID is not set
     */
    /* If there is a specific event for cleanup error, send it */
    if (CleanupStatus != CFE_SUCCESS && ControlReqInfo->CleanupErrEventID != 0) {
      /* Make detail message for event containing cleanup error code */
      CFE_EVS_SendEvent(ControlReqInfo->CleanupErrEventID, CFE_EVS_EventType_ERROR,
                        "%s Application %s Failed: CleanUpApp Error 0x%08X.",
                        ControlReqInfo->ReqName, AppName, CleanupStatus);
    } else if (StartupStatus != CFE_SUCCESS && ControlReqInfo->StartupErrEventID != 0) {
      /* Make detail message for event containing startup error code */
      /* The StartupStatus is a dont-care if StartupErrEventID is not set */
      CFE_EVS_SendEvent(ControlReqInfo->StartupErrEventID, CFE_EVS_EventType_ERROR,
                        "%s Application %s Failed: AppCreate Error 0x%08X.",
                        ControlReqInfo->ReqName, AppName, StartupStatus);
    } else if (ControlReqInfo->NominalEventID != 0) {
      /* Make detail message including new AppID, if valid */
      CFE_ES_ProcessControlRequest_SuccessEvent(ControlReqInfo, AppName, NewAppId);
    }
  }
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE WHOLE LIFECYCLE IN TWENTY LINES: snapshot, delete, maybe recreate, report. And
// StartupStatus is CFE_STATUS_NOT_IMPLEMENTED when no restart was asked for -- not
// CFE_SUCCESS, which would make the "AppCreate Error" branch above misfire, and not an error
// code, which would too. It is a value no StartupErrEventID is paired with.
U0 CFE_ES_ProcessControlRequest(U32 AppId)
{
  U32 PendingControlReq;
  CFE_ES_AppStartParams_t RestartParams;
  U8 OrigAppName[OS_MAX_API_NAME];
  I32 CleanupStatus;
  I32 StartupStatus;
  U32 NewAppId;
  /* Init/clear all local state variables */
  NewAppId = CFE_ES_APPID_UNDEFINED;
  MemSet(&RestartParams, 0, sizeof(CFE_ES_AppStartParams_t));
  MemSet(OrigAppName, 0, OS_MAX_API_NAME);
  /*
   * This subroutine looks up the app, gets the name, checks for the pending request
   */
  PendingControlReq =
      CFE_ES_ProcessControlRequest_Start(AppId, OrigAppName, OS_MAX_API_NAME, &RestartParams);
  /*
   * All control requests start by deleting the app/task and
   * all associated resources.
   *
   * The reload/restart requests will start it again, and it gets
   * a new appID.  For other requests it just leaves it deleted.
   *
   * Note that Cleanup can fail for a variety of reasons, including
   * situations where e.g. a task ID had become stale because the task
   * already exited itself.  In most cases these are minor errors and
   * reflect problems with the consistency of the old app record.
   *
   * Even when this happens the cleanup should still do its best effort
   * to release all relevant global data entries.  So it should not
   * prevent starting the new app, if a restart/reload is indicated.
   */
  CleanupStatus = CFE_ES_CleanUpApp(AppId);
  /*
   * Attempt to restart the app if the request indicated to do so,
   * regardless of the CleanupStatus.
   */
  if (PendingControlReq == CFE_ES_RunStatus_SYS_RESTART ||
      PendingControlReq == CFE_ES_RunStatus_SYS_RELOAD) {
    StartupStatus = CFE_ES_AppCreate(&NewAppId, OrigAppName, &RestartParams);
  } else {
    StartupStatus = CFE_STATUS_NOT_IMPLEMENTED;
  }
  /*
   * Send the event(s)
   *
   * Determine the event ID associated with the control request,
   * which indicates the success/failure of the operation and
   * any other relevant detail.
   *
   * Note that the specific event ID that gets generated is the only
   * other difference between all these control request types.
   */
  CFE_ES_ProcessControlRequest_Finish(PendingControlReq, OrigAppName, StartupStatus,
                                      CleanupStatus, NewAppId);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE SCAN IS WHAT MAKES A STORED REQUEST HAPPEN, and it runs from the background task. Two
// things make it due: the timer running out, or the COMMAND COUNTER changing -- NASA's comment
// is "If the command count changes, then a scan becomes due immediately", so a ground command
// that stores a request is acted on at once rather than up to a second later.
//
// A RUNNING APP IS NOT KILLED, IT IS ASKED. An app with a pending request moves to WAITING and
// gets AppTimerMsec; only when that reaches zero does its id go on the timeout list. That is
// the app's chance to exit cleanly through CFE_ES_ExitApp.
//
// AND THE REQUESTS ARE PROCESSED OUTSIDE THE LOCK, from a local list, with NASA's reason:
// "Call CFE_ES_ProcessControlRequest() with a reference to the _copies_ of the app record
// details. (This avoids needing to access the global records outside of the lock)." The scan
// itself must be atomic -- "these state changes need to be done atomically with respect to
// other tasks that also access/update the state" -- but the deletion cannot be.
Bool CFE_ES_RunAppTableScan(U32 ElapsedTime, U8 *Arg)
{
  CFE_ES_AppTableScanState_t *State = Arg;
  U32 i;
  CFE_ES_AppRecord_t *AppPtr;
  U32 AppTimeoutList[CFE_PLATFORM_ES_MAX_APPLICATIONS];
  U32 NumAppTimeouts;
  if (State->PendingAppStateChanges == 0) {
    /*
     * If the command count changes, then a scan becomes due immediately.
     */
    if (State->LastScanCommandCount == CFE_ES_Global.TaskData.CommandCounter &&
        State->BackgroundScanTimer > ElapsedTime) {
      /* no action at this time, background scan is not due yet */
      State->BackgroundScanTimer -= ElapsedTime;
      return FALSE;
    }
  }
  /*
   * Every time a scan is initiated (for any reason)
   * reset the background scan timer to the full value,
   * and take a snapshot of the command counter.
   */
  NumAppTimeouts = 0;
  State->BackgroundScanTimer = CFE_PLATFORM_ES_APP_SCAN_RATE;
  State->LastScanCommandCount = CFE_ES_Global.TaskData.CommandCounter;
  State->PendingAppStateChanges = 0;
  /*
   * Scan needs to be done with the table locked,
   * as these state changes need to be done atomically
   * with respect to other tasks that also access/update
   * the state.
   */
  CFE_ES_LockSharedData("CFE_ES_RunAppTableScan", 425);
  /*
  ** Scan the ES Application table. Skip entries that are:
  **  - Not in use, or
  **  - cFE Core apps, or
  **  - Currently running
  */
  AppPtr = CFE_ES_Global.AppTable;
  for (i = 0; i < CFE_PLATFORM_ES_MAX_APPLICATIONS; i++) {
    if (CFE_ES_AppRecordIsUsed(AppPtr) && AppPtr->Type == CFE_ES_AppType_EXTERNAL) {
      if (AppPtr->AppState > CFE_ES_AppState_RUNNING) {
        /*
         * Increment the "pending" counter which reflects
         * the number of apps that are in some phase of clean up.
         */
        ++State->PendingAppStateChanges;
        /*
         * Decrement the wait timer, if active.
         * When the timeout value becomes zero, take the action to delete/restart/reload the app
         */
        if (AppPtr->ControlReq.AppTimerMsec > ElapsedTime) {
          AppPtr->ControlReq.AppTimerMsec -= ElapsedTime;
        } else {
          AppPtr->ControlReq.AppTimerMsec = 0;
          /* Add it to the list to be processed later */
          AppTimeoutList[NumAppTimeouts] = CFE_ES_AppRecordGetID(AppPtr);
          ++NumAppTimeouts;
        }
      } else if (AppPtr->AppState == CFE_ES_AppState_RUNNING &&
                 AppPtr->ControlReq.AppControlRequest > CFE_ES_RunStatus_APP_RUN) {
        /* this happens after a command arrives to restart/reload/delete an app */
        /* switch to WAITING state, and set the timer for transition */
        AppPtr->AppState = CFE_ES_AppState_WAITING;
        AppPtr->ControlReq.AppTimerMsec =
            CFE_PLATFORM_ES_APP_KILL_TIMEOUT * CFE_PLATFORM_ES_APP_SCAN_RATE;
      }
    }
    ++AppPtr;
  } /* end for loop */
  CFE_ES_UnlockSharedData("CFE_ES_RunAppTableScan", 477);
  /*
   * Now invoke the CFE_ES_ProcessControlRequest() routine for any app
   * which has reached that point.
   */
  for (i = 0; i < NumAppTimeouts; i++) {
    /*
     * Call CFE_ES_ProcessControlRequest() with a reference to
     * the _copies_ of the app record details.  (This avoids
     * needing to access the global records outside of the lock).
     */
    CFE_ES_ProcessControlRequest(AppTimeoutList[i]);
  }
  /*
   * This state machine is considered active if there are any
   * pending app state changes.  Returning "true" will cause this job
   * to be called from the background task at a faster interval.
   */
  return (State->PendingAppStateChanges != 0);
}
#endif
