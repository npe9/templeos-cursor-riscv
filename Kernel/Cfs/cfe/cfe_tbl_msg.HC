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
// TABLE SERVICES' GROUND INTERFACE -- the translation of NASA's
// modules/tbl/config/default_cfe_tbl_msgdefs.h and default_cfe_tbl_msgstruct.h: eleven commands
// and two telemetry packets, the whole vocabulary an operator has for talking to tbl.
//
// ELEVEN COMMANDS, AND EIGHT OF THEM NAME A TABLE. That is the shape of the service: almost
// everything is "do this to the table called X", where X is a processor-specific full name like
// "CFE_TBL.CritTbl". Load is the exception -- it names a FILE, because the file header carries
// the table name -- and Noop, ResetCounters and SendHk take no payload at all.
//
// TWO OF THEM ARE A PAIR WORTH SEEING: Validate asks the owning app to check a buffer and
// Activate makes that buffer the live one. A load is three separate ground commands -- load,
// validate, activate -- precisely so an operator can look at the validation result before
// committing, and so the app's own validation function gets a say.
//
// THE NOTIFY COMMAND GOES THE OTHER WAY. CFE_TBL_NotifyCmd_t is sent BY Table Services, on an
// owning app's behalf, to whatever message id that app registered -- it is how an app that does
// not poll CFE_TBL_Manage finds out its table needs attention. Its one payload field is the
// opaque parameter the app supplied, which cFE never interprets.
//
// THE TWO PADDING FIELDS IN THE REGISTRY PACKET ARE NASA'S OWN, named Padding1 and Padding2 in
// the source rather than inserted by a compiler. They are translated as the fields they are,
// not as this port's `_pad` members, because a ground system's telemetry database has them.
#ifndef CFE_TBL_MSG_HC
#define CFE_TBL_MSG_HC
#ifndef CFE_MISSION_TBL_MAX_FULL_NAME_LEN
#define CFE_MISSION_TBL_MAX_FULL_NAME_LEN 40
#endif
// --- cfe_tbl_extern_typedefs.h --------------------------------------------------------------
// WHICH BUFFER A COMMAND MEANS, and it is a uint16 rather than a C enum -- which is why
// CFE_TBL_ValidationResult_t's copy of it sits at an odd offset. 0 is the inactive buffer and 1
// the active one, so a Validate with no flag set checks the one a load just went into.
#ifndef CFE_TBL_BufferSelect_INACTIVE
#define CFE_TBL_BufferSelect_INACTIVE 0
#define CFE_TBL_BufferSelect_ACTIVE   1
#endif

/*******************************************************************************/
// The three with no payload.
class CFE_TBL_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TBL_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TBL_SendHkCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

/*******************************************************************************/
// LOAD NAMES A FILE, NOT A TABLE -- the only command that does. The table it applies to comes
// out of the file's own header, which is what lets one file be the authoritative record of what
// was loaded.
class CFE_TBL_LoadCmd_Payload_t
{
  U8 LoadFilename[CFE_MISSION_MAX_PATH_LEN];
};

class CFE_TBL_LoadCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TBL_LoadCmd_Payload_t Payload;
};

/*******************************************************************************/
class CFE_TBL_DumpCmd_Payload_t
{
  U16 ActiveTableFlag; // CFE_TBL_BufferSelect_Enum_t
  U8 TableName[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
  U8 DumpFilename[CFE_MISSION_MAX_PATH_LEN];
};

class CFE_TBL_DumpCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TBL_DumpCmd_Payload_t Payload;
};

/*******************************************************************************/
class CFE_TBL_ValidateCmd_Payload_t
{
  U16 ActiveTableFlag; // CFE_TBL_BufferSelect_Enum_t
  U8 TableName[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
};

class CFE_TBL_ValidateCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TBL_ValidateCmd_Payload_t Payload;
};

/*******************************************************************************/
class CFE_TBL_ActivateCmd_Payload_t
{
  U8 TableName[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
};

class CFE_TBL_ActivateCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TBL_ActivateCmd_Payload_t Payload;
};

/*******************************************************************************/
class CFE_TBL_DumpRegistryCmd_Payload_t
{
  U8 DumpFilename[CFE_MISSION_MAX_PATH_LEN];
};

class CFE_TBL_DumpRegistryCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TBL_DumpRegistryCmd_Payload_t Payload;
};

/*******************************************************************************/
class CFE_TBL_SendRegistryCmd_Payload_t
{
  U8 TableName[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
};

class CFE_TBL_SendRegistryCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TBL_SendRegistryCmd_Payload_t Payload;
};

/*******************************************************************************/
// NASA's payload type is CFE_TBL_DelCDSCmd_Payload_t -- "Del", not "Delete" -- while the command
// wrapper is CFE_TBL_DeleteCDSCmd_t. Both names are kept as they are.
class CFE_TBL_DelCDSCmd_Payload_t
{
  U8 TableName[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
};

class CFE_TBL_DeleteCDSCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TBL_DelCDSCmd_Payload_t Payload;
};

/*******************************************************************************/
class CFE_TBL_AbortLoadCmd_Payload_t
{
  U8 TableName[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
};

class CFE_TBL_AbortLoadCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TBL_AbortLoadCmd_Payload_t Payload;
};

/*******************************************************************************/
// SENT BY TABLE SERVICES, not to it. The parameter is the owning app's own opaque value.
class CFE_TBL_NotifyCmd_Payload_t
{
  U32 Parameter;
};

class CFE_TBL_NotifyCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TBL_NotifyCmd_Payload_t Payload;
};

/*******************************************************************************/
// THE HOUSEKEEPING PACKET, and most of it is about the LAST thing that happened: the last
// validation's CRC, status, buffer and table name; the last update's time and table; the last
// file loaded and the last file dumped. A ground system watching this sees the history of the
// service rather than a snapshot of it.
class CFE_TBL_HousekeepingTlm_Payload_t
{
  U8 CommandCounter;
  U8 CommandErrorCounter;
  U16 NumTables;
  U16 NumLoadPending;
  U16 ValidationCounter;
  U32 LastValCrc;
  I32 LastValStatus;
  Bool ActiveBuffer;
  U8 LastValTableName[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
  U8 SuccessValCounter;
  U8 FailedValCounter;
  U8 NumValRequests;
  U8 NumFreeSharedBufs;
  // NASA'S OWN PADDING FIELD, named in the source and present in a ground system's telemetry
  // database -- "Spare byte to ensure longword alignment". Translated as the field it is.
  U8 ByteAlignPad1;
  // AND IT IS NOT ENOUGH. ByteAlignPad1 lands at offset 61, so the compiler still inserts TWO
  // more bytes before the 4-byte-aligned MemPoolHandle at 64 -- NASA's named padding field
  // aligns the preceding run of bytes, not this member. check_padding named the offset.
  U8 _pad0[2];
  U32 MemPoolHandle; // CFE_ES_MemHandle_t
  CFE_TIME_SysTime LastUpdateTime;
  U8 LastUpdatedTable[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
  U8 LastFileLoaded[CFE_MISSION_MAX_PATH_LEN];
  U8 LastFileDumped[CFE_MISSION_MAX_PATH_LEN];
  U8 LastTableLoaded[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
};

class CFE_TBL_HousekeepingTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_TBL_HousekeepingTlm_Payload_t Payload;
};

/*******************************************************************************/
// ONE REGISTRY ENTRY, ON REQUEST. The three MemAddress fields are the reason this packet
// exists: a ground system can see where a table's buffers actually are, which is what makes a
// memory dump of a table interpretable.
class CFE_TBL_TblRegPacket_Payload_t
{
  U64 Size; // CFE_ES_MemOffset_t
  U32 Crc;
  U8 Padding1[4]; // NASA's own, named in the source
  U64 ActiveBufferAddr;   // CFE_ES_MemAddress_t
  U64 InactiveBufferAddr; // CFE_ES_MemAddress_t
  U64 ValidationFuncPtr;  // CFE_ES_MemAddress_t
  CFE_TIME_SysTime TimeOfLastUpdate;
  CFE_TIME_SysTime FileTime;
  Bool TableLoadedOnce;
  Bool LoadPending;
  Bool DumpOnly;
  Bool DoubleBuffered;
  U8 Name[CFE_MISSION_TBL_MAX_FULL_NAME_LEN];
  U8 LastFileLoaded[CFE_MISSION_MAX_PATH_LEN];
  U8 OwnerAppName[CFE_MISSION_MAX_API_LEN];
  Bool Critical;
  U8 Padding2[7]; // NASA's own
};

class CFE_TBL_TableRegistryTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_TBL_TblRegPacket_Payload_t Payload;
};
#endif
