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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-mutex.c. Same shape as
// osapi-countsem.c, which carries the full commentary on why these modules look the way they
// do: they are the thin typed front door onto osapi-idmap.c, and everything interesting
// happens there.
//
// The two argument checks still behave differently -- OS_CHECK_POINTER is a BUGCHECK and LOGS,
// OS_CHECK_APINAME adds a LENGTHCHECK which is a silent ARGCHECK -- so a NULL name returns -2
// with a marker and a too-long name returns -13 without one.
#ifndef OSAPI_MUTEX_HC
#define OSAPI_MUTEX_HC
#include "osapi_idmap.HC"
#include "os_shared_mutex.HC"
I32 OS_MutSemCreate_Impl(OS_object_token_t *token, U32 options);
I32 OS_MutSemDelete_Impl(OS_object_token_t *token);
I32 OS_MutSemGive_Impl(OS_object_token_t *token);
I32 OS_MutSemTake_Impl(OS_object_token_t *token);
I32 OS_MutSemGetInfo_Impl(OS_object_token_t *token, OS_mut_sem_prop_t *mutex_prop);

OS_mutex_internal_record_t OS_mutex_table[OS_MAX_MUTEXES];

I32 OS_MutexAPI_Init()
{
  MemSet(OS_mutex_table, 0, sizeof(OS_mutex_table));
  return OS_SUCCESS;
}

I32 OS_MutSemCreate(U32 *sem_id, U8 *sem_name, U32 options)
{
  I32 return_code;
  OS_object_token_t token;
  OS_mutex_internal_record_t *rec;
  OS_common_record_t *grec;
  if (sem_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (sem_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(sem_name, 0, OS_MAX_API_NAME) == NULL)
    return OS_ERR_NAME_TOO_LONG;
  // the common ObjectIdAllocate routine leaves the object type locked
  return_code = OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_MUTEX, sem_name, &token);
  if (return_code == OS_SUCCESS) {
    rec = &OS_mutex_table[OS_ObjectIndexFromToken(&token)];
    // OS_OBJECT_INIT: clear the record, copy the name in, point the COMMON record at that copy
    MemSet(rec, 0, sizeof(OS_mutex_internal_record_t));
    StrNCpy(rec->obj_name, sem_name, OS_MAX_API_NAME - 1);
    grec = OS_ObjectIdGlobalFromToken(&token);
    grec->name_entry = rec->obj_name;
    return_code = OS_MutSemCreate_Impl(&token, options);
    return_code = OS_ObjectIdFinalizeNew(return_code, &token, sem_id);
  }
  return return_code;
}

I32 OS_MutSemDelete(U32 sem_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, OS_OBJECT_TYPE_OS_MUTEX, sem_id, &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_MutSemDelete_Impl(&token);
    return_code = OS_ObjectIdFinalizeDelete(return_code, &token);
  }
  return return_code;
}

I32 OS_MutSemGive(U32 sem_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_MUTEX, sem_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_MutSemGive_Impl(&token);
  return return_code;
}

I32 OS_MutSemTake(U32 sem_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_MUTEX, sem_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_MutSemTake_Impl(&token);
  return return_code;
}

I32 OS_MutSemGetIdByName(U32 *sem_id, U8 *sem_name)
{
  I32 return_code;
  if (sem_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (sem_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdFindByName(OS_OBJECT_TYPE_OS_MUTEX, sem_name, sem_id);
  return return_code;
}

I32 OS_MutSemGetInfo(U32 sem_id, OS_mut_sem_prop_t *mutex_prop)
{
  OS_common_record_t *record;
  OS_common_record_t *base;
  OS_object_token_t token;
  I32 return_code;
  if (mutex_prop == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  MemSet(mutex_prop, 0, sizeof(OS_mut_sem_prop_t));
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_MUTEX, sem_id, &token);
  if (return_code == OS_SUCCESS) {
    // Base into a local first: indexing the parenthesised OS_global_*_table macro directly is
    // off by one in this compiler (docs/HOLYC_STRUCT_LIMITS.md).
    base = &OS_common_table[OS_MUTEX_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
  StrNCpy(mutex_prop->name, record->name_entry, OS_MAX_API_NAME - 1);
    mutex_prop->creator = record->creator;
    return_code = OS_MutSemGetInfo_Impl(&token, mutex_prop);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}
#endif
