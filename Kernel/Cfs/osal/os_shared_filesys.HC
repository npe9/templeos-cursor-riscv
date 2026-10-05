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

// 1:1 HolyC translation of the filesystem types, from OSAL src/os/shared/inc/os-shared-filesys.h
// and the public types in src/os/inc/osapi-filesys.h. Separate from the implementation so a
// backend can declare its _Impl functions first; see os_shared_errors.HC for why include order
// does that job here.
#ifndef OS_SHARED_FILESYS_HC
#define OS_SHARED_FILESYS_HC
#include "osconfig.HC"

// From src/os/inc/osapi-constants.h, where it is DERIVED rather than configured:
//     #define OS_MAX_LOCAL_PATH_LEN (OS_MAX_PATH_LEN + OS_FS_PHYS_NAME_LEN)
// It is not in osconfig.h.in, so gen_osconfig.py does not emit it and it belongs here.
// 64 + 64 = 128 in this configuration.
#define OS_MAX_LOCAL_PATH_LEN (OS_MAX_PATH_LEN + OS_FS_PHYS_NAME_LEN)

// --- os-shared-filesys.h flags -----------------------------------------------------------------
// A fixed map, created by OS_FileSysAddFixedMap; mount/unmount do not apply to it.
#define OS_FILESYS_FLAG_IS_FIXED           0x01
// mkfs/initfs has been called: the volume exists and can be mounted.
#define OS_FILESYS_FLAG_IS_READY           0x02
#define OS_FILESYS_FLAG_IS_MOUNTED_SYSTEM  0x10
#define OS_FILESYS_FLAG_IS_MOUNTED_VIRTUAL 0x20

// The filesystem type enum. HolyC has no enum, so these are the same ordinals NASA's compiler
// assigns, in NASA's declaration order.
#define OS_FILESYS_TYPE_UNKNOWN        0
#define OS_FILESYS_TYPE_FS_BASED       1
#define OS_FILESYS_TYPE_NORMAL_DISK    2
#define OS_FILESYS_TYPE_VOLATILE_DISK  3
#define OS_FILESYS_TYPE_MTD            4
#define OS_FILESYS_TYPE_MAX            5

class OS_filesys_internal_record_t
{
  U8 device_name[OS_FS_DEV_NAME_LEN];   // the underlying block device, if applicable
  U8 volume_name[OS_FS_VOL_NAME_LEN];
  U8 system_mountpt[OS_MAX_LOCAL_PATH_LEN]; // where the contents are reachable in the host OS
  U8 virtual_mountpt[OS_MAX_PATH_LEN];  // the prefix applications see in the OSAL virtual FS
  U8 *address;
  I64 blocksize;  // size_t
  I64 numblocks;  // osal_blockcount_t, itself a size_t
  U8 flags;
  U8 fstype;
  U8 _pad0[6]; // C rounds the struct up to its alignment; HolyC does not
};

// --- osapi-filesys.h public types --------------------------------------------------------------
class os_fsinfo_t
{
  U32 MaxFds;      // total number of file descriptors
  U32 FreeFds;     // total number that are free
  U32 MaxVolumes;  // maximum number of volumes
  U32 FreeVolumes; // total number of volumes free
};

// OS_statvfs_t moved to osapi_filesys_decl.HC, because cFE needs it on its own:
// cfe_es_start.c asks the RAM disk how full it is and must not drag this file's implementation
// across the seam. Same split, same reason, as osapi_heap_decl.HC and osapi_module_decl.HC.
#include "osapi_filesys_decl.HC"
#endif
