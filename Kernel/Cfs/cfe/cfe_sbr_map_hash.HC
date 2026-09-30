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

// 1:1 HolyC translation of cFE modules/sbr/fsw/src/cfe_sbr_map_hash.c -- the default
// message-id-to-route map, selected by MISSION_MSGMAP_IMPLEMENTATION defaulting to HASH.
//
// THE HASH IS 32-BIT ARITHMETIC AND THAT IS LOAD-BEARING. Every step multiplies by 0x45d9f3b
// and the product OVERFLOWS; the whole function is that overflow, twice. C does it in uint32
// because CFE_SB_MsgId_Atom_t is uint32, so the wrap is the algorithm. HolyC computes in 64
// bits and only NARROWS ON THE STORE, so `hash` must be a U32 local and every assignment must
// land in it -- keep the intermediate in an I64 and the multiply does not wrap, and every hash
// value in the table differs from NASA's. The differential transcript checks the hash of a
// spread of message ids for exactly this reason: it is a property no amount of reading the
// translation would confirm.
//
// The collision handling is open addressing with linear probing, and SetRouteId RETURNS the
// number of probes it took -- the software bus reports that as a housekeeping counter, so the
// count is observable behaviour and not a diagnostic.
#ifndef CFE_SBR_MAP_HASH_HC
#define CFE_SBR_MAP_HASH_HC
#include "cfe_sbr_route_unsorted.HC"
// Sized to give a load factor of 1/4 at capacity
#define CFE_SBR_MSG_MAP_SIZE (4 * CFE_PLATFORM_SB_MAX_MSG_IDS)
// The C has a #error here if CFE_SBR_MSG_MAP_SIZE is not a power of two, since the size doubles
// as the wrap mask. HolyC's preprocessor has no #error, so the property is asserted at runtime
// in the oracle instead of being dropped in translation.
#define CFE_SBR_HASH_MAGIC 0x45d9f3b

CFE_SBR_RouteId CFE_SBR_MSGMAP[CFE_SBR_MSG_MAP_SIZE];

U32 CFE_SBR_MsgIdHash(CFE_SB_MsgId MsgId)
{
  U32 hash;
  hash = CFE_SB_MsgIdToValue(MsgId);
  hash = ((hash >> 16) ^ hash) * CFE_SBR_HASH_MAGIC;
  hash = ((hash >> 16) ^ hash) * CFE_SBR_HASH_MAGIC;
  hash = (hash >> 16) ^ hash;
  // Reduce to fit in map. Parenthesised where the C is not, but MEASURED to be unnecessary
  // rather than assumed: HolyC binds `&` tighter than `-`, so `h & SIZE - 1` in an expression
  // really does mean `(h & SIZE) - 1` -- 0x12345 & 1024 - 1 yields -1, not 837 -- but a
  // COMPOUND assignment parses its whole right-hand side first, so the C's bare
  // `hash &= CFE_SBR_MSG_MAP_SIZE - 1;` would have been correct here too. The negative control
  // that removed these parentheses left all 119 transcript lines identical, which is how that
  // is known. Kept for the reader, since the trap is real one line over in an expression.
  hash &= (CFE_SBR_MSG_MAP_SIZE - 1);
  return hash;
}

U0 CFE_SBR_Init_Map()
{
  // Clear the shared data
  memset(&CFE_SBR_MSGMAP, 0, sizeof(CFE_SBR_MSGMAP));
}

U32 CFE_SBR_SetRouteId(CFE_SB_MsgId MsgId, CFE_SBR_RouteId RouteId)
{
  U32 hash;
  U32 collisions = 0;
  if (CFE_SB_IsValidMsgId(MsgId)) {
    hash = CFE_SBR_MsgIdHash(MsgId);
    // Increment until an unused entry is found
    while (CFE_SBR_IsValidRouteId(CFE_SBR_MSGMAP[hash])) {
      // Increment or loop to start of array
      hash = (hash + 1) & (CFE_SBR_MSG_MAP_SIZE - 1);
      collisions++;
    }
    CFE_SBR_MSGMAP[hash] = RouteId;
  }
  return collisions;
}

CFE_SBR_RouteId CFE_SBR_GetRouteId(CFE_SB_MsgId MsgId)
{
  U32 hash;
  CFE_SBR_RouteId routeid = CFE_SBR_InvalidRouteId;
  if (CFE_SB_IsValidMsgId(MsgId)) {
    hash = CFE_SBR_MsgIdHash(MsgId);
    routeid = CFE_SBR_MSGMAP[hash];
    // Increment while a valid route id is found that does not match the message id
    while (CFE_SBR_IsValidRouteId(routeid) && !CFE_SB_MsgId_Equal(CFE_SBR_GetMsgId(routeid), MsgId)) {
      // Increment or loop to start of array
      hash = (hash + 1) & (CFE_SBR_MSG_MAP_SIZE - 1);
      routeid = CFE_SBR_MSGMAP[hash];
    }
  }
  return routeid;
}
#endif
