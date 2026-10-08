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
// LIMIT CHECKER'S WIRE MESSAGES -- NASA's config/default_lc_msgdefs.h, default_lc_msgstruct.h,
// fsw/inc/lc_fcncodes.h and config/default_lc_msgids.h, in that order.
//
// SEVEN COMMAND CODES, against CS's forty. LC is a small interface onto a large mechanism: the
// ground tells it to go active, passive or disabled, sets or permanently disables an actionpoint,
// and resets statistics. Everything else LC does is driven by PACKETS ARRIVING, not by commands --
// which is what makes it the first app in this port whose input is other apps' telemetry.
//
// AND IT **SENDS** A COMMAND, which no app before it has done. LC_RTSRequestCmd_t is built by LC
// and transmitted to Stored Command's MsgId when an actionpoint fails. That is why LC_RTS_REQ_MID
// and LC_RTS_REQ_CC are in lc_cfg.HC as INTERFACE configuration rather than internal: they name
// another application's command, and a mission that renumbers SC's pipe has to retarget LC.
//
// ### THE HOUSEKEEPING PACKET IS BIT-PACKED, AND THAT IS THE WHOLE REASON THE HK CONSTANTS EXIST
//
// LC_HkTlm_Payload_t carries every watchpoint's result at TWO BITS each and every actionpoint's
// result and state at FOUR BITS each:
//
//     LC_HKWR_NUM_BYTES = ((LC_MAX_WATCHPOINTS  + 15) / 16) * 4   = ((176+15)/16)*4 = 44
//     LC_HKAR_NUM_BYTES = ((LC_MAX_ACTIONPOINTS +  7) /  8) * 4   = ((176+7)/8)*4   = 88
//
// Both round UP to a whole number of 4-byte words, which is what the `* 4` is for -- 176
// watchpoints need 44 bytes exactly, but 177 would need 48 and not 45. So 176 of each fit in 132
// bytes of a 156-byte payload, and the eight LC_HKWR_*/LC_HKAR_* two-bit codes below are the
// alphabet. They are NOT the same values as the table results they encode: LC_WATCH_STALE is 0xFF
// in a WRT entry and 0x03 in the packet, so the packing is a translation and not a copy.
#ifndef LC_MSG_HC
#define LC_MSG_HC

#include "lc_cfg.HC"

// --- default_lc_msgdefs.h: the states, the wildcards and the packed-result alphabet ------------

// The LC application's own state. LC_STATE_FROM_CDS is NASA's comment "Used for reset processing,
// not valid state" -- it is what LC_STATE_WHEN_CDS_RESTORED is set to, meaning "whatever the CDS
// said", so it can never appear in CurrentLCState.
#define LC_STATE_ACTIVE   1
#define LC_STATE_PASSIVE  2
#define LC_STATE_DISABLED 3
#define LC_STATE_FROM_CDS 4

// One actionpoint's state. LC_APSTATE_PERMOFF is the one a command cannot undo -- see
// LC_SET_AP_PERM_OFF_CC -- and LC_APSTATE_NOT_USED is "no actionpoint here", which NASA notes is
// "not valid command argument".
#define LC_APSTATE_NOT_USED 0xFF
#define LC_APSTATE_ACTIVE   1
#define LC_APSTATE_PASSIVE  2
#define LC_APSTATE_DISABLED 3
#define LC_APSTATE_PERMOFF  4

// The "all of them" wildcards a command may carry in place of an index.
#define LC_ALL_ACTIONPOINTS 0xFFFF
#define LC_ALL_WATCHPOINTS  0xFFFF

// The two-bit watch-result codes in the housekeeping packet. NOT the WRT values.
#define LC_HKWR_FALSE 0x00
#define LC_HKWR_TRUE  0x01
#define LC_HKWR_ERROR 0x02
#define LC_HKWR_STALE 0x03

// The two-bit action-result codes. Again NOT the ART values.
#define LC_HKAR_PASS  0x00
#define LC_HKAR_FAIL  0x01
#define LC_HKAR_ERROR 0x02
#define LC_HKAR_STALE 0x03

// The two-bit action-STATE codes, which share each actionpoint's nibble with the result above.
// NOT_USED and PERMOFF collapse to the same code, which is NASA's: a ground display cannot tell
// an unused actionpoint from a permanently disabled one out of this packet alone.
#define LC_HKAR_STATE_NOT_USED 0x00
#define LC_HKAR_STATE_ACTIVE   0x01
#define LC_HKAR_STATE_PASSIVE  0x02
#define LC_HKAR_STATE_DISABLED 0x03

// The two packed-array sizes. Written as NASA's expressions rather than as 44 and 88, because the
// rounding is the point and a mission that changes LC_MAX_WATCHPOINTS has to get the new size.
#define LC_HKWR_NUM_BYTES (((LC_MAX_WATCHPOINTS + 15) / 16) * 4)
#define LC_HKAR_NUM_BYTES (((LC_MAX_ACTIONPOINTS + 7) / 8) * 4)

// NASA's deprecated alias, under `#ifndef LC_OMIT_DEPRECATED`, which this configuration does not
// define. Same reasoning as lc_tbldefs.HC's seventeen.
#define LC_ACTION_NOT_USED LC_APSTATE_NOT_USED

// --- lc_fcncodes.h: the seven command codes ---------------------------------------------------
//
// NASA'S ARE AN `enum LC_FunctionCode` REACHED THROUGH TOKEN PASTING -- `LC_NOOP_CC` is
// `LC_CCVAL(NOOP)` is `LC_FunctionCode_NOOP`. HolyC has neither enums nor `##`, so both levels are
// written out as #defines: the LC_FunctionCode_* names so a reader of NASA's enum finds them, and
// the LC_*_CC names the dispatcher switches on.
#define LC_FunctionCode_NOOP            0
#define LC_FunctionCode_RESET_COUNTERS  1
#define LC_FunctionCode_SET_LC_STATE    2
#define LC_FunctionCode_SET_AP_STATE    3
#define LC_FunctionCode_SET_AP_PERM_OFF 4
#define LC_FunctionCode_RESET_AP_STATS  5
#define LC_FunctionCode_RESET_WP_STATS  6

#define LC_NOOP_CC            LC_FunctionCode_NOOP
#define LC_RESET_CC           LC_FunctionCode_RESET_COUNTERS
#define LC_SET_LC_STATE_CC    LC_FunctionCode_SET_LC_STATE
#define LC_SET_AP_STATE_CC    LC_FunctionCode_SET_AP_STATE
#define LC_SET_AP_PERM_OFF_CC LC_FunctionCode_SET_AP_PERM_OFF
#define LC_RESET_AP_STATS_CC  LC_FunctionCode_RESET_AP_STATS
#define LC_RESET_WP_STATS_CC  LC_FunctionCode_RESET_WP_STATS
// NASA's deprecated spelling of the fifth.
#define LC_SET_AP_PERMOFF_CC  LC_SET_AP_PERM_OFF_CC

// --- default_lc_msgstruct.h: the messages --------------------------------------------------------
//
// EVERY PAYLOAD IS A WHOLE NUMBER OF 4-BYTE WORDS AND NASA NAMES ITS OWN PADDING to get there --
// `uint16 Padding` beside a single U16 field, five times. These go on the wire, so the holes are
// interface and NASA declares them; translated as themselves, not as invented _pad members.

class LC_SendHkCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class LC_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class LC_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class LC_SetLCState_Payload_t
{
  U16 NewLCState; // new LC application state
  U16 Padding;    // NASA's own structure padding
};

class LC_SetLCStateCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  LC_SetLCState_Payload_t Payload;
};

// THE ONLY TWO-FIELD PAYLOAD WITH NO PADDING, because both fields are real.
class LC_SetAPState_Payload_t
{
  U16 APNumber;   // which actionpoint(s) to change -- may be LC_ALL_ACTIONPOINTS
  U16 NewAPState; // new actionpoint state
};

class LC_SetAPStateCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  LC_SetAPState_Payload_t Payload;
};

class LC_SetAPPermOff_Payload_t
{
  U16 APNumber; // which actionpoint to change -- NOT a wildcard, this one is irreversible
  U16 Padding;  // NASA's own structure padding
};

class LC_SetAPPermOffCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  LC_SetAPPermOff_Payload_t Payload;
};

class LC_ResetAPStats_Payload_t
{
  U16 APNumber; // which actionpoint(s) to change
  U16 Padding;  // NASA's own structure padding
};

class LC_ResetAPStatsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  LC_ResetAPStats_Payload_t Payload;
};

class LC_ResetWPStats_Payload_t
{
  U16 WPNumber; // which watchpoint(s) to change
  U16 Padding;  // NASA's own structure padding
};

class LC_ResetWPStatsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  LC_ResetWPStats_Payload_t Payload;
};

// THE SAMPLE COMMAND IS LC'S CLOCK. Nothing in LC evaluates an actionpoint on its own; a scheduler
// sends this, and UpdateAge is what ages watchpoint results toward stale. A range rather than a
// wildcard, so a mission can sample different actionpoints at different rates.
class LC_SampleAP_Payload_t
{
  U16 StartIndex; // first actionpoint to sample
  U16 EndIndex;   // last actionpoint to sample
  U16 UpdateAge;  // update the watchpoint results' age (true or false)
  U16 Padding;    // NASA's own structure padding
};

class LC_SampleAPCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  LC_SampleAP_Payload_t Payload;
};

// THE COMMAND LC SENDS rather than receives: a request to Stored Command to start an RTS.
class LC_RTSRequest_Payload_t
{
  U16 RTSId;   // RTS id to start
  U16 Padding; // NASA's own structure padding
};

class LC_RTSRequestCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  LC_RTSRequest_Payload_t Payload;
};

// The housekeeping packet. 156 bytes of payload, 132 of which are the two bit-packed arrays -- see
// the note at the top of this file. `Pad8` and `Pad16` are NASA's own members.
class LC_HkTlm_Payload_t
{
  U8 CmdCount;       // command counter
  U8 CmdErrCount;    // command error counter
  U8 CurrentLCState; // current LC application operating state
  U8 Pad8;           // NASA's own structure padding
  U8 WPResults[LC_HKWR_NUM_BYTES]; // packed watchpoint results, 2 bits each
  U8 APResults[LC_HKAR_NUM_BYTES]; // packed actionpoint results and states, 4 bits each
  U16 PassiveRTSExecCount; // RTS sequences NOT started because LC or the AP was passive
  U16 WPsInUse;            // how many watchpoints are currently in effect
  U16 ActiveAPs;           // how many actionpoints are currently active
  U16 Pad16;               // NASA's own structure padding
  U32 APSampleCount;     // total actionpoints sampled
  U32 MonitoredMsgCount; // total messages monitored for watchpoints
  U32 RTSExecCount;      // total RTS sequences initiated
};

class LC_HkPacket_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  LC_HkTlm_Payload_t Payload;
};

// --- default_lc_msgids.h: FOUR message ids ----------------------------------------------------
//
// NASA reaches each through two levels of token pasting -- LC_CMD_MID is
// `LC_CMD_PLATFORM_MIDVAL(CMD)`, which composes a topic id with the command/telemetry base. HolyC
// has no `##`, so the resolved values are written out; they were READ OUT OF THE C rather than
// counted by hand, which matters because the topic-id arithmetic is not obvious from the headers.
//
// THREE IN AND ONE OUT, and the third inbound one is the interesting one: LC subscribes to
// LC_CMD_MID for ground commands, LC_SEND_HK_MID for the housekeeping request, and
// LC_SAMPLE_AP_MID -- which is a SCHEDULER's wakeup, and is what makes an actionpoint ever get
// evaluated. LC also subscribes to every MsgId named by its watchpoint table, which is not here
// because it is not known until the WDT is loaded.
//
// NOTE LC_HK_TLM_MID IS 0x08A7 AND THE OTHER THREE ARE 0x18Ax. The 0x1000 bit is the
// command/telemetry split cfe_sb_msgid.HC's CFE_SB_IsValidMsgId enforces, so the HK packet's id
// being numerically adjacent to the commands' is a coincidence of the topic ids, not a pattern.
#define LC_CMD_MID       0x18A4
#define LC_SEND_HK_MID   0x18A5
#define LC_SAMPLE_AP_MID 0x18A6
#define LC_HK_TLM_MID    0x08A7

#endif
