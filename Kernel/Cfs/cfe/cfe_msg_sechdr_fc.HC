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

// 1:1 HolyC translation of cFE modules/msg/fsw/src/cfe_msg_sechdr_fc.c, with the secondary-header
// types it needs from modules/msg/option_inc/default_cfe_msg_sechdr.h and
// default_cfe_msg_hdr_pri.h.
//
// This is the first unit that CASTS a base message pointer to a command header -- the C does
// exactly that, and HolyC's cast syntax expresses it directly. It is also the first unit whose
// result depends on the primary header's own fields: a function code only exists on a version-1
// CCSDS command that says it HAS a secondary header, so the same call returns WRONG_MSG_TYPE or
// SUCCESS depending on three bits set by the module translated alongside it. That coupling is why
// the differential transcript covers the rejection paths and not only the happy one.
#ifndef CFE_MSG_SECHDR_FC_HC
#define CFE_MSG_SECHDR_FC_HC
#include "cfe_msg_ccsdspri.HC"
// From cfe_msg_api_typedefs.h -> cfe_error.h: CFE_MSG_WRONG_MSG_TYPE is CFE_SB_WRONG_MSG_TYPE.
#define CFE_MSG_WRONG_MSG_TYPE 0xCA00000D
// From cfe_msg_defaults.h. Zero, per CCSDS 133.0-B-2 section 4.1.3.2 -- version 1 of the CCSDS
// header is the bit pattern '000', so the "version" this code compares against is 0, not 1.
#define CFE_MISSION_CCSDSVER 0
#define CFE_MSG_FC_MASK 0x7F
// --- default_cfe_msg_sechdr.h ---------------------------------------------------------------
class CFE_MSG_CommandSecondaryHeader
{
  U8 FunctionCode;
  U8 Checksum;
};

class CFE_MSG_TelemetrySecondaryHeader
{
  U8 Time[6];
};
// --- default_cfe_msg_hdr_pri.h --------------------------------------------------------------
class CFE_MSG_CommandHeader
{
  CFE_MSG_Message Msg;
  CFE_MSG_CommandSecondaryHeader Sec;
};

class CFE_MSG_TelemetryHeader
{
  CFE_MSG_Message Msg;
  CFE_MSG_TelemetrySecondaryHeader Sec;
  U8 Spare[4];
};
// --- cfe_msg_sechdr_fc.c --------------------------------------------------------------------
I32 CFE_MSG_GetFcnCode(CFE_MSG_Message *MsgPtr, U16 *FcnCode)
{
  U16 version;
  I64 type;
  Bool hassechdr = FALSE;
  CFE_MSG_CommandHeader *cmd = MsgPtr(CFE_MSG_CommandHeader *);
  if (MsgPtr == NULL || FcnCode == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  // Ignore return, pointer already checked
  CFE_MSG_GetHasSecondaryHeader(MsgPtr, &hassechdr);
  CFE_MSG_GetHeaderVersion(MsgPtr, &version);
  CFE_MSG_GetType(MsgPtr, &type);
  if (version != CFE_MISSION_CCSDSVER || type != CFE_MSG_Type_Cmd || !hassechdr) {
    *FcnCode = 0;
    return CFE_MSG_WRONG_MSG_TYPE;
  }
  *FcnCode = cmd->Sec.FunctionCode & CFE_MSG_FC_MASK;
  return CFE_SUCCESS;
}

I32 CFE_MSG_SetFcnCode(CFE_MSG_Message *MsgPtr, U16 FcnCode)
{
  U16 version;
  I64 type;
  Bool hassechdr = FALSE;
  CFE_MSG_CommandHeader *cmd = MsgPtr(CFE_MSG_CommandHeader *);
  if (MsgPtr == NULL || FcnCode > CFE_MSG_FC_MASK)
    return CFE_MSG_BAD_ARGUMENT;
  // Ignore return, pointer already checked
  CFE_MSG_GetHasSecondaryHeader(MsgPtr, &hassechdr);
  CFE_MSG_GetHeaderVersion(MsgPtr, &version);
  CFE_MSG_GetType(MsgPtr, &type);
  if (version != CFE_MISSION_CCSDSVER || type != CFE_MSG_Type_Cmd || !hassechdr)
    return CFE_MSG_WRONG_MSG_TYPE;
  cmd->Sec.FunctionCode = FcnCode;
  return CFE_SUCCESS;
}
#endif
