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
// 1:1 HolyC translation of cFE modules/time/fsw/src/cfe_time_utils.c -- the MACHINERY under the
// TIME API: the lock-free reference ring, the local clock latch, the reset-area save and restore,
// the telemetry assembly, and the setters the ground commands reach through.
//
// INCLUDE cfe_time_global.HC FIRST, and cfe_time_api.HC AFTER this file: the two are mutually
// recursive -- utils calls CFE_TIME_Micro2SubSecs and CFE_TIME_GetClockInfo in api, api calls
// CFE_TIME_GetReference and CFE_TIME_LatchClock here -- so each declares what it needs from the
// other. NASA has both in cfe_time_utils.h and cfe_time.h; the prototypes below are those.
//
// THE RING IS THE POINT OF THIS FILE. Readers of the time reference take no lock: a writer fills
// the NEXT slot of a four-deep ring and publishes it by bumping LastVersionCounter, and a reader
// copies a slot and then checks the version it started from. If the version moved, the reader
// retries. CFE_TIME_StartReferenceUpdate and CFE_TIME_FinishReferenceUpdate are the two halves of
// the write, and CFE_TIME_GetReference is the retry loop. Nothing else here matters as much:
// every API answer is derived from one consistent snapshot, which is why MET, STCF and the leap
// seconds never disagree with each other.
#ifndef CFE_TIME_UTILS_HC
#define CFE_TIME_UTILS_HC
// Guarded, so including this first costs nothing where a driver has them already.
#include "cfe_time_global.HC"          // the types, the constants and CFE_TIME_Global
#include "cfe_es_resetdata.HC"         // CFE_ES_ResetData_t and CFE_TIME_ResetVars_t
#include "../osal/os_shared_clock.HC"  // OS_time_t, which the local clock latch reads
// --- cfe_psp.h -------------------------------------------------------------------------------
#ifndef CFE_PSP_SUCCESS
#define CFE_PSP_SUCCESS 0
#endif
// --- what this file needs from elsewhere -----------------------------------------------------
// cfe_time_api.c, translated beside this one and included after it.
U32 CFE_TIME_Micro2SubSecs(U32 MicroSeconds);
U32 CFE_TIME_Sub2MicroSecs(U32 SubSeconds);
U16 CFE_TIME_GetClockInfo();
CFE_TIME_SysTime CFE_TIME_Add(CFE_TIME_SysTime Time1, CFE_TIME_SysTime Time2);
CFE_TIME_SysTime CFE_TIME_Subtract(CFE_TIME_SysTime Time1, CFE_TIME_SysTime Time2);
I32 CFE_TIME_Compare(CFE_TIME_SysTime TimeA, CFE_TIME_SysTime TimeB);
// Defined at the bottom of this file and called from the middle of it.
I32 CFE_TIME_CalculateState(CFE_TIME_Reference_t *Reference);
U0 CFE_TIME_FinishReferenceUpdate(CFE_TIME_ReferenceState_t *NextState);
// ES, PSP and MSG. None of ES is translated; the PSP clock and the reset area are the two things
// this file cannot do without, and the differential oracle supplies both.
I32 CFE_ES_AppID_ToIndex(U32 AppID, U32 *Idx);
I32 CFE_ES_GetAppID(U32 *AppIdPtr);
I32 CFE_PSP_GetResetArea(U64 *PtrToResetArea, U32 *SizeOfResetArea);
U0 CFE_PSP_GetTime(OS_time_t *LocalTime);
I64 OS_TimeGetTotalSeconds(OS_time_t tm);
U32 OS_TimeGetSubsecondsPart(OS_time_t tm);
// --- cfe_time_utils.h: the two halves of a reference write -----------------------------------
// NASA's CFE_TIME_FinishReferenceUpdate is a static inline in the header; it is the PUBLISH step,
// and it must come after every field of the new slot is written.
U0 CFE_TIME_FinishReferenceUpdate(CFE_TIME_ReferenceState_t *NextState)
{
  CFE_TIME_Global.LastVersionCounter = NextState->StateVersion;
}
// Returns the slot a writer should fill: the one AFTER the currently published slot, pre-loaded
// with the published values so a writer that changes one field leaves the rest alone.
CFE_TIME_ReferenceState_t *CFE_TIME_StartReferenceUpdate()
{
  U32 Version = CFE_TIME_Global.LastVersionCounter;
  CFE_TIME_ReferenceState_t *CurrState;
  CFE_TIME_ReferenceState_t *NextState;
  CurrState = &CFE_TIME_Global.ReferenceState[Version & CFE_TIME_REFERENCE_BUF_MASK];
  ++Version;
  NextState = &CFE_TIME_Global.ReferenceState[Version & CFE_TIME_REFERENCE_BUF_MASK];
  NextState->StateVersion = Version;
  // initially propagate all previous values to next values
  NextState->AtToneLeapSeconds = CurrState->AtToneLeapSeconds;
  NextState->ClockSetState = CurrState->ClockSetState;
  NextState->ClockFlyState = CurrState->ClockFlyState;
  NextState->DelayDirection = CurrState->DelayDirection;
  NextState->AtToneMET = CurrState->AtToneMET;
  NextState->AtToneSTCF = CurrState->AtToneSTCF;
  NextState->AtToneDelay = CurrState->AtToneDelay;
  NextState->AtToneLatch = CurrState->AtToneLatch;
  return NextState;
}

CFE_TIME_SysTime CFE_TIME_LatchClock()
{
  CFE_TIME_SysTime LatchTime;
  OS_time_t LocalTime;
  MemSet(&LocalTime, 0, sizeof(OS_time_t));
  // Get time in O/S format (seconds : microseconds)...
  CFE_PSP_GetTime(&LocalTime);
  // Convert time to cFE format (seconds : 1/2^32 subseconds)...
  LatchTime.Seconds = OS_TimeGetTotalSeconds(LocalTime);
  LatchTime.Subseconds = OS_TimeGetSubsecondsPart(LocalTime);
  return LatchTime;
}

U0 CFE_TIME_QueryResetVars()
{
  CFE_TIME_ResetVars_t LocalResetVars;
  U32 DefSubsMET;
  U32 DefSubsSTCF;
  I32 PspStatus;
  CFE_TIME_ReferenceState_t *RefState;
  U32 resetAreaSize;
  U64 resetAreaAddr;
  CFE_ES_ResetData_t *CFE_TIME_ResetDataPtr;
  RefState = CFE_TIME_StartReferenceUpdate();
  // Get the pointer to the Reset area from the BSP
  PspStatus = CFE_PSP_GetResetArea(&resetAreaAddr, &resetAreaSize);
  if (PspStatus != CFE_PSP_SUCCESS) {
    // There is something wrong with the Reset Area
    CFE_TIME_Global.DataStoreStatus = CFE_TIME_RESET_AREA_BAD;
  } else {
    CFE_TIME_ResetDataPtr = resetAreaAddr;
    // Get the structure from the Reset Area. A 32-byte whole-class assignment whose LEFT side is
    // an instance, which has always worked -- the sibling in CFE_TIME_UpdateResetVars goes the
    // other way and needed a compiler fix. docs/HOLYC_STRUCT_LIMITS.md #2.
    LocalResetVars = CFE_TIME_ResetDataPtr->TimeResetVars;
    // Verify TIME data signature and clock signal selection...
    //    (other data fields have no verifiable limits)
    if (LocalResetVars.Signature == CFE_TIME_RESET_SIGNATURE && (LocalResetVars.ClockSignal == CFE_TIME_ToneSignalSelect_PRIMARY || LocalResetVars.ClockSignal == CFE_TIME_ToneSignalSelect_REDUNDANT)) {
      // Initialize TIME to valid  Reset Area values...
      RefState->AtToneMET = LocalResetVars.CurrentMET;
      RefState->AtToneSTCF = LocalResetVars.CurrentSTCF;
      RefState->AtToneDelay = LocalResetVars.CurrentDelay;
      RefState->AtToneLeapSeconds = LocalResetVars.LeapSeconds;
      CFE_TIME_Global.ClockSignal = LocalResetVars.ClockSignal;
      CFE_TIME_Global.DataStoreStatus = CFE_TIME_RESET_AREA_EXISTING;
    } else {
      // We got a blank area from the reset variables
      CFE_TIME_Global.DataStoreStatus = CFE_TIME_RESET_AREA_NEW;
    }
  }
  // Initialize TIME to default values if no valid Reset data...
  if (CFE_TIME_Global.DataStoreStatus != CFE_TIME_RESET_AREA_EXISTING) {
    DefSubsMET = CFE_TIME_Micro2SubSecs(CFE_MISSION_TIME_DEF_MET_SUBS);
    DefSubsSTCF = CFE_TIME_Micro2SubSecs(CFE_MISSION_TIME_DEF_STCF_SUBS);
    RefState->AtToneMET.Seconds = CFE_MISSION_TIME_DEF_MET_SECS;
    RefState->AtToneMET.Subseconds = DefSubsMET;
    RefState->AtToneSTCF.Seconds = CFE_MISSION_TIME_DEF_STCF_SECS;
    RefState->AtToneSTCF.Subseconds = DefSubsSTCF;
    RefState->AtToneLeapSeconds = CFE_MISSION_TIME_DEF_LEAPS;
    CFE_TIME_Global.ClockSignal = CFE_TIME_ToneSignalSelect_PRIMARY;
    RefState->AtToneDelay.Seconds = 0;
    RefState->AtToneDelay.Subseconds = 0;
  }
  CFE_TIME_FinishReferenceUpdate(RefState);
}

U0 CFE_TIME_UpdateResetVars(CFE_TIME_Reference_t *Reference)
{
  CFE_TIME_ResetVars_t LocalResetVars;
  U32 resetAreaSize;
  U64 resetAreaAddr;
  CFE_ES_ResetData_t *CFE_TIME_ResetDataPtr;
  // Update the data only if our Reset Area is valid...
  if (CFE_TIME_Global.DataStoreStatus != CFE_TIME_RESET_AREA_ERROR) {
    // Store all of our critical variables to a ResetVars_t
    LocalResetVars.Signature = CFE_TIME_RESET_SIGNATURE;
    LocalResetVars.CurrentMET = Reference->CurrentMET;
    LocalResetVars.CurrentSTCF = Reference->AtToneSTCF;
    LocalResetVars.CurrentDelay = Reference->AtToneDelay;
    LocalResetVars.LeapSeconds = Reference->AtToneLeapSeconds;
    LocalResetVars.ClockSignal = CFE_TIME_Global.ClockSignal;
    // Get the pointer to the Reset area from the BSP
    if (CFE_PSP_GetResetArea(&resetAreaAddr, &resetAreaSize) == CFE_PSP_SUCCESS) {
      CFE_TIME_ResetDataPtr = resetAreaAddr;
      // THIS LINE is the one that needed the compiler fix: a 32-byte whole-class assignment whose
      // LEFT side is a MEMBER used to copy only the first eight bytes, silently.
      // docs/HOLYC_STRUCT_LIMITS.md #2 and tests/exec/cases/e_struct_assign_member.hc.
      CFE_TIME_ResetDataPtr->TimeResetVars = LocalResetVars;
    }
  }
}

U0 CFE_TIME_InitData()
{
  U32 i;
  CFE_TIME_ReferenceState_t *RefState;
  // Clear task global
  MemSet(&CFE_TIME_Global, 0, sizeof(CFE_TIME_Global_t));
  // Initialize task configuration data...
  for (i = 0; i < CFE_TIME_REFERENCE_BUF_DEPTH; ++i) {
    CFE_TIME_Global.ReferenceState[i].StateVersion = 0xFFFFFFFF;
  }
  // Try to get values used to compute time from Reset Area...
  CFE_TIME_QueryResetVars();
  RefState = CFE_TIME_StartReferenceUpdate();
  // Remaining data values used to compute time...
  RefState->AtToneLatch = CFE_TIME_LatchClock();
  // Data values used to define the current clock state...
  RefState->ClockSetState = CFE_TIME_SetState_NOT_SET;
  RefState->ClockFlyState = CFE_TIME_FlywheelState_IS_FLY;
  // CFE_PLATFORM_TIME_CFG_SOURCE is 0 in this configuration, so the EXTERNAL arm is not built.
  CFE_TIME_Global.ClockSource = CFE_TIME_SourceSelect_INTERNAL;
  CFE_TIME_Global.ServerFlyState = CFE_TIME_FlywheelState_IS_FLY;
  // Pending data values (from "time at tone" command data packet)...
  CFE_TIME_Global.PendingState = CFE_TIME_ClockState_INVALID;
  // Nonzero adjustment values...
  CFE_TIME_Global.OneTimeDirection = CFE_TIME_AdjustDirection_ADD;
  CFE_TIME_Global.OneHzDirection = CFE_TIME_AdjustDirection_ADD;
  RefState->DelayDirection = CFE_TIME_AdjustDirection_ADD;
  // Miscellaneous counters...
  CFE_TIME_Global.VirtualMET = RefState->AtToneMET.Seconds;
  // Time window verification values...
  CFE_TIME_Global.MinElapsed = CFE_TIME_Micro2SubSecs(CFE_MISSION_TIME_MIN_ELAPSED);
  CFE_TIME_Global.MaxElapsed = CFE_TIME_Micro2SubSecs(CFE_MISSION_TIME_MAX_ELAPSED);
  // Range checking for external time source data is under CFE_PLATFORM_TIME_CFG_SOURCE, which is
  // 0 here, so MaxDelta keeps the zero MemSet left in it.
  // Maximum local clock value (before roll-over)...
  CFE_TIME_Global.MaxLocalClock.Seconds = CFE_PLATFORM_TIME_MAX_LOCAL_SECS;
  CFE_TIME_Global.MaxLocalClock.Subseconds = CFE_PLATFORM_TIME_MAX_LOCAL_SUBS;
  // Range limits for time between tone signal interrupts...
  CFE_TIME_Global.ToneOverLimit = CFE_TIME_Micro2SubSecs(CFE_PLATFORM_TIME_CFG_TONE_LIMIT);
  CFE_TIME_Global.ToneUnderLimit = CFE_TIME_Micro2SubSecs(1000000 - CFE_PLATFORM_TIME_CFG_TONE_LIMIT);
  CFE_TIME_FinishReferenceUpdate(RefState);
  // Initialize housekeeping packet (clear user data area)...
  CFE_MSG_Init(&CFE_TIME_Global.HkPacket.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CFE_TIME_HK_TLM_MID), sizeof(CFE_TIME_HousekeepingTlm_t));
  // Initialize diagnostic packet (clear user data area)...
  CFE_MSG_Init(&CFE_TIME_Global.DiagPacket.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CFE_TIME_DIAG_TLM_MID), sizeof(CFE_TIME_DiagnosticTlm_t));
  // Initialize "time at the tone" signal command packet...
  CFE_MSG_Init(&CFE_TIME_Global.ToneSignalCmd.CommandHeader.Msg, CFE_SB_ValueToMsgId(CFE_TIME_TONE_CMD_MID), sizeof(CFE_TIME_ToneSignalCmd_t));
  // Initialize "time at the tone" data command packet (server only, which this port is)...
  CFE_MSG_Init(&CFE_TIME_Global.ToneDataCmd.CommandHeader.Msg, CFE_SB_ValueToMsgId(CFE_TIME_DATA_CMD_MID), sizeof(CFE_TIME_ToneDataCmd_t));
  // Initialize simulated tone send message ("fake tone" mode only, which this port is)...
  CFE_MSG_Init(&CFE_TIME_Global.ToneSendCmd.CommandHeader.Msg, CFE_SB_ValueToMsgId(CFE_TIME_SEND_CMD_MID), sizeof(CFE_TIME_FakeToneCmd_t));
  // Initialize local 1Hz "wake-up" command packet (optional)...
  CFE_MSG_Init(&CFE_TIME_Global.LocalOneHzCmd.CommandHeader.Msg, CFE_SB_ValueToMsgId(CFE_TIME_ONEHZ_CMD_MID), sizeof(CFE_TIME_OneHzCmd_t));
}

U0 CFE_TIME_GetHkData(CFE_TIME_Reference_t *Reference)
{
  // Get command execution counters...
  CFE_TIME_Global.HkPacket.Payload.CommandCounter = CFE_TIME_Global.CommandCounter;
  CFE_TIME_Global.HkPacket.Payload.CommandErrorCounter = CFE_TIME_Global.CommandErrorCounter;
  // Current "as calculated" clock state...
  CFE_TIME_Global.HkPacket.Payload.ClockStateAPI = CFE_TIME_CalculateState(Reference);
  // Current clock state flags...
  CFE_TIME_Global.HkPacket.Payload.ClockStateFlags = CFE_TIME_GetClockInfo();
  // Leap Seconds...
  CFE_TIME_Global.HkPacket.Payload.LeapSeconds = Reference->AtToneLeapSeconds;
  // Current MET and STCF time values...
  CFE_TIME_Global.HkPacket.Payload.MET = Reference->CurrentMET;
  CFE_TIME_Global.HkPacket.Payload.STCF = Reference->AtToneSTCF;
  // 1Hz STCF adjustment values (server only, which this port is). The CLIENT arm assigns
  // Reference->AtToneDelay to the same field and is not built here.
  CFE_TIME_Global.HkPacket.Payload.AdjustmentFactor = CFE_TIME_Global.OneHzAdjust;
}

U0 CFE_TIME_GetDiagData()
{
  CFE_TIME_Reference_t Reference;
  CFE_TIME_SysTime TempTime;
  // Get reference time values (local time, time at tone, etc.)...
  CFE_TIME_GetReference(&Reference);
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.AtToneMET, &Reference.AtToneMET);
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.AtToneSTCF, &Reference.AtToneSTCF);
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.AtToneDelay, &Reference.AtToneDelay);
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.AtToneLatch, &Reference.AtToneLatch);
  CFE_TIME_Global.DiagPacket.Payload.AtToneLeapSeconds = Reference.AtToneLeapSeconds;
  CFE_TIME_Global.DiagPacket.Payload.ClockStateAPI = CFE_TIME_CalculateState(&Reference);
  // Data values that reflect the time (right now)...
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.TimeSinceTone, &Reference.TimeSinceTone);
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.CurrentLatch, &Reference.CurrentLatch);
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.CurrentMET, &Reference.CurrentMET);
  TempTime = CFE_TIME_CalculateTAI(&Reference);
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.CurrentTAI, &TempTime);
  TempTime = CFE_TIME_CalculateUTC(&Reference);
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.CurrentUTC, &TempTime);
  // Data values used to define the current clock state...
  CFE_TIME_Global.DiagPacket.Payload.ClockSetState = Reference.ClockSetState;
  CFE_TIME_Global.DiagPacket.Payload.ClockFlyState = Reference.ClockFlyState;
  CFE_TIME_Global.DiagPacket.Payload.ClockSource = CFE_TIME_Global.ClockSource;
  CFE_TIME_Global.DiagPacket.Payload.ClockSignal = CFE_TIME_Global.ClockSignal;
  CFE_TIME_Global.DiagPacket.Payload.ServerFlyState = CFE_TIME_Global.ServerFlyState;
  CFE_TIME_Global.DiagPacket.Payload.Forced2Fly = CFE_TIME_Global.Forced2Fly;
  // Clock state flags...
  CFE_TIME_Global.DiagPacket.Payload.ClockStateFlags = CFE_TIME_GetClockInfo();
  // STCF adjustment direction values...
  CFE_TIME_Global.DiagPacket.Payload.OneTimeDirection = CFE_TIME_Global.OneTimeDirection;
  CFE_TIME_Global.DiagPacket.Payload.OneHzDirection = CFE_TIME_Global.OneHzDirection;
  CFE_TIME_Global.DiagPacket.Payload.DelayDirection = Reference.DelayDirection;
  // STCF adjustment values...
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.OneTimeAdjust, &CFE_TIME_Global.OneTimeAdjust);
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.OneHzAdjust, &CFE_TIME_Global.OneHzAdjust);
  // Most recent local clock latch values...
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.ToneSignalLatch, &CFE_TIME_Global.ToneSignalLatch);
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.ToneDataLatch, &CFE_TIME_Global.ToneDataLatch);
  // Miscellaneous counters (subject to reset command)...
  CFE_TIME_Global.DiagPacket.Payload.ToneMatchCounter = CFE_TIME_Global.ToneMatchCounter;
  CFE_TIME_Global.DiagPacket.Payload.ToneMatchErrorCounter = CFE_TIME_Global.ToneMatchErrorCounter;
  CFE_TIME_Global.DiagPacket.Payload.ToneSignalCounter = CFE_TIME_Global.ToneSignalCounter;
  CFE_TIME_Global.DiagPacket.Payload.ToneDataCounter = CFE_TIME_Global.ToneDataCounter;
  CFE_TIME_Global.DiagPacket.Payload.ToneIntCounter = CFE_TIME_Global.ToneIntCounter;
  CFE_TIME_Global.DiagPacket.Payload.ToneIntErrorCounter = CFE_TIME_Global.ToneIntErrorCounter;
  CFE_TIME_Global.DiagPacket.Payload.ToneTaskCounter = CFE_TIME_Global.ToneTaskCounter;
  CFE_TIME_Global.DiagPacket.Payload.VersionCounter = CFE_TIME_Global.LastVersionCounter - CFE_TIME_Global.ResetVersionCounter;
  CFE_TIME_Global.DiagPacket.Payload.LocalIntCounter = CFE_TIME_Global.LocalIntCounter;
  CFE_TIME_Global.DiagPacket.Payload.LocalTaskCounter = CFE_TIME_Global.LocalTaskCounter;
  // Miscellaneous counters (not subject to reset command)...
  CFE_TIME_Global.DiagPacket.Payload.VirtualMET = CFE_TIME_Global.VirtualMET;
  // Time window verification values (converted from micro-secs)...
  //
  // Regardless of whether the tone follows the time packet, or vice versa, these values define
  // the acceptable window of time for the second event to follow the first. The minimum value
  // may be as little as zero, and the maximum must be something less than a second.
  CFE_TIME_Global.DiagPacket.Payload.MinElapsed = CFE_TIME_Global.MinElapsed;
  CFE_TIME_Global.DiagPacket.Payload.MaxElapsed = CFE_TIME_Global.MaxElapsed;
  // Maximum local clock value (before roll-over)...
  CFE_TIME_Copy(&CFE_TIME_Global.DiagPacket.Payload.MaxLocalClock, &CFE_TIME_Global.MaxLocalClock);
  // Tone signal tolerance limits...
  CFE_TIME_Global.DiagPacket.Payload.ToneOverLimit = CFE_TIME_Global.ToneOverLimit;
  CFE_TIME_Global.DiagPacket.Payload.ToneUnderLimit = CFE_TIME_Global.ToneUnderLimit;
  // Reset Area access status...
  CFE_TIME_Global.DiagPacket.Payload.DataStoreStatus = CFE_TIME_Global.DataStoreStatus;
}

U0 CFE_TIME_GetReference(CFE_TIME_Reference_t *Reference)
{
  CFE_TIME_SysTime TimeSinceTone;
  CFE_TIME_SysTime CurrentMET;
  U32 VersionCounter;
  U32 RetryCount = 4;
  CFE_TIME_ReferenceState_t *RefState;
  // THE LOCK-FREE READ. VersionCounter is incremented when reference data is modified, so the
  // loop copies a slot and then checks that the version it started from is still the one the
  // slot carries. A writer that overtook the reader shows up as a mismatch and the read retries.
  while (TRUE) {
    VersionCounter = CFE_TIME_Global.LastVersionCounter;
    RefState = &CFE_TIME_Global.ReferenceState[VersionCounter & CFE_TIME_REFERENCE_BUF_MASK];
    Reference->CurrentLatch = CFE_TIME_LatchClock();
    Reference->AtToneMET = RefState->AtToneMET;
    Reference->AtToneSTCF = RefState->AtToneSTCF;
    Reference->AtToneLeapSeconds = RefState->AtToneLeapSeconds;
    Reference->AtToneDelay = RefState->AtToneDelay;
    Reference->AtToneLatch = RefState->AtToneLatch;
    Reference->ClockSetState = RefState->ClockSetState;
    Reference->ClockFlyState = RefState->ClockFlyState;
    Reference->DelayDirection = RefState->DelayDirection;
    if (VersionCounter == RefState->StateVersion) {
      // successful read
      break;
    }
    if (RetryCount == 0) {
      // unsuccessful read
      break;
    }
    --RetryCount;
  }
  if (RetryCount == 0) {
    // set the flag that indicates this failed
    CFE_TIME_Global.GetReferenceFail = TRUE;
    // NASA writes sizeof(*Reference); a `sizeof` of a dereference does not parse in HolyC
    // (HOLYC_STRUCT_LIMITS.md #9), so the type is named. check_padding keeps it the same size.
    MemSet(Reference, 0, sizeof(CFE_TIME_Reference_t));
    return;
  }
  // Compute the amount of time "since" the tone...
  if (CFE_TIME_Compare(Reference->CurrentLatch, Reference->AtToneLatch) == CFE_TIME_A_LT_B) {
    // Local clock has rolled over since last tone...
    TimeSinceTone = CFE_TIME_Subtract(CFE_TIME_Global.MaxLocalClock, Reference->AtToneLatch);
    TimeSinceTone = CFE_TIME_Add(TimeSinceTone, Reference->CurrentLatch);
  } else {
    // Normal case -- local clock is greater than latch at tone...
    TimeSinceTone = CFE_TIME_Subtract(Reference->CurrentLatch, Reference->AtToneLatch);
  }
  Reference->TimeSinceTone = TimeSinceTone;
  // Add in the MET at the tone...
  CurrentMET = CFE_TIME_Add(TimeSinceTone, Reference->AtToneMET);
  // Synchronizing a time CLIENT to the server applies AtToneDelay here, under
  // CFE_PLATFORM_TIME_CFG_CLIENT, which is 0 in this configuration.
  Reference->CurrentMET = CurrentMET;
}

CFE_TIME_SysTime CFE_TIME_CalculateTAI(CFE_TIME_Reference_t *Reference)
{
  CFE_TIME_SysTime TimeAsTAI;
  TimeAsTAI = CFE_TIME_Add(Reference->CurrentMET, Reference->AtToneSTCF);
  return TimeAsTAI;
}

CFE_TIME_SysTime CFE_TIME_CalculateUTC(CFE_TIME_Reference_t *Reference)
{
  CFE_TIME_SysTime TimeAsUTC;
  TimeAsUTC = CFE_TIME_Add(Reference->CurrentMET, Reference->AtToneSTCF);
  TimeAsUTC.Seconds -= Reference->AtToneLeapSeconds;
  return TimeAsUTC;
}

I32 CFE_TIME_CalculateState(CFE_TIME_Reference_t *Reference)
{
  I32 ClockState;
  // Determine the current clock state...
  if (Reference->ClockSetState == CFE_TIME_SetState_WAS_SET) {
    if (Reference->ClockFlyState == CFE_TIME_FlywheelState_NO_FLY) {
      // CFE_TIME_ClockState_VALID = clock set and not fly-wheeling...
      ClockState = CFE_TIME_ClockState_VALID;
      // A CLIENT must report fly-wheel when the server is fly-wheeling even if it is not; that
      // arm is under CFE_PLATFORM_TIME_CFG_CLIENT, which is 0 here.
    } else {
      // CFE_TIME_ClockState_FLYWHEEL = clock set and fly-wheeling...
      ClockState = CFE_TIME_ClockState_FLYWHEEL;
    }
  } else {
    // CFE_TIME_ClockState_INVALID = clock not set...
    ClockState = CFE_TIME_ClockState_INVALID;
  }
  return ClockState;
}

U0 CFE_TIME_SetState(I32 NewState)
{
  CFE_TIME_ReferenceState_t *RefState;
  RefState = CFE_TIME_StartReferenceUpdate();
  // If we get a command to set the clock to "flywheel" mode, then set a global flag so that we
  // can choose to ignore time updates until we get another clock state command...
  if (NewState == CFE_TIME_ClockState_FLYWHEEL) {
    CFE_TIME_Global.Forced2Fly = TRUE;
    RefState->ClockFlyState = CFE_TIME_FlywheelState_IS_FLY;
    // SERVER only, which this port is.
    CFE_TIME_Global.ServerFlyState = CFE_TIME_FlywheelState_IS_FLY;
  } else if (NewState == CFE_TIME_ClockState_VALID) {
    CFE_TIME_Global.Forced2Fly = FALSE;
    RefState->ClockSetState = CFE_TIME_SetState_WAS_SET;
  } else {
    CFE_TIME_Global.Forced2Fly = FALSE;
    RefState->ClockSetState = CFE_TIME_SetState_NOT_SET;
  }
  // Time has changed, force anyone reading time to retry...
  CFE_TIME_FinishReferenceUpdate(RefState);
}
// NOT TRANSLATED, because this configuration does not build them:
//   CFE_TIME_SetSource   under CFE_PLATFORM_TIME_CFG_SOURCE   (0 here)
//   CFE_TIME_SetSignal   under CFE_PLATFORM_TIME_CFG_SIGNAL   (0 here)
//   CFE_TIME_SetDelay    under CFE_PLATFORM_TIME_CFG_CLIENT   (0 here)
// All three are whole-function conditional bodies in cfe_time_utils.c, so the C the oracle links does not
// contain them either -- which is what makes leaving them out checkable rather than a gap. Each
// is listed in check_coverage.py's CONFIG_EXCLUDED with its guard.
U0 CFE_TIME_SetTime(CFE_TIME_SysTime NewTime)
{
  CFE_TIME_ReferenceState_t *RefState;
  // The input to this function is a time value that includes MET and STCF. If the default time
  // format is UTC, the input time value has had leaps seconds removed from the total.
  CFE_TIME_Reference_t Reference;
  CFE_TIME_SysTime NewSTCF;
  // Get reference time values (local time, time at tone, etc.)...
  CFE_TIME_GetReference(&Reference);
  // Remove current MET from the new time value (leaves STCF)...
  NewSTCF = CFE_TIME_Subtract(NewTime, Reference.CurrentMET);
  // Leap seconds would be restored here if the default format were UTC;
  // CFE_MISSION_TIME_CFG_DEFAULT_UTC is 0 and DEFAULT_TAI is 1 in this configuration.
  RefState = CFE_TIME_StartReferenceUpdate();
  RefState->AtToneSTCF = NewSTCF;
  // Time has changed, force anyone reading time to retry...
  CFE_TIME_FinishReferenceUpdate(RefState);
}

U0 CFE_TIME_SetMET(CFE_TIME_SysTime NewMET)
{
  CFE_TIME_ReferenceState_t *RefState;
  RefState = CFE_TIME_StartReferenceUpdate();
  // Update reference values used to compute current time...
  RefState->AtToneMET = NewMET;
  CFE_TIME_Global.VirtualMET = NewMET.Seconds;
  RefState->AtToneLatch = CFE_TIME_LatchClock();
  // A hardware MET register would be written here; CFE_PLATFORM_TIME_CFG_VIRTUAL is 1, so the
  // MET is software and OS_SetLocalMET is not called.
  // Time has changed, force anyone reading time to retry...
  CFE_TIME_FinishReferenceUpdate(RefState);
}

U0 CFE_TIME_SetSTCF(CFE_TIME_SysTime NewSTCF)
{
  CFE_TIME_ReferenceState_t *RefState;
  RefState = CFE_TIME_StartReferenceUpdate();
  RefState->AtToneSTCF = NewSTCF;
  // Time has changed, force anyone reading time to retry...
  CFE_TIME_FinishReferenceUpdate(RefState);
}

U0 CFE_TIME_SetLeapSeconds(I16 NewLeaps)
{
  CFE_TIME_ReferenceState_t *RefState;
  RefState = CFE_TIME_StartReferenceUpdate();
  RefState->AtToneLeapSeconds = NewLeaps;
  // Time has changed, force anyone reading time to retry...
  CFE_TIME_FinishReferenceUpdate(RefState);
}

U0 CFE_TIME_SetAdjust(CFE_TIME_SysTime NewAdjust, I16 Direction)
{
  CFE_TIME_SysTime NewSTCF;
  CFE_TIME_ReferenceState_t *RefState;
  RefState = CFE_TIME_StartReferenceUpdate();
  CFE_TIME_Global.OneTimeAdjust = NewAdjust;
  CFE_TIME_Global.OneTimeDirection = Direction;
  if (Direction == CFE_TIME_AdjustDirection_ADD) {
    NewSTCF = CFE_TIME_Add(RefState->AtToneSTCF, NewAdjust);
  } else {
    NewSTCF = CFE_TIME_Subtract(RefState->AtToneSTCF, NewAdjust);
  }
  RefState->AtToneSTCF = NewSTCF;
  // Time has changed, force anyone reading time to retry...
  CFE_TIME_FinishReferenceUpdate(RefState);
}

U0 CFE_TIME_Set1HzAdj(CFE_TIME_SysTime NewAdjust, I16 Direction)
{
  // Store values for 1Hz adjustment...
  CFE_TIME_Global.OneHzAdjust = NewAdjust;
  CFE_TIME_Global.OneHzDirection = Direction;
}

I32 CFE_TIME_CleanUpApp(U32 Id)
{
  I32 Status;
  U32 AppIndex;
  U32 AppId;
  AppId = CFE_ResourceId_FromInteger(Id);
  Status = CFE_ES_AppID_ToIndex(AppId, &AppIndex);
  if (Status != CFE_SUCCESS) {
    // Do nothing
  } else if (AppIndex < CFE_PLATFORM_ES_MAX_APPLICATIONS) {
    // NASA writes sizeof(..SynchCallback)/sizeof(..SynchCallback[0]); neither spelling parses in
    // HolyC (HOLYC_STRUCT_LIMITS.md #9), and the quotient IS the array's bound, which
    // check_padding verifies is CFE_PLATFORM_ES_MAX_APPLICATIONS.
    CFE_TIME_Global.SynchCallback[AppIndex].Ptr = NULL;
  } else {
    Status = CFE_TIME_CALLBACK_NOT_REGISTERED;
  }
  return Status;
}

// --- CONSTANTS NASA'S HEADER DECLARES AND NO SOURCE USES -------------------------------------
//
// Dead upstream: a grep across every .c in the repository finds no use of CFE_TIME_TASK_NAME. They are translated anyway
// because they are part of the header's declared interface and cost nothing, which is the answer
// that needs no judgement -- and because tools/cfs/check_defines.py now refuses a #define that is
// nowhere in the translation. That gate was written after a case-sensitive grep silently dropped
// EIGHT of HS's event ids; these nineteen are what it found on its first run, across six years of
// this port's history.
#define CFE_TIME_TASK_NAME "CFE_TIME"

#endif
