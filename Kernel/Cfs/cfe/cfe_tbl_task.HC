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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_task.c -- THREE FUNCTIONS, AND THE
// LAST OBJECT-TABLE STUB GOES WITH THEM. cfe_tbl_objtab.c has held &CFE_TBL_TaskMain since it
// was gated; CFE_TBL_EarlyInit became real two commits ago and this makes the second of the
// three hooks real too.
//
// THE MAIN LOOP IS AN INFINITE LOOP THAT EXITS ONLY ON ERROR. `while (Status == CFE_SUCCESS)`
// and the only assignment inside it is CFE_SB_ReceiveBuffer's -- so the task runs until the
// software bus fails, and then falls out of the loop into CFE_ES_ExitApp. That is also what
// makes it exercisable in a transcript: give ReceiveBuffer a pipe that is not there and the
// loop runs exactly once.
//
// FIVE "LAST ID" FIELDS SET TO THEIR BASE, which is the detail worth knowing about
// CFE_TBL_InitData. Every one of tbl's five resource-id spaces allocates by searching FORWARD
// from a Last* field, so a Last* of zero finds nothing -- the id machinery needs a real
// starting point, not an absent one. (A transcript block learned this the hard way: see the
// note at tbl_alloc in the driver.)
//
// CFE_TBL_Global ITSELF IS NOT DEFINED HERE even though NASA defines it in this file. It lives
// in cfe_tbl_global.HC beside its type, for the reason cfe_es_global.HC records at its own
// instance.
#ifndef CFE_TBL_TASK_HC
#define CFE_TBL_TASK_HC
// cfe_perfids.h
#ifndef CFE_MISSION_TBL_MAIN_PERF_ID
#define CFE_MISSION_TBL_MAIN_PERF_ID 3
#endif
// cfe_tbl_msgids.h: measured through a probe, not read off the macro -- each is
// CFE_PLATFORM_TBL_{CMD,TLM}_MIDVAL(X), two layers of CMake-driven macro over a base and an
// offset. check_constants.py compares every one against NASA's own expansion.
#ifndef CFE_TBL_CMD_MID
#define CFE_TBL_CMD_MID     0x1804
#endif
#ifndef CFE_TBL_SEND_HK_MID
#define CFE_TBL_SEND_HK_MID 0x180C
#endif
#ifndef CFE_TBL_HK_TLM_MID
#define CFE_TBL_HK_TLM_MID  0x804
#endif
#ifndef CFE_TBL_REG_TLM_MID
#define CFE_TBL_REG_TLM_MID 0x80C
#endif
#ifndef CFE_TBL_INIT_INF_EID
#define CFE_TBL_INIT_INF_EID 1
#endif
// CFE_SB_INVALID_MSG_ID is CFE_SB_MSGID_C(0), a compound literal the translation renders as
// CFE_SB_InvalidMsgId() -- see the note in cfe_sb_msgid.HC.
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TBL_TaskMain()
{
  I32 Status;
  CFE_SB_Buffer *SBBufPtr;
  CFE_ES_PerfLogEntry(CFE_MISSION_TBL_MAIN_PERF_ID);
  Status = CFE_TBL_TaskInit();
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Application Init Failed,RC=0x%08X\n", "CFE_TBL_TaskMain", Status);
    CFE_ES_PerfLogExit(CFE_MISSION_TBL_MAIN_PERF_ID);
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
    CFE_ES_PerfLogExit(CFE_MISSION_TBL_MAIN_PERF_ID);
    /* Pend on receipt of packet */
    Status = CFE_SB_ReceiveBuffer(&SBBufPtr, CFE_TBL_Global.CmdPipe, CFE_SB_PEND_FOREVER);
    CFE_ES_PerfLogEntry(CFE_MISSION_TBL_MAIN_PERF_ID);
    if (Status == CFE_SUCCESS) {
      /* Process cmd pipe msg */
      CFE_TBL_TaskPipe(SBBufPtr);
    } else {
      CFE_ES_WriteToSysLog("%s: Error reading cmd pipe,RC=0x%08X\n", "CFE_TBL_TaskMain", Status);
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
I32 CFE_TBL_TaskInit()
{
  I32 Status;
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];
  // FIVE SEQUENTIAL `return Status` ON FAILURE, not one error path -- so the transcript can say
  // exactly how far initialisation got by which syslog line arrives, and a caller that sees a
  // non-zero status knows nothing about which resources were already created. That is the
  // design, and CFE_TBL_TaskMain's response to any of them is the same: log and exit the app.
  /*
  ** Initialize global Table Services data
  */
  CFE_TBL_InitData();
  /*
  ** Register event filter table
  */
  Status = CFE_EVS_Register(NULL, 0, 0);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Call to CFE_EVS_Register Failed:RC=0x%08X\n", "CFE_TBL_TaskInit", Status);
    return Status;
  }
  /*
  ** Create Software Bus message pipe
  */
  Status = CFE_SB_CreatePipe(&CFE_TBL_Global.CmdPipe, CFE_TBL_TASK_PIPE_DEPTH, CFE_TBL_TASK_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error creating cmd pipe:RC=0x%08X\n", "CFE_TBL_TaskInit", Status);
    return Status;
  }
  /*
  ** Subscribe to Housekeeping request commands
  */
  Status = CFE_SB_Subscribe(CFE_TBL_SEND_HK_MID, CFE_TBL_Global.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error subscribing to HK Request:RC=0x%08X\n", "CFE_TBL_TaskInit", Status);
    return Status;
  }
  /*
  ** Subscribe to Table task ground command packets
  */
  Status = CFE_SB_Subscribe(CFE_TBL_CMD_MID, CFE_TBL_Global.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error subscribing to gnd cmds:RC=0x%08X\n", "CFE_TBL_TaskInit", Status);
    return Status;
  }
  /*
  ** Task startup event message
  */
  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "CFE_TBL", CFE_SRC_VERSION, CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);
  Status = CFE_EVS_SendEvent(CFE_TBL_INIT_INF_EID, CFE_EVS_EventType_INFORMATION, "cFE TBL Initialized: %s", VersionString);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Error sending init event:RC=0x%08X\n", "CFE_TBL_TaskInit", Status);
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
U0 CFE_TBL_InitData()
{
  /* Get the assigned Application ID for the Table Services Task */
  CFE_ES_GetAppID(&CFE_TBL_Global.TableTaskAppId);
  // CFE_MSG_PTR(x) is `&x.Msg` -- a macro over the telemetry/command header, written out here
  // for the same reason cfe_es_task.HC writes it out: HolyC has the member, not the macro.
  /* Initialize Packet Headers */
  CFE_MSG_Init(&CFE_TBL_Global.HkPacket.TelemetryHeader.Msg, CFE_TBL_HK_TLM_MID, sizeof(CFE_TBL_HousekeepingTlm_t));
  CFE_MSG_Init(&CFE_TBL_Global.TblRegPacket.TelemetryHeader.Msg, CFE_TBL_REG_TLM_MID, sizeof(CFE_TBL_TableRegistryTlm_t));
  /* Message ID is set when sent, so OK as 0 here */
  CFE_MSG_Init(&CFE_TBL_Global.NotifyMsg.CommandHeader.Msg, CFE_SB_InvalidMsgId, sizeof(CFE_TBL_NotifyCmd_t));
  // EVERY ONE OF THE FIVE ID SPACES STARTS AT ITS BASE, and this is the line the rest of tbl
  // depends on: CFE_TBL_GetNextRegId and its four siblings search FORWARD from these, so a
  // zero here means the search begins at the undefined id and finds nothing at all.
  CFE_TBL_Global.LastLoadBuffId = CFE_ResourceId_FromInteger(CFE_TBL_LOADBUFFID_BASE);
  CFE_TBL_Global.LastValidationResultId = CFE_ResourceId_FromInteger(CFE_TBL_VALRESULTID_BASE);
  CFE_TBL_Global.LastDumpCtrlBlockId = CFE_ResourceId_FromInteger(CFE_TBL_DUMPCTRLID_BASE);
  CFE_TBL_Global.LastRegId = CFE_ResourceId_FromInteger(CFE_TBL_REGID_BASE);
  CFE_TBL_Global.LastHandle = CFE_ResourceId_FromInteger(CFE_TBL_HANDLE_BASE);
}
#endif
