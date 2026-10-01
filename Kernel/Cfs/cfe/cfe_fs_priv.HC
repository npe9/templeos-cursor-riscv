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

// 1:1 HolyC translation of cFE modules/fs/fsw/src/cfe_fs_priv.c, together with the type and
// constant declarations the fs module needs, from
//
//   modules/fs/config/default_cfe_fs_filedef.h       CFE_FS_Header_t, enum CFE_FS_SubType
//   modules/core_api/fsw/inc/cfe_fs_api_typedefs.h   the file categories, the write-event codes,
//                                                    the two callback types, the metadata object
//   modules/fs/fsw/inc/cfe_fs_interface_cfg.h        the header's description length and content id
//   modules/fs/fsw/src/cfe_fs_priv.h                 the background-dump queue and the global
//
// INCLUDE THIS BEFORE cfe_fs_api.HC. HolyC is single pass and has one compilation unit, so
// include order does a linker's job: cfe_fs_api.HC calls CFE_FS_LockSharedData and reads
// CFE_FS_Global, both of which live here.
//
// CFE_SUCCESS comes from cfe_msg_ccsdspri.HC, which is the first translated unit any driver
// includes. That is the existing convention in this directory -- each unit defines the constants
// that are its own and relies on the ones already in scope -- and not an accident of this file.
#ifndef CFE_FS_PRIV_HC
#define CFE_FS_PRIV_HC
// OS_SUCCESS belongs to OSAL, which this module checks the status of; defined here rather than
// in cfe_fs_api.HC because cfe_fs_priv.c's CFE_FS_EarlyInit uses it and comes first.
#ifndef OS_SUCCESS
#define OS_SUCCESS 0
#endif
// --- cfe_error.h: the codes this module returns -----------------------------------------------
#define CFE_FS_BAD_ARGUMENT                0xC6000001
#define CFE_FS_INVALID_PATH                0xC6000002
#define CFE_FS_FNAME_TOO_LONG              0xC6000003
#define CFE_STATUS_EXTERNAL_RESOURCE_FAIL  0xC8000005
#define CFE_STATUS_REQUEST_ALREADY_PENDING 0xC8000006
// --- cfe_core_api_interface_cfg.h / cfe_fs_interface_cfg.h ------------------------------------
// Both are CFE_MISSION_*_CFGVAL indirections in the C, resolving to the DEFAULT_* values below
// in a configuration that does not use EDS. Measured with the host preprocessor rather than
// read off, because the indirection goes through a token paste.
#define CFE_MISSION_MAX_PATH_LEN 64
#define CFE_FS_HDR_DESC_MAX_LEN  32
#define CFE_FS_FILE_CONTENT_ID   0x63464531 // 'cFE1'
// --- osconfig.h -------------------------------------------------------------------------------
// CFE_FS_ExtractFilenameFromPath compares against OS_MAX_PATH_LEN, which is OSAL's limit and
// not cFE's -- the one place in this module where the two configurations have to agree.
#ifndef OS_MAX_PATH_LEN
#define OS_MAX_PATH_LEN 64
#endif
// --- default_cfe_fs_filedef.h: enum CFE_FS_SubType --------------------------------------------
// The values are NOT contiguous and NOT in order in NASA's enum: TBL_REG is 9 and TBL_IMG is 8,
// declared in that sequence, and 5, 7 and 10..14 are unassigned. Kept exactly, because a file
// subtype appears in the file header a ground system reads.
#define CFE_FS_SubType_ES_ERLOG         1
#define CFE_FS_SubType_ES_SYSLOG        2
#define CFE_FS_SubType_ES_QUERYALL      3
#define CFE_FS_SubType_ES_PERFDATA      4
#define CFE_FS_SubType_ES_CDS_REG       6
#define CFE_FS_SubType_TBL_REG          9
#define CFE_FS_SubType_TBL_IMG          8
#define CFE_FS_SubType_EVS_APPDATA      15
#define CFE_FS_SubType_EVS_EVENTLOG     16
#define CFE_FS_SubType_SB_PIPEDATA      20
#define CFE_FS_SubType_SB_ROUTEDATA     21
#define CFE_FS_SubType_SB_MAPDATA       22
#define CFE_FS_SubType_ES_QUERYALLTASKS 23
#define CFE_FS_SubType_TA_QUERYALLTASKS 24

// The standard cFE file header. Written BIG ENDIAN on disk whatever the processor is, which is
// what CFE_FS_ByteSwapCFEHeader is for. Eight uint32 then a fixed description, so this is one
// of the few cFE structs a C compiler does not pad -- see tools/cfs/check_padding.py.
class CFE_FS_Header_t
{
  U32 ContentType;   // identifies the content type (= 'cFE1' = 0x63464531)
  U32 SubType;       // CFE_FS_SubType_Enum_t, itself a uint32
  U32 Length;        // length of this header, to support external processing
  U32 SpacecraftID;
  U32 ProcessorID;
  U32 ApplicationID;
  U32 TimeSeconds;
  U32 TimeSubSeconds;
  U8 Description[CFE_FS_HDR_DESC_MAX_LEN];
};
// --- cfe_fs_api_typedefs.h --------------------------------------------------------------------
// CFE_FS_FileCategory_t: where a kind of file lives by default. NOT the SubType above -- this
// one never appears in a file or a message.
#define CFE_FS_FileCategory_UNKNOWN          0
#define CFE_FS_FileCategory_DYNAMIC_MODULE   1
#define CFE_FS_FileCategory_BINARY_DATA_DUMP 2
#define CFE_FS_FileCategory_TEXT_LOG         3
#define CFE_FS_FileCategory_SCRIPT           4
#define CFE_FS_FileCategory_TEMP             5
#define CFE_FS_FileCategory_MAX              6

// The abstract events a background file write reports. FS is a library, not an app, so it has
// no event ids of its own: the requester supplies a callback that turns these into its own.
#define CFE_FS_FileWriteEvent_UNDEFINED          0
#define CFE_FS_FileWriteEvent_COMPLETE           1
#define CFE_FS_FileWriteEvent_CREATE_ERROR       2
#define CFE_FS_FileWriteEvent_HEADER_WRITE_ERROR 3
#define CFE_FS_FileWriteEvent_RECORD_WRITE_ERROR 4
#define CFE_FS_FileWriteEvent_MAX                5

// The requester's metadata object. An application instantiates this in its own static memory and
// hands cFE a pointer, so its LAYOUT is part of the interface and not an internal detail -- and
// it is the first struct in this translation where a C compiler pads. _pad0 covers the three
// bytes C inserts to align FileSubType after the 1-byte IsPending and the 64-byte FileName.
//
// GetData and OnEvent are CFE_FS_FileWriteGetData_t and CFE_FS_FileWriteOnEvent_t, two function
// pointer typedefs; HolyC has no typedef, so they are spelled out. Their first parameter is
// `void *Meta` in the C -- NASA passes the object back to its owner untyped, because the owner
// usually has a larger struct whose first member is this one.
class CFE_FS_FileWriteMetaData_t
{
  Bool IsPending; // `volatile` in the C, as it is read outside the lock; HolyC has no volatile
  U8 FileName[CFE_MISSION_MAX_PATH_LEN];
  U8 _pad0[3]; // C pads here; HolyC packs. See tools/cfs/check_padding.py
  U32 FileSubType; // CFE_FS_SubType_Enum_t
  U8 Description[CFE_FS_HDR_DESC_MAX_LEN];
  Bool (*GetData)(U8 *Meta, U32 RecordNum, U8 **Buffer, I64 *BufSize);
  U0 (*OnEvent)(U8 *Meta, I32 Event, I32 Status, U32 RecordNum, I64 BlockSize, I64 Position);
};
// --- cfe_fs_priv.h ----------------------------------------------------------------------------
// A power of two, so the queue wraps with a bitwise AND rather than a modulo.
#define CFE_FS_MAX_BACKGROUND_FILE_WRITES 4
// Bytes of write credit earned per second of elapsed time: a 10 kbyte/sec ceiling.
#define CFE_FS_BACKGROUND_CREDIT_PER_SECOND 10000
// The cap on accumulated credit. Without it, a long idle period would bank enough credit to
// bypass the rate limit entirely on the next request.
#define CFE_FS_BACKGROUND_MAX_CREDIT 10000

class CFE_FS_BackgroundFileDumpEntry_t
{
  U32 RequestorAppId; // CFE_ES_AppId_t
  U8 _pad0[4]; // C pads here; HolyC packs. See tools/cfs/check_padding.py
  CFE_FS_FileWriteMetaData_t *Meta;
};

class CFE_FS_CurrentFileState_t
{
  U32 Fd;        // osal_id_t
  I32 Credit;
  U32 RecordNum;
  U8 _pad0[4]; // C pads here; HolyC packs. See tools/cfs/check_padding.py
  I64 FileSize;  // size_t
};

// Normally RequestCount and CompleteCount are equal and the queue is idle. A request bumps the
// first; finishing the job bumps the second.
class CFE_FS_BackgroundFileDumpState_t
{
  U32 RequestCount;  // total number of background file writes requested
  U32 CompleteCount; // total number completed
  CFE_FS_BackgroundFileDumpEntry_t Entries[CFE_FS_MAX_BACKGROUND_FILE_WRITES];
  CFE_FS_CurrentFileState_t Current; // reused for each file
};

class CFE_FS_Global_t
{
  U32 SharedDataMutexId; // osal_id_t
  U8 _pad0[4]; // C pads here; HolyC packs. See tools/cfs/check_padding.py
  CFE_FS_BackgroundFileDumpState_t FileDump;
};
// --- cfe_fs_priv.c ----------------------------------------------------------------------------
// Global data
CFE_FS_Global_t CFE_FS_Global;

// The OSAL and ES entry points this module reaches for. In a built port these resolve to the
// translated OSAL in Kernel/Cfs/osal and to ES; in the differential oracle the driver supplies
// them, which is the same arrangement cfe_msg_integrity.HC has for CFE_TIME_GetTime. The blob's
// import trailer is what keeps an undefined one from binding silently to the host C runtime.
I32 OS_MutSemCreate(U32 *sem_id, U8 *sem_name, U32 options);
I32 OS_MutSemTake(U32 sem_id);
I32 OS_MutSemGive(U32 sem_id);
I32 CFE_ES_GetAppID(U32 *AppIdPtr);

I32 CFE_FS_EarlyInit()
{
  I32 OsStatus;

  MemSet(&CFE_FS_Global, 0, sizeof(CFE_FS_Global));

  OsStatus = OS_MutSemCreate(&CFE_FS_Global.SharedDataMutexId, "CFE_FS_SharedMutex", 0);
  if (OsStatus != OS_SUCCESS) {
    // NASA logs `"%s: Shared Data Mutex creation failed! RC=%ld\n", __func__, (long)OsStatus`.
    // HolyC has no __func__ and this translation's CFE_ES_WriteToSysLog takes a plain string --
    // see cfe_sb_util.HC for why the format arguments are deliberately outside the comparison.
    CFE_ES_WriteToSysLog("CFE_FS_EarlyInit: Shared Data Mutex creation failed!\n");
    return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  }

  return CFE_SUCCESS;
}

U0 CFE_FS_LockSharedData(U8 *FunctionName)
{
  I32 OsStatus;
  U32 AppId; // CFE_ES_AppId_t

  OsStatus = OS_MutSemTake(CFE_FS_Global.SharedDataMutexId);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_GetAppID(&AppId);
    CFE_ES_WriteToSysLog("CFE_FS_LockSharedData: SharedData Mutex Take Err\n");
  }
}

U0 CFE_FS_UnlockSharedData(U8 *FunctionName)
{
  I32 OsStatus;
  U32 AppId; // CFE_ES_AppId_t

  OsStatus = OS_MutSemGive(CFE_FS_Global.SharedDataMutexId);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_GetAppID(&AppId);
    CFE_ES_WriteToSysLog("CFE_FS_UnlockSharedData: SharedData Mutex Give Err\n");
  }
}
#endif
