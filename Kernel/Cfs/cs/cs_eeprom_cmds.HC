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
// CHECKSUM'S EEPROM COMMANDS -- the 1:1 translation of NASA's fsw/src/cs_eeprom_cmds.c, 425 lines
// and seven functions: the type's enable/disable pair, the per-entry baseline report, the per-entry
// recompute, the per-entry enable/disable pair, and the address-to-entry lookup.
//
// THIS FILE AND cs_memory_cmds.c ARE TWINS, and the three places they DISAGREE are upstream
// defects rather than translation choices. They are recorded in docs/CFS_UPSTREAM_NOTES.md and kept
// verbatim; the one that matters is marked at its site below.
//
// EVERY COMMAND HERE STARTS WITH CS_CheckRecomputeOneshot EXCEPT TWO. The report and the lookup do
// not, and that is NASA's: reading a baseline or asking which entry covers an address changes
// nothing a child task could be racing. The five that WRITE all refuse while one is running.
//
// `#if (CS_PRESERVE_STATES_ON_PROCESSOR_RESET == true) CS_UpdateCDS(); #endif` is translated as a
// bare call, for the reason stated once at the top of cs_cmds.HC: the value is true here and
// `#if <expr>` is unconditionally true in this compiler (limit #19).
#ifndef CS_EEPROM_CMDS_HC
#define CS_EEPROM_CMDS_HC

/*******************************************************************************/
// Disable checksumming of the whole EEPROM table.
I32 CS_DisableEepromCmd(CS_DisableEepromCmd_t *CmdPtr)
{
  if (CS_CheckRecomputeOneshot() == FALSE) {
    CS_AppData.HkPacket.Payload.EepromCSState = CS_ChecksumState_DISABLED;
    CS_ZeroEepromTempValues();

    CS_UpdateCDS();

    CFE_EVS_SendEvent(CS_DISABLE_EEPROM_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Checksumming of EEPROM is Disabled");

    CS_AppData.HkPacket.Payload.CommandCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable checksumming of the whole EEPROM table.
I32 CS_EnableEepromCmd(CS_EnableEepromCmd_t *CmdPtr)
{
  if (CS_CheckRecomputeOneshot() == FALSE) {
    CS_AppData.HkPacket.Payload.EepromCSState = CS_ChecksumState_ENABLED;

    CS_UpdateCDS();

    CFE_EVS_SendEvent(CS_ENABLE_EEPROM_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Checksumming of EEPROM is Enabled");

    CS_AppData.HkPacket.Payload.CommandCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Report one EEPROM entry's baseline.
//
// UPSTREAM DEFECT, KEPT VERBATIM: `ResultsEntry->State = CS_ChecksumState_ENABLED;` -- A REPORT
// COMMAND WRITES THE ENTRY'S STATE. Ask a DISABLED entry for its baseline and it comes back
// ENABLED, and the background walk starts checksumming a region the ground had switched off. The
// identical Memory command (cs_memory_cmds.c, CS_ReportBaselineEntryIDMemoryCmd) does NOT have this
// line -- the two functions are otherwise line for line -- so it is not a deliberate convention,
// it is one of the twins having an extra statement. See docs/CFS_UPSTREAM_NOTES.md.
//
// AND THE NULL CASE IS NOT GUARDED AFTER THE TEST. `State` is set to UNDEFINED when ResultsEntry is
// NULL, CS_StateValid refuses UNDEFINED, so the dereference below cannot run with NULL -- but it is
// the test on a COPY of the state, not on the pointer, that makes that true.
I32 CS_ReportBaselineEntryIDEepromCmd(CS_ReportBaselineEntryIDEepromCmd_t *CmdPtr)
{
  U32 Baseline = 0;
  U16 EntryID = 0;
  U32 State = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;

  EntryID = CmdPtr->Payload.EntryID;
  ResultsEntry = CS_GetEepromResEntry(EntryID);

  if (ResultsEntry == NULL) {
    State = CS_ChecksumState_UNDEFINED;
  } else {
    State = ResultsEntry->State;
  }

  if (CS_StateValid(State)) {
    ResultsEntry->State = CS_ChecksumState_ENABLED;

    if (ResultsEntry->ComputedYet == TRUE) {
      Baseline = ResultsEntry->ComparisonValue;
      CFE_EVS_SendEvent(CS_BASELINE_EEPROM_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Report baseline of EEPROM Entry %d is 0x%08X", EntryID, Baseline);
    } else {
      CFE_EVS_SendEvent(CS_NO_BASELINE_EEPROM_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Report baseline of EEPROM Entry %d has not been computed yet", EntryID);
    }
    CS_AppData.HkPacket.Payload.CommandCounter++;
  } else {
    CFE_EVS_SendEvent(CS_BASELINE_INVALID_ENTRY_EEPROM_ERR_EID, CFE_EVS_EventType_ERROR,
                      "EEPROM report baseline failed, Entry ID invalid: %d, State: %d Max ID: %d",
                      EntryID, State, CS_MAX_NUM_EEPROM_TABLE_ENTRIES - 1);
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Recompute one EEPROM entry's baseline, out of line in a child task.
//
// UPSTREAM DEFECT, KEPT VERBATIM: `EntryID = CmdPtr->Payload.EntryID;` IS INSIDE THE `if`, and the
// child-task-busy event in the `else` prints EntryID -- which is therefore ALWAYS 0 on that path,
// whatever the ground commanded. The Memory twin assigns it OUTSIDE the `if` and reports the real
// id. Milder than an uninitialised read only because the declaration initialises it to zero.
I32 CS_RecomputeBaselineEepromCmd(CS_RecomputeBaselineEepromCmd_t *CmdPtr)
{
  U32 ChildTaskID = CFE_ES_TASKID_UNDEFINED; // CFE_ES_TaskId_t
  I32 Status = CS_ERROR;
  U16 EntryID = 0;
  U32 State = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;

  if (CS_AppData.HkPacket.Payload.RecomputeInProgress == FALSE &&
      CS_AppData.HkPacket.Payload.OneShotInProgress == FALSE) {
    EntryID = CmdPtr->Payload.EntryID;
    ResultsEntry = CS_GetEepromResEntry(EntryID);

    if (ResultsEntry == NULL) {
      State = CS_ChecksumState_UNDEFINED;
    } else {
      State = ResultsEntry->State;
    }

    if (CS_StateValid(State)) {
      // make sure we don't try to do more than one recompute at a time
      CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;

      // fill in child task variables
      CS_AppData.ChildTaskTable = CS_ChecksumType_EEPROM_TABLE;
      CS_AppData.ChildTaskEntryID = EntryID;
      CS_AppData.RecomputeEepromMemoryEntryPtr = ResultsEntry;

      Status = CFE_ES_CreateChildTask(&ChildTaskID, CS_RECOMP_EEPROM_TASK_NAME,
                                      &CS_RecomputeEepromMemoryChildTask, NULL,
                                      CFE_PLATFORM_ES_DEFAULT_STACK_SIZE, CS_CHILD_TASK_PRIORITY,
                                      0);
      if (Status == CFE_SUCCESS) {
        CFE_EVS_SendEvent(CS_RECOMPUTE_EEPROM_STARTED_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "Recompute baseline of EEPROM Entry ID %d started", EntryID);
        CS_AppData.HkPacket.Payload.CommandCounter++;
      } else { // child task creation failed
        CFE_EVS_SendEvent(
            CS_RECOMPUTE_EEPROM_CREATE_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
            "Recompute baseline of EEPROM Entry ID %d failed, CFE_ES_CreateChildTask returned:  0x%08X",
            EntryID, Status);
        CS_AppData.HkPacket.Payload.CommandErrorCounter++;
        CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
      }
    } else {
      CFE_EVS_SendEvent(CS_RECOMPUTE_INVALID_ENTRY_EEPROM_ERR_EID, CFE_EVS_EventType_ERROR,
                        "EEPROM recompute baseline of entry failed, Entry ID invalid: %d, State: %d, Max ID: %d",
                        EntryID, State, CS_MAX_NUM_EEPROM_TABLE_ENTRIES - 1);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } else {
    CFE_EVS_SendEvent(CS_RECOMPUTE_EEPROM_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Recompute baseline of EEPROM Entry ID %d failed: child task in use", EntryID);
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable one EEPROM entry.
//
// IT WRITES BOTH TABLES, and the definition write can fail quietly: CS_SetDefEntryState returns the
// PREVIOUS state, and a previous state that is not commandable means the definition entry is empty
// -- so the results entry is enabled and the definition entry is not, and the mismatch survives
// only until the next ground table load. That is what the DEBUG event says.
I32 CS_EnableEntryIDEepromCmd(CS_EnableEntryIDEepromCmd_t *CmdPtr)
{
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;
  CS_Def_EepromMemory_Table_Entry_t *DefEntry = NULL;
  CS_TableWrapper_t *tw = &CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE];
  U16 EntryID = 0;
  U32 State = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t

  if (CS_CheckRecomputeOneshot() == FALSE) {
    EntryID = CmdPtr->Payload.EntryID;
    ResultsEntry = CS_GetEepromResEntry(EntryID);

    if (ResultsEntry == NULL) {
      State = CS_ChecksumState_UNDEFINED;
    } else {
      State = ResultsEntry->State;
    }

    if (CS_StateValid(State)) {
      DefEntry = CS_GetEepromDefEntry(EntryID);

      ResultsEntry->State = CS_ChecksumState_ENABLED;

      CFE_EVS_SendEvent(CS_ENABLE_EEPROM_ENTRY_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Checksumming of EEPROM Entry ID %d is Enabled", EntryID);

      State = CS_SetDefEntryState(tw, DefEntry, CS_ChecksumState_ENABLED);
      if (!CS_StateValid(State)) {
        CFE_EVS_SendEvent(CS_ENABLE_EEPROM_DEF_EMPTY_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "CS unable to update EEPROM definition table for entry %d, State: %d",
                          EntryID, State);
      }

      CS_AppData.HkPacket.Payload.CommandCounter++;
    } else {
      CFE_EVS_SendEvent(CS_ENABLE_EEPROM_INVALID_ENTRY_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Enable EEPROM entry failed, invalid Entry ID:  %d, State: %d, Max ID: %d",
                        EntryID, State, CS_MAX_NUM_EEPROM_TABLE_ENTRIES - 1);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } // end InProgress if

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable one EEPROM entry. The disable also clears the entry's partial checksum; the enable does
// not, which is the same asymmetry every disable in CS has.
I32 CS_DisableEntryIDEepromCmd(CS_DisableEntryIDEepromCmd_t *CmdPtr)
{
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;
  CS_Def_EepromMemory_Table_Entry_t *DefEntry = NULL;
  CS_TableWrapper_t *tw = &CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE];
  U16 EntryID = 0;
  U32 State = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t

  if (CS_CheckRecomputeOneshot() == FALSE) {
    EntryID = CmdPtr->Payload.EntryID;
    ResultsEntry = CS_GetEepromResEntry(EntryID);

    if (ResultsEntry == NULL) {
      State = CS_ChecksumState_UNDEFINED;
    } else {
      State = ResultsEntry->State;
    }

    if (CS_StateValid(State)) {
      DefEntry = CS_GetEepromDefEntry(EntryID);

      ResultsEntry->State = CS_ChecksumState_DISABLED;
      ResultsEntry->TempChecksumValue = 0;
      ResultsEntry->ByteOffset = 0;

      CFE_EVS_SendEvent(CS_DISABLE_EEPROM_ENTRY_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Checksumming of EEPROM Entry ID %d is Disabled", EntryID);

      State = CS_SetDefEntryState(tw, DefEntry, CS_ChecksumState_DISABLED);
      if (!CS_StateValid(State)) {
        CFE_EVS_SendEvent(CS_DISABLE_EEPROM_DEF_EMPTY_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "CS unable to update EEPROM definition table for entry %d, State: %d",
                          EntryID, State);
      }

      CS_AppData.HkPacket.Payload.CommandCounter++;
    } else {
      CFE_EVS_SendEvent(CS_DISABLE_EEPROM_INVALID_ENTRY_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Disable EEPROM entry failed, invalid Entry ID:  %d, State: %d, Max ID: %d",
                        EntryID, State, CS_MAX_NUM_EEPROM_TABLE_ENTRIES - 1);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } // end InProgress if

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Which entry covers this address.
//
// THE LOOP DOES NOT STOP AT THE FIRST MATCH. It walks the whole table and sends an event for EVERY
// entry whose range contains the address, so overlapping definition entries all report. That is
// NASA's and it is the right answer: a ground operator asking "who is watching this byte" wants all
// of them. EntryFound is only used for the not-found event.
I32 CS_GetEntryIDEepromCmd(CS_GetEntryIDEepromCmd_t *CmdPtr)
{
  U16 Loop = 0;
  Bool EntryFound = FALSE;
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry;

  Loop = 0;
  while (TRUE) {
    ResultsEntry = CS_GetEepromResEntry(Loop);
    if (ResultsEntry == NULL) {
      break;
    }

    if (ResultsEntry->State != CS_ChecksumState_EMPTY &&
        ResultsEntry->StartAddress <= CmdPtr->Payload.Address &&
        CmdPtr->Payload.Address < ResultsEntry->StartAddress + ResultsEntry->NumBytesToChecksum) {
      CFE_EVS_SendEvent(CS_GET_ENTRY_ID_EEPROM_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "EEPROM Found Address 0x%08X in Entry ID %d", CmdPtr->Payload.Address, Loop);
      EntryFound = TRUE;
    }

    ++Loop;
  }

  if (EntryFound == FALSE) {
    CFE_EVS_SendEvent(CS_GET_ENTRY_ID_EEPROM_NOT_FOUND_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Address 0x%08X was not found in EEPROM table", CmdPtr->Payload.Address);
  }

  CS_AppData.HkPacket.Payload.CommandCounter++;

  return CFE_SUCCESS;
}
#endif
