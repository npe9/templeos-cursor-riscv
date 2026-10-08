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
// CHECKSUM'S APPS COMMANDS -- the 1:1 translation of NASA's fsw/src/cs_app_cmds.c, 320 lines and six
// functions. The twin of cs_table_cmds.c, and the two differ in nothing but the names, the event
// ids, the entry types and the name LENGTH: a table's full name is 40 characters and an app's is 20.
//
// AN APP ENTRY IS CHECKSUMMED WITHOUT AN ADDRESS, which is the structural difference from the
// EEPROM/Memory pair: the results entry carries only a state and a name, and cs_compute.c looks the
// code segment up through CFE_ES_GetModuleInfo every cycle. So there is no per-entry address to
// report and no GetEntryID command here -- four commands against the EEPROM pair's five.
//
// THE SAME UPSTREAM DEFECT AS ITS TWIN: CS_RecomputeBaselineAppCmd prints `Name` in its
// child-task-busy event and the StrNCpy that fills Name is inside the `if` that arm is the `else`
// of, so the event sends 20 bytes of uninitialised stack. Marked at its site and recorded in
// docs/CFS_UPSTREAM_NOTES.md.
#ifndef CS_APP_CMDS_HC
#define CS_APP_CMDS_HC

/*******************************************************************************/
// Disable checksumming of the whole app table.
I32 CS_DisableAppsCmd(CS_DisableAppsCmd_t *CmdPtr)
{
  if (CS_CheckRecomputeOneshot() == FALSE) {
    CS_AppData.HkPacket.Payload.AppCSState = CS_ChecksumState_DISABLED;
    CS_ZeroAppTempValues();

    CS_UpdateCDS();

    CFE_EVS_SendEvent(CS_DISABLE_APP_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Checksumming of App is Disabled");

    CS_AppData.HkPacket.Payload.CommandCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable checksumming of the whole app table.
I32 CS_EnableAppsCmd(CS_EnableAppsCmd_t *CmdPtr)
{
  if (CS_CheckRecomputeOneshot() == FALSE) {
    CS_AppData.HkPacket.Payload.AppCSState = CS_ChecksumState_ENABLED;

    CS_UpdateCDS();

    CFE_EVS_SendEvent(CS_ENABLE_APP_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Checksumming of App is Enabled");

    CS_AppData.HkPacket.Payload.CommandCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Report one app's baseline, by name.
//
// THE NAME IS COPIED AND HAND-TERMINATED -- `strncpy(Name, ..., sizeof(Name) - 1)` and then
// `Name[sizeof(Name) - 1] = '\0'` -- because the command's Name field may fill its 40 bytes with no
// NUL at all. The translation keeps both halves: StrNCpy zero-fills where C's strncpy does not, so
// the explicit terminator is redundant HERE and is carried anyway, because dropping a line NASA
// wrote on the grounds that this port's library is kinder is how a 1:1 translation stops being one.
I32 CS_ReportBaselineAppCmd(CS_ReportBaselineAppCmd_t *CmdPtr)
{
  CS_Res_App_Table_Entry_t *ResultsEntry;
  U32 Baseline;
  U8 Name[OS_MAX_API_NAME];

  StrNCpy(Name, CmdPtr->Payload.Name, OS_MAX_API_NAME - 1);
  Name[OS_MAX_API_NAME - 1] = '\0';

  if (CS_GetAppResTblEntryByName(&ResultsEntry, Name)) {
    if (ResultsEntry->ComputedYet == TRUE) {
      Baseline = ResultsEntry->ComparisonValue;
      CFE_EVS_SendEvent(CS_BASELINE_APP_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Report baseline of app %s is 0x%08X", Name, Baseline);
    } else {
      CFE_EVS_SendEvent(CS_NO_BASELINE_APP_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Report baseline of app %s has not been computed yet", Name);
    }
    CS_AppData.HkPacket.Payload.CommandCounter++;
  } else {
    CFE_EVS_SendEvent(CS_BASELINE_INVALID_NAME_APP_ERR_EID, CFE_EVS_EventType_ERROR,
                      "App report baseline failed, app %s not found", Name);
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Recompute one app's baseline, by name, out of line in a child task.
//
// UPSTREAM DEFECT, KEPT VERBATIM: the `else` arm at the bottom prints `Name`, and the StrNCpy that
// fills it is inside the `if`. On the child-task-busy path Name has never been written, so the event
// carries 40 bytes of whatever the frame held. The EEPROM/Memory twins print an EntryID instead,
// which is at least an initialised zero. Same family as the two words of stack cFE writes into every
// app dump. See docs/CFS_UPSTREAM_NOTES.md.
I32 CS_RecomputeBaselineAppCmd(CS_RecomputeBaselineAppCmd_t *CmdPtr)
{
  U32 ChildTaskID; // CFE_ES_TaskId_t
  I32 Status;
  CS_Res_App_Table_Entry_t *ResultsEntry;
  U8 Name[OS_MAX_API_NAME];

  if (CS_AppData.HkPacket.Payload.RecomputeInProgress == FALSE &&
      CS_AppData.HkPacket.Payload.OneShotInProgress == FALSE) {
    StrNCpy(Name, CmdPtr->Payload.Name, OS_MAX_API_NAME - 1);
    Name[OS_MAX_API_NAME - 1] = '\0';

    if (CS_GetAppResTblEntryByName(&ResultsEntry, Name)) {
      // make sure we don't try to do more than one recompute at a time
      CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;

      CS_AppData.ChildTaskTable = CS_ChecksumType_APP_TABLE;
      CS_AppData.RecomputeAppEntryPtr = ResultsEntry;

      Status = CFE_ES_CreateChildTask(&ChildTaskID, CS_RECOMP_APP_TASK_NAME,
                                      &CS_RecomputeAppChildTask, NULL,
                                      CFE_PLATFORM_ES_DEFAULT_STACK_SIZE, CS_CHILD_TASK_PRIORITY,
                                      0);
      if (Status == CFE_SUCCESS) {
        CFE_EVS_SendEvent(CS_RECOMPUTE_APP_STARTED_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "Recompute baseline of app %s started", Name);
        CS_AppData.HkPacket.Payload.CommandCounter++;
      } else { // child task creation failed
        CFE_EVS_SendEvent(CS_RECOMPUTE_APP_CREATE_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Recompute baseline of app %s failed, CFE_ES_CreateChildTask returned: 0x%08X",
                          Name, Status);
        CS_AppData.HkPacket.Payload.CommandErrorCounter++;
        CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
      }
    } else {
      CFE_EVS_SendEvent(CS_RECOMPUTE_UNKNOWN_NAME_APP_ERR_EID, CFE_EVS_EventType_ERROR,
                        "App recompute baseline failed, app %s not found", Name);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } else {
    CFE_EVS_SendEvent(CS_RECOMPUTE_APP_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                      "App recompute baseline for app %s failed: child task in use", Name);
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable one app by name. It writes the RESULTS entry unconditionally and the DEFINITION entry
// only if a definition entry of that name exists -- and a missing definition entry is a DEBUG event
// rather than an error, because a app CS is watching need not be in the definition app at all
// (it can have arrived there from a results app that outlived a definition load).
I32 CS_DisableNameAppCmd(CS_DisableNameAppCmd_t *CmdPtr)
{
  CS_Res_App_Table_Entry_t *ResultsEntry;
  CS_Def_App_Table_Entry_t *DefinitionEntry;
  CS_TableWrapper_t *tw = &CS_AppData.Tbl[CS_ChecksumType_APP_TABLE];
  U8 Name[OS_MAX_API_NAME];

  if (CS_CheckRecomputeOneshot() == FALSE) {
    StrNCpy(Name, CmdPtr->Payload.Name, OS_MAX_API_NAME - 1);
    Name[OS_MAX_API_NAME - 1] = '\0';

    if (CS_GetAppResTblEntryByName(&ResultsEntry, Name)) {
      ResultsEntry->State = CS_ChecksumState_DISABLED;
      ResultsEntry->TempChecksumValue = 0;
      ResultsEntry->ByteOffset = 0;

      CFE_EVS_SendEvent(CS_DISABLE_APP_NAME_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Checksumming of app %s is Disabled", Name);

      if (CS_GetAppDefTblEntryByName(&DefinitionEntry, Name)) {
        CS_SetDefEntryState(tw, DefinitionEntry, CS_ChecksumState_DISABLED);
      } else {
        CFE_EVS_SendEvent(CS_DISABLE_APP_DEF_NOT_FOUND_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "CS unable to update apps definition table for entry %s", Name);
      }

      CS_AppData.HkPacket.Payload.CommandCounter++;
    } else {
      CFE_EVS_SendEvent(CS_DISABLE_APP_UNKNOWN_NAME_ERR_EID, CFE_EVS_EventType_ERROR,
                        "App disable app command failed, app %s not found", Name);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } // end InProgress if

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable one app by name.
I32 CS_EnableNameAppCmd(CS_EnableNameAppCmd_t *CmdPtr)
{
  CS_Res_App_Table_Entry_t *ResultsEntry;
  CS_Def_App_Table_Entry_t *DefinitionEntry;
  CS_TableWrapper_t *tw = &CS_AppData.Tbl[CS_ChecksumType_APP_TABLE];
  U8 Name[OS_MAX_API_NAME];

  if (CS_CheckRecomputeOneshot() == FALSE) {
    StrNCpy(Name, CmdPtr->Payload.Name, OS_MAX_API_NAME - 1);
    Name[OS_MAX_API_NAME - 1] = '\0';

    if (CS_GetAppResTblEntryByName(&ResultsEntry, Name)) {
      ResultsEntry->State = CS_ChecksumState_ENABLED;

      CFE_EVS_SendEvent(CS_ENABLE_APP_NAME_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Checksumming of app %s is Enabled", Name);

      if (CS_GetAppDefTblEntryByName(&DefinitionEntry, Name)) {
        CS_SetDefEntryState(tw, DefinitionEntry, CS_ChecksumState_ENABLED);
      } else {
        CFE_EVS_SendEvent(CS_ENABLE_APP_DEF_NOT_FOUND_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "CS unable to update apps definition table for entry %s", Name);
      }

      CS_AppData.HkPacket.Payload.CommandCounter++;
    } else {
      CFE_EVS_SendEvent(CS_ENABLE_APP_UNKNOWN_NAME_ERR_EID, CFE_EVS_EventType_ERROR,
                        "App enable app command failed, app %s not found", Name);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } // end InProgress if

  return CFE_SUCCESS;
}
#endif
