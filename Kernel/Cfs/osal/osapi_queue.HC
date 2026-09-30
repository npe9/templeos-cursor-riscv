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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-queue.c.
//
// The resource shape again, but this one CARRIES DATA, and that puts real logic in the portable
// layer rather than leaving it all to the backend: the queue's max_size is recorded at create
// time, and Get and Put each check the caller's buffer against it BEFORE the backend is
// reached. The two checks are deliberately asymmetric --
//     Get rejects a buffer SMALLER than max_size   (it could not hold a full message)
//     Put rejects a payload LARGER than max_size   (it would not fit)
// -- and Get also zeroes *size_copied on that path while Put has nothing to zero. Getting the
// comparison backwards in either one would still pass every "it returned something" test.
#ifndef OSAPI_QUEUE_HC
#define OSAPI_QUEUE_HC
#include "osapi_idmap.HC"
#include "os_shared_queue.HC"
#define LOCAL_OBJID_TYPE_QUEUE OS_OBJECT_TYPE_OS_QUEUE
I32 OS_QueueCreate_Impl(OS_object_token_t *token, U32 flags);
I32 OS_QueueDelete_Impl(OS_object_token_t *token);
I32 OS_QueueGet_Impl(OS_object_token_t *token, U8 *data, I64 size, I64 *size_copied, I32 timeout);
I32 OS_QueuePut_Impl(OS_object_token_t *token, U8 *data, I64 size, U32 flags);

OS_queue_internal_record_t OS_queue_table[OS_MAX_QUEUES];

I32 OS_QueueAPI_Init()
{
  MemSet(OS_queue_table, 0, sizeof(OS_queue_table));
  return OS_SUCCESS;
}

I32 OS_QueueCreate(U32 *queue_id, U8 *queue_name, I64 queue_depth, I64 data_size, U32 flags)
{
  I32 return_code;
  OS_object_token_t token;
  OS_queue_internal_record_t *queue;
  OS_common_record_t *grec;
  // validate inputs. OS_CHECK_POINTER and the pointer half of OS_CHECK_APINAME are BUGCHECKs
  // and LOG; the length check, OS_CHECK_SIZE and the bare ARGCHECK are silent ARGCHECKs.
  if (queue_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (queue_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(queue_name, 0, OS_MAX_API_NAME) == NULL)
    return OS_ERR_NAME_TOO_LONG;
  if (!(data_size > 0 && data_size < 0x7FFFFFFF))
    return OS_ERR_INVALID_SIZE;
  // ARGCHECK(queue_depth <= OS_QUEUE_MAX_DEPTH, OS_QUEUE_INVALID_SIZE)
  if (!(queue_depth <= OS_QUEUE_MAX_DEPTH))
    return OS_QUEUE_INVALID_SIZE;
  return_code = OS_ObjectIdAllocateNew(LOCAL_OBJID_TYPE_QUEUE, queue_name, &token);
  if (return_code == OS_SUCCESS) {
    queue = &OS_queue_table[OS_ObjectIndexFromToken(&token)];
    // OS_OBJECT_INIT(token, queue, queue_name, queue_name) -- the field and the argument
    // happen to share a name here, which is why the macro takes the field explicitly.
    MemSet(queue, 0, sizeof(OS_queue_internal_record_t));
    StrNCpy(queue->queue_name, queue_name, OS_MAX_API_NAME - 1);
    grec = OS_ObjectIdGlobalFromToken(&token);
    grec->name_entry = queue->queue_name;
    queue->max_depth = queue_depth;
    queue->max_size = data_size;
    return_code = OS_QueueCreate_Impl(&token, flags);
    return_code = OS_ObjectIdFinalizeNew(return_code, &token, queue_id);
  }
  return return_code;
}

I32 OS_QueueDelete(U32 queue_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, LOCAL_OBJID_TYPE_QUEUE, queue_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_QueueDelete_Impl(&token);
    return_code = OS_ObjectIdFinalizeDelete(return_code, &token);
  }
  return return_code;
}

I32 OS_QueueGet(U32 queue_id, U8 *data, I64 size, I64 *size_copied, I32 timeout)
{
  OS_object_token_t token;
  I32 return_code;
  OS_queue_internal_record_t *queue;
  if (data == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (size_copied == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (!(size > 0 && size < 0x7FFFFFFF))
    return OS_ERR_INVALID_SIZE;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, LOCAL_OBJID_TYPE_QUEUE, queue_id, &token);
  if (return_code == OS_SUCCESS) {
    queue = &OS_queue_table[OS_ObjectIndexFromToken(&token)];
    if (size < queue->max_size) {
      // The buffer that the user is passing in is potentially too small
      *size_copied = 0;
      return_code = OS_QUEUE_INVALID_SIZE;
    } else {
      return_code = OS_QueueGet_Impl(&token, data, size, size_copied, timeout);
    }
  }
  return return_code;
}

I32 OS_QueuePut(U32 queue_id, U8 *data, I64 size, U32 flags)
{
  OS_object_token_t token;
  I32 return_code;
  OS_queue_internal_record_t *queue;
  if (data == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (!(size > 0 && size < 0x7FFFFFFF))
    return OS_ERR_INVALID_SIZE;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, LOCAL_OBJID_TYPE_QUEUE, queue_id, &token);
  if (return_code == OS_SUCCESS) {
    queue = &OS_queue_table[OS_ObjectIndexFromToken(&token)];
    if (size > queue->max_size) {
      // The buffer that the user is passing in is too large
      return_code = OS_QUEUE_INVALID_SIZE;
    } else {
      return_code = OS_QueuePut_Impl(&token, data, size, flags);
    }
  }
  return return_code;
}

I32 OS_QueueGetIdByName(U32 *queue_id, U8 *queue_name)
{
  I32 return_code;
  if (queue_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (queue_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdFindByName(LOCAL_OBJID_TYPE_QUEUE, queue_name, queue_id);
  return return_code;
}

// NOTE there is NO OS_QueueGetInfo_Impl call -- unlike every other module's GetInfo, this one
// reports only what the SHARED layer knows, and the C has a comment where the backend call
// would be. So a queue's depth and max size are never reported back, which is a gap in NASA's
// API rather than an omission here.
I32 OS_QueueGetInfo(U32 queue_id, OS_queue_prop_t *queue_prop)
{
  OS_common_record_t *record;
  OS_common_record_t *base;
  I32 return_code;
  OS_object_token_t token;
  if (queue_prop == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  MemSet(queue_prop, 0, sizeof(OS_queue_prop_t));
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_QUEUE, queue_id, &token);
  if (return_code == OS_SUCCESS) {
    // Base into a local first: indexing the parenthesised macro is off by one here.
    base = &OS_common_table[OS_QUEUE_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
    StrNCpy(queue_prop->name, record->name_entry, OS_MAX_API_NAME - 1);
    queue_prop->creator = record->creator;
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}
#endif
