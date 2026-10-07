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
// CHECKSUM'S STATE -- the translation of NASA's fsw/src/cs_app.h, plus the CS_TableWrapper_t
// declaration that cs_table_processing.h carries and CS_AppData_t embeds, plus the global
// instance. Same arrangement as md_global.HC, mm_global.HC and the four cFE globals: NASA
// declares CS_AppData `extern` in cs_app.h and defines it in cs_app.c, and the translation
// defines it here beside its type so the global does not move when a different implementation
// file happens to be gated first.
//
// CS HAS A CONTROL STRUCTURE, AND IT IS A TABLE OF TABLES. MD kept four dwell streams; MM kept
// three buffers and nothing else. CS keeps SIX CS_TableWrapper_t records, one per checksum type,
// and almost every function in the app takes a `CS_TableWrapper_t *tw` and works through it
// rather than naming a type. That is why cs_utils.c, cs_compute.c and cs_table_processing.c form
// a cycle: the wrapper is the shared vocabulary and all three both produce and consume it.
//
// THE WRAPPER IS NASA'S OWN REFACTOR, not this port's. Older CS had six near-identical copies of
// every loop. The wrapper replaced them with one loop plus a per-type descriptor -- which is why
// it carries DefEntrySize, ResEntrySize and DefStateOffset: the generic code indexes and pokes
// entries of six different layouts by byte arithmetic. CS_GetGenericEntryState and
// CS_SetGenericEntryState in cs_utils.c are the two functions that do it.
#ifndef CS_GLOBAL_HC
#define CS_GLOBAL_HC

/*******************************************************************************/
// cs_app.h's own constants.

// THREE ERROR CODES THAT ARE NOT CFE STATUSES. CS returns these from its own helpers, small
// negatives in a space cFE does not use, and the ground never sees them -- they pick which
// event to send.
#define CS_ERROR         -1
#define CS_ERR_NOT_FOUND -2
#define CS_TABLE_ERROR   -3

#define CS_CMD_PIPE_NAME "CS_CMD_PIPE"

// SEVEN CHILD TASK NAMES, because a recompute runs OUT OF LINE. A full recompute of the app
// table can take longer than a cycle, so CS spawns a child task, and OSAL names tasks -- so
// each of the six recompute kinds and the one-shot gets its own name. All seven are within
// OS_MAX_API_NAME, which is 20.
#define CS_RECOMP_OS_TASK_NAME      "CS_RecmpOSTsk"
#define CS_RECOMP_CFECORE_TASK_NAME "CS_RecmpCfeCoreTsk"
#define CS_RECOMP_MEMORY_TASK_NAME  "CS_RecmpMemoryTsk"
#define CS_RECOMP_EEPROM_TASK_NAME  "CS_RecmpEepromTsk"
#define CS_RECOMP_APP_TASK_NAME     "CS_RecmpAppTsk"
#define CS_RECOMP_TABLES_TASK_NAME  "CS_RecmpTableTsk"
#define CS_ONESHOT_TASK_NAME        "CS_OneShotTask"

#define CS_WAKEUP_TIMEOUT 1000

/*******************************************************************************/
// cs_table_processing.h's CS_TableWrapper_t. NASA declares it `struct CS_TableWrapper` so the
// UpdateHandler member can take a pointer to its own type; HolyC resolves a class's own name
// inside its body, the same way cfe_es_generic_pool.HC's CFE_ES_GenPoolRecord_t does for its
// Retrieve and Commit members.
//
// FIVE MEMBERS ARE COMPILE-TIME CONSTANTS and still live in a runtime record: DefTableName,
// ResTableName, DefEntrySize, DefStateOffset and UpdateHandler never change after
// CS_InitAllTables fills them. NASA writes them as a `static const` array of designated
// initialisers in cs_init.c and copies one into place per type. That array becomes a runtime
// fill in the translation -- the shape recorded as "generated table init order" -- so the
// ordering constraint is real and cs_init.HC states it where the fill happens.
class CS_TableWrapper_t
{
  U8 *DefTableName;
  U8 *ResTableName;
  // SIGNED, and it matters. CFE_TBL_Handle_t is an int16 and CFE_TBL_BAD_TABLE_HANDLE is -1
  // (cfe_tbl_internal.HC:110 records why it is not zero in this configuration), so these two
  // held as U16 would make CFE_TBL_HANDLE_IS_VALID -- `(x) != CFE_TBL_BAD_TABLE_HANDLE` -- read
  // 65535 != -1 and answer TRUE for the one value that means "no handle".
  // cs_compute.c's CS_RefreshTableHandleAndAddress is the caller that would then unregister a
  // handle it never had. Same family as the `(I32)` casts docs/HOLYC_STRUCT_LIMITS.md records for
  // high-bit status constants: the layout is identical either way, so no layout gate can see it.
  I16 DefHandle; // CFE_TBL_Handle_t
  I16 ResHandle; // CFE_TBL_Handle_t
  U8 _pad0[4];   // C aligns NumEntries to 8
  I64 NumEntries;
  U8 *DefAddr;
  I64 DefEntrySize;
  I64 DefStateOffset;
  U8 *ResAddr;
  I64 ResEntrySize;
  U8 *DefaultDefinitionPtr;
  U0 (*UpdateHandler)(CS_TableWrapper_t *tw);
  U32 *BaselineValue; // into CS_AppData.HkPacket.Payload
  U8 *GlobalState;    // into CS_AppData.HkPacket.Payload
  CS_Res_Tables_Table_Entry_t *ResTblPtr;
};

/*******************************************************************************/
// THE WHOLE APPLICATION, in one object -- 2,936 bytes, against MM's 1,312 and MD's 2,608.
//
// MOST OF IT IS THE FOUR DEFAULT DEFINITION TABLES: 256 + 256 + 1,008 + 528 = 2,048 bytes, and
// they exist because a definition table has to come from SOMEWHERE on a cold boot when the file
// is missing. CS_TableInit loads the file if it is there and falls back to
// CFE_TBL_Load(CFE_TBL_SRC_ADDRESS, DefaultDefinitionPtr) if it is not -- pointing at one of
// these four, which are zero, which means every entry is CS_STATE_EMPTY. So a CS with no table
// files comes up watching nothing rather than refusing to come up.
//
// THE RESULTS TABLES ARE NOT HERE. Four of the six live in cFE table services, allocated by
// CFE_TBL_Register and reached through tw->ResAddr. The two that ARE here are OSCodeSeg and
// CfeCoreCodeSeg, because a code segment is one entry and needs no ground-replaceable
// definition -- cs_init.c points their wrappers' ResAddr straight at these two members.
class CS_AppData_t
{
  CS_HkPacket_t HkPacket;
  U32 ChildTaskTable; // CS_ChecksumType_Enum_t
  U16 ChildTaskEntryID;
  U8 _pad0[2]; // C aligns ChildTaskID to 4
  U32 ChildTaskID; // CFE_ES_TaskId_t
  U8 _pad1[4];     // C aligns MaxBytesPerCycle to 8
  I64 MaxBytesPerCycle;
  U32 RunStatus;
  U8 _pad2[4]; // C aligns the three recompute pointers to 8
  CS_Res_EepromMemory_Table_Entry_t *RecomputeEepromMemoryEntryPtr;
  CS_Res_App_Table_Entry_t *RecomputeAppEntryPtr;
  CS_Res_Tables_Table_Entry_t *RecomputeTablesEntryPtr;
  U32 CmdPipe; // CFE_SB_PipeId_t
  U8 _pad3[4]; // C aligns Tbl to 8
  CS_TableWrapper_t Tbl[CS_NUM_TABLES];
  CS_Res_EepromMemory_Table_Entry_t OSCodeSeg;
  CS_Res_EepromMemory_Table_Entry_t CfeCoreCodeSeg;
  CS_Def_EepromMemory_Table_Entry_t DefaultEepromDefTable[CS_MAX_NUM_EEPROM_TABLE_ENTRIES];
  CS_Def_EepromMemory_Table_Entry_t DefaultMemoryDefTable[CS_MAX_NUM_MEMORY_TABLE_ENTRIES];
  CS_Def_Tables_Table_Entry_t DefaultTablesDefTable[CS_MAX_NUM_TABLES_TABLE_ENTRIES];
  CS_Def_App_Table_Entry_t DefaultAppDefTable[CS_MAX_NUM_APP_TABLE_ENTRIES];
  // Present because CS_PRESERVE_STATES_ON_PROCESSOR_RESET is true in NASA's default
  // configuration. If it were false this member and the two CDS functions would be excluded --
  // and this compiler could not tell, because `#if <expr>` is unconditionally true here (limit
  // #19). The configuration agreeing with the default is what makes that moot.
  U32 DataStoreHandle; // CFE_ES_CDSHandle_t
  U8 _pad4[4];         // C rounds the object to 8
};

/*******************************************************************************/
// The global. NASA: `CS_AppData_t CS_AppData;` at the top of cs_app.c.
CS_AppData_t CS_AppData;

/*******************************************************************************/
// cs_app.h's eighteen inline accessors, in NASA's order.
//
// CS_ChecksumType_Enum_t IS SPELLED U32 HERE, with the NASA type named in a trailing comment --
// the same convention mm_utils.HC uses for MM_MemType_Enum_t, and check_signatures carries the
// rule that makes NASA's spelling and this one compare equal. Every one is a one-liner over
// CS_AppData.Tbl, and together they are the reason no CS source outside cs_init.c and
// cs_table_processing.c touches a wrapper member by name.

// WHICH TYPE IS THIS WRAPPER. NASA recovers the index by subtracting the array base, which in C
// divides the byte difference by sizeof(CS_TableWrapper_t). HolyC scales a pointer difference
// the same way when both sides have the same pointee, and e_tblwrapper_id.hc in
// tests/exec/cases asserts it -- because getting this wrong would not crash, it would silently
// return a table id six times too large and every event would name the wrong type.
U32 CS_GetTableId(CS_TableWrapper_t *tw) // CS_ChecksumType_Enum_t
{
  return tw - CS_AppData.Tbl;
}

Bool CS_CheckTableId(CS_TableWrapper_t *tw, U32 TableId)
{
  return tw == &CS_AppData.Tbl[TableId];
}

I16 CS_GetDefHandle(U32 TableId) // CFE_TBL_Handle_t
{
  return CS_AppData.Tbl[TableId].DefHandle;
}

I16 CS_GetResHandle(U32 TableId) // CFE_TBL_Handle_t
{
  return CS_AppData.Tbl[TableId].ResHandle;
}

U8 *CS_GetDefName(U32 TableId)
{
  return CS_AppData.Tbl[TableId].DefTableName;
}

U8 *CS_GetResName(U32 TableId)
{
  return CS_AppData.Tbl[TableId].ResTableName;
}

U8 *CS_GetDefAddr(U32 TableId)
{
  return CS_AppData.Tbl[TableId].DefAddr;
}

U8 *CS_GetResAddr(U32 TableId)
{
  return CS_AppData.Tbl[TableId].ResAddr;
}

CS_Res_EepromMemory_Table_Entry_t *CS_GetOSCodeSegResTable()
{
  return CS_GetResAddr(CS_ChecksumType_OSCORE);
}

CS_Res_EepromMemory_Table_Entry_t *CS_GetCfeCoreCodeSegResTable()
{
  return CS_GetResAddr(CS_ChecksumType_CFECORE);
}

CS_Def_EepromMemory_Table_Entry_t *CS_GetEepromDefTable()
{
  return CS_GetDefAddr(CS_ChecksumType_EEPROM_TABLE);
}

CS_Res_EepromMemory_Table_Entry_t *CS_GetEepromResTable()
{
  return CS_GetResAddr(CS_ChecksumType_EEPROM_TABLE);
}

CS_Def_EepromMemory_Table_Entry_t *CS_GetMemoryDefTable()
{
  return CS_GetDefAddr(CS_ChecksumType_MEMORY_TABLE);
}

CS_Res_EepromMemory_Table_Entry_t *CS_GetMemoryResTable()
{
  return CS_GetResAddr(CS_ChecksumType_MEMORY_TABLE);
}

CS_Def_Tables_Table_Entry_t *CS_GetTablesDefTable()
{
  return CS_GetDefAddr(CS_ChecksumType_TABLES_TABLE);
}

CS_Res_Tables_Table_Entry_t *CS_GetTablesResTable()
{
  return CS_GetResAddr(CS_ChecksumType_TABLES_TABLE);
}

CS_Def_App_Table_Entry_t *CS_GetAppDefTable()
{
  return CS_GetDefAddr(CS_ChecksumType_APP_TABLE);
}

CS_Res_App_Table_Entry_t *CS_GetAppResTable()
{
  return CS_GetResAddr(CS_ChecksumType_APP_TABLE);
}
#endif
