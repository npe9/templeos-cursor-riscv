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
// 1:1 HolyC translation of cFE modules/time/fsw/src/cfe_time_task.c -- TIME's task entry points
// and its twenty-two command handlers.
//
// EVERY HANDLER HERE IS A GROUND COMMAND, and the shape they share is the point of the file: a
// handler validates its argument, calls the matching setter in cfe_time_utils.c, bumps
// CommandCounter and sends an INFORMATION event -- or bumps CommandErrorCounter and sends an
// ERROR event with the rejected value in it. Nothing is silently ignored and nothing is clamped,
// so a wrong number in a command sequence comes back as a specific event rather than a clock
// that quietly disagrees with the ground.
//
// THE CONFIGURATION DECIDES WHICH HALF OF SIX HANDLERS IS BUILT. This port is a time SERVER
// (CFE_PLATFORM_TIME_CFG_SERVER 1, CFE_PLATFORM_TIME_CFG_CLIENT 0) with neither a selectable
// source (CFE_PLATFORM_TIME_CFG_SOURCE 0) nor a selectable tone signal
// (CFE_PLATFORM_TIME_CFG_SIGNAL 0), so:
//
//   SetTime, SetMET, SetSTCF, SetLeapSeconds, AddAdjust, SubAdjust,
//   AddOneHzAdjustment, SubOneHzAdjustment      take the REAL branch (server)
//   SetSource, SetSignal, AddDelay, SubDelay    take the "invalid without ..." branch, which is
//                                               NASA's own code and not a stub: a disabled
//                                               command still has to be COUNTED and reported.
//
// That asymmetry is worth stating because the ERROR branch of a disabled command is the branch
// this build exercises, and it is easy to mistake for an unimplemented one.
// THIS FILE CONTAINS NO `#if`, AND THAT IS DELIBERATE. This compiler's `#if <expr>` is
// UNCONDITIONALLY TRUE -- host/lexer.c handles only a literal `0`, so `#if (SOMETHING == 1)` is
// compiled in however SOMETHING is defined, silently. docs/HOLYC_STRUCT_LIMITS.md #15. NASA's
// configuration directives are therefore resolved BY HAND here, each one replaced by a bracketed
// comment naming the guard, its value and which branch survived, so the translation can still be
// read against the C line for line. Every other TIME file that landed before this one does the
// same thing, cfe_time_utils.HC included; what is new is that these three had enough
// configuration in them to make the silence dangerous rather than merely untidy -- written with
// the directives in place, the first version of this file referenced CFE_TIME_SetDelay,
// CFE_TIME_SetSignal, CFE_TIME_SetSource, OS_GetLocalMET and OS_SelectTone, none of which this
// configuration builds. The blob's import trailer is what caught it.
//
#ifndef CFE_TIME_TASK_HC
#define CFE_TIME_TASK_HC
#include "cfe_time_global.HC"  // the types, the constants and CFE_TIME_Global
// --- cfe_time_eventids.h ----------------------------------------------------------------------
#define CFE_TIME_INIT_EID       1
#define CFE_TIME_NOOP_EID       4
#define CFE_TIME_RESET_EID      5
#define CFE_TIME_DIAG_EID       6
#define CFE_TIME_STATE_EID      7
#define CFE_TIME_SOURCE_EID     8
#define CFE_TIME_SIGNAL_EID     9
#define CFE_TIME_DELAY_EID      11
#define CFE_TIME_TIME_EID       12
#define CFE_TIME_MET_EID        13
#define CFE_TIME_STCF_EID       14
#define CFE_TIME_DELTA_EID      15
#define CFE_TIME_ONEHZ_EID      16
#define CFE_TIME_LEAPS_EID      17
#define CFE_TIME_STATE_ERR_EID  30
#define CFE_TIME_SOURCE_ERR_EID 31
#define CFE_TIME_SIGNAL_ERR_EID 32
#define CFE_TIME_DELAY_ERR_EID  33
#define CFE_TIME_TIME_ERR_EID   34
#define CFE_TIME_MET_ERR_EID    35
#define CFE_TIME_STCF_ERR_EID   36
#define CFE_TIME_DELTA_ERR_EID  37
#define CFE_TIME_SOURCE_CFG_EID 40
#define CFE_TIME_SIGNAL_CFG_EID 41
#define CFE_TIME_DELAY_CFG_EID  42
#define CFE_TIME_TIME_CFG_EID   43
#define CFE_TIME_MET_CFG_EID    44
#define CFE_TIME_STCF_CFG_EID   45
#define CFE_TIME_LEAPS_CFG_EID  46
#define CFE_TIME_DELTA_CFG_EID  47
#define CFE_TIME_ONEHZ_CFG_EID  48
// --- cfe_perfids.h ----------------------------------------------------------------------------
// The other four TIME performance IDs live in cfe_time_tone.HC with the functions that use them.
#define CFE_MISSION_TIME_MAIN_PERF_ID 6
// --- cfe_time_utils.h: the names and sizes TaskInit creates its resources with -----------------
#define CFE_TIME_TASK_TONE_NAME  "TIME_TONE_TASK"
#define CFE_TIME_TASK_ONEHZ_NAME "TIME_ONEHZ_TASK"
#define CFE_TIME_TASK_STACK_PTR  NULL
// CFE_ES_TASK_STACK_ALLOCATE, which is NULL -- "let ES allocate the stack"
#define CFE_TIME_TASK_FLAGS      0
#define CFE_TIME_SEM_TONE_NAME   "TIME_TONE_SEM"
#define CFE_TIME_SEM_ONEHZ_NAME  "TIME_ONEHZ_SEM"
#define CFE_TIME_SEM_VALUE       0
#define CFE_TIME_SEM_OPTIONS     0
#define CFE_TIME_TASK_PIPE_NAME  "TIME_CMD_PIPE"
#define CFE_TIME_TASK_PIPE_DEPTH 12
// --- cfe_time_internal_cfg.h: the two child tasks ----------------------------------------------
#define CFE_PLATFORM_TIME_TONE_TASK_PRIORITY    25
#define CFE_PLATFORM_TIME_ONEHZ_TASK_PRIORITY   25
#define CFE_PLATFORM_TIME_TONE_TASK_STACK_SIZE  4096
#define CFE_PLATFORM_TIME_ONEHZ_TASK_STACK_SIZE 8192
// --- cfe_sb_internal_cfg.h --------------------------------------------------------------------
// A time SERVER subscribes to the tone messages LOCALLY, with a message limit; a client
// subscribes globally and has no limit to give. SB is not translated, so the number is spelled
// out and check_constants.py compares it against NASA's header.
#define CFE_PLATFORM_SB_DEFAULT_MSG_LIMIT 4
// --- cfe_es_api_typedefs.h / cfe_error.h ------------------------------------------------------
#ifndef CFE_STATUS_EXTERNAL_RESOURCE_FAIL
#define CFE_STATUS_EXTERNAL_RESOURCE_FAIL -57
#endif
// --- what this file needs from elsewhere ------------------------------------------------------
// cfe_time_utils.c, cfe_time_api.c and cfe_time_tone.c, translated beside this one.
U0 CFE_TIME_InitData();
U0 CFE_TIME_GetReference(CFE_TIME_Reference_t *Reference);
U0 CFE_TIME_UpdateResetVars(CFE_TIME_Reference_t *Reference);
U0 CFE_TIME_GetHkData(CFE_TIME_Reference_t *Reference);
U0 CFE_TIME_GetDiagData();
U0 CFE_TIME_SetState(I32 NewState);
U0 CFE_TIME_SetTime(CFE_TIME_SysTime NewTime);
U0 CFE_TIME_SetMET(CFE_TIME_SysTime NewMET);
U0 CFE_TIME_SetSTCF(CFE_TIME_SysTime NewSTCF);
U0 CFE_TIME_SetLeapSeconds(I16 NewLeaps);
U0 CFE_TIME_SetAdjust(CFE_TIME_SysTime NewAdjust, I16 Direction);
U0 CFE_TIME_Set1HzAdj(CFE_TIME_SysTime NewAdjust, I16 Direction);
U32 CFE_TIME_Micro2SubSecs(U32 MicroSeconds);
U0 CFE_TIME_ToneSend();
U0 CFE_TIME_ToneSignal();
U0 CFE_TIME_ToneData(CFE_TIME_ToneDataCmd_Payload_t *ToneDataCmd);
U0 CFE_TIME_Tone1HzISR();
U0 CFE_TIME_Tone1HzTask();
U0 CFE_TIME_Local1HzTask();
U0 CFE_TIME_Local1HzStateMachine();
U0 CFE_TIME_Local1HzTimerCallback(U32 TimerId, U8 *Arg);
// cfe_time_dispatch.c, the conditional source, translated in cfe_time_dispatch.HC.
U0 CFE_TIME_TaskPipe(CFE_SB_Buffer *SBBufPtr);
// Defined further down this file and called from above it.
I32 CFE_TIME_TaskInit();
// SB, ES, EVS, CONFIG and OSAL. None of ES is translated; the differential oracle gives both
// sides the same recording stubs, which is the arrangement cfe_ta_task.HC records.
I32 CFE_SB_TransmitMsg(CFE_MSG_Message *MsgPtr, Bool IncrementSequenceCount);
I32 CFE_SB_TimeStampMsg(CFE_MSG_Message *MsgPtr);
I32 CFE_SB_CreatePipe(U32 *PipeIdPtr, U16 Depth, U8 *PipeName);
I32 CFE_SB_Subscribe(U32 MsgId, U32 PipeId);
I32 CFE_SB_SubscribeLocal(U32 MsgId, U32 PipeId, U16 MsgLim);
I32 CFE_SB_ReceiveBuffer(CFE_SB_Buffer **BufPtr, U32 PipeId, I32 TimeOut);
U32 CFE_SB_ValueToMsgId(U32 MsgIdValue);
U0 CFE_ES_PerfLogEntry(U32 Marker);
U0 CFE_ES_PerfLogExit(U32 Marker);
U0 CFE_ES_IncrementTaskCounter();
U0 CFE_ES_ExitApp(U32 ExitStatus);
I32 CFE_ES_WaitForSystemState(U32 MinSystemState, U32 TimeOutMilliseconds);
I32 CFE_ES_CreateChildTask(U32 *TaskIdPtr, U8 *TaskName, U0 (*FunctionPtr)(), U32 *StackPtr, U32 StackSize, U32 Priority, U32 Flags);
I32 CFE_ES_WriteToSysLog(U8 *Spec,...);
I32 CFE_EVS_Register(U8 *Filters, U16 NumEventFilters, U16 FilterScheme);
I32 CFE_EVS_SendEvent(U16 EventID, U16 EventType, U8 *Spec,...);
U0 CFE_Config_GetVersionString(U8 *Buf, I64 Size, U8 *Component, U8 *SrcVersion, U8 *CodeName, U8 *LastOfficial);
I32 OS_BinSemCreate(U32 *sem_id, U8 *sem_name, U32 sem_initial_value, U32 options);
I32 OS_TimeBaseGetIdByName(U32 *timebase_id, U8 *timebase_name);
I32 OS_TimerAdd(U32 *timer_id, U8 *timer_name, U32 timebase_id, U0 (*callback_ptr)(), U8 *callback_arg);
I32 OS_TimerSet(U32 timer_id, U32 start_time, U32 interval_time);
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_EarlyInit()
{
  /*
  ** Initialize global Time Services nonzero data...
  */
  CFE_TIME_InitData();
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_TaskMain()
{
  I32 Status;
  CFE_SB_Buffer *SBBufPtr;
  CFE_ES_PerfLogEntry(CFE_MISSION_TIME_MAIN_PERF_ID);
  Status = CFE_TIME_TaskInit();
  if (Status != CFE_SUCCESS) {
    // NASA passes __func__ here. HolyC has no __func__, so the name is spelled out -- the same
    // deviation cfe_evs_task.HC records, and the string is what appears in the syslog either way.
    CFE_ES_WriteToSysLog("CFE_TIME_TaskMain: Application Init Failed,RC=0x%08X\n", Status);
    CFE_ES_PerfLogExit(CFE_MISSION_TIME_MAIN_PERF_ID);
    /* Note: CFE_ES_ExitApp will not return */
    CFE_ES_ExitApp(CFE_ES_RunStatus_CORE_APP_INIT_ERROR);
  }
  /*
   * Wait for other apps to start.
   * It is important that the core apps are present before this starts receiving
   * messages from the command pipe, as some of those handlers might depend on
   * the other core apps.
   */
  CFE_ES_WaitForSystemState(CFE_ES_SystemState_CORE_READY, CFE_PLATFORM_CORE_MAX_STARTUP_MSEC);
  /* Main loop */
  while (Status == CFE_SUCCESS) {
    /* Increment the Main task Execution Counter */
    CFE_ES_IncrementTaskCounter();
    CFE_ES_PerfLogExit(CFE_MISSION_TIME_MAIN_PERF_ID);
    /* Pend on receipt of packet */
    Status = CFE_SB_ReceiveBuffer(&SBBufPtr, CFE_TIME_Global.CmdPipe, CFE_SB_PEND_FOREVER);
    CFE_ES_PerfLogEntry(CFE_MISSION_TIME_MAIN_PERF_ID);
    if (Status == CFE_SUCCESS) {
      /* Process cmd pipe msg */
      CFE_TIME_TaskPipe(SBBufPtr);
    } else {
      CFE_ES_WriteToSysLog("CFE_TIME_TaskMain: Error reading cmd pipe,RC=0x%08X\n", Status);
    }
  }
  /* end while */
  /* while loop exits only if CFE_SB_ReceiveBuffer returns error */
  CFE_ES_ExitApp(CFE_ES_RunStatus_CORE_APP_RUNTIME_ERROR);
}
/*----------------------------------------------------------------
 *
 * Local helper function
 * Subscribes the command pipe to one of the "time at the tone" messages
 * A time client subscribes globally, a time server subscribes locally.
 * Note that cfe_time_verify.h enforces that exactly one of
 * CFE_PLATFORM_TIME_CFG_CLIENT / CFE_PLATFORM_TIME_CFG_SERVER is true.
 *
 *-----------------------------------------------------------------*/
// THE FIVE TaskInit_* HELPERS ARE `static` IN THE C AND NOT HERE, which is a deviation worth
// stating because it looks like the one docs/HOLYC_STRUCT_LIMITS.md #12 fixed and is not. #12 was
// about a `static` LOCAL; HolyC has no `static` on a FUNCTION at all -- the compiler refuses the
// declaration outright -- so these five names have unit scope instead of file scope. Nothing else
// in cFS declares a function by any of these names, and cfe_evs_utils.HC's EVS_* helpers are the
// same deviation. If a second module ever adds a TaskInit_CreateResources, this is where the
// collision would show up.
I32 CFE_TIME_TaskInit_SubscribeTone(U32 MsgId)
{
  // [#if CFE_PLATFORM_TIME_CFG_CLIENT == 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_CLIENT is 0), so what follows is NASA's #else branch]
  return CFE_SB_SubscribeLocal(MsgId, CFE_TIME_Global.CmdPipe, CFE_PLATFORM_SB_DEFAULT_MSG_LIMIT);
}
/*----------------------------------------------------------------
 *
 * Local helper function
 * Registers for events and creates the semaphores and child tasks
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_TaskInit_CreateResources(U8 *LogFunction)
{
  I32 Status;
  I32 OsStatus;
  Status = CFE_EVS_Register(NULL, 0, 0);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Call to CFE_EVS_Register Failed:RC=0x%08X\n", LogFunction, Status);
    return Status;
  }
  OsStatus = OS_BinSemCreate(&CFE_TIME_Global.ToneSemaphore, CFE_TIME_SEM_TONE_NAME, CFE_TIME_SEM_VALUE, CFE_TIME_SEM_OPTIONS);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error creating tone semaphore:RC=%d\n", LogFunction, OsStatus);
    return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  }
  OsStatus = OS_BinSemCreate(&CFE_TIME_Global.LocalSemaphore, CFE_TIME_SEM_ONEHZ_NAME, CFE_TIME_SEM_VALUE, CFE_TIME_SEM_OPTIONS);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error creating local semaphore:RC=%d\n", LogFunction, OsStatus);
    return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  }
  Status = CFE_ES_CreateChildTask(&CFE_TIME_Global.ToneTaskID, CFE_TIME_TASK_TONE_NAME, &CFE_TIME_Tone1HzTask, CFE_TIME_TASK_STACK_PTR, CFE_PLATFORM_TIME_TONE_TASK_STACK_SIZE, CFE_PLATFORM_TIME_TONE_TASK_PRIORITY, CFE_TIME_TASK_FLAGS);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error creating tone 1Hz child task:RC=0x%08X\n", LogFunction, Status);
    return Status;
  }
  Status = CFE_ES_CreateChildTask(&CFE_TIME_Global.LocalTaskID, CFE_TIME_TASK_ONEHZ_NAME, &CFE_TIME_Local1HzTask, CFE_TIME_TASK_STACK_PTR, CFE_PLATFORM_TIME_ONEHZ_TASK_STACK_SIZE, CFE_PLATFORM_TIME_ONEHZ_TASK_PRIORITY, CFE_TIME_TASK_FLAGS);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error creating local 1Hz child task:RC=0x%08X\n", LogFunction, Status);
    return Status;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Local helper function
 * Creates the command pipe and subscribes to all Time task messages
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_TaskInit_SubscribeMsgs(U8 *LogFunction)
{
  I32 Status;
  Status = CFE_SB_CreatePipe(&CFE_TIME_Global.CmdPipe, CFE_TIME_TASK_PIPE_DEPTH, CFE_TIME_TASK_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error creating cmd pipe:RC=0x%08X\n", LogFunction, Status);
    return Status;
  }
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_TIME_SEND_HK_MID), CFE_TIME_Global.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error subscribing to HK Request:RC=0x%08X\n", LogFunction, Status);
    return Status;
  }
  /*
  ** Subscribe to time at the tone "signal" commands...
  */
  Status = CFE_TIME_TaskInit_SubscribeTone(CFE_SB_ValueToMsgId(CFE_TIME_TONE_CMD_MID));
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error subscribing to tone cmd:RC=0x%08X\n", LogFunction, Status);
    return Status;
  }
  /*
  ** Subscribe to time at the tone "data" commands...
  */
  Status = CFE_TIME_TaskInit_SubscribeTone(CFE_SB_ValueToMsgId(CFE_TIME_DATA_CMD_MID));
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error subscribing to time data cmd:RC=0x%08X\n", LogFunction, Status);
    return Status;
  }
  /*
  ** Subscribe to 1Hz signal commands...
  */
  Status = CFE_TIME_TaskInit_SubscribeTone(CFE_SB_ValueToMsgId(CFE_TIME_ONEHZ_CMD_MID));
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error subscribing to fake tone signal cmds:RC=0x%08X\n", LogFunction, Status);
    return Status;
  }
  /*
  ** Subscribe to time at the tone "request data" commands...
  */
  // [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_TIME_SEND_CMD_MID), CFE_TIME_Global.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error subscribing to time at the tone request data cmds:RC=0x%08X\n", LogFunction, Status);
    return Status;
  }
  /*
  ** Subscribe to Time task ground command packets...
  */
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_TIME_CMD_MID), CFE_TIME_Global.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error subscribing to time task gnd cmds:RC=0x%08X\n", LogFunction, Status);
    return Status;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Local helper function
 * Sends the Time task initialization event
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_TaskInit_SendInitEvent(U8 *LogFunction)
{
  I32 Status;
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];
  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "CFE_TIME", CFE_SRC_VERSION, CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);
  Status = CFE_EVS_SendEvent(CFE_TIME_INIT_EID, CFE_EVS_EventType_INFORMATION, "cFE TIME Initialized: %s", VersionString);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error sending init event:RC=0x%08X\n", LogFunction, Status);
    return Status;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Local helper function
 * Creates the 1Hz callback if the system time base is available
 * Checks to see if the OSAL in use implements the TimeBase API and if the
 * PSP has set up a system time base.  If so, then create a 1Hz callback
 * based on that system time base.  The lookup should return
 * OS_ERR_NOT_IMPLEMENTED if the OSAL does not support this, or
 * OS_ERR_NAME_NOT_FOUND if the PSP didn't set this up.  Either way any
 * error here means the PSP must use the "old way" and call the 1hz
 * function directly, so the lookup failure is not reported.
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_TaskInit_Setup1HzTimer(U8 *LogFunction)
{
  I32 OsStatus;
  U32 TimeBaseId;
  U32 TimerId;
  OsStatus = OS_TimeBaseGetIdByName(&TimeBaseId, "cFS-Master");
  if (OsStatus != OS_SUCCESS) {
    return;
  }
  /* Create the 1Hz callback */
  OsStatus = OS_TimerAdd(&TimerId, "cFS-1Hz", TimeBaseId, &CFE_TIME_Local1HzTimerCallback, NULL);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: 1Hz OS_TimerAdd failed:RC=%d\n", LogFunction, OsStatus);
    return;
  }
  OsStatus = OS_TimerSet(TimerId, 500000, 1000000);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: 1Hz OS_TimerSet failed:RC=%d\n", LogFunction, OsStatus);
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_TaskInit()
{
  I32 Status;
  Status = CFE_TIME_TaskInit_CreateResources("CFE_TIME_TaskInit");
  if (Status != CFE_SUCCESS) {
    return Status;
  }
  Status = CFE_TIME_TaskInit_SubscribeMsgs("CFE_TIME_TaskInit");
  if (Status != CFE_SUCCESS) {
    return Status;
  }
  Status = CFE_TIME_TaskInit_SendInitEvent("CFE_TIME_TaskInit");
  if (Status != CFE_SUCCESS) {
    return Status;
  }
  /*
  ** Select primary vs redundant tone interrupt signal...
  */
  // [#if CFE_PLATFORM_TIME_CFG_SIGNAL == 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_SIGNAL is 0); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
  CFE_TIME_TaskInit_Setup1HzTimer("CFE_TIME_TaskInit");
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SendHkCmd(CFE_TIME_SendHkCmd_t *data)
{
  CFE_TIME_Reference_t Reference;
  /*
  ** Get reference time values (local time, time at tone, etc.)...
  */
  CFE_TIME_GetReference(&Reference);
  /*
  ** Update TIME portion of Critical Data Store...
  */
  CFE_TIME_UpdateResetVars(&Reference);
  /*
  ** Collect housekeeping data from Time Services utilities...
  */
  CFE_TIME_GetHkData(&Reference);
  /*
  ** Send housekeeping telemetry packet...
  */
  CFE_SB_TimeStampMsg(&CFE_TIME_Global.HkPacket.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&CFE_TIME_Global.HkPacket.TelemetryHeader.Msg, TRUE);
  /*
  ** Note: we only increment the command execution counter when
  **   processing CFE_TIME_CMD_MID commands...
  */
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_ToneSignalCmd(CFE_TIME_ToneSignalCmd_t *data)
{
  /*
  ** Indication that tone signal occurred recently...
  */
  CFE_TIME_ToneSignal();
  /*
  ** Note: we only increment the command execution counter when
  **   processing CFE_TIME_CMD_MID commands...
  */
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_ToneDataCmd(CFE_TIME_ToneDataCmd_t *data)
{
  /*
  ** This command packet contains "time at the tone" data...
  */
  CFE_TIME_ToneData(&data->Payload);
  /*
  ** Note: we only increment the command execution counter when
  **   processing CFE_TIME_CMD_MID commands...
  */
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_OneHzCmd(CFE_TIME_OneHzCmd_t *data)
{
  /*
   * Run the state machine updates required at 1Hz.
   *
   * This task used to be performed as part of the 1Hz ISR, but this was unsafe on SMP
   * as the updates cannot be synchronized with the command handlers in this environment
   */
  CFE_TIME_Local1HzStateMachine();
  // [#if CFE_MISSION_TIME_CFG_FAKE_TONE == 1 -- TRUE here (CFE_MISSION_TIME_CFG_FAKE_TONE is 1); NASA's directive resolved by hand]
  /*
  ** Fake the call-back from the "real" h/w ISR...
  */
  CFE_TIME_Tone1HzISR();
  /*
  ** Note: we only increment the command execution counter when
  **   processing CFE_TIME_CMD_MID commands...
  */
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
I32 CFE_TIME_ToneSendCmd(CFE_TIME_FakeToneCmd_t *data)
{
  /*
  ** Request for "time at tone" data packet (probably scheduler)...
  */
  CFE_TIME_ToneSend();
  /*
  ** Note: we only increment the command execution counter when
  **   processing CFE_TIME_CMD_MID commands...
  */
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_NoopCmd(CFE_TIME_NoopCmd_t *data)
{
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];
  CFE_TIME_Global.CommandCounter++;
  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "CFE_TIME", CFE_SRC_VERSION, CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);
  CFE_EVS_SendEvent(CFE_TIME_NOOP_EID, CFE_EVS_EventType_INFORMATION, "No-op Cmd Rcvd: %s", VersionString);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_ResetCountersCmd(CFE_TIME_ResetCountersCmd_t *data)
{
  CFE_TIME_Global.CommandCounter = 0;
  CFE_TIME_Global.CommandErrorCounter = 0;
  CFE_TIME_Global.ToneMatchCounter = 0;
  CFE_TIME_Global.ToneMatchErrorCounter = 0;
  CFE_TIME_Global.ToneSignalCounter = 0;
  CFE_TIME_Global.ToneDataCounter = 0;
  CFE_TIME_Global.ToneIntCounter = 0;
  CFE_TIME_Global.ToneIntErrorCounter = 0;
  CFE_TIME_Global.ToneTaskCounter = 0;
  /*
   * Note: Not resetting "LastVersion" counter here, that might
   * disturb access to the time reference data by other tasks
   */
  CFE_TIME_Global.ResetVersionCounter = CFE_TIME_Global.LastVersionCounter;
  CFE_TIME_Global.LocalIntCounter = 0;
  CFE_TIME_Global.LocalTaskCounter = 0;
  CFE_TIME_Global.InternalCount = 0;
  CFE_TIME_Global.ExternalCount = 0;
  CFE_EVS_SendEvent(CFE_TIME_RESET_EID, CFE_EVS_EventType_DEBUG, "Reset Counters command");
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SendDiagnosticTlm(CFE_TIME_SendDiagnosticCmd_t *data)
{
  CFE_TIME_Global.CommandCounter++;
  /*
  ** Collect diagnostics data from Time Services utilities...
  */
  CFE_TIME_GetDiagData();
  /*
  ** Send diagnostics telemetry packet...
  */
  CFE_SB_TimeStampMsg(&CFE_TIME_Global.DiagPacket.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&CFE_TIME_Global.DiagPacket.TelemetryHeader.Msg, TRUE);
  CFE_EVS_SendEvent(CFE_TIME_DIAG_EID, CFE_EVS_EventType_DEBUG, "Request diagnostics command");
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SetStateCmd(CFE_TIME_SetStateCmd_t *data)
{
  CFE_TIME_StateCmd_Payload_t *CommandPtr = &data->Payload;
  U8 *ClockStateText;
  /*
  ** Verify command argument value (clock state)...
  */
  if ((CommandPtr->ClockState == CFE_TIME_ClockState_INVALID) || (CommandPtr->ClockState == CFE_TIME_ClockState_VALID) || (CommandPtr->ClockState == CFE_TIME_ClockState_FLYWHEEL)) {
    CFE_TIME_SetState(CommandPtr->ClockState);
    /*
    ** Select appropriate text for event message...
    */
    if (CommandPtr->ClockState == CFE_TIME_ClockState_INVALID) {
      ClockStateText = "INVALID";
    } else if (CommandPtr->ClockState == CFE_TIME_ClockState_VALID) {
      ClockStateText = "VALID";
    } else {
      ClockStateText = "FLYWHEEL";
    }
    CFE_TIME_Global.CommandCounter++;
    CFE_EVS_SendEvent(CFE_TIME_STATE_EID, CFE_EVS_EventType_INFORMATION, "Set Clock State = %s", ClockStateText);
  } else {
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_STATE_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid Clock State = 0x%X", CommandPtr->ClockState);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SetSourceCmd(CFE_TIME_SetSourceCmd_t *data)
{
  CFE_TIME_SourceCmd_Payload_t *CommandPtr = &data->Payload;
  // [#if CFE_PLATFORM_TIME_CFG_SOURCE == 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_SOURCE is 0); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
  /*
  ** Verify command argument value (time data source)...
  */
  if ((CommandPtr->TimeSource == CFE_TIME_SourceSelect_INTERNAL) || (CommandPtr->TimeSource == CFE_TIME_SourceSelect_EXTERNAL)) {
    // [#if CFE_PLATFORM_TIME_CFG_SOURCE == 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_SOURCE is 0), so what follows is NASA's #else branch]
    /*
    ** We want to know if disabled commands are being sent...
    */
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_SOURCE_CFG_EID, CFE_EVS_EventType_ERROR, "Set Source commands invalid without CFE_PLATFORM_TIME_CFG_SOURCE set to TRUE");
  } else {
    /*
    ** Ground system database will prevent most of these errors...
    */
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_SOURCE_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid Time Source = 0x%X", CommandPtr->TimeSource);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SetSignalCmd(CFE_TIME_SetSignalCmd_t *data)
{
  CFE_TIME_SignalCmd_Payload_t *CommandPtr = &data->Payload;
  // [#if CFE_PLATFORM_TIME_CFG_SIGNAL == 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_SIGNAL is 0); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
  /*
  ** Verify command argument value (tone source)...
  */
  if ((CommandPtr->ToneSource == CFE_TIME_ToneSignalSelect_PRIMARY) || (CommandPtr->ToneSource == CFE_TIME_ToneSignalSelect_REDUNDANT)) {
    // [#if CFE_PLATFORM_TIME_CFG_SIGNAL == 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_SIGNAL is 0), so what follows is NASA's #else branch]
    /*
    ** We want to know if disabled commands are being sent...
    */
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_SIGNAL_CFG_EID, CFE_EVS_EventType_ERROR, "Set Signal commands invalid without CFE_PLATFORM_TIME_CFG_SIGNAL set to TRUE");
  } else {
    /*
    ** Ground system database will prevent most of these errors...
    */
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_SIGNAL_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid Tone Source = 0x%X", CommandPtr->ToneSource);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// `U8 Direction`, not I16, and the difference is NASA's own: here the parameter is
// CFE_TIME_AdjustDirection_Enum_t, which is a uint8 typedef, while cfe_time_utils.c's
// CFE_TIME_SetAdjust and CFE_TIME_Set1HzAdj really do declare `int16 Direction`. The first draft
// wrote I16 in all five by analogy and check_signatures.py could not see it, because int16 on
// NASA's side and I16 on this one both normalised to NOTHING -- so they matched by being equally
// invisible. Both have a token now, and these three turned red.
U0 CFE_TIME_SetDelayImpl(CFE_TIME_TimeCmd_Payload_t *CommandPtr, U8 Direction)
{
  /*
  ** Verify "micro-seconds" command argument...
  */
  if (CommandPtr->MicroSeconds < 1000000) {
    // [#if CFE_PLATFORM_TIME_CFG_CLIENT == 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_CLIENT is 0), so what follows is NASA's #else branch]
    /*
    ** We want to know if disabled commands are being sent...
    */
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_DELAY_CFG_EID, CFE_EVS_EventType_ERROR, "Set Delay commands invalid without CFE_PLATFORM_TIME_CFG_CLIENT set to TRUE");
  } else {
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_DELAY_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid Tone Delay -- secs = %u, usecs = %u", CommandPtr->Seconds, CommandPtr->MicroSeconds);
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_AddDelayCmd(CFE_TIME_AddDelayCmd_t *data)
{
  CFE_TIME_SetDelayImpl(&data->Payload, CFE_TIME_AdjustDirection_ADD);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SubDelayCmd(CFE_TIME_SubDelayCmd_t *data)
{
  CFE_TIME_SetDelayImpl(&data->Payload, CFE_TIME_AdjustDirection_SUBTRACT);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SetTimeCmd(CFE_TIME_SetTimeCmd_t *data)
{
  CFE_TIME_TimeCmd_Payload_t *CommandPtr = &data->Payload;
  /*
  ** Verify "micro-seconds" command argument...
  */
  if (CommandPtr->MicroSeconds < 1000000) {
    // [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
    CFE_TIME_SysTime NewTime;
    NewTime.Seconds = CommandPtr->Seconds;
    NewTime.Subseconds = CFE_TIME_Micro2SubSecs(CommandPtr->MicroSeconds);
    CFE_TIME_SetTime(NewTime);
    CFE_TIME_Global.CommandCounter++;
    CFE_EVS_SendEvent(CFE_TIME_TIME_EID, CFE_EVS_EventType_INFORMATION, "Set Time -- secs = %u, usecs = %u, ssecs = 0x%X", CommandPtr->Seconds, CommandPtr->MicroSeconds, CFE_TIME_Micro2SubSecs(CommandPtr->MicroSeconds));
    // [NASA's #else branch is omitted: it is the one this configuration does not build]
  } else {
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_TIME_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid Time -- secs = %u, usecs = %u", CommandPtr->Seconds, CommandPtr->MicroSeconds);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SetMETCmd(CFE_TIME_SetMETCmd_t *data)
{
  CFE_TIME_TimeCmd_Payload_t *CommandPtr = &data->Payload;
  /*
  ** Verify "micro-seconds" command argument...
  */
  if (CommandPtr->MicroSeconds < 1000000) {
    // [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
    CFE_TIME_SysTime NewMET;
    NewMET.Seconds = CommandPtr->Seconds;
    NewMET.Subseconds = CFE_TIME_Micro2SubSecs(CommandPtr->MicroSeconds);
    CFE_TIME_SetMET(NewMET);
    CFE_TIME_Global.CommandCounter++;
    CFE_EVS_SendEvent(CFE_TIME_MET_EID, CFE_EVS_EventType_INFORMATION, "Set MET -- secs = %u, usecs = %u, ssecs = 0x%X", CommandPtr->Seconds, CommandPtr->MicroSeconds, CFE_TIME_Micro2SubSecs(CommandPtr->MicroSeconds));
    // [NASA's #else branch is omitted: it is the one this configuration does not build]
  } else {
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_MET_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid MET -- secs = %u, usecs = %u", CommandPtr->Seconds, CommandPtr->MicroSeconds);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SetSTCFCmd(CFE_TIME_SetSTCFCmd_t *data)
{
  CFE_TIME_TimeCmd_Payload_t *CommandPtr = &data->Payload;
  /*
  ** Verify "micro-seconds" command argument...
  */
  if (CommandPtr->MicroSeconds < 1000000) {
    // [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
    CFE_TIME_SysTime NewSTCF;
    NewSTCF.Seconds = CommandPtr->Seconds;
    NewSTCF.Subseconds = CFE_TIME_Micro2SubSecs(CommandPtr->MicroSeconds);
    CFE_TIME_SetSTCF(NewSTCF);
    CFE_TIME_Global.CommandCounter++;
    CFE_EVS_SendEvent(CFE_TIME_STCF_EID, CFE_EVS_EventType_INFORMATION, "Set STCF -- secs = %u, usecs = %u, ssecs = 0x%X", CommandPtr->Seconds, CommandPtr->MicroSeconds, CFE_TIME_Micro2SubSecs(CommandPtr->MicroSeconds));
    // [NASA's #else branch is omitted: it is the one this configuration does not build]
  } else {
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_STCF_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid STCF -- secs = %u, usecs = %u", CommandPtr->Seconds, CommandPtr->MicroSeconds);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SetLeapSecondsCmd(CFE_TIME_SetLeapSecondsCmd_t *data)
{
  // [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
  CFE_TIME_LeapsCmd_Payload_t *CommandPtr = &data->Payload;
  /*
  ** No value checking (leaps may be positive or negative)...
  */
  CFE_TIME_SetLeapSeconds(CommandPtr->LeapSeconds);
  CFE_TIME_Global.CommandCounter++;
  CFE_EVS_SendEvent(CFE_TIME_LEAPS_EID, CFE_EVS_EventType_INFORMATION, "Set Leap Seconds = %d", CommandPtr->LeapSeconds);
  // [NASA's #else branch is omitted: it is the one this configuration does not build]
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_AdjustImpl(CFE_TIME_TimeCmd_Payload_t *CommandPtr, U8 Direction)
{
  /*
  ** Verify command arguments...
  */
  if (CommandPtr->MicroSeconds < 1000000) {
    // [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
    CFE_TIME_SysTime Adjust;
    Adjust.Seconds = CommandPtr->Seconds;
    Adjust.Subseconds = CFE_TIME_Micro2SubSecs(CommandPtr->MicroSeconds);
    CFE_TIME_SetAdjust(Adjust, Direction);
    CFE_TIME_Global.CommandCounter++;
    CFE_EVS_SendEvent(CFE_TIME_DELTA_EID, CFE_EVS_EventType_INFORMATION, "STCF Adjust -- secs = %u, usecs = %u, ssecs = 0x%X, dir[1=Pos, 2=Neg] = %d", CommandPtr->Seconds, CommandPtr->MicroSeconds, CFE_TIME_Micro2SubSecs(CommandPtr->MicroSeconds), Direction);
    // [NASA's #else branch is omitted: it is the one this configuration does not build]
  } else {
    CFE_TIME_Global.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_TIME_DELTA_ERR_EID, CFE_EVS_EventType_ERROR, "Invalid STCF Adjust -- secs = %u, usecs = %u, dir[1=Pos, 2=Neg] = %d", CommandPtr->Seconds, CommandPtr->MicroSeconds, Direction);
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_AddAdjustCmd(CFE_TIME_AddAdjustCmd_t *data)
{
  CFE_TIME_AdjustImpl(&data->Payload, CFE_TIME_AdjustDirection_ADD);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SubAdjustCmd(CFE_TIME_SubAdjustCmd_t *data)
{
  CFE_TIME_AdjustImpl(&data->Payload, CFE_TIME_AdjustDirection_SUBTRACT);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_1HzAdjImpl(CFE_TIME_OneHzAdjustmentCmd_Payload_t *CommandPtr, U8 Direction)
{
  /*
  ** 1Hz adjustments are only valid for "Time Servers"...
  */
  // [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
  CFE_TIME_SysTime Adjust;
  // NASA writes `CFE_TIME_Copy(&Adjust, CommandPtr)`, and the reason it is a MACRO upstream is
  // exactly this call: the two arguments have DIFFERENT types -- CFE_TIME_SysTime_t and
  // CFE_TIME_OneHzAdjustmentCmd_Payload_t -- and the macro only needs both to have Seconds and
  // Subseconds. cfe_time_global.HC's CFE_TIME_Copy is a typed function, so it cannot take this
  // pair, and the two fields are copied here instead. That is the one place in TIME where the
  // macro's looseness is load-bearing, and it is this line.
  Adjust.Seconds = CommandPtr->Seconds;
  Adjust.Subseconds = CommandPtr->Subseconds;
  CFE_TIME_Set1HzAdj(Adjust, Direction);
  CFE_TIME_Global.CommandCounter++;
  CFE_EVS_SendEvent(CFE_TIME_ONEHZ_EID, CFE_EVS_EventType_INFORMATION, "STCF 1Hz Adjust -- secs = %d, ssecs = 0x%X, dir[1=Pos, 2=Neg] = %d", CommandPtr->Seconds, CommandPtr->Subseconds, Direction);
  // [NASA's #else branch is omitted: it is the one this configuration does not build]
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_AddOneHzAdjustmentCmd(CFE_TIME_AddOneHzAdjustmentCmd_t *data)
{
  CFE_TIME_1HzAdjImpl(&data->Payload, CFE_TIME_AdjustDirection_ADD);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TIME_SubOneHzAdjustmentCmd(CFE_TIME_SubOneHzAdjustmentCmd_t *data)
{
  CFE_TIME_1HzAdjImpl(&data->Payload, CFE_TIME_AdjustDirection_SUBTRACT);
  return CFE_SUCCESS;
}
#endif
