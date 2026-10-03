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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_apps.c -- THE APP LIFECYCLE, which
// NASA's own header sums up as "starting cFE applications from a filesystem".
//
// Eighteen functions, and they are the two ends of an app's life. One end: load a shared
// object, look up its entry symbol, create its task, and reserve the app-table slot the whole
// rest of ES then finds it by. The other end: take all of that apart again, which is five
// functions because a task owns resources the task cannot release once it is dead.
//
// THE RESERVED-SLOT PROTOCOL IS THE THING TO READ FIRST, and NASA states it in a comment this
// translation keeps verbatim: "In this state, the entry is no longer free, but also will not
// pass the validation test. So this function effectively has exclusive access without holding
// the global lock. IMPORTANT: it must set the ID to something else before leaving this
// function or else the resource will be leaked." That is why CFE_ES_AppCreate has no early
// return after the lock -- "execution must proceed to the end of the function to guarantee
// that the entry is either completed or freed".
//
// CLEANUP IS FIVE FUNCTIONS BECAUSE THE DEAD TASK CANNOT HELP. The resources are gathered
// under the lock, the global records are freed under the lock, and the OSAL objects are deleted
// OUTSIDE it -- a task's queues, semaphores, timers and open files are found by walking every
// OSAL object and asking who created it, which is what CFE_ES_CleanupObjectCallback is for.
//
// THIS FILE INCLUDES NOTHING. docs/HOLYC_STRUCT_LIMITS.md #13.
//
// REQUIRED INCLUDE ORDER, which the driver provides:
//     cfe_es_global.HC    CFE_ES_Global and the four record tables
//     cfe_es_resource.HC  their accessors, locators and slot-used predicates
//     cfe_es_api.HC       the locks, the run-status and app-state enums, CFE_ES_ExitApp
//     cfe_es_syslog.HC    CFE_ES_SysLogWrite_Unsync, which runs under the lock
//     cfe_msg_objtab.HC   Target_ObjectTable, whose AppCleanupCb the cleanup path invokes
//     cfe_target_config.HC  GLOBAL_CONFIGDATA, which carries the core module table
//     cfe_es_mempool.HC   CFE_ES_PoolDelete, called for every pool the app owned
//     ../osal/osapi_module_decl.HC  OS_module_prop_t, for CFE_ES_CopyModuleAddressInfo
#ifndef CFE_ES_APPS_HC
#define CFE_ES_APPS_HC
// --- cfe_es_internal_cfg.h ------------------------------------------------------------------
#ifndef CFE_PLATFORM_ES_STARTUP_SCRIPT_TIMEOUT_MSEC
#define CFE_PLATFORM_ES_STARTUP_SCRIPT_TIMEOUT_MSEC 1000
#endif
#ifndef CFE_PLATFORM_ES_STARTUP_SYNC_POLL_MSEC
#define CFE_PLATFORM_ES_STARTUP_SYNC_POLL_MSEC 100
#endif
// --- osapi-task.h ---------------------------------------------------------------------------
#ifndef OS_FP_ENABLED
#define OS_FP_ENABLED 1
#endif
// --- osapi-idmap.h: the eight object kinds the cleanup callback switches on ------------------
// The translation declares these in os_shared_idmap.HC, which is OSAL's own and across the
// seam; named here with the same values, which tools/cfs/check_constants.py compares against
// NASA's enumerators either way.
#ifndef OS_OBJECT_TYPE_OS_QUEUE
#define OS_OBJECT_TYPE_OS_QUEUE    0x02
#define OS_OBJECT_TYPE_OS_COUNTSEM 0x03
#define OS_OBJECT_TYPE_OS_BINSEM   0x04
#define OS_OBJECT_TYPE_OS_MUTEX    0x05
#define OS_OBJECT_TYPE_OS_TIMECB   0x09
#define OS_OBJECT_TYPE_OS_STREAM   0x06
#define OS_OBJECT_TYPE_OS_MODULE   0x0A
#define OS_OBJECT_TYPE_OS_TASK     0x01
#endif
// --- osapi-module.h: the two symbol-visibility flags ----------------------------------------
// NASA's reasoning for the split is worth keeping, because it is the whole reason cFE cannot
// unload a library: an app's symbols stay LOCAL so the module remains unloadable, and a
// library's must be GLOBAL so other apps can link against them -- "on some OS/loader
// implementations this may make it so the module cannot be unloaded".
#ifndef OS_MODULE_FLAG_LOCAL_SYMBOLS
#define OS_MODULE_FLAG_LOCAL_SYMBOLS  0x01
#endif
// GLOBAL IS ZERO, which makes the library arm's `LoadFlags |= OS_MODULE_FLAG_GLOBAL_SYMBOLS` a
// no-op -- global visibility is OSAL's default and LOCAL is the opt-in. NASA writes the OR
// anyway, for symmetry and so the switch reads as a choice, and so does this.
#ifndef OS_MODULE_FLAG_GLOBAL_SYMBOLS
#define OS_MODULE_FLAG_GLOBAL_SYMBOLS 0x00
#endif
// --- cfe_error.h ----------------------------------------------------------------------------
#ifndef CFE_ES_ERR_APP_REGISTER
#define CFE_ES_ERR_APP_REGISTER 0xC4000017(I32)
#endif
#ifndef CFE_STATUS_EXTERNAL_RESOURCE_FAIL
#define CFE_STATUS_EXTERNAL_RESOURCE_FAIL 0xC8000005(I32)
#endif
// The six per-object-type delete errors CFE_ES_CleanupObjectCallback picks between, plus the
// two the task cleanup returns. Each is the status a LEAKED resource of that kind reports, so
// a caller reading the system log can tell a stuck queue from a stuck semaphore.
// CFE_ES_MEMHANDLE_UNDEFINED is `CFE_ES_MEMHANDLE_C(CFE_RESOURCEID_UNDEFINED)` upstream, and
// the wrapper is the identity in this port -- a memory-pool handle is a resource id like every
// other. Named here because nothing else in the translation had needed it, which
// tools/cfs/check_struct_copy.py is what said so: it refused to call
// `PoolList[i] = CFE_ES_MEMHANDLE_UNDEFINED` resolved, before this file was wired to anything.
#ifndef CFE_ES_MEMHANDLE_UNDEFINED
#define CFE_ES_MEMHANDLE_UNDEFINED CFE_RESOURCEID_UNDEFINED
#endif
#ifndef CFE_ES_MUT_SEM_DELETE_ERR
#define CFE_ES_MUT_SEM_DELETE_ERR   0xC400001B(I32)
#define CFE_ES_BIN_SEM_DELETE_ERR   0xC400001C(I32)
#define CFE_ES_COUNT_SEM_DELETE_ERR 0xC400001D(I32)
#define CFE_ES_QUEUE_DELETE_ERR     0xC400001E(I32)
#define CFE_ES_APP_CLEANUP_ERR      0xC4000023(I32)
#define CFE_ES_TIMER_DELETE_ERR     0xC4000024(I32)
#define CFE_ES_TASK_DELETE_ERR      0xC4000026(I32)
#endif
// --- what this file needs from elsewhere ----------------------------------------------------
// CFE_PSP_SetDefaultExceptionEnvironment is THE BOARD and will still be a stub when every line
// of cFE is translated: it installs the trap handlers a newly created task runs under. NASA
// calls it inside the shared-data lock and says why -- "this should be done serialized (i.e.
// only one task at a time should call into CFE_PSP_SetDefaultExceptionEnvironment)".
U0 CFE_PSP_SetDefaultExceptionEnvironment();

/*
 * Simple state structure used when cleaning up objects associated with tasks
 *
 * This is used locally by CFE_ES_CleanupTaskResources
 */
class CFE_ES_CleanupState_t
{
  U32 ErrorFlag;
  U32 FoundObjects;
  U32 PrevFoundObjects;
  U32 DeletedObjects;
  I32 OverallStatus;
};

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// IT RETURNS STILL HOLDING THE LOCK, which is the one thing a caller has to know and the
// signature cannot say. On success the shared-data lock is HELD and the caller must release
// it; on any failure the lock is dropped and NULL comes back. Three ways to fail -- the id
// matches no record, the app is a CORE app, or it is not running -- and each writes a different
// system-log line, which is why LogMsgAction exists: the caller passes "Restart" or "Delete"
// and one function serves all of them.
CFE_ES_AppRecord_t *CFE_ES_LockUserAppRecord(U32 AppID, U8 *LogMsgAction)
{
  CFE_ES_AppRecord_t *AppRecPtr;
  Bool IsValid;
  IsValid = FALSE;
  AppRecPtr = CFE_ES_LocateAppRecordByID(AppID);
  CFE_ES_LockSharedData("CFE_ES_LockUserAppRecord", 79);
  if (!CFE_ES_AppRecordIsMatch(AppRecPtr, AppID)) {
    CFE_ES_WriteToSysLog("%s: Invalid Application ID received for %s, AppID = %lu\n",
                         "CFE_ES_LockUserAppRecord", LogMsgAction, AppID);
  } else if (AppRecPtr->Type == CFE_ES_AppType_CORE) {
    CFE_ES_SysLogWrite_Unsync("%s: Cannot %s a CORE Application: %s.\n",
                              "CFE_ES_LockUserAppRecord", LogMsgAction,
                              CFE_ES_AppRecordGetName(AppRecPtr));
  } else if (AppRecPtr->AppState != CFE_ES_AppState_RUNNING) {
    CFE_ES_SysLogWrite_Unsync("%s: Cannot %s Application %s, It is not running.\n",
                              "CFE_ES_LockUserAppRecord", LogMsgAction,
                              CFE_ES_AppRecordGetName(AppRecPtr));
  } else {
    IsValid = TRUE;
  }
  if (!IsValid) {
    CFE_ES_UnlockSharedData("CFE_ES_LockUserAppRecord", 108);
    AppRecPtr = NULL;
  }
  return AppRecPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// AN EMPTY FILE NAME IS NOT AN ERROR. A core app, or a library that is already linked in, has
// nothing to load -- so the module id stays undefined and the function still succeeds. The
// entry symbol is looked up only if there is one, and the literal string "NULL" counts as "no
// entry symbol", which is how a startup-script line says so.
//
// AND IT UNLOADS WHAT IT LOADED IF THE LOOKUP FAILS, so a bad entry symbol does not leak a
// module. NASA's note on the failure of that unload is the honest one: "There's not much we can
// do except notify."
I32 CFE_ES_LoadModule(U32 ParentResourceId, U8 *ModuleName, CFE_ES_ModuleLoadParams_t *LoadParams,
                      CFE_ES_ModuleLoadStatus_t *LoadStatus)
{
  U32 ModuleId = OS_OBJECT_ID_UNDEFINED;
  U64 InitSymbolAddress;
  I32 ReturnCode;
  I32 OsStatus;
  U32 LoadFlags;
  LoadFlags = 0;
  InitSymbolAddress = 0;
  ReturnCode = CFE_SUCCESS;
  if (LoadParams->FileName[0] != 0) {
    switch (CFE_ResourceId_GetBase(ParentResourceId)) {
      case CFE_ES_APPID_BASE:
        /*
         * Apps should not typically have symbols exposed to other apps.
         *
         * Keeping symbols local/private may help ensure this module is unloadable
         * in the future, depending on underlying OS/loader implementation.
         */
        LoadFlags |= OS_MODULE_FLAG_LOCAL_SYMBOLS;
        break;
      case CFE_ES_LIBID_BASE:
        /*
         * Libraries need to have their symbols exposed to other apps.
         *
         * Note on some OS/loader implementations this may make it so the module
         * cannot be unloaded, if there is no way to ensure that symbols
         * are not being referenced.  CFE does not currently support unloading
         * of libraries for this reason, among others.
         */
        LoadFlags |= OS_MODULE_FLAG_GLOBAL_SYMBOLS;
        break;
      default:
        break;
    }
    /*
     * Load the module via OSAL.
     */
    OsStatus = OS_ModuleLoad(&ModuleId, ModuleName, LoadParams->FileName, LoadFlags);
    if (OsStatus != OS_SUCCESS) {
      CFE_ES_WriteToSysLog("%s: Could not load file:%s. EC = %ld\n", "CFE_ES_LoadModule",
                           LoadParams->FileName, OsStatus);
      ModuleId = OS_OBJECT_ID_UNDEFINED;
      ReturnCode = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }
  } else {
    ModuleId = OS_OBJECT_ID_UNDEFINED;
  }
  /*
   * If the Load was OK, then lookup the address of the entry point
   */
  if (ReturnCode == CFE_SUCCESS && LoadParams->InitSymbolName[0] != 0 &&
      StrCmp(LoadParams->InitSymbolName, "NULL") != 0) {
    OsStatus = OS_ModuleSymbolLookup(ModuleId, &InitSymbolAddress, LoadParams->InitSymbolName);
    if (OsStatus != OS_SUCCESS) {
      CFE_ES_WriteToSysLog("%s: Could not find symbol:%s. EC = %ld\n", "CFE_ES_LoadModule",
                           LoadParams->InitSymbolName, OsStatus);
      ReturnCode = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }
  }
  if (ReturnCode == CFE_SUCCESS) {
    /* store the data in the app record after successful load+lookup */
    LoadStatus->ModuleId = ModuleId;
    LoadStatus->InitSymbolAddress = InitSymbolAddress;
  } else if (OS_ObjectIdDefined(ModuleId)) {
    /* If the module had been successfully loaded, then unload it,
     * so that it does not consume resources */
    OsStatus = OS_ModuleUnload(ModuleId);
    if (OsStatus != OS_SUCCESS) /* There's not much we can do except notify */
    {
      CFE_ES_WriteToSysLog("%s: Failed to unload: %s. EC = %ld\n", "CFE_ES_LoadModule",
                           ModuleName, OsStatus);
    }
  }
  return ReturnCode;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THIS RUNS IN THE NEW TASK AND WAITS FOR THE TASK THAT CREATED IT. OS_TaskCreate returns
// before CFE_ES_StartAppTask has filled in the task record, so the new task cannot simply read
// its own entry point -- it polls until the record it finds by context has both an app id and
// an entry function. NASA's comment on the timeout is the reason it is the startup script's
// own: "Use the same timeout as was used for the startup script itself."
//
// AND IT POLLS BEFORE IT CHECKS, which matters: the delay is the first statement of the loop,
// so even a record that is already complete costs one poll interval. That is deliberate --
// without it a task created and immediately scheduled would read a half-written record.
I32 CFE_ES_GetTaskFunction(U0 (**FuncPtr)())
{
  CFE_ES_TaskRecord_t *TaskRecPtr;
  U0 (*EntryFunc)();
  I32 ReturnCode;
  I32 Timeout;
  /*
   * Use the same timeout as was used for the startup script itself.
   */
  ReturnCode = CFE_ES_ERR_APP_REGISTER;
  Timeout = CFE_PLATFORM_ES_STARTUP_SCRIPT_TIMEOUT_MSEC;
  EntryFunc = NULL;
  while (TRUE) {
    OS_TaskDelay(CFE_PLATFORM_ES_STARTUP_SYNC_POLL_MSEC);
    CFE_ES_LockSharedData("CFE_ES_GetTaskFunction", 245);
    TaskRecPtr = CFE_ES_GetTaskRecordByContext();
    if (TaskRecPtr != NULL) {
      EntryFunc = TaskRecPtr->EntryFunc;
      if (CFE_ResourceId_IsDefined(TaskRecPtr->AppId) && EntryFunc != NULL) {
        ReturnCode = CFE_SUCCESS;
      }
    }
    CFE_ES_UnlockSharedData("CFE_ES_GetTaskFunction", 255);
    if (ReturnCode == CFE_SUCCESS || Timeout <= 0) {
      /* end of loop condition */
      break;
    }
    Timeout -= CFE_PLATFORM_ES_STARTUP_SYNC_POLL_MSEC;
  }
  /* output function address to caller */
  if (FuncPtr != NULL) {
    *FuncPtr = EntryFunc;
  }
  return ReturnCode;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// EVERY APP TASK IN THE SYSTEM STARTS HERE, and the app's own main is reached through a
// pointer. NASA's comment explains why the NULL check a reader expects is absent, and it is
// kept because it is an argument about COVERAGE and not about correctness: "When
// CFE_ES_GetTaskFunction returns CFE_SUCCESS, RealEntryFunc != NULL is implicit and therefore
// does not need to be checked here... The condition RealEntryFunc != NUL was therefore removed
// for coverage purposes."
U0 CFE_ES_TaskEntryPoint()
{
  U0 (*RealEntryFunc)();
  /* When CFE_ES_GetTaskFunction returns CFE_SUCCESS, RealEntryFunc != NULL
   * is implicit and therefore does not need to be checked here. This is
   * because in CFE_ES_GetTaskFunction, ReturnCode is set to CFE_SUCCESS only
   * if EntryFunc != 0, and *FuncPtr which is RealEntryFunc is set to
   * EntryFunc. Since FuncPtr != NULL is also implicitly true since FuncPtr =
   * &RealEntryFunc, FuncPtr != NULL will always evaluate to true. The
   * condition RealEntryFunc != NUL was therefore removed for coverage
   * purposes.*/
  if (CFE_ES_GetTaskFunction(&RealEntryFunc) == CFE_SUCCESS) {
    /*
     * Set the default exception environment, which should
     * be done serialized (i.e. only one task at a time should
     * call into CFE_PSP_SetDefaultExceptionEnvironment).
     */
    CFE_ES_LockSharedData("CFE_ES_TaskEntryPoint", 300);
    CFE_PSP_SetDefaultExceptionEnvironment();
    CFE_ES_UnlockSharedData("CFE_ES_TaskEntryPoint", 302);
    /*
     * Call the actual task entry function
     */
    (*RealEntryFunc)();
  }
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE TASK IS CREATED BEFORE ITS RECORD EXISTS, which is the race CFE_ES_GetTaskFunction above
// is built around: OS_TaskCreate may schedule the new task immediately, and the new task runs
// CFE_ES_TaskEntryPoint, which polls for the record this function is about to write. So the
// slot-in-use complaint below is a real diagnostic and not paranoia -- it means OSAL handed
// back a task id whose ES slot some earlier task never released.
I32 CFE_ES_StartAppTask(U32 *TaskIdPtr, U8 *TaskName, U0 (*EntryFunc)(),
                        CFE_ES_TaskStartParams_t *Params, U32 ParentAppId)
{
  CFE_ES_TaskRecord_t *TaskRecPtr;
  U32 OsalTaskId = OS_OBJECT_ID_UNDEFINED;
  U32 LocalTaskId;
  I32 OsStatus;
  I32 ReturnCode;
  /*
   * Create the primary task for the newly loaded task
   */
  OsStatus = OS_TaskCreate(&OsalTaskId,           /* task id */
                           TaskName,              /* task name matches app name for main task */
                           &CFE_ES_TaskEntryPoint, /* task function pointer */
                           Params->StackPtr,      /* stack pointer (allocate if NULL) */
                           Params->StackSize,     /* stack size */
                           Params->Priority,      /* task priority */
                           OS_FP_ENABLED);        /* task options */
  CFE_ES_LockSharedData("CFE_ES_StartAppTask", 340);
  if (OsStatus == OS_SUCCESS) {
    /*
     * As this is a newly-created task, this shouldn't fail.
     * The entry is not (yet) matching the task ID - it will be
     * initialized here.
     */
    LocalTaskId = CFE_ES_TaskId_FromOSAL(OsalTaskId);
    TaskRecPtr = CFE_ES_LocateTaskRecordByID(LocalTaskId);
    if (CFE_ES_TaskRecordIsUsed(TaskRecPtr)) {
      CFE_ES_SysLogWrite_Unsync("%s: Error: ES_TaskTable slot for ID %lx in use at task creation!\n",
                                "CFE_ES_StartAppTask", OsalTaskId);
    }
    /*
     * Clear any other/stale data that might be in the entry,
     * and reset all fields to the correct value.
     */
    MemSet(TaskRecPtr, 0, sizeof(CFE_ES_TaskRecord_t));
    TaskRecPtr->AppId = ParentAppId;
    TaskRecPtr->EntryFunc = EntryFunc;
    // `TaskRecPtr->StartParams = *Params;` -- a struct copy whose DESTINATION is a member
    // selector, which docs/HOLYC_STRUCT_LIMITS.md #21 measures as a WHOLE copy even with a
    // dereference on the source side. tests/exec/cases/e_struct_copy_into_slot.hc pins both
    // halves of that: `ptr->member = *p` is whole, `arr[i] = *p` is the first eight bytes. So
    // this one is NASA's line unchanged, and tools/cfs/check_struct_copy.py knows the
    // difference.
    TaskRecPtr->StartParams = *Params;
    StrNCpy(TaskRecPtr->TaskName, TaskName, OS_MAX_API_NAME - 1);
    TaskRecPtr->TaskName[OS_MAX_API_NAME - 1] = 0;
    CFE_ES_TaskRecordSetUsed(TaskRecPtr, LocalTaskId);
    /*
     * Increment the registered Task count.
     */
    CFE_ES_Global.RegisteredTasks++;
    ReturnCode = CFE_SUCCESS;
    *TaskIdPtr = CFE_ES_TaskRecordGetID(TaskRecPtr);
  } else {
    CFE_ES_SysLogWrite_Unsync("%s: AppCreate Error: TaskCreate %s Failed. EC = %ld!\n",
                              "CFE_ES_StartAppTask", TaskName, OsStatus);
    ReturnCode = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    *TaskIdPtr = CFE_ES_TASKID_UNDEFINED;
  }
  CFE_ES_UnlockSharedData("CFE_ES_StartAppTask", 390);
  return ReturnCode;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE RESERVED-SLOT PROTOCOL, in one function. The slot is claimed under the lock with the id
// CFE_RESOURCEID_RESERVED -- not free, but failing every validation test -- and the lock is
// then DROPPED for the slow part, loading the module and creating the task. NASA's reasoning,
// which is the reason the function is shaped the way it is: "In this state, the entry is no
// longer free, but also will not pass the validation test. So this function effectively has
// exclusive access without holding the global lock. IMPORTANT: it must set the ID to something
// else before leaving this function or else the resource will be leaked. After this point,
// execution must proceed to the end of the function to guarantee that the entry is either
// completed or freed."
//
// There is exactly one early return after the lock is taken, and it is on the path where the
// slot was never claimed.
//
// AND THE NAME HAS TO FIT BEFORE ANYTHING ELSE HAPPENS, checked with MemChr rather than a
// length: StrLen on a caller's buffer with no terminator is what runs off the end, which is
// why NASA uses memchr here. See Kernel/Cfs/CfsStr.HC.
I32 CFE_ES_AppCreate(U32 *ApplicationIdPtr, U8 *AppName, CFE_ES_AppStartParams_t *Params)
{
  I32 Status;
  I32 CleanupStatus;
  CFE_ES_AppRecord_t *AppRecPtr;
  U32 PendingResourceId = CFE_RESOURCEID_UNDEFINED;
  /*
   * The AppName must not be NULL
   */
  if (AppName == NULL || Params == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  /* Confirm name will fit inside the record */
  if (MemChr(AppName, 0, OS_MAX_API_NAME) == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  /*
  ** Allocate an ES_AppTable entry
  */
  CFE_ES_LockSharedData("CFE_ES_AppCreate", 425);
  /*
  ** Find an ES AppTable entry, and set to RESERVED
  **
  ** In this state, the entry is no longer free, but also will not pass the
  ** validation test.  So this function effectively has exclusive access
  ** without holding the global lock.
  **
  ** IMPORTANT: it must set the ID to something else before leaving
  ** this function or else the resource will be leaked.  After this
  ** point, execution must proceed to the end of the function to
  ** guarantee that the entry is either completed or freed.
  */
  /*
   * Check for an existing entry with the same name.
   * Also check for a matching Library name.
   * (Apps and libraries should be uniquely named)
   */
  AppRecPtr = CFE_ES_LocateAppRecordByName(AppName);
  if (AppRecPtr != NULL) {
    CFE_ES_SysLogWrite_Unsync("%s: Duplicate app name '%s'\n", "CFE_ES_AppCreate", AppName);
    Status = CFE_ES_ERR_DUPLICATE_NAME;
  } else {
    /* scan for a free slot */
    PendingResourceId = CFE_ResourceId_FindNext(CFE_ES_Global.LastAppId,
                                                CFE_PLATFORM_ES_MAX_APPLICATIONS,
                                                &CFE_ES_CheckAppIdSlotUsed);
    AppRecPtr = CFE_ES_LocateAppRecordByID(PendingResourceId);
    if (AppRecPtr == NULL) {
      CFE_ES_SysLogWrite_Unsync("%s: No free application slots available\n", "CFE_ES_AppCreate");
      Status = CFE_ES_NO_RESOURCE_IDS_AVAILABLE;
    } else {
      /* Fully clear the entry, just in case of stale data */
      MemSet(AppRecPtr, 0, sizeof(CFE_ES_AppRecord_t));
      /* Store the app name from passed-in value */
      StrNCpy(AppRecPtr->AppName, AppName, OS_MAX_API_NAME - 1);
      AppRecPtr->Type = CFE_ES_AppType_EXTERNAL;
      /*
       * Fill out the parameters in the StartParams sub-structure
       *
       * This contains all relevant info, including file name, entry point,
       * main task info, etc. which is required to start the app now
       * or in a future restart/reload request.
       */
      // A member-selector destination, so this 344-byte copy is whole -- the same shape and
      // the same measurement as CFE_ES_StartAppTask's above.
      AppRecPtr->StartParams = *Params;
      /*
       * Fill out the Task State info
       */
      AppRecPtr->ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
      AppRecPtr->ControlReq.AppTimerMsec = 0;
      CFE_ES_AppRecordSetUsed(AppRecPtr, CFE_RESOURCEID_RESERVED);
      CFE_ES_Global.LastAppId = PendingResourceId;
      Status = CFE_SUCCESS;
    }
  }
  CFE_ES_UnlockSharedData("CFE_ES_AppCreate", 495);
  /*
   * If ID allocation was not successful, return now.
   * A message regarding the issue should have already been logged
   */
  if (Status != CFE_SUCCESS) {
    return Status;
  }
  /*
   * Load the module based on StartParams configured above.
   */
  Status = CFE_ES_LoadModule(PendingResourceId, AppName, &AppRecPtr->StartParams.BasicInfo,
                             &AppRecPtr->LoadStatus);
  /*
   * If the Load was OK, then complete the initialization
   */
  if (Status == CFE_SUCCESS) {
    Status = CFE_ES_StartAppTask(&AppRecPtr->MainTaskId, /* Task ID (output) stored in App Record as main task */
                                 AppName,                /* Main Task name matches app name */
                                 AppRecPtr->LoadStatus.InitSymbolAddress, /* Init Symbol is main task entry point */
                                 &AppRecPtr->StartParams.MainTaskInfo,    /* Main task parameters */
                                 PendingResourceId);                      /* Parent App ID */
  }
  /*
   * Finalize data in the app table entry, which must be done under lock.
   * This transitions the entry from being RESERVED to the real ID.
   */
  CFE_ES_LockSharedData("CFE_ES_AppCreate", 529);
  if (Status == CFE_SUCCESS) {
    /*
     * important - set the ID to its proper value
     * which turns this into a real/valid table entry
     */
    CFE_ES_AppRecordSetUsed(AppRecPtr, PendingResourceId);
    /*
     ** Increment the registered App counter.
     */
    CFE_ES_Global.RegisteredExternalApps++;
  } else {
    /*
     * Set the table entry back to free
     */
    if (OS_ObjectIdDefined(AppRecPtr->LoadStatus.ModuleId)) {
      CleanupStatus = OS_ModuleUnload(AppRecPtr->LoadStatus.ModuleId);
      if (CleanupStatus != OS_SUCCESS) {
        CFE_ES_WriteToSysLog("%s: Module (ID:0x%08lX) Unload failed. RC=%ld\n",
                             "CFE_ES_AppCreate", AppRecPtr->LoadStatus.ModuleId, CleanupStatus);
      }
    }
    CFE_ES_AppRecordSetFree(AppRecPtr);
    PendingResourceId = CFE_RESOURCEID_UNDEFINED;
  }
  CFE_ES_UnlockSharedData("CFE_ES_AppCreate", 565);
  *ApplicationIdPtr = PendingResourceId;
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE SAME PROTOCOL, AND THREE REAL DIFFERENCES FROM AN APP. A library has no task: its entry
// symbol is called ONCE, inline, by whoever is loading it, and it is handed its own library id
// so it can register things under it. Its symbols are loaded GLOBAL, which is what makes it a
// library and also why cFE never unloads one. And a duplicate name here reports the EXISTING
// library's id rather than UNDEFINED -- the only path in either function where a failure
// returns a usable id, which a caller that wanted "load it if it isn't loaded" can use.
//
// The name is also checked against the APP table, because NASA requires one namespace: "Apps
// and libraries should be uniquely named".
I32 CFE_ES_LoadLibrary(U32 *LibraryIdPtr, U8 *LibName, CFE_ES_ModuleLoadParams_t *Params)
{
  I32 (*FunctionPointer)();
  CFE_ES_LibRecord_t *LibSlotPtr;
  I32 Status;
  U32 PendingResourceId;
  /*
   * The LibName must not be NULL
   */
  if (LibName == NULL || Params == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  /* Confirm name will fit inside the record */
  if (MemChr(LibName, 0, OS_MAX_API_NAME) == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  /*
  ** Allocate an ES_LibTable entry
  */
  PendingResourceId = CFE_RESOURCEID_UNDEFINED;
  /*
  ** Find an ES AppTable entry, and set to RESERVED
  **
  ** In this state, the entry is no longer free, but also will not pass the
  ** validation test.  So this function effectively has exclusive access
  ** without holding the global lock.
  **
  ** IMPORTANT: it must set the ID to something else before leaving
  ** this function or else the resource will be leaked.  After this
  ** point, execution must proceed to the end of the function to
  ** guarantee that the entry is either completed or freed.
  */
  CFE_ES_LockSharedData("CFE_ES_LoadLibrary", 616);
  /*
   * Check for an existing entry with the same name.
   * Also check for a matching Library name.
   * (Libs and libraries should be uniquely named)
   */
  LibSlotPtr = CFE_ES_LocateLibRecordByName(LibName);
  if (LibSlotPtr != NULL || CFE_ES_LocateAppRecordByName(LibName) != NULL) {
    CFE_ES_SysLogWrite_Unsync("%s: Duplicate Lib name '%s'\n", "CFE_ES_LoadLibrary", LibName);
    if (LibSlotPtr != NULL) {
      PendingResourceId = CFE_ES_LibRecordGetID(LibSlotPtr);
    }
    Status = CFE_ES_ERR_DUPLICATE_NAME;
  } else {
    /* scan for a free slot */
    PendingResourceId = CFE_ResourceId_FindNext(CFE_ES_Global.LastLibId,
                                                CFE_PLATFORM_ES_MAX_LIBRARIES,
                                                &CFE_ES_CheckLibIdSlotUsed);
    LibSlotPtr = CFE_ES_LocateLibRecordByID(PendingResourceId);
    if (LibSlotPtr == NULL) {
      CFE_ES_SysLogWrite_Unsync("%s: No free library slots available\n", "CFE_ES_LoadLibrary");
      Status = CFE_ES_NO_RESOURCE_IDS_AVAILABLE;
    } else {
      /* Fully clear the entry, just in case of stale data */
      MemSet(LibSlotPtr, 0, sizeof(CFE_ES_LibRecord_t));
      /*
       * Fill out the parameters in the AppStartParams sub-structure
       */
      StrNCpy(LibSlotPtr->LibName, LibName, OS_MAX_API_NAME - 1);
      LibSlotPtr->LibName[OS_MAX_API_NAME - 1] = '\0';
      LibSlotPtr->LoadParams = *Params;
      CFE_ES_LibRecordSetUsed(LibSlotPtr, CFE_RESOURCEID_RESERVED);
      CFE_ES_Global.LastLibId = PendingResourceId;
      Status = CFE_SUCCESS;
    }
  }
  CFE_ES_UnlockSharedData("CFE_ES_LoadLibrary", 663);
  /*
   * If any off-nominal condition exists, skip the rest of this logic.
   * (Log message already written)
   */
  if (Status != CFE_SUCCESS) {
    *LibraryIdPtr = PendingResourceId;
    return Status;
  }
  /*
   * Load the module based on StartParams configured above.
   */
  Status = CFE_ES_LoadModule(PendingResourceId, LibName, &LibSlotPtr->LoadParams,
                             &LibSlotPtr->LoadStatus);
  if (Status == CFE_SUCCESS) {
    FunctionPointer = LibSlotPtr->LoadStatus.InitSymbolAddress;
    if (FunctionPointer != NULL) {
      Status = (*FunctionPointer)(PendingResourceId);
      if (Status != CFE_SUCCESS) {
        CFE_ES_WriteToSysLog("%s: Load Shared Library Init Error = 0x%08x\n",
                             "CFE_ES_LoadLibrary", Status);
      }
    }
  }
  /*
   * Finalize data in the app table entry, which must be done under lock.
   * This transitions the entry from being RESERVED to the real type,
   * either MAIN_TASK (success) or returning to INVALID (failure).
   */
  CFE_ES_LockSharedData("CFE_ES_LoadLibrary", 697);
  if (Status == CFE_SUCCESS) {
    /*
     * important - set the ID to its proper value
     * which turns this into a real/valid table entry
     */
    CFE_ES_LibRecordSetUsed(LibSlotPtr, PendingResourceId);
    /*
     * Increment the registered Lib counter.
     */
    CFE_ES_Global.RegisteredLibs++;
  } else {
    CFE_ES_LibRecordSetFree(LibSlotPtr);
    PendingResourceId = CFE_RESOURCEID_UNDEFINED;
  }
  CFE_ES_UnlockSharedData("CFE_ES_LoadLibrary", 718);
  *LibraryIdPtr = PendingResourceId;
  return Status;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Collects the set of resources that are associated with the app being cleaned up
 * This only marks them for removal, it does not fully remove yet.
 *
 *-----------------------------------------------------------------*/
// MARK, DO NOT DELETE. Everything this function touches is inside the shared-data lock, so it
// may only write to the global records -- it cannot call into OSAL or another cFE module,
// because that would mean holding two locks. So each task and pool it finds is set to
// CFE_RESOURCEID_RESERVED, which keeps the slot from being handed out again while the real
// deletion happens with the lock released.
//
// THE MAIN TASK IS MOVED TO INDEX 0, by swapping it with whatever was there. That ordering is
// what lets CFE_ES_CleanUpApp_FreeTasks walk the list BACKWARDS and so delete every child task
// before the task that owns them.
I32 CFE_ES_CleanUpApp_GetResources(U32 AppId, U32 *ModuleIdPtr, U32 *TaskList, U32 *PoolList)
{
  I32 ReturnCode;
  CFE_ES_AppRecord_t *AppRecPtr;
  CFE_ES_TaskRecord_t *TaskRecPtr;
  CFE_ES_MemPoolRecord_t *MemPoolRecPtr;
  I64 i;
  I64 NumTasks;
  I64 NumPools;
  NumTasks = 0;
  NumPools = 0;
  ReturnCode = CFE_SUCCESS;
  AppRecPtr = CFE_ES_LocateAppRecordByID(AppId);
  /*
   * Collect a list of resources previously owned by this app, which
   * must be done while the global data is locked.
   */
  CFE_ES_LockSharedData("CFE_ES_CleanUpApp_GetResources", 755);
  if (CFE_ES_AppRecordIsMatch(AppRecPtr, AppId)) {
    if (AppRecPtr->Type == CFE_ES_AppType_EXTERNAL) {
      CFE_ES_Global.RegisteredExternalApps--;
      /*
       * Get the Module ID, if it was an external app
       *
       * (this will be OS_OBJECT_ID_UNDEFINED if it was not loaded dynamically)
       */
      *ModuleIdPtr = AppRecPtr->LoadStatus.ModuleId;
    }
    /*
     * Collect all tasks associated with this app
     */
    TaskRecPtr = CFE_ES_Global.TaskTable;
    for (i = 0; i < OS_MAX_TASKS; i++) {
      if (CFE_ES_TaskRecordIsUsed(TaskRecPtr) && TaskRecPtr->AppId == AppId) {
        TaskList[NumTasks] = CFE_ES_TaskRecordGetID(TaskRecPtr);
        /* Store the main task ID at index 0 (swap with whatever was there) */
        if (TaskList[NumTasks] == AppRecPtr->MainTaskId && NumTasks != 0) {
          TaskList[NumTasks] = TaskList[0];
          TaskList[0] = AppRecPtr->MainTaskId;
        }
        /* Mark record for removal */
        CFE_ES_TaskRecordSetUsed(TaskRecPtr, CFE_RESOURCEID_RESERVED);
        ++NumTasks;
      }
      ++TaskRecPtr;
    }
    CFE_ES_Global.RegisteredTasks -= NumTasks;
    /*
     * Collect memory pools associated with this app
     */
    MemPoolRecPtr = CFE_ES_Global.MemPoolTable;
    for (i = 0; i < CFE_PLATFORM_ES_MAX_MEMORY_POOLS; i++) {
      if (CFE_ES_MemPoolRecordIsUsed(MemPoolRecPtr) && MemPoolRecPtr->OwnerAppID == AppId) {
        PoolList[NumPools] = CFE_ES_MemPoolRecordGetID(MemPoolRecPtr);
        ++NumPools;
      }
      ++MemPoolRecPtr;
    }
    /*
     * Set the record to RESERVED.
     *
     * This prevents reallocation of this slot while the remainder
     * of resources are freed.
     */
    CFE_ES_AppRecordSetUsed(AppRecPtr, CFE_RESOURCEID_RESERVED);
  } else {
    CFE_ES_SysLogWrite_Unsync("%s: AppID %lu is not valid for deletion\n",
                              "CFE_ES_CleanUpApp_GetResources", AppId);
    ReturnCode = CFE_ES_APP_CLEANUP_ERR;
  }
  CFE_ES_UnlockSharedData("CFE_ES_CleanUpApp_GetResources", 830);
  /* clear out any remaining entries in the lists */
  for (i = NumTasks; i < OS_MAX_TASKS; ++i) {
    TaskList[i] = CFE_ES_TASKID_UNDEFINED;
  }
  for (i = NumPools; i < CFE_PLATFORM_ES_MAX_MEMORY_POOLS; ++i) {
    PoolList[i] = CFE_ES_MEMHANDLE_UNDEFINED;
  }
  return ReturnCode;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Frees resources associated with this app in _other_ core modules
 * This is done by invoking the notification callback for that module
 *
 * Returns the number of callbacks that returned non-success.  Should be 0.
 *
 *-----------------------------------------------------------------*/
// EVERY CORE MODULE GETS TOLD, through the same object table ES's own entry lives in: each
// module may register an AppCleanupCb, and this walks the NULL-terminated table calling them.
// That is how EVS forgets the app's filters, SB unsubscribes its pipes and TBL releases its
// tables -- none of which ES knows anything about.
//
// AND IT COUNTS FAILURES RATHER THAN STOPPING, which NASA argues for: "Cleaning up resource is
// 'best effort' -- the app is gone, so we reclaim everything assocated with that app if
// possible. If failures occur, that should not stop the rest of cleanup."
U32 CFE_ES_CleanUpApp_FreeCoreResources(U32 AppId)
{
  /*
   * Now actually delete all the resources associated with the task.
   *
   * Most of this involves calling into other subsystems, so it is
   * done while the ES global data is UNLOCKED to avoid holding more
   * than one lock at a time.
   */
  I32 Status;
  U32 i;
  U32 FailCount;
  Target_ObjectTable *Entry;
  /* Cleaning up resource is "best effort" -- the app is gone, so
   * we reclaim everything assocated with that app if possible.  If
   * failures occur, that should not stop the rest of cleanup. */
  FailCount = 0;
  i = 0;
  while (TRUE) {
    Entry = GLOBAL_CONFIGDATA.CoreObjectTable[i];
    if (Entry == NULL) {
      /* this list is always terminated with a NULL entry */
      break;
    }
    if (Entry->AppCleanupCb != NULL) {
      /* Notify the core module that the app is going away.  This is so those
       * modules can also reclaim any resources associated with this app */
      Status = Entry->AppCleanupCb(AppId);
      if (Status != CFE_SUCCESS) {
        CFE_ES_WriteToSysLog("%s: Error returned from app Cleanup for %s: EC = 0x%08X\n",
                             "CFE_ES_CleanUpApp_FreeCoreResources", Entry->Name, Status);
        ++FailCount;
      }
    }
    ++i;
  }
  return FailCount;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Frees task resources associated with this app, for every task
 * that was identified for removal
 *
 * Returns the number of task cleanups that returned non-success.  Should be 0.
 *
 *-----------------------------------------------------------------*/
// BACKWARDS, AND THAT IS THE WHOLE POINT. GetResources put the main task at index 0, so walking
// the list from the end deletes every child task first and the task that owns them last. NASA
// states it: "This iterates the list in reverse order, such that the child tasks are deleted
// first (in any order) and main task is deleted last."
U32 CFE_ES_CleanUpApp_FreeTasks(U32 AppId, U32 *TaskList)
{
  I64 i;
  U32 FailCount;
  I32 Status;
  /*
   * Delete all tasks.
   *
   * Note that the main task is always positioned at index 0 in this list.
   *
   * This iterates the list in reverse order, such that the child
   * tasks are deleted first (in any order) and main task is deleted last.
   */
  FailCount = 0;
  i = OS_MAX_TASKS;
  while (i > 0) {
    --i;
    if (CFE_ResourceId_IsDefined(TaskList[i])) {
      Status = CFE_ES_CleanupTaskResources(TaskList[i]);
    } else {
      Status = CFE_SUCCESS;
    }
    if (Status != CFE_SUCCESS) {
      CFE_ES_WriteToSysLog("%s: CleanUpTaskResources for Task ID:%lu returned Error: 0x%08X\n",
                           "CFE_ES_CleanUpApp_FreeTasks", TaskList[i], Status);
      ++FailCount;
    }
  }
  return FailCount;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Frees memory pool resources associated with this app, for every mempool
 * that was identified for removal
 *
 * Returns the number of cleanups that returned non-success.  Should be 0.
 *
 *-----------------------------------------------------------------*/
U32 CFE_ES_CleanUpApp_FreePools(U32 AppId, U32 *PoolList)
{
  I64 i;
  U32 FailCount;
  I32 Status;
  /*
   * Delete all mem pools.
   */
  FailCount = 0;
  for (i = 0; i < CFE_PLATFORM_ES_MAX_MEMORY_POOLS; ++i) {
    if (CFE_ResourceId_IsDefined(PoolList[i])) {
      Status = CFE_ES_PoolDelete(PoolList[i]);
    } else {
      Status = CFE_SUCCESS;
    }
    if (Status != CFE_SUCCESS) {
      CFE_ES_WriteToSysLog("%s: delete pool %lu returned Error: 0x%08X\n",
                           "CFE_ES_CleanUpApp_FreePools", PoolList[i], Status);
      ++FailCount;
    }
  }
  return FailCount;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * All task/app resources that were previously marked for removal are
 * fully removed here.  This cannot fail.
 *
 *-----------------------------------------------------------------*/
// IT ONLY FREES WHAT IT MARKED, and the check is for the RESERVED id specifically rather than
// for the real one: GetResources set every task it collected and the app record itself to
// CFE_RESOURCEID_RESERVED, so matching against RESERVED is how this knows the slot is still the
// one it is entitled to release. A slot something else has since claimed does not match and is
// left alone.
U0 CFE_ES_CleanUpApp_Finish(U32 AppId, U32 *TaskList)
{
  CFE_ES_AppRecord_t *AppRecPtr;
  CFE_ES_TaskRecord_t *TaskRecPtr;
  I64 i;
  /*
   * Finally, re-acquire the ES lock and set all
   * table entries free for re-use.
   */
  CFE_ES_LockSharedData("CFE_ES_CleanUpApp_Finish", 1014);
  /*
   * Free all task records.
   */
  for (i = 0; i < OS_MAX_TASKS; ++i) {
    /* note - if this returns NULL then CFE_ES_TaskRecordIsMatch will be false */
    TaskRecPtr = CFE_ES_LocateTaskRecordByID(TaskList[i]);
    if (CFE_ES_TaskRecordIsMatch(TaskRecPtr, CFE_RESOURCEID_RESERVED)) {
      CFE_ES_TaskRecordSetFree(TaskRecPtr);
    }
  }
  /*
   * Now finally delete the record and allow re-use of the slot.
   */
  AppRecPtr = CFE_ES_LocateAppRecordByID(AppId);
  if (CFE_ES_AppRecordIsMatch(AppRecPtr, CFE_RESOURCEID_RESERVED)) {
    CFE_ES_AppRecordSetFree(AppRecPtr);
  }
  CFE_ES_UnlockSharedData("CFE_ES_CleanUpApp_Finish", 1038);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE FIVE PARTS IN ORDER, and the order is the argument: collect under the lock, then free the
// other modules' resources, the tasks and the pools with the lock RELEASED, then unload the
// module, then re-take the lock and release the slots.
//
// AND THE RETURN VALUE IS INFORMATION, NOT A VERDICT. NASA is explicit: "The FailCount is the
// number of resources that were _not_ successfully reclaimed. It should normally be 0. This
// return value is for informational purposes only, the caller should not really do anything
// differently - the app is gone as much as it can be, even if this is nonzero." Which is why
// cfe_es_appctrl.c starts the app again regardless of what this returns.
I32 CFE_ES_CleanUpApp(U32 AppId)
{
  I32 ReturnCode;
  U32 TaskList[OS_MAX_TASKS];
  U32 PoolList[CFE_PLATFORM_ES_MAX_MEMORY_POOLS];
  U32 ModuleId;
  I32 OsStatus;
  U32 FailCount;
  ModuleId = OS_OBJECT_ID_UNDEFINED;
  FailCount = 0;
  MemSet(TaskList, 0, sizeof(TaskList));
  MemSet(PoolList, 0, sizeof(PoolList));
  /*
   * Collect a list of resources previously owned by this app, which
   * must be done while the global data is locked.
   */
  ReturnCode = CFE_ES_CleanUpApp_GetResources(AppId, &ModuleId, TaskList, PoolList);
  /* if that failed, do not do anything else */
  if (ReturnCode == CFE_SUCCESS) {
    /*
     * Now actually delete all the resources associated with the task.
     *
     * Most of this involves calling into other subsystems, so it is
     * done while the ES global data is UNLOCKED to avoid holding more
     * than one lock at a time.
     */
    FailCount += CFE_ES_CleanUpApp_FreeCoreResources(AppId);
    FailCount += CFE_ES_CleanUpApp_FreeTasks(AppId, TaskList);
    FailCount += CFE_ES_CleanUpApp_FreePools(AppId, PoolList);
    /*
    ** Unload the module, if applicable
    */
    if (OS_ObjectIdDefined(ModuleId)) {
      /*
      ** Unload the module only if it is an external app
      */
      OsStatus = OS_ModuleUnload(ModuleId);
      if (OsStatus != OS_SUCCESS) {
        CFE_ES_WriteToSysLog("%s: Module (ID:0x%08lX) Unload failed. RC=%ld\n",
                             "CFE_ES_CleanUpApp", ModuleId, OsStatus);
        ++FailCount;
      }
    }
    /*
     * Finally, re-acquire the ES lock and set all
     * table entries free for re-use.
     */
    CFE_ES_CleanUpApp_Finish(AppId, TaskList);
    /*
     * The FailCount is the number of resources that were _not_ successfully reclaimed.
     * It should normally be 0.  This return value is for informational purposes only,
     * the caller should not really do anything differently - the app is gone as much
     * as it can be, even if this is nonzero.
     */
    if (FailCount != 0) {
      ReturnCode = CFE_ES_APP_CLEANUP_ERR;
    }
  }
  return ReturnCode;
}

/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Purpose: clean up all objects.
 * NOTE: This is called while holding the ES global lock
 *
 *-----------------------------------------------------------------*/
// IT ASKS OSAL WHAT THE OBJECT IS AND THEN DELETES IT ACCORDINGLY, which is the only way a
// task's resources can be reclaimed after the task is gone: nothing recorded what it created.
// OS_ForEachObject hands every object whose creator is this task to this callback, and
// OS_IdentifyObject says which of the eight kinds it is.
//
// AN UNKNOWN TYPE IS NOT COUNTED AT ALL, which is what ObjIsValid is for -- the default arm
// leaves it false, so a type OSAL grows later neither counts as found nor as a failure, and the
// caller's downward-trend loop is not confused by it.
//
// A STREAM AND A MODULE HAVE NO ErrorStatus OF THEIR OWN, so a failure to close a file or
// unload a module reports the default CFE_ES_APP_CLEANUP_ERR. That is NASA's, and the comment
// at the declaration says so: "Set default cFE error status".
U0 CFE_ES_CleanupObjectCallback(U32 ObjectId, U8 *arg)
{
  CFE_ES_CleanupState_t *CleanState;
  I32 OsStatus;
  U32 ObjType;
  Bool ObjIsValid;
  I32 ErrorStatus = CFE_ES_APP_CLEANUP_ERR; // Set default cFE error status
  CleanState = arg;
  ObjIsValid = TRUE;
  ObjType = OS_IdentifyObject(ObjectId);
  switch (ObjType) {
    case OS_OBJECT_TYPE_OS_TASK:
      OsStatus = OS_TaskDelete(ObjectId);
      ErrorStatus = CFE_ES_ERR_CHILD_TASK_DELETE;
      break;
    case OS_OBJECT_TYPE_OS_QUEUE:
      OsStatus = OS_QueueDelete(ObjectId);
      ErrorStatus = CFE_ES_QUEUE_DELETE_ERR;
      break;
    case OS_OBJECT_TYPE_OS_BINSEM:
      OsStatus = OS_BinSemDelete(ObjectId);
      ErrorStatus = CFE_ES_BIN_SEM_DELETE_ERR;
      break;
    case OS_OBJECT_TYPE_OS_COUNTSEM:
      OsStatus = OS_CountSemDelete(ObjectId);
      ErrorStatus = CFE_ES_COUNT_SEM_DELETE_ERR;
      break;
    case OS_OBJECT_TYPE_OS_MUTEX:
      OsStatus = OS_MutSemDelete(ObjectId);
      ErrorStatus = CFE_ES_MUT_SEM_DELETE_ERR;
      break;
    case OS_OBJECT_TYPE_OS_TIMECB:
      OsStatus = OS_TimerDelete(ObjectId);
      ErrorStatus = CFE_ES_TIMER_DELETE_ERR;
      break;
    case OS_OBJECT_TYPE_OS_STREAM:
      OsStatus = OS_close(ObjectId);
      break;
    case OS_OBJECT_TYPE_OS_MODULE:
      OsStatus = OS_ModuleUnload(ObjectId);
      break;
    default:
      ObjIsValid = FALSE;
      OsStatus = OS_ERROR;
      break;
  }
  if (ObjIsValid) {
    ++CleanState->FoundObjects;
    if (OsStatus == OS_SUCCESS) {
      ++CleanState->DeletedObjects;
    } else {
      CFE_ES_SysLogWrite_Unsync("%s: Call to OSAL Delete Object (ID:%lu) failed. RC=%ld\n",
                                "CFE_ES_CleanupObjectCallback", ObjectId, OsStatus);
      if (CleanState->OverallStatus == CFE_SUCCESS) {
        // Save the object-type-specific error status that was set earlier in the switch statement
        CleanState->OverallStatus = ErrorStatus;
      }
    }
  }
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// IT SWEEPS REPEATEDLY, because deleting one object can release another -- a timer whose
// callback held a semaphore. So the walk runs again until nothing is found.
//
// AND IT REFUSES TO LOOP FOREVER ON A TREND THAT IS NOT DOWNWARD, which is the interesting
// part. NASA: "The number of found objects should show a downward trend, if not, then stop and
// do not loop here forever. (This can happen when using the UT stub functions, or if an object
// cannot be fully deleted successfully)." PrevFoundObjects starts at -1 -- a DECREMENT of a
// zeroed field, so the largest U32 -- which is what makes the first pass always pass the trend
// test however many objects it finds.
//
// A SELF-EXITED TASK IS NOT AN ERROR. OS_TaskDelete then returns OS_ERR_INVALID_ID, and NASA
// accepts it: "if the task self exited, then the ID becomes invalid... but that is OK, there is
// nothing else needed to do."
I32 CFE_ES_CleanupTaskResources(U32 TaskId)
{
  CFE_ES_CleanupState_t CleanState;
  I32 OsStatus;
  I32 Result;
  U32 OsalId;
  /* Get the Task ID for calling OSAL APIs (convert type) */
  OsalId = CFE_ES_TaskId_ToOSAL(TaskId);
  /*
  ** Delete all OSAL resources that belong to this task
  */
  MemSet(&CleanState, 0, sizeof(CFE_ES_CleanupState_t));
  --CleanState.PrevFoundObjects;
  while (1) {
    OS_ForEachObject(OsalId, &CFE_ES_CleanupObjectCallback, &CleanState);
    if (CleanState.FoundObjects == 0 || CleanState.ErrorFlag != 0) {
      break;
    }
    /*
     * The number of found objects should show a downward trend,
     * if not, then stop and do not loop here forever.  (This can
     * happen when using the UT stub functions, or if an object
     * cannot be fully deleted successfully).
     */
    CleanState.ErrorFlag = (CleanState.DeletedObjects == 0 ||
                            CleanState.FoundObjects >= CleanState.PrevFoundObjects);
    CleanState.PrevFoundObjects = CleanState.FoundObjects;
    CleanState.FoundObjects = 0;
    CleanState.DeletedObjects = 0;
  }
  /*
  ** Delete the task itself
  **
  ** Note, if the task self exited, then the ID becomes invalid.
  ** In this case the OS_ERR_INVALID_ID status is returned, but
  ** that is OK, there is nothing else needed to do.
  */
  OsStatus = OS_TaskDelete(OsalId);
  if (OsStatus == OS_SUCCESS || OsStatus == OS_ERR_INVALID_ID) {
    Result = CleanState.OverallStatus;
    if (Result == CFE_SUCCESS && CleanState.FoundObjects > 0) {
      /* Objects leftover after cleanup -- resource leak */
      Result = CFE_ES_APP_CLEANUP_ERR;
    }
  } else {
    Result = CFE_ES_TASK_DELETE_ERR;
  }
  return Result;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_ES_CopyModuleBasicInfo(CFE_ES_ModuleLoadParams_t *ParamsPtr, CFE_ES_AppInfo_t *AppInfoPtr)
{
  StrNCpy(AppInfoPtr->EntryPoint, ParamsPtr->InitSymbolName, CFE_MISSION_MAX_API_LEN - 1);
  AppInfoPtr->EntryPoint[CFE_MISSION_MAX_API_LEN - 1] = '\0';
  StrNCpy(AppInfoPtr->FileName, ParamsPtr->FileName, CFE_MISSION_MAX_PATH_LEN - 1);
  AppInfoPtr->FileName[CFE_MISSION_MAX_PATH_LEN - 1] = '\0';
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_ES_CopyModuleStatusInfo(CFE_ES_ModuleLoadStatus_t *StatusPtr, CFE_ES_AppInfo_t *AppInfoPtr)
{
  AppInfoPtr->StartAddress = StatusPtr->InitSymbolAddress;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE ADDRESSES ARE COPIED WHETHER THEY ARE VALID OR NOT, and only the FLAG is conditional --
// NASA writes the six fields unconditionally from a ModuleInfo that was zeroed first, so a
// failed OS_ModuleInfo yields six zeroes and AddressesAreValid false rather than stale values.
//
// AND THE VALIDITY TEST IS PARTLY A WIDTH CHECK: NASA ANDs the module's own `valid` flag with
// `sizeof(ModuleInfo.addr.code_address) <= sizeof(AppInfoPtr->CodeAddress)`, because "the
// telemetry format may be a different bitwidth than the native processor". On this target both
// are eight bytes, so the comparison is 8 <= 8 -- written out, because HolyC cannot take the
// sizeof of a member through a pointer (docs/HOLYC_STRUCT_LIMITS.md #16) and because a reader
// should see that it is a real test upstream and a tautology here.
U0 CFE_ES_CopyModuleAddressInfo(U32 ModuleId, CFE_ES_AppInfo_t *AppInfoPtr)
{
  OS_module_prop_t ModuleInfo;
  I32 OsStatus;
  MemSet(&ModuleInfo, 0, sizeof(OS_module_prop_t));
  OsStatus = OS_ModuleInfo(ModuleId, &ModuleInfo);
  if (OsStatus == OS_SUCCESS) {
    AppInfoPtr->AddressesAreValid = (8 <= 8) && ModuleInfo.addr.valid;
  } else {
    AppInfoPtr->AddressesAreValid = FALSE;
  }
  /*
   * Convert the internal size and address to the telemetry format.
   * (The telemetry format may be a different bitwidth than the native processor)
   */
  AppInfoPtr->CodeAddress = ModuleInfo.addr.code_address;
  AppInfoPtr->CodeSize = ModuleInfo.addr.code_size;
  AppInfoPtr->DataAddress = ModuleInfo.addr.data_address;
  AppInfoPtr->DataSize = ModuleInfo.addr.data_size;
  AppInfoPtr->BSSAddress = ModuleInfo.addr.bss_address;
  AppInfoPtr->BSSSize = ModuleInfo.addr.bss_size;
}
#endif
