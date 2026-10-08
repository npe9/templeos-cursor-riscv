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
// CHECKSUM'S INITIALISATION -- the 1:1 translation of NASA's fsw/src/cs_init.c, 307 lines and
// three functions. Step 2 of three, and the smallest of the three by a wide margin.
//
// WHY IT IS A STEP OF ITS OWN rather than part of either group: it depends on the 3-cycle (seven
// functions out of cs_table_processing.c and one out of cs_utils.c) and the 7-cycle depends on IT
// -- cs_app.c needs all three functions here. It is the join between CS's two halves.
//
// AND IT IS WHERE THE SIX WRAPPERS COME FROM. Everything in cs_utils.c, cs_compute.c and
// cs_table_processing.c works through a CS_TableWrapper_t; CS_InitAllTables is the one function
// that fills one in. Until it ran, step 1's exercise had to hand-build all six.
#ifndef CS_INIT_HC
#define CS_INIT_HC

/*******************************************************************************/
// CS Software Bus Setup
//
// THREE SUBSCRIPTIONS, AND THE ORDER IS LOAD-BEARING. Housekeeping first, then the background
// cycle INSIDE the housekeeping success arm, then commands guarded on `Result == CFE_SUCCESS` --
// so a failed housekeeping subscribe skips the background one but STILL ATTEMPTS commands, while a
// failed background subscribe leaves Result set and skips commands. That is not symmetric and it
// is NASA's; a translation that flattened the nesting would subscribe to commands in a case where
// NASA does not.
I32 CS_SbInit()
{
  I32 Result = CFE_SUCCESS;

  // Initialize housekeeping packet
  CFE_MSG_Init(&CS_AppData.HkPacket.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CS_HK_TLM_MID),
               sizeof(CS_HkPacket_t));

  // Create Software Bus message pipe
  Result = CFE_SB_CreatePipe(&CS_AppData.CmdPipe, CS_PIPE_DEPTH, CS_CMD_PIPE_NAME);
  if (Result != CFE_SUCCESS) {
    CFE_EVS_SendEvent(CS_CR_PIPE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Software Bus Create Pipe for command returned: 0x%08X", Result);
  } else {
    // Subscribe to Housekeeping request commands
    Result = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CS_SEND_HK_MID), CS_AppData.CmdPipe);

    if (Result != CFE_SUCCESS) {
      CFE_EVS_SendEvent(CS_INIT_SB_SUBSCRIBE_HK_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Software Bus subscribe to housekeeping returned: 0x%08X", Result);
    } else {
      // Subscribe to background checking schedule
      Result = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CS_BACKGROUND_CYCLE_MID), CS_AppData.CmdPipe);

      if (Result != CFE_SUCCESS) {
        CFE_EVS_SendEvent(CS_INIT_SB_SUBSCRIBE_BACK_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Software Bus subscribe to background cycle returned: 0x%08X", Result);
      }
    }

    if (Result == CFE_SUCCESS) {
      // Subscribe to CS Internal command packets
      Result = CFE_SB_Subscribe(CFE_SB_ValueToMsgId(CS_CMD_MID), CS_AppData.CmdPipe);
      if (Result != CFE_SUCCESS) {
        CFE_EVS_SendEvent(CS_INIT_SB_SUBSCRIBE_CMD_ERR_EID, CFE_EVS_EventType_ERROR,
                          "Software Bus subscribe to command returned: 0x%08X", Result);
      }
    }
  }
  return Result;
}

/*******************************************************************************/
// CS Table Initialization
//
// NASA WRITES FOUR `static const` ARRAYS OF DESIGNATED INITIALISERS and copies one row of each per
// checksum type: the wrapper template, a filename, a validation callback and an event id. HolyC
// has no aggregate initialiser, so all four become RUNTIME FILLS at the top of this function --
// the shape recorded in memory as "generated table init order", and the ordering constraint is
// real: the fill has to run before the loop reads it, and a reader that ran first would see zeros
// with no diagnostic.
//
// EVERY SLOT IS WRITTEN EXPLICITLY, INCLUDING THE ZEROES. NASA leaves the cFE core and OS rows out
// of three of the four arrays, and those omissions are LOAD-BEARING: a NULL filename is how
// CS_TableInit knows "this type has no table" and returns success having done nothing, and a zero
// event id is how the error arm below stays silent for them. Writing them out is what keeps a
// stale frame from inventing a filename.
//
// AND `*tw = TABLE_INITIALIZERS[TableId]` IS A 112-BYTE STRUCT COPY THROUGH A BARE POINTER, which
// this compiler truncates to eight bytes (limit #21). It is a MemCpy here, with the size written
// out, because a class copy through a pointer is exactly the form check_struct_copy refuses.
I32 CS_InitAllTables()
{
  CS_TableWrapper_t TABLE_INITIALIZERS[CS_NUM_TABLES];
  U8 *TABLE_FILENAME_MAP[CS_NUM_TABLES];
  I32 (*TABLE_CALLBACK_MAP[CS_NUM_TABLES])(U8 *); // CFE_TBL_CallbackFuncPtr_t
  U16 TABLE_EVENTID_MAP[CS_NUM_TABLES];

  I32 ResultAll;
  I32 Result;
  U8 *LoadFilename;
  I32 (*ValidationFunc)(U8 *); // CFE_TBL_CallbackFuncPtr_t
  CS_TableWrapper_t *tw;
  U32 TableId; // CS_ChecksumType_Enum_t
  U16 ErrorEventID;

  MemSet(TABLE_INITIALIZERS, 0, sizeof(CS_TableWrapper_t) * CS_NUM_TABLES);

  TABLE_INITIALIZERS[CS_ChecksumType_CFECORE].BaselineValue =
      &CS_AppData.HkPacket.Payload.CfeCoreBaseline;
  TABLE_INITIALIZERS[CS_ChecksumType_CFECORE].ResEntrySize =
      sizeof(CS_Res_EepromMemory_Table_Entry_t);
  TABLE_INITIALIZERS[CS_ChecksumType_CFECORE].ResAddr = &CS_AppData.CfeCoreCodeSeg;
  TABLE_INITIALIZERS[CS_ChecksumType_CFECORE].NumEntries = 1;

  TABLE_INITIALIZERS[CS_ChecksumType_OSCORE].BaselineValue =
      &CS_AppData.HkPacket.Payload.OSBaseline;
  TABLE_INITIALIZERS[CS_ChecksumType_OSCORE].ResEntrySize =
      sizeof(CS_Res_EepromMemory_Table_Entry_t);
  TABLE_INITIALIZERS[CS_ChecksumType_OSCORE].ResAddr = &CS_AppData.OSCodeSeg;
  TABLE_INITIALIZERS[CS_ChecksumType_OSCORE].NumEntries = 1;

  TABLE_INITIALIZERS[CS_ChecksumType_EEPROM_TABLE].DefTableName = CS_DEF_EEPROM_TABLE_NAME;
  TABLE_INITIALIZERS[CS_ChecksumType_EEPROM_TABLE].ResTableName = CS_RESULTS_EEPROM_TABLE_NAME;
  TABLE_INITIALIZERS[CS_ChecksumType_EEPROM_TABLE].GlobalState =
      &CS_AppData.HkPacket.Payload.EepromCSState;
  TABLE_INITIALIZERS[CS_ChecksumType_EEPROM_TABLE].NumEntries = CS_MAX_NUM_EEPROM_TABLE_ENTRIES;
  TABLE_INITIALIZERS[CS_ChecksumType_EEPROM_TABLE].DefEntrySize =
      sizeof(CS_Def_EepromMemory_Table_Entry_t);
  TABLE_INITIALIZERS[CS_ChecksumType_EEPROM_TABLE].ResEntrySize =
      sizeof(CS_Res_EepromMemory_Table_Entry_t);
  // offsetof(CS_Def_EepromMemory_Table_Entry_t, State) -- 8, measured in cs_msg.HC.
  TABLE_INITIALIZERS[CS_ChecksumType_EEPROM_TABLE].DefStateOffset = 8;
  TABLE_INITIALIZERS[CS_ChecksumType_EEPROM_TABLE].UpdateHandler =
      &CS_ProcessNewEepromMemoryDefinitionTable;
  TABLE_INITIALIZERS[CS_ChecksumType_EEPROM_TABLE].DefaultDefinitionPtr =
      CS_AppData.DefaultEepromDefTable;

  TABLE_INITIALIZERS[CS_ChecksumType_MEMORY_TABLE].DefTableName = CS_DEF_MEMORY_TABLE_NAME;
  TABLE_INITIALIZERS[CS_ChecksumType_MEMORY_TABLE].ResTableName = CS_RESULTS_MEMORY_TABLE_NAME;
  TABLE_INITIALIZERS[CS_ChecksumType_MEMORY_TABLE].GlobalState =
      &CS_AppData.HkPacket.Payload.MemoryCSState;
  TABLE_INITIALIZERS[CS_ChecksumType_MEMORY_TABLE].NumEntries = CS_MAX_NUM_MEMORY_TABLE_ENTRIES;
  TABLE_INITIALIZERS[CS_ChecksumType_MEMORY_TABLE].DefEntrySize =
      sizeof(CS_Def_EepromMemory_Table_Entry_t);
  TABLE_INITIALIZERS[CS_ChecksumType_MEMORY_TABLE].ResEntrySize =
      sizeof(CS_Res_EepromMemory_Table_Entry_t);
  TABLE_INITIALIZERS[CS_ChecksumType_MEMORY_TABLE].DefStateOffset = 8;
  TABLE_INITIALIZERS[CS_ChecksumType_MEMORY_TABLE].UpdateHandler =
      &CS_ProcessNewEepromMemoryDefinitionTable;
  TABLE_INITIALIZERS[CS_ChecksumType_MEMORY_TABLE].DefaultDefinitionPtr =
      CS_AppData.DefaultMemoryDefTable;

  TABLE_INITIALIZERS[CS_ChecksumType_TABLES_TABLE].DefTableName = CS_DEF_TABLES_TABLE_NAME;
  TABLE_INITIALIZERS[CS_ChecksumType_TABLES_TABLE].ResTableName = CS_RESULTS_TABLES_TABLE_NAME;
  TABLE_INITIALIZERS[CS_ChecksumType_TABLES_TABLE].GlobalState =
      &CS_AppData.HkPacket.Payload.TablesCSState;
  TABLE_INITIALIZERS[CS_ChecksumType_TABLES_TABLE].NumEntries = CS_MAX_NUM_TABLES_TABLE_ENTRIES;
  TABLE_INITIALIZERS[CS_ChecksumType_TABLES_TABLE].DefEntrySize =
      sizeof(CS_Def_Tables_Table_Entry_t);
  TABLE_INITIALIZERS[CS_ChecksumType_TABLES_TABLE].ResEntrySize =
      sizeof(CS_Res_Tables_Table_Entry_t);
  // offsetof(CS_Def_Tables_Table_Entry_t, State) -- 0.
  TABLE_INITIALIZERS[CS_ChecksumType_TABLES_TABLE].DefStateOffset = 0;
  TABLE_INITIALIZERS[CS_ChecksumType_TABLES_TABLE].UpdateHandler =
      &CS_ProcessNewTablesDefinitionTable;
  TABLE_INITIALIZERS[CS_ChecksumType_TABLES_TABLE].DefaultDefinitionPtr =
      CS_AppData.DefaultTablesDefTable;

  TABLE_INITIALIZERS[CS_ChecksumType_APP_TABLE].DefTableName = CS_DEF_APP_TABLE_NAME;
  TABLE_INITIALIZERS[CS_ChecksumType_APP_TABLE].ResTableName = CS_RESULTS_APP_TABLE_NAME;
  TABLE_INITIALIZERS[CS_ChecksumType_APP_TABLE].GlobalState =
      &CS_AppData.HkPacket.Payload.AppCSState;
  TABLE_INITIALIZERS[CS_ChecksumType_APP_TABLE].NumEntries = CS_MAX_NUM_APP_TABLE_ENTRIES;
  TABLE_INITIALIZERS[CS_ChecksumType_APP_TABLE].DefEntrySize = sizeof(CS_Def_App_Table_Entry_t);
  TABLE_INITIALIZERS[CS_ChecksumType_APP_TABLE].ResEntrySize = sizeof(CS_Res_App_Table_Entry_t);
  // offsetof(CS_Def_App_Table_Entry_t, State) -- 0.
  TABLE_INITIALIZERS[CS_ChecksumType_APP_TABLE].DefStateOffset = 0;
  TABLE_INITIALIZERS[CS_ChecksumType_APP_TABLE].UpdateHandler = &CS_ProcessNewAppDefinitionTable;
  TABLE_INITIALIZERS[CS_ChecksumType_APP_TABLE].DefaultDefinitionPtr =
      CS_AppData.DefaultAppDefTable;

  TABLE_FILENAME_MAP[CS_ChecksumType_CFECORE] = NULL;
  TABLE_FILENAME_MAP[CS_ChecksumType_OSCORE] = NULL;
  TABLE_FILENAME_MAP[CS_ChecksumType_EEPROM_TABLE] = CS_DEF_EEPROM_TABLE_FILENAME;
  TABLE_FILENAME_MAP[CS_ChecksumType_MEMORY_TABLE] = CS_DEF_MEMORY_TABLE_FILENAME;
  TABLE_FILENAME_MAP[CS_ChecksumType_TABLES_TABLE] = CS_DEF_TABLES_TABLE_FILENAME;
  TABLE_FILENAME_MAP[CS_ChecksumType_APP_TABLE] = CS_DEF_APP_TABLE_FILENAME;

  TABLE_CALLBACK_MAP[CS_ChecksumType_CFECORE] = NULL;
  TABLE_CALLBACK_MAP[CS_ChecksumType_OSCORE] = NULL;
  TABLE_CALLBACK_MAP[CS_ChecksumType_EEPROM_TABLE] = &CS_ValidateEepromChecksumDefinitionTable;
  TABLE_CALLBACK_MAP[CS_ChecksumType_MEMORY_TABLE] = &CS_ValidateMemoryChecksumDefinitionTable;
  TABLE_CALLBACK_MAP[CS_ChecksumType_TABLES_TABLE] = &CS_ValidateTablesChecksumDefinitionTable;
  TABLE_CALLBACK_MAP[CS_ChecksumType_APP_TABLE] = &CS_ValidateAppChecksumDefinitionTable;

  TABLE_EVENTID_MAP[CS_ChecksumType_CFECORE] = 0;
  TABLE_EVENTID_MAP[CS_ChecksumType_OSCORE] = 0;
  TABLE_EVENTID_MAP[CS_ChecksumType_EEPROM_TABLE] = CS_INIT_EEPROM_ERR_EID;
  TABLE_EVENTID_MAP[CS_ChecksumType_MEMORY_TABLE] = CS_INIT_MEMORY_ERR_EID;
  TABLE_EVENTID_MAP[CS_ChecksumType_TABLES_TABLE] = CS_INIT_TABLES_ERR_EID;
  TABLE_EVENTID_MAP[CS_ChecksumType_APP_TABLE] = CS_INIT_APP_ERR_EID;

  ResultAll = CFE_SUCCESS;
  tw = CS_AppData.Tbl;

  for (TableId = 0; TableId < CS_NUM_TABLES; ++TableId) {
    MemCpy(tw, &TABLE_INITIALIZERS[TableId], sizeof(CS_TableWrapper_t));
    LoadFilename = TABLE_FILENAME_MAP[TableId];
    ValidationFunc = TABLE_CALLBACK_MAP[TableId];
    ErrorEventID = TABLE_EVENTID_MAP[TableId];

    // If this table needs to be loaded via table services, do that now
    Result = CS_TableInit(tw, LoadFilename, ValidationFunc);
    if (Result != CFE_SUCCESS) {
      // If the init did not work then make sure the global status is set to disabled
      if (tw->GlobalState) {
        *tw->GlobalState = CS_ChecksumState_DISABLED;
      }

      // `ErrorEventID != 0` IS NEVER FALSE WHEN IT IS EVALUATED, and that is provable rather than
      // observed. CS_TableInit returns CFE_SUCCESS immediately when DefinitionTableFileName is
      // NULL, and TABLE_FILENAME_MAP is NULL for exactly the two types whose event id is zero -- so
      // the only types that can reach this block are the four that have an id. A mutation replacing
      // the guard with `TRUE` is a NO-OP and will stay one.
      //
      // IT IS STILL A REAL GUARD, and the mutation that shows what it guards is its neighbour:
      // giving a code-segment type a filename in TABLE_FILENAME_MAP is CAUGHT, because that type
      // can then fail -- and would then try to send event id 0. The guard and the NULL filename are
      // one mechanism stated twice, which is why only one of the two mutations bites.
      if (ErrorEventID != 0) {
        CFE_EVS_SendEvent(ErrorEventID, CFE_EVS_EventType_ERROR,
                          "Table initialization failed for %s: 0x%08X",
                          CS_GetTableTypeAsString(tw), Result);
      }

      ResultAll = Result;
    }

    ++tw;
  }

  return ResultAll;
}

/*******************************************************************************/
// CS Segment Initialization
//
// THE TWO CODE SEGMENTS, and the only place CS asks the PSP where its own code is. Both arms write
// all seven fields -- a failure writes zeros and DISABLED rather than leaving the entry alone --
// which is what keeps a platform that cannot report a segment from making CS checksum whatever the
// BSS happened to hold.
//
// NEITHER SEGMENT IS REAL CODE IN THIS PORT'S DRIVERS, and that is deliberate: see the note at the
// top of cs_msg.HC. CFE_ES_CalculateCRC takes a raw pointer, so pointing a checksum at real text
// would make the number depend on the COMPILER -- the one thing the differential must not do.
U0 CS_InitSegments()
{
  I32 ResultSegment = OS_SUCCESS;
  U32 CFESize;
  U64 CFEAddress; // cpuaddr
  U32 KernelSize;
  U64 KernelAddress; // cpuaddr

  CS_Res_EepromMemory_Table_Entry_t *CodeSeg;

  // Initalize the CFE core segments
  ResultSegment = CFE_PSP_GetCFETextSegmentInfo(&CFEAddress, &CFESize);
  CodeSeg = CS_GetCfeCoreCodeSegResTable();

  if (ResultSegment != OS_SUCCESS) {
    CodeSeg->StartAddress = 0;
    CodeSeg->NumBytesToChecksum = 0;
    CodeSeg->ComputedYet = FALSE;
    CodeSeg->ComparisonValue = 0;
    CodeSeg->ByteOffset = 0;
    CodeSeg->TempChecksumValue = 0;
    CodeSeg->State = CS_ChecksumState_DISABLED;

    CFE_EVS_SendEvent(CS_CFE_TEXT_SEG_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "CFE Text Segment disabled");
  } else {
    CodeSeg->StartAddress = CFEAddress;
    CodeSeg->NumBytesToChecksum = CFESize;
    CodeSeg->ComputedYet = FALSE;
    CodeSeg->ComparisonValue = 0;
    CodeSeg->ByteOffset = 0;
    CodeSeg->TempChecksumValue = 0;
    CodeSeg->State = CS_ChecksumState_ENABLED;
  }

  // Initialize the OS Core code segment

  ResultSegment = CFE_PSP_GetKernelTextSegmentInfo(&KernelAddress, &KernelSize);
  CodeSeg = CS_GetOSCodeSegResTable();

  if (ResultSegment != OS_SUCCESS) {
    CodeSeg->StartAddress = 0;
    CodeSeg->NumBytesToChecksum = 0;
    CodeSeg->ComputedYet = FALSE;
    CodeSeg->ComparisonValue = 0;
    CodeSeg->ByteOffset = 0;
    CodeSeg->TempChecksumValue = 0;
    CodeSeg->State = CS_ChecksumState_DISABLED;

    CFE_EVS_SendEvent(CS_OS_TEXT_SEG_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "OS Text Segment disabled due to platform");
  } else {
    CodeSeg->StartAddress = KernelAddress;
    CodeSeg->NumBytesToChecksum = KernelSize;
    CodeSeg->ComputedYet = FALSE;
    CodeSeg->ComparisonValue = 0;
    CodeSeg->ByteOffset = 0;
    CodeSeg->TempChecksumValue = 0;
    CodeSeg->State = CS_ChecksumState_ENABLED;
  }
}
#endif
