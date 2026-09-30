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

// 1:1 HolyC translation of cFE modules/msg/fsw/src/cfe_msg_msgid_shared.c and
// modules/msg/fsw/src/cfe_msg_initdefaulthdr_pri.c and modules/msg/fsw/src/cfe_msg_init.c.
//
// Three small files that finish the message module's v1 / primary-header-only configuration.
// They are grouped because each is a handful of lines and they only make sense together: Init
// clears the buffer, calls InitDefaultHdr (which the _pri variant points at SetDefaultCCSDSPri),
// then sets the id and the size. GetTypeFromMsgId is the odd one -- it builds a THROWAWAY message
// on the stack, writes the id into it and reads the type back out, rather than decoding the bit
// directly. That is a real design choice, not an accident, and it is translated as written: the
// type bit's position is knowledge that belongs to one place.
#ifndef CFE_MSG_INIT_HC
#define CFE_MSG_INIT_HC
#include "cfe_msg_msgid_v1.HC"
#include "../CfsStr.HC"
// --- cfe_msg_msgid_shared.c -----------------------------------------------------------------
I32 CFE_MSG_GetTypeFromMsgId(CFE_SB_MsgId MsgId, I64 *Type)
{
  CFE_MSG_Message msg;
  I32 Status;
  // Memset to initialize avoids possible GCC bug 53119
  MemSet(&msg, 0, sizeof(CFE_MSG_Message));
  if (Type == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  Status = CFE_MSG_SetMsgId(&msg, MsgId);
  if (Status == CFE_SUCCESS)
    Status = CFE_MSG_GetType(&msg, Type);
  return Status;
}
// --- cfe_msg_initdefaulthdr_pri.c -----------------------------------------------------------
// The build picks between this and the _priext variant. This is the one that matches the
// primary-header-only message layout translated in cfe_msg_sechdr_fc.HC.
U0 CFE_MSG_InitDefaultHdr(CFE_MSG_Message *MsgPtr)
{
  CFE_MSG_SetDefaultCCSDSPri(MsgPtr);
}
// --- cfe_msg_init.c -------------------------------------------------------------------------
I32 CFE_MSG_Init(CFE_MSG_Message *MsgPtr, CFE_SB_MsgId MsgId, I64 Size)
{
  I32 status;
  if (MsgPtr == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  // Clear and set defaults
  MemSet(MsgPtr, 0, Size);
  CFE_MSG_InitDefaultHdr(MsgPtr);
  // Set values input
  // Allow "CFE_SB_INVALID_MSG_ID" here - in some cases the real msgid is filled in later
  // however the size should always be a valid value
  if (CFE_SB_MsgIdToValue(MsgId) == CFE_SB_MsgIdToValue(CFE_SB_InvalidMsgId))
    status = CFE_SUCCESS;
  else
    status = CFE_MSG_SetMsgId(MsgPtr, MsgId);
  if (status == CFE_SUCCESS)
    status = CFE_MSG_SetSize(MsgPtr, Size);
  return status;
}
#endif
