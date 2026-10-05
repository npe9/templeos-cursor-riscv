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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_dumpctl.c AND the five
// `static inline` accessors of cfe_tbl_dumpctl.h -- DUMP-ONLY TABLES' HANDSHAKE.
//
// WHAT A DUMP CONTROL BLOCK IS FOR. Most tables are LOADED: the ground sends a file, Table
// Services validates it and the app picks it up. A DUMP-ONLY table runs the other way -- the
// app owns the only copy and the ground asks for a snapshot of it. Table Services cannot just
// read the app's buffer, because the app may be halfway through writing it, so instead it
// records a REQUEST and waits: the block goes to CFE_TBL_DUMP_PENDING, and the next time the
// owning app calls CFE_TBL_Manage it notices, copies its own table into the dump buffer at a
// moment of its choosing, and the block becomes CFE_TBL_DUMP_PERFORMED.
//
// So these four blocks are a rendezvous between the ground and an application that is not
// listening for it. There are CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS of them -- four -- which
// is the same number as the shared load buffers, because a dump and a load both need somewhere
// to put a table-sized block of memory.
//
// THE RESOURCE-ID PATTERN, which is the same in all five of tbl's id spaces and in ES's four.
// A block is addressed by an ID, not an index: the id carries a base value identifying WHICH
// KIND of resource it is, so handing a dump-control id to something expecting a registry id is
// caught rather than silently indexing the wrong array. ToIndex subtracts the base and range
// checks; Locate turns an id into a pointer or NULL; IsUsed/SetUsed/SetFree are the allocator.
#ifndef CFE_TBL_DUMPCTL_HC
#define CFE_TBL_DUMPCTL_HC

// --- cfe_tbl_dumpctl.h: the five accessors ------------------------------------------------
// NASA writes these as `static inline` in the header. They are functions here, for the reason
// cfe_es_resource.HC records: HolyC has no inline, and a header inline is as much a part of
// the translation as anything in the .c -- tools/cfs/check_header_inlines.py now requires them.
Bool CFE_TBL_DumpCtrlBlockIsMatch(CFE_TBL_DumpControl_t *BlockPtr, U32 BlockId)
{
  return BlockPtr != NULL && CFE_ResourceId_Equal(BlockPtr->BlockId, BlockId);
}

Bool CFE_TBL_DumpCtrlBlockIsUsed(CFE_TBL_DumpControl_t *BlockPtr)
{
  return CFE_ResourceId_IsDefined(BlockPtr->BlockId);
}

U0 CFE_TBL_DumpCtrlBlockSetUsed(CFE_TBL_DumpControl_t *BlockPtr, U32 PendingId)
{
  BlockPtr->BlockId = PendingId;
}

U0 CFE_TBL_DumpCtrlBlockSetFree(CFE_TBL_DumpControl_t *BlockPtr)
{
  // BOTH FIELDS, and the order is NASA's. State goes back to FREE as well as the id being
  // cleared, because the state is what CFE_TBL_Manage switches on and a recycled block that
  // kept PERFORMED would be copied again by the next owner.
  BlockPtr->State = CFE_TBL_DUMP_FREE;
  BlockPtr->BlockId = CFE_TBL_DUMPCTRLID_UNDEFINED;
}

U32 CFE_TBL_DumpCtrlBlockGetId(CFE_TBL_DumpControl_t *BlockPtr)
{
  return BlockPtr->BlockId;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_TBL_DumpCtrlId_ToIndex(U32 DumpCtrlId, U32 *Idx)
{
  return CFE_ResourceId_ToIndex(DumpCtrlId, CFE_TBL_DUMPCTRLID_BASE,
                                CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS, Idx);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_TBL_DumpControl_t *CFE_TBL_LocateDumpCtrlByID(U32 BlockId)
{
  CFE_TBL_DumpControl_t *BlockPtr;
  U32 Idx;
  if (CFE_TBL_DumpCtrlId_ToIndex(BlockId, &Idx) == CFE_SUCCESS) {
    BlockPtr = &CFE_TBL_Global.DumpControlBlocks[Idx];
  } else {
    BlockPtr = NULL;
  }
  return BlockPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_TBL_CheckDumpCtrlSlotUsed(U32 CheckId)
{
  CFE_TBL_DumpControl_t *BlockPtr;
  /*
  ** Note - The pointer here should never be NULL because the ID should always be
  ** within the expected range, but if it ever is NULL, this should return true
  ** such that the caller will _not_ attempt to use the record.
  */
  BlockPtr = CFE_TBL_LocateDumpCtrlByID(CheckId);
  return BlockPtr == NULL || CFE_TBL_DumpCtrlBlockIsUsed(BlockPtr);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U32 CFE_TBL_GetNextDumpCtrlBlock()
{
  return CFE_ResourceId_FindNext(CFE_TBL_Global.LastDumpCtrlBlockId,
                                 CFE_PLATFORM_TBL_MAX_SIMULTANEOUS_LOADS,
                                 &CFE_TBL_CheckDumpCtrlSlotUsed);
}
#endif
