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
// 1:1 HolyC translation of cFE modules/time/fsw/src/cfe_time_tone.c -- the detection and
// processing of the "time at the tone" signal, and the local 1Hz interrupt.
//
// WHAT THIS FILE IS ABOUT. A spacecraft's clock is a pulse-per-second signal plus a packet that
// says what time that pulse was. The two arrive separately and either can be late, lost or
// duplicated, so nothing here trusts a single one of them: CFE_TIME_ToneVerify only accepts a
// SIGNAL and a PACKET that are a MATCHED PAIR -- neither repeats the previous one, and the gap
// between them is inside a configured window -- and only a matched pair is allowed to move the
// published time reference. When a pair stops arriving the clock goes to "flywheel": it keeps
// counting on the local oscillator and says so in its telemetry, which is the honest answer
// rather than a stalled one.
//
// This port is a TIME SERVER with a VIRTUAL MET (CFE_PLATFORM_TIME_CFG_SERVER 1,
// CFE_PLATFORM_TIME_CFG_VIRTUAL 1), so the mission elapsed time is a count of valid tone
// interrupts rather than a hardware register, and the three external-source variants
// (CFE_TIME_ToneSendMET/GPS/Time) are compiled out -- see the note at the bottom of this file.
// CFE_MISSION_TIME_AT_TONE_WAS is 1, so the packet is expected AFTER the pulse; the "will be"
// halves of ToneSend, ToneData and ToneSignal are the ones NASA's preprocessor drops.
// THIS FILE CONTAINS NO `#if`, AND THAT IS DELIBERATE. This compiler's `#if <expr>` is
// UNCONDITIONALLY TRUE -- host/lexer.c handles only a literal `0`, so `#if (SOMETHING == 1)` is
// compiled in however SOMETHING is defined, silently. docs/HOLYC_STRUCT_LIMITS.md #15. NASA's
// configuration directives are therefore resolved BY HAND here, each one replaced by a bracketed
// comment naming the guard, its value and which branch survived, so the translation can still be
// read against the C line for line. Every other TIME file that landed before this one does the
// same thing, cfe_time_utils.HC included; what is new is that these three had enough
// configuration in them to make the silence dangerous rather than merely untidy -- written with
// the directives in place, the first version of this file referenced CFE_TIME_SetDelay,
// CFE_TIME_SetSignal, CFE_TIME_SetSource, OS_GetLocalMET and OS_SelectTone, none of which this
// configuration builds. The blob's import trailer is what caught it.
//
#ifndef CFE_TIME_TONE_HC
#define CFE_TIME_TONE_HC
#include "cfe_time_global.HC"  // the types, the constants and CFE_TIME_Global
// --- cfe_time_eventids.h ----------------------------------------------------------------------
#define CFE_TIME_FLY_ON_EID  20
#define CFE_TIME_FLY_OFF_EID 21
// --- cfe_time_internal_cfg.h: the two flywheel thresholds, in SECONDS since the last tone ------
// START_FLY is how long the clock will wait for a tone before admitting it is flywheeling.
// LATCH_FLY is how often, once flywheeling, it rolls the "time at tone" forward -- not for
// accuracy, which it cannot improve, but so the elapsed-time-since-tone number stays small. A
// local clock that rolls over every few seconds would otherwise wrap PAST the latched tone and
// the subtraction would give a time in the future.
#define CFE_PLATFORM_TIME_CFG_START_FLY 2
#define CFE_PLATFORM_TIME_CFG_LATCH_FLY 8
// --- cfe_perfids.h ----------------------------------------------------------------------------
#define CFE_MISSION_TIME_TONE1HZISR_PERF_ID   7
#define CFE_MISSION_TIME_LOCAL1HZISR_PERF_ID  8
#define CFE_MISSION_TIME_LOCAL1HZTASK_PERF_ID 10
#define CFE_MISSION_TIME_TONE1HZTASK_PERF_ID  11
// --- cfe_mission_cfg.h: the packet arrives AFTER the pulse ------------------------------------
// Exactly one of these is true; cfe_time_verify.h enforces it upstream.
#ifndef CFE_MISSION_TIME_AT_TONE_WILL_BE
#define CFE_MISSION_TIME_AT_TONE_WILL_BE 0
#endif
// --- what this file needs from elsewhere ------------------------------------------------------
// cfe_time_utils.c and cfe_time_api.c, translated beside this one.
U0 CFE_TIME_GetReference(CFE_TIME_Reference_t *Reference);
CFE_TIME_SysTime CFE_TIME_LatchClock();
I32 CFE_TIME_CalculateState(CFE_TIME_Reference_t *Reference);
CFE_TIME_ReferenceState_t *CFE_TIME_StartReferenceUpdate();
U0 CFE_TIME_FinishReferenceUpdate(CFE_TIME_ReferenceState_t *NextState);
CFE_TIME_SysTime CFE_TIME_Add(CFE_TIME_SysTime Time1, CFE_TIME_SysTime Time2);
CFE_TIME_SysTime CFE_TIME_Subtract(CFE_TIME_SysTime Time1, CFE_TIME_SysTime Time2);
I32 CFE_TIME_Compare(CFE_TIME_SysTime TimeA, CFE_TIME_SysTime TimeB);
// Defined further down this file and called from above it.
U0 CFE_TIME_ToneVerify(CFE_TIME_SysTime Time1, CFE_TIME_SysTime Time2);
U0 CFE_TIME_ToneUpdate();
U0 CFE_TIME_Local1HzISR();
U0 CFE_TIME_NotifyTimeSynchApps();
// SB, ES, EVS and OSAL. None of ES is translated and the differential oracle supplies the
// recording stubs for both sides, which is the arrangement cfe_ta_task.HC records.
I32 CFE_SB_TransmitMsg(CFE_MSG_Message *MsgPtr, Bool IncrementSequenceCount);
U0 CFE_ES_PerfLogEntry(U32 Marker);
U0 CFE_ES_PerfLogExit(U32 Marker);
U0 CFE_ES_IncrementTaskCounter();
I32 CFE_EVS_SendEvent(U16 EventID, U16 EventType, U8 *Spec,...);
I32 OS_BinSemGive(U32 sem_id);
I32 OS_BinSemTake(U32 sem_id);
U8 *MemSet(U8 *dst, I64 dat, I64 size);
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
U0 CFE_TIME_ToneSend()
{
  CFE_TIME_Reference_t Reference;
  CFE_TIME_SysTime NewMET;
  /* Zero out the Reference variable because we pass it into
   * a function before using it
   * */
  MemSet(&Reference, 0, sizeof(CFE_TIME_Reference_t));
  /*
  ** Get reference time values (local time, time at tone, etc.)...
  */
  CFE_TIME_GetReference(&Reference);
  /*
  ** Get the new MET from the appropriate source...
  */
  if (Reference.ClockFlyState == CFE_TIME_FlywheelState_IS_FLY) {
    /*
    ** At least one of the following conditions is true...
    **
    **  1) loss of tone signal
    **  2) loss of "time at the tone" data packet
    **  3) signal and packet not within valid window
    **  4) we were commanded into fly-wheel mode
    **
    ** Set the new MET to our fly-wheel best guess...
    */
    NewMET.Seconds = Reference.CurrentMET.Seconds;
  } else {
    /*
    ** MET seconds is the count of tone interrupts...
    */
    // [#if CFE_PLATFORM_TIME_CFG_VIRTUAL == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_VIRTUAL is 1); NASA's directive resolved by hand]
    NewMET.Seconds = CFE_TIME_Global.VirtualMET;
    /*
    ** Read MET seconds from a h/w register...
    */
    // [#if CFE_PLATFORM_TIME_CFG_VIRTUAL != 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_VIRTUAL is 1); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
  }
  /*
  ** Add a second if the tone has not yet occurred...
  */
  // [#if CFE_MISSION_TIME_AT_TONE_WILL_BE == 1 -- FALSE here (CFE_MISSION_TIME_AT_TONE_WILL_BE is 0); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
  /*
  ** Need to fix this if the tone is not 1Hz...
  */
  NewMET.Subseconds = 0;
  /*
  ** Remainder of time values are unchanged...
  */
  // NASA's `#ifdef CFE_PLATFORM_TIME_CFG_BIGENDIAN` half, which byte-swaps every field of the
  // payload, is not built here: RISC-V is little-endian and the macro is undefined, exactly as
  // on an x86 build of cFE. The payload is therefore platform-endian, which is what
  // CFE_TIME_ToneData below expects to read back.
  CFE_TIME_Copy(&CFE_TIME_Global.ToneDataCmd.Payload.AtToneMET, &NewMET);
  CFE_TIME_Copy(&CFE_TIME_Global.ToneDataCmd.Payload.AtToneSTCF, &Reference.AtToneSTCF);
  CFE_TIME_Global.ToneDataCmd.Payload.AtToneLeapSeconds = Reference.AtToneLeapSeconds;
  /*
  ** Current clock state is a combination of factors...
  */
  CFE_TIME_Global.ToneDataCmd.Payload.AtToneState = CFE_TIME_CalculateState(&Reference);
  /*
  ** Send "time at the tone" command data packet...
  */
  CFE_SB_TransmitMsg(&CFE_TIME_Global.ToneDataCmd.CommandHeader.Msg, TRUE);
  /*
  ** Count of "time at the tone" commands sent with internal data...
  */
  CFE_TIME_Global.InternalCount++;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_ToneData(CFE_TIME_ToneDataCmd_Payload_t *ToneDataCmd)
{
  /*
  ** Save the time when the data packet was received...
  */
  CFE_TIME_Global.ToneDataLatch = CFE_TIME_LatchClock();
  /*
  ** Save the data packet (may be a while before the data is used)...
  */
  CFE_TIME_Copy(&CFE_TIME_Global.PendingMET, &ToneDataCmd->AtToneMET);
  CFE_TIME_Copy(&CFE_TIME_Global.PendingSTCF, &ToneDataCmd->AtToneSTCF);
  CFE_TIME_Global.PendingLeaps = ToneDataCmd->AtToneLeapSeconds;
  CFE_TIME_Global.PendingState = ToneDataCmd->AtToneState;
  /*
  ** If the data packet is designed to arrive after the tone...
  **
  ** Check to see if the most recent tone signal matches this
  **    data packet.  If so, we have a matched pair and can
  **    now start using the new data to compute time.
  */
  // [#if CFE_MISSION_TIME_AT_TONE_WAS == 1 -- TRUE here (CFE_MISSION_TIME_AT_TONE_WAS is 1); NASA's directive resolved by hand]
  CFE_TIME_ToneVerify(CFE_TIME_Global.ToneSignalLatch, CFE_TIME_Global.ToneDataLatch);
  /*
  ** If the data packet is designed to arrive before the tone...
  **
  ** We don't really need to do anything except to save the time
  **    and contents of this data packet.  (above)
  **
  ** Note that we do not immediately start using the data packet
  **    values to compute current time.  We continue to use the
  **    old tone/data combo until we get a new matched pair.
  */
  // [#if CFE_MISSION_TIME_AT_TONE_WILL_BE == 1 -- FALSE here (CFE_MISSION_TIME_AT_TONE_WILL_BE is 0); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
  /*
  ** Maintain a count of tone data packets...
  */
  CFE_TIME_Global.ToneDataCounter++;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_ToneSignal()
{
  /*
  ** If the data packet is designed to arrive after the tone signal...
  **
  ** We don't really need to do anything except latch the local clock
  **    at the moment of the tone.  And that has already happened at
  **    the time when the tone was detected.
  **
  ** Note that we do not immediately start using this latched value to
  **    compute current time.  We continue to use the old tone/data
  **    combo until we get a new matched pair.
  */
  // [#if CFE_MISSION_TIME_AT_TONE_WAS == 1 -- TRUE here (CFE_MISSION_TIME_AT_TONE_WAS is 1); NASA's directive resolved by hand]
  /*
  ** If the data packet is designed to arrive before the tone signal...
  **
  ** Check to see if the most recent data packet matches this
  **    tone signal.  If so, we have a matched pair and can
  **    now start using the new data to compute time.
  */
  // [#if CFE_MISSION_TIME_AT_TONE_WILL_BE == 1 -- FALSE here (CFE_MISSION_TIME_AT_TONE_WILL_BE is 0); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
  /*
  ** Maintain a count of tone signal packets...
  */
  CFE_TIME_Global.ToneSignalCounter++;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_ToneVerify(CFE_TIME_SysTime Time1, CFE_TIME_SysTime Time2)
{
  I32 result;
  CFE_TIME_SysTime elapsed;
  // NASA writes `static CFE_TIME_SysTime_t PrevTime1 = {0, 0};`. HolyC has no aggregate
  // initialiser, and these must be ZERO ON THE FIRST CALL and PRESERVED between calls -- the
  // whole duplicate-detection below is a comparison against them -- so they rely on a static
  // local starting zeroed. tests/exec/cases/e_static_local_class_zero.hc gates exactly that,
  // because "it happened to work" is not a thing to find out from a spacecraft clock.
  static CFE_TIME_SysTime PrevTime1;
  static CFE_TIME_SysTime PrevTime2;
  result = CFE_TIME_Compare(PrevTime1, Time1);
  if (result == CFE_TIME_EQUAL) {
    CFE_TIME_Global.ToneMatchErrorCounter++;
  } else {
    result = CFE_TIME_Compare(PrevTime2, Time2);
    if (result == CFE_TIME_EQUAL) {
      CFE_TIME_Global.ToneMatchErrorCounter++;
    } else {
      /*
      ** Compute elapsed time between tone and data packet...
      */
      result = CFE_TIME_Compare(Time1, Time2);
      if (result == CFE_TIME_A_GT_B) {
        /*
        ** Local clock has rolled over...
        */
        elapsed = CFE_TIME_Subtract(CFE_TIME_Global.MaxLocalClock, Time1);
        elapsed = CFE_TIME_Add(elapsed, Time2);
      } else {
        /*
        ** Normal case...
        */
        elapsed = CFE_TIME_Subtract(Time2, Time1);
      }
      /*
      ** Ensure that time between packet and tone is within limits...
      */
      if ((elapsed.Seconds != 0) || (elapsed.Subseconds < CFE_TIME_Global.MinElapsed) || (elapsed.Subseconds > CFE_TIME_Global.MaxElapsed)) {
        /*
        ** Maintain count of tone vs data packet mis-matches...
        */
        CFE_TIME_Global.ToneMatchErrorCounter++;
      } else {
        CFE_TIME_Global.ToneMatchCounter++;
        /*
        ** Skip tone packet update if commanded into "flywheel" mode...
        */
        if (!CFE_TIME_Global.Forced2Fly) {
          /*
          ** Process "matching" tone and data packet...
          */
          CFE_TIME_ToneUpdate();
        }
      }
    }
  }
  PrevTime1 = Time1;
  PrevTime2 = Time2;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_ToneUpdate()
{
  CFE_TIME_Reference_t Reference;
  Bool NewFlywheelStatus = FALSE;
  CFE_TIME_ReferenceState_t *NextState;
  /*
  ** Get current reference state before starting any update
  **
  ** If we have been flywheeling, VirtualMET may be incorrect
  **  (e.g. missing tone signals -- VirtualMET is tone count)
  */
  CFE_TIME_GetReference(&Reference);
  /*
  ** Ensure that reader(s) know of the pending update
  */
  NextState = CFE_TIME_StartReferenceUpdate();
  // [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
  /*
  ** Time servers cannot always use the new time data from the
  **    packet (saved as "pending" when the packet arrived).
  **
  ** If the time source is "internal" then the time data came
  **    from the same values that we would be updating, hence
  **    there is no need to do the update.  And if there has
  **    been a command to set new values during the moment
  **    between making the time at the tone packet and now,
  **    then we would want to use the command values anyway.
  **
  ** If the time source is "external" then things get complex.
  **    If the external data is MET then we only want to take
  **    the MET from the packet.  But, if the external data
  **    is "time" then we only want to take the STCF from the
  **    packet.  And, if the external data is GPS then we
  **    need to take both the STCF and the leap seconds from
  **    the packet.  Also, by definition, we cannot have both
  **    external data and a local h/w MET - so we don't need
  **    to worry about updating a local MET to external time.
  */
  NextState->AtToneLatch = CFE_TIME_Global.ToneSignalLatch;
  if (CFE_TIME_Global.ClockSource == CFE_TIME_SourceSelect_INTERNAL) {
    /*
    ** If we have been flywheeling, VirtualMET may be incorrect
    **  (flywheel state is changed later in this function)
    */
    if (NextState->ClockFlyState == CFE_TIME_FlywheelState_IS_FLY) {
      CFE_TIME_Global.VirtualMET = Reference.CurrentMET.Seconds;
    }
    /*
    ** Update "time at tone" to match virtual MET counter...
    **
    ** Note: It is OK to not bother with reading the h/w MET
    **       since we sync'ed them at the moment of the tone.
    */
    NextState->AtToneMET.Seconds = CFE_TIME_Global.VirtualMET;
    NextState->AtToneMET.Subseconds = 0;
  } else {
    /*
    ** Update "time at tone" with external MET data...
    */
    // [#if CFE_PLATFORM_TIME_CFG_SRC_MET == 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_SRC_MET is 0); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
    /*
    ** Update "time at tone" with external GPS data...
    **
    **  STCF = GPS time at the tone - local MET at the tone
    **  Leaps = GPS leaps
    **
    ** It is possible that a command changed the MET after it was used
    **    to calculate the pending STCF -- in which case the current
    **    time will jump next second when the STCF gets calculated
    **    again with the new MET value.  This (small) possibility can
    **    be prevented by switching to "internal" mode before sending
    **    set time commands...
    */
    // [#if CFE_PLATFORM_TIME_CFG_SRC_GPS == 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_SRC_GPS is 0); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
    /*
    ** Update "time at tone" with external time data...
    **
    **  STCF = external time at the tone - local MET at the tone
    */
    // [#if CFE_PLATFORM_TIME_CFG_SRC_TIME == 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_SRC_TIME is 0); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
  }
  /*
  ** With a "time" update, this server cannot be "flywheeling"
  **  (we won't get this update if commanded to flywheel)
  */
  if (NextState->ClockFlyState == CFE_TIME_FlywheelState_IS_FLY) {
    NextState->ClockFlyState = CFE_TIME_FlywheelState_NO_FLY;
    CFE_TIME_Global.ServerFlyState = CFE_TIME_FlywheelState_NO_FLY;
    NewFlywheelStatus = TRUE;
  }
  // [#if CFE_PLATFORM_TIME_CFG_CLIENT == 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_CLIENT is 0); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
  /*
  ** Complete the time update.
  */
  CFE_TIME_FinishReferenceUpdate(NextState);
  /*
  ** Wait until after interrupts are enabled to send event...
  */
  if (NewFlywheelStatus) {
    CFE_EVS_SendEvent(CFE_TIME_FLY_OFF_EID, CFE_EVS_EventType_INFORMATION, "Stop FLYWHEEL");
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_Local1HzTimerCallback(U32 TimerId, U8 *Arg)
{
  CFE_TIME_Local1HzISR();
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_Tone1HzISR()
{
  CFE_TIME_SysTime ToneSignalLatch;
  CFE_TIME_SysTime Elapsed;
  I32 Result;
  /* Start Performance Monitoring */
  CFE_ES_PerfLogEntry(CFE_MISSION_TIME_TONE1HZISR_PERF_ID);
  /*
  ** Latch the local clock when the tone signal occurred...
  */
  ToneSignalLatch = CFE_TIME_LatchClock();
  /*
  ** Compute elapsed time since the previous tone signal...
  */
  Result = CFE_TIME_Compare(ToneSignalLatch, CFE_TIME_Global.ToneSignalLatch);
  if (Result == CFE_TIME_A_LT_B) {
    /*
    ** Local clock has rolled over...
    */
    Elapsed = CFE_TIME_Subtract(CFE_TIME_Global.MaxLocalClock, CFE_TIME_Global.ToneSignalLatch);
    Elapsed = CFE_TIME_Add(Elapsed, ToneSignalLatch);
  } else {
    /*
    ** Normal case...
    */
    Elapsed = CFE_TIME_Subtract(ToneSignalLatch, CFE_TIME_Global.ToneSignalLatch);
  }
  /*
  ** Verify that tone occurred ~1 second after previous tone...
  */
  if (((Elapsed.Seconds == 1) && (Elapsed.Subseconds < CFE_TIME_Global.ToneOverLimit)) || ((Elapsed.Seconds == 0) && (Elapsed.Subseconds > CFE_TIME_Global.ToneUnderLimit))) {
    /*
    ** Maintain count of valid tone signal interrupts...
    **   (set to zero by reset command)
    */
    CFE_TIME_Global.ToneIntCounter++;
    /* Since the tone occurred ~1 seconds after the previous one, we
    ** can mark this tone as 'good'
    */
    CFE_TIME_Global.IsToneGood = TRUE;
    /*
    ** Maintain virtual MET as count of valid tone signal interrupts...
    **   (not set to zero by reset command)
    */
    // [#if CFE_PLATFORM_TIME_CFG_VIRTUAL == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_VIRTUAL is 1); NASA's directive resolved by hand]
    CFE_TIME_Global.VirtualMET++;
    /*
    ** Maintain virtual MET as count read from h/w MET register...
    */
    // [#if CFE_PLATFORM_TIME_CFG_VIRTUAL != 1 -- FALSE here (CFE_PLATFORM_TIME_CFG_VIRTUAL is 1); NASA's block is omitted, and check_coverage.py's CONFIG_EXCLUDED is what verifies that]
    /*
    ** Enable tone task (we can't send a SB message from here)...
    */
    OS_BinSemGive(CFE_TIME_Global.ToneSemaphore);
  } else {
    /*
    ** Maintain count of invalid tone signal interrupts...
    **   (set to zero by reset command)
    */
    CFE_TIME_Global.ToneIntErrorCounter++;
    /* Since the tone didn't occur ~1 seconds after the previous one, we
    ** can mark this tone as 'not good'
    */
    CFE_TIME_Global.IsToneGood = FALSE;
  }
  /*
  ** Save local time latch of most recent tone signal...
  */
  CFE_TIME_Global.ToneSignalLatch = ToneSignalLatch;
  /* Notify registered time synchronization applications */
  CFE_TIME_NotifyTimeSynchApps();
  /* Exit performance monitoring */
  CFE_ES_PerfLogExit(CFE_MISSION_TIME_TONE1HZISR_PERF_ID);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_Tone1HzTask()
{
  I32 OsStatus;
  while (TRUE) {
    /* Increment the Main task Execution Counter */
    CFE_ES_IncrementTaskCounter();
    /*
    ** Pend on semaphore given by tone ISR (above)...
    */
    OsStatus = OS_BinSemTake(CFE_TIME_Global.ToneSemaphore);
    if (OsStatus != OS_SUCCESS) {
      break;
    }
    /* Start Performance Monitoring */
    CFE_ES_PerfLogEntry(CFE_MISSION_TIME_TONE1HZTASK_PERF_ID);
    /*
    ** Send tone signal command packet...
    */
    CFE_SB_TransmitMsg(&CFE_TIME_Global.ToneSignalCmd.CommandHeader.Msg, TRUE);
    // [#if CFE_MISSION_TIME_CFG_FAKE_TONE == 1 -- TRUE here (CFE_MISSION_TIME_CFG_FAKE_TONE is 1); NASA's directive resolved by hand]
    /*
    ** If we are simulating the tone signal, also generate the message
    ** to send the tone to other time clients.
    ** (this is done by scheduler in non-fake mode)
    */
    CFE_SB_TransmitMsg(&CFE_TIME_Global.ToneSendCmd.CommandHeader.Msg, TRUE);
    /*
    ** Maintain count of tone task wake-ups...
    */
    CFE_TIME_Global.ToneTaskCounter++;
    /* Exit performance monitoring */
    CFE_ES_PerfLogExit(CFE_MISSION_TIME_TONE1HZTASK_PERF_ID);
  }
  /*
  ** This should never happen - but during development we
  **    had an error in the creation of the semaphore.
  */
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_Local1HzStateMachine()
{
  CFE_TIME_Reference_t Reference;
  CFE_TIME_ReferenceState_t *NextState;
  /* Start Performance Monitoring */
  CFE_ES_PerfLogEntry(CFE_MISSION_TIME_LOCAL1HZISR_PERF_ID);
  /* Zero out the Reference variable because we pass it into
   * a function before using it
   * */
  MemSet(&Reference, 0, sizeof(CFE_TIME_Reference_t));
  /*
  ** Apply 1Hz adjustment to STCF...
  */
  // [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
  if ((CFE_TIME_Global.OneHzAdjust.Seconds != 0) || (CFE_TIME_Global.OneHzAdjust.Subseconds != 0)) {
    CFE_TIME_SysTime NewSTCF;
    NextState = CFE_TIME_StartReferenceUpdate();
    if (CFE_TIME_Global.OneHzDirection == CFE_TIME_AdjustDirection_ADD) {
      NewSTCF = CFE_TIME_Add(NextState->AtToneSTCF, CFE_TIME_Global.OneHzAdjust);
    } else {
      NewSTCF = CFE_TIME_Subtract(NextState->AtToneSTCF, CFE_TIME_Global.OneHzAdjust);
    }
    NextState->AtToneSTCF = NewSTCF;
    /*
    ** Time has changed, force anyone reading time to retry...
    */
    CFE_TIME_FinishReferenceUpdate(NextState);
  }
  /*
  ** Get reference time (calculates time since tone, etc.)...
  */
  CFE_TIME_GetReference(&Reference);
  /*
  ** See if it has been long enough without receiving a time update
  **    to autonomously start "fly-wheel" mode...
  */
  if (Reference.ClockFlyState == CFE_TIME_FlywheelState_NO_FLY) {
    if (Reference.TimeSinceTone.Seconds >= CFE_PLATFORM_TIME_CFG_START_FLY) {
      NextState = CFE_TIME_StartReferenceUpdate();
      /*
      ** Change current state to "fly-wheel"...
      */
      NextState->ClockFlyState = CFE_TIME_FlywheelState_IS_FLY;
      // [#if CFE_PLATFORM_TIME_CFG_SERVER == 1 -- TRUE here (CFE_PLATFORM_TIME_CFG_SERVER is 1); NASA's directive resolved by hand]
      CFE_TIME_Global.ServerFlyState = CFE_TIME_FlywheelState_IS_FLY;
      CFE_TIME_Global.AutoStartFly = TRUE;
      /*
      ** Force anyone currently reading time to retry...
      */
      CFE_TIME_FinishReferenceUpdate(NextState);
    }
  }
  /*
  ** See if it has been long enough without receiving a time update
  **    (or since last doing this update) to autonomously update the
  **    MET at the tone and local clock latched at the tone...
  */
  if (Reference.ClockFlyState == CFE_TIME_FlywheelState_IS_FLY) {
    if (Reference.TimeSinceTone.Seconds >= CFE_PLATFORM_TIME_CFG_LATCH_FLY) {
      NextState = CFE_TIME_StartReferenceUpdate();
      /*
      ** Update MET at tone and local clock latched at tone...
      **
      ** This does not increase the accuracy of the local clock,
      **    but it does avoid some problems.  It is not uncommon
      **    for a local clock to roll over after only a few
      **    seconds, so we try and keep the elapsed time since
      **    the "tone" to a relatively small number of seconds.
      **    We can handle a simple roll-over but need to prevent
      **    the local clock from completely wrapping around the
      **    time latched at the tone.
      */
      NextState->AtToneMET = Reference.CurrentMET;
      NextState->AtToneLatch = Reference.CurrentLatch;
      /*
      ** Force anyone currently reading time to retry...
      */
      CFE_TIME_FinishReferenceUpdate(NextState);
    }
  }
  /* Exit performance monitoring */
  CFE_ES_PerfLogExit(CFE_MISSION_TIME_LOCAL1HZISR_PERF_ID);
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_Local1HzISR()
{
  CFE_TIME_Global.LocalIntCounter++;
  /*
  ** Enable 1Hz task (we can't send a SB message from here)...
  */
  OS_BinSemGive(CFE_TIME_Global.LocalSemaphore);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_Local1HzTask()
{
  I32 OsStatus;
  while (TRUE) {
    /* Increment the Main task Execution Counter */
    CFE_ES_IncrementTaskCounter();
    /*
    ** Pend on the 1HZ semaphore (given by local 1Hz ISR)...
    */
    OsStatus = OS_BinSemTake(CFE_TIME_Global.LocalSemaphore);
    if (OsStatus != OS_SUCCESS) {
      break;
    }
    /* Start Performance Monitoring */
    CFE_ES_PerfLogEntry(CFE_MISSION_TIME_LOCAL1HZTASK_PERF_ID);
    /*
    ** Send "info" event if we just started flywheel mode...
    */
    if (CFE_TIME_Global.AutoStartFly) {
      CFE_TIME_Global.AutoStartFly = FALSE;
      CFE_EVS_SendEvent(CFE_TIME_FLY_ON_EID, CFE_EVS_EventType_INFORMATION, "Start FLYWHEEL");
    }
    /*
    ** Send 1Hz timing packet...
    ** This used to be optional in previous CFE versions, but it is now required
    ** as TIME subscribes to this itself to do state machine tasks.
    */
    CFE_SB_TransmitMsg(&CFE_TIME_Global.LocalOneHzCmd.CommandHeader.Msg, TRUE);
    CFE_TIME_Global.LocalTaskCounter++;
    /* Exit performance monitoring */
    CFE_ES_PerfLogExit(CFE_MISSION_TIME_LOCAL1HZTASK_PERF_ID);
  }
  /*
  ** This should never happen - but during development we had an
  **    error in the creation of the semaphore.
  */
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_TIME_NotifyTimeSynchApps()
{
  U32 i;
  I32 (*Func)();
  /*
  ** Notify applications that have requested tone synchronization
  */
  if (CFE_TIME_Global.IsToneGood) {
    // NASA writes sizeof(..SynchCallback)/sizeof(..SynchCallback[0]); neither spelling parses in
    // HolyC (docs/HOLYC_STRUCT_LIMITS.md #9), and the quotient IS the array's bound -- which
    // check_padding.py verifies is CFE_PLATFORM_ES_MAX_APPLICATIONS. cfe_time_utils.HC's
    // CFE_TIME_CleanUpApp records the same deviation for the same array.
    for (i = 0; i < CFE_PLATFORM_ES_MAX_APPLICATIONS; ++i) {
      /* IMPORTANT:
       * Read the global pointer only once, since a thread could be unregistering
       * the same pointer in parallel with this action.
       */
      Func = CFE_TIME_Global.SynchCallback[i].Ptr;
      if (Func != NULL) {
        Func();
      }
    }
  }
}
// THE THREE FUNCTIONS THIS CONFIGURATION DOES NOT BUILD, and why they are absent rather than
// stubbed: CFE_TIME_ToneSendMET, CFE_TIME_ToneSendGPS and CFE_TIME_ToneSendTime are each wrapped
// in `#if (CFE_PLATFORM_TIME_CFG_SRC_MET/GPS/TIME == true)`, and all three switches are 0 here --
// this port's MET is the tone count, not an external source. NASA's own build does not compile
// them either, so a stub would be MORE code than NASA has, not less. check_coverage.py's
// CONFIG_EXCLUDED lists them and EVALUATES the guard with the host C preprocessor: if any of the
// three ever becomes true, the gate turns red rather than quietly accepting the absence.
#endif
