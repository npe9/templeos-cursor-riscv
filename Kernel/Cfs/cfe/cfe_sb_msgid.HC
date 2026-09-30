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

// 1:1 HolyC translation of cFE's software-bus message-id type and its helpers, gathered from:
//   modules/sb/config/default_cfe_sb_extern_typedefs.h   CFE_SB_MsgId_Atom_t, CFE_SB_MsgId_t
//   modules/core_api/fsw/inc/cfe_sb_api_typedefs.h       the WRAP/UNWRAP macros, INVALID_MSG_ID
//   modules/core_api/fsw/inc/cfe_sb.h                    MsgIdToValue, ValueToMsgId, MsgId_Equal
//   modules/sb/fsw/src/cfe_sb_msg_id_util.c              CFE_SB_IsValidMsgId
//
// THE OPAQUE-TYPE IDIOM. CFE_SB_MsgId_t is a struct wrapping one uint32, deliberately, so a raw
// integer cannot be passed where a message id is wanted. Every resource id in cFE is built the
// same way, so this one translation sets the pattern for a large part of the codebase. It works
// directly: HolyC passes and returns a class by value, verified before relying on it.
//
// Note this file crosses a module boundary that the C does too: cfe_msg_msgid_v1.c calls
// CFE_SB_IsValidMsgId, which lives in the SB module, not the MSG one. A translation cannot be more
// modular than its original.
#ifndef CFE_SB_MSGID_HC
#define CFE_SB_MSGID_HC
// For the three header sizes CFE_SB_MsgHdrSize reports.
#include "cfe_msg_sechdr_fc.HC"
// From the sample platform configuration. In a real build this is mission-defined; it is the
// bound that makes an id "valid", so it is part of the behaviour, not a detail.
#define CFE_PLATFORM_SB_HIGHEST_VALID_MSGID 0x1FFF

class CFE_SB_MsgId
{
  U32 Value;
};

U32 CFE_SB_MsgIdToValue(CFE_SB_MsgId MsgId)
{
  return MsgId.Value;
}

CFE_SB_MsgId CFE_SB_ValueToMsgId(U32 MsgIdValue)
{
  CFE_SB_MsgId Result;
  Result.Value = MsgIdValue;
  return Result;
}

Bool CFE_SB_MsgId_Equal(CFE_SB_MsgId MsgId1, CFE_SB_MsgId MsgId2)
{
  return CFE_SB_MsgIdToValue(MsgId1) == CFE_SB_MsgIdToValue(MsgId2);
}
// CFE_SB_INVALID_MSG_ID is CFE_SB_MSGID_C(0) -- a compile-time literal in the C. HolyC has no
// compound-literal syntax for a class, so it becomes a function. Same value, same meaning.
CFE_SB_MsgId CFE_SB_InvalidMsgId()
{
  return CFE_SB_ValueToMsgId(0);
}

Bool CFE_SB_IsValidMsgId(CFE_SB_MsgId MsgId)
{
  return !CFE_SB_MsgId_Equal(MsgId, CFE_SB_InvalidMsgId) &&
         CFE_SB_MsgIdToValue(MsgId) <= CFE_PLATFORM_SB_HIGHEST_VALID_MSGID;
}
// --- the rest of cfe_sb_msg_id_util.c --------------------------------------------------------
// Which header a message has is decided by two bits of its own primary header, so this is the
// one place that knows a command header is 8 bytes and a telemetry header 16. The bus's payload
// offset comes from here. Note the C's own comment on the first branch -- "Since all cFE
// messages must have a secondary hdr this check is not needed" -- kept, because it explains why
// a branch that looks dead is there.
I64 CFE_SB_MsgHdrSize(CFE_MSG_Message *MsgPtr)
{
  I64 size = 0;
  Bool hassechdr = FALSE;
  I64 type = CFE_MSG_Type_Invalid;
  if (MsgPtr == NULL)
    return size;
  CFE_MSG_GetHasSecondaryHeader(MsgPtr, &hassechdr);
  CFE_MSG_GetType(MsgPtr, &type);
  // if secondary hdr is not present...
  // Since all cFE messages must have a secondary hdr this check is not needed
  if (!hassechdr)
    size = sizeof(CFE_MSG_Message);
  else if (type == CFE_MSG_Type_Cmd)
    size = sizeof(CFE_MSG_CommandHeader);
  else if (type == CFE_MSG_Type_Tlm)
    size = sizeof(CFE_MSG_TelemetryHeader);
  return size;
}
// --- the topic-id mapping ---------------------------------------------------------------------
// From modules/core_api/config/default_cfe_core_api_msgid_mapping.h and
// default_cfe_core_api_base_msgid_values.h. The C file under translation also carries
// "ifndef CFE_PLATFORM_CMD_TOPICID_TO_MIDV, define it to 0" fallbacks; those are DEAD in a
// stock build, because the mapping header above defines all four. Verified rather than assumed,
// by compiling a probe with this port's exact include set: CMD(5)=0x1805, TLM(5)=0x0805,
// GCMD(5)=0x1865, GTLM(5)=0x0865. The fallbacks are not translated, because translating a
// branch the build never takes would misrepresent what this code does.
#define CFE_PLATFORM_CMD_MID_BASE 0x1800
#define CFE_PLATFORM_TLM_MID_BASE 0x0800
#define CFE_GLOBAL_CMD_MID_BASE   0x1860
#define CFE_GLOBAL_TLM_MID_BASE   0x0860
#define CFE_PLATFORM_CMD_TOPICID_TO_MIDV(topic) (CFE_PLATFORM_CMD_MID_BASE | (topic))
#define CFE_PLATFORM_TLM_TOPICID_TO_MIDV(topic) (CFE_PLATFORM_TLM_MID_BASE | (topic))
#define CFE_GLOBAL_CMD_TOPICID_TO_MIDV(topic)   (CFE_GLOBAL_CMD_MID_BASE | (topic))
#define CFE_GLOBAL_TLM_TOPICID_TO_MIDV(topic)   (CFE_GLOBAL_TLM_MID_BASE | (topic))
// From cfe_psp_api.h, supplied by the platform layer; the harness stubs it, as it does for the C.
U32 CFE_PSP_GetProcessorId();
U32 CFE_SB_GlobalTlmTopicIdToMsgId(U16 TopicId);

// TRANSLATED AS WRITTEN, INCLUDING WHAT LOOKS LIKE AN UPSTREAM DEFECT. On the instance-0 branch
// this COMMAND function calls the GLOBAL TELEMETRY mapping, so it returns 0x0860|topic where
// 0x1860|topic was surely meant. In the v1 format the message id IS the CCSDS stream id, so bit
// 0x1000 is the packet TYPE -- the value handed back is a telemetry id in answer to a request
// for a command id. The evidence that it is a slip and not intent:
//   - CFE_SB_GlobalCmdTopicIdToMsgId exists right below, is public in cfe_sb.h:1008, and in the
//     non-EDS build NOTHING calls it; its only reference anywhere is the EDS mapping header.
//   - the sibling below has the identical instance-0 branch, so command and telemetry both land
//     on the global TELEMETRY base.
//   - the EDS implementation of this same pair keeps the two strictly apart, mapping through
//     Listener and Publisher components respectively.
// It is LATENT rather than live in a stock build: instance 0 is reached only via
// CFE_PSP_GetProcessorId, and cmake/sample_defs/targets.cmake sets PROCESSORID 1 and 2 with an
// unset one defaulting to the target id from 1. An application can still reach it directly --
// CFE_SB_CmdTopicIdToMsgId is public API and instance 0 is the documented "global" value.
//
// A 1:1 translation reproduces it, and the differential oracle then holds both languages to the
// same answer, so if upstream fixes this the gate fails and says so. See
// docs/CFS_UPSTREAM_NOTES.md.
U32 CFE_SB_CmdTopicIdToMsgId(U16 TopicId, U16 InstanceNum)
{
  U32 MsgIdValue;
  // Instance Number 0 is reserved for globals
  if (InstanceNum == 0)
    MsgIdValue = CFE_SB_GlobalTlmTopicIdToMsgId(TopicId);
  else
    MsgIdValue = CFE_PLATFORM_CMD_TOPICID_TO_MIDV(TopicId);
  return MsgIdValue;
}

U32 CFE_SB_TlmTopicIdToMsgId(U16 TopicId, U16 InstanceNum)
{
  U32 MsgIdValue;
  // Instance Number 0 is reserved for globals
  if (InstanceNum == 0)
    MsgIdValue = CFE_SB_GlobalTlmTopicIdToMsgId(TopicId);
  else
    MsgIdValue = CFE_PLATFORM_TLM_TOPICID_TO_MIDV(TopicId);
  return MsgIdValue;
}

U32 CFE_SB_GlobalCmdTopicIdToMsgId(U16 TopicId)
{
  return CFE_GLOBAL_CMD_TOPICID_TO_MIDV(TopicId);
}

U32 CFE_SB_GlobalTlmTopicIdToMsgId(U16 TopicId)
{
  return CFE_GLOBAL_TLM_TOPICID_TO_MIDV(TopicId);
}

U32 CFE_SB_LocalCmdTopicIdToMsgId(U16 TopicId)
{
  // PSP-reported Instance number is used for locals
  return CFE_SB_CmdTopicIdToMsgId(TopicId, CFE_PSP_GetProcessorId);
}

U32 CFE_SB_LocalTlmTopicIdToMsgId(U16 TopicId)
{
  // PSP-reported Instance number is used for locals
  return CFE_SB_TlmTopicIdToMsgId(TopicId, CFE_PSP_GetProcessorId);
}
#endif
