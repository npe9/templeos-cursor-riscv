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
#endif
