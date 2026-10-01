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
// The TIME module's DECLARATIONS, gathered from four of NASA's headers:
//
//   modules/time/config/default_cfe_time_extern_typedefs.h   the seven enum typedefs
//   modules/time/config/default_cfe_time_msgdefs.h           the command and telemetry payloads
//   modules/time/config/default_cfe_time_msgstruct.h         the twenty-three messages
//   modules/time/fsw/src/cfe_time_utils.h                    Reference, ReferenceState, Global
//
// SPLIT OUT, for the reason cfe_evs_global.HC records: NASA defines CFE_TIME_Global in
// cfe_time_task.c -- the LAST source to be translated -- and the files above it reach it through
// an `extern` in cfe_time_utils.h. HolyC has no usable forward declaration for a variable, so the
// definition has to precede its first use, which means it lives here beside its type and
// cfe_time_task.HC will say so at the point NASA defines it. One definition either way;
// docs/HOLYC_STRUCT_LIMITS.md has the measurement that forced it.
//
// THE CONFIGURATION THIS IS. All seven of TIME's switches are resolved below from
// example_platform_cfg.h, because they change the SHAPE of the global: this port is a time
// SERVER with a VIRTUAL (software) MET, no external time source, and the FAKE TONE on -- which
// is what puts ToneSendCmd in the structure. check_padding.py measures the result against
// NASA's own compiler, so a wrong switch is a wrong byte offset and not an opinion.
#ifndef CFE_TIME_GLOBAL_HC
#define CFE_TIME_GLOBAL_HC
// Guarded, so including this first costs nothing where a driver has them already.
#include "../osal/osconfig.HC"
#include "cfe_msg_sechdr_time.HC" // class CFE_TIME_SysTime
#include "cfe_msg_sechdr_fc.HC"    // CFE_MSG_CommandHeader, CFE_MSG_TelemetryHeader
#include "cfe_resourceid.HC"
// From cfe_platform_cfg.h. It sizes the 1Hz callback registry below -- one slot per application,
// not per registered callback -- so it is part of the global's layout.
#ifndef CFE_PLATFORM_ES_MAX_APPLICATIONS
#define CFE_PLATFORM_ES_MAX_APPLICATIONS 32
#endif
// --- cfe_time_internal_cfg.h, through CFE_PLATFORM_TIME_CFGVAL -------------------------------
// The five that decide the module's shape and the branches it compiles.
#define CFE_PLATFORM_TIME_CFG_SERVER   1 // this port keeps the time, it does not read it
#define CFE_PLATFORM_TIME_CFG_CLIENT   0
#define CFE_PLATFORM_TIME_CFG_VIRTUAL  1 // a software MET, not a hardware register
#define CFE_PLATFORM_TIME_CFG_SIGNAL   0 // no tone-signal ISR
#define CFE_PLATFORM_TIME_CFG_SRC_MET  0 // and no external time source of any kind
#define CFE_PLATFORM_TIME_CFG_SRC_GPS  0
#define CFE_PLATFORM_TIME_CFG_SRC_TIME 0
// From cfe_mission_cfg.h. With the fake tone ON, TIME sends its own tone instead of waiting for
// a hardware one -- and ToneSendCmd below exists only because of it.
#define CFE_MISSION_TIME_CFG_FAKE_TONE 1
#define CFE_MISSION_TIME_AT_TONE_WAS   1
#define CFE_MISSION_TIME_EPOCH_YEAR    1980
// Which of the two the API's "GetTime" means. TAI here, so CFE_TIME_GetTime returns MET+STCF
// WITHOUT removing the leap seconds -- and CFE_TIME_SetTime does not add them back.
#define CFE_MISSION_TIME_CFG_DEFAULT_TAI 1
#define CFE_MISSION_TIME_CFG_DEFAULT_UTC 0
// --- cfe_time_internal_cfg.h / cfe_mission_cfg.h: the numbers the module computes with -------
// CFG_SOURCE is 0, the same answer as the three CFG_SRC_* above: this port has no external time
// source, so every range check against MaxDelta is compiled out.
#define CFE_PLATFORM_TIME_CFG_SOURCE       0
#define CFE_MISSION_TIME_MIN_ELAPSED       0
#define CFE_MISSION_TIME_MAX_ELAPSED       200000
#define CFE_MISSION_TIME_DEF_MET_SECS      1000
#define CFE_MISSION_TIME_DEF_MET_SUBS      0
#define CFE_MISSION_TIME_DEF_STCF_SECS     1000000
#define CFE_MISSION_TIME_DEF_STCF_SUBS     0
#define CFE_MISSION_TIME_DEF_LEAPS         37
#define CFE_PLATFORM_TIME_MAX_LOCAL_SECS   27
#define CFE_PLATFORM_TIME_MAX_LOCAL_SUBS   0
#define CFE_PLATFORM_TIME_MAX_DELTA_SECS   0
#define CFE_PLATFORM_TIME_MAX_DELTA_SUBS   500000
#define CFE_PLATFORM_TIME_CFG_TONE_LIMIT   20000
#define CFE_PLATFORM_TIME_START_TASK_PRIORITY   60
#define CFE_PLATFORM_TIME_START_TASK_STACK_SIZE 8192
// The reset-area validation word. It is what tells a processor reset's surviving clock data from
// a blank area, so it is the one value in this file that must not be approximated.
#define CFE_TIME_RESET_SIGNATURE 0xA5A55A5A
// --- cfe_time_msgids.h -----------------------------------------------------------------------
// Eight message ids. Four of them -- TONE, DATA, SEND and ONEHZ -- are messages TIME sends to
// ITSELF, which is why the global carries the command packets for them.
#define CFE_TIME_HK_TLM_MID   0x0805
#define CFE_TIME_DIAG_TLM_MID 0x0806
#define CFE_TIME_CMD_MID      0x1805
#define CFE_TIME_SEND_HK_MID  0x180D
#define CFE_TIME_TONE_CMD_MID 0x1810
#define CFE_TIME_ONEHZ_CMD_MID 0x1811
#define CFE_TIME_DATA_CMD_MID 0x1860
#define CFE_TIME_SEND_CMD_MID 0x1862
// --- cfe_error.h: TIME's status codes --------------------------------------------------------
// The (I32) is NASA's own cast; see the note in cfe_evs_global.HC for what dropping it did.
#define CFE_TIME_INTERNAL_ONLY            0xCE000001(I32)
#define CFE_TIME_TOO_MANY_SYNCH_CALLBACKS 0xCE000003(I32)
#define CFE_TIME_CALLBACK_NOT_REGISTERED  0xCE000004(I32)
#define CFE_TIME_BAD_ARGUMENT             0xCE000005(I32)
#define CFE_TIME_NOT_IMPLEMENTED          0xCE00FFFF(I32)
// --- cfe_time_api_typedefs.h: CFE_TIME_Compare_t ---------------------------------------------
// A three-valued comparison, and A_LT_B is NEGATIVE -- which is why CFE_TIME_Compare returns it
// as a signed value and not as a bare flag.
#define CFE_TIME_A_LT_B -1
#define CFE_TIME_EQUAL  0
#define CFE_TIME_A_GT_B 1
// --- cfe_time_utils.h: limits ---------------------------------------------------------------
// The reference buffer is a 4-deep ring that readers walk WITHOUT a lock: a writer fills the
// next slot and then publishes it by bumping LastVersionCounter, so a reader that is overtaken
// retries. The DEPTH is therefore part of the concurrency argument, not a convenience.
#define CFE_TIME_REFERENCE_BUF_DEPTH 4
#define CFE_TIME_REFERENCE_BUF_MASK  3
#define CFE_TIME_RESET_AREA_ERROR    1
#define CFE_TIME_RESET_AREA_BAD      2
#define CFE_TIME_RESET_AREA_NEW      3
#define CFE_TIME_RESET_AREA_EXISTING 4
// --- default_cfe_time_extern_typedefs.h -----------------------------------------------------
// Seven C enums, and their WIDTHS are not uniform -- three are uint8 and four are int16, which
// is exactly the kind of thing that silently shifts a struct. Each is spelled as the integer
// type NASA's typedef names, and the enumerators become #defines because HolyC has no enum.
// CFE_TIME_ClockState_INVALID is NEGATIVE, which is why its typedef is signed.
#define CFE_TIME_ClockState_INVALID        -1
#define CFE_TIME_ClockState_VALID          0
#define CFE_TIME_ClockState_FLYWHEEL       1
#define CFE_TIME_SourceSelect_INTERNAL     1
#define CFE_TIME_SourceSelect_EXTERNAL     2
#define CFE_TIME_ToneSignalSelect_PRIMARY  1
#define CFE_TIME_ToneSignalSelect_REDUNDANT 2
#define CFE_TIME_AdjustDirection_ADD       1
#define CFE_TIME_AdjustDirection_SUBTRACT  2
#define CFE_TIME_FlywheelState_NO_FLY      0
#define CFE_TIME_FlywheelState_IS_FLY      1
#define CFE_TIME_SetState_NOT_SET          0
#define CFE_TIME_SetState_WAS_SET          1
// --- default_cfe_time_msgdefs.h: the command payloads ----------------------------------------
class CFE_TIME_LeapsCmd_Payload_t
{
  I16 LeapSeconds;
};

class CFE_TIME_StateCmd_Payload_t
{
  I16 ClockState;
  // CFE_TIME_ClockState_Enum_t -- int16
};

class CFE_TIME_SourceCmd_Payload_t
{
  U8 TimeSource;
  // CFE_TIME_SourceSelect_Enum_t -- uint8
};

class CFE_TIME_SignalCmd_Payload_t
{
  I16 ToneSource;
  // CFE_TIME_ToneSignalSelect_Enum_t -- int16
};

class CFE_TIME_TimeCmd_Payload_t
{
  U32 Seconds;
  U32 MicroSeconds;
};

class CFE_TIME_OneHzAdjustmentCmd_Payload_t
{
  U32 Seconds;
  U32 Subseconds;
};

class CFE_TIME_ToneDataCmd_Payload_t
{
  CFE_TIME_SysTime AtToneMET;
  CFE_TIME_SysTime AtToneSTCF;
  I16 AtToneLeapSeconds;
  I16 AtToneState;
  // CFE_TIME_ClockState_Enum_t
};
// --- default_cfe_time_msgdefs.h: the telemetry payloads --------------------------------------
class CFE_TIME_HousekeepingTlm_Payload_t
{
  U8 CommandCounter;
  U8 CommandErrorCounter;
  U16 ClockStateFlags;
  I16 ClockStateAPI;
  // CFE_TIME_ClockState_Enum_t
  I16 LeapSeconds;
  CFE_TIME_SysTime MET;
  CFE_TIME_SysTime STCF;
  CFE_TIME_SysTime AdjustmentFactor;
};

class CFE_TIME_DiagnosticTlm_Payload_t
{
  CFE_TIME_SysTime AtToneMET;
  CFE_TIME_SysTime AtToneSTCF;
  CFE_TIME_SysTime AtToneDelay;
  CFE_TIME_SysTime AtToneLatch;
  I16 AtToneLeapSeconds;
  I16 ClockStateAPI;
  // CFE_TIME_ClockState_Enum_t
  CFE_TIME_SysTime TimeSinceTone;
  CFE_TIME_SysTime CurrentLatch;
  CFE_TIME_SysTime CurrentMET;
  CFE_TIME_SysTime CurrentTAI;
  CFE_TIME_SysTime CurrentUTC;
  I16 ClockSetState;
  // CFE_TIME_SetState_Enum_t -- int16
  I16 ClockFlyState;
  // CFE_TIME_FlywheelState_Enum_t -- int16
  U8 ClockSource;
  // CFE_TIME_SourceSelect_Enum_t -- uint8
  U8 _pad0;
  // C aligns the int16 that follows
  I16 ClockSignal;
  I16 ServerFlyState;
  // CFE_TIME_FlywheelState_Enum_t
  I16 Forced2Fly;
  U16 ClockStateFlags;
  I16 OneTimeDirection;
  I16 OneHzDirection;
  I16 DelayDirection;
  CFE_TIME_SysTime OneTimeAdjust;
  CFE_TIME_SysTime OneHzAdjust;
  CFE_TIME_SysTime ToneSignalLatch;
  CFE_TIME_SysTime ToneDataLatch;
  U32 ToneMatchCounter;
  U32 ToneMatchErrorCounter;
  U32 ToneSignalCounter;
  U32 ToneDataCounter;
  U32 ToneIntCounter;
  U32 ToneIntErrorCounter;
  U32 ToneTaskCounter;
  U32 VersionCounter;
  U32 LocalIntCounter;
  U32 LocalTaskCounter;
  U32 VirtualMET;
  U32 MinElapsed;
  U32 MaxElapsed;
  CFE_TIME_SysTime MaxLocalClock;
  U32 ToneOverLimit;
  U32 ToneUnderLimit;
  U32 DataStoreStatus;
};
// --- default_cfe_time_msgstruct.h: the twenty-three messages ---------------------------------
// Seven carry no payload and are a bare command header. CFE_TIME_ToneSignalCmd_t,
// CFE_TIME_FakeToneCmd_t and CFE_TIME_OneHzCmd_t are the three the module sends to ITSELF, and
// all three are members of the global below.
class CFE_TIME_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TIME_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TIME_SendDiagnosticCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TIME_OneHzCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TIME_ToneSignalCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TIME_FakeToneCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TIME_SendHkCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class CFE_TIME_SetLeapSecondsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_LeapsCmd_Payload_t Payload;
};

class CFE_TIME_SetStateCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_StateCmd_Payload_t Payload;
};

class CFE_TIME_SetSourceCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_SourceCmd_Payload_t Payload;
};

class CFE_TIME_SetSignalCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_SignalCmd_Payload_t Payload;
};

class CFE_TIME_AddDelayCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_TimeCmd_Payload_t Payload;
};

class CFE_TIME_SubDelayCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_TimeCmd_Payload_t Payload;
};

class CFE_TIME_SetMETCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_TimeCmd_Payload_t Payload;
};

class CFE_TIME_SetSTCFCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_TimeCmd_Payload_t Payload;
};

class CFE_TIME_AddAdjustCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_TimeCmd_Payload_t Payload;
};

class CFE_TIME_SubAdjustCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_TimeCmd_Payload_t Payload;
};

class CFE_TIME_SetTimeCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_TimeCmd_Payload_t Payload;
};

class CFE_TIME_AddOneHzAdjustmentCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_OneHzAdjustmentCmd_Payload_t Payload;
};

class CFE_TIME_SubOneHzAdjustmentCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_OneHzAdjustmentCmd_Payload_t Payload;
};

class CFE_TIME_ToneDataCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TIME_ToneDataCmd_Payload_t Payload;
};

class CFE_TIME_HousekeepingTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_TIME_HousekeepingTlm_Payload_t Payload;
};

class CFE_TIME_DiagnosticTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  CFE_TIME_DiagnosticTlm_Payload_t Payload;
};
// --- cfe_time_utils.h: the internal types ----------------------------------------------------
// A SNAPSHOT, assembled by CFE_TIME_GetReference from the published reference state plus a fresh
// read of the local clock. Every API call that returns a time builds one of these first, which
// is what makes the answers self-consistent: MET, STCF and the leap seconds all come from the
// same tone.
class CFE_TIME_Reference_t
{
  CFE_TIME_SysTime AtToneMET;
  // MET at time of tone
  CFE_TIME_SysTime AtToneSTCF;
  // STCF at time of tone
  I16 AtToneLeapSeconds;
  // Leap Seconds at time of tone
  I16 ClockSetState;
  // Time has been "set" -- CFE_TIME_SetState_Enum_t
  I16 ClockFlyState;
  // Current fly-wheel state -- CFE_TIME_FlywheelState_Enum_t
  I16 DelayDirection;
  // Whether "AtToneDelay" is add or subtract
  CFE_TIME_SysTime AtToneDelay;
  // Adjustment for slow tone detection
  CFE_TIME_SysTime AtToneLatch;
  // Local clock latched at time of tone
  CFE_TIME_SysTime CurrentLatch;
  // Local clock latched just "now"
  CFE_TIME_SysTime TimeSinceTone;
  // Time elapsed since the tone
  CFE_TIME_SysTime CurrentMET;
  // MET at this instant
};
// One entry of the 1Hz callback registry. NASA's member is
// `volatile CFE_TIME_SynchCallbackPtr_t Ptr` -- a function pointer, and HolyC has those.
//
// `I32 (*Ptr)()`, and this was `U0 (*Ptr)()` until the TIME driver tried to assign a real
// callback to it. NASA's typedef is `int32 (*)(void)` -- the callback RETURNS a status, which
// CFE_TIME_NotifyTimeSynchApps discards. Nothing in this port's nine gates could see the error:
// a function pointer is eight bytes either way, so check_padding and check_structs agree, and
// check_signatures looks at function PARAMETERS, not at the types of class members. What found
// it was the C compiler refusing the assignment on the oracle's side.
class CFE_TIME_SynchCallbackRegEntry_t
{
  I32 (*Ptr)();
};
// ONE SLOT OF THE LOCK-FREE RING. StateVersion is the sequence number a reader checks before and
// after copying, so a slot that was overwritten mid-read is detected and the read retried. That
// is why this is a separate type from CFE_TIME_Reference_t: this one is PUBLISHED, that one is
// derived.
class CFE_TIME_ReferenceState_t
{
  U32 StateVersion;
  I16 AtToneLeapSeconds;
  I16 ClockSetState;
  // CFE_TIME_SetState_Enum_t
  I16 ClockFlyState;
  // CFE_TIME_FlywheelState_Enum_t
  I16 DelayDirection;
  CFE_TIME_SysTime AtToneMET;
  CFE_TIME_SysTime AtToneSTCF;
  CFE_TIME_SysTime AtToneDelay;
  CFE_TIME_SysTime AtToneLatch;
};
// THE MODULE'S WHOLE STATE. NASA defines the object in cfe_time_task.c and declares it extern in
// cfe_time_utils.h; the translation defines it at the bottom of this file, for the reason at the
// top. ToneSendCmd is present because CFE_MISSION_TIME_CFG_FAKE_TONE is 1 -- with the real tone
// it is not a member at all, and check_padding would say so.
class CFE_TIME_Global_t
{
  U8 CommandCounter;
  U8 CommandErrorCounter;
  U8 _pad0[2];
  // C aligns HkPacket, whose first member is 4-aligned
  CFE_TIME_HousekeepingTlm_t HkPacket;
  CFE_TIME_DiagnosticTlm_t DiagPacket;
  U32 CmdPipe;
  // CFE_SB_PipeId_t
  I16 ClockSource;
  I16 ClockSignal;
  // CFE_TIME_ToneSignalSelect_Enum_t
  I16 ServerFlyState;
  // CFE_TIME_FlywheelState_Enum_t
  U8 _pad1[2];
  CFE_TIME_SysTime PendingMET;
  CFE_TIME_SysTime PendingSTCF;
  I16 PendingLeaps;
  I16 PendingState;
  // CFE_TIME_ClockState_Enum_t
  CFE_TIME_SysTime OneTimeAdjust;
  CFE_TIME_SysTime OneHzAdjust;
  I16 OneTimeDirection;
  // Add = true
  I16 OneHzDirection;
  CFE_TIME_SysTime ToneSignalLatch;
  // Latched at tone
  CFE_TIME_SysTime ToneDataLatch;
  // Latched at packet
  U32 ToneMatchCounter;
  // Tone and data match
  U32 ToneMatchErrorCounter;
  // Tone and data mismatch
  U32 ToneSignalCounter;
  // Tone signal commands
  U32 ToneDataCounter;
  // Tone data commands
  U32 ToneIntCounter;
  // Tone interrupts (valid)
  U32 ToneIntErrorCounter;
  // Tone interrupts (invalid)
  U32 ToneTaskCounter;
  // Tone task wake-ups
  U32 VirtualMET;
  // Software MET
  U32 LocalIntCounter;
  // Local 1Hz interrupts
  U32 LocalTaskCounter;
  // Local 1Hz task wake-ups
  U32 InternalCount;
  // Time from internal data
  U32 ExternalCount;
  // Time from external data
  CFE_TIME_ReferenceState_t ReferenceState[CFE_TIME_REFERENCE_BUF_DEPTH];
  U32 LastVersionCounter;
  // Completed Updates to "AtTone" values
  U32 ResetVersionCounter;
  // Version counter at last counter reset
  U32 MinElapsed;
  U32 MaxElapsed;
  CFE_TIME_SysTime MaxLocalClock;
  Bool Forced2Fly;
  Bool AutoStartFly;
  Bool IsToneGood;
  Bool GetReferenceFail;
  CFE_TIME_OneHzCmd_t LocalOneHzCmd;
  CFE_TIME_ToneDataCmd_t ToneDataCmd;
  CFE_TIME_ToneSignalCmd_t ToneSignalCmd;
  CFE_TIME_FakeToneCmd_t ToneSendCmd;
  // only with CFE_MISSION_TIME_CFG_FAKE_TONE
  U32 LocalSemaphore;
  // osal_id_t
  U32 ToneSemaphore;
  U32 LocalTaskID;
  // CFE_ES_TaskId_t
  U32 ToneTaskID;
  CFE_TIME_SysTime MaxDelta;
  U32 ToneOverLimit;
  U32 ToneUnderLimit;
  U32 DataStoreStatus;
  U8 _pad2[4];
  // C aligns the registry to 8: its entries hold a function pointer
  CFE_TIME_SynchCallbackRegEntry_t SynchCallback[CFE_PLATFORM_ES_MAX_APPLICATIONS];
};
// NASA's definition is in cfe_time_task.c; see the note at the top of this file for why the
// translation's has to come before its first use instead.
CFE_TIME_Global_t CFE_TIME_Global;
// --- cfe_time.h: CFE_TIME_Copy ---------------------------------------------------------------
// A MACRO upstream, and a function here -- the same move os_shared_task_affinity.HC records for
// OSAL's cpu-set macros. NASA's comment says the macro is preferred BECAUSE it does not require
// the two arguments to have the same type: it will take any two structures with Seconds and
// Subseconds members. Every call site in TIME passes CFE_TIME_SysTime on both sides, so a typed
// function is exact here; a future caller that wants the loose form has to say so.
U0 CFE_TIME_Copy(CFE_TIME_SysTime *m, CFE_TIME_SysTime *t)
{
  m->Seconds = t->Seconds;
  m->Subseconds = t->Subseconds;
}
#endif
