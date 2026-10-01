/************************************************************************
 * NASA Docket No. GSC-18,719-1, and identified as "core Flight System:
 * Bootes"
 *
 * Copyright (c) 2020 United States Government as represented by the
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

// The TYPE from OSAL's src/os/inc/osapi-clock.h, split out of osapi_clock.HC for the same
// reason os_shared_task_affinity.HC exists: cFE needs OS_time_t -- EVS keeps one in every
// application's record -- and must not drag in OSAL's implementation, which reaches
// OS_GetLocalTime_Impl and, through osapi_errors.HC, the error-name tables.
//
// Only the type and the tick scale live here. The arithmetic (OS_TimeAdd, OS_TimeSubtract,
// OS_TimeGetTotalMilliseconds and the rest) stays in osapi_clock.HC, which is where the OSAL
// gate drives it; a cFE module that calls one declares it and the driver supplies it, exactly
// as it does for OS_MutSemTake.
#ifndef OS_SHARED_CLOCK_HC
#define OS_SHARED_CLOCK_HC
// One tick is one nanosecond in this configuration, which is what makes the conversions in
// osapi_clock.HC exact rather than rounded.
#ifndef OS_TIME_TICK_RESOLUTION_NS
#define OS_TIME_TICK_RESOLUTION_NS 1
#endif

class OS_time_t
{
  I64 ticks; // Ticks elapsed since reference point
};
#endif
