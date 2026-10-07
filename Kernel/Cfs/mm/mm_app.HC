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
// 1:1 translation of NASA's vendor/MM/fsw/src/mm_app.c -- MM's entry point, its run loop and
// its initialisation. THE LAST SOURCE IN THE APP: with this gated, Memory Manager is 100%.
//
// MM IS A SIMPLER APP THAN MD AND THIS FILE IS WHERE THAT SHOWS. NASA says so in four comments
// of its own: MM uses no critical data store, does not distinguish a power-on reset from a
// processor reset, registers no cFE TABLES, and creates no CDS. So MM_AppInit is five cFE calls
// -- register for events, initialise the housekeeping packet, create a pipe, subscribe twice --
// and nothing else. MD's equivalent registers four dwell tables and recovers them from the CDS.
//
// THE RUN LOOP'S PERFORMANCE STAMPS ARE INSIDE OUT, and that is deliberate rather than a slip:
// PerfLogEntry is taken BEFORE the loop and PerfLogExit at the TOP of each iteration, so the
// interval the ground measures is "MM awake", with the pend on CFE_SB_ReceiveBuffer outside it.
// An app that stamped the other way round would report a duty cycle of ~100% while idle.
//
// AND A TIMEOUT IS NOT AN ERROR. The loop treats CFE_SB_TIME_OUT and CFE_SB_NO_MESSAGE as "no
// action, but also no error" and exits on anything else -- so MM wakes every
// MM_INTERNAL_SB_TIMEOUT milliseconds whether or not a command arrived, and a genuinely broken
// pipe takes the app down with an event.
#ifndef MM_APP_HC
#define MM_APP_HC

// --- what this file needs from elsewhere -----------------------------------------------------
// MM_TaskPipe is in mm_dispatch.HC, which has no call back into this file -- so unlike MD's pair
// these two are ACYCLIC and the include order alone resolves them. MM_SendHkCmd lives in
// mm_cmds.c rather than in the app, which is the difference.

/*******************************************************************************/
// MM application entry point and main process loop.
U0 MM_AppMain()
{
  I32 Status = CFE_SUCCESS;
  CFE_SB_Buffer *BufPtr = NULL;

  /*
  ** Create the first Performance Log entry
  */
  CFE_ES_PerfLogEntry(MM_APPMAIN_PERF_ID);

  /*
  ** Perform application specific initialization
  */
  Status = MM_AppInit();
  if (Status != CFE_SUCCESS) {
    MM_AppData.RunStatus = CFE_ES_RunStatus_APP_ERROR;
  }

  /*
  ** Application main loop
  */
  while (CFE_ES_RunLoop(&MM_AppData.RunStatus) == TRUE) {
    /*
    ** Performance Log exit stamp
    */
    CFE_ES_PerfLogExit(MM_APPMAIN_PERF_ID);

    /*
    ** Pend on the arrival of the next Software Bus message
    */
    Status = CFE_SB_ReceiveBuffer(&BufPtr, MM_AppData.CmdPipe, MM_INTERNAL_SB_TIMEOUT);
    /*
    ** Performance Log entry stamp
    */
    CFE_ES_PerfLogEntry(MM_APPMAIN_PERF_ID);

    /*
    ** Check the return status from the software bus
    */
    if (Status == CFE_SUCCESS && BufPtr != NULL) {
      /* Process Software Bus message */
      MM_TaskPipe(BufPtr);
    } else if (Status == CFE_SB_TIME_OUT || Status == CFE_SB_NO_MESSAGE) {
      /* No action, but also no error */
    } else {
      /*
      ** Exit on pipe read error
      */
      CFE_EVS_SendEvent(MM_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "SB Pipe Read Error, App will exit. RC = 0x%08X", Status);

      MM_AppData.RunStatus = CFE_ES_RunStatus_APP_ERROR;
    }
  } /* end CFS_ES_RunLoop while */

  /*
  ** Performance Log exit stamp
  */
  CFE_ES_PerfLogExit(MM_APPMAIN_PERF_ID);

  /*
  ** Exit the application
  */
  CFE_ES_ExitApp(MM_AppData.RunStatus);
}

/*******************************************************************************/
// MM initialization.
//
// EVERY FAILURE RETURNS EARLY AND THE CALLER TURNS THAT INTO APP_ERROR, so the run loop never
// starts -- which means a pipe that could not be created cannot be received from. The FIRST
// failure is the one that cannot send an event, because event services are not registered yet:
// it goes to the system log instead. That asymmetry is the only reason CFE_ES_WriteToSysLog
// appears in this file.
I32 MM_AppInit()
{
  I32 Status = CFE_SUCCESS;

  /*
  ** MM doesn't use the critical data store and
  ** doesn't need to identify power on vs. processor resets.
  ** If this changes add it here as shown in the qq_app.c template
  */

  /*
  ** Setup the RunStatus variable
  */
  MM_AppData.RunStatus = CFE_ES_RunStatus_APP_RUN;

  /*
  ** Initialize application command execution counters
  */
  MM_AppData.HkTlm.Payload.CommandCounter = 0;
  MM_AppData.HkTlm.Payload.CommandErrorCounter = 0;

  /*
  ** Register for event services
  */
  Status = CFE_EVS_Register(NULL, 0, CFE_EVS_EventFilter_BINARY);

  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("MM App: Error Registering For Event Services, RC = 0x%08X\n", Status);
    return Status;
  }

  /*
  ** Initialize the local housekeeping telemetry packet (clear user data area)
  */
  CFE_MSG_Init(&MM_AppData.HkTlm.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(MM_HK_TLM_MID),
               sizeof(MM_HkTlm_t));

  /*
  ** Create Software Bus message pipe
  */
  Status = CFE_SB_CreatePipe(&MM_AppData.CmdPipe, MM_INTERNAL_CMD_PIPE_DEPTH,
                             MM_INTERNAL_CMD_PIPE_NAME);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(MM_CR_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Creating SB Pipe, RC = 0x%08X", Status);
    return Status;
  }

  /*
  ** Subscribe to Housekeeping request commands
  */
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(MM_SEND_HK_MID), MM_AppData.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(MM_HK_SUB_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Subscribing to HK Request, RC = 0x%08X", Status);
    return Status;
  }

  /*
  ** Subscribe to MM ground command packets
  */
  Status = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(MM_CMD_MID), MM_AppData.CmdPipe);
  if (Status != CFE_SUCCESS) {
    CFE_EVS_SendEvent(MM_CMD_SUB_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error Subscribing to MM Command, RC = 0x%08X", Status);
    return Status;
  }

  /*
  ** MM doesn't use tables. If this changes add table registration
  ** and initialization here as shown in the qq_app.c template
  */

  /*
  ** MM doesn't use the critical data store. If this changes add CDS
  ** creation here as shown in the qq_app.c template
  */

  /*
  ** Initialize MM housekeeping information
  */
  MM_ResetHk();

  /*
  ** Application startup event message
  */
  CFE_EVS_SendEvent(MM_INIT_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "MM Initialized. Version %d.%d.%d.%d", MM_MAJOR_VERSION, MM_MINOR_VERSION,
                    MM_REVISION, MM_INTERNAL_MISSION_REV);

  return CFE_SUCCESS;
}
#endif
