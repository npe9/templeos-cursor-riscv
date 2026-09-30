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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-filesys.c.
//
// THE C LIBRARY CALLS HERE MAP ONTO TempleOS's OWN, and two of them are traps that were checked
// rather than assumed (see Kernel/Cfs/CfsStr.HC for the full mapping):
//
//   strstr(haystack, needle)  ->  StrMatch(NEEDLE, HAYSTACK)   ARGUMENTS REVERSED. NASA's
//                                 _extern declaration is StrMatch(U8 *needle, U8 *haystack_str)
//                                 at Kernel/StrA.HC:316, the opposite order from C's strstr.
//   strrchr(s, '/')           ->  StrLastOcc(s, "/")           StrLastOcc takes a marker SET,
//                                 a string of characters, not a single char. For a one-character
//                                 set it is exactly strrchr, NULL when absent included
//                                 (Kernel/StrA.HC:596).
//   strncmp(a, b, n)          ->  StrNCmp                      same argument order; only ever
//                                 compared against zero here, so the +-1 magnitude of
//                                 TempleOS's result does not matter.
#ifndef OSAPI_FILESYS_HC
#define OSAPI_FILESYS_HC
#include "os_shared_filesys.HC"
#include "../CfsStr.HC"

#define LOCAL_NUM_OBJECTS_FILESYS OS_MAX_FILE_SYSTEMS
#define LOCAL_OBJID_TYPE_FILESYS  OS_OBJECT_TYPE_OS_FILESYS

// The backend seam. Declared before use because HolyC is single-pass.
I32 OS_FileSysStartVolume_Impl(OS_object_token_t *token);
I32 OS_FileSysStopVolume_Impl(OS_object_token_t *token);
I32 OS_FileSysFormatVolume_Impl(OS_object_token_t *token);
I32 OS_FileSysCheckVolume_Impl(OS_object_token_t *token, Bool repair);
I32 OS_FileSysStatVolume_Impl(OS_object_token_t *token, OS_statvfs_t *statbuf);
I32 OS_FileSysMountVolume_Impl(OS_object_token_t *token);
I32 OS_FileSysUnmountVolume_Impl(OS_object_token_t *token);

OS_filesys_internal_record_t OS_filesys_table[LOCAL_NUM_OBJECTS_FILESYS];

// A string that should be the prefix of RAM disk volume names, a hint that the file system
// refers to a RAM disk. Multiple RAM disks can be numbered RAM0, RAM1 and so on.
U8 *OS_FILESYS_RAMDISK_VOLNAME_PREFIX = "RAM";
// sizeof() of NASA's array INCLUDES the NUL, and the length check below uses sizeof()-1, so the
// comparison is over the three characters "RAM". Spelled out because HolyC's sizeof on a
// pointer would be 8, not 4.
#define OS_FILESYS_RAMDISK_VOLNAME_PREFIX_LEN 3

// Local helper, not part of the OSAL API. Matches only the free/open entries.
Bool OS_FileSysFilterFree(U8 *ref, OS_object_token_t *token, OS_common_record_t *obj)
{
  return !OS_ObjectIdDefined(obj->active_id);
}

// Local helper, not part of the OSAL API. True when the filesys entry's virtual_mountpt is a
// prefix of the search target AND the match ends on a separator or the end of the string, so
// that a mount point of /mnt/abc does NOT match a target of /mnt/abcd.
Bool OS_FileSys_FindVirtMountPoint(U8 *ref, OS_object_token_t *token, OS_common_record_t *obj)
{
  OS_filesys_internal_record_t *filesys;
  U8 *target = ref;
  I64 mplen;
  filesys = &OS_filesys_table[OS_ObjectIndexFromToken(token)];
  if ((filesys->flags & OS_FILESYS_FLAG_IS_MOUNTED_VIRTUAL) == 0)
    return FALSE;
  mplen = OS_strnlen(filesys->virtual_mountpt, OS_MAX_PATH_LEN);
  if (mplen == 0 || mplen >= OS_MAX_PATH_LEN ||
      StrNCmp(target, filesys->virtual_mountpt, mplen) != 0) {
    // not a substring, so not a match
    return FALSE;
  }
  return target[mplen] == '/' || target[mplen] == 0;
}

// Local helper, not part of the OSAL API. The common code between mkfs and initfs: mkfs passes
// should_format TRUE and initfs passes FALSE.
I32 OS_FileSys_Initialize(U8 *address, U8 *fsdevname, U8 *fsvolname, I64 blocksize,
                          I64 numblocks, Bool should_format)
{
  OS_filesys_internal_record_t *filesys;
  I32 return_code;
  OS_object_token_t token;
  OS_common_record_t *grec;
  // "address" is deliberately NOT checked; in certain configurations it can validly be null,
  // and NASA says so here. OS_CHECK_STRING is a pointer BUGCHECK (logs) followed by a silent
  // LENGTHCHECK ARGCHECK.
  if (fsdevname == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(fsdevname, 0, OS_FS_DEV_NAME_LEN) == NULL)
    return OS_FS_ERR_PATH_TOO_LONG;
  if (fsvolname == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(fsvolname, 0, OS_FS_VOL_NAME_LEN) == NULL)
    return OS_FS_ERR_PATH_TOO_LONG;
  // check names are not empty strings
  if (fsdevname[0] == 0 || fsvolname[0] == 0)
    return OS_FS_ERR_PATH_INVALID;
  return_code = OS_ObjectIdAllocateNew(LOCAL_OBJID_TYPE_FILESYS, fsdevname, &token);
  if (return_code == OS_SUCCESS) {
    filesys = &OS_filesys_table[OS_ObjectIndexFromToken(&token)];
    // OS_OBJECT_INIT(token, filesys, device_name, fsdevname)
    MemSet(filesys, 0, sizeof(OS_filesys_internal_record_t));
    StrNCpy(filesys->device_name, fsdevname, OS_FS_DEV_NAME_LEN - 1);
    grec = OS_ObjectIdGlobalFromToken(&token);
    grec->name_entry = filesys->device_name;
    // populate the VolumeName and BlockSize ahead of the Impl call, so the implementation can
    // reference this info if necessary
    filesys->blocksize = blocksize;
    filesys->numblocks = numblocks;
    filesys->address = address;
    StrNCpy(filesys->volume_name, fsvolname, OS_FS_VOL_NAME_LEN - 1);
    // Determine basic type of filesystem, if not already known: if either an address was
    // supplied, or the volume name starts with "RAM", it is a RAM disk. Otherwise leave the
    // type UNKNOWN and let the implementation decide.
    if (filesys->address != NULL ||
        StrNCmp(filesys->volume_name, OS_FILESYS_RAMDISK_VOLNAME_PREFIX,
                OS_FILESYS_RAMDISK_VOLNAME_PREFIX_LEN) == 0) {
      filesys->fstype = OS_FILESYS_TYPE_VOLATILE_DISK;
    }
    return_code = OS_FileSysStartVolume_Impl(&token);
    if (return_code == OS_SUCCESS) {
      // The "mkfs" call also formats the device; this is the primary difference from initfs.
      if (should_format)
        return_code = OS_FileSysFormatVolume_Impl(&token);
      if (return_code == OS_SUCCESS) {
        filesys->flags |= OS_FILESYS_FLAG_IS_READY;
      } else {
        // To avoid leaving an intermediate state, this also stops the volume if formatting
        // failed. NASA casts the result to void to repress analysis warnings.
        OS_FileSysStopVolume_Impl(&token);
      }
    }
    // Check result, finalize record, and unlock global table.
    return_code = OS_ObjectIdFinalizeNew(return_code, &token, NULL);
  }
  return return_code;
}

I32 OS_FileSysAPI_Init()
{
  I32 return_code = OS_SUCCESS;
  MemSet(OS_filesys_table, 0, sizeof(OS_filesys_table));
  return return_code;
}

I32 OS_FileSysAddFixedMap(U32 *filesys_id, U8 *phys_path, U8 *virt_path)
{
  OS_filesys_internal_record_t *filesys;
  I32 return_code;
  OS_object_token_t token;
  OS_common_record_t *grec;
  if (filesys_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (phys_path == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(phys_path, 0, OS_MAX_LOCAL_PATH_LEN) == NULL)
    return OS_FS_ERR_PATH_TOO_LONG;
  // OS_CHECK_PATHNAME(virt_path)
  if (virt_path == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(virt_path, 0, OS_MAX_PATH_LEN) == NULL)
    return OS_FS_ERR_PATH_TOO_LONG;
  return_code = OS_ObjectIdAllocateNew(LOCAL_OBJID_TYPE_FILESYS, virt_path, &token);
  if (return_code == OS_SUCCESS) {
    filesys = &OS_filesys_table[OS_ObjectIndexFromToken(&token)];
    // OS_OBJECT_INIT(token, filesys, virtual_mountpt, virt_path) -- note the name field here is
    // virtual_mountpt, NOT device_name as in OS_FileSys_Initialize.
    MemSet(filesys, 0, sizeof(OS_filesys_internal_record_t));
    StrNCpy(filesys->virtual_mountpt, virt_path, OS_MAX_PATH_LEN - 1);
    grec = OS_ObjectIdGlobalFromToken(&token);
    grec->name_entry = filesys->virtual_mountpt;
    StrNCpy(filesys->system_mountpt, phys_path, OS_MAX_LOCAL_PATH_LEN - 1);
    StrNCpy(filesys->virtual_mountpt, virt_path, OS_MAX_PATH_LEN - 1);
    // mark the entry that it is a fixed disk
    filesys->fstype = OS_FILESYS_TYPE_FS_BASED;
    filesys->flags = OS_FILESYS_FLAG_IS_FIXED;
    // The "mount" implementation is required as it will create the mountpoint if it does not
    // already exist.
    return_code = OS_FileSysStartVolume_Impl(&token);
    if (return_code == OS_SUCCESS) {
      filesys->flags |= OS_FILESYS_FLAG_IS_READY;
      return_code = OS_FileSysMountVolume_Impl(&token);
    }
    if (return_code == OS_SUCCESS)
      filesys->flags |= OS_FILESYS_FLAG_IS_MOUNTED_SYSTEM | OS_FILESYS_FLAG_IS_MOUNTED_VIRTUAL;
    return_code = OS_ObjectIdFinalizeNew(return_code, &token, filesys_id);
  }
  return return_code;
}

I32 OS_mkfs(U8 *address, U8 *devname, U8 *volname, I64 blocksize, I64 numblocks)
{
  I32 return_code;
  return_code = OS_FileSys_Initialize(address, devname, volname, blocksize, numblocks, TRUE);
  if (return_code == OS_ERR_INCORRECT_OBJ_STATE || return_code == OS_ERR_NO_FREE_IDS) {
    // The historic filesystem-specific code for mkfs/initfs on an already-initialized
    // filesystem, or no free slots. Preserved in case application code checks for it.
    return_code = OS_FS_ERR_DEVICE_NOT_FREE;
  }
  return return_code;
}

I32 OS_rmfs(U8 *devname)
{
  I32 return_code;
  OS_object_token_t token;
  if (devname == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(devname, 0, OS_MAX_PATH_LEN) == NULL)
    return OS_FS_ERR_PATH_TOO_LONG;
  return_code = OS_ObjectIdGetByName(OS_LOCK_MODE_EXCLUSIVE, LOCAL_OBJID_TYPE_FILESYS, devname,
                                     &token);
  if (return_code == OS_SUCCESS) {
    // NASA: it is likely that if the file system is mounted, this call to stop the volume will
    // fail. Checking the flags first would be prudent but would break the existing unit tests.
    return_code = OS_FileSysStopVolume_Impl(&token);
    // Free the entry in the master table
    return_code = OS_ObjectIdFinalizeDelete(return_code, &token);
  } else {
    return_code = OS_ERR_NAME_NOT_FOUND;
  }
  return return_code;
}

I32 OS_initfs(U8 *address, U8 *devname, U8 *volname, I64 blocksize, I64 numblocks)
{
  I32 return_code;
  return_code = OS_FileSys_Initialize(address, devname, volname, blocksize, numblocks, FALSE);
  if (return_code == OS_ERR_INCORRECT_OBJ_STATE || return_code == OS_ERR_NO_FREE_IDS)
    return_code = OS_FS_ERR_DEVICE_NOT_FREE;
  return return_code;
}

I32 OS_mount(U8 *devname, U8 *mountpoint)
{
  I32 return_code;
  OS_object_token_t token;
  OS_filesys_internal_record_t *filesys;
  if (devname == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(devname, 0, OS_FS_DEV_NAME_LEN) == NULL)
    return OS_FS_ERR_PATH_TOO_LONG;
  if (mountpoint == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(mountpoint, 0, OS_MAX_PATH_LEN) == NULL)
    return OS_FS_ERR_PATH_TOO_LONG;
  return_code = OS_ObjectIdGetByName(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_FILESYS, devname,
                                     &token);
  if (return_code == OS_SUCCESS) {
    filesys = &OS_filesys_table[OS_ObjectIndexFromToken(&token)];
    // READY should be set (mkfs/initfs must have run); MOUNTED SYSTEM/VIRTUAL should be unset.
    // FIXED _should_ be unset too -- fixed maps do not support mount/unmount -- but to support
    // abstraction that is not enforced, which is what masking it out here means.
    if ((filesys->flags & ~OS_FILESYS_FLAG_IS_FIXED) != OS_FILESYS_FLAG_IS_READY) {
      return_code = OS_ERR_INCORRECT_OBJ_STATE;
    } else if (filesys->system_mountpt[0] == 0) {
      // The system mount point should be a non-empty string.
      return_code = OS_FS_ERR_PATH_INVALID;
    } else {
      return_code = OS_FileSysMountVolume_Impl(&token);
    }
    if (return_code == OS_SUCCESS) {
      // mark as mounted in the local table; for now this does both sides
      filesys->flags |= OS_FILESYS_FLAG_IS_MOUNTED_SYSTEM | OS_FILESYS_FLAG_IS_MOUNTED_VIRTUAL;
      StrNCpy(filesys->virtual_mountpt, mountpoint, OS_MAX_PATH_LEN - 1);
      filesys->virtual_mountpt[OS_MAX_PATH_LEN - 1] = 0;
    }
    OS_ObjectIdRelease(&token);
  }
  // NOTE every failure is collapsed to OS_ERR_NAME_NOT_FOUND here, INCLUDING the
  // OS_ERR_INCORRECT_OBJ_STATE and OS_FS_ERR_PATH_INVALID computed just above. Translated as
  // written: a caller cannot tell "no such device" from "device not ready".
  if (return_code != OS_SUCCESS)
    return_code = OS_ERR_NAME_NOT_FOUND;
  return return_code;
}

I32 OS_unmount(U8 *mountpoint)
{
  I32 return_code;
  OS_object_token_t token;
  OS_filesys_internal_record_t *filesys;
  if (mountpoint == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(mountpoint, 0, OS_MAX_PATH_LEN) == NULL)
    return OS_FS_ERR_PATH_TOO_LONG;
  return_code = OS_ObjectIdGetBySearch(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_FILESYS,
                                       &OS_FileSys_FindVirtMountPoint, mountpoint, &token);
  if (return_code == OS_SUCCESS) {
    filesys = &OS_filesys_table[OS_ObjectIndexFromToken(&token)];
    // READY and both MOUNTED flags must all be set; FIXED is masked out rather than enforced.
    if ((filesys->flags & ~OS_FILESYS_FLAG_IS_FIXED) !=
        (OS_FILESYS_FLAG_IS_READY | OS_FILESYS_FLAG_IS_MOUNTED_SYSTEM |
         OS_FILESYS_FLAG_IS_MOUNTED_VIRTUAL)) {
      return_code = OS_ERR_INCORRECT_OBJ_STATE;
    } else {
      return_code = OS_FileSysUnmountVolume_Impl(&token);
    }
    if (return_code == OS_SUCCESS)
      filesys->flags &= ~(OS_FILESYS_FLAG_IS_MOUNTED_SYSTEM | OS_FILESYS_FLAG_IS_MOUNTED_VIRTUAL);
    OS_ObjectIdRelease(&token);
  }
  if (return_code != OS_SUCCESS)
    return_code = OS_ERR_NAME_NOT_FOUND;
  return return_code;
}

I32 OS_FileSysStatVolume(U8 *name, OS_statvfs_t *statbuf)
{
  I32 return_code;
  OS_object_token_t token;
  if (name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(name, 0, OS_MAX_PATH_LEN) == NULL)
    return OS_FS_ERR_PATH_TOO_LONG;
  if (statbuf == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdGetBySearch(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_FILESYS,
                                       &OS_FileSys_FindVirtMountPoint, name, &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_FileSysStatVolume_Impl(&token, statbuf);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_chkfs(U8 *name, Bool repair)
{
  OS_object_token_t token;
  I32 return_code;
  if (name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(name, 0, OS_MAX_PATH_LEN) == NULL)
    return OS_FS_ERR_PATH_TOO_LONG;
  // REFCOUNT, not GLOBAL: a filesystem check could take some time, so the table is not held.
  return_code = OS_ObjectIdGetBySearch(OS_LOCK_MODE_REFCOUNT, LOCAL_OBJID_TYPE_FILESYS,
                                       &OS_FileSys_FindVirtMountPoint, name, &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_FileSysCheckVolume_Impl(&token, repair);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_FS_GetPhysDriveName(U8 *PhysDriveName, U8 *MountPoint)
{
  OS_object_token_t token;
  I32 return_code;
  OS_filesys_internal_record_t *filesys;
  if (MountPoint == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(MountPoint, 0, OS_MAX_PATH_LEN) == NULL)
    return OS_FS_ERR_PATH_TOO_LONG;
  if (PhysDriveName == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdGetBySearch(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_FILESYS,
                                       &OS_FileSys_FindVirtMountPoint, MountPoint, &token);
  if (return_code == OS_SUCCESS) {
    filesys = &OS_filesys_table[OS_ObjectIndexFromToken(&token)];
    if ((filesys->flags & OS_FILESYS_FLAG_IS_MOUNTED_SYSTEM) != 0) {
      StrNCpy(PhysDriveName, filesys->system_mountpt, OS_FS_PHYS_NAME_LEN - 1);
      PhysDriveName[OS_FS_PHYS_NAME_LEN - 1] = 0;
    } else {
      return_code = OS_ERR_INCORRECT_OBJ_STATE;
    }
    OS_ObjectIdRelease(&token);
  } else {
    return_code = OS_ERR_NAME_NOT_FOUND;
  }
  return return_code;
}

I32 OS_GetFsInfo(os_fsinfo_t *filesys_info)
{
  OS_object_iter_t iter;
  if (filesys_info == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  MemSet(filesys_info, 0, sizeof(os_fsinfo_t));
  filesys_info->MaxFds = OS_MAX_NUM_OPEN_FILES;
  filesys_info->MaxVolumes = OS_MAX_FILE_SYSTEMS;
  OS_ObjectIdIteratorInit(&OS_FileSysFilterFree, NULL, OS_OBJECT_TYPE_OS_STREAM, &iter);
  while (OS_ObjectIdIteratorGetNext(&iter))
    ++filesys_info->FreeFds;
  OS_ObjectIdIteratorDestroy(&iter);
  OS_ObjectIdIteratorInit(&OS_FileSysFilterFree, NULL, OS_OBJECT_TYPE_OS_FILESYS, &iter);
  while (OS_ObjectIdIteratorGetNext(&iter))
    ++filesys_info->FreeVolumes;
  OS_ObjectIdIteratorDestroy(&iter);
  return OS_SUCCESS;
}

I32 OS_TranslatePath(U8 *VirtualPath, U8 *LocalPath)
{
  OS_object_token_t token;
  I32 return_code;
  U8 *name_ptr;
  U8 *result;
  OS_filesys_internal_record_t *filesys;
  I64 SysMountPointLen;
  I64 VirtPathLen;
  I64 VirtPathBegin;
  if (VirtualPath == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (LocalPath == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // Check length
  VirtPathLen = OS_strnlen(VirtualPath, OS_MAX_PATH_LEN);
  if (VirtPathLen >= OS_MAX_PATH_LEN)
    return OS_FS_ERR_PATH_TOO_LONG;
  // checks to see if there is a '/' somewhere in the path
  name_ptr = StrLastOcc(VirtualPath, "/");
  if (name_ptr == NULL)
    return OS_FS_ERR_PATH_INVALID;
  // StrLastOcc points at the last '/', so advance one char
  name_ptr = name_ptr + 1;
  if (MemChr(name_ptr, 0, OS_MAX_FILE_NAME) == NULL)
    return OS_FS_ERR_NAME_TOO_LONG;
  SysMountPointLen = 0;
  VirtPathBegin = VirtPathLen;
  // All valid Virtual paths must start with a '/' character
  if (VirtualPath[0] != '/')
    return OS_FS_ERR_PATH_INVALID;
  // Preventing backing out of the virtual mount point. NOTE the reversed arguments: StrMatch
  // takes the NEEDLE first, C's strstr takes the haystack first.
  result = StrMatch("..", VirtualPath);
  if (result)
    return OS_FS_ERR_PATH_INVALID;
  // Get a reference lock, as a filesystem check could take some time.
  return_code = OS_ObjectIdGetBySearch(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_FILESYS,
                                       &OS_FileSys_FindVirtMountPoint, VirtualPath, &token);
  if (return_code != OS_SUCCESS) {
    return_code = OS_FS_ERR_PATH_INVALID;
  } else {
    filesys = &OS_filesys_table[OS_ObjectIndexFromToken(&token)];
    if ((filesys->flags & OS_FILESYS_FLAG_IS_MOUNTED_SYSTEM) != 0) {
      SysMountPointLen = OS_strnlen(filesys->system_mountpt, OS_MAX_LOCAL_PATH_LEN);
      VirtPathBegin = OS_strnlen(filesys->virtual_mountpt, OS_MAX_PATH_LEN);
      if (SysMountPointLen < OS_MAX_LOCAL_PATH_LEN)
        MemCpy(LocalPath, filesys->system_mountpt, SysMountPointLen);
    } else {
      return_code = OS_ERR_INCORRECT_OBJ_STATE;
    }
    OS_ObjectIdRelease(&token);
  }
  if (return_code == OS_SUCCESS) {
    if (VirtPathLen < VirtPathBegin) {
      return_code = OS_FS_ERR_PATH_INVALID;
    } else {
      VirtPathLen -= VirtPathBegin;
      if ((SysMountPointLen + VirtPathLen) < OS_MAX_LOCAL_PATH_LEN) {
        MemCpy(&LocalPath[SysMountPointLen], &VirtualPath[VirtPathBegin], VirtPathLen);
        LocalPath[SysMountPointLen + VirtPathLen] = 0;
      } else {
        return_code = OS_FS_ERR_PATH_TOO_LONG;
      }
    }
  }
  return return_code;
}
#endif
