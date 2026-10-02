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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_generic_pool.c -- THE ALLOCATOR.
//
// This is the thing the differential driver has been FAKING since the SB module landed: every
// CFE_ES_GetPoolBuf in the transcript so far has gone to a hand-written bump allocator in
// tests/cfs/oracle_ccsdspri.c, because NASA's real pool lives here and here was not
// translated. cfe_es_mempool.c wraps this and is what SB actually calls.
//
// HOW IT WORKS, because the offsets are easy to misread. The pool is a byte range addressed by
// OFFSET, not by pointer -- deliberately, so that a pool can live somewhere that is not
// directly memory-mapped (a CDS in battery-backed RAM is the case NASA has in mind). Every
// access goes through the Retrieve and Commit function pointers, which for an ordinary
// memory-mapped pool just hand back a pointer and do nothing.
//
// Each allocation is preceded by a DESCRIPTOR: check bits, an allocated/deallocated marker
// that encodes the bucket id, the actual requested size, and a free-list link. A block is
// found by `BlockOffset - sizeof(descriptor)`, so the descriptor is BEHIND the pointer the
// caller holds -- exactly the arrangement cfe_sb_priv.c uses for its buffer descriptors, and
// the one that cost this port a dropped cast (see docs/HOLYC_STRUCT_LIMITS.md and
// tests/exec/cases/e_ptr_minus_int_scales.hc).
//
// THE BUCKET ID IS INVERTED AND THAT IS NOT A STYLE CHOICE. CFE_ES_GenPoolFindBucket returns
// `NumBuckets - Index`, so a valid bucket is NONZERO and "no bucket fits" is 0 -- which is
// what lets CFE_ES_GenPoolGetBlock test `BucketId == 0` instead of carrying a separate flag.
// Every other function undoes it with the same subtraction.
#ifndef CFE_ES_GENERIC_POOL_HC
#define CFE_ES_GENERIC_POOL_HC
#include "cfe_es_crc.HC" // the first ES file, for the shared chain rather than for the CRC
// --- cfe_error.h ------------------------------------------------------------------------------
#define CFE_ES_ERR_MEM_BLOCK_SIZE 0xC4000008(I32)
#define CFE_ES_BUFFER_NOT_IN_POOL 0xC4000025(I32)
#define CFE_ES_POOL_BLOCK_INVALID 0xC400002C(I32)
#ifndef CFE_ES_BAD_ARGUMENT
#define CFE_ES_BAD_ARGUMENT 0xC400000A(I32)
#endif
// --- cfe_es_platform_cfg.h --------------------------------------------------------------------
#define CFE_PLATFORM_ES_POOL_MAX_BUCKETS 17
// --- cfe_es_generic_pool.h: the three marker patterns ----------------------------------------
// THESE ARE NOT INTERCHANGEABLE AND THE ARITHMETIC ON THEM IS LOAD-BEARING. CheckBits is a
// fixed pattern that says "this is a descriptor at all". Allocated is a pattern PLUS the
// bucket id, so one 16-bit field carries both the state and which bucket it belongs to, and
// the state is recovered by subtracting the pattern and asking GetBucketState whether the
// result is in range. CFE_ES_GenPoolRebuild tries DEALLOCATED first and then ALLOCATED, and
// which one matches is how it tells a freed block from a live one while scanning raw memory.
#define CFE_ES_CHECK_PATTERN      0x5A5A
#define CFE_ES_MEMORY_ALLOCATED   0xAAAA
#define CFE_ES_MEMORY_DEALLOCATED 0xDDDD
class CFE_ES_GenPoolBD_t
{
  U16 CheckBits;
  // Set to a fixed bit pattern after init
  U16 Allocated;
  // Set to a bit pattern depending on allocation state
  U8 _pad0[4];
  // C aligns the two size_t that follow to 8
  I64 ActualSize;
  // size_t -- The actual requested size of the block
  I64 NextOffset;
  // size_t -- The offset of the next descriptor in the free stack
};
// NASA writes this as `sizeof(CFE_ES_GenPoolBD_t)` through a #define. HolyC has no offsetof
// problem here -- the whole struct is the unit -- so the macro is the sizeof, as NASA's is.
#define CFE_ES_GENERIC_POOL_DESCRIPTOR_SIZE sizeof(CFE_ES_GenPoolBD_t)
class CFE_ES_GenPoolBucket_t
{
  I64 BlockSize;
  // size_t
  I64 FirstOffset;
  // size_t -- Top of the "free stack" of buffers which have been returned
  U32 AllocationCount;
  // Total number of buffers of this block size that exist (initial get)
  U32 ReleaseCount;
  // Total number of buffers that have been released (put back)
  U32 RecycleCount;
  // Total number of buffers that have been recycled (get after put)
  U8 _pad0[4];
  // C's tail padding: the struct aligns to its size_t members
};
// --- cfe_es_extern_typedefs.h -----------------------------------------------------------------
class CFE_ES_BlockStats_t
{
  I64 BlockSize;
  // CFE_ES_MemOffset_t -- Number of bytes in each of these blocks
  U32 NumCreated;
  // Number of Memory Blocks of this size created
  U32 NumFree;
  // Number of Memory Blocks of this size that are free
};
// THE POOL RECORD, and the two function pointers are the whole reason this module is "generic":
// the pool does not assume its storage can be dereferenced. For a memory-mapped pool Retrieve
// returns a pointer into the partition and Commit is a no-op; for a CDS they go through the
// PSP. cfe_es_mempool.HC supplies the memory-mapped pair.
class CFE_ES_GenPoolRecord_t
{
  I64 PoolTotalSize;
  // size_t -- Total size of the pool area, in bytes
  I64 PoolMaxOffset;
  // size_t -- End offset (position) of the pool
  I64 AlignMask;
  // size_t -- Alignment mask applied to all new allocations
  I64 TailPosition;
  // size_t -- Current high watermark of the pool, end of last allocation
  I32 (*Retrieve)(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 Offset, CFE_ES_GenPoolBD_t **BdPtr);
  I32 (*Commit)(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 Offset, CFE_ES_GenPoolBD_t *BdPtr);
  U32 AllocationCount;
  // Total number of block allocations of any size
  U32 ValidationErrorCount;
  // Count of validation errors
  U16 NumBuckets;
  // Number of entries in the "Buckets" array that are valid
  U8 _pad0[6];
  // C aligns Buckets to 8
  CFE_ES_GenPoolBucket_t Buckets[CFE_PLATFORM_ES_POOL_MAX_BUCKETS];
  // Bucket States
};
// --- what this file needs from elsewhere ------------------------------------------------------
// cfe_es_syslog.c, not yet translated. Three call sites here, all of them on an argument-check
// failure during pool creation.
I32 CFE_ES_WriteToSysLog(U8 *Msg,...);
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Find the appropriate bucket given a requested block size
 *
 *-----------------------------------------------------------------*/
U16 CFE_ES_GenPoolFindBucket(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 ReqSize)
{
  U16 Index;
  for (Index = 0; Index < PoolRecPtr->NumBuckets; ++Index) {
    if (ReqSize <= PoolRecPtr->Buckets[Index].BlockSize) {
      /* it fits - stop here */
      break;
    }
  }
  /*
   * Invert output such that if a bucket wasn't found, this
   * will return 0.  A valid bucket ID will be nonzero.
   */
  return PoolRecPtr->NumBuckets - Index;
}
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Obtain a pointer to the state structure associated with a given bucket ID
 *
 *-----------------------------------------------------------------*/
CFE_ES_GenPoolBucket_t *CFE_ES_GenPoolGetBucketState(CFE_ES_GenPoolRecord_t *PoolRecPtr, U16 BucketId)
{
  U16 Index;
  Index = PoolRecPtr->NumBuckets - BucketId;
  if (Index >= PoolRecPtr->NumBuckets) {
    return NULL;
  }
  return &PoolRecPtr->Buckets[Index];
}
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Find and re-allocate a previously returned block
 *
 *-----------------------------------------------------------------*/
// THE THREE-WAY GUARD AT THE TOP IS WHAT MAKES THE FREE STACK SAFE. RecycleCount ==
// ReleaseCount means everything freed has already been handed back out; FirstOffset == 0 means
// the stack is empty. Either alone would be a weaker test, and the pair of counters is also
// what CFE_ES_GenPoolGetBucketUsage reports as NumFree.
I32 CFE_ES_GenPoolRecyclePoolBlock(CFE_ES_GenPoolRecord_t *PoolRecPtr, U16 BucketId, I64 NewSize, I64 *BlockOffsetPtr)
{
  CFE_ES_GenPoolBucket_t *BucketPtr;
  I64 DescOffset;
  I64 BlockOffset;
  I64 NextOffset;
  CFE_ES_GenPoolBD_t *BdPtr;
  U16 RecycleBucketId;
  I32 Status;
  BucketPtr = CFE_ES_GenPoolGetBucketState(PoolRecPtr, BucketId);
  if (BucketPtr == NULL || BucketPtr->RecycleCount == BucketPtr->ReleaseCount || BucketPtr->FirstOffset == 0) {
    /* no buffers in pool to recycle */
    return CFE_ES_BUFFER_NOT_IN_POOL;
  }
  BlockOffset = BucketPtr->FirstOffset;
  DescOffset = BlockOffset - CFE_ES_GENERIC_POOL_DESCRIPTOR_SIZE;
  Status = PoolRecPtr->Retrieve(PoolRecPtr, DescOffset, &BdPtr);
  if (Status == CFE_SUCCESS) {
    RecycleBucketId = BdPtr->Allocated - CFE_ES_MEMORY_DEALLOCATED;
    if (BdPtr->CheckBits != CFE_ES_CHECK_PATTERN || RecycleBucketId != BucketId) {
      /* sanity check failed - possible pool corruption? */
      Status = CFE_ES_BUFFER_NOT_IN_POOL;
    } else {
      /*
       * Get it off the top on the list
       */
      NextOffset = BdPtr->NextOffset;
      BdPtr->Allocated = CFE_ES_MEMORY_ALLOCATED + BucketId;
      /* Flag memory block as allocated */
      BdPtr->ActualSize = NewSize;
      BdPtr->NextOffset = 0;
      Status = PoolRecPtr->Commit(PoolRecPtr, DescOffset, BdPtr);
      if (Status == CFE_SUCCESS) {
        *BlockOffsetPtr = BlockOffset;
        BucketPtr->FirstOffset = NextOffset;
        ++BucketPtr->RecycleCount;
      }
    }
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Create a new block of the given size
 *
 *-----------------------------------------------------------------*/
// NOTHING IS COMMITTED UNTIL THE SIZE CHECK PASSES. The offsets are all pre-calculated, the
// pool-end test comes next, and only then does the descriptor get written -- so a request that
// does not fit leaves TailPosition exactly where it was. That ordering is why a failed
// allocation cannot fragment the pool.
I32 CFE_ES_GenPoolCreatePoolBlock(CFE_ES_GenPoolRecord_t *PoolRecPtr, U16 BucketId, I64 NewSize, I64 *BlockOffsetPtr)
{
  CFE_ES_GenPoolBucket_t *BucketPtr;
  I64 DescOffset;
  I64 BlockOffset;
  I64 NextTailPosition;
  CFE_ES_GenPoolBD_t *BdPtr;
  I32 Status;
  BucketPtr = CFE_ES_GenPoolGetBucketState(PoolRecPtr, BucketId);
  if (BucketPtr == NULL) {
    /* no buffers in pool to create */
    return CFE_ES_BUFFER_NOT_IN_POOL;
  }
  /*
   * Determine the offsets of the new user block,
   * which must be aligned according to the AlignMask member.
   *
   * Note - just pre-calculating offsets here, nothing is committed yet.
   */
  BlockOffset = PoolRecPtr->TailPosition + CFE_ES_GENERIC_POOL_DESCRIPTOR_SIZE;
  BlockOffset += PoolRecPtr->AlignMask;
  BlockOffset &= ~PoolRecPtr->AlignMask;
  DescOffset = BlockOffset - CFE_ES_GENERIC_POOL_DESCRIPTOR_SIZE;
  NextTailPosition = BlockOffset + BucketPtr->BlockSize;
  /*
   * Check if there is enough space remaining in the pool -- the
   * proposed start address plus the block size must not exceed the pool end.
   */
  if (NextTailPosition > PoolRecPtr->PoolMaxOffset) {
    /* can't fit in remaining mem */
    return CFE_ES_ERR_MEM_BLOCK_SIZE;
  }
  /*
   * Now commit the new block
   */
  Status = PoolRecPtr->Retrieve(PoolRecPtr, DescOffset, &BdPtr);
  if (Status == CFE_SUCCESS) {
    BdPtr->CheckBits = CFE_ES_CHECK_PATTERN;
    BdPtr->Allocated = CFE_ES_MEMORY_ALLOCATED + BucketId;
    /* Flag memory block as allocated */
    BdPtr->ActualSize = NewSize;
    BdPtr->NextOffset = 0;
    Status = PoolRecPtr->Commit(PoolRecPtr, DescOffset, BdPtr);
    if (Status == CFE_SUCCESS) {
      /*
      ** adjust pool current pointer and other record keeping
      */
      PoolRecPtr->TailPosition = NextTailPosition;
      ++BucketPtr->AllocationCount;
      ++PoolRecPtr->AllocationCount;
      *BlockOffsetPtr = BlockOffset;
    }
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE XOR SWAP IS NASA'S AND IT STAYS. The bubble sort that orders the block sizes exchanges
// two size_t with three XORs rather than a temporary -- a 1980s idiom, and translating it as a
// three-line temporary swap would be a readability edit, not a translation. It also happens to
// be the shape that exposed a HolyC codegen quirk once before: `a ^= b` on a U64 compiles to
// different code from `a = a ^ b` (docs/HOLYC_STRUCT_LIMITS.md #11 is the sibling case for
// division), so the compound form is kept exactly as written and the sort's result is in the
// transcript.
//
// AND THE SORT IS WHY THE BUCKET ID IS INVERTED. After sorting ascending, Buckets[0] is the
// SMALLEST; FindBucket walks up and stops at the first that fits, and inverting the index means
// the largest bucket gets id 1 and "none fit" gets 0.
I32 CFE_ES_GenPoolInitialize(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 StartOffset, I64 PoolSize, I64 AlignSize, U16 NumBlockSizes, I64 *BlockSizeList, I32 (*RetrieveFunc)(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 Offset, CFE_ES_GenPoolBD_t **BdPtr), I32 (*CommitFunc)(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 Offset, CFE_ES_GenPoolBD_t *BdPtr))
{
  I64 AlignMask;
  // cpuaddr
  U32 i;
  U32 j;
  CFE_ES_GenPoolBucket_t *BucketPtr;
  if (NumBlockSizes == 0) {
    CFE_ES_WriteToSysLog("%s: cannot create pool with 0 block sizes\n", "CFE_ES_GenPoolInitialize");
    return CFE_ES_BAD_ARGUMENT;
  }
  /*
   * Note - being an internal/non-public API this does not need to
   * check the directly-supplied arguments, it is assumed they are already
   * sanity checked.
   */
  MemSet(PoolRecPtr, 0, sizeof(CFE_ES_GenPoolRecord_t));
  /*
   * Convert alignment to a bit mask.
   */
  if (AlignSize <= 1) {
    AlignMask = 0;
  } else {
    AlignMask = AlignSize - 1;
  }
  /*
   * This confirms that the passed in value is a power of 2.
   * The result of this check should always be 0 if so.
   */
  if ((AlignMask & AlignSize) != 0) {
    CFE_ES_WriteToSysLog("%s: invalid alignment for pool: %lu\n", "CFE_ES_GenPoolInitialize", AlignSize);
    return CFE_ES_BAD_ARGUMENT;
  }
  /* complete initialization of pool record entry */
  PoolRecPtr->AlignMask = AlignMask;
  PoolRecPtr->PoolTotalSize = PoolSize;
  PoolRecPtr->PoolMaxOffset = PoolSize + StartOffset;
  PoolRecPtr->NumBuckets = NumBlockSizes;
  PoolRecPtr->Retrieve = RetrieveFunc;
  PoolRecPtr->Commit = CommitFunc;
  PoolRecPtr->TailPosition = StartOffset;
  /* initially copy all block sizes */
  BucketPtr = PoolRecPtr->Buckets;
  for (i = 0; i < NumBlockSizes; ++i) {
    BucketPtr->BlockSize = BlockSizeList[i];
    ++BucketPtr;
  }
  /* Sort by block size - a simple bubble sort -
   * this does not run often and the list is relatively small. */
  do {
    j = 0;
    BucketPtr = PoolRecPtr->Buckets;
    for (i = 1; i < NumBlockSizes; ++i) {
      if (BucketPtr[0].BlockSize > BucketPtr[1].BlockSize) {
        /* swap */
        BucketPtr[0].BlockSize ^= BucketPtr[1].BlockSize;
        BucketPtr[1].BlockSize ^= BucketPtr[0].BlockSize;
        BucketPtr[0].BlockSize ^= BucketPtr[1].BlockSize;
        ++j;
      }
      ++BucketPtr;
    }
  } while (j > 0);
  /*
   * Additional sanity check - after sorting the list,
   * confirm that the smallest block size (first entry)
   * is not zero.
   */
  if (PoolRecPtr->Buckets[0].BlockSize == 0) {
    return CFE_ES_ERR_MEM_BLOCK_SIZE;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I64 CFE_ES_GenPoolCalcMinSize(U16 NumBlockSizes, I64 *BlockSizeList, U32 NumBlocks)
{
  U16 BucketId;
  I64 MinBlockSize;
  MinBlockSize = 0;
  if (NumBlockSizes > 0) {
    MinBlockSize = BlockSizeList[0];
    for (BucketId = 1; BucketId < NumBlockSizes; ++BucketId) {
      if (BlockSizeList[BucketId] < MinBlockSize) {
        MinBlockSize = BlockSizeList[BucketId];
      }
    }
  }
  MinBlockSize += sizeof(CFE_ES_GenPoolBD_t);
  return NumBlocks *MinBlockSize;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// RECYCLE FIRST, THEN CREATE, and the order matters for more than speed: a pool that always
// created would run out while holding a free stack full of blocks the right size. The failure
// return from Recycle is not an error here -- it is the "nothing to reuse" signal.
I32 CFE_ES_GenPoolGetBlock(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 *BlockOffsetPtr, I64 ReqSize)
{
  I32 Status;
  U16 BucketId;
  /* Find the bucket which can accommodate the requested size. */
  BucketId = CFE_ES_GenPoolFindBucket(PoolRecPtr, ReqSize);
  if (BucketId == 0) {
    CFE_ES_WriteToSysLog("%s: Err:size(%lu) > max(%lu)\n", "CFE_ES_GenPoolGetBlock", ReqSize, PoolRecPtr->Buckets[PoolRecPtr->NumBuckets - 1].BlockSize);
    return CFE_ES_ERR_MEM_BLOCK_SIZE;
  }
  /* first attempt to recycle any buffers from the same bucket that were freed */
  Status = CFE_ES_GenPoolRecyclePoolBlock(PoolRecPtr, BucketId, ReqSize, BlockOffsetPtr);
  if (Status != CFE_SUCCESS) {
    /* recycling not available - try making a new one instead */
    Status = CFE_ES_GenPoolCreatePoolBlock(PoolRecPtr, BucketId, ReqSize, BlockOffsetPtr);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE FOUR-PART VALIDITY TEST IS THE SAME IN BOTH GetBlockSize AND PutBlock, and only PutBlock
// counts a failure: a size query on a bad pointer is the caller's problem, a FREE of one is
// pool corruption and shows up in ValidationErrorCount and then in housekeeping telemetry.
I32 CFE_ES_GenPoolGetBlockSize(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 *BlockSizePtr, I64 BlockOffset)
{
  I64 DescOffset;
  CFE_ES_GenPoolBucket_t *BucketPtr;
  CFE_ES_GenPoolBD_t *BdPtr;
  I32 Status;
  U16 BucketId;
  if (BlockOffset >= PoolRecPtr->TailPosition || BlockOffset < CFE_ES_GENERIC_POOL_DESCRIPTOR_SIZE) {
    /* outside the bounds of the pool */
    return CFE_ES_BUFFER_NOT_IN_POOL;
  }
  DescOffset = BlockOffset - CFE_ES_GENERIC_POOL_DESCRIPTOR_SIZE;
  Status = PoolRecPtr->Retrieve(PoolRecPtr, DescOffset, &BdPtr);
  if (Status == CFE_SUCCESS) {
    BucketId = BdPtr->Allocated - CFE_ES_MEMORY_ALLOCATED;
    BucketPtr = CFE_ES_GenPoolGetBucketState(PoolRecPtr, BucketId);
    if (BdPtr->CheckBits != CFE_ES_CHECK_PATTERN || BucketPtr == NULL || BdPtr->ActualSize == 0 || BucketPtr->BlockSize < BdPtr->ActualSize) {
      /* This does not appear to be a valid data buffer */
      Status = CFE_ES_POOL_BLOCK_INVALID;
    } else {
      *BlockSizePtr = BdPtr->ActualSize;
    }
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_GenPoolPutBlock(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 *BlockSizePtr, I64 BlockOffset)
{
  I64 DescOffset;
  CFE_ES_GenPoolBucket_t *BucketPtr;
  CFE_ES_GenPoolBD_t *BdPtr;
  I32 Status;
  U16 BucketId;
  if (BlockOffset >= PoolRecPtr->TailPosition || BlockOffset < CFE_ES_GENERIC_POOL_DESCRIPTOR_SIZE) {
    /* outside the bounds of the pool */
    return CFE_ES_BUFFER_NOT_IN_POOL;
  }
  DescOffset = BlockOffset - CFE_ES_GENERIC_POOL_DESCRIPTOR_SIZE;
  Status = PoolRecPtr->Retrieve(PoolRecPtr, DescOffset, &BdPtr);
  if (Status == CFE_SUCCESS) {
    BucketId = BdPtr->Allocated - CFE_ES_MEMORY_ALLOCATED;
    BucketPtr = CFE_ES_GenPoolGetBucketState(PoolRecPtr, BucketId);
    if (BdPtr->CheckBits != CFE_ES_CHECK_PATTERN || BucketPtr == NULL || BdPtr->ActualSize == 0 || BucketPtr->BlockSize < BdPtr->ActualSize) {
      /* This does not appear to be a valid data buffer */
      ++PoolRecPtr->ValidationErrorCount;
      Status = CFE_ES_POOL_BLOCK_INVALID;
    } else {
      BdPtr->Allocated = CFE_ES_MEMORY_DEALLOCATED + BucketId;
      BdPtr->NextOffset = BucketPtr->FirstOffset;
      *BlockSizePtr = BdPtr->ActualSize;
      Status = PoolRecPtr->Commit(PoolRecPtr, DescOffset, BdPtr);
      if (Status == CFE_SUCCESS) {
        BucketPtr->FirstOffset = BlockOffset;
        ++BucketPtr->ReleaseCount;
      }
    }
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// REBUILD IS FOR A POOL THAT SURVIVED THE REBOOT, which is what a Critical Data Store is. The
// pool record itself is gone -- it lived in RAM -- but the DESCRIPTORS are still in the
// storage, so this walks them from the start, re-deriving TailPosition, the allocation counts
// and the free stacks from the check patterns alone.
//
// IT STOPS AT THE FIRST THING IT CANNOT READ, and that is correct rather than lenient: a
// descriptor whose CheckBits are wrong means the scan has reached memory that was never part
// of this pool, so everything past it is unknown. A rebuild that skipped bad blocks and
// carried on would hand out a free list containing addresses it had invented.
I32 CFE_ES_GenPoolRebuild(CFE_ES_GenPoolRecord_t *PoolRecPtr)
{
  I32 Status;
  I64 DescOffset;
  I64 BlockOffset;
  CFE_ES_GenPoolBucket_t *BucketPtr;
  CFE_ES_GenPoolBD_t *BdPtr;
  U16 BucketId;
  Bool IsDeallocatedBlock;
  Status = CFE_SUCCESS;
  /* Scan the pool to find blocks that were created and freed */
  while (TRUE) {
    IsDeallocatedBlock = FALSE;
    BucketId = 0;
    BucketPtr = NULL;
    /*
     * Determine the offsets of the next user block,
     * which must be aligned according to the AlignMask member.
     */
    BlockOffset = PoolRecPtr->TailPosition + CFE_ES_GENERIC_POOL_DESCRIPTOR_SIZE;
    BlockOffset += PoolRecPtr->AlignMask;
    BlockOffset &= ~PoolRecPtr->AlignMask;
    if (BlockOffset > PoolRecPtr->PoolMaxOffset) {
      /* End of pool reached, stop now */
      break;
    }
    DescOffset = BlockOffset - CFE_ES_GENERIC_POOL_DESCRIPTOR_SIZE;
    Status = PoolRecPtr->Retrieve(PoolRecPtr, DescOffset, &BdPtr);
    if (Status != CFE_SUCCESS) {
      /* Failed to read descriptor */
      break;
    }
    /*
     * If the CheckBits indicate the block was in use,
     * then do further inspection to find the block size
     * and allocated/deallocated status.
     */
    if (BdPtr->CheckBits == CFE_ES_CHECK_PATTERN) {
      /* Test if block is deallocated */
      BucketId = BdPtr->Allocated - CFE_ES_MEMORY_DEALLOCATED;
      BucketPtr = CFE_ES_GenPoolGetBucketState(PoolRecPtr, BucketId);
      if (BucketPtr != NULL) {
        IsDeallocatedBlock = TRUE;
      } else {
        /*
         * Test if block is allocated.
         * In this case there is nothing more to do, just
         * get the size and skip the block.
         */
        BucketId = BdPtr->Allocated - CFE_ES_MEMORY_ALLOCATED;
        BucketPtr = CFE_ES_GenPoolGetBucketState(PoolRecPtr, BucketId);
      }
    }
    /*
     * Sanity check that the actual size is less than the bucket size -
     * it always should be, as long as the pool was created with the same
     * set of bucket sizes.
     */
    if (BucketPtr == NULL || BucketPtr->BlockSize < BdPtr->ActualSize) {
      /* Not a valid block signature - stop recovery now */
      break;
    }
    PoolRecPtr->TailPosition = BlockOffset + BucketPtr->BlockSize;
    BucketPtr = CFE_ES_GenPoolGetBucketState(PoolRecPtr, BucketId);
    ++BucketPtr->AllocationCount;
    ++PoolRecPtr->AllocationCount;
    /*
     * If it was a deallocated block, then add it to the local
     * pool linked list structure and rewrite the descriptor.
     */
    if (IsDeallocatedBlock) {
      ++BucketPtr->ReleaseCount;
      BdPtr->NextOffset = BucketPtr->FirstOffset;
      BucketPtr->FirstOffset = BlockOffset;
      Status = PoolRecPtr->Commit(PoolRecPtr, DescOffset, BdPtr);
      if (Status != CFE_SUCCESS) {
        break;
      }
    }
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_ES_GenPoolValidateState(CFE_ES_GenPoolRecord_t *PoolRecPtr)
{
  return PoolRecPtr->PoolTotalSize > 0 && PoolRecPtr->TailPosition <= PoolRecPtr->PoolMaxOffset && PoolRecPtr->NumBuckets > 0 && PoolRecPtr->NumBuckets <= CFE_PLATFORM_ES_POOL_MAX_BUCKETS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_ES_GenPoolGetUsage(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 *FreeSizeBuf, I64 *TotalSizeBuf)
{
  if (TotalSizeBuf != NULL) {
    *TotalSizeBuf = PoolRecPtr->PoolTotalSize;
    // CFE_ES_MEMOFFSET_C, a cast to U64
  }
  if (FreeSizeBuf != NULL) {
    *FreeSizeBuf = PoolRecPtr->PoolMaxOffset - PoolRecPtr->TailPosition;
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_ES_GenPoolGetCounts(CFE_ES_GenPoolRecord_t *PoolRecPtr, U16 *NumBucketsBuf, U32 *AllocCountBuf, U32 *ValidationErrorCountBuf)
{
  if (NumBucketsBuf != NULL) {
    *NumBucketsBuf = PoolRecPtr->NumBuckets;
  }
  if (AllocCountBuf != NULL) {
    *AllocCountBuf = PoolRecPtr->AllocationCount;
  }
  if (ValidationErrorCountBuf != NULL) {
    *ValidationErrorCountBuf = PoolRecPtr->ValidationErrorCount;
  }
}
// The all-zero bucket CFE_ES_GenPoolGetBucketUsage falls back to. NASA declares it
// `static const ... ZeroBucket = {0}` inside the function; a static local is a file-scope
// global in HolyC, and HolyC zeroes globals, so no initialiser is needed or written.
CFE_ES_GenPoolBucket_t CFE_ES_GenPoolGetBucketUsage_ZeroBucket;
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// NumFree IS A DIFFERENCE, NOT A COUNTER. ReleaseCount - RecycleCount is how many blocks were
// freed and have not yet been handed back out -- the depth of the free stack. There is no
// field holding it, which is why a pool's free count cannot be corrupted independently of the
// two counters that produce it.
U0 CFE_ES_GenPoolGetBucketUsage(CFE_ES_GenPoolRecord_t *PoolRecPtr, U16 BucketId, CFE_ES_BlockStats_t *BlockStatsBuf)
{
  CFE_ES_GenPoolBucket_t *BucketPtr;
  BucketPtr = CFE_ES_GenPoolGetBucketState(PoolRecPtr, BucketId);
  if (BucketPtr == NULL) {
    /* bucket ID is not valid */
    BucketPtr = &CFE_ES_GenPoolGetBucketUsage_ZeroBucket;
  }
  if (BlockStatsBuf != NULL) {
    BlockStatsBuf->NumCreated = BucketPtr->AllocationCount;
    BlockStatsBuf->BlockSize = BucketPtr->BlockSize;
    BlockStatsBuf->NumFree = BucketPtr->ReleaseCount - BucketPtr->RecycleCount;
  }
}
#endif
