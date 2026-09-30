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

// 1:1 HolyC translation of the counting-semaphore types: the internal record from OSAL
// src/os/shared/inc/os-shared-countsem.h and the public property struct from
// src/os/inc/osapi-countsem.h.
//
// Separate from the implementation for the same reason os_shared_errors.HC is: a BACKEND has to
// see these types to declare its own _Impl functions, and HolyC is single-pass, so the types
// must be available before either side of the seam is written. In C the header does that job;
// here the include order does.
#ifndef OS_SHARED_COUNTSEM_HC
#define OS_SHARED_COUNTSEM_HC
#include "osconfig.HC"
// --- os-shared-countsem.h ----------------------------------------------------------------------
class OS_count_sem_internal_record_t
{
  U8 obj_name[OS_MAX_API_NAME];
};
// --- osapi-countsem.h --------------------------------------------------------------------------
class OS_count_sem_prop_t
{
  U8 name[OS_MAX_API_NAME];
  U32 creator;
  I32 value;
};
#endif
