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
// CHECKSUM'S TABLE MACHINERY -- the 1:1 translation of NASA's fsw/src/cs_table_processing.c,
// 984 lines and eighteen functions. Three jobs, in this order:
//
//   VALIDATE  four callbacks table services calls BEFORE accepting a ground table load, one per
//             definition table, sharing one CS_ValidationMetrics_t accumulator.
//   PROCESS   three update handlers that copy an accepted definition table into the matching
//             results table -- the UpdateHandler member of CS_TableWrapper_t.
//   REGISTER  CS_TableInit, which registers both tables, loads the definition one from a file or
//             from CS's own default, and calls the update handler once.
//
// AND IT IS THE FILE THAT CLOSES THE CYCLE: CS_HandleTableUpdate is the one function here that
// cs_utils.HC calls, and the reason the three middle sources of CS gate together.
//
// THE VALIDATION ACCUMULATOR IS THE INTERESTING DESIGN. Four tables with four layouts and four
// sets of event ids share one counting-and-reporting object; the per-table event ids arrive as an
// EventMap indexed by the error enum, so ReportEvent has one switch rather than four. Two
// consequences worth naming:
//
//   ONLY THE FIRST ERROR IS REPORTED. CS_ValidationMetrics_Accumulate sends the event only while
//   BadCount is still zero, so a table with twelve bad entries produces one error event and a
//   summary saying twelve. That is deliberate: a bad table load must not flood the event log.
//
//   AN UNUSED SLOT IN AN EventMap IS A ZERO, and a zero event id is still SENT. The EEPROM and
//   Memory maps define three of six slots, so a LONG_NAME or DUPLICATE error -- which those two
//   tables cannot produce, having no name field -- would report event id 0. Unreachable, and kept
//   1:1; the `default:` arm of ReportEvent shares its body with the STATE case for the same
//   reason.
#ifndef CS_TABLE_PROCESSING_HC
#define CS_TABLE_PROCESSING_HC

/*******************************************************************************/
// Errors that may be detected by table validation
//
// NASA's enum, which doubles as the EventMap index -- so the values and the order are an
// interface between these six names and four arrays further down.
#define CS_ValidationError_NONE      0 // keep first, should be 0
#define CS_ValidationError_LONG_NAME 1
#define CS_ValidationError_STATE     2
#define CS_ValidationError_ZERO_NAME 3
#define CS_ValidationError_DUPLICATE 4
#define CS_ValidationError_MEM_RANGE 5
#define CS_ValidationError_MAX       6 // keep last, indicates number of entries

/*******************************************************************************/
// Helper struct to keep state of table validation
// This allows app, table, memory, and eeprom table validation to
// share common counting and reporting logic to keep things consistent.
//
// 80 bytes, four of them tail padding, measured. ErrorMessage is CFE_TBL_MAX_FULL_NAME_LEN
// because the DUPLICATE message has to be able to hold a table name -- NASA's own comment.
class CS_ValidationMetrics_t
{
  U8 *TableName;
  U16 *EventMap;

  U16 Position;
  U16 StateField;

  U32 PendingError; // CS_ValidationError_t
  U8 ErrorMessage[CFE_TBL_MAX_FULL_NAME_LEN];

  I32 GoodCount;
  I32 BadCount;
  I32 EmptyCount;
  U8 _pad0[4]; // C rounds the object to 8, for TableName
};

/*******************************************************************************/
// Local helper function
// Checks if the overall validation is OK so far
Bool CS_ValidationMetrics_IsAllOK(CS_ValidationMetrics_t *Metrics)
{
  return Metrics->BadCount == 0;
}

/*******************************************************************************/
// Local helper function
// Checks if the current entry is OK
Bool CS_ValidationMetrics_IsCurrentOK(CS_ValidationMetrics_t *Metrics)
{
  return Metrics->PendingError == CS_ValidationError_NONE;
}

/*******************************************************************************/
// Local helper function
// Starts checking an entry, checks that the state is valid
//
// EMPTY IS LEGAL HERE AND NOWHERE ELSE. CS_StateValid refuses EMPTY, because a COMMAND may not
// set it -- but a definition table is mostly empty slots, so validation has to accept it. This
// is the one place the two notions of a valid state differ.
U0 CS_ValidationMetrics_StartNext(CS_ValidationMetrics_t *Metrics, U16 EntryState)
{
  Metrics->StateField = EntryState;
  Metrics->ErrorMessage[0] = 0;

  if (!CS_StateValid(EntryState) && EntryState != CS_ChecksumState_EMPTY) {
    // The state field is not one of the valid values
    Metrics->PendingError = CS_ValidationError_STATE;
  } else {
    Metrics->PendingError = CS_ValidationError_NONE;
  }
}

/*******************************************************************************/
// Local helper function
// Reports an error event associated with table validation
//
// `case CS_ValidationError_STATE: default:` -- an empty label falling into the next case, which
// docs/CFS_PLAN.md records measuring for MM, and which is kept verbatim here.
U0 CS_ValidationMetrics_ReportEvent(CS_ValidationMetrics_t *Metrics)
{
  U16 PendingEventId;

  PendingEventId = Metrics->EventMap[Metrics->PendingError];
  switch (Metrics->PendingError) {
    case CS_ValidationError_STATE:
    default:
      CFE_EVS_SendEvent(PendingEventId, CFE_EVS_EventType_ERROR,
                        "%s Table Validate: Illegal State Field (0x%04X) found in Entry ID %d",
                        Metrics->TableName, Metrics->StateField, Metrics->Position);
      break;

    case CS_ValidationError_LONG_NAME:
      CFE_EVS_SendEvent(PendingEventId, CFE_EVS_EventType_ERROR,
                        "%s Table Validate: Unterminated Name found at entry %d",
                        Metrics->TableName, Metrics->Position);
      break;

    case CS_ValidationError_ZERO_NAME:
      CFE_EVS_SendEvent(PendingEventId, CFE_EVS_EventType_ERROR,
                        "%s Table Validate: Illegal State (0x%04X) with empty name at entry %d",
                        Metrics->TableName, Metrics->StateField, Metrics->Position);
      break;

    case CS_ValidationError_DUPLICATE:
      CFE_EVS_SendEvent(PendingEventId, CFE_EVS_EventType_ERROR,
                        "%s Table Validate: Duplicate Name (%s) found at entry %d",
                        Metrics->TableName, Metrics->ErrorMessage, Metrics->Position);
      break;

    case CS_ValidationError_MEM_RANGE:
      CFE_EVS_SendEvent(PendingEventId, CFE_EVS_EventType_ERROR,
                        "%s Table Validate: Illegal MemRange in Entry ID %d, "
                        "CFE_PSP_MemValidateRange: %s",
                        Metrics->TableName, Metrics->Position, Metrics->ErrorMessage);
      break;
  }
}

/*******************************************************************************/
// Local helper function
// Accumulate table validation counters
U0 CS_ValidationMetrics_Accumulate(CS_ValidationMetrics_t *Metrics)
{
  // increment the respective counter for final report
  if (!CS_ValidationMetrics_IsCurrentOK(Metrics)) {
    // Only do event report on the first error
    if (CS_ValidationMetrics_IsAllOK(Metrics)) {
      CS_ValidationMetrics_ReportEvent(Metrics);
    }

    ++Metrics->BadCount;
  } else if (Metrics->StateField == CS_ChecksumState_EMPTY) {
    ++Metrics->EmptyCount;
  } else {
    ++Metrics->GoodCount;
  }

  ++Metrics->Position;
}

/*******************************************************************************/
// Local helper function
// Gets the final status of the table validation and report INFO event
//
// EventMap[0] IS THE *INFO* ID, which is why CS_ValidationError_NONE has to be zero: the slot
// that would hold "the event for no error" holds the summary event instead.
I32 CS_ValidationMetrics_GetFinalStatus(CS_ValidationMetrics_t *Metrics)
{
  CFE_EVS_SendEvent(Metrics->EventMap[0], CFE_EVS_EventType_INFORMATION,
                    "CS %s Table verification results: good = %d, bad = %d, unused = %d",
                    Metrics->TableName, Metrics->GoodCount, Metrics->BadCount,
                    Metrics->EmptyCount);

  if (CS_ValidationMetrics_IsAllOK(Metrics)) {
    return CFE_SUCCESS;
  } else {
    return CS_TABLE_ERROR;
  }
}

/*******************************************************************************/
// Local helper function
// Call respective table update handler
//
// AN INDIRECT CALL THROUGH AN ARROW MEMBER, with a NULL guard that four of CS's six wrappers
// need. tests/exec/cases/e_tbl_wrapper_idiom.hc measures both halves of this line before any of
// CS depended on it, and its third negative control is this guard removed -- which hangs.
U0 CS_CallTableUpdateHandler(CS_TableWrapper_t *tw)
{
  if (tw->UpdateHandler) {
    tw->UpdateHandler(tw);
  }
}

/*******************************************************************************/
// Local helper function
// Checks for duplicate name enty in table
//
// IT WALKS BACKWARD BY RAW BYTES, EntrySize at a time, from the entry being checked to the start
// of the table -- so it is O(n^2) in the table size and needs no second pointer. EntrySize is
// `sizeof(*Entry)`, 42 for the tables table and 22 for the app table, and those strides are
// exactly the odd-sized classes cs_msg.HC measures: a port that rounded either entry up to a
// multiple of 8 would make this read the middle of a name instead of its first byte.
U0 CS_CheckForDuplicateEntry(CS_ValidationMetrics_t *Metrics, U8 *RefName, I64 EntrySize)
{
  U8 *EntryName;
  U16 Count;

  EntryName = RefName;
  Count = Metrics->Position;

  while (Count > 0) {
    --Count;
    EntryName -= EntrySize;

    if (StrCmp(RefName, EntryName) == 0) {
      Metrics->PendingError = CS_ValidationError_DUPLICATE;
      StrPrintN(Metrics->ErrorMessage, CFE_TBL_MAX_FULL_NAME_LEN, "position=%d", Count);
      break;
    }
  }
}

/*******************************************************************************/
// Local helper function
// Checks sanity of entry name
//
// THREE RULES, AND THE THIRD IS THE ONE A READER MISSES: a slot whose state is EMPTY must also
// have an EMPTY NAME, and a name in an empty slot is reported as a STATE error rather than as a
// name error. So a ground table that disables an entry by zeroing its state and leaving the name
// is REJECTED -- the only way to retire an entry is to clear both.
U0 CS_ValidateEntryName(CS_ValidationMetrics_t *Metrics, U8 *NameField, I64 NameSize)
{
  if (CS_StateValid(Metrics->StateField)) {
    if (MemChr(NameField, 0, NameSize) == NULL) {
      // Not null-terminated, name is too long
      Metrics->PendingError = CS_ValidationError_LONG_NAME;
    } else if (NameField[0] == 0) {
      // non-empty entries MUST have a name
      Metrics->PendingError = CS_ValidationError_ZERO_NAME;
    }
  } else if (NameField[0] != 0) {
    // empty entries must NOT have a name
    Metrics->PendingError = CS_ValidationError_STATE;
  }
}

/*******************************************************************************/
// Local helper function
// Checks sanity of entry address
//
// THE ONE SIMULATED PIECE OF HARDWARE CS VALIDATES AGAINST. CFE_PSP_MemValidateRange answers
// whether an address range exists and is of the right kind; on real flight hardware it reads a
// board memory map. The driver supplies it, which is why the EEPROM and Memory tables in the
// exercises name addresses the simulated map agrees with -- see docs/BENCHTOP_SAT_BOM.md.
U0 CS_ValidateEntryAddress(CS_ValidationMetrics_t *Metrics, U64 MemoryAddr, I64 MemorySize,
                          U32 MemoryType)
{
  I32 PspStatus;

  if (CS_StateValid(Metrics->StateField)) {
    PspStatus = CFE_PSP_MemValidateRange(MemoryAddr, MemorySize, MemoryType);
    if (PspStatus != CFE_PSP_SUCCESS) {
      Metrics->PendingError = CS_ValidationError_MEM_RANGE;
      StrPrintN(Metrics->ErrorMessage, CFE_TBL_MAX_FULL_NAME_LEN, "status=%d", PspStatus);
    }
  }
}

/*******************************************************************************/
// CS Validation Callback function for EEPROM Table
//
// NASA'S EVENTID_MAP IS A `static const uint16[6]` with three of six slots given. HolyC has no
// aggregate initialiser, so it becomes a local array filled at the top -- and the three slots
// NASA leaves out are written as explicit zeros rather than left to the frame, because a stale
// value there would send a real event id for an error this table cannot produce. The same
// treatment, and the same reason, as the EventIdMap in cs_utils.HC's
// CS_HandleRoutineTableUpdates.
I32 CS_ValidateEepromChecksumDefinitionTable(U8 *TblPtr)
{
  U16 EEPROM_EVENTID_MAP[CS_ValidationError_MAX];

  CS_Def_EepromMemory_Table_Entry_t *Entry;
  CS_ValidationMetrics_t Metrics;

  EEPROM_EVENTID_MAP[CS_ValidationError_NONE] = CS_VAL_EEPROM_INF_EID;
  EEPROM_EVENTID_MAP[CS_ValidationError_LONG_NAME] = 0;
  EEPROM_EVENTID_MAP[CS_ValidationError_STATE] = CS_VAL_EEPROM_STATE_ERR_EID;
  EEPROM_EVENTID_MAP[CS_ValidationError_ZERO_NAME] = 0;
  EEPROM_EVENTID_MAP[CS_ValidationError_DUPLICATE] = 0;
  EEPROM_EVENTID_MAP[CS_ValidationError_MEM_RANGE] = CS_VAL_EEPROM_RANGE_ERR_EID;

  MemSet(&Metrics, 0, sizeof(CS_ValidationMetrics_t));

  // These are needed for assembling event data, if necessary
  Metrics.TableName = "EEPROM";
  Metrics.EventMap = EEPROM_EVENTID_MAP;

  Entry = TblPtr;
  while (Metrics.Position < CS_MAX_NUM_EEPROM_TABLE_ENTRIES) {
    CS_ValidationMetrics_StartNext(&Metrics, Entry->State);

    CS_ValidateEntryAddress(&Metrics, Entry->StartAddress, Entry->NumBytesToChecksum,
                            CFE_PSP_MEM_EEPROM);

    // increment the respective counter for final report
    CS_ValidationMetrics_Accumulate(&Metrics);
    ++Entry;
  }

  return CS_ValidationMetrics_GetFinalStatus(&Metrics);
}

/*******************************************************************************/
// CS Validation Callback function for Memory Table
//
// IDENTICAL TO THE EEPROM ONE BUT FOR CFE_PSP_MEM_ANY instead of CFE_PSP_MEM_EEPROM, three event
// ids and the table bound. That is the whole difference between CS's EEPROM table and its memory
// table, and it is why they share both entry types.
I32 CS_ValidateMemoryChecksumDefinitionTable(U8 *TblPtr)
{
  U16 MEMORY_EVENTID_MAP[CS_ValidationError_MAX];

  CS_Def_EepromMemory_Table_Entry_t *Entry;
  CS_ValidationMetrics_t Metrics;

  MEMORY_EVENTID_MAP[CS_ValidationError_NONE] = CS_VAL_MEMORY_INF_EID;
  MEMORY_EVENTID_MAP[CS_ValidationError_LONG_NAME] = 0;
  MEMORY_EVENTID_MAP[CS_ValidationError_STATE] = CS_VAL_MEMORY_STATE_ERR_EID;
  MEMORY_EVENTID_MAP[CS_ValidationError_ZERO_NAME] = 0;
  MEMORY_EVENTID_MAP[CS_ValidationError_DUPLICATE] = 0;
  MEMORY_EVENTID_MAP[CS_ValidationError_MEM_RANGE] = CS_VAL_MEMORY_RANGE_ERR_EID;

  MemSet(&Metrics, 0, sizeof(CS_ValidationMetrics_t));

  // These are needed for assembling event data, if necessary
  Metrics.TableName = "Memory";
  Metrics.EventMap = MEMORY_EVENTID_MAP;

  Entry = TblPtr;
  while (Metrics.Position < CS_MAX_NUM_MEMORY_TABLE_ENTRIES) {
    CS_ValidationMetrics_StartNext(&Metrics, Entry->State);

    CS_ValidateEntryAddress(&Metrics, Entry->StartAddress, Entry->NumBytesToChecksum,
                            CFE_PSP_MEM_ANY);

    // increment the respective counter for final report
    CS_ValidationMetrics_Accumulate(&Metrics);
    ++Entry;
  }

  return CS_ValidationMetrics_GetFinalStatus(&Metrics);
}

/*******************************************************************************/
// CS Validation Callback function for Tables Table
//
// THE NAME-BASED TABLES VALIDATE FIVE OF SIX ERROR KINDS -- everything but MEM_RANGE, which has
// no address to check. Note the duplicate check runs ONLY when the name passed AND the state is
// a commandable one, so a table full of empty slots is not 24 * 23 / 2 string compares.
I32 CS_ValidateTablesChecksumDefinitionTable(U8 *TblPtr)
{
  U16 TABLES_EVENTID_MAP[CS_ValidationError_MAX];

  CS_Def_Tables_Table_Entry_t *Entry = NULL;
  CS_ValidationMetrics_t Metrics;

  TABLES_EVENTID_MAP[CS_ValidationError_NONE] = CS_VAL_TABLES_INF_EID;
  TABLES_EVENTID_MAP[CS_ValidationError_LONG_NAME] = CS_VAL_TABLES_DEF_TBL_LONG_NAME_ERR_EID;
  TABLES_EVENTID_MAP[CS_ValidationError_STATE] = CS_VAL_TABLES_STATE_ERR_EID;
  TABLES_EVENTID_MAP[CS_ValidationError_ZERO_NAME] = CS_VAL_TABLES_DEF_TBL_ZERO_NAME_ERR_EID;
  TABLES_EVENTID_MAP[CS_ValidationError_DUPLICATE] = CS_VAL_TABLES_DEF_TBL_DUPL_ERR_EID;
  TABLES_EVENTID_MAP[CS_ValidationError_MEM_RANGE] = 0;

  MemSet(&Metrics, 0, sizeof(CS_ValidationMetrics_t));

  // These are needed for assembling event data, if necessary
  Metrics.TableName = "Tables";
  Metrics.EventMap = TABLES_EVENTID_MAP;

  Entry = TblPtr;
  while (Metrics.Position < CS_MAX_NUM_TABLES_TABLE_ENTRIES) {
    CS_ValidationMetrics_StartNext(&Metrics, Entry->State);

    // sizeof(Entry->Name) and sizeof(*Entry) in NASA's C -- 40 and 42, written out because
    // `sizeof` through `->` does not work in this compiler (HolyC limit #16), and the 42 is the
    // odd stride measured in cs_msg.HC.
    CS_ValidateEntryName(&Metrics, Entry->Name, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    if (CS_ValidationMetrics_IsCurrentOK(&Metrics) && CS_StateValid(Entry->State)) {
      CS_CheckForDuplicateEntry(&Metrics, Entry->Name, sizeof(CS_Def_Tables_Table_Entry_t));
    }

    // increment the respective counter for final report
    CS_ValidationMetrics_Accumulate(&Metrics);
    ++Entry;
  }

  return CS_ValidationMetrics_GetFinalStatus(&Metrics);
}

/*******************************************************************************/
// CS Validation Callback function for App Table
I32 CS_ValidateAppChecksumDefinitionTable(U8 *TblPtr)
{
  U16 APP_EVENTID_MAP[CS_ValidationError_MAX];

  CS_Def_App_Table_Entry_t *Entry;
  CS_ValidationMetrics_t Metrics;

  APP_EVENTID_MAP[CS_ValidationError_NONE] = CS_VAL_APP_INF_EID;
  APP_EVENTID_MAP[CS_ValidationError_LONG_NAME] = CS_VAL_APP_DEF_TBL_LONG_NAME_ERR_EID;
  APP_EVENTID_MAP[CS_ValidationError_STATE] = CS_VAL_APP_STATE_ERR_EID;
  APP_EVENTID_MAP[CS_ValidationError_ZERO_NAME] = CS_VAL_APP_DEF_TBL_ZERO_NAME_ERR_EID;
  APP_EVENTID_MAP[CS_ValidationError_DUPLICATE] = CS_VAL_APP_DEF_TBL_DUPL_ERR_EID;
  APP_EVENTID_MAP[CS_ValidationError_MEM_RANGE] = 0;

  MemSet(&Metrics, 0, sizeof(CS_ValidationMetrics_t));

  // These are needed for assembling event data, if necessary
  Metrics.TableName = "Apps";
  Metrics.EventMap = APP_EVENTID_MAP;

  Entry = TblPtr;
  while (Metrics.Position < CS_MAX_NUM_APP_TABLE_ENTRIES) {
    CS_ValidationMetrics_StartNext(&Metrics, Entry->State);

    // 20 and 22 -- sizeof(Entry->Name) and sizeof(*Entry) in NASA's C.
    CS_ValidateEntryName(&Metrics, Entry->Name, CFE_MISSION_MAX_API_LEN);
    if (CS_ValidationMetrics_IsCurrentOK(&Metrics) && CS_StateValid(Entry->State)) {
      CS_CheckForDuplicateEntry(&Metrics, Entry->Name, sizeof(CS_Def_App_Table_Entry_t));
    }

    // increment the respective counter for final report
    CS_ValidationMetrics_Accumulate(&Metrics);
    ++Entry;
  }

  return CS_ValidationMetrics_GetFinalStatus(&Metrics);
}

/*******************************************************************************/
// CS  processing new definition tables for EEPROM or Memory
//
// ONE HANDLER FOR TWO TABLES, which is why it takes a wrapper rather than naming a type: the only
// difference between the EEPROM and the Memory table at this point is which global state byte
// tw->GlobalState points at. NASA's own comment spells "chekcksums"; kept.
//
// THE memset BEFORE THE COPY IS THE WHOLE SAFETY PROPERTY. Every results entry is wiped, so an
// entry the new definition table leaves empty does not keep the old one's address and byte count
// -- a ground table load that REMOVES a region must stop CS checksumming it.
U0 CS_ProcessNewEepromMemoryDefinitionTable(CS_TableWrapper_t *tw)
{
  CS_Def_EepromMemory_Table_Entry_t *DefEntry = NULL;
  CS_Res_EepromMemory_Table_Entry_t *ResultsEntry = NULL;
  U16 Loop = 0;
  U16 NumRegionsInTable = 0;
  U32 PreviousState = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t

  // We don't want to be doing chekcksums while changing the table out
  if (tw->GlobalState) {
    PreviousState = *tw->GlobalState;
    *tw->GlobalState = CS_ChecksumState_DISABLED;
  }

  Loop = 0;
  while (TRUE) {
    ResultsEntry = CS_GetResEntryAddr(tw, Loop);
    DefEntry = CS_GetDefEntryAddr(tw, Loop);

    if (ResultsEntry == NULL || DefEntry == NULL) {
      break;
    }

    // wipe the entry, sets everything to safe state, state set to CS_ChecksumState_EMPTY (0)
    MemSet(ResultsEntry, 0, sizeof(CS_Res_EepromMemory_Table_Entry_t));

    if (CS_StateValid(DefEntry->State)) {
      // This is just a real simple test, because all of the exception handling
      //  has already been done by the Validation routine above
      NumRegionsInTable++;

      ResultsEntry->State = DefEntry->State;
      ResultsEntry->NumBytesToChecksum = DefEntry->NumBytesToChecksum;
      ResultsEntry->StartAddress = DefEntry->StartAddress;
    }

    ++Loop;
  }

  // Reset the table back to the original checksumming state
  if (tw->GlobalState) {
    *tw->GlobalState = PreviousState;
  }

  CS_ResetTablesTblResultEntry(tw->ResTblPtr);

  if (NumRegionsInTable == 0) {
    CFE_EVS_SendEvent(CS_PROCESS_EEPROM_MEMORY_NO_ENTRIES_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "CS %s Table: No valid entries in the table", CS_GetTableTypeAsString(tw));
  }
}

/*******************************************************************************/
// Helper function to split the App.Table name pattern
//
// A cFE TABLE'S FULL NAME IS "Owner.Table", and CS's tables table holds the full name. This
// splits it so the owner can be compared against CS's own app name -- which is how CS knows
// whether a table it is asked to watch is one of its OWN, and therefore whether it already has a
// handle rather than needing to share one.
//
// THE NO-SEPARATOR CASE TREATS THE WHOLE STRING AS A TABLE NAME with an empty owner, so a bare
// "DefEepromTbl" never matches CS's app name and is looked up by share like anyone else's.
U0 CS_ExtractNames(CS_Def_Tables_Table_Entry_t *DefEntry, U8 *AppBuf, I64 AppSz, U8 *TableBuf,
                   I64 TableSz)
{
  U8 *Sep;
  I64 TableNameLen;
  I64 AppNameLen;

  // Look for the separator char (.) somewhere in the name
  // sizeof(DefEntry->Name) is CFE_MISSION_TBL_MAX_FULL_NAME_LEN, written out: `sizeof` through
  // `->` does not work in this compiler (HolyC limit #16).
  TableNameLen = OS_strnlen(DefEntry->Name, CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
  Sep = MemChr(DefEntry->Name, '.', TableNameLen);
  if (Sep == NULL) {
    // There is no separator, assume the name is just a table name
    Sep = DefEntry->Name;
    AppNameLen = 0;
  } else {
    // Move past the separator
    AppNameLen = Sep - DefEntry->Name;
    ++Sep;
  }

  TableNameLen -= AppNameLen;

  if (AppNameLen >= AppSz) {
    AppNameLen = AppSz - 1;
  }
  if (TableNameLen >= TableSz) {
    TableNameLen = TableSz - 1;
  }

  MemCpy(AppBuf, DefEntry->Name, AppNameLen);
  AppBuf[AppNameLen] = 0;
  MemCpy(TableBuf, Sep, TableNameLen);
  TableBuf[TableNameLen] = 0;
}

/*******************************************************************************/
// CS processing new definition tables for Tables
//
// THE ONE HANDLER THAT CAN POINT A WRAPPER AT A RESULTS ENTRY. If the new tables table names one
// of CS's OWN eight tables, that wrapper's ResTblPtr is aimed at the matching results entry -- so
// CS_SetDefEntryState can later invalidate the checksum of the very table it just modified. All
// six are cleared to NULL first, so a table dropped from the new definition stops being tracked.
//
// AND NOTE THE REUSE OF `TableId`: the clearing loop and the name-matching loop inside the walk
// share one variable, which is NASA's, and the inner loop's `break` leaves it at the matched
// index -- harmless only because nothing reads it afterwards.
U0 CS_ProcessNewTablesDefinitionTable(CS_TableWrapper_t *tw)
{
  CS_Def_Tables_Table_Entry_t *DefEntry = NULL;
  CS_Res_Tables_Table_Entry_t *ResultsEntry = NULL;
  U16 Loop = 0;
  U16 NumRegionsInTable = 0;
  U32 PreviousState = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t
  U32 AppID = CFE_ES_APPID_UNDEFINED;         // CFE_ES_AppId_t
  I16 TableHandle = CFE_TBL_BAD_TABLE_HANDLE; // CFE_TBL_Handle_t
  Bool Owned = FALSE;
  U8 AppName[OS_MAX_API_NAME];
  U8 TableAppName[OS_MAX_API_NAME];
  U8 TableTableName[CFE_MISSION_TBL_MAX_NAME_LENGTH];
  U16 TableId;

  CFE_ES_GetAppID(&AppID);
  CFE_ES_GetAppName(AppName, AppID, OS_MAX_API_NAME);

  // We don't want to be doing chekcksums while changing the table out
  PreviousState = CS_AppData.HkPacket.Payload.TablesCSState;
  CS_AppData.HkPacket.Payload.TablesCSState = CS_ChecksumState_DISABLED;

  // Assume none of the CS tables are listed in the new Tables table
  for (TableId = 0; TableId < CS_NUM_TABLES; ++TableId) {
    CS_AppData.Tbl[TableId].ResTblPtr = NULL;
  }

  Loop = 0;
  while (TRUE) {
    DefEntry = CS_GetDefEntryAddr(tw, Loop);
    ResultsEntry = CS_GetResEntryAddr(tw, Loop);

    if (DefEntry == NULL || ResultsEntry == NULL) {
      break;
    }

    // wipe the entry, sets everything to safe state, state set to CS_ChecksumState_EMPTY (0)
    // This also needs to explicitly set the TBL handle as 0 might be valid
    MemSet(ResultsEntry, 0, sizeof(CS_Res_Tables_Table_Entry_t));
    ResultsEntry->TblHandleID = CFE_TBL_HANDLEID_UNDEFINED;

    if (CS_StateValid(DefEntry->State)) {
      CS_ExtractNames(DefEntry, TableAppName, OS_MAX_API_NAME, TableTableName,
                      CFE_MISSION_TBL_MAX_NAME_LENGTH);

      TableHandle = CFE_TBL_BAD_TABLE_HANDLE;
      Owned = FALSE;

      // if the table's owner's name is CS
      if (StrCmp(TableAppName, AppName) == 0) {
        for (TableId = 0; TableId < CS_NUM_TABLES; ++TableId) {
          if (CS_CheckDefTableNameMatch(TableTableName, TableId)) {
            CS_AppData.Tbl[TableId].ResTblPtr = ResultsEntry;

            TableHandle = CS_GetDefHandle(TableId);
            Owned = TRUE;
            break;
          }
          if (CS_CheckResTableNameMatch(TableTableName, TableId)) {
            TableHandle = CS_GetResHandle(TableId);
            Owned = TRUE;
            break;
          }
        }
      }

      // This is just a real simple test, because all of the exception handling
      //  has already been done by the Validation routine above
      NumRegionsInTable++;

      ResultsEntry->State = DefEntry->State;
      ResultsEntry->TblHandleID = CFE_TBL_HandleToID(TableHandle);
      ResultsEntry->IsCSOwner = Owned;

      // sizeof(ResultsEntry->Name) and sizeof(DefEntry->Name), both 40.
      CFE_SB_MessageStringGet(ResultsEntry->Name, DefEntry->Name, NULL,
                              CFE_MISSION_TBL_MAX_FULL_NAME_LEN,
                              CFE_MISSION_TBL_MAX_FULL_NAME_LEN);
    }

    ++Loop;
  }

  // Reset the table back to the original checksumming state

  CS_AppData.HkPacket.Payload.TablesCSState = PreviousState;

  if (NumRegionsInTable == 0) {
    CFE_EVS_SendEvent(CS_PROCESS_TABLES_NO_ENTRIES_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "CS Tables Table: No valid entries in the table");
  }
}

/*******************************************************************************/
// CS processing new definition tables for Apps
//
// AND NOTE WHAT THIS ONE DOES *NOT* DO: it copies only the state and the name, no address and no
// size, because an app's code address is looked up every time through CFE_ES_GetModuleInfo rather
// than stored. Compare the EEPROM/Memory handler, which copies three fields.
//
// IT ALSO CALLS CS_ResetTablesTblResultEntry, which the TABLES handler does not. Both touch CS's
// own tables table, so the asymmetry is NASA's and is kept.
U0 CS_ProcessNewAppDefinitionTable(CS_TableWrapper_t *tw)
{
  CS_Def_App_Table_Entry_t *DefEntry = NULL;
  CS_Res_App_Table_Entry_t *ResultsEntry = NULL;
  U16 Loop = 0;
  U16 NumRegionsInTable = 0;
  U32 PreviousState = CS_ChecksumState_EMPTY; // CS_ChecksumState_Enum_t

  // We don't want to be doing chekcksums while changing the table out

  PreviousState = CS_AppData.HkPacket.Payload.AppCSState;
  CS_AppData.HkPacket.Payload.AppCSState = CS_ChecksumState_DISABLED;

  Loop = 0;
  while (TRUE) {
    DefEntry = CS_GetDefEntryAddr(tw, Loop);
    ResultsEntry = CS_GetResEntryAddr(tw, Loop);

    if (DefEntry == NULL || ResultsEntry == NULL) {
      break;
    }

    // wipe the entry, sets everything to safe state, state set to CS_ChecksumState_EMPTY (0)
    MemSet(ResultsEntry, 0, sizeof(CS_Res_App_Table_Entry_t));

    if (CS_StateValid(DefEntry->State)) {
      // This is just a real simple test, because all of the exception handling
      //  has already been done by the Validation routine above
      NumRegionsInTable++;

      ResultsEntry->State = DefEntry->State;
      // sizeof(ResultsEntry->Name) and sizeof(DefEntry->Name), both 20.
      CFE_SB_MessageStringGet(ResultsEntry->Name, DefEntry->Name, NULL, CFE_MISSION_MAX_API_LEN,
                              CFE_MISSION_MAX_API_LEN);
    }

    ++Loop;
  }

  // Reset the table back to the original checksumming state

  CS_AppData.HkPacket.Payload.AppCSState = PreviousState;
  CS_ResetTablesTblResultEntry(tw->ResTblPtr);

  if (NumRegionsInTable == 0) {
    CFE_EVS_SendEvent(CS_PROCESS_APP_NO_ENTRIES_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "CS Apps Table: No valid entries in the table");
  }
}

/*******************************************************************************/
// Local helper function
// Register the result table with CFE table services and obtain the address
//
// DUMP ONLY, SINGLE BUFFER, AND NO VALIDATION CALLBACK -- a results table is CS's own output, so
// the ground may read it and may not load it.
I32 CS_RegisterResultTable(CS_TableWrapper_t *tw)
{
  I32 Result;

  Result = CFE_TBL_Register(&tw->ResHandle, tw->ResTableName, tw->NumEntries * tw->ResEntrySize,
                            CFE_TBL_OPT_SNGL_BUFFER | CFE_TBL_OPT_DUMP_ONLY, NULL);

  if (Result >= CFE_SUCCESS) {
    Result = CFE_TBL_GetAddress(&tw->ResAddr, tw->ResHandle);
  }

  if (Result >= CFE_SUCCESS) {
    Result = CFE_SUCCESS;
  }

  return Result;
}

/*******************************************************************************/
// Local helper function
// Register the definition table with CFE table services, load the
// table, and obtain the address.
//
// THE COLD-BOOT FALLBACK, and the one line that makes it safe: a table loaded from CS's own
// zeroed default has its GLOBAL STATE set to DISABLED, so CS does not come up claiming to watch
// things it was never told about. A table loaded from a FILE keeps whatever states the file says.
I32 CS_RegisterDefinitionTable(CS_TableWrapper_t *tw, U8 *DefinitionTableFileName,
                               I32 (*CallBackFunction)(U8 *)) // CFE_TBL_CallbackFuncPtr_t
{
  Bool LoadedFromMemory = FALSE;
  I32 Result;

  Result = CFE_TBL_Register(&tw->DefHandle, tw->DefTableName, tw->NumEntries * tw->DefEntrySize,
                            CFE_TBL_OPT_SNGL_BUFFER | CFE_TBL_OPT_LOAD_DUMP, CallBackFunction);

  if (Result >= CFE_SUCCESS) {
    Result = CFE_TBL_Load(tw->DefHandle, CFE_TBL_SRC_FILE, DefinitionTableFileName);

    // if the load from the file fails, load from the default tables in CS
    if (Result < CFE_SUCCESS) {
      Result = CFE_TBL_Load(tw->DefHandle, CFE_TBL_SRC_ADDRESS, tw->DefaultDefinitionPtr);
      LoadedFromMemory = Result >= CFE_SUCCESS;
    }
  }

  if (Result >= CFE_SUCCESS) {
    Result = CFE_TBL_GetAddress(&tw->DefAddr, tw->DefHandle);
  }

  if (Result >= CFE_SUCCESS) {
    // If we loaded from file successfully then the states we wish to use have already been set
    //  If we loaded from memory then disable the table
    if (LoadedFromMemory && tw->GlobalState != NULL) {
      *tw->GlobalState = CS_ChecksumState_DISABLED;
    }

    CS_CallTableUpdateHandler(tw);
    Result = CFE_SUCCESS;
  }

  return Result;
}

/*******************************************************************************/
// CS  function for initializing new tables
//
// A NULL FILENAME MEANS "THIS TYPE HAS NO TABLE", which is how the cFE core and OS code segments
// get through CS_InitAllTables' one loop without a special case: their wrappers have no
// DefTableName, no filename and no update handler, so this returns CFE_SUCCESS having done
// nothing and cs_init.c's `if (ErrorEventID != 0)` keeps the silence.
I32 CS_TableInit(CS_TableWrapper_t *tw, U8 *DefinitionTableFileName,
                 I32 (*CallBackFunction)(U8 *)) // CFE_TBL_CallbackFuncPtr_t
{
  I32 Result;

  if (DefinitionTableFileName == NULL) {
    Result = CFE_SUCCESS; // nothing to do
  } else {
    Result = CS_RegisterResultTable(tw);

    if (Result == CFE_SUCCESS) {
      Result = CS_RegisterDefinitionTable(tw, DefinitionTableFileName, CallBackFunction);
    }

    if (Result != CFE_SUCCESS) {
      CFE_EVS_SendEvent(CS_TBL_INIT_ERR_EID, CFE_EVS_EventType_ERROR,
                        "CS received error 0x%08X initializing tables for %s", Result,
                        CS_GetTableTypeAsString(tw));
    }
  }

  return Result;
}

/*******************************************************************************/
// CS Handles table updates
//
// SIX RESULTS AND ONE IS READ. NASA's own comment says why -- "there are several values that are
// returned and assigned, but never evaluated. This is done so intentionally, as it helps us with
// Source-Level debugging" -- and the event at the bottom prints five of them. So the variables
// are not dead: they are a snapshot for the error message. Kept verbatim, including that
// GetResult1 is assigned into Result and GetResult2 is the one the event prints.
//
// AND THE RELEASE-BEFORE-MANAGE ORDER IS THE POINT OF THE FUNCTION. CFE_TBL_Manage is what
// actually swaps in a ground-loaded buffer, and it cannot while CS holds an address, so both
// addresses are released first and re-acquired after. CFE_TBL_INFO_UPDATED on the second
// GetAddress is the signal that a load happened, and the ONLY thing that calls the update handler.
//
// THE UNREGISTER LOOP IS FOR SOMEONE ELSE'S TABLES. When the tables table itself is replaced, CS
// holds shared handles to every table it was watching; those have to go back before the new
// definition is processed, and `IsCSOwner` is what keeps CS from unregistering its own.
I32 CS_HandleTableUpdate(CS_TableWrapper_t *tw)
{
  I32 ReleaseResult1 = CFE_SUCCESS;
  I32 ManageResult1 = CFE_SUCCESS;
  I32 GetResult1 = CFE_SUCCESS;
  I32 ReleaseResult2 = CFE_SUCCESS;
  I32 ManageResult2 = CFE_SUCCESS;
  I32 GetResult2 = CFE_SUCCESS;
  I32 Result = CFE_SUCCESS;
  I32 Loop = 0;

  I16 LocalHandle; // CFE_TBL_Handle_t
  CS_Res_Tables_Table_Entry_t *ResTablesTblPtr;

  // Below, there are several values that are returned and assigned, but never evaluated.
  // This is done so intentionally, as it helps us with Source-Level debugging this functions.

  // Release the Table Address.
  ReleaseResult1 = CFE_TBL_ReleaseAddress(tw->ResHandle);
  ReleaseResult2 = CFE_TBL_ReleaseAddress(tw->DefHandle);

  ManageResult1 = CFE_TBL_Manage(tw->ResHandle);
  ManageResult2 = CFE_TBL_Manage(tw->DefHandle);

  GetResult1 = CFE_TBL_GetAddress(&tw->ResAddr, tw->ResHandle);
  Result = GetResult1;

  if (Result >= CFE_SUCCESS) {
    GetResult2 = CFE_TBL_GetAddress(&tw->DefAddr, tw->DefHandle);
    Result = GetResult2;
  }

  if (Result == CFE_TBL_INFO_UPDATED) {
    if (CS_CheckTableId(tw, CS_ChecksumType_TABLES_TABLE)) {
      // before we update the results table, we need to release all of the
      //  table handles that are in the results table
      Loop = 0;
      while (TRUE) {
        ResTablesTblPtr = CS_GetTablesResEntry(Loop);
        if (ResTablesTblPtr == NULL) {
          break;
        }
        if (!ResTablesTblPtr->IsCSOwner) {
          LocalHandle = CFE_TBL_HandleFromID(ResTablesTblPtr->TblHandleID);
        } else {
          LocalHandle = CFE_TBL_BAD_TABLE_HANDLE;
        }
        if (CFE_TBL_HANDLE_IS_VALID(LocalHandle)) {
          CFE_TBL_Unregister(LocalHandle);
        }
        ++Loop;
      }
    }

    CS_CallTableUpdateHandler(tw);

    Result = CFE_SUCCESS;
  } else {
    if (Result < CFE_SUCCESS) {
      // There was a problem somewhere, generate an event
      CFE_EVS_SendEvent(CS_TBL_UPDATE_ERR_EID, CFE_EVS_EventType_ERROR,
                        "CS had problems updating table. Res Release: 0x%08X Def Release:0x%08X Res "
                        "Manage:0x%08X Def Manage: 0x%08X Get:0x%08X for table %s",
                        ReleaseResult1, ReleaseResult2, ManageResult1, ManageResult2, GetResult2,
                        CS_GetTableTypeAsString(tw));
    }
  }
  return Result;
}
#endif
