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
// CHECKSUM'S UTILITIES -- the 1:1 translation of NASA's fsw/src/cs_utils.c, 1,168 lines and
// twenty-six functions, plus the nine `static inline`s in cs_utils.h that the whole app reaches
// through.
//
// THIS IS THE LARGEST SINGLE SOURCE IN ANY cFS APP SO FAR, and it is also the one that makes CS's
// three middle files a CYCLE: everything in cs_compute.c and cs_table_processing.c calls into
// here, and three functions here call back out -- CS_ComputeEepromMemory, CS_ComputeTables and
// CS_ComputeApp in cs_compute.c, and CS_HandleTableUpdate in cs_table_processing.c. All four are
// forward-declared below and defined in those files, which is the same arrangement md_app.HC and
// md_dispatch.HC use for MD's two-file cycle. docs/CFS_PLAN.md records why no stand-in is used:
// every one of the four is real logic, so a stand-in would be a claim about CS rather than a seam.
//
// THE SIX "BACKGROUND" FUNCTIONS ARE THE APP. CS_BackgroundCfeCore, _OS, _Eeprom, _Memory,
// _Tables and _App are one per checksum type, called one per wakeup by the dispatcher, and each
// returns whether this cycle's byte budget has been spent. They are near-identical by design --
// NASA's own duplication, not a translation artefact -- and the differences between them are the
// interesting part:
//
//   cFE core / OS   ONE entry, no table. Walk a single results record and stop.
//   EEPROM          a table AND a running total: when the walk reaches the end it sums every
//                   entry's ComparisonValue into EepromBaseline. Memory has NO such total,
//                   and the asymmetry is NASA's.
//   Tables / App    can fail with CS_ERR_NOT_FOUND -- the named table is not registered or the
//                   named app is not running -- which the other four cannot, and which is
//                   treated as "done with this entry" rather than as an error to retry.
//
// AND THE EVENT TEXT IS WHY TWO OF THEM NEED CARE IN THE EXERCISE: EEPROM's and Memory's
// miscompare events print `Address 0x%lx`, a real pointer. Everything else prints a checksum or
// a name. See the note at the top of cs_msg.HC: the exercises drive those two through
// driver-owned buffers and assert a COMPARISON rather than the value.
#ifndef CS_UTILS_HC
#define CS_UTILS_HC

// The three calls out of this file that close the cycle, defined in cs_compute.HC, plus the one
// in cs_table_processing.HC. NASA reaches them through cs_compute.h and cs_table_processing.h.
I32 CS_ComputeEepromMemory(CS_Res_EepromMemory_Table_Entry_t *ResultsEntry, U32 *ComputedCSValue,
                           Bool *DoneWithEntry);
I32 CS_ComputeTables(CS_Res_Tables_Table_Entry_t *ResultsEntry, U32 *ComputedCSValue,
                     Bool *DoneWithEntry);
I32 CS_ComputeApp(CS_Res_App_Table_Entry_t *ResultsEntry, U32 *ComputedCSValue, Bool *DoneWithEntry);
I32 CS_HandleTableUpdate(CS_TableWrapper_t *tw);

// THREE FORWARD DECLARATIONS WITHIN THIS FILE, because NASA's order puts callers before callees
// twice: cs_utils.h's eight inlines index through CS_GetDefEntryAddr and CS_GetResEntryAddr,
// which cs_utils.c defines after them, and CS_SetDefEntryState calls
// CS_ResetTablesTblResultEntry, which is 700 lines further down. NASA gets all three from
// cs_utils.h; HolyC needs them stated.
U8 *CS_GetDefEntryAddr(CS_TableWrapper_t *tw, U16 EntryId);
U8 *CS_GetResEntryAddr(CS_TableWrapper_t *tw, U16 EntryId);
U0 CS_ResetTablesTblResultEntry(CS_Res_Tables_Table_Entry_t *TablesTblResultEntry);

/*******************************************************************************/
// cs_utils.h's nine `static inline`s. Eight of them are the same expression with a different
// checksum type and a different return type, which is what the wrapper's DefEntrySize and
// ResEntrySize exist to make possible: ONE indexing function, eight typed views of it.

// WHICH STATES A COMMAND MAY SET. EMPTY and UNDEFINED are not among them -- the ground may
// enable or disable an entry, but it cannot un-define one, and it cannot empty a slot it filled.
// This is the guard that makes CS_SetGenericEntryState refuse twice: once on the state asked
// for, once on the state already there.
Bool CS_StateValid(U32 State) // CS_ChecksumState_Enum_t
{
  return State == CS_ChecksumState_ENABLED || State == CS_ChecksumState_DISABLED;
}

CS_Def_EepromMemory_Table_Entry_t *CS_GetEepromDefEntry(U16 EntryIdx)
{
  return CS_GetDefEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE], EntryIdx);
}

CS_Res_EepromMemory_Table_Entry_t *CS_GetEepromResEntry(U16 EntryIdx)
{
  return CS_GetResEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_EEPROM_TABLE], EntryIdx);
}

CS_Def_EepromMemory_Table_Entry_t *CS_GetMemoryDefEntry(U16 EntryIdx)
{
  return CS_GetDefEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_MEMORY_TABLE], EntryIdx);
}

CS_Res_EepromMemory_Table_Entry_t *CS_GetMemoryResEntry(U16 EntryIdx)
{
  return CS_GetResEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_MEMORY_TABLE], EntryIdx);
}

CS_Def_Tables_Table_Entry_t *CS_GetTablesDefEntry(U16 EntryIdx)
{
  return CS_GetDefEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_TABLES_TABLE], EntryIdx);
}

CS_Res_Tables_Table_Entry_t *CS_GetTablesResEntry(U16 EntryIdx)
{
  return CS_GetResEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_TABLES_TABLE], EntryIdx);
}

CS_Def_App_Table_Entry_t *CS_GetAppDefEntry(U16 EntryIdx)
{
  return CS_GetDefEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_APP_TABLE], EntryIdx);
}

CS_Res_App_Table_Entry_t *CS_GetAppResEntry(U16 EntryIdx)
{
  return CS_GetResEntryAddr(&CS_AppData.Tbl[CS_ChecksumType_APP_TABLE], EntryIdx);
}

/*******************************************************************************/
// Local helper function
// Checks if two names match in a NULL-safe manner.
// If either string is NULL then there is no match.
Bool CS_CheckGenericNameMatch(U8 *Name1, U8 *Name2)
{
  if (Name1 == NULL || Name2 == NULL) {
    return FALSE;
  }

  return StrCmp(Name1, Name2) == 0;
}

/*******************************************************************************/
// Application utility function
// Checks if the definition table name matches (NULL-safe)
Bool CS_CheckDefTableNameMatch(U8 *Name, U16 TableId)
{
  return CS_CheckGenericNameMatch(CS_GetDefName(TableId), Name);
}

/*******************************************************************************/
// Application utility function
// Checks if the result table name matches (NULL-safe)
Bool CS_CheckResTableNameMatch(U8 *Name, U16 TableId)
{
  return CS_CheckGenericNameMatch(CS_GetResName(TableId), Name);
}

/*******************************************************************************/
// Application utility function
// Gets a pointer to the given definition table entry
//
// THE BOUND IS WHAT MAKES THE EIGHT INLINES ABOVE SAFE, and it is also what makes NASA's
// `while (true) { e = CS_Get...(Loop); if (e == NULL) break; }` loops terminate: there is no
// separate count anywhere, the NULL return IS the end of the table. A translation that returned
// a pointer past the end would turn eleven loops in this file into runaways.
U8 *CS_GetDefEntryAddr(CS_TableWrapper_t *tw, U16 EntryId)
{
  U8 *EntryAddr = tw->DefAddr;

  if (tw->DefAddr != NULL && EntryId < tw->NumEntries) {
    EntryAddr = tw->DefAddr;
    EntryAddr += tw->DefEntrySize * EntryId;
  } else {
    EntryAddr = NULL;
  }

  return EntryAddr;
}

/*******************************************************************************/
// Application utility function
// Gets a pointer to the given result table entry
U8 *CS_GetResEntryAddr(CS_TableWrapper_t *tw, U16 EntryId)
{
  U8 *EntryAddr;

  if (tw->ResAddr != NULL && EntryId < tw->NumEntries) {
    EntryAddr = tw->ResAddr;
    EntryAddr += tw->ResEntrySize * EntryId;
  } else {
    EntryAddr = NULL;
  }

  return EntryAddr;
}

/*******************************************************************************/
// Local helper function
// Sets the state of a definition table entry
//
// THE GENERIC POKE. The caller hands over an entry pointer of one of three unrelated layouts and
// the BYTE OFFSET of its State member -- tw->DefStateOffset -- and this writes through it. The
// cast through `void *` in NASA's C is there because a uint16 may be at an odd offset in
// CS_Def_Tables_Table_Entry_t (it is at 0, but the compiler cannot know that here), and it is
// the one place in CS where the wrapper's byte arithmetic is visible rather than implied.
U32 CS_SetGenericEntryState(U8 *EntryPtr, I64 Offset, U32 NewState) // CS_ChecksumState_Enum_t
{
  U8 *StateAddr;
  U32 PreviousDefState; // CS_ChecksumState_Enum_t
  U16 *StatePtr;

  PreviousDefState = CS_ChecksumState_UNDEFINED;
  if (CS_StateValid(NewState)) {
    StateAddr = EntryPtr;
  } else {
    StateAddr = NULL;
  }

  if (StateAddr != NULL) {
    StateAddr += Offset;
    StatePtr = StateAddr;

    PreviousDefState = *StatePtr;
    if (CS_StateValid(PreviousDefState)) {
      *StatePtr = NewState;
    }
  }

  return PreviousDefState;
}

/*******************************************************************************/
// Application utility function
// Sets the state of a definition table entry
//
// AND THE TWO SIDE EFFECTS ARE THE REASON THIS WRAPPER EXISTS. Changing a definition entry's
// state invalidates any partial checksum of the table that HOLDS the definition -- so the
// results entry for CS's own definition table is reset -- and tells table services the buffer
// changed, so the next dump reflects it. Both only happen when the state actually MOVED.
U32 CS_SetDefEntryState(CS_TableWrapper_t *tw, U8 *EntryPtr, U32 NewState) // CS_ChecksumState_Enum_t
{
  U32 PreviousDefState; // CS_ChecksumState_Enum_t

  PreviousDefState = CS_SetGenericEntryState(EntryPtr, tw->DefStateOffset, NewState);
  if (CS_StateValid(PreviousDefState) && PreviousDefState != NewState) {
    CS_ResetTablesTblResultEntry(tw->ResTblPtr);
    CFE_TBL_Modified(tw->DefHandle);
  }

  return PreviousDefState;
}

/*******************************************************************************/
// Gets a table type ID value as a printable string
//
// SIX NAMES AND AN "Undef". The default arm is unreachable through CS's own code, because every
// caller passes &CS_AppData.Tbl[n] for n in 0..5 -- but CS_GetTableId is a pointer subtraction,
// so a wrapper pointer from anywhere else would land here rather than index off the end of a
// jump table. Kept 1:1.
U8 *CS_GetTableTypeAsString(CS_TableWrapper_t *tw)
{
  U8 *TableTypeStr;

  switch (CS_GetTableId(tw)) {
    case CS_ChecksumType_APP_TABLE:
      TableTypeStr = "Apps";
      break;
    case CS_ChecksumType_TABLES_TABLE:
      TableTypeStr = "Tables";
      break;
    case CS_ChecksumType_EEPROM_TABLE:
      TableTypeStr = "EEPROM";
      break;
    case CS_ChecksumType_MEMORY_TABLE:
      TableTypeStr = "Memory";
      break;
    case CS_ChecksumType_CFECORE:
      TableTypeStr = "cFE Core";
      break;
    case CS_ChecksumType_OSCORE:
      TableTypeStr = "OS";
      break;
    default:
      TableTypeStr = "Undef";
      break;
  }

  return TableTypeStr;
}

/*******************************************************************************/
// CS Zero out the temp chcksum values of EEPROM
//
// NASA's spelling of "checksum" in these six comment banners is kept as NASA wrote it.
U0 CS_ZeroEepromTempValues()
{
  CS_Res_EepromMemory_Table_Entry_t *ResEepromTblPtr;
  U16 Loop;

  Loop = 0;
  while (TRUE) {
    ResEepromTblPtr = CS_GetEepromResEntry(Loop);
    if (ResEepromTblPtr == NULL) {
      break;
    }

    ResEepromTblPtr->TempChecksumValue = 0;
    ResEepromTblPtr->ByteOffset = 0;

    ++Loop;
  }
}

/*******************************************************************************/
// CS Zero out the temp chcksum values of Memory
U0 CS_ZeroMemoryTempValues()
{
  CS_Res_EepromMemory_Table_Entry_t *ResMemoryTblPtr;
  U16 Loop;

  Loop = 0;
  while (TRUE) {
    ResMemoryTblPtr = CS_GetMemoryResEntry(Loop);
    if (ResMemoryTblPtr == NULL) {
      break;
    }

    ResMemoryTblPtr->TempChecksumValue = 0;
    ResMemoryTblPtr->ByteOffset = 0;

    ++Loop;
  }
}

/*******************************************************************************/
// CS Zero out the temp chcksum values of Tables
U0 CS_ZeroTablesTempValues()
{
  CS_Res_Tables_Table_Entry_t *ResTablesTblPtr;
  U16 Loop;

  Loop = 0;
  while (TRUE) {
    ResTablesTblPtr = CS_GetTablesResEntry(Loop);
    if (ResTablesTblPtr == NULL) {
      break;
    }

    ResTablesTblPtr->TempChecksumValue = 0;
    ResTablesTblPtr->ByteOffset = 0;

    ++Loop;
  }
}

/*******************************************************************************/
// CS Zero out the temp chcksum values of Applications
U0 CS_ZeroAppTempValues()
{
  CS_Res_App_Table_Entry_t *ResAppTblPtr;
  U16 Loop;

  Loop = 0;
  while (TRUE) {
    ResAppTblPtr = CS_GetAppResEntry(Loop);
    if (ResAppTblPtr == NULL) {
      break;
    }

    ResAppTblPtr->TempChecksumValue = 0;
    ResAppTblPtr->ByteOffset = 0;

    ++Loop;
  }
}

/*******************************************************************************/
// CS Zero out the temp chcksum values ofthe cFE core
U0 CS_ZeroCfeCoreTempValues()
{
  CS_Res_EepromMemory_Table_Entry_t *CfeCoreCodeSeg = CS_GetCfeCoreCodeSegResTable();

  if (CfeCoreCodeSeg != NULL) {
    CfeCoreCodeSeg->TempChecksumValue = 0;
    CfeCoreCodeSeg->ByteOffset = 0;
  }
}

/*******************************************************************************/
// CS Zero out the temp chcksum values of the OS code segment
U0 CS_ZeroOSTempValues()
{
  CS_Res_EepromMemory_Table_Entry_t *OSCodeSeg = CS_GetOSCodeSegResTable();

  if (OSCodeSeg != NULL) {
    OSCodeSeg->TempChecksumValue = 0;
    OSCodeSeg->ByteOffset = 0;
  }
}

/*******************************************************************************/
// CS Nullifies the entries in the Results table for All
//
// WHAT A COLD BOOT WITH NO TABLE FILES LOOKS LIKE. These four arrays are the fallback
// CS_TableInit hands to CFE_TBL_Load when the definition file is missing, and this is what
// makes them an empty table rather than whatever the BSS happened to hold -- CS comes up
// watching nothing instead of refusing to come up. The two EEPROM/Memory loops clear three
// fields and the two name loops clear only Name[0], which is NASA's: a zero first byte is an
// empty C string, so the remaining 39 or 19 bytes do not matter to any reader.
U0 CS_InitializeDefaultTables()
{
  U16 Loop;

  for (Loop = 0; Loop < CS_MAX_NUM_EEPROM_TABLE_ENTRIES; Loop++) {
    CS_AppData.DefaultEepromDefTable[Loop].State = CS_ChecksumState_EMPTY;
    CS_AppData.DefaultEepromDefTable[Loop].NumBytesToChecksum = 0;
    CS_AppData.DefaultEepromDefTable[Loop].StartAddress = 0;
  }

  for (Loop = 0; Loop < CS_MAX_NUM_MEMORY_TABLE_ENTRIES; Loop++) {
    CS_AppData.DefaultMemoryDefTable[Loop].State = CS_ChecksumState_EMPTY;
    CS_AppData.DefaultMemoryDefTable[Loop].NumBytesToChecksum = 0;
    CS_AppData.DefaultMemoryDefTable[Loop].StartAddress = 0;
  }

  for (Loop = 0; Loop < CS_MAX_NUM_APP_TABLE_ENTRIES; Loop++) {
    CS_AppData.DefaultAppDefTable[Loop].State = CS_ChecksumState_EMPTY;
    CS_AppData.DefaultAppDefTable[Loop].Name[0] = '\0';
  }

  for (Loop = 0; Loop < CS_MAX_NUM_TABLES_TABLE_ENTRIES; Loop++) {
    CS_AppData.DefaultTablesDefTable[Loop].State = CS_ChecksumState_EMPTY;
    CS_AppData.DefaultTablesDefTable[Loop].Name[0] = '\0';
  }
}

/*******************************************************************************/
// CS Set the global variables to the start of the next table
//
// THE PASS COUNTER IS INCREMENTED HERE AND NOWHERE ELSE, on the wrap from table 5 back to 0 --
// so "CS has completed a full pass over everything it watches" is a single `else` arm. The
// ground reads PassCounter to know CS is progressing rather than stuck on one table.
U0 CS_GoToNextTable()
{
  if (CS_AppData.HkPacket.Payload.CurrentCSTable < CS_NUM_TABLES - 1) {
    CS_AppData.HkPacket.Payload.CurrentCSTable++;
  } else {
    CS_AppData.HkPacket.Payload.CurrentCSTable = 0;
    // we are back to the beginning of the tables to checksum
    // we need to update the pass counter
    CS_AppData.HkPacket.Payload.PassCounter++;
  }

  CS_AppData.HkPacket.Payload.CurrentEntryInTable = 0;
}

/*******************************************************************************/
// CS Get the Results Table Entry info of a table by its name
//
// THE FOUR "BY NAME" LOOKUPS ARE NOT SYMMETRIC, and the asymmetry is NASA's rather than a
// transcription slip: the two RESULTS lookups test `State != CS_ChecksumState_EMPTY` and the two
// DEFINITION lookups test `CS_StateValid(State)`. Those differ on UNDEFINED -- a results entry
// whose table could not be found is still findable by name, a definition entry in that state is
// not. It matters to the ground: "enable this table" must refuse a name CS has given up on,
// while "report its baseline" must still be able to say there isn't one.
Bool CS_GetTableResTblEntryByName(CS_Res_Tables_Table_Entry_t **EntryPtr, U8 *Name)
{
  CS_Res_Tables_Table_Entry_t *ResultsEntry = NULL;
  I32 Loop;
  Bool Status = FALSE;

  Loop = 0;
  while (TRUE) {
    ResultsEntry = CS_GetTablesResEntry(Loop);
    if (ResultsEntry == NULL) {
      break;
    }

    if (ResultsEntry->State != CS_ChecksumState_EMPTY &&
        StrNCmp(ResultsEntry->Name, Name, CFE_TBL_MAX_FULL_NAME_LEN) == 0) {
      Status = TRUE;
      *EntryPtr = ResultsEntry;
      break;
    }

    ++Loop;
  }
  return Status;
}

/*******************************************************************************/
// CS Get the Definition Table Entry info of a table by its name
Bool CS_GetTableDefTblEntryByName(CS_Def_Tables_Table_Entry_t **EntryPtr, U8 *Name)
{
  CS_Def_Tables_Table_Entry_t *DefinitionEntry = NULL;
  I32 Loop;
  Bool Status = FALSE;

  Loop = 0;
  while (TRUE) {
    DefinitionEntry = CS_GetTablesDefEntry(Loop);
    if (DefinitionEntry == NULL) {
      break;
    }

    if (CS_StateValid(DefinitionEntry->State) &&
        StrNCmp(DefinitionEntry->Name, Name, CFE_TBL_MAX_FULL_NAME_LEN) == 0) {
      Status = TRUE;
      *EntryPtr = DefinitionEntry;
      break;
    }

    ++Loop;
  }
  return Status;
}

/*******************************************************************************/
// CS Get the Results Entry info of an app by its name
Bool CS_GetAppResTblEntryByName(CS_Res_App_Table_Entry_t **EntryPtr, U8 *Name)
{
  CS_Res_App_Table_Entry_t *ResultsEntry = NULL;
  I32 Loop;
  Bool Status = FALSE;

  Loop = 0;
  while (TRUE) {
    ResultsEntry = CS_GetAppResEntry(Loop);
    if (ResultsEntry == NULL) {
      break;
    }

    if (ResultsEntry->State != CS_ChecksumState_EMPTY &&
        StrNCmp(ResultsEntry->Name, Name, OS_MAX_API_NAME) == 0) {
      Status = TRUE;
      *EntryPtr = ResultsEntry;
      break;
    }

    ++Loop;
  }
  return Status;
}

/*******************************************************************************/
// CS Get the Definition Entry info of an app by its name
Bool CS_GetAppDefTblEntryByName(CS_Def_App_Table_Entry_t **EntryPtr, U8 *Name)
{
  CS_Def_App_Table_Entry_t *DefinitionEntry = NULL;
  I32 Loop;
  Bool Status = FALSE;

  Loop = 0;
  while (TRUE) {
    DefinitionEntry = CS_GetAppDefEntry(Loop);
    if (DefinitionEntry == NULL) {
      break;
    }

    if (CS_StateValid(DefinitionEntry->State) &&
        StrNCmp(DefinitionEntry->Name, Name, OS_MAX_API_NAME) == 0) {
      Status = TRUE;
      *EntryPtr = DefinitionEntry;
      break;
    }

    ++Loop;
  }
  return Status;
}

/*******************************************************************************/
// CS Get the next CS-enabled entry of this table
//
// THE WALK ADVANCES CurrentEntryInTable AS A SIDE EFFECT, which is how a cycle resumes where the
// last one stopped: the four Find functions skip disabled and empty slots by MOVING the
// housekeeping counter, then return the first enabled entry or NULL at the end of the table.
// There is no separate cursor.
CS_Res_EepromMemory_Table_Entry_t *CS_FindEnabledEepromEntry()
{
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;

  while (TRUE) {
    ResultsEntry = CS_GetEepromResEntry(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
    if (ResultsEntry == NULL || ResultsEntry->State == CS_ChecksumState_ENABLED) {
      break;
    }

    CS_AppData.HkPacket.Payload.CurrentEntryInTable++;
  } // end while

  return ResultsEntry;
}

/*******************************************************************************/
// CS Get the next CS-enabled entry of this table
CS_Res_EepromMemory_Table_Entry_t *CS_FindEnabledMemoryEntry()
{
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;

  while (TRUE) {
    ResultsEntry = CS_GetMemoryResEntry(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
    if (ResultsEntry == NULL || ResultsEntry->State == CS_ChecksumState_ENABLED) {
      break;
    }

    CS_AppData.HkPacket.Payload.CurrentEntryInTable++;
  } // end while

  return ResultsEntry;
}

/*******************************************************************************/
// CS Get the next CS-enabled entry of this table
CS_Res_Tables_Table_Entry_t *CS_FindEnabledTablesEntry()
{
  CS_Res_Tables_Table_Entry_t *ResultsEntry = NULL;

  while (TRUE) {
    ResultsEntry = CS_GetTablesResEntry(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
    if (ResultsEntry == NULL || ResultsEntry->State == CS_ChecksumState_ENABLED) {
      break;
    }

    CS_AppData.HkPacket.Payload.CurrentEntryInTable++;
  } // end while

  return ResultsEntry;
}

/*******************************************************************************/
// CS Get the next CS-enabled entry of this table
CS_Res_App_Table_Entry_t *CS_FindEnabledAppEntry()
{
  CS_Res_App_Table_Entry_t *ResultsEntry = NULL;

  while (TRUE) {
    ResultsEntry = CS_GetAppResEntry(CS_AppData.HkPacket.Payload.CurrentEntryInTable);
    if (ResultsEntry == NULL || ResultsEntry->State == CS_ChecksumState_ENABLED) {
      break;
    }

    CS_AppData.HkPacket.Payload.CurrentEntryInTable++;
  } // end while

  return ResultsEntry;
}

/*******************************************************************************/
// Background check cFE core
//
// ONE ENTRY, TWO GATES. The outer gate is the ground's "is cFE core checksumming on at all";
// the inner one is the results entry's own State, which a recompute command clears while its
// child task owns the entry. NASA's comment says so, and the distinction is why a recompute
// does not race the background walk.
Bool CS_BackgroundCfeCore()
{
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry;
  Bool DoneWithCycle = FALSE;
  Bool DoneWithEntry = FALSE;
  U32 ComputedCSValue = 0;
  I32 Status;

  if (CS_AppData.HkPacket.Payload.CfeCoreCSState == CS_ChecksumState_ENABLED) {
    ResultsEntry = CS_GetCfeCoreCodeSegResTable();

    // Check if the code segment state is enabled (could be disabled for
    //  a ground-commanded recompute)
    if (ResultsEntry->State == CS_ChecksumState_ENABLED) {
      // If we complete an entry's checksum, this function will update it for us
      Status = CS_ComputeEepromMemory(ResultsEntry, &ComputedCSValue, &DoneWithEntry);

      // We need to avoid the case of finishing a table, moving on to the next one
      //  and computing an entry in that table, since it could put us above the
      //  maximum bytes per cycle
      DoneWithCycle = TRUE;

      if (Status == CS_ERROR) {
        // we had a miscompare

        CS_AppData.HkPacket.Payload.CfeCoreCSErrCounter++;

        CFE_EVS_SendEvent(CS_CFECORE_MISCOMPARE_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Checksum Failure: cFE Core, Expected: 0x%08X, Calculated: 0x%08X",
                          ResultsEntry->ComparisonValue, ComputedCSValue);
      }

      if (DoneWithEntry == TRUE) {
        CS_AppData.HkPacket.Payload.CurrentEntryInTable++;
      }

      // only one entry to do
      if (CS_AppData.HkPacket.Payload.CurrentEntryInTable > 0) {
        // We are done with this table
        CS_AppData.HkPacket.Payload.CfeCoreBaseline = ResultsEntry->ComparisonValue;
        CS_GoToNextTable();
      }
    } else {
      // Currently disabled, so skip it
      CS_GoToNextTable();
    }
  } else { // Table is disabled, skip it
    CS_GoToNextTable();
  }

  return DoneWithCycle;
}

/*******************************************************************************/
// Background check OS
Bool CS_BackgroundOS()
{
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry;
  Bool DoneWithCycle = FALSE;
  Bool DoneWithEntry = FALSE;
  U32 ComputedCSValue = 0;
  I32 Status;

  if (CS_AppData.HkPacket.Payload.OSCSState == CS_ChecksumState_ENABLED) {
    ResultsEntry = CS_GetOSCodeSegResTable();

    // Check if the code segment state is enabled (could be disabled for
    //  a ground-commanded recompute)
    if (ResultsEntry->State == CS_ChecksumState_ENABLED) {
      // If we complete an entry's checksum, this function will update it for us
      Status = CS_ComputeEepromMemory(ResultsEntry, &ComputedCSValue, &DoneWithEntry);

      // We need to avoid the case of finishing a table, moving on to the next one
      //  and computing an entry in that table, since it could put us above the
      //  maximum bytes per cycle
      DoneWithCycle = TRUE;

      if (Status == CS_ERROR) {
        // we had a miscompare
        CS_AppData.HkPacket.Payload.OSCSErrCounter++;

        CFE_EVS_SendEvent(CS_OS_MISCOMPARE_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Checksum Failure: OS code segment, Expected: 0x%08X, Calculated: 0x%08X",
                          ResultsEntry->ComparisonValue, ComputedCSValue);
      }

      if (DoneWithEntry == TRUE) {
        CS_AppData.HkPacket.Payload.CurrentEntryInTable++;
      }

      // only one entry to do
      if (CS_AppData.HkPacket.Payload.CurrentEntryInTable > 0) {
        // We are done with this table
        CS_AppData.HkPacket.Payload.OSBaseline = ResultsEntry->ComparisonValue;
        CS_GoToNextTable();
      }
    } else {
      // Currently disabled, so skip it
      CS_GoToNextTable();
    }
  } else { // Table is disabled, skip it
    CS_GoToNextTable();
  }
  return DoneWithCycle;
}

/*******************************************************************************/
// Background check EEPROM
//
// THE ONLY ONE WITH A RUNNING TOTAL. When the walk reaches the end of the table this sums every
// entry's ComparisonValue into EepromBaseline -- an unsigned 32-bit sum, so it wraps, which is
// fine because it is a change detector and not a checksum of anything. Memory, Tables and App
// have NO equivalent and their baselines are never set. That asymmetry is NASA's; the three
// baselines housekeeping reports are EEPROM, OS and cFE core, which is exactly the three things
// a mission would ask about on a voice loop.
Bool CS_BackgroundEeprom()
{
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry;
  CS_Res_EepromMemory_Table_Entry_t *LoopEntry;
  Bool DoneWithCycle = FALSE;
  Bool DoneWithEntry = FALSE;
  U32 ComputedCSValue = 0;
  I32 Loop;
  U32 EntireEepromCS;
  I32 Status;

  if (CS_AppData.HkPacket.Payload.EepromCSState == CS_ChecksumState_ENABLED) {
    ResultsEntry = CS_FindEnabledEepromEntry();
  } else {
    ResultsEntry = NULL;
  }

  if (ResultsEntry != NULL) {
    // we found an enabled entry to checksum
    // If we complete an entry's checksum, this function will update it for us
    Status = CS_ComputeEepromMemory(ResultsEntry, &ComputedCSValue, &DoneWithEntry);

    // We need to avoid the case of finishing a table, moving on to the next one
    //     and computing an entry in that table, since it could put us above the
    //     maximum bytes per cycle
    DoneWithCycle = TRUE;

    if (Status == CS_ERROR) {
      // we had a miscompare

      CS_AppData.HkPacket.Payload.EepromCSErrCounter++;

      CFE_EVS_SendEvent(CS_EEPROM_MISCOMPARE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Checksum Failure: Address 0x%lx in EEPROM Table, Expected: 0x%08X, Calculated: 0x%08X",
                        ResultsEntry->StartAddress, ResultsEntry->ComparisonValue, ComputedCSValue);
    }

    if (DoneWithEntry) {
      CS_AppData.HkPacket.Payload.CurrentEntryInTable++;
    }
  }

  if (CS_AppData.HkPacket.Payload.CurrentEntryInTable >= CS_MAX_NUM_EEPROM_TABLE_ENTRIES) {
    // Since we are done CS'ing the entire EEPROM table, update the baseline
    //     number for telemetry
    EntireEepromCS = 0;
    Loop = 0;
    while (TRUE) {
      LoopEntry = CS_GetEepromResEntry(Loop);
      if (LoopEntry == NULL) {
        break;
      }

      EntireEepromCS += LoopEntry->ComparisonValue;
      ++Loop;
    }

    CS_AppData.HkPacket.Payload.EepromBaseline = EntireEepromCS;
  }

  if (ResultsEntry == NULL ||
      CS_AppData.HkPacket.Payload.CurrentEntryInTable >= CS_MAX_NUM_EEPROM_TABLE_ENTRIES) {
    // We are done with this table
    CS_GoToNextTable();
  }

  return DoneWithCycle;
}

/*******************************************************************************/
// Background check Memory
Bool CS_BackgroundMemory()
{
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry;
  Bool DoneWithCycle = FALSE;
  Bool DoneWithEntry = FALSE;
  U32 ComputedCSValue = 0;
  I32 Status;

  if (CS_AppData.HkPacket.Payload.MemoryCSState == CS_ChecksumState_ENABLED) {
    // If we complete an entry's checksum, this function will update it for us
    ResultsEntry = CS_FindEnabledMemoryEntry();
  } else {
    ResultsEntry = NULL;
  }

  if (ResultsEntry != NULL) {
    // we found an enabled entry to checksum
    // If we complete an entry's checksum, this function will update it for us
    Status = CS_ComputeEepromMemory(ResultsEntry, &ComputedCSValue, &DoneWithEntry);

    // We need to avoid the case of finishing a table, moving on to the next one
    //     and computing an entry in that table, since it could put us above the
    //     maximum bytes per cycle
    DoneWithCycle = TRUE;

    if (Status == CS_ERROR) {
      // we had a miscompare

      CS_AppData.HkPacket.Payload.MemoryCSErrCounter++;

      CFE_EVS_SendEvent(CS_MEMORY_MISCOMPARE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Checksum Failure: Address 0x%lx in Memory Table, Expected: 0x%08X, Calculated: 0x%08X",
                        ResultsEntry->StartAddress, ResultsEntry->ComparisonValue, ComputedCSValue);
    }

    if (DoneWithEntry) {
      CS_AppData.HkPacket.Payload.CurrentEntryInTable++;
    }
  }

  if (ResultsEntry == NULL ||
      CS_AppData.HkPacket.Payload.CurrentEntryInTable >= CS_MAX_NUM_MEMORY_TABLE_ENTRIES) {
    // We are done with this table
    CS_GoToNextTable();
  }

  return DoneWithCycle;
}

/*******************************************************************************/
// Background check Tables
//
// THE THIRD STATUS. Tables and App can return CS_ERR_NOT_FOUND -- the table is not registered or
// the app is not running -- and NASA treats it as DoneWithEntry rather than as a miscompare: the
// error counter does not move, the event says "skipping", and the walk advances. So a table that
// is deleted at runtime produces one event per pass, forever, rather than wedging the walk.
Bool CS_BackgroundTables()
{
  CS_Res_Tables_Table_Entry_t *TablesResultsEntry;
  Bool DoneWithCycle = FALSE;
  Bool DoneWithEntry = FALSE;
  U32 ComputedCSValue = 0;
  I32 Status;

  if (CS_AppData.HkPacket.Payload.TablesCSState == CS_ChecksumState_ENABLED) {
    // If we complete an entry's checksum, this function will update it for us
    TablesResultsEntry = CS_FindEnabledTablesEntry();
  } else {
    TablesResultsEntry = NULL;
  }

  if (TablesResultsEntry != NULL) {
    // we found an enabled entry to checksum
    Status = CS_ComputeTables(TablesResultsEntry, &ComputedCSValue, &DoneWithEntry);

    // We need to avoid the case of finishing a table, moving on to the next one
    //     and computing an entry in that table, since  it could put us above the
    //     maximum bytes per cycle
    DoneWithCycle = TRUE;

    if (Status == CS_ERROR) {
      // we had a miscompare
      CS_AppData.HkPacket.Payload.TablesCSErrCounter++;

      CFE_EVS_SendEvent(CS_TABLES_MISCOMPARE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Checksum Failure: Table %s, Expected: 0x%08X, Calculated: 0x%08X",
                        TablesResultsEntry->Name, TablesResultsEntry->ComparisonValue,
                        ComputedCSValue);
    }

    if (Status == CS_ERR_NOT_FOUND) {
      CFE_EVS_SendEvent(CS_COMPUTE_TABLES_NOT_FOUND_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Tables table computing: Table %s could not be found, skipping",
                        TablesResultsEntry->Name);

      DoneWithEntry = TRUE;
    }

    if (DoneWithEntry) {
      CS_AppData.HkPacket.Payload.CurrentEntryInTable++;
    }
  }

  if (TablesResultsEntry == NULL ||
      CS_AppData.HkPacket.Payload.CurrentEntryInTable >= CS_MAX_NUM_TABLES_TABLE_ENTRIES) {
    // We are done with this table
    CS_GoToNextTable();
  }

  return DoneWithCycle;
}

/*******************************************************************************/
// Background check App
Bool CS_BackgroundApp()
{
  CS_Res_App_Table_Entry_t *AppResultsEntry;
  Bool DoneWithCycle = FALSE;
  Bool DoneWithEntry = FALSE;
  U32 ComputedCSValue = 0;
  I32 Status;

  if (CS_AppData.HkPacket.Payload.AppCSState == CS_ChecksumState_ENABLED) {
    AppResultsEntry = CS_FindEnabledAppEntry();
  } else {
    AppResultsEntry = NULL;
  }

  if (AppResultsEntry != NULL) {
    // we found an enabled entry to checksum
    // If we complete an entry's checksum, this function will update it for us
    Status = CS_ComputeApp(AppResultsEntry, &ComputedCSValue, &DoneWithEntry);

    // We need to avoid the case of finishing a table, moving on to the next one
    //     and computing an entry in that table, since it could put us above the
    //     maximum bytes per cycle
    DoneWithCycle = TRUE;

    if (Status == CS_ERROR) {
      // we had a miscompare
      CS_AppData.HkPacket.Payload.AppCSErrCounter++;

      CFE_EVS_SendEvent(CS_APP_MISCOMPARE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Checksum Failure: Application %s, Expected: 0x%08X, Calculated: 0x%08X",
                        AppResultsEntry->Name, AppResultsEntry->ComparisonValue, ComputedCSValue);
    }

    if (Status == CS_ERR_NOT_FOUND) {
      CFE_EVS_SendEvent(CS_COMPUTE_APP_NOT_FOUND_ERR_EID, CFE_EVS_EventType_ERROR,
                        "App table computing: App %s could not be found, skipping",
                        AppResultsEntry->Name);

      DoneWithEntry = TRUE;
    }

    if (DoneWithEntry) {
      CS_AppData.HkPacket.Payload.CurrentEntryInTable++;
    }
  }

  if (AppResultsEntry == NULL ||
      CS_AppData.HkPacket.Payload.CurrentEntryInTable >= CS_MAX_NUM_APP_TABLE_ENTRIES) {
    // We are done with this table
    CS_GoToNextTable();
  }

  return DoneWithCycle;
}

/*******************************************************************************/
// Reset Tables result table entry after a CS table gets modified
U0 CS_ResetTablesTblResultEntry(CS_Res_Tables_Table_Entry_t *TablesTblResultEntry)
{
  // Ptr will be NULL if this CS table is not listed in the CS Tables table
  if (TablesTblResultEntry != NULL) {
    TablesTblResultEntry->ByteOffset = 0;
    TablesTblResultEntry->TempChecksumValue = 0;
    TablesTblResultEntry->ComputedYet = FALSE;
  }
}

/*******************************************************************************/
// Update all tables
//
// NASA'S EventIdMap IS A `static const uint16[6]` WITH DESIGNATED INITIALISERS, two of whose six
// slots are left at zero (the cFE core and OS types have no table to update, so no event id).
// HolyC has no aggregate initialiser, so it becomes a local array filled at the top -- which is
// exact in behaviour, because NASA's is const and never written. The ZEROES ARE LOAD-BEARING:
// `if (ErrorEventID != 0)` in cs_init.c and the DefEntrySize guard here are what keep the two
// code-segment types from being reported as failed table updates, so the fill writes all six
// slots explicitly rather than relying on a zeroed frame.
//
// AND THE RETURN VALUE IS A NO-OP. NASA computes Result per table, uses it to pick an event and
// to disable checksumming, then returns CFE_SUCCESS unconditionally. Kept 1:1; the caller in
// cs_app.c ignores it, which is why nothing has ever noticed.
I32 CS_HandleRoutineTableUpdates()
{
  I32 Result = CFE_SUCCESS;
  U16 TableId;
  CS_TableWrapper_t *tw;
  Bool ShouldProcess;

  U16 EventIdMap[CS_NUM_TABLES];

  EventIdMap[CS_ChecksumType_CFECORE] = 0;
  EventIdMap[CS_ChecksumType_OSCORE] = 0;
  EventIdMap[CS_ChecksumType_EEPROM_TABLE] = CS_UPDATE_EEPROM_ERR_EID;
  EventIdMap[CS_ChecksumType_MEMORY_TABLE] = CS_UPDATE_MEMORY_ERR_EID;
  EventIdMap[CS_ChecksumType_TABLES_TABLE] = CS_UPDATE_TABLES_ERR_EID;
  EventIdMap[CS_ChecksumType_APP_TABLE] = CS_UPDATE_APP_ERR_EID;

  for (TableId = 0; TableId < CS_NUM_TABLES; ++TableId) {
    tw = &CS_AppData.Tbl[TableId];

    if (tw->DefEntrySize == 0) {
      // There is no table to update
      ShouldProcess = FALSE;
    } else if (!CS_AppData.HkPacket.Payload.RecomputeInProgress ||
               CS_AppData.HkPacket.Payload.OneShotInProgress) {
      // Always update
      ShouldProcess = TRUE;
    } else {
      // Do not process if the child task owns this table
      ShouldProcess = CS_AppData.ChildTaskTable != TableId;
    }

    if (ShouldProcess) {
      Result = CS_HandleTableUpdate(tw);
    } else {
      Result = CFE_SUCCESS;
    }

    if (Result != CFE_SUCCESS) {
      CFE_EVS_SendEvent(EventIdMap[TableId], CFE_EVS_EventType_ERROR,
                        "Table update failed for %s: 0x%08X, checksumming is disabled",
                        CS_GetTableTypeAsString(tw), Result);

      if (tw->GlobalState) {
        *tw->GlobalState = CS_ChecksumState_DISABLED;
      }
    }
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Check if one shot recompute is already in progress
//
// THE GUARD EVERY COMMAND HANDLER CALLS FIRST, and it is the one utility that increments the
// error counter itself -- so a handler that forgets to return after a TRUE would count the
// failure twice.
Bool CS_CheckRecomputeOneshot()
{
  Bool Result = FALSE;

  if (CS_AppData.HkPacket.Payload.RecomputeInProgress == TRUE ||
      CS_AppData.HkPacket.Payload.OneShotInProgress == TRUE) {
    CFE_EVS_SendEvent(CS_CMD_COMPUTE_PROG_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Cannot perform command. Recompute or oneshot in progress.");

    CS_AppData.HkPacket.Payload.CommandErrorCounter++;

    Result = TRUE;
  }
  return Result;
}
#endif
