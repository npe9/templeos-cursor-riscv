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

// 1:1 HolyC translation of cFE modules/msg/fsw/src/cfe_msg_msgid_v1.c
//
// "v1" is the cFS message-id format where the id IS the 16-bit CCSDS stream id. The v2 variant in
// the same directory splits the id across the primary and extended headers; the build picks one.
// This is the v1 one, matching the primary-header-only message layout translated alongside it.
#ifndef CFE_MSG_MSGID_V1_HC
#define CFE_MSG_MSGID_V1_HC
#include "cfe_sb_msgid.HC"
#include "cfe_msg_ccsdspri.HC"

I32 CFE_MSG_GetMsgId(CFE_MSG_Message *MsgPtr, CFE_SB_MsgId *MsgId)
{
  U32 msgidval;
  if (MsgPtr == NULL || MsgId == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  msgidval = (MsgPtr->CCSDS.Pri.StreamId[0] << 8) + MsgPtr->CCSDS.Pri.StreamId[1];
  *MsgId = CFE_SB_ValueToMsgId(msgidval);
  return CFE_SUCCESS;
}

I32 CFE_MSG_SetMsgId(CFE_MSG_Message *MsgPtr, CFE_SB_MsgId MsgId)
{
  U32 msgidval = CFE_SB_MsgIdToValue(MsgId);
  if (MsgPtr == NULL || !CFE_SB_IsValidMsgId(MsgId))
    return CFE_MSG_BAD_ARGUMENT;
  // Shift and mask bytes to be endian agnostic
  MsgPtr->CCSDS.Pri.StreamId[0] = (msgidval >> 8) & 0xFF;
  MsgPtr->CCSDS.Pri.StreamId[1] = msgidval & 0xFF;
  return CFE_SUCCESS;
}
#endif
