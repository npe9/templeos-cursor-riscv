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

// 1:1 HolyC translation of the queue types, from OSAL src/os/shared/inc/os-shared-queue.h and
// src/os/inc/osapi-queue.h. Separate from the implementation so a backend can declare its
// _Impl functions first; see os_shared_errors.HC for why include order does that job here.
#ifndef OS_SHARED_QUEUE_HC
#define OS_SHARED_QUEUE_HC
#include "osconfig.HC"
// NOTE the name field is queue_name, not obj_name as in the semaphore family -- OS_OBJECT_INIT
// takes the field name as a macro argument precisely so it can differ per module.
class OS_queue_internal_record_t
{
  U8 queue_name[OS_MAX_API_NAME];
  I64 max_size;  // size_t
  I64 max_depth; // osal_blockcount_t, itself a size_t
};

class OS_queue_prop_t
{
  U8 name[OS_MAX_API_NAME];
  U32 creator;
};
#endif
