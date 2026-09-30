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

// 1:1 HolyC translation of cFE modules/msg/fsw/src/cfe_msg_integrity.c.
//
// Both hooks in the DEFAULT implementation accept everything -- VerificationAction's body is a
// comment saying so. They exist for a mission to replace. Translating a hook that does nothing
// still matters: it is the seam a real integrity check would be installed at, and it is where
// the two calls below establish that a message is stamped on the way out.
//
// The interesting line is the one that IGNORES two return values. OriginationAction calls
// SetMsgTime and GenerateChecksum on the same buffer, and exactly one of them can succeed: the
// first only works on telemetry, the second only on a command. The C says so ("This may fail if
// this is not a TLM packet (that is OK)"). So the transcript below has to show a command coming
// back with a checksum and no timestamp, and telemetry the other way round.
#ifndef CFE_MSG_INTEGRITY_HC
#define CFE_MSG_INTEGRITY_HC
#include "cfe_msg_sechdr_time.HC"
#include "cfe_msg_sechdr_checksum.HC"
// From cfe_time.h. The TIME module is not translated yet, so this is a DECLARATION only and the
// harness supplies the body -- the same arrangement the C oracle uses for CFE_PSP_GetProcessorId.
// A stub is honest here in a way it would not be for a function under test: nothing about
// OriginationAction depends on what the clock says, only on the call happening.
CFE_TIME_SysTime CFE_TIME_GetTime();

// BufferSize is unused in the default implementation, in the C as well.
I32 CFE_MSG_OriginationAction(CFE_MSG_Message *MsgPtr, I64 BufferSize, Bool *IsAcceptable)
{
  if (MsgPtr == NULL || IsAcceptable == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  // TLM packets have a timestamp in the secondary header.
  // This may fail if this is not a TLM packet (that is OK)
  CFE_MSG_SetMsgTime(MsgPtr, CFE_TIME_GetTime);
  // CMD packets have a checksum in the secondary header.
  // This may fail if this is not a CMD packet (that is OK)
  CFE_MSG_GenerateChecksum(MsgPtr);
  // This implementation permits all outgoing messages
  *IsAcceptable = TRUE;
  return CFE_SUCCESS;
}

I32 CFE_MSG_VerificationAction(CFE_MSG_Message *MsgPtr, I64 BufferSize, Bool *IsAcceptable)
{
  if (MsgPtr == NULL || IsAcceptable == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  // In the default implementation, there is not anything to check here.
  //
  // This is mainly a hook for user expansion, in case a custom implementation
  // has message verification capability.
  *IsAcceptable = TRUE;
  return CFE_SUCCESS;
}
#endif
