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
// 1:1 HolyC translation of cFE modules/time/fsw/src/cfe_time_api.c -- the PUBLIC TIME API every
// other cFS module calls. CFE_TIME_GetTime is here, and so is CFE_TIME_Print: with this file
// translated, both stop being driver stubs, and every
//
//     EVS Port1 1980-001-00:00:44.52768 23130/1/CFE_EVS 2: ...
//
// line in the differential transcript has its TIMESTAMP produced by translated code. That string
// was already inside the byte-identical comparison -- the stub just happened to agree.
//
// INCLUDE cfe_time_global.HC and cfe_time_utils.HC FIRST. The two code files are mutually
// recursive, exactly as NASA's are: utils calls CFE_TIME_Micro2SubSecs and CFE_TIME_GetClockInfo
// here, and this file calls CFE_TIME_GetReference and CFE_TIME_CalculateTAI there.
//
// THE ONE REAL DEVIATION IN THIS FILE IS CFE_TIME_Print, and it is not a shortcut. NASA's calls
// gmtime_r and strftime; this port has no libc, so the calendar conversion is written out below.
// The differential transcript is the right place to settle whether it is right, because the C
// side of the oracle is still calling glibc's.
#ifndef CFE_TIME_API_HC
#define CFE_TIME_API_HC
// NO #include HERE, deliberately. This file needs cfe_time_global.HC and cfe_time_utils.HC, and
// including them was how it was written first -- which cost an afternoon: when utils had ALREADY
// been included, re-including it from here made the compiler lose THIS ENTIRE FILE, with no
// diagnostic and a clean exit. Bisected to four comment lines in utils that mention `#if`;
// rewording them fixes it deterministically, and a small synthetic case does not reproduce, so
// the trigger is not yet characterised. docs/HOLYC_STRUCT_LIMITS.md #13.
//
// So the include order is the caller's job, as it is for every other file in this port: include
// cfe_time_global.HC and cfe_time_utils.HC before this one.
// --- cfe_time_utils.h ------------------------------------------------------------------------
#define CFE_TIME_NEGATIVE 0x80000000
// --- default_cfe_time_msgdefs.h: the clock state flags ---------------------------------------
// Twelve bits, assembled by CFE_TIME_GetClockInfo and downlinked in both the housekeeping and
// the diagnostic packet. A wrong bit is a wrong word in telemetry that a ground display decodes.
#define CFE_TIME_FLAG_CLKSET 0x8000
#define CFE_TIME_FLAG_FLYING 0x4000
#define CFE_TIME_FLAG_SRCINT 0x2000
#define CFE_TIME_FLAG_SIGPRI 0x1000
#define CFE_TIME_FLAG_SRVFLY 0x0800
#define CFE_TIME_FLAG_CMDFLY 0x0400
#define CFE_TIME_FLAG_ADDADJ 0x0200
#define CFE_TIME_FLAG_ADD1HZ 0x0100
#define CFE_TIME_FLAG_ADDTCL 0x0080
#define CFE_TIME_FLAG_SERVER 0x0040
#define CFE_TIME_FLAG_GDTONE 0x0020
#define CFE_TIME_FLAG_REFERR 0x0010
#define CFE_TIME_FLAG_UNUSED 0x000F
// --- cfe_mission_cfg.h: the epoch ------------------------------------------------------------
// The cFE epoch is 1980-001-00:00:00, and EPOCH_SECONDS is what converts it to the UNIX epoch
// that the calendar conversion below works in: 315,532,800 = ten years including two leap days.
#define CFE_MISSION_TIME_EPOCH_SECONDS 315532800
#define CFE_MISSION_TIME_EPOCH_MICROS  0
#define CFE_TIME_PRINTED_STRING_SIZE   24
// --- cfe_time_tone.c, which is not translated yet --------------------------------------------
// CFE_TIME_ExternalTone's whole body is a call to it, and that function is NOT under any #if --
// it is built in every configuration. Declared here and supplied by whoever links, the same
// arrangement cfe_evs_utils.HC used for CFE_EVS_GetTypeEnable before cfe_evs_task.c landed.
U0 CFE_TIME_Tone1HzISR();
// OSAL's time assembly, from osapi-clock.c (translated in osapi_clock.HC).
OS_time_t OS_TimeAssembleFromSubseconds(I64 seconds, U32 subsecs);
OS_time_t OS_TimeAssembleFromNanoseconds(I64 seconds, U32 nanosecs);
U32 OS_TimeGetMicrosecondsPart(OS_time_t tm);
// Defined below and used above it.
U32 CFE_TIME_GetLeapSeconds();
CFE_TIME_SysTime CFE_TIME_GetSTCF();
// --- cfe_time_utils.h: CFE_TIME_GetReferenceState --------------------------------------------
// A static inline upstream: the currently PUBLISHED slot of the reference ring. Callers that only
// want a flag read it directly instead of taking a full snapshot.
CFE_TIME_ReferenceState_t *CFE_TIME_GetReferenceState()
{
  return &CFE_TIME_Global.ReferenceState[CFE_TIME_Global.LastVersionCounter & CFE_TIME_REFERENCE_BUF_MASK];
}

CFE_TIME_SysTime CFE_TIME_GetTAI()
{
  CFE_TIME_Reference_t Reference;
  CFE_TIME_SysTime tai;
  // Zero out the Reference variable because we pass it into a function with its address
  MemSet(&Reference, 0, sizeof(CFE_TIME_Reference_t));
  CFE_TIME_GetReference(&Reference);
  tai = CFE_TIME_CalculateTAI(&Reference);
  return tai;
}

CFE_TIME_SysTime CFE_TIME_GetUTC()
{
  CFE_TIME_Reference_t Reference;
  CFE_TIME_SysTime utc;
  // Zero out the Reference variable because we pass it into a function with its address
  MemSet(&Reference, 0, sizeof(CFE_TIME_Reference_t));
  CFE_TIME_GetReference(&Reference);
  utc = CFE_TIME_CalculateUTC(&Reference);
  return utc;
}

CFE_TIME_SysTime CFE_TIME_GetTime()
{
  CFE_TIME_SysTime CurrentTime;
  // CFE_MISSION_TIME_CFG_DEFAULT_TAI is 1 in this configuration, so "the time" is TAI: MET plus
  // STCF with the leap seconds LEFT IN. The UTC arm is not built.
  CurrentTime = CFE_TIME_GetTAI();
  return CurrentTime;
}

CFE_TIME_SysTime CFE_TIME_MET2SCTime(CFE_TIME_SysTime METTime)
{
  CFE_TIME_SysTime STCF;
  CFE_TIME_SysTime TIATime;
  CFE_TIME_SysTime ReturnTime;
  STCF = CFE_TIME_GetSTCF();
  // TIA = MET + STCF
  TIATime = CFE_TIME_Add(METTime, STCF);
  // DEFAULT_TAI, so the result IS the TAI time; the UTC arm would subtract the leap seconds.
  ReturnTime = TIATime;
  return ReturnTime;
}

I32 CFE_TIME_GetClockState()
{
  CFE_TIME_Reference_t Reference;
  I32 state;
  // Zero out the Reference variable because we pass it into a function with its address
  MemSet(&Reference, 0, sizeof(CFE_TIME_Reference_t));
  CFE_TIME_GetReference(&Reference);
  state = CFE_TIME_CalculateState(&Reference);
  return state;
}

U16 CFE_TIME_GetClockInfo()
{
  U16 StateFlags = 0;
  CFE_TIME_ReferenceState_t *RefState = CFE_TIME_GetReferenceState();
  if (RefState->ClockSetState == CFE_TIME_SetState_WAS_SET) {
    StateFlags |= CFE_TIME_FLAG_CLKSET;
  }
  if (RefState->ClockFlyState == CFE_TIME_FlywheelState_IS_FLY) {
    StateFlags |= CFE_TIME_FLAG_FLYING;
  }
  if (CFE_TIME_Global.ClockSource == CFE_TIME_SourceSelect_INTERNAL) {
    StateFlags |= CFE_TIME_FLAG_SRCINT;
  }
  if (CFE_TIME_Global.ClockSignal == CFE_TIME_ToneSignalSelect_PRIMARY) {
    StateFlags |= CFE_TIME_FLAG_SIGPRI;
  }
  if (CFE_TIME_Global.ServerFlyState == CFE_TIME_FlywheelState_IS_FLY) {
    StateFlags |= CFE_TIME_FLAG_SRVFLY;
  }
  if (CFE_TIME_Global.Forced2Fly) {
    StateFlags |= CFE_TIME_FLAG_CMDFLY;
  }
  if (CFE_TIME_Global.OneTimeDirection == CFE_TIME_AdjustDirection_ADD) {
    StateFlags |= CFE_TIME_FLAG_ADDADJ;
  }
  if (CFE_TIME_Global.OneHzDirection == CFE_TIME_AdjustDirection_ADD) {
    StateFlags |= CFE_TIME_FLAG_ADD1HZ;
  }
  if (RefState->DelayDirection == CFE_TIME_AdjustDirection_ADD) {
    StateFlags |= CFE_TIME_FLAG_ADDTCL;
  }
  // SERVER is unconditional here, because this port is one.
  StateFlags |= CFE_TIME_FLAG_SERVER;
  if (CFE_TIME_Global.IsToneGood == TRUE) {
    StateFlags |= CFE_TIME_FLAG_GDTONE;
  }
  if (CFE_TIME_Global.GetReferenceFail) {
    StateFlags |= CFE_TIME_FLAG_REFERR;
  }
  return StateFlags;
}

U32 CFE_TIME_GetLeapSeconds()
{
  CFE_TIME_Reference_t Reference;
  // Zero out the Reference variable because we pass it into a function with its address
  MemSet(&Reference, 0, sizeof(CFE_TIME_Reference_t));
  CFE_TIME_GetReference(&Reference);
  return Reference.AtToneLeapSeconds;
}

CFE_TIME_SysTime CFE_TIME_GetSTCF()
{
  CFE_TIME_Reference_t Reference;
  // Zero out the Reference variable because we pass it into a function with its address
  MemSet(&Reference, 0, sizeof(CFE_TIME_Reference_t));
  CFE_TIME_GetReference(&Reference);
  return Reference.AtToneSTCF;
}

CFE_TIME_SysTime CFE_TIME_GetMET()
{
  CFE_TIME_Reference_t Reference;
  // Zero out the Reference variable because we pass it into a function with its address
  MemSet(&Reference, 0, sizeof(CFE_TIME_Reference_t));
  CFE_TIME_GetReference(&Reference);
  return Reference.CurrentMET;
}

U32 CFE_TIME_GetMETseconds()
{
  CFE_TIME_Reference_t Reference;
  // Zero out the Reference variable because we pass it into a function with its address
  MemSet(&Reference, 0, sizeof(CFE_TIME_Reference_t));
  CFE_TIME_GetReference(&Reference);
  return Reference.CurrentMET.Seconds;
}

U32 CFE_TIME_GetMETsubsecs()
{
  CFE_TIME_Reference_t Reference;
  // Zero out the Reference variable because we pass it into a function with its address
  MemSet(&Reference, 0, sizeof(CFE_TIME_Reference_t));
  CFE_TIME_GetReference(&Reference);
  return Reference.CurrentMET.Subseconds;
}
// THE CARRY IS DETECTED BY WRAPPING, not by comparing against a limit: the subsecond field is a
// full 32 bits of 1/2^32 second, so a sum that came out SMALLER than one of its inputs is the
// only evidence that it overflowed. Same trick, inverted, in Subtract.
CFE_TIME_SysTime CFE_TIME_Add(CFE_TIME_SysTime Time1, CFE_TIME_SysTime Time2)
{
  CFE_TIME_SysTime Result;
  Result.Subseconds = Time1.Subseconds + Time2.Subseconds;
  if (Result.Subseconds < Time1.Subseconds) {
    Result.Seconds = Time1.Seconds + Time2.Seconds + 1;
  } else {
    Result.Seconds = Time1.Seconds + Time2.Seconds;
  }
  return Result;
}

CFE_TIME_SysTime CFE_TIME_Subtract(CFE_TIME_SysTime Time1, CFE_TIME_SysTime Time2)
{
  CFE_TIME_SysTime Result;
  Result.Subseconds = Time1.Subseconds - Time2.Subseconds;
  if (Result.Subseconds > Time1.Subseconds) {
    Result.Seconds = Time1.Seconds - Time2.Seconds - 1;
  } else {
    Result.Seconds = Time1.Seconds - Time2.Seconds;
  }
  return Result;
}
// A COMPARISON THAT ASSUMES THE TWO TIMES ARE CLOSE. Seconds is unsigned and wraps, so a
// difference bigger than CFE_TIME_NEGATIVE (2^31, about 68 years) is read as the other side of a
// roll-over and the answer is inverted. That is a deliberate choice upstream, documented in the
// Application Developers Guide, and it is why this returns a signed three-valued result.
I32 CFE_TIME_Compare(CFE_TIME_SysTime TimeA, CFE_TIME_SysTime TimeB)
{
  I32 Result;
  if (TimeA.Seconds > TimeB.Seconds) {
    if (TimeA.Seconds - TimeB.Seconds > CFE_TIME_NEGATIVE) {
      Result = CFE_TIME_A_LT_B;
    } else {
      Result = CFE_TIME_A_GT_B;
    }
  } else if (TimeA.Seconds < TimeB.Seconds) {
    if (TimeB.Seconds - TimeA.Seconds > CFE_TIME_NEGATIVE) {
      Result = CFE_TIME_A_GT_B;
    } else {
      Result = CFE_TIME_A_LT_B;
    }
  } else {
    if (TimeA.Subseconds > TimeB.Subseconds) {
      Result = CFE_TIME_A_GT_B;
    } else if (TimeA.Subseconds < TimeB.Subseconds) {
      Result = CFE_TIME_A_LT_B;
    } else {
      Result = CFE_TIME_EQUAL;
    }
  }
  return Result;
}

U32 CFE_TIME_Sub2MicroSecs(U32 SubSeconds)
{
  OS_time_t tm;
  tm = OS_TimeAssembleFromSubseconds(0, SubSeconds);
  return OS_TimeGetMicrosecondsPart(tm);
}

U32 CFE_TIME_Micro2SubSecs(U32 MicroSeconds)
{
  OS_time_t tm;
  U32 SubSeconds;
  if (MicroSeconds > 999999) {
    SubSeconds = 0xFFFFFFFF;
  } else {
    tm = OS_TimeAssembleFromNanoseconds(0, MicroSeconds * 1000);
    SubSeconds = OS_TimeGetSubsecondsPart(tm);
  }
  return SubSeconds;
}
// --- CFE_TIME_Print, and the calendar it needs -----------------------------------------------
// NASA's CFE_TIME_Print is six lines of libc:
//
//     time_t sec = TimeToPrint.Seconds + CFE_MISSION_TIME_EPOCH_SECONDS;
//     gmtime_r(&sec, &tm);
//     strftime(PrintBuffer, CFE_TIME_PRINTED_STRING_SIZE - 6, "%Y-%j-%H:%M:%S", &tm);
//
// This port has no libc, so the two calls are written out. THIS IS THE MODULE'S ONE REAL
// DEVIATION -- everything else in TIME is NASA's code with NASA's arithmetic -- and the only
// honest way to settle it is the differential transcript: the C half of the oracle still calls
// glibc's gmtime_r and strftime, so the two implementations are compared character for character
// on every timestamp the driver produces, and there are hundreds of them.
//
// WHAT strftime("%Y-%j-%H:%M:%S") PRODUCES is a four-digit year, a THREE-DIGIT DAY OF YEAR
// (1-366, zero padded) and a 24-hour time -- "1980-001-00:00:44". Not a month or a day of month,
// which is why no month table is needed: only the year boundary matters.
//
// The conversion works in the UNIX epoch because that is what NASA hands gmtime_r, and the leap
// rule is the proleptic Gregorian one: every 4th year, except every 100th, except every 400th.
// 1980 is a leap year and 2000 is a leap year; 1900 and 2100 are not.
Bool CFE_TIME_IsLeapYear(I64 Year)
{
  if (Year % 400 == 0)
    return TRUE;
  if (Year % 100 == 0)
    return FALSE;
  return Year % 4 == 0;
}
// gmtime_r's answer, reduced to the four fields "%Y-%j-%H:%M:%S" uses. Takes seconds since the
// UNIX epoch; walks forward a year at a time, which is exact and needs no table.
U0 CFE_TIME_UnixToCalendar(I64 UnixSeconds, I64 *Year, I64 *YearDay, I64 *Hour, I64 *Minute, I64 *Second)
{
  I64 Days = UnixSeconds / 86400;
  I64 Rem = UnixSeconds % 86400;
  I64 Y = 1970;
  I64 YearLen;
  // A time before the UNIX epoch would make both quotients negative; cFE times start at 1980 and
  // EPOCH_SECONDS is added before this is called, so the input is never negative. Guarded anyway,
  // because getting a negative here wrong would print a plausible wrong date.
  if (Rem < 0) {
    Rem += 86400;
    Days -= 1;
  }
  // `Y = Y + 1` and `Days = Days - YearLen`, NOT `Y++` and `Days -= YearLen`. Measured: the
  // increment form left Y at 1970 here, so every year was treated as 365 days and this function
  // returned 1970-003 where glibc's gmtime_r returns 1980-001 -- which the differential
  // transcript caught, on the very first run with TIME gated. The explicit forms work.
  // docs/HOLYC_STRUCT_LIMITS.md #14.
  while (TRUE) {
    YearLen = 365;
    if (CFE_TIME_IsLeapYear(Y))
      YearLen = 366;
    if (Days < YearLen)
      break;
    Days = Days - YearLen;
    Y = Y + 1;
  }
  *Year = Y;
  *YearDay = Days + 1;
  // strftime's %j is 1-based
  *Hour = Rem / 3600;
  *Minute = Rem % 3600 / 60;
  *Second = Rem % 60;
}
// A fixed-width unsigned decimal, which is what both %Y/%j (zero padded by strftime) and the
// subsecond digits need. Writes exactly Width characters and returns the next position.
U8 *CFE_TIME_PrintPad(U8 *Buf, I64 Value, I64 Width)
{
  I64 Scale = 1;
  I64 i;
  for (i = 1; i < Width; i++)
    Scale *= 10;
  while (Scale > 0) {
    *Buf++ = '0' + Value / Scale % 10;
    Scale /= 10;
  }
  return Buf;
}

I32 CFE_TIME_Print(U8 *PrintBuffer, CFE_TIME_SysTime TimeToPrint)
{
  U32 Micros;
  I64 Year;
  I64 YearDay;
  I64 Hour;
  I64 Minute;
  I64 Second;
  I64 UnixSeconds;
  U8 *p;
  if (PrintBuffer == NULL) {
    return CFE_TIME_BAD_ARGUMENT;
  }
  Micros = (CFE_TIME_Sub2MicroSecs(TimeToPrint.Subseconds) + CFE_MISSION_TIME_EPOCH_MICROS) / 10;
  // epoch is Jan 1, 1980
  UnixSeconds = TimeToPrint.Seconds + CFE_MISSION_TIME_EPOCH_SECONDS;
  // NASA returns CFE_TIME_BAD_ARGUMENT when gmtime_r fails, which it does only for a year that
  // will not fit in a struct tm. The conversion below cannot fail, so that arm is unreachable
  // here -- noted rather than faked, because a reachable-looking branch nothing can enter is
  // worse than an absent one.
  CFE_TIME_UnixToCalendar(UnixSeconds, &Year, &YearDay, &Hour, &Minute, &Second);
  // strftime(..., "%Y-%j-%H:%M:%S", &tm)
  p = PrintBuffer;
  p = CFE_TIME_PrintPad(p, Year, 4);
  *p++ = '-';
  p = CFE_TIME_PrintPad(p, YearDay, 3);
  *p++ = '-';
  p = CFE_TIME_PrintPad(p, Hour, 2);
  *p++ = ':';
  p = CFE_TIME_PrintPad(p, Minute, 2);
  *p++ = ':';
  p = CFE_TIME_PrintPad(p, Second, 2);
  // and the five subsecond digits NASA appends by hand
  *p++ = '.';
  *p++ = '0' + Micros % 100000 / 10000;
  *p++ = '0' + Micros % 10000 / 1000;
  *p++ = '0' + Micros % 1000 / 100;
  *p++ = '0' + Micros % 100 / 10;
  *p++ = '0' + Micros % 10;
  *p = 0;
  return CFE_SUCCESS;
}

U0 CFE_TIME_ExternalTone()
{
  CFE_TIME_Tone1HzISR();
}

I32 CFE_TIME_RegisterSynchCallback(U0 (*CallbackFuncPtr)())
{
  I32 Status;
  U32 AppId;
  U32 AppIndex;
  U32 i;
  Status = CFE_ES_GetAppID(&AppId);
  if (Status == CFE_SUCCESS) {
    Status = CFE_ES_AppID_ToIndex(AppId, &AppIndex);
  }
  // Report an error if the AppID is out of range
  if (Status == CFE_SUCCESS && AppIndex >= CFE_PLATFORM_ES_MAX_APPLICATIONS) {
    Status = CFE_TIME_TOO_MANY_SYNCH_CALLBACKS;
  }
  if (Status == CFE_SUCCESS) {
    // Report an error if this app is already registered
    if (CFE_TIME_Global.SynchCallback[AppIndex].Ptr != NULL) {
      Status = CFE_TIME_TOO_MANY_SYNCH_CALLBACKS;
    } else {
      CFE_TIME_Global.SynchCallback[AppIndex].Ptr = CallbackFuncPtr;
    }
  }
  return Status;
}

I32 CFE_TIME_UnregisterSynchCallback(U0 (*CallbackFuncPtr)())
{
  I32 Status;
  U32 AppId;
  U32 AppIndex;
  Status = CFE_ES_GetAppID(&AppId);
  if (Status == CFE_SUCCESS) {
    Status = CFE_ES_AppID_ToIndex(AppId, &AppIndex);
  }
  // Report an error if the AppID is out of range
  if (Status == CFE_SUCCESS && AppIndex >= CFE_PLATFORM_ES_MAX_APPLICATIONS) {
    Status = CFE_TIME_CALLBACK_NOT_REGISTERED;
  }
  if (Status == CFE_SUCCESS) {
    if (CFE_TIME_Global.SynchCallback[AppIndex].Ptr == CallbackFuncPtr) {
      CFE_TIME_Global.SynchCallback[AppIndex].Ptr = NULL;
    } else {
      Status = CFE_TIME_CALLBACK_NOT_REGISTERED;
    }
  }
  return Status;
}
// NOT TRANSLATED, because this configuration does not build them:
//   CFE_TIME_ExternalMET   #if CFE_PLATFORM_TIME_CFG_SRC_MET == true   (0 here)
//   CFE_TIME_ExternalGPS   #if CFE_PLATFORM_TIME_CFG_SRC_GPS == true   (0 here)
//   CFE_TIME_ExternalTime  #if CFE_PLATFORM_TIME_CFG_SRC_TIME == true  (0 here)
// All three are whole-function #if bodies, so the C the oracle links does not contain them
// either -- the same arrangement cfe_time_utils.HC records for its three setters.
#endif
