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
// LIMIT CHECKER'S ENTRY POINT AND STARTUP -- the 1:1 translation of NASA's fsw/src/lc_app.c,
// 1,031 lines and nine functions. The last of LC's seven sources, and the one that decides
// whether LC's critical data store exists at all.
//
// ### IN THIS CONFIGURATION LC'S ENTIRE CDS PATH IS DEAD, AND THAT IS NASA'S DEFAULT
//
// LC_TableInit opens with
//
//     #ifdef LC_SAVE_TO_CDS
//         LC_OperData.HaveActiveCDS = true;
//     #endif
//
// and `LC_SAVE_TO_CDS` IS NOT DEFINED. NASA ships it commented out in lc_internal_cfg.h -- both
// the `#define LC_SAVE_TO_CDS LC_INTERNAL_CFGVAL(SAVE_TO_CDS)` and the `DEFAULT_` line that feeds
// it sit inside a block comment. So `HaveActiveCDS` is false from the memset to the exit, and
// with it go: the three CFE_ES_RegisterCDS calls, both critical-table registrations, the
// un-register/re-register dance, the exit-time save, and LC_PerformMaintenance's periodic one.
// NASA's own unit test states the consequence -- "When this is not defined EVENT ID=23 is always
// issued" -- and 23 is LC_CDS_DISABLED_INF_EID, the event at the bottom of LC_TableInit.
//
// THE CODE IS STILL TRANSLATED IN FULL. The `#ifdef` body is the one line omitted, with a note at
// the site; everything it would have enabled is here and reachable the moment the flag is set or
// the exercise writes HaveActiveCDS directly, which is how the differential drives it. Resolving
// a directive is not the same as dropping its subject.
//
// ### THE OTHER RESOLVED DIRECTIVE IS A COMPARISON OF TWO CONFIGURATION VALUES
//
// LC_CreateTaskCDS ends its AppData restore with
//
//     #if LC_STATE_WHEN_CDS_RESTORED != LC_STATE_FROM_CDS
//         LC_AppData.CurrentLCState = LC_STATE_WHEN_CDS_RESTORED;
//     #endif
//
// and in the stock configuration both are 4, so the override is excluded. That line is the ONLY
// place in LC that would write CurrentLCState during a CDS restore, which is why it is called out
// here rather than silently omitted: with the directive resolved this way, a restored CDS keeps
// whatever state the previous run was in, and a mission that wants LC to come up disabled after a
// warm boot changes LC_STATE_WHEN_CDS_RESTORED and this line reappears.
//
// Both omissions follow docs/CFS_PORT.md's rule for a directive whose condition is decidable at
// translation time: resolve it, omit the dead arm, and say so at the site.
//
// ### A STATUS THAT IS DELIBERATELY THROWN AWAY
//
// In LC_TableInit, LC_CreateTaskCDS's result is assigned to `Result` and then IMMEDIATELY
// overwritten by LC_CreateDefinitionTables without being tested:
//
//     Result = LC_CreateTaskCDS();
//     if (Result != CFE_SUCCESS) { LC_OperData.HaveActiveCDS = false; }
//     Result = LC_CreateDefinitionTables();
//
// That reads like a bug and is not one. NASA's comment above it says "continue with init, but
// disable CDS if unable to create all 3" -- the failure's whole effect is the flag, and the
// definition tables are a hard requirement that must be attempted regardless. Kept verbatim,
// because a translation that "fixed" it would turn a recoverable CDS failure into a task that
// refuses to start.
//
// ### THE MAIN LOOP TREATS A TIMEOUT AS WORK, NOT AS AN ERROR
//
// LC_AppMain pends with LC_SB_TIMEOUT (1000 ms) rather than CFE_SB_PEND_FOREVER, and
// CFE_SB_TIME_OUT runs LC_PerformMaintenance -- the same routine the housekeeping request runs.
// NASA's comment: "If we are not getting messages as expected, the routine actions are done here
// instead." So LC keeps managing its tables and writing its CDS even if the scheduler stops
// talking to it, and CFE_SB_NO_MESSAGE is folded to CFE_SUCCESS with "no action, but also no
// error". Everything else that is not CFE_SUCCESS terminates the loop.
#ifndef LC_APP_HC
#define LC_APP_HC

// --- lc_app.h's prototypes ---------------------------------------------------------------------
U0 LC_AppMain();
I32 LC_AppInit();
I32 LC_EvsInit();
I32 LC_SbInit();
I32 LC_TableInit();
I32 LC_CreateResultTables();
I32 LC_CreateDefinitionTables();
I32 LC_CreateTaskCDS();
I32 LC_LoadDefaultTables();

/*******************************************************************************/
// LC application entry point and main process loop.
U0 LC_AppMain()
{
  I32 Status = CFE_SUCCESS;
  Bool Initialized = FALSE;
  U32 RunStatus = CFE_ES_RunStatus_APP_RUN;
  CFE_SB_Buffer *BufPtr = NULL;

  /*
  ** Performance Log, Start
  */
  CFE_ES_PerfLogEntry(LC_APPMAIN_PERF_ID);

  /*
  ** Perform application specific initialization
  */
  Status = LC_AppInit();

  /*
  ** Check for start-up error...
  */
  if (Status != CFE_SUCCESS) {
    /*
    ** Set run status to terminate main loop
    */
    RunStatus = CFE_ES_RunStatus_APP_ERROR;
    Initialized = FALSE;
  } else {
    Initialized = TRUE;
  }

  /*
  ** Application main loop
  */
  while (CFE_ES_RunLoop(&RunStatus) == TRUE) {
    /*
    ** Performance Log, Stop
    */
    CFE_ES_PerfLogExit(LC_APPMAIN_PERF_ID);

    /*
    ** Pend on the arrival of the next Software Bus message
    */
    Status = CFE_SB_ReceiveBuffer(&BufPtr, LC_OperData.CmdPipe, LC_SB_TIMEOUT);

    /*
    ** Performance Log, Start
    */
    CFE_ES_PerfLogEntry(LC_APPMAIN_PERF_ID);

    /*
    ** Process the software bus message
    */
    if (Status == CFE_SB_TIME_OUT) {
      /* Note: these routine actions are generally done in the
       * housekeeping cycle.  If we are not getting messages as
       * expected, the routine actions are done here instead. */
      Status = LC_PerformMaintenance();
    } else if (Status == CFE_SB_NO_MESSAGE) {
      /* no action, but also no error */
      Status = CFE_SUCCESS;
    } else if (Status == CFE_SUCCESS) {
      LC_AppPipe(BufPtr);
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
    CFE_EVS_SendEvent(LC_TASK_EXIT_EID, CFE_EVS_EventType_CRITICAL,
                      "Task terminating, err = 0x%08X", Status);

    /*
    ** In case cFE Event Services is not working
    */
    CFE_ES_WriteToSysLog("LC task terminating, err = 0x%08X\n", Status);
  }

  /*
  ** Performance Log, Stop
  */
  CFE_ES_PerfLogExit(LC_APPMAIN_PERF_ID);

  /*
  ** Do not update CDS if inactive or startup was incomplete
  */
  if ((Initialized == TRUE) && (LC_OperData.HaveActiveCDS) &&
      (LC_AppData.CDSSavedOnExit == LC_CDS_SAVED)) {
    LC_UpdateTaskCDS();
  }

  /*
  ** Exit the application
  */
  CFE_ES_ExitApp(RunStatus);
}

/*******************************************************************************/
// LC initialization.
//
// THE TWO memsets ARE THE ONLY THING THAT ZEROES LC'S STATE, and in C a file-scope object is
// already zero -- so on a cold start they are redundant and on a re-init they are not. The
// translation keeps both, and they matter MORE here than in NASA's build: the differential
// exercise calls LC_AppInit more than once in a single process, so the second call depends on
// these two lines for the clean slate a fresh program image would have given it.
I32 LC_AppInit()
{
  I32 Status = CFE_SUCCESS;

  /*
  ** Zero out the global data structures...
  */
  MemSet(&LC_OperData, 0, sizeof(LC_OperData_t));
  MemSet(&LC_AppData, 0, sizeof(LC_AppData_t));

  /*
  ** Initialize event services
  */
  Status = LC_EvsInit();

  /*
  ** Initialize software bus
  */
  if (Status == CFE_SUCCESS) {
    Status = LC_SbInit();
  }

  /*
  ** Initialize table services
  */
  if (Status == CFE_SUCCESS) {
    Status = LC_TableInit();
  }

  if (Status == CFE_SUCCESS) {
    /*
    ** If we get here, all is good
    ** Issue the application startup event message
    */
    CFE_EVS_SendEvent(LC_INIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "LC Initialized. Version %d.%d.%d.%d", LC_MAJOR_VERSION, LC_MINOR_VERSION,
                      LC_REVISION, LC_MISSION_REV);
  }

  return Status;
}

/*******************************************************************************/
// Initialize event services interface.
//
// LC REGISTERS WITH NO FILTERS AT ALL -- NULL, 0, BINARY -- so every event LC sends goes out
// every time, and the per-event rate limiting the other apps in this port rely on does not exist
// here. NASA's comment says why it is shaped for a filter table anyway: "If an application event
// filter table is added in the future, initialize it here."
//
// That is load-bearing for LC specifically. lc_watch.c sends LC_MID_INF_EID once PER UNRECOGNISED
// PACKET, and lc_action.c can send a failure event per actionpoint per sample. With no filter, a
// misconfigured watchpoint table is an unbounded event stream rather than a handful of messages.
I32 LC_EvsInit()
{
  I32 Status = CFE_SUCCESS;

  /*
  ** If an application event filter table is added
  ** in the future, initialize it here
  */

  /*
  **  Register for event services
  */
  Status = CFE_EVS_Register(NULL, 0, CFE_EVS_EventFilter_BINARY);

  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("LC App: Error Registering For Event Services, RC = 0x%08X\n", Status);
  }

  return Status;
}

/*******************************************************************************/
// Initialize the software bus interface.
//
// THREE SUBSCRIPTIONS HERE, AND THE WATCHPOINT SUBSCRIPTIONS ARE SOMEWHERE ELSE ENTIRELY. This
// function subscribes to LC's own ids only -- housekeeping request, ground command, internal
// actionpoint sample. The packets LC actually monitors are subscribed by LC_CreateHashTable, from
// the watchpoint definition table, during LC_TableInit. So LC's pipe is not fully wired until the
// tables are up, and the order in LC_AppInit (EVS, SB, then tables) is what makes that work.
//
// EACH FAILURE REPORTS THE MESSAGE ID IT COULD NOT SUBSCRIBE TO, as a bare constant rather than
// through CFE_SB_MsgIdToValue -- the ids are compile-time values here, so there is no handle to
// convert.
I32 LC_SbInit()
{
  I32 Status = CFE_SUCCESS;

  /*
  ** Initialize housekeeping packet...
  */
  // CFE_MSG_PTR(x) is NASA's &x.Msg, written out as it is elsewhere in this port.
  CFE_MSG_Init(&LC_OperData.HkPacket.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(LC_HK_TLM_MID),
               sizeof(LC_HkPacket_t));

  /*
  ** Create Software Bus message pipe...
  */
  Status = CFE_SB_CreatePipe(&LC_OperData.CmdPipe, LC_PIPE_DEPTH, LC_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(LC_CR_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Creating LC Pipe, RC=0x%08X", Status);
  }

  if (Status == CFE_SUCCESS) {
    /*
    ** Subscribe to Housekeeping request messages...
    */
    Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(LC_SEND_HK_MID), LC_OperData.CmdPipe);
    if (Status != CFE_SUCCESS) {
      CFE_EVS_SendEvent(LC_SUB_HK_REQ_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error Subscribing to HK Request, MID=0x%08X, RC=0x%08X", LC_SEND_HK_MID,
                        Status);
    }
  }

  if (Status == CFE_SUCCESS) {
    /*
    ** Subscribe to LC ground command messages...
    */
    Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(LC_CMD_MID), LC_OperData.CmdPipe);
    if (Status != CFE_SUCCESS) {
      CFE_EVS_SendEvent(LC_SUB_GND_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error Subscribing to GND CMD, MID=0x%08X, RC=0x%08X", LC_CMD_MID, Status);
    }
  }

  if (Status == CFE_SUCCESS) {
    /*
    ** Subscribe to LC internal actionpoint sample messages...
    */
    Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(LC_SAMPLE_AP_MID), LC_OperData.CmdPipe);
    if (Status != CFE_SUCCESS) {
      CFE_EVS_SendEvent(LC_SUB_SAMPLE_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error Subscribing to Sample CMD, MID=0x%08X, RC=0x%08X", LC_SAMPLE_AP_MID,
                        Status);
    }
  }

  return Status;
}

/*******************************************************************************/
// Table initialization - includes Critical Data Store (CDS).
//
// THE FIVE-WAY RESTORE TEST IS ALL-OR-NOTHING AND THAT IS THE POINT. LC only accepts a restored
// state if ALL of WRT, ART, AppData, WDT and ADT came back; any one missing sends it down
// LC_LoadDefaultTables, which reloads both definition tables from file, clears every result, and
// resets the counters. NASA's comment lists the reasons that can happen -- "might be due to reset
// type, CDS disabled or corrupt, table restore error" -- and the reasoning is that a half-restored
// LC would check watchpoints against one run's limits using another run's accumulated results.
//
// AND THE EVENT AT THE BOTTOM IS THE ONLY PUBLIC RECORD OF WHICH PATH WAS TAKEN. TableResults is
// a 23-bit mask of everything that happened during startup, and it is reported exactly once, in
// one of three mutually exclusive events -- restored, defaults-written-to-CDS, or CDS-disabled.
// The mask also lands in the housekeeping packet, so the full detail stays readable afterwards;
// the event is what makes it legible in the event log at the moment it was decided.
I32 LC_TableInit()
{
  I32 Result;

  /*
  ** LC task use of Critical Data Store (CDS)
  **
  **    Global application data (LC_AppData)
  **    Watchpoint results dump only table data
  **    Actionpoint results dump only table data
  **
  ** cFE Table Services use of CDS for LC task
  **
  **    Watchpoint definition loadable table data
  **    Actionpoint definition loadable table data
  **
  ** LC table initialization logic re CDS
  **
  **    If LC cannot create all the CDS storage at startup, then LC
  **    will disable LC use of CDS and continue.
  **
  **    If LC cannot register definition tables as critical, then LC
  **    will disable LC use of CDS and re-register tables as non-critical.
  **
  **    If LC cannot register definition and results tables at startup,
  **    then LC will terminate - table use is a required function.
  **
  **    If LC can create all the CDS storage and register definition
  **    tables as critical, then LC will write to CDS regardless of
  **    whether LC was able to read from CDS at startup.
  **
  **    If LC cannot restore everything from CDS at startup, then LC
  **    will initialize everything - load default definition tables,
  **    init results table contents, init global application data.
  */

  // NASA'S `#ifdef LC_SAVE_TO_CDS` BLOCK IS OMITTED HERE, and its body was one line:
  //
  //     LC_OperData.HaveActiveCDS = true;
  //
  // LC_SAVE_TO_CDS is NOT DEFINED in the stock configuration -- lc_internal_cfg.h ships both its
  // #define and its DEFAULT_ inside a block comment -- so in this build HaveActiveCDS stays
  // FALSE, nothing below this point touches the CDS, and LC_CDS_DISABLED_INF_EID is always the
  // event at the bottom of this function. See the file header for what that switches off.
  // Everything the flag gates is translated and reachable; only this assignment is gone.

  /*
  ** Maintain a detailed record of table initialization results
  */
  if (LC_OperData.HaveActiveCDS) {
    LC_OperData.TableResults |= LC_CDS_ENABLED;
  }

  /*
  ** Create watchpoint and actionpoint result tables
  */
  Result = LC_CreateResultTables();

  /*
  ** If CDS is enabled - create the 3 CDS areas managed by the LC task
  **  (continue with init, but disable CDS if unable to create all 3)
  */
  if (Result == CFE_SUCCESS) {
    if (LC_OperData.HaveActiveCDS) {
      Result = LC_CreateTaskCDS();
      if (Result != CFE_SUCCESS) {
        LC_OperData.HaveActiveCDS = FALSE;
      }
    }
    /*
     ** Create wp/ap definition tables - critical if CDS enabled
     */
    // THE OVERWRITE ABOVE IS NASA'S AND IS INTENTIONAL: a failed LC_CreateTaskCDS has already had
    // its entire effect (HaveActiveCDS = FALSE), and the definition tables must be attempted
    // either way. See the file header.
    Result = LC_CreateDefinitionTables();
  }

  /*
  ** CDS still active only if we created 3 CDS areas and 2 critical tables
  */
  if ((Result == CFE_SUCCESS) && (LC_OperData.HaveActiveCDS)) {
    LC_OperData.TableResults |= LC_CDS_CREATED;
  }

  /*
  ** If any CDS area or critical table is not restored - initialize everything.
  **  (might be due to reset type, CDS disabled or corrupt, table restore error)
  */
  if (Result == CFE_SUCCESS) {
    if (((LC_OperData.TableResults & LC_WRT_CDS_RESTORED) == LC_WRT_CDS_RESTORED) &&
        ((LC_OperData.TableResults & LC_ART_CDS_RESTORED) == LC_ART_CDS_RESTORED) &&
        ((LC_OperData.TableResults & LC_APP_CDS_RESTORED) == LC_APP_CDS_RESTORED) &&
        ((LC_OperData.TableResults & LC_WDT_TBL_RESTORED) == LC_WDT_TBL_RESTORED) &&
        ((LC_OperData.TableResults & LC_ADT_TBL_RESTORED) == LC_ADT_TBL_RESTORED)) {
      LC_OperData.TableResults |= LC_CDS_RESTORED;

      /*
      ** Get a pointer to the watchpoint definition table data...
      */
      Result = CFE_TBL_GetAddress(&LC_OperData.WDTPtr, LC_OperData.WDTHandle);

      if ((Result != CFE_SUCCESS) && (Result != CFE_TBL_INFO_UPDATED)) {
        CFE_EVS_SendEvent(LC_WDT_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Error getting WDT address, RC=0x%08X", Result);
      }

      /*
      ** Get a pointer to the actionpoint definition table data
      */
      if ((Result == CFE_SUCCESS) || (Result == CFE_TBL_INFO_UPDATED)) {
        Result = CFE_TBL_GetAddress(&LC_OperData.ADTPtr, LC_OperData.ADTHandle);

        if ((Result != CFE_SUCCESS) && (Result != CFE_TBL_INFO_UPDATED)) {
          CFE_EVS_SendEvent(LC_ADT_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                            "Error getting ADT address, RC=0x%08X", Result);
        }
      }
    } else {
      Result = LC_LoadDefaultTables();
    }

    if (Result == CFE_TBL_INFO_UPDATED) {
      Result = CFE_SUCCESS;
    }
  }

  /*
  ** Create watchpoint hash tables -- also subscribes to watchpoint packets
  */
  if (Result == CFE_SUCCESS) {
    LC_CreateHashTable();

    /*
    ** Display results of CDS initialization (if enabled at startup)
    */
    if ((LC_OperData.TableResults & LC_CDS_ENABLED) == LC_CDS_ENABLED) {
      if ((LC_OperData.TableResults & LC_CDS_RESTORED) == LC_CDS_RESTORED) {
        CFE_EVS_SendEvent(LC_CDS_RESTORED_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "Previous state restored from Critical Data Store");
      } else if ((LC_OperData.TableResults & LC_CDS_UPDATED) == LC_CDS_UPDATED) {
        CFE_EVS_SendEvent(LC_CDS_UPDATED_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "Default state loaded and written to CDS, activity mask = 0x%08X",
                          LC_OperData.TableResults);
      }
    } else {
      CFE_EVS_SendEvent(LC_CDS_DISABLED_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "LC use of Critical Data Store disabled, activity mask = 0x%08X",
                        LC_OperData.TableResults);
    }
  }

  return Result;
}

/*******************************************************************************/
// Startup initialization - create WP and AP results tables.
//
// A RESULTS TABLE IS DUMP-ONLY, SINGLE-BUFFERED, AND HAS NO VALIDATION CALLBACK -- the same shape
// CS uses for its results tables, and for the same reason: this is LC's output, so the ground may
// read it and may not load it. NASA's comment adds the CDS consequence: "dump only tables cannot
// be critical with CDS use managed by CFE Table Services", which is exactly why LC_CreateTaskCDS
// exists to register the WRT and ART contents as CDS areas by hand.
//
// THE FOUR STEPS ARE SEQUENCED THROUGH `Result` RATHER THAN NESTED, so a WRT registration failure
// skips the ART entirely and the two LC_*_TBL_CREATED bits record exactly how far it got.
I32 LC_CreateResultTables()
{
  I32 Result;
  U32 DataSize;
  U32 OptionFlags;

  /*
  ** Set "dump only" table option flags
  */
  OptionFlags = CFE_TBL_OPT_SNGL_BUFFER | CFE_TBL_OPT_DUMP_ONLY;

  /*
  ** Register the Watchpoint Results Table (WRT) - "dump only" tables
  ** cannot be critical with CDS use managed by CFE Table Services.
  */
  DataSize = LC_MAX_WATCHPOINTS * sizeof(LC_WRTEntry_t);
  Result = CFE_TBL_Register(&LC_OperData.WRTHandle, LC_WRT_TABLENAME, DataSize, OptionFlags, NULL);
  if (Result != CFE_SUCCESS) {
    CFE_EVS_SendEvent(LC_WRT_REGISTER_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error registering WRT, RC=0x%08X", Result);
  } else {
    Result = CFE_TBL_GetAddress(&LC_OperData.WRTPtr, LC_OperData.WRTHandle);

    if (Result != CFE_SUCCESS) {
      CFE_EVS_SendEvent(LC_WRT_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error getting WRT address, RC=0x%08X", Result);
    }
  }

  if (Result == CFE_SUCCESS) {
    LC_OperData.TableResults |= LC_WRT_TBL_CREATED;

    /*
    ** Register the Actionpoint Results Table (ART) - "dump only" tables
    ** cannot be critical with CDS use managed by CFE Table Services.
    */
    DataSize = LC_MAX_ACTIONPOINTS * sizeof(LC_ARTEntry_t);
    Result = CFE_TBL_Register(&LC_OperData.ARTHandle, LC_ART_TABLENAME, DataSize, OptionFlags,
                              NULL);
    if (Result != CFE_SUCCESS) {
      CFE_EVS_SendEvent(LC_ART_REGISTER_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error registering ART, RC=0x%08X", Result);
    }
  }

  if (Result == CFE_SUCCESS) {
    Result = CFE_TBL_GetAddress(&LC_OperData.ARTPtr, LC_OperData.ARTHandle);

    if (Result != CFE_SUCCESS) {
      CFE_EVS_SendEvent(LC_ART_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error getting ART address, RC=0x%08X", Result);
    }
  }

  if (Result == CFE_SUCCESS) {
    LC_OperData.TableResults |= LC_ART_TBL_CREATED;
  }

  return Result;
}

/*******************************************************************************/
// Startup initialization - create WP and AP definition tables.
//
// ### THIS IS THE FOUR-WAY RETRY, AND THE LAST ARM EXISTS BECAUSE THE TWO TABLES CAN DISAGREE
//
// With the CDS enabled LC wants both definition tables CRITICAL. Each registration can fail that
// way independently, so there are three recovery points and one repair:
//
//   1. WDT critical fails -> disable the CDS, drop to CFE_TBL_OPT_DEFAULT, re-register the WDT.
//   2. ADT critical fails -> disable the CDS, drop to default, re-register the ADT.
//   3. Either returns CFE_TBL_INFO_RECOVERED_TBL -> the table came back from the CDS; record
//      CRITICAL_TBL *and* TBL_RESTORED and normalise the status to CFE_SUCCESS.
//   4. AND THEN: if the WDT ended up CRITICAL while the ADT ended up NOT_CRITICAL, LC
//      UN-REGISTERS THE WDT AND REGISTERS IT AGAIN non-critical.
//
// Step 4 is the one that is not obvious. It can only happen in ordering 2 -- the WDT succeeded as
// critical, then the ADT did not -- and it exists because a critical WDT paired with a
// non-critical ADT would let cFE Table Services restore watchpoint LIMITS from the CDS while the
// actionpoint LOGIC that reads them came from a file. NASA's comment is just "In case we created a
// critical WDT and then created a non-critical ADT"; the consequence is that LC would evaluate
// one run's thresholds with another run's expressions.
//
// AND THE RE-REGISTER IS THE ONLY STEP THAT CAN STILL FAIL FATALLY AFTER A SUCCESSFUL ONE. Its
// failure gets its own event id, LC_WDT_REREGISTER_ERR_EID, distinct from the first registration's
// -- so the event log distinguishes "LC never had a WDT" from "LC gave up a working critical WDT
// and could not get a plain one back".
I32 LC_CreateDefinitionTables()
{
  I32 Result;
  U32 DataSize;
  U32 OptionFlags = CFE_TBL_OPT_DEFAULT;

  /*
  ** If CDS is still enabled, try to register the 2 definition tables as critical
  **  (if error, continue with init - but disable CDS and re-register as non-critical)
  */
  if (LC_OperData.HaveActiveCDS) {
    OptionFlags = CFE_TBL_OPT_DEFAULT | CFE_TBL_OPT_CRITICAL;
  }

  /*
  ** Register the Watchpoint Definition Table (WDT)
  */
  DataSize = LC_MAX_WATCHPOINTS * sizeof(LC_WDTEntry_t);
  Result = CFE_TBL_Register(&LC_OperData.WDTHandle, LC_WDT_TABLENAME, DataSize, OptionFlags,
                            &LC_ValidateWDT);

  if ((LC_OperData.HaveActiveCDS) &&
      ((Result != CFE_TBL_INFO_RECOVERED_TBL) && (Result != CFE_SUCCESS))) {
    LC_OperData.HaveActiveCDS = FALSE;
    OptionFlags = CFE_TBL_OPT_DEFAULT;

    CFE_EVS_SendEvent(LC_WDT_REGISTER_CRIT_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error registering WDT as critical table, retrying with default options, RC=0x%08X",
                      Result);

    /*
    ** Re-register the Watchpoint Definition Table (WDT) non-critical
    */
    Result = CFE_TBL_Register(&LC_OperData.WDTHandle, LC_WDT_TABLENAME, DataSize, OptionFlags,
                              &LC_ValidateWDT);
  }

  if (Result == CFE_TBL_INFO_RECOVERED_TBL) {
    LC_OperData.TableResults |= LC_WDT_CRITICAL_TBL;
    LC_OperData.TableResults |= LC_WDT_TBL_RESTORED;
    Result = CFE_SUCCESS;
  } else if (Result == CFE_SUCCESS) {
    if (LC_OperData.HaveActiveCDS) {
      LC_OperData.TableResults |= LC_WDT_CRITICAL_TBL;
    } else {
      LC_OperData.TableResults |= LC_WDT_NOT_CRITICAL;
    }
  } else {
    /*
    ** Task initialization fails without this table
    **
    */
    CFE_EVS_SendEvent(LC_WDT_REGISTER_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error registering WDT, RC=0x%08X", Result);
  }

  if (Result == CFE_SUCCESS) {
    /*
    ** Register the Actionpoint Definition Table (ADT)
    */
    DataSize = LC_MAX_ACTIONPOINTS * sizeof(LC_ADTEntry_t);
    Result = CFE_TBL_Register(&LC_OperData.ADTHandle, LC_ADT_TABLENAME, DataSize, OptionFlags,
                              &LC_ValidateADT);

    if ((LC_OperData.HaveActiveCDS) &&
        ((Result != CFE_TBL_INFO_RECOVERED_TBL) && (Result != CFE_SUCCESS))) {
      LC_OperData.HaveActiveCDS = FALSE;
      OptionFlags = CFE_TBL_OPT_DEFAULT;

      CFE_EVS_SendEvent(LC_ADT_REGISTER_CRIT_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error registering ADT as critical table, retrying with default options, RC=0x%08X",
                        Result);

      /*
      ** Re-register the Actionpoint Definition Table (ADT) non-critical
      */
      Result = CFE_TBL_Register(&LC_OperData.ADTHandle, LC_ADT_TABLENAME, DataSize, OptionFlags,
                                &LC_ValidateADT);
    }

    if (Result == CFE_TBL_INFO_RECOVERED_TBL) {
      LC_OperData.TableResults |= LC_ADT_CRITICAL_TBL;
      LC_OperData.TableResults |= LC_ADT_TBL_RESTORED;
      Result = CFE_SUCCESS;
    } else if (Result == CFE_SUCCESS) {
      if (LC_OperData.HaveActiveCDS) {
        LC_OperData.TableResults |= LC_ADT_CRITICAL_TBL;
      } else {
        LC_OperData.TableResults |= LC_ADT_NOT_CRITICAL;
      }
    } else {
      /*
      ** Task initialization fails without this table
      */
      CFE_EVS_SendEvent(LC_ADT_REGISTER_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error registering ADT, RC=0x%08X", Result);
    }
  }

  if (Result == CFE_SUCCESS) {
    /*
    ** In case we created a critical WDT and then created a non-critical ADT
    */
    if (((LC_OperData.TableResults & LC_WDT_CRITICAL_TBL) == LC_WDT_CRITICAL_TBL) &&
        ((LC_OperData.TableResults & LC_ADT_NOT_CRITICAL) == LC_ADT_NOT_CRITICAL)) {
      /*
      ** Un-register the critical watchpoint Definition Table (WDT)
      */
      CFE_TBL_Unregister(LC_OperData.WDTHandle);

      /*
      ** Re-register the Watchpoint Definition Table (WDT) non-critical
      */
      DataSize = LC_MAX_WATCHPOINTS * sizeof(LC_WDTEntry_t);
      OptionFlags = CFE_TBL_OPT_DEFAULT;
      Result = CFE_TBL_Register(&LC_OperData.WDTHandle, LC_WDT_TABLENAME, DataSize, OptionFlags,
                                &LC_ValidateWDT);
      if (Result == CFE_SUCCESS) {
        LC_OperData.TableResults |= LC_WDT_NOT_CRITICAL;
      } else {
        /*
        ** Task initialization fails without this table
        */
        CFE_EVS_SendEvent(LC_WDT_REREGISTER_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Error re-registering WDT, RC=0x%08X", Result);
      }
    }
  }

  return Result;
}

/*******************************************************************************/
// Startup initialization - create Critical Data Store (CDS).
//
// ### CFE_ES_CDS_ALREADY_EXISTS IS THE WARM-BOOT PATH, NOT AN ERROR
//
// Each of the three areas is handled the same way, and the shape is worth stating because the
// naming inverts the intuition. CFE_ES_RegisterCDS returning CFE_SUCCESS means the area was
// CREATED FRESH -- a cold boot, nothing to restore. Returning CFE_ES_CDS_ALREADY_EXISTS means the
// area SURVIVED a processor reset, and only then does LC call CFE_ES_RestoreFromCDS. Anything else
// is a real failure and returns immediately, leaving the later areas unregistered.
//
// SO A FAILED *RESTORE* IS SILENT. If the area exists but RestoreFromCDS fails, the *_CDS_RESTORED
// bit simply never gets set, there is no event, and LC_TableInit's five-way test then sends LC
// down the defaults path. The event ids here cover only a failed REGISTRATION.
//
// ### THE THIRD AREA IS THE ONE WITH A CONDITION ON ITS CONTENTS
//
// WRT and ART accept any successful restore. AppData additionally requires
// `LC_AppData.CDSSavedOnExit == LC_CDS_SAVED`, because the structure it just read is the one
// carrying that flag -- NASA's comment: "only if previous session saved CDS data at least once".
// An AppData area that exists but was never written holds zeroes, and zero is not LC_CDS_SAVED,
// so the counters and the operating state are rejected rather than believed. See the block comment
// on LC_AppData_t in lc_global.HC for why that flag is cumulative rather than per-exit.
//
// AND NOTE WHICH ARGUMENT EACH RESTORE TAKES. WRT and ART pass `LC_OperData.WRTPtr` and
// `LC_OperData.ARTPtr` -- pointer VALUES, already aimed at the table memory cFE handed back from
// CFE_TBL_GetAddress. AppData passes `&LC_AppData`, the ADDRESS of a structure. The asymmetry is
// NASA's and is correct; writing `&LC_OperData.WRTPtr` would restore eight bytes of CDS over the
// pointer variable instead of filling the table.
I32 LC_CreateTaskCDS()
{
  I32 Result;
  U32 DataSize;

  /*
  ** Create CDS and try to restore Watchpoint Results Table (WRT) data
  */
  DataSize = LC_MAX_WATCHPOINTS * sizeof(LC_WRTEntry_t);
  Result = CFE_ES_RegisterCDS(&LC_OperData.WRTDataCDSHandle, DataSize, LC_WRT_CDSNAME);

  if (Result == CFE_SUCCESS) {
    /*
    ** Normal result after a power on reset (cold boot) - continue with next CDS area
    */
    LC_OperData.TableResults |= LC_WRT_CDS_CREATED;
  } else if (Result == CFE_ES_CDS_ALREADY_EXISTS) {
    /*
    ** Normal result after a processor reset (warm boot) - try to restore previous data
    */
    LC_OperData.TableResults |= LC_WRT_CDS_CREATED;

    Result = CFE_ES_RestoreFromCDS(LC_OperData.WRTPtr, LC_OperData.WRTDataCDSHandle);

    if (Result == CFE_SUCCESS) {
      LC_OperData.TableResults |= LC_WRT_CDS_RESTORED;
    }
  } else {
    CFE_EVS_SendEvent(LC_WRT_CDS_REGISTER_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error registering WRT CDS Area, RC=0x%08X", Result);
    return Result;
  }

  /*
  ** Create CDS and try to restore Actionpoint Results Table (ART) data
  */
  DataSize = LC_MAX_ACTIONPOINTS * sizeof(LC_ARTEntry_t);
  Result = CFE_ES_RegisterCDS(&LC_OperData.ARTDataCDSHandle, DataSize, LC_ART_CDSNAME);

  if (Result == CFE_SUCCESS) {
    /*
    ** Normal result after a power on reset (cold boot) - continue with next CDS area
    */
    LC_OperData.TableResults |= LC_ART_CDS_CREATED;
  } else if (Result == CFE_ES_CDS_ALREADY_EXISTS) {
    /*
    ** Normal result after a processor reset (warm boot) - try to restore previous data
    */
    LC_OperData.TableResults |= LC_ART_CDS_CREATED;

    Result = CFE_ES_RestoreFromCDS(LC_OperData.ARTPtr, LC_OperData.ARTDataCDSHandle);

    if (Result == CFE_SUCCESS) {
      LC_OperData.TableResults |= LC_ART_CDS_RESTORED;
    }
  } else {
    CFE_EVS_SendEvent(LC_ART_CDS_REGISTER_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error registering ART CDS Area, RC=0x%08X", Result);
    return Result;
  }

  /*
  ** Create CDS and try to restore Application (APP) data
  */
  DataSize = sizeof(LC_AppData_t);
  Result = CFE_ES_RegisterCDS(&LC_OperData.AppDataCDSHandle, DataSize, LC_APPDATA_CDSNAME);

  if (Result == CFE_SUCCESS) {
    /*
    ** Normal result after a power on reset (cold boot) - continue with next CDS area
    */
    LC_OperData.TableResults |= LC_APP_CDS_CREATED;
  } else if (Result == CFE_ES_CDS_ALREADY_EXISTS) {
    /*
    ** Normal result after a processor reset (warm boot) - try to restore previous data
    */
    LC_OperData.TableResults |= LC_APP_CDS_CREATED;

    Result = CFE_ES_RestoreFromCDS(&LC_AppData, LC_OperData.AppDataCDSHandle);

    if ((Result == CFE_SUCCESS) && (LC_AppData.CDSSavedOnExit == LC_CDS_SAVED)) {
      /*
      ** Success - only if previous session saved CDS data at least once
      */
      LC_OperData.TableResults |= LC_APP_CDS_RESTORED;

      /*
      ** May need to override the restored application state
      */

      // NASA'S `#if LC_STATE_WHEN_CDS_RESTORED != LC_STATE_FROM_CDS` BLOCK IS OMITTED HERE, and
      // its body was one line:
      //
      //     LC_AppData.CurrentLCState = LC_STATE_WHEN_CDS_RESTORED;
      //
      // In the stock configuration LC_STATE_WHEN_CDS_RESTORED and LC_STATE_FROM_CDS are BOTH 4,
      // so the condition is false and the override is excluded. This is the only place in LC that
      // would write CurrentLCState during a restore, so with the directive resolved this way a
      // restored CDS keeps whatever state the previous run was in. A mission wanting LC to come
      // up disabled or passive after a warm boot sets LC_STATE_WHEN_CDS_RESTORED to that state
      // and this assignment comes back.
    }
  } else {
    CFE_EVS_SendEvent(LC_APP_CDS_REGISTER_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error registering application data CDS Area, RC=0x%08X", Result);
    return Result;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Startup initialization - load default WP/AP definition tables.
//
// THE RETURN VALUE CAN BE CFE_TBL_INFO_UPDATED AND THE CALLER NORMALISES IT. Every stage here
// tests `(Result == CFE_SUCCESS) || (Result == CFE_TBL_INFO_UPDATED)` because CFE_TBL_GetAddress
// reports a pending table update as a POSITIVE non-zero status -- the same trap cs_compute.c
// documents. LC_TableInit folds it back to CFE_SUCCESS after this returns.
//
// AND THE THREE `if` CHAINS ARE NOT THE SAME TEST. Look closely: the ADT load and the final
// results-table block are guarded by the two-value test, but the two GetAddress blocks are
// guarded by plain `Result == CFE_SUCCESS`. So a WDT whose load returned CFE_TBL_INFO_UPDATED
// reaches the ADT load but SKIPS the WDT GetAddress. That is NASA's code as written and is kept;
// in practice CFE_TBL_Load on a fresh registration returns CFE_SUCCESS, so the asymmetry is
// unreachable through this path, which is precisely why nobody has had to decide whether it is
// deliberate.
//
// THE LAST BLOCK IS WHERE LC'S COLD-START STATE ACTUALLY COMES FROM: every watchpoint result
// cleared, every actionpoint result cleared, the housekeeping counters zeroed, and
// CurrentLCState set to LC_STATE_POWER_ON_RESET -- which is LC_STATE_DISABLED in this
// configuration, so a freshly started LC monitors nothing until the ground enables it.
I32 LC_LoadDefaultTables()
{
  I32 Result;

  /*
  ** Load default watchpoint definition table (WDT)
  */
  Result = CFE_TBL_Load(LC_OperData.WDTHandle, CFE_TBL_SRC_FILE, LC_WDT_FILENAME);

  if (Result == CFE_SUCCESS) {
    LC_OperData.TableResults |= LC_WDT_DEFAULT_TBL;
  } else {
    /*
    ** Task initialization fails without this table
    */
    CFE_EVS_SendEvent(LC_WDT_LOAD_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error (RC=0x%08X) Loading WDT with '%s'", Result, LC_WDT_FILENAME);
  }

  if (Result == CFE_SUCCESS) {
    /*
    ** Get a pointer to the watchpoint definition table data...
    */
    Result = CFE_TBL_GetAddress(&LC_OperData.WDTPtr, LC_OperData.WDTHandle);

    if ((Result != CFE_SUCCESS) && (Result != CFE_TBL_INFO_UPDATED)) {
      CFE_EVS_SendEvent(LC_WDT_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error getting WDT address, RC=0x%08X", Result);
    }
  }

  if ((Result == CFE_SUCCESS) || (Result == CFE_TBL_INFO_UPDATED)) {
    /*
    ** Load default actionpoint definition table (ADT)
    */
    Result = CFE_TBL_Load(LC_OperData.ADTHandle, CFE_TBL_SRC_FILE, LC_ADT_FILENAME);

    if (Result == CFE_SUCCESS) {
      LC_OperData.TableResults |= LC_ADT_DEFAULT_TBL;
    } else {
      /*
      ** Task initialization fails without this table
      */
      CFE_EVS_SendEvent(LC_ADT_LOAD_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error (RC=0x%08X) Loading ADT with '%s'", Result, LC_ADT_FILENAME);
    }
  }

  if (Result == CFE_SUCCESS) {
    /*
    ** Get a pointer to the actionpoint definition table data
    */
    Result = CFE_TBL_GetAddress(&LC_OperData.ADTPtr, LC_OperData.ADTHandle);

    if ((Result != CFE_SUCCESS) && (Result != CFE_TBL_INFO_UPDATED)) {
      CFE_EVS_SendEvent(LC_ADT_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error getting ADT address, RC=0x%08X", Result);
    }
  }

  if ((Result == CFE_SUCCESS) || (Result == CFE_TBL_INFO_UPDATED)) {
    /*
    ** Initialize the watchpoint and actionpoint result table data
    */
    LC_ResetResultsWP(0, LC_MAX_WATCHPOINTS - 1, FALSE);
    LC_OperData.TableResults |= LC_WRT_DEFAULT_DATA;

    LC_ResetResultsAP(0, LC_MAX_ACTIONPOINTS - 1, FALSE);
    LC_OperData.TableResults |= LC_ART_DEFAULT_DATA;

    /*
    ** Reset application data counters reported in housekeeping
    */
    LC_ResetCounters();

    /*
    ** Set LC operational state to configured startup value
    */
    LC_AppData.CurrentLCState = LC_STATE_POWER_ON_RESET;
    LC_OperData.TableResults |= LC_APP_DEFAULT_DATA;

    /*
    ** If CDS is enabled - try to update the 3 CDS areas managed by the LC task
    **  (continue, but disable CDS if unable to update all 3)
    */
    if (LC_OperData.HaveActiveCDS) {
      if (LC_UpdateTaskCDS() == CFE_SUCCESS) {
        LC_OperData.TableResults |= LC_CDS_UPDATED;
      } else {
        LC_OperData.HaveActiveCDS = FALSE;
      }
    }
  }

  return Result;
}

#endif
