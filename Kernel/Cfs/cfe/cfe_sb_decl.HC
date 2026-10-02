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
// The three PUBLIC SB declarations from cFE modules/core_api/fsw/inc/cfe_sb_api_typedefs.h and
// modules/sb/config/default_cfe_sb_extern_typedefs.h that modules outside SB need, and nothing
// else.
//
// WHY IT IS ITS OWN FILE. CFE_SB_Buffer lived in cfe_ta_task.HC, which is where it was first
// needed -- and that was fine while SB was not translated. It is a SOFTWARE BUS type, every
// module that receives a message uses it, and cfe_sb_global.HC now needs it for the Content
// member of the buffer descriptor. Including cfe_sb_global.HC to get it would drag in
// CFE_SB_Global, whose Mem.Partition alone is 512 KiB, into every unit that only wants to name a
// message buffer. cfe_time_decl.HC exists for exactly this reason and records the same argument.
#ifndef CFE_SB_DECL_HC
#define CFE_SB_DECL_HC
#include "cfe_msg_sechdr_fc.HC" // CFE_MSG_Message, which the buffer is a view of
// A union whose other members exist only to force the ALIGNMENT a message buffer needs, which is
// why RawData is sizeof(CFE_MSG_Message_t) and not a buffer size: the SIZE of this type is one
// message HEADER, and the storage behind a real buffer runs past it. CFE_SB_BufferD_t keeps it
// last for that reason.
union CFE_SB_Buffer
{
  CFE_MSG_Message Msg;
  // Base message type without enforced alignment
  I64 LongInt;
  // Align to support Long Integer
  F64 LongDouble;
  // Align to support Long Double
  U8 RawData[6];
  // Allows access as opaque octet data; sizeof(CFE_MSG_Message_t)
};
// Quality of service, and NASA's comment is that it is CURRENTLY UNUSED -- an unused parameter in
// CFE_SB_SubscribeEx, intended for interprocessor communication. Both members are uint8 typedefs
// (CFE_SB_QosPriority_Enum_t, CFE_SB_QosReliability_Enum_t), so the type is two bytes, and that
// matters: it is a member of CFE_SB_Global and of two telemetry payloads, so getting its width
// wrong moves the fields after it in a ground-visible packet.
class CFE_SB_Qos_t
{
  U8 Priority;
  // CFE_SB_QosPriority_Enum_t -- high(1) or low(0), for off-board routing
  U8 Reliability;
  // CFE_SB_QosReliability_Enum_t
};
// CFE_SB_ReceiveBuffer's timeout: block until a message arrives.
#ifndef CFE_SB_PEND_FOREVER
#define CFE_SB_PEND_FOREVER -1
#endif
#endif
