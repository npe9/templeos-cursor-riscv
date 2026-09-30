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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-dir.c.
//
// THREE DIFFERENT LOCK MODES in one small module, which is the thing to get right:
//   OS_DirectoryClose   EXCLUSIVE -- it deletes the record
//   OS_DirectoryRead    GLOBAL    -- and RELEASES afterwards
//   OS_DirectoryRewind  NONE      -- and does NOT release, because NONE took nothing
// Giving Rewind a real lock mode without a matching release leaks a reference every call, and
// the EXCLUSIVE close that follows can then never succeed.
#ifndef OSAPI_DIR_HC
#define OSAPI_DIR_HC
#include "os_shared_dir.HC"
#include "os_shared_filesys.HC"
#include "../CfsStr.HC"

#define LOCAL_NUM_OBJECTS_DIR OS_MAX_NUM_OPEN_DIRS
#define LOCAL_OBJID_TYPE_DIR  OS_OBJECT_TYPE_OS_DIR

// The backend seam. Declared before use because HolyC is single-pass.
I32 OS_DirCreate_Impl(U8 *local_path, U32 access);
I32 OS_DirOpen_Impl(OS_object_token_t *token, U8 *local_path);
I32 OS_DirClose_Impl(OS_object_token_t *token);
I32 OS_DirRead_Impl(OS_object_token_t *token, os_dirent_t *dirent);
I32 OS_DirRewind_Impl(OS_object_token_t *token);
I32 OS_DirRemove_Impl(U8 *local_path);

OS_dir_internal_record_t OS_dir_table[LOCAL_NUM_OBJECTS_DIR];

I32 OS_DirAPI_Init()
{
  MemSet(OS_dir_table, 0, sizeof(OS_dir_table));
  return OS_SUCCESS;
}

I32 OS_mkdir(U8 *path, U32 access)
{
  I32 return_code;
  U8 local_path[OS_MAX_LOCAL_PATH_LEN];
  return_code = OS_TranslatePath(path, local_path);
  if (return_code == OS_SUCCESS)
    return_code = OS_DirCreate_Impl(local_path, access);
  return return_code;
}

I32 OS_DirectoryOpen(U32 *dir_id, U8 *path)
{
  U8 local_path[OS_MAX_LOCAL_PATH_LEN];
  OS_object_token_t token;
  OS_dir_internal_record_t *dir;
  I32 return_code;
  OS_common_record_t *grec;
  if (dir_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_TranslatePath(path, local_path);
  if (return_code == OS_SUCCESS) {
    // ObjectIdAllocateNew locks the object type and LEAVES IT LOCKED; FinalizeNew unlocks. The
    // name passed is NULL, as in OS_OpenCreate -- the record is named from `path` below.
    return_code = OS_ObjectIdAllocateNew(LOCAL_OBJID_TYPE_DIR, NULL, &token);
    if (return_code == OS_SUCCESS) {
      dir = &OS_dir_table[OS_ObjectIndexFromToken(&token)];
      // OS_OBJECT_INIT(token, dir, dir_name, path)
      MemSet(dir, 0, sizeof(OS_dir_internal_record_t));
      StrNCpy(dir->dir_name, path, OS_MAX_PATH_LEN - 1);
      grec = OS_ObjectIdGlobalFromToken(&token);
      grec->name_entry = dir->dir_name;
      return_code = OS_DirOpen_Impl(&token, local_path);
      return_code = OS_ObjectIdFinalizeNew(return_code, &token, dir_id);
    }
  }
  return return_code;
}

I32 OS_DirectoryClose(U32 dir_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, LOCAL_OBJID_TYPE_DIR, dir_id, &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_DirClose_Impl(&token);
    return_code = OS_ObjectIdFinalizeDelete(return_code, &token);
  }
  return return_code;
}

I32 OS_DirectoryRead(U32 dir_id, os_dirent_t *dirent)
{
  OS_object_token_t token;
  I32 return_code;
  if (dirent == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_DIR, dir_id, &token);
  if (return_code == OS_SUCCESS) {
    // NASA's note: this does NOT map virtual mount points appearing in the listing back to the
    // virtualized name. If the real /eeprom is virtualized to /cf and the application reads
    // "/", it sees the real name, not the virtual one.
    return_code = OS_DirRead_Impl(&token, dirent);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_DirectoryRewind(U32 dir_id)
{
  OS_object_token_t token;
  I32 return_code;
  // LOCK_MODE_NONE, and correspondingly NO release below -- see the note at the top.
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, LOCAL_OBJID_TYPE_DIR, dir_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_DirRewind_Impl(&token);
  return return_code;
}

I32 OS_rmdir(U8 *path)
{
  I32 return_code;
  U8 local_path[OS_MAX_LOCAL_PATH_LEN];
  return_code = OS_TranslatePath(path, local_path);
  if (return_code == OS_SUCCESS)
    return_code = OS_DirRemove_Impl(local_path);
  return return_code;
}
#endif
