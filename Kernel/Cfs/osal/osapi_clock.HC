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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-clock.c, with the type, constants and
// inline arithmetic it needs from src/os/inc/osapi-clock.h.
//
// OS_time_t IS EXACTLY EIGHT BYTES -- one int64 of ticks -- which is the only reason the
// by-value returns below compile at all. This compiler has no struct-return ABI and now refuses
// anything larger (docs/HOLYC_STRUCT_LIMITS.md); OS_time_t sits precisely at the boundary. Worth
// knowing before anyone "improves" the struct by adding a field to it.
//
// A tick is 100 ns, so the whole API is integer arithmetic on a 64-bit tick count and there is
// no floating point anywhere in it.
#ifndef OSAPI_CLOCK_HC
#define OSAPI_CLOCK_HC
#include "osapi_errors.HC"
// --- osapi-clock.h ---------------------------------------------------------------------------
#define OS_TIME_TICK_RESOLUTION_NS 100
#define OS_TIME_TICKS_PER_SECOND   (1000000000 / OS_TIME_TICK_RESOLUTION_NS)
#define OS_TIME_TICKS_PER_MSEC     (1000000 / OS_TIME_TICK_RESOLUTION_NS)
#define OS_TIME_TICKS_PER_USEC     (1000 / OS_TIME_TICK_RESOLUTION_NS)
#define OS_PEND  (-1)
#define OS_CHECK (0)
#define INT32_MAX 0x7FFFFFFF
#define INT64_MAX 0x7FFFFFFFFFFFFFFF

// The type and the tick scale live beside this file so cFE can have OS_time_t without this
// implementation -- see os_shared_clock.HC.
#include "os_shared_clock.HC"
// OS_TIME_ZERO and OS_TIME_MAX are compound literals in the C; HolyC has none, so they are
// functions, as CFE_SB_INVALID_MSG_ID and CFE_SBR_INVALID_ROUTE_ID became.
OS_time_t OS_TimeZero()
{
  OS_time_t t;
  t.ticks = 0;
  return t;
}

OS_time_t OS_TimeMax()
{
  OS_time_t t;
  t.ticks = INT64_MAX;
  return t;
}

OS_time_t OS_TimeAdd(OS_time_t time1, OS_time_t time2)
{
  OS_time_t ostm;
  ostm.ticks = time1.ticks + time2.ticks;
  return ostm;
}

OS_time_t OS_TimeSubtract(OS_time_t time1, OS_time_t time2)
{
  OS_time_t ostm;
  ostm.ticks = time1.ticks - time2.ticks;
  return ostm;
}

Bool OS_TimeEqual(OS_time_t time1, OS_time_t time2)
{
  return time1.ticks == time2.ticks;
}

// Three-way sign without a branch, exactly as the C writes it: (x > 0) - (x < 0).
I8 OS_TimeGetSign(OS_time_t time)
{
  return (time.ticks > 0) - (time.ticks < 0);
}

I8 OS_TimeCompare(OS_time_t time1, OS_time_t time2)
{
  return OS_TimeGetSign(OS_TimeSubtract(time1, time2));
}

OS_time_t OS_TimeFromTotalMilliseconds(I64 tm)
{
  OS_time_t ostm;
  ostm.ticks = tm * OS_TIME_TICKS_PER_MSEC;
  return ostm;
}

I64 OS_TimeGetTotalMilliseconds(OS_time_t tm)
{
  return tm.ticks / OS_TIME_TICKS_PER_MSEC;
}
// --- the backend seam ------------------------------------------------------------------------
// Declared, supplied by whoever links this. The gate asserts an empty import trailer, so a
// missing one cannot bind silently to the C runtime.
I32 OS_GetMonotonicTime_Impl(OS_time_t *time_struct);
I32 OS_GetLocalTime_Impl(OS_time_t *time_struct);
I32 OS_SetLocalTime_Impl(OS_time_t *time_struct);
// --- osapi-clock.c ---------------------------------------------------------------------------
I32 OS_GetMonotonicTime(OS_time_t *time_struct)
{
  // Check parameters
  if (time_struct == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return OS_GetMonotonicTime_Impl(time_struct);
}

I32 OS_GetLocalTime(OS_time_t *time_struct)
{
  if (time_struct == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return OS_GetLocalTime_Impl(time_struct);
}

I32 OS_SetLocalTime(OS_time_t *time_struct)
{
  if (time_struct == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return OS_SetLocalTime_Impl(time_struct);
}

// Note it calls OS_GetLocalTime_Impl DIRECTLY rather than OS_GetLocalTime -- skipping its own
// module's NULL check, because the pointer is its own local. Translated as written.
OS_time_t OS_TimeFromRelativeMilliseconds(I32 relative_msec)
{
  OS_time_t abs_time = OS_TimeZero;
  if (relative_msec == OS_CHECK) {
    abs_time = OS_TimeZero;
  } else if (relative_msec > 0) {
    OS_GetLocalTime_Impl(&abs_time);
    abs_time = OS_TimeAdd(abs_time, OS_TimeFromTotalMilliseconds(relative_msec));
  } else {
    abs_time = OS_TimeMax;
  }
  return abs_time;
}

I32 OS_TimeToRelativeMilliseconds(OS_time_t time)
{
  I64 relative_msec;
  OS_time_t curr_time = OS_TimeZero;
  // A time already in the past, or the sentinel maximum, is used as-is
  if (OS_TimeGetSign(time) <= 0 || OS_TimeEqual(time, OS_TimeMax)) {
    curr_time = time;
  } else {
    OS_GetLocalTime_Impl(&curr_time);
    curr_time = OS_TimeSubtract(time, curr_time);
  }
  if (OS_TimeGetSign(curr_time) <= 0) {
    // map this to a polling op (OS_CHECK)
    relative_msec = OS_CHECK;
  } else {
    // note this result is 64 bits, as this can exceed int32 potentially
    relative_msec = OS_TimeGetTotalMilliseconds(curr_time);
    // Just in case: cap the value at INT32_MAX
    if (relative_msec > INT32_MAX) {
      // map this to an indefinite block (OS_PEND)
      relative_msec = OS_PEND;
    }
  }
  return relative_msec;
}
#endif
