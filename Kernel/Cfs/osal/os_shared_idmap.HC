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

// 1:1 HolyC translation of the types, constants and inline helpers in OSAL
// src/os/shared/inc/os-shared-idmap.h, plus the id helpers from src/os/inc/osapi-idmap.h.
//
// This is the foundation every OSAL resource module stands on: a 32-bit object id that encodes
// a TYPE in its upper 16 bits and a SERIAL in its lower 16, a flat table of records covering
// every resource type, and a token that carries the lock state of one operation on one record.
//
// osal_id_t IS A PLAIN uint32 here, not the struct-wrapped variant. OSAL selects between them on
// OSAL_OMIT_DEPRECATED (common_types.h:92), which is unset in this build -- the same flag that
// makes cFE use its SIMPLE resourceid, so the two are consistent by construction rather than by
// accident.
#ifndef OS_SHARED_IDMAP_HC
#define OS_SHARED_IDMAP_HC
#include "osapi_errors.HC"
// The array bounds every table below is sized by, generated from NASA's own defaults by
// tools/cfs/gen_osconfig.py beside the C the oracle compiles.
#include "osconfig.HC"
// --- osapi-idmap.h ---------------------------------------------------------------------------
#define OS_OBJECT_INDEX_MASK 0xFFFF
#define OS_OBJECT_TYPE_SHIFT 16
#define OS_OBJECT_TYPE_UNDEFINED   0x00
#define OS_OBJECT_TYPE_OS_TASK     0x01
#define OS_OBJECT_TYPE_OS_QUEUE    0x02
#define OS_OBJECT_TYPE_OS_COUNTSEM 0x03
#define OS_OBJECT_TYPE_OS_BINSEM   0x04
#define OS_OBJECT_TYPE_OS_MUTEX    0x05
#define OS_OBJECT_TYPE_OS_STREAM   0x06
#define OS_OBJECT_TYPE_OS_DIR      0x07
#define OS_OBJECT_TYPE_OS_TIMEBASE 0x08
#define OS_OBJECT_TYPE_OS_TIMECB   0x09
#define OS_OBJECT_TYPE_OS_MODULE   0x0A
#define OS_OBJECT_TYPE_OS_FILESYS  0x0B
#define OS_OBJECT_TYPE_OS_CONSOLE  0x0C
#define OS_OBJECT_TYPE_OS_CONDVAR  0x0D
#define OS_OBJECT_TYPE_OS_RWLOCK   0x0E
#define OS_OBJECT_TYPE_USER        0x10
// Compound literals in the C; functions here, as every other opaque-id sentinel has become.
#define OS_OBJECT_ID_UNDEFINED 0
#define OS_OBJECT_ID_RESERVED  0xFFFFFFFF
#define OS_OBJECT_CREATOR_ANY  OS_OBJECT_ID_UNDEFINED
// OSAL_INDEX_C(X) is ((osal_index_t)(X)), a cast to uint32. Note OSAL_INDEX_C(-1) is therefore
// 0xFFFFFFFF and is used as "no index yet" -- it must stay unsigned or the >= comparisons that
// bound the tables stop working.
#define OSAL_INDEX_C(X) ((X) & 0xFFFFFFFF)

U64 OS_ObjectIdToInteger(U32 object_id)
{
  return object_id;
}

U32 OS_ObjectIdFromInteger(U64 value)
{
  return value;
}

Bool OS_ObjectIdEqual(U32 object_id1, U32 object_id2)
{
  return OS_ObjectIdToInteger(object_id1) == OS_ObjectIdToInteger(object_id2);
}

Bool OS_ObjectIdDefined(U32 object_id)
{
  return OS_ObjectIdToInteger(object_id) != 0;
}
// --- os-shared-idmap.h -------------------------------------------------------------------------
class OS_common_record_t
{
  U8 *name_entry;
  U32 active_id;
  U32 creator;
  U16 refcount;
};
// The base of each type's slice of the one flat table. Cumulative, exactly as the C's enum is,
// so each depends on the previous -- which is why they are written in this order and why
// OS_MAX_TOTAL_RECORDS falls out of the last one.
#define OS_TASK_BASE     0
#define OS_QUEUE_BASE    (OS_TASK_BASE + OS_MAX_TASKS)
#define OS_BINSEM_BASE   (OS_QUEUE_BASE + OS_MAX_QUEUES)
#define OS_COUNTSEM_BASE (OS_BINSEM_BASE + OS_MAX_BIN_SEMAPHORES)
#define OS_MUTEX_BASE    (OS_COUNTSEM_BASE + OS_MAX_COUNT_SEMAPHORES)
#define OS_RWLOCK_BASE   (OS_MUTEX_BASE + OS_MAX_MUTEXES)
#define OS_STREAM_BASE   (OS_RWLOCK_BASE + OS_MAX_RWLOCKS)
#define OS_DIR_BASE      (OS_STREAM_BASE + OS_MAX_NUM_OPEN_FILES)
#define OS_TIMEBASE_BASE (OS_DIR_BASE + OS_MAX_NUM_OPEN_DIRS)
#define OS_TIMECB_BASE   (OS_TIMEBASE_BASE + OS_MAX_TIMEBASES)
#define OS_MODULE_BASE   (OS_TIMECB_BASE + OS_MAX_TIMERS)
#define OS_FILESYS_BASE  (OS_MODULE_BASE + OS_MAX_MODULES)
#define OS_CONSOLE_BASE  (OS_FILESYS_BASE + OS_MAX_FILE_SYSTEMS)
#define OS_CONDVAR_BASE  (OS_CONSOLE_BASE + OS_MAX_CONSOLES)
#define OS_MAX_TOTAL_RECORDS (OS_CONDVAR_BASE + OS_MAX_CONDVARS)
// Lock modes, in the C's enum order because the values are compared.
#define OS_LOCK_MODE_NONE      0
#define OS_LOCK_MODE_GLOBAL    1
#define OS_LOCK_MODE_REFCOUNT  2
#define OS_LOCK_MODE_EXCLUSIVE 3
#define OS_LOCK_MODE_RESERVED  4

class osal_key_t
{
  U32 key_value;
};

class OS_object_token_t
{
  I64 lock_mode;
  osal_key_t lock_key;
  U32 obj_type;
  U32 obj_idx;
  U32 obj_id;
};

class OS_object_iter_t
{
  OS_common_record_t *base;
  Bool (*match)(U8 *, OS_object_token_t *, OS_common_record_t *);
  U8 *arg;
  U32 limit;
  OS_object_token_t token;
};

U32 OS_ObjectIdFromToken(OS_object_token_t *token)
{
  return token->obj_id;
}

U32 OS_ObjectIndexFromToken(OS_object_token_t *token)
{
  return token->obj_idx;
}
// These three are static inline in the SHARED header despite the _Impl suffix -- they are not
// backend-provided, which is worth knowing because it cuts this file's real backend seam from
// seven functions to four.
U32 OS_ObjectIdToSerialNumber_Impl(U32 id)
{
  return OS_ObjectIdToInteger(id) & OS_OBJECT_INDEX_MASK;
}

U32 OS_ObjectIdToType_Impl(U32 id)
{
  return OS_ObjectIdToInteger(id) >> OS_OBJECT_TYPE_SHIFT;
}

U0 OS_ObjectIdCompose_Impl(U32 idtype, U32 idserial, U32 *result)
{
  *result = OS_ObjectIdFromInteger((idtype << OS_OBJECT_TYPE_SHIFT) | idserial);
}

Bool OS_ObjectIdIsValid(U32 object_id)
{
  U32 objtype = OS_ObjectIdToType_Impl(object_id);
  return objtype > OS_OBJECT_TYPE_UNDEFINED && objtype < OS_OBJECT_TYPE_USER;
}
#endif
