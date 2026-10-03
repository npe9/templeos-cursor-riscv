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
// ES'S GROUND MESSAGE FORMATS -- cFE modules/es/config/default_cfe_es_{msgdefs,msgstruct}.h.
//
// NASA splits these across two generated headers: msgdefs.h has the PAYLOADS and msgstruct.h
// wraps each one in a command or telemetry header. They are one file here because nothing in
// the port needs a payload without its envelope, and because both halves of every pair are
// measured by the same check_padding run.
//
// THESE ARE THE GROUND INTERFACE, which is why they are their own file rather than a block
// inside cfe_es_task.HC: cfe_sb_task.c includes cfe_es_msg.h too, with NASA's own comment
// "needed for local use of CFE_ES_RestartCmd_t", so cfe_sb_task.HC includes this. A second
// copy of CFE_ES_RestartCmd_t used to live there, and THE COMPILER ACCEPTS A DUPLICATE CLASS
// SILENTLY -- two class bodies under one name compile with no diagnostic and the layout rule
// is then in two places free to drift. One definition, measured once.
//
// THE THREE TELEMETRY STRUCTS ARE NOT HERE. CFE_ES_HousekeepingTlm_t, CFE_ES_OneAppTlm_t and
// CFE_ES_MemStatsTlm_t are embedded BY VALUE in CFE_ES_TaskData_t, so cfe_es_global.HC has to
// have them to size its own state and they live there, with their payloads.
#ifndef CFE_ES_MSG_HC
#define CFE_ES_MSG_HC
#include "cfe_es_global.HC" // the three telemetry structs and their payloads, and the enums
// --- default_cfe_es_msgdefs.h: the command PAYLOADS -------------------------------------------
class CFE_ES_RestartCmd_Payload_t
{
  U16 RestartType;
  // CFE_PSP_RST_TYPE_PROCESSOR or CFE_PSP_RST_TYPE_POWERON
};

class CFE_ES_FileNameCmd_Payload_t
{
  U8 FileName[CFE_MISSION_MAX_PATH_LEN];
};

class CFE_ES_OverWriteSysLogCmd_Payload_t
{
  U32 Mode;
  // CFE_ES_LogMode_DISCARD or CFE_ES_LogMode_OVERWRITE
};
// NASA'S OWN PADDING, NAMED AS NASA NAMES IT. Padding1 and Padding2 are fields of the ground
// message format, not gaps this port's compiler left, so they keep their names rather than
// becoming _pad0 -- a reader has to be able to tell the two apart. Same rule as
// CFE_ES_AppInfo_t's three.
class CFE_ES_StartAppCmd_Payload_t
{
  U8 Application[CFE_MISSION_MAX_API_LEN];
  U8 AppEntryPoint[CFE_MISSION_MAX_API_LEN];
  U8 AppFileName[CFE_MISSION_MAX_PATH_LEN];
  I64 StackSize;
  // CFE_ES_MemOffset_t
  U8 ExceptionAction;
  // CFE_ES_ExceptionAction_Enum_t -- ONE byte
  U8 Padding1;
  U16 Priority;
  // CFE_ES_TaskPriority_Atom_t -- SIXTEEN bits
  U8 Padding2[4];
};

class CFE_ES_AppNameCmd_Payload_t
{
  U8 Application[CFE_MISSION_MAX_API_LEN];
};

class CFE_ES_AppReloadCmd_Payload_t
{
  U8 Application[CFE_MISSION_MAX_API_LEN];
  U8 AppFileName[CFE_MISSION_MAX_PATH_LEN];
};

class CFE_ES_SetMaxPRCountCmd_Payload_t
{
  U16 MaxPRCount;
};

class CFE_ES_DeleteCDSCmd_Payload_t
{
  U8 CdsName[CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN];
};

class CFE_ES_StartPerfCmd_Payload_t
{
  U32 TriggerMode;
  // CFE_ES_PerfMode_Enum_t
};

class CFE_ES_StopPerfCmd_Payload_t
{
  U8 DataFileName[CFE_MISSION_MAX_PATH_LEN];
};

class CFE_ES_SetPerfFilterMaskCmd_Payload_t
{
  U8 FilterMaskNum;
  U8 FilterMask;
};

class CFE_ES_SetPerfTrigMaskCmd_Payload_t
{
  U8 TriggerMaskNum;
  U8 TriggerMask;
};

class CFE_ES_SendMemPoolStatsCmd_Payload_t
{
  U8 Application[CFE_MISSION_MAX_API_LEN];
  U32 PoolHandle;
  // CFE_ES_MemHandle_t
};

class CFE_ES_DumpCDSRegistryCmd_Payload_t
{
  U8 DumpFilename[CFE_MISSION_MAX_PATH_LEN];
};
// --- default_cfe_es_msgstruct.h: the command ENVELOPES ----------------------------------------
// THE SIX "NO ARGUMENTS" COMMANDS EACH GET THEIR OWN TYPE, and NASA explains why rather than
// sharing one: "They are each given their own type name matching the command name, which allows
// them to change independently in the future without changing the prototype of the handler
// function." So six identical classes, on purpose.
class CFE_ES_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_ES_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_ES_ClearSysLogCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_ES_ClearERLogCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_ES_ResetPRCountCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_ES_SendHkCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_ES_RestartCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_RestartCmd_Payload_t Payload;
};
// The four that share the FileNameCmd payload, for the same reason as the six above.
class CFE_ES_QueryAllCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_FileNameCmd_Payload_t Payload;
};

class CFE_ES_QueryAllTasksCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_FileNameCmd_Payload_t Payload;
};

class CFE_ES_WriteSysLogCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_FileNameCmd_Payload_t Payload;
};

class CFE_ES_WriteERLogCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_FileNameCmd_Payload_t Payload;
};

class CFE_ES_OverWriteSysLogCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_OverWriteSysLogCmd_Payload_t Payload;
};

class CFE_ES_StartAppCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_StartAppCmd_Payload_t Payload;
};
// The three that share the AppNameCmd payload.
class CFE_ES_StopAppCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_AppNameCmd_Payload_t Payload;
};

class CFE_ES_RestartAppCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_AppNameCmd_Payload_t Payload;
};

class CFE_ES_QueryOneCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_AppNameCmd_Payload_t Payload;
};

class CFE_ES_ReloadAppCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_AppReloadCmd_Payload_t Payload;
};

class CFE_ES_SetMaxPRCountCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_SetMaxPRCountCmd_Payload_t Payload;
};

class CFE_ES_DeleteCDSCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_DeleteCDSCmd_Payload_t Payload;
};

class CFE_ES_StartPerfDataCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_StartPerfCmd_Payload_t Payload;
};

class CFE_ES_StopPerfDataCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_StopPerfCmd_Payload_t Payload;
};

class CFE_ES_SetPerfFilterMaskCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_SetPerfFilterMaskCmd_Payload_t Payload;
};

class CFE_ES_SetPerfTriggerMaskCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_SetPerfTrigMaskCmd_Payload_t Payload;
};

class CFE_ES_SendMemPoolStatsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_SendMemPoolStatsCmd_Payload_t Payload;
};

class CFE_ES_DumpCDSRegistryCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_ES_DumpCDSRegistryCmd_Payload_t Payload;
};
#endif
