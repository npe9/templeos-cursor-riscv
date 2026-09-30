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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-task-affinity.c.
//
// OS_cpuset_t is passed BY VALUE to SetAffinity. That is safe here and it was checked rather
// than assumed: OS_MAX_CPUS is 1 in this configuration, so affinity_mask is
// (1 + 7) / 8 = 1 byte and the whole class is 1 byte -- well inside the 8 bytes HolyC can pass
// in a register. A configuration with more than 64 cores would make it 9 bytes and run into
// the limit in docs/HOLYC_STRUCT_LIMITS.md.
#ifndef OSAPI_TASK_AFFINITY_HC
#define OSAPI_TASK_AFFINITY_HC
#include "osconfig.HC"

class OS_cpuset_t
{
  U8 affinity_mask[(OS_MAX_CPUS + 7) / 8];
};

U32 OS_TaskAffinityGetCoresConfigured_Impl();
I32 OS_TaskAffinitySetAffinity_Impl(OS_object_token_t *token, OS_cpuset_t cpuset);
I32 OS_TaskAffinityGetAffinity_Impl(OS_object_token_t *token, OS_cpuset_t *cpuset);

// Asks the OS. Its sibling below returns what OSAL recorded at init instead.
U32 OS_TaskAffinityGetCoresConfigured()
{
  return OS_TaskAffinityGetCoresConfigured_Impl;
}

U32 OS_TaskAffinityCoresConfigured()
{
  return OS_SharedGlobalVars.CoresConfigured;
}

I32 OS_TaskAffinitySetAffinity(U32 task_id, OS_cpuset_t cpuset)
{
  I32 OsStatus;
  OS_object_token_t token;
  OsStatus = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TASK, task_id, &token);
  if (OsStatus == OS_SUCCESS)
    OsStatus = OS_TaskAffinitySetAffinity_Impl(&token, cpuset);
  // NASA releases UNCONDITIONALLY, outside the success branch. That is safe and deliberate,
  // not a bug, and it was checked: OS_ObjectIdGetById begins with
  // OS_ObjectIdTransactionInit, which starts with memset(token, 0, sizeof(*token)), so on
  // every failure path lock_mode is 0 -- and OS_LOCK_MODE_NONE is the FIRST enum member, so
  // it is 0, and OS_ObjectIdTransactionFinish returns immediately for it. The release is a
  // deterministic no-op rather than a read of uninitialised stack, which is also what makes
  // the bad-id path testable by a differential oracle at all.
  OS_ObjectIdRelease(&token);
  return OsStatus;
}

I32 OS_TaskAffinityGetAffinity(U32 task_id, OS_cpuset_t *cpuset)
{
  I32 OsStatus;
  OS_object_token_t token;
  OsStatus = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TASK, task_id, &token);
  if (OsStatus == OS_SUCCESS)
    OsStatus = OS_TaskAffinityGetAffinity_Impl(&token, cpuset);
  OS_ObjectIdRelease(&token);
  return OsStatus;
}
#endif
