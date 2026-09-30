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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-countsem.c, with the types from
// src/os/shared/inc/os-shared-countsem.h and src/os/inc/osapi-countsem.h.
//
// THE TEMPLATE FOR THE WHOLE RESOURCE FAMILY. countsem, mutex, binsem, condvar and rwlock are
// the same shape: allocate an id through the common table, stash a name, call the backend, and
// finalise. Everything interesting happens in osapi-idmap.c; these files are the thin, typed
// front door onto it. Getting this one exactly right makes the other four mechanical.
//
// TWO ARGUMENT CHECKS THAT BEHAVE DIFFERENTLY, and the difference is easy to translate away:
//   OS_CHECK_POINTER(x)  is a BUGCHECK -- it LOGS through OS_printf and returns OS_INVALID_POINTER
//   OS_CHECK_APINAME(s)  is OS_CHECK_POINTER(s) followed by LENGTHCHECK, and LENGTHCHECK is an
//                        ARGCHECK: SILENT, returning OS_ERR_NAME_TOO_LONG
// So a NULL name logs and returns -2, while a too-long name says nothing and returns -13. The
// transcript checks both, because the first draft of osapi-idmap.c got exactly this wrong.
#ifndef OSAPI_COUNTSEM_HC
#define OSAPI_COUNTSEM_HC
#include "osapi_idmap.HC"
#include "os_shared_countsem.HC"
// The C has `#error` if OS_MAX_COUNT_SEMAPHORES is undefined or zero. HolyC's preprocessor has
// no #error, so that guard cannot be translated; the value comes from the generated osconfig.HC
// and the transcript prints the table size, which is the same property observed from outside.
#define LOCAL_NUM_OBJECTS_COUNTSEM OS_MAX_COUNT_SEMAPHORES
#define LOCAL_OBJID_TYPE_COUNTSEM  OS_OBJECT_TYPE_OS_COUNTSEM
// --- the backend seam ---------------------------------------------------------------------------
I32 OS_CountSemCreate_Impl(OS_object_token_t *token, U32 sem_initial_value, U32 options);
I32 OS_CountSemDelete_Impl(OS_object_token_t *token);
I32 OS_CountSemGive_Impl(OS_object_token_t *token);
I32 OS_CountSemTake_Impl(OS_object_token_t *token);
I32 OS_CountSemTimedWait_Impl(OS_object_token_t *token, U32 msecs);
I32 OS_CountSemGetInfo_Impl(OS_object_token_t *token, OS_count_sem_prop_t *count_prop);
// --- osapi-countsem.c ----------------------------------------------------------------------------
OS_count_sem_internal_record_t OS_count_sem_table[LOCAL_NUM_OBJECTS_COUNTSEM];

I32 OS_CountSemAPI_Init()
{
  MemSet(OS_count_sem_table, 0, sizeof(OS_count_sem_table));
  return OS_SUCCESS;
}

I32 OS_CountSemCreate(U32 *sem_id, U8 *sem_name, U32 sem_initial_value, U32 options)
{
  I32 return_code;
  OS_object_token_t token;
  OS_count_sem_internal_record_t *countsem;
  OS_common_record_t *grec;
  // Check parameters. OS_CHECK_POINTER logs; the length half of OS_CHECK_APINAME does not.
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
  // Note - the common ObjectIdAllocate routine will lock the object type and leave it locked.
  return_code = OS_ObjectIdAllocateNew(LOCAL_OBJID_TYPE_COUNTSEM, sem_name, &token);
  if (return_code == OS_SUCCESS) {
    countsem = &OS_count_sem_table[OS_ObjectIndexFromToken(&token)];
    // OS_OBJECT_INIT(token, countsem, obj_name, sem_name): reset the table entry, copy the
    // name into it, and point the COMMON record's name_entry at that copy. This is where a
    // name enters the system at all -- idmap itself never stores one.
    MemSet(countsem, 0, sizeof(OS_count_sem_internal_record_t));
    StrNCpy(countsem->obj_name, sem_name, OS_MAX_API_NAME - 1);
    grec = OS_ObjectIdGlobalFromToken(&token);
    grec->name_entry = countsem->obj_name;
    // Now call the OS-specific implementation. This reads info from the table.
    return_code = OS_CountSemCreate_Impl(&token, sem_initial_value, options);
    // Check result, finalize record, and unlock global table.
    return_code = OS_ObjectIdFinalizeNew(return_code, &token, sem_id);
  }
  return return_code;
}

I32 OS_CountSemDelete(U32 sem_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, LOCAL_OBJID_TYPE_COUNTSEM, sem_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_CountSemDelete_Impl(&token);
    // Complete the operation via the common routine
    return_code = OS_ObjectIdFinalizeDelete(return_code, &token);
  }
  return return_code;
}

I32 OS_CountSemGive(U32 sem_id)
{
  OS_object_token_t token;
  I32 return_code;
  // Check Parameters
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, LOCAL_OBJID_TYPE_COUNTSEM, sem_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_CountSemGive_Impl(&token);
  return return_code;
}

I32 OS_CountSemTake(U32 sem_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, LOCAL_OBJID_TYPE_COUNTSEM, sem_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_CountSemTake_Impl(&token);
  return return_code;
}

I32 OS_CountSemTimedWait(U32 sem_id, U32 msecs)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, LOCAL_OBJID_TYPE_COUNTSEM, sem_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_CountSemTimedWait_Impl(&token, msecs);
  return return_code;
}

I32 OS_CountSemGetIdByName(U32 *sem_id, U8 *sem_name)
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
  return_code = OS_ObjectIdFindByName(LOCAL_OBJID_TYPE_COUNTSEM, sem_name, sem_id);
  return return_code;
}

I32 OS_CountSemGetInfo(U32 sem_id, OS_count_sem_prop_t *count_prop)
{
  OS_common_record_t *record;
  OS_common_record_t *base;
  OS_object_token_t token;
  I32 return_code;
  if (count_prop == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  MemSet(count_prop, 0, sizeof(OS_count_sem_prop_t));
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_COUNTSEM, sem_id, &token);
  if (return_code == OS_SUCCESS) {
    // OS_OBJECT_TABLE_GET(OS_global_count_sem_table, token). The base is taken into a local
    // first: indexing the parenthesised macro directly, `(&OS_common_table[BASE])[idx]`, does
    // not produce the right address in HolyC -- it faulted reading a NULL name_entry.
    base = &OS_common_table[OS_COUNTSEM_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
    StrNCpy(count_prop->name, record->name_entry, OS_MAX_API_NAME - 1);
    count_prop->creator = record->creator;
    return_code = OS_CountSemGetInfo_Impl(&token, count_prop);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}
#endif
