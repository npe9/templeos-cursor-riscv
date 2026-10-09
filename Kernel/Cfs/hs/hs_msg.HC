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
// HEALTH & SAFETY'S MESSAGES -- the 1:1 translation of NASA's config/default_hs_msgdefs.h,
// config/default_hs_msg.h, config/default_hs_msgstruct.h, config/default_hs_msgids.h and
// fsw/inc/hs_fcncodes.h, with the token-pasted ids resolved (read out of the preprocessor).
//
// ### HS SUBSCRIBES TO A **cFE** MESSAGE ID, WHICH NO OTHER APP IN THIS PORT DOES
//
// Its event monitor reads the event stream: HS subscribes to CFE_EVS_LONG_EVENT_MSG_MID (0x0808)
// on its own event pipe and inspects every event message the whole system emits, looking for an
// app name and event number listed in its Event Monitor Table. So HS is the only translated app
// whose INPUT is another cFE CORE SERVICE's telemetry rather than an app's.
//
// That is also why it has THREE pipes where every other app has one: commands (depth 12), wakeup
// (depth 1) and events (depth 32). The event pipe is the deepest because it carries everything.
//
// ### TWELVE COMMANDS, AND TEN OF THEM ARE A STATE TOGGLE
//
// NOOP, RESET, then five enable/disable pairs -- app monitor, event monitor, aliveness, CPU hog --
// plus RESET_RESETS_PERFORMED and SET_MAX_RESETS. **Only SET_MAX_RESETS has a payload.** So HS's
// command set is almost entirely "turn this monitor on or off", and the interesting state is in
// its four tables rather than in its commands.
//
// ### THE HK PACKET CARRIES THE APP-MONITOR ENABLES AS A **BITMAP**
//
// AppMonEnables is `((HS_MAX_MONITORED_APPS - 1) / HS_BITS_PER_APPMON_ENABLE) + 1` uint32s --
// with 32 apps and 32 bits per word that is exactly ONE word, so the arithmetic looks like
// over-engineering until you notice it is what keeps the packet layout stable if a mission raises
// HS_MAX_MONITORED_APPS to 33. The expression is kept rather than folded to 1 for that reason;
// docs/ records that a `/` in a configuration expression is where integer division bit a gate.
//
// AND THE PACKET ALSO CARRIES 32 EXECUTION COUNTERS -- ExeCounts[HS_MAX_EXEC_CNT_SLOTS], one per
// XCT entry, 128 bytes of the 164-byte payload. So most of HS's telemetry is other components'
// counters, which is the point: HS tells the ground whether everything else is still running.
#ifndef HS_MSG_HC
#define HS_MSG_HC

#include "hs_cfg.HC"

// --- hs_msg.h ---------------------------------------------------------------------------------
#define HS_BITS_PER_APPMON_ENABLE 32

// --- hs_msgids.h, resolved. Commands are 0x18xx, telemetry 0x08xx. ---------------------------
#define HS_CMD_MID     0x18AE
#define HS_SEND_HK_MID 0x18AF
#define HS_WAKEUP_MID  0x18B0
#define HS_HK_TLM_MID  0x08AD

// --- hs_fcncodes.h: twelve, and only SET_MAX_RESETS carries a payload ------------------------
#define HS_NOOP_CC                   0
#define HS_RESET_CC                  1
#define HS_ENABLE_APP_MON_CC         2
#define HS_DISABLE_APP_MON_CC        3
#define HS_ENABLE_EVENT_MON_CC       4
#define HS_DISABLE_EVENT_MON_CC      5
#define HS_ENABLE_ALIVENESS_CC       6
#define HS_DISABLE_ALIVENESS_CC      7
#define HS_RESET_RESETS_PERFORMED_CC 8
#define HS_SET_MAX_RESETS_CC         9
#define HS_ENABLE_CPU_HOG_CC         10
#define HS_DISABLE_CPU_HOG_CC        11

/*******************************************************************************/
// The eleven bare commands, 8 bytes each. NASA declares each as its own type rather than reusing
// one, so each is written out -- the names are what the dispatcher's `switch` and
// HS_VerifyMsgLength's sizeof refer to, and collapsing them would make the length checks
// indistinguishable from each other.
class HS_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HS_ResetCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HS_EnableAppMonCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HS_DisableAppMonCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HS_EnableEventMonCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HS_DisableEventMonCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HS_EnableAlivenessCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HS_DisableAlivenessCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HS_ResetResetsPerformedCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HS_EnableCpuHogCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HS_DisableCpuHogCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HS_SendHkCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

/*******************************************************************************/
// THE ONE COMMAND WITH A PAYLOAD. NASA declares its own `Padding` field, so the 4 bytes are
// upstream's rather than this translation's.
class HS_SetMaxResets_Payload_t
{
  U16 MaxResets; // the new maximum
  U16 Padding;   // NASA's own structure padding
};

class HS_SetMaxResetsCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  HS_SetMaxResets_Payload_t Payload;
};

/*******************************************************************************/
// HS's housekeeping payload. 164 bytes, and 128 of them are other components' execution counters.
//
// NASA DECLARES ITS OWN `SpareBytes` here, named "Alignment Spares" -- one byte, which is what
// takes the seven uint8s to eight and puts ResetsPerformed on a 2-byte boundary. Upstream's, not
// this translation's.
class HS_HkTlm_Payload_t
{
  U8 CmdCount;              // HS application command counter
  U8 CmdErrCount;           // HS application command error counter
  U8 CurrentAppMonState;    // status of the application monitor
  U8 CurrentEventMonState;  // status of the event monitor
  U8 CurrentAlivenessState; // status of the aliveness indicator
  U8 CurrentCPUHogState;    // status of the hogging indicator
  U8 StatusFlags;           // HS_StatusFlag_* -- which tables loaded, and whether the CDS is used
  U8 SpareBytes;            // NASA's own, named "Alignment Spares"
  U16 ResetsPerformed;      // processor resets HS has performed
  U16 MaxResets;            // the configured maximum
  U32 EventsMonitoredCount; // total event messages inspected
  U32 InvalidEventMonCount; // total invalid event monitors

  // ONE WORD with the shipped configuration, and the expression is kept -- see the header.
  U32 AppMonEnables[((HS_MAX_MONITORED_APPS - 1) / HS_BITS_PER_APPMON_ENABLE) + 1];

  U32 MsgActExec;  // software bus message actions executed
  U32 UtilCpuAvg;  // current CPU utilisation average
  U32 UtilCpuPeak; // current CPU utilisation peak

  U32 ExeCounts[HS_MAX_EXEC_CNT_SLOTS]; // the execution counters -- 128 of the payload's 164 bytes
};

/*******************************************************************************/
// HS's housekeeping packet. 180 bytes.
class HS_HkPacket_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  HS_HkTlm_Payload_t Payload;
};

#endif
