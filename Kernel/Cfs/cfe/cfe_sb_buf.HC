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
// 1:1 HolyC translation of cFE modules/sb/fsw/src/cfe_sb_buf.c -- SB's BUFFER LIFETIME.
//
// NINE FUNCTIONS, AND THE WHOLE FILE IS ABOUT ONE INVARIANT: a message buffer is freed when the
// last reference to it goes away, and not before. A message transmitted to three subscribed
// pipes is ONE buffer with UseCount 3; each receiver decrements on release, and the third
// decrement is what returns it to the pool. That is why CFE_SB_IncrBufUseCnt and
// CFE_SB_DecrBufUseCnt are separate from the pool calls, and why DecrBufUseCnt is the only
// caller of CFE_SB_ReturnBufferToPool in normal operation.
//
// THE TRACKING LIST IS A CIRCULAR DOUBLY-LINKED LIST WHOSE EMPTY STATE POINTS AT ITSELF. That
// one decision removes every null check from the three list operations: Add and Remove are each
// four pointer writes with no branches, and "is this node in a list" needs no flag because a
// node that is not in one is a singleton pointing at itself. CFE_SB_TrackingListRemove on a node
// that was never added is therefore harmless, which is what lets ReturnBufferToPool call it
// unconditionally.
#ifndef CFE_SB_BUF_HC
#define CFE_SB_BUF_HC
#include "cfe_sb_global.HC" // the types, the constants and CFE_SB_Global
#include "cfe_sb_util.HC"   // CFE_SB_BAD_ARGUMENT, which PutDestinationBlk returns
// The actual message content of a SB Buffer Descriptor is the offset of the content member. This
// will be auto-aligned by the compiler according to the requirements of the machine.
//
// NASA writes `offsetof(CFE_SB_BufferD_t, Content)`. HolyC has no offsetof, and the value is the
// size of everything before Content -- which check_padding.py measures against NASA's own
// compiler for this exact class, so the number below is verified rather than counted by hand.
// It is load-bearing twice: it is added to every allocation, and the memory pool's block sizes
// in cfe_platformcfg_tables.HC are chosen around it.
//
// IT WAS 48 IN THE FIRST DRAFT, which is simply wrong -- the members before Content are
// 16+2+2+4+4+4+8+8+2+6 = 56 -- and NOTHING BUT THE TRANSCRIPT COULD SEE IT. check_padding
// measures this class and agreed, because it compares the class's OFFSETS and SIZE and not a
// `#define` that happens to restate one of them; check_constants compares numbers against
// NASA's `#define`s and NASA spells this one `offsetof(...)`, which is in its
// not-compared-as-an-expression bucket. The differential oracle caught it on the first run:
// a 100-byte request allocated 148 bytes against NASA's 156. The comment above this one used to
// claim the number was "verified rather than counted by hand". It was counted by hand.
#define CFE_SB_BUFFERD_CONTENT_OFFSET 56
// --- what this file needs from elsewhere ------------------------------------------------------
// ES's memory pool. None of ES is translated; the differential oracle supplies both sides with
// the same recording stubs, which is the arrangement cfe_ta_task.HC records.
I32 CFE_ES_GetPoolBuf(U8 **BufPtr, U32 Handle, I64 Size);
I32 CFE_ES_PutPoolBuf(U32 Handle, U8 *BufPtr);
U8 *MemSet(U8 *dst, I64 dat, I64 size);
// Defined below and called from above it.
U0 CFE_SB_TrackingListReset(CFE_SB_BufferLink_t *Link);
U0 CFE_SB_ReturnBufferToPool(CFE_SB_BufferD_t *bd);
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_TrackingListReset(CFE_SB_BufferLink_t *Link)
{
  /* A singleton node/empty list points to itself */
  Link->Prev = Link;
  Link->Next = Link;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_TrackingListRemove(CFE_SB_BufferLink_t *Node)
{
  /* Remove from list */
  Node->Prev->Next = Node->Next;
  Node->Next->Prev = Node->Prev;
  /* The node is now a singleton */
  CFE_SB_TrackingListReset(Node);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_TrackingListAdd(CFE_SB_BufferLink_t *List, CFE_SB_BufferLink_t *Node)
{
  /* Connect this node to the list at "prev" position (tail) */
  Node->Prev = List->Prev;
  Node->Next = List;
  /* Connect list nodes to this node */
  Node->Prev->Next = Node;
  Node->Next->Prev = Node;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_SB_BufferD_t *CFE_SB_GetBufferFromPool(I64 MaxMsgSize)
{
  I32 stat1;
  I64 AllocSize;
  U8 *addr = NULL;
  CFE_SB_BufferD_t *bd;
  /* The allocation needs to include enough space for the descriptor object */
  AllocSize = MaxMsgSize + CFE_SB_BUFFERD_CONTENT_OFFSET;
  /* Allocate a new buffer descriptor from the SB memory pool.*/
  stat1 = CFE_ES_GetPoolBuf(&addr, CFE_SB_Global.Mem.PoolHdl, AllocSize);
  if (stat1 < 0) {
    return NULL;
  }
  /* increment the number of buffers in use and adjust the high water mark if needed */
  CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse++;
  if (CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse > CFE_SB_Global.StatTlmMsg.Payload.PeakSBBuffersInUse) {
    CFE_SB_Global.StatTlmMsg.Payload.PeakSBBuffersInUse = CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse;
  }
  /* Add the size of the actual buffer to the memory-in-use ctr and */
  /* adjust the high water mark if needed */
  CFE_SB_Global.StatTlmMsg.Payload.MemInUse += AllocSize;
  if (CFE_SB_Global.StatTlmMsg.Payload.MemInUse > CFE_SB_Global.StatTlmMsg.Payload.PeakMemInUse) {
    CFE_SB_Global.StatTlmMsg.Payload.PeakMemInUse = CFE_SB_Global.StatTlmMsg.Payload.MemInUse;
  }
  /* Initialize the buffer descriptor structure. */
  bd = addr;
  // NASA clears only the DESCRIPTOR, not the message area after it -- that is what
  // CFE_SB_BUFFERD_CONTENT_OFFSET is doing here rather than sizeof(*bd). Clearing the whole
  // allocation would be a memset of up to the largest message on every send.
  MemSet(bd, 0, CFE_SB_BUFFERD_CONTENT_OFFSET);
  bd->UseCount = 1;
  bd->AllocatedSize = AllocSize;
  CFE_SB_TrackingListReset(&bd->Link);
  return bd;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_ReturnBufferToPool(CFE_SB_BufferD_t *bd)
{
  /* Remove from any tracking list (no effect if not in a list) */
  CFE_SB_TrackingListRemove(&bd->Link);
  --CFE_SB_Global.StatTlmMsg.Payload.SBBuffersInUse;
  CFE_SB_Global.StatTlmMsg.Payload.MemInUse -= bd->AllocatedSize;
  /* finally give the buf descriptor back to the buf descriptor pool */
  CFE_ES_PutPoolBuf(CFE_SB_Global.Mem.PoolHdl, bd);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_IncrBufUseCnt(CFE_SB_BufferD_t *bd)
{
  /* range check the UseCount variable */
  // 0x7FFF, not 0xFFFF, on a uint16 field: NASA leaves the top bit alone. A buffer with 32,767
  // live references is a bug somewhere else, and the ceiling makes it stop climbing rather than
  // wrap to zero and free a buffer that is still in use.
  if (bd->UseCount < 0x7FFF) {
    ++bd->UseCount;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_DecrBufUseCnt(CFE_SB_BufferD_t *bd)
{
  /* range check the UseCount variable */
  if (bd->UseCount > 0) {
    --bd->UseCount;
    if (bd->UseCount == 0) {
      CFE_SB_ReturnBufferToPool(bd);
    }
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_SB_DestinationD_t *CFE_SB_GetDestinationBlk()
{
  I32 Stat;
  U8 *addr = NULL;
  /* Allocate a new destination descriptor from the SB memory pool.*/
  Stat = CFE_ES_GetPoolBuf(&addr, CFE_SB_Global.Mem.PoolHdl, sizeof(CFE_SB_DestinationD_t));
  if (Stat < 0) {
    return NULL;
  }
  /* Add the size of a destination descriptor to the memory-in-use ctr and */
  /* adjust the high water mark if needed */
  // NASA adds `Stat`, the POOL's answer, not the size it asked for -- the pool rounds up to a
  // block size, and the accounting follows the pool rather than the request.
  CFE_SB_Global.StatTlmMsg.Payload.MemInUse += Stat;
  if (CFE_SB_Global.StatTlmMsg.Payload.MemInUse > CFE_SB_Global.StatTlmMsg.Payload.PeakMemInUse) {
    CFE_SB_Global.StatTlmMsg.Payload.PeakMemInUse = CFE_SB_Global.StatTlmMsg.Payload.MemInUse;
  }
  return addr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_PutDestinationBlk(CFE_SB_DestinationD_t *Dest)
{
  I32 Stat;
  if (Dest == NULL) {
    return CFE_SB_BAD_ARGUMENT;
  }
  /* give the destination block back to the SB memory pool */
  Stat = CFE_ES_PutPoolBuf(CFE_SB_Global.Mem.PoolHdl, Dest);
  if (Stat > 0) {
    /* Subtract the size of the destination block from the Memory in use ctr */
    CFE_SB_Global.StatTlmMsg.Payload.MemInUse -= Stat;
  }
  return CFE_SUCCESS;
}
#endif
