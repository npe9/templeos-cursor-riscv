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
// CHECKSUM'S ARITHMETIC -- the 1:1 translation of NASA's fsw/src/cs_compute.c, 825 lines and
// fourteen functions. This is where CS actually reads memory.
//
// ONE CHUNKING ENGINE, THREE TYPED WRAPPERS AROUND IT. CS_DoChecksumChunk takes a
// CS_LocalChecksumState_t -- a buffer address, a total size, how far through it the last cycle
// got, and the partial CRC -- CRCs at most CS_AppData.MaxBytesPerCycle of it, and writes the
// position and partial result back. CS_ComputeEepromMemory, CS_ComputeTables and CS_ComputeApp
// each load that state out of a results entry, call the engine once, and store it back. The
// difference between them is entirely in WHERE the buffer address comes from:
//
//   EEPROM / Memory / code segments  the results entry's own StartAddress. Nothing to look up.
//   Tables                          CFE_TBL_GetAddress EVERY CYCLE, because table services may
//                                   have moved the buffer -- and released again at the end of
//                                   the same cycle. The cached SIZE is reused, the address never.
//   Apps                            CFE_ES_GetModuleInfo, re-read whenever the cached address is
//                                   NULL or the walk has wrapped.
//
// THE FOUR CHILD TASKS ARE THE REST OF THE FILE. A ground-commanded recompute cannot run inside
// a cycle -- it must finish the whole entry -- so it runs out of line, with OS_TaskDelay between
// chunks, and the three recompute tasks all follow one pattern: disable the entry so the
// background walk cannot touch it, clear its partial state, disable the matching DEFINITION
// entry too, loop until done, then restore both. CS_OneShotChildTask is the odd one: it has no
// table entry at all and CRCs a bare address the ground named.
//
// WHY THE BYTES HAVE TO BE DRIVER-OWNED. CFE_ES_CalculateCRC is handed a raw pointer here, so
// this is the file the note at the top of cs_msg.HC is about: the native oracle and the RISC-V
// guest must be CRC-ing identical bytes or the number differs and nothing says why. Every
// address the exercises feed in points into a driver buffer both halves fill the same way.
#ifndef CS_COMPUTE_HC
#define CS_COMPUTE_HC

/*******************************************************************************/
// Local helper structure to keep state of checksum calculation
// This allows the checksum calculation to be consolidated into a
// common helper function for memory, apps, and tables.
//
// NASA DECLARES THIS IN THE .c, not a header, so it is private to this file in C and merely
// file-scope here. 32 bytes with four of tail padding, measured.
class CS_LocalChecksumState_t
{
  U8 *BufferAddr;
  I64 TotalSize;
  I64 CurrOffset;
  U32 ResultBuffer;
  U8 _pad0[4]; // C rounds the object to 8, for BufferAddr
};

/*******************************************************************************/
// Local helper function
//
// `>=`, NOT `==`, and that is what makes CS_DoChecksumChunk's "start again at beginning" arm
// reachable: a size that SHRANK between cycles leaves CurrOffset past the end.
Bool CS_IsChecksumComplete(CS_LocalChecksumState_t *State)
{
  return State->CurrOffset >= State->TotalSize;
}

/*******************************************************************************/
// Local helper function
//
// THE WHOLE BUDGET MECHANISM, in fifteen lines. Note it always CRCs SOMETHING: with
// NumBytesThisCycle clamped to MaxBytesPerCycle and a zero TotalSize it calls
// CFE_ES_CalculateCRC with a length of zero, which returns the input CRC unchanged. So an empty
// entry is complete after one cycle rather than looping.
U0 CS_DoChecksumChunk(CS_LocalChecksumState_t *State)
{
  I64 NumBytesThisCycle;
  U32 NewChecksumValue;

  if (State->CurrOffset >= State->TotalSize) {
    // Start again at beginning
    State->CurrOffset = 0;
    State->ResultBuffer = 0;
  }

  NumBytesThisCycle = State->TotalSize - State->CurrOffset;

  // Limit to the configured max
  if (NumBytesThisCycle > CS_AppData.MaxBytesPerCycle) {
    NumBytesThisCycle = CS_AppData.MaxBytesPerCycle;
  }

  NewChecksumValue = CFE_ES_CalculateCRC(State->BufferAddr + State->CurrOffset, NumBytesThisCycle,
                                         State->ResultBuffer, CS_DEFAULT_ALGORITHM);

  // Export all data
  State->CurrOffset = State->CurrOffset + NumBytesThisCycle;
  State->ResultBuffer = NewChecksumValue;
}

/*******************************************************************************/
// Local helper function
//
// THE BASELINE IS SET BY THE FIRST COMPLETED WALK, not by a command -- `ComputedYet` is the flag
// that says which case this is, and it is a uint16 in all three results-entry layouts, which is
// why this takes a U16 * rather than a Bool *. Only a COMPLETE pass compares or records; a
// partial one returns CFE_SUCCESS and leaves the reference alone.
I32 CS_CheckOrUpdateReference(CS_LocalChecksumState_t *State, U16 *RefValid, U32 *CompareBuffer)
{
  I32 Status;

  Status = CFE_SUCCESS;

  if (CS_IsChecksumComplete(State)) {
    if (*RefValid) {
      // Comparison value was computed before, so check against it
      if (*CompareBuffer != State->ResultBuffer) {
        // Not Matching is an error
        Status = CS_ERROR;
      }
    } else {
      // First time, so update the reference value for future use
      *CompareBuffer = State->ResultBuffer;
      *RefValid = TRUE;
    }
  }

  return Status;
}

/*******************************************************************************/
// Local helper function
//
// `>= CFE_SUCCESS`, NOT `== CFE_SUCCESS`, and the comment further down in
// CS_RefreshTableData says why: CFE_TBL_GetAddress returns CFE_TBL_INFO_UPDATED -- a positive
// INFO code, not an error -- when the buffer changed since the last look, and that is a success
// that also means "re-read the size".
I32 CS_GetTableAddr(CS_LocalChecksumState_t *State, I16 LocalHandle) // CFE_TBL_Handle_t
{
  I32 Status;
  U8 *Addr;

  Status = CFE_TBL_GetAddress(&Addr, LocalHandle);

  if (Status >= CFE_SUCCESS) {
    State->BufferAddr = Addr;
  } else {
    State->BufferAddr = NULL;
  }

  return Status;
}

/*******************************************************************************/
// Local helper function
U0 CS_ReleaseTableAddr(U32 LocalId, U8 *Name) // CFE_TBL_HandleId_t
{
  I32 Result;
  I16 LocalHandle; // CFE_TBL_Handle_t

  LocalHandle = CFE_TBL_HandleFromID(LocalId);

  Result = CFE_TBL_ReleaseAddress(LocalHandle);
  if (Result != CFE_SUCCESS) {
    CFE_EVS_SendEvent(CS_COMPUTE_TABLES_RELEASE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "CS Tables: Could not release addresss for table %s, returned: 0x%08X", Name,
                      Result);
  }
}

/*******************************************************************************/
// Local helper function
//
// NASA'S MISSPELLING "addresss" above is kept, because an event string is a ground-system
// interface and a ground display that greps for it would stop matching.
I32 CS_RefreshTableSize(CS_LocalChecksumState_t *State, U8 *Name)
{
  CFE_TBL_Info_t TblInfo;
  I32 Result;

  // First do GetInfo, this looks up the table by name
  Result = CFE_TBL_GetInfo(&TblInfo, Name);
  if (Result >= CFE_SUCCESS) {
    State->TotalSize = TblInfo.Size;
    Result = CFE_SUCCESS;
  } else {
    State->TotalSize = 0;
    Result = CS_ERR_NOT_FOUND;
  }

  return Result;
}

/*******************************************************************************/
// Local helper function
//
// THE STALE-HANDLE PATH. CS holds a handle to someone else's table across cycles; if that table
// was unregistered and re-registered, the handle is a number that now means something else or
// nothing. This unregisters CS's own share, takes a fresh one by name, and re-reads the address.
// It is the one place the I16 signedness of CFE_TBL_Handle_t is load-bearing -- see the note on
// CS_TableWrapper_t in cs_global.HC.
I32 CS_RefreshTableHandleAndAddress(CS_LocalChecksumState_t *State, I16 *LocalHandle, U8 *Name)
{
  I32 Result;

  // This means our local handle went stale, unregister it before getting a new one
  if (CFE_TBL_HANDLE_IS_VALID(*LocalHandle)) {
    CFE_TBL_Unregister(*LocalHandle);
  }

  Result = CFE_TBL_Share(LocalHandle, Name);
  if (Result < CFE_SUCCESS) {
    *LocalHandle = CFE_TBL_BAD_TABLE_HANDLE;
  } else {
    // Try getting an address again, we still do not have one
    Result = CS_GetTableAddr(State, *LocalHandle);
  }

  if (Result >= CFE_SUCCESS) {
    Result = CFE_SUCCESS;
  }

  return Result;
}

/*******************************************************************************/
// Local helper function
//
// WHAT IS CACHED AND WHAT IS NOT, which is the whole subtlety of checksumming someone else's
// table: the SIZE is kept between cycles, the ADDRESS never is. Table services may swap the
// active buffer under CS at any time, so an address held across a cycle boundary could be CRCing
// the inactive copy.
I32 CS_RefreshTableData(CS_LocalChecksumState_t *State, U32 *LocalId, U8 *Name) // CFE_TBL_HandleId_t *
{
  I32 Status;
  I16 LocalHandle; // CFE_TBL_Handle_t

  Status = CFE_SUCCESS;

  // Always refresh the address (we do not hold it between cycles, but we do cache it)
  // Notably if this returns CFE_SUCCESS then it means there are no known changes
  //  since the last time we checked this table.
  if (State->TotalSize != 0) {
    LocalHandle = CFE_TBL_HandleFromID(*LocalId);
    Status = CS_GetTableAddr(State, LocalHandle);
  } else {
    LocalHandle = CFE_TBL_BAD_TABLE_HANDLE;
  }

  // NOTE: This intentionally is bypassed only in plain CFE_SUCCESS, meaning that info
  //  codes like CFE_TBL_INFO_UPDATED will also trigger refreshing the size info
  //  The intent is to save the cost of refreshing the size info if the value we have
  //  is still valid.
  if (Status != CFE_SUCCESS || State->TotalSize == 0) {
    Status = CS_RefreshTableSize(State, Name);
  }

  // Check if the table handle needs a refresh
  if (Status == CFE_SUCCESS && State->BufferAddr == NULL) {
    Status = CS_RefreshTableHandleAndAddress(State, &LocalHandle, Name);
  }

  if (Status == CFE_SUCCESS) {
    *LocalId = CFE_TBL_HandleToID(LocalHandle);
  } else {
    *LocalId = CFE_TBL_HANDLEID_UNDEFINED;
  }

  return Status;
}

/*******************************************************************************/
// Local helper function
//
// AN APP OR A LIBRARY. CS's app table does not distinguish them -- a name that is not a running
// app is tried as a library, which is how a mission checksums code that has no task of its own.
// And AddressesAreValid is a PLATFORM property: a PSP that cannot report where a module's code
// landed makes this a DEBUG event and a CS_ERROR rather than a failure, because nothing is wrong.
//
// CFE_ES_MEMOFFSET_TO_SIZET and CFE_ES_MEMADDRESS_TO_PTR are casts in NASA's C; this port writes
// them out, the same way mm_dump.HC does, because HolyC has no token pasting.
I32 CS_RefreshAppSizeAndAddr(CS_LocalChecksumState_t *State, U8 *AppName)
{
  U32 ResourceID; // CFE_ResourceId_t
  CFE_ES_AppInfo_t AppInfo;
  I32 Result;

  AppInfo.AddressesAreValid = FALSE;
  ResourceID = CFE_RESOURCEID_UNDEFINED;

  Result = CFE_ES_GetAppIDByName(&ResourceID, AppName);
  if (Result == CFE_ES_ERR_NAME_NOT_FOUND) {
    // Also check for a matching library name
    Result = CFE_ES_GetLibIDByName(&ResourceID, AppName);
  }

  if (Result == CFE_SUCCESS) {
    // We got a valid ResourceID, so get the Resource info
    Result = CFE_ES_GetModuleInfo(&AppInfo, ResourceID);

    // We got a valid ResourceID and good App info, so check the for valid addresses
    if (Result == CFE_SUCCESS && !AppInfo.AddressesAreValid) {
      CFE_EVS_SendEvent(CS_COMPUTE_APP_PLATFORM_DBG_EID, CFE_EVS_EventType_DEBUG,
                        "CS cannot get a valid address for %s, due to the platform", AppName);

      Result = CS_ERROR;
    }
  }

  if (Result == CFE_SUCCESS) {
    // Push in the data from the module info
    State->TotalSize = AppInfo.CodeSize;  // CFE_ES_MEMOFFSET_TO_SIZET
    State->BufferAddr = AppInfo.CodeAddress(U8 *); // CFE_ES_MEMADDRESS_TO_PTR
    State->CurrOffset = 0;
  } else {
    // Something failed -- either invalid ResourceID, bad App info, or invalid addresses, so notify ground
    CFE_EVS_SendEvent(CS_COMPUTE_APP_ERR_EID, CFE_EVS_EventType_ERROR,
                      "CS Apps: Problems getting module %s info, Result: 0x%08X, AddressValid: %d",
                      AppName, Result, AppInfo.AddressesAreValid);

    Result = CS_ERR_NOT_FOUND;
  }

  return Result;
}

/*******************************************************************************/
// CS function that computes the checksum for EEPROM, Memory, OS
// and cFE core code segments
//
// NOTE IT WRITES StartAddress BACK, unchanged, every cycle -- `ResultsEntry->StartAddress =
// State.BufferAddr`. That is a no-op for EEPROM and Memory, where the address came from this same
// field, and it is NOT one in CS_ComputeTables, which shares the export block's shape. Kept 1:1.
I32 CS_ComputeEepromMemory(CS_Res_EepromMemory_Table_Entry_t *ResultsEntry, U32 *ComputedCSValue,
                           Bool *DoneWithEntry)
{
  I32 Status;
  CS_LocalChecksumState_t State;

  Status = CFE_SUCCESS;

  MemSet(&State, 0, sizeof(CS_LocalChecksumState_t));

  State.BufferAddr = ResultsEntry->StartAddress(U8 *); // CFE_ES_MEMADDRESS_TO_PTR
  State.TotalSize = ResultsEntry->NumBytesToChecksum;
  State.CurrOffset = ResultsEntry->ByteOffset;

  if (!CS_IsChecksumComplete(&State)) {
    // resume where left off
    State.ResultBuffer = ResultsEntry->TempChecksumValue;
  }

  CS_DoChecksumChunk(&State);

  // Export all values to resume next time
  ResultsEntry->TempChecksumValue = State.ResultBuffer;
  ResultsEntry->StartAddress = State.BufferAddr;
  ResultsEntry->ByteOffset = State.CurrOffset;
  ResultsEntry->NumBytesToChecksum = State.TotalSize;

  // mirror the value to the supplied register
  *ComputedCSValue = State.ResultBuffer;

  // Check against the previous value, if applicable
  Status = CS_CheckOrUpdateReference(&State, &ResultsEntry->ComputedYet, &ResultsEntry->ComparisonValue);

  *DoneWithEntry = CS_IsChecksumComplete(&State);

  return Status;
}

/*******************************************************************************/
// CS function that computes the checksum for Tables
//
// THE SECOND memset IS THE INTERESTING LINE. On the failure arm NASA clears State again, AFTER
// the event -- which zeroes BufferAddr, so the release below is skipped, and zeroes TotalSize,
// so the next cycle re-looks-up the size instead of trusting a stale one. A translation that
// dropped it would leak a table address reference per failed cycle.
I32 CS_ComputeTables(CS_Res_Tables_Table_Entry_t *ResultsEntry, U32 *ComputedCSValue, Bool *DoneWithEntry)
{
  I32 Status;
  CS_LocalChecksumState_t State;

  MemSet(&State, 0, sizeof(CS_LocalChecksumState_t));

  // For tables, This size will be nonzero if we have been here before
  // Note we do NOT used the cached address, only the cached size.  The address
  //  needs to come from tbl services every cycle, since it can be updated
  State.TotalSize = ResultsEntry->NumBytesToChecksum;

  // By the time we get here, we know we have an enabled entry
  Status = CS_RefreshTableData(&State, &ResultsEntry->TblHandleID, ResultsEntry->Name);

  if (Status != CFE_SUCCESS || State.BufferAddr == NULL) {
    CFE_EVS_SendEvent(CS_COMPUTE_TABLES_ERR_EID, CFE_EVS_EventType_ERROR,
                      "CS Tables: Problem Getting table %s: Status=0x%08X", ResultsEntry->Name,
                      Status);

    MemSet(&State, 0, sizeof(CS_LocalChecksumState_t));

    // pass generic error to the caller, since the underlying one was logged already
    Status = CS_ERR_NOT_FOUND;
  } else {
    // If the address and size has NOT changed since our last visit, resume checksumming
    if (ResultsEntry->StartAddress == State.BufferAddr &&
        ResultsEntry->NumBytesToChecksum == State.TotalSize) {
      State.CurrOffset = ResultsEntry->ByteOffset;
      State.ResultBuffer = ResultsEntry->TempChecksumValue;
    }

    CS_DoChecksumChunk(&State);

    // mirror the value to the supplied register
    *ComputedCSValue = State.ResultBuffer;

    // Check against the previous value, if applicable
    Status = CS_CheckOrUpdateReference(&State, &ResultsEntry->ComputedYet, &ResultsEntry->ComparisonValue);
  }

  // If we got a table address, we need to release it (always)
  if (State.BufferAddr != NULL) {
    // We are done with the table for this cycle, so we need to release the address
    CS_ReleaseTableAddr(ResultsEntry->TblHandleID, ResultsEntry->Name);
  }

  // Export all values to resume next time
  ResultsEntry->TempChecksumValue = State.ResultBuffer;
  ResultsEntry->StartAddress = State.BufferAddr;
  ResultsEntry->ByteOffset = State.CurrOffset;
  ResultsEntry->NumBytesToChecksum = State.TotalSize;

  *DoneWithEntry = CS_IsChecksumComplete(&State);

  return Status;
}

/*******************************************************************************/
// CS function that computes the checksum for Apps
I32 CS_ComputeApp(CS_Res_App_Table_Entry_t *ResultsEntry, U32 *ComputedCSValue, Bool *DoneWithEntry)
{
  I32 Status;
  CS_LocalChecksumState_t State;

  Status = CFE_SUCCESS;

  MemSet(&State, 0, sizeof(CS_LocalChecksumState_t));

  State.BufferAddr = ResultsEntry->StartAddress(U8 *); // CFE_ES_MEMADDRESS_TO_PTR
  State.TotalSize = ResultsEntry->NumBytesToChecksum;
  State.CurrOffset = ResultsEntry->ByteOffset;

  if (State.BufferAddr == NULL || CS_IsChecksumComplete(&State)) {
    Status = CS_RefreshAppSizeAndAddr(&State, ResultsEntry->Name);
  } else {
    // Already got address and size, resume where left off
    State.ResultBuffer = ResultsEntry->TempChecksumValue;
    Status = CFE_SUCCESS;
  }

  if (Status == CFE_SUCCESS) {
    CS_DoChecksumChunk(&State);

    // Export all values to resume next time
    ResultsEntry->TempChecksumValue = State.ResultBuffer;
    ResultsEntry->StartAddress = State.BufferAddr;
    ResultsEntry->ByteOffset = State.CurrOffset;
    ResultsEntry->NumBytesToChecksum = State.TotalSize;

    // mirror the value to the supplied register
    *ComputedCSValue = State.ResultBuffer;

    // Check against the previous value, if applicable
    Status = CS_CheckOrUpdateReference(&State, &ResultsEntry->ComputedYet, &ResultsEntry->ComparisonValue);
  } // end if got module id ok

  *DoneWithEntry = CS_IsChecksumComplete(&State);

  return Status;
}

/*******************************************************************************/
// CS child task for recomputing EEPROM and Memory entry baselines
//
// THE SHAPE ALL THREE RECOMPUTE TASKS SHARE: disable the results entry so the background walk
// cannot touch it, clear its partial state so the next pass starts from zero rather than
// comparing against the old baseline, disable the matching DEFINITION entry too, loop with a
// delay until the whole entry is done, then restore both states.
//
// AND THE DEFINITION ENTRY IS MATCHED BY ADDRESS, NOT BY INDEX. `ResultsEntry->StartAddress ==
// DefEntry->StartAddress` -- because the results table and the definition table can disagree
// after a ground table load, and disabling the wrong definition entry would silently stop
// checksumming a region nobody asked to stop. If they disagree, DefEntry is set back to NULL and
// nothing is restored later, which is why that assignment is in the `else`.
U0 CS_RecomputeEepromMemoryChildTask()
{
  U32 NewChecksumValue = 0;
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;
  U16 EntryID = 0;
  U32 PreviousState = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t
  Bool DoneWithEntry = FALSE;
  U32 PreviousDefState = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t
  CS_Def_EepromMemory_Table_Entry_t *DefEntry = NULL;
  CS_TableWrapper_t *tw;

  tw = &CS_AppData.Tbl[CS_AppData.ChildTaskTable];
  EntryID = CS_AppData.ChildTaskEntryID;
  ResultsEntry = CS_AppData.RecomputeEepromMemoryEntryPtr;

  // we want to  make sure that the entry isn't being checksummed in the
  //  background at the same time we are recomputing
  PreviousState = ResultsEntry->State;
  ResultsEntry->State = CS_ChecksumState_DISABLED;

  // Set entry as if this is the first time we are computing the checksum,
  //    since we want the entry to take on the new value

  ResultsEntry->ByteOffset = 0;
  ResultsEntry->TempChecksumValue = 0;
  ResultsEntry->ComputedYet = FALSE;

  // Update the definition table entry as well.  We need to determine which memory type is
  //    being updated as well as which entry in the table is being updated.
  if (CS_CheckTableId(tw, CS_ChecksumType_EEPROM_TABLE) ||
      CS_CheckTableId(tw, CS_ChecksumType_MEMORY_TABLE)) {
    DefEntry = CS_GetDefEntryAddr(tw, EntryID);
  }

  if (DefEntry != NULL && ResultsEntry->StartAddress == DefEntry->StartAddress) {
    PreviousDefState = CS_SetDefEntryState(tw, DefEntry, CS_ChecksumState_DISABLED);
  } else {
    DefEntry = NULL;
  }

  while (!DoneWithEntry) {
    CS_ComputeEepromMemory(ResultsEntry, &NewChecksumValue, &DoneWithEntry);

    OS_TaskDelay(CS_CHILD_TASK_DELAY);
  }

  // The new checksum value is stored in the table by the above functions

  // restore the entry's previous state
  ResultsEntry->State = PreviousState;

  // Restore the definition table if we found one earlier
  if (DefEntry != NULL) {
    CS_SetDefEntryState(tw, DefEntry, PreviousDefState);
  }

  // Update reported value in HK TLM, if applicable
  if (tw->BaselineValue) {
    *tw->BaselineValue = NewChecksumValue;
  }

  // send event message
  // NASA spells this one "0X%08X" with a capital X in the literal prefix, unlike every other
  // baseline event in CS. Kept, because the event text is a ground-system interface.
  CFE_EVS_SendEvent(CS_RECOMPUTE_FINISH_EEPROM_MEMORY_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "%s entry %d recompute finished. New baseline is 0X%08X",
                    CS_GetTableTypeAsString(tw), EntryID, NewChecksumValue);

  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  CFE_ES_ExitChildTask();
}

/*******************************************************************************/
// CS child task for recomputing baselines for Apps
//
// Status STARTS AS CS_ERROR, not CFE_SUCCESS, and it is read after the loop -- so the ONE case
// where the loop body never runs would report success. It cannot happen here (DoneWithEntry is
// FALSE on entry), which is why the initialiser looks arbitrary; it is the defensive-write shape
// recorded for MM, kept verbatim.
U0 CS_RecomputeAppChildTask()
{
  U32 NewChecksumValue = 0;
  CS_Res_App_Table_Entry_t *ResultsEntry = NULL;
  U32 PreviousState = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t
  Bool DoneWithEntry = FALSE;
  I32 Status = CS_ERROR;
  U32 PreviousDefState = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t
  CS_Def_App_Table_Entry_t *DefTblEntry = NULL;

  CS_TableWrapper_t *tw = &CS_AppData.Tbl[CS_ChecksumType_APP_TABLE];

  // Get the variables to use from the global data
  ResultsEntry = CS_AppData.RecomputeAppEntryPtr;

  // we want to  make sure that the entry isn't being checksummed in the
  //  background at the same time we are recomputing

  PreviousState = ResultsEntry->State;
  ResultsEntry->State = CS_ChecksumState_DISABLED;

  // Set entry as if this is the first time we are computing the checksum,
  //    since we want the entry to take on the new value

  ResultsEntry->ByteOffset = 0;
  ResultsEntry->TempChecksumValue = 0;
  ResultsEntry->ComputedYet = FALSE;

  // Update the definition table entry as well.  We need to determine which memory type is
  //    being updated as well as which entry in the table is being updated.

  CS_GetAppDefTblEntryByName(&DefTblEntry, ResultsEntry->Name);

  if (DefTblEntry != NULL) {
    PreviousDefState = CS_SetDefEntryState(tw, DefTblEntry, CS_ChecksumState_DISABLED);
  }

  while (!DoneWithEntry) {
    Status = CS_ComputeApp(ResultsEntry, &NewChecksumValue, &DoneWithEntry);

    if (Status == CS_ERR_NOT_FOUND) {
      break;
    }

    OS_TaskDelay(CS_CHILD_TASK_DELAY);
  }
  // The new checksum value is stored in the table by the above functions

  // restore the entry's state
  ResultsEntry->State = PreviousState;

  // Restore the definition table if we found one earlier
  if (DefTblEntry != NULL) {
    CS_SetDefEntryState(tw, DefTblEntry, PreviousDefState);
  }

  if (Status == CS_ERR_NOT_FOUND) {
    CFE_EVS_SendEvent(CS_RECOMPUTE_ERROR_APP_ERR_EID, CFE_EVS_EventType_ERROR,
                      "App %s recompute failed. Could not get address", ResultsEntry->Name);
  } else {
    // send event message
    CFE_EVS_SendEvent(CS_RECOMPUTE_FINISH_APP_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "App %s recompute finished. New baseline is 0x%08X", ResultsEntry->Name,
                      NewChecksumValue);
  }

  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  CFE_ES_ExitChildTask();
}

/*******************************************************************************/
// CS child task for recomputing baselines for Tables
//
// THE ORDER DIFFERS FROM THE APP TASK, and it is NASA's: this one sends the event BEFORE
// restoring the entry's state, the app one restores first and then sends. Nothing observable
// depends on it -- no event here reads either state -- but the two functions are otherwise
// line-for-line twins, so the difference is worth naming rather than quietly normalising.
U0 CS_RecomputeTablesChildTask()
{
  U32 NewChecksumValue = 0;
  CS_Res_Tables_Table_Entry_t *ResultsEntry = NULL;
  U32 PreviousState = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t
  Bool DoneWithEntry = FALSE;
  I32 Status = CS_ERROR;
  U32 PreviousDefState = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t
  CS_Def_Tables_Table_Entry_t *DefTblEntry = NULL;

  CS_TableWrapper_t *tw = &CS_AppData.Tbl[CS_ChecksumType_TABLES_TABLE];

  // Get the variables to use from the global data
  ResultsEntry = CS_AppData.RecomputeTablesEntryPtr;

  // we want to  make sure that the entry isn't being checksummed in the
  //  background at the same time we are recomputing

  PreviousState = ResultsEntry->State;
  ResultsEntry->State = CS_ChecksumState_DISABLED;

  // Set entry as if this is the first time we are computing the checksum,
  //  since we want the entry to take on the new value

  ResultsEntry->ByteOffset = 0;
  ResultsEntry->TempChecksumValue = 0;
  ResultsEntry->ComputedYet = FALSE;

  // Update the definition table entry as well.  We need to determine which memory type is
  //  being updated as well as which entry in the table is being updated.
  CS_GetTableDefTblEntryByName(&DefTblEntry, ResultsEntry->Name);
  if (DefTblEntry != NULL) {
    PreviousDefState = CS_SetDefEntryState(tw, DefTblEntry, CS_ChecksumState_DISABLED);
  }

  while (!DoneWithEntry) {
    Status = CS_ComputeTables(ResultsEntry, &NewChecksumValue, &DoneWithEntry);

    if (Status == CS_ERR_NOT_FOUND) {
      break;
    }

    OS_TaskDelay(CS_CHILD_TASK_DELAY);
  }

  // The new checksum value is stored in the table by the above functions
  if (Status == CS_ERR_NOT_FOUND) {
    CFE_EVS_SendEvent(CS_RECOMPUTE_ERROR_TABLES_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Table %s recompute failed. Could not get address", ResultsEntry->Name);
  } else {
    // send event message
    CFE_EVS_SendEvent(CS_RECOMPUTE_FINISH_TABLES_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Table %s recompute finished. New baseline is 0x%08X", ResultsEntry->Name,
                      NewChecksumValue);
  }

  // restore the entry's state
  ResultsEntry->State = PreviousState;

  // Restore the definition table if we found one earlier
  if (DefTblEntry != NULL) {
    CS_SetDefEntryState(tw, DefTblEntry, PreviousDefState);
  }

  CS_AppData.HkPacket.Payload.RecomputeInProgress = FALSE;
  CFE_ES_ExitChildTask();
}

/*******************************************************************************/
// CS child task for getting the checksum on an area of memory
//
// THE ONLY CHECKSUM IN CS WITH NO TABLE ENTRY. The ground names an address, a size and a budget;
// this walks it to the end in one task and reports the number. It does NOT use
// CS_LocalChecksumState_t or CS_DoChecksumChunk -- it keeps its own three variables -- and the
// reason is that there is nothing to resume: a one-shot either finishes or is cancelled.
//
// AND MaxBytesPerCycle COMES FROM HOUSEKEEPING, not from CS_AppData.MaxBytesPerCycle. The command
// handler in cs_cmds.c is what substitutes the platform default when the ground sends zero, so a
// zero reaching here would make NumBytesThisCycle zero and this loop would never terminate.
U0 CS_OneShotChildTask()
{
  U32 NewChecksumValue = 0;
  I64 NumBytesRemainingCycles = 0;
  I64 NumBytesThisCycle = 0;
  U64 FirstAddrThisCycle = 0; // cpuaddr
  I64 MaxBytesPerCycle = 0;

  NewChecksumValue = 0;
  NumBytesRemainingCycles = CS_AppData.HkPacket.Payload.LastOneShotSize;
  FirstAddrThisCycle = CS_AppData.HkPacket.Payload.LastOneShotAddress;
  MaxBytesPerCycle = CS_AppData.HkPacket.Payload.LastOneShotMaxBytesPerCycle;

  while (NumBytesRemainingCycles > 0) {
    if (MaxBytesPerCycle < NumBytesRemainingCycles)
      NumBytesThisCycle = MaxBytesPerCycle;
    else
      NumBytesThisCycle = NumBytesRemainingCycles;

    NewChecksumValue = CFE_ES_CalculateCRC(FirstAddrThisCycle(U8 *), NumBytesThisCycle,
                                           NewChecksumValue, CS_DEFAULT_ALGORITHM);

    // Update the remainders for the next cycle
    FirstAddrThisCycle += NumBytesThisCycle;
    NumBytesRemainingCycles -= NumBytesThisCycle;

    OS_TaskDelay(CS_CHILD_TASK_DELAY);
  }

  // Checksum Calculation is done!

  // put the new checksum value in the baseline
  CS_AppData.HkPacket.Payload.LastOneShotChecksum = NewChecksumValue;

  // send event message
  CFE_EVS_SendEvent(CS_ONESHOT_FINISHED_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "OneShot checksum on Address: 0x%08X, size %d completed. Checksum =  0x%08X",
                    CS_AppData.HkPacket.Payload.LastOneShotAddress,
                    CS_AppData.HkPacket.Payload.LastOneShotSize,
                    CS_AppData.HkPacket.Payload.LastOneShotChecksum);

  CS_AppData.HkPacket.Payload.OneShotInProgress = FALSE;
  CS_AppData.ChildTaskID = CFE_ES_TASKID_UNDEFINED;

  CFE_ES_ExitChildTask();
}
#endif
