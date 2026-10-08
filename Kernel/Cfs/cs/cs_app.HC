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
// CHECKSUM'S APPLICATION LAYER -- the 1:1 translation of NASA's fsw/src/cs_app.c, 371 lines and
// four functions, plus the global instance NASA defines at its top (which this port keeps in
// cs_global.HC, beside its type, for the reason recorded there).
//
// FOUR FUNCTIONS AND THREE JOBS: the main loop, the one-time init, and the two halves of the
// Critical Data Store. CS_AppMain and CS_AppInit are the shape every cFS app shares; the CDS pair
// is CS's own, and it is why CS comes back after a processor reset still watching what the ground
// last told it to watch rather than what the platform config says.
//
// THE CDS IS SIX BYTES. Four table states plus the OS and cFE core states -- not the baselines, not
// the tables themselves. A checksum is cheap to recompute and a ground decision is not, so what
// survives a reset is the DECISION.
#ifndef CS_APP_HC
#define CS_APP_HC

// Six: four tables + OS CS + cFE core number of checksum states for CDS
#define CS_NUM_DATA_STORE_STATES 6

// CS_AppPipe is cs_dispatch.HC's, and it is one of the two functions that close CS's seven-source
// cycle -- cs_app.c calls it and it calls back into all five command files. NASA reaches it through
// cs_dispatch.h.
I32 CS_AppPipe(CFE_SB_Buffer *BufPtr);

/*******************************************************************************/
// CS application entry point and main process loop
//
// THE PERFORMANCE MARKER BRACKETS THE WAIT, INVERTED. PerfLogExit is called BEFORE
// CFE_SB_ReceiveBuffer and PerfLogEntry after it, so the interval the ground sees is the time CS
// spends WORKING and not the time it spends blocked -- which is the opposite of what a reader
// expects from an Entry/Exit pair and is why the two calls look misplaced.
//
// AND A TIMEOUT IS NOT AN ERROR: CFE_SB_TIME_OUT and CFE_SB_NO_MESSAGE are the normal case, and
// they are what drives CS_HandleRoutineTableUpdates. A cycle with no command still has to sweep the
// six wrappers for ground table loads.
U0 CS_AppMain()
{
  I32 Result = 0;
  CFE_SB_Buffer *BufPtr = NULL;

  // Performance Log (start time counter)
  CFE_ES_PerfLogEntry(CS_APPMAIN_PERF_ID);

  // Perform application-specific initialization
  Result = CS_AppInit();

  // Check for start-up error
  if (Result != CFE_SUCCESS) {
    // Set request to terminate main loop
    CS_AppData.RunStatus = CFE_ES_RunStatus_APP_ERROR;
  }

  CFE_ES_WaitForStartupSync(CS_STARTUP_TIMEOUT);

  // Main process loop
  while (CFE_ES_RunLoop(&CS_AppData.RunStatus)) {
    // Performance Log (stop time counter)
    CFE_ES_PerfLogExit(CS_APPMAIN_PERF_ID);

    // Wait for the next Software Bus message
    Result = CFE_SB_ReceiveBuffer(&BufPtr, CS_AppData.CmdPipe, CS_WAKEUP_TIMEOUT);

    // Performance Log (start time counter)
    CFE_ES_PerfLogEntry(CS_APPMAIN_PERF_ID);

    if (Result == CFE_SUCCESS && BufPtr != NULL) {
      // Process Software Bus message
      Result = CS_AppPipe(BufPtr);
    } else if (Result == CFE_SB_TIME_OUT || Result == CFE_SB_NO_MESSAGE) {
      Result = CS_HandleRoutineTableUpdates();
    } else {
      // All other cases are caught by the following condition
      //    Result != CFE_SUCCESS
    }

    //
    // Note: If there were some reason to exit the task
    //       normally (without error) then we would set
    //       RunStatus = CFE_ES_APP_EXIT
    //
    if (Result != CFE_SUCCESS) {
      // Set request to terminate main loop
      CS_AppData.RunStatus = CFE_ES_RunStatus_APP_ERROR;
    }
  } // end run loop

  // Check for "fatal" process error
  if (CS_AppData.RunStatus == CFE_ES_RunStatus_APP_ERROR ||
      CS_AppData.RunStatus == CFE_ES_RunStatus_SYS_EXCEPTION) {
    // Send an error event with run status and result
    CFE_EVS_SendEvent(CS_EXIT_ERR_EID, CFE_EVS_EventType_ERROR,
                      "App terminating, RunStatus:0x%08X, RC:0x%08X", CS_AppData.RunStatus, Result);
  } else {
    // Send an informational event describing the reason for the termination
    CFE_EVS_SendEvent(CS_EXIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "App terminating, RunStatus:0x%08X", CS_AppData.RunStatus);
  }

  // In case cFE Event Services is not working
  CFE_ES_WriteToSysLog("CS App terminating, RunStatus:0x%08X, RC:0x%08X\n", CS_AppData.RunStatus,
                       Result);

  // Performance Log (stop time counter)
  CFE_ES_PerfLogExit(CS_APPMAIN_PERF_ID);

  // Let cFE kill the task (and child task)
  CFE_ES_ExitApp(CS_AppData.RunStatus);
}

/*******************************************************************************/
// CS Application initialization function
//
// THE ORDER IS A CHAIN OF `if (Result == CFE_SUCCESS)`, not nesting, and each link is a different
// kind of thing: register for events, zero the whole global, stand up the bus, fill the four
// default tables, take the poweron states from the platform config, let the CDS OVERRIDE them,
// register the eight tables, read the two code segments, and only then set the app enabled.
//
// NOTE WHAT COMES BEFORE THE CDS READ: the six states are set from the platform configuration
// FIRST and CS_CreateRestoreStatesFromCDS overwrites them if a store survives. So a cold boot
// follows the config and a warm one follows the ground. The order is the whole feature.
I32 CS_AppInit()
{
  I32 Result = CFE_SUCCESS;

  // Register for event services
  Result = CFE_EVS_Register(NULL, 0, 0);

  if (Result != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CS App: Error Registering For Event Services, RC = 0x%08X\n", Result);
  } else {
    // Zero out all data in CS_AppData, including the housekeeping data
    MemSet(&CS_AppData, 0, sizeof(CS_AppData_t));

    CS_AppData.RunStatus = CFE_ES_RunStatus_APP_RUN;

    Result = CS_SbInit();
  }

  if (Result == CFE_SUCCESS) {
    // Set up default tables in memory
    CS_InitializeDefaultTables();

    CS_AppData.HkPacket.Payload.EepromCSState = CS_EEPROM_TBL_POWERON_STATE;
    CS_AppData.HkPacket.Payload.MemoryCSState = CS_MEMORY_TBL_POWERON_STATE;
    CS_AppData.HkPacket.Payload.AppCSState = CS_APPS_TBL_POWERON_STATE;
    CS_AppData.HkPacket.Payload.TablesCSState = CS_TABLES_TBL_POWERON_STATE;

    CS_AppData.HkPacket.Payload.OSCSState = CS_OSCS_CHECKSUM_STATE;
    CS_AppData.HkPacket.Payload.CfeCoreCSState = CS_CFECORE_CHECKSUM_STATE;

    // NASA guards this call with `#if (CS_PRESERVE_STATES_ON_PROCESSOR_RESET == true)`. The value
    // IS true in this configuration, so the call is present -- and it has to be written WITHOUT the
    // guard, because `#if <expr>` is unconditionally true in this compiler (limit #19) and a guard
    // that cannot be false is worse than none: it would read as a choice that was checked.
    Result = CS_CreateRestoreStatesFromCDS();
  }

  if (Result == CFE_SUCCESS) {
    Result = CS_InitAllTables();
  }

  if (Result == CFE_SUCCESS) {
    CS_InitSegments();

    // initialize the place to ostart background checksumming
    CS_AppData.HkPacket.Payload.CurrentCSTable = 0;
    CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;

    // Initial settings for the CS Application
    // the rest of the tables are initialized in CS_TableInit
    CS_AppData.HkPacket.Payload.ChecksumState = CS_ChecksumState_ENABLED;

    CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
    CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;

    CS_AppData.MaxBytesPerCycle = CS_DEFAULT_BYTES_PER_CYCLE;

    // Application startup event message
    Result = CFE_EVS_SendEvent(CS_INIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                               "CS Initialized. Version %d.%d.%d.%d", CS_MAJOR_VERSION,
                               CS_MINOR_VERSION, CS_REVISION, CS_MISSION_REV);
  }
  return Result;
}

/*******************************************************************************/
// CS_CreateCDS() - create CS storage area in CDS
//
// THREE OUTCOMES FROM ONE CALL, and CFE_ES_CDS_ALREADY_EXISTS is the INTERESTING one rather than an
// error: a fresh store is WRITTEN from the states just set, a surviving store is READ and overwrites
// them, and anything else gives up. The ground's last decision outliving a processor reset is this
// one `else if`.
//
// AND A BROKEN CDS IS NOT FATAL. The handle is set to CFE_ES_CDS_BAD_HANDLE so CS_UpdateCDS stops
// trying, the six states go back to the platform configuration, an event says so -- and the function
// returns CFE_SUCCESS, so CS_AppInit carries on. NASA's comment says it: "CDS errors are not fatal".
I32 CS_CreateRestoreStatesFromCDS()
{
  // Store task ena/dis state of tables in CDS
  U8 DataStoreBuffer[CS_NUM_DATA_STORE_STATES];
  I32 Result;
  I32 EventId = 0;

  MemSet(DataStoreBuffer, 0, CS_NUM_DATA_STORE_STATES);

  //
  // Request for CDS area from cFE Executive Services...
  //
  Result = CFE_ES_RegisterCDS(&CS_AppData.DataStoreHandle, CS_NUM_DATA_STORE_STATES, CS_CDS_NAME);

  if (Result == CFE_SUCCESS) {
    //
    // New CDS area - write to Critical Data Store...
    //
    DataStoreBuffer[0] = CS_AppData.HkPacket.Payload.EepromCSState;
    DataStoreBuffer[1] = CS_AppData.HkPacket.Payload.MemoryCSState;
    DataStoreBuffer[2] = CS_AppData.HkPacket.Payload.AppCSState;
    DataStoreBuffer[3] = CS_AppData.HkPacket.Payload.TablesCSState;

    DataStoreBuffer[4] = CS_AppData.HkPacket.Payload.OSCSState;
    DataStoreBuffer[5] = CS_AppData.HkPacket.Payload.CfeCoreCSState;

    Result = CFE_ES_CopyToCDS(CS_AppData.DataStoreHandle, DataStoreBuffer);

    if (Result != CFE_SUCCESS) {
      EventId = CS_CR_CDS_CPY_ERR_EID;
    }
  } else if (Result == CFE_ES_CDS_ALREADY_EXISTS) {
    //
    // Pre-existing CDS area - read from Critical Data Store...
    //
    Result = CFE_ES_RestoreFromCDS(DataStoreBuffer, CS_AppData.DataStoreHandle);

    if (Result == CFE_SUCCESS) {
      CS_AppData.HkPacket.Payload.EepromCSState = DataStoreBuffer[0];
      CS_AppData.HkPacket.Payload.MemoryCSState = DataStoreBuffer[1];
      CS_AppData.HkPacket.Payload.AppCSState = DataStoreBuffer[2];
      CS_AppData.HkPacket.Payload.TablesCSState = DataStoreBuffer[3];

      CS_AppData.HkPacket.Payload.OSCSState = DataStoreBuffer[4];
      CS_AppData.HkPacket.Payload.CfeCoreCSState = DataStoreBuffer[5];
    } else {
      EventId = CS_CR_CDS_RES_ERR_EID;
    }
  } else {
    EventId = CS_CR_CDS_REG_ERR_EID;
  }

  if (Result != CFE_SUCCESS) {
    //
    // CDS is broken - prevent further errors...
    //
    CS_AppData.DataStoreHandle = CFE_ES_CDS_BAD_HANDLE;

    // Use states from platform configuration
    CS_AppData.HkPacket.Payload.EepromCSState = CS_EEPROM_TBL_POWERON_STATE;
    CS_AppData.HkPacket.Payload.MemoryCSState = CS_MEMORY_TBL_POWERON_STATE;
    CS_AppData.HkPacket.Payload.AppCSState = CS_APPS_TBL_POWERON_STATE;
    CS_AppData.HkPacket.Payload.TablesCSState = CS_TABLES_TBL_POWERON_STATE;

    CS_AppData.HkPacket.Payload.OSCSState = CS_OSCS_CHECKSUM_STATE;
    CS_AppData.HkPacket.Payload.CfeCoreCSState = CS_CFECORE_CHECKSUM_STATE;

    CFE_EVS_SendEvent(EventId, CFE_EVS_EventType_ERROR,
                      "Critical Data Store access error = 0x%08X", Result);
    //
    // CDS errors are not fatal - CS can still run...
    //
    Result = CFE_SUCCESS;
  }

  return Result;
}

/*******************************************************************************/
// CS_UpdateCDS() - update DS storage area in CDS
//
// THE OTHER FUNCTION THAT CLOSES CS'S SEVEN-SOURCE CYCLE: all five command files call this, and
// cs_app.c calls cs_dispatch.c's CS_AppPipe, which calls all five. Two edges, forty others that are
// a dispatcher calling its own handlers.
//
// IT IS SILENT WHEN THERE IS NO STORE. `CFE_RESOURCEID_TEST_DEFINED` is false after a failed
// registration, so every enable/disable command still works and simply does not persist -- which is
// what makes a broken CDS non-fatal everywhere and not just in CS_AppInit.
U0 CS_UpdateCDS()
{
  // Store table ena/dis state in CDS
  U8 DataStoreBuffer[CS_NUM_DATA_STORE_STATES];
  I32 Result;

  //
  // Handle is defined when CDS is active...
  //
  if (CFE_ResourceId_IsDefined(CS_AppData.DataStoreHandle)) {
    //
    // Copy ena/dis states of tables to the data array...
    //
    DataStoreBuffer[0] = CS_AppData.HkPacket.Payload.EepromCSState;
    DataStoreBuffer[1] = CS_AppData.HkPacket.Payload.MemoryCSState;
    DataStoreBuffer[2] = CS_AppData.HkPacket.Payload.AppCSState;
    DataStoreBuffer[3] = CS_AppData.HkPacket.Payload.TablesCSState;

    DataStoreBuffer[4] = CS_AppData.HkPacket.Payload.OSCSState;
    DataStoreBuffer[5] = CS_AppData.HkPacket.Payload.CfeCoreCSState;

    //
    // Update CS portion of Critical Data Store...
    //
    Result = CFE_ES_CopyToCDS(CS_AppData.DataStoreHandle, DataStoreBuffer);

    if (Result != CFE_SUCCESS) {
      CFE_EVS_SendEvent(CS_UPDATE_CDS_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Critical Data Store access error = 0x%08X", Result);
      //
      // CDS is broken - prevent further errors...
      //
      CS_AppData.DataStoreHandle = CFE_ES_CDS_BAD_HANDLE;
    }
  }
}
#endif
