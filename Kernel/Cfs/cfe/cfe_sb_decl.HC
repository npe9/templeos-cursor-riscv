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
// CFE_SB_DEFAULT_QOS IS A COMPOUND LITERAL IN C -- `((CFE_SB_Qos_t){0})` -- and HolyC has no
// such expression, so it is a ZEROED GLOBAL here instead. The three callers (CFE_SB_Subscribe,
// CFE_SB_SubscribeLocal and every app that passes the default) only ever READ it, and HolyC
// zeroes globals, so the value they see is the same two zero bytes C would have built on the
// stack. The one behavioural difference is that a caller could now WRITE to it; nothing does,
// and the translation gate compares the transcript, which would show it if anything did.
CFE_SB_Qos_t CFE_SB_DEFAULT_QOS;
// SB's DESTINATION DESCRIPTOR, from core_private/fsw/inc/cfe_sb_destination_typedef.h, and NASA's
// warning on it is the same one the buffer descriptor carries: "Changing the size of this
// structure may require the memory pool block sizes to change." One of these exists per
// (message id, pipe) route, they are allocated from the same 512 KiB pool as the buffers, and
// cfe_sb_buf.c's CFE_SB_GetDestinationBlk sizes the allocation with sizeof() -- so the layout is
// load-bearing rather than descriptive.
//
// IT WAS `#define CFE_SB_DestinationD U8` IN THIS PORT until SB's buffer layer needed it.
// cfe_sbr_route_unsorted.HC only ever stores and returns the POINTER and never looks inside, so
// an opaque byte was enough there and the comment said so. It is not enough for the module that
// allocates them.
class CFE_SB_DestinationD_t
{
  U32 PipeId;
  // CFE_SB_PipeId_t
  U8 Active;
  U8 _pad0[1];
  // C aligns MsgId2PipeLim to 2
  U16 MsgId2PipeLim;
  U16 BuffCount;
  U16 DestCnt;
  U8 Scope;
  U8 Spare[3];
  // NASA's own, and they are what makes the pointers land on 16 with no padding of mine
  CFE_SB_DestinationD_t *Prev;
  CFE_SB_DestinationD_t *Next;
};
// CFE_SB_ReceiveBuffer's timeout: block until a message arrives.
#ifndef CFE_SB_PEND_FOREVER
#define CFE_SB_PEND_FOREVER -1
#endif
#endif
