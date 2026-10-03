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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_backgroundtask.c -- COOPERATIVE
// MULTITASKING FOR WORK THAT CAN WAIT.
//
// Five functions and a table. NASA's description of the contract is the thing to read first:
// "This uses 'cooperative multitasking' -- the function should do some limited work, then
// return to the background task. It will be called again after a delay period to do more
// work." Each job returns TRUE if it is still active and FALSE if it is idle, and the
// background task picks its next delay from the shortest period any job asked for.
//
// SO THE TABLE IS THE SCHEDULER. There is no priority, no preemption and no queue: seven
// entries, each with a function and two periods, walked in order, forever.
//
// THREE OF THE SEVEN ENTRIES EXIST ONLY FOR COVERAGE, and NASA says so at each one -- a NULL
// RunFunc, an active job with a zero ActivePeriod, and an active job whose ActivePeriod is one
// less than the delay the previous entry set. They are not dead weight to be tidied away: they
// are how the three branches of the inner loop are reached. CFE_ES_ActiveJob exists for the
// same reason and has the same comment.
//
// THIS FILE INCLUDES NOTHING. docs/HOLYC_STRUCT_LIMITS.md #13.
//
// REQUIRED INCLUDE ORDER, which the driver provides:
//     cfe_es_global.HC   CFE_ES_Global.BackgroundTask and the two job argument states
//     cfe_es_api.HC      WriteToSysLog, CreateChildTask, DeleteChildTask
//     cfe_fs_api.HC      CFE_FS_RunBackgroundFileDump, which is job four
//     cfe_es_erlog.HC    CFE_ES_RunExceptionScan, which is job three
#ifndef CFE_ES_BACKGROUNDTASK_HC
#define CFE_ES_BACKGROUNDTASK_HC
#define CFE_ES_BACKGROUND_SEM_NAME   "ES_BG_SEM"
#define CFE_ES_BACKGROUND_CHILD_NAME "ES_BG_TASK"
// CFE_ES_TASK_STACK_ALLOCATE is NULL -- NASA's comment is "aka OS_TASK_STACK_ALLOCATE in
// proposed OSAL change", i.e. "let the OS pick the stack".
#define CFE_ES_BACKGROUND_CHILD_STACK_PTR  NULL
#define CFE_ES_BACKGROUND_CHILD_STACK_SIZE CFE_PLATFORM_ES_PERF_CHILD_STACK_SIZE
#define CFE_ES_BACKGROUND_CHILD_PRIORITY   CFE_PLATFORM_ES_PERF_CHILD_PRIORITY
#define CFE_ES_BACKGROUND_CHILD_FLAGS      0
#define CFE_ES_BACKGROUND_MAX_IDLE_DELAY   30000 /* 30 seconds */
// --- cfe_es_internal_cfg.h -------------------------------------------------------------------
#ifndef CFE_PLATFORM_ES_APP_SCAN_RATE
#define CFE_PLATFORM_ES_APP_SCAN_RATE          1000
#endif
#define CFE_PLATFORM_ES_PERF_CHILD_PRIORITY    200
#define CFE_PLATFORM_ES_PERF_CHILD_STACK_SIZE  4096
#define CFE_PLATFORM_ES_PERF_CHILD_MS_DELAY    20
// --- osapi-error.h ---------------------------------------------------------------------------
// The TIMEOUT is the NORMAL outcome of the background task's wait, not an error -- see the
// condition in CFE_ES_BackgroundTask -- so it has to be nameable here.
#ifndef OS_SEM_TIMEOUT
#define OS_SEM_TIMEOUT -7
#endif
// --- what this file needs from elsewhere -----------------------------------------------------
// Jobs one and two are REAL now -- cfe_es_appctrl.c and cfe_es_perf.c are both gated, and both
// are included before this file so that the table below can take their addresses. The two
// declarations stay because this file must still parse on its own.
Bool CFE_ES_RunAppTableScan(U32 ElapsedTime, U8 *Arg);
Bool CFE_ES_RunPerfLogDump(U32 ElapsedTime, U8 *Arg);
class CFE_ES_BackgroundJobEntry_t
{
  Bool (*RunFunc)(U32 ElapsedTime, U8 *Arg);
  U8 *JobArg;
  U32 ActivePeriod;
  // max wait/delay time between calls when job is active
  U32 IdlePeriod;
  // max wait/delay time between calls when job is idle
  // NO TRAILING PAD: the two U32s together fill the last 8-byte slot after the two pointers,
  // so the struct is already 24 and a multiple of its own alignment. check_padding said so --
  // the first version carried a _pad0[4] by habit and came out 28 against NASA's 24.
};
/** @brief function that returns true. Used for purposes of improving coverage
 * in testing of function CFE_ES_BackgroundTask (located in this file)
 */
Bool CFE_ES_ActiveJob(U32 ElapsedTime, U8 *Arg)
{
  return TRUE;
}
/*
 * List of "background jobs"
 *
 * This is just a list of functions to periodically call from the context of the background
 * task, and can be added/extended as needed.
 *
 * Each Job function returns a boolean, and should return "true" if it is active, or "false" if
 * it is idle.
 *
 * This uses "cooperative multitasking" -- the function should do some limited work, then
 * return to the background task.  It will be called again after a delay period to do more
 * work.
 */
// POSITIONAL, BECAUSE HOLYC HAS NO DESIGNATED INITIALISERS. NASA writes `.RunFunc =` and so on;
// the field order here is RunFunc, JobArg, ActivePeriod, IdlePeriod. check_padding measures the class against
// NASA's layout, which is what keeps that order honest.
CFE_ES_BackgroundJobEntry_t CFE_ES_BACKGROUND_JOB_TABLE[7] = { /* ES app table background scan */{&CFE_ES_RunAppTableScan, &CFE_ES_Global.BackgroundAppScanState, CFE_PLATFORM_ES_APP_SCAN_RATE / 4, CFE_PLATFORM_ES_APP_SCAN_RATE}, /* Performance Log Data Dump to file */{&CFE_ES_RunPerfLogDump, &CFE_ES_Global.BackgroundPerfDumpState, CFE_PLATFORM_ES_PERF_CHILD_MS_DELAY, CFE_PLATFORM_ES_PERF_CHILD_MS_DELAY * 1000}, /* Check for exceptions stored in the PSP */{&CFE_ES_RunExceptionScan, NULL, CFE_PLATFORM_ES_APP_SCAN_RATE, CFE_PLATFORM_ES_APP_SCAN_RATE}, /* Call FS to handle background file writes */{&CFE_FS_RunBackgroundFileDump, NULL, CFE_PLATFORM_ES_APP_SCAN_RATE, CFE_PLATFORM_ES_APP_SCAN_RATE}, /* Empty Job (for coverage purposes) */ /* Setting RunFunc to NULL triggers JobPtr->RunFunc != NULL to be false */{NULL, NULL, 0, 0}, /* Active Job with 0 active period (for coverage purposes)*/ /* Setting ActivePeriod to 0 triggers JobPtr->ActivePeriod != 0 to be false */{&CFE_ES_ActiveJob, NULL, 0, 0}, /* Active Job with non-zero active period (for coverage purposes)*/ /* We set the ActivePeriod to this so we can trigger set the expression
     * NextDelay > JobPtr->ActivePeriod to be false, since the previous
     * setting for NextDelay was CFE_PLATFORM_ES_APP_SCAN_RATE */{&CFE_ES_ActiveJob, NULL, CFE_PLATFORM_ES_APP_SCAN_RATE - 1, 0}};
// DERIVED FROM THE TABLE, exactly as NASA derives it, rather than written down as 7. The two
// then cannot disagree: an eighth entry changes both at once. It also means neither side is a
// literal, so check_constants.py files it in its "not a literal and so NOT compared" bucket --
// which it reports as a number -- rather than comparing two hand-written sevens.
#define CFE_ES_BACKGROUND_NUM_JOBS \
  (sizeof(CFE_ES_BACKGROUND_JOB_TABLE) / sizeof(CFE_ES_BackgroundJobEntry_t))
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE ONLY WAY OUT IS A SEMAPHORE ERROR THAT IS NOT A TIMEOUT, and NASA's comment on it is
// "should never occur". A timeout is the NORMAL case -- it is how the delay happens -- so the
// condition has to name both, and the task runs until something is genuinely wrong.
//
// THE ELAPSED TIME IS MEASURED ACROSS THE WHOLE PASS, including however long the jobs took,
// which is what makes a job that overruns its period visible to the next one rather than
// silently stretching the schedule.
U0 CFE_ES_BackgroundTask()
{
  I32 OsStatus;
  U32 JobTotal;
  U32 NumJobsRunning;
  U32 NextDelay;
  U32 ElapsedTime;
  OS_time_t CurrTime;
  OS_time_t LastTime;
  CFE_ES_BackgroundJobEntry_t *JobPtr;
  MemSet(&LastTime, 0, sizeof(OS_time_t));
  MemSet(&CurrTime, 0, sizeof(OS_time_t));
  CFE_PSP_GetTime(&LastTime);
  while (TRUE) {
    /*
     * compute the elapsed time (difference) between last
     * execution and now, in milliseconds.
     */
    CFE_PSP_GetTime(&CurrTime);
    ElapsedTime = OS_TimeGetTotalMilliseconds(OS_TimeSubtract(CurrTime, LastTime));
    LastTime = CurrTime;
    NextDelay = CFE_ES_BACKGROUND_MAX_IDLE_DELAY;
    /* default; will be adjusted based on active jobs */
    JobPtr = CFE_ES_BACKGROUND_JOB_TABLE;
    JobTotal = CFE_ES_BACKGROUND_NUM_JOBS;
    NumJobsRunning = 0;
    while (JobTotal > 0) {
      /*
       * call the background job -
       * if it returns "true" that means it is active,
       * if it returns "false" that means it is idle
       */
      if (JobPtr->RunFunc != NULL && JobPtr->RunFunc(ElapsedTime, JobPtr->JobArg)) {
        ++NumJobsRunning;
        if (JobPtr->ActivePeriod != 0 && NextDelay > JobPtr->ActivePeriod) {
          /* next delay is based on this active job wait time */
          NextDelay = JobPtr->ActivePeriod;
        }
      } else if (JobPtr->IdlePeriod != 0 && NextDelay > JobPtr->IdlePeriod) {
        /* next delay is based on this idle job wait time */
        NextDelay = JobPtr->IdlePeriod;
      }
      --JobTotal;
      ++JobPtr;
    }
    CFE_ES_Global.BackgroundTask.NumJobsRunning = NumJobsRunning;
    OsStatus = OS_BinSemTimedWait(CFE_ES_Global.BackgroundTask.WorkSem, NextDelay);
    if (OsStatus != OS_SUCCESS && OsStatus != OS_SEM_TIMEOUT) {
      /* should never occur */
      CFE_ES_WriteToSysLog("%s: Failed to take background sem: %ld\n", "CFE_ES_BackgroundTask", OsStatus);
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
// THE SEMAPHORE STARTS AT ZERO, which is what makes OS_BinSemTimedWait a DELAY rather than a
// lock: nothing holds it, so the wait always times out unless CFE_ES_BackgroundWakeup gives it.
I32 CFE_ES_BackgroundInit()
{
  I32 status;
  I32 OsStatus;
  OsStatus = OS_BinSemCreate(&CFE_ES_Global.BackgroundTask.WorkSem, CFE_ES_BACKGROUND_SEM_NAME, 0, 0);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Failed to create background sem: %ld\n", "CFE_ES_BackgroundInit", OsStatus);
    return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  }
  /* Spawn a task to write the performance data to a file */
  status = CFE_ES_CreateChildTask(&CFE_ES_Global.BackgroundTask.TaskID, CFE_ES_BACKGROUND_CHILD_NAME, &CFE_ES_BackgroundTask, CFE_ES_BACKGROUND_CHILD_STACK_PTR, CFE_ES_BACKGROUND_CHILD_STACK_SIZE, CFE_ES_BACKGROUND_CHILD_PRIORITY, CFE_ES_BACKGROUND_CHILD_FLAGS);
  if (status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Failed to create background task: %08lx\n", "CFE_ES_BackgroundInit", status);
    return status;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_ES_BackgroundCleanup()
{
  CFE_ES_DeleteChildTask(CFE_ES_Global.BackgroundTask.TaskID);
  OS_BinSemDelete(CFE_ES_Global.BackgroundTask.WorkSem);
  CFE_ES_Global.BackgroundTask.TaskID = CFE_ES_TASKID_UNDEFINED;
  CFE_ES_Global.BackgroundTask.WorkSem = OS_OBJECT_ID_UNDEFINED;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// IT IGNORES THE RETURN, and NASA explains: "This is 'informational' and not strictly
// required, but it will make the task immediately wake up and check for new work if it was
// idle." A give that fails costs at most one delay period of latency.
U0 CFE_ES_BackgroundWakeup()
{
  /* wake up the background task by giving the sem.
   * This is "informational" and not strictly required,
   * but it will make the task immediately wake up and check for new
   * work if it was idle. */
  OS_BinSemGive(CFE_ES_Global.BackgroundTask.WorkSem);
}
#endif
