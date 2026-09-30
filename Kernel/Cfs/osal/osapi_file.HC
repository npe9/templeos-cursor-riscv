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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-file.c.
#ifndef OSAPI_FILE_HC
#define OSAPI_FILE_HC
#include "os_shared_file.HC"
#include "os_shared_filesys.HC"
#include "../CfsStr.HC"

#define LOCAL_NUM_OBJECTS_FILE OS_MAX_NUM_OPEN_FILES
#define LOCAL_OBJID_TYPE_FILE  OS_OBJECT_TYPE_OS_STREAM

// NASA's own comment: a fixed block size defined here rather than configured; a requirement
// could transition it to a configuration parameter.
#define OS_CP_BLOCK_SIZE 512

// The backend seam. Declared before use because HolyC is single-pass.
I32 OS_FileOpen_Impl(OS_object_token_t *token, U8 *local_path, I32 flags, I32 access_mode);
I32 OS_GenericClose_Impl(OS_object_token_t *token);
I32 OS_GenericRead_Impl(OS_object_token_t *token, U8 *buffer, I64 nbytes, OS_time_t abstime);
I32 OS_GenericWrite_Impl(OS_object_token_t *token, U8 *buffer, I64 nbytes, OS_time_t abstime);
I32 OS_GenericSeek_Impl(OS_object_token_t *token, I64 offset, U32 whence);
I32 OS_FileChmod_Impl(U8 *local_path, U32 access_mode);
I32 OS_FileStat_Impl(U8 *local_path, os_fstat_t *filestat);
I32 OS_FileRemove_Impl(U8 *local_path);
I32 OS_FileRename_Impl(U8 *old_path, U8 *new_path);
I32 OS_FileAllocate_Impl(OS_object_token_t *token, I64 offset, I64 length);
I32 OS_FileTruncate_Impl(OS_object_token_t *token, I64 length);

// OS_close and OS_TimedReadAbs are used before they are defined in NASA's file order (by
// OS_FileIteratorClose and OS_TimedRead respectively). In C the public header declares them;
// HolyC is single-pass, so they go here rather than reordering away from NASA's layout.
I32 OS_close(U32 filedes);
I32 OS_TimedReadAbs(U32 filedes, U8 *buffer, I64 nbytes, OS_time_t abstime);
I32 OS_TimedWriteAbs(U32 filedes, U8 *buffer, I64 nbytes, OS_time_t abstime);

OS_stream_internal_record_t OS_stream_table[LOCAL_NUM_OBJECTS_FILE];

// Helper to close a file from an iterator.
I32 OS_FileIteratorClose(U32 filedes, U8 *arg)
{
  return OS_close(filedes);
}

I32 OS_FileAPI_Init()
{
  MemSet(OS_stream_table, 0, sizeof(OS_stream_table));
  return OS_SUCCESS;
}

I32 OS_OpenCreate(U32 *filedes, U8 *path, I32 flags, I32 access_mode)
{
  I32 return_code;
  U8 local_path[OS_MAX_LOCAL_PATH_LEN];
  OS_object_token_t token;
  OS_stream_internal_record_t *stream;
  OS_common_record_t *grec;
  if (filedes == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // Initialize file descriptor
  *filedes = OS_OBJECT_ID_UNDEFINED;
  // Check for a valid access mode
  if (access_mode != OS_WRITE_ONLY && access_mode != OS_READ_ONLY && access_mode != OS_READ_WRITE)
    return OS_ERROR;
  return_code = OS_TranslatePath(path, local_path);
  if (return_code == OS_SUCCESS) {
    // ObjectIdAllocateNew locks the object type and LEAVES IT LOCKED; FinalizeNew unlocks.
    // NOTE the name passed is NULL here: the stream is named below from `path`, not from the
    // allocation, because two streams may legitimately share a file name.
    return_code = OS_ObjectIdAllocateNew(LOCAL_OBJID_TYPE_FILE, NULL, &token);
    if (return_code == OS_SUCCESS) {
      stream = &OS_stream_table[OS_ObjectIndexFromToken(&token)];
      // OS_OBJECT_INIT(token, stream, stream_name, path)
      MemSet(stream, 0, sizeof(OS_stream_internal_record_t));
      StrNCpy(stream->stream_name, path, OS_MAX_PATH_LEN - 1);
      grec = OS_ObjectIdGlobalFromToken(&token);
      grec->name_entry = stream->stream_name;
      return_code = OS_FileOpen_Impl(&token, local_path, flags, access_mode);
      // Check result, finalize record, and unlock global table.
      return_code = OS_ObjectIdFinalizeNew(return_code, &token, filedes);
    }
  }
  return return_code;
}

I32 OS_close(U32 filedes)
{
  OS_object_token_t token;
  I32 return_code;
  // Make sure the file descriptor is legit before using it
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, LOCAL_OBJID_TYPE_FILE, filedes,
                                   &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_GenericClose_Impl(&token);
    return_code = OS_ObjectIdFinalizeDelete(return_code, &token);
  }
  return return_code;
}

I32 OS_TimedReadAbs(U32 filedes, U8 *buffer, I64 nbytes, OS_time_t abstime)
{
  OS_object_token_t token;
  I32 return_code;
  if (buffer == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (!(nbytes > 0 && nbytes < 0x7FFFFFFF))
    return OS_ERR_INVALID_SIZE;
  // REFCOUNT, not GLOBAL: a read can block, so the global table is not held across it.
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_REFCOUNT, LOCAL_OBJID_TYPE_FILE, filedes, &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_GenericRead_Impl(&token, buffer, nbytes, abstime);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_TimedRead(U32 filedes, U8 *buffer, I64 nbytes, I32 timeout)
{
  return OS_TimedReadAbs(filedes, buffer, nbytes, OS_TimeFromRelativeMilliseconds(timeout));
}

I32 OS_TimedWriteAbs(U32 filedes, U8 *buffer, I64 nbytes, OS_time_t abstime)
{
  OS_object_token_t token;
  I32 return_code;
  if (buffer == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (!(nbytes > 0 && nbytes < 0x7FFFFFFF))
    return OS_ERR_INVALID_SIZE;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_REFCOUNT, LOCAL_OBJID_TYPE_FILE, filedes, &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_GenericWrite_Impl(&token, buffer, nbytes, abstime);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_TimedWrite(U32 filedes, U8 *buffer, I64 nbytes, I32 timeout)
{
  return OS_TimedWriteAbs(filedes, buffer, nbytes, OS_TimeFromRelativeMilliseconds(timeout));
}

I32 OS_read(U32 filedes, U8 *buffer, I64 nbytes)
{
  return OS_TimedRead(filedes, buffer, nbytes, OS_PEND);
}

I32 OS_write(U32 filedes, U8 *buffer, I64 nbytes)
{
  return OS_TimedWrite(filedes, buffer, nbytes, OS_PEND);
}

I32 OS_chmod(U8 *path, U32 access_mode)
{
  U8 local_path[OS_MAX_LOCAL_PATH_LEN];
  I32 return_code;
  return_code = OS_TranslatePath(path, local_path);
  if (return_code == OS_SUCCESS)
    return_code = OS_FileChmod_Impl(local_path, access_mode);
  return return_code;
}

I32 OS_stat(U8 *path, os_fstat_t *filestats)
{
  I32 return_code;
  U8 local_path[OS_MAX_LOCAL_PATH_LEN];
  if (filestats == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  MemSet(filestats, 0, sizeof(os_fstat_t));
  return_code = OS_TranslatePath(path, local_path);
  if (return_code == OS_SUCCESS)
    return_code = OS_FileStat_Impl(local_path, filestats);
  return return_code;
}

I32 OS_lseek(U32 filedes, I64 offset, U32 whence)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_REFCOUNT, LOCAL_OBJID_TYPE_FILE, filedes, &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_GenericSeek_Impl(&token, offset, whence);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_FileAllocate(U32 filedes, I64 offset, I64 length)
{
  OS_object_token_t token;
  I32 return_code;
  // The allocation might block while space is obtained, so REFCOUNT.
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_REFCOUNT, LOCAL_OBJID_TYPE_FILE, filedes, &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_FileAllocate_Impl(&token, offset, length);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_FileTruncate(U32 filedes, I64 length)
{
  OS_object_token_t token;
  I32 return_code;
  // NASA: ftruncate is expected to be quick and should not TYPICALLY block, but it can if
  // there are other simultaneous ops on the same file -- hence REFCOUNT rather than GLOBAL.
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_REFCOUNT, LOCAL_OBJID_TYPE_FILE, filedes, &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_FileTruncate_Impl(&token, length);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_remove(U8 *path)
{
  I32 return_code;
  U8 local_path[OS_MAX_LOCAL_PATH_LEN];
  return_code = OS_TranslatePath(path, local_path);
  if (return_code == OS_SUCCESS)
    return_code = OS_FileRemove_Impl(local_path);
  return return_code;
}

I32 OS_rename(U8 *old_filename, U8 *new_filename)
{
  OS_object_iter_t iter;
  OS_stream_internal_record_t *stream;
  I32 return_code;
  U8 old_path[OS_MAX_LOCAL_PATH_LEN];
  U8 new_path[OS_MAX_LOCAL_PATH_LEN];
  return_code = OS_TranslatePath(old_filename, old_path);
  if (return_code == OS_SUCCESS)
    return_code = OS_TranslatePath(new_filename, new_path);
  if (return_code == OS_SUCCESS)
    return_code = OS_FileRename_Impl(old_path, new_path);
  if (return_code == OS_SUCCESS) {
    // Any OPEN stream still naming the old file has its recorded name updated. The
    // socket_domain test is how a plain file is told apart from a socket in the shared stream
    // table: OS_SocketDomain_INVALID is 0, so a zeroed record is a file.
    OS_ObjectIdIterateActive(LOCAL_OBJID_TYPE_FILE, &iter);
    while (OS_ObjectIdIteratorGetNext(&iter)) {
      stream = &OS_stream_table[OS_ObjectIndexFromToken(&iter.token)];
      if (stream->socket_domain == OS_SocketDomain_INVALID &&
          StrCmp(stream->stream_name, old_filename) == 0) {
        StrNCpy(stream->stream_name, new_filename, OS_MAX_PATH_LEN - 1);
        stream->stream_name[OS_MAX_PATH_LEN - 1] = 0;
      }
    }
    OS_ObjectIdIteratorDestroy(&iter);
  }
  return return_code;
}

I32 OS_cp(U8 *src, U8 *dest)
{
  I32 return_code;
  I32 rd_size;
  I32 wr_size;
  I32 wr_total;
  U32 file1;
  U32 file2;
  U8 copyblock[OS_CP_BLOCK_SIZE];
  if (src == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (dest == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  file1 = OS_OBJECT_ID_UNDEFINED;
  file2 = OS_OBJECT_ID_UNDEFINED;
  return_code = OS_OpenCreate(&file1, src, OS_FILE_FLAG_NONE, OS_READ_ONLY);
  if (return_code == OS_SUCCESS)
    return_code = OS_OpenCreate(&file2, dest, OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE,
                                OS_WRITE_ONLY);
  while (return_code == OS_SUCCESS) {
    rd_size = OS_read(file1, copyblock, sizeof(copyblock));
    if (rd_size < 0) {
      return_code = rd_size;
      break;
    }
    if (rd_size == 0)
      break;
    wr_total = 0;
    while (wr_total < rd_size) {
      wr_size = OS_write(file2, &copyblock[wr_total], rd_size - wr_total);
      if (wr_size < 0) {
        return_code = wr_size;
        break;
      }
      wr_total += wr_size;
    }
  }
  if (OS_ObjectIdDefined(file1))
    OS_close(file1);
  if (OS_ObjectIdDefined(file2))
    OS_close(file2);
  return return_code;
}

I32 OS_mv(U8 *src, U8 *dest)
{
  I32 return_code;
  // First try rename -- this only works if it is on the same filesystem.
  return_code = OS_rename(src, dest);
  if (return_code != OS_SUCCESS) {
    return_code = OS_cp(src, dest);
    if (return_code == OS_SUCCESS)
      OS_remove(src);
  }
  return return_code;
}

I32 OS_FDGetInfo(U32 filedes, OS_file_prop_t *fd_prop)
{
  OS_common_record_t *record;
  OS_common_record_t *base;
  OS_object_token_t token;
  I32 return_code;
  if (fd_prop == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  MemSet(fd_prop, 0, sizeof(OS_file_prop_t));
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_FILE, filedes, &token);
  if (return_code == OS_SUCCESS) {
    // Base into a local first: indexing the parenthesised OS_global_*_table macro directly is
    // off by one in this compiler (docs/HOLYC_STRUCT_LIMITS.md).
    base = &OS_common_table[OS_STREAM_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
    if (record->name_entry != NULL)
      StrNCpy(fd_prop->Path, record->name_entry, OS_MAX_PATH_LEN - 1);
    fd_prop->User = record->creator;
    fd_prop->IsValid = TRUE;
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_FileOpenCheck(U8 *Filename)
{
  I32 return_code;
  OS_object_iter_t iter;
  OS_stream_internal_record_t *stream;
  if (Filename == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ERROR;
  OS_ObjectIdIterateActive(LOCAL_OBJID_TYPE_FILE, &iter);
  while (OS_ObjectIdIteratorGetNext(&iter)) {
    stream = &OS_stream_table[OS_ObjectIndexFromToken(&iter.token)];
    if (stream->socket_domain == OS_SocketDomain_INVALID &&
        StrCmp(stream->stream_name, Filename) == 0) {
      return_code = OS_SUCCESS;
      break;
    }
  }
  OS_ObjectIdIteratorDestroy(&iter);
  return return_code;
}

I32 OS_CloseFileByName(U8 *Filename)
{
  I32 return_code;
  I32 close_code;
  OS_object_iter_t iter;
  OS_stream_internal_record_t *stream;
  if (Filename == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_FS_ERR_PATH_INVALID;
  OS_ObjectIdIterateActive(LOCAL_OBJID_TYPE_FILE, &iter);
  while (OS_ObjectIdIteratorGetNext(&iter)) {
    stream = &OS_stream_table[OS_ObjectIndexFromToken(&iter.token)];
    if (stream->socket_domain == OS_SocketDomain_INVALID &&
        StrCmp(stream->stream_name, Filename) == 0) {
      // call OS_close() on the entry referred to by the iterator
      close_code = OS_ObjectIdIteratorProcessEntry(&iter, &OS_FileIteratorClose);
      // NOTE the condition: the initial OS_FS_ERR_PATH_INVALID is replaced by the FIRST close's
      // result, and after that only a FAILING close replaces it. So "found and closed" reports
      // success while any failure along the way survives to the caller.
      if (return_code == OS_FS_ERR_PATH_INVALID || close_code != OS_SUCCESS)
        return_code = close_code;
    }
  }
  OS_ObjectIdIteratorDestroy(&iter);
  return return_code;
}

I32 OS_CloseAllFiles()
{
  I32 return_code;
  I32 close_code;
  OS_object_iter_t iter;
  return_code = OS_SUCCESS;
  OS_ObjectIdIterateActive(LOCAL_OBJID_TYPE_FILE, &iter);
  while (OS_ObjectIdIteratorGetNext(&iter)) {
    close_code = OS_ObjectIdIteratorProcessEntry(&iter, &OS_FileIteratorClose);
    if (close_code != OS_SUCCESS)
      return_code = close_code;
  }
  OS_ObjectIdIteratorDestroy(&iter);
  return return_code;
}
#endif
