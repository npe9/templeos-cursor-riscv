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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-idmap.c -- the object-table and
// id-mapping core that every OSAL resource module stands on. 38 functions, 1,501 lines of C.
//
// WHAT IT DOES. One flat table of 316 records covers every resource type; an object id encodes
// the type in its upper 16 bits and a serial in its lower 16; and a TOKEN carries the lock
// state of one operation on one record from start to finish. Allocation walks for a free slot
// from the last id issued, so ids cycle rather than repeat immediately -- which is what makes a
// stale id detectable instead of silently aliasing a new object.
//
// ONLY FOUR BACKEND CALLS, once you notice that OS_ObjectIdToType_Impl, ToSerialNumber_Impl and
// Compose_Impl are static inline in the shared header despite their names: OS_Lock_Global_Impl,
// OS_Unlock_Global_Impl, OS_WaitForStateChange_Impl and OS_TaskGetId_Impl.
//
// THREE COMPILER CONSTRAINTS SHAPE THE CODE, each measured (docs/HOLYC_STRUCT_LIMITS.md):
//   - a function pointer held in a class member cannot be called in place, so every indirect
//     call copies it to a local first;
//   - `*dst = *src` on a class larger than 8 bytes copies only 8, so OS_ObjectIdTransferToken
//     copies field by field;
//   - OS_DEBUG(...) is empty in this configuration (OSAL_CONFIG_DEBUG_PRINTF defaults FALSE),
//     so the C's diagnostic calls become comments and those error paths are SILENT here. That
//     is NASA's configuration, not a shortcut, but it is worth knowing when debugging a lock.
#ifndef OSAPI_IDMAP_HC
#define OSAPI_IDMAP_HC
#include "os_shared_idmap.HC"
#include "osapi_common.HC"
#include "../cfe/cfe_xlat_libc.HC"
// --- osapi-idmap.c ----------------------------------------------------------------------------
#define OS_LOCK_KEY_FIXED_VALUE 0x4D000000

class OS_creator_filter_t
{
  U32 creator_id;
  U0 (*user_callback)(U32, U8 *);
  U8 *user_arg;
};

// Tables where the OS object information is stored
OS_common_record_t OS_common_table[OS_MAX_TOTAL_RECORDS];

class OS_objtype_state_t
{
  U32 last_id_issued;    // last successfully-issued object ID of each type
  U32 transaction_count; // individual lock/unlock cycles on this type
  osal_key_t owner_key;  // the key required to unlock this table
};

OS_objtype_state_t OS_objtype_state[OS_OBJECT_TYPE_USER];
// The C has `OS_common_record_t *const OS_global_task_table = &OS_common_table[OS_TASK_BASE];`
// and thirteen more. HolyC cannot initialise a global pointer from the address of another
// global's element, so they are macros -- same address, computed at each use instead of once.
#define OS_global_task_table      (&OS_common_table[OS_TASK_BASE])
#define OS_global_queue_table     (&OS_common_table[OS_QUEUE_BASE])
#define OS_global_bin_sem_table   (&OS_common_table[OS_BINSEM_BASE])
#define OS_global_count_sem_table (&OS_common_table[OS_COUNTSEM_BASE])
#define OS_global_mutex_table     (&OS_common_table[OS_MUTEX_BASE])
#define OS_global_rwlock_table    (&OS_common_table[OS_RWLOCK_BASE])
#define OS_global_stream_table    (&OS_common_table[OS_STREAM_BASE])
#define OS_global_dir_table       (&OS_common_table[OS_DIR_BASE])
#define OS_global_timebase_table  (&OS_common_table[OS_TIMEBASE_BASE])
#define OS_global_timecb_table    (&OS_common_table[OS_TIMECB_BASE])
#define OS_global_module_table    (&OS_common_table[OS_MODULE_BASE])
#define OS_global_filesys_table   (&OS_common_table[OS_FILESYS_BASE])
#define OS_global_console_table   (&OS_common_table[OS_CONSOLE_BASE])
#define OS_global_condvar_table   (&OS_common_table[OS_CONDVAR_BASE])
// --- the backend seam ---------------------------------------------------------------------------
U0 OS_Lock_Global_Impl(U32 idtype);
U0 OS_Unlock_Global_Impl(U32 idtype);
U0 OS_WaitForStateChange_Impl(U32 idtype, U32 attempts);
U32 OS_TaskGetId_Impl();
U32 OS_TaskGetId();
// Forward declarations: the C gets these from os-shared-idmap.h, and HolyC is single-pass.
U0 OS_Lock_Global(OS_object_token_t *token);
U0 OS_Unlock_Global(OS_object_token_t *token);
U0 OS_WaitForStateChange(OS_object_token_t *token, U32 attempts);
U0 OS_ObjectIdTransactionFinish(OS_object_token_t *token, U32 *final_id);
I32 OS_ObjectIdFinalizeNew(I32 operation_status, OS_object_token_t *token, U32 *outid);
U0 OS_ObjectIdRelease(OS_object_token_t *token);
U32 OS_GetBaseForObjectType(U32 idtype);
U32 OS_GetMaxForObjectType(U32 idtype);
I32 OS_ObjectIdToArrayIndex(U32 idtype, U32 object_id, U32 *ArrayIndex);

I32 OS_ObjectIdInit()
{
  memset(OS_common_table, 0, sizeof(OS_common_table));
  memset(OS_objtype_state, 0, sizeof(OS_objtype_state));
  return OS_SUCCESS;
}

U32 OS_GetMaxForObjectType(U32 idtype)
{
  switch (idtype) {
    case OS_OBJECT_TYPE_OS_TASK:
      return OS_MAX_TASKS;
    case OS_OBJECT_TYPE_OS_QUEUE:
      return OS_MAX_QUEUES;
    case OS_OBJECT_TYPE_OS_BINSEM:
      return OS_MAX_BIN_SEMAPHORES;
    case OS_OBJECT_TYPE_OS_COUNTSEM:
      return OS_MAX_COUNT_SEMAPHORES;
    case OS_OBJECT_TYPE_OS_MUTEX:
      return OS_MAX_MUTEXES;
    case OS_OBJECT_TYPE_OS_RWLOCK:
      return OS_MAX_RWLOCKS;
    case OS_OBJECT_TYPE_OS_STREAM:
      return OS_MAX_NUM_OPEN_FILES;
    case OS_OBJECT_TYPE_OS_DIR:
      return OS_MAX_NUM_OPEN_DIRS;
    case OS_OBJECT_TYPE_OS_TIMEBASE:
      return OS_MAX_TIMEBASES;
    case OS_OBJECT_TYPE_OS_TIMECB:
      return OS_MAX_TIMERS;
    case OS_OBJECT_TYPE_OS_MODULE:
      return OS_MAX_MODULES;
    case OS_OBJECT_TYPE_OS_FILESYS:
      return OS_MAX_FILE_SYSTEMS;
    case OS_OBJECT_TYPE_OS_CONSOLE:
      return OS_MAX_CONSOLES;
    case OS_OBJECT_TYPE_OS_CONDVAR:
      return OS_MAX_CONDVARS;
    default:
      return 0;
  }
}

U32 OS_GetBaseForObjectType(U32 idtype)
{
  switch (idtype) {
    case OS_OBJECT_TYPE_OS_TASK:
      return OS_TASK_BASE;
    case OS_OBJECT_TYPE_OS_QUEUE:
      return OS_QUEUE_BASE;
    case OS_OBJECT_TYPE_OS_BINSEM:
      return OS_BINSEM_BASE;
    case OS_OBJECT_TYPE_OS_COUNTSEM:
      return OS_COUNTSEM_BASE;
    case OS_OBJECT_TYPE_OS_MUTEX:
      return OS_MUTEX_BASE;
    case OS_OBJECT_TYPE_OS_RWLOCK:
      return OS_RWLOCK_BASE;
    case OS_OBJECT_TYPE_OS_STREAM:
      return OS_STREAM_BASE;
    case OS_OBJECT_TYPE_OS_DIR:
      return OS_DIR_BASE;
    case OS_OBJECT_TYPE_OS_TIMEBASE:
      return OS_TIMEBASE_BASE;
    case OS_OBJECT_TYPE_OS_TIMECB:
      return OS_TIMECB_BASE;
    case OS_OBJECT_TYPE_OS_MODULE:
      return OS_MODULE_BASE;
    case OS_OBJECT_TYPE_OS_FILESYS:
      return OS_FILESYS_BASE;
    case OS_OBJECT_TYPE_OS_CONSOLE:
      return OS_CONSOLE_BASE;
    case OS_OBJECT_TYPE_OS_CONDVAR:
      return OS_CONDVAR_BASE;
    default:
      return 0;
  }
}

Bool OS_ForEachFilterCreator(U8 *ref, OS_object_token_t *token, OS_common_record_t *obj)
{
  OS_creator_filter_t *filter = ref(OS_creator_filter_t *);
  // Check if the obj is a match for the creator
  return OS_ObjectIdIsValid(obj->active_id) &&
         (OS_ObjectIdEqual(filter->creator_id, OS_OBJECT_CREATOR_ANY) ||
          OS_ObjectIdEqual(obj->creator, filter->creator_id));
}

I32 OS_ForEachDoCallback(U32 obj_id, U8 *ref)
{
  OS_creator_filter_t *filter = ref(OS_creator_filter_t *);
  U0 (*cb)(U32, U8 *);
  // Just invoke the user callback. Copied to a local first: a function pointer in a class
  // member cannot be called in place in HolyC.
  cb = filter->user_callback;
  cb(obj_id, filter->user_arg);
  return OS_SUCCESS;
}

OS_common_record_t *OS_ObjectIdGlobalFromToken(OS_object_token_t *token)
{
  U32 base_idx = OS_GetBaseForObjectType(token->obj_type);
  return &OS_common_table[base_idx + token->obj_idx];
}

Bool OS_ObjectNameMatch(U8 *ref, OS_object_token_t *token, OS_common_record_t *obj)
{
  return obj->name_entry != NULL && strcmp(ref, obj->name_entry) == 0;
}

I32 OS_ObjectIdTransactionInit(I64 lock_mode, U32 idtype, OS_object_token_t *token)
{
  memset(token, 0, sizeof(OS_object_token_t));
  // Transactions are only allowed once the API is initialised, and only an EXCLUSIVE one
  // (i.e. a delete) is allowed while shutting down.
  if (OS_SharedGlobalVars.GlobalState != OS_INIT_MAGIC_NUMBER &&
      OS_SharedGlobalVars.GlobalState != OS_SHUTDOWN_MAGIC_NUMBER)
    return OS_ERROR;
  if (OS_SharedGlobalVars.GlobalState == OS_SHUTDOWN_MAGIC_NUMBER &&
      lock_mode != OS_LOCK_MODE_EXCLUSIVE)
    return OS_ERR_INCORRECT_OBJ_STATE;
  if (OS_GetMaxForObjectType(idtype) == 0)
    return OS_ERR_INVALID_ID;
  token->lock_mode = lock_mode;
  token->obj_type = idtype;
  token->obj_idx = OSAL_INDEX_C(-1);
  if (lock_mode != OS_LOCK_MODE_NONE)
    OS_Lock_Global(token);
  return OS_SUCCESS;
}

U0 OS_ObjectIdTransactionCancel(OS_object_token_t *token)
{
  if (token->lock_mode != OS_LOCK_MODE_NONE) {
    OS_Unlock_Global(token);
    token->lock_mode = OS_LOCK_MODE_NONE;
  }
}

I32 OS_ObjectIdConvertToken(OS_object_token_t *token)
{
  I32 return_code = OS_ERROR;
  U32 attempts = 0;
  OS_common_record_t *obj;
  U32 expected_id;
  obj = OS_ObjectIdGlobalFromToken(token);
  expected_id = OS_ObjectIdFromToken(token);
  if (!OS_ObjectIdIsValid(expected_id))
    return OS_ERR_INCORRECT_OBJ_STATE;
  // A RESERVED lock is confirming a record someone else already reserved.
  if (token->lock_mode == OS_LOCK_MODE_RESERVED)
    expected_id = OS_OBJECT_ID_RESERVED;
  while (TRUE) {
    // Validate the integrity of the ID
    if (OS_ObjectIdEqual(obj->active_id, expected_id)) {
      if (token->lock_mode == OS_LOCK_MODE_EXCLUSIVE) {
        // Reserve the record so no one else can take it while we wait for the refcount
        if (!OS_ObjectIdEqual(expected_id, OS_OBJECT_ID_RESERVED)) {
          expected_id = OS_OBJECT_ID_RESERVED;
          obj->active_id = expected_id;
        }
        if (obj->refcount == 0) {
          return_code = OS_SUCCESS;
          break;
        }
      } else {
        return_code = OS_SUCCESS;
        break;
      }
    } else if (token->lock_mode == OS_LOCK_MODE_NONE ||
               !OS_ObjectIdEqual(obj->active_id, OS_OBJECT_ID_RESERVED)) {
      // Not an ID match and not RESERVED - fail out
      return_code = OS_ERR_INVALID_ID;
      break;
    }
    // Give up after a bounded number of attempts rather than spinning forever
    ++attempts;
    if (attempts >= 5) {
      return_code = OS_ERR_OBJECT_IN_USE;
      break;
    }
    OS_WaitForStateChange(token, attempts);
  }
  if (token->lock_mode != OS_LOCK_MODE_NONE) {
    if (return_code == OS_SUCCESS) {
      // always increment the refcount, which means a task is actively using the record
      ++obj->refcount;
      if (token->lock_mode == OS_LOCK_MODE_REFCOUNT ||
          token->lock_mode == OS_LOCK_MODE_EXCLUSIVE)
        OS_Unlock_Global(token);
    } else if (token->lock_mode == OS_LOCK_MODE_EXCLUSIVE &&
               OS_ObjectIdEqual(expected_id, OS_OBJECT_ID_RESERVED)) {
      // Put the ID back the way it was: this attempt reserved it and then failed
      obj->active_id = OS_ObjectIdFromToken(token);
    }
  }
  return return_code;
}

I32 OS_ObjectIdFindNextMatch(Bool (*MatchFunc)(U8 *, OS_object_token_t *, OS_common_record_t *),
                             U8 *arg, OS_object_token_t *token)
{
  I32 return_code;
  U32 obj_count;
  OS_common_record_t *base;
  OS_common_record_t *record;
  return_code = OS_ERR_NAME_NOT_FOUND;
  base = &OS_common_table[OS_GetBaseForObjectType(token->obj_type)];
  obj_count = OS_GetMaxForObjectType(token->obj_type);
  token->obj_id = OS_OBJECT_ID_UNDEFINED;
  while (TRUE) {
    ++token->obj_idx;
    if (token->obj_idx >= obj_count)
      break;
    record = &base[OS_ObjectIndexFromToken(token)];
    if (OS_ObjectIdDefined(record->active_id) && MatchFunc(arg, token, record)) {
      return_code = OS_SUCCESS;
      token->obj_id = record->active_id;
      break;
    }
  }
  return return_code;
}

I32 OS_ObjectIdFindNextFree(OS_object_token_t *token)
{
  U32 max_id;
  U32 base_id;
  U32 local_id = 0;
  U32 serial;
  U32 i;
  I32 return_code;
  OS_common_record_t *obj = NULL;
  OS_objtype_state_t *objtype_state = NULL;
  base_id = OS_GetBaseForObjectType(token->obj_type);
  max_id = OS_GetMaxForObjectType(token->obj_type);
  if (max_id == 0) {
    // if the max id is zero, then this build of OSAL does not include this object type
    return_code = OS_ERR_NOT_IMPLEMENTED;
    serial = 0;
  } else {
    return_code = OS_ERR_NO_FREE_IDS;
    objtype_state = &OS_objtype_state[token->obj_type];
    serial = OS_ObjectIdToSerialNumber_Impl(objtype_state->last_id_issued);
  }
  for (i = 0; i < max_id; ++i) {
    ++serial;
    local_id = serial % max_id;
    if (serial >= OS_OBJECT_INDEX_MASK) {
      // reset to beginning of ID space
      serial = local_id;
    }
    obj = &OS_common_table[local_id + base_id];
    if (!OS_ObjectIdDefined(obj->active_id)) {
      return_code = OS_SUCCESS;
      break;
    }
  }
  if (return_code == OS_SUCCESS) {
    token->obj_idx = OSAL_INDEX_C(local_id);
    OS_ObjectIdCompose_Impl(token->obj_type, serial, &token->obj_id);
    // Ensure any data in the record has been cleared
    obj->active_id = token->obj_id;
    obj->name_entry = NULL;
    obj->creator = OS_TaskGetId;
    obj->refcount = 0;
    // preemptively update the last id issued
    objtype_state->last_id_issued = token->obj_id;
  }
  if (return_code != OS_SUCCESS) {
    token->obj_idx = OSAL_INDEX_C(-1);
    token->obj_id = OS_OBJECT_ID_UNDEFINED;
  }
  return return_code;
}

// Locks the global table identified by "idtype"
U0 OS_Lock_Global(OS_object_token_t *token)
{
  U32 self_task_id;
  OS_objtype_state_t *objtype;
  if (token->obj_type < OS_OBJECT_TYPE_USER && token->lock_mode != OS_LOCK_MODE_NONE) {
    objtype = &OS_objtype_state[token->obj_type];
    self_task_id = OS_TaskGetId_Impl;
    OS_Lock_Global_Impl(token->obj_type);
    if (!OS_ObjectIdIsValid(self_task_id)) {
      // nonzero, but also won't alias a known task
      self_task_id = OS_OBJECT_ID_RESERVED;
    }
    // The key is the task id mixed with a per-type counter, so a mismatched unlock is
    // detectable rather than silently succeeding.
    token->lock_key.key_value =
        OS_LOCK_KEY_FIXED_VALUE |
        ((OS_ObjectIdToInteger(self_task_id) ^ objtype->transaction_count) & 0xFFFFFF);
    ++objtype->transaction_count;
    if (objtype->owner_key.key_value != 0) {
      // this is almost certainly a bug -- OS_DEBUG, which is empty in this configuration
    } else {
      objtype->owner_key = token->lock_key;
    }
  } else {
    // OS_DEBUG("ERROR: cannot lock global %u for mode %u") -- empty in this configuration
  }
}

// Unlocks the global table identified by "idtype"
U0 OS_Unlock_Global(OS_object_token_t *token)
{
  OS_objtype_state_t *objtype;
  if (token->obj_type < OS_OBJECT_TYPE_USER && token->lock_mode != OS_LOCK_MODE_NONE) {
    objtype = &OS_objtype_state[token->obj_type];
    if ((objtype->owner_key.key_value & 0xFF000000) != OS_LOCK_KEY_FIXED_VALUE ||
        objtype->owner_key.key_value != token->lock_key.key_value) {
      // this is almost certainly a bug -- OS_DEBUG, empty in this configuration
    }
    objtype->owner_key.key_value = 0; // OS_LOCK_KEY_INVALID
    token->lock_key.key_value = 0;
    OS_Unlock_Global_Impl(token->obj_type);
  } else {
    // OS_DEBUG("ERROR: cannot unlock global %u for mode %u") -- empty here
  }
}

U0 OS_WaitForStateChange(OS_object_token_t *token, U32 attempts)
{
  osal_key_t saved_unlock_key;
  OS_objtype_state_t *objtype;
  objtype = &OS_objtype_state[token->obj_type];
  saved_unlock_key = objtype->owner_key;
  // temporarily release the table
  objtype->owner_key.key_value = 0;
  OS_WaitForStateChange_Impl(token->obj_type, attempts);
  // Re-acquire the table. cppcheck-suppress redundantAssignment
  objtype->owner_key = saved_unlock_key;
}

I32 OS_ObjectIdFinalizeNew(I32 operation_status, OS_object_token_t *token, U32 *outid)
{
  U32 final_id;
  // if operation was unsuccessful, then clear the active_id
  if (operation_status == OS_SUCCESS)
    final_id = token->obj_id;
  else
    final_id = OS_OBJECT_ID_UNDEFINED;
  // Either way we must unlock the object type
  OS_ObjectIdTransactionFinish(token, &final_id);
  // Give event callback to the application
  if (operation_status == OS_SUCCESS)
    OS_NotifyEvent(OS_EVENT_RESOURCE_CREATED, token->obj_id, NULL);
  if (outid != NULL) {
    // always write the final value to the output buffer
    *outid = final_id;
  }
  return operation_status;
}

I32 OS_ObjectIdFinalizeDelete(I32 operation_status, OS_object_token_t *token)
{
  U32 final_id;
  // Clear the OSAL ID if successful - this returns the record to the pool
  if (operation_status == OS_SUCCESS)
    final_id = OS_OBJECT_ID_UNDEFINED;
  else
    final_id = token->obj_id; // this restores the original ID
  OS_ObjectIdTransactionFinish(token, &final_id);
  if (operation_status == OS_SUCCESS)
    OS_NotifyEvent(OS_EVENT_RESOURCE_DELETED, token->obj_id, NULL);
  return operation_status;
}

I32 OS_ObjectIdGetBySearch(I64 lock_mode, U32 idtype,
                           Bool (*MatchFunc)(U8 *, OS_object_token_t *, OS_common_record_t *),
                           U8 *arg, OS_object_token_t *token)
{
  I32 return_code;
  OS_ObjectIdTransactionInit(lock_mode, idtype, token);
  return_code = OS_ObjectIdFindNextMatch(MatchFunc, arg, token);
  if (return_code == OS_SUCCESS) {
    // The match function may have left the token pointing at a record; confirm it.
    return_code = OS_ObjectIdConvertToken(token);
  } else {
    OS_ObjectIdTransactionCancel(token);
  }
  return return_code;
}

I32 OS_ObjectIdGetByName(I64 lock_mode, U32 idtype, U8 *name, OS_object_token_t *token)
{
  return OS_ObjectIdGetBySearch(lock_mode, idtype, &OS_ObjectNameMatch, name, token);
}

I32 OS_ObjectIdFindByName(U32 idtype, U8 *name, U32 *object_id)
{
  I32 return_code;
  OS_object_token_t token;
  // ARGCHECK(name, OS_ERR_NAME_NOT_FOUND) and
  // LENGTHCHECK(name, OS_MAX_API_NAME, OS_ERR_NAME_TOO_LONG). LENGTHCHECK is
  // ARGCHECK(memchr(str, 0, len), ...) -- the name must be NUL-terminated WITHIN the limit,
  // which is a length check written as a search.
  //
  // ARGCHECK IS SILENT. Unlike BUGCHECK it only returns -- no OS_printf. The first draft
  // logged here and the transcript caught it: NASA's C prints no marker before byname_null.
  // The distinction is deliberate upstream, an invalid argument being a caller error and a
  // failed BUGCHECK being "almost certainly a bug" in OSAL itself.
  if (name == NULL)
    return OS_ERR_NAME_NOT_FOUND;
  if (memchr(name, 0, OS_MAX_API_NAME) == NULL)
    return OS_ERR_NAME_TOO_LONG;
  return_code = OS_ObjectIdGetByName(OS_LOCK_MODE_GLOBAL, idtype, name, &token);
  if (return_code == OS_SUCCESS) {
    *object_id = token.obj_id;
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_ObjectIdGetById(I64 lock_mode, U32 idtype, U32 id, OS_object_token_t *token)
{
  I32 return_code;
  return_code = OS_ObjectIdTransactionInit(lock_mode, idtype, token);
  if (return_code != OS_SUCCESS)
    return return_code;
  return_code = OS_ObjectIdToArrayIndex(idtype, id, &token->obj_idx);
  if (return_code == OS_SUCCESS) {
    token->obj_id = id;
    return_code = OS_ObjectIdConvertToken(token);
  }
  if (return_code != OS_SUCCESS)
    OS_ObjectIdTransactionCancel(token);
  return return_code;
}

U0 OS_ObjectIdTransactionFinish(OS_object_token_t *token, U32 *final_id)
{
  OS_common_record_t *record;
  if (token->lock_mode == OS_LOCK_MODE_NONE) {
    // nothing to do
    return;
  }
  record = OS_ObjectIdGlobalFromToken(token);
  // re-acquire global table lock to adjust refcount
  if (token->lock_mode == OS_LOCK_MODE_EXCLUSIVE || token->lock_mode == OS_LOCK_MODE_REFCOUNT)
    OS_Lock_Global(token);
  if (record->refcount > 0)
    --record->refcount;
  if (final_id != NULL) {
    record->active_id = *final_id;
  } else if (token->lock_mode == OS_LOCK_MODE_EXCLUSIVE) {
    // Exclusive locks reserved the ID; put it back
    record->active_id = token->obj_id;
  }
  // always unlock (this also covers OS_LOCK_MODE_GLOBAL case)
  OS_Unlock_Global(token);
  token->lock_mode = OS_LOCK_MODE_NONE;
}

U0 OS_ObjectIdRelease(OS_object_token_t *token)
{
  OS_ObjectIdTransactionFinish(token, NULL);
}

I32 OS_ObjectIdAllocateNew(U32 idtype, U8 *name, OS_object_token_t *token)
{
  I32 return_code;
  // No new objects once shutdown has started
  if (OS_SharedGlobalVars.GlobalState == OS_SHUTDOWN_MAGIC_NUMBER)
    return OS_ERR_INCORRECT_OBJ_STATE;
  return_code = OS_ObjectIdTransactionInit(OS_LOCK_MODE_EXCLUSIVE, idtype, token);
  if (return_code != OS_SUCCESS)
    return return_code;
  // A name that already exists is a failure; no name at all skips the search.
  if (name != NULL)
    return_code = OS_ObjectIdFindNextMatch(&OS_ObjectNameMatch, name, token);
  else
    return_code = OS_ERR_NAME_NOT_FOUND;
  if (return_code == OS_SUCCESS)
    return_code = OS_ERR_NAME_TAKEN;
  else
    return_code = OS_ObjectIdFindNextFree(token);
  // If allocation failed, abort now - no ID was allocated
  if (return_code != OS_SUCCESS) {
    OS_ObjectIdTransactionCancel(token);
    return return_code;
  } else {
    return_code = OS_NotifyEvent(OS_EVENT_RESOURCE_ALLOCATED, token->obj_id, NULL);
  }
  if (return_code == OS_SUCCESS)
    return_code = OS_ObjectIdConvertToken(token);
  if (return_code != OS_SUCCESS)
    return_code = OS_ObjectIdFinalizeNew(return_code, token, NULL);
  return return_code;
}

// Transfer ownership of a token to another buffer
U0 OS_ObjectIdTransferToken(OS_object_token_t *token_from, OS_object_token_t *token_to)
{
  // FIELD BY FIELD, not `*token_to = *token_from`. That form copies only the first eight bytes
  // of a class through pointers in this compiler -- an open defect, see
  // docs/HOLYC_STRUCT_LIMITS.md. A token is twenty bytes, so the C's one-line copy would have
  // transferred the lock mode and lost the id, the index and the key.
  token_to->lock_mode = token_from->lock_mode;
  token_to->lock_key = token_from->lock_key;
  token_to->obj_type = token_from->obj_type;
  token_to->obj_idx = token_from->obj_idx;
  token_to->obj_id = token_from->obj_id;
  // ensure the old token no longer holds the lock
  token_from->lock_mode = OS_LOCK_MODE_NONE;
}

// Start the process of iterating through OSAL objects
I32 OS_ObjectIdIteratorInit(Bool (*matchfunc)(U8 *, OS_object_token_t *, OS_common_record_t *),
                            U8 *matcharg, U32 objtype, OS_object_iter_t *iter)
{
  iter->match = matchfunc;
  iter->arg = matcharg;
  iter->limit = OS_GetMaxForObjectType(objtype);
  iter->base = &OS_common_table[OS_GetBaseForObjectType(objtype)];
  return OS_ObjectIdTransactionInit(OS_LOCK_MODE_GLOBAL, objtype, &iter->token);
}

// Match function to iterate only active objects
Bool OS_ObjectFilterActive(U8 *ref, OS_object_token_t *token, OS_common_record_t *obj)
{
  return OS_ObjectIdDefined(obj->active_id);
}

I32 OS_ObjectIdIterateActive(U32 objtype, OS_object_iter_t *iter)
{
  return OS_ObjectIdIteratorInit(&OS_ObjectFilterActive, NULL, objtype, iter);
}

// Move iterator to the next entry
Bool OS_ObjectIdIteratorGetNext(OS_object_iter_t *iter)
{
  OS_common_record_t *record;
  Bool got_next;
  Bool (*mf)(U8 *, OS_object_token_t *, OS_common_record_t *);
  got_next = FALSE;
  iter->token.obj_id = OS_OBJECT_ID_UNDEFINED;
  do {
    ++iter->token.obj_idx;
    if (iter->token.obj_idx >= iter->limit)
      break;
    record = &iter->base[OS_ObjectIndexFromToken(&iter->token)];
    // Copied to a local: a function pointer in a class member cannot be called in place.
    mf = iter->match;
    if (mf == NULL || mf(iter->arg, &iter->token, record)) {
      iter->token.obj_id = record->active_id;
      got_next = TRUE;
    }
  } while (!got_next);
  return got_next;
}

// Release iterator resources
U0 OS_ObjectIdIteratorDestroy(OS_object_iter_t *iter)
{
  OS_ObjectIdTransactionCancel(&iter->token);
}

// Call a handler function on an iterator object ID. The global is released around the call so
// the handler may itself take locks.
I32 OS_ObjectIdIteratorProcessEntry(OS_object_iter_t *iter, I32 (*func)(U32, U8 *))
{
  I32 status;
  OS_Unlock_Global(&iter->token);
  status = func(OS_ObjectIdFromToken(&iter->token), iter->arg);
  OS_Lock_Global(&iter->token);
  return status;
}

I32 OS_ConvertToArrayIndex(U32 object_id, U32 *ArrayIndex)
{
  // pass to conversion routine with undefined type
  return OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_UNDEFINED, object_id, ArrayIndex);
}

U0 OS_ForEachObjectOfType(U32 objtype, U32 creator_id, U0 (*callback_ptr)(U32, U8 *),
                          U8 *callback_arg)
{
  OS_object_iter_t iter;
  OS_creator_filter_t filter;
  filter.creator_id = creator_id;
  filter.user_callback = callback_ptr;
  filter.user_arg = callback_arg;
  if (OS_ObjectIdIteratorInit(&OS_ForEachFilterCreator, &filter, objtype, &iter) == OS_SUCCESS) {
    while (OS_ObjectIdIteratorGetNext(&iter))
      OS_ObjectIdIteratorProcessEntry(&iter, &OS_ForEachDoCallback);
    OS_ObjectIdIteratorDestroy(&iter);
  }
}

U0 OS_ForEachObject(U32 creator_id, U0 (*callback_ptr)(U32, U8 *), U8 *callback_arg)
{
  U32 idtype;
  for (idtype = 0; idtype < OS_OBJECT_TYPE_USER; ++idtype)
    OS_ForEachObjectOfType(idtype, creator_id, callback_ptr, callback_arg);
}

U32 OS_IdentifyObject(U32 object_id)
{
  return OS_ObjectIdToType_Impl(object_id);
}

I32 OS_GetResourceName(U32 object_id, U8 *buffer, I64 buffer_size)
{
  OS_common_record_t *record;
  I32 return_code;
  I64 name_len;
  OS_object_token_t token;
  // sanity check the passed-in buffer and size. OS_CHECK_SIZE is
  // ARGCHECK((val) > 0 && (val) < (UINT32_MAX / 2), OS_ERR_INVALID_SIZE).
  if (buffer == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // OS_CHECK_SIZE is an ARGCHECK, so it is SILENT -- unlike OS_CHECK_POINTER above it, which
  // is a BUGCHECK and logs. Two checks, two lines apart, with different reporting behaviour.
  if (!(buffer_size > 0 && buffer_size < 0x7FFFFFFF))
    return OS_ERR_INVALID_SIZE;
  // Initialise to an empty string, so a failure leaves a usable buffer
  buffer[0] = 0;
  return_code =
      OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_ObjectIdToType_Impl(object_id), object_id, &token);
  if (return_code == OS_SUCCESS) {
    record = OS_ObjectIdGlobalFromToken(&token);
    if (record->name_entry != NULL) {
      name_len = OS_strnlen(record->name_entry, buffer_size);
      if (buffer_size <= name_len) {
        // indicates the name does not fit into supplied buffer
        return_code = OS_ERR_NAME_TOO_LONG;
        name_len = buffer_size - 1;
      }
      memcpy(buffer, record->name_entry, name_len);
      buffer[name_len] = 0;
    }
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_ObjectIdToArrayIndex(U32 idtype, U32 object_id, U32 *ArrayIndex)
{
  U32 max_id;
  U32 obj_index;
  U32 actual_type;
  I32 return_code;
  // Check Parameters
  if (ArrayIndex == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  obj_index = OS_ObjectIdToSerialNumber_Impl(object_id);
  actual_type = OS_ObjectIdToType_Impl(object_id);
  // If requested by the caller, enforce that the ID is of the correct type
  if (idtype != OS_OBJECT_TYPE_UNDEFINED && actual_type != idtype) {
    return_code = OS_ERR_INVALID_ID;
  } else {
    max_id = OS_GetMaxForObjectType(actual_type);
    if (max_id == 0)
      return_code = OS_ERR_INVALID_ID;
    else {
      return_code = OS_SUCCESS;
      *ArrayIndex = OSAL_INDEX_C(obj_index % max_id);
    }
  }
  return return_code;
}
#endif
