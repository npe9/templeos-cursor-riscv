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

// 1:1 HolyC translation of cFE modules/msg/fsw/src/cfe_msg_sechdr_checksum.c.
//
// The checksum is an XOR of every byte of the packet, and the packet length comes from the
// primary header -- so the checksum reads a length the CALLER wrote and then walks that many
// bytes. CFE_MSG_ComputeCheckSum trusts it completely ("Message already checked, no error case
// reachable"). Translating that faithfully means translating the trust: the loop bound is
// whatever GetSize returns, and GetSize adds CFE_MSG_SIZE_OFFSET to two header bytes. The oracle
// sets a size, generates, validates, corrupts a byte, and validates again, so the two
// implementations have to agree on all of it -- including that a zero checksum field is what
// makes the recomputation come out zero.
#ifndef CFE_MSG_SECHDR_CHECKSUM_HC
#define CFE_MSG_SECHDR_CHECKSUM_HC
#include "cfe_msg_sechdr_fc.HC"

U8 CFE_MSG_ComputeCheckSum(CFE_MSG_Message *MsgPtr)
{
  I64 PktLen = 0;
  U8 *BytePtr = MsgPtr(U8 *);
  U8 chksum = 0xFF;
  // Message already checked, no error case reachable
  CFE_MSG_GetSize(MsgPtr, &PktLen);
  while (PktLen--)
    chksum ^= *(BytePtr++);
  return chksum;
}

I32 CFE_MSG_GenerateChecksum(CFE_MSG_Message *MsgPtr)
{
  I64 type;
  U16 version;
  Bool hassechdr = FALSE;
  CFE_MSG_CommandHeader *cmd = MsgPtr(CFE_MSG_CommandHeader *);
  if (MsgPtr == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  // Ignore return, pointer already checked
  CFE_MSG_GetHasSecondaryHeader(MsgPtr, &hassechdr);
  CFE_MSG_GetHeaderVersion(MsgPtr, &version);
  CFE_MSG_GetType(MsgPtr, &type);
  if (version != CFE_MISSION_CCSDSVER || type != CFE_MSG_Type_Cmd || !hassechdr)
    return CFE_MSG_WRONG_MSG_TYPE;
  // Zero checksum so new checksum will be correct
  cmd->Sec.Checksum = 0;
  // Compute using aligned MsgPtr and set
  cmd->Sec.Checksum = CFE_MSG_ComputeCheckSum(MsgPtr);
  return CFE_SUCCESS;
}

I32 CFE_MSG_ValidateChecksum(CFE_MSG_Message *MsgPtr, Bool *IsValid)
{
  I64 type;
  U16 version;
  Bool hassechdr = FALSE;
  if (MsgPtr == NULL || IsValid == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  // Ignore return, pointer already checked
  CFE_MSG_GetHasSecondaryHeader(MsgPtr, &hassechdr);
  CFE_MSG_GetHeaderVersion(MsgPtr, &version);
  CFE_MSG_GetType(MsgPtr, &type);
  if (version != CFE_MISSION_CCSDSVER || type != CFE_MSG_Type_Cmd || !hassechdr)
    return CFE_MSG_WRONG_MSG_TYPE;
  // Compute, valid if == 0
  *IsValid = (CFE_MSG_ComputeCheckSum(MsgPtr) == 0);
  return CFE_SUCCESS;
}
#endif
