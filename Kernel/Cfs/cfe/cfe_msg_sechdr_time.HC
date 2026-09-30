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

// 1:1 HolyC translation of cFE modules/msg/fsw/src/cfe_msg_sechdr_time.c, with CFE_TIME_SysTime_t
// from modules/time/config/default_cfe_time_extern_typedefs.h.
//
// The comment in the C file -- "cFS default 32 bit seconds, 16 bit subseconds in big endian
// format" -- is the whole design: the telemetry secondary header carries six bytes, and the
// struct it converts to and from carries two 32-bit words. So a round trip is LOSSY BY
// CONSTRUCTION. Set a subsecond value and read it back and the low 16 bits are gone, because
// only Time[4] and Time[5] exist to hold them. The oracle exercises that on purpose: it is the
// kind of thing a translation "cleans up" by accident, and then the two transcripts disagree.
#ifndef CFE_MSG_SECHDR_TIME_HC
#define CFE_MSG_SECHDR_TIME_HC
#include "cfe_msg_sechdr_fc.HC"
#include "../CfsStr.HC"
// --- default_cfe_time_extern_typedefs.h -----------------------------------------------------
class CFE_TIME_SysTime
{
  U32 Seconds;    // Number of seconds since epoch
  U32 Subseconds; // Number of subseconds since epoch (LSB = 2^(-32) seconds)
};
// --- cfe_msg_sechdr_time.c ------------------------------------------------------------------
I32 CFE_MSG_SetMsgTime(CFE_MSG_Message *MsgPtr, CFE_TIME_SysTime NewTime)
{
  I64 type;
  U16 version;
  Bool hassechdr = FALSE;
  CFE_MSG_TelemetryHeader *tlm = MsgPtr(CFE_MSG_TelemetryHeader *);
  if (MsgPtr == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  // Ignore return, pointer already checked
  CFE_MSG_GetHasSecondaryHeader(MsgPtr, &hassechdr);
  CFE_MSG_GetHeaderVersion(MsgPtr, &version);
  CFE_MSG_GetType(MsgPtr, &type);
  if (version != CFE_MISSION_CCSDSVER || type != CFE_MSG_Type_Tlm || !hassechdr)
    return CFE_MSG_WRONG_MSG_TYPE;
  // Set big endian time field with default 32/16 layout
  tlm->Sec.Time[0] = (NewTime.Seconds >> 24) & 0xFF;
  tlm->Sec.Time[1] = (NewTime.Seconds >> 16) & 0xFF;
  tlm->Sec.Time[2] = (NewTime.Seconds >> 8) & 0xFF;
  tlm->Sec.Time[3] = NewTime.Seconds & 0xFF;
  tlm->Sec.Time[4] = (NewTime.Subseconds >> 24) & 0xFF;
  tlm->Sec.Time[5] = (NewTime.Subseconds >> 16) & 0xFF;
  return CFE_SUCCESS;
}

I32 CFE_MSG_GetMsgTime(CFE_MSG_Message *MsgPtr, CFE_TIME_SysTime *Time)
{
  I64 type;
  U16 version;
  Bool hassechdr = FALSE;
  CFE_MSG_TelemetryHeader *tlm = MsgPtr(CFE_MSG_TelemetryHeader *);
  if (MsgPtr == NULL || Time == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  // Ignore return, pointer already checked
  CFE_MSG_GetHasSecondaryHeader(MsgPtr, &hassechdr);
  CFE_MSG_GetHeaderVersion(MsgPtr, &version);
  CFE_MSG_GetType(MsgPtr, &type);
  if (version != CFE_MISSION_CCSDSVER || type != CFE_MSG_Type_Tlm || !hassechdr) {
    MemSet(Time, 0, sizeof(CFE_TIME_SysTime));
    return CFE_MSG_WRONG_MSG_TYPE;
  }
  // Get big endian time fields with default 32/16 layout
  // The C writes (uint32)tlm->Sec.Time[n] here. THE CAST DOES NOT SURVIVE TRANSLATION, and
  // writing it as tlm->Sec.Time[n](U32) would be a silent bug: a HolyC cast on an LVALUE
  // relabels the storage rather than converting the value, so that expression reads FOUR bytes
  // starting at Time[n] instead of widening the one byte there. Measured, not assumed --
  // t[0](U32) over the bytes 12 34 56 78 yields 0x78563412, while (t[0] + 0)(U32) yields 0x12.
  //
  // Dropping it is the faithful translation, not a shortcut. In C the cast exists to stop a
  // uint8 promoting to a signed int before the shift, which would make 0x9A << 24 overflow.
  // HolyC loads a U8 zero-extended into a 64-bit register and shifts there, so the overflow the
  // cast defends against cannot happen, and the store to a U32 field truncates exactly as C's
  // uint32 arithmetic would. Same values, and the oracle is what says so.
  Time->Subseconds = (tlm->Sec.Time[4] << 24) + (tlm->Sec.Time[5] << 16);
  Time->Seconds = (tlm->Sec.Time[0] << 24) + (tlm->Sec.Time[1] << 16) +
                  (tlm->Sec.Time[2] << 8) + tlm->Sec.Time[3];
  return CFE_SUCCESS;
}
#endif
