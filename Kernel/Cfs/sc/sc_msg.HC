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
// STORED COMMAND'S MESSAGES -- the 1:1 translation of NASA's config/default_sc_msgids.h,
// fsw/inc/sc_fcncodes.h, config/default_sc_msgdefs.h and config/default_sc_msgstruct.h, with the
// token-pasted ids resolved out of the preprocessor rather than guessed.
//
// ### SEVENTEEN COMMANDS, AND **SC IS THE FIRST APP HERE WHOSE COMMAND SET INCLUDES A cFE PAYLOAD**
//
// SC_ManageTableCmd_t carries `CFE_TBL_NotifyCmd_Payload_t` -- Table Services' own notification
// payload, not one of SC's. That is how cFE tells SC "one of your nine tables has a pending
// update": SC registers for notification and cFE sends SC a command built from cFE's structure.
// So the type is already translated (Kernel/Cfs/cfe/cfe_tbl_msg.HC) and SC's vocabulary must NOT
// redeclare it -- which is also why SC_ManageTableCmd_t is 4-byte aligned while fifteen of the
// other sixteen commands are 2-byte or 1-byte aligned.
//
// ### THE WAKEUP IS WHAT MAKES SC A SEQUENCER, AND IT HAS TWO NAMES FOR ONE ID
//
// SC does nothing on its own: SC_WAKEUP_MID arrives from a scheduler and SC advances every active
// sequence by one step. `SC_1HZ_WAKEUP_MID` is a **deprecated alias for the same id** (both
// 0x18AB, measured) left from when the rate was fixed at 1 Hz -- the name still says 1 Hz and the
// value no longer promises it, which is why RTS timing is counted in WAKEUPS rather than seconds.
// See SC_RtsEntryHeader_t in sc_tbl.HC.
//
// ### THE HOUSEKEEPING PAYLOAD IS 64 BYTES AND HAS **NO COMPILER PADDING AT ALL**
//
// Twenty-nine fields, every one naturally aligned, nothing inserted. That is not luck: NASA
// declares an explicit `Padding8` at offset 5, and without it five uint8s followed by a uint16
// would have left a hole exactly there. So the one byte that looks like slack is what makes the
// other twenty-eight fields pack -- and every offset below was read out of the C with offsetof,
// not derived, for the reason sc_tbl.HC's header gives.
//
// ### AND TWO MORE INTEGER DIVISIONS IN CONFIGURATION EXPRESSIONS
//
// `RtsExecutingStatus[(SC_NUMBER_OF_RTS + 15) / 16]` and its disabled twin: a BITMAP, one bit per
// RTS, sized in 16-bit words by a round-up. With SC_NUMBER_OF_RTS = 4 that is one word, so twelve
// of the sixteen bits are unused -- and the expression is kept unfolded because a mission with 17
// RTSs needs two words and nothing else in the packet layout would say so.
//
// **AND THE BITMAP IS 1-BASED AGAINST A 0-BASED WORD**, which NASA's own comment spells out: bit
// zero of word zero is RTS number ONE. So the bitmap is indexed by `RtsNum - 1` while the array is
// indexed from 0 -- the same number/index split sc_tbl.HC's header describes, here inside a single
// expression.
#ifndef SC_MSG_HC
#define SC_MSG_HC

#include "sc_cfg.HC"
#include "sc_tbl.HC"

// --- config/default_sc_msgids.h, resolved. Commands are 0x18xx, telemetry 0x08xx. ------------
//
// NASA writes these as `CFE_PLATFORM_SC_CMD_MIDVAL(CMD)`, a token paste onto the topic ids.
// HolyC has no `##`, so the values are the ones the preprocessor produces -- read out of a probe
// built on the real include path, not computed by hand.
#define SC_CMD_MID     0x18A9
#define SC_SEND_HK_MID 0x18AA
#define SC_WAKEUP_MID  0x18AB
#define SC_HK_TLM_MID  0x08AA
// DEPRECATED, AND EQUAL TO SC_WAKEUP_MID -- see the file header.
#define SC_1HZ_WAKEUP_MID SC_WAKEUP_MID

// --- config/default_sc_msg.h's own two constants ----------------------------------------------
//
// **BOTH ARE 0xFFFFFFFF, AND THEY ARE SATURATION VALUES RATHER THAN SENTINELS.** SC compares an
// ATS command's time tag against SC_MAX_TIME and an RTS command's target against
// SC_MAX_WAKEUP_CNT to decide "this will never arrive" -- so a sequence whose next command sits
// at the maximum is parked rather than rejected. The two names are the same number because an
// absolute time in seconds and a wakeup count are both uint32, which is the one place SC's two
// clocks share a representation.
//
// FOUND BY check_defines, NOT BY READING. default_sc_msg.h is a four-line header whose only job
// is to include the other four and add these two, so it was missed entirely -- and the gate paired
// it with this file by basename and named both constants. That gate exists because HS shipped
// eight event ids short.
#define SC_MAX_TIME       0xFFFFFFFF
#define SC_MAX_WAKEUP_CNT 0xFFFFFFFF

// --- fsw/inc/sc_fcncodes.h: seventeen codes, 0..16 -------------------------------------------
#define SC_NOOP_CC                    0
#define SC_RESET_COUNTERS_CC          1
#define SC_START_ATS_CC               2
#define SC_STOP_ATS_CC                3
#define SC_START_RTS_CC               4
#define SC_STOP_RTS_CC                5
#define SC_DISABLE_RTS_CC             6
#define SC_ENABLE_RTS_CC              7
#define SC_SWITCH_ATS_CC              8
#define SC_JUMP_ATS_CC                9
#define SC_CONTINUE_ATS_ON_FAILURE_CC 10
#define SC_APPEND_ATS_CC              11
#define SC_MANAGE_TABLE_CC            12
#define SC_START_RTS_GRP_CC           13
#define SC_STOP_RTS_GRP_CC            14
#define SC_DISABLE_RTS_GRP_CC         15
#define SC_ENABLE_RTS_GRP_CC          16

// THE FOUR DEPRECATED SPELLINGS, live in this configuration for the reason sc_tbl.HC's nine are:
// SC_OMIT_DEPRECATED is defined nowhere in SC's tree. These are the old no-underscore names for
// the four group commands.
#define SC_START_RTSGRP_CC   SC_START_RTS_GRP_CC
#define SC_STOP_RTSGRP_CC    SC_STOP_RTS_GRP_CC
#define SC_DISABLE_RTSGRP_CC SC_DISABLE_RTS_GRP_CC
#define SC_ENABLE_RTSGRP_CC  SC_ENABLE_RTS_GRP_CC

// --- config/default_sc_msgdefs.h's four enums ------------------------------------------------
//
// WHICH PROCESSOR RUNS NEXT. Note the values are NOT 0,1,2: NONE is **0xFF**, so "no pending
// process" is a sentinel at the top of the uint8 range rather than the next member. A loop that
// treated the enum as dense would run 254 phantom processes.
#define SC_Process_ATP  0
#define SC_Process_RTP  1
#define SC_Process_NONE 0xFF

#define SC_ATP  SC_Process_ATP
#define SC_RTP  SC_Process_RTP
#define SC_NONE SC_Process_NONE

// WHICH ATS, AS THE GROUND NAMES IT. 0 is "no ATS", so ATSA is 1 and ATSB is 2 -- the same
// 1-based numbering sc_tbl.HC's number/index split describes, and the reason SC_IDX_AS_CHAR adds
// its index to 'A' rather than to 'A'-1.
#define SC_AtsId_NO_ATS 0
#define SC_AtsId_ATSA   1
#define SC_AtsId_ATSB   2

#define SC_NO_ATS SC_AtsId_NO_ATS
#define SC_ATSA   SC_AtsId_ATSA
#define SC_ATSB   SC_AtsId_ATSB

// WHICH CLOCK AN ATS IS SCHEDULED AGAINST. SC_TIME_TO_USE selects one at build time (see
// sc_cfg.HC) and sc_utils.c switches on it. **SC_TimeRef_MAX IS A COUNT AND NOT A CHOICE** -- it
// is one past USE_UTC and exists so a range check can be written; selecting it would be a
// configuration error no code tests for.
#define SC_TimeRef_USE_CFE_TIME 0
#define SC_TimeRef_USE_TAI      1
#define SC_TimeRef_USE_UTC      2
#define SC_TimeRef_MAX          3

#define SC_USE_CFE_TIME SC_TimeRef_USE_CFE_TIME
#define SC_USE_TAI      SC_TimeRef_USE_TAI
#define SC_USE_UTC      SC_TimeRef_USE_UTC

// ZERO IS NOT A VALID RTS, which is what makes it usable as "none" -- the number/index rule again.
#define SC_INVALID_RTS_NUMBER 0

// WHETHER AN ATS KEEPS GOING AFTER A COMMAND FAILS. NASA writes these as `= false` and `= true`
// from stdbool, so they are 0 and 1; the translation writes the numbers because HolyC's FALSE and
// TRUE are the same values and check_constants compares against the resolved C.
#define SC_AtsCont_FALSE 0
#define SC_AtsCont_TRUE  1

#define SC_CONTINUE_TRUE  SC_AtsCont_TRUE
#define SC_CONTINUE_FALSE SC_AtsCont_FALSE

/*******************************************************************************/
// SC's housekeeping payload. 64 bytes, 29 fields, NO compiler padding -- see the file header.
class SC_HkTlm_Payload_t
{
  U8 CurrAtsId;                // SC_AtsId_Enum_t -- 1 = ATS A, 2 = ATS B         offset 0
  U8 AtpState;                 // SC_Status_Enum_t -- 2 = IDLE, 5 = EXECUTING     offset 1
  U8 ContinueAtsOnFailureFlag; // SC_AtsCont_Enum_t                               offset 2
  U8 CmdErrCtr;                // ground request errors                           offset 3
  U8 CmdCtr;                   // ground requests                                 offset 4
  // NASA'S OWN, "Structure padding" -- and it is what makes the other 28 fields pack. See the
  // file header; this is not slack.
  U8 Padding8;                 //                                                 offset 5
  U16 SwitchPendFlag;  // a buffer switch is pending: 0 = no, 1 = yes              offset 6
  U16 NumRtsActive;    // RTSs currently active                                    offset 8
  U16 RtsNum;          // SC_RtsNum_t -- the next RTS number                       offset 10
  U16 RtsActiveCtr;    // RTSs started without error                               offset 12
  U16 RtsActiveErrCtr; // failed attempts to start an RTS                           offset 14
  U16 AtsCmdCtr;       // TOTAL commands sent by the ATS                           offset 16
  U16 AtsCmdErrCtr;    // TOTAL command errors in the ATS                          offset 18
  U16 RtsCmdCtr;       // TOTAL commands sent from ALL active RTSs                 offset 20
  U16 RtsCmdErrCtr;    // TOTAL errors from ALL active RTSs                        offset 22
  U16 LastAtsErrSeq;   // SC_AtsNum_t -- last errant ATS, 1 or 2                   offset 24
  U16 LastAtsErrCmd;   // SC_CommandNum_t -- last errant ATS command number        offset 26
  U16 LastRtsErrSeq;   // SC_RtsNum_t -- last errant RTS                           offset 28
  // IN **WORDS**, not bytes -- an SC_EntryOffset_t. NASA's own comment says so, and it is the
  // only field in the packet whose unit is not obvious from its name.
  U16 LastRtsErrCmd;   // SC_EntryOffset_t -- offset of the last RTS command error  offset 30
  U16 AppendCmdArg;      // SC_AtsNum_t -- the ATS the last Append command named    offset 32
  U16 AppendEntryCount;  // command entries in the current Append table            offset 34
  U16 AppendByteCount;   // size of those entries, in bytes                        offset 36
  U16 AppendLoadCount;   // total Append table loads                               offset 38
  U32 AtpCmdNumber;      // the current command number                             offset 40
  U32 AtpFreeBytes[SC_NUMBER_OF_ATS]; // free BYTES in each ATS                    offset 44
  U32 NextRtsWakeupCnt;  // the next RTS command's absolute wakeup count            offset 52
  U32 NextAtsTime;       // the next ATS command's time, in seconds                 offset 56
  // ONE WORD with the shipped configuration, and the round-up is kept -- see the file header.
  // Bit zero of word zero is RTS number ONE: 1-based bits in a 0-based array.
  U16 RtsExecutingStatus[(SC_NUMBER_OF_RTS + 15) / 16]; //                         offset 60
  U16 RtsDisabledStatus[(SC_NUMBER_OF_RTS + 15) / 16];  //                         offset 62
};

/*******************************************************************************/
// --- the command payloads. Every one is 4 bytes, and five of the six are a number plus NASA's
// own explicit padding -- so SC's commands are uniformly sized whatever they carry.

class SC_StartAtsCmd_Payload_t
{
  U16 AtsNum;  // SC_AtsNum_t -- the ATS to start, 1 = ATS A, 2 = ATS B
  U16 Padding; // NASA's own structure padding
};

class SC_RtsCmd_Payload_t
{
  U16 RtsNum;  // SC_RtsNum_t -- the RTS to act on, 1 .. SC_NUMBER_OF_RTS
  U16 Padding; // NASA's own
};

// THE ONE PAYLOAD WITH NO PADDING, because its single field already fills the four bytes. An
// absolute time in seconds -- the only command that moves the ATS clock.
class SC_JumpAtsCmd_Payload_t
{
  U32 NewTime; // the time to jump to
};

// **THE ONLY PAYLOAD WITH THREE PADDING BYTES OF TWO DIFFERENT PARENTAGES**, and a first draft of
// this class got it wrong twice over: it declared `U16 ContinueState` with a comment rationalising
// the widening as "matching the measured layout". NASA declares `SC_AtsCont_Enum_t`, which is a
// **uint8**, and offsetof says ContinueState is one byte at 0 while Padding sits at **2**. So
// there is a compiler hole at offset 1 that NASA's explicit `Padding` does not cover -- it brings
// the structure to the four bytes every other SC payload has, and the hole is separate.
//
// A `U16` there would have failed check_structs on the field type and, worse, written TWO bytes
// where the ground writes one. The lesson is the one docs/ already records: measure the layout and
// keep NASA's field types; a comment explaining why a type was changed is a sign the measurement
// was skipped.
class SC_SetContinueAtsOnFailureCmd_Payload_t
{
  U8 ContinueState; // SC_AtsCont_Enum_t -- a uint8                              offset 0
  U8 _pad0[1];      // the COMPILER's hole: the uint16 below is 2-byte aligned
  U16 Padding;      // NASA's own, bringing the payload to four bytes            offset 2
};

class SC_AppendAtsCmd_Payload_t
{
  U16 AtsNum;  // SC_AtsNum_t -- the ATS to append to
  U16 Padding; // NASA's own
};

// A RANGE OF RTSs, INCLUSIVE AT BOTH ENDS -- see SC_RtsNumWithinRange in sc_tbl.HC.
class SC_RtsGrpCmd_Payload_t
{
  U16 FirstRtsNum; // SC_RtsNum_t
  U16 LastRtsNum;  // SC_RtsNum_t
};

/*******************************************************************************/
// --- the twenty-one messages. SIX ARE BARE 8-byte command headers and fifteen carry a payload.

class SC_HkTlm_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  SC_HkTlm_Payload_t Payload;
};

class SC_SendHkCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class SC_WakeupCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class SC_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class SC_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class SC_StopAtsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class SC_SwitchAtsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class SC_StartAtsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_StartAtsCmd_Payload_t Payload;
};

class SC_JumpAtsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_JumpAtsCmd_Payload_t Payload;
};

class SC_SetContinueAtsOnFailureCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_SetContinueAtsOnFailureCmd_Payload_t Payload;
};

// AND ITS TWIN WITH A DIFFERENT NAME AND THE SAME PAYLOAD. NASA declares both
// SC_SetContinueAtsOnFailureCmd_t and SC_ContinueAtsOnFailureCmd_t over
// SC_SetContinueAtsOnFailureCmd_Payload_t -- two message types, one payload, one command code.
class SC_ContinueAtsOnFailureCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_SetContinueAtsOnFailureCmd_Payload_t Payload;
};

class SC_AppendAtsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_AppendAtsCmd_Payload_t Payload;
};

class SC_StartRtsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_RtsCmd_Payload_t Payload;
};

class SC_StopRtsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_RtsCmd_Payload_t Payload;
};

class SC_DisableRtsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_RtsCmd_Payload_t Payload;
};

class SC_EnableRtsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_RtsCmd_Payload_t Payload;
};

// **cFE'S PAYLOAD, NOT SC'S** -- see the file header. CFE_TBL_NotifyCmd_Payload_t is declared in
// Kernel/Cfs/cfe/cfe_tbl_msg.HC and is NOT redeclared here.
class SC_ManageTableCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  CFE_TBL_NotifyCmd_Payload_t Payload;
};

class SC_StartRtsGrpCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_RtsGrpCmd_Payload_t Payload;
};

class SC_StopRtsGrpCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_RtsGrpCmd_Payload_t Payload;
};

class SC_DisableRtsGrpCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_RtsGrpCmd_Payload_t Payload;
};

class SC_EnableRtsGrpCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  SC_RtsGrpCmd_Payload_t Payload;
};

#endif
