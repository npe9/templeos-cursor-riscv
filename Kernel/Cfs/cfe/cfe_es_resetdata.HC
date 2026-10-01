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
// The CFE RESET AREA's types, from cFE modules/core_private/fsw/inc/ -- cfe_es_resetdata_typedef.h
// and the three headers it includes, plus cfe_time_resetvars_typedef.h.
//
// THEY ARE TYPES, NOT CODE. No ES function is translated here. They exist because TWO modules
// read the reset area and neither owns it: CFE_EVS_EarlyInit sizes the WHOLE of
// CFE_ES_ResetData_t before it will take the event log out of it, and CFE_TIME_QueryResetVars
// reads CFE_TIME_ResetVars_t out of the same block to recover the clock across a processor
// reset. They were in cfe_evs_task.HC while EVS was the only reader; TIME is the second, and two
// files declaring the same class is not something HolyC can guard per-class.
//
// check_padding.py measures every offset and every size here against NASA's own compiler, which
// is what makes the explicit alignment members below checkable rather than guesswork -- a wrong
// one is a wrong sizeof, and EVS COMPARES that sizeof against what the PSP reports.
#ifndef CFE_ES_RESETDATA_HC
#define CFE_ES_RESETDATA_HC
#include "cfe_msg_sechdr_time.HC" // CFE_TIME_SysTime, which three of these carry
// The reset area ENDS with the EVS log, which is why NASA's cfe_es_resetdata_typedef.h
// includes cfe_evs_log_typedef.h. In this port CFE_EVS_Log_t lives in cfe_evs_global.HC with
// the rest of EVS's types, so that is what is included; it is guarded, and the dependency is
// NASA's, not this file's invention.
#include "cfe_evs_global.HC"
// --- cfe_es_internal_cfg.h / cfe_mission_cfg.h: the reset area's dimensions -------------------
// Every one of these is a bound inside the structure below, so they belong with it. The
// 10,000-entry performance buffer is what makes CFE_ES_ResetData_t 134,536 bytes -- a number EVS
// compares against what the PSP reports before it will use the area at all.
#define CFE_PLATFORM_ES_PERF_DATA_BUFFER_SIZE   10000
#define CFE_MISSION_ES_PERF_MAX_IDS             128
#define CFE_ES_PERF_8BIT_WORDS_IN_MASK          16
#define CFE_PLATFORM_ES_ER_LOG_ENTRIES          20
#define CFE_PLATFORM_ES_SYSTEM_LOG_SIZE         8192
#define CFE_ES_ERLOG_DESCRIPTION_MAX_LENGTH     80
#define CFE_PLATFORM_ES_ER_LOG_MAX_CONTEXT_SIZE 256
// --- cfe_es_perfdata_typedef.h ----------------------------------------------------------------
class CFE_ES_PerfDataEntry_t
{
  U32 Data;
  U32 TimerUpper32;
  // TBU - timebase register
  U32 TimerLower32;
  // TBL - timebase register
};

class CFE_ES_PerfMetaData_t
{
  U8 Version;
  U8 Endian;
  U8 Spare[2];
  U32 TimerTicksPerSecond;
  U32 TimerLow32Rollover;
  U32 State;
  // `volatile` in the C; HolyC has no volatile and nothing here caches it
  U32 Mode;
  U32 TriggerCount;
  U32 DataStart;
  U32 DataEnd;
  U32 DataCount;
  U32 InvalidMarkerReported;
  U32 FilterTriggerMaskSize;
  U8 FilterMask[CFE_ES_PERF_8BIT_WORDS_IN_MASK];
  U8 TriggerMask[CFE_ES_PERF_8BIT_WORDS_IN_MASK];
};

class CFE_ES_PerfData_t
{
  CFE_ES_PerfMetaData_t MetaData;
  CFE_ES_PerfDataEntry_t DataBuffer[CFE_PLATFORM_ES_PERF_DATA_BUFFER_SIZE];
};
// --- cfe_es_erlog_typedef.h -------------------------------------------------------------------
class CFE_ES_DebugVariables_t
{
  U32 DebugFlag;
  U32 WatchdogWriteFlag;
  U32 PrintfEnabledFlag;
  U32 LastAppId;
};

class CFE_ES_ERLog_BaseInfo_t
{
  U32 LogEntryType;
  // What type of log entry
  U32 ResetType;
  // Main cause for the reset
  U32 ResetSubtype;
  // The sub-type for the reset
  U32 BootSource;
  // The boot source
  U32 ProcessorResetCount;
  // The number of processor resets
  U32 MaxProcessorResetCount;
  // The maximum number before a Power On
  CFE_ES_DebugVariables_t DebugVars;
  CFE_TIME_SysTime TimeCode;
  U8 Description[CFE_ES_ERLOG_DESCRIPTION_MAX_LENGTH];
};

class CFE_ES_ERLog_MetaData_t
{
  CFE_ES_ERLog_BaseInfo_t BaseInfo;
  // Core Log Data
  U32 AppID;
  // The application ID
  U32 PspContextId;
  // Reference to context information stored in PSP
};
// --- cfe_time_resetvars_typedef.h -------------------------------------------------------------
class CFE_TIME_ResetVars_t
{
  U32 Signature;
  // Data validation signature used to verify data structure contents
  I16 LeapSeconds;
  // Leap seconds value
  U16 ClockSignal;
  // CFE_TIME_ToneSignalSelect_Enum_t -- a uint16 typedef, not a C enum
  CFE_TIME_SysTime CurrentMET;
  CFE_TIME_SysTime CurrentSTCF;
  CFE_TIME_SysTime CurrentDelay;
};
// --- cfe_es_resetdata_typedef.h ---------------------------------------------------------------
class CFE_ES_ResetVariables_t
{
  U32 ResetType;
  U32 ResetSubtype;
  U32 BootSource;
  U32 ES_CausedReset;
  U32 ProcessorResetCount;
  U32 MaxProcessorResetCount;
};
// The whole reset area. EVS reads one member of it -- EVS_Log -- and the SIZE of the rest, which
// is why all of it is here: EarlyInit refuses to run if CFE_PSP_GetResetArea reports an area
// smaller than this type.
class CFE_ES_ResetData_t
{
  // Exception and Reset Log
  CFE_ES_ERLog_MetaData_t ERLog[CFE_PLATFORM_ES_ER_LOG_ENTRIES];
  U32 ERLogIndex;
  U32 ERLogEntries;
  U32 LastAppId;
  // System Log
  U8 SystemLog[CFE_PLATFORM_ES_SYSTEM_LOG_SIZE];
  U8 _pad0[4];
  // C aligns the two size_t that follow to 8; HolyC classes are packed
  I64 SystemLogWriteIdx;
  // size_t
  I64 SystemLogEndIdx;
  // size_t
  U32 SystemLogMode;
  U32 SystemLogEntryNum;
  // Performance Data
  CFE_ES_PerfData_t Perf;
  // Reset Variables
  CFE_ES_ResetVariables_t ResetVars;
  // Time variables that are preserved on a processor reset
  CFE_TIME_ResetVars_t TimeResetVars;
  // EVS Log and associated variables. This needs to be preserved on a processor reset.
  CFE_EVS_Log_t EVS_Log;
  // TAIL padding. CFE_EVS_Log_t is 4-aligned and the two size_t above make the whole struct
  // 8-aligned, so C rounds 134532 up to 134536. EarlyInit COMPARES this number against what the
  // PSP reports, so the four bytes are not cosmetic: a translation four bytes short would refuse
  // a reset area that NASA's accepts.
  U8 _pad1[4];
};
#endif
