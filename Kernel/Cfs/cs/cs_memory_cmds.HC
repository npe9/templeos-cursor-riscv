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
// CHECKSUM'S MEMORY COMMANDS -- the 1:1 translation of NASA's fsw/src/cs_memory_cmds.c, 424 lines
// and seven functions. Line for line the twin of cs_eeprom_cmds.c, which is why the two share both
// entry types: there is no CS_Def_Memory_Table_Entry_t, the memory table uses
// CS_Def_EepromMemory_Table_Entry_t, and the only functional difference between the two TABLES is
// which CFE_PSP_MemValidateRange type their definitions are checked against.
//
// THE TWINS DISAGREE IN THREE PLACES AND ALL THREE ARE UPSTREAM. Two are marked at their sites below
// and both have THIS file on the correct side: the report command does not write the entry's state,
// and the recompute reports the id the ground commanded. The third is an event string --
// "ES_CreateChildTask returned" here against "CFE_ES_CreateChildTask returned" in the EEPROM file, a
// dropped prefix in text a ground display greps. All three are kept verbatim and recorded in
// docs/CFS_UPSTREAM_NOTES.md.
//
// HOW THE THREE WERE FOUND, because it generalises: NASA's two sources were diffed against EACH
// OTHER with the words Eeprom/EEPROM/eeprom and Memory/MEMORY/memory normalised to one token. What
// survives such a diff is either a real difference or a formatting one, and there were five lines of
// it. Two translated files that are twins should be checked the same way.
//
// `#if (CS_PRESERVE_STATES_ON_PROCESSOR_RESET == true) CS_UpdateCDS(); #endif` is translated as a
// bare call, for the reason stated once at the top of cs_cmds.HC.
#ifndef CS_MEMORY_CMDS_HC
#define CS_MEMORY_CMDS_HC

/*******************************************************************************/
// Disable checksumming of the whole Memory table.
I32 CS_DisableMemoryCmd(CS_DisableMemoryCmd_t *CmdPtr)
{
  if (CS_CheckRecomputeOneshot() == FALSE) {
    CS_AppData.HkPacket.Payload.MemoryCSState = CS_ChecksumState_DISABLED;
    CS_ZeroMemoryTempValues();

    CS_UpdateCDS();

    CFE_EVS_SendEvent(CS_DISABLE_MEMORY_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Checksumming of Memory is Disabled");

    CS_AppData.HkPacket.Payload.CommandCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable checksumming of the whole Memory table.
I32 CS_EnableMemoryCmd(CS_EnableMemoryCmd_t *CmdPtr)
{
  if (CS_CheckRecomputeOneshot() == FALSE) {
    CS_AppData.HkPacket.Payload.MemoryCSState = CS_ChecksumState_ENABLED;

    CS_UpdateCDS();

    CFE_EVS_SendEvent(CS_ENABLE_MEMORY_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Checksumming of Memory is Enabled");

    CS_AppData.HkPacket.Payload.CommandCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Report one Memory entry's baseline.
//
// THIS IS THE HALF OF THE PAIR THAT IS RIGHT. Its EEPROM twin writes
// `ResultsEntry->State = CS_ChecksumState_ENABLED;` here -- a REPORT command that silently
// re-enables a DISABLED entry -- and this one does not. The two functions are otherwise line for
// line, so the extra statement over there is a defect and not a convention. Recorded in
// docs/CFS_UPSTREAM_NOTES.md and kept verbatim in both files.
I32 CS_ReportBaselineEntryIDMemoryCmd(CS_ReportBaselineEntryIDMemoryCmd_t *CmdPtr)
{
  // The pointer is declared FIRST here and last in the EEPROM twin -- NASA's order, carried, for
  // the reason stated at CS_GetEntryIDMemoryCmd below.
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;
  U32 Baseline = 0;
  U16 EntryID = 0;
  U32 State = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t

  EntryID = CmdPtr->Payload.EntryID;
  ResultsEntry = CS_GetMemoryResEntry(EntryID);

  if (ResultsEntry == NULL) {
    State = CS_ChecksumState_UNDEFINED;
  } else {
    State = ResultsEntry->State;
  }

  if (CS_StateValid(State)) {
    if (ResultsEntry->ComputedYet == TRUE) {
      Baseline = ResultsEntry->ComparisonValue;
      CFE_EVS_SendEvent(CS_BASELINE_MEMORY_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Report baseline of Memory Entry %d is 0x%08X", EntryID, Baseline);
    } else {
      CFE_EVS_SendEvent(CS_NO_BASELINE_MEMORY_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Report baseline of Memory Entry %d has not been computed yet", EntryID);
    }
    CS_AppData.HkPacket.Payload.CommandCounter++;
  } else {
    CFE_EVS_SendEvent(CS_BASELINE_INVALID_ENTRY_MEMORY_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Memory report baseline failed, Entry ID invalid: %d, State: %d Max ID: %d",
                      EntryID, State, CS_MAX_NUM_MEMORY_TABLE_ENTRIES - 1);
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Recompute one Memory entry's baseline, out of line in a child task.
//
// AND THIS IS THE OTHER HALF THAT IS RIGHT: `EntryID = CmdPtr->Payload.EntryID;` is assigned
// OUTSIDE the `if`, so the child-task-busy event in the `else` reports the id the ground actually
// commanded. The EEPROM twin assigns it inside, and that event always says Entry ID 0.
I32 CS_RecomputeBaselineMemoryCmd(CS_RecomputeBaselineMemoryCmd_t *CmdPtr)
{
  // Pointer first again, as NASA has it.
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;
  U32 ChildTaskID = CFE_ES_TASKID_UNDEFINED; // CFE_ES_TaskId_t
  I32 Status = CS_ERROR;
  U16 EntryID = 0;
  U32 State = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t

  EntryID = CmdPtr->Payload.EntryID;

  if (CS_AppData.HkPacket.Payload.RecomputeInProgress == FALSE &&
      CS_AppData.HkPacket.Payload.OneShotInProgress == FALSE) {
    ResultsEntry = CS_GetMemoryResEntry(EntryID);

    if (ResultsEntry == NULL) {
      State = CS_ChecksumState_UNDEFINED;
    } else {
      State = ResultsEntry->State;
    }

    if (CS_StateValid(State)) {
      // make sure we don't try to do more than one recompute at a time
      CS_AppData.HkPacket.Payload.RecomputeInProgress = TRUE;

      // fill in child task variables
      CS_AppData.ChildTaskTable = CS_ChecksumType_MEMORY_TABLE;
      CS_AppData.ChildTaskEntryID = EntryID;
      CS_AppData.RecomputeEepromMemoryEntryPtr = ResultsEntry;

      Status = CFE_ES_CreateChildTask(&ChildTaskID, CS_RECOMP_MEMORY_TASK_NAME,
                                      &CS_RecomputeEepromMemoryChildTask, NULL,
                                      CFE_PLATFORM_ES_DEFAULT_STACK_SIZE, CS_CHILD_TASK_PRIORITY,
                                      0);
      if (Status == CFE_SUCCESS) {
        CFE_EVS_SendEvent(CS_RECOMPUTE_MEMORY_STARTED_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "Recompute baseline of Memory Entry ID %d started", EntryID);
        CS_AppData.HkPacket.Payload.CommandCounter++;
      } else { // child task creation failed
        CFE_EVS_SendEvent(
            CS_RECOMPUTE_MEMORY_CREATE_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
            "Recompute baseline of Memory Entry ID %d failed, ES_CreateChildTask returned:  0x%08X",
            EntryID, Status);
        CS_AppData.HkPacket.Payload.CommandErrorCounter++;
        CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
      }
    } else {
      CFE_EVS_SendEvent(CS_RECOMPUTE_INVALID_ENTRY_MEMORY_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Memory recompute baseline of entry failed, Entry ID invalid: %d, State: %d, Max ID: %d",
                        EntryID, State, CS_MAX_NUM_MEMORY_TABLE_ENTRIES - 1);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } else {
    CFE_EVS_SendEvent(CS_RECOMPUTE_MEMORY_CHDTASK_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Recompute baseline of Memory Entry ID %d failed: child task in use", EntryID);
    CS_AppData.HkPacket.Payload.CommandErrorCounter++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable one Memory entry.
//
// IT WRITES BOTH TABLES, and the definition write can fail quietly: CS_SetDefEntryState returns the
// PREVIOUS state, and a previous state that is not commandable means the definition entry is empty
// -- so the results entry is enabled and the definition entry is not, and the mismatch survives
// only until the next ground table load. That is what the DEBUG event says.
I32 CS_EnableEntryIDMemoryCmd(CS_EnableEntryIDMemoryCmd_t *CmdPtr)
{
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;
  CS_Def_EepromMemory_Table_Entry_t *DefEntry = NULL;
  CS_TableWrapper_t *tw = &CS_AppData.Tbl[CS_ChecksumType_MEMORY_TABLE];
  U16 EntryID = 0;
  U32 State = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t

  if (CS_CheckRecomputeOneshot() == FALSE) {
    EntryID = CmdPtr->Payload.EntryID;
    ResultsEntry = CS_GetMemoryResEntry(EntryID);

    if (ResultsEntry == NULL) {
      State = CS_ChecksumState_UNDEFINED;
    } else {
      State = ResultsEntry->State;
    }

    if (CS_StateValid(State)) {
      DefEntry = CS_GetMemoryDefEntry(EntryID);

      ResultsEntry->State = CS_ChecksumState_ENABLED;

      CFE_EVS_SendEvent(CS_ENABLE_MEMORY_ENTRY_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Checksumming of Memory Entry ID %d is Enabled", EntryID);

      State = CS_SetDefEntryState(tw, DefEntry, CS_ChecksumState_ENABLED);
      if (!CS_StateValid(State)) {
        CFE_EVS_SendEvent(CS_ENABLE_MEMORY_DEF_EMPTY_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "CS unable to update memory definition table for entry %d, State: %d",
                          EntryID, State);
      }

      CS_AppData.HkPacket.Payload.CommandCounter++;
    } else {
      CFE_EVS_SendEvent(CS_ENABLE_MEMORY_INVALID_ENTRY_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Enable Memory entry failed, invalid Entry ID:  %d, State: %d, Max ID: %d",
                        EntryID, State, CS_MAX_NUM_MEMORY_TABLE_ENTRIES - 1);
      CS_AppData.HkPacket.Payload.CommandErrorCounter++;
    }
  } // end InProgress if

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable one Memory entry. The disable also clears the entry's partial checksum; the enable does
// not, which is the same asymmetry every disable in CS has.
I32 CS_DisableEntryIDMemoryCmd(CS_DisableEntryIDMemoryCmd_t *CmdPtr)
{
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;
  CS_Def_EepromMemory_Table_Entry_t *DefEntry = NULL;
  CS_TableWrapper_t *tw = &CS_AppData.Tbl[CS_ChecksumType_MEMORY_TABLE];
  U16 EntryID = 0;
  U32 State = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t

  if (CS_CheckRecomputeOneshot() == FALSE) {
    EntryID = CmdPtr->Payload.EntryID;
    ResultsEntry = CS_GetMemoryResEntry(EntryID);

    if (ResultsEntry == NULL) {
      State = CS_ChecksumState_UNDEFINED;
    } else {
      State = ResultsEntry->State;
    }

    if (CS_StateValid(State)) {
      DefEntry = CS_GetMemoryDefEntry(EntryID);

      ResultsEntry->State = CS_ChecksumState_DISABLED;
      ResultsEntry->TempChecksumValue = 0;
      ResultsEntry->ByteOffset = 0;

      CFE_EVS_SendEvent(CS_DISABLE_MEMORY_ENTRY_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Checksumming of Memory Entry ID %d is Disabled", EntryID);

      State = CS_SetDefEntryState(tw, DefEntry, CS_ChecksumState_DISABLED);
      if (!CS_StateValid(State)) {
        CFE_EVS_SendEvent(CS_DISABLE_MEMORY_DEF_EMPTY_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "CS unable to update memory definition table for entry %d, State: %d",
                          EntryID, State);
      }

      CS_AppData.HkPacket.Payload.CommandCounter++;
    } else {
      CFE_EVS_SendEvent(CS_DISABLE_MEMORY_INVALID_ENTRY_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Disable Memory entry failed, invalid Entry ID:  %d, State: %d, Max ID: %d",
                        EntryID, State, CS_MAX_NUM_MEMORY_TABLE_ENTRIES - 1);
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
I32 CS_GetEntryIDMemoryCmd(CS_GetEntryIDMemoryCmd_t *CmdPtr)
{
  // NASA's declaration ORDER and its `= NULL` differ from the EEPROM twin's here: the pointer comes
  // first and is initialised. Carried as NASA wrote it, because a twin pair is only evidence of
  // anything if the differences in the translation are exactly the differences upstream.
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;
  U16 Loop = 0;
  Bool EntryFound = FALSE;

  Loop = 0;
  while (TRUE) {
    ResultsEntry = CS_GetMemoryResEntry(Loop);
    if (ResultsEntry == NULL) {
      break;
    }

    if (ResultsEntry->State != CS_ChecksumState_EMPTY &&
        ResultsEntry->StartAddress <= CmdPtr->Payload.Address &&
        CmdPtr->Payload.Address < ResultsEntry->StartAddress + ResultsEntry->NumBytesToChecksum) {
      CFE_EVS_SendEvent(CS_GET_ENTRY_ID_MEMORY_INF_EID, CFE_EVS_EventType_INFORMATION,
                        "Memory Found Address 0x%08X in Entry ID %d", CmdPtr->Payload.Address, Loop);
      EntryFound = TRUE;
    }

    ++Loop;
  }

  if (EntryFound == FALSE) {
    CFE_EVS_SendEvent(CS_GET_ENTRY_ID_MEMORY_NOT_FOUND_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Address 0x%08X was not found in Memory table", CmdPtr->Payload.Address);
  }

  CS_AppData.HkPacket.Payload.CommandCounter++;

  return CFE_SUCCESS;
}
#endif
