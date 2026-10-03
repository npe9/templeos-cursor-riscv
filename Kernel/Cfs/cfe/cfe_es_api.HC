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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_api.c -- EXECUTIVE SERVICES' PUBLIC API.
//
// Forty-seven functions and the largest single file in the port. It is also the LAST one holding
// stubs that every other module's driver has been answering for since the EVS module landed:
// CFE_ES_GetAppID, CFE_ES_GetAppName, CFE_ES_GetTaskInfo, CFE_ES_WriteToSysLog and
// CFE_ES_LockSharedData. Those five appear in essentially every cFS error path.
//
// WHAT IS IN HERE, in groups, because forty-seven functions in one file needs a map:
//   reset and restart     GetResetType, ResetCFE -- and ResetCFE DOES NOT RETURN on success
//   app control           RestartApp, ReloadApp, DeleteApp, ExitApp, RunLoop
//   startup sync          WaitForSystemState, WaitForStartupSync
//   identity              Get{App,Lib,Task}IDByName, GetAppID, GetTaskID
//   names                 Get{App,Lib,Task}Name
//   info                  Get{App,Lib,Module,Task}Info
//   child tasks           CreateChildTask, DeleteChildTask, ExitChildTask, IncrementTaskCounter
//   logging               WriteToSysLog, CalculateCRC
//   the CDS               RegisterCDS, GetCDSBlock{IDByName,Name}, CopyToCDS, RestoreFromCDS
//   generic counters      Register, Delete, Increment, Set, Get, GetIDByName, GetName
//   index conversions     {App,Lib,Task,Counter}ID_ToIndex
//   the shared-data lock  LockSharedData, UnlockSharedData
//   odds and ends         ProcessAsyncEvent, StatusToString
//
// THE LOCK PAIR AT THE BOTTOM IS THE ONE WORTH READING FIRST, and NASA's comment on it is a
// confession: when OS_MutSemTake fails it writes the failure into the syslog, and "this is going
// to write into a buffer that itself is _supposed_ to be protected by this same mutex". There is
// nowhere else to put the message. The translation keeps that comment because it is the design.
#ifndef CFE_ES_API_HC
#define CFE_ES_API_HC
#include "cfe_es_resource.HC" // the four record tables and their accessors
#include "../CfsStr.HC"      // StrNCpy and StrPrintN (the guard makes it idempotent)
// --- cfe_error.h ------------------------------------------------------------------------------
#define CFE_ES_NOT_IMPLEMENTED                 0xC400FFFF(I32)
#define CFE_ES_ERR_NAME_NOT_FOUND              0xC4000002(I32)
#define CFE_ES_ERR_APP_CREATE                  0xC4000004(I32)
#define CFE_ES_ERR_CHILD_TASK_CREATE           0xC4000005(I32)
#define CFE_ES_ERR_CHILD_TASK_REGISTER         0xC400000B(I32)
#define CFE_ES_ERR_CHILD_TASK_DELETE           0xC4000018(I32)
#define CFE_ES_ERR_CHILD_TASK_DELETE_MAIN_TASK 0xC4000019(I32)
#define CFE_ES_ERR_DUPLICATE_NAME              0xC400002E(I32)
#define CFE_ES_CDS_INVALID_NAME                0xC400000F(I32)
#define CFE_ES_CDS_INVALID_SIZE                0xC4000010(I32)
// cfe_error.h: CFE_StatusString_t is `char[CFE_STATUS_STRING_LENGTH]`, so NASA's
// sizeof(*status_string) in CFE_ES_StatusToString resolves to exactly this.
#define CFE_STATUS_STRING_LENGTH 11
#define CFE_ES_OPERATION_TIMED_OUT             0xC4000027(I32)
#ifndef CFE_ES_FILE_IO_ERR
#define CFE_ES_FILE_IO_ERR 0xC4000014(I32)
#endif
// --- cfe_psp.h: the reset types -------------------------------------------------------------
#define CFE_PSP_RST_TYPE_PROCESSOR        1
#define CFE_PSP_RST_TYPE_POWERON          2
#define CFE_PSP_RST_SUBTYPE_RESET_COMMAND 5
// --- default_cfe_es_extern_typedefs.h: the enumerations ------------------------------------
// NASA spells all of these as enums. check_constants.py resolves an enumerator through the
// probe's second pass, so each number here is compared against NASA's header rather than
// trusted -- which is how the pool-id base offset was caught being wrong by one.
// --- cfe_es_eventids.h ----------------------------------------------------------------------
#define CFE_ES_CDS_REGISTER_ERR_EID 69
// --- cfe_es_interface_cfg.h -----------------------------------------------------------------
#ifndef CFE_MISSION_ES_CDS_MAX_NAME_LENGTH
#define CFE_MISSION_ES_CDS_MAX_NAME_LENGTH 16
#endif
#define CFE_ES_LogEntryType_CORE 1
#define CFE_ES_RunStatus_APP_RUN                1
#define CFE_ES_RunStatus_APP_EXIT               2
#define CFE_ES_RunStatus_APP_ERROR              3
#define CFE_ES_RunStatus_SYS_EXCEPTION          4
#define CFE_ES_RunStatus_CORE_APP_INIT_ERROR    8
#define CFE_ES_RunStatus_CORE_APP_RUNTIME_ERROR 9
#define CFE_ES_RunStatus_UNDEFINED              0
#define CFE_ES_RunStatus_SYS_RESTART            5
#define CFE_ES_RunStatus_SYS_RELOAD             6
#define CFE_ES_RunStatus_SYS_DELETE             7
#define CFE_ES_RunStatus_MAX                    10
#ifndef CFE_ES_APPID_UNDEFINED
#define CFE_ES_APPID_UNDEFINED  CFE_RESOURCEID_UNDEFINED
#define CFE_ES_TASKID_UNDEFINED CFE_RESOURCEID_UNDEFINED
#endif
#define CFE_ES_LIBID_UNDEFINED      CFE_RESOURCEID_UNDEFINED
#define CFE_ES_COUNTERID_UNDEFINED  CFE_RESOURCEID_UNDEFINED
#define CFE_ES_CDS_BAD_HANDLE       CFE_RESOURCEID_UNDEFINED
#define CFE_ES_AppType_CORE     1
#define CFE_ES_AppType_EXTERNAL 2
#define CFE_ES_AppType_LIBRARY  3
#define CFE_ES_AppState_EARLY_INIT 1
#define CFE_ES_AppState_LATE_INIT  2
#define CFE_ES_AppState_RUNNING    3
#define CFE_ES_AppState_WAITING    4
#define CFE_ES_AppState_STOPPED    5
#define CFE_ES_SystemState_CORE_READY 3
#define CFE_ES_SystemState_APPS_INIT  4
#define CFE_ES_SystemState_OPERATIONAL 5
#define CFE_ES_SystemState_SHUTDOWN   6
// --- cfe_es_platform_cfg.h --------------------------------------------------------------------
#define CFE_PLATFORM_ES_STARTUP_SYNC_POLL_MSEC 50
#ifndef CFE_PLATFORM_ES_DEFAULT_STACK_SIZE
#define CFE_PLATFORM_ES_DEFAULT_STACK_SIZE 8192
#endif
// --- what this file needs from elsewhere ------------------------------------------------------
// cfe_es_cds.c, cfe_es_cds_mempool.c, cfe_es_apps.c and cfe_es_erlog.c, none gated yet --
// fifteen functions, so fifteen stubs on both halves of the differential oracle. The same
// temporary arrangement CFE_SB_SendSubscriptionReport had until cfe_sb_task.c landed.
U0 CFE_ES_WriteToERLog(U32 EntryType, U32 ResetType, U32 ResetSubtype, U8 *Description);
I32 CFE_ES_FormCDSName(U8 *FullCDSName, U8 *CDSName, U32 ThisAppId);
CFE_ES_CDS_RegRec_t *CFE_ES_LocateCDSBlockRecordByID(U32 BlockID);
CFE_ES_CDS_RegRec_t *CFE_ES_LocateCDSBlockRecordByName(U8 *CDSName);
Bool CFE_ES_CDSBlockRecordIsMatch(CFE_ES_CDS_RegRec_t *CDSBlockRecPtr, U32 BlockID);
U32 CFE_ES_CDSBlockRecordGetID(CFE_ES_CDS_RegRec_t *CDSBlockRecPtr);
I32 CFE_ES_CDSBlockWrite(U32 Handle, U8 *DataToCopy);
I32 CFE_ES_CDSBlockRead(U8 *DataToCopy, U32 Handle);
I32 CFE_ES_RegisterCDSEx(U32 *HandlePtr, I64 UserBlockSize, U8 *Name, Bool CriticalTbl);
U0 CFE_ES_LockCDS();
U0 CFE_ES_UnlockCDS();
U0 CFE_ES_CopyModuleBasicInfo(CFE_ES_ModuleLoadParams_t *ParamsPtr, CFE_ES_AppInfo_t *ModuleInfo);
U0 CFE_ES_CopyModuleStatusInfo(CFE_ES_ModuleLoadStatus_t *StatusPtr, CFE_ES_AppInfo_t *ModuleInfo);
U0 CFE_ES_CopyModuleAddressInfo(U32 ModuleId, CFE_ES_AppInfo_t *ModuleInfo);
I32 CFE_ES_StartAppTask(U32 *TaskIdPtr, U8 *TaskName, U0 (*EntryPoint)(), CFE_ES_TaskStartParams_t *Params, U32 ParentAppId);
// It takes the ACTION NAME as its second argument and writes the "not valid" log message
// itself, which is why every caller below comments "Lock function already wrote log message".
CFE_ES_AppRecord_t *CFE_ES_LockUserAppRecord(U32 AppID, U8 *LogMsgAction);
// The PSP. CFE_PSP_Restart does not return when it works.
U0 CFE_PSP_Restart(U32 ResetType);
// OSAL.
I32 OS_TaskCreate(U32 *task_id, U8 *task_name, U0 (*function_pointer)(), U8 *stack_pointer, I64 stack_size, U32 priority, U32 flags);
I32 OS_TaskDelete(U32 task_id);
U0 OS_TaskExit();
I32 OS_TaskGetInfo(U32 task_id, OS_task_prop_t *task_prop);
I32 OS_TaskGetIdByName(U32 *task_id, U8 *task_name);
I32 OS_TaskDelay(U32 millisecond);
I32 OS_stat(U8 *path, os_fstat_t *filestats);
I32 OS_ModuleUnload(U32 module_id);
// Declared here, defined below -- the C's own order has each used above its definition.
I32 CFE_ES_WriteToSysLog(U8 *SpecStringPtr,...);
U0 CFE_ES_LockSharedData(U8 *FunctionName, I32 LineNumber);
U0 CFE_ES_UnlockSharedData(U8 *FunctionName, I32 LineNumber);
U0 CFE_ES_IncrementTaskCounter();
I32 CFE_ES_GetAppInfo(CFE_ES_AppInfo_t *AppInfo, U32 AppId);
I32 CFE_ES_GetLibInfo(CFE_ES_AppInfo_t *LibInfo, U32 LibId);
I32 CFE_ES_GetTaskName(U8 *TaskName, U32 TaskId, I64 BufferLength);
I32 CFE_ES_DeleteChildTask(U32 TaskId);
U0 CFE_ES_ExitChildTask();
I32 CFE_ES_CounterID_ToIndex(U32 CounterId, U32 *Idx);
I32 CFE_ES_GetGenCounterIDByName(U32 *CounterIdPtr, U8 *CounterName);
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// IT RETURNS THE TYPE AND OPTIONALLY WRITES THE SUBTYPE, which is an unusual shape for cFS: the
// return value is data rather than a status. There is no error case -- the reset area is always
// readable by the time anything calls this.
I32 CFE_ES_GetResetType(U32 *ResetSubtypePtr)
{
  if (ResetSubtypePtr != NULL) {
    *ResetSubtypePtr = CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype;
  }
  return CFE_ES_Global.ResetDataPtr->ResetVars.ResetType;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THIS FUNCTION IS NOT SUPPOSED TO RETURN, and the only reason it has a return value is that it
// might. CFE_PSP_Restart restarts the processor; NASA's comment on each of the three paths is
// "If the BSP routine is not implemented, it will return", and CFE_ES_NOT_IMPLEMENTED is what
// that looks like from the caller's side.
//
// A PROCESSOR RESET CAN BECOME A POWER-ON RESET. The count is incremented FIRST, then compared
// against MaxProcessorResetCount, so a board that keeps failing eventually gets the harder
// reset instead -- and the ER log entry is written before the restart with NASA's note that
// "the log will be wiped out, but it's good to have the entry just in case something fails".
I32 CFE_ES_ResetCFE(U32 ResetType)
{
  I32 ReturnCode;
  if (ResetType == CFE_PSP_RST_TYPE_PROCESSOR) {
    /*
    ** Increment the processor reset count
    */
    CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount++;
    /*
    ** Before doing a Processor reset, check to see
    ** if the maximum number has been exceeded
    */
    if (CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount > CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount) {
      CFE_ES_WriteToSysLog("%s: POWER ON RESET due to max proc resets (Commanded).\n", "CFE_ES_ResetCFE");
      /*
      ** Log the reset in the ER Log. The log will be wiped out, but it's good to have
      ** the entry just in case something fails.
      */
      CFE_ES_WriteToERLog(CFE_ES_LogEntryType_CORE, CFE_PSP_RST_TYPE_POWERON, CFE_PSP_RST_SUBTYPE_RESET_COMMAND, "POWER ON RESET due to max proc resets (Commanded).");
      /*
      ** Call the BSP reset routine
      */
      CFE_PSP_Restart(CFE_PSP_RST_TYPE_POWERON);
    } else {
      CFE_ES_WriteToSysLog("%s: PROCESSOR RESET called from CFE_ES_ResetCFE (Commanded).\n", "CFE_ES_ResetCFE");
      /*
      ** Update the reset variables
      */
      CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset = TRUE;
      /*
      ** Log the reset in the ER Log
      */
      CFE_ES_WriteToERLog(CFE_ES_LogEntryType_CORE, CFE_PSP_RST_TYPE_PROCESSOR, CFE_PSP_RST_SUBTYPE_RESET_COMMAND, "PROCESSOR RESET called from CFE_ES_ResetCFE (Commanded).");
      /*
      ** Call the BSP reset routine
      */
      CFE_PSP_Restart(CFE_PSP_RST_TYPE_PROCESSOR);
    }
    /*
    ** If the BSP routine is not implemented,
    ** it will return.
    */
    ReturnCode = CFE_ES_NOT_IMPLEMENTED;
  } else if (ResetType == CFE_PSP_RST_TYPE_POWERON) {
    CFE_ES_WriteToSysLog("%s: POWERON RESET called from CFE_ES_ResetCFE (Commanded).\n", "CFE_ES_ResetCFE");
    /*
    ** Log the reset in the ER Log. The log will be wiped out, but it's good to have
    ** the entry just in case something fails.
    */
    CFE_ES_WriteToERLog(CFE_ES_LogEntryType_CORE, CFE_PSP_RST_TYPE_POWERON, CFE_PSP_RST_SUBTYPE_RESET_COMMAND, "POWERON RESET called from CFE_ES_ResetCFE (Commanded).");
    /*
    ** Call the BSP reset routine
    */
    CFE_PSP_Restart(CFE_PSP_RST_TYPE_POWERON);
    /*
    ** If the BSP routine is not implemented,
    ** it will return.
    */
    ReturnCode = CFE_ES_NOT_IMPLEMENTED;
  } else {
    CFE_ES_WriteToSysLog("%s: Invalid Reset Type: %d.\n", "CFE_ES_ResetCFE", ResetType);
    ReturnCode = CFE_ES_BAD_ARGUMENT;
  }
  return ReturnCode;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// RESTART, RELOAD AND DELETE DO NOT DO ANYTHING. All three set ControlReq.AppControlRequest and
// return; the ES background task notices it later and does the work. That is deliberate and it
// is why none of them can fail for any reason except a bad id or a missing file: an app cannot
// be torn down from inside the caller's context, because the caller might BE the app.
//
// CFE_ES_LockUserAppRecord takes the lock AND writes the "not valid" log line itself, which is
// what every "Lock function already wrote log message" comment below refers to. The unlock is
// in the success branch only -- a NULL return means the lock was never taken.
I32 CFE_ES_RestartApp(U32 AppID)
{
  I32 ReturnCode = CFE_SUCCESS;
  os_fstat_t FileStatus;
  CFE_ES_AppRecord_t *AppRecPtr;
  AppRecPtr = CFE_ES_LockUserAppRecord(AppID, "Restart");
  if (AppRecPtr == NULL) {
    /* Lock function already wrote log message */
    ReturnCode = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  } else {
    if (OS_stat(AppRecPtr->StartParams.BasicInfo.FileName, &FileStatus) == OS_SUCCESS) {
      CFE_ES_SysLogWrite_Unsync("%s: Restart Application %s Initiated\n", "CFE_ES_RestartApp", CFE_ES_AppRecordGetName(AppRecPtr));
      AppRecPtr->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_RESTART;
    } else {
      CFE_ES_SysLogWrite_Unsync("%s: Cannot Restart Application %s, File %s does not exist.\n", "CFE_ES_RestartApp", CFE_ES_AppRecordGetName(AppRecPtr), AppRecPtr->StartParams.BasicInfo.FileName);
      ReturnCode = CFE_ES_FILE_IO_ERR;
    }
    CFE_ES_UnlockSharedData("CFE_ES_RestartApp", 0);
  }
  return ReturnCode;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_ReloadApp(U32 AppID, U8 *AppFileName)
{
  I32 ReturnCode = CFE_SUCCESS;
  os_fstat_t FileStatus;
  CFE_ES_AppRecord_t *AppRecPtr;
  if (AppFileName == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  AppRecPtr = CFE_ES_LockUserAppRecord(AppID, "Reload");
  if (AppRecPtr == NULL) {
    /* Lock function already wrote log message */
    ReturnCode = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  } else {
    /*
    ** Check to see if the file exists
    */
    if (OS_stat(AppFileName, &FileStatus) == OS_SUCCESS) {
      CFE_ES_SysLogWrite_Unsync("%s: Reload Application %s Initiated. New filename = %s\n", "CFE_ES_ReloadApp", CFE_ES_AppRecordGetName(AppRecPtr), AppFileName);
      StrNCpy(AppRecPtr->StartParams.BasicInfo.FileName, AppFileName, OS_MAX_PATH_LEN - 1);
      AppRecPtr->StartParams.BasicInfo.FileName[OS_MAX_PATH_LEN - 1] = 0;
      AppRecPtr->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_RELOAD;
    } else {
      CFE_ES_SysLogWrite_Unsync("%s: Cannot Reload Application %s, File %s does not exist.\n", "CFE_ES_ReloadApp", CFE_ES_AppRecordGetName(AppRecPtr), AppFileName);
      ReturnCode = CFE_ES_FILE_IO_ERR;
    }
    CFE_ES_UnlockSharedData("CFE_ES_ReloadApp", 0);
  }
  return ReturnCode;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_DeleteApp(U32 AppID)
{
  I32 ReturnCode = CFE_SUCCESS;
  CFE_ES_AppRecord_t *AppRecPtr;
  AppRecPtr = CFE_ES_LockUserAppRecord(AppID, "Delete");
  if (AppRecPtr == NULL) {
    /* Lock function already wrote log message */
    ReturnCode = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  } else {
    CFE_ES_SysLogWrite_Unsync("%s: Delete Application %s Initiated\n", "CFE_ES_DeleteApp", CFE_ES_AppRecordGetName(AppRecPtr));
    AppRecPtr->ControlReq.AppControlRequest = CFE_ES_RunStatus_SYS_DELETE;
    CFE_ES_UnlockSharedData("CFE_ES_DeleteApp", 0);
  }
  return ReturnCode;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// AN EXTERNAL APP THAT CALLS THIS NEVER COMES BACK: the last branch is `while (1)
// OS_TaskDelay(500)`, and NASA's comment is "Suspend the Application until ES kills it. It
// might be better to have a way of suspending the app in the OS". A core app either triggers a
// processor reset or exits its task. The three `return`s in the middle are each guarded by a
// comment saying the code will not reach them except under unit test.
//
// THE PASSED-IN STATUS IS ONLY STORED IF NOTHING IS ALREADY PENDING, and NASA explains why: if
// a control request is already set, this exit is part of the orderly shutdown that request
// caused, so overwriting it would lose the reason.
//
// AND AN INVALID ExitStatus IS NOT REFUSED, it is DOWNGRADED to APP_ERROR with a log line --
// NASA's comment calls an out-of-range value "a bug in the caller". Refusing would leave the
// app running.
U0 CFE_ES_ExitApp(U32 ExitStatus)
{
  I32 ReturnCode;
  CFE_ES_AppRecord_t *AppRecPtr;
  CFE_ES_LockSharedData("CFE_ES_ExitApp", 0);
  /*
   * This should only be called with a valid ExitStatus, anything else is invalid
   * and indicates a bug in the caller.
   */
  if (ExitStatus == CFE_ES_RunStatus_UNDEFINED || ExitStatus >= CFE_ES_RunStatus_MAX) {
    CFE_ES_SysLogWrite_Unsync("%s: Called with invalid status (%u).\n", "CFE_ES_ExitApp", ExitStatus);
    /* revert to the ERROR status */
    ExitStatus = CFE_ES_RunStatus_APP_ERROR;
  }
  AppRecPtr = CFE_ES_GetAppRecordByContext();
  if (AppRecPtr != NULL) {
    /*
     * Set the status in the global table.
     *
     * The passed-in status should only be stored if there was no already-pending
     * request from a ground command or other source, such as an exception, etc.
     *
     * If a control request is already pending, it is assumed that this exit is
     * part of an orderly shutdown caused by that request, and therefore it
     * should not be overwritten here.
     */
    if (AppRecPtr->ControlReq.AppControlRequest == CFE_ES_RunStatus_APP_RUN) {
      AppRecPtr->ControlReq.AppControlRequest = ExitStatus;
    }
    /*
    ** Check to see if the App is an external cFE App.
    */
    if (AppRecPtr->Type == CFE_ES_AppType_CORE) {
      /*
      ** A core app should only call this function with one of two ExitStatus codes.
      */
      if (ExitStatus == CFE_ES_RunStatus_CORE_APP_INIT_ERROR) {
        CFE_ES_SysLogWrite_Unsync("%s: CORE Application %s Had an Init Error.\n", "CFE_ES_ExitApp", CFE_ES_AppRecordGetName(AppRecPtr));
        /*
        ** Unlock the ES Shared data before calling ResetCFE
        */
        CFE_ES_UnlockSharedData("CFE_ES_ExitApp", 0);
        /*
        ** Do a Processor Reset the cFE
        */
        ReturnCode = CFE_ES_ResetCFE(CFE_PSP_RST_TYPE_PROCESSOR);
        /*
        ** The CFE_ES_ResetCFE function does not normally return,
        ** but it may return during unit testing. If it does,
        ** log the return code (even if it claims CFE_SUCCESS).
        */
        CFE_ES_WriteToSysLog("%s: CORE Application Init Error Processor Reset, RC = 0x%08X\n", "CFE_ES_ExitApp", ReturnCode);
        return;
      } else if (ExitStatus == CFE_ES_RunStatus_CORE_APP_RUNTIME_ERROR) {
        CFE_ES_SysLogWrite_Unsync("%s: CORE Application %s Had a Runtime Error.\n", "CFE_ES_ExitApp", CFE_ES_AppRecordGetName(AppRecPtr));
        /*
        ** Unlock the ES Shared data before killing the main task
        */
        CFE_ES_UnlockSharedData("CFE_ES_ExitApp", 0);
        /*
        ** Exit this task
        */
        OS_TaskExit();
        /*
        ** Code will not return, except under unit test
        */
        return;
      } else {
        CFE_ES_SysLogWrite_Unsync("%s: Cannot Exit CORE Application %s\n", "CFE_ES_ExitApp", CFE_ES_AppRecordGetName(AppRecPtr));
      }
    } else
      /* It is an external App */
      {
        CFE_ES_SysLogWrite_Unsync("%s: Application %s called CFE_ES_ExitApp\n", "CFE_ES_ExitApp", CFE_ES_AppRecordGetName(AppRecPtr));
        AppRecPtr->AppState = CFE_ES_AppState_STOPPED;
        /*
      ** Unlock the ES Shared data before suspending the app
      */
        CFE_ES_UnlockSharedData("CFE_ES_ExitApp", 0);
        /*
      ** Suspend the Application until ES kills it.
      ** It might be better to have a way of suspending the app in the OS
      */
        while (1) {
          OS_TaskDelay(500);
        }
      }
  }
  CFE_ES_UnlockSharedData("CFE_ES_ExitApp", 0);
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE RunStatus ARGUMENT IS NEARLY VESTIGIAL. NASA's own comment says "the RunStatus really
// doesn't add much value here, so this also allows this function to be called with NULL, with
// the possibility of phasing this out entirely." Both reads of it are NULL-guarded.
//
// Note which side of the lock the counter increment is on: OUTSIDE, with the reason spelled out
// -- "each task has its own counter which is only updated by itself".
Bool CFE_ES_RunLoop(U32 *RunStatus)
{
  Bool ReturnCode;
  CFE_ES_AppRecord_t *AppRecPtr;
  /*
   * call CFE_ES_IncrementTaskCounter() so this is
   * recorded as task activity for outgoing telemetry.
   *
   * This will update the counter for whatever task context
   * is calling this API, which is expected to be the main
   * task of the app.  This can be done outside of any lock
   * because each task has its own counter which is only updated
   * by itself.
   */
  CFE_ES_IncrementTaskCounter();
  /*
   * This API should generally only be called with the status as CFE_ES_RunStatus_APP_RUN.
   * Anything else gets an immediate "false" return which should cause the caller to
   * break out of its main loop.  There is no need to take the lock or do any other
   * accounting in that case.
   *
   * Note that the RunStatus really doesn't add much value here, so this also allows
   * this function to be called with NULL, with the possibility of phasing this out
   * entirely.
   */
  if (RunStatus != NULL && *RunStatus != CFE_ES_RunStatus_APP_RUN) {
    return FALSE;
  }
  CFE_ES_LockSharedData("CFE_ES_RunLoop", 0);
  /*
  ** Get App Record
  */
  AppRecPtr = CFE_ES_GetAppRecordByContext();
  if (AppRecPtr != NULL) {
    /*
     ** App state must be RUNNING (no-op if already set to running)
     */
    if (AppRecPtr->AppState < CFE_ES_AppState_RUNNING) {
      AppRecPtr->AppState = CFE_ES_AppState_RUNNING;
    }
    /*
     * Check if the control request is also set to "RUN"
     * Anything else should also return false, so the loop will exit.
     */
    if (AppRecPtr->ControlReq.AppControlRequest == CFE_ES_RunStatus_APP_RUN) {
      ReturnCode = TRUE;
    } else {
      /*
       * Just in case, also output the status, just in case the app looks at this.
       */
      if (RunStatus != NULL) {
        *RunStatus = AppRecPtr->ControlReq.AppControlRequest;
      }
      ReturnCode = FALSE;
    }
  } else {
    /*
     * Cannot do anything without the AppID
     */
    CFE_ES_SysLogWrite_Unsync("%s: Error getting AppID for the caller\n", "CFE_ES_RunLoop");
    ReturnCode = FALSE;
  }
  CFE_ES_UnlockSharedData("CFE_ES_RunLoop", 0);
  return ReturnCode;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// WAITING FOR A SYSTEM STATE ALSO MOVES THE CALLER INTO THE MATCHING APP STATE, and NASA's
// comment gives the reason that makes it more than a convenience: "if this was not done an app
// could be waiting for itself (which will always time out)." The system state only advances when
// every app has reached the required app state, so an app that waited without first declaring
// itself ready would be one of the apps holding the state back.
//
// THE CORE/EXTERNAL SPLIT IS NOT SYMMETRIC. A core app gets one coarse rule (anything at or
// above CORE_READY means RUNNING); an external app gets three finer bands. That is because
// core apps are all up before CORE_READY by construction.
//
// THE TIMEOUT IS CHECKED AFTER THE STATE, so a request already satisfied returns CFE_SUCCESS
// even with a zero timeout; and the subtraction cannot underflow because WaitTime is clamped to
// WaitRemaining in the `else if (WaitRemaining > 0)` branch.
I32 CFE_ES_WaitForSystemState(U32 MinSystemState, U32 TimeOutMilliseconds)
{
  I32 Status = CFE_SUCCESS;
  CFE_ES_AppRecord_t *AppRecPtr;
  U32 RequiredAppState;
  U32 WaitTime;
  U32 WaitRemaining;
  /*
   * Calling app is assumed to have completed its own initialization up to the point
   * it is waiting for.
   *
   * Determine the implicit app state based on the system state it is indicating
   */
  CFE_ES_LockSharedData("CFE_ES_WaitForSystemState", 0);
  /*
  ** Get App Record
  */
  AppRecPtr = CFE_ES_GetAppRecordByContext();
  if (AppRecPtr != NULL) {
    RequiredAppState = CFE_ES_AppState_EARLY_INIT;
    /*
     * If a core app waits for anything above "CORE_READY" then it is assumed to be RUNNING
     *
     * External apps have additional finer-grained sync:
     *  - SYSTEM_STATE_APPS_INIT requires that all apps are at least up to LATE_INIT
     *  - SYSTEM_STATE_OPERATIONAL requires that all apps are RUNNING
     *  - SYSTEM_STATE_SHUTDOWN requires that all apps are STOPPED (in concept anyway)
     */
    if (AppRecPtr->Type == CFE_ES_AppType_CORE) {
      if (MinSystemState >= CFE_ES_SystemState_CORE_READY) {
        RequiredAppState = CFE_ES_AppState_RUNNING;
      }
    } else if (MinSystemState >= CFE_ES_SystemState_SHUTDOWN) {
      RequiredAppState = CFE_ES_AppState_STOPPED;
    } else if (MinSystemState >= CFE_ES_SystemState_OPERATIONAL) {
      RequiredAppState = CFE_ES_AppState_RUNNING;
    } else if (MinSystemState >= CFE_ES_SystemState_APPS_INIT) {
      RequiredAppState = CFE_ES_AppState_LATE_INIT;
    }
    /*
     * NOTE -- a call to "CFE_ES_WaitForSystemState()" implies that the calling app MUST also
     * be in the requisite state.  This is hooked into here to avoid needing to update all
     *existing apps to add an explicit state change call, but it makes sense because if this was
     *not done an app could be waiting for itself (which will always time out).
     */
    if (AppRecPtr->AppState < RequiredAppState) {
      AppRecPtr->AppState = RequiredAppState;
    }
  }
  CFE_ES_UnlockSharedData("CFE_ES_WaitForSystemState", 0);
  /*
   * Do the actual delay loop.
   *
   * This is only dependent on the main (startup) task updating the global variable
   * to be at least the state requested.
   */
  WaitRemaining = TimeOutMilliseconds;
  while (CFE_ES_Global.SystemState < MinSystemState) {
    /* TBD: Very Crude timing here, but not sure if it matters,
     * as this is only done during startup, not real work */
    if (WaitRemaining > CFE_PLATFORM_ES_STARTUP_SYNC_POLL_MSEC) {
      WaitTime = CFE_PLATFORM_ES_STARTUP_SYNC_POLL_MSEC;
    } else if (WaitRemaining > 0) {
      WaitTime = WaitRemaining;
    } else {
      Status = CFE_ES_OPERATION_TIMED_OUT;
      break;
    }
    OS_TaskDelay(WaitTime);
    WaitRemaining -= WaitTime;
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_ES_WaitForStartupSync(U32 TimeOutMilliseconds)
{
  CFE_ES_WaitForSystemState(CFE_ES_SystemState_OPERATIONAL, TimeOutMilliseconds);
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE "BY NAME" LOOKUPS ALL WRITE THE OUTPUT EVEN WHEN THEY FAIL, and NASA says why: "ensure
// the output value is set to a safe value, in case the caller does not check the return code."
// That is not belt-and-braces, it is the difference between a caller using UNDEFINED -- which
// every IsMatch rejects -- and a caller using whatever was on its stack.
I32 CFE_ES_GetAppIDByName(U32 *AppIdPtr, U8 *AppName)
{
  CFE_ES_AppRecord_t *AppRecPtr;
  I32 Result;
  if (AppName == NULL || AppIdPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  CFE_ES_LockSharedData("CFE_ES_GetAppIDByName", 0);
  AppRecPtr = CFE_ES_LocateAppRecordByName(AppName);
  if (AppRecPtr == NULL) {
    /*
     * ensure the output value is set to a safe value,
     * in case the caller does not check the return code.
     */
    Result = CFE_ES_ERR_NAME_NOT_FOUND;
    *AppIdPtr = CFE_ES_APPID_UNDEFINED;
  } else {
    Result = CFE_SUCCESS;
    *AppIdPtr = CFE_ES_AppRecordGetID(AppRecPtr);
  }
  CFE_ES_UnlockSharedData("CFE_ES_GetAppIDByName", 0);
  return Result;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_GetLibIDByName(U32 *LibIdPtr, U8 *LibName)
{
  CFE_ES_LibRecord_t *LibRecPtr;
  I32 Result;
  if (LibName == NULL || LibIdPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  CFE_ES_LockSharedData("CFE_ES_GetLibIDByName", 0);
  LibRecPtr = CFE_ES_LocateLibRecordByName(LibName);
  if (LibRecPtr == NULL) {
    /*
     * ensure the output value is set to a safe value,
     * in case the caller does not check the return code.
     */
    Result = CFE_ES_ERR_NAME_NOT_FOUND;
    *LibIdPtr = CFE_ES_LIBID_UNDEFINED;
  } else {
    Result = CFE_SUCCESS;
    *LibIdPtr = CFE_ES_LibRecordGetID(LibRecPtr);
  }
  CFE_ES_UnlockSharedData("CFE_ES_GetLibIDByName", 0);
  return Result;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THIS ONE TAKES NO LOCK, and the one-line comment is the whole reason: "For tasks IDs, defer
// to OSAL for name lookup". ES's task table is indexed by the OSAL id, it does not own the
// names, so there is no ES state to protect.
I32 CFE_ES_GetTaskIDByName(U32 *TaskIdPtr, U8 *TaskName)
{
  U32 OsalId = OS_OBJECT_ID_UNDEFINED;
  I32 OsStatus;
  I32 Result;
  if (TaskName == NULL || TaskIdPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  /* For tasks IDs, defer to OSAL for name lookup */
  OsStatus = OS_TaskGetIdByName(&OsalId, TaskName);
  if (OsStatus == OS_SUCCESS) {
    Result = CFE_SUCCESS;
    *TaskIdPtr = CFE_ES_TaskId_FromOSAL(OsalId);
  } else {
    Result = CFE_ES_ERR_NAME_NOT_FOUND;
    *TaskIdPtr = CFE_ES_TASKID_UNDEFINED;
  }
  return Result;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_GetAppID(U32 *AppIdPtr)
{
  CFE_ES_AppRecord_t *AppRecPtr;
  I32 Result;
  if (AppIdPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  CFE_ES_LockSharedData("CFE_ES_GetAppID", 0);
  AppRecPtr = CFE_ES_GetAppRecordByContext();
  if (AppRecPtr != NULL) {
    *AppIdPtr = CFE_ES_AppRecordGetID(AppRecPtr);
    Result = CFE_SUCCESS;
  } else {
    *AppIdPtr = CFE_ES_APPID_UNDEFINED;
    Result = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  CFE_ES_UnlockSharedData("CFE_ES_GetAppID", 0);
  return Result;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_GetTaskID(U32 *TaskIdPtr)
{
  I32 Result;
  CFE_ES_TaskRecord_t *TaskRecPtr;
  if (TaskIdPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  CFE_ES_LockSharedData("CFE_ES_GetTaskID", 0);
  TaskRecPtr = CFE_ES_GetTaskRecordByContext();
  if (TaskRecPtr == NULL) {
    *TaskIdPtr = CFE_ES_TASKID_UNDEFINED;
    Result = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  } else {
    *TaskIdPtr = CFE_ES_TaskRecordGetID(TaskRecPtr);
    Result = CFE_SUCCESS;
  }
  CFE_ES_UnlockSharedData("CFE_ES_GetTaskID", 0);
  return Result;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE LOCATE IS OUTSIDE THE LOCK AND THE MATCH IS INSIDE IT, and NASA's comment states the
// rule: "confirm that the app record is a match, which must be done while locked." Locate is
// pure arithmetic on the id -- it cannot read a torn record because it reads nothing. IsMatch
// reads the record's own id, which another task can be in the middle of writing.
I32 CFE_ES_GetAppName(U8 *AppName, U32 AppId, I64 BufferLength)
{
  I32 Result;
  CFE_ES_AppRecord_t *AppRecPtr;
  if (BufferLength == 0 || AppName == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  /*
  ** Get App Record
  */
  AppRecPtr = CFE_ES_LocateAppRecordByID(AppId);
  CFE_ES_LockSharedData("CFE_ES_GetAppName", 0);
  /*
   * confirm that the app record is a match,
   * which must be done while locked.
   */
  if (CFE_ES_AppRecordIsMatch(AppRecPtr, AppId)) {
    StrNCpy(AppName, CFE_ES_AppRecordGetName(AppRecPtr), BufferLength - 1);
    AppName[BufferLength - 1] = 0;
    Result = CFE_SUCCESS;
  } else {
    AppName[0] = 0;
    Result = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  CFE_ES_UnlockSharedData("CFE_ES_GetAppName", 0);
  return Result;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_GetLibName(U8 *LibName, U32 LibId, I64 BufferLength)
{
  I32 Result;
  CFE_ES_LibRecord_t *LibRecPtr;
  if (BufferLength == 0 || LibName == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  /*
  ** Get Lib Record
  */
  LibRecPtr = CFE_ES_LocateLibRecordByID(LibId);
  CFE_ES_LockSharedData("CFE_ES_GetLibName", 0);
  /*
   * confirm that the Lib record is a match,
   * which must be done while locked.
   */
  if (CFE_ES_LibRecordIsMatch(LibRecPtr, LibId)) {
    StrNCpy(LibName, CFE_ES_LibRecordGetName(LibRecPtr), BufferLength - 1);
    LibName[BufferLength - 1] = 0;
    Result = CFE_SUCCESS;
  } else {
    LibName[0] = 0;
    Result = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  CFE_ES_UnlockSharedData("CFE_ES_GetLibName", 0);
  return Result;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THREE OSAL ERRORS MAP TO THREE DIFFERENT cFE ERRORS and the fourth case is logged. Note that
// OS_ERR_NAME_TOO_LONG becomes BAD_ARGUMENT, not a truncation: the caller's buffer was too
// small, which is the caller's fault, so the name is not returned at all.
I32 CFE_ES_GetTaskName(U8 *TaskName, U32 TaskId, I64 BufferLength)
{
  I32 OsStatus;
  U32 OsalId;
  if (BufferLength == 0 || TaskName == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  // CFE_RESOURCEID_TEST_DEFINED(id) expands to CFE_ResourceId_IsDefined(CFE_RESOURCEID_UNWRAP(id)),
  // and UNWRAP is the identity in the SIMPLE resourceid variant this port uses.
  if (!CFE_ResourceId_IsDefined(TaskId)) {
    return CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  /*
   * Query OSAL to get the task name
   */
  OsalId = CFE_ES_TaskId_ToOSAL(TaskId);
  OsStatus = OS_GetResourceName(OsalId, TaskName, BufferLength);
  if (OsStatus == OS_ERR_INVALID_ID) {
    /* Supplied ID is not a CFE task */
    return CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  if (OsStatus == OS_ERR_NAME_TOO_LONG) {
    /* Name is too long to fit in supplied buffer */
    return CFE_ES_BAD_ARGUMENT;
  }
  if (OsStatus != OS_SUCCESS) {
    /* Some other uncaught error */
    CFE_ES_WriteToSysLog("%s(): Unexpected error from OS_GetResourceName(): %ld", "CFE_ES_GetTaskName", OsStatus);
    return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE MODULE ID IS CARRIED OUT PAST THE UNLOCK ON PURPOSE. CFE_ES_CopyModuleAddressInfo calls
// into OSAL, and ES does not hold its own lock across a call into another subsystem -- so the
// ModuleId is copied to a local inside the lock and used after it. That is also why ModuleId is
// initialised to OS_OBJECT_ID_UNDEFINED before the lock: the failure path leaves it untouched,
// and the call is skipped anyway because Status is not CFE_SUCCESS.
//
// THE CHILD-TASK COUNT IS A FULL SCAN of the task table, and the main task is identified by
// comparing ids, not by position. The main task contributes its execution count, stack size and
// priority to the app info; every other task of the app only increments a counter.
I32 CFE_ES_GetAppInfo(CFE_ES_AppInfo_t *AppInfo, U32 AppId)
{
  CFE_ES_AppRecord_t *AppRecPtr;
  CFE_ES_TaskRecord_t *TaskRecPtr;
  I32 Status;
  U32 ModuleId;
  U32 i;
  if (AppInfo == NULL) {
    CFE_ES_WriteToSysLog("%s: Invalid Parameter ( Null Pointer )\n", "CFE_ES_GetAppInfo");
    return CFE_ES_BAD_ARGUMENT;
  }
  MemSet(AppInfo, 0, sizeof(CFE_ES_AppInfo_t));
  ModuleId = OS_OBJECT_ID_UNDEFINED;
  AppRecPtr = CFE_ES_LocateAppRecordByID(AppId);
  CFE_ES_LockSharedData("CFE_ES_GetAppInfo", 0);
  if (!CFE_ES_AppRecordIsMatch(AppRecPtr, AppId)) {
    /*
     * Log a message if called with an invalid ID.
     */
    CFE_ES_WriteToSysLog("%s: App ID not active: %lu\n", "CFE_ES_GetAppInfo", AppId);
    Status = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  } else {
    AppInfo->ResourceId = AppId;
    /* make into a generic resource ID */
    AppInfo->Type = AppRecPtr->Type;
    StrNCpy(AppInfo->Name, CFE_ES_AppRecordGetName(AppRecPtr), CFE_MISSION_MAX_API_LEN - 1);
    CFE_ES_CopyModuleBasicInfo(&AppRecPtr->StartParams.BasicInfo, AppInfo);
    CFE_ES_CopyModuleStatusInfo(&AppRecPtr->LoadStatus, AppInfo);
    AppInfo->ExceptionAction = AppRecPtr->StartParams.ExceptionAction;
    AppInfo->MainTaskId = AppRecPtr->MainTaskId;
    ModuleId = AppRecPtr->LoadStatus.ModuleId;
    /*
    ** Calculate the number of child tasks
    */
    AppInfo->NumOfChildTasks = 0;
    TaskRecPtr = CFE_ES_Global.TaskTable;
    for (i = 0; i < OS_MAX_TASKS; i++) {
      if (CFE_ES_TaskRecordIsUsed(TaskRecPtr) && CFE_ResourceId_Equal(TaskRecPtr->AppId, AppId)) {
        if (CFE_ResourceId_Equal(CFE_ES_TaskRecordGetID(TaskRecPtr), AppInfo->MainTaskId)) {
          /* This is the main task - capture its name and execution count */
          AppInfo->ExecutionCounter = TaskRecPtr->ExecutionCounter;
          StrNCpy(AppInfo->MainTaskName, TaskRecPtr->TaskName, CFE_MISSION_MAX_API_LEN - 1);
          AppInfo->MainTaskName[CFE_MISSION_MAX_API_LEN - 1] = 0;
          AppInfo->StackSize = CFE_ES_MEMOFFSET_C(TaskRecPtr->StartParams.StackSize);
          AppInfo->Priority = TaskRecPtr->StartParams.Priority;
        } else {
          /* This is a child task, no extra info, just increment count */
          ++AppInfo->NumOfChildTasks;
        }
      }
      ++TaskRecPtr;
    }
    Status = CFE_SUCCESS;
  }
  CFE_ES_UnlockSharedData("CFE_ES_GetAppInfo", 0);
  /*
  ** Get the address information from the OSAL
  */
  if (Status == CFE_SUCCESS) {
    CFE_ES_CopyModuleAddressInfo(ModuleId, AppInfo);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// A LIBRARY REPORTS ITS TYPE AS A CONSTANT, not from a record field -- a CFE_ES_LibRecord_t has
// no Type member, because every library is CFE_ES_AppType_LIBRARY by construction.
//
// NOTE WHICH SYSLOG CALL THIS ONE USES: SysLogWrite_Unsync, because it is already holding the
// shared-data lock, where CFE_ES_GetAppInfo above calls the locking CFE_ES_WriteToSysLog from
// the same place. That is an inconsistency in NASA's source, not in the translation, and it is
// visible in the transcript as the two calls taking the lock a different number of times.
I32 CFE_ES_GetLibInfo(CFE_ES_AppInfo_t *LibInfo, U32 LibId)
{
  I32 Status;
  CFE_ES_LibRecord_t *LibRecPtr;
  U32 ModuleId;
  if (LibInfo == NULL) {
    CFE_ES_WriteToSysLog("%s: Invalid Parameter ( Null Pointer )\n", "CFE_ES_GetLibInfo");
    return CFE_ES_BAD_ARGUMENT;
  }
  MemSet(LibInfo, 0, sizeof(CFE_ES_AppInfo_t));
  ModuleId = OS_OBJECT_ID_UNDEFINED;
  LibRecPtr = CFE_ES_LocateLibRecordByID(LibId);
  CFE_ES_LockSharedData("CFE_ES_GetLibInfo", 0);
  if (!CFE_ES_LibRecordIsMatch(LibRecPtr, LibId)) {
    /*
     * Log a message if called with an invalid ID.
     */
    CFE_ES_SysLogWrite_Unsync("%s: Lib ID not active: %lu\n", "CFE_ES_GetLibInfo", LibId);
    Status = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  } else {
    LibInfo->ResourceId = LibId;
    /* make into generic ID */
    LibInfo->Type = CFE_ES_AppType_LIBRARY;
    StrNCpy(LibInfo->Name, CFE_ES_LibRecordGetName(LibRecPtr), CFE_MISSION_MAX_API_LEN - 1);
    CFE_ES_CopyModuleBasicInfo(&LibRecPtr->LoadParams, LibInfo);
    CFE_ES_CopyModuleStatusInfo(&LibRecPtr->LoadStatus, LibInfo);
    ModuleId = LibRecPtr->LoadStatus.ModuleId;
    Status = CFE_SUCCESS;
  }
  CFE_ES_UnlockSharedData("CFE_ES_GetLibInfo", 0);
  /*
   ** Get the address information from the OSAL
   */
  if (Status == CFE_SUCCESS) {
    CFE_ES_CopyModuleAddressInfo(ModuleId, LibInfo);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THIS DISPATCHES ON THE ID'S BASE, which is how one generic resource id serves both tables --
// the base is the high bits CFE_ResourceId_GetBase masks out, and an app id and a lib id differ
// only there. NASA's own comment explains the missing NULL check: "ModuleInfo NULL pointer
// check is performed by CFE_ES_GetAppInfo or CFE_ES_GetLibInfo".
I32 CFE_ES_GetModuleInfo(CFE_ES_AppInfo_t *ModuleInfo, U32 ResourceId)
{
  I32 Status;
  /* Note - ModuleInfo NULL pointer check is performed by CFE_ES_GetAppInfo or CFE_ES_GetLibInfo
   */
  switch (CFE_ResourceId_GetBase(ResourceId)) {
    case CFE_ES_APPID_BASE :
    Status = CFE_ES_GetAppInfo(ModuleInfo, ResourceId);
    break;
    case CFE_ES_LIBID_BASE :
    Status = CFE_ES_GetLibInfo(ModuleInfo, ResourceId);
    break;
    default:
    /*
       * Log a message if called with an invalid ID.
       */
    CFE_ES_WriteToSysLog("%s: Resource ID not valid: %lu\n", "CFE_ES_GetModuleInfo", CFE_ResourceId_ToInteger(ResourceId));
    Status = CFE_ES_ERR_RESOURCEID_NOT_VALID;
    break;
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THERE ARE TWO WAYS TO FAIL HERE AND THEY RETURN THE SAME CODE. A bad task id logs "Task ID
// Not Active"; a GOOD task id whose parent app id is bad returns the same
// RESOURCEID_NOT_VALID with no log line at all -- NASA's comment is "task ID was OK but parent
// app ID is bad". A caller cannot tell them apart, and the second one means ES's own tables
// disagree with each other.
I32 CFE_ES_GetTaskInfo(CFE_ES_TaskInfo_t *TaskInfo, U32 TaskId)
{
  CFE_ES_TaskRecord_t *TaskRecPtr;
  CFE_ES_AppRecord_t *AppRecPtr;
  I32 Status;
  if (TaskInfo == NULL) {
    CFE_ES_WriteToSysLog("%s: Invalid Parameter ( Null Pointer )\n", "CFE_ES_GetTaskInfo");
    return CFE_ES_BAD_ARGUMENT;
  }
  MemSet(TaskInfo, 0, sizeof(CFE_ES_TaskInfo_t));
  TaskRecPtr = CFE_ES_LocateTaskRecordByID(TaskId);
  CFE_ES_LockSharedData("CFE_ES_GetTaskInfo", 0);
  if (!CFE_ES_TaskRecordIsMatch(TaskRecPtr, TaskId)) {
    /* task ID is bad */
    Status = CFE_ES_ERR_RESOURCEID_NOT_VALID;
    CFE_ES_SysLogWrite_Unsync("%s: Task ID Not Active: %lu\n", "CFE_ES_GetTaskInfo", TaskId);
  } else {
    /*
    ** Get the Application ID and Task Name
    */
    TaskInfo->AppId = TaskRecPtr->AppId;
    StrNCpy(TaskInfo->TaskName, CFE_ES_TaskRecordGetName(TaskRecPtr), CFE_MISSION_MAX_API_LEN - 1);
    TaskInfo->TaskName[CFE_MISSION_MAX_API_LEN - 1] = 0;
    /*
    ** Store away the Task ID ( for the QueryAllTasks Cmd )
    */
    TaskInfo->TaskId = CFE_ES_TaskRecordGetID(TaskRecPtr);
    /*
    ** Get the other stats for the task
    */
    TaskInfo->ExecutionCounter = TaskRecPtr->ExecutionCounter;
    TaskInfo->StackSize = CFE_ES_MEMOFFSET_C(TaskRecPtr->StartParams.StackSize);
    TaskInfo->Priority = TaskRecPtr->StartParams.Priority;
    /*
    ** Get the Application Details
    */
    AppRecPtr = CFE_ES_LocateAppRecordByID(TaskRecPtr->AppId);
    if (CFE_ES_AppRecordIsMatch(AppRecPtr, TaskRecPtr->AppId)) {
      StrNCpy(TaskInfo->AppName, CFE_ES_AppRecordGetName(AppRecPtr), CFE_MISSION_MAX_API_LEN - 1);
      TaskInfo->AppName[CFE_MISSION_MAX_API_LEN - 1] = 0;
      Status = CFE_SUCCESS;
    } else {
      /* task ID was OK but parent app ID is bad */
      Status = CFE_ES_ERR_RESOURCEID_NOT_VALID;
    }
  }
  CFE_ES_UnlockSharedData("CFE_ES_GetTaskInfo", 0);
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// ONLY A MAIN TASK MAY CREATE A CHILD TASK -- there is no task tree, only one level. The check
// is `SelfTaskId == AppRecPtr->MainTaskId`, and a child calling this gets
// ERR_CHILD_TASK_CREATE, not a second-generation task.
//
// THE NULL CHECKS ARE NESTED TWO DEEP FOR A REASON: if BOTH TaskIdPtr and TaskName are NULL
// there is no name to put in the log line, so NASA writes a different message. Each of the four
// messages names a different missing argument, which is the difference between a readable
// syslog and four identical BAD_ARGUMENT lines.
I32 CFE_ES_CreateChildTask(U32 *TaskIdPtr, U8 *TaskName, U0 (*FunctionPtr)(), U8 *StackPtr, I64 StackSize, U16 Priority, U32 Flags)
{
  I32 ReturnCode;
  CFE_ES_AppRecord_t *AppRecPtr;
  U32 ParentAppId;
  U32 SelfTaskId;
  CFE_ES_TaskStartParams_t Params;
  ParentAppId = CFE_ES_APPID_UNDEFINED;
  MemSet(&Params, 0, sizeof(CFE_ES_TaskStartParams_t));
  Params.Priority = Priority;
  Params.StackSize = StackSize;
  Params.StackPtr = StackPtr;
  /*
  ** Validate some of the arguments
  */
  if (TaskIdPtr == NULL) {
    if (TaskName == NULL) {
      CFE_ES_WriteToSysLog("%s: Task Id and Name Pointer Parameters are NULL.\n", "CFE_ES_CreateChildTask");
      ReturnCode = CFE_ES_BAD_ARGUMENT;
    } else {
      CFE_ES_WriteToSysLog("%s: Task Id Pointer Parameter is NULL for Task '%s'.\n", "CFE_ES_CreateChildTask", TaskName);
      ReturnCode = CFE_ES_BAD_ARGUMENT;
    }
  } else if (TaskName == NULL) {
    CFE_ES_WriteToSysLog("%s: TaskName Parameter is NULL\n", "CFE_ES_CreateChildTask");
    ReturnCode = CFE_ES_BAD_ARGUMENT;
  } else if (FunctionPtr == NULL) {
    CFE_ES_WriteToSysLog("%s: Function Pointer Parameter is NULL for Task '%s'\n", "CFE_ES_CreateChildTask", TaskName);
    ReturnCode = CFE_ES_BAD_ARGUMENT;
  } else {
    /*
    ** First, Make sure the Calling Task is a cFE Main task.
    ** TaskID must be the same as the Parent Task ID.
    */
    SelfTaskId = CFE_ES_TaskId_FromOSAL(OS_TaskGetId());
    CFE_ES_LockSharedData("CFE_ES_CreateChildTask", 0);
    /*
    ** Get the App Record of the calling Application
    */
    AppRecPtr = CFE_ES_GetAppRecordByContext();
    if (AppRecPtr == NULL) {
      CFE_ES_SysLogWrite_Unsync("%s: Invalid calling context when creating Task '%s'\n", "CFE_ES_CreateChildTask", TaskName);
      ReturnCode = CFE_ES_ERR_RESOURCEID_NOT_VALID;
    } else if (!CFE_ResourceId_Equal(SelfTaskId, AppRecPtr->MainTaskId)) {
      CFE_ES_SysLogWrite_Unsync("%s: Error: Cannot call from a Child Task (for Task '%s').\n", "CFE_ES_CreateChildTask", TaskName);
      ReturnCode = CFE_ES_ERR_CHILD_TASK_CREATE;
    } else {
      ParentAppId = CFE_ES_AppRecordGetID(AppRecPtr);
      ReturnCode = CFE_SUCCESS;
    }
    /* end If AppID is valid */
    CFE_ES_UnlockSharedData("CFE_ES_CreateChildTask", 0);
  }
  /* end if parameter checking */
  /*
  ** Step 2: Create the new task if the parameter validation succeeded
  */
  if (ReturnCode == CFE_SUCCESS) {
    ReturnCode = CFE_ES_StartAppTask(TaskIdPtr, TaskName, FunctionPtr, &Params, ParentAppId);
  }
  return ReturnCode;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE ONLY ES WRITE TO SHARED DATA THAT DELIBERATELY SKIPS THE LOCK, and NASA writes out the
// whole argument: "Locking is avoided for efficiency reasons. As tasks can only increment their
// own counters, there is no risk of concurrent access to the same counter. Because the global
// data is not locked, only minimal validation is performed."
//
// "Minimal validation" means exactly the NULL check and nothing else -- note there is no
// TaskRecordIsMatch here, unlike every other function in this file. A stale record gets its
// counter bumped rather than the lock being taken.
U0 CFE_ES_IncrementTaskCounter()
{
  CFE_ES_TaskRecord_t *TaskRecPtr;
  U32 TaskID;
  /*
   * Note this locates a task record but intentionally does _not_
   * lock the global data structure.  Locking is avoided for
   * efficiency reasons.
   *
   * As tasks can only increment their own counters, there is no risk
   * of concurrent access to the same counter.
   *
   * Because the global data is not locked, only minimal validation
   * is performed.
   */
  TaskID = CFE_ES_TaskId_FromOSAL(OS_TaskGetId());
  TaskRecPtr = CFE_ES_LocateTaskRecordByID(TaskID);
  if (TaskRecPtr != NULL) {
    TaskRecPtr->ExecutionCounter++;
  }
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THREE DISTINCT FAILURES, THREE DISTINCT CODES, AND TWO DIFFERENT SYSLOG FUNCTIONS. The
// outermost "Invalid Task ID (too large)" branch is outside the lock, so it uses the locking
// CFE_ES_WriteToSysLog; everything inside uses SysLogWrite_Unsync.
//
// DELETING A MAIN TASK IS REFUSED, and the check is a full scan of the app table rather than a
// lookup -- an app's record is found by its MainTaskId, for which there is no reverse index.
I32 CFE_ES_DeleteChildTask(U32 TaskId)
{
  CFE_ES_TaskRecord_t *TaskRecPtr;
  CFE_ES_AppRecord_t *AppRecPtr;
  U32 i;
  Bool TaskIsMain;
  I32 ReturnCode = CFE_SUCCESS;
  I32 OsStatus;
  U32 OsalId;
  /*
  ** Make sure the task ID is within range
  */
  TaskRecPtr = CFE_ES_LocateTaskRecordByID(TaskId);
  if (TaskRecPtr != NULL) {
    CFE_ES_LockSharedData("CFE_ES_DeleteChildTask", 0);
    /*
    ** Make sure the task is active/valid
    */
    if (CFE_ES_TaskRecordIsMatch(TaskRecPtr, TaskId)) {
      /*
      ** Search for this task ID in the ES App Table to make sure
      ** it is not a cFE App Main Task
      */
      TaskIsMain = FALSE;
      AppRecPtr = CFE_ES_Global.AppTable;
      for (i = 0; i < CFE_PLATFORM_ES_MAX_APPLICATIONS; i++) {
        if (CFE_ES_AppRecordIsUsed(AppRecPtr)) {
          if (CFE_ResourceId_Equal(AppRecPtr->MainTaskId, TaskId)) {
            /*
            ** Error, the task Id is an App Main Task ID
            */
            TaskIsMain = TRUE;
            break;
          }
        }
        ++AppRecPtr;
      }
      if (TaskIsMain == FALSE) {
        /*
        ** Can delete the Task
        */
        OsalId = CFE_ES_TaskId_ToOSAL(TaskId);
        OsStatus = OS_TaskDelete(OsalId);
        if (OsStatus == OS_SUCCESS) {
          /*
          ** Invalidate the task table entry
          */
          CFE_ES_TaskRecordSetFree(TaskRecPtr);
          CFE_ES_Global.RegisteredTasks--;
          /*
          ** Report the task delete
          */
          CFE_ES_SysLogWrite_Unsync("%s: Task %lu Deleted\n", "CFE_ES_DeleteChildTask", TaskId);
          ReturnCode = CFE_SUCCESS;
        } else {
          CFE_ES_SysLogWrite_Unsync("%s: Error Calling OS_TaskDelete: Task %lu, RC = %ld\n", "CFE_ES_DeleteChildTask", TaskId, OsStatus);
          ReturnCode = CFE_ES_ERR_CHILD_TASK_DELETE;
        }
      } else {
        /*
        ** Error: The task is a cFE Application Main task
        */
        CFE_ES_SysLogWrite_Unsync("%s: Error: Task %lu is a cFE Main Task.\n", "CFE_ES_DeleteChildTask", TaskId);
        ReturnCode = CFE_ES_ERR_CHILD_TASK_DELETE_MAIN_TASK;
      }
      /* end if TaskMain == false */
    } else {
      /*
      ** Task ID is not in use, so it is invalid
      */
      CFE_ES_SysLogWrite_Unsync("%s: Error: Task ID is not active: %lu\n", "CFE_ES_DeleteChildTask", TaskId);
      ReturnCode = CFE_ES_ERR_RESOURCEID_NOT_VALID;
    }
    CFE_ES_UnlockSharedData("CFE_ES_DeleteChildTask", 0);
  } else {
    /*
    ** Task ID is invalid ( too large )
    */
    CFE_ES_WriteToSysLog("%s: Error: Invalid Task ID: %lu\n", "CFE_ES_DeleteChildTask", TaskId);
    ReturnCode = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  return ReturnCode;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE UNLOCK IS DUPLICATED ON THE SUCCESS PATH, because that path does not fall through to the
// bottom -- it unlocks, calls OS_TaskExit and returns. Leaving the lock held across OS_TaskExit
// would deadlock ES permanently: the task never comes back to release it.
U0 CFE_ES_ExitChildTask()
{
  CFE_ES_AppRecord_t *AppRecPtr;
  CFE_ES_TaskRecord_t *TaskRecPtr;
  CFE_ES_LockSharedData("CFE_ES_ExitChildTask", 0);
  /*
  ** Check to see if this is being called from a cFE Application's
  ** main task.
  */
  TaskRecPtr = CFE_ES_GetTaskRecordByContext();
  if (TaskRecPtr != NULL) {
    AppRecPtr = CFE_ES_LocateAppRecordByID(TaskRecPtr->AppId);
    if (CFE_ES_AppRecordIsMatch(AppRecPtr, TaskRecPtr->AppId) && !CFE_ES_TaskRecordIsMatch(TaskRecPtr, AppRecPtr->MainTaskId)) {
      /*
      ** Invalidate the task table entry
      */
      CFE_ES_TaskRecordSetFree(TaskRecPtr);
      CFE_ES_Global.RegisteredTasks--;
      CFE_ES_UnlockSharedData("CFE_ES_ExitChildTask", 0);
      /*
      ** Call the OS AL routine
      */
      OS_TaskExit();
      /*
      ** Does not return from OS_TaskExit, except under unit test
      */
      return;
    } else {
      CFE_ES_SysLogWrite_Unsync("%s: Error: Cannot Call from a cFE App Main Task. ID = %lu\n", "CFE_ES_ExitChildTask", CFE_ES_TaskRecordGetID(TaskRecPtr));
    }
  } else {
    CFE_ES_SysLogWrite_Unsync("%s: Called from invalid task context\n", "CFE_ES_ExitChildTask");
  }
  /* end if GetAppId */
  CFE_ES_UnlockSharedData("CFE_ES_ExitChildTask", 0);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE LOCKING TWIN OF CFE_ES_SysLogWrite_Unsync, and the ORDER DIFFERS FROM IT. This one
// appends under the lock and prints to the console AFTER releasing it; _Unsync prints first and
// appends second. So two threads using the two different functions can interleave their console
// output relative to their buffer order. That is NASA's, not a translation artefact.
//
// The variadic seam is the same one cfe_es_syslog.HC records: HolyC hands the callee (argc,
// argv) where NASA forwards a va_list, so va_start/va_end have no counterpart and need none.
// check_signatures.py carries CFE_ES_SysLog_vsnprintf in DEVIATIONS with that reason.
I32 CFE_ES_WriteToSysLog(U8 *SpecStringPtr,...)
{
  U8 TmpString[CFE_ES_MAX_SYSLOG_MSG_SIZE];
  I32 ReturnCode;
  if (SpecStringPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  CFE_ES_SysLog_vsnprintf(TmpString, CFE_ES_MAX_SYSLOG_MSG_SIZE, SpecStringPtr, argc, argv);
  /*
   * Append to the syslog buffer, which must be done while locked.
   * Only one thread can actively write into the buffer at time.
   */
  CFE_ES_LockSharedData("CFE_ES_WriteToSysLog", 0);
  ReturnCode = CFE_ES_SysLogAppend_Unsync(TmpString);
  CFE_ES_UnlockSharedData("CFE_ES_WriteToSysLog", 0);
  /* Output the entry to the console */
  OS_printf("%s", TmpString);
  return ReturnCode;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// A BAD POINTER RETURNS THE INPUT CRC UNCHANGED, which NASA labels "historical behavior". It is
// not an error return -- the function has no error return -- so a caller that passes NULL gets
// a plausible-looking CRC that happens to be whatever it passed in.
//
// THE DISPATCH CANNOT FAIL: "This always returns a valid object, even if it is not
// implemented". An unimplemented type gets the NONE parameters, whose algorithm returns the
// input CRC -- the same answer as the NULL case, by construction.
U32 CFE_ES_CalculateCRC(U8 *DataPtr, I64 DataLength, U32 InputCRC, U32 TypeCRC)
{
  CFE_ES_ComputeCRC_Params_t *CrcParams;
  U32 CrcResult;
  /* Protect against bad pointer input - historical behavior is to just return the input */
  if (DataPtr == NULL || DataLength == 0) {
    CrcResult = InputCRC;
  } else {
    /* This always returns a valid object, even if it is not implemented */
    CrcParams = CFE_ES_ComputeCRC_GetParams(TypeCRC);
    CrcResult = CrcParams->Algorithm(DataPtr, DataLength, InputCRC);
  }
  return CrcResult;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE APP ID IS FETCHED BEFORE THE NULL CHECK AND ITS STATUS IS CHECKED THREE BRANCHES LATER.
// That ordering is NASA's: CFE_ES_GetAppID runs first, then the arguments are validated, then
// Status is examined. It matters because the final error reporting at the bottom uses ThisAppId
// to name the app -- which is why ThisAppId is still wanted even on the "Bad AppId context"
// path, where CFE_ES_GetAppName will fail and leave AppName as the initialised "UNKNOWN".
//
// AND THAT "UNKNOWN" IS WHY THE DECLARATIONS ARE INITIALISED. NASA writes
//   char AppName[OS_MAX_API_NAME] = { "UNKNOWN" };
// a BRACED string initialiser. In this compiler the braced form silently produces garbage and
// the file-scope forms are worse -- see docs/HOLYC_STRUCT_LIMITS.md #19, measured and pinned by
// tests/exec/cases/e_char_array_string_init.hc. The local UNBRACED form below is the one
// spelling that copies the characters and zeroes the tail, so it is what is written here.
I32 CFE_ES_RegisterCDS(U32 *CDSHandlePtr, I64 BlockSize, U8 *Name)
{
  I32 Status;
  I64 NameLen;
  U32 ThisAppId;
  U8 AppName[OS_MAX_API_NAME] = "UNKNOWN";
  U8 CDSName[CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN] = "";
  /* Check to make sure calling application is legit */
  Status = CFE_ES_GetAppID(&ThisAppId);
  if (CDSHandlePtr == NULL || Name == NULL) {
    CFE_ES_WriteToSysLog("%s: Failed invalid arguments\n", "CFE_ES_RegisterCDS");
    return CFE_ES_BAD_ARGUMENT;
  }
  /* Initialize output to safe value, in case this fails */
  *CDSHandlePtr = CFE_ES_CDS_BAD_HANDLE;
  if (Status != CFE_SUCCESS)
    /* Application ID was invalid */
    {
      CFE_ES_WriteToSysLog("%s: Bad AppId context\n", "CFE_ES_RegisterCDS");
    }
  else if (!CFE_ES_Global.CDSIsAvailable) {
    CFE_ES_WriteToSysLog("%s: CDS not available\n", "CFE_ES_RegisterCDS");
    Status = CFE_ES_NOT_IMPLEMENTED;
  } else {
    /* Make sure specified CDS name is not too long or too short */
    NameLen = StrLen(Name);
    if ((NameLen > CFE_MISSION_ES_CDS_MAX_NAME_LENGTH) || (NameLen == 0)) {
      Status = CFE_ES_CDS_INVALID_NAME;
      /* Perform a buffer overrun safe copy of name for debug log message */
      StrNCpy(CDSName, Name, CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN - 1);
      CDSName[CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN - 1] = 0;
      CFE_ES_WriteToSysLog("%s: CDS Name (%s) is either too long, or an empty string\n", "CFE_ES_RegisterCDS", CDSName);
    } else {
      /* Modify specified name to be processor specific name */
      /* of the form "AppName.Name"                          */
      CFE_ES_FormCDSName(CDSName, Name, ThisAppId);
      /* Create CDS and designate it as NOT being a Critical Table */
      Status = CFE_ES_RegisterCDSEx(CDSHandlePtr, BlockSize, CDSName, FALSE);
      /* If size is unacceptable, log it */
      if (Status == CFE_ES_CDS_INVALID_SIZE) {
        CFE_ES_WriteToSysLog("%s: CDS %s has invalid size (%lu)\n", "CFE_ES_RegisterCDS", Name, BlockSize);
      }
    }
  }
  /* On Error conditions, notify ground of screw up */
  if (Status < 0) {
    /* Translate AppID of caller into App Name */
    CFE_ES_GetAppName(AppName, ThisAppId, OS_MAX_API_NAME);
    CFE_EVS_SendEventWithAppID(CFE_ES_CDS_REGISTER_ERR_EID, CFE_EVS_EventType_ERROR, ThisAppId, "%s Failed to Register CDS '%s', Status=0x%08X", AppName, Name, Status);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE CDS HAS ITS OWN LOCK, not the ES shared-data lock -- CFE_ES_LockCDS/UnlockCDS. The CDS
// registry lives in non-volatile memory behind the PSP, and holding the ES lock across a PSP
// access would block every other ES call for the duration of a flash read.
I32 CFE_ES_GetCDSBlockIDByName(U32 *BlockIdPtr, U8 *BlockName)
{
  I32 Status;
  CFE_ES_CDS_RegRec_t *RegRecPtr;
  if (BlockName == NULL || BlockIdPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  if (!CFE_ES_Global.CDSIsAvailable) {
    return CFE_ES_NOT_IMPLEMENTED;
  }
  CFE_ES_LockCDS();
  RegRecPtr = CFE_ES_LocateCDSBlockRecordByName(BlockName);
  if (RegRecPtr != NULL) {
    *BlockIdPtr = CFE_ES_CDSBlockRecordGetID(RegRecPtr);
    Status = CFE_SUCCESS;
  } else {
    *BlockIdPtr = CFE_ES_CDS_BAD_HANDLE;
    Status = CFE_ES_ERR_NAME_NOT_FOUND;
  }
  CFE_ES_UnlockCDS();
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_GetCDSBlockName(U8 *BlockName, U32 BlockId, I64 BufferLength)
{
  I32 Status;
  CFE_ES_CDS_RegRec_t *RegRecPtr;
  if (BufferLength == 0 || BlockName == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  if (!CFE_ES_Global.CDSIsAvailable) {
    return CFE_ES_NOT_IMPLEMENTED;
  }
  RegRecPtr = CFE_ES_LocateCDSBlockRecordByID(BlockId);
  CFE_ES_LockCDS();
  if (CFE_ES_CDSBlockRecordIsMatch(RegRecPtr, BlockId)) {
    StrNCpy(BlockName, RegRecPtr->Name, BufferLength - 1);
    BlockName[BufferLength - 1] = 0;
    Status = CFE_SUCCESS;
  } else {
    BlockName[0] = 0;
    Status = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  CFE_ES_UnlockCDS();
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// NOTE WHAT IS NOT CHECKED: the block SIZE. Neither of these two knows how big the caller's
// buffer is -- the size was fixed when the block was registered, and CDSBlockWrite/Read get it
// from the registry. A caller that passes a smaller buffer than it registered reads or writes
// past it, and nothing here can tell.
I32 CFE_ES_CopyToCDS(U32 Handle, U8 *DataToCopy)
{
  if (DataToCopy == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  return CFE_ES_CDSBlockWrite(Handle, DataToCopy);
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_RestoreFromCDS(U8 *RestoreToMemory, U32 Handle)
{
  if (RestoreToMemory == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  return CFE_ES_CDSBlockRead(RestoreToMemory, Handle);
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE OUTPUT IS WRITTEN AFTER THE UNLOCK AND ON EVERY PATH, including the duplicate-name and
// no-slots failures -- which is why PendingResourceId is set to CFE_RESOURCEID_UNDEFINED in the
// duplicate branch. The no-slots branch does not set it, because FindNext already returned
// UNDEFINED, which is exactly why CountRecPtr came back NULL.
//
// THE NAME LENGTH IS CHECKED WITH >=, NOT >: a name that exactly fills the field would leave no
// room for the terminator.
I32 CFE_ES_RegisterGenCounter(U32 *CounterIdPtr, U8 *CounterName)
{
  CFE_ES_GenCounterRecord_t *CountRecPtr;
  U32 PendingResourceId;
  I32 Status;
  if (CounterName == NULL || CounterIdPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  if (StrLen(CounterName) >= OS_MAX_API_NAME) {
    return CFE_ES_BAD_ARGUMENT;
  }
  CFE_ES_LockSharedData("CFE_ES_RegisterGenCounter", 0);
  /*
   * Check for an existing entry with the same name.
   */
  CountRecPtr = CFE_ES_LocateCounterRecordByName(CounterName);
  if (CountRecPtr != NULL) {
    CFE_ES_SysLogWrite_Unsync("%s: Duplicate Counter name '%s'\n", "CFE_ES_RegisterGenCounter", CounterName);
    Status = CFE_ES_ERR_DUPLICATE_NAME;
    PendingResourceId = CFE_RESOURCEID_UNDEFINED;
  } else {
    /* scan for a free slot */
    PendingResourceId = CFE_ResourceId_FindNext(CFE_ES_Global.LastCounterId, CFE_PLATFORM_ES_MAX_GEN_COUNTERS, CFE_ES_CheckCounterIdSlotUsed);
    CountRecPtr = CFE_ES_LocateCounterRecordByID(PendingResourceId);
    if (CountRecPtr == NULL) {
      CFE_ES_SysLogWrite_Unsync("%s: No free Counter slots available\n", "CFE_ES_RegisterGenCounter");
      Status = CFE_ES_NO_RESOURCE_IDS_AVAILABLE;
    } else {
      StrNCpy(CountRecPtr->CounterName, CounterName, OS_MAX_API_NAME - 1);
      CountRecPtr->CounterName[OS_MAX_API_NAME - 1] = 0;
      CountRecPtr->Counter = 0;
      CFE_ES_CounterRecordSetUsed(CountRecPtr, PendingResourceId);
      CFE_ES_Global.LastCounterId = PendingResourceId;
      Status = CFE_SUCCESS;
    }
  }
  CFE_ES_UnlockSharedData("CFE_ES_RegisterGenCounter", 0);
  *CounterIdPtr = PendingResourceId;
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE DEFAULT RETURN IS BAD_ARGUMENT, NOT SUCCESS, which is how a NULL record and a non-matching
// record end up returning the same thing without either branch saying so. Delete is the only
// one of the four counter functions that checks the Locate result for NULL -- Increment and
// SetGenCount below pass it straight to IsMatch, which must therefore tolerate NULL.
I32 CFE_ES_DeleteGenCounter(U32 CounterId)
{
  CFE_ES_GenCounterRecord_t *CountRecPtr;
  I32 Status = CFE_ES_BAD_ARGUMENT;
  CountRecPtr = CFE_ES_LocateCounterRecordByID(CounterId);
  if (CountRecPtr != NULL) {
    CFE_ES_LockSharedData("CFE_ES_DeleteGenCounter", 0);
    if (CFE_ES_CounterRecordIsMatch(CountRecPtr, CounterId)) {
      CountRecPtr->Counter = 0;
      CFE_ES_CounterRecordSetFree(CountRecPtr);
      Status = CFE_SUCCESS;
    }
    CFE_ES_UnlockSharedData("CFE_ES_DeleteGenCounter", 0);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_IncrementGenCounter(U32 CounterId)
{
  I32 Status = CFE_ES_BAD_ARGUMENT;
  CFE_ES_GenCounterRecord_t *CountRecPtr;
  CountRecPtr = CFE_ES_LocateCounterRecordByID(CounterId);
  CFE_ES_LockSharedData("CFE_ES_IncrementGenCounter", 0);
  if (CFE_ES_CounterRecordIsMatch(CountRecPtr, CounterId)) {
    ++CountRecPtr->Counter;
    Status = CFE_SUCCESS;
  }
  CFE_ES_UnlockSharedData("CFE_ES_IncrementGenCounter", 0);
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_SetGenCount(U32 CounterId, U32 Count)
{
  I32 Status = CFE_ES_BAD_ARGUMENT;
  CFE_ES_GenCounterRecord_t *CountRecPtr;
  CountRecPtr = CFE_ES_LocateCounterRecordByID(CounterId);
  CFE_ES_LockSharedData("CFE_ES_SetGenCount", 0);
  if (CFE_ES_CounterRecordIsMatch(CountRecPtr, CounterId)) {
    CountRecPtr->Counter = Count;
    Status = CFE_SUCCESS;
  }
  CFE_ES_UnlockSharedData("CFE_ES_SetGenCount", 0);
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THIS ONE TAKES NO LOCK and the other three counter accessors do. Reading a U32 is atomic on
// this target, so the value cannot be torn -- but the IsMatch and the read are not atomic
// together, so a counter deleted between them is read anyway. NASA accepts that; it is the same
// trade CFE_ES_IncrementTaskCounter makes explicitly.
//
// NOTE THE ORDER OF THE &&: IsMatch runs BEFORE the NULL check on Count. A NULL Count with a
// valid id still costs the match.
I32 CFE_ES_GetGenCount(U32 CounterId, U32 *Count)
{
  I32 Status = CFE_ES_BAD_ARGUMENT;
  CFE_ES_GenCounterRecord_t *CountRecPtr;
  CountRecPtr = CFE_ES_LocateCounterRecordByID(CounterId);
  if (CFE_ES_CounterRecordIsMatch(CountRecPtr, CounterId) && Count != NULL) {
    *Count = CountRecPtr->Counter;
    Status = CFE_SUCCESS;
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_GetGenCounterIDByName(U32 *CounterIdPtr, U8 *CounterName)
{
  CFE_ES_GenCounterRecord_t *CounterRecPtr;
  I32 Result;
  if (CounterName == NULL || CounterIdPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  /*
  ** Search the ES Generic Counter table for a counter with a matching name.
  */
  CFE_ES_LockSharedData("CFE_ES_GetGenCounterIDByName", 0);
  CounterRecPtr = CFE_ES_LocateCounterRecordByName(CounterName);
  if (CounterRecPtr == NULL) {
    /*
     * ensure the output value is set to a safe value,
     * in case the caller does not check the return code.
     */
    Result = CFE_ES_ERR_NAME_NOT_FOUND;
    *CounterIdPtr = CFE_ES_COUNTERID_UNDEFINED;
  } else {
    Result = CFE_SUCCESS;
    *CounterIdPtr = CFE_ES_CounterRecordGetID(CounterRecPtr);
  }
  CFE_ES_UnlockSharedData("CFE_ES_GetGenCounterIDByName", 0);
  return Result;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_GetGenCounterName(U8 *CounterName, U32 CounterId, I64 BufferLength)
{
  CFE_ES_GenCounterRecord_t *CountRecPtr;
  I32 Status;
  if (BufferLength == 0 || CounterName == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  CountRecPtr = CFE_ES_LocateCounterRecordByID(CounterId);
  CFE_ES_LockSharedData("CFE_ES_GetGenCounterName", 0);
  if (CFE_ES_CounterRecordIsMatch(CountRecPtr, CounterId)) {
    StrNCpy(CounterName, CFE_ES_CounterRecordGetName(CountRecPtr), BufferLength - 1);
    CounterName[BufferLength - 1] = 0;
    Status = CFE_SUCCESS;
  } else {
    CounterName[0] = 0;
    Status = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  CFE_ES_UnlockSharedData("CFE_ES_GetGenCounterName", 0);
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE FOUR INDEX CONVERSIONS, AND THE TASK ONE IS NOT LIKE THE OTHER THREE. App, lib and
// counter ids are ES's own, so each subtracts its own base and bounds-checks against its own
// table size. A TASK id is an OSAL id wearing a cFE wrapper, so its index has to come from
// OSAL -- there is no base to subtract, and OS_ObjectIdToArrayIndex is the only thing that
// knows the mapping.
//
// THIS IS THE FUNCTION PAIR THAT BROKE THE PROBES. While api.c was stubbed, the driver's
// *_ToIndex stubs were `id & 0xFF`, which accepts a bare 1 or 2. The real ones below do not:
// CFE_ResourceId_ToIndex subtracts CFE_ES_APPID_BASE first, so a bare small integer is out of
// range and returns CFE_ES_ERR_RESOURCEID_NOT_VALID. Exactly the break
// CFE_SB_PipeId_ToIndex caused when it stopped being a mask.
I32 CFE_ES_AppID_ToIndex(U32 AppID, U32 *Idx)
{
  return CFE_ResourceId_ToIndex(AppID, CFE_ES_APPID_BASE, CFE_PLATFORM_ES_MAX_APPLICATIONS, Idx);
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_LibID_ToIndex(U32 LibId, U32 *Idx)
{
  return CFE_ResourceId_ToIndex(LibId, CFE_ES_LIBID_BASE, CFE_PLATFORM_ES_MAX_LIBRARIES, Idx);
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_TaskID_ToIndex(U32 TaskID, U32 *Idx)
{
  U32 OsalID;
  U32 OsalIndex = 0;
  I32 OsStatus;
  if (!CFE_ResourceId_IsDefined(TaskID)) {
    return CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  if (Idx == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  OsalID = CFE_ES_TaskId_ToOSAL(TaskID);
  OsStatus = OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_TASK, OsalID, &OsalIndex);
  if (OsStatus != OS_SUCCESS) {
    return CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  *Idx = OsalIndex;
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_CounterID_ToIndex(U32 CounterId, U32 *Idx)
{
  return CFE_ResourceId_ToIndex(CounterId, CFE_ES_COUNTID_BASE, CFE_PLATFORM_ES_MAX_GEN_COUNTERS, Idx);
}
/***************************************************************************************
** Private API functions
*/
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE LOCK FAILURE PATH IS KNOWINGLY UNSOUND, and NASA says so in as many words: "NOTE: this is
// going to write into a buffer that itself is _supposed_ to be protected by this same mutex."
// There is nowhere else to report it from -- the syslog IS the reporting channel -- so the
// failure to take the lock is recorded by writing, unlocked, into the thing the lock protects.
//
// THE FUNCTION RETURNS VOID. A caller cannot find out that the lock was not taken; it proceeds
// to touch shared data regardless. Every CFE_ES_LockSharedData call site in this translation
// therefore has the same property as NASA's.
//
// FunctionName AND LineNumber ARE PURELY DIAGNOSTIC, which is why this port passes the function
// name as a literal and 0 for the line: HolyC has no __func__ or __LINE__, and a line number
// from the translated file would be a number NASA's source does not have. The differential
// oracle compares the transcript, so any call that can reach this message passes the same name
// on both sides and the line is 0 on both.
U0 CFE_ES_LockSharedData(U8 *FunctionName, I32 LineNumber)
{
  I32 OsStatus;
  OsStatus = OS_MutSemTake(CFE_ES_Global.SharedDataMutex);
  if (OsStatus != OS_SUCCESS) {
    /*
     * NOTE: this is going to write into a buffer that itself
     * is _supposed_ to be protected by this same mutex.
     */
    CFE_ES_SysLogWrite_Unsync("%s: SharedData Mutex Take Err Stat=%ld,Func=%s,Line=%d\n", "CFE_ES_LockSharedData", OsStatus, FunctionName, LineNumber);
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_ES_UnlockSharedData(U8 *FunctionName, I32 LineNumber)
{
  I32 OsStatus;
  OsStatus = OS_MutSemGive(CFE_ES_Global.SharedDataMutex);
  if (OsStatus != OS_SUCCESS) {
    /*
     * NOTE: this is going to write into a buffer that itself
     * is _supposed_ to be protected by this same mutex.
     */
    CFE_ES_SysLogWrite_Unsync("%s: SharedData Mutex Give Err Stat=%ld,Func=%s,Line=%d\n", "CFE_ES_UnlockSharedData", OsStatus, FunctionName, LineNumber);
  }
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// AN EXCEPTION HANDLER CALLS THIS, which is why it does nothing but a wakeup: it may be running
// in an interrupt or exception context where the syslog mutex cannot be taken.
U0 CFE_ES_ProcessAsyncEvent()
{
  /* This just wakes up the background task to log/handle the event. */
  CFE_ES_BackgroundWakeup();
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// NASA's status_string is a `CFE_StatusString_t *`, a POINTER TO AN ARRAY of
// CFE_STATUS_STRING_LENGTH chars -- so `*status_string` is the array, `sizeof(*status_string)`
// is 11, and the returned `string` is that same buffer. HolyC has no pointer-to-array type, so
// the parameter is a U8 * to the caller's buffer and the size is the constant NASA's sizeof
// resolves to. The return value is the caller's own buffer either way.
//
// THE FORMAT IS %08x ON A SIGNED STATUS cast to unsigned int -- so 0xC4000014 prints as eight
// digits and an eleven-byte buffer holds "0x" + 8 + the terminator exactly.
U8 *CFE_ES_StatusToString(I32 status, U8 *status_string)
{
  U8 *string = NULL;
  if (status_string != NULL) {
    StrPrintN(status_string, CFE_STATUS_STRING_LENGTH, "0x%08x", status);
    string = status_string;
  }
  return string;
}
