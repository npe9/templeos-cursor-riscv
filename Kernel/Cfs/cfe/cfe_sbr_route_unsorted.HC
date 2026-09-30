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

// 1:1 HolyC translation of the cFE software-bus ROUTING module: the types from
// modules/core_private/fsw/inc/cfe_sbr_api_typedefs.h and cfe_sbr.h, and the route table from
// modules/sbr/fsw/src/cfe_sbr_route_unsorted.c. The message-id-to-route map that goes with it
// is in cfe_sbr_map_hash.HC.
//
// WHICH VARIANTS. modules/sbr/CMakeLists.txt picks the map implementation from
// MISSION_MSGMAP_IMPLEMENTATION, defaulting to HASH -- so a stock build compiles
// cfe_sbr_map_hash.c, cfe_sbr_route_unsorted.c and cfe_sbr_objtab.c, and NOT
// cfe_sbr_map_direct.c. That default is what is translated. The route table has no variants.
//
// This is the layer the simulated spacecraft's bus reimplements by hand today: subscribe a
// message id, get a route, walk the destinations. Translating it is the step that would let
// CfsSb.HC's routing be NASA's rather than its own.
#ifndef CFE_SBR_ROUTE_UNSORTED_HC
#define CFE_SBR_ROUTE_UNSORTED_HC
#include "cfe_sb_msgid.HC"
#include "../CfsStr.HC"
// From cmake/sample_defs/example_platform_cfg.h, reaching the module as
// CFE_PLATFORM_SB_CFGVAL(MAX_MSG_IDS).
#define CFE_PLATFORM_SB_MAX_MSG_IDS 256
// --- default_cfe_sb_extern_typedefs.h --------------------------------------------------------
// A route index is 16 bits, NOT 32 like a message id. The distinction matters below.
// CFE_SB_RouteId_Atom_t is U16.
// --- cfe_sbr_api_typedefs.h ------------------------------------------------------------------
// The same opaque-wrapper idiom as CFE_SB_MsgId, and with the same purpose: a route id cannot be
// confused with an index. Note the OFF-BY-ONE that makes it work -- ValueToRouteId stores
// index+1, so a zeroed structure is the invalid id rather than route 0.
class CFE_SBR_RouteId
{
  U16 RouteId; // Holding value, do not use directly in code
};

// Callback throttling structure
class CFE_SBR_Throttle
{
  U32 StartIndex; // 0 based index to start at
  U32 MaxLoop;    // Max number to process
  U32 NextIndex;  // Next start index (output), 0 if completed
};
// For each id callback function prototype:
//   typedef void (*CFE_SBR_CallbackPtr_t)(CFE_SBR_RouteId_t RouteId, void *ArgPtr);
// HolyC has no typedef, so it is spelled out at the one parameter that takes it.

// CFE_SB_DestinationD_t is SB's destination descriptor. This module only ever stores and returns
// the POINTER, never looks inside, so it stays opaque here rather than dragging in cfe_sb_priv.h.
#define CFE_SB_DestinationD U8
// --- cfe_sbr.h, the inline helpers -----------------------------------------------------------
// CFE_SBR_INVALID_ROUTE_ID is a compound literal in the C; HolyC has none, so it is a function,
// exactly as CFE_SB_INVALID_MSG_ID became CFE_SB_InvalidMsgId.
CFE_SBR_RouteId CFE_SBR_InvalidRouteId()
{
  CFE_SBR_RouteId Result;
  Result.RouteId = 0;
  return Result;
}

Bool CFE_SBR_IsValidRouteId(CFE_SBR_RouteId RouteId)
{
  return RouteId.RouteId != 0 && RouteId.RouteId <= CFE_PLATFORM_SB_MAX_MSG_IDS;
}

CFE_SBR_RouteId CFE_SBR_ValueToRouteId(U16 Value)
{
  CFE_SBR_RouteId Result;
  Result.RouteId = 1 + Value;
  return Result;
}

U16 CFE_SBR_RouteIdToValue(CFE_SBR_RouteId RouteId)
{
  return RouteId.RouteId - 1;
}
// --- cfe_sbr_priv.h --------------------------------------------------------------------------
// Defined in cfe_sbr_map_hash.HC, which includes this file.
U0 CFE_SBR_Init_Map();
U32 CFE_SBR_SetRouteId(CFE_SB_MsgId MsgId, CFE_SBR_RouteId RouteId);
// --- cfe_sbr_route_unsorted.c ----------------------------------------------------------------
class CFE_SBR_RouteEntry
{
  CFE_SB_DestinationD *ListHeadPtr; // Destination list head
  CFE_SB_MsgId MsgId;               // Message ID associated with route
  U16 SeqCnt;                       // Message sequence counter
};

class cfe_sbr_route_data
{
  CFE_SBR_RouteEntry RoutingTbl[CFE_PLATFORM_SB_MAX_MSG_IDS]; // Routing table
  U16 RouteIdxTop;                                            // First unused entry in RoutingTbl
};

cfe_sbr_route_data CFE_SBR_RDATA;

U0 CFE_SBR_Init()
{
  U16 routeidx;
  // Clear the shared data
  MemSet(&CFE_SBR_RDATA, 0, sizeof(cfe_sbr_route_data));
  // Only non-zero value for shared data initialization is the invalid MsgId
  for (routeidx = 0; routeidx < CFE_PLATFORM_SB_MAX_MSG_IDS; routeidx++)
    CFE_SBR_RDATA.RoutingTbl[routeidx].MsgId = CFE_SB_InvalidMsgId;
  // Initialize map
  CFE_SBR_Init_Map;
}

CFE_SBR_RouteId CFE_SBR_AddRoute(CFE_SB_MsgId MsgId, U32 *CollisionsPtr)
{
  CFE_SBR_RouteId routeid = CFE_SBR_InvalidRouteId;
  U32 collisions = 0;
  if (CFE_SB_IsValidMsgId(MsgId) && CFE_SBR_RDATA.RouteIdxTop < CFE_PLATFORM_SB_MAX_MSG_IDS) {
    routeid = CFE_SBR_ValueToRouteId(CFE_SBR_RDATA.RouteIdxTop);
    collisions = CFE_SBR_SetRouteId(MsgId, routeid);
    CFE_SBR_RDATA.RoutingTbl[CFE_SBR_RDATA.RouteIdxTop].MsgId = MsgId;
    CFE_SBR_RDATA.RouteIdxTop++;
  }
  if (CollisionsPtr != NULL)
    *CollisionsPtr = collisions;
  return routeid;
}

CFE_SB_MsgId CFE_SBR_GetMsgId(CFE_SBR_RouteId RouteId)
{
  CFE_SB_MsgId msgid = CFE_SB_InvalidMsgId;
  if (CFE_SBR_IsValidRouteId(RouteId))
    msgid = CFE_SBR_RDATA.RoutingTbl[CFE_SBR_RouteIdToValue(RouteId)].MsgId;
  return msgid;
}

CFE_SB_DestinationD *CFE_SBR_GetDestListHeadPtr(CFE_SBR_RouteId RouteId)
{
  CFE_SB_DestinationD *destptr = NULL;
  if (CFE_SBR_IsValidRouteId(RouteId))
    destptr = CFE_SBR_RDATA.RoutingTbl[CFE_SBR_RouteIdToValue(RouteId)].ListHeadPtr;
  return destptr;
}

U0 CFE_SBR_SetDestListHeadPtr(CFE_SBR_RouteId RouteId, CFE_SB_DestinationD *DestPtr)
{
  if (CFE_SBR_IsValidRouteId(RouteId))
    CFE_SBR_RDATA.RoutingTbl[CFE_SBR_RouteIdToValue(RouteId)].ListHeadPtr = DestPtr;
}

U0 CFE_SBR_IncrementSequenceCounter(CFE_SBR_RouteId RouteId)
{
  U16 *cnt;
  if (CFE_SBR_IsValidRouteId(RouteId)) {
    cnt = &CFE_SBR_RDATA.RoutingTbl[CFE_SBR_RouteIdToValue(RouteId)].SeqCnt;
    *cnt = CFE_MSG_GetNextSequenceCount(*cnt);
  }
}

U16 CFE_SBR_GetSequenceCounter(CFE_SBR_RouteId RouteId)
{
  U16 seqcnt = 0;
  if (CFE_SBR_IsValidRouteId(RouteId))
    seqcnt = CFE_SBR_RDATA.RoutingTbl[CFE_SBR_RouteIdToValue(RouteId)].SeqCnt;
  return seqcnt;
}

U0 CFE_SBR_ForEachRouteId(U0 (*CallbackPtr)(CFE_SBR_RouteId, U8 *), U8 *ArgPtr,
                          CFE_SBR_Throttle *ThrottlePtr)
{
  U16 routeidx;
  U16 startidx = 0;
  U16 endidx = CFE_SBR_RDATA.RouteIdxTop;
  // Update throttle settings if needed
  if (ThrottlePtr != NULL) {
    startidx = ThrottlePtr->StartIndex;
    // Return next index of zero if full range is processed
    ThrottlePtr->NextIndex = 0;
    if (startidx + ThrottlePtr->MaxLoop < endidx) {
      endidx = startidx + ThrottlePtr->MaxLoop;
      ThrottlePtr->NextIndex = endidx;
    }
  }
  for (routeidx = startidx; routeidx < endidx; routeidx++)
    (*CallbackPtr)(CFE_SBR_ValueToRouteId(routeidx), ArgPtr);
}
#endif
