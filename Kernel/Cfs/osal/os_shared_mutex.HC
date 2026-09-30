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

// 1:1 HolyC translation of the mutex types, from OSAL os-shared-mutex.h/osapi-mutex.h. Separate from the
// implementation so a backend can declare its _Impl functions before seeing it -- the same
// header/implementation split the C has, with include order doing the linker's job.
#ifndef OS_SHARED_MUTEX_HC
#define OS_SHARED_MUTEX_HC
#include "osconfig.HC"
class OS_mutex_internal_record_t
{
  U8 obj_name[OS_MAX_API_NAME];
  // The task that most recently took the mutex, OS_OBJECT_ID_UNDEFINED when not held.
  // Was MISSING from this translation, and with it the whole of the ownership tracking in
  // OS_MutSemGive/Take -- found by tools/cfs/check_structs.py, not by any behavioural gate.
  U32 last_owner;
};

class OS_mut_sem_prop_t
{
  U8 name[OS_MAX_API_NAME];
  U32 creator;

};
#endif
