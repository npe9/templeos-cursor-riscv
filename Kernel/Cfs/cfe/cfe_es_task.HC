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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_task.c -- ES'S TASK AND ITS COMMANDS.
//
// Twenty-eight functions: the main loop, the init, and the twenty-two ground commands. Where
// cfe_es_api.c is the API other apps call, this is the one that answers the GROUND -- so almost
// every function here ends in an event and a command counter, and the event TEXT is inside the
// byte-identical comparison.
//
// WHAT IS IN HERE, in groups:
//   the task          TaskMain, TaskInit
//   version events    GenerateSingleVersionEvent, ModSrcVerCallback, GenerateVersionEvents,
//                     GenerateBuildInfoEvents
//   housekeeping      SendHkCmd
//   trivial commands  NoopCmd, ResetCountersCmd, RestartCmd
//   app control       StartAppCmd, StopAppCmd, RestartAppCmd, ReloadAppCmd
//   queries           QueryOneCmd, QueryAllCmd, QueryAllTasksCmd
//   the system log    ClearSysLogCmd, OverWriteSysLogCmd, WriteSysLogCmd
//   the ER log        ClearERLogCmd, WriteERLogCmd
//   reset counts      ResetPRCountCmd, SetMaxPRCountCmd
//   the CDS           DeleteCDSCmd, DumpCDSRegistryCmd
//   memory            SendMemPoolStatsCmd
//   shared            FileWriteByteCntErr -- which every file-writing command above calls
//
// THE MAIN LOOP IS DRIVABLE, which is not obvious and had to be checked before this file was
// gated. CFE_ES_TaskMain is `while (AppRunStatus == APP_RUN)` and the only thing that changes
// AppRunStatus inside it is CFE_SB_ReceiveBuffer returning something other than CFE_SUCCESS. It
// then falls out to CFE_ES_ExitApp(CORE_APP_RUNTIME_ERROR), which for a CORE app unlocks and
// calls OS_TaskExit -- a stub that returns under the differential driver, which is the case
// NASA's own comment covers ("Code will not return, except under unit test"). An EXTERNAL app
// would spin in `while (1) OS_TaskDelay(500)` forever, so the exercise drives this as CORE.
// THIS FILE INCLUDES NOTHING, which is the house rule and not a style preference: a translated
// unit that includes a sibling the driver has ALREADY included loses everything after that
// line, silently, with a clean exit (docs/HOLYC_STRUCT_LIMITS.md #13 -- it cost cfe_time_api.HC
// all forty-six of its functions). This file was written with three sibling includes and
// contributed nothing to the driver until they came out.
//
// REQUIRED INCLUDE ORDER, which the driver provides:
//     cfe_es_global.HC        ES's state, including CFE_ES_TaskData_t and the three TLM packets
//     cfe_es_syslog.HC        SysLogClear_Unsync, SysLogSetMode, SysLogDump
//     cfe_es_mempool.HC       ValidateHandle, GetMemPoolStats
//     cfe_es_resource.HC      the record tables and their accessors
//     cfe_es_api.HC           ES's public API -- and the locks, the CRC and WriteToSysLog
//     cfe_es_msg.HC           the twenty-two ground command formats
//     ../osal/osapi_heap_decl.HC   OS_heap_prop_t, for CFE_ES_SendHkCmd
// plus SB, EVS, FS and config, which cfe_es_api.HC's own header comment already requires.
#ifndef CFE_ES_TASK_HC
#define CFE_ES_TASK_HC
// OS_HeapGetInfo: the TYPE comes from osapi_heap_decl.HC above, the FUNCTION from whoever
// links this. Including osapi_heap.HC would drag OSAL's implementation into the cFE
// translation unit, which is the one thing check_seam exists to prevent.
I32 OS_HeapGetInfo(OS_heap_prop_t *heap_prop);
// --- cfe_es_task.h --------------------------------------------------------------------------
#define CFE_ES_PIPE_NAME             "ES_CMD_PIPE"
#define CFE_ES_PIPE_DEPTH            12
#define CFE_ES_QUERY_ALL_MAX_ENTRIES 42
// The four file DESCRIPTIONS, which go in the cFE file header of each dump.
#define CFE_ES_APP_LOG_DESC  "ES Application Info file"
#define CFE_ES_ER_LOG_DESC   "ES ERlog data file"
#define CFE_ES_TASK_LOG_DESC "ES Task Info file"
// OS_MAX_PRIORITY is NOT an OSAL symbol. cfe_es_task.c defines it itself, with the comment
// "This define should be put in the OS API headers -- Right now it matches what the OS API
// uses", so it is here for the same reason and with the same risk NASA names.
#define OS_MAX_PRIORITY 255
// --- cfe_es_internal_cfg.h: the four default dump filenames ----------------------------------
#define CFE_PLATFORM_ES_DEFAULT_APP_LOG_FILE      "/ram/cfe_es_app_info.log"
#define CFE_PLATFORM_ES_DEFAULT_TASK_LOG_FILE     "/ram/cfe_es_taskinfo.log"
#define CFE_PLATFORM_ES_DEFAULT_ER_LOG_FILE       "/ram/cfe_erlog.log"
#define CFE_PLATFORM_ES_DEFAULT_SYSLOG_FILE       "/ram/cfe_es_syslog.log"
#define CFE_PLATFORM_ES_DEFAULT_CDS_REG_DUMP_FILE "/ram/cfe_cds_reg.log"
// --- cfe_error.h: the two CDS codes this file compares against -------------------------------
#define CFE_ES_CDS_WRONG_TYPE_ERR   0xC4000020(I32)
#define CFE_ES_CDS_OWNER_ACTIVE_ERR 0xC4000022(I32)
// --- default_cfe_es_extern_typedefs.h: the exception actions ---------------------------------
#define CFE_ES_ExceptionAction_RESTART_APP  0
#define CFE_ES_ExceptionAction_PROC_RESTART 1
// --- cfe_fs_extern_typedefs.h: the five file subtypes this file writes -----------------------
#ifndef CFE_FS_SubType_ES_ERLOG
#define CFE_FS_SubType_ES_ERLOG         1
#define CFE_FS_SubType_ES_SYSLOG        2
#define CFE_FS_SubType_ES_QUERYALL      3
#define CFE_FS_SubType_ES_CDS_REG       6
#define CFE_FS_SubType_ES_QUERYALLTASKS 23
#endif
// --- cfe_perfids.h --------------------------------------------------------------------------
#define CFE_MISSION_ES_MAIN_PERF_ID 1
// --- cfe_es_msgids.h: measured through the probe, not read off the macro ---------------------
// Each is CFE_PLATFORM_ES_{CMD,TLM}_MIDVAL(X), two layers of CMake-driven macro over a base and
// an offset. check_constants.py compares every one of these against NASA's own expansion.
#define CFE_ES_CMD_MID          0x1806
#define CFE_ES_SEND_HK_MID      0x1808
#define CFE_ES_HK_TLM_MID       0x800
#define CFE_ES_APP_TLM_MID      0x80B
#define CFE_ES_MEMSTATS_TLM_MID 0x810
// --- cfe_es_internal_cfg.h --------------------------------------------------------------------
#ifndef CFE_PLATFORM_CORE_MAX_STARTUP_MSEC
#define CFE_PLATFORM_CORE_MAX_STARTUP_MSEC 30000
#endif
#define CFE_PLATFORM_ES_DEFAULT_POR_SYSLOG_MODE 0
#define CFE_PLATFORM_ES_DEFAULT_PR_SYSLOG_MODE  1
// --- cfe_es_interface_cfg.h -------------------------------------------------------------------
#ifndef CFE_MISSION_ES_PERF_MAX_IDS
#define CFE_MISSION_ES_PERF_MAX_IDS 128
#endif
// CFE_MISSION_ES_DEFAULT_CRC is CFE_ES_CrcType_16_ARC -- an ENUMERATOR, not a number, and the
// one in cmake/sample_defs spelt CFE_ES_CrcType_CRC_16 is an old alias whose value is 2, which
// is CFE_ES_CrcType_MAX and out of range. cfe_es_crc.HC carries the real enumerators.
#define CFE_MISSION_ES_DEFAULT_CRC CFE_ES_CrcType_16_ARC
// --- cfe_config.h: the version string length --------------------------------------------------
#ifndef CFE_CFG_MAX_VERSION_STR_LEN
#define CFE_CFG_MAX_VERSION_STR_LEN 256
#endif
// --- cfe_es_eventids.h: all fifty-five this file raises ---------------------------------------
// Written out rather than included because HolyC has no generated-header step. Every one is
// compared against NASA's own number by check_constants.py, which is the only reason a list
// this long can be trusted -- an event id nothing routes is invisible to the transcript.
#define CFE_ES_ALL_APPS_EID                          16
#define CFE_ES_BOOT_ERR_EID                          24
#define CFE_ES_BUILD_INF_EID                         92
#define CFE_ES_CDS_DELETED_INFO_EID                  78
#define CFE_ES_CDS_DELETE_ERR_EID                    76
#define CFE_ES_CDS_DELETE_TBL_ERR_EID                79
#define CFE_ES_CDS_DUMP_ERR_EID                      84
#define CFE_ES_CDS_NAME_ERR_EID                      77
#define CFE_ES_CDS_OWNER_ACTIVE_EID                  80
#define CFE_ES_CDS_REG_DUMP_INF_EID                  83
#define CFE_ES_CREATING_CDS_DUMP_ERR_EID             86
#define CFE_ES_ERLOG1_INF_EID                        19
#define CFE_ES_ERLOG2_ERR_EID                        56
#define CFE_ES_ERLOG_PENDING_ERR_EID                 93
#define CFE_ES_ERR_SYSLOGMODE_EID                    71
#define CFE_ES_FILEWRITE_ERR_EID                     74
#define CFE_ES_INITSTATS_INF_EID                     2
#define CFE_ES_INIT_INF_EID                          1
#define CFE_ES_INVALID_POOL_HANDLE_ERR_EID           82
#define CFE_ES_NOOP_INF_EID                          3
#define CFE_ES_ONE_APPID_ERR_EID                     50
#define CFE_ES_ONE_APP_EID                           15
#define CFE_ES_ONE_ERR_EID                           49
#define CFE_ES_OSCREATE_ERR_EID                      51
#define CFE_ES_RELOAD_APP_DBG_EID                    11
#define CFE_ES_RELOAD_APP_ERR1_EID                   42
#define CFE_ES_RELOAD_APP_ERR2_EID                   43
#define CFE_ES_RESET_INF_EID                         4
#define CFE_ES_RESET_PR_COUNT_EID                    72
#define CFE_ES_RESTART_APP_DBG_EID                   9
#define CFE_ES_RESTART_APP_ERR1_EID                  38
#define CFE_ES_RESTART_APP_ERR2_EID                  39
#define CFE_ES_SET_MAX_PR_COUNT_EID                  73
#define CFE_ES_START_ERR_EID                         26
#define CFE_ES_START_EXC_ACTION_ERR_EID              32
#define CFE_ES_START_INF_EID                         6
#define CFE_ES_START_INVALID_ENTRY_POINT_ERR_EID     28
#define CFE_ES_START_INVALID_FILENAME_ERR_EID        27
#define CFE_ES_START_NULL_APP_NAME_ERR_EID           29
#define CFE_ES_START_PRIORITY_ERR_EID                31
#define CFE_ES_STOP_DBG_EID                          7
#define CFE_ES_STOP_ERR1_EID                         35
#define CFE_ES_STOP_ERR2_EID                         36
#define CFE_ES_SYSLOG1_INF_EID                       17
#define CFE_ES_SYSLOG2_ERR_EID                       55
#define CFE_ES_SYSLOGMODE_EID                        70
#define CFE_ES_TASKINFO_EID                          87
#define CFE_ES_TASKINFO_OSCREATE_ERR_EID             88
#define CFE_ES_TASKINFO_WRHDR_ERR_EID                89
#define CFE_ES_TASKINFO_WR_ERR_EID                   90
#define CFE_ES_TASKWR_ERR_EID                        53
#define CFE_ES_TLM_POOL_STATS_INFO_EID               81
#define CFE_ES_VERSION_INF_EID                       91
#define CFE_ES_WRHDR_ERR_EID                         52
#define CFE_ES_WRITE_CFE_HDR_ERR_EID                 85
// --- what this file needs from elsewhere ------------------------------------------------------
// cfe_es_apps.c, cfe_es_cds.c, cfe_es_perf.c, cfe_es_backgroundtask.c and cfe_es_dispatch.c are
// none of them gated yet, so these are stubs on both halves of the differential oracle.
I32 CFE_ES_AppCreate(U32 *ApplicationIdPtr, U8 *AppName, CFE_ES_AppStartParams_t *Params);
I32 CFE_ES_BackgroundInit();
U0 CFE_ES_TaskPipe(CFE_SB_Buffer *SBBufPtr);
I32 CFE_ES_DeleteCDS(U8 *CDSName, Bool CalledByTblServices);
U32 CFE_ES_GetPerfLogDumpRemaining();
// The PSP.
I32 CFE_PSP_GetCFETextSegmentInfo(U64 *PtrToCFESegment, U32 *SizeOfCFESegment);
U0 CFE_PSP_GetVersionNumber(U8 *VersionNumbers);
U8 *CFE_PSP_GetVersionString();
// OSAL.
U0 OS_GetVersionNumber(U8 *VersionNumbers);
U8 *OS_GetVersionString();
// Declared here, defined below -- the C's own order has each used above its definition.
I32 CFE_ES_TaskInit();
U0 CFE_ES_FileWriteByteCntErr(U8 *Filename, I64 Requested, I32 Status);
// NASA DECLARES THIS AND NEVER READS IT. `CFE_ES_TaskData_t CFE_ES_TaskData;` sits at file
// scope in cfe_es_task.c while every line of the file uses CFE_ES_Global.TaskData instead. It
// is kept because the translation is 1:1 and because a symbol NASA exports is part of the
// interface whether or not this configuration links anything to it.
CFE_ES_TaskData_t CFE_ES_TaskData;
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE LOOP EXITS ONLY ON AN SB ERROR, and that is the whole termination argument: nothing
// inside it sets AppRunStatus except the else branch of CFE_SB_ReceiveBuffer. A pipe that keeps
// delivering keeps the task alive forever, which is what a flight task is for.
//
// THE EXECUTION COUNTER IS BUMPED HERE AND NOT BY CFE_ES_RunLoop, and NASA says why: "This is
// normally done in the CFE_ES_RunLoop call, but currently CFE Child tasks and the cFE core
// tasks do not use the RunLoop call."
//
// AND THE WAIT IS BEFORE THE LOOP, NOT INSIDE IT. NASA's comment: "It is important that the
// core apps are present before this starts receiving messages from the command pipe, as some of
// those handlers might depend on the other core apps."
U0 CFE_ES_TaskMain()
{
  I32 Status;
  U32 AppRunStatus = CFE_ES_RunStatus_APP_RUN;
  CFE_SB_Buffer *SBBufPtr;
  /*
  ** Performance Time Stamp Entry
  */
  CFE_ES_PerfLogEntry(CFE_MISSION_ES_MAIN_PERF_ID);
  /*
  ** Perform task specific initialization.
  */
  Status = CFE_ES_TaskInit();
  if (Status != CFE_SUCCESS) {
    /*
    ** Create a syslog entry
    */
    CFE_ES_WriteToSysLog("%s: Application Init Failed,RC=0x%08X\n", "CFE_ES_TaskMain", Status);
    /*
    ** Allow Core App to Exit
    */
    AppRunStatus = CFE_ES_RunStatus_CORE_APP_INIT_ERROR;
  }
  /*
   * Wait for other apps to start.
   * It is important that the core apps are present before this starts receiving
   * messages from the command pipe, as some of those handlers might depend on
   * the other core apps.
   */
  CFE_ES_WaitForSystemState(CFE_ES_SystemState_CORE_READY, CFE_PLATFORM_CORE_MAX_STARTUP_MSEC);
  /*
  ** Main process loop
  */
  while (AppRunStatus == CFE_ES_RunStatus_APP_RUN) {
    /*
    ** Increment the main task execution counter
    **  This is normally done in the CFE_ES_RunLoop call, but
    **  currently CFE Child tasks and the cFE core tasks do not
    **  use the RunLoop call.
    */
    CFE_ES_IncrementTaskCounter();
    /*
    ** Performance Time Stamp Exit
    */
    CFE_ES_PerfLogExit(CFE_MISSION_ES_MAIN_PERF_ID);
    /*
    ** Wait for the next Software Bus message.
    */
    Status = CFE_SB_ReceiveBuffer(&SBBufPtr, CFE_ES_Global.TaskData.CmdPipe, CFE_SB_PEND_FOREVER);
    /*
    ** Performance Time Stamp Entry
    */
    CFE_ES_PerfLogEntry(CFE_MISSION_ES_MAIN_PERF_ID);
    if (Status == CFE_SUCCESS) {
      /*
      ** Process message.
      */
      CFE_ES_TaskPipe(SBBufPtr);
      /*
       * Wake up the background task, which includes the
       * scanning of the ES app table for entries that may need cleanup
       */
      CFE_ES_BackgroundWakeup();
    } else {
      /*
      ** SB Error: Write a SysLog Message
      */
      CFE_ES_WriteToSysLog("%s: Error reading cmd pipe,RC=0x%08X\n", "CFE_ES_TaskMain", Status);
      /*
      ** Allow Core App to Exit
      */
      AppRunStatus = CFE_ES_RunStatus_CORE_APP_RUNTIME_ERROR;
    }
  }
  /* end while */
  /*
  ** Performance Time Stamp Exit
  */
  CFE_ES_PerfLogExit(CFE_MISSION_ES_MAIN_PERF_ID);
  /*
  ** Exit the application, CFE_ES_ExitApp will not return.
  */
  CFE_ES_ExitApp(AppRunStatus);
}
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Send a single CFE_ES_VERSION_INF_EID event for a component/module
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_GenerateSingleVersionEvent(U8 *ModuleType, U8 *ModuleName, U32 Id)
{
  I32 Status;
  /*
   * Advertise the mission version information
   * NOTE: CFE_Config_GetString() does not return NULL, so its OK to use inside an arg list
   */
  Status = CFE_EVS_SendEvent(CFE_ES_VERSION_INF_EID, CFE_EVS_EventType_INFORMATION, "Version Info: %s %s, version %s", ModuleType, ModuleName, CFE_Config_GetString(Id));
  return Status;
}
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Callback for iterating all configuration keys
 *
 *-----------------------------------------------------------------*/
// THE PREFIX LENGTH IS WRITTEN OUT, because NASA gets it from `sizeof(IDNAME_PREFIX) - 1` on a
// `static const char[]` and HolyC cannot: a file-scope char array initialised from a string
// literal is silently miscompiled (docs/HOLYC_STRUCT_LIMITS.md #19), so the tag is a `U8 *` and
// its length is the constant below. cfe_es_syslog.HC's FRAGMENT_TAG is the same arrangement.
U8 *CFE_ES_ModSrcVerCallback_IDNAME_PREFIX = "MOD_SRCVER_";
#define CFE_ES_IDNAME_PREFIX_LEN 11
U0 CFE_ES_ModSrcVerCallback(U8 *Arg, U32 Id, U8 *Name)
{
  if (StrNCmp(Name, CFE_ES_ModSrcVerCallback_IDNAME_PREFIX, CFE_ES_IDNAME_PREFIX_LEN) == 0) {
    CFE_ES_GenerateSingleVersionEvent("Module", &Name[CFE_ES_IDNAME_PREFIX_LEN], Id);
  }
}
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Send CFE_ES_VERSION_INF_EID events for all components/modules
 *
 *-----------------------------------------------------------------*/
U0 CFE_ES_GenerateVersionEvents()
{
  I32 Status;
  /*
   * Advertise the mission version information
   */
  Status = CFE_ES_GenerateSingleVersionEvent("Mission", GLOBAL_CONFIGDATA.MissionName, CFE_CONFIGID_MISSION_SRCVER);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error sending mission version event:RC=0x%08X\n", "CFE_ES_GenerateVersionEvents", Status);
  }
  CFE_Config_IterateAll(NULL, &CFE_ES_ModSrcVerCallback);
}
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Sends the CFE_ES_BUILD_INF_EID event with build information
 *
 *-----------------------------------------------------------------*/
U0 CFE_ES_GenerateBuildInfoEvents()
{
  I32 Status;
  U8 *BuildDate;
  U8 *BuildUser;
  U8 *BuildHost;
  /* NOTE: The config APIs using "GetString" will not return NULL */
  BuildDate = CFE_Config_GetString(CFE_CONFIGID_CORE_BUILDINFO_DATE);
  BuildUser = CFE_Config_GetString(CFE_CONFIGID_CORE_BUILDINFO_USER);
  BuildHost = CFE_Config_GetString(CFE_CONFIGID_CORE_BUILDINFO_HOST);
  Status = CFE_EVS_SendEvent(CFE_ES_BUILD_INF_EID, CFE_EVS_EventType_INFORMATION, "Build %s by %s@%s, config %s", BuildDate, BuildUser, BuildHost, GLOBAL_CONFIGDATA.Config);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error sending build info event:RC=0x%08X\n", "CFE_ES_GenerateBuildInfoEvents", Status);
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// EVERY FAILURE RETURNS EARLY AND LOGS, and the order matters: the syslog MODE is set before
// anything can log, EVS registration before anything can raise an event, the three telemetry
// packets before the pipe, and the pipe before the subscriptions. A reader can tell which step
// failed from the syslog line alone, which is the point of each one naming itself.
//
// THE SYSLOG MODE DEPENDS ON THE RESET TYPE. A power-on reset gets OVERWRITE (0) and a
// processor reset gets DISCARD (1) -- NASA's reasoning being that after a processor reset the
// log already holds the evidence of why, and overwriting it would lose that.
//
// THE CORE CHECKSUM IS 0xFFFF WHEN THE PSP CANNOT SAY. Not zero, and not an error return:
// CFE_ES_TaskInit succeeds either way, and the ground sees 0xFFFF in housekeeping.
I32 CFE_ES_TaskInit()
{
  I32 Status;
  I32 PspStatus;
  U32 SizeofCfeSegment;
  U64 CfeSegmentAddr;
  U8 VersionNumber[4];
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];
  /*
  ** Initialize task command execution counters
  */
  CFE_ES_Global.TaskData.CommandCounter = 0;
  CFE_ES_Global.TaskData.CommandErrorCounter = 0;
  /*
  ** Initialize systemlog to default Power On or Processor Reset mode
  */
  if (CFE_ES_GetResetType(NULL) == CFE_PSP_RST_TYPE_POWERON) {
    CFE_ES_Global.ResetDataPtr->SystemLogMode = CFE_PLATFORM_ES_DEFAULT_POR_SYSLOG_MODE;
  } else {
    CFE_ES_Global.ResetDataPtr->SystemLogMode = CFE_PLATFORM_ES_DEFAULT_PR_SYSLOG_MODE;
  }
  /*
  ** Register event filter table.
  */
  Status = CFE_EVS_Register(NULL, 0, CFE_EVS_EventFilter_BINARY);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Call to CFE_EVS_Register Failed, RC = 0x%08X\n", "CFE_ES_TaskInit", Status);
    return Status;
  }
  /*
  ** Initialize housekeeping packet (clear user data area)
  */
  CFE_MSG_Init(&CFE_ES_Global.TaskData.HkPacket.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CFE_ES_HK_TLM_MID), sizeof(CFE_ES_HousekeepingTlm_t));
  /*
  ** Initialize single application telemetry packet
  */
  CFE_MSG_Init(&CFE_ES_Global.TaskData.OneAppPacket.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CFE_ES_APP_TLM_MID), sizeof(CFE_ES_OneAppTlm_t));
  /*
  ** Initialize memory pool statistics telemetry packet
  */
  CFE_MSG_Init(&CFE_ES_Global.TaskData.MemStatsPacket.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CFE_ES_MEMSTATS_TLM_MID), sizeof(CFE_ES_MemStatsTlm_t));
  /*
  ** Create Software Bus message pipe
  */
  Status = CFE_SB_CreatePipe(&CFE_ES_Global.TaskData.CmdPipe, CFE_ES_PIPE_DEPTH, CFE_ES_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Cannot Create SB Pipe, RC = 0x%08X\n", "CFE_ES_TaskInit", Status);
    return Status;
  }
  /*
  ** Subscribe to Housekeeping request commands
  */
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_ES_SEND_HK_MID), CFE_ES_Global.TaskData.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Cannot Subscribe to HK packet, RC = 0x%08X\n", "CFE_ES_TaskInit", Status);
    return Status;
  }
  /*
  ** Subscribe to ES task ground command packets
  */
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_ES_CMD_MID), CFE_ES_Global.TaskData.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Cannot Subscribe to ES ground commands, RC = 0x%08X\n", "CFE_ES_TaskInit", Status);
    return Status;
  }
  /*
  ** Compute the CRC for the cfe core code segment and place
  ** in ES Housekeeping pkt.
  */
  PspStatus = CFE_PSP_GetCFETextSegmentInfo(&CfeSegmentAddr, &SizeofCfeSegment);
  if (PspStatus == CFE_PSP_SUCCESS) {
    CFE_ES_Global.TaskData.HkPacket.Payload.CFECoreChecksum = CFE_ES_CalculateCRC(CfeSegmentAddr, SizeofCfeSegment, 0, CFE_MISSION_ES_DEFAULT_CRC);
  } else {
    CFE_ES_Global.TaskData.HkPacket.Payload.CFECoreChecksum = 0xFFFF;
  }
  /*
  ** Initialize the version numbers in the ES Housekeeping pkt
  */
  CFE_ES_Global.TaskData.HkPacket.Payload.CFEMajorVersion = CFE_MAJOR_VERSION;
  CFE_ES_Global.TaskData.HkPacket.Payload.CFEMinorVersion = CFE_MINOR_VERSION;
  CFE_ES_Global.TaskData.HkPacket.Payload.CFERevision = CFE_REVISION;
  CFE_ES_Global.TaskData.HkPacket.Payload.CFEMissionRevision = CFE_MISSION_REV;
  OS_GetVersionNumber(VersionNumber);
  CFE_ES_Global.TaskData.HkPacket.Payload.OSALMajorVersion = VersionNumber[0];
  CFE_ES_Global.TaskData.HkPacket.Payload.OSALMinorVersion = VersionNumber[1];
  CFE_ES_Global.TaskData.HkPacket.Payload.OSALRevision = VersionNumber[2];
  CFE_ES_Global.TaskData.HkPacket.Payload.OSALMissionRevision = VersionNumber[3];
  CFE_PSP_GetVersionNumber(VersionNumber);
  CFE_ES_Global.TaskData.HkPacket.Payload.PSPMajorVersion = VersionNumber[0];
  CFE_ES_Global.TaskData.HkPacket.Payload.PSPMinorVersion = VersionNumber[1];
  CFE_ES_Global.TaskData.HkPacket.Payload.PSPRevision = VersionNumber[2];
  CFE_ES_Global.TaskData.HkPacket.Payload.PSPMissionRevision = VersionNumber[3];
  /*
  ** Task startup event message.
  */
  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "CFE_ES", CFE_SRC_VERSION, CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);
  Status = CFE_EVS_SendEvent(CFE_ES_INIT_INF_EID, CFE_EVS_EventType_INFORMATION, "cFE ES Initialized: %s", VersionString);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error sending init event:RC=0x%08X\n", "CFE_ES_TaskInit", Status);
    return Status;
  }
  Status = CFE_EVS_SendEvent(CFE_ES_INITSTATS_INF_EID, CFE_EVS_EventType_INFORMATION, "cFS Versions: cfe %s, osal %s, psp %s. cFE chksm %d", CFE_SRC_VERSION, OS_GetVersionString(), CFE_PSP_GetVersionString(), CFE_ES_Global.TaskData.HkPacket.Payload.CFECoreChecksum);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error sending init stats event:RC=0x%08X\n", "CFE_ES_TaskInit", Status);
    return Status;
  }
  /*
   * Generate all module version and build info events.
   */
  CFE_ES_GenerateVersionEvents();
  CFE_ES_GenerateBuildInfoEvents();
  /*
   * Initialize the "background task" which is a low priority child task
   * devoted to maintenance duties that do not need to execute on a
   * strict/precise schedule.
   */
  Status = CFE_ES_BackgroundInit();
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error initializing background task:RC=0x%08X\n", "CFE_ES_TaskInit", Status);
    return Status;
  }
  return CFE_SUCCESS;
}
// --- cfe_es_perf.h: the bit-in-a-byte-array helpers -------------------------------------------
// CFE_ES_TEST_U8_MASK is `static inline` in cfe_es_perf.h, not a function in a .c file, so it
// is DEFINED here rather than stubbed -- the C half gets the real body from NASA's header, and
// a recording stub would be the one place the two halves could disagree about which bit a
// performance id means. It belongs in cfe_es_perf.HC and moves there when cfe_es_perf.c is
// gated, the same way cfe_es_resource.HC took cfe_es_resource.h's accessors.
//
// CFE_ES_DBIT(x) is `((uint8)1 << (x))` and CFE_ES_DTEST(i,x) is `((i) & DBIT(x)) != 0`.
Bool CFE_ES_TEST_U8_MASK(U8 *m, U32 s)
{
  return ((m[s / 8] & (1 << (s % 8))) != 0);
}
// THE FOUR DERIVED BIT COUNTS ARE ALL 8, and the derivation is worth writing down because the
// macros look like they could be anything. NASA computes
//   BITS_PER_RESETDATA_OCTET = CFE_MISSION_ES_PERF_MAX_IDS / sizeof(Perf.MetaData.TriggerMask)
//   BITS_PER_RESETDATA_WORD  = sizeof(TriggerMask[0]) * BITS_PER_RESETDATA_OCTET
// and the same pair for the HK packet's own mask. Both masks are U8[CFE_MISSION_ES_PERF_MAX_IDS
// / 8] -- 16 bytes for 128 ids -- so 128/16 = 8 bits per octet, times sizeof(U8) = 1, is 8 bits
// per word in both. check_padding measures both arrays against NASA's compiler, which is what
// keeps that derivation true.
#define CFE_ES_PERF_BITS_PER_HKTLM_WORD 8
// CFE_ES_SET_HKTLM_PERF_MASK(f, s, v), spelled out: HolyC has no do/while(0) macro and the
// field is selected by name at each of the two call sites, so NASA's one macro becomes two
// functions that differ only in which array they touch.
U0 CFE_ES_SetHkTlmPerfTriggerMask(U32 s, Bool v)
{
  if (v)
    CFE_ES_Global.TaskData.HkPacket.Payload.PerfTriggerMask[s / CFE_ES_PERF_BITS_PER_HKTLM_WORD] |= (1 << (s % CFE_ES_PERF_BITS_PER_HKTLM_WORD));
  else
    CFE_ES_Global.TaskData.HkPacket.Payload.PerfTriggerMask[s / CFE_ES_PERF_BITS_PER_HKTLM_WORD] &= ~(1 << (s % CFE_ES_PERF_BITS_PER_HKTLM_WORD));
}

U0 CFE_ES_SetHkTlmPerfFilterMask(U32 s, Bool v)
{
  if (v)
    CFE_ES_Global.TaskData.HkPacket.Payload.PerfFilterMask[s / CFE_ES_PERF_BITS_PER_HKTLM_WORD] |= (1 << (s % CFE_ES_PERF_BITS_PER_HKTLM_WORD));
  else
    CFE_ES_Global.TaskData.HkPacket.Payload.PerfFilterMask[s / CFE_ES_PERF_BITS_PER_HKTLM_WORD] &= ~(1 << (s % CFE_ES_PERF_BITS_PER_HKTLM_WORD));
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THIS COMMAND DOES NOT COUNT, and NASA says so at the bottom: "This command does not affect
// the command execution counter." Housekeeping is a request from the scheduler, not a ground
// command, so counting it would make the counter a measure of uptime.
//
// A HEAP THE OSAL CANNOT REPORT GIVES ZEROES, not an error: CFE_ES_SendHkCmd always succeeds,
// and the ground sees three zeroes rather than a missing packet.
I32 CFE_ES_SendHkCmd(CFE_ES_SendHkCmd_t *data)
{
  OS_heap_prop_t HeapProp;
  I32 OsStatus;
  U32 PerfIdx;
  MemSet(&HeapProp, 0, sizeof(OS_heap_prop_t));
  /*
  ** Get command execution counters, system log entry count & bytes used.
  */
  CFE_ES_Global.TaskData.HkPacket.Payload.CommandCounter = CFE_ES_Global.TaskData.CommandCounter;
  CFE_ES_Global.TaskData.HkPacket.Payload.CommandErrorCounter = CFE_ES_Global.TaskData.CommandErrorCounter;
  // CFE_ES_MEMOFFSET_C on the next five assignments, a cast to CFE_ES_MemOffset_t. That is a
  // size_t, which is I64 here, and every destination field below is already declared I64 in
  // cfe_es_global.HC -- check_padding measures them against NASA's compiler -- so the cast has
  // nothing to do and is not written. Same reasoning as in cfe_es_api.HC's GetAppInfo.
  CFE_ES_Global.TaskData.HkPacket.Payload.SysLogBytesUsed = CFE_ES_Global.ResetDataPtr->SystemLogEndIdx;
  CFE_ES_Global.TaskData.HkPacket.Payload.SysLogSize = CFE_PLATFORM_ES_SYSTEM_LOG_SIZE;
  CFE_ES_Global.TaskData.HkPacket.Payload.SysLogEntries = CFE_ES_Global.ResetDataPtr->SystemLogEntryNum;
  CFE_ES_Global.TaskData.HkPacket.Payload.SysLogMode = CFE_ES_Global.ResetDataPtr->SystemLogMode;
  CFE_ES_Global.TaskData.HkPacket.Payload.ERLogIndex = CFE_ES_Global.ResetDataPtr->ERLogIndex;
  CFE_ES_Global.TaskData.HkPacket.Payload.ERLogEntries = CFE_ES_Global.ResetDataPtr->ERLogEntries;
  CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredCoreApps = CFE_ES_Global.RegisteredCoreApps;
  CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredExternalApps = CFE_ES_Global.RegisteredExternalApps;
  CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredTasks = CFE_ES_Global.RegisteredTasks;
  CFE_ES_Global.TaskData.HkPacket.Payload.RegisteredLibs = CFE_ES_Global.RegisteredLibs;
  CFE_ES_Global.TaskData.HkPacket.Payload.ResetType = CFE_ES_Global.ResetDataPtr->ResetVars.ResetType;
  CFE_ES_Global.TaskData.HkPacket.Payload.ResetSubtype = CFE_ES_Global.ResetDataPtr->ResetVars.ResetSubtype;
  CFE_ES_Global.TaskData.HkPacket.Payload.ProcessorResets = CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount;
  CFE_ES_Global.TaskData.HkPacket.Payload.MaxProcessorResets = CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount;
  CFE_ES_Global.TaskData.HkPacket.Payload.BootSource = CFE_ES_Global.ResetDataPtr->ResetVars.BootSource;
  CFE_ES_Global.TaskData.HkPacket.Payload.PerfState = CFE_ES_Global.ResetDataPtr->Perf.MetaData.State;
  CFE_ES_Global.TaskData.HkPacket.Payload.PerfMode = CFE_ES_Global.ResetDataPtr->Perf.MetaData.Mode;
  CFE_ES_Global.TaskData.HkPacket.Payload.PerfTriggerCount = CFE_ES_Global.ResetDataPtr->Perf.MetaData.TriggerCount;
  CFE_ES_Global.TaskData.HkPacket.Payload.PerfDataStart = CFE_ES_Global.ResetDataPtr->Perf.MetaData.DataStart;
  CFE_ES_Global.TaskData.HkPacket.Payload.PerfDataEnd = CFE_ES_Global.ResetDataPtr->Perf.MetaData.DataEnd;
  CFE_ES_Global.TaskData.HkPacket.Payload.PerfDataCount = CFE_ES_Global.ResetDataPtr->Perf.MetaData.DataCount;
  CFE_ES_Global.TaskData.HkPacket.Payload.PerfDataToWrite = CFE_ES_GetPerfLogDumpRemaining();
  /*
   * Copy the performance trigger and filter masks into the HK telemetry packet
   * one performance ID (bit) at a time. The internal reset-data masks and the HK
   * packet masks are both sized from CFE_MISSION_ES_PERF_MAX_IDS, which is a
   * multiple of 8 (enforced in cfe_es_verify.h), so every ID maps onto a valid
   * bit in both arrays and is copied directly with no need to pad or truncate.
   */
  for (PerfIdx = 0; PerfIdx < CFE_MISSION_ES_PERF_MAX_IDS; ++PerfIdx) {
    CFE_ES_SetHkTlmPerfTriggerMask(PerfIdx, CFE_ES_TEST_U8_MASK(CFE_ES_Global.ResetDataPtr->Perf.MetaData.TriggerMask, PerfIdx));
  }
  /* Filter mask, populated the same way as the trigger mask above */
  for (PerfIdx = 0; PerfIdx < CFE_MISSION_ES_PERF_MAX_IDS; ++PerfIdx) {
    CFE_ES_SetHkTlmPerfFilterMask(PerfIdx, CFE_ES_TEST_U8_MASK(CFE_ES_Global.ResetDataPtr->Perf.MetaData.FilterMask, PerfIdx));
  }
  /* Fill in heap info if get successful/supported */
  OsStatus = OS_HeapGetInfo(&HeapProp);
  if (OsStatus == OS_SUCCESS) {
    CFE_ES_Global.TaskData.HkPacket.Payload.HeapBytesFree = HeapProp.free_bytes;
    CFE_ES_Global.TaskData.HkPacket.Payload.HeapBlocksFree = HeapProp.free_blocks;
    CFE_ES_Global.TaskData.HkPacket.Payload.HeapMaxBlockSize = HeapProp.largest_free_block;
  } else {
    CFE_ES_Global.TaskData.HkPacket.Payload.HeapBytesFree = 0;
    CFE_ES_Global.TaskData.HkPacket.Payload.HeapBlocksFree = 0;
    CFE_ES_Global.TaskData.HkPacket.Payload.HeapMaxBlockSize = 0;
  }
  /*
  ** Send housekeeping telemetry packet.
  */
  CFE_SB_TimeStampMsg(&CFE_ES_Global.TaskData.HkPacket.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&CFE_ES_Global.TaskData.HkPacket.TelemetryHeader.Msg, TRUE);
  /*
  ** This command does not affect the command execution counter.
  */
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE BUILD EVENT COMES FIRST, and NASA says why in a comment that is really a note to the
// unit test: "For unit testing purposes, it helps to put this first - the UT is checking for
// the last event sent to be NOOP_INF_EID." So the order of two events is load-bearing.
I32 CFE_ES_NoopCmd(CFE_ES_NoopCmd_t *Cmd)
{
  /*
  ** Advertise the build and version information with the no-op command
  ** For unit testing purposes, it helps to put this first - the UT
  ** is checking for the last event sent to be NOOP_INF_EID.
  */
  CFE_ES_GenerateBuildInfoEvents();
  /*
  ** This command will always succeed.
  */
  CFE_ES_Global.TaskData.CommandCounter++;
  CFE_EVS_SendEvent(CFE_ES_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION, "No-op command:\n cFS Versions: cfe %s, osal %s, psp %s", CFE_SRC_VERSION, OS_GetVersionString(), CFE_PSP_GetVersionString());
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// IT DOES NOT COUNT ITSELF. Zeroing both counters and then incrementing CommandCounter would
// report 1, so NASA zeroes and sends the event without counting -- the ground's next
// housekeeping packet shows 0/0, which is what "reset counters" means.
I32 CFE_ES_ResetCountersCmd(CFE_ES_ResetCountersCmd_t *data)
{
  CFE_ES_Global.TaskData.CommandCounter = 0;
  CFE_ES_Global.TaskData.CommandErrorCounter = 0;
  /*
  ** This command will always succeed.
  */
  CFE_EVS_SendEvent(CFE_ES_RESET_INF_EID, CFE_EVS_EventType_INFORMATION, "Reset Counters command");
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE SUCCESS PATH NEVER INCREMENTS THE COMMAND COUNTER, because CFE_ES_ResetCFE does not
// return: the processor is gone before the counter could be written, let alone downlinked.
// Only the REFUSAL is counted, as an error.
I32 CFE_ES_RestartCmd(CFE_ES_RestartCmd_t *data)
{
  CFE_ES_RestartCmd_Payload_t *cmd = &data->Payload;
  if ((cmd->RestartType != CFE_PSP_RST_TYPE_PROCESSOR) && (cmd->RestartType != CFE_PSP_RST_TYPE_POWERON)) {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_BOOT_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid cFE restart type: %d", cmd->RestartType);
  } else {
    /*
    ** This function will not return.
    */
    CFE_ES_ResetCFE(cmd->RestartType);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// FIVE WAYS TO REFUSE AND EACH HAS ITS OWN EVENT. The three string arguments are copied out of
// the message FIRST, before any of them is checked, because CFE_SB_MessageStringGet is what
// bounds them -- a ground message is not NUL-terminated by anything but luck, and the length
// it returns is what "empty" and "too long" are decided from.
//
// THE RETURN IS ALWAYS CFE_SUCCESS. Every one of the six outcomes returns CFE_SUCCESS; what
// distinguishes them is which counter moved and which event went out. That is the shape of
// every ground command in this file: the return value goes to the dispatcher, which only cares
// that the handler ran.
//
// A ZERO STACK SIZE MEANS "DEFAULT", not an error -- NASA's comment is "If stack size was
// provided, use it, otherwise use default."
I32 CFE_ES_StartAppCmd(CFE_ES_StartAppCmd_t *data)
{
  CFE_ES_StartAppCmd_Payload_t *cmd = &data->Payload;
  U32 AppID;
  I32 Result;
  I32 AppEntryLen;
  I32 AppNameLen;
  U8 LocalAppName[OS_MAX_API_NAME];
  CFE_ES_AppStartParams_t StartParams;
  MemSet(&StartParams, 0, sizeof(CFE_ES_AppStartParams_t));
  /* Create local copies of all input strings and ensure null termination */
  Result = CFE_FS_ParseInputFileNameEx(StartParams.BasicInfo.FileName, cmd->AppFileName, OS_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, NULL, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_DYNAMIC_MODULE), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_DYNAMIC_MODULE));
  AppEntryLen = CFE_SB_MessageStringGet(StartParams.BasicInfo.InitSymbolName, cmd->AppEntryPoint, NULL, OS_MAX_API_NAME, CFE_MISSION_MAX_API_LEN);
  AppNameLen = CFE_SB_MessageStringGet(LocalAppName, cmd->Application, NULL, OS_MAX_API_NAME, CFE_MISSION_MAX_API_LEN);
  /*
  ** Verify command parameters
  */
  if (Result != CFE_SUCCESS) {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_START_INVALID_FILENAME_ERR_EID, CFE_EVS_EventType_ERROR, "CFE_ES_StartAppCmd: invalid filename, status=%lx", Result);
  } else if (AppEntryLen <= 0) {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_START_INVALID_ENTRY_POINT_ERR_EID, CFE_EVS_EventType_ERROR, "CFE_ES_StartAppCmd: App Entry Point is empty.");
  } else if (AppNameLen <= 0) {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_START_NULL_APP_NAME_ERR_EID, CFE_EVS_EventType_ERROR, "CFE_ES_StartAppCmd: App Name is empty.");
  } else if (cmd->Priority > OS_MAX_PRIORITY) {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_START_PRIORITY_ERR_EID, CFE_EVS_EventType_ERROR, "CFE_ES_StartAppCmd: Priority is too large: %d.", cmd->Priority);
  } else if ((cmd->ExceptionAction != CFE_ES_ExceptionAction_RESTART_APP) && (cmd->ExceptionAction != CFE_ES_ExceptionAction_PROC_RESTART)) {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_START_EXC_ACTION_ERR_EID, CFE_EVS_EventType_ERROR, "CFE_ES_StartAppCmd: Invalid Exception Action: %d.", cmd->ExceptionAction);
  } else {
    /* If stack size was provided, use it, otherwise use default. */
    // CFE_ES_MEMOFFSET_TO_SIZET, a cast to size_t -- I64 here, and StackSize is already I64.
    StartParams.MainTaskInfo.StackSize = cmd->StackSize;
    if (StartParams.MainTaskInfo.StackSize == 0) {
      StartParams.MainTaskInfo.StackSize = CFE_PLATFORM_ES_DEFAULT_STACK_SIZE;
    }
    StartParams.MainTaskInfo.Priority = cmd->Priority;
    StartParams.ExceptionAction = cmd->ExceptionAction;
    /*
    ** Invoke application loader/startup function.
    */
    Result = CFE_ES_AppCreate(&AppID, LocalAppName, &StartParams);
    /*
    ** Send appropriate event message
    */
    if (Result == CFE_SUCCESS) {
      CFE_ES_Global.TaskData.CommandCounter++;
      CFE_EVS_SendEvent(CFE_ES_START_INF_EID, CFE_EVS_EventType_INFORMATION, "Started %s from %s, AppID = %lu", LocalAppName, StartParams.BasicInfo.FileName, AppID);
    } else {
      CFE_ES_Global.TaskData.CommandErrorCounter++;
      CFE_EVS_SendEvent(CFE_ES_START_ERR_EID, CFE_EVS_EventType_ERROR, "Failed to start %s from %s, RC = 0x%08X", LocalAppName, StartParams.BasicInfo.FileName, Result);
    }
  }
  /* End if -- command parameter validation */
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE SAME THREE-WAY SHAPE AS THE NEXT TWO: look the name up, act on the id, and report. The
// two failures get DIFFERENT events -- ERR1 for "the operation failed" and ERR2 for "there is
// no such app" -- so the ground can tell a name it got wrong from a name that stopped working.
I32 CFE_ES_StopAppCmd(CFE_ES_StopAppCmd_t *data)
{
  CFE_ES_AppNameCmd_Payload_t *cmd = &data->Payload;
  U8 LocalApp[OS_MAX_API_NAME];
  U32 AppID;
  I32 Result;
  CFE_SB_MessageStringGet(LocalApp, cmd->Application, NULL, OS_MAX_API_NAME, CFE_MISSION_MAX_API_LEN);
  Result = CFE_ES_GetAppIDByName(&AppID, LocalApp);
  if (Result == CFE_SUCCESS) {
    /*
    ** Delete the App
    */
    Result = CFE_ES_DeleteApp(AppID);
    /*
    ** Send appropriate event message.
    */
    if (Result == CFE_SUCCESS) {
      CFE_ES_Global.TaskData.CommandCounter++;
      CFE_EVS_SendEvent(CFE_ES_STOP_DBG_EID, CFE_EVS_EventType_DEBUG, "Stop Application %s Initiated.", LocalApp);
    } else {
      CFE_ES_Global.TaskData.CommandErrorCounter++;
      CFE_EVS_SendEvent(CFE_ES_STOP_ERR1_EID, CFE_EVS_EventType_ERROR, "Stop Application %s Failed, RC = 0x%08X", LocalApp, Result);
    }
  } else {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_STOP_ERR2_EID, CFE_EVS_EventType_ERROR, "Stop Application %s, GetAppIDByName failed. RC = 0x%08X.", LocalApp, Result);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_RestartAppCmd(CFE_ES_RestartAppCmd_t *data)
{
  CFE_ES_AppNameCmd_Payload_t *cmd = &data->Payload;
  U8 LocalApp[OS_MAX_API_NAME];
  U32 AppID;
  I32 Result;
  CFE_SB_MessageStringGet(LocalApp, cmd->Application, NULL, OS_MAX_API_NAME, CFE_MISSION_MAX_API_LEN);
  Result = CFE_ES_GetAppIDByName(&AppID, LocalApp);
  if (Result == CFE_SUCCESS) {
    Result = CFE_ES_RestartApp(AppID);
    /*
    ** Send appropriate event message.
    */
    if (Result == CFE_SUCCESS) {
      CFE_ES_Global.TaskData.CommandCounter++;
      CFE_EVS_SendEvent(CFE_ES_RESTART_APP_DBG_EID, CFE_EVS_EventType_DEBUG, "Restart Application %s Initiated.", LocalApp);
    } else {
      CFE_ES_Global.TaskData.CommandErrorCounter++;
      CFE_EVS_SendEvent(CFE_ES_RESTART_APP_ERR1_EID, CFE_EVS_EventType_ERROR, "Restart Application %s Failed, RC = 0x%08X", LocalApp, Result);
    }
  } else {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_RESTART_APP_ERR2_EID, CFE_EVS_EventType_ERROR, "Restart Application %s, GetAppIDByName failed. RC = 0x%08X.", LocalApp, Result);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// A BAD FILENAME AND A FAILED RELOAD SHARE ONE EVENT. Result is reused for both the filename
// parse and the reload, so ERR1's "Reload Application %s Failed" covers a malformed path as
// well as a reload that was refused -- the status code in the message is the only thing that
// separates them.
I32 CFE_ES_ReloadAppCmd(CFE_ES_ReloadAppCmd_t *data)
{
  CFE_ES_AppReloadCmd_Payload_t *cmd = &data->Payload;
  U8 LocalApp[OS_MAX_API_NAME];
  U8 LocalFileName[OS_MAX_PATH_LEN];
  U32 AppID;
  I32 Result;
  CFE_SB_MessageStringGet(LocalApp, cmd->Application, NULL, OS_MAX_API_NAME, CFE_MISSION_MAX_API_LEN);
  Result = CFE_ES_GetAppIDByName(&AppID, LocalApp);
  if (Result == CFE_SUCCESS) {
    /* Read input string as a file name for dynamic module */
    Result = CFE_FS_ParseInputFileNameEx(LocalFileName, cmd->AppFileName, OS_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, NULL, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_DYNAMIC_MODULE), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_DYNAMIC_MODULE));
    if (Result == CFE_SUCCESS) {
      Result = CFE_ES_ReloadApp(AppID, LocalFileName);
    }
    /*
    ** Send appropriate event message.
    */
    if (Result == CFE_SUCCESS) {
      CFE_ES_Global.TaskData.CommandCounter++;
      CFE_EVS_SendEvent(CFE_ES_RELOAD_APP_DBG_EID, CFE_EVS_EventType_DEBUG, "Reload Application %s Initiated.", LocalApp);
    } else {
      CFE_ES_Global.TaskData.CommandErrorCounter++;
      CFE_EVS_SendEvent(CFE_ES_RELOAD_APP_ERR1_EID, CFE_EVS_EventType_ERROR, "Reload Application %s Failed, RC = 0x%08X", LocalApp, Result);
    }
  } else {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_RELOAD_APP_ERR2_EID, CFE_EVS_EventType_ERROR, "Reload Application %s, GetAppIDByName failed. RC = 0x%08X.", LocalApp, Result);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// A UNION OF THREE IDS, and it is the point of the function rather than a convenience: a name
// might belong to an APP or to a LIBRARY, and CFE_ES_GetModuleInfo dispatches on the base bits
// that tell them apart. So the lookup writes whichever member matched and the generic member
// is what is passed on.
I32 CFE_ES_QueryOneCmd(CFE_ES_QueryOneCmd_t *data)
{
  CFE_ES_AppNameCmd_Payload_t *cmd = &data->Payload;
  U8 LocalApp[OS_MAX_API_NAME];
  // The union is three names for one U32 in the SIMPLE resourceid variant, so it is one
  // variable here. check_structs.py measures NASA's unions; this one is a LOCAL, which no gate
  // reads, and collapsing it is safe only because all three members are the same width --
  // which cfe_resourceid.HC's CFE_ResourceId_t being a bare U32 is what guarantees.
  U32 IdBuf;
  I32 Result;
  CFE_SB_MessageStringGet(LocalApp, cmd->Application, NULL, OS_MAX_API_NAME, CFE_MISSION_MAX_API_LEN);
  Result = CFE_ES_GetAppIDByName(&IdBuf, LocalApp);
  if (Result == CFE_ES_ERR_NAME_NOT_FOUND) {
    /* Also check for a matching library name */
    Result = CFE_ES_GetLibIDByName(&IdBuf, LocalApp);
  }
  if (Result == CFE_SUCCESS) {
    Result = CFE_ES_GetModuleInfo(&CFE_ES_Global.TaskData.OneAppPacket.Payload.AppInfo, IdBuf);
  }
  /*
  ** Send appropriate event message...
  */
  if (Result == CFE_SUCCESS) {
    /*
    ** Send application status telemetry packet.
    */
    CFE_SB_TimeStampMsg(&CFE_ES_Global.TaskData.OneAppPacket.TelemetryHeader.Msg);
    Result = CFE_SB_TransmitMsg(&CFE_ES_Global.TaskData.OneAppPacket.TelemetryHeader.Msg, TRUE);
    if (Result == CFE_SUCCESS) {
      CFE_ES_Global.TaskData.CommandCounter++;
      CFE_EVS_SendEvent(CFE_ES_ONE_APP_EID, CFE_EVS_EventType_DEBUG, "Sent %s application data", LocalApp);
    } else {
      CFE_ES_Global.TaskData.CommandErrorCounter++;
      CFE_EVS_SendEvent(CFE_ES_ONE_ERR_EID, CFE_EVS_EventType_ERROR, "Failed to send %s application data, RC = 0x%08X", LocalApp, Result);
    }
  } else {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_ONE_APPID_ERR_EID, CFE_EVS_EventType_ERROR, "Failed to send %s application data: GetAppIDByName Failed, RC = 0x%08X", LocalApp, Result);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE IDS ARE COLLECTED UNDER THE LOCK AND THE FILE IS WRITTEN WITHOUT IT, and NASA's comment
// says exactly that: "This should be done while locked, but the actual writing of the AppInfo
// data should be done while NOT locked." Writing a file is an OSAL call of unbounded duration
// and ES's lock protects every other module's error path.
//
// THE CONSEQUENCE IS A RACE NASA ACCEPTS: an app deleted between the scan and the write makes
// CFE_ES_GetModuleInfo fail for that id, and the loop simply skips it -- EntryCount is what
// went in the file, not what was in the table.
//
// AND A WRITE FAILURE RETURNS CFE_SUCCESS. NASA's comment is "returning 'success' here as
// there is no other recourse; the full extent of the error recovery has been done" -- the
// error counter and the event are the report; the return value goes to the dispatcher.
I32 CFE_ES_QueryAllCmd(CFE_ES_QueryAllCmd_t *data)
{
  CFE_FS_Header_t FileHeader;
  U32 FileDescriptor = OS_OBJECT_ID_UNDEFINED;
  U32 i;
  U32 EntryCount = 0;
  I64 FileSize = 0;
  I32 OsStatus;
  I32 Result;
  CFE_ES_AppInfo_t AppInfo;
  CFE_ES_FileNameCmd_Payload_t *CmdPtr = &data->Payload;
  U8 QueryAllFilename[OS_MAX_PATH_LEN];
  U32 ResourceList[CFE_ES_QUERY_ALL_MAX_ENTRIES];
  U32 NumResources;
  CFE_ES_AppRecord_t *AppRecPtr;
  CFE_ES_LibRecord_t *LibRecPtr;
  /*
   * Collect list of active resource IDs.
   *
   * This should be done while locked, but the actual writing
   * of the AppInfo data should be done while NOT locked.
   */
  CFE_ES_LockSharedData("CFE_ES_QueryAllCmd", 1063);
  NumResources = 0;
  AppRecPtr = CFE_ES_Global.AppTable;
  for (i = 0; i < CFE_PLATFORM_ES_MAX_APPLICATIONS; ++i) {
    if (CFE_ES_AppRecordIsUsed(AppRecPtr)) {
      ResourceList[NumResources] = CFE_ES_AppRecordGetID(AppRecPtr);
      ++NumResources;
    }
    ++AppRecPtr;
  }
  LibRecPtr = CFE_ES_Global.LibTable;
  for (i = 0; i < CFE_PLATFORM_ES_MAX_LIBRARIES; ++i) {
    if (CFE_ES_LibRecordIsUsed(LibRecPtr)) {
      ResourceList[NumResources] = CFE_ES_LibRecordGetID(LibRecPtr);
      ++NumResources;
    }
    ++LibRecPtr;
  }
  CFE_ES_UnlockSharedData("CFE_ES_QueryAllCmd", 1085);
  /* Copy the commanded filename, using default if unspecified */
  Result = CFE_FS_ParseInputFileNameEx(QueryAllFilename, CmdPtr->FileName, OS_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, CFE_PLATFORM_ES_DEFAULT_APP_LOG_FILE, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_BINARY_DATA_DUMP), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_BINARY_DATA_DUMP));
  if (Result == CFE_SUCCESS) {
    /*
    ** Create (or truncate) ES task log data file
    */
    OsStatus = OS_OpenCreate(&FileDescriptor, QueryAllFilename, OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE, OS_WRITE_ONLY);
    if (OsStatus != OS_SUCCESS) {
      CFE_EVS_SendEvent(CFE_ES_OSCREATE_ERR_EID, CFE_EVS_EventType_ERROR, "Failed to write App Info file, OS_OpenCreate RC = %ld", OsStatus);
      Result = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }
  } else {
    CFE_EVS_SendEvent(CFE_ES_OSCREATE_ERR_EID, CFE_EVS_EventType_ERROR, "Failed to write App Info file, CFE_FS_ParseInputFileNameEx RC = %08x", Result);
  }
  if (Result >= 0) {
    /*
    ** Initialize cFE file header
    */
    CFE_FS_InitHeader(&FileHeader, CFE_ES_APP_LOG_DESC, CFE_FS_SubType_ES_QUERYALL);
    /*
    ** Output the Standard cFE File Header to the App File
    */
    Result = CFE_FS_WriteHeader(FileDescriptor, &FileHeader);
    if (Result != sizeof(CFE_FS_Header_t)) {
      OS_close(FileDescriptor);
      CFE_ES_Global.TaskData.CommandErrorCounter++;
      CFE_EVS_SendEvent(CFE_ES_WRHDR_ERR_EID, CFE_EVS_EventType_ERROR, "Failed to write App Info file, WriteHdr RC = 0x%08X, exp %d", Result, sizeof(CFE_FS_Header_t));
      /*
       * returning "success" here as there is no other recourse;
       * the full extent of the error recovery has been done
       */
      return CFE_SUCCESS;
    }
    /*
    ** Maintain statistics of amount of data written to file
    */
    FileSize += sizeof(CFE_FS_Header_t);
    /*
    ** Loop through the ES AppTable for main applications
    */
    for (i = 0; i < NumResources; ++i) {
      /*
       ** Populate the AppInfo entry
       */
      Result = CFE_ES_GetModuleInfo(&AppInfo, ResourceList[i]);
      if (Result == CFE_SUCCESS) {
        /*
        ** Write the local entry to file
        */
        OsStatus = OS_write(FileDescriptor, &AppInfo, sizeof(CFE_ES_AppInfo_t));
        if (OsStatus != sizeof(CFE_ES_AppInfo_t)) {
          OS_close(FileDescriptor);
          CFE_ES_Global.TaskData.CommandErrorCounter++;
          CFE_EVS_SendEvent(CFE_ES_TASKWR_ERR_EID, CFE_EVS_EventType_ERROR, "Failed to write App Info file, Task write RC = %ld, exp %d", OsStatus, sizeof(CFE_ES_AppInfo_t));
          /*
           * returning "success" here as there is no other recourse;
           * the full extent of the error recovery has been done
           */
          return CFE_SUCCESS;
        }
        FileSize += sizeof(CFE_ES_AppInfo_t);
        EntryCount++;
      }
    }
    /* end for */
    OS_close(FileDescriptor);
    CFE_ES_Global.TaskData.CommandCounter++;
    CFE_EVS_SendEvent(CFE_ES_ALL_APPS_EID, CFE_EVS_EventType_DEBUG, "App Info file written to %s, Entries=%d, FileSize=%lu", QueryAllFilename, EntryCount, FileSize);
  } else {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE SAME SHAPE AS CFE_ES_QueryAllCmd ABOVE, ONE TABLE INSTEAD OF TWO, and with its own four
// event ids so a failure says which file it was writing. The duplication is NASA's; a reader
// comparing the two should find them identical except for the table, the record type, the
// subtype and the events.
I32 CFE_ES_QueryAllTasksCmd(CFE_ES_QueryAllTasksCmd_t *data)
{
  CFE_FS_Header_t FileHeader;
  U32 FileDescriptor = OS_OBJECT_ID_UNDEFINED;
  U32 i;
  U32 EntryCount = 0;
  I64 FileSize = 0;
  I32 OsStatus;
  I32 Result;
  CFE_ES_TaskInfo_t TaskInfo;
  CFE_ES_FileNameCmd_Payload_t *CmdPtr = &data->Payload;
  U8 QueryAllFilename[OS_MAX_PATH_LEN];
  U32 TaskList[OS_MAX_TASKS];
  U32 NumTasks;
  CFE_ES_TaskRecord_t *TaskRecPtr;
  /*
   * Collect list of active task IDs.
   *
   * This should be done while locked, but the actual writing
   * of the AppInfo data should be done while NOT locked.
   */
  CFE_ES_LockSharedData("CFE_ES_QueryAllTasksCmd", 1238);
  NumTasks = 0;
  TaskRecPtr = CFE_ES_Global.TaskTable;
  for (i = 0; i < OS_MAX_TASKS; ++i) {
    if (CFE_ES_TaskRecordIsUsed(TaskRecPtr)) {
      TaskList[NumTasks] = CFE_ES_TaskRecordGetID(TaskRecPtr);
      ++NumTasks;
    }
    ++TaskRecPtr;
  }
  CFE_ES_UnlockSharedData("CFE_ES_QueryAllTasksCmd", 1250);
  /*
  ** Copy the commanded filename into local buffer to ensure size limitation and to allow for
  *modification
  */
  Result = CFE_FS_ParseInputFileNameEx(QueryAllFilename, CmdPtr->FileName, OS_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, CFE_PLATFORM_ES_DEFAULT_TASK_LOG_FILE, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_BINARY_DATA_DUMP), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_BINARY_DATA_DUMP));
  if (Result == CFE_SUCCESS) {
    /*
    ** Create (or truncate) ES task log data file
    */
    OsStatus = OS_OpenCreate(&FileDescriptor, QueryAllFilename, OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE, OS_WRITE_ONLY);
    if (OsStatus != OS_SUCCESS) {
      CFE_EVS_SendEvent(CFE_ES_TASKINFO_OSCREATE_ERR_EID, CFE_EVS_EventType_ERROR, "Failed to write Task Info file, OS_OpenCreate RC = %ld", OsStatus);
      Result = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }
  } else {
    CFE_EVS_SendEvent(CFE_ES_TASKINFO_OSCREATE_ERR_EID, CFE_EVS_EventType_ERROR, "Failed to write Task Info file, CFE_FS_ParseInputFileNameEx RC = %08x", Result);
  }
  if (Result >= 0) {
    /*
    ** Initialize cFE file header
    */
    CFE_FS_InitHeader(&FileHeader, CFE_ES_TASK_LOG_DESC, CFE_FS_SubType_ES_QUERYALLTASKS);
    /*
    ** Output the Standard cFE File Header to the App File
    */
    Result = CFE_FS_WriteHeader(FileDescriptor, &FileHeader);
    if (Result != sizeof(CFE_FS_Header_t)) {
      OS_close(FileDescriptor);
      CFE_ES_Global.TaskData.CommandErrorCounter++;
      CFE_EVS_SendEvent(CFE_ES_TASKINFO_WRHDR_ERR_EID, CFE_EVS_EventType_ERROR, "Failed to write Task Info file, WriteHdr RC = 0x%08X, exp %d", Result, sizeof(CFE_FS_Header_t));
      /*
       * returning "success" here as there is no other recourse;
       * the full extent of the error recovery has been done
       */
      return CFE_SUCCESS;
    }
    /*
    ** Maintain statistics of amount of data written to file
    */
    FileSize += sizeof(CFE_FS_Header_t);
    /*
    ** Loop through the ES AppTable for main applications
    */
    for (i = 0; i < NumTasks; ++i) {
      /*
      ** Populate the AppInfo entry
      */
      Result = CFE_ES_GetTaskInfo(&TaskInfo, TaskList[i]);
      if (Result == CFE_SUCCESS) {
        /*
        ** Write the local entry to file
        */
        OsStatus = OS_write(FileDescriptor, &TaskInfo, sizeof(CFE_ES_TaskInfo_t));
        if (OsStatus != sizeof(CFE_ES_TaskInfo_t)) {
          OS_close(FileDescriptor);
          CFE_ES_Global.TaskData.CommandErrorCounter++;
          CFE_EVS_SendEvent(CFE_ES_TASKINFO_WR_ERR_EID, CFE_EVS_EventType_ERROR, "Failed to write Task Info file, Task write RC = %ld, exp %d", OsStatus, sizeof(CFE_ES_TaskInfo_t));
          /*
           * returning "success" here as there is no other recourse;
           * the full extent of the error recovery has been done
           */
          return CFE_SUCCESS;
        }
        FileSize += sizeof(CFE_ES_TaskInfo_t);
        EntryCount++;
      }
    }
    /* end for */
    OS_close(FileDescriptor);
    CFE_ES_Global.TaskData.CommandCounter++;
    CFE_EVS_SendEvent(CFE_ES_TASKINFO_EID, CFE_EVS_EventType_DEBUG, "Task Info file written to %s, Entries=%d, FileSize=%lu", QueryAllFilename, EntryCount, FileSize);
  } else {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_ClearSysLogCmd(CFE_ES_ClearSysLogCmd_t *data)
{
  /*
  ** Clear syslog index and memory area
  */
  CFE_ES_LockSharedData("CFE_ES_ClearSysLogCmd", 1389);
  CFE_ES_SysLogClear_Unsync();
  CFE_ES_UnlockSharedData("CFE_ES_ClearSysLogCmd", 1391);
  /*
  ** This command will always succeed...
  */
  CFE_ES_Global.TaskData.CommandCounter++;
  CFE_EVS_SendEvent(CFE_ES_SYSLOG1_INF_EID, CFE_EVS_EventType_INFORMATION, "Cleared Executive Services log data");
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_OverWriteSysLogCmd(CFE_ES_OverWriteSysLogCmd_t *data)
{
  I32 Status;
  CFE_ES_OverWriteSysLogCmd_Payload_t *CmdPtr = &data->Payload;
  Status = CFE_ES_SysLogSetMode(CmdPtr->Mode);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(CFE_ES_ERR_SYSLOGMODE_EID, CFE_EVS_EventType_ERROR, "Set OverWriteSysLog Command: Invalid Mode setting = %d", CmdPtr->Mode);
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  } else {
    CFE_EVS_SendEvent(CFE_ES_SYSLOGMODE_EID, CFE_EVS_EventType_DEBUG, "Set OverWriteSysLog Command Received with Mode setting = %d", CmdPtr->Mode);
    CFE_ES_Global.TaskData.CommandCounter++;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THIS ONE WRITES SYNCHRONOUSLY and the ER log command below does not, which is the only real
// difference between the two: CFE_ES_SysLogDump blocks the ES task for the length of the dump,
// where CFE_ES_WriteERLogCmd hands the work to FS's background writer. NASA's note on the file
// category is the other thing worth keeping: "even though this fundamentally contains strings,
// it is written as a binary file with an FS header, not as normal text file."
I32 CFE_ES_WriteSysLogCmd(CFE_ES_WriteSysLogCmd_t *data)
{
  CFE_ES_FileNameCmd_Payload_t *CmdPtr = &data->Payload;
  I32 Stat;
  U8 LogFilename[OS_MAX_PATH_LEN];
  /*
  ** Copy the filename into local buffer with default name/path/extension if not specified
  **
  ** Note even though this fundamentally contains strings, it is written as a binary file with
  *an FS header, not as normal text file, so still using the BINARY DATA DUMP category for its
  *default extension.
  */
  Stat = CFE_FS_ParseInputFileNameEx(LogFilename, CmdPtr->FileName, OS_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, CFE_PLATFORM_ES_DEFAULT_SYSLOG_FILE, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_BINARY_DATA_DUMP), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_BINARY_DATA_DUMP));
  if (Stat != CFE_SUCCESS) {
    CFE_EVS_SendEvent(CFE_ES_SYSLOG2_ERR_EID, CFE_EVS_EventType_ERROR, "Error parsing file name RC = 0x%08X", Stat);
  } else {
    Stat = CFE_ES_SysLogDump(LogFilename);
  }
  if (Stat == CFE_SUCCESS) {
    CFE_ES_Global.TaskData.CommandCounter++;
  } else {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// IT CLEARS THE BUFFER AS WELL AS THE INDEX, which the syslog's own clear does not: the ER log
// is a fixed array of records rather than a ring of bytes, so an index reset alone would leave
// the old entries readable by anything that walked the array instead of the index.
I32 CFE_ES_ClearERLogCmd(CFE_ES_ClearERLogCmd_t *data)
{
  /*
  ** Clear ER log data buffer
  */
  MemSet(CFE_ES_Global.ResetDataPtr->ERLog, 0, sizeof(CFE_ES_ERLog_MetaData_t) * CFE_PLATFORM_ES_ER_LOG_ENTRIES);
  /*
  ** Reset ER log buffer index
  */
  CFE_ES_Global.ResetDataPtr->ERLogIndex = 0;
  /*
  ** Set Number of Entries in ER log buffer back to zero
  */
  CFE_ES_Global.ResetDataPtr->ERLogEntries = 0;
  /*
  ** This command will always succeed
  */
  CFE_ES_Global.TaskData.CommandCounter++;
  CFE_EVS_SendEvent(CFE_ES_ERLOG1_INF_EID, CFE_EVS_EventType_INFORMATION, "Cleared ES Exception and Reset Log data");
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE PENDING CHECK COMES BEFORE THE MEMSET and NASA's comment says why: "check if pending
// before overwriting fields in the structure". The background writer owns that object while a
// dump is in flight, so zeroing it first would corrupt a dump already running -- and the
// specific CFE_ES_ERLOG_PENDING_ERR_EID exists so the ground can tell "already running" from
// "could not start".
//
// snprintf INTO Description IS NASA'S OWN ODDITY: the format string IS the description, with
// no arguments. StrNCpy is the same operation without the formatter.
I32 CFE_ES_WriteERLogCmd(CFE_ES_WriteERLogCmd_t *data)
{
  CFE_ES_FileNameCmd_Payload_t *CmdPtr = &data->Payload;
  CFE_ES_BackgroundLogDumpGlobal_t *StatePtr;
  I32 Status;
  StatePtr = &CFE_ES_Global.BackgroundERLogDumpState;
  /* check if pending before overwriting fields in the structure */
  if (CFE_FS_BackgroundFileDumpIsPending(&StatePtr->FileWrite)) {
    Status = CFE_STATUS_REQUEST_ALREADY_PENDING;
  } else {
    /* Reset the entire state object (just for good measure, ensure no stale data) */
    MemSet(StatePtr, 0, sizeof(CFE_ES_BackgroundLogDumpGlobal_t));
    /*
     * Fill out the remainder of meta data.
     * This data is currently the same for every request
     */
    StatePtr->FileWrite.FileSubType = CFE_FS_SubType_ES_ERLOG;
    StrNCpy(StatePtr->FileWrite.Description, CFE_ES_ER_LOG_DESC, CFE_FS_HDR_DESC_MAX_LEN - 1);
    StatePtr->FileWrite.Description[CFE_FS_HDR_DESC_MAX_LEN - 1] = 0;
    StatePtr->FileWrite.GetData = &CFE_ES_BackgroundERLogFileDataGetter;
    StatePtr->FileWrite.OnEvent = &CFE_ES_BackgroundERLogFileEventHandler;
    /*
    ** Copy the filename into local buffer with default name/path/extension if not specified
    */
    Status = CFE_FS_ParseInputFileNameEx(StatePtr->FileWrite.FileName, CmdPtr->FileName, CFE_MISSION_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, CFE_PLATFORM_ES_DEFAULT_ER_LOG_FILE, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_BINARY_DATA_DUMP), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_BINARY_DATA_DUMP));
    if (Status == CFE_SUCCESS) {
      Status = CFE_FS_BackgroundFileDumpRequest(&StatePtr->FileWrite);
    }
  }
  if (Status != CFE_SUCCESS) {
    if (Status == CFE_STATUS_REQUEST_ALREADY_PENDING) {
      /* Specific event if already pending */
      CFE_EVS_SendEvent(CFE_ES_ERLOG_PENDING_ERR_EID, CFE_EVS_EventType_ERROR, "Error log write already in progress");
    } else {
      /* Some other validation issue e.g. bad file name */
      CFE_EVS_SendEvent(CFE_ES_ERLOG2_ERR_EID, CFE_EVS_EventType_ERROR, "Error creating file, RC = %d", Status);
    }
    /* background dump did not start, consider this an error */
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  } else {
    CFE_ES_Global.TaskData.CommandCounter++;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_ResetPRCountCmd(CFE_ES_ResetPRCountCmd_t *data)
{
  /*
  ** Reset the processor reset count
  */
  CFE_ES_Global.ResetDataPtr->ResetVars.ProcessorResetCount = 0;
  /*
  ** This command will always succeed.
  */
  CFE_EVS_SendEvent(CFE_ES_RESET_PR_COUNT_EID, CFE_EVS_EventType_INFORMATION, "Set Processor Reset Count to Zero");
  CFE_ES_Global.TaskData.CommandCounter++;
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// NO RANGE CHECK ON MaxPRCount. Any 16-bit value is accepted, including 0, which makes the
// NEXT processor reset exceed the maximum and become a power-on reset instead.
I32 CFE_ES_SetMaxPRCountCmd(CFE_ES_SetMaxPRCountCmd_t *data)
{
  CFE_ES_SetMaxPRCountCmd_Payload_t *cmd = &data->Payload;
  /*
  ** Set the MAX Processor reset count
  */
  CFE_ES_Global.ResetDataPtr->ResetVars.MaxProcessorResetCount = cmd->MaxPRCount;
  /*
  ** This command will always succeed.
  */
  CFE_EVS_SendEvent(CFE_ES_SET_MAX_PR_COUNT_EID, CFE_EVS_EventType_INFORMATION, "Maximum Processor Reset Count set to: %d", cmd->MaxPRCount);
  CFE_ES_Global.TaskData.CommandCounter++;
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// FOUR DISTINCT FAILURES, FOUR EVENTS, and the first two are the interesting ones: a CDS that
// belongs to a CRITICAL TABLE must be deleted through TBL, not ES, and a CDS whose owning app
// is still running is refused outright. Both are the CDS protecting data across a reset from
// being thrown away by a single ground command.
I32 CFE_ES_DeleteCDSCmd(CFE_ES_DeleteCDSCmd_t *data)
{
  I32 Status;
  CFE_ES_DeleteCDSCmd_Payload_t *cmd = &data->Payload;
  U8 LocalCdsName[CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN];
  CFE_SB_MessageStringGet(LocalCdsName, cmd->CdsName, NULL, CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN, CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN);
  Status = CFE_ES_DeleteCDS(LocalCdsName, FALSE);
  if (Status == CFE_ES_CDS_WRONG_TYPE_ERR) {
    CFE_EVS_SendEvent(CFE_ES_CDS_DELETE_TBL_ERR_EID, CFE_EVS_EventType_ERROR, "CDS '%s' is a Critical Table CDS. Must be deleted via TBL Command", LocalCdsName);
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  } else if (Status == CFE_ES_CDS_OWNER_ACTIVE_ERR) {
    CFE_EVS_SendEvent(CFE_ES_CDS_OWNER_ACTIVE_EID, CFE_EVS_EventType_ERROR, "CDS '%s' not deleted because owning app is active", LocalCdsName);
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  } else if (Status == CFE_ES_ERR_NAME_NOT_FOUND) {
    CFE_EVS_SendEvent(CFE_ES_CDS_NAME_ERR_EID, CFE_EVS_EventType_ERROR, "Unable to locate '%s' in CDS Registry", LocalCdsName);
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  } else if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(CFE_ES_CDS_DELETE_ERR_EID, CFE_EVS_EventType_ERROR, "Error while deleting '%s' from CDS, See SysLog.(Err=0x%08X)", LocalCdsName, Status);
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  } else {
    CFE_EVS_SendEvent(CFE_ES_CDS_DELETED_INFO_EID, CFE_EVS_EventType_INFORMATION, "Successfully removed '%s' from CDS", LocalCdsName);
    CFE_ES_Global.TaskData.CommandCounter++;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE HANDLE IS ECHOED BACK IN THE PACKET, which is the only way the ground can match a
// statistics packet to the pool it asked about: these are sent on command, not on a schedule,
// and nothing else in the packet identifies the pool.
I32 CFE_ES_SendMemPoolStatsCmd(CFE_ES_SendMemPoolStatsCmd_t *data)
{
  CFE_ES_SendMemPoolStatsCmd_Payload_t *Cmd;
  U32 MemHandle;
  Bool ValidHandle;
  Cmd = &data->Payload;
  /* Verify the handle to make sure it is legit */
  MemHandle = Cmd->PoolHandle;
  ValidHandle = CFE_ES_ValidateHandle(MemHandle);
  if (ValidHandle) {
    /* Extract the memory statistics from the memory pool */
    CFE_ES_GetMemPoolStats(&CFE_ES_Global.TaskData.MemStatsPacket.Payload.PoolStats, MemHandle);
    /* Echo the specified pool handle in the telemetry packet */
    CFE_ES_Global.TaskData.MemStatsPacket.Payload.PoolHandle = MemHandle;
    /*
    ** Send memory statistics telemetry packet.
    */
    CFE_SB_TimeStampMsg(&CFE_ES_Global.TaskData.MemStatsPacket.TelemetryHeader.Msg);
    CFE_SB_TransmitMsg(&CFE_ES_Global.TaskData.MemStatsPacket.TelemetryHeader.Msg, TRUE);
    CFE_ES_Global.TaskData.CommandCounter++;
    CFE_EVS_SendEvent(CFE_ES_TLM_POOL_STATS_INFO_EID, CFE_EVS_EventType_DEBUG, "Successfully telemetered memory pool stats for 0x%08lX", Cmd->PoolHandle);
  } else {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_INVALID_POOL_HANDLE_ERR_EID, CFE_EVS_EventType_ERROR, "Cannot telemeter memory pool stats. Illegal Handle (0x%08lX)", Cmd->PoolHandle);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// OsStatus IS DOING TWO JOBS and that is what makes the loop work: it is PRE-LOADED with
// sizeof(CFE_ES_CDSRegDumpRec_t) before the loop so the `while` condition is true on entry,
// and it then holds each OS_write's return. A short write makes the condition false and stops
// the walk, and the same comparison after the loop decides which event goes out. An empty
// registry therefore reports success, because the pre-loaded value survives untouched.
//
// `if (Status == OS_SUCCESS)` COMPARES A CFE STATUS TO AN OSAL ONE, which is NASA's, and works
// only because both are 0. CFE_FS_ParseInputFileNameEx returns CFE_SUCCESS on the path that
// gets here.
I32 CFE_ES_DumpCDSRegistryCmd(CFE_ES_DumpCDSRegistryCmd_t *data)
{
  CFE_FS_Header_t StdFileHeader;
  U32 FileDescriptor = OS_OBJECT_ID_UNDEFINED;
  I32 OsStatus;
  I32 Status;
  I16 RegIndex = 0;
  CFE_ES_DumpCDSRegistryCmd_Payload_t *CmdPtr = &data->Payload;
  U8 DumpFilename[OS_MAX_PATH_LEN];
  CFE_ES_CDS_RegRec_t *RegRecPtr;
  CFE_ES_CDSRegDumpRec_t DumpRecord;
  I32 FileSize = 0;
  I32 NumEntries = 0;
  /*
  ** Copy the filename into local buffer with default name/path/extension if not specified
  */
  Status = CFE_FS_ParseInputFileNameEx(DumpFilename, CmdPtr->DumpFilename, OS_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, CFE_PLATFORM_ES_DEFAULT_CDS_REG_DUMP_FILE, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_BINARY_DATA_DUMP), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_BINARY_DATA_DUMP));
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(CFE_ES_CREATING_CDS_DUMP_ERR_EID, CFE_EVS_EventType_ERROR, "Error parsing CDS dump filename, Status=0x%08X", Status);
  } else {
    /* Create a new dump file, overwriting anything that may have existed previously */
    OsStatus = OS_OpenCreate(&FileDescriptor, DumpFilename, OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE, OS_WRITE_ONLY);
    if (OsStatus != OS_SUCCESS) {
      CFE_EVS_SendEvent(CFE_ES_CREATING_CDS_DUMP_ERR_EID, CFE_EVS_EventType_ERROR, "Error creating CDS dump file '%s', Status=%ld", DumpFilename, OsStatus);
      Status = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }
  }
  if (Status == OS_SUCCESS) {
    /* Initialize the standard cFE File Header for the Dump File */
    CFE_FS_InitHeader(&StdFileHeader, "CDS_Registry", CFE_FS_SubType_ES_CDS_REG);
    /* Output the Standard cFE File Header to the Dump File */
    Status = CFE_FS_WriteHeader(FileDescriptor, &StdFileHeader);
    /* Maintain statistics of amount of data written to file */
    FileSize += Status;
    if (Status == sizeof(CFE_FS_Header_t)) {
      OsStatus = sizeof(CFE_ES_CDSRegDumpRec_t);
      RegRecPtr = CFE_ES_Global.CDSVars.Registry;
      while ((RegIndex < CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES) && (OsStatus == sizeof(CFE_ES_CDSRegDumpRec_t))) {
        /* Check to see if the Registry entry is empty */
        if (CFE_ES_CDSBlockRecordIsUsed(RegRecPtr)) {
          /* Fill CDS Registry Dump Record with relevant information */
          MemSet(&DumpRecord, 0, sizeof(CFE_ES_CDSRegDumpRec_t));
          // CFE_ES_MEMOFFSET_C, the same no-op cast as elsewhere: Size is already I64.
          DumpRecord.Size = CFE_ES_CDSBlockRecordGetUserSize(RegRecPtr);
          DumpRecord.Handle = CFE_ES_CDSBlockRecordGetID(RegRecPtr);
          DumpRecord.Table = RegRecPtr->Table;
          StrNCpy(DumpRecord.Name, RegRecPtr->Name, CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN - 1);
          /* Output Registry Dump Record to Registry Dump File */
          OsStatus = OS_write(FileDescriptor, &DumpRecord, sizeof(CFE_ES_CDSRegDumpRec_t));
          FileSize += OsStatus;
          NumEntries++;
        }
        /* Look at the next entry in the Registry */
        ++RegIndex;
        ++RegRecPtr;
      }
      if (OsStatus == sizeof(CFE_ES_CDSRegDumpRec_t)) {
        CFE_EVS_SendEvent(CFE_ES_CDS_REG_DUMP_INF_EID, CFE_EVS_EventType_DEBUG, "Successfully dumped CDS Registry to '%s':Size=%d,Entries=%d", DumpFilename, FileSize, NumEntries);
        /* Increment Successful Command Counter */
        CFE_ES_Global.TaskData.CommandCounter++;
      } else {
        CFE_EVS_SendEvent(CFE_ES_CDS_DUMP_ERR_EID, CFE_EVS_EventType_ERROR, "Error writing CDS Registry to '%s', Status=%ld", DumpFilename, OsStatus);
        /* Increment Command Error Counter */
        CFE_ES_Global.TaskData.CommandErrorCounter++;
      }
    } else {
      CFE_EVS_SendEvent(CFE_ES_WRITE_CFE_HDR_ERR_EID, CFE_EVS_EventType_ERROR, "Error writing cFE File Header to '%s', Status=0x%08X", DumpFilename, Status);
      /* Increment Command Error Counter */
      CFE_ES_Global.TaskData.CommandErrorCounter++;
    }
    /* We are done outputting data to the dump file.  Close it. */
    OS_close(FileDescriptor);
  } else {
    /* Increment Command Error Counter */
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE ONE FUNCTION IN THIS FILE THAT IS NOT A COMMAND. Every file-writing command above and in
// cfe_es_backgroundtask.c calls it on a short write, which is why it was a stub on both halves
// of the differential driver until this source was gated.
U0 CFE_ES_FileWriteByteCntErr(U8 *Filename, I64 Requested, I32 Status)
{
  CFE_EVS_SendEvent(CFE_ES_FILEWRITE_ERR_EID, CFE_EVS_EventType_ERROR, "File write,byte cnt err,file %s,request=%u,status=0x%08x", Filename, Requested, Status);
}
#endif
