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
// A TICK IS 100 NANOSECONDS in this configuration, not one. OSAL declares these as ENUM MEMBERS
// in osapi-clock.h, not as #defines -- OS_TIME_TICKS_PER_SECOND is literally
// `1000000000 / OS_TIME_TICK_RESOLUTION_NS` in an enum -- and this file said 1 for several
// commits. It cost nothing until the TIME module divided by it: CFE_TIME_LatchClock turned a
// one-second PSP reading into 1 second where NASA's turns it into 100, and the differential
// transcript printed 00:00:01 against 00:01:40.
//
// check_constants.py could not see the error, because an `#ifdef` test cannot see an
// ENUMERATOR: both names came back undefined, were classified as "a name this port invented",
// and were never compared. That hole is closed now -- the tool retries the undefined set as
// EXPRESSIONS -- and these two are the first things it checks.
#ifndef OS_TIME_TICK_RESOLUTION_NS
#define OS_TIME_TICK_RESOLUTION_NS 100
#endif

class OS_time_t
{
  I64 ticks; // Ticks elapsed since reference point
};

// --- osapi-clock.h: the five conversions that are HEADER INLINES, not osapi-clock.c code -----
// NASA declares these `static inline` in osapi-clock.h, so they are compiled into every caller
// rather than into the OSAL library -- which is why they belong here with the type and not in
// osapi_clock.HC. The TIME module is the first caller: CFE_TIME_LatchClock converts the PSP's
// answer into cFE's seconds-and-1/2^32-subseconds form, and CFE_TIME_Micro2SubSecs goes back.
//
// A SUBSECOND IS 1/2^32 OF A SECOND, not a microsecond, and the two conversions below are
// NASA's exact integer arithmetic for that -- shifts and a rounding term, written to avoid a
// 32-bit left shift and to round UP so a microsecond value survives a round trip. Reproduced
// verbatim, because this is the arithmetic every timestamp in the port's telemetry goes through.
#define OS_TIME_TICKS_PER_SECOND 10000000
#define OS_TIME_TICKS_PER_USEC   10

I64 OS_TimeGetTotalSeconds(OS_time_t tm)
{
  return tm.ticks / OS_TIME_TICKS_PER_SECOND;
}

I64 OS_TimeGetFractionalPart(OS_time_t tm)
{
  return tm.ticks % OS_TIME_TICKS_PER_SECOND;
}

U32 OS_TimeGetSubsecondsPart(OS_time_t tm)
{
  // This computation avoids a 32-bit left shift which may not be implemented.
  //
  // It also must round up, otherwise this may result in a value one less than the original when
  // converted back to usec again.
  I64 frac = (OS_TimeGetFractionalPart(tm) << 30) + (OS_TIME_TICKS_PER_SECOND >> 2);
  return (frac - 1) / (OS_TIME_TICKS_PER_SECOND >> 2);
}

U32 OS_TimeGetMicrosecondsPart(OS_time_t tm)
{
  return OS_TimeGetFractionalPart(tm) / OS_TIME_TICKS_PER_USEC;
}

OS_time_t OS_TimeAssembleFromNanoseconds(I64 seconds, U32 nanoseconds)
{
  OS_time_t result;
  result.ticks = seconds * OS_TIME_TICKS_PER_SECOND;
  result.ticks += nanoseconds / OS_TIME_TICK_RESOLUTION_NS;
  return result;
}

OS_time_t OS_TimeAssembleFromSubseconds(I64 seconds, U32 subseconds)
{
  OS_time_t result;
  result.ticks = seconds * OS_TIME_TICKS_PER_SECOND;
  result.ticks += (subseconds(I64) * (OS_TIME_TICKS_PER_SECOND >> 2)) >> 30;
  return result;
}
#endif
