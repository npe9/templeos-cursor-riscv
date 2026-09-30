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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-condvar.c. Same shape as
// osapi-countsem.c, which carries the full commentary on why these modules look the way they
// do: they are the thin typed front door onto osapi-idmap.c, and everything interesting
// happens there.
//
// The two argument checks still behave differently -- OS_CHECK_POINTER is a BUGCHECK and LOGS,
// OS_CHECK_APINAME adds a LENGTHCHECK which is a silent ARGCHECK -- so a NULL name returns -2
// with a marker and a too-long name returns -13 without one.
#ifndef OSAPI_CONDVAR_HC
#define OSAPI_CONDVAR_HC
#include "osapi_idmap.HC"
#include "os_shared_condvar.HC"
// for OS_time_t, which CondVarTimedWait takes
#include "osapi_clock.HC"
I32 OS_CondVarCreate_Impl(OS_object_token_t *token, U32 options);
I32 OS_CondVarDelete_Impl(OS_object_token_t *token);
I32 OS_CondVarLock_Impl(OS_object_token_t *token);
I32 OS_CondVarUnlock_Impl(OS_object_token_t *token);
I32 OS_CondVarSignal_Impl(OS_object_token_t *token);
I32 OS_CondVarBroadcast_Impl(OS_object_token_t *token);
I32 OS_CondVarWait_Impl(OS_object_token_t *token);
I32 OS_CondVarTimedWait_Impl(OS_object_token_t *token, OS_time_t *abs_wakeup_time);
I32 OS_CondVarGetInfo_Impl(OS_object_token_t *token, OS_condvar_prop_t *condvar_prop);

OS_condvar_internal_record_t OS_condvar_table[OS_MAX_CONDVARS];

I32 OS_CondVarAPI_Init()
{
  memset(OS_condvar_table, 0, sizeof(OS_condvar_table));
  return OS_SUCCESS;
}

I32 OS_CondVarCreate(U32 *var_id, U8 *var_name, U32 options)
{
  I32 return_code;
  OS_object_token_t token;
  OS_condvar_internal_record_t *rec;
  OS_common_record_t *grec;
  if (var_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (var_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (memchr(var_name, 0, OS_MAX_API_NAME) == NULL)
    return OS_ERR_NAME_TOO_LONG;
  // the common ObjectIdAllocate routine leaves the object type locked
  return_code = OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_CONDVAR, var_name, &token);
  if (return_code == OS_SUCCESS) {
    rec = &OS_condvar_table[OS_ObjectIndexFromToken(&token)];
    // OS_OBJECT_INIT: clear the record, copy the name in, point the COMMON record at that copy
    memset(rec, 0, sizeof(OS_condvar_internal_record_t));
    strncpy(rec->obj_name, var_name, OS_MAX_API_NAME - 1);
    grec = OS_ObjectIdGlobalFromToken(&token);
    grec->name_entry = rec->obj_name;
    return_code = OS_CondVarCreate_Impl(&token, options);
    return_code = OS_ObjectIdFinalizeNew(return_code, &token, var_id);
  }
  return return_code;
}

I32 OS_CondVarDelete(U32 var_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, OS_OBJECT_TYPE_OS_CONDVAR, var_id, &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_CondVarDelete_Impl(&token);
    return_code = OS_ObjectIdFinalizeDelete(return_code, &token);
  }
  return return_code;
}

I32 OS_CondVarLock(U32 var_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_CONDVAR, var_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_CondVarLock_Impl(&token);
  return return_code;
}

I32 OS_CondVarUnlock(U32 var_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_CONDVAR, var_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_CondVarUnlock_Impl(&token);
  return return_code;
}

I32 OS_CondVarSignal(U32 var_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_CONDVAR, var_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_CondVarSignal_Impl(&token);
  return return_code;
}

I32 OS_CondVarBroadcast(U32 var_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_CONDVAR, var_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_CondVarBroadcast_Impl(&token);
  return return_code;
}

I32 OS_CondVarWait(U32 var_id)
{
  OS_object_token_t token;
  I32 return_code;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_CONDVAR, var_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_CondVarWait_Impl(&token);
  return return_code;
}

// UNLIKE ITS SIBLINGS this takes an ABSOLUTE wake time, not a relative millisecond count, and
// it has its own OS_CHECK_POINTER on that argument -- a BUGCHECK, so it logs. A generated
// template gave it the binsem shape (uint32 msecs, no check) and comparing against NASA's
// signature is what caught it.
I32 OS_CondVarTimedWait(U32 var_id, OS_time_t *abs_wakeup_time)
{
  OS_object_token_t token;
  I32 return_code;
  if (abs_wakeup_time == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_CONDVAR, var_id, &token);
  if (return_code == OS_SUCCESS)
    return_code = OS_CondVarTimedWait_Impl(&token, abs_wakeup_time);
  return return_code;
}

I32 OS_CondVarGetIdByName(U32 *var_id, U8 *var_name)
{
  I32 return_code;
  if (var_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (var_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdFindByName(OS_OBJECT_TYPE_OS_CONDVAR, var_name, var_id);
  return return_code;
}

I32 OS_CondVarGetInfo(U32 var_id, OS_condvar_prop_t *condvar_prop)
{
  OS_common_record_t *record;
  OS_common_record_t *base;
  OS_object_token_t token;
  I32 return_code;
  if (condvar_prop == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  memset(condvar_prop, 0, sizeof(OS_condvar_prop_t));
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_CONDVAR, var_id, &token);
  if (return_code == OS_SUCCESS) {
    // Base into a local first: indexing the parenthesised OS_global_*_table macro directly is
    // off by one in this compiler (docs/HOLYC_STRUCT_LIMITS.md).
    base = &OS_common_table[OS_CONDVAR_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
    // NOTE: this module uses snprintf("%s") where its four siblings use strncpy. Same
    // intent, different truncation rule -- snprintf always terminates, strncpy does not --
    // and translated as written rather than made uniform.
  snprintf(condvar_prop->name, OS_MAX_API_NAME, "%s", record->name_entry);
    condvar_prop->creator = record->creator;
    return_code = OS_CondVarGetInfo_Impl(&token, condvar_prop);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}
#endif
