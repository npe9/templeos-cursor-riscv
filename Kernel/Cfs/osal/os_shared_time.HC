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

// 1:1 HolyC translation of the timebase and timer-callback types, from OSAL
// src/os/shared/inc/os-shared-timebase.h and os-shared-time.h, plus the public property structs
// from src/os/inc/osapi-timebase.h and osapi-timer.h.
#ifndef OS_SHARED_TIME_HC
#define OS_SHARED_TIME_HC
#include "osconfig.HC"
#include "os_shared_idmap.HC"

// Set on a timer whose time base was created FOR it by OS_TimerCreate, so deleting the timer
// must also delete that time base.
#define TIMECB_FLAG_DEDICATED_TIMEBASE 0x1

// The callback typedefs, spelled out at each use because HolyC has no typedef:
//   OS_TimerSync_t     uint32 (*)(osal_id_t timer_id)
//   OS_TimerCallback_t void   (*)(osal_id_t timer_id)
//   OS_ArgCallback_t   void   (*)(osal_id_t object_id, void *arg)

class OS_timebase_internal_record_t
{
  U8 timebase_name[OS_MAX_API_NAME];
  U8 _pad0[4]; // C pads here; HolyC packs. See tools/cfs/check_padding.py
  U32 (*external_sync)(U32); // OS_TimerSync_t
  U32 accuracy_usec;
  U32 first_cb;
  U32 freerun_time;
  U32 nominal_start_time;
  U32 nominal_interval_time;
  U8 _pad1[4]; // C rounds the struct up to its alignment; HolyC does not
};

class OS_timecb_internal_record_t
{
  U8 timer_name[OS_MAX_API_NAME];
  U32 flags;
  OS_object_token_t timebase_token;
  U32 prev_cb;
  U32 next_cb;
  U32 backlog_resets;
  I32 wait_time;
  I32 interval_time;
  U0 (*callback_ptr)(U32, U8 *); // OS_ArgCallback_t
  U8 *callback_arg;
};

class OS_timebase_prop_t
{
  U8 name[OS_MAX_API_NAME];
  U32 creator;
  U32 nominal_interval_time;
  U32 freerun_time;
  U32 accuracy;
};

class OS_timer_prop_t
{
  U8 name[OS_MAX_API_NAME];
  U32 creator;
  U32 start_time;
  U32 interval_time;
  U32 accuracy;
};

// THE TWO TABLES LIVE HERE, and in NASA they do not: osapi-timebase.c defines OS_timebase_table
// and osapi-time.c defines OS_timecb_table, each declared `extern` in the other's header. That
// works in C because the two are separate translation units resolved by a linker.
//
// It cannot work here. The two modules reference each other's table -- the callback thread in
// osapi-timebase.c walks OS_timecb_table, and OS_DoTimerAdd in osapi-time.c updates
// OS_timebase_table -- and HolyC compiles one single-pass unit with no separate compilation, so
// whichever file came second would be the only one able to see the other. `extern` is not a way
// out: outside the compiler's imports window it declares a module-local dummy, which would
// silently give one module its own empty copy of the table.
//
// So both definitions sit in the file that stands in for both headers. This is the same
// include-order-does-a-linker's-job device used throughout this translation, applied to data
// rather than to declarations.
OS_timebase_internal_record_t OS_timebase_table[OS_MAX_TIMEBASES];
OS_timecb_internal_record_t OS_timecb_table[OS_MAX_TIMERS];
#endif
