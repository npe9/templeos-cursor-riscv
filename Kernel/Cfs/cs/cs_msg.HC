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
// CHECKSUM'S VOCABULARY -- the translation of NASA's CS config headers: cs_interface_cfg.h and
// cs_internal_cfg.h (both through their *_CFGVAL indirection), default_cs_tbl.h,
// default_cs_extern_typedefs.h, default_cs_tbldefs.h, default_cs_msgids.h,
// default_cs_fcncode_values.h, default_cs_msgdefs.h and default_cs_msgstruct.h.
//
// WHAT CHECKSUM DOES, AND WHY IT IS THE THIRD APP. MD reads memory and reports it; MM writes
// it. CS watches it: it CRCs six kinds of thing on a budget of bytes per cycle, remembers the
// first answer as a baseline, and sends an event the moment a later pass disagrees. The six are
// the cFE core's text segment, the OS kernel's text segment, a table of EEPROM regions, a table
// of RAM regions, every registered cFE table, and every running application's code. That list
// is CS_ChecksumType_Enum_t and it is the organising idea of the whole app -- almost every
// command, every table and every housekeeping field comes in six.
//
// SO CS IS THE FIRST APP THAT READS MEMORY DIRECTLY. MD and MM both went through the PSP:
// CFE_PSP_MemRead8, CFE_PSP_MemWrite32 and their siblings, which the driver simulates. CS calls
// CFE_ES_CalculateCRC(addr, size, ...) with a raw pointer, so the BYTES AT THAT ADDRESS have to
// be identical in the native oracle and in the RISC-V guest or the checksum differs and nothing
// says why. Every address CS is given in the exercises therefore points into a driver-owned
// buffer whose contents both halves fill the same way -- including the two text segments, which
// the simulated CFE_PSP_GetCFETextSegmentInfo and CFE_PSP_GetKernelTextSegmentInfo report as a
// short fixed string rather than real code, for exactly this reason.
//
// THE ADDRESSES THEMSELVES STILL DIFFER between the halves, and that is fine: a CRC over equal
// bytes is equal wherever the bytes live. What is NOT fine is printing one, so the exercises
// print a COMPARISON against the pointer the driver handed over rather than the pointer.
#ifndef CS_MSG_HC
#define CS_MSG_HC

/*******************************************************************************/
// cs_interface_cfg.h -- the sizes the ground has to agree with, since they bound the def tables
// and therefore the EntryID a command may name.
//
// CS_DEFAULT_ALGORITHM is CFE_MISSION_ES_DEFAULT_CRC, which is CFE_ES_CrcType_16_ARC -- 1. The
// same resolution mm_msg.HC records for MM's three CRC-type settings.
#define CS_DEFAULT_ALGORITHM 1

#define CS_MAX_NUM_EEPROM_TABLE_ENTRIES 16
#define CS_MAX_NUM_MEMORY_TABLE_ENTRIES 16
#define CS_MAX_NUM_TABLES_TABLE_ENTRIES 24
#define CS_MAX_NUM_APP_TABLE_ENTRIES    24

/*******************************************************************************/
// cs_internal_cfg.h -- the private side.
//
// CS_PIPE_DEPTH is not a literal in NASA's header: it is 3 * CFE_PLATFORM_SB_DEFAULT_MSG_LIMIT,
// and that limit is 4. Written out with the expansion stated, because check_constants compares
// this value against NASA's own preprocessor.
#define CS_PIPE_DEPTH 12

#define CS_DEF_EEPROM_TABLE_FILENAME "/cf/cs_eepromtbl.tbl"
#define CS_DEF_MEMORY_TABLE_FILENAME "/cf/cs_memorytbl.tbl"
#define CS_DEF_TABLES_TABLE_FILENAME "/cf/cs_tablestbl.tbl"
#define CS_DEF_APP_TABLE_FILENAME    "/cf/cs_apptbl.tbl"

// THE BUDGET. 16 KiB per wakeup is what keeps CS from starving the rest of the system: a full
// pass over everything CS watches can be megabytes, and it is spread over as many cycles as
// that takes. CS_ComputeEepromMemory and its siblings stop at this many bytes and store a
// ByteOffset and a partial checksum to resume from, which is why every results entry carries
// ByteOffset and TempChecksumValue.
#define CS_DEFAULT_BYTES_PER_CYCLE 16384

#define CS_CHILD_TASK_PRIORITY 200
#define CS_CHILD_TASK_DELAY    1000
#define CS_STARTUP_TIMEOUT     60000

// The six poweron states, all ENABLED (CS_ChecksumState_ENABLED, 1) in NASA's default
// configuration -- so no #if in CS excludes a function and check_coverage sees all of them.
#define CS_OSCS_CHECKSUM_STATE      1
#define CS_CFECORE_CHECKSUM_STATE   1
#define CS_EEPROM_TBL_POWERON_STATE 1
#define CS_MEMORY_TBL_POWERON_STATE 1
#define CS_APPS_TBL_POWERON_STATE   1
#define CS_TABLES_TBL_POWERON_STATE 1

// CS_PRESERVE_STATES_ON_PROCESSOR_RESET is `true` in NASA's default configuration, so the CDS
// path IS compiled -- CS_AppData gains DataStoreHandle and CS_CreateRestoreStatesFromCDS and
// CS_UpdateCDS are real functions rather than excluded ones. This is the one place in CS where
// the limit recorded as #19 in docs/HOLYC_STRUCT_LIMITS.md would have mattered if the value
// were false, because `#if <expr>` in this compiler is unconditionally true.
#define CS_PRESERVE_STATES_ON_PROCESSOR_RESET 1
#define CS_CDS_NAME                           "CS_CDS"
#define CS_MISSION_REV                        0xFF

/*******************************************************************************/
// default_cs_tbl.h -- the eight cFE table names. Four definition tables the ground may replace
// and four results tables CS owns and dumps.
#define CS_DEF_EEPROM_TABLE_NAME "DefEepromTbl"
#define CS_DEF_MEMORY_TABLE_NAME "DefMemoryTbl"
#define CS_DEF_TABLES_TABLE_NAME "DefTablesTbl"
#define CS_DEF_APP_TABLE_NAME    "DefAppTbl"

#define CS_RESULTS_EEPROM_TABLE_NAME "ResEepromTbl"
#define CS_RESULTS_MEMORY_TABLE_NAME "ResMemoryTbl"
#define CS_RESULTS_TABLES_TABLE_NAME "ResTablesTbl"
#define CS_RESULTS_APP_TABLE_NAME    "ResAppTbl"

/*******************************************************************************/
// default_cs_extern_typedefs.h.
//
// CS_ChecksumType_Enum_t IS A NAMED `typedef enum`, so it is four bytes wide as a member and as
// a parameter -- the same distinction mm_msg.HC records between MM_MemType_Enum_t and
// MM_LastAction_Enum_t. It is also used as an ARRAY INDEX into CS_AppData.Tbl, and NASA's
// CS_GetTableId recovers it by SUBTRACTING pointers, so the six values must stay 0..5 and in
// this order.
#define CS_ChecksumType_CFECORE      0
#define CS_ChecksumType_OSCORE       1
#define CS_ChecksumType_EEPROM_TABLE 2
#define CS_ChecksumType_MEMORY_TABLE 3
#define CS_ChecksumType_TABLES_TABLE 4
#define CS_ChecksumType_APP_TABLE    5

// NASA's own short aliases, defined in the same header. Both spellings appear in CS's sources.
#define CS_CFECORE      CS_ChecksumType_CFECORE
#define CS_OSCORE       CS_ChecksumType_OSCORE
#define CS_EEPROM_TABLE CS_ChecksumType_EEPROM_TABLE
#define CS_MEMORY_TABLE CS_ChecksumType_MEMORY_TABLE
#define CS_TABLES_TABLE CS_ChecksumType_TABLES_TABLE
#define CS_APP_TABLE    CS_ChecksumType_APP_TABLE

#define CS_NUM_TABLES 6

// The per-entry state. EMPTY and UNDEFINED are not the same thing and the difference is the
// reason CS has so many events: EMPTY means the ground never asked for this slot, UNDEFINED
// means the ground asked and CS could not find what was named -- a table that is not registered
// or an app that is not running.
#define CS_ChecksumState_EMPTY     0x00
#define CS_ChecksumState_ENABLED   0x01
#define CS_ChecksumState_DISABLED  0x02
#define CS_ChecksumState_UNDEFINED 0x03

#define CS_STATE_EMPTY     CS_ChecksumState_EMPTY
#define CS_STATE_ENABLED   CS_ChecksumState_ENABLED
#define CS_STATE_DISABLED  CS_ChecksumState_DISABLED
#define CS_STATE_UNDEFINED CS_ChecksumState_UNDEFINED

/*******************************************************************************/
// default_cs_tbldefs.h -- the six table entry types, three definition and three results.
//
// A DEFINITION ENTRY SAYS WHAT TO WATCH; A RESULTS ENTRY SAYS WHAT WAS SEEN. They are separate
// cFE tables because the definition table is ground-replaceable and the results table is CS's
// own working state -- and because the results table is what a dump has to contain for the
// ground to see a baseline.
//
// EEPROM AND MEMORY SHARE BOTH TYPES. There is no CS_Def_Memory_Table_Entry_t: the memory table
// uses CS_Def_EepromMemory_Table_Entry_t, and cs_init.c's initialiser list says so twice. The
// two tables differ only in which CFE_PSP_MemValidateRange type they are checked against.

class CS_Def_EepromMemory_Table_Entry_t
{
  U64 StartAddress; // CFE_ES_MemAddress_t
  U16 State;
  U16 Filler16; // NASA's own name, and NASA's own gap
  U32 NumBytesToChecksum;
};

class CS_Res_EepromMemory_Table_Entry_t
{
  U64 StartAddress; // CFE_ES_MemAddress_t
  U16 State;
  U16 ComputedYet;
  U32 NumBytesToChecksum;
  U32 ComparisonValue;   // the baseline
  U32 ByteOffset;        // where the last cycle ran out of budget
  U32 TempChecksumValue; // the partial CRC to resume from
  U32 Filler32;          // NASA's own name
};

// THE FIRST ODD-SIZED CLASS IN THIS PORT: 42 bytes, two-byte alignment, no padding anywhere.
// A U16 followed by a 40-char name packs exactly, and CS declares an array of 24 of them inside
// CS_AppData -- so the array stride is 42, not 48. check_padding measures it; the reason it is
// worth a line is that a port that quietly rounded the entry to 48 would place
// DefaultAppDefTable 144 bytes further on and the CDS image would stop matching NASA's.
class CS_Def_Tables_Table_Entry_t
{
  U16 State;
  U8 Name[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
};

// 22 bytes, same reason.
class CS_Def_App_Table_Entry_t
{
  U16 State;
  U8 Name[CFE_MISSION_MAX_API_LEN];
};

class CS_Res_Tables_Table_Entry_t
{
  U64 StartAddress; // CFE_ES_MemAddress_t
  U16 State;
  U16 ComputedYet;
  U32 NumBytesToChecksum;
  U32 ComparisonValue;
  U32 ByteOffset;
  U32 TempChecksumValue;
  U32 TblHandleID; // CFE_TBL_HandleId_t
  U8 IsCSOwner;    // bool -- did CS create this table, or is it watching someone else's
  U8 Filler8;      // NASA's own name
  U8 Name[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
  U8 _pad0[6]; // C aligns the whole entry to 8, for StartAddress
};

class CS_Res_App_Table_Entry_t
{
  U64 StartAddress; // CFE_ES_MemAddress_t
  U16 State;
  U16 ComputedYet;
  U32 NumBytesToChecksum;
  U32 ComparisonValue;
  U32 ByteOffset;
  U32 TempChecksumValue;
  U8 Name[CFE_MISSION_MAX_API_LEN];
};

/*******************************************************************************/
// default_cs_msgids.h. Each resolves through CFE_PLATFORM_CMD_TOPICID_TO_MIDV or its telemetry
// twin and a CS topic id (0x9F command, 0xA0 send-hk, 0xA1 background cycle, 0xA4 telemetry),
// so the values are written out and check_constants compares them against NASA's own expansion.
//
// CS IS THE FIRST APP WITH THREE COMMAND PIPES' WORTH OF SUBSCRIPTIONS rather than two: the
// background cycle is a separate MID from housekeeping, because the scheduler drives checksum
// work at a different rate from telemetry.
#define CS_CMD_MID              0x189F
#define CS_SEND_HK_MID          0x18A0
#define CS_BACKGROUND_CYCLE_MID 0x18A1
#define CS_HK_TLM_MID           0x8A4

/*******************************************************************************/
// default_cs_fcncode_values.h -- 40 command codes, which is more than MD's 7 and MM's 10 put
// together. The pattern is the six checksum types crossed with enable, disable, report-baseline
// and recompute-baseline, plus the per-entry and per-name variants, plus one-shot.
#define CS_FunctionCode_NOOP                            0
#define CS_FunctionCode_RESET_COUNTERS                  1
#define CS_FunctionCode_ONE_SHOT                        2
#define CS_FunctionCode_CANCEL_ONE_SHOT                 3
#define CS_FunctionCode_ENABLE_ALL_CS                   4
#define CS_FunctionCode_DISABLE_ALL_CS                  5
#define CS_FunctionCode_ENABLE_CFE_CORE                 6
#define CS_FunctionCode_DISABLE_CFE_CORE                7
#define CS_FunctionCode_REPORT_BASELINE_CFE_CORE        8
#define CS_FunctionCode_RECOMPUTE_BASELINE_CFE_CORE     9
#define CS_FunctionCode_ENABLE_OS                       10
#define CS_FunctionCode_DISABLE_OS                      11
#define CS_FunctionCode_REPORT_BASELINE_OS              12
#define CS_FunctionCode_RECOMPUTE_BASELINE_OS           13
#define CS_FunctionCode_ENABLE_EEPROM                   14
#define CS_FunctionCode_DISABLE_EEPROM                  15
#define CS_FunctionCode_REPORT_BASELINE_ENTRY_ID_EEPROM 16
#define CS_FunctionCode_RECOMPUTE_BASELINE_EEPROM       17
#define CS_FunctionCode_ENABLE_ENTRY_ID_EEPROM          18
#define CS_FunctionCode_DISABLE_ENTRY_ID_EEPROM         19
#define CS_FunctionCode_GET_ENTRY_ID_EEPROM             20
#define CS_FunctionCode_ENABLE_MEMORY                   21
#define CS_FunctionCode_DISABLE_MEMORY                  22
#define CS_FunctionCode_REPORT_BASELINE_ENTRY_ID_MEMORY 23
#define CS_FunctionCode_RECOMPUTE_BASELINE_MEMORY       24
#define CS_FunctionCode_ENABLE_ENTRY_ID_MEMORY          25
#define CS_FunctionCode_DISABLE_ENTRY_ID_MEMORY         26
#define CS_FunctionCode_GET_ENTRY_ID_MEMORY             27
#define CS_FunctionCode_ENABLE_TABLES                   28
#define CS_FunctionCode_DISABLE_TABLES                  29
#define CS_FunctionCode_REPORT_BASELINE_TABLE           30
#define CS_FunctionCode_RECOMPUTE_BASELINE_TABLE        31
#define CS_FunctionCode_ENABLE_NAME_TABLE               32
#define CS_FunctionCode_DISABLE_NAME_TABLE              33
#define CS_FunctionCode_ENABLE_APPS                     34
#define CS_FunctionCode_DISABLE_APPS                    35
#define CS_FunctionCode_REPORT_BASELINE_APP             36
#define CS_FunctionCode_RECOMPUTE_BASELINE_APP          37
#define CS_FunctionCode_ENABLE_NAME_APP                 38
#define CS_FunctionCode_DISABLE_NAME_APP                39

// NASA's own aliases for six of them, in the same header -- both spellings appear in CS's
// sources and in its dispatch table.
#define CS_NOOP_CC                            CS_FunctionCode_NOOP
#define CS_RESET_COUNTERS_CC                  CS_FunctionCode_RESET_COUNTERS
#define CS_ONE_SHOT_CC                        CS_FunctionCode_ONE_SHOT
#define CS_CANCEL_ONE_SHOT_CC                 CS_FunctionCode_CANCEL_ONE_SHOT
#define CS_ENABLE_ALL_CS_CC                   CS_FunctionCode_ENABLE_ALL_CS
#define CS_DISABLE_ALL_CS_CC                  CS_FunctionCode_DISABLE_ALL_CS
#define CS_ENABLE_CFE_CORE_CC                 CS_FunctionCode_ENABLE_CFE_CORE
#define CS_DISABLE_CFE_CORE_CC                CS_FunctionCode_DISABLE_CFE_CORE
#define CS_REPORT_BASELINE_CFE_CORE_CC        CS_FunctionCode_REPORT_BASELINE_CFE_CORE
#define CS_RECOMPUTE_BASELINE_CFE_CORE_CC     CS_FunctionCode_RECOMPUTE_BASELINE_CFE_CORE
#define CS_ENABLE_OS_CC                       CS_FunctionCode_ENABLE_OS
#define CS_DISABLE_OS_CC                      CS_FunctionCode_DISABLE_OS
#define CS_REPORT_BASELINE_OS_CC              CS_FunctionCode_REPORT_BASELINE_OS
#define CS_RECOMPUTE_BASELINE_OS_CC           CS_FunctionCode_RECOMPUTE_BASELINE_OS
#define CS_ENABLE_EEPROM_CC                   CS_FunctionCode_ENABLE_EEPROM
#define CS_DISABLE_EEPROM_CC                  CS_FunctionCode_DISABLE_EEPROM
#define CS_REPORT_BASELINE_ENTRY_ID_EEPROM_CC CS_FunctionCode_REPORT_BASELINE_ENTRY_ID_EEPROM
#define CS_RECOMPUTE_BASELINE_EEPROM_CC       CS_FunctionCode_RECOMPUTE_BASELINE_EEPROM
#define CS_ENABLE_ENTRY_ID_EEPROM_CC          CS_FunctionCode_ENABLE_ENTRY_ID_EEPROM
#define CS_DISABLE_ENTRY_ID_EEPROM_CC         CS_FunctionCode_DISABLE_ENTRY_ID_EEPROM
#define CS_GET_ENTRY_ID_EEPROM_CC             CS_FunctionCode_GET_ENTRY_ID_EEPROM
#define CS_ENABLE_MEMORY_CC                   CS_FunctionCode_ENABLE_MEMORY
#define CS_DISABLE_MEMORY_CC                  CS_FunctionCode_DISABLE_MEMORY
#define CS_REPORT_BASELINE_ENTRY_ID_MEMORY_CC CS_FunctionCode_REPORT_BASELINE_ENTRY_ID_MEMORY
#define CS_RECOMPUTE_BASELINE_MEMORY_CC       CS_FunctionCode_RECOMPUTE_BASELINE_MEMORY
#define CS_ENABLE_ENTRY_ID_MEMORY_CC          CS_FunctionCode_ENABLE_ENTRY_ID_MEMORY
#define CS_DISABLE_ENTRY_ID_MEMORY_CC         CS_FunctionCode_DISABLE_ENTRY_ID_MEMORY
#define CS_GET_ENTRY_ID_MEMORY_CC             CS_FunctionCode_GET_ENTRY_ID_MEMORY
#define CS_ENABLE_TABLES_CC                   CS_FunctionCode_ENABLE_TABLES
#define CS_DISABLE_TABLES_CC                  CS_FunctionCode_DISABLE_TABLES
#define CS_REPORT_BASELINE_TABLE_CC           CS_FunctionCode_REPORT_BASELINE_TABLE
#define CS_RECOMPUTE_BASELINE_TABLE_CC        CS_FunctionCode_RECOMPUTE_BASELINE_TABLE
#define CS_ENABLE_NAME_TABLE_CC               CS_FunctionCode_ENABLE_NAME_TABLE
#define CS_DISABLE_NAME_TABLE_CC              CS_FunctionCode_DISABLE_NAME_TABLE
#define CS_ENABLE_APPS_CC                     CS_FunctionCode_ENABLE_APPS
#define CS_DISABLE_APPS_CC                    CS_FunctionCode_DISABLE_APPS
#define CS_REPORT_BASELINE_APP_CC             CS_FunctionCode_REPORT_BASELINE_APP
#define CS_RECOMPUTE_BASELINE_APP_CC          CS_FunctionCode_RECOMPUTE_BASELINE_APP
#define CS_ENABLE_NAME_APP_CC                 CS_FunctionCode_ENABLE_NAME_APP
#define CS_DISABLE_NAME_APP_CC                CS_FunctionCode_DISABLE_NAME_APP

#define CS_ONESHOT_CC                    CS_ONE_SHOT_CC
#define CS_CANCEL_ONESHOT_CC             CS_CANCEL_ONE_SHOT_CC
#define CS_ENABLE_CFECORE_CC             CS_ENABLE_CFE_CORE_CC
#define CS_DISABLE_CFECORE_CC            CS_DISABLE_CFE_CORE_CC
#define CS_REPORT_BASELINE_CFECORE_CC    CS_REPORT_BASELINE_CFE_CORE_CC
#define CS_RECOMPUTE_BASELINE_CFECORE_CC CS_RECOMPUTE_BASELINE_CFE_CORE_CC

/*******************************************************************************/
// default_cs_msgdefs.h -- the payloads.
//
// HOUSEKEEPING IS THE WHOLE INTERFACE. 64 bytes, and nearly every field is one of six: six
// state bytes, six error counters, three baselines. The two counters that are NOT in sixes are
// the interesting ones -- CurrentCSTable and CurrentEntryInTable say where the background walk
// has got to, which is how the ground knows a pass is progressing rather than stuck.
class CS_HkPacket_Payload_t
{
  U8 CommandCounter;
  U8 CommandErrorCounter;
  U8 ChecksumState;
  U8 EepromCSState;
  U8 MemoryCSState;
  U8 AppCSState;
  U8 TablesCSState;
  U8 OSCSState;
  U8 CfeCoreCSState;
  U8 RecomputeInProgress;
  U8 OneShotInProgress;
  U8 Filler8; // NASA's own name
  U16 EepromCSErrCounter;
  U16 MemoryCSErrCounter;
  U16 AppCSErrCounter;
  U16 TablesCSErrCounter;
  U16 CfeCoreCSErrCounter;
  U16 OSCSErrCounter;
  U16 CurrentCSTable;
  U16 CurrentEntryInTable;
  U32 EepromBaseline;
  U32 OSBaseline;
  U32 CfeCoreBaseline;
  U64 LastOneShotAddress; // CFE_ES_MemAddress_t
  U32 LastOneShotSize;
  U32 LastOneShotMaxBytesPerCycle;
  U32 LastOneShotChecksum;
  U32 PassCounter;
};

// An address, as the ground spells it for CS: no symbol name and no offset, unlike MD's and
// MM's MM_SymAddr_t. CS never resolves a symbol -- the ground is asking "which entry of my
// definition table covers this address", so a bare address is the whole question.
class CS_GetEntryIDCmd_Payload_t
{
  U64 Address; // CFE_ES_MemAddress_t
};

class CS_EntryCmd_Payload_t
{
  U32 EntryID;
};

class CS_TableNameCmd_Payload_t
{
  U8 Name[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
};

class CS_AppNameCmd_Payload_t
{
  U8 Name[CFE_MISSION_MAX_API_LEN];
};

// ONE SHOT: checksum this one region now, outside the six tables, in a child task, and report
// the answer. MaxBytesPerCycle of zero means "use CS_DEFAULT_BYTES_PER_CYCLE".
class CS_OneShotCmd_Payload_t
{
  U64 Address; // CFE_ES_MemAddress_t
  U32 Size;
  U32 MaxBytesPerCycle;
};

/*******************************************************************************/
// default_cs_msgstruct.h -- the wire messages. 41 of them, and 22 are a bare command header
// with no payload at all, which is what "enable the memory table" looks like on the wire.

class CS_HkPacket_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CS_HkPacket_Payload_t Payload;
};

class CS_SendHkCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_BackgroundCheckCycleCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_DisableAllCSCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_EnableAllCSCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_DisableCfeCoreCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_EnableCfeCoreCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_DisableOSCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_EnableOSCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_ReportBaselineCfeCoreCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_ReportBaselineOSCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_RecomputeBaselineCfeCoreCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_RecomputeBaselineOSCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_CancelOneShotCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_DisableAppsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_EnableAppsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_DisableEepromCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_EnableEepromCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_DisableMemoryCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_EnableMemoryCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_DisableTablesCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_EnableTablesCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CS_GetEntryIDEepromCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_GetEntryIDCmd_Payload_t Payload;
};

class CS_GetEntryIDMemoryCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_GetEntryIDCmd_Payload_t Payload;
};

class CS_ReportBaselineEntryIDEepromCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_EntryCmd_Payload_t Payload;
};

class CS_DisableEntryIDEepromCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_EntryCmd_Payload_t Payload;
};

class CS_RecomputeBaselineEepromCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_EntryCmd_Payload_t Payload;
};

class CS_EnableEntryIDEepromCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_EntryCmd_Payload_t Payload;
};

class CS_ReportBaselineEntryIDMemoryCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_EntryCmd_Payload_t Payload;
};

class CS_DisableEntryIDMemoryCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_EntryCmd_Payload_t Payload;
};

class CS_RecomputeBaselineMemoryCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_EntryCmd_Payload_t Payload;
};

class CS_EnableEntryIDMemoryCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_EntryCmd_Payload_t Payload;
};

class CS_ReportBaselineTableCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_TableNameCmd_Payload_t Payload;
};

class CS_RecomputeBaselineTableCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_TableNameCmd_Payload_t Payload;
};

class CS_DisableNameTableCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_TableNameCmd_Payload_t Payload;
};

class CS_EnableNameTableCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_TableNameCmd_Payload_t Payload;
};

class CS_ReportBaselineAppCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_AppNameCmd_Payload_t Payload;
};

class CS_RecomputeBaselineAppCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_AppNameCmd_Payload_t Payload;
};

class CS_DisableNameAppCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_AppNameCmd_Payload_t Payload;
};

class CS_EnableNameAppCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_AppNameCmd_Payload_t Payload;
};

class CS_OneShotCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CS_OneShotCmd_Payload_t Payload;
};
#endif
