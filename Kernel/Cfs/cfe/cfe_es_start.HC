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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_start.c -- THE BOOT SEQUENCE. This is
// cFE's main(): everything else in the framework exists because this function called it.
//
// Eight functions, and CFE_ES_Main is the spine. It walks the system through five states in
// order, writing each transition to the system log, and the order is the whole design:
//
//     EARLY_INIT    the shared-data mutex, the reset area, the perf log, the file systems
//     CORE_STARTUP  CFE_ES_CreateObjects -- every core module's EarlyInit, then its task
//     CORE_READY    the startup script runs, so external apps begin loading
//     APPS_INIT     wait for every app to reach at least LATE_INIT
//     OPERATIONAL   wait for every app to reach RUNNING
//
// THE FIRST THING IT DOES IS CREATE A MUTEX, AND THE COMMENT SAYS WHY: "This must be done
// before ANY calls to CFE_ES_WriteToSysLog(), since this uses the mutex." Before that line
// there is no way to report anything, which is why the failure path uses OS_printf and then
// panics -- NASA's note at the reset-area setup makes the same point: "Any logging in here must
// use CFE_ES_SysLogWrite_Unsync() as the necessary primitives are not even initialized yet."
//
// A PANIC IS THE ONLY FAILURE MODE IN HERE. Five of the eight functions call CFE_PSP_Panic, and
// every one of them first does OS_TaskDelay(CFE_ES_PANIC_DELAY) with the comment "Delay to
// allow the message to be read" -- half a second for a console nobody may be watching. After
// the panic every one of them `return`s, and NASA says why: "Normally CFE_PSP_Panic() will not
// return but it will under UT." This driver is that case.
//
// NOT EVERYTHING STARTING UP IS NOT FATAL, which is the other half of the policy and is stated
// twice: "if not everything starts up, that is not a fatal error, we will continue anyway since
// the core apps are OK and control/telemetry should function. The problem app could be
// deleted/restarted/etc by the ground station." So a timed-out sync is a log line, not a halt.
//
// CFE_ES_Global ITSELF IS DEFINED UPSTREAM IN THIS FILE. The translation defines it in
// cfe_es_global.HC beside its type, for the reason that file records: a global whose definition
// sits in whichever implementation file happened to be translated first moves when that
// changes. So this file does not define it, and that is the one structural difference.
//
// THIS FILE INCLUDES NOTHING. docs/HOLYC_STRUCT_LIMITS.md #13.
//
// REQUIRED INCLUDE ORDER, which the driver provides:
//     cfe_es_global.HC    CFE_ES_Global and every record table it initialises
//     cfe_es_resource.HC  the id bases and the slot predicates
//     cfe_es_api.HC       the locks
//     cfe_es_erlog.HC     CFE_ES_WriteToERLog, which the reset paths log through
//     cfe_es_perf.HC      CFE_ES_SetupPerfVariables
//     cfe_es_apps.HC      CFE_ES_StartAppTask, for the core apps
//     cfe_es_startupscript.HC  CFE_ES_StartApplications
//     ../osal/osapi_filesys_decl.HC  OS_statvfs_t, for the free-space check
#ifndef CFE_ES_START_HC
#define CFE_ES_START_HC
// --- cfe_es_start.c's own ---------------------------------------------------------------------
// Half a second, and it is always followed by a panic: "Delay to allow the message to be read."
#define CFE_ES_PANIC_DELAY 500
// --- cfe_psp.h: the panic codes ---------------------------------------------------------------
#ifndef CFE_PSP_PANIC_VOLATILE_DISK
#define CFE_PSP_PANIC_VOLATILE_DISK 2
#endif
#ifndef CFE_PSP_PANIC_CORE_APP
#define CFE_PSP_PANIC_CORE_APP 6
#endif
// --- cfe_es_internal_cfg.h --------------------------------------------------------------------
#ifndef CFE_PLATFORM_ES_RAM_DISK_SECTOR_SIZE
#define CFE_PLATFORM_ES_RAM_DISK_SECTOR_SIZE 512
#endif
#ifndef CFE_PLATFORM_ES_RAM_DISK_NUM_SECTORS
#define CFE_PLATFORM_ES_RAM_DISK_NUM_SECTORS 4096
#endif
#ifndef CFE_PLATFORM_ES_RAM_DISK_MOUNT_STRING
#define CFE_PLATFORM_ES_RAM_DISK_MOUNT_STRING "/ram"
#endif
// ZERO DISABLES THE CHECK, which NASA states at the call site: "When
// CFE_PLATFORM_ES_RAM_DISK_PERCENT_RESERVED is set to 0, this feature is disabled."
#ifndef CFE_PLATFORM_ES_RAM_DISK_PERCENT_RESERVED
#define CFE_PLATFORM_ES_RAM_DISK_PERCENT_RESERVED 30
#endif
#ifndef CFE_PLATFORM_ES_MAX_PROCESSOR_RESETS
#define CFE_PLATFORM_ES_MAX_PROCESSOR_RESETS 2
#endif
// --- cfe_es_extern_typedefs.h: the five system states -----------------------------------------
#ifndef CFE_ES_SystemState_EARLY_INIT
#define CFE_ES_SystemState_EARLY_INIT 1
#endif
#ifndef CFE_ES_SystemState_CORE_STARTUP
#define CFE_ES_SystemState_CORE_STARTUP 2
#endif
#ifndef CFE_ES_SystemState_CORE_READY
#define CFE_ES_SystemState_CORE_READY 3
#endif
#ifndef CFE_ES_SystemState_APPS_INIT
#define CFE_ES_SystemState_APPS_INIT 4
#endif
#ifndef CFE_ES_SystemState_OPERATIONAL
#define CFE_ES_SystemState_OPERATIONAL 5
#endif
// --- cfe_psp.h: the reset subtypes this file distinguishes -------------------------------------
#ifndef CFE_PSP_RST_SUBTYPE_POWER_CYCLE
#define CFE_PSP_RST_SUBTYPE_POWER_CYCLE 1
#endif
#ifndef CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND
#define CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND 3
#endif
#ifndef CFE_PSP_RST_SUBTYPE_HW_WATCHDOG
#define CFE_PSP_RST_SUBTYPE_HW_WATCHDOG 4
#endif
// --- what this file needs from elsewhere ------------------------------------------------------
// The PSP, and both of these are the BOARD. CFE_PSP_AttachExceptions installs the trap vectors
// -- NASA's own comment at the call is "Install exception Handlers ( Placeholder )" -- and
// CFE_PSP_GetVolatileDiskMem hands back the RAM the volatile file system is built in.
U0 CFE_PSP_AttachExceptions();
I32 CFE_PSP_GetVolatileDiskMem(U64 *PtrToVolDisk, U32 *SizeOfVolDisk);
// Defined later in this file, and CFE_ES_Main calls all of them.
U0 CFE_ES_SetupResetVariables(U32 StartType, U32 StartSubtype, U32 BootSource);
U0 CFE_ES_InitializeFileSystems(U32 StartType);
U0 CFE_ES_CreateObjects();
I32 CFE_ES_MainTaskSyncDelay(U32 AppStateId, U32 TimeOutMilliseconds);
U0 CFE_ES_InitializeFileSystems_ReformatVolume(U64 RamDiskMemoryAddress, U8 *LogFunction);

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE WHOLE GLOBAL IS ZEROED FIRST, and NASA's comment explains what that buys: "This also
// takes care of setting all resource IDs on all table entries to be 'undefined' (not in use)."
// Every table in ES is free because zero is not a valid resource id -- there is no init loop.
//
// THE FOUR LastXxxId FIELDS ARE SET AFTER the file systems are up and before CreateObjects,
// because the id allocators walk FORWARD from them and the core apps are the first things to
// take ids.
U0 CFE_ES_Main(U32 StartType, U32 StartSubtype, U32 ModeId, U8 *StartFilePath)
{
  I32 OsStatus;
  /*
   * Clear the entire global data structure.
   * This also takes care of setting all resource IDs on all table entries
   * to be "undefined" (not in use).
   */
  MemSet(&CFE_ES_Global, 0, sizeof(CFE_ES_Global_t));
  /*
  ** Indicate that the CFE is the earliest initialization state
  */
  CFE_ES_Global.SystemState = CFE_ES_SystemState_EARLY_INIT;
  /*
  ** Create the ES Shared Data Mutex
  ** This must be done before ANY calls to CFE_ES_WriteToSysLog(), since this uses the mutex
  */
  OsStatus = OS_MutSemCreate(&CFE_ES_Global.SharedDataMutex, "ES_DATA_MUTEX", 0);
  if (OsStatus != OS_SUCCESS) {
    /* Cannot use SysLog here, since that requires the reset area to be set up */
    OS_printf("ES Startup: Error: ES Shared Data Mutex could not be created. RC=%ld\n", OsStatus);
    /*
    ** Delay to allow the message to be printed
    */
    OS_TaskDelay(CFE_ES_PANIC_DELAY);
    /*
    ** cFE Cannot continue to start up.
    */
    CFE_PSP_Panic(CFE_PSP_PANIC_STARTUP_SEM);
    /*
     * Normally CFE_PSP_Panic() will not return but it will under UT
     */
    return;
  }
  /*
  ** Initialize the Reset variables. This call is required
  ** Before most of the ES functions can be used including the
  ** ES System log.
  */
  CFE_ES_SetupResetVariables(StartType, StartSubtype, ModeId);
  /*
  ** Initialize the Logic Perf variables
  ** Because this is in the ES Reset area, it must be called after
  ** CFE_ES_SetupResetVariables.
  */
  CFE_ES_SetupPerfVariables(StartType);
  /*
  ** Also Create the ES Performance Data Mutex
  ** This is to separately protect against concurrent writes to the global performance log data
  */
  OsStatus = OS_MutSemCreate(&CFE_ES_Global.PerfDataMutex, "ES_PERF_MUTEX", 0);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_SysLogWrite_Unsync("%s: Error: ES Performance Data Mutex could not be created. RC=%ld\n",
                              "CFE_ES_Main", OsStatus);
    /*
    ** Delay to allow the message to be read
    */
    OS_TaskDelay(CFE_ES_PANIC_DELAY);
    /*
    ** cFE Cannot continue to start up.
    */
    CFE_PSP_Panic(CFE_PSP_PANIC_STARTUP_SEM);
    /*
     * Normally CFE_PSP_Panic() will not return but it will under UT
     */
    return;
  }
  /*
  ** Announce the startup
  */
  CFE_ES_WriteToSysLog("%s: CFE_ES_Main in EARLY_INIT state\n", "CFE_ES_Main");
  /*
  ** Create and Mount the filesystems needed
  */
  CFE_ES_InitializeFileSystems(StartType);
  /*
  ** Install exception Handlers ( Placeholder )
  */
  CFE_PSP_AttachExceptions();
  /*
  ** Initialize the Last Id
  */
  CFE_ES_Global.LastAppId = CFE_ES_APPID_BASE;
  CFE_ES_Global.LastLibId = CFE_ES_LIBID_BASE;
  CFE_ES_Global.LastCounterId = CFE_ES_COUNTID_BASE;
  CFE_ES_Global.LastMemPoolId = CFE_ES_POOLID_BASE;
  /*
  ** Indicate that the CFE core is now starting up / going multi-threaded
  */
  CFE_ES_WriteToSysLog("%s: CFE_ES_Main entering CORE_STARTUP state\n", "CFE_ES_Main");
  CFE_ES_Global.SystemState = CFE_ES_SystemState_CORE_STARTUP;
  /*
  ** Create the tasks, OS objects, and initialize hardware
  */
  CFE_ES_CreateObjects();
  /*
  ** Indicate that the CFE core is ready
  */
  CFE_ES_WriteToSysLog("%s: CFE_ES_Main entering CORE_READY state\n", "CFE_ES_Main");
  CFE_ES_Global.SystemState = CFE_ES_SystemState_CORE_READY;
  /*
  ** Start the cFE Applications from the disk using the file
  ** specified in the CFE_PLATFORM_ES_NONVOL_STARTUP_FILE or CFE_PLATFORM_ES_VOLATILE_STARTUP_FILE
  ** ( defined in the cfe_platform_cfg.h file )
  */
  CFE_ES_StartApplications(StartType, StartFilePath);
  /*
   * Wait for applications to be in at least "LATE_INIT"
   *
   * However, if not everything starts up, that is not a fatal error, we will
   * continue anyway since the core apps are OK and control/telemetry should function.
   * The problem app could be deleted/restarted/etc by the ground station.
   */
  if (CFE_ES_MainTaskSyncDelay(CFE_ES_AppState_LATE_INIT,
                               CFE_PLATFORM_ES_STARTUP_SCRIPT_TIMEOUT_MSEC) != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Startup Sync failed - Applications may not have all initialized\n",
                         "CFE_ES_Main");
  }
  CFE_ES_WriteToSysLog("%s: CFE_ES_Main entering APPS_INIT state\n", "CFE_ES_Main");
  CFE_ES_Global.SystemState = CFE_ES_SystemState_APPS_INIT;
  /*
   * Wait for applications to be "RUNNING" before moving to operational system state.
   *
   * However, if not everything starts up, that is not a fatal error, we will
   * continue anyway since the core apps are OK and control/telemetry should function.
   * The problem app could be deleted/restarted/etc by the ground station.
   */
  if (CFE_ES_MainTaskSyncDelay(CFE_ES_AppState_RUNNING,
                               CFE_PLATFORM_ES_STARTUP_SCRIPT_TIMEOUT_MSEC) != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Startup Sync failed - Applications may not have all started\n",
                         "CFE_ES_Main");
  }
  /*
  ** Startup is fully complete
  */
  CFE_ES_WriteToSysLog("%s: CFE_ES_Main entering OPERATIONAL state\n", "CFE_ES_Main");
  CFE_ES_Global.SystemState = CFE_ES_SystemState_OPERATIONAL;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 * SYSLOGGING NOTE: Any logging in here must use CFE_ES_SysLogWrite_Unsync() as the necessary
 * primitives are not even initialized yet.  There is no chance for log contention here.
 *-----------------------------------------------------------------*/
// THIS FUNCTION DECIDES WHETHER THE SPACECRAFT IS IN A RESET LOOP, and that is the only place
// in cFE where software counts its own restarts and gives up. A processor reset that ES did not
// cause increments ProcessorResetCount; when it passes MaxProcessorResetCount (2 by default)
// the next one is escalated to a POWER-ON reset, which wipes the reset area -- so the loop is
// broken by losing state deliberately.
//
// AND IT LOGS THE ESCALATION TO THE ER LOG FIRST, knowing the log will not survive. NASA's
// comment is the interesting one: "Log the reset in the ER Log. The log will be wiped out, but
// it's good to have the entry just in case something fails." The entry is written for the case
// where the restart does NOT happen.
//
// ES_CausedReset IS THE WHOLE BRANCH. A reset that ES commanded, or that came from an
// exception, was already logged on the way down -- NASA: "The logic for detecting maximum
// resets is done on the command/exception side on the 'way down'" -- so this only updates the
// variables. The flag is cleared at the end, unconditionally, "in case a watchdog happens":
// the next unexplained reset must look uncommanded.
U0 CFE_ES_SetupResetVariables(U32 StartType, U32 StartSubtype, U32 BootSource)
{
  I32 PspStatus;
  U32 resetAreaSize;
  U64 ResetDataAddr;
  /*
  ** Get the pointer to the Reset area from the BSP
  */
  PspStatus = CFE_PSP_GetResetArea(&ResetDataAddr, &resetAreaSize);
  /*
  ** Make sure the status is OK or size is big enough
  */
  if (PspStatus != CFE_PSP_SUCCESS) {
    /*
    ** Cannot use the ES System log without the Reset Area
    */
    OS_printf("ES Startup: CFE_PSP_GetResetArea call Failed (0x%08x)!\n", PspStatus);
    /*
    ** Delay to allow the message to be read
    */
    OS_TaskDelay(CFE_ES_PANIC_DELAY);
    /*
    ** cFE Cannot continue to start up.
    */
    CFE_PSP_Panic(CFE_PSP_PANIC_MEMORY_ALLOC);
    /*
     * Normally unreachable, except in UT where
     * CFE_PSP_Panic is a stub that may return
     */
    return;
  } else if (resetAreaSize < sizeof(CFE_ES_ResetData_t)) {
    /*
    ** Cannot use the ES system log without the Reset Area
    */
    OS_printf("ES Startup: Error: ES Reset area not big enough. Needed: %d, Given: %d.\n",
              sizeof(CFE_ES_ResetData_t), resetAreaSize);
    /*
    ** Delay to allow the message to be read
    */
    OS_TaskDelay(CFE_ES_PANIC_DELAY);
    /*
    ** cFE Cannot continue to start up.
    */
    CFE_PSP_Panic(CFE_PSP_PANIC_MEMORY_ALLOC);
    /*
     * Normally unreachable, except in UT where
     * CFE_PSP_Panic is a stub that may return
     */
    return;
  }
  CFE_ES_Global.ResetDataPtr = ResetDataAddr;
  /*
  ** Record the BootSource (bank) so it will be valid in the ER log entries.
  */
  CFE_ES_Global.ResetDataPtr->ResetVars.BootSource = BootSource;
  /*
  ** Determine how the system was started. The choices are:
  **   CFE_ES_POWER_ON_RESET, or CFE_PSP_RST_TYPE_PROCESSOR
  ** The subtypes include:
  **   CFE_PSP_RST_SUBTYPE_POWER_CYCLE, CFE_PSP_RST_SUBTYPE_PUSH_BUTTON, CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND,
  **   CFE_PSP_RST_SUBTYPE_HW_WATCHDOG, CFE_PSP_RST_TYPE_COMMAND, or CFE_PSP_RST_SUBTYPE_EXCEPTION.
  ** Some of these reset types are logged before the system is restarted.
  **  ( CFE_PSP_RST_TYPE_COMMAND, CFE_PSP_RST_SUBTYPE_EXCEPTION ) while others occur
  **  without the knowledge of the software and must be logged here.
  */
  if (StartType == CFE_PSP_RST_TYPE_POWERON) {
    /*
    ** Record the reset type and subtype
    */
    CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype = StartSubtype;
    CFE_ES_Global.ResetDataPtr->ResetVars.ResetType = CFE_PSP_RST_TYPE_POWERON;
    /*
    ** Log the power-on reset.
    */
    if (StartSubtype == CFE_PSP_RST_SUBTYPE_POWER_CYCLE) {
      CFE_ES_SysLogWrite_Unsync("%s: POWER ON RESET due to Power Cycle (Power Cycle).\n",
                                "CFE_ES_SetupResetVariables");
      CFE_ES_WriteToERLog(CFE_ES_LogEntryType_CORE, CFE_PSP_RST_TYPE_POWERON, StartSubtype,
                          "POWER ON RESET due to Power Cycle (Power Cycle)");
    } else if (StartSubtype == CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND) {
      CFE_ES_SysLogWrite_Unsync("%s: POWER ON RESET due to HW Special Cmd (Hw Spec Cmd).\n",
                                "CFE_ES_SetupResetVariables");
      CFE_ES_WriteToERLog(CFE_ES_LogEntryType_CORE, CFE_PSP_RST_TYPE_POWERON, StartSubtype,
                          "POWER ON RESET due to HW Special Cmd (Hw Spec Cmd)");
    } else {
      CFE_ES_SysLogWrite_Unsync("%s: POWER ON RESET due to other cause (See Subtype).\n",
                                "CFE_ES_SetupResetVariables");
      CFE_ES_WriteToERLog(CFE_ES_LogEntryType_CORE, CFE_PSP_RST_TYPE_POWERON, StartSubtype,
                          "POWER ON RESET due to other cause (See Subtype)");
    }
    /*
    ** Initialize all reset counters.
    */
    CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount = 0;
    CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount =
        CFE_PLATFORM_ES_MAX_PROCESSOR_RESETS;
    CFE_ES_Global.DebugVars.DebugFlag = 0;
  } else if (StartType == CFE_PSP_RST_TYPE_PROCESSOR) {
    /*
    ** If a Processor reset was not commanded, it must be a watchdog or other non-commanded reset
    ** Log the reset before updating any reset variables.
    */
    if (CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset != TRUE) {
      CFE_ES_Global.ResetDataPtr->ResetVars.ResetType = CFE_PSP_RST_TYPE_PROCESSOR;
      CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount++;
      /*
      ** When coming up from a Processor reset that was not caused by ES, check to see
      ** if the maximum number has been exceeded
      */
      if (CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount >
          CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount) {
        if (StartSubtype == CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND) {
          CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype =
              CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND;
          CFE_ES_SysLogWrite_Unsync("%s: POWER ON RESET due to max proc resets (HW Spec Cmd).\n",
                                    "CFE_ES_SetupResetVariables");
          /*
          ** Log the reset in the ER Log. The log will be wiped out, but it's good to have
          ** the entry just in case something fails.
          */
          CFE_ES_WriteToERLog(CFE_ES_LogEntryType_CORE, CFE_PSP_RST_TYPE_POWERON, StartSubtype,
                              "POWER ON RESET due to max proc resets (HW Spec Cmd).");
        } else {
          CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype = CFE_PSP_RST_SUBTYPE_HW_WATCHDOG;
          CFE_ES_SysLogWrite_Unsync("%s: POWER ON RESET due to max proc resets (Watchdog).\n",
                                    "CFE_ES_SetupResetVariables");
          /*
          ** Log the reset in the ER Log. The log will be wiped out, but it's good to have
          ** the entry just in case something fails.
          */
          CFE_ES_WriteToERLog(CFE_ES_LogEntryType_CORE, CFE_PSP_RST_TYPE_POWERON, StartSubtype,
                              "POWER ON RESET due to max proc resets (Watchdog).");
        }
        /*
        ** Call the BSP reset routine
        */
        CFE_PSP_Restart(CFE_PSP_RST_TYPE_POWERON);
        /*
        ** Should not return here.
        */
        CFE_ES_SysLogWrite_Unsync("%s: Error: CFE_PSP_Restart returned.\n",
                                  "CFE_ES_SetupResetVariables");
      } else /* Maximum processor reset not exceeded */
      {
        if (StartSubtype == CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND) {
          CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype =
              CFE_PSP_RST_SUBTYPE_HW_SPECIAL_COMMAND;
          CFE_ES_SysLogWrite_Unsync("%s: PROCESSOR RESET due to Hardware Special Command (HW Spec Cmd).\n",
                                    "CFE_ES_SetupResetVariables");
          /*
          ** Log the watchdog reset
          */
          CFE_ES_WriteToERLog(CFE_ES_LogEntryType_CORE, CFE_PSP_RST_TYPE_PROCESSOR, StartSubtype,
                              "PROCESSOR RESET due to Hardware Special Command (Hw Spec Cmd).");
        } else {
          CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype = CFE_PSP_RST_SUBTYPE_HW_WATCHDOG;
          CFE_ES_SysLogWrite_Unsync("%s: PROCESSOR RESET due to Watchdog (Watchdog).\n",
                                    "CFE_ES_SetupResetVariables");
          /*
          ** Log the watchdog reset
          */
          CFE_ES_WriteToERLog(CFE_ES_LogEntryType_CORE, CFE_PSP_RST_TYPE_PROCESSOR, StartSubtype,
                              "PROCESSOR RESET due to Watchdog (Watchdog).");
        }
      }
    }
    /*
    ** If a processor reset is due to a command or exception, the reset has already been logged.
    ** Update the reset variables only.
    ** The logic for detecting maximum resets is done on the command/exception side
    ** on the "way down" when the command or exception handler is executed.
    */
    else {
      CFE_ES_Global.ResetDataPtr->ResetVars.ResetType = CFE_PSP_RST_TYPE_PROCESSOR;
      CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype = StartSubtype;
    }
    /*
    ** Initialize processor reset counters.
    */
    CFE_ES_Global.DebugVars.DebugFlag = 0;
  }
  /*
  ** Clear the commanded reset flag, in case a watchdog happens.
  */
  CFE_ES_Global.ResetDataPtr->ResetVars.ES_CausedReset = FALSE;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Creates or initializes the volatile file system based on the reset type
 *
 *-----------------------------------------------------------------*/
// FORMAT ON A POWER-ON RESET, RE-ATTACH ON A PROCESSOR RESET -- that difference IS the volatile
// disk's purpose. OS_initfs attaches to a file system already in the RAM, so a processor reset
// keeps whatever was written there; OS_mkfs makes a new one, which is what a power cycle gets
// because the RAM contents are not trustworthy.
//
// AND A FAILED RE-ATTACH FALLS BACK TO FORMATTING, with its own log line, so RAM that did not
// survive the reset costs the disk's contents and nothing more. Only a failure to FORMAT is
// fatal.
U0 CFE_ES_InitializeFileSystems_SetupVolume(U32 StartType, U64 RamDiskMemoryAddress,
                                            U8 *LogFunction)
{
  I32 OsStatus;
  /*
  ** Either format or just initialize the RAM disk depending on the reset type
  */
  if (StartType == CFE_PSP_RST_TYPE_POWERON) {
    OsStatus = OS_mkfs(RamDiskMemoryAddress, "/ramdev0", "RAM",
                       CFE_PLATFORM_ES_RAM_DISK_SECTOR_SIZE,
                       CFE_PLATFORM_ES_RAM_DISK_NUM_SECTORS);
    if (OsStatus != OS_SUCCESS) {
      CFE_ES_WriteToSysLog("%s: Error Creating Volatile(RAM) Volume. EC = %ld\n", LogFunction,
                           OsStatus);
      /*
      ** Delay to allow the message to be read
      */
      OS_TaskDelay(CFE_ES_PANIC_DELAY);
      /*
      ** cFE Cannot continue to start up.
      */
      CFE_PSP_Panic(CFE_PSP_PANIC_VOLATILE_DISK);
    }
  } else {
    OsStatus = OS_initfs(RamDiskMemoryAddress, "/ramdev0", "RAM",
                         CFE_PLATFORM_ES_RAM_DISK_SECTOR_SIZE,
                         CFE_PLATFORM_ES_RAM_DISK_NUM_SECTORS);
    if (OsStatus != OS_SUCCESS) {
      CFE_ES_WriteToSysLog("%s: Error Initializing Volatile(RAM) Volume. EC = %ld\n",
                           LogFunction, OsStatus);
      CFE_ES_WriteToSysLog("%s: Formatting Volatile(RAM) Volume.\n", LogFunction);
      OsStatus = OS_mkfs(RamDiskMemoryAddress, "/ramdev0", "RAM",
                         CFE_PLATFORM_ES_RAM_DISK_SECTOR_SIZE,
                         CFE_PLATFORM_ES_RAM_DISK_NUM_SECTORS);
      if (OsStatus != OS_SUCCESS) {
        CFE_ES_WriteToSysLog("%s: Error Creating Volatile(RAM) Volume. EC = %ld\n", LogFunction,
                             OsStatus);
        /*
        ** Delay to allow the message to be read
        */
        OS_TaskDelay(CFE_ES_PANIC_DELAY);
        /*
        ** cFE Cannot continue to start up.
        */
        CFE_PSP_Panic(CFE_PSP_PANIC_VOLATILE_DISK);
      }
    }
  }
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Re-formats and re-mounts a volatile file system that is too full
 *
 *-----------------------------------------------------------------*/
// FOUR STEPS AND EVERY ONE IS FATAL: unmount, remove, make, remount. There is no partial
// recovery, because a volatile disk that is half torn down is worse than one that is full --
// every step panics on failure rather than trying to put it back.
U0 CFE_ES_InitializeFileSystems_ReformatVolume(U64 RamDiskMemoryAddress, U8 *LogFunction)
{
  I32 OsStatus;
  /*
  ** First, unmount the disk
  */
  OsStatus = OS_unmount(CFE_PLATFORM_ES_RAM_DISK_MOUNT_STRING);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error Un-Mounting Volatile(RAM) Volume. EC = %ld\n", LogFunction,
                         OsStatus);
    /*
    ** Delay to allow the message to be read
    */
    OS_TaskDelay(CFE_ES_PANIC_DELAY);
    /*
    ** cFE Cannot continue to start up.
    */
    CFE_PSP_Panic(CFE_PSP_PANIC_VOLATILE_DISK);
    return;
  }
  /*
  ** Remove the file system from the OSAL
  */
  OsStatus = OS_rmfs("/ramdev0");
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error Removing Volatile(RAM) Volume. EC = %ld\n", LogFunction,
                         OsStatus);
    /*
    ** Delay to allow the message to be read
    */
    OS_TaskDelay(CFE_ES_PANIC_DELAY);
    /*
    ** cFE Cannot continue to start up.
    */
    CFE_PSP_Panic(CFE_PSP_PANIC_VOLATILE_DISK);
    return;
  }
  /*
  ** Next, make a new file system on the disk
  */
  OsStatus = OS_mkfs(RamDiskMemoryAddress, "/ramdev0", "RAM",
                     CFE_PLATFORM_ES_RAM_DISK_SECTOR_SIZE,
                     CFE_PLATFORM_ES_RAM_DISK_NUM_SECTORS);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error Re-Formatting Volatile(RAM) Volume. EC = %ld\n", LogFunction,
                         OsStatus);
    /*
    ** Delay to allow the message to be read
    */
    OS_TaskDelay(CFE_ES_PANIC_DELAY);
    /*
    ** cFE Cannot continue to start up.
    */
    CFE_PSP_Panic(CFE_PSP_PANIC_VOLATILE_DISK);
    return;
  }
  /*
  ** Last, remount the disk
  */
  OsStatus = OS_mount("/ramdev0", CFE_PLATFORM_ES_RAM_DISK_MOUNT_STRING);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error Re-Mounting Volatile(RAM) Volume. EC = %ld\n", LogFunction,
                         OsStatus);
    /*
    ** Delay to allow the message to be read
    */
    OS_TaskDelay(CFE_ES_PANIC_DELAY);
    /*
    ** cFE Cannot continue to start up.
    */
    CFE_PSP_Panic(CFE_PSP_PANIC_VOLATILE_DISK);
  }
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Checks the free space on the volatile file system and re-formats if necessary
 *
 *-----------------------------------------------------------------*/
// INTEGER PERCENT, AND THE PERCENTAGE IS LOGGED EVERY BOOT -- so a disk slowly filling across
// processor resets leaves a trail in the system log before it ever gets reformatted.
//
// AN UNREADABLE VOLUME IS FATAL, and NASA's comment explains the odd-looking status handling:
// "note that BlocksFree returns the error code in this case". A total_blocks of zero takes the
// same arm, because the division would be by zero.
U0 CFE_ES_InitializeFileSystems_CheckFreeSpace(U64 RamDiskMemoryAddress, U8 *LogFunction)
{
  I32 OsStatus;
  I32 PercentFree;
  OS_statvfs_t StatBuf;
  MemSet(&StatBuf, 0, sizeof(OS_statvfs_t));
  /*
  ** See how many blocks are free in the RAM disk
  */
  OsStatus = OS_FileSysStatVolume(CFE_PLATFORM_ES_RAM_DISK_MOUNT_STRING, &StatBuf);
  if (OsStatus == OS_SUCCESS && StatBuf.total_blocks > 0) {
    /*
    ** Determine if the disk is too full
    */
    PercentFree = (StatBuf.blocks_free * 100) / StatBuf.total_blocks;
    CFE_ES_WriteToSysLog("%s: Volatile Disk has %d Percent free space.\n", LogFunction,
                         PercentFree);
    if (PercentFree < CFE_PLATFORM_ES_RAM_DISK_PERCENT_RESERVED) {
      CFE_ES_WriteToSysLog("%s: Insufficient Free Space on Volatile Disk, Reformatting.\n",
                           LogFunction);
      CFE_ES_InitializeFileSystems_ReformatVolume(RamDiskMemoryAddress, LogFunction);
    }
  } else {
    /* Log error message -- note that BlocksFree returns the error code in this case */
    CFE_ES_WriteToSysLog("%s: Error Determining Blocks Free on Volume. EC = %ld\n", LogFunction,
                         OsStatus);
    /*
    ** Delay to allow the message to be read
    */
    OS_TaskDelay(CFE_ES_PANIC_DELAY);
    /*
    ** cFE Cannot continue to start up.
    */
    CFE_PSP_Panic(CFE_PSP_PANIC_VOLATILE_DISK);
  }
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE THREE HELPERS ABOVE TAKE __func__ AS AN ARGUMENT, which is why they have a LogFunction
// parameter at all: every line they log says CFE_ES_InitializeFileSystems, not the helper's own
// name, so the log reads as one operation. The translation passes the string literal, the same
// way every other __func__ in this port becomes one.
//
// NOTE THE FREE-SPACE CHECK RUNS ONLY ON A PROCESSOR RESET, because a power-on reset just
// formatted the disk -- there is nothing to be too full.
U0 CFE_ES_InitializeFileSystems(U32 StartType)
{
  I32 OsStatus;
  I32 PspStatus;
  U64 RamDiskMemoryAddress = 0;
  U32 RamDiskMemorySize;
  /*
  ** Get the memory area for the RAM disk
  */
  PspStatus = CFE_PSP_GetVolatileDiskMem(&RamDiskMemoryAddress, &RamDiskMemorySize);
  if (PspStatus != CFE_PSP_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Cannot Get Memory for Volatile Disk. EC = 0x%08X\n",
                         "CFE_ES_InitializeFileSystems", PspStatus);
    /*
    ** Delay to allow the message to be read
    */
    OS_TaskDelay(CFE_ES_PANIC_DELAY);
    /*
    ** cFE Cannot continue to start up.
    */
    CFE_PSP_Panic(CFE_PSP_PANIC_VOLATILE_DISK);
  }
  CFE_ES_InitializeFileSystems_SetupVolume(StartType, RamDiskMemoryAddress,
                                           "CFE_ES_InitializeFileSystems");
  /*
  ** Now, mount the RAM disk
  */
  OsStatus = OS_mount("/ramdev0", CFE_PLATFORM_ES_RAM_DISK_MOUNT_STRING);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error Mounting Volatile(RAM) Volume. EC = %ld\n",
                         "CFE_ES_InitializeFileSystems", OsStatus);
    /*
    ** Delay to allow the message to be read
    */
    OS_TaskDelay(CFE_ES_PANIC_DELAY);
    /*
    ** cFE Cannot continue to start up.
    */
    CFE_PSP_Panic(CFE_PSP_PANIC_VOLATILE_DISK);
  }
  /*
  ** During a Processor reset, if the RAM disk has less than a defined
  ** amount of free space, reformat and re-mount it.
  ** The parameter being checked is CFE_PLATFORM_ES_RAM_DISK_PERCENT_RESERVED
  ** Note: When CFE_PLATFORM_ES_RAM_DISK_PERCENT_RESERVED is set to 0, this feature is
  **       disabled.
  */
  if ((StartType == CFE_PSP_RST_TYPE_PROCESSOR) &&
      (CFE_PLATFORM_ES_RAM_DISK_PERCENT_RESERVED > 0)) {
    CFE_ES_InitializeFileSystems_CheckFreeSpace(RamDiskMemoryAddress,
                                                "CFE_ES_InitializeFileSystems");
  } /* end if processor reset */
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// EVERY CORE MODULE, IN TWO PASSES OVER THE SAME TABLE, and the two passes are the point: ALL
// the EarlyInits run before ANY task starts. A module's EarlyInit may set up state another
// module's task depends on, so a single pass that started each task as it went would be a race
// -- and this is also why a failed EarlyInit panics rather than skipping the module.
//
// A CORE APP IS AN APP-TABLE ENTRY WITH NO FILE. Each one gets a real slot, Type CORE, the
// name, priority and stack from the object table, and ExceptionAction PROC_RESTART -- a core
// app cannot be restarted on its own, so an exception in one resets the processor. The
// RESERVED-id protocol is the same as CFE_ES_AppCreate's: claim the slot under the lock, start
// the task with the lock released, then set the real id or wipe the record.
//
// AND IT WAITS FOR EACH TASK TO REACH RUNNING BEFORE STARTING THE NEXT, with
// CFE_PLATFORM_CORE_MAX_STARTUP_MSEC to do it, so the core comes up in table order and a module
// that hangs is reported as the one that hung. The failure message is "OS_TaskCreate error
// creating core App" whichever of the two steps failed, which is NASA's.
U0 CFE_ES_CreateObjects()
{
  I32 ReturnCode;
  I64 i;
  CFE_ES_AppRecord_t *AppRecPtr;
  U32 PendingAppId;
  Target_ObjectTable *Entry;
  CFE_ES_WriteToSysLog("%s: Starting Object Creation calls.\n", "CFE_ES_CreateObjects");
  /* Phase 1: EarlyInit */
  for (i = 0;; i++) {
    Entry = GLOBAL_CONFIGDATA.CoreObjectTable[i];
    if (Entry == NULL) {
      break;
    }
    if (Entry->EarlyInit != NULL) {
      CFE_ES_WriteToSysLog("%s: Calling EarlyInit for %s\n", "CFE_ES_CreateObjects", Entry->Name);
      ReturnCode = Entry->EarlyInit();
      if (ReturnCode != CFE_SUCCESS) {
        CFE_ES_WriteToSysLog("%s: Error returned from EarlyInit for %s: EC = 0x%08X\n",
                             "CFE_ES_CreateObjects", Entry->Name, ReturnCode);
        OS_TaskDelay(CFE_ES_PANIC_DELAY);
        CFE_PSP_Panic(CFE_PSP_PANIC_CORE_APP);
      }
    }
  }
  /* Phase 2: TaskMain */
  for (i = 0;; i++) {
    Entry = GLOBAL_CONFIGDATA.CoreObjectTable[i];
    if (Entry == NULL) {
      break;
    }
    if (Entry->TaskMain == NULL) {
      continue;
    }
    CFE_ES_LockSharedData("CFE_ES_CreateObjects", 814);
    PendingAppId = CFE_ResourceId_FindNext(CFE_ES_Global.LastAppId,
                                           CFE_PLATFORM_ES_MAX_APPLICATIONS,
                                           &CFE_ES_CheckAppIdSlotUsed);
    AppRecPtr = CFE_ES_LocateAppRecordByID(PendingAppId);
    if (AppRecPtr != NULL) {
      AppRecPtr->Type = CFE_ES_AppType_CORE;
      StrNCpy(AppRecPtr->AppName, Entry->Name, OS_MAX_API_NAME - 1);
      AppRecPtr->AppName[OS_MAX_API_NAME - 1] = '\0';
      AppRecPtr->StartParams.MainTaskInfo.StackSize = Entry->StackSize;
      AppRecPtr->StartParams.MainTaskInfo.Priority = Entry->Priority;
      AppRecPtr->StartParams.ExceptionAction = CFE_ES_ExceptionAction_PROC_RESTART;
      AppRecPtr->ControlReq.AppControlRequest = CFE_ES_RunStatus_APP_RUN;
      AppRecPtr->ControlReq.AppTimerMsec = 0;
      CFE_ES_AppRecordSetUsed(AppRecPtr, CFE_RESOURCEID_RESERVED);
      CFE_ES_Global.LastAppId = PendingAppId;
    }
    CFE_ES_UnlockSharedData("CFE_ES_CreateObjects", 832);
    if (AppRecPtr != NULL) {
      ReturnCode = CFE_ES_StartAppTask(&AppRecPtr->MainTaskId, AppRecPtr->AppName,
                                       Entry->TaskMain, &AppRecPtr->StartParams.MainTaskInfo,
                                       PendingAppId);
      CFE_ES_LockSharedData("CFE_ES_CreateObjects", 841);
      if (ReturnCode == CFE_SUCCESS) {
        CFE_ES_AppRecordSetUsed(AppRecPtr, PendingAppId);
        CFE_ES_Global.RegisteredCoreApps++;
      } else {
        MemSet(AppRecPtr, 0, sizeof(CFE_ES_AppRecord_t));
      }
      CFE_ES_UnlockSharedData("CFE_ES_CreateObjects", 851);
    } else {
      CFE_ES_WriteToSysLog("%s: Error, No free application slots available for CORE App!\n",
                           "CFE_ES_CreateObjects");
      ReturnCode = CFE_ES_ERR_APP_CREATE;
    }
    if (ReturnCode == CFE_SUCCESS) {
      ReturnCode = CFE_ES_MainTaskSyncDelay(CFE_ES_AppState_RUNNING,
                                            CFE_PLATFORM_CORE_MAX_STARTUP_MSEC);
    }
    if (ReturnCode != CFE_SUCCESS) {
      CFE_ES_WriteToSysLog("%s: OS_TaskCreate error creating core App: %s: EC = 0x%08X\n",
                           "CFE_ES_CreateObjects", Entry->Name, ReturnCode);
      OS_TaskDelay(CFE_ES_PANIC_DELAY);
      CFE_PSP_Panic(CFE_PSP_PANIC_CORE_APP);
    }
  } /* end for */
  CFE_ES_WriteToSysLog("%s: Finished ES CreateObject table entries.\n", "CFE_ES_CreateObjects");
}

/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Waits for all of the applications that CFE has started thus far to
 * reach the indicated state, by polling the app counters in a delay loop.
 *
 *-----------------------------------------------------------------*/
// IT COUNTS APPS THAT ARE NOT YET THERE, under the lock, and sleeps if any are. The states are
// ORDERED, so `AppState < AppStateId` means "has not got that far yet" -- which is what lets
// one function serve both the LATE_INIT and the RUNNING wait.
//
// THE TIMEOUT IS CONSUMED IN POLL-SIZED BITES and the last one is shortened to whatever is
// left, so the total wait is the caller's number rather than a multiple of the poll interval.
// A timeout is CFE_ES_OPERATION_TIMED_OUT, which CFE_ES_Main logs and ignores.
I32 CFE_ES_MainTaskSyncDelay(U32 AppStateId, U32 TimeOutMilliseconds)
{
  I32 Status;
  U32 i;
  U32 WaitTime;
  U32 WaitRemaining;
  U32 AppNotReadyCounter;
  CFE_ES_AppRecord_t *AppRecPtr;
  Status = CFE_ES_OPERATION_TIMED_OUT;
  WaitRemaining = TimeOutMilliseconds;
  while (TRUE) {
    AppNotReadyCounter = 0;
    /*
     * Count the number of apps that are NOT in (at least) in the state requested
     */
    CFE_ES_LockSharedData("CFE_ES_MainTaskSyncDelay", 904);
    AppRecPtr = CFE_ES_Global.AppTable;
    for (i = 0; i < CFE_PLATFORM_ES_MAX_APPLICATIONS; i++) {
      if (CFE_ES_AppRecordIsUsed(AppRecPtr) && (AppRecPtr->AppState < AppStateId)) {
        ++AppNotReadyCounter;
      }
      ++AppRecPtr;
    }
    CFE_ES_UnlockSharedData("CFE_ES_MainTaskSyncDelay", 914);
    if (AppNotReadyCounter == 0) {
      /* Condition Met */
      Status = CFE_SUCCESS;
      break;
    }
    /*
     * Must delay and check again
     */
    if (WaitRemaining > CFE_PLATFORM_ES_STARTUP_SYNC_POLL_MSEC) {
      WaitTime = CFE_PLATFORM_ES_STARTUP_SYNC_POLL_MSEC;
    } else if (WaitRemaining > 0) {
      WaitTime = WaitRemaining;
    } else {
      break;
    }
    OS_TaskDelay(WaitTime);
    WaitRemaining -= WaitTime;
  }
  return Status;
}
#endif
