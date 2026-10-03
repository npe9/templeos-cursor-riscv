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
// 1:1 HolyC translation of cFE modules/sb/fsw/src/cfe_sb_task.c -- THE SB APPLICATION.
//
// cfe_sb_api.HC is the bus as a library; this is the bus as an APP: a task with a command pipe,
// fourteen housekeeping counters, eleven ground commands and three file writers. The three
// files are the interesting part -- SB can dump its routing table, its pipe table and its
// message-id map to disk, and it does so a few records at a time through the FS background
// writer rather than in one pass, because a full routing table is larger than any buffer it
// is allowed to hold.
//
// AND THIS IS WHERE CFE_SB_SendSubscriptionReport STOPS BEING A STUB. cfe_sb_api.HC's
// CFE_SB_SubscribeFull calls it on every successful global subscribe, and until this file it
// was a recording stub on both sides of the differential oracle.
#ifndef CFE_SB_TASK_HC
#define CFE_SB_TASK_HC
#include "cfe_sb_api.HC" // the public bus this app commands
// --- cfe_sb_eventids.h: the sixteen this file raises ------------------------------------------
#define CFE_SB_INIT_EID             1
#define CFE_SB_SUBSCRIPTION_RPT_EID 22
#define CFE_SB_CMD0_RCVD_EID        28
#define CFE_SB_CMD1_RCVD_EID        29
#define CFE_SB_SND_STATS_EID        32
#define CFE_SB_ENBL_RTE1_EID        33
#define CFE_SB_ENBL_RTE2_EID        34
#define CFE_SB_ENBL_RTE3_EID        35
#define CFE_SB_DSBL_RTE1_EID        36
#define CFE_SB_DSBL_RTE2_EID        37
#define CFE_SB_DSBL_RTE3_EID        38
#define CFE_SB_SND_RTG_EID          39
#define CFE_SB_SND_RTG_ERR1_EID     40
#define CFE_SB_FULL_SUB_PKT_EID     44
#define CFE_SB_PART_SUB_PKT_EID     45
#define CFE_SB_FILEWRITE_ERR_EID    49
// --- default_cfe_sb_msgids.h ------------------------------------------------------------------
#define CFE_SB_HK_TLM_MID       0x0803
#define CFE_SB_ALLSUBS_TLM_MID  0x080D
#define CFE_SB_SUB_RPT_CTRL_MID 0x180E
#define CFE_SB_ONESUB_TLM_MID   0x080E
// --- cfe_sb_internal_cfg.h / cfe_mission_cfg.h ------------------------------------------------
#define CFE_PLATFORM_SB_CMD_PIPE_DEPTH 50
#define CFE_PLATFORM_SB_CMD_PIPE_NAME  "SB_CMD_PIPE"
#define CFE_PLATFORM_SB_MAX_MSG_IDS    256
#define CFE_MISSION_SB_MAX_PIPES       32
#define CFE_MISSION_SB_MAIN_PERF_ID    4
#define CFE_CFG_MAX_VERSION_STR_LEN    256
// --- cfe_sb_internal_cfg.h: the EIGHT EVENTS SB FILTERS AT STARTUP ---------------------------
// Four are set and four are zero, and the zeros are load-bearing: CFE_SB_AppInit's loop skips a
// zero EVENT, so the filter count it registers with EVS is FOUR, not eight. The four it does
// filter are the ones a busy bus would otherwise flood the event log with -- no subscribers, a
// duplicate subscription, the per-message-id limit and a full pipe queue.
//
// ALL FOUR PAIRS ARE IN THE TRANSCRIPT, and that is deliberate rather than thorough. These
// #defines expand to other macro NAMES, which puts every one of them in check_constants.py's
// "not a literal and so NOT compared" bucket -- so nothing but the transcript can see them,
// and the first draft of this file had three of the four event names INFERRED FROM THEIR
// VALUES rather than read from NASA's header. The driver prints EventFilters[0..3] with their
// masks, and the C half fills those using the real macros, so a wrong name diverges at once.
//
// cfe_evs_api_typedefs.h's binary-filter masks, which NASA documents as "send the first N".
#ifndef CFE_EVS_FIRST_4_STOP
#define CFE_EVS_FIRST_4_STOP  0xFFFC
#define CFE_EVS_FIRST_16_STOP 0xFFF0
#define CFE_EVS_NO_FILTER     0x0000
#endif
#define CFE_PLATFORM_SB_FILTERED_EVENT1 CFE_SB_SEND_NO_SUBS_EID
#define CFE_PLATFORM_SB_FILTER_MASK1    CFE_EVS_FIRST_4_STOP
#define CFE_PLATFORM_SB_FILTERED_EVENT2 CFE_SB_DUP_SUBSCRIP_EID
#define CFE_PLATFORM_SB_FILTER_MASK2    CFE_EVS_FIRST_4_STOP
#define CFE_PLATFORM_SB_FILTERED_EVENT3 CFE_SB_MSGID_LIM_ERR_EID
#define CFE_PLATFORM_SB_FILTER_MASK3    CFE_EVS_FIRST_16_STOP
#define CFE_PLATFORM_SB_FILTERED_EVENT4 CFE_SB_Q_FULL_ERR_EID
#define CFE_PLATFORM_SB_FILTER_MASK4    CFE_EVS_FIRST_16_STOP
#define CFE_PLATFORM_SB_FILTERED_EVENT5 0
#define CFE_PLATFORM_SB_FILTER_MASK5    CFE_EVS_NO_FILTER
#define CFE_PLATFORM_SB_FILTERED_EVENT6 0
#define CFE_PLATFORM_SB_FILTER_MASK6    CFE_EVS_NO_FILTER
#define CFE_PLATFORM_SB_FILTERED_EVENT7 0
#define CFE_PLATFORM_SB_FILTER_MASK7    CFE_EVS_NO_FILTER
#define CFE_PLATFORM_SB_FILTERED_EVENT8 0
#define CFE_PLATFORM_SB_FILTER_MASK8    CFE_EVS_NO_FILTER
// --- cfe_sb_internal_cfg.h: where the three dump files go by default -------------------------
#define CFE_PLATFORM_SB_DEFAULT_ROUTING_FILENAME "/ram/cfe_sb_route.dat"
#define CFE_PLATFORM_SB_DEFAULT_PIPE_FILENAME    "/ram/cfe_sb_pipe.dat"
#define CFE_PLATFORM_SB_DEFAULT_MAP_FILENAME     "/ram/cfe_sb_msgmap.dat"
// --- cfe_sb_api_typedefs.h: the subscription-report subtype ----------------------------------
// The other value, CFE_SB_UNSUBSCRIPTION, is 1 and nothing in cFE sends it -- NASA's comment
// says the SBN app is the consumer of both.
#define CFE_SB_SUBSCRIPTION 0
// --- cfe_sb_verify.h / cfe_sb_priv.h: the enable/disable pair --------------------------------
#ifndef CFE_SB_ENABLE
#define CFE_SB_ENABLE  1
#define CFE_SB_DISABLE 0
#endif
// --- default_cfe_es_msgstruct.h: the ONE ES TYPE this file needs ----------------------------
// CFE_SB_AppInit does `CFE_ES_GetPoolBuf(..., sizeof(CFE_ES_RestartCmd_t))` purely so that the
// pool has a block of that size configured -- the memory is freed on the next line. So the
// only thing that matters about this type is its SIZE, and getting it wrong would configure
// the wrong block size and let a ground-commanded reset fail to allocate (DCR6772, which is
// what the allocation exists to prevent). check_padding.py measures it against NASA's.
class CFE_ES_RestartCmd_Payload_t
{
  U16 RestartType;
  // CFE_PSP_RST_TYPE_PROCESSOR or CFE_PSP_RST_TYPE_POWERON
};

class CFE_ES_RestartCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_RestartCmd_Payload_t Payload;
};
// --- what this file needs from elsewhere ------------------------------------------------------
// ES's task lifecycle, the config service's version string, and the FS background file writer.
// None of ES is translated; FS is, and CFE_FS_BackgroundFileDumpRequest lives there.
U0 CFE_ES_PerfLogAdd(U32 Marker, U32 EntryExit);
U0 CFE_ES_IncrementTaskCounter();
U0 CFE_ES_ExitApp(U32 ExitStatus);
I32 CFE_ES_WaitForSystemState(U32 MinSystemState, U32 TimeOutMilliseconds);
I32 CFE_EVS_Register(U8 *Filters, U16 NumEventFilters, U16 FilterScheme);
U0 CFE_Config_GetVersionString(U8 *Buf, I64 Size, U8 *CfgName, U8 *SrcVer, U8 *CodeName, U8 *LastOffcl);
// cfe_sb_dispatch.c, translated after this file; CFE_SB_TaskMain's loop body.
U0 CFE_SB_ProcessCmdPipePkt(CFE_SB_Buffer *SBBufPtr);
// Declared here and defined below, in the C's own order.
U0 CFE_SB_ResetCounters();
U0 CFE_SB_SetSubscriptionReporting(U32 state);
I32 CFE_SB_AppInit();
/*  Task Globals */
// NASA defines CFE_SB_Global here, and so does the translation -- in cfe_sb_global.HC, beside
// its type, for the reason recorded there.
//
// THE TWO FILTER TABLES ARE FILE-SCOPE AGGREGATE INITIALISERS, which HolyC does support (and
// tests/exec/cases/zz-style probing confirmed before this was written, because a limit
// recorded for LOCAL aggregates reads as if it applied here too). NASA writes them with the
// CFE_PLATFORM_SB_FILTERED_EVENTn / FILTER_MASKn macros; those expand to event ids and EVS
// filter masks, and check_constants.py compares each one, so they are spelled by name.
I32 CFE_Platform_SB_Filter_Events[CFE_PLATFORM_EVS_MAX_EVENT_FILTERS] = {CFE_PLATFORM_SB_FILTERED_EVENT1, CFE_PLATFORM_SB_FILTERED_EVENT2, CFE_PLATFORM_SB_FILTERED_EVENT3, CFE_PLATFORM_SB_FILTERED_EVENT4, CFE_PLATFORM_SB_FILTERED_EVENT5, CFE_PLATFORM_SB_FILTERED_EVENT6, CFE_PLATFORM_SB_FILTERED_EVENT7, CFE_PLATFORM_SB_FILTERED_EVENT8};
I32 CFE_Platform_SB_Filter_Masks[CFE_PLATFORM_EVS_MAX_EVENT_FILTERS] = {CFE_PLATFORM_SB_FILTER_MASK1, CFE_PLATFORM_SB_FILTER_MASK2, CFE_PLATFORM_SB_FILTER_MASK3, CFE_PLATFORM_SB_FILTER_MASK4, CFE_PLATFORM_SB_FILTER_MASK5, CFE_PLATFORM_SB_FILTER_MASK6, CFE_PLATFORM_SB_FILTER_MASK7, CFE_PLATFORM_SB_FILTER_MASK8};
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_TaskMain()
{
  I32 Status;
  CFE_SB_Buffer *SBBufPtr;
  CFE_ES_PerfLogEntry(CFE_MISSION_SB_MAIN_PERF_ID);
  Status = CFE_SB_AppInit();
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Application Init Failed,RC=0x%08X\n", "CFE_SB_TaskMain", Status);
    CFE_ES_PerfLogExit(CFE_MISSION_SB_MAIN_PERF_ID);
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
    CFE_ES_PerfLogExit(CFE_MISSION_SB_MAIN_PERF_ID);
    /* Pend on receipt of packet */
    Status = CFE_SB_ReceiveBuffer(&SBBufPtr, CFE_SB_Global.CmdPipe, CFE_SB_PEND_FOREVER);
    CFE_ES_PerfLogEntry(CFE_MISSION_SB_MAIN_PERF_ID);
    if (Status == CFE_SUCCESS) {
      /* Process cmd pipe msg */
      CFE_SB_ProcessCmdPipePkt(SBBufPtr);
    } else {
      CFE_ES_WriteToSysLog("%s: Error reading cmd pipe,RC=0x%08X\n", "CFE_SB_TaskMain", Status);
    }
  }
  /* end while */
  /* while loop exits only if CFE_SB_ReceiveBuffer returns error */
  CFE_ES_ExitApp(CFE_ES_RunStatus_CORE_APP_RUNTIME_ERROR);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE GetPoolBuf/PutPoolBuf PAIR NEAR THE END IS NOT DEAD CODE, and NASA's comment says why:
// it allocates and immediately frees a block the size of a reset command, so that the pool has
// a block of that size CONFIGURED. A ground-commanded reset must not be the allocation that
// fails because the pool filled up with other block sizes first. DCR6772.
I32 CFE_SB_AppInit()
{
  U32 CfgFileEventsToFilter = 0;
  U8 *TmpPtr;
  I32 Status;
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];
  I32 CurrEvent, CurrMask;
  I32 i;
  /* Get the assigned Application ID for the SB Task */
  CFE_ES_GetAppID(&CFE_SB_Global.AppId);
  /* Process the platform cfg file events to be filtered */
  for (i = 0; i < CFE_PLATFORM_EVS_MAX_EVENT_FILTERS; i++) {
    if (CFE_Platform_SB_Filter_Events[i] != 0) {
      CurrEvent = CFE_Platform_SB_Filter_Events[i];
      CurrMask = CFE_Platform_SB_Filter_Masks[i];
      CFE_SB_Global.EventFilters[CfgFileEventsToFilter].EventID = CurrEvent;
      CFE_SB_Global.EventFilters[CfgFileEventsToFilter].Mask = CurrMask;
      CfgFileEventsToFilter++;
    }
  }
  /* Register event filter table... */
  Status = CFE_EVS_Register(CFE_SB_Global.EventFilters, CfgFileEventsToFilter, CFE_EVS_EventFilter_BINARY);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Call to CFE_EVS_Register Failed:RC=0x%08X\n", "CFE_SB_AppInit", Status);
    return Status;
  }
  CFE_ES_WriteToSysLog("%s: Registered %d events for filtering\n", "CFE_SB_AppInit", CfgFileEventsToFilter);
  CFE_MSG_Init(&CFE_SB_Global.HKTlmMsg.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CFE_SB_HK_TLM_MID), sizeof(CFE_SB_HousekeepingTlm_t));
  CFE_MSG_Init(&CFE_SB_Global.PrevSubMsg.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CFE_SB_ALLSUBS_TLM_MID), sizeof(CFE_SB_AllSubscriptionsTlm_t));
  /* Populate the fixed fields in the HK Tlm Msg */
  CFE_SB_Global.HKTlmMsg.Payload.MemPoolHandle = CFE_SB_Global.Mem.PoolHdl;
  /* Populate the fixed fields in the Stat Tlm Msg */
  CFE_SB_Global.StatTlmMsg.Payload.MaxMsgIdsAllowed = CFE_PLATFORM_SB_MAX_MSG_IDS;
  CFE_SB_Global.StatTlmMsg.Payload.MaxPipesAllowed = CFE_PLATFORM_SB_MAX_PIPES;
  CFE_SB_Global.StatTlmMsg.Payload.MaxMemAllowed = CFE_PLATFORM_SB_BUF_MEMORY_BYTES;
  CFE_SB_Global.StatTlmMsg.Payload.MaxPipeDepthAllowed = OS_QUEUE_MAX_DEPTH;
  CFE_SB_Global.StatTlmMsg.Payload.MaxSubscriptionsAllowed = CFE_PLATFORM_SB_MAX_MSG_IDS *CFE_PLATFORM_SB_MAX_DEST_PER_PKT;
  Status = CFE_SB_CreatePipe(&CFE_SB_Global.CmdPipe, CFE_PLATFORM_SB_CMD_PIPE_DEPTH, CFE_PLATFORM_SB_CMD_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Call to CFE_SB_CreatePipe Failed:RC=0x%08X\n", "CFE_SB_AppInit", Status);
    return Status;
  }
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_SB_CMD_MID), CFE_SB_Global.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Subscribe to Cmds Failed:RC=0x%08X\n", "CFE_SB_AppInit", Status);
    return Status;
  }
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_SB_SEND_HK_MID), CFE_SB_Global.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Subscribe to HK Request Failed:RC=0x%08X\n", "CFE_SB_AppInit", Status);
    return Status;
  }
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CFE_SB_SUB_RPT_CTRL_MID), CFE_SB_Global.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Subscribe to Subscription Report Request Failed:RC=0x%08X\n", "CFE_SB_AppInit", Status);
    return Status;
  }
  /* Ensure a ground commanded reset does not get blocked if SB mem pool  */
  /* becomes fully configured (DCR6772) */
  Status = CFE_ES_GetPoolBuf(&TmpPtr, CFE_SB_Global.Mem.PoolHdl, sizeof(CFE_ES_RestartCmd_t));
  if (Status < 0) {
    CFE_ES_WriteToSysLog("%s: Init error, GetPool Failed:RC=0x%08X\n", "CFE_SB_AppInit", Status);
    return Status;
  }
  /* Return mem block used on previous call,the actual memory is not needed.*/
  /* The SB mem pool is now configured with a block size for the reset cmd. */
  Status = CFE_ES_PutPoolBuf(CFE_SB_Global.Mem.PoolHdl, TmpPtr);
  if (Status < 0) {
    CFE_ES_WriteToSysLog("%s: Init error, PutPool Failed:RC=0x%08X\n", "CFE_SB_AppInit", Status);
    return Status;
  }
  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "CFE_SB", CFE_SRC_VERSION, CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);
  Status = CFE_EVS_SendEvent(CFE_SB_INIT_EID, CFE_EVS_EventType_INFORMATION, "cFE SB Initialized: %s", VersionString);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error sending init event:RC=0x%08X\n", "CFE_SB_AppInit", Status);
    return Status;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_NoopCmd(CFE_SB_NoopCmd_t *data)
{
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];
  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "CFE_SB", CFE_SRC_VERSION, CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);
  CFE_EVS_SendEvent(CFE_SB_CMD0_RCVD_EID, CFE_EVS_EventType_INFORMATION, "No-op Cmd Rcvd: %s", VersionString);
  CFE_SB_Global.HKTlmMsg.Payload.CommandCounter++;
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_ResetCountersCmd(CFE_SB_ResetCountersCmd_t *data)
{
  CFE_EVS_SendEvent(CFE_SB_CMD1_RCVD_EID, CFE_EVS_EventType_DEBUG, "Reset Counters Cmd Rcvd");
  CFE_SB_ResetCounters();
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_EnableSubReportingCmd(CFE_SB_EnableSubReportingCmd_t *data)
{
  CFE_SB_SetSubscriptionReporting(CFE_SB_ENABLE);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_DisableSubReportingCmd(CFE_SB_DisableSubReportingCmd_t *data)
{
  CFE_SB_SetSubscriptionReporting(CFE_SB_DISABLE);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_SendHKTlmCmd(CFE_SB_SendHkCmd_t *data)
{
  CFE_SB_LockSharedData("cfe_sb_task.c", 310);
  CFE_SB_Global.HKTlmMsg.Payload.MemInUse = CFE_SB_Global.StatTlmMsg.Payload.MemInUse;
  CFE_SB_Global.HKTlmMsg.Payload.UnmarkedMem = CFE_PLATFORM_SB_BUF_MEMORY_BYTES - CFE_SB_Global.StatTlmMsg.Payload.PeakMemInUse;
  CFE_SB_UnlockSharedData("cfe_sb_task.c", 316);
  CFE_SB_TimeStampMsg(&CFE_SB_Global.HKTlmMsg.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&CFE_SB_Global.HKTlmMsg.TelemetryHeader.Msg, TRUE);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_ResetCounters()
{
  CFE_SB_Global.HKTlmMsg.Payload.CommandCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.NoSubscribersCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.DuplicateSubscriptionsCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.MsgSendErrorCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.MsgReceiveErrorCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.InternalErrorCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.CreatePipeErrorCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.DeletePipeErrorCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.SubscribeErrorCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.PipeOptsErrorCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.GetPipeIdByNameErrorCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.PipeOverflowErrorCounter = 0;
  CFE_SB_Global.HKTlmMsg.Payload.MsgLimitErrorCounter = 0;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_EnableRouteCmd(CFE_SB_EnableRouteCmd_t *data)
{
  CFE_SB_MsgId MsgId;
  CFE_SB_PipeD_t *PipeDscPtr;
  CFE_SB_DestinationD_t *DestPtr;
  CFE_SB_RouteCmd_Payload_t *CmdPtr;
  U16 PendingEventID;
  PendingEventID = 0;
  CmdPtr = &data->Payload;
  MsgId = CmdPtr->MsgId;
  CFE_SB_LockSharedData("CFE_SB_EnableRouteCmd", 367);
  /* check cmd parameters */
  PipeDscPtr = CFE_SB_LocatePipeDescByID(CmdPtr->Pipe);
  if (!CFE_SB_IsValidMsgId(MsgId) || !CFE_SB_PipeDescIsMatch(PipeDscPtr, CmdPtr->Pipe)) {
    PendingEventID = CFE_SB_ENBL_RTE3_EID;
    CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter++;
  } else {
    DestPtr = CFE_SB_GetDestPtr(CFE_SBR_GetRouteId(MsgId), CmdPtr->Pipe);
    if (DestPtr == NULL) {
      PendingEventID = CFE_SB_ENBL_RTE1_EID;
      CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter++;
    } else {
      DestPtr->Active = CFE_SB_ACTIVE;
      PendingEventID = CFE_SB_ENBL_RTE2_EID;
      CFE_SB_Global.HKTlmMsg.Payload.CommandCounter++;
    }
  }
  CFE_SB_UnlockSharedData("CFE_SB_EnableRouteCmd", 392);
  switch (PendingEventID) {
    case CFE_SB_ENBL_RTE1_EID :
    CFE_EVS_SendEvent(CFE_SB_ENBL_RTE1_EID, CFE_EVS_EventType_ERROR, "Enbl Route Cmd:Route does not exist.Msg 0x%x,Pipe %lu", CFE_SB_MsgIdToValue(MsgId), CmdPtr->Pipe);
    break;
    case CFE_SB_ENBL_RTE3_EID :
    CFE_EVS_SendEvent(CFE_SB_ENBL_RTE3_EID, CFE_EVS_EventType_ERROR, "Enbl Route Cmd:Invalid Param.Msg 0x%x,Pipe %lu", CFE_SB_MsgIdToValue(MsgId), CmdPtr->Pipe);
    break;
    case CFE_SB_ENBL_RTE2_EID :
    /* Intentional fall through */
    default:
    CFE_EVS_SendEvent(CFE_SB_ENBL_RTE2_EID, CFE_EVS_EventType_DEBUG, "Enabling Route,Msg 0x%x,Pipe %lu", CFE_SB_MsgIdToValue(MsgId), CmdPtr->Pipe);
    break;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_DisableRouteCmd(CFE_SB_DisableRouteCmd_t *data)
{
  CFE_SB_MsgId MsgId;
  CFE_SB_PipeD_t *PipeDscPtr;
  CFE_SB_DestinationD_t *DestPtr;
  CFE_SB_RouteCmd_Payload_t *CmdPtr;
  U16 PendingEventID;
  PendingEventID = 0;
  CmdPtr = &data->Payload;
  MsgId = CmdPtr->MsgId;
  CFE_SB_LockSharedData("CFE_SB_DisableRouteCmd", 443);
  /* check cmd parameters */
  PipeDscPtr = CFE_SB_LocatePipeDescByID(CmdPtr->Pipe);
  if (!CFE_SB_IsValidMsgId(MsgId) || !CFE_SB_PipeDescIsMatch(PipeDscPtr, CmdPtr->Pipe)) {
    PendingEventID = CFE_SB_DSBL_RTE3_EID;
    CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter++;
  } else {
    DestPtr = CFE_SB_GetDestPtr(CFE_SBR_GetRouteId(MsgId), CmdPtr->Pipe);
    if (DestPtr == NULL) {
      PendingEventID = CFE_SB_DSBL_RTE1_EID;
      CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter++;
    } else {
      DestPtr->Active = CFE_SB_INACTIVE;
      PendingEventID = CFE_SB_DSBL_RTE2_EID;
      CFE_SB_Global.HKTlmMsg.Payload.CommandCounter++;
    }
  }
  CFE_SB_UnlockSharedData("CFE_SB_DisableRouteCmd", 468);
  switch (PendingEventID) {
    case CFE_SB_DSBL_RTE1_EID :
    CFE_EVS_SendEvent(CFE_SB_DSBL_RTE1_EID, CFE_EVS_EventType_ERROR, "Disable Route Cmd:Route does not exist,Msg 0x%x,Pipe %lu", CFE_SB_MsgIdToValue(MsgId), CmdPtr->Pipe);
    break;
    case CFE_SB_DSBL_RTE3_EID :
    CFE_EVS_SendEvent(CFE_SB_DSBL_RTE3_EID, CFE_EVS_EventType_ERROR, "Disable Route Cmd:Invalid Param.Msg 0x%x,Pipe %lu", CFE_SB_MsgIdToValue(MsgId), CmdPtr->Pipe);
    break;
    case CFE_SB_DSBL_RTE2_EID :
    /* Intentional fall through */
    default:
    CFE_EVS_SendEvent(CFE_SB_DSBL_RTE2_EID, CFE_EVS_EventType_DEBUG, "Route Disabled,Msg 0x%x,Pipe %lu", CFE_SB_MsgIdToValue(MsgId), CmdPtr->Pipe);
    break;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// TWO LOOPS WITH ONE SHARED CURSOR, and the second one runs UNLOCKED. The first walks the pipe
// table under the lock copying depth stats into the telemetry packet; the second zeroes the
// remaining packet slots, and it can be unlocked because those slots are the packet's, not
// SB's. PipeStatPtr and PipeStatCount carry across, which is why the second loop is a `while`
// on the same counter rather than a fresh one.
I32 CFE_SB_SendStatsCmd(CFE_SB_SendSbStatsCmd_t *data)
{
  U32 PipeDscCount;
  U32 PipeStatCount;
  CFE_SB_PipeD_t *PipeDscPtr;
  CFE_SB_PipeDepthStats_t *PipeStatPtr;
  CFE_SB_LockSharedData("cfe_sb_task.c", 513);
  /* Collect data on pipes */
  PipeDscCount = CFE_PLATFORM_SB_MAX_PIPES;
  PipeStatCount = CFE_MISSION_SB_MAX_PIPES;
  PipeDscPtr = CFE_SB_Global.PipeTbl;
  PipeStatPtr = CFE_SB_Global.StatTlmMsg.Payload.PipeDepthStats;
  while (PipeDscCount > 0 && PipeStatCount > 0) {
    if (CFE_SB_PipeDescIsUsed(PipeDscPtr)) {
      PipeStatPtr->PipeId = PipeDscPtr->PipeId;
      /* Copy depth info */
      PipeStatPtr->CurrentQueueDepth = PipeDscPtr->CurrentQueueDepth;
      PipeStatPtr->PeakQueueDepth = PipeDscPtr->PeakQueueDepth;
      PipeStatPtr->MaxQueueDepth = PipeDscPtr->MaxQueueDepth;
      ++PipeStatPtr;
      --PipeStatCount;
    }
    --PipeDscCount;
    ++PipeDscPtr;
  }
  CFE_SB_UnlockSharedData("cfe_sb_task.c", 540);
  while (PipeStatCount > 0) {
    MemSet(PipeStatPtr, 0, sizeof(CFE_SB_PipeDepthStats_t));
    ++PipeStatPtr;
    --PipeStatCount;
  }
  CFE_SB_TimeStampMsg(&CFE_SB_Global.StatTlmMsg.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&CFE_SB_Global.StatTlmMsg.TelemetryHeader.Msg, TRUE);
  CFE_EVS_SendEvent(CFE_SB_SND_STATS_EID, CFE_EVS_EventType_DEBUG, "Software Bus Statistics packet sent");
  CFE_SB_Global.HKTlmMsg.Payload.CommandCounter++;
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE NAME LOOKUPS HAPPEN AFTER THE UNLOCK, DELIBERATELY. The locked part copies the ids; the
// unlocked part asks ES and OSAL what those ids are called, because both of those are other
// subsystems with their own locks and calling into them while holding SB's is how a deadlock
// gets built. DestAppId is the hand-off: a small stack array of app ids snapshotted inside the
// lock and resolved to names outside it.
U0 CFE_SB_CollectRouteInfo(CFE_SBR_RouteId RouteId, U8 *ArgPtr)
{
  CFE_SB_DestinationD_t *DestPtr;
  CFE_SB_PipeD_t *PipeDscPtr;
  CFE_SB_MsgId RouteMsgId;
  CFE_SB_BackgroundRouteInfoBuffer_t *RouteBufferPtr;
  CFE_SB_RoutingFileEntry_t *FileEntryPtr;
  U32 DestAppId[CFE_PLATFORM_SB_MAX_DEST_PER_PKT];
  U32 i;
  /* Cast arguments for local use */
  RouteBufferPtr = ArgPtr;
  /* Extract data from runtime info, write into the temporary buffer */
  /* Data must be locked to snapshot the route info */
  CFE_SB_LockSharedData("cfe_sb_task.c", 581);
  RouteMsgId = CFE_SBR_GetMsgId(RouteId);
  RouteBufferPtr->NumDestinations = 0;
  /* If this is a valid route, get the destinations */
  if (CFE_SB_IsValidMsgId(RouteMsgId)) {
    DestPtr = CFE_SBR_GetDestListHeadPtr(RouteId);
    /* copy relevant data from the destination list into the temp buffer */
    while (DestPtr != NULL && RouteBufferPtr->NumDestinations < CFE_PLATFORM_SB_MAX_DEST_PER_PKT) {
      PipeDscPtr = CFE_SB_LocatePipeDescByID(DestPtr->PipeId);
      /* If invalid id, continue on to next entry */
      if (CFE_SB_PipeDescIsMatch(PipeDscPtr, DestPtr->PipeId)) {
        FileEntryPtr = &RouteBufferPtr->DestEntries[RouteBufferPtr->NumDestinations];
        /* clear all fields in the temp buffer before re-use */
        MemSet(FileEntryPtr, 0, sizeof(CFE_SB_RoutingFileEntry_t));
        FileEntryPtr->PipeId = DestPtr->PipeId;
        FileEntryPtr->State = DestPtr->Active;
        FileEntryPtr->MsgCnt = DestPtr->DestCnt;
        /* Stash the Pipe Owner AppId - App Name is looked up later (comes from ES) */
        DestAppId[RouteBufferPtr->NumDestinations] = PipeDscPtr->AppId;
        ++RouteBufferPtr->NumDestinations;
      }
      DestPtr = DestPtr->Next;
    }
  }
  CFE_SB_UnlockSharedData("cfe_sb_task.c", 618);
  /* Go through the temp buffer and fill in the remaining info for each dest */
  FileEntryPtr = RouteBufferPtr->DestEntries;
  for (i = 0; i < RouteBufferPtr->NumDestinations; ++i) {
    /* All dest entries refer to the same MsgId (based on the route) */
    FileEntryPtr->MsgId = RouteMsgId;
    /*
     * NOTE: as long as CFE_ES_GetAppName() is given a nonzero-length
     * output buffer, it guarantees null termination of the output, even
     * if the AppID is invalid - in which case it returns an empty string.
     */
    CFE_ES_GetAppName(FileEntryPtr->AppName, DestAppId[i], CFE_MISSION_MAX_API_LEN);
    CFE_SB_GetPipeName(FileEntryPtr->PipeName, CFE_MISSION_MAX_API_LEN, FileEntryPtr->PipeId);
    ++FileEntryPtr;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// AND HERE IT STOPS BEING A STUB. cfe_sb_api.HC's CFE_SB_SubscribeFull calls this on every
// successful GLOBAL subscribe; until this file it was a recording stub on both sides of the
// differential oracle, because it lives here and here was not translated.
//
// It does nothing unless SubscriptionReporting is enabled, which is why the two commands above
// that set that flag are worth having: the whole of this function is behind them.
I32 CFE_SB_SendSubscriptionReport(CFE_SB_MsgId MsgId, U32 PipeId, CFE_SB_Qos_t Quality)
{
  CFE_SB_SingleSubscriptionTlm_t SubRptMsg;
  I32 Status = CFE_SUCCESS;
  MemSet(&SubRptMsg, 0, sizeof(CFE_SB_SingleSubscriptionTlm_t));
  if (CFE_SB_Global.SubscriptionReporting == CFE_SB_ENABLE) {
    CFE_MSG_Init(&SubRptMsg.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CFE_SB_ONESUB_TLM_MID), sizeof(CFE_SB_SingleSubscriptionTlm_t));
    SubRptMsg.Payload.MsgId = MsgId;
    SubRptMsg.Payload.Pipe = PipeId;
    SubRptMsg.Payload.Qos = Quality;
    SubRptMsg.Payload.SubType = CFE_SB_SUBSCRIPTION;
    Status = CFE_SB_TransmitMsg(&SubRptMsg.TelemetryHeader.Msg, TRUE);
    CFE_EVS_SendEventWithAppID(CFE_SB_SUBSCRIPTION_RPT_EID, CFE_EVS_EventType_DEBUG, CFE_SB_Global.AppId, "Sending Subscription Report Msg=0x%x,Pipe=%lu,Stat=0x%x", CFE_SB_MsgIdToValue(MsgId), PipeId, Status);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE THROTTLE IS WHAT MAKES THIS A BACKGROUND JOB. MaxLoop = 1 means CFE_SBR_ForEachRouteId
// visits exactly ONE route per call, and NextIndex comes back nonzero while there are more.
// Returning TRUE means end-of-file, so `Throttle.NextIndex == 0` IS the EOF test -- the file
// writer calls this once per background cycle until it says so.
Bool CFE_SB_WriteRouteInfoDataGetter(U8 *Meta, U32 RecordNum, U8 **Buffer, I64 *BufSize)
{
  CFE_SB_BackgroundFileStateInfo_t *BgFilePtr;
  CFE_SBR_Throttle Throttle;
  /* Cast arguments for local use */
  BgFilePtr = Meta;
  Throttle.StartIndex = RecordNum;
  Throttle.MaxLoop = 1;
  Throttle.NextIndex = 0;
  /* Reset NumDestinations to 0, just in case the CFE_SBR_ForEachRouteId() is a no-op */
  BgFilePtr->Buffer.RouteInfo.NumDestinations = 0;
  /* Collect info on the next route (limited to one per cycle via throttle) */
  CFE_SBR_ForEachRouteId(&CFE_SB_CollectRouteInfo, &BgFilePtr->Buffer.RouteInfo, &Throttle);
  /* Pass the output of CFE_SB_CollectRouteInfo() back to be written */
  *Buffer = &BgFilePtr->Buffer.RouteInfo.DestEntries;
  *BufSize = sizeof(CFE_SB_RoutingFileEntry_t) * BgFilePtr->Buffer.RouteInfo.NumDestinations;
  /* Check for EOF (last entry) - NextIndex is nonzero if more records left, zero at the end of
   * the route table */
  return Throttle.NextIndex == 0;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_BackgroundFileEventHandler(U8 *Meta, U32 Event, I32 Status, U32 RecordNum, I64 BlockSize, I64 Position)
{
  CFE_SB_BackgroundFileStateInfo_t *BgFilePtr;
  BgFilePtr = Meta;
  /*
   * Note that this runs in the context of ES background task (file writer background job)
   * It does NOT run in the context of the CFE_TBL app task.
   *
   * Events should use CFE_EVS_SendEventWithAppID() rather than CFE_EVS_SendEvent()
   * to get proper association with TBL task.
   */
  switch (Event) {
    case CFE_FS_FileWriteEvent_COMPLETE :
    CFE_EVS_SendEventWithAppID(CFE_SB_SND_RTG_EID, CFE_EVS_EventType_DEBUG, CFE_SB_Global.AppId, "%s written:Size=%d,Entries=%d", BgFilePtr->FileWrite.FileName, Position, RecordNum);
    break;
    case CFE_FS_FileWriteEvent_HEADER_WRITE_ERROR :
    case CFE_FS_FileWriteEvent_RECORD_WRITE_ERROR :
    CFE_EVS_SendEventWithAppID(CFE_SB_FILEWRITE_ERR_EID, CFE_EVS_EventType_ERROR, CFE_SB_Global.AppId, "File write,byte cnt err,file %s,request=%d,actual=%d", BgFilePtr->FileWrite.FileName, BlockSize, Status);
    break;
    case CFE_FS_FileWriteEvent_CREATE_ERROR :
    CFE_EVS_SendEventWithAppID(CFE_SB_SND_RTG_ERR1_EID, CFE_EVS_EventType_ERROR, CFE_SB_Global.AppId, "Error creating file %s, stat=0x%x", BgFilePtr->FileWrite.FileName, Status);
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
// THE THREE FILE COMMANDS ARE THE SAME FUNCTION THREE TIMES, and NASA wrote them out rather
// than factoring them. The translation keeps that: the only differences are the subtype, the
// description, the getter and the default filename, and a shared helper taking four arguments
// would be a refactor the oracle could not justify.
//
// All three return CFE_SUCCESS whatever happens. The outcome is in the counters -- the whole
// point of CFE_SB_IncrCmdCtr -- and in the event the error path raises by calling the
// background handler directly with CREATE_ERROR, which is NASA's own comment: it is the same
// thing, really.
I32 CFE_SB_WriteRoutingInfoCmd(CFE_SB_WriteRoutingInfoCmd_t *data)
{
  CFE_SB_WriteFileInfoCmd_Payload_t *CmdPtr;
  CFE_SB_BackgroundFileStateInfo_t *StatePtr;
  I32 Status;
  StatePtr = &CFE_SB_Global.BackgroundFile;
  CmdPtr = &data->Payload;
  /* If a routing info dump was already pending, do not overwrite the current request */
  if (!CFE_FS_BackgroundFileDumpIsPending(&StatePtr->FileWrite)) {
    /* Reset the entire state object (just for good measure, ensure no stale data) */
    MemSet(StatePtr, 0, sizeof(CFE_SB_BackgroundFileStateInfo_t));
    /*
     * Fill out the remainder of meta data.
     * This data is currently the same for every request
     */
    StatePtr->FileWrite.FileSubType = CFE_FS_SubType_SB_ROUTEDATA;
    StrPrintN(StatePtr->FileWrite.Description, CFE_FS_HDR_DESC_MAX_LEN, "SB Routing Information");
    StatePtr->FileWrite.GetData = &CFE_SB_WriteRouteInfoDataGetter;
    StatePtr->FileWrite.OnEvent = &CFE_SB_BackgroundFileEventHandler;
    /*
    ** Copy the filename into local buffer with default name/path/extension if not specified
    */
    Status = CFE_FS_ParseInputFileNameEx(StatePtr->FileWrite.FileName, CmdPtr->Filename, CFE_MISSION_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, CFE_PLATFORM_SB_DEFAULT_ROUTING_FILENAME, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_BINARY_DATA_DUMP), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_BINARY_DATA_DUMP));
    if (Status == CFE_SUCCESS) {
      Status = CFE_FS_BackgroundFileDumpRequest(&StatePtr->FileWrite);
    }
  } else {
    Status = CFE_STATUS_REQUEST_ALREADY_PENDING;
  }
  if (Status != CFE_SUCCESS) {
    /* generate the same event as is generated when unable to create the file (same thing,
     * really) */
    CFE_SB_BackgroundFileEventHandler(StatePtr, CFE_FS_FileWriteEvent_CREATE_ERROR, Status, 0, 0, 0);
  }
  CFE_SB_IncrCmdCtr(Status);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// ONE PIPE PER CALL, INDEXED BY RecordNum, and that is a different throttling scheme from the
// route writer above: the pipe table is a fixed array, so the record number IS the index and
// end-of-file is simply reaching the last slot. An unused slot writes NOTHING (*BufSize = 0)
// but is still a record, which is why the file can be shorter than the record count.
Bool CFE_SB_WritePipeInfoDataGetter(U8 *Meta, U32 RecordNum, U8 **Buffer, I64 *BufSize)
{
  CFE_SB_BackgroundFileStateInfo_t *BgFilePtr;
  CFE_SB_PipeInfoEntry_t *PipeBufferPtr;
  CFE_SB_PipeD_t *PipeDscPtr;
  U32 SysQueueId = OS_OBJECT_ID_UNDEFINED;
  Bool PipeIsValid;
  BgFilePtr = Meta;
  PipeDscPtr = NULL;
  PipeIsValid = FALSE;
  PipeBufferPtr = &BgFilePtr->Buffer.PipeInfo;
  if (RecordNum < CFE_PLATFORM_SB_MAX_PIPES) {
    PipeDscPtr = &CFE_SB_Global.PipeTbl[RecordNum];
    CFE_SB_LockSharedData("cfe_sb_task.c", 857);
    PipeIsValid = CFE_SB_PipeDescIsUsed(PipeDscPtr);
    if (PipeIsValid) {
      /*
       * Ensure any old data in the struct has been cleared
       */
      MemSet(PipeBufferPtr, 0, sizeof(CFE_SB_PipeInfoEntry_t));
      /*
       * Take a "snapshot" of the PipeDsc state while locked
       */
      PipeBufferPtr->PipeId = CFE_SB_PipeDescGetID(PipeDscPtr);
      PipeBufferPtr->AppId = PipeDscPtr->AppId;
      PipeBufferPtr->Opts = PipeDscPtr->Opts;
      /* copy stats info */
      PipeBufferPtr->SendErrors = PipeDscPtr->SendErrors;
      PipeBufferPtr->MaxQueueDepth = PipeDscPtr->MaxQueueDepth;
      PipeBufferPtr->CurrentQueueDepth = PipeDscPtr->CurrentQueueDepth;
      PipeBufferPtr->PeakQueueDepth = PipeDscPtr->PeakQueueDepth;
      SysQueueId = PipeDscPtr->SysQueueId;
    }
    CFE_SB_UnlockSharedData("cfe_sb_task.c", 884);
  }
  if (PipeIsValid) {
    /*
     * Gather data from other subsystems while unlocked.
     * This might fail if the pipe is deleted simultaneously while this runs, but in
     * the unlikely event that happens, the name data will simply be blank as the ID(s)
     * will not validate.
     */
    OS_GetResourceName(SysQueueId, PipeBufferPtr->PipeName, CFE_MISSION_MAX_API_LEN);
    CFE_ES_GetAppName(PipeBufferPtr->AppName, PipeBufferPtr->AppId, CFE_MISSION_MAX_API_LEN);
    *Buffer = PipeBufferPtr;
    *BufSize = sizeof(CFE_SB_PipeInfoEntry_t);
  } else {
    *Buffer = NULL;
    *BufSize = 0;
  }
  /* Check for EOF (last entry)  */
  return RecordNum >= CFE_PLATFORM_SB_MAX_PIPES - 1;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_WritePipeInfoCmd(CFE_SB_WritePipeInfoCmd_t *data)
{
  CFE_SB_WriteFileInfoCmd_Payload_t *CmdPtr;
  CFE_SB_BackgroundFileStateInfo_t *StatePtr;
  I32 Status;
  StatePtr = &CFE_SB_Global.BackgroundFile;
  CmdPtr = &data->Payload;
  /* If a pipe info dump was already pending, do not overwrite the current request */
  if (!CFE_FS_BackgroundFileDumpIsPending(&StatePtr->FileWrite)) {
    /* Reset the entire state object (just for good measure, ensure no stale data) */
    MemSet(StatePtr, 0, sizeof(CFE_SB_BackgroundFileStateInfo_t));
    /*
     * Fill out the remainder of meta data.
     * This data is currently the same for every request
     */
    StatePtr->FileWrite.FileSubType = CFE_FS_SubType_SB_PIPEDATA;
    StrPrintN(StatePtr->FileWrite.Description, CFE_FS_HDR_DESC_MAX_LEN, "SB Pipe Information");
    StatePtr->FileWrite.GetData = &CFE_SB_WritePipeInfoDataGetter;
    StatePtr->FileWrite.OnEvent = &CFE_SB_BackgroundFileEventHandler;
    /*
    ** Copy the filename into local buffer with default name/path/extension if not specified
    */
    Status = CFE_FS_ParseInputFileNameEx(StatePtr->FileWrite.FileName, CmdPtr->Filename, CFE_MISSION_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, CFE_PLATFORM_SB_DEFAULT_PIPE_FILENAME, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_BINARY_DATA_DUMP), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_BINARY_DATA_DUMP));
    if (Status == CFE_SUCCESS) {
      Status = CFE_FS_BackgroundFileDumpRequest(&StatePtr->FileWrite);
    }
  } else {
    Status = CFE_STATUS_REQUEST_ALREADY_PENDING;
  }
  if (Status != CFE_SUCCESS) {
    /* generate the same event as is generated when unable to create the file (same thing,
     * really) */
    CFE_SB_BackgroundFileEventHandler(StatePtr, CFE_FS_FileWriteEvent_CREATE_ERROR, Status, 0, 0, 0);
  }
  CFE_SB_IncrCmdCtr(Status);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_CollectMsgMapInfo(CFE_SBR_RouteId RouteId, U8 *ArgPtr)
{
  CFE_SB_MsgMapFileEntry_t *BufferPtr;
  /* Cast arguments for local use */
  BufferPtr = ArgPtr;
  /* Extract data from runtime info, write into the temporary buffer */
  /* Data must be locked to snapshot the route info */
  CFE_SB_LockSharedData("cfe_sb_task.c", 989);
  BufferPtr->MsgId = CFE_SBR_GetMsgId(RouteId);
  BufferPtr->Index = CFE_SBR_RouteIdToValue(RouteId);
  CFE_SB_UnlockSharedData("cfe_sb_task.c", 994);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE MsgId IS PRE-SET TO INVALID AND THAT IS THE NO-OP DETECTOR. CFE_SBR_ForEachRouteId may
// visit nothing at all -- a throttled range past the end of the table -- and the callback is
// then never called, so the buffer would hold the PREVIOUS record. Writing an invalid id first
// and testing it afterwards is how this tells "no route here" from "a route whose id is zero".
Bool CFE_SB_WriteMsgMapInfoDataGetter(U8 *Meta, U32 RecordNum, U8 **Buffer, I64 *BufSize)
{
  CFE_SB_BackgroundFileStateInfo_t *BgFilePtr;
  CFE_SBR_Throttle Throttle;
  /* Cast arguments for local use */
  BgFilePtr = Meta;
  Throttle.StartIndex = RecordNum;
  Throttle.MaxLoop = 1;
  Throttle.NextIndex = 0;
  /* Set the MsgId initially - will be overwritten with real info in CFE_SB_CollectMsgMapInfo */
  BgFilePtr->Buffer.MsgMapInfo.MsgId = CFE_SB_InvalidMsgId;
  /* Collect info on the next route (limited to one per cycle via throttle) */
  CFE_SBR_ForEachRouteId(&CFE_SB_CollectMsgMapInfo, &BgFilePtr->Buffer.MsgMapInfo, &Throttle);
  /* If Map was valid, pass the output of CFE_SB_CollectMsgMapInfo() back to be written */
  if (CFE_SB_IsValidMsgId(BgFilePtr->Buffer.MsgMapInfo.MsgId)) {
    *Buffer = &BgFilePtr->Buffer.MsgMapInfo;
    *BufSize = sizeof(CFE_SB_MsgMapFileEntry_t);
  } else {
    *Buffer = NULL;
    *BufSize = 0;
  }
  /* Check for EOF (last entry) - NextIndex is nonzero if more records left, zero at the end of
   * the route table */
  return Throttle.NextIndex == 0;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_WriteMapInfoCmd(CFE_SB_WriteMapInfoCmd_t *data)
{
  CFE_SB_WriteFileInfoCmd_Payload_t *CmdPtr;
  CFE_SB_BackgroundFileStateInfo_t *StatePtr;
  I32 Status;
  StatePtr = &CFE_SB_Global.BackgroundFile;
  CmdPtr = &data->Payload;
  /* If a pipe info dump was already pending, do not overwrite the current request */
  if (!CFE_FS_BackgroundFileDumpIsPending(&StatePtr->FileWrite)) {
    /* Reset the entire state object (just for good measure, ensure no stale data) */
    MemSet(StatePtr, 0, sizeof(CFE_SB_BackgroundFileStateInfo_t));
    /*
     * Fill out the remainder of meta data.
     * This data is currently the same for every request
     */
    StatePtr->FileWrite.FileSubType = CFE_FS_SubType_SB_MAPDATA;
    StrPrintN(StatePtr->FileWrite.Description, CFE_FS_HDR_DESC_MAX_LEN, "SB Map Information");
    StatePtr->FileWrite.GetData = &CFE_SB_WriteMsgMapInfoDataGetter;
    StatePtr->FileWrite.OnEvent = &CFE_SB_BackgroundFileEventHandler;
    /*
    ** Copy the filename into local buffer with default name/path/extension if not specified
    */
    Status = CFE_FS_ParseInputFileNameEx(StatePtr->FileWrite.FileName, CmdPtr->Filename, CFE_MISSION_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, CFE_PLATFORM_SB_DEFAULT_MAP_FILENAME, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_BINARY_DATA_DUMP), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_BINARY_DATA_DUMP));
    if (Status == CFE_SUCCESS) {
      Status = CFE_FS_BackgroundFileDumpRequest(&StatePtr->FileWrite);
    }
  } else {
    Status = CFE_STATUS_REQUEST_ALREADY_PENDING;
  }
  if (Status != CFE_SUCCESS) {
    /* generate the same event as is generated when unable to create the file (same thing,
     * really) */
    CFE_SB_BackgroundFileEventHandler(StatePtr, CFE_FS_FileWriteEvent_CREATE_ERROR, Status, 0, 0, 0);
  }
  CFE_SB_IncrCmdCtr(Status);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Callback for sending route subscriptions
 *
 *-----------------------------------------------------------------*/
// THIS CALLBACK UNLOCKS AND RE-LOCKS IN THE MIDDLE OF ITSELF. Its caller holds the shared-data
// lock; sending a packet goes through SB, which would take the lock again, so the full-packet
// branch drops it around the transmit and the event and takes it back. The callback is
// therefore NOT safe to call unlocked, and the `break` at the end of the global branch is
// NASA's own note: ONE network subscription per message id, whatever the destination count.
U0 CFE_SB_SendRouteSub(CFE_SBR_RouteId RouteId, U8 *ArgPtr)
{
  CFE_SB_DestinationD_t *destptr;
  I32 status;
  destptr = CFE_SBR_GetDestListHeadPtr(RouteId);
  /* Loop through destinations */
  while (destptr != NULL) {
    if (destptr->Scope == CFE_SB_MSG_GLOBAL) {
      /* ...add entry into pkt */
      CFE_SB_Global.PrevSubMsg.Payload.Entry[CFE_SB_Global.PrevSubMsg.Payload.Entries].MsgId = CFE_SBR_GetMsgId(RouteId);
      CFE_SB_Global.PrevSubMsg.Payload.Entry[CFE_SB_Global.PrevSubMsg.Payload.Entries].Qos.Priority = 0;
      CFE_SB_Global.PrevSubMsg.Payload.Entry[CFE_SB_Global.PrevSubMsg.Payload.Entries].Qos.Reliability = 0;
      CFE_SB_Global.PrevSubMsg.Payload.Entries++;
      /* send pkt if full */
      if (CFE_SB_Global.PrevSubMsg.Payload.Entries >= CFE_MISSION_SB_SUB_ENTRIES_PER_PKT) {
        CFE_SB_UnlockSharedData("CFE_SB_SendRouteSub", 1129);
        status = CFE_SB_TransmitMsg(&CFE_SB_Global.PrevSubMsg.TelemetryHeader.Msg, TRUE);
        CFE_EVS_SendEvent(CFE_SB_FULL_SUB_PKT_EID, CFE_EVS_EventType_DEBUG, "Full Sub Pkt %d Sent,Entries=%d,Stat=0x%x\n", CFE_SB_Global.PrevSubMsg.Payload.PktSegment, CFE_SB_Global.PrevSubMsg.Payload.Entries, status);
        CFE_SB_LockSharedData("CFE_SB_SendRouteSub", 1137);
        CFE_SB_Global.PrevSubMsg.Payload.Entries = 0;
        CFE_SB_Global.PrevSubMsg.Payload.PktSegment++;
      }
      /*
       * break while loop through destinations, onto next route
       * This is done because we want only one network subscription per msgid
       * Later when Qos is used, we may want to take just the highest priority
       * subscription if there are more than one
       */
      break;
    }
    /* Advance to next destination */
    destptr = destptr->Next;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_SendPrevSubsCmd(CFE_SB_SendPrevSubsCmd_t *data)
{
  I32 status;
  /* Take semaphore to ensure data does not change during this function */
  CFE_SB_LockSharedData("CFE_SB_SendPrevSubsCmd", 1167);
  /* Initialize entry/segment tracking */
  CFE_SB_Global.PrevSubMsg.Payload.PktSegment = 1;
  CFE_SB_Global.PrevSubMsg.Payload.Entries = 0;
  /* Send subscription for each route */
  CFE_SBR_ForEachRouteId(&CFE_SB_SendRouteSub, NULL, NULL);
  CFE_SB_UnlockSharedData("CFE_SB_SendPrevSubsCmd", 1176);
  /* if pkt has any number of entries, send it as a partial pkt */
  if (CFE_SB_Global.PrevSubMsg.Payload.Entries > 0) {
    status = CFE_SB_TransmitMsg(&CFE_SB_Global.PrevSubMsg.TelemetryHeader.Msg, TRUE);
    CFE_EVS_SendEvent(CFE_SB_PART_SUB_PKT_EID, CFE_EVS_EventType_DEBUG, "Partial Sub Pkt %d Sent,Entries=%d,Stat=0x%x", CFE_SB_Global.PrevSubMsg.Payload.PktSegment, CFE_SB_Global.PrevSubMsg.Payload.Entries, status);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_IncrCmdCtr(I32 status)
{
  if (status == CFE_SUCCESS) {
    CFE_SB_Global.HKTlmMsg.Payload.CommandCounter++;
  } else {
    CFE_SB_Global.HKTlmMsg.Payload.CommandErrorCounter++;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_SetSubscriptionReporting(U32 state)
{
  CFE_SB_Global.SubscriptionReporting = state;
}
#endif
