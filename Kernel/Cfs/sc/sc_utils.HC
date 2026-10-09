/************************************************************************
 * NASA Docket No. GSC-18,924-1, and identified as "Core Flight
 * System (cFS) Stored Command Application (SC)"
 *
 * Copyright (c) 2021 United States Government as represented by the
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
// STORED COMMAND'S TIME ARITHMETIC -- the 1:1 translation of NASA's fsw/src/sc_utils.c, 184 lines
// and seven functions. SC's first source, and the one every other source depends on.
//
// ### SC HAS TWO CLOCKS AND THIS FILE IS WHERE THEY BOTH LIVE
//
// An ATS schedules on the SPACECRAFT CLOCK -- absolute seconds, read through a function pointer
// chosen at init. An RTS schedules on SC'S OWN WAKEUP COUNT -- a tick that only advances when the
// scheduler sends SC_WAKEUP_MID. So `SC_ComputeAbsTime` adds seconds and `SC_ComputeAbsWakeup`
// adds wakeups, and they are four lines apart doing arithmetic that is not interchangeable.
//
// **AND THE TWO ARE ASYMMETRIC IN A WAY WORTH NAMING**: SC_ComputeAbsTime goes through
// `CFE_TIME_Add`, which handles the subsecond field and the 32-bit rollover that cFE defines;
// SC_ComputeAbsWakeup is a bare `+`, which wraps silently. That is defensible -- a wakeup count
// has no subseconds and no epoch -- but it means a mission running long enough to wrap the wakeup
// counter gets a wrong answer from one of these two and a correct one from the other.
//
// ### `SC_LookupTimeAccessor` IS A DESIGNATED-INITIALISER TABLE OF FUNCTION POINTERS
//
// NASA writes
//
//     static const SC_TimeAccessor_t TIMEREF_LOOKUP[] = {
//         [SC_TimeRef_USE_CFE_TIME] = {CFE_TIME_GetTime},
//         [SC_TimeRef_USE_TAI]      = {CFE_TIME_GetTAI},
//         [SC_TimeRef_USE_UTC]      = {CFE_TIME_GetUTC}};
//
// HolyC has neither designated initialisers nor an initialised static aggregate, and docs/ records
// what the naive translation costs: a static-in-C table becomes a RUNTIME FILL, and the failure is
// SILENT -- five lost configuration entries and an empty block-size array, twice. So the table is
// declared at file scope and **filled at the top of the function, on every call, before it is
// read**. Three assignments, const data, no ordering hazard possible: there is no "reader that
// runs before the fill" because the fill and the read are the same five lines.
//
// The three designated indices are 0, 1 and 2 in order, so they are equivalent to a positional
// initialiser -- checked, not assumed, because a gap would have made the array longer than three
// and changed the bound below.
//
// ### AND THE BOUND IS A `sizeof` RATIO, WHICH IS WHY THE ARRAY IS FILE-SCOPE
//
// `TimeRef < (sizeof(TIMEREF_LOOKUP) / sizeof(TIMEREF_LOOKUP[0]))` is NASA's own guard and it is
// kept as the ratio rather than folded to 3 -- the array and its bound then cannot drift. A
// mission adding a fourth time reference changes one line.
//
// **NOTE WHAT THE GUARD DOES NOT CATCH.** `SC_TimeRef_MAX` is 3, so a configuration of
// `SC_TIME_TO_USE = SC_TimeRef_MAX` fails the bound, leaves `Result.GetTime` NULL, and is then
// silently repaired by the `if (Result.GetTime == NULL)` fallback to CFE_TIME_GetTime. So an
// out-of-range time reference is not an error -- it is cFE time. That fallback is the only error
// handling in this file.
//
// ### `SC_GetAtsEntryTime` REASSEMBLES A 32-BIT TIME FROM TWO 16-BIT HALVES, AND IN C THAT SHIFT
// ### IS IMPLEMENTATION-DEFINED
//
//     return ((Entry->TimeTag_MS << 16) + Entry->TimeTag_LS);
//
// `TimeTag_MS` is a `uint16`, which C promotes to `int` before the shift -- so for any MS value
// with the top bit set (0x8000 and above) `MS << 16` sets the sign bit of a 32-bit signed int,
// which C99 leaves implementation-defined. It works on every compiler cFS targets and the result
// is converted to the `uint32` return type, so the bits come out right.
//
// **IT COMES OUT RIGHT IN HolyC FOR A DIFFERENT REASON**: a U16 load zero-extends to 64 bits, so
// the shift happens in I64 where there is no overflow at all, and the truncation to U32 on return
// produces the same 32 bits. Two languages, two routes, one answer -- and NASA's parentheses
// around the shift are load-bearing in BOTH, because C puts `+` tighter than `<<` and HolyC puts
// `<<` tightest. Without them C would compute `MS << (16 + LS)`. tools/cfs/check_shift_parens.py
// is the gate.
#ifndef SC_UTILS_HC
#define SC_UTILS_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// sc_cfg.HC, sc_tbl.HC, sc_msg.HC, sc_global.HC, sc_events.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13. Re-including a
// guarded file the driver has already read makes the compiler skip EVERYTHING AFTER THAT LINE in
// the including file, with no diagnostic and exit status 0. LC carried sibling includes from its
// first commit and got away with it until two dead constants tipped it over; the trigger is TEXT,
// not structure, so every app here states its order instead.

// --- sc_utils.h's prototypes -------------------------------------------------------------------
U0 SC_GetCurrentTime();
U32 SC_GetAtsEntryTime(SC_AtsEntryHeader_t *Entry);
U32 SC_ComputeAbsTime(U32 RelTime);
U32 SC_ComputeAbsWakeup(U32 RelWakeup);
Bool SC_CompareAbsTime(U32 AbsTime1, U32 AbsTime2);
U16 SC_ToggleAtsIndex();
SC_TimeAccessor_t SC_LookupTimeAccessor(U8 TimeRef);

// NASA'S `static const` LOOKUP TABLE, hoisted to file scope and filled at use -- see the file
// header for why, and for why that is safe here where docs/ records it being unsafe elsewhere.
SC_TimeAccessor_t SC_TIMEREF_LOOKUP[3];

/*******************************************************************************/
// Choose the clock an ATS is scheduled against. Called once, from SC_AppInit.
SC_TimeAccessor_t SC_LookupTimeAccessor(U8 TimeRef)
{
  SC_TimeAccessor_t Result;

  // THE FILL. NASA's three designated initialisers, in index order -- and the indices really are
  // 0, 1, 2 with no gap, which is what makes a positional fill equivalent.
  SC_TIMEREF_LOOKUP[SC_TimeRef_USE_CFE_TIME].GetTime = &CFE_TIME_GetTime;
  SC_TIMEREF_LOOKUP[SC_TimeRef_USE_TAI].GetTime = &CFE_TIME_GetTAI;
  SC_TIMEREF_LOOKUP[SC_TimeRef_USE_UTC].GetTime = &CFE_TIME_GetUTC;

  Result.GetTime = NULL;

  if (TimeRef < sizeof(SC_TIMEREF_LOOKUP) / sizeof(SC_TimeAccessor_t)) {
    Result = SC_TIMEREF_LOOKUP[TimeRef];
  }

  // THE ONLY ERROR HANDLING IN THIS FILE, and it is a repair rather than a report: an
  // out-of-range reference silently becomes cFE time. See the file header.
  if (Result.GetTime == NULL) {
    Result.GetTime = &CFE_TIME_GetTime;
  }

  return Result;
}

/*******************************************************************************/
// Read the configured clock into SC_AppData.CurrentTime.
//
// AN INDIRECT CALL THROUGH A STRUCT MEMBER, which is the only one in SC. And NASA's comment --
// "We don't care about subseconds" -- is the whole reason SC's absolute times are uint32 seconds
// rather than CFE_TIME_SysTime_t: a stored sequence's resolution is one second, so half the
// precision cFE offers is dropped here on purpose and never recovered.
U0 SC_GetCurrentTime()
{
  CFE_TIME_SysTime TempTime;

  /* Use SC defined time */
  TempTime = SC_AppData.TimeRef.GetTime();

  /* We don't care about subseconds */
  SC_AppData.CurrentTime = TempTime.Seconds;
}

/*******************************************************************************/
// Reassemble an ATS entry's 32-bit time tag from its two 16-bit halves. See the file header on
// why NASA's parentheses matter in both languages and why the C is implementation-defined.
U32 SC_GetAtsEntryTime(SC_AtsEntryHeader_t *Entry)
{
  /*
  ** ATS Entry Header looks like this...
  **
  **    uint16 Pad;
  **    uint16 CmdNumber;
  **
  **    uint16 TimeTag_MS;
  **    uint16 TimeTag_LS;
  **
  **    CFE_SB_Buffer_t Buffer;
  **
  ** The command packet data is variable length,
  **    only the command packet header is shown here.
  */

  return (Entry->TimeTag_MS << 16) + Entry->TimeTag_LS;
}

/*******************************************************************************/
// Absolute time = current time + a relative offset, THROUGH CFE_TIME_Add. See the file header on
// the asymmetry with SC_ComputeAbsWakeup.
U32 SC_ComputeAbsTime(U32 RelTime)
{
  CFE_TIME_SysTime AbsoluteTimeWSubs;
  CFE_TIME_SysTime RelTimeWSubs;
  CFE_TIME_SysTime ResultTimeWSubs;
  /*
   ** get the current time
   */
  AbsoluteTimeWSubs.Seconds = SC_AppData.CurrentTime;
  AbsoluteTimeWSubs.Subseconds = 0;

  RelTimeWSubs.Seconds = RelTime;
  RelTimeWSubs.Subseconds = 0;
  /*
   ** add the relative time the current time
   */
  ResultTimeWSubs = CFE_TIME_Add(AbsoluteTimeWSubs, RelTimeWSubs);

  /* We don't need subseconds */
  return ResultTimeWSubs.Seconds;
}

/*******************************************************************************/
// Absolute wakeup count = current count + a relative offset, as a BARE ADDITION. Four lines from
// SC_ComputeAbsTime and deliberately not the same shape -- see the file header.
U32 SC_ComputeAbsWakeup(U32 RelWakeup)
{
  return SC_AppData.CurrentWakeupCount + RelWakeup;
}

/*******************************************************************************/
// Is AbsTime1 STRICTLY LATER than AbsTime2?
//
// **IT IS `A_GT_B` AND NOT `>=`**, so two commands with the same time tag compare as "not later"
// in both directions -- which is what lets SC's time-sorted index keep equal-time commands in
// upload order rather than reordering them.
Bool SC_CompareAbsTime(U32 AbsTime1, U32 AbsTime2)
{
  Bool Status;
  CFE_TIME_SysTime Time1WSubs;
  CFE_TIME_SysTime Time2WSubs;
  I64 Result;

  Time1WSubs.Seconds = AbsTime1;
  Time1WSubs.Subseconds = 0;

  Time2WSubs.Seconds = AbsTime2;
  Time2WSubs.Subseconds = 0;

  Result = CFE_TIME_Compare(Time1WSubs, Time2WSubs);

  if (Result == CFE_TIME_A_GT_B) {
    Status = TRUE;
  } else {
    Status = FALSE;
  }

  return Status;
}

/*******************************************************************************/
// The OTHER ATS's index: ATS A -> ATS B -> ATS A. With SC_NUMBER_OF_ATS = 2 this is a toggle, and
// the name says so -- but the code is a general increment-and-wrap, so a mission with three ATSs
// would get a ROTATION from a function called Toggle. Kept as NASA writes it.
//
// NOTE IT READS THROUGH `AtsCtrlBlckAddr`, a TABLE POINTER, with no NULL check -- so calling it
// before SC_AppInit has acquired the control block dereferences NULL. Every caller is inside the
// ATS processor, which cannot run before init; named here because the function itself promises
// nothing.
U16 SC_ToggleAtsIndex()
{
  U16 CurrAtsIndex = SC_AtsNumToIndex(SC_OperData.AtsCtrlBlckAddr->CurrAtsNum);

  SC_IDX_INCREMENT(CurrAtsIndex);
  if (!SC_AtsIndexIsValid(CurrAtsIndex)) {
    CurrAtsIndex = SC_ATS_IDX_C(0);
  }

  return CurrAtsIndex;
}

#endif
