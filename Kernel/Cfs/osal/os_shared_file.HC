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

// 1:1 HolyC translation of the file/stream types, from OSAL src/os/shared/inc/os-shared-file.h
// and the public types in src/os/inc/osapi-file.h. Separate from the implementation so a backend
// can declare its _Impl functions first; see os_shared_errors.HC for why include order does that.
#ifndef OS_SHARED_FILE_HC
#define OS_SHARED_FILE_HC
#include "osconfig.HC"

// --- osapi-file.h access modes and flags -------------------------------------------------------
#define OS_READ_ONLY  0
#define OS_WRITE_ONLY 1
#define OS_READ_WRITE 2

// OS_file_flag_t, an enum in the C; these are the ordinals its declaration assigns.
#define OS_FILE_FLAG_NONE     0x00
#define OS_FILE_FLAG_CREATE   0x01
#define OS_FILE_FLAG_TRUNCATE 0x02

// os_fstat_t mode bits, likewise an enum in the C.
#define OS_FILESTAT_MODE_EXEC  0x00001
#define OS_FILESTAT_MODE_WRITE 0x00002
#define OS_FILESTAT_MODE_READ  0x00004
#define OS_FILESTAT_MODE_DIR   0x10000

// From osapi-sockets.h. OS_SocketDomain_INVALID is the FIRST member of OS_SocketDomain_t, so it
// is 0 -- which matters because osapi-file.c uses it to tell a plain file apart from a socket
// in a table they share, and a zeroed record is therefore a file.
#define OS_SocketDomain_INVALID 0

// OS_StreamState_t, an enum in src/os/inc/osapi-select.h; these are its assigned values.
#define OS_STREAM_STATE_BOUND     0x01
#define OS_STREAM_STATE_CONNECTED 0x02
#define OS_STREAM_STATE_READABLE  0x04
#define OS_STREAM_STATE_WRITABLE  0x08
#define OS_STREAM_STATE_LISTENING 0x10

// --- os-shared-file.h --------------------------------------------------------------------------
class OS_stream_internal_record_t
{
  U8 stream_name[OS_MAX_PATH_LEN];
  U8 socket_domain;
  U8 socket_type;
  U16 stream_state;
};

// --- osapi-file.h public types -----------------------------------------------------------------
class OS_file_prop_t
{
  U8 Path[OS_MAX_PATH_LEN];
  U32 User;
  U8 IsValid; // for backward compatibility; always true if OS_FDGetInfo succeeded
};

class os_fstat_t
{
  U32 FileModeBits;
  OS_time_t FileTime;
  I64 FileSize; // size_t
};
#endif
