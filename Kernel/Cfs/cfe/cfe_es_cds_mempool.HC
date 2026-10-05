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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_cds_mempool.c -- THE SAME ALLOCATOR,
// RUNNING ON MEMORY IT CANNOT ADDRESS.
//
// Seven functions, and the first two are the whole idea. cfe_es_generic_pool.c is a block
// allocator that never touches the memory it manages: it asks its owner to FETCH a block
// descriptor from an offset and to COMMIT one back. For a RAM pool those are a cast and an
// assignment (cfe_es_mempool.c). For the CDS they are reads and writes through the PSP, because
// the critical data store is NON-VOLATILE MEMORY THE PROCESSOR CANNOT LOAD FROM -- it survives
// a reset, and reaching it is a call, not a dereference.
//
// SO CFE_ES_CDS_PoolRetrieve AND PoolCommit ARE THE BRIDGE, and NASA's comments say exactly
// that: "This is a bridge between the generic pool implementation and the CDS cache." The cache
// is one descriptor-sized staging buffer in CFE_ES_Global.CDSVars; everything the pool does to
// the CDS goes through it.
//
// AND THE CAST IN BOTH OF THEM IS LOAD-BEARING: `(CFE_ES_CDS_Instance_t *)GenPoolRecPtr` works
// because Pool is the FIRST member of the instance, so a pointer to the pool is a pointer to
// the whole CDS state. tools/cfs/check_padding.py measures that it still is.
//
// THE SYSLOG IS WRITTEN AFTER THE UNLOCK, DELIBERATELY. CFE_ES_CDSBlockWrite builds its message
// into a local buffer, releases the CDS lock, and only then logs -- so the log write, which
// takes the shared-data lock, never happens while the CDS lock is held. One lock at a time is
// the rule the whole CDS is written to, and this is the one place it is visible as a shape.
//
// THIS FILE INCLUDES NOTHING. docs/HOLYC_STRUCT_LIMITS.md #13.
//
// REQUIRED INCLUDE ORDER, which the driver provides:
//     cfe_es_global.HC    CFE_ES_Global.CDSVars, the cache and the registry record
//     cfe_es_generic_pool.HC  the pool, its descriptor and CFE_ES_GenPoolRebuild
//     cfe_es_mempool.HC   GenPoolInitialize, GenPoolCalcMinSize, GenPoolGetBlockSize
//     cfe_es_crc.HC       CFE_ES_CalculateCRC, which is what makes a stale block detectable
//     cfe_es_api.HC       CFE_ES_CDSBlockRecordIsMatch and the locks
//     cfe_es_cds.HC       the cache accessors and CFE_ES_LocateCDSBlockRecordByID
#ifndef CFE_ES_CDS_MEMPOOL_HC
#define CFE_ES_CDS_MEMPOOL_HC
// --- cfe_error.h: the CDS's own status codes -------------------------------------------------
// One guard per name -- see the note in cfe_es_cds.HC, where a group guard keyed on
// CFE_ES_CDS_INVALID_SIZE was satisfied by cfe_es_api.HC and silently dropped the other two.
#ifndef CFE_ES_CDS_INVALID_SIZE
#define CFE_ES_CDS_INVALID_SIZE 0xC4000010(I32)
#endif
#ifndef CFE_ES_CDS_ACCESS_ERROR
#define CFE_ES_CDS_ACCESS_ERROR 0xC4000013(I32)
#endif
#ifndef CFE_ES_CDS_BLOCK_CRC_ERR
#define CFE_ES_CDS_BLOCK_CRC_ERR 0xC400001A(I32)
#endif
// --- what this file needs from elsewhere ----------------------------------------------------
// THE PSP's CDS INTERFACE IS THE HARDWARE, and it will still be a stub when every line of cFE
// is translated: the critical data store is non-volatile memory reached by a call. On a real
// spacecraft this is battery-backed RAM or an EEPROM region that survives a processor reset,
// which is the entire reason the CDS exists.
I32 CFE_PSP_WriteToCDS(U8 *PtrToDataToWrite, U32 CDSOffset, U32 NumBytes);
I32 CFE_PSP_ReadFromCDS(U8 *PtrToDataFromRead, U32 CDSOffset, U32 NumBytes);

/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Obtains a block descriptor from CDS storage.
 * This is a bridge between the generic pool implementation and the CDS cache.
 *
 *-----------------------------------------------------------------*/
// IT HANDS BACK A POINTER INTO THE CACHE, not a copy. The pool reads the descriptor through
// *BdPtr after this returns, so the cache must still hold what the fetch put there -- which is
// why the pool is single-threaded under the CDS lock and why there is only one cache.
I32 CFE_ES_CDS_PoolRetrieve(CFE_ES_GenPoolRecord_t *GenPoolRecPtr, I64 Offset,
                            CFE_ES_GenPoolBD_t **BdPtr)
{
  CFE_ES_CDS_Instance_t *CDS = GenPoolRecPtr;
  *BdPtr = &CDS->Cache.Data.Desc;
  return CFE_ES_CDS_CacheFetch(&CDS->Cache, Offset, sizeof(CFE_ES_GenPoolBD_t));
}

/*----------------------------------------------------------------
 *
 * Internal helper routine only, not part of API.
 *
 * Writes a block descriptor to CDS storage.
 * This is a bridge between the generic pool implementation and the CDS cache.
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_CDS_PoolCommit(CFE_ES_GenPoolRecord_t *GenPoolRecPtr, I64 Offset,
                          CFE_ES_GenPoolBD_t *BdPtr)
{
  CFE_ES_CDS_Instance_t *CDS = GenPoolRecPtr;
  CFE_ES_CDS_CachePreload(&CDS->Cache, BdPtr, Offset, sizeof(CFE_ES_GenPoolBD_t));
  return CFE_ES_CDS_CacheFlush(&CDS->Cache);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE BLOCK SIZES COME FROM THE CONFIG SERVICE, the same way SB's do, and the minimum is
// computed rather than assumed: NASA's reason is in the refusal message -- the pool must be able
// to hold "Pool verification, block descriptor and at least one of the smallest blocks".
//
// ALIGNMENT IS 4, not the 16 a RAM pool uses, because nothing dereferences a CDS block: the
// store is reached through CFE_PSP_ReadFromCDS and WriteToCDS, so there is no load to misalign.
I32 CFE_ES_CreateCDSPool(I64 CDSPoolSize, I64 StartOffset)
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I32 Status;
  I64 SizeCheck;
  CFE_Config_ArrayValue CDSMemPoolDefSize;
  // NASA writes `CDSMemPoolDefSize = CFE_Config_GetArrayValue(...)`. This port's version takes
  // an OUT-PARAMETER, the one deviation cfe_config.HC records in full: the C returns a 16-byte
  // class by value and this compiler has no struct-return ABI, so it REFUSES the return rather
  // than truncating it. Same shape as cfe_sb_init.HC's call.
  CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_ES_CDS_MEM_BLOCK_SIZE, &CDSMemPoolDefSize);
  SizeCheck = CFE_ES_GenPoolCalcMinSize(CDSMemPoolDefSize.NumElements,
                                        CDSMemPoolDefSize.ElementPtr, 1);
  if (CDSPoolSize < SizeCheck) {
    /* Must be able make Pool verification, block descriptor and at least one of the smallest blocks  */
    CFE_ES_SysLogWrite_Unsync("%s: Pool size(%lu) too small for one CDS Block, need >=%lu\n",
                              "CFE_ES_CreateCDSPool", CDSPoolSize, SizeCheck);
    return CFE_ES_CDS_INVALID_SIZE;
  }
  Status = CFE_ES_GenPoolInitialize(&CDS->Pool, StartOffset, /* starting offset */
                                    CDSPoolSize,             /* total size */
                                    4,                       /* alignment */
                                    CDSMemPoolDefSize.NumElements, CDSMemPoolDefSize.ElementPtr,
                                    &CFE_ES_CDS_PoolRetrieve, &CFE_ES_CDS_PoolCommit);
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// A REBUILD IS A CLEAN POOL PLUS A WALK OF WHAT IS ALREADY THERE, which is the whole point of
// a critical data store: the blocks survived the reset and the allocator has to find them
// again. NASA's comment -- "Start by creating the pool in a clean state, as it would be in a
// non-rebuild" -- then CFE_ES_GenPoolRebuild reads every descriptor out of the CDS through
// PoolRetrieve above and rebuilds the free lists from them.
I32 CFE_ES_RebuildCDSPool(I64 CDSPoolSize, I64 StartOffset)
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I32 Status;
  /*
   * Start by creating the pool in a clean state, as it would be in a non-rebuild.
   */
  Status = CFE_ES_CreateCDSPool(CDSPoolSize, StartOffset);
  if (Status != CFE_SUCCESS) {
    return Status;
  }
  /* Now walk through the CDS memory and attempt to recover existing CDS blocks */
  Status = CFE_ES_GenPoolRebuild(&CDS->Pool);
  if (Status != CFE_SUCCESS) {
    CFE_ES_SysLogWrite_Unsync("%s: Err rebuilding CDS (Stat=0x%08x)\n", "CFE_ES_RebuildCDSPool",
                              Status);
    Status = CFE_ES_CDS_ACCESS_ERROR;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// A CDS BLOCK IS A CRC AND THEN THE USER'S BYTES, and this writes both: the header through the
// cache, the data straight through the PSP. The CRC is computed over what the CALLER handed in,
// before anything is written, so a block whose write is interrupted reads back as corrupt
// rather than as plausible -- which is what CFE_ES_CDSBlockRead's comparison is for.
//
// THE SIZE IS TAKEN FROM THE DESCRIPTOR AND THEN CROSS-CHECKED AGAINST THE REGISTRY. NASA's
// comment says why both: "Getting the buffer size via this function retrieves it from the
// internal descriptor, and validates the descriptor as part of the operation. This should
// always agree with the size in the registry for this block." Two copies of one number, one in
// volatile RAM and one in the store that survived the reset -- a disagreement means the CDS is
// not what the registry thinks it is, and that is a refusal, not a repair.
//
// AND THE LOG IS WRITTEN AFTER THE UNLOCK. The message is built into a local and emitted at the
// end, so CFE_ES_WriteToSysLog -- which takes the shared-data lock -- is never called while the
// CDS lock is held.
I32 CFE_ES_CDSBlockWrite(U32 Handle, U8 *DataToWrite)
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  U8 LogMessage[CFE_ES_MAX_SYSLOG_MSG_SIZE];
  I32 Status;
  I32 PspStatus;
  I64 BlockSize;
  I64 UserDataSize;
  I64 UserDataOffset;
  CFE_ES_CDS_RegRec_t *CDSRegRecPtr;
  /* Ensure the log message is an empty string in case it is never written to */
  LogMessage[0] = 0;
  CDSRegRecPtr = CFE_ES_LocateCDSBlockRecordByID(Handle);
  /*
   * A CDS block ID must be accessed by only one thread at a time.
   * Checking the validity of the block requires access to the registry.
   */
  CFE_ES_LockCDS();
  if (CFE_ES_CDSBlockRecordIsMatch(CDSRegRecPtr, Handle)) {
    /*
     * Getting the buffer size via this function retrieves it from the
     * internal descriptor, and validates the descriptor as part of the operation.
     * This should always agree with the size in the registry for this block.
     */
    Status = CFE_ES_GenPoolGetBlockSize(&CDS->Pool, &BlockSize, CDSRegRecPtr->BlockOffset);
    if (Status != CFE_SUCCESS) {
      StrPrintN(LogMessage, CFE_ES_MAX_SYSLOG_MSG_SIZE, "Invalid Handle or Block Descriptor.\n");
    } else if (BlockSize <= sizeof(CFE_ES_CDS_BlockHeader_t) ||
               BlockSize != CDSRegRecPtr->BlockSize) {
      StrPrintN(LogMessage, CFE_ES_MAX_SYSLOG_MSG_SIZE, "Block size %lu invalid, expected %lu\n",
                BlockSize, CDSRegRecPtr->BlockSize);
      Status = CFE_ES_CDS_INVALID_SIZE;
    } else {
      UserDataSize = CDSRegRecPtr->BlockSize;
      UserDataSize -= sizeof(CFE_ES_CDS_BlockHeader_t);
      UserDataOffset = CDSRegRecPtr->BlockOffset;
      UserDataOffset += sizeof(CFE_ES_CDS_BlockHeader_t);
      CDS->Cache.Data.BlockHeader.Crc =
          CFE_ES_CalculateCRC(DataToWrite, UserDataSize, 0, CFE_MISSION_ES_DEFAULT_CRC);
      CDS->Cache.Offset = CDSRegRecPtr->BlockOffset;
      CDS->Cache.Size = sizeof(CFE_ES_CDS_BlockHeader_t);
      /* Write the new block descriptor for the data coming from the Application */
      Status = CFE_ES_CDS_CacheFlush(&CDS->Cache);
      if (Status != CFE_SUCCESS) {
        StrPrintN(LogMessage, CFE_ES_MAX_SYSLOG_MSG_SIZE,
                  "Err writing header data to CDS (Stat=0x%08x) @Offset=0x%08lx\n",
                  CDS->Cache.AccessStatus, CDSRegRecPtr->BlockOffset);
      } else {
        PspStatus = CFE_PSP_WriteToCDS(DataToWrite, UserDataOffset, UserDataSize);
        if (PspStatus != CFE_PSP_SUCCESS) {
          StrPrintN(LogMessage, CFE_ES_MAX_SYSLOG_MSG_SIZE,
                    "Err writing user data to CDS (Stat=0x%08x) @Offset=0x%08lx\n", PspStatus,
                    UserDataOffset);
          Status = CFE_ES_CDS_ACCESS_ERROR;
        }
      }
    }
  } else {
    Status = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  CFE_ES_UnlockCDS();
  /* Do the actual syslog if something went wrong */
  if (LogMessage[0] != 0) {
    CFE_ES_WriteToSysLog("%s: %s", "CFE_ES_CDSBlockWrite", LogMessage);
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE CRC IS THE ANSWER TO "DID THIS SURVIVE THE RESET", and it is the only one there is. The
// header is read through the cache, the user's bytes through the PSP, and the CRC recomputed
// over what came back: a mismatch is CFE_ES_CDS_BLOCK_CRC_ERR and the caller gets to decide
// whether to trust the data. Nothing repairs it, because nothing can.
//
// It takes the same two size checks as the write and in the same order, so a block that cannot
// be written cannot be read either -- the two functions agree about what a valid block is.
I32 CFE_ES_CDSBlockRead(U8 *DataRead, U32 Handle)
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I32 Status;
  I32 PspStatus;
  U32 CrcOfCDSData;
  I64 BlockSize;
  I64 UserDataSize;
  I64 UserDataOffset;
  CFE_ES_CDS_RegRec_t *CDSRegRecPtr;
  CDSRegRecPtr = CFE_ES_LocateCDSBlockRecordByID(Handle);
  /*
   * A CDS block ID must be accessed by only one thread at a time.
   * Checking the validity of the block requires access to the registry.
   */
  CFE_ES_LockCDS();
  if (CFE_ES_CDSBlockRecordIsMatch(CDSRegRecPtr, Handle)) {
    /*
     * Getting the buffer size via this function retrieves it from the
     * internal descriptor, and validates the descriptor as part of the operation.
     * This should always agree with the size in the registry for this block.
     */
    Status = CFE_ES_GenPoolGetBlockSize(&CDS->Pool, &BlockSize, CDSRegRecPtr->BlockOffset);
    if (Status == CFE_SUCCESS) {
      if (BlockSize <= sizeof(CFE_ES_CDS_BlockHeader_t) || BlockSize != CDSRegRecPtr->BlockSize) {
        Status = CFE_ES_CDS_INVALID_SIZE;
      } else {
        UserDataSize = CDSRegRecPtr->BlockSize;
        UserDataSize -= sizeof(CFE_ES_CDS_BlockHeader_t);
        UserDataOffset = CDSRegRecPtr->BlockOffset;
        UserDataOffset += sizeof(CFE_ES_CDS_BlockHeader_t);
        /* Read the header */
        Status = CFE_ES_CDS_CacheFetch(&CDS->Cache, CDSRegRecPtr->BlockOffset,
                                       sizeof(CFE_ES_CDS_BlockHeader_t));
        if (Status == CFE_SUCCESS) {
          /* Read the data block */
          PspStatus = CFE_PSP_ReadFromCDS(DataRead, UserDataOffset, UserDataSize);
          if (PspStatus == CFE_PSP_SUCCESS) {
            /* Compute the CRC for the data read from the CDS and determine if the data is still valid */
            CrcOfCDSData = CFE_ES_CalculateCRC(DataRead, UserDataSize, 0,
                                               CFE_MISSION_ES_DEFAULT_CRC);
            /* If the CRCs do not match, report an error */
            if (CrcOfCDSData != CDS->Cache.Data.BlockHeader.Crc) {
              Status = CFE_ES_CDS_BLOCK_CRC_ERR;
            } else {
              Status = CFE_SUCCESS;
            }
          } else {
            Status = CFE_ES_CDS_ACCESS_ERROR;
          }
        }
      }
    }
  } else {
    Status = CFE_ES_ERR_RESOURCEID_NOT_VALID;
  }
  CFE_ES_UnlockCDS();
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// What the CDS needs to be to hold a given number of blocks, asked by ES's startup before it
// trusts the store's reported size.
I64 CFE_ES_CDSReqdMinSize(U32 MaxNumBlocksToSupport)
{
  CFE_Config_ArrayValue CDSMemPoolDefSize;
  // The out-parameter deviation again; see CFE_ES_CreateCDSPool above.
  CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_ES_CDS_MEM_BLOCK_SIZE, &CDSMemPoolDefSize);
  return CFE_ES_GenPoolCalcMinSize(CDSMemPoolDefSize.NumElements, CDSMemPoolDefSize.ElementPtr,
                                   MaxNumBlocksToSupport);
}
#endif
