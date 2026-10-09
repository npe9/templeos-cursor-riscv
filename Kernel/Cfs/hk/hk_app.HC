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
// HOUSEKEEPING'S ENTRY POINT AND STARTUP -- the 1:1 translation of NASA's fsw/src/hk_app.c, 358
// lines and four functions. The last of HK's four sources.
//
// ### HK_AppInit IS A STRAIGHT LINE OF EARLY RETURNS, NOT A CHAIN OF `if (Status == SUCCESS)`
//
// Every other app in this port threads a status through `if (Status == CFE_SUCCESS)` guards --
// MD, MM, CS and LC all do. HK instead returns immediately on each failure:
//
//     Status = CFE_EVS_Register(...);  if (Status != CFE_SUCCESS) { ...; return Status; }
//     Status = CFE_SB_CreatePipe(...); if (Status != CFE_SUCCESS) { ...; return Status; }
//     ... four subscriptions, a pool, HK_ResetHkData, HK_TableInit ...
//
// Nine steps, eight of them with their own event id and an early return. The observable
// difference is the same -- a failure stops initialisation -- but it makes HK the one app whose
// init is readable top to bottom, and it means **the failing step's event is always the LAST
// event before the app gives up**, with nothing after it. The exercise leans on that.
//
// AND THE EVENT SERVICES FAILURE HAS NO EVENT, which is the one step that cannot: a failed
// CFE_EVS_Register leaves nothing able to send one, so HK writes to the system log instead. The
// same reasoning HK_AppMain uses when it logs alongside its termination event "in case there is a
// problem with event services".
//
// ### THE HOUSEKEEPING PACKET IS INITIALISED **BEFORE** EVENT SERVICES IS REGISTERED
//
// CFE_MSG_Init on HK's own telemetry header is the first statement of HK_AppInit, ahead of
// CFE_EVS_Register. That ordering is deliberate and slightly odd: it means HK's packet header is
// valid even on a run where nothing else worked. No other app in this port initialises a message
// before registering for events.
//
// ### HK_TableInit IS NINE cFE CALLS WITH NINE EVENT IDS, AND ONE OF THEM EXPECTS A NON-SUCCESS
//
// Register copy table, register runtime table, load, manage, manage, get address, get address,
// process. The seventh is the interesting one:
//
//     Status = CFE_TBL_GetAddress(...CopyTableHandle);
//     if (Status != CFE_TBL_INFO_UPDATED) { ...error...; return Status; }
//
// -- it treats CFE_SUCCESS as a FAILURE. NASA's comment says why: "Status should be
// CFE_TBL_INFO_UPDATED because we loaded it above". So a copy table that came back without the
// updated indicator means the load did not take, and HK refuses to start. The runtime table's
// GetAddress two lines later tests for CFE_SUCCESS in the normal way, so the two adjacent calls
// have opposite success conditions -- which is exactly the shape
// docs/ records as a status constant that is dead code if its comparison is wrong.
//
// ### AND THE COPY TABLE IS DOUBLE-BUFFERED WHILE THE RUNTIME TABLE IS DUMP-ONLY
//
//     CopyTable     CFE_TBL_OPT_DBL_BUFFER | CFE_TBL_OPT_LOAD_DUMP   validated by HK
//     RuntimeTable  CFE_TBL_OPT_SNGL_BUFFER | CFE_TBL_OPT_DUMP_ONLY  no validation callback
//
// Double-buffered because a copy table load must not tear while HK is walking it, and HK is the
// only app in this port that asks for DBL_BUFFER. The runtime table needs no validator because
// the ground cannot load it -- it is HK's own bookkeeping, dumped outward only.
#ifndef HK_APP_HC
#define HK_APP_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// hk_global.HC, hk_eventids.HC, hk_utils.HC, hk_cmds.HC, hk_dispatch.HC
//
// **THIS UNIT DOES NOT INCLUDE ITS SIBLINGS**, and that is not style -- it is
// docs/HOLYC_STRUCT_LIMITS.md #13. Re-including a guarded file the driver has already read makes
// the compiler skip EVERYTHING AFTER THAT LINE in the including file, with no diagnostic and exit
// status 0. A first draft of this file did include them and check_in_blob caught the result: all
// four functions defined here, every static gate passing, and not one of them in the binary.
//
// The trigger is a `#if` appearing in a COMMENT inside the skipped region, and HK has two of them
// -- hk_cfg.HC and hk_utils.HC both quote NASA's HK_DISCARD_INCOMPLETE_COMBO directive, which is
// the one place in this port where that directive matters enough to write out. So HK is unusually
// exposed to #13 and the workaround is applied here rather than relied on by luck.

// --- hk_app.h's prototypes -------------------------------------------------------------------
U0 HK_AppMain();
I32 HK_AppInit();
I32 HK_TableInit();
U0 HK_ResetHkData();

/*******************************************************************************/
// HK application entry point and main process loop.
//
// THE PERFORMANCE LOG IS **NOT** BALANCED THE WAY LC'S IS. LC brackets every loop iteration with
// an exit at the top and an entry after the receive. HK puts its PerfLogExit at the top of the
// loop and its PerfLogEntry inside the `Status == CFE_SUCCESS` arm ONLY -- so a cycle that times
// out or errors records an exit with no matching entry. NASA's, kept verbatim: the performance
// log is a stream of timestamped markers rather than a stack, so an unmatched exit is a
// measurement artefact rather than a fault, but it does mean HK's reported main-loop time
// excludes every timeout cycle.
//
// AND A RECEIVE ERROR TERMINATES THE APP, which is not what LC does. LC folds CFE_SB_NO_MESSAGE
// to success and keeps running; HK has no such arm -- anything that is neither CFE_SUCCESS nor
// CFE_SB_TIME_OUT sends HK_RCV_MSG_ERR_EID, writes the syslog, and sets APP_ERROR. The event text
// names CFE_SB_RcvMsg, a function that no longer exists under that name in Draco; it is
// CFE_SB_ReceiveBuffer now, and the string is upstream's.
U0 HK_AppMain()
{
  I32 Status = CFE_SUCCESS;
  CFE_SB_Buffer *BufPtr = NULL;

  /*
  ** Create the first Performance Log entry
  */
  CFE_ES_PerfLogEntry(HK_APPMAIN_PERF_ID);

  /* Perform Application Initialization */
  Status = HK_AppInit();
  if (Status != CFE_SUCCESS) {
    HK_AppData.RunStatus = CFE_ES_RunStatus_APP_ERROR;
  }

  /*
  ** Application Main Loop.
  */
  while (CFE_ES_RunLoop(&HK_AppData.RunStatus) == TRUE) {
    /*
    ** Performance Log Exit Stamp.
    */
    CFE_ES_PerfLogExit(HK_APPMAIN_PERF_ID);

    /*
    ** Pend on the arrival of the next Software Bus message.
    */
    Status = CFE_SB_ReceiveBuffer(&BufPtr, HK_AppData.CmdPipe, HK_SB_TIMEOUT);

    if (Status == CFE_SUCCESS) {
      /*
      ** Performance Log Entry Stamp.
      */
      CFE_ES_PerfLogEntry(HK_APPMAIN_PERF_ID);

      /* Perform Message Processing */
      HK_AppPipe(BufPtr);
    } else if (Status == CFE_SB_TIME_OUT) {
      /* Check for copy table load and runtime dump request. This is
       * generally done during the housekeeping cycle.  If we are
       * getting routine messages at a rate of less than 1Hz we do
       * the routine maintenance here. */
      if (HK_CheckStatusOfTables() != HK_SUCCESS) {
        HK_AppData.RunStatus = CFE_ES_RunStatus_APP_ERROR;
      }
    } else {
      CFE_EVS_SendEvent(HK_RCV_MSG_ERR_EID, CFE_EVS_EventType_ERROR,
                        "HK_APP Exiting due to CFE_SB_RcvMsg error 0x%08X", Status);

      /* Write to syslog in case there is a problem with event services */
      CFE_ES_WriteToSysLog("HK_APP Exiting due to CFE_SB_RcvMsg error 0x%08X\n", Status);

      HK_AppData.RunStatus = CFE_ES_RunStatus_APP_ERROR;
    }
  } /* end while */

  /*
   ** Performance Log Exit Stamp.
   */
  CFE_ES_PerfLogExit(HK_APPMAIN_PERF_ID);

  /*
  ** Exit the Application.
  */
  CFE_ES_ExitApp(HK_AppData.RunStatus);
}

/*******************************************************************************/
// HK application initialization routine. Nine steps, eight early returns -- see the file header.
//
// IT DOES **NOT** ZERO HK_AppData. MD, MM, CS and LC all memset their global first; HK sets
// RunStatus and then relies on the file-scope object already being zero. That is correct in
// NASA's build and it is the one thing an exercise running HK_AppInit twice in one process has to
// arrange for itself.
I32 HK_AppInit()
{
  I32 Status = CFE_SUCCESS;

  HK_AppData.RunStatus = CFE_ES_RunStatus_APP_RUN;

  /* Initialize housekeeping packet  */
  // CFE_MSG_PTR(x) is NASA's &x.Msg, written out as it is elsewhere in this port.
  CFE_MSG_Init(&HK_AppData.HkPacket.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(HK_HK_TLM_MID),
               sizeof(HK_HkPacket_t));

  /* Register for event services...        */
  Status = CFE_EVS_Register(NULL, 0, CFE_EVS_EventFilter_BINARY);
  if (Status != CFE_SUCCESS) {
    // NO EVENT HERE, and there cannot be one: event services is what just failed.
    CFE_ES_WriteToSysLog("HK: error registering for event services: 0x%08X\n", Status);
    return Status;
  }

  /* Create HK Command Pipe */
  Status = CFE_SB_CreatePipe(&HK_AppData.CmdPipe, HK_PIPE_DEPTH, HK_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_CR_PIPE_ERR_EID, CFE_EVS_EventType_ERROR, "Error Creating SB Pipe,RC=0x%08X",
                      Status);
    return Status;
  }

  /* Subscribe to 'Send Combined HK Pkt' Command */
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(HK_SEND_COMBINED_PKT_MID), HK_AppData.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_SUB_CMB_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Subscribing to HK Snd Cmb Pkt, MID=0x%08X, RC=0x%08X",
                      HK_SEND_COMBINED_PKT_MID, Status);
    return Status;
  }

  /* Subscribe to Housekeeping Request */
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(HK_SEND_HK_MID), HK_AppData.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_SUB_REQ_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Subscribing to HK Request, MID=0x%08X, RC=0x%08X", HK_SEND_HK_MID,
                      Status);
    return Status;
  }

  /* Subscribe to HK ground commands */
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(HK_CMD_MID), HK_AppData.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_SUB_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Subscribing to HK Gnd Cmds, MID=0x%08X, RC=0x%08X", HK_CMD_MID,
                      Status);
    return Status;
  }

  /* Create a memory pool for combined output messages */
  Status = CFE_ES_PoolCreate(&HK_AppData.MemPoolHandle, HK_AppData.MemPoolBuffer,
                             HK_NUM_BYTES_IN_MEM_POOL);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_CR_POOL_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Creating Memory Pool,RC=0x%08X", Status);
    return Status;
  }

  HK_ResetHkData();

  /* Register The HK Tables */
  Status = HK_TableInit();
  if (Status != CFE_SUCCESS) {
    /* Specific failure is detailed in function HK_TableInit */
    return Status;
  }

  /* Application initialization event */
  Status = CFE_EVS_SendEvent(HK_INIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                             "HK Initialized.  Version %d.%d.%d.%d", HK_MAJOR_VERSION,
                             HK_MINOR_VERSION, HK_REVISION, HK_MISSION_REV);

  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("HK App:Error Sending Initialization Event,RC=0x%08X\n", Status);
  }

  return Status;
}

/*******************************************************************************/
// HK application table initialization routine.
//
// THE COPY TABLE'S GetAddress EXPECTS CFE_TBL_INFO_UPDATED AND NOT CFE_SUCCESS -- see the file
// header. Two adjacent GetAddress calls with opposite success conditions.
//
// AND NOTE WHAT THIS FUNCTION RETURNS ON THAT PATH: `return Status`, which is CFE_SUCCESS. So
// HK_AppInit's `if (Status != CFE_SUCCESS)` does NOT fire, initialisation continues, and HK runs
// with a CopyTablePtr that was never passed to HK_ProcessNewCopyTable -- no output buffers, no
// subscriptions. **That is an upstream defect and it is kept verbatim**: the event is sent and the
// app carries on believing it is configured. It is reachable only when cFE returns CFE_SUCCESS
// from a GetAddress that followed a successful Load, which the differential can drive directly.
I32 HK_TableInit()
{
  I32 Status = CFE_SUCCESS;

  /* Register The HK Copy Table */
  Status = CFE_TBL_Register(&HK_AppData.CopyTableHandle, HK_COPY_TABLE_NAME,
                            sizeof(HK_CopyTableEntry_t) * HK_COPY_TABLE_ENTRIES,
                            CFE_TBL_OPT_DBL_BUFFER | CFE_TBL_OPT_LOAD_DUMP, &HK_ValidateHkCopyTable);

  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_CPTBL_REG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Registering Copy Table,RC=0x%08X", Status);
    return Status;
  }

  /* Register The HK Runtime Table */
  Status = CFE_TBL_Register(&HK_AppData.RuntimeTableHandle, HK_RUNTIME_TABLE_NAME,
                            sizeof(HK_RuntimeTableEntry_t) * HK_COPY_TABLE_ENTRIES,
                            CFE_TBL_OPT_SNGL_BUFFER | CFE_TBL_OPT_DUMP_ONLY, NULL);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_RTTBL_REG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Registering Runtime Table,RC=0x%08X", Status);
    return Status;
  }

  Status = CFE_TBL_Load(HK_AppData.CopyTableHandle, CFE_TBL_SRC_FILE, HK_COPY_TABLE_FILENAME);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_CPTBL_LD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Loading Copy Table,RC=0x%08X", Status);
    return Status;
  }

  Status = CFE_TBL_Manage(HK_AppData.CopyTableHandle);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_CPTBL_MNG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error from TBL Manage call for Copy Table,RC=0x%08X", Status);
    return Status;
  }

  Status = CFE_TBL_Manage(HK_AppData.RuntimeTableHandle);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_RTTBL_MNG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error from TBL Manage call for Runtime Table,RC=0x%08X", Status);
    return Status;
  }

  Status = CFE_TBL_GetAddress(&HK_AppData.CopyTablePtr, HK_AppData.CopyTableHandle);
  /* Status should be CFE_TBL_INFO_UPDATED because we loaded it above */
  if (Status != CFE_TBL_INFO_UPDATED) {
    CFE_EVS_SendEvent(HK_CPTBL_GADR_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Getting Adr for Cpy Tbl,RC=0x%08X", Status);
    return Status;
  }

  Status = CFE_TBL_GetAddress(&HK_AppData.RuntimeTablePtr, HK_AppData.RuntimeTableHandle);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HK_RTTBL_GADR_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Getting Adr for Runtime Table,RC=0x%08X", Status);
    return Status;
  }

  Status = HK_ProcessNewCopyTable(HK_AppData.CopyTablePtr, HK_AppData.RuntimeTablePtr);

  if (Status != CFE_SUCCESS) {
    /* If status was not success, then the copy table function received a NULL pointer argument */
    CFE_EVS_SendEvent(HK_NEWCPYTBL_INIT_FAILED_EID, CFE_EVS_EventType_ERROR,
                      "Process New Copy Table Failed, status = 0x%08X", Status);

    return Status;
  }

  return CFE_SUCCESS;
} /* HK_TableInit */

/*******************************************************************************/
// Reset housekeeping data: the four counters, and nothing else.
//
// IT DOES NOT TOUCH THE TABLES, THE POOL OR THE SUBSCRIPTIONS. Called from HK_AppInit (before
// HK_TableInit) and from HK_ResetCountersCmd, and in both cases the four counters are the whole
// job -- so a ground reset-counters command does not disturb a single output packet or
// subscription.
U0 HK_ResetHkData()
{
  HK_AppData.CommandCounter = 0;
  HK_AppData.CommandErrorCounter = 0;
  HK_AppData.CombinedPacketsSent = 0;
  HK_AppData.MissingDataCtr = 0;
}

#endif
