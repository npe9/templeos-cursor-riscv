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
// HOUSEKEEPING'S MESSAGES -- the 1:1 translation of NASA's config/default_hk_msgdefs.h,
// config/default_hk_msgstruct.h, config/default_hk_msgids.h and fsw/inc/hk_fcncodes.h.
//
// ### A COMMAND AND A TELEMETRY PACKET SHARE A TOPIC ID, TWICE
//
// NASA's fsw/inc/hk_topicids.h assigns
//
//     HK_SEND_HK_TOPICID           0x9B        HK_HK_TLM_TOPICID           0x9B
//     HK_SEND_COMBINED_PKT_TOPICID 0x9C        HK_COMBINED_PKT1_TLM_TOPICID 0x9C
//
// -- the same topic id for a command and for a telemetry message, deliberately, twice. It works
// because the resolved message id is the topic id OR'd with a direction base: commands land in
// 0x18xx and telemetry in 0x08xx, so HK_SEND_HK_MID is 0x189B and HK_HK_TLM_MID is 0x089B. Two
// different message ids from one topic id.
//
// IT IS WORTH WRITING DOWN BECAUSE THE RESOLVED VALUES LOOK LIKE A TYPO. 0x089B and 0x189B differ
// in one nibble, and HK subscribes to one while transmitting the other; a translation that mixed
// them would make HK subscribe to its own telemetry. The values below were read out of the
// PREPROCESSOR, not computed by hand -- HolyC has no `##` and the ids arrive through two levels
// of token pasting (`CFE_PLATFORM_HK_CMD_MIDVAL(CMD)`), so writing them out is forced and
// checking them against the C is the only way to be sure.
//
// ### HK HAS ONLY TWO COMMAND CODES, AND ONE OF THEM IS ZERO
//
// HK_NOOP_CC is **0** and HK_RESET_COUNTERS_CC is 1. A zero command code is unusual -- MD, MM, CS
// and LC all start at 0 too, but HK is the first app in this port where the dispatcher's
// `switch` has only two arms, so a zero-initialised buffer routes to NOOP rather than to the
// `default:` error arm. The dispatch exercise has to set the function code explicitly to reach
// the error arm at all, which is the opposite of the usual trap.
#ifndef HK_MSG_HC
#define HK_MSG_HC

// --- hk_msgids.h, resolved. Commands are 0x18xx, telemetry 0x08xx. ---------------------------
#define HK_CMD_MID               0x189A
#define HK_SEND_HK_MID           0x189B
#define HK_SEND_COMBINED_PKT_MID 0x189C
#define HK_HK_TLM_MID            0x089B
#define HK_COMBINED_PKT1_MID     0x089C
#define HK_COMBINED_PKT2_MID     0x089D
#define HK_COMBINED_PKT3_MID     0x089E
#define HK_COMBINED_PKT4_MID     0x089F

// --- hk_fcncodes.h ---------------------------------------------------------------------------
#define HK_NOOP_CC           0
#define HK_RESET_COUNTERS_CC 1

/*******************************************************************************/
// HK's own housekeeping payload. 12 bytes.
//
// NASA DECLARES ITS OWN PADDING MEMBER HERE and names the reason: "Padding to force 32 bit
// alignment". So `Padding` is upstream's, not this translation's, and it sits where C would have
// put a hole anyway -- between two uint8s and a uint16. The tail needs none: 1+1+2+2+2 is 8 and
// the 4-byte MemPoolHandle lands on 8 exactly.
class HK_HkTlm_Payload_t
{
  U8 CommandCounter;      // count of valid commands received
  U8 CommandErrorCounter; // count of invalid commands received
  U16 Padding;            // NASA's own, to force 32-bit alignment
  U16 CombinedPacketsSent; // count of combined telemetry packets sent
  U16 MissingDataCtr;     // times missing data was detected
  U32 MemPoolHandle;      // CFE_ES_MemHandle_t -- reported so the ground can read pool diags
};

/*******************************************************************************/
// HK's housekeeping packet. 28 bytes.
class HK_HkPacket_t
{
  CFE_MSG_TelemetryHeader TelemetryHeader;
  HK_HkTlm_Payload_t Payload;
};

/*******************************************************************************/
// THE ONLY COMMAND WITH A PAYLOAD: which combined packet to send. 12 bytes.
//
// And it is the one command whose argument is a MESSAGE ID rather than an index -- the ground
// names the output packet it wants by its MsgId, and HK_SendCombinedHkPacket walks the runtime
// table looking for a match. So an id nothing in the copy table produces is not an error, it is
// HK_UNKNOWN_COMBINED_PACKET_EID, an INFORMATION event.
class HK_SendCombinedPkt_Payload_t
{
  CFE_SB_MsgId OutMsgToSend; // MsgId of the combined telemetry packet to send
};

class HK_SendCombinedPktCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
  HK_SendCombinedPkt_Payload_t Payload;
};

// --- the three bare commands, 8 bytes each ---------------------------------------------------
class HK_SendHkCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HK_NoopCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

class HK_ResetCountersCmd_t
{
  CFE_MSG_CommandHeader CommandHeader;
};

#endif
