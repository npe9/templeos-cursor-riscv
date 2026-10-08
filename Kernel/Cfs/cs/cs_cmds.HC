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
// CHECKSUM'S GENERAL COMMANDS -- the 1:1 translation of NASA's fsw/src/cs_cmds.c, 625 lines and
// sixteen functions: housekeeping, no-op, reset, the background cycle, the two all-CS switches, the
// cFE core and OS pairs, their two baseline reports and two recomputes, and the one-shot pair.
//
// THE BACKGROUND CYCLE IS THE APP'S HEARTBEAT, and it is the only function here that is not a
// ground command in spirit: the scheduler sends it on its own MsgId, and it loops over the six
// checksum types until ONE of them says the byte budget is spent. Each CS_Background* returns that
// answer, which is why the loop has no counter -- the six functions move
// CurrentCSTable themselves.
//
// `#if (CS_PRESERVE_STATES_ON_PROCESSOR_RESET == true) CS_UpdateCDS(); #endif` APPEARS TEN TIMES IN
// THIS FILE and is translated as a bare call every time. The value IS true in this configuration, so
// the call is present -- and the guard has to go rather than be written out, because `#if <expr>` is
// unconditionally true in this compiler (limit #19): a guard that cannot be false reads as a choice
// that was checked. Said once here instead of ten times below.
#ifndef CS_CMDS_HC
#define CS_CMDS_HC

/*******************************************************************************/
// Housekeeping, and it does TWO things: transmits the packet and sweeps the six wrappers for ground
// table loads. The sweep is here as well as in CS_AppMain's timeout arm, so a busy pipe that never
// times out still picks up a new table.
I32 CS_SendHkCmd(CS_SendHkCmd_t *CmdPtr)
{
  CFE_SB_TimeStampMsg(&CS_AppData.HkPacket.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&CS_AppData.HkPacket.TelemetryHeader.Msg, TRUE);

  CS_HandleRoutineTableUpdates();

  return CFE_SUCCESS;
}

/*******************************************************************************/
// No-op, which answers with the version. The only command in CS whose entire purpose is to prove
// the app is alive and which build is running.
I32 CS_NoopCmd(CS_NoopCmd_t *CmdPtr)
{
  CS_AppData.HkPacket.Payload.CommandCounter++;

  CFE_EVS_SendEvent(CS_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "No-op command. Version %d.%d.%d.%d", CS_MAJOR_VERSION, CS_MINOR_VERSION,
                    CS_REVISION, CS_MISSION_REV);

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Reset counters -- NINE of them, and NOT the baselines. A reset clears what CS has COUNTED and
// leaves what it has MEASURED, so the ground can zero an error tally without losing the reference
// every future comparison is against.
//
// AND IT DOES NOT INCREMENT CommandCounter, which it has just zeroed. Every other command in CS
// does. NASA's, and deliberate: the count after a reset is zero, not one.
I32 CS_ResetCountersCmd(CS_ResetCountersCmd_t *CmdPtr)
{
  CS_AppData.HkPacket.Payload.CommandCounter = 0;
  CS_AppData.HkPacket.Payload.CommandErrorCounter = 0;
  CS_AppData.HkPacket.Payload.EepromCSErrCounter = 0;
  CS_AppData.HkPacket.Payload.MemoryCSErrCounter = 0;
  CS_AppData.HkPacket.Payload.TablesCSErrCounter = 0;
  CS_AppData.HkPacket.Payload.AppCSErrCounter = 0;
  CS_AppData.HkPacket.Payload.CfeCoreCSErrCounter = 0;
  CS_AppData.HkPacket.Payload.OSCSErrCounter = 0;
  CS_AppData.HkPacket.Payload.PassCounter = 0;

  CFE_EVS_SendEvent(CS_RESET_INF_EID, CFE_EVS_EventType_DEBUG, "Reset Counters command recieved");

  return CFE_SUCCESS;
}

/*******************************************************************************/
// The background cycle.
//
// THE `EndOfList` TEST LOOKS WRONG AND IS NOT. It is set when CurrentCSTable reaches
// CS_NUM_TABLES - 1 -- the LAST type -- and it is tested at the TOP of the next iteration, so the
// loop still runs that last type once and then stops. NASA's comment says why: the cycle must not
// finish one table and immediately start another, because that could put the pass over the
// byte budget.
//
// AND THE `default:` ARM IS A RECOVERY, not dead code: a CurrentCSTable outside 0..5 -- which only a
// corrupted housekeeping packet produces -- rewinds to the start and counts a pass. It is the one
// place other than CS_GoToNextTable that touches PassCounter.
I32 CS_BackgroundCheckCycleCmd(CS_BackgroundCheckCycleCmd_t *CmdPtr)
{
  Bool DoneWithCycle = FALSE;
  Bool EndOfList = FALSE;

  if (CS_AppData.HkPacket.Payload.ChecksumState == CS_ChecksumState_ENABLED) {
    DoneWithCycle = FALSE;
    EndOfList = FALSE;

    if (CS_AppData.HkPacket.Payload.RecomputeInProgress == TRUE ||
        CS_AppData.HkPacket.Payload.OneShotInProgress == TRUE) {
      CFE_EVS_SendEvent(CS_BKGND_COMPUTE_PROG_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Skipping background cycle. Recompute or oneshot in progress.");
      DoneWithCycle = TRUE;
    }

    // We check for end of list because we don't know the
    //    order in which the table entries are defined, and we don't
    //    want to keep looping through the list
    while (DoneWithCycle != TRUE && EndOfList != TRUE) {
      // We need to check the current table at the start, because
      //    it is updated (and possibly reset to zero) inside each
      //    function called
      if (CS_AppData.HkPacket.Payload.CurrentCSTable >= CS_NUM_TABLES - 1) {
        EndOfList = TRUE;
      }

      // Call the appropriate background function based on the current table
      //    value.  The value is updated inside each function
      switch (CS_AppData.HkPacket.Payload.CurrentCSTable) {
        case CS_ChecksumType_CFECORE:
          DoneWithCycle = CS_BackgroundCfeCore();
          break;
        case CS_ChecksumType_OSCORE:
          DoneWithCycle = CS_BackgroundOS();
          break;
        case CS_ChecksumType_EEPROM_TABLE:
          DoneWithCycle = CS_BackgroundEeprom();
          break;
        case CS_ChecksumType_MEMORY_TABLE:
          DoneWithCycle = CS_BackgroundMemory();
          break;
        case CS_ChecksumType_TABLES_TABLE:
          DoneWithCycle = CS_BackgroundTables();
          break;
        case CS_ChecksumType_APP_TABLE:
          DoneWithCycle = CS_BackgroundApp();
          break;
        default:
          CS_AppData.HkPacket.Payload.CurrentCSTable = 0;
          CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
          CS_AppData.HkPacket.Payload.PassCounter++;
          DoneWithCycle = TRUE;
          break;
      } // end switch
    }   // end while
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable ALL background checksumming, and the six Zero*TempValues calls are the point: a partial
// checksum left behind would be resumed when the ground re-enabled, producing a baseline computed
// half before and half after whatever the ground was doing in between. NASA's comment says it --
// "they don't start with a half-old value".
//
// THE ENABLE TWIN DOES NOT ZERO ANYTHING, which is the asymmetry: disabling is where the partial
// state becomes dangerous.
I32 CS_DisableAllCSCmd(CS_DisableAllCSCmd_t *CmdPtr)
{
  CS_AppData.HkPacket.Payload.ChecksumState = CS_ChecksumState_DISABLED;

  // zero out the temp values, so that when the checksums are re-enabled,
  //  they don't start with a half-old value
  CS_ZeroEepromTempValues();
  CS_ZeroMemoryTempValues();
  CS_ZeroTablesTempValues();
  CS_ZeroAppTempValues();
  CS_ZeroCfeCoreTempValues();
  CS_ZeroOSTempValues();

  CS_AppData.HkPacket.Payload.CommandCounter++;

  CFE_EVS_SendEvent(CS_DISABLE_ALL_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Background Checksumming Disabled");

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable ALL background checksumming. NOTE IT DOES NOT CALL CS_UpdateCDS, and neither does its
// disable twin: the APP-WIDE state is not one of the six bytes the CDS preserves. Only the per-type
// states survive a reset, so "checksumming off entirely" comes back ON. NASA's, and the six
// per-type commands below DO persist.
I32 CS_EnableAllCSCmd(CS_EnableAllCSCmd_t *CmdPtr)
{
  CS_AppData.HkPacket.Payload.ChecksumState = CS_ChecksumState_ENABLED;

  CS_AppData.HkPacket.Payload.CommandCounter++;

  CFE_EVS_SendEvent(CS_ENABLE_ALL_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Background Checksumming Enabled");

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable cFE core checksumming. The DISABLE of each pair zeroes that type's partial state; the
// ENABLE does not. Both persist to the CDS.
I32 CS_DisableCfeCoreCmd(CS_DisableCfeCoreCmd_t *CmdPtr)
{
  CS_AppData.HkPacket.Payload.CfeCoreCSState = CS_ChecksumState_DISABLED;
  CS_ZeroCfeCoreTempValues();

  CS_UpdateCDS();

  CFE_EVS_SendEvent(CS_DISABLE_CFECORE_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Checksumming of cFE Core is Disabled");

  CS_AppData.HkPacket.Payload.CommandCounter++;

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable cFE core checksumming.
I32 CS_EnableCfeCoreCmd(CS_EnableCfeCoreCmd_t *CmdPtr)
{
  CS_AppData.HkPacket.Payload.CfeCoreCSState = CS_ChecksumState_ENABLED;

  CS_UpdateCDS();

  CFE_EVS_SendEvent(CS_ENABLE_CFECORE_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Checksumming of cFE Core is Enabled");

  CS_AppData.HkPacket.Payload.CommandCounter++;

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable OS code segment checksumming.
I32 CS_DisableOSCmd(CS_DisableOSCmd_t *CmdPtr)
{
  CS_AppData.HkPacket.Payload.OSCSState = CS_ChecksumState_DISABLED;
  CS_ZeroOSTempValues();

  CS_UpdateCDS();

  CFE_EVS_SendEvent(CS_DISABLE_OS_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Checksumming of OS code segment is Disabled");

  CS_AppData.HkPacket.Payload.CommandCounter++;

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable OS code segment checksumming.
I32 CS_EnableOSCmd(CS_EnableOSCmd_t *CmdPtr)
{
  CS_AppData.HkPacket.Payload.OSCSState = CS_ChecksumState_ENABLED;

  CS_UpdateCDS();

  CFE_EVS_SendEvent(CS_ENABLE_OS_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Checksumming of OS code segment is Enabled");

  CS_AppData.HkPacket.Payload.CommandCounter++;

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Report the cFE core baseline, and `ComputedYet` is the whole command: a baseline that has not been
// measured is not zero, it is ABSENT, and the two cases are different events. A ground display that
// read the number alone could not tell "the checksum is 0" from "there is no checksum".
I32 CS_ReportBaselineCfeCoreCmd(CS_ReportBaselineCfeCoreCmd_t *CmdPtr)
{
  CS_Res_EepromMemory_Table_Entry_t *CfeCoreCodeSeg = CS_GetCfeCoreCodeSegResTable();

  if (CfeCoreCodeSeg->ComputedYet == TRUE) {
    CFE_EVS_SendEvent(CS_BASELINE_CFECORE_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Baseline of cFE Core is 0x%08X", CfeCoreCodeSeg->ComparisonValue);
  } else {
    CFE_EVS_SendEvent(CS_NO_BASELINE_CFECORE_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Baseline of cFE Core has not been computed yet");
  }
  CS_AppData.HkPacket.Payload.CommandCounter++;

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Report the OS code segment baseline.
I32 CS_ReportBaselineOSCmd(CS_ReportBaselineOSCmd_t *CmdPtr)
{
  CS_Res_EepromMemory_Table_Entry_t *OSCodeSeg = CS_GetOSCodeSegResTable();

  if (OSCodeSeg->ComputedYet == TRUE) {
    CFE_EVS_SendEvent(CS_BASELINE_OS_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Baseline of OS code segment is 0x%08X", OSCodeSeg->ComparisonValue);
  } else {
    CFE_EVS_SendEvent(CS_NO_BASELINE_OS_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Baseline of OS code segment has not been computed yet");
  }
  CS_AppData.HkPacket.Payload.CommandCounter++;

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Recompute the cFE core baseline, out of line in a child task.
//
// THE FLAG IS SET BEFORE THE TASK IS CREATED and cleared again if the create fails, which is the
// only safe order: a child task that started would otherwise find RecomputeInProgress false and a
// second recompute could be accepted behind it. Both failure arms are distinct events -- the create
// failed, against the child task is already busy -- because they are different problems for the
// ground.
I32 CS_RecomputeBaselineCfeCoreCmd(CS_RecomputeBaselineCfeCoreCmd_t *CmdPtr)
{
  U32 ChildTaskID; // CFE_ES_TaskId_t
  I32 Status;

  if (CS_AppData.HkPacket.Payload.RecomputeInProgress == FALSE &&
      CS_AppData.HkPacket.Payload.OneShotInProgress == FALSE) {
    // make sure we don't try to do more than one recompute at a time
    CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;

    // fill in child task variables
    CS_AppData.ChildTaskTable = CS_ChecksumType_CFECORE;
    CS_AppData.ChildTaskEntryID = 0;
    CS_AppData.RecomputeEepromMemoryEntryPtr = CS_GetCfeCoreCodeSegResTable();

    Status = CFE_ES_CreateChildTask(&ChildTaskID, CS_RECOMP_CFECORE_TASK_NAME,
                                    &CS_RecomputeEepromMemoryChildTask, NULL,
                                    CFE_PLATFORM_ES_DEFAULT_STACK_SIZE, CS_CHILD_TASK_PRIORITY, 0);
    if (Status == CFE_SUCCESS) {
      CFE_EVS_SendEvent(CS_RECOMPUTE_CFECORE_STARTED_DBG_EID, CFE_EVS_EventType_DEBUG,
                        "Recompute of cFE core started");
      CS_AppData.HkPacket.Payload.CommandCounter++;
    } else { // child task creation failed
      CFE_EVS_SendEvent(CS_RECOMPUTE_CFECORE_CREATE_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Recompute cFE core failed, CFE_ES_CreateChildTask returned: 0x%08X",
                        Status);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
      CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
    }
  } else {
    CFE_EVS_SendEvent(CS_RECOMPUTE_CFECORE_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Recompute cFE core failed: child task in use");
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Recompute the OS code segment baseline. Line-for-line the cFE core twin with a different type, a
// different task name and three different event ids.
I32 CS_RecomputeBaselineOSCmd(CS_RecomputeBaselineOSCmd_t *CmdPtr)
{
  U32 ChildTaskID; // CFE_ES_TaskId_t
  I32 Status;

  if (CS_AppData.HkPacket.Payload.RecomputeInProgress == FALSE &&
      CS_AppData.HkPacket.Payload.OneShotInProgress == FALSE) {
    CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;

    CS_AppData.ChildTaskTable = CS_ChecksumType_OSCORE;
    CS_AppData.ChildTaskEntryID = 0;
    CS_AppData.RecomputeEepromMemoryEntryPtr = CS_GetOSCodeSegResTable();

    Status = CFE_ES_CreateChildTask(&ChildTaskID, CS_RECOMP_OS_TASK_NAME,
                                    &CS_RecomputeEepromMemoryChildTask, NULL,
                                    CFE_PLATFORM_ES_DEFAULT_STACK_SIZE, CS_CHILD_TASK_PRIORITY, 0);
    if (Status == CFE_SUCCESS) {
      CFE_EVS_SendEvent(CS_RECOMPUTE_OS_STARTED_DBG_EID, CFE_EVS_EventType_DEBUG,
                        "Recompute of OS code segment started");
      CS_AppData.HkPacket.Payload.CommandCounter++;
    } else { // child task creation failed
      CFE_EVS_SendEvent(CS_RECOMPUTE_OS_CREATE_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Recompute OS code segment failed, CFE_ES_CreateChildTask returned: 0x%08X",
                        Status);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
      CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
    }
  } else {
    CFE_EVS_SendEvent(CS_RECOMPUTE_OS_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Recompute OS code segment failed: child task in use");
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// One-shot: checksum an address the ground names, once, outside the six tables.
//
// THE RANGE IS VALIDATED FIRST, which no other CS command does -- every other address comes from a
// definition table that was validated when it was loaded. A one-shot address has never been
// validated by anything, so CFE_PSP_MemValidateRange is the only thing between the ground and a
// CRC over whatever is at that address.
//
// AND A ZERO BUDGET MEANS "USE THE PLATFORM DEFAULT". A zero reaching CS_OneShotChildTask would make
// its loop never terminate, so this substitution is the only thing keeping that loop bounded.
I32 CS_OneShotCmd(CS_OneShotCmd_t *CmdPtr)
{
  U32 ChildTaskID; // CFE_ES_TaskId_t
  I32 Status;

  Status = CFE_PSP_MemValidateRange(CmdPtr->Payload.Address, CmdPtr->Payload.Size, CFE_PSP_MEM_ANY);

  if (Status == CFE_SUCCESS) {
    if (CS_AppData.HkPacket.Payload.RecomputeInProgress == FALSE &&
        CS_AppData.HkPacket.Payload.OneShotInProgress == FALSE) {
      // make sure we don't try to do more than one single shot checksum at a time
      CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
      CS_AppData.HkPacket.Payload.OneShotInProgress = TRUE;

      CS_AppData.HkPacket.Payload.LastOneShotAddress = CmdPtr->Payload.Address;
      CS_AppData.HkPacket.Payload.LastOneShotSize = CmdPtr->Payload.Size;
      if (CmdPtr->Payload.MaxBytesPerCycle == 0) {
        CS_AppData.HkPacket.Payload.LastOneShotMaxBytesPerCycle = CS_AppData.MaxBytesPerCycle;
      } else {
        CS_AppData.HkPacket.Payload.LastOneShotMaxBytesPerCycle = CmdPtr->Payload.MaxBytesPerCycle;
      }

      CS_AppData.HkPacket.Payload.LastOneShotChecksum = 0;

      Status = CFE_ES_CreateChildTask(&ChildTaskID, CS_ONESHOT_TASK_NAME, &CS_OneShotChildTask,
                                      NULL, CFE_PLATFORM_ES_DEFAULT_STACK_SIZE,
                                      CS_CHILD_TASK_PRIORITY, 0);
      if (Status == CFE_SUCCESS) {
        CFE_EVS_SendEvent(CS_ONESHOT_STARTED_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "OneShot checksum started on address: 0x%08X, size: %d",
                          CmdPtr->Payload.Address, CmdPtr->Payload.Size);
        CS_AppData.ChildTaskID = ChildTaskID;
        CS_AppData.HkPacket.Payload.CommandCounter++;
      } else { // child task creation failed
        CFE_EVS_SendEvent(CS_ONESHOT_CREATE_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                          "OneShot checkum failed, CFE_ES_CreateChildTask returned: 0x%08X",
                          Status);
        CS_AppData.HkPacket.Payload.CommandErrorCounter++;
        CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
        CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
      }
    } else {
      CFE_EVS_SendEvent(CS_ONESHOT_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                        "OneShot checksum failed: child task in use");
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } // end if CFE_PSP_MemValidateRange
  else {
    CFE_EVS_SendEvent(CS_ONESHOT_MEMVALIDATE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "OneShot checksum failed, CFE_PSP_MemValidateRange returned: 0x%08X", Status);
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Cancel a one-shot in progress. The guard is `Recompute == FALSE && OneShot == TRUE`, so it
// refuses while a RECOMPUTE is running even though that also owns the child task -- there is one
// ChildTaskID and deleting it from here would kill a recompute the ground did not ask to cancel.
I32 CS_CancelOneShotCmd(CS_CancelOneShotCmd_t *CmdPtr)
{
  I32 Status;

  if (CS_AppData.HkPacket.Payload.RecomputeInProgress == FALSE &&
      CS_AppData.HkPacket.Payload.OneShotInProgress == TRUE) {
    Status = CFE_ES_DeleteChildTask(CS_AppData.ChildTaskID);

    if (Status == CFE_SUCCESS) {
      CS_AppData.ChildTaskID = CFE_ES_TASKID_UNDEFINED;
      CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
      CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
      CS_AppData.HkPacket.Payload.CommandCounter++;
      CFE_EVS_SendEvent(CS_ONESHOT_CANCELLED_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "OneShot checksum calculation has been cancelled");
    } else {
      CFE_EVS_SendEvent(CS_ONESHOT_CANCEL_DELETE_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Cancel OneShot checksum failed, CFE_ES_DeleteChildTask returned:  0x%08X",
                        Status);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } else {
    CFE_EVS_SendEvent(CS_ONESHOT_CANCEL_NO_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Cancel OneShot checksum failed. No OneShot active");
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}
#endif
