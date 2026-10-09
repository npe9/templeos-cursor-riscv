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
// HEALTH & SAFETY'S ENTRY POINT AND INITIALISATION -- the 1:1 translation of NASA's
// fsw/src/hs_app.c, 725 lines and six functions: the task entry, the three initialisers and the
// two levels of the processing loop. HS'S LAST SOURCE.
//
// ### THE WATCHDOG IS SERVICED TWICE BEFORE THE MAIN LOOP STARTS, AND BOTH ARE NECESSARY
//
//     CFE_PSP_WatchdogSet(HS_WATCHDOG_TIMEOUT_VALUE);
//     CFE_PSP_WatchdogService();          <-- (1)
//     CFE_PSP_WatchdogEnable();
//     CFE_PSP_WatchdogService();          <-- (2)
//
// (1) loads the new timeout into a watchdog that is **not yet enabled**, so the counter starts
// from the full HS_WATCHDOG_TIMEOUT_VALUE rather than from whatever the boot loader left. (2)
// restarts it immediately after enabling, because the enable itself takes time and the window
// between Set and Enable is unbounded -- HS has just come out of CFE_ES_WaitForStartupSync, which
// waits for every other application in the system to report in. Dropping either one is a reset
// in the first second of flight, and it is not visible in a test that does not measure the
// INTERVAL between services. The simulated watchdog in the differential counts calls for exactly
// that reason.
//
// AND NOTE WHERE THE SYNC IS: AFTER HS_AppInit and BEFORE the event subscription. So HS has its
// pipes, its tables and its CDS before anything else starts, and it only begins reading the
// system's event stream once everything is up -- which is what keeps the event pipe from
// overflowing with startup events HS's tables were not yet loaded to interpret.
//
// ### `#if HS_POST_PROCESSING_DELAY != 0` IS RESOLVED BY HAND, AND IT IS FALSE
//
// NASA writes
//
//     #if HS_POST_PROCESSING_DELAY != 0
//         OS_TaskDelay(HS_POST_PROCESSING_DELAY);
//     #endif
//
// DEFAULT_HS_POST_PROCESSING_DELAY is **0** in the shipped configuration, so the call is not
// compiled and the translation omits it. It is omitted rather than guarded because
// docs/HOLYC_STRUCT_LIMITS.md #19 measures that HolyC's `#if <expr>` is unconditionally TRUE
// unless the text is a literal 0 -- so writing the directive out would EXECUTE the delay, which
// is the opposite of what NASA's configuration says. A mission that set a non-zero delay has one
// line to add here, named at the site.
//
// ### THE CDS IS VALIDATED, AND THE THREE FAILURE PATHS ALL END IN THE SAME CALL
//
// CFE_ES_RegisterCDS has three outcomes and HS_AppInit handles all three:
//
//   CFE_ES_CDS_ALREADY_EXISTS  restore it, and check each count against its own complement;
//                              on corruption or a failed restore, HS_SetCDSData(0, MAX)
//   CFE_SUCCESS                a fresh area -- HS_SetCDSData(0, MAX)
//   anything else              CDSState = DISABLED, then HS_SetCDSData(0, MAX) ANYWAY
//
// So **the reset counters are initialised on every path**, and the last case is the one worth
// naming: NASA's comment says "Initialize values anyway (they will not be saved)", and that is
// why HS_SetCDSData tests CDSState before copying. The in-memory counts are always valid even
// when nothing persists them, which means HS still enforces its reset limit WITHIN one boot on a
// board whose CDS is broken. It just forgets across boots -- and forgetting the count upward is
// the safe direction only because MaxResets is forgotten with it.
//
// AND `Status = CFE_SUCCESS` AT THE END OF THE ALREADY_EXISTS ARM is load-bearing: the arm
// overwrote Status with CFE_ES_RestoreFromCDS's result, and without that line a successful
// restore of a corrupt CDS would return a cFE status from HS_AppInit and the application would
// terminate. The other two arms never touch Status.
//
// ### HS_TblInit REGISTERS FOUR TABLES AND LOADS FOUR, AND THE ORDER IS NOT THE SAME
//
// Registration order: AMT, EMT, MAT, XCT -- each failure returning immediately, so a failure to
// register the Applications Monitor Table means the other three are never registered and HS
// exits.
//
// Load order: **XCT, AMT, EMT, MAT** -- and NONE of the four returns on failure. The execution
// counter table is loaded FIRST and the monitors after it, which is the opposite of the
// registration order and of their importance. The reason is visible in the XCT arm: it is the
// only one that writes into the housekeeping packet, filling all 32 ExeCounts with
// HS_INVALID_EXECOUNT, and NASA's comment cites a requirement by number -- "HS 8005.1 Report
// 0xFFFFFFFF for all entries". Doing that first means a later load failure cannot leave the
// packet half initialised.
//
// **A FAILED LOAD IS NOT A FAILED INIT.** HS_TblInit returns CFE_SUCCESS unconditionally at the
// end. All four load failures disable their feature, say so, and let HS run -- because an HS that
// exits because one table file is missing monitors nothing at all, and a watchdog nobody pets is
// a reboot. That is the single most important design decision in this file and it is expressed
// as the absence of four `return` statements.
//
// AND THE TWO MONITOR TABLES SEND **TWO** EVENTS ON A FAILED LOAD where the other two send one:
// the load error, then a separate HS_DISABLE_APPMON_ERR_EID / HS_DISABLE_EVENTMON_ERR_EID saying
// the feature is off. The MAT and XCT arms set their state and stay quiet about it. So of the four
// tables, exactly the two whose absence stops HS from taking ACTION announce it twice.
//
// ### THE UTILISATION COUNTER IS TESTED AT ZERO, RELOADED, AND THEN DECREMENTED ANYWAY
//
//     if (HS_AppData.UtilizationCycleCounter == 0) { HS_MonitorUtilization(); reload; }
//     --HS_AppData.UtilizationCycleCounter;
//
// The decrement is OUTSIDE the `if`, so the cycle the sample is taken on also consumes one count.
// With HS_CPU_UTILIZATION_CYCLES_PER_INTERVAL reloaded and then immediately decremented, the
// interval is actually that many cycles -- the reload value is a count of cycles INCLUDING the
// sampling one, not in addition to it. An implementation that moved the decrement inside the
// `else` would sample one cycle later every interval and the drift would be invisible in any test
// shorter than the interval.
//
// ### HS_ProcessCommands DRAINS THE EVENT PIPE FIRST, AND NASA SAYS WHY
//
// "done first so EventMon does not get enabled without table checking" -- the event monitor reads
// HS_AppData.EMTablePtr, and HS_ProcessMain called HS_AcquirePointers at the top of the cycle, so
// draining events before processing commands means the table pointer the monitor uses is the one
// this cycle validated. A command that re-enabled the event monitor would otherwise be followed
// by a drain in the same cycle against a pointer acquired before the enable.
//
// **BOTH DRAIN LOOPS TURN CFE_SB_NO_MESSAGE INTO CFE_SUCCESS AFTERWARDS**, which is how a poll
// that found nothing is distinguished from a real failure -- and the second loop's condition is
// `while (Status == CFE_SUCCESS)`, so that conversion is also what lets the command loop run at
// all after an empty event pipe. Remove the first conversion and HS never processes a command on
// any cycle where no event arrived. The two conversions look like duplicated boilerplate and one
// of them is a dependency.
//
// AND THE EVENT COUNTER MOVES BEFORE THE MONITOR RUNS: `EventsMonitoredCount++` then
// HS_MonitorEvent. So the count is "events dequeued", not "events acted on", which is the right
// meaning for a telemetry point whose purpose is to show the event stream is flowing.
#ifndef HS_APP_HC
#define HS_APP_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// hs_cfg.HC, hs_msg.HC, hs_tbl.HC, hs_global.HC, hs_eventids.HC, hs_utils.HC, hs_sysmon.HC,
// hs_monitors.HC, hs_cmds.HC, hs_dispatch.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13.
//
// NOTE WHAT IS **NOT** HERE: `HS_AppData_t HS_AppData;`. NASA defines the global in this file and
// declares it `extern` in hs_app.h; the translation defines it in hs_global.HC beside its type,
// for the reason every app in this port shares -- a HolyC `extern` outside the module loader's
// window is a module-local dummy, so a global gets exactly one definition. tools/cfs/
// check_oracle_globals.py enforces that the C oracle does not also define it.

// --- hs_app.h's prototypes --------------------------------------------------------------------
U0 HS_AppMain();
I32 HS_AppInit();
I32 HS_SbInit();
I32 HS_TblInit();
I32 HS_ProcessMain();
I32 HS_ProcessCommands();

/*******************************************************************************/
// The task entry point and the outer loop.
U0 HS_AppMain()
{
  I32 Status;
  U32 RunStatus = CFE_ES_RunStatus_APP_RUN;
  CFE_SB_Buffer *BufPtr = NULL;

  /*
  ** Performance Log, Start
  */
  CFE_ES_PerfLogEntry(HS_APPMAIN_PERF_ID);

  /*
  ** Perform application specific initialization
  */
  Status = HS_AppInit();

  /*
  ** If no errors were detected during initialization, then wait for everyone to start
  */
  if (Status == CFE_SUCCESS) {
    CFE_ES_WaitForStartupSync(HS_STARTUP_SYNC_TIMEOUT);

    /*
    ** Enable and set the watchdog timer
    */
    // TWO SERVICES, AND BOTH ARE NECESSARY -- see the file header.
    CFE_PSP_WatchdogSet(HS_WATCHDOG_TIMEOUT_VALUE);
    CFE_PSP_WatchdogService();
    CFE_PSP_WatchdogEnable();
    CFE_PSP_WatchdogService();

    /*
    ** Subscribe to Event Messages
    */
    if (HS_AppData.CurrentEventMonState == HS_State_ENABLED) {
      Status = CFE_SB_SubscribeEx(CFE_SB_ValueToMsgId(CFE_EVS_LONG_EVENT_MSG_MID),
                                  HS_AppData.EventPipe, CFE_SB_DEFAULT_QOS, HS_EVENT_PIPE_DEPTH);
      if (Status != CFE_SUCCESS) {
        CFE_EVS_SendEvent(HS_SUB_LONG_EVS_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Error Subscribing to long-format Events,RC=0x%08X", Status);

        /* Set run status to terminate main loop */
        RunStatus = CFE_ES_RunStatus_APP_ERROR;
      }

      // A SECOND `if` ON THE SAME CONDITION rather than an `else`, which is the same thing here
      // and is NASA's text.
      if (Status == CFE_SUCCESS) {
        Status = CFE_SB_SubscribeEx(CFE_SB_ValueToMsgId(CFE_EVS_SHORT_EVENT_MSG_MID),
                                    HS_AppData.EventPipe, CFE_SB_DEFAULT_QOS, HS_EVENT_PIPE_DEPTH);
        if (Status != CFE_SUCCESS) {
          CFE_EVS_SendEvent(HS_SUB_SHORT_EVS_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Error Subscribing to short-format Events,RC=0x%08X", Status);

          /* Set run status to terminate main loop */
          RunStatus = CFE_ES_RunStatus_APP_ERROR;
        }
      }
    }
  }

  /*
  ** Application main loop
  */
  while (CFE_ES_RunLoop(&RunStatus) == TRUE) {
    /*
    ** Performance Log, Stop
    */
    CFE_ES_PerfLogExit(HS_APPMAIN_PERF_ID);

    /*
    ** Task Delay for a configured timeout
    */
    // NASA GUARDS AN OS_TaskDelay HERE WITH `#if HS_POST_PROCESSING_DELAY != 0`, and the shipped
    // value is 0 -- so the call is not compiled and is not translated. See the file header: the
    // directive is resolved by hand because HolyC's `#if <expr>` would execute it. A mission with
    // a non-zero HS_POST_PROCESSING_DELAY adds `OS_TaskDelay(HS_POST_PROCESSING_DELAY);` here.

    /*
    ** Task Delay for a configured timeout
    */
    Status = CFE_SB_ReceiveBuffer(&BufPtr, HS_AppData.WakeupPipe, HS_WAKEUP_TIMEOUT);

    /*
    ** Performance Log, Start
    */
    CFE_ES_PerfLogEntry(HS_APPMAIN_PERF_ID);

    /*
    ** Process the software bus message
    */
    // A TIMEOUT AND AN EMPTY PIPE ARE BOTH "keep going". HS's cycle is driven by a wakeup
    // message, but it runs anyway if the scheduler misses one -- which is what keeps the watchdog
    // serviced when the scheduler itself is the thing that failed.
    if (Status == CFE_SUCCESS || Status == CFE_SB_NO_MESSAGE || Status == CFE_SB_TIME_OUT) {
      Status = HS_ProcessMain();
    }

    /*
    ** Note: If there were some reason to exit the task
    **       normally (without error) then we would set
    **       RunStatus = CFE_ES_APP_EXIT
    */
    if (Status != CFE_SUCCESS) {
      /*
      ** Set request to terminate main loop
      */
      RunStatus = CFE_ES_RunStatus_APP_ERROR;
    }
  } /* end CFS_ES_RunLoop while */

  /*
  ** Check for "fatal" process error...
  */
  if (Status != CFE_SUCCESS) {
    /*
    ** Send an event describing the reason for the termination
    */
    // CFE_EVS_EventType_CRITICAL -- THE ONLY CRITICAL EVENT IN HS, and one of very few in the
    // whole port. HS exiting means nothing is watching anything.
    CFE_EVS_SendEvent(HS_APP_EXIT_EID, CFE_EVS_EventType_CRITICAL,
                      "Application Terminating, err = 0x%08X", Status);

    /*
    ** In case cFE Event Services is not working
    */
    CFE_ES_WriteToSysLog("HS App: Application Terminating, ERR = 0x%08X\n", Status);
  }

  // AND THE DEVICE IS STOPPED BEFORE THE EXIT, on every path including the error ones -- so the
  // simulated system monitor's SET_RUNNING goes back to 0 whether HS left cleanly or not.
  HS_SysMonCleanup();

  /*
  ** Performance Log, Stop
  */
  CFE_ES_PerfLogExit(HS_APPMAIN_PERF_ID);

  /*
  ** Exit the application
  */
  CFE_ES_ExitApp(RunStatus);
}

/*******************************************************************************/
// Initialise HS: default state, event services, the CDS, the bus, the tables, the monitor.
I32 HS_AppInit()
{
  I32 Status;

  /*
  ** Initialize operating data to default states...
  */
  MemSet(&HS_AppData, 0, sizeof(HS_AppData_t));
  HS_AppData.ServiceWatchdogFlag = HS_State_ENABLED;
  HS_AppData.RunStatus = CFE_ES_RunStatus_APP_RUN;

  HS_AppData.CurrentAppMonState = HS_APPMON_DEFAULT_STATE;
  HS_AppData.CurrentEventMonState = HS_EVENTMON_DEFAULT_STATE;
  HS_AppData.CurrentAlivenessState = HS_ALIVENESS_DEFAULT_STATE;
  HS_AppData.CurrentCPUHogState = HS_CPUHOG_DEFAULT_STATE;

  // THE FIVE THAT ARE ENABLED UNCONDITIONALLY, with no configuration switch -- the four tables'
  // states and the CDS. A table whose load fails is disabled by HS_TblInit; starting from
  // ENABLED is what makes HS_AcquirePointers report the first failure instead of swallowing it.
  HS_AppData.ExeCountState = HS_State_ENABLED;
  HS_AppData.MsgActsState = HS_State_ENABLED;
  HS_AppData.AppMonLoaded = HS_State_ENABLED;
  HS_AppData.EventMonLoaded = HS_State_ENABLED;
  HS_AppData.CDSState = HS_State_ENABLED;

  HS_AppData.MaxCPUHoggingTime = HS_UTIL_HOGGING_TIMEOUT;

  /*
  ** Register for event services...
  */
  Status = CFE_EVS_Register(NULL, 0, CFE_EVS_EventFilter_BINARY);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("HS App: Error Registering For Event Services, RC = 0x%08X\n", Status);
    return Status;
  }

  /*
  ** Create Critical Data Store
  */
  Status = CFE_ES_RegisterCDS(&HS_AppData.MyCDSHandle, sizeof(HS_CDSData_t), HS_CDSNAME);

  if (Status == CFE_ES_CDS_ALREADY_EXISTS) {
    /*
    ** Critical Data Store already existed, we need to get a
    ** copy of its current contents to see if we can use it
    */
    Status = CFE_ES_RestoreFromCDS(&HS_AppData.CDSData, HS_AppData.MyCDSHandle);

    if (Status == CFE_SUCCESS) {
      // THE COMPLEMENT CHECK. The cast is NASA's and it MATTERS: `~` of a uint16 promotes to int,
      // so without the (uint16) the comparison would be against a value with the top 48 bits set.
      // HolyC's (U16) cast masks, so the two sides agree -- see
      // docs/HOLYC_IMPLEMENTATION_STATUS.md on which casts mask and which relabel.
      if (HS_AppData.CDSData.ResetsPerformed != (~HS_AppData.CDSData.ResetsPerformedNot)(U16) ||
          HS_AppData.CDSData.MaxResets != (~HS_AppData.CDSData.MaxResetsNot)(U16)) {
        /*
        ** Report error restoring data
        */
        CFE_EVS_SendEvent(HS_CDS_CORRUPT_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Data in CDS was corrupt, initializing resets data");
        /*
        ** If data was corrupt, initialize data
        */
        HS_SetCDSData(0, HS_MAX_RESTART_ACTIONS);
      }
    } else {
      /*
      ** Report error restoring data
      */
      // LOWER-CASE %08x HERE, upper case everywhere else in HS. NASA's, and kept -- the two
      // spellings render the same digits for the statuses this can carry and differ for A-F,
      // which is exactly the class of drift docs/ records as invisible until a value exercises it.
      CFE_EVS_SendEvent(HS_CDS_RESTORE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Failed to restore data from CDS (Err=0x%08x), initializing resets data",
                        Status);
      /*
      ** If data could not be retrieved, initialize data
      */
      HS_SetCDSData(0, HS_MAX_RESTART_ACTIONS);
    }

    // LOAD-BEARING -- see the file header. Without it a restored-but-corrupt CDS terminates HS.
    Status = CFE_SUCCESS;
  } else if (Status == CFE_SUCCESS) {
    /*
    ** If CDS did not previously exist, initialize data
    */
    HS_SetCDSData(0, HS_MAX_RESTART_ACTIONS);
  } else {
    /*
    ** Disable saving to CDS
    */
    HS_AppData.CDSState = HS_State_DISABLED;

    /*
    ** Initialize values anyway (they will not be saved)
    */
    HS_SetCDSData(0, HS_MAX_RESTART_ACTIONS);
  }

  /*
  ** Set up the HS Software Bus
  */
  Status = HS_SbInit();
  if (Status != CFE_SUCCESS) {
    return Status;
  }

  /*
  ** Register The HS Tables
  */
  Status = HS_TblInit();
  if (Status != CFE_SUCCESS) {
    return Status;
  }

  /*
  ** Perform initialization for system monitoring
  */
  Status = HS_SysMonInit();
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_SYSMON_INIT_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error in system monitor initialization, RC=0x%08X", Status);
    return Status;
  }

  /*
  ** Application initialization event
  */
  CFE_EVS_SendEvent(HS_INIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "HS Initialized.  Version %d.%d.%d.%d", HS_MAJOR_VERSION, HS_MINOR_VERSION,
                    HS_REVISION, HS_MISSION_REV);

  return Status;
}

/*******************************************************************************/
// Create HS's three pipes and subscribe to its three inputs.
//
// NOTE THE ASYMMETRY: the housekeeping request and the ground commands go to the SAME pipe
// (CmdPipe) and the wakeup to its own, because the wakeup is what paces the main loop --
// CFE_SB_ReceiveBuffer blocks on WakeupPipe with a timeout while CmdPipe is polled. A command
// arriving on the wakeup pipe would wake HS early; a wakeup arriving on the command pipe would be
// an unrecognised message id.
//
// AND THE EVENT PIPE IS CREATED HERE BUT SUBSCRIBED TO IN HS_AppMain, after the startup sync --
// NASA's closing comment says so: "Event message subscription delayed until after startup synch".
I32 HS_SbInit()
{
  I32 Status;

  /* Initialize housekeeping packet  */
  CFE_MSG_Init(&HS_AppData.HkPacket.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(HS_HK_TLM_MID),
               sizeof(HS_HkPacket_t));

  /* Create Command Pipe */
  Status = CFE_SB_CreatePipe(&HS_AppData.CmdPipe, HS_CMD_PIPE_DEPTH, HS_CMD_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_CR_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Creating SB Command Pipe,RC=0x%08X", Status);
    return Status;
  }

  /* Create Event Pipe */
  Status = CFE_SB_CreatePipe(&HS_AppData.EventPipe, HS_EVENT_PIPE_DEPTH, HS_EVENT_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_CR_EVENT_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Creating SB Event Pipe,RC=0x%08X", Status);
    return Status;
  }

  /* Create Wakeup Pipe */
  Status = CFE_SB_CreatePipe(&HS_AppData.WakeupPipe, HS_WAKEUP_PIPE_DEPTH, HS_WAKEUP_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_CR_WAKEUP_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Creating SB Wakeup Pipe,RC=0x%08X", Status);
    return Status;
  }

  /* Subscribe to Housekeeping Request */
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(HS_SEND_HK_MID), HS_AppData.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_SUB_REQ_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Subscribing to HK Request,RC=0x%08X", Status);
    return Status;
  }

  /* Subscribe to HS ground commands */
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(HS_CMD_MID), HS_AppData.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_SUB_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Subscribing to Gnd Cmds,RC=0x%08X", Status);
    return Status;
  }

  /* Subscribe to HS Wakeup Message */
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(HS_WAKEUP_MID), HS_AppData.WakeupPipe);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_SUB_WAKEUP_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Subscribing to Wakeup,RC=0x%08X", Status);
    return Status;
  }

  /*
  ** Event message subscription delayed until after startup synch
  */

  return Status;
}

/*******************************************************************************/
// Register and load HS's four tables. REGISTRATION FAILS HARD, A LOAD NEVER DOES -- see the file
// header, which is where this function's one design decision is written down.
I32 HS_TblInit()
{
  U32 TableSize = 0;
  U32 TableIndex = 0;
  I32 Status;

  /* Register The HS Applications Monitor Table */
  TableSize = HS_MAX_MONITORED_APPS * sizeof(HS_AMTEntry_t);
  Status = CFE_TBL_Register(&HS_AppData.AMTableHandle, HS_AMT_TABLENAME, TableSize,
                            CFE_TBL_OPT_DEFAULT, &HS_ValidateAMTable);

  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_AMT_REG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Registering AppMon Table,RC=0x%08X", Status);
    return Status;
  }

  /* Register The HS Events Monitor Table */
  TableSize = HS_MAX_MONITORED_EVENTS * sizeof(HS_EMTEntry_t);
  Status = CFE_TBL_Register(&HS_AppData.EMTableHandle, HS_EMT_TABLENAME, TableSize,
                            CFE_TBL_OPT_DEFAULT, &HS_ValidateEMTable);

  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_EMT_REG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Registering EventMon Table,RC=0x%08X", Status);
    return Status;
  }

  /* Register The HS Message Actions Table */
  TableSize = HS_MAX_MSG_ACT_TYPES * sizeof(HS_MATEntry_t);
  Status = CFE_TBL_Register(&HS_AppData.MATableHandle, HS_MAT_TABLENAME, TableSize,
                            CFE_TBL_OPT_DEFAULT, &HS_ValidateMATable);

  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_MAT_REG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Registering MsgActs Table,RC=0x%08X", Status);
    return Status;
  }

  /* Register The HS Execution Counters Table */
  TableSize = HS_MAX_EXEC_CNT_SLOTS * sizeof(HS_XCTEntry_t);
  Status = CFE_TBL_Register(&HS_AppData.XCTableHandle, HS_XCT_TABLENAME, TableSize,
                            CFE_TBL_OPT_DEFAULT, &HS_ValidateXCTable);

  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_XCT_REG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Registering ExeCount Table,RC=0x%08X", Status);
    return Status;
  }

  /* Load the HS Execution Counters Table */
  // LOADED FIRST, out of registration order, because its failure arm writes the housekeeping
  // packet -- see the file header and NASA's requirement citation below.
  Status = CFE_TBL_Load(HS_AppData.XCTableHandle, CFE_TBL_SRC_FILE, HS_XCT_FILENAME);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_XCT_LD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Loading ExeCount Table,RC=0x%08X", Status);
    HS_AppData.ExeCountState = HS_State_DISABLED;
    for (TableIndex = 0; TableIndex < HS_MAX_EXEC_CNT_SLOTS; TableIndex++) {
      /* HS 8005.1 Report 0xFFFFFFFF for all entries */
      HS_AppData.HkPacket.Payload.ExeCounts[TableIndex] = HS_INVALID_EXECOUNT;
    }
  }

  /* Load the HS Applications Monitor Table */
  Status = CFE_TBL_Load(HS_AppData.AMTableHandle, CFE_TBL_SRC_FILE, HS_AMT_FILENAME);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_AMT_LD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Loading AppMon Table,RC=0x%08X", Status);
    HS_AppData.CurrentAppMonState = HS_State_DISABLED;
    // THE SECOND EVENT. Only the two monitor tables announce the disable separately.
    CFE_EVS_SendEvent(HS_DISABLE_APPMON_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Application Monitoring Disabled due to Table Load Failure");
    HS_AppData.AppMonLoaded = HS_State_DISABLED;
  }

  /* Load the HS Events Monitor Table */
  Status = CFE_TBL_Load(HS_AppData.EMTableHandle, CFE_TBL_SRC_FILE, HS_EMT_FILENAME);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_EMT_LD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Loading EventMon Table,RC=0x%08X", Status);
    HS_AppData.CurrentEventMonState = HS_State_DISABLED;
    CFE_EVS_SendEvent(HS_DISABLE_EVENTMON_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Event Monitoring Disabled due to Table Load Failure");
    HS_AppData.EventMonLoaded = HS_State_DISABLED;
  }

  /* Load the HS Message Actions Table */
  Status = CFE_TBL_Load(HS_AppData.MATableHandle, CFE_TBL_SRC_FILE, HS_MAT_FILENAME);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(HS_MAT_LD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Loading MsgActs Table,RC=0x%08X", Status);
    HS_AppData.MsgActsState = HS_State_DISABLED;
  }

  /*
  ** Get pointers to table data
  */
  HS_AcquirePointers();

  // CFE_SUCCESS UNCONDITIONALLY, DISCARDING FOUR LOAD RESULTS. The most important line in this
  // file -- see the file header.
  return CFE_SUCCESS;
}

/*******************************************************************************/
// One HS cycle: re-acquire the tables, age the cooldowns, sample utilisation, monitor the
// applications, blink, drain the pipes, pet the dog.
I32 HS_ProcessMain()
{
  I32 Status = CFE_SUCCESS;
  U8 *AliveString = HS_CPU_ALIVE_STRING;
  U32 i = 0;

  /*
  ** Get Tables
  */
  HS_AcquirePointers();

  /*
  ** Decrement Cooldowns for Message Actions
  */
  for (i = 0; i < HS_MAX_MSG_ACT_TYPES; i++) {
    if (HS_AppData.MsgActCooldown[i] != 0) {
      HS_AppData.MsgActCooldown[i]--;
    }
  }

  if (HS_AppData.UtilizationCycleCounter == 0) {
    HS_MonitorUtilization();
    HS_AppData.UtilizationCycleCounter = HS_CPU_UTILIZATION_CYCLES_PER_INTERVAL;
  }
  // OUTSIDE THE `if`, so the sampling cycle consumes a count too -- see the file header.
  --HS_AppData.UtilizationCycleCounter;

  /*
  ** Monitor Applications
  */
  if (HS_AppData.CurrentAppMonState == HS_State_ENABLED) {
    HS_MonitorApplications();
  }

  /*
  ** Output Aliveness
  */
  // OS_printf, NOT AN EVENT -- the aliveness indicator goes to the console, so a ground operator
  // never sees it and a developer with a serial cable does. HS_CPU_ALIVE_STRING has no newline;
  // the dots accumulate on one line until something else prints.
  if (HS_AppData.CurrentAlivenessState == HS_State_ENABLED) {
    HS_AppData.AlivenessCounter++;

    if (HS_AppData.AlivenessCounter >= HS_CPU_ALIVE_PERIOD) {
      OS_printf("%s", AliveString);
      HS_AppData.AlivenessCounter = 0;
    }
  }

  /*
  ** Check for Commands, Events, and HK Requests
  */
  Status = HS_ProcessCommands();

  /*
  ** Service the Watchdog
  */
  // THE FLAG THE MONITORS CLEAR BEFORE A SOFTWARE RESET. See hs_monitors.HC: this `if` is what
  // makes HS_AppData.ServiceWatchdogFlag = HS_State_DISABLED stop the petting.
  if (HS_AppData.ServiceWatchdogFlag == HS_State_ENABLED) {
    CFE_PSP_WatchdogService();
  }

  return Status;
}

/*******************************************************************************/
// Drain both polled pipes. Events first, and NASA says why -- see the file header.
I32 HS_ProcessCommands()
{
  I32 Status = CFE_SUCCESS;
  CFE_SB_Buffer *BufPtr = NULL;

  /*
  ** Event Message Pipe (done first so EventMon does not get enabled without table checking)
  */
  if (HS_AppData.CurrentEventMonState == HS_State_ENABLED) {
    while (Status == CFE_SUCCESS) {
      Status = CFE_SB_ReceiveBuffer(&BufPtr, HS_AppData.EventPipe, CFE_SB_POLL);

      if (Status == CFE_SUCCESS && BufPtr != NULL) {
        /*
        ** Pass Events to Event Monitor
        */
        // COUNTED BEFORE THE MONITOR RUNS: this is "events dequeued", not "events acted on".
        HS_AppData.EventsMonitoredCount++;
        HS_MonitorEvent(BufPtr);
      }
    }
  }

  if (Status == CFE_SB_NO_MESSAGE) {
    /*
    ** It's Good to not get a message -- we are polling
    */
    // NOT BOILERPLATE: the command loop below tests `Status == CFE_SUCCESS`, so without this
    // conversion an empty event pipe would stop HS from processing any command this cycle.
    Status = CFE_SUCCESS;
  }

  /*
  ** Command and HK Requests Pipe
  */
  while (Status == CFE_SUCCESS) {
    /*
    ** Process pending Commands or HK Reqs
    */
    Status = CFE_SB_ReceiveBuffer(&BufPtr, HS_AppData.CmdPipe, CFE_SB_POLL);
    if (Status == CFE_SUCCESS && BufPtr != NULL) {
      /*
      ** Pass Commands/HK Req to AppPipe Processing
      */
      HS_AppPipe(BufPtr);
    }
  }

  if (Status == CFE_SB_NO_MESSAGE) {
    /*
    ** It's Good to not get a message -- we are polling
    */
    Status = CFE_SUCCESS;
  }

  return Status;
}

#endif
