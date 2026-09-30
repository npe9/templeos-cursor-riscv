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

// 1:1 HolyC translation of the console types, from OSAL src/os/shared/inc/os-shared-console.h.
// Separate from the implementation so a backend can declare its _Impl functions first; see
// os_shared_errors.HC for why include order does that job here.
#ifndef OS_SHARED_CONSOLE_HC
#define OS_SHARED_CONSOLE_HC
#include "osconfig.HC"
class OS_console_internal_record_t
{
  U8 device_name[OS_MAX_API_NAME];
  U8 *BufBase;  // start of the buffer memory
  I64 BufSize;  // total size of the buffer (size_t)
  I64 ReadPos;  // offset of next byte to read; `volatile` in the C, and HolyC has no volatile
  I64 WritePos; // offset of next byte to write; likewise
  U32 OverflowEvents; // number of lines dropped due to overflow
  Bool IsAsync; // whether to write data via a deferred utility task
};
#endif
