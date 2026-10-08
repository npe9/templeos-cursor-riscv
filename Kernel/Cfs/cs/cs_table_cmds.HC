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
// CHECKSUM'S TABLES COMMANDS -- the 1:1 translation of NASA's fsw/src/cs_table_cmds.c, 317 lines and
// six functions. The twin of cs_app_cmds.c, and the pair differ from the EEPROM/Memory pair in one
// structural way: these are addressed BY NAME rather than by entry id, so every one starts by
// copying a 40- or 20-character name out of the command and NUL-terminating it by hand.
//
// UPSTREAM DEFECT, KEPT VERBATIM, AND MARKED AT ITS SITE: CS_RecomputeBaselineTableCmd prints
// `Name` in its child-task-busy event, and the strncpy that fills Name is INSIDE the `if` that arm
// is the `else` of. So that event sends 40 bytes of UNINITIALISED STACK to the ground. The app twin
// has it too. See docs/CFS_UPSTREAM_NOTES.md.
#ifndef CS_TABLE_CMDS_HC
#define CS_TABLE_CMDS_HC

/*******************************************************************************/
// Disable checksumming of the whole tables table.
I32 CS_DisableTablesCmd(CS_DisableTablesCmd_t *CmdPtr)
{
  if (CS_CheckRecomputeOneshot() == FALSE) {
    CS_AppData.HkPacket.Payload.TablesCSState = CS_ChecksumState_DISABLED;
    CS_ZeroTablesTempValues();

    CS_UpdateCDS();

    CFE_EVS_SendEvent(CS_DISABLE_TABLES_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Checksumming of Tables is Disabled");

    CS_AppData.HkPacket.Payload.CommandCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable checksumming of the whole tables table.
I32 CS_EnableTablesCmd(CS_EnableTablesCmd_t *CmdPtr)
{
  if (CS_CheckRecomputeOneshot() == FALSE) {
    CS_AppData.HkPacket.Payload.TablesCSState = CS_ChecksumState_ENABLED;

    CS_UpdateCDS();

    CFE_EVS_SendEvent(CS_ENABLE_TABLES_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Checksumming of Tables is Enabled");

    CS_AppData.HkPacket.Payload.CommandCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Report one table's baseline, by name.
//
// THE NAME IS COPIED AND HAND-TERMINATED -- `strncpy(Name, ..., sizeof(Name) - 1)` and then
// `Name[sizeof(Name) - 1] = '\0'` -- because the command's Name field may fill its 40 bytes with no
// NUL at all. The translation keeps both halves: StrNCpy zero-fills where C's strncpy does not, so
// the explicit terminator is redundant HERE and is carried anyway, because dropping a line NASA
// wrote on the grounds that this port's library is kinder is how a 1:1 translation stops being one.
I32 CS_ReportBaselineTableCmd(CS_ReportBaselineTableCmd_t *CmdPtr)
{
  CS_Res_Tables_Table_Entry_t *ResultsEntry;
  U32 Baseline;
  U8 Name[CFE_TBL_MAX_FULL_NAME_LEN];

  StrNCpy(Name, CmdPtr->Payload.Name, CFE_TBL_MAX_FULL_NAME_LEN - 1);
  Name[CFE_TBL_MAX_FULL_NAME_LEN - 1] = '\0';

  if (CS_GetTableResTblEntryByName(&ResultsEntry, Name)) {
    if (ResultsEntry->ComputedYet == TRUE) {
      Baseline = ResultsEntry->ComparisonValue;
      CFE_EVS_SendEvent(CS_BASELINE_TABLE_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Report baseline of table %s is 0x%08X", Name, Baseline);
    } else {
      CFE_EVS_SendEvent(CS_NO_BASELINE_TABLE_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Report baseline of table %s has not been computed yet", Name);
    }
    CS_AppData.HkPacket.Payload.CommandCounter++;
  } else {
    CFE_EVS_SendEvent(CS_BASELINE_INVALID_NAME_TABLES_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Tables report baseline failed, table %s not found", Name);
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Recompute one table's baseline, by name, out of line in a child task.
//
// UPSTREAM DEFECT, KEPT VERBATIM: the `else` arm at the bottom prints `Name`, and the StrNCpy that
// fills it is inside the `if`. On the child-task-busy path Name has never been written, so the event
// carries 40 bytes of whatever the frame held. The EEPROM/Memory twins print an EntryID instead,
// which is at least an initialised zero. Same family as the two words of stack cFE writes into every
// table dump. See docs/CFS_UPSTREAM_NOTES.md.
I32 CS_RecomputeBaselineTableCmd(CS_RecomputeBaselineTableCmd_t *CmdPtr)
{
  U32 ChildTaskID; // CFE_ES_TaskId_t
  I32 Status;
  CS_Res_Tables_Table_Entry_t *ResultsEntry;
  U8 Name[CFE_TBL_MAX_FULL_NAME_LEN];

  if (CS_AppData.HkPacket.Payload.RecomputeInProgress == FALSE &&
      CS_AppData.HkPacket.Payload.OneShotInProgress == FALSE) {
    StrNCpy(Name, CmdPtr->Payload.Name, CFE_TBL_MAX_FULL_NAME_LEN - 1);
    Name[CFE_TBL_MAX_FULL_NAME_LEN - 1] = '\0';

    if (CS_GetTableResTblEntryByName(&ResultsEntry, Name)) {
      // make sure we don't try to do more than one recompute at a time
      CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;

      CS_AppData.ChildTaskTable = CS_ChecksumType_TABLES_TABLE;
      CS_AppData.RecomputeTablesEntryPtr = ResultsEntry;

      Status = CFE_ES_CreateChildTask(&ChildTaskID, CS_RECOMP_TABLES_TASK_NAME,
                                      &CS_RecomputeTablesChildTask, NULL,
                                      CFE_PLATFORM_ES_DEFAULT_STACK_SIZE, CS_CHILD_TASK_PRIORITY,
                                      0);
      if (Status == CFE_SUCCESS) {
        CFE_EVS_SendEvent(CS_RECOMPUTE_TABLES_STARTED_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "Recompute baseline of table %s started", Name);
        CS_AppData.HkPacket.Payload.CommandCounter++;
      } else { // child task creation failed
        CFE_EVS_SendEvent(CS_RECOMPUTE_TABLES_CREATE_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Recompute baseline of table %s failed, CFE_ES_CreateChildTask returned: 0x%08X",
                          Name, Status);
        CS_AppData.HkPacket.Payload.CommandErrorCounter++;
        CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
      }
    } else {
      CFE_EVS_SendEvent(CS_RECOMPUTE_UNKNOWN_NAME_TABLES_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Tables recompute baseline failed, table %s not found", Name);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } else {
    CFE_EVS_SendEvent(CS_RECOMPUTE_TABLES_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Tables recompute baseline for table %s failed: child task in use", Name);
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable one table by name. It writes the RESULTS entry unconditionally and the DEFINITION entry
// only if a definition entry of that name exists -- and a missing definition entry is a DEBUG event
// rather than an error, because a table CS is watching need not be in the definition table at all
// (it can have arrived there from a results table that outlived a definition load).
I32 CS_DisableNameTableCmd(CS_DisableNameTableCmd_t *CmdPtr)
{
  CS_Res_Tables_Table_Entry_t *ResultsEntry;
  CS_Def_Tables_Table_Entry_t *DefinitionEntry;
  CS_TableWrapper_t *tw = &CS_AppData.Tbl[CS_ChecksumType_TABLES_TABLE];
  U8 Name[CFE_TBL_MAX_FULL_NAME_LEN];

  if (CS_CheckRecomputeOneshot() == FALSE) {
    StrNCpy(Name, CmdPtr->Payload.Name, CFE_TBL_MAX_FULL_NAME_LEN - 1);
    Name[CFE_TBL_MAX_FULL_NAME_LEN - 1] = '\0';

    if (CS_GetTableResTblEntryByName(&ResultsEntry, Name)) {
      ResultsEntry->State = CS_ChecksumState_DISABLED;
      ResultsEntry->TempChecksumValue = 0;
      ResultsEntry->ByteOffset = 0;

      CFE_EVS_SendEvent(CS_DISABLE_TABLES_NAME_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Checksumming of table %s is Disabled", Name);

      if (CS_GetTableDefTblEntryByName(&DefinitionEntry, Name)) {
        CS_SetDefEntryState(tw, DefinitionEntry, CS_ChecksumState_DISABLED);
      } else {
        CFE_EVS_SendEvent(CS_DISABLE_TABLE_DEF_NOT_FOUND_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "CS unable to update tables definition table for entry %s", Name);
      }

      CS_AppData.HkPacket.Payload.CommandCounter++;
    } else {
      CFE_EVS_SendEvent(CS_DISABLE_TABLES_UNKNOWN_NAME_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Tables disable table command failed, table %s not found", Name);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } // end InProgress if

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable one table by name.
I32 CS_EnableNameTableCmd(CS_EnableNameTableCmd_t *CmdPtr)
{
  CS_Res_Tables_Table_Entry_t *ResultsEntry;
  CS_Def_Tables_Table_Entry_t *DefinitionEntry;
  CS_TableWrapper_t *tw = &CS_AppData.Tbl[CS_ChecksumType_TABLES_TABLE];
  U8 Name[CFE_TBL_MAX_FULL_NAME_LEN];

  if (CS_CheckRecomputeOneshot() == FALSE) {
    StrNCpy(Name, CmdPtr->Payload.Name, CFE_TBL_MAX_FULL_NAME_LEN - 1);
    Name[CFE_TBL_MAX_FULL_NAME_LEN - 1] = '\0';

    if (CS_GetTableResTblEntryByName(&ResultsEntry, Name)) {
      ResultsEntry->State = CS_ChecksumState_ENABLED;

      CFE_EVS_SendEvent(CS_ENABLE_TABLES_NAME_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Checksumming of table %s is Enabled", Name);

      if (CS_GetTableDefTblEntryByName(&DefinitionEntry, Name)) {
        CS_SetDefEntryState(tw, DefinitionEntry, CS_ChecksumState_ENABLED);
      } else {
        CFE_EVS_SendEvent(CS_ENABLE_TABLE_DEF_NOT_FOUND_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "CS unable to update tables definition table for entry %s", Name);
      }

      CS_AppData.HkPacket.Payload.CommandCounter++;
    } else {
      CFE_EVS_SendEvent(CS_ENABLE_TABLES_UNKNOWN_NAME_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Tables enable table command failed, table %s not found", Name);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } // end InProgress if

  return CFE_SUCCESS;
}
#endif
