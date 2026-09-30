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

// 1:1 HolyC translation of the task types: the internal record from OSAL
// src/os/shared/inc/os-shared-task.h and the public property struct from
// src/os/inc/osapi-task.h. Separate from the implementation so a backend can declare its _Impl
// functions first; see os_shared_errors.HC for why include order does that job here.
#ifndef OS_SHARED_TASK_HC
#define OS_SHARED_TASK_HC
#include "osconfig.HC"
// --- osapi-task.h ------------------------------------------------------------------------------
// osal_priority_t is uint8_t and osal_stackptr_t is void *. osal_task_entry is
//     typedef void ((*osal_task_entry)(void));
// HolyC has no typedef, so every use is spelled out as U0 (*name)() -- the same thing the
// translation already does for OS_ObjectMatchFunc_t in osapi_idmap.HC.
class OS_task_prop_t
{
  U8 name[OS_MAX_API_NAME];
  U32 creator;
  I64 stack_size; // size_t
  U8 priority;    // osal_priority_t
};
// --- os-shared-task.h --------------------------------------------------------------------------
class OS_task_internal_record_t
{
  U8 task_name[OS_MAX_API_NAME];
  I64 stack_size; // size_t
  U8 priority;    // osal_priority_t
  U0 (*entry_function_pointer)();
  U0 (*delete_hook_pointer)();
  U8 *entry_arg;      // void *
  U8 *stack_pointer;  // osal_stackptr_t, itself a void *
};
#endif
