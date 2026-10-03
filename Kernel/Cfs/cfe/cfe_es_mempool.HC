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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_mempool.c -- THE PUBLIC MEMORY POOL.
//
// THIS IS THE FILE THE DIFFERENTIAL DRIVER HAS BEEN FAKING SINCE THE SB MODULE LANDED. Every
// CFE_ES_GetPoolBuf and CFE_ES_PutPoolBuf in the transcript went to a hand-written bump
// allocator in tests/cfs/oracle_ccsdspri.c, with a comment admitting it. With this gated, SB's
// buffer lifetime, its destination blocks and EVS's event packets all allocate from NASA's real
// pool on both sides of the comparison.
//
// WHAT IT ADDS TO cfe_es_generic_pool.c, which is where the allocation logic actually lives:
//   a RESOURCE ID, so a pool can be named by a 32-bit handle rather than a pointer;
//   a table of ten of them in CFE_ES_Global;
//   an optional MUTEX per pool;
//   an OWNER app id, so ES can reclaim a pool whose app died;
//   and the offset-to-pointer translation, because the generic layer works in offsets.
//
// THE RECORD'S FIRST MEMBER IS THE GENERIC POOL AND THAT IS LOAD-BEARING. The Retrieve/Commit
// pair below casts a CFE_ES_GenPoolRecord_t * straight back to a CFE_ES_MemPoolRecord_t *,
// which is only valid because the pool sits at offset 0. cfe_es_global.HC says so at the
// declaration; moving it would compile and then read BaseAddr out of the bucket array.
#ifndef CFE_ES_MEMPOOL_HC
#define CFE_ES_MEMPOOL_HC
#include "cfe_es_syslog.HC" // CFE_ES_WriteToSysLog, and the ES chain below it
#include "cfe_config.HC"    // CFE_Config_GetArrayValue, for the default block sizes
// --- cfe_error.h ------------------------------------------------------------------------------
#define CFE_ES_ERR_RESOURCEID_NOT_VALID   0xC4000001(I32)
#define CFE_ES_NO_RESOURCE_IDS_AVAILABLE  0xC400002B(I32)
#ifndef CFE_STATUS_EXTERNAL_RESOURCE_FAIL
#define CFE_STATUS_EXTERNAL_RESOURCE_FAIL 0xC8000005(I32)
#endif
// --- cfe_es_platform_cfg.h / cfe_es_api_typedefs.h -------------------------------------------
#define CFE_PLATFORM_ES_MEMPOOL_ALIGN_SIZE_MIN 4
#define CFE_ES_NO_MUTEX                        0
#define CFE_ES_USE_MUTEX                       1
// --- cfe_core_resourceid_basevalues.h --------------------------------------------------------
// +4, not +5: the enumerators run APPID 1, LIBID 2, COUNTID 3, POOLID 4, CDSBLOCKID 5. I wrote
// 5 from the ordering in the file and check_constants named it -- an off-by-one in a resource-id
// BASE puts every pool handle in the CDS block's space, which the pool table would then
// range-check out and report as a bad handle a long way from here.
#define CFE_RESOURCEID_ES_POOLID_BASE_OFFSET (OS_OBJECT_TYPE_USER + 4)
#define CFE_ES_POOLID_BASE CFE_RESOURCEID_MAKE_BASE(CFE_RESOURCEID_ES_POOLID_BASE_OFFSET)
// --- cfe_psp.h --------------------------------------------------------------------------------
#define CFE_PSP_MEM_ANY 3
#ifndef CFE_PSP_SUCCESS
#define CFE_PSP_SUCCESS 0
#endif
// --- what this file needs from elsewhere ------------------------------------------------------
// The PSP, which is not translated: CFE_ES_ValidateHandle asks it whether a pool's base address
// is real memory, which is the one check the pool cannot make for itself.
I32 CFE_PSP_MemValidateRange(U64 Address, I64 Size, U32 MemoryType);
I32 OS_MutSemCreate(U32 *sem_id, U8 *sem_name, U32 options);
I32 OS_MutSemDelete(U32 sem_id);
I32 OS_MutSemTake(U32 sem_id);
I32 OS_MutSemGive(U32 sem_id);
// Declared here, defined below, in the C's own order.
I32 CFE_ES_PoolCreateEx(U32 *PoolID, U8 *MemPtr, I64 Size, U16 NumBlockSizes, I64 *BlockSizes, Bool UseMutex);
I32 CFE_ES_PoolCreateEx_WithAlignment(U32 *PoolID, U8 *MemPtr, I64 Size, U16 NumBlockSizes, I64 *BlockSizes, Bool UseMutex, I64 Alignment);
CFE_ES_MemPoolRecord_t *CFE_ES_LocateMemPoolRecordByID(U32 PoolID);
// --- cfe_es_mempool.h: the record accessors, `static inline` in the C ------------------------
// HolyC has no `static` on a function and no inline; these are ordinary functions, which is how
// every other translated inline in this port is spelled. CFE_ES_MEMHANDLE_C and
// CFE_RESOURCEID_TEST_* are the identity for the SIMPLE resourceid variant.
Bool CFE_ES_MemPoolRecordIsUsed(CFE_ES_MemPoolRecord_t *PoolRecPtr)
{
  return CFE_ResourceId_IsDefined(PoolRecPtr->PoolID);
}

U32 CFE_ES_MemPoolRecordGetID(CFE_ES_MemPoolRecord_t *PoolRecPtr)
{
  return PoolRecPtr->PoolID;
}

U0 CFE_ES_MemPoolRecordSetUsed(CFE_ES_MemPoolRecord_t *PoolRecPtr, U32 PendingId)
{
  PoolRecPtr->PoolID = PendingId;
}

U0 CFE_ES_MemPoolRecordSetFree(CFE_ES_MemPoolRecord_t *PoolRecPtr)
{
  PoolRecPtr->PoolID = CFE_RESOURCEID_UNDEFINED;
}

Bool CFE_ES_MemPoolRecordIsMatch(CFE_ES_MemPoolRecord_t *PoolRecPtr, U32 PoolID)
{
  return PoolRecPtr != NULL && PoolRecPtr->PoolID == PoolID;
}
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 *-----------------------------------------------------------------*/
// THE MEMORY-MAPPED Retrieve/Commit PAIR. The generic pool reaches its storage only through
// these two, which is what lets a pool live somewhere that cannot be dereferenced. For an
// ordinary RAM pool Retrieve adds the offset to the base and Commit does nothing at all --
// NASA's whole body is `return CFE_SUCCESS;`, and that is not a stub: there is genuinely
// nothing to write back when the descriptor was edited in place.
I32 CFE_ES_MemPoolDirectRetrieve(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 Offset, CFE_ES_GenPoolBD_t **BdPtr)
{
  U64 DataAddress;
  CFE_ES_MemPoolRecord_t *MemPoolRecPtr = PoolRecPtr;
  DataAddress = MemPoolRecPtr->BaseAddr + Offset;
  *BdPtr = DataAddress;
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_MemPoolDirectCommit(CFE_ES_GenPoolRecord_t *PoolRecPtr, I64 Offset, CFE_ES_GenPoolBD_t *BdPtr)
{
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_MemPoolID_ToIndex(U32 PoolID, U32 *Idx)
{
  return CFE_ResourceId_ToIndex(PoolID, CFE_ES_POOLID_BASE, CFE_PLATFORM_ES_MAX_MEMORY_POOLS, Idx);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// NASA's comment is worth keeping whole: the pointer "should never be NULL because the ID should
// always be within the expected range, but if it ever is NULL, this should return true such
// that the caller will _not_ attempt to use the record". A slot-used predicate that fails safe
// by claiming the slot is TAKEN is the right way round -- the search moves on.
Bool CFE_ES_CheckMemPoolSlotUsed(U32 CheckId)
{
  CFE_ES_MemPoolRecord_t *MemPoolRecPtr;
  /*
   * Note - The pointer here should never be NULL because the ID should always be
   * within the expected range, but if it ever is NULL, this should return true
   * such that the caller will _not_ attempt to use the record.
   */
  MemPoolRecPtr = CFE_ES_LocateMemPoolRecordByID(CheckId);
  return MemPoolRecPtr == NULL || CFE_ES_MemPoolRecordIsUsed(MemPoolRecPtr);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_ES_MemPoolRecord_t *CFE_ES_LocateMemPoolRecordByID(U32 PoolID)
{
  CFE_ES_MemPoolRecord_t *MemPoolRecPtr;
  U32 Idx;
  if (CFE_ES_MemPoolID_ToIndex(PoolID, &Idx) == CFE_SUCCESS) {
    MemPoolRecPtr = &CFE_ES_Global.MemPoolTable[Idx];
  } else {
    MemPoolRecPtr = NULL;
  }
  return MemPoolRecPtr;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// CFE_Config_GetArrayValue RETURNS A 16-BYTE STRUCT BY VALUE in the C, and HolyC has no
// struct-return ABI for anything over 8 bytes, so the translation takes a destination pointer.
// That deviation is recorded in check_signatures.py's DEVIATIONS and in
// docs/HOLYC_STRUCT_LIMITS.md; here it is just the two call sites below.
I32 CFE_ES_PoolCreateNoSem(U32 *PoolID, U8 *MemPtr, I64 Size)
{
  CFE_Config_ArrayValue MemPoolDefSize;
  CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_ES_MEM_BLOCK_SIZE, &MemPoolDefSize);
  return CFE_ES_PoolCreateEx(PoolID, MemPtr, Size, MemPoolDefSize.NumElements, MemPoolDefSize.ElementPtr, CFE_ES_NO_MUTEX);
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_PoolCreate(U32 *PoolID, U8 *MemPtr, I64 Size)
{
  CFE_Config_ArrayValue MemPoolDefSize;
  CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_ES_MEM_BLOCK_SIZE, &MemPoolDefSize);
  return CFE_ES_PoolCreateEx(PoolID, MemPtr, Size, MemPoolDefSize.NumElements, MemPoolDefSize.ElementPtr, CFE_ES_USE_MUTEX);
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// NASA computes the alignment with an ALIGN_OF macro -- a `&((struct { char Byte; type Align; }
// *)NULL)->Align` trick, because C99 has no alignof. HolyC classes are PACKED, so translating
// the trick would yield 1. The number is spelled out instead, and it is MEASURED rather than
// reasoned about: ALIGN_OF(CFE_ES_PoolAlign_t) on the host C compiler the oracle's C half uses
// is 8, which is what that half passes and therefore what the transcript compares against.
//
// AND THE SAME UNION WOULD GIVE 16 ON A RISC-V C COMPILER, which is the asymmetry
// cfe_sb_global.HC already records for CFE_SB_MemPartition_t: CFE_ES_PoolAlign_t contains a
// `long double`, 8 bytes on arm64 Darwin and 16 on RV64. It does not matter here -- 8 satisfies
// every alignment RV64 has (pointers and doubles are 8) and the pool only needs a power of two
// that is large enough -- but the first draft of this comment claimed 8 was "the alignment the
// target needs" without checking either number, and only the test data's block sizes (all
// multiples of 16) would have hidden a mismatch.
#define CFE_ES_POOL_ALIGN_MEASURED 8
I32 CFE_ES_PoolCreateEx(U32 *PoolID, U8 *MemPtr, I64 Size, U16 NumBlockSizes, I64 *BlockSizes, Bool UseMutex)
{
  I64 Alignment = 8;
  // ALIGN_OF(CFE_ES_PoolAlign_t) -- see the note above
  return CFE_ES_PoolCreateEx_WithAlignment(PoolID, MemPtr, Size, NumBlockSizes, BlockSizes, UseMutex, Alignment);
}
/*----------------------------------------------------------------
 *
 * Internal function used to implement CFE_ES_PoolCreateEx with the added
 * parameter of Alignment
 *
 *-----------------------------------------------------------------*/
// "NO MORE INLINE RETURNS AFTER THIS POINT" IS NASA'S OWN COMMENT AND IT IS A CONTRACT. Once a
// slot has been reserved, every path must reach the bottom so the reservation is either
// completed or freed. That is why the mutex failure sets Status and falls through instead of
// returning, and why *PoolID is written on the way out whether the create worked or not.
I32 CFE_ES_PoolCreateEx_WithAlignment(U32 *PoolID, U8 *MemPtr, I64 Size, U16 NumBlockSizes, I64 *BlockSizes, Bool UseMutex, I64 Alignment)
{
  I32 OsStatus;
  I32 Status;
  U32 PendingID;
  CFE_ES_MemPoolRecord_t *PoolRecPtr;
  I64 MinimumSize;
  U8 MutexName[OS_MAX_API_NAME];
  CFE_Config_ArrayValue MemPoolDefSize;
  /* Sanity Check inputs */
  if (MemPtr == NULL || PoolID == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  /* If too many sizes are specified, return an error */
  if (NumBlockSizes > CFE_MISSION_ES_POOL_MAX_BUCKETS) {
    CFE_ES_WriteToSysLog("%s: Num Block Sizes (%d) greater than max (%d)\n", "CFE_ES_PoolCreateEx_WithAlignment", NumBlockSizes, CFE_MISSION_ES_POOL_MAX_BUCKETS);
    return CFE_ES_BAD_ARGUMENT;
  }
  /*
   * Use default block sizes if not specified
   */
  if (BlockSizes == NULL) {
    CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_ES_MEM_BLOCK_SIZE, &MemPoolDefSize);
    BlockSizes = MemPoolDefSize.ElementPtr;
    if (NumBlockSizes == 0) {
      NumBlockSizes = MemPoolDefSize.NumElements;
    }
    /* If too many sizes are specified, return an error */
    if (NumBlockSizes > MemPoolDefSize.NumElements) {
      CFE_ES_WriteToSysLog("%s: Num Block Sizes (%d) greater than max (%lu)\n", "CFE_ES_PoolCreateEx_WithAlignment", NumBlockSizes, MemPoolDefSize.NumElements);
      return CFE_ES_BAD_ARGUMENT;
    }
  }
  /*
   * Sanity check the pool size
   */
  MinimumSize = CFE_ES_GenPoolCalcMinSize(NumBlockSizes, BlockSizes, 1);
  if (Size < MinimumSize) {
    CFE_ES_WriteToSysLog("%s: Pool size(%lu) too small, need >=%lu bytes\n", "CFE_ES_PoolCreateEx_WithAlignment", Size, MinimumSize);
    return CFE_ES_BAD_ARGUMENT;
  }
  CFE_ES_LockSharedData("CFE_ES_PoolCreateEx_WithAlignment", 276);
  /* scan for a free slot */
  PendingID = CFE_ResourceId_FindNext(CFE_ES_Global.LastMemPoolId, CFE_PLATFORM_ES_MAX_MEMORY_POOLS, &CFE_ES_CheckMemPoolSlotUsed);
  PoolRecPtr = CFE_ES_LocateMemPoolRecordByID(PendingID);
  if (PoolRecPtr == NULL) {
    CFE_ES_SysLogWrite_Unsync("%s: No free MemPool slots available\n", "CFE_ES_PoolCreateEx_WithAlignment");
    Status = CFE_ES_NO_RESOURCE_IDS_AVAILABLE;
  } else {
    /* Fully clear the entry, just in case of stale data */
    MemSet(PoolRecPtr, 0, sizeof(CFE_ES_MemPoolRecord_t));
    CFE_ES_MemPoolRecordSetUsed(PoolRecPtr, CFE_RESOURCEID_RESERVED);
    CFE_ES_Global.LastMemPoolId = PendingID;
    Status = CFE_SUCCESS;
  }
  CFE_ES_UnlockSharedData("CFE_ES_PoolCreateEx_WithAlignment", 298);
  /*
   * If no open resource ID was found, return now.
   *
   * No more inline returns after this point; execution
   * must continue to the end of this function where the ID is freed
   * if not fully successful.
   */
  if (Status != CFE_SUCCESS) {
    return Status;
  }
  if (Alignment < CFE_PLATFORM_ES_MEMPOOL_ALIGN_SIZE_MIN) {
    /*
     * Note about path coverage testing - depending on the
     * system architecture and configuration this line may be
     * unreachable.  This is OK.
     */
    Alignment = CFE_PLATFORM_ES_MEMPOOL_ALIGN_SIZE_MIN;
  }
  /*
   * Most of the work is done by the generic pool implementation.
   * This subsystem works in offsets, not pointers.
   */
  Status = CFE_ES_GenPoolInitialize(&PoolRecPtr->Pool, 0, Size, Alignment, NumBlockSizes, BlockSizes, &CFE_ES_MemPoolDirectRetrieve, &CFE_ES_MemPoolDirectCommit);
  /*
   * If successful, complete the process.
   */
  if (Status == CFE_SUCCESS && UseMutex == CFE_ES_USE_MUTEX) {
    /*
    ** Construct a name for the Mutex from the address
    ** This is needed only because OS_MutSemCreate requires
    ** a unique name for each semaphore created.
    */
    StrPrintN(MutexName, OS_MAX_API_NAME, "Pool%08lX", CFE_ResourceId_ToInteger(PendingID));
    /* create a mutex to protect this memory pool */
    OsStatus = OS_MutSemCreate(&PoolRecPtr->MutexId, MutexName, 0);
    if (OsStatus != OS_SUCCESS) {
      /* log error and rewrite to CFE status code */
      CFE_ES_WriteToSysLog("%s: OSAL error %ld while creating mutex\n", "CFE_ES_PoolCreateEx_WithAlignment", OsStatus);
      Status = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    }
  }
  if (Status == CFE_SUCCESS) {
    /*
     * Store the base address.
     * This is only relevant for memory-mapped pools which is why it is done here.
     */
    PoolRecPtr->BaseAddr = MemPtr(U64);
    /*
     * Get the calling context.
     * If this is not a valid CFE context, then AppID will be undefined.
     * We can still permit the creation of the pool but automatic cleanup
     * if an exception or other event occurs will not be possible.
     */
    CFE_ES_GetAppID(&PoolRecPtr->OwnerAppID);
    /*
     * Store the actual/correct pool ID in the record.
     */
    CFE_ES_MemPoolRecordSetUsed(PoolRecPtr, PendingID);
  } else {
    /*
     * Free the entry that was reserved earlier
     */
    CFE_ES_MemPoolRecordSetFree(PoolRecPtr);
    PendingID = CFE_RESOURCEID_UNDEFINED;
  }
  /*
   * Export pool ID to caller as handle
   */
  *PoolID = PendingID;
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE MUTEX IS DELETED AFTER THE ES LOCK IS RELEASED, and NASA says why: "to avoid potential
// conflict with holding two locks". The id is snapshotted inside the lock and used outside it,
// which is the same hand-off pattern SB uses for its pipe queues.
I32 CFE_ES_PoolDelete(U32 PoolID)
{
  CFE_ES_MemPoolRecord_t *PoolRecPtr;
  U32 MutexId;
  I32 Status;
  I32 OsStatus;
  PoolRecPtr = CFE_ES_LocateMemPoolRecordByID(PoolID);
  CFE_ES_LockSharedData("CFE_ES_PoolDelete", 411);
  /* basic sanity check */
  if (CFE_ES_MemPoolRecordIsMatch(PoolRecPtr, PoolID)) {
    MutexId = PoolRecPtr->MutexId;
    /* snapshot mutex ID, will be freed later */
    CFE_ES_MemPoolRecordSetFree(PoolRecPtr);
    Status = CFE_SUCCESS;
  } else {
    MutexId = OS_OBJECT_ID_UNDEFINED;
    Status = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  CFE_ES_UnlockSharedData("CFE_ES_PoolDelete", 426);
  /* Release the mutex if it was configured.
   * This is done after releasing the ES lock, to avoid
   * potential conflict with holding two locks. */
  if (OS_ObjectIdDefined(MutexId)) {
    OsStatus = OS_MutSemDelete(MutexId);
    if (OsStatus != OS_SUCCESS) {
      /*
       * Report to syslog for informational purposes only.
       *
       * The MemPool entry has already been deleted, so this
       * function should not return an error at this point.
       */
      CFE_ES_WriteToSysLog("%s: Error %ld deleting mutex\n", "CFE_ES_PoolDelete", OsStatus);
    }
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// IT RETURNS THE SIZE, NOT CFE_SUCCESS. `return (int32)Size` on the way out, and every caller
// in cFS relies on it -- cfe_sb_buf.c adds the return value to MemInUse rather than the size it
// asked for, because a real pool rounds up to a block size. The driver's simulated pool had to
// reproduce that contract by hand; now it is NASA's own.
I32 CFE_ES_GetPoolBuf(U8 **BufPtr, U32 Handle, I64 Size)
{
  I32 Status;
  U32 AppId;
  CFE_ES_MemPoolRecord_t *PoolRecPtr;
  I64 DataOffset;
  if (BufPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  PoolRecPtr = CFE_ES_LocateMemPoolRecordByID(Handle);
  /* basic sanity check */
  if (!CFE_ES_MemPoolRecordIsMatch(PoolRecPtr, Handle)) {
    CFE_ES_GetAppID(&AppId);
    CFE_ES_WriteToSysLog("%s: Err:Bad handle(0x%08lX) AppId=%lu\n", "CFE_ES_GetPoolBuf", Handle, AppId);
    return CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  /*
   * Real work begins here.
   * If pool is mutex-protected, take the mutex now.
   */
  if (OS_ObjectIdDefined(PoolRecPtr->MutexId)) {
    OS_MutSemTake(PoolRecPtr->MutexId);
  }
  /*
   * Fundamental work is done as a generic routine.
   *
   * If successful, this gets an offset, which can then
   * be translated into a pointer to return to the caller.
   */
  Status = CFE_ES_GenPoolGetBlock(&PoolRecPtr->Pool, &DataOffset, Size);
  /*
   * Real work ends here.
   * If pool is mutex-protected, release the mutex now.
   */
  if (OS_ObjectIdDefined(PoolRecPtr->MutexId)) {
    OS_MutSemGive(PoolRecPtr->MutexId);
  }
  /* If not successful, return error now */
  if (Status != CFE_SUCCESS) {
    return Status;
  }
  /* Compute the actual buffer address. */
  *BufPtr = PoolRecPtr->BaseAddr + DataOffset;
  return Size;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// NASA'S OWN NOTE ON THE RETURN TYPE: "Historically this function returns the size of the
// buffer as an int32. This is not workable for large (64 bit) pools." Kept as written, because
// the API is what it is and changing it here would diverge from every caller.
I32 CFE_ES_GetPoolBufInfo(U32 Handle, U8 *BufPtr)
{
  I32 Status;
  CFE_ES_MemPoolRecord_t *PoolRecPtr;
  I64 DataOffset;
  I64 DataSize;
  if (BufPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  PoolRecPtr = CFE_ES_LocateMemPoolRecordByID(Handle);
  /* basic sanity check */
  if (!CFE_ES_MemPoolRecordIsMatch(PoolRecPtr, Handle)) {
    return CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  /*
   * Real work begins here.
   * If pool is mutex-protected, take the mutex now.
   */
  if (OS_ObjectIdDefined(PoolRecPtr->MutexId)) {
    OS_MutSemTake(PoolRecPtr->MutexId);
  }
  DataOffset = BufPtr(U64) - PoolRecPtr->BaseAddr;
  Status = CFE_ES_GenPoolGetBlockSize(&PoolRecPtr->Pool, &DataSize, DataOffset);
  /*
   * Real work ends here.
   * If pool is mutex-protected, release the mutex now.
   */
  if (OS_ObjectIdDefined(PoolRecPtr->MutexId)) {
    OS_MutSemGive(PoolRecPtr->MutexId);
  }
  if (Status == CFE_SUCCESS) {
    /*
     * Historically this function returns the size of the buffer
     * as an int32.  This is not workable for large (64 bit) pools.
     */
    Status = DataSize;
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE TWO ERROR BRANCHES AT THE BOTTOM SAY DIFFERENT THINGS AND BOTH MATTER. A
// POOL_BLOCK_INVALID is a block whose descriptor failed its check bits -- corruption, reported
// with the ADDRESS. A BUFFER_NOT_IN_POOL is an offset outside the pool -- the wrong handle or a
// wild pointer, reported with the OFFSET. Collapsing them into one message would lose the
// distinction a flight log is being read for.
I32 CFE_ES_PutPoolBuf(U32 Handle, U8 *BufPtr)
{
  CFE_ES_MemPoolRecord_t *PoolRecPtr;
  I64 DataSize;
  I64 DataOffset;
  I32 Status;
  if (BufPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  PoolRecPtr = CFE_ES_LocateMemPoolRecordByID(Handle);
  /* basic sanity check */
  if (!CFE_ES_MemPoolRecordIsMatch(PoolRecPtr, Handle)) {
    CFE_ES_WriteToSysLog("%s: Err:Invalid Memory Handle (0x%08lX).\n", "CFE_ES_PutPoolBuf", Handle);
    return CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  /*
   * Real work begins here.
   * If pool is mutex-protected, take the mutex now.
   */
  if (OS_ObjectIdDefined(PoolRecPtr->MutexId)) {
    OS_MutSemTake(PoolRecPtr->MutexId);
  }
  DataOffset = BufPtr(U64) - PoolRecPtr->BaseAddr;
  /*
   * Fundamental work is done as a generic routine.
   *
   * If successful, this gets an offset, which can then
   * be translated into a pointer to return to the caller.
   */
  Status = CFE_ES_GenPoolPutBlock(&PoolRecPtr->Pool, &DataSize, DataOffset);
  /*
   * Real work ends here.
   * If pool is mutex-protected, release the mutex now.
   */
  if (OS_ObjectIdDefined(PoolRecPtr->MutexId)) {
    OS_MutSemGive(PoolRecPtr->MutexId);
  }
  /*
   * If successful then modify return code to be
   * the size of the original buffer that was put (backward compatible)
   *
   * Otherwise if not successful, log the relevant detail
   */
  if (Status == CFE_SUCCESS) {
    Status = DataSize;
  } else if (Status == CFE_ES_POOL_BLOCK_INVALID) {
    CFE_ES_WriteToSysLog("%s: Err:Deallocating invalid or corrupt memory block @ 0x%08lX\n", "CFE_ES_PutPoolBuf", BufPtr);
  } else if (Status == CFE_ES_BUFFER_NOT_IN_POOL) {
    CFE_ES_WriteToSysLog("%s: Err:Bad offset(%lu) outside pool boundary\n", "CFE_ES_PutPoolBuf", DataOffset);
  }
  return Status;
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE BUCKET LOOP COUNTS DOWN AND THE GUARD IS WHY. GetBucketUsage is called with NumBuckets
// -- the id of the SMALLEST bucket -- and then NumBuckets is decremented, so the statistics
// come out largest-last. The `if (NumBuckets > 0)` keeps it from wrapping once the real buckets
// run out, and the remaining slots get the all-zero bucket GetBucketUsage falls back to. A
// packet of seventeen slots is reported whatever the pool actually has.
I32 CFE_ES_GetMemPoolStats(CFE_ES_MemPoolStats_t *BufPtr, U32 Handle)
{
  U32 AppId;
  CFE_ES_MemPoolRecord_t *PoolRecPtr;
  U16 NumBuckets;
  U16 Idx;
  if (BufPtr == NULL) {
    return CFE_ES_BAD_ARGUMENT;
  }
  PoolRecPtr = CFE_ES_LocateMemPoolRecordByID(Handle);
  /* basic sanity check */
  if (!CFE_ES_MemPoolRecordIsMatch(PoolRecPtr, Handle)) {
    CFE_ES_GetAppID(&AppId);
    CFE_ES_WriteToSysLog("%s: Err:Bad handle(0x%08lX) AppId=%lu\n", "CFE_ES_GetMemPoolStats", Handle, AppId);
    return CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  /*
   * Real work begins here.
   * If pool is mutex-protected, take the mutex now.
   */
  if (OS_ObjectIdDefined(PoolRecPtr->MutexId)) {
    OS_MutSemTake(PoolRecPtr->MutexId);
  }
  /*
   * Obtain the free and total byte count
   */
  CFE_ES_GenPoolGetUsage(&PoolRecPtr->Pool, &BufPtr->NumFreeBytes, &BufPtr->PoolSize);
  /*
   * Obtain the allocation and validation error counts
   */
  CFE_ES_GenPoolGetCounts(&PoolRecPtr->Pool, &NumBuckets, &BufPtr->NumBlocksRequested, &BufPtr->CheckErrCtr);
  for (Idx = 0; Idx < CFE_MISSION_ES_POOL_MAX_BUCKETS; ++Idx) {
    CFE_ES_GenPoolGetBucketUsage(&PoolRecPtr->Pool, NumBuckets, &BufPtr->BlockStats[Idx]);
    if (NumBuckets > 0) {
      --NumBuckets;
    }
  }
  /*
   * Real work ends here.
   * If pool is mutex-protected, release the mutex now.
   */
  if (OS_ObjectIdDefined(PoolRecPtr->MutexId)) {
    OS_MutSemGive(PoolRecPtr->MutexId);
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THREE TESTS, AND THE THIRD IS THE ONE THE POOL CANNOT DO ITSELF. A valid handle and a
// self-consistent record say nothing about whether BaseAddr points at memory that exists, so
// the PSP is asked -- and CFE_PSP_MEM_ANY is passed deliberately, because a pool may legally
// live in EEPROM as well as RAM.
Bool CFE_ES_ValidateHandle(U32 Handle)
{
  CFE_ES_MemPoolRecord_t *PoolRecPtr;
  I64 TotalSize;
  /* Test #1) Handle must be valid */
  PoolRecPtr = CFE_ES_LocateMemPoolRecordByID(Handle);
  if (!CFE_ES_MemPoolRecordIsMatch(PoolRecPtr, Handle)) {
    return FALSE;
  }
  /* Test #2) Check critical internal fields are within reason */
  if (!CFE_ES_GenPoolValidateState(&PoolRecPtr->Pool)) {
    return FALSE;
  }
  /* Test #3) Check memory address in PSP (allows both RAM and EEPROM) */
  CFE_ES_GenPoolGetUsage(&PoolRecPtr->Pool, NULL, &TotalSize);
  if (CFE_PSP_MemValidateRange(PoolRecPtr->BaseAddr, TotalSize, CFE_PSP_MEM_ANY) != CFE_PSP_SUCCESS) {
    return FALSE;
  }
  return TRUE;
}
#endif
