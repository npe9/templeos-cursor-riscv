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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_cds.c -- THE CRITICAL DATA STORE: the
// one piece of memory on a spacecraft that is expected to still be there after the processor
// resets.
//
// Twenty-four functions. What makes the whole file the shape it is: THE CDS IS NOT MEMORY
// MAPPED. NASA says so where the cache is declared -- "Because CDS memory is not memory mapped,
// this serves as temporary holding location for data being actively accessed." Every byte in or
// out is a CFE_PSP_ReadFromCDS or CFE_PSP_WriteToCDS call, so there is no pointer into the
// store, no struct overlaid on it, and a one-entry RAM cache that everything funnels through.
//
// THE PERSISTENT LAYOUT IS AN OFFSET MAP, not a structure, and NASA is explicit that the
// structures describing it are never instantiated: "NOTE: these aren't necessarily instantiated
// in RAM, just in CDS. Mainly interested in the size of these elements, and offset of the
// various members within." So this translation carries the OFFSETS as constants -- see the
// CDS_* block below -- where the C computes them with offsetof over a macro-built struct.
//
// A SIGNATURE AT EACH END IS HOW A VALID CDS IS RECOGNISED. "_CDSBeg_" at offset 0 and
// "_CDSEnd_" in the last eight bytes; both present means the store is one this build wrote, and
// the registry can be read back and the allocator rebuilt from the descriptors already in it.
// Either missing means CFE_ES_CDS_INVALID, which is not a failure -- it is the signal to wipe
// the store and start a new one.
//
// AND EVERY BLOCK CARRIES ITS OWN CRC, because surviving a reset is not the same as surviving
// it intact. cfe_es_cds_mempool.c checks it on every read.
//
// ONE LOCK AT A TIME, which this file is written around. The CDS has its own mutex, separate
// from ES's shared-data lock, and the two are never held together: the registration path takes
// the CDS lock, does all its work through pointers into the registry, releases it, and only
// then sends events -- NASA's comment on the helper that does so is "This should be called with
// the CDS _unlocked_ because it makes calls into other subsystems." CFE_ES_DeleteCDS builds its
// log message into a local for the same reason.
//
// THIS FILE INCLUDES NOTHING. docs/HOLYC_STRUCT_LIMITS.md #13.
//
// REQUIRED INCLUDE ORDER, which the driver provides:
//     cfe_es_global.HC    CFE_ES_Global.CDSVars, the cache union and the registry record
//     cfe_es_resource.HC  CFE_RESOURCEID_MAKE_BASE and the id bases
//     cfe_es_generic_pool.HC / cfe_es_mempool.HC   the pool this file creates and rebuilds
//     cfe_es_api.HC       the CDS record accessors and CFE_ES_GetAppName
//     cfe_es_cds_mempool.HC  CreateCDSPool, RebuildCDSPool, CDSReqdMinSize
#ifndef CFE_ES_CDS_HC
#define CFE_ES_CDS_HC
// --- cfe_es_cds.h ---------------------------------------------------------------------------
#define CFE_ES_CDS_SIGNATURE_BEGIN "_CDSBeg_"
#define CFE_ES_CDS_SIGNATURE_END   "_CDSEnd_"
#define CFE_ES_CDS_MUT_REG_NAME    "CDS_MUTEX"
#define CFE_ES_CDS_MUT_REG_VALUE   0
// `((size_t)(1 << 30) - sizeof(CFE_ES_CDS_BlockHeader_t))` -- a gigabyte less the four-byte
// block header. Not a platform limit; a sanity bound, so a caller's bad size is refused before
// it reaches the allocator.
#define CDS_ABS_MAX_BLOCK_SIZE (1073741824 - 4)
// THE PERSISTENT OFFSET MAP. NASA computes these with offsetof and sizeof over
// CFE_ES_CDS_PersistentHeader_t, a struct built from a CDS_RESERVE_SPACE macro that rounds every
// member up to a whole number of 32-bit words -- and never instantiates it. The arithmetic,
// which tools/cfs/check_constants.py compares against NASA's own expressions:
//
//     SignatureBegin   8 bytes at 0
//     RegistrySize     4 bytes at 8
//     RegistryContent  512 * sizeof(CFE_ES_CDS_RegRec_t) = 512 * 72 = 36864 bytes at 12
//     -> CDS_POOL_OFFSET      = 12 + 36864      = 36876
//     -> CDS_RESERVED_MIN_SIZE = 36876 + 8      = 36884   (header + 8-byte trailer)
//
// The 512 is CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES and the 72 is the registry record's measured
// size, which tools/cfs/check_padding.py holds to NASA's byte for byte. If either moves these
// numbers are wrong, and the gate that would say so is the padding one, not this file.
#define CDS_SIG_BEGIN_OFFSET  0
#define CDS_REG_SIZE_OFFSET   8
#define CDS_REG_OFFSET        12
#define CDS_POOL_OFFSET       36876
#define CDS_RESERVED_MIN_SIZE 36884
// `sizeof(CFE_ES_CDS_PersistentTrailer_t)` -- the end signature, rounded to a word boundary.
#define CDS_PERSISTENT_TRAILER_SIZE 8
// --- cfe_error.h ----------------------------------------------------------------------------
// EACH NAME GETS ITS OWN GUARD, and that is not style. A single `#ifndef` around the group,
// keyed on the first name, is all-or-nothing: cfe_es_api.HC already defines
// CFE_ES_CDS_INVALID_SIZE, so the group guard was satisfied and CFE_ES_CDS_ACCESS_ERROR and
// CFE_ES_CDS_BLOCK_CRC_ERR were never defined at all. The compiler said so -- four undefined
// variables -- but a group guard whose first member happens to be absent would have defined the
// rest and hidden the next collision.
#ifndef CFE_ES_CDS_INVALID_SIZE
#define CFE_ES_CDS_INVALID_SIZE 0xC4000010(I32)
#endif
#ifndef CFE_ES_CDS_ACCESS_ERROR
#define CFE_ES_CDS_ACCESS_ERROR 0xC4000013(I32)
#endif
#ifndef CFE_ES_CDS_BLOCK_CRC_ERR
#define CFE_ES_CDS_BLOCK_CRC_ERR 0xC400001A(I32)
#endif
#ifndef CFE_ES_CDS_INVALID
#define CFE_ES_CDS_INVALID 0xC4000012(I32)
#endif
#ifndef CFE_ES_CDS_WRONG_TYPE_ERR
#define CFE_ES_CDS_WRONG_TYPE_ERR 0xC4000020(I32)
#endif
#ifndef CFE_ES_CDS_OWNER_ACTIVE_ERR
#define CFE_ES_CDS_OWNER_ACTIVE_ERR 0xC4000022(I32)
#endif
#ifndef CFE_ES_CDS_ALREADY_EXISTS
// NOT AN ERROR -- the high bit is clear. NASA returns it "for backward compatibility" when an
// app re-registers a CDS it already owns at the same size, so an app that restarts and asks for
// its store back is told "you already have it" rather than "here is a new one".
#define CFE_ES_CDS_ALREADY_EXISTS 0x4400000D(I32)
#endif
#ifndef CFE_ES_ERR_NAME_NOT_FOUND
#define CFE_ES_ERR_NAME_NOT_FOUND 0xC4000002(I32)
#endif
// --- cfe_core_resourceid_basevalues.h -------------------------------------------------------
#ifndef CFE_RESOURCEID_ES_CDSBLOCKID_BASE_OFFSET
#define CFE_RESOURCEID_ES_CDSBLOCKID_BASE_OFFSET (OS_OBJECT_TYPE_USER + 5)
#endif
#ifndef CFE_ES_CDSBLOCKID_BASE
#define CFE_ES_CDSBLOCKID_BASE \
  CFE_RESOURCEID_MAKE_BASE(CFE_RESOURCEID_ES_CDSBLOCKID_BASE_OFFSET)
#endif
// --- what this file needs from elsewhere ----------------------------------------------------
// The PSP's CDS interface -- the non-volatile store itself, and the one part of this file that
// is hardware. cfe_es_cds_mempool.HC declares the same two.
I32 CFE_PSP_GetCDSSize(U32 *SizeOfCDS);
I32 CFE_PSP_WriteToCDS(U8 *PtrToDataToWrite, U32 CDSOffset, U32 NumBytes);
I32 CFE_PSP_ReadFromCDS(U8 *PtrToDataFromRead, U32 CDSOffset, U32 NumBytes);
// THE TWO CDS FILES ARE MUTUALLY DEPENDENT, which is NASA's arrangement and not a choice here:
// this file creates and rebuilds the pool that cfe_es_cds_mempool.c manages, and that file
// reaches every byte of the store through this file's cache. So one of them has to be included
// first and declare the other's three entry points. This one is first.
I32 CFE_ES_CreateCDSPool(I64 CDSPoolSize, I64 StartOffset);
I32 CFE_ES_RebuildCDSPool(I64 CDSPoolSize, I64 StartOffset);
I64 CFE_ES_CDSReqdMinSize(U32 MaxNumBlocksToSupport);
// And this file's own, because CFE_ES_CDS_EarlyInit is defined first and calls most of them.
I32 CFE_ES_ValidateCDS();
I32 CFE_ES_RebuildCDS();
I32 CFE_ES_ClearCDS();
I32 CFE_ES_InitCDSSignatures();
I32 CFE_ES_InitCDSRegistry();
I32 CFE_ES_UpdateCDSRegistry();
I32 CFE_ES_LockCDS();
I32 CFE_ES_UnlockCDS();
CFE_ES_CDS_RegRec_t *CFE_ES_LocateCDSBlockRecordByID(U32 BlockID);
CFE_ES_CDS_RegRec_t *CFE_ES_LocateCDSBlockRecordByName(U8 *CDSName);
Bool CFE_ES_CheckCDSHandleSlotUsed(U32 CheckId);

/**
 * Context information used with registering a CDS
 *
 * This keeps the important state info so it can be easily
 * passed to helper functions.
 */
// FOUR FUNCTIONS SHARE ONE REGISTRATION, which is why this exists: Setup finds the slot,
// AllocateBlock sizes it, UpdateRegistry commits it and SendEvents decides what to say. The two
// `IsNew` flags are the interesting state -- they are what tells SendEvents whether this was a
// fresh registration, a resize, or an app asking for a store it already had.
class CFE_ES_CDS_RegistrationContext_t
{
  U8 *Name;
  CFE_ES_CDS_RegRec_t *RegRecPtr;
  U32 PendingBlockId; // CFE_ResourceId_t
  U8 _pad0[4];        // C aligns the two size_t that follow to 8
  I64 BlockOffset;    // size_t
  I64 BlockSize;      // size_t
  Bool IsNewEntry;
  Bool IsNewOffset;
  Bool IsTable;
  U8 _pad1[5];
};
// --- cfe_es_cds.h: the six `static inline` record accessors ---------------------------------
// DEFINED, not declared: the C half gets the real bodies from NASA's header, so a recording stub
// on this side would be the one place the two halves could disagree about what a CDS handle
// means. Four of them lived in cfe_es_api.HC until this file existed, with a note saying they
// would move here; they have.
//
// A CDS HANDLE AND A RESOURCE ID ARE THE SAME NUMBER in this port -- CFE_ES_CDSHANDLE_C is the
// identity -- which is why SetUsed takes a CFE_ResourceId_t and stores it in a
// CFE_ES_CDSHandle_t field without a conversion.
Bool CFE_ES_CDSBlockRecordIsUsed(CFE_ES_CDS_RegRec_t *CDSBlockRecPtr)
{
  return CFE_ResourceId_IsDefined(CDSBlockRecPtr->BlockID);
}

U32 CFE_ES_CDSBlockRecordGetID(CFE_ES_CDS_RegRec_t *CDSBlockRecPtr)
{
  return CDSBlockRecPtr->BlockID;
}

U0 CFE_ES_CDSBlockRecordSetUsed(CFE_ES_CDS_RegRec_t *CDSBlockRecPtr, U32 PendingId)
{
  CDSBlockRecPtr->BlockID = PendingId;
}

U0 CFE_ES_CDSBlockRecordSetFree(CFE_ES_CDS_RegRec_t *CDSBlockRecPtr)
{
  CDSBlockRecPtr->BlockID = CFE_ES_CDS_BAD_HANDLE;
}

Bool CFE_ES_CDSBlockRecordIsMatch(CFE_ES_CDS_RegRec_t *CDSBlockRecPtr, U32 BlockID)
{
  return (CDSBlockRecPtr != NULL && CFE_ResourceId_Equal(CDSBlockRecPtr->BlockID, BlockID));
}
// THE USER SIZE IS NOT THE BLOCK SIZE: every CDS block carries a CFE_ES_CDS_BlockHeader_t of
// its own -- a CRC, so a block that survived a reset can be checked -- and what the owning app
// asked for is what is left.
I64 CFE_ES_CDSBlockRecordGetUserSize(CFE_ES_CDS_RegRec_t *CDSBlockRecPtr)
{
  return (CDSBlockRecPtr->BlockSize - sizeof(CFE_ES_CDS_BlockHeader_t));
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// EVERY OUTCOME HERE EXCEPT ONE LEAVES THE CDS UNAVAILABLE, and that is deliberate: a
// spacecraft whose critical data store is too small, unreadable or unrecognisable still has to
// boot. CDSIsAvailable is cleared first and set only on the one path that got all the way
// through, so every public CDS entry point refuses rather than faulting.
//
// AND "INVALID" IS NOT A FAILURE. CFE_ES_ValidateCDS returning CFE_ES_CDS_INVALID means the
// signatures are not there -- a first boot, or a store from a different build -- so the answer
// is to wipe it, write the signatures, create the pool and write an empty registry. A store
// that validates gets its registry read back and its allocator rebuilt from the descriptors
// that are already in it, which is the whole point of the thing.
//
// A SIZE TOO SMALL IS REPORTED AND THEN IGNORED: Status stays CFE_SUCCESS, so ES's startup
// carries on with CDSIsAvailable false. The log line is the only trace.
I32 CFE_ES_CDS_EarlyInit()
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  U32 PlatformSize;
  I64 MinRequiredSize;
  I32 OsStatus;
  I32 Status;
  I32 PspStatus;
  CFE_ES_Global.CDSIsAvailable = FALSE;
  /* Create CDS general access mutex */
  OsStatus = OS_MutSemCreate(&CDS->GenMutex, CFE_ES_CDS_MUT_REG_NAME, CFE_ES_CDS_MUT_REG_VALUE);
  if (OsStatus != OS_SUCCESS) {
    CFE_ES_SysLogWrite_Unsync("%s: Failed to create mutex with error %ld\n",
                              "CFE_ES_CDS_EarlyInit", OsStatus);
    return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  }
  CDS->LastCDSBlockId = CFE_ES_CDSBLOCKID_BASE;
  /* Get CDS size from PSP.  Note that the PSP interface
   * uses "uint32" for size here. */
  PspStatus = CFE_PSP_GetCDSSize(&PlatformSize);
  if (PspStatus != CFE_PSP_SUCCESS) {
    /* Error getting the size of the CDS from the BSP */
    CFE_ES_WriteToSysLog("%s: Unable to obtain CDS Size from BSP (Err=0x%08X)\n",
                         "CFE_ES_CDS_EarlyInit", PspStatus);
    return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  }
  /* Always truncate the size to the nearest 4 byte boundary */
  CDS->TotalSize = PlatformSize & 0xFFFFFFFC;
  /* Compute the minimum size required for the CDS with the current configuration of the cFE */
  MinRequiredSize = CDS_RESERVED_MIN_SIZE;
  MinRequiredSize += CFE_ES_CDSReqdMinSize(CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES); /* Max # of Min Sized Blocks */
  if (CDS->TotalSize < MinRequiredSize) {
    CFE_ES_WriteToSysLog("%s: CDS Size (%lu) less than required (%lu)\n",
                         "CFE_ES_CDS_EarlyInit", CDS->TotalSize, MinRequiredSize);
    Status = CFE_SUCCESS;
  } else {
    CDS->DataSize = CDS->TotalSize;
    CDS->DataSize -= CDS_RESERVED_MIN_SIZE;
    /* If the size was obtained successfully and meets the minimum requirements, then check its contents */
    Status = CFE_ES_ValidateCDS();
    if (Status == CFE_SUCCESS) {
      /* If a valid CDS was found, rebuild the memory pool */
      Status = CFE_ES_RebuildCDS();
    }
    /* If the CDS is accessible but invalid, then create a new one */
    if (Status == CFE_ES_CDS_INVALID) {
      /* First wipe the entire CDS area */
      Status = CFE_ES_ClearCDS();
      if (Status == CFE_SUCCESS) {
        Status = CFE_ES_InitCDSSignatures();
      }
      if (Status == CFE_SUCCESS) {
        /* Initialize the variables for managing the CDS Memory Pool */
        Status = CFE_ES_CreateCDSPool(CDS->DataSize, CDS_POOL_OFFSET);
      }
      if (Status == CFE_SUCCESS) {
        Status = CFE_ES_InitCDSRegistry();
      }
    }
    if (Status != CFE_SUCCESS) {
      /* Unrecoverable error while reading the CDS */
      CFE_ES_WriteToSysLog("%s: Error validating/initializing CDS (0x%08lX)\n",
                           "CFE_ES_CDS_EarlyInit", Status);
    } else {
      /* Set the CDS Overall flag to be present/valid */
      CFE_ES_Global.CDSIsAvailable = TRUE;
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
I32 CFE_ES_CDSHandle_ToIndex(U32 BlockID, U32 *Idx)
{
  return CFE_ResourceId_ToIndex(BlockID, CFE_ES_CDSBLOCKID_BASE,
                                CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES, Idx);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// NULL ANSWERS "USED", and NASA's comment says why that is the safe direction: "The pointer
// here should never be NULL because the ID should always be within the expected range, but if it
// ever is NULL, this should return true such that the caller will _not_ attempt to use the
// record." A slot-scan that cannot see a record must not hand it out.
Bool CFE_ES_CheckCDSHandleSlotUsed(U32 CheckId)
{
  CFE_ES_CDS_RegRec_t *CDSRegRecPtr;
  /*
   * Note - The pointer here should never be NULL because the ID should always be
   * within the expected range, but if it ever is NULL, this should return true
   * such that the caller will _not_ attempt to use the record.
   */
  CDSRegRecPtr = CFE_ES_LocateCDSBlockRecordByID(CheckId);
  return (CDSRegRecPtr == NULL || CFE_ES_CDSBlockRecordIsUsed(CDSRegRecPtr));
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_ES_CDS_RegRec_t *CFE_ES_LocateCDSBlockRecordByID(U32 BlockID)
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  CFE_ES_CDS_RegRec_t *CDSRegRecPtr;
  U32 Idx;
  if (CFE_ES_CDSHandle_ToIndex(BlockID, &Idx) == CFE_SUCCESS) {
    CDSRegRecPtr = &CDS->Registry[Idx];
  } else {
    CDSRegRecPtr = NULL;
  }
  return CDSRegRecPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE CACHE IS ONE BUFFER AND IT IS BOUNDED BY THE UNION'S SIZE. Every fetch, flush and preload
// refuses a size of zero or anything larger than the cache can hold, which is 72 bytes -- the
// registry record, the union's largest member. That is the only bound checking the CDS has
// against a bad offset or length, because the store is reached by call and not by pointer:
// there is no fault to catch, only a PSP status.
I32 CFE_ES_CDS_CacheFetch(CFE_ES_CDS_AccessCache_t *Cache, I64 Offset, I64 Size)
{
  I32 Status;
  if (Size > 0 && Size <= sizeof(CFE_ES_CDS_AccessCacheData_t)) {
    Cache->AccessStatus = CFE_PSP_ReadFromCDS(&Cache->Data, Offset, Size);
    if (Cache->AccessStatus == CFE_PSP_SUCCESS) {
      Cache->Offset = Offset;
      Cache->Size = Size;
      Status = CFE_SUCCESS;
    } else {
      Status = CFE_ES_CDS_ACCESS_ERROR;
    }
  } else {
    Status = CFE_ES_CDS_INVALID_SIZE;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// IT WRITES WHAT THE CACHE ALREADY SAYS, taking the offset and size from the cache rather than
// from arguments -- so a flush always pairs with a preload or a fetch, and the two cannot
// disagree about where the bytes go.
I32 CFE_ES_CDS_CacheFlush(CFE_ES_CDS_AccessCache_t *Cache)
{
  I32 Status;
  if (Cache->Size > 0 && Cache->Size <= sizeof(CFE_ES_CDS_AccessCacheData_t)) {
    Cache->AccessStatus = CFE_PSP_WriteToCDS(&Cache->Data, Cache->Offset, Cache->Size);
    if (Cache->AccessStatus == CFE_PSP_SUCCESS) {
      Status = CFE_SUCCESS;
    } else {
      Status = CFE_ES_CDS_ACCESS_ERROR;
    }
  } else {
    Status = CFE_ES_CDS_INVALID_SIZE;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// A NULL SOURCE MEANS ZEROS, which is what CFE_ES_ClearCDS wipes the store with. And a source
// that IS the cache is left alone -- the `Source != &Cache->Data` test -- because
// CFE_ES_CDSBlockWrite fills the cache in place and then asks for it to be staged at an offset,
// and a memcpy onto itself is what that would otherwise be.
I32 CFE_ES_CDS_CachePreload(CFE_ES_CDS_AccessCache_t *Cache, U8 *Source, I64 Offset, I64 Size)
{
  I32 Status;
  if (Size > 0 && Size <= sizeof(CFE_ES_CDS_AccessCacheData_t)) {
    if (Source == NULL) {
      /* just zero it out */
      MemSet(&Cache->Data, 0, Size);
    } else if (Source != &Cache->Data) {
      /* copy from the user-supplied preload data */
      MemCpy(&Cache->Data, Source, Size);
    }
    Cache->Size = Size;
    Cache->Offset = Offset;
    Status = CFE_SUCCESS;
  } else {
    Status = CFE_ES_CDS_INVALID_SIZE;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Finds a registry table entry and sets up the Context object
 * This must be called with the CDS _locked_ because it searches through
 * the registry.  If this returns successfully, then it is guaranteed
 * that the RegRecPtr within the context object is valid and usable.
 *
 *-----------------------------------------------------------------*/
// A DUPLICATE NAME IS NOT AN ERROR HERE, and NASA's comment is the reason the whole CDS works
// the way it does: "in CDS a duplicate name is not necessarily an error, we may reuse/resize the
// existing entry". An app that restarts asks for its store by the same name and gets the same
// block back, with whatever survived in it -- that is what a critical data store is for.
//
// AND A NEW SLOT IS FOUND BUT NOT CLAIMED. The record is zeroed and remembered in the context,
// and CFE_ES_CDSBlockRecordSetUsed is not called until UpdateRegistry. NASA's note at the
// caller: "if an unused one is found, it is NOT marked as used (yet)... This way we can simply
// drop the pointer if a future step does not succeed." A different protocol from the app
// table's RESERVED id, and it works because the CDS lock is held across the whole operation.
I32 CFE_ES_RegisterCDS_Setup(CFE_ES_CDS_RegistrationContext_t *Ctxt, I64 UserBlockSize, U8 *Name,
                             Bool IsTable)
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I32 Status;
  Status = CFE_SUCCESS;
  /* Account for the extra header which will be added */
  Ctxt->BlockSize = UserBlockSize + sizeof(CFE_ES_CDS_BlockHeader_t);
  Ctxt->Name = Name;
  Ctxt->IsTable = IsTable;
  /*
   * Check for an existing entry with the same name.
   */
  Ctxt->RegRecPtr = CFE_ES_LocateCDSBlockRecordByName(Name);
  if (Ctxt->RegRecPtr != NULL) {
    /* in CDS a duplicate name is not necessarily an error, we
     * may reuse/resize the existing entry */
    Ctxt->PendingBlockId = CFE_ES_CDSBlockRecordGetID(Ctxt->RegRecPtr);
  } else {
    /* scan for a free slot */
    Ctxt->PendingBlockId = CFE_ResourceId_FindNext(CDS->LastCDSBlockId,
                                                   CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES,
                                                   &CFE_ES_CheckCDSHandleSlotUsed);
    Ctxt->RegRecPtr = CFE_ES_LocateCDSBlockRecordByID(Ctxt->PendingBlockId);
    if (Ctxt->RegRecPtr != NULL) {
      /* Fully clear the entry, just in case of stale data */
      MemSet(Ctxt->RegRecPtr, 0, sizeof(CFE_ES_CDS_RegRec_t));
      CDS->LastCDSBlockId = Ctxt->PendingBlockId;
      Ctxt->IsNewEntry = TRUE;
    } else {
      Status = CFE_ES_NO_RESOURCE_IDS_AVAILABLE;
      Ctxt->PendingBlockId = CFE_RESOURCEID_UNDEFINED;
    }
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Allocates the necessary pool block for this CDS, if needed
 * This should be called with the CDS _locked_ as it accesses and changes registry values
 * This may do nothing if there is already an existing entry and the block size is OK
 *
 *-----------------------------------------------------------------*/
// A ZERO OFFSET MEANS "NO BLOCK", and NASA explains why that is safe: "because CDS puts a
// signature at the very beginning of the memory, valid data offsets are never zero." The
// signature is not just a validity marker, it is what makes offset 0 usable as a null.
//
// AND A FAILED FREE IS DROPPED ON PURPOSE, which is worth quoting because it looks like a
// missing check: "This is done regardless of the status from CFE_ES_GenPoolPutBlock() - because
// if that failed for some reason, the block must've been bad/invalid anyway, so it wasn't
// actually usable. That should never happen in practice, but if it does happen then there is
// nothing we can do about it, so just drop it and move on."
I32 CFE_ES_RegisterCDS_AllocateBlock(CFE_ES_CDS_RegistrationContext_t *Ctxt)
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I64 OldBlockSize;
  I32 Status;
  /* If a reallocation is needed, the old block may need to be freed first */
  if (Ctxt->RegRecPtr->BlockOffset != 0 && Ctxt->BlockSize != Ctxt->RegRecPtr->BlockSize) {
    /* If the new size is different, the old CDS must be deleted first  */
    CFE_ES_GenPoolPutBlock(&CDS->Pool, &OldBlockSize, Ctxt->RegRecPtr->BlockOffset);
    /*
     * Track that there is no longer any block associated with this registry entry
     * Note because CDS puts a signature at the very beginning of the memory,
     * valid data offsets are never zero.
     *
     * This is done regardless of the status from CFE_ES_GenPoolPutBlock() - because
     * if that failed for some reason, the block must've been bad/invalid anyway, so
     * it wasn't actually usable.  That should never happen in practice, but if it does
     * happen then there is nothing we can do about it, so just drop it and move on.
     */
    Ctxt->RegRecPtr->BlockOffset = 0;
    Ctxt->RegRecPtr->BlockSize = 0;
  }
  /* If a new allocation is needed, do it now */
  if (Ctxt->RegRecPtr->BlockOffset != 0) {
    /* the existing block will be used as-is, nothing to be done */
    Status = CFE_SUCCESS;
  } else {
    /* Allocate the block for the CDS */
    Status = CFE_ES_GenPoolGetBlock(&CDS->Pool, &Ctxt->BlockOffset, Ctxt->BlockSize);
    if (Status == CFE_SUCCESS) {
      /* Save the size of the CDS.  The IsNewOffset flag indicates a registry update is needed */
      Ctxt->RegRecPtr->BlockOffset = Ctxt->BlockOffset;
      Ctxt->RegRecPtr->BlockSize = Ctxt->BlockSize;
      Ctxt->IsNewOffset = TRUE;
    }
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Allocates the necessary pool block for this CDS, if needed
 * This should be called with the CDS _locked_ as it accesses and changes registry values
 * This may do nothing if there is already an existing entry and the block size is OK
 *
 *-----------------------------------------------------------------*/
// IT ONLY WRITES THE REGISTRY TO THE STORE IF THE OFFSET MOVED. A new entry gets its name and
// table flag and is marked used; but the 36 KiB registry is only pushed out to the CDS when
// IsNewOffset says a block was actually allocated. Re-registering at the same size writes
// nothing, which is the case an app restart hits every time.
I32 CFE_ES_RegisterCDS_UpdateRegistry(CFE_ES_CDS_RegistrationContext_t *Ctxt)
{
  I32 Status;
  if (Ctxt->IsNewEntry) {
    /* Save flag indicating whether it is a Critical Table or not */
    Ctxt->RegRecPtr->Table = Ctxt->IsTable;
    /* Save CDS Name in Registry */
    StrNCpy(Ctxt->RegRecPtr->Name, Ctxt->Name, CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN - 1);
    Ctxt->RegRecPtr->Name[CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN - 1] = 0;
    /* marks the block as used. */
    CFE_ES_CDSBlockRecordSetUsed(Ctxt->RegRecPtr, Ctxt->PendingBlockId);
  }
  if (Ctxt->IsNewOffset) {
    /* save updated registry in the CDS */
    Status = CFE_ES_UpdateCDSRegistry();
  } else {
    /* there is no need to update anything (e.g. when reusing a block and not resized) */
    Status = CFE_SUCCESS;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Local helper function
 * Send any events from the registration operation and determine the final status code
 * This should be called with the CDS _unlocked_ because it makes calls into other subsystems
 *
 *-----------------------------------------------------------------*/
// THE ALT-SUCCESS CODE, and the condition for it is exact: allocation succeeded, the entry is
// not new, and the offset did not move -- an app asking for a store it already had, at the size
// it already had. NASA: "For backward compatibility, return the special alt-success code when
// reallocating an existing CDS without changing any block allocations. Note this intentionally
// does NOT return this code when reusing an exiting entry but changing the size."
//
// CFE_ES_CDS_ALREADY_EXISTS has its HIGH BIT CLEAR -- 0x4400000D, not 0xC4... -- so a caller
// testing `< 0` or `!= CFE_SUCCESS` treats it differently, which is the whole reason it is
// shaped that way.
I32 CFE_ES_RegisterCDS_SendEvents(CFE_ES_CDS_RegistrationContext_t *Ctxt, I32 AllocStatus,
                                  I32 RegUpdateStatus)
{
  I32 FinalStatus;
  FinalStatus = CFE_SUCCESS;
  /* Log any failures AFTER releasing the lock */
  if (RegUpdateStatus != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Failed to update CDS Registry (Stat=0x%08X)\n",
                         "CFE_ES_RegisterCDS_SendEvents", RegUpdateStatus);
  } else if (AllocStatus == CFE_SUCCESS && !Ctxt->IsNewEntry && !Ctxt->IsNewOffset) {
    /*
     * For backward compatibility, return the
     * special alt-success code when reallocating
     * an existing CDS without changing
     * any block allocations.
     *
     * Note this intentionally does NOT return this code
     * when reusing an exiting entry but changing the size.
     */
    FinalStatus = CFE_ES_CDS_ALREADY_EXISTS;
  }
  /* determine which status code should be returned as the final status */
  /* if everything worked all of these will be CFE_SUCCESS */
  if (FinalStatus == CFE_SUCCESS) {
    FinalStatus = AllocStatus;
  }
  if (FinalStatus == CFE_SUCCESS) {
    FinalStatus = RegUpdateStatus;
  }
  return FinalStatus;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE HANDLE IS EXPORTED WHATEVER HAPPENS, which looks wrong and is not: the memset at the top
// leaves PendingBlockId as CFE_RESOURCEID_UNDEFINED, and only the paths that got as far as
// finding a slot overwrite it. NASA's comment -- "Export the handle regardless of status code.
// Note that the initial memset above will make this into the UNDEFINED memhandle value unless
// we got to the point in allocation where we have a valid ID" -- so a caller that ignores the
// status still gets an unusable handle rather than an uninitialised one.
//
// AND THE LOCK SPANS EXACTLY THE PART THAT USES THE POINTER. Setup through UpdateRegistry all
// work through Ctxt->RegRecPtr, which points into the registry; the unlock is immediately after,
// with NASA's note "the registry pointer shouldn't be used after this", and SendEvents takes
// only the flags and the two statuses.
I32 CFE_ES_RegisterCDSEx(U32 *HandlePtr, I64 UserBlockSize, U8 *Name, Bool CriticalTbl)
{
  CFE_ES_CDS_RegistrationContext_t Ctxt;
  I32 Status;
  I32 RegUpdateStatus;
  MemSet(&Ctxt, 0, sizeof(CFE_ES_CDS_RegistrationContext_t));
  /* Basic sanity check of request */
  if (UserBlockSize == 0 || UserBlockSize > CDS_ABS_MAX_BLOCK_SIZE) {
    /* Block size is not supportable */
    Status = CFE_ES_CDS_INVALID_SIZE;
  } else {
    /* Lock Registry for update.  This prevents two applications from */
    /* trying to register CDSs at the same location at the same time  */
    CFE_ES_LockCDS();
    /*
     * Set up all pointers/values in the context.  This locates the an existing
     * registry entry or finds an unused one.  If an unused one is found, it
     * is NOT marked as used (yet).  Only a pointer to the entry is obtained.
     * This way we can simply drop the pointer if a future step does not succeed.
     *
     * Either way, if this returns CFE_SUCCESS, it means that the RegRecPtr
     * within the context object is non-NULL and points to an entry that will
     * be used in the rest of the operation.
     *
     * Since this is operating via a pointer, the lock must be held for the
     * remainder of the operation until it is finalized.
     */
    Status = CFE_ES_RegisterCDS_Setup(&Ctxt, UserBlockSize, Name, CriticalTbl);
    if (Status == CFE_SUCCESS) {
      /*
       * [Re-]Allocate pool block.  This may be a no-op if the reusing a block and the
       * size has not changed.  Otherwise it will free the existing block if needed,
       * and allocate an appropriately-sized block.
       *
       * If this returns successfully, it means we have an appropriately-sized block
       */
      Status = CFE_ES_RegisterCDS_AllocateBlock(&Ctxt);
    }
    /*
     * Note: If this is unsuccessful at this point, if it was a new entry then
     * it was not (yet) marked as used -- its still free in the registry.  So
     * doing nothing here will effectively drop it.
     */
    if (Status == CFE_SUCCESS) {
      /* Update all relevant values in the CDS registry and commit.
       * The status is kept separate because this only is used for
       * sending informational events */
      RegUpdateStatus = CFE_ES_RegisterCDS_UpdateRegistry(&Ctxt);
    } else {
      /* nothing to do */
      RegUpdateStatus = CFE_SUCCESS;
    }
    /* now that any changes are committed, the CDS can be unlocked, but
     * The registry pointer shouldn't be used after this */
    CFE_ES_UnlockCDS();
    /* This sends any relevent events, and also scrubs the return value
     * to make it backward compatible with historical implementations of
     * this function. */
    Status = CFE_ES_RegisterCDS_SendEvents(&Ctxt, Status, RegUpdateStatus);
  }
  /* Export the handle regardless of status code.  Note that the initial memset
   * above will make this into the UNDEFINED memhandle value unless we got to
   * the point in allocation where we have a valid ID. */
  *HandlePtr = Ctxt.PendingBlockId;
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// TWO SIGNATURES, ONE AT EACH END, and that is the whole validity test. "_CDSBeg_" in the first
// eight bytes and "_CDSEnd_" in the last eight: both present means a store this build wrote and
// did not run off the end of. A PSP read error is reported as itself; a signature that does not
// match is CFE_ES_CDS_INVALID, which the caller reads as "wipe it and start again".
//
// NASA writes `const size_t SIG_CDS_SIZE = { CFE_ES_CDS_SIGNATURE_LEN };` -- a braced
// initialiser on a scalar. HolyC has no `const` and the braces mean nothing here, so it is a
// plain local.
I32 CFE_ES_ValidateCDS()
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I64 TrailerOffset;
  I64 SIG_CDS_SIZE = CFE_ES_CDS_SIGNATURE_LEN;
  I32 Status;
  /* Perform 2 checks to validate the CDS Memory Pool */
  /* First, determine if the first validity check field is correct */
  Status = CFE_ES_CDS_CacheFetch(&CDS->Cache, CDS_SIG_BEGIN_OFFSET, SIG_CDS_SIZE);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: 1st ReadFromCDS Failed. Status=0x%X\n", "CFE_ES_ValidateCDS",
                         Status);
    return Status;
  }
  if (StrNCmp(CDS->Cache.Data.Sig, CFE_ES_CDS_SIGNATURE_BEGIN, CFE_ES_CDS_SIGNATURE_LEN) != 0) {
    /* Beginning Validity Field failed */
    return CFE_ES_CDS_INVALID;
  }
  TrailerOffset = CDS->TotalSize;
  TrailerOffset -= CDS_PERSISTENT_TRAILER_SIZE;
  Status = CFE_ES_CDS_CacheFetch(&CDS->Cache, TrailerOffset, SIG_CDS_SIZE);
  if (Status != CFE_SUCCESS) {
    /* BSP reported an error reading from CDS */
    CFE_ES_WriteToSysLog("%s: 2nd ReadFromCDS Failed. Status=0x%X\n", "CFE_ES_ValidateCDS",
                         Status);
    return Status;
  }
  if (StrNCmp(CDS->Cache.Data.Sig, CFE_ES_CDS_SIGNATURE_END, CFE_ES_CDS_SIGNATURE_LEN) != 0) {
    /* Ending Validity Field failed */
    return CFE_ES_CDS_INVALID;
  }
  /* All sanity checks passed */
  return CFE_SUCCESS;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// SIXTEEN BYTES AT A TIME, because that is the largest zero-fill the cache union offers --
// `uint32 Zero[4]`. A CDS of any size is wiped by one preload of zeros and then a flush per
// step, with the last step shortened to whatever is left. Slow and simple, and it runs once: on
// a store that did not validate.
I32 CFE_ES_ClearCDS()
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I64 RemainSize;
  I32 Status;
  Status = CFE_SUCCESS;
  /* Clear the CDS to ensure everything is gone */
  /* Create a block of zeros to write to the CDS */
  CFE_ES_CDS_CachePreload(&CDS->Cache, NULL, 0, 16);
  /* While there is space to write another block of zeros, then do so */
  while (CDS->Cache.Offset < CDS->TotalSize) {
    RemainSize = CDS->TotalSize - CDS->Cache.Offset;
    if (RemainSize < 16) {
      /* partial size */
      CDS->Cache.Size = RemainSize;
    }
    Status = CFE_ES_CDS_CacheFlush(&CDS->Cache);
    if (Status != CFE_SUCCESS) {
      break;
    }
    CDS->Cache.Offset += CDS->Cache.Size;
  }
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Clear CDS failed @ Offset=%lu Status=0x%08X\n", "CFE_ES_ClearCDS",
                         CDS->Cache.Offset, CDS->Cache.AccessStatus);
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// WRITING THE SIGNATURES IS WHAT MAKES THE STORE OURS, and it is the last step before the pool
// and registry go in -- so a store whose signatures are written but whose registry is not will
// validate on the next boot and then fail the registry-size check in CFE_ES_RebuildCDS, which
// returns CFE_ES_CDS_INVALID and wipes it again. There is no half-initialised state that gets
// trusted.
I32 CFE_ES_InitCDSSignatures()
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I64 SigOffset;
  I32 Status;
  /* Initialize the Validity Check strings */
  SigOffset = 0;
  CFE_ES_CDS_CachePreload(&CDS->Cache, CFE_ES_CDS_SIGNATURE_BEGIN, SigOffset,
                          CFE_ES_CDS_SIGNATURE_LEN);
  Status = CFE_ES_CDS_CacheFlush(&CDS->Cache);
  if (Status != CFE_SUCCESS) {
    /* BSP reported an error writing to CDS */
    CFE_ES_WriteToSysLog("%s: '_CDSBeg_' write failed. Status=0x%08X\n",
                         "CFE_ES_InitCDSSignatures", CDS->Cache.AccessStatus);
    return Status;
  }
  SigOffset = CDS->TotalSize;
  SigOffset -= CDS_PERSISTENT_TRAILER_SIZE;
  CFE_ES_CDS_CachePreload(&CDS->Cache, CFE_ES_CDS_SIGNATURE_END, SigOffset,
                          CFE_ES_CDS_SIGNATURE_LEN);
  Status = CFE_ES_CDS_CacheFlush(&CDS->Cache);
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: '_CDSEnd_' write failed. Status=0x%08X\n",
                         "CFE_ES_InitCDSSignatures", CDS->Cache.AccessStatus);
    return Status;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE ENTRY COUNT GOES IN THE STORE, which is how a store written by a differently-configured
// build is recognised: CFE_ES_RebuildCDS reads this number back and refuses anything that is
// not CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES, because the registry it would read next would be the
// wrong size.
I32 CFE_ES_InitCDSRegistry()
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I32 Status;
  U32 RegSize;
  /* Initialize the local CDS Registry */
  RegSize = CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES;
  CFE_ES_CDS_CachePreload(&CDS->Cache, &RegSize, CDS_REG_SIZE_OFFSET, sizeof(U32));
  /* Copy the number of registry entries to the CDS */
  Status = CFE_ES_CDS_CacheFlush(&CDS->Cache);
  if (Status == CFE_SUCCESS) {
    MemSet(CDS->Registry, 0,
           CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES * sizeof(CFE_ES_CDS_RegRec_t));
    Status = CFE_ES_UpdateCDSRegistry();
  } else {
    CFE_ES_WriteToSysLog("%s: Failed to write Reg Size. Status=0x%08X\n",
                         "CFE_ES_InitCDSRegistry", CDS->Cache.AccessStatus);
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE WHOLE 36 KiB REGISTRY, EVERY TIME, and it does not go through the cache: the cache holds
// 72 bytes, so this is the one write in the file that hands the PSP a RAM pointer directly.
// That is why a registration that does not move a block does not call this.
I32 CFE_ES_UpdateCDSRegistry()
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I32 PspStatus;
  /* Copy the contents of the local registry to the CDS */
  PspStatus = CFE_PSP_WriteToCDS(CDS->Registry, CDS_REG_OFFSET,
                                 CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES *
                                     sizeof(CFE_ES_CDS_RegRec_t));
  if (PspStatus != CFE_PSP_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: Failed to write CDS Registry. Status=0x%08X\n",
                         "CFE_ES_UpdateCDSRegistry", PspStatus);
    return CFE_ES_CDS_ACCESS_ERROR;
  }
  return CFE_SUCCESS;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// A CDS NAME IS "APPNAME.CDSNAME", and the dot is what CFE_ES_DeleteCDS scans back for to work
// out who owns a block -- so the format here and the parser there are one rule in two places.
U0 CFE_ES_FormCDSName(U8 *FullCDSName, U8 *CDSName, U32 ThisAppId)
{
  U8 AppName[OS_MAX_API_NAME];
  CFE_ES_GetAppName(AppName, ThisAppId, OS_MAX_API_NAME);
  /* Ensure that AppName is null terminated */
  AppName[OS_MAX_API_NAME - 1] = '\0';
  /* Complete formation of processor specific table name */
  StrPrintN(FullCDSName, CFE_MISSION_ES_CDS_MAX_FULL_NAME_LEN, "%s.%s", AppName, CDSName);
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE CDS HAS ITS OWN MUTEX, separate from ES's shared-data lock, and the two are never held
// together. Both of these convert the OSAL status to a cFE one and nothing else -- the callers
// do not check it, which is NASA's choice and is kept.
I32 CFE_ES_LockCDS()
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I32 OsStatus;
  I32 Status;
  OsStatus = OS_MutSemTake(CDS->GenMutex);
  /* Convert to CFE return code */
  if (OsStatus == OS_SUCCESS) {
    Status = CFE_SUCCESS;
  } else {
    Status = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_UnlockCDS()
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I32 OsStatus;
  I32 Status;
  OsStatus = OS_MutSemGive(CDS->GenMutex);
  /* Convert to CFE return code */
  if (OsStatus == OS_SUCCESS) {
    Status = CFE_SUCCESS;
  } else {
    Status = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// A CASE-SENSITIVE WALK OF THE WHOLE REGISTRY, and the loop leaves the pointer ON the match --
// so the caller gets the record, not an index. Only a used entry is compared, which is what
// lets a freed slot keep its stale name without being found again.
CFE_ES_CDS_RegRec_t *CFE_ES_LocateCDSBlockRecordByName(U8 *CDSName)
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  CFE_ES_CDS_RegRec_t *CDSRegRecPtr;
  U32 NumReg;
  CDSRegRecPtr = CDS->Registry;
  NumReg = CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES;
  while (TRUE) {
    if (NumReg == 0) {
      CDSRegRecPtr = NULL; /* not found */
      break;
    }
    if (CFE_ES_CDSBlockRecordIsUsed(CDSRegRecPtr)) {
      /* Perform a case sensitive name comparison */
      if (StrCmp(CDSName, CDSRegRecPtr->Name) == 0) {
        /* If the names match, then stop */
        break;
      }
    }
    ++CDSRegRecPtr;
    --NumReg;
  }
  return CDSRegRecPtr;
}

/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE RECOVERY PATH, and it checks the ENTRY COUNT before it reads the registry. A store from a
// build configured for a different number of entries would otherwise be read as 36 KiB of
// something else, so the count written by CFE_ES_InitCDSRegistry is the version number of the
// layout. A mismatch is CFE_ES_CDS_INVALID -- wipe and start again -- not an attempt to
// convert.
I32 CFE_ES_RebuildCDS()
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I32 Status;
  I32 PspStatus;
  /* First, determine if the CDS registry stored in the CDS is smaller or equal */
  /* in size to the CDS registry we are currently configured for                */
  /* Copy the number of registry entries to the CDS */
  Status = CFE_ES_CDS_CacheFetch(&CDS->Cache, CDS_REG_SIZE_OFFSET, sizeof(U32));
  if (Status != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("%s: PSP Error reading Registry size (%lx)\n", "CFE_ES_RebuildCDS",
                         CDS->Cache.AccessStatus);
    return CFE_ES_CDS_INVALID;
  }
  if (CDS->Cache.Data.RegistrySize != CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES) {
    /* Registry in CDS is incompatible size to recover */
    CFE_ES_WriteToSysLog("%s: Registry in CDS incorrect size (%lu)\n", "CFE_ES_RebuildCDS",
                         CDS->Cache.Data.RegistrySize);
    return CFE_ES_CDS_INVALID;
  }
  PspStatus = CFE_PSP_ReadFromCDS(&CDS->Registry, CDS_REG_OFFSET,
                                  CFE_PLATFORM_ES_CDS_MAX_NUM_ENTRIES *
                                      sizeof(CFE_ES_CDS_RegRec_t));
  if (PspStatus == CFE_PSP_SUCCESS) {
    /* Scan the memory pool and identify the created but currently unused memory blocks */
    Status = CFE_ES_RebuildCDSPool(CDS->DataSize, CDS_POOL_OFFSET);
  } else {
    /* Registry in CDS is unreadable */
    CFE_ES_WriteToSysLog("%s: Registry in CDS is unreadable, PSP error %lx\n",
                         "CFE_ES_RebuildCDS", PspStatus);
    Status = CFE_ES_CDS_INVALID;
  }
  return Status;
}

/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// YOU MAY NOT DELETE A CRITICAL TABLE'S CDS WITH AN ES COMMAND, and the test is one line:
// `RegRecPtr->Table != CalledByTblServices`. The Table flag recorded at registration and the
// caller's own claim about who it is have to agree, which is why the parameter exists at all --
// NASA's comment: "Critical tables are not allowed to be deleted via an ES Command. They must be
// deleted by a Table Services Command."
//
// AND THE OWNER MUST BE GONE. The app name is scanned out of the "APPNAME.CDSNAME" the registry
// holds, up to the dot, and looked up: if the app is still registered the delete is refused with
// CFE_ES_CDS_OWNER_ACTIVE_ERR. NASA's comment on the inverted test is worth keeping -- "If we
// can't find the name, then things are good" -- because a FAILED lookup is the success case
// here.
//
// The log message is built into a local and written after the unlock, for the reason the whole
// file is written around: one lock at a time.
I32 CFE_ES_DeleteCDS(U8 *CDSName, Bool CalledByTblServices)
{
  CFE_ES_CDS_Instance_t *CDS = &CFE_ES_Global.CDSVars;
  I32 Status;
  CFE_ES_CDS_RegRec_t *RegRecPtr;
  U8 OwnerName[OS_MAX_API_NAME];
  U32 AppId;
  U32 i;
  U8 LogMessage[CFE_ES_MAX_SYSLOG_MSG_SIZE];
  I64 OldBlockSize;
  LogMessage[0] = 0;
  /* Lock Registry for update.  This prevents two applications from */
  /* trying to change the CDS registry at the same time  */
  CFE_ES_LockCDS();
  /* Find CDS name in registry */
  RegRecPtr = CFE_ES_LocateCDSBlockRecordByName(CDSName);
  /* Check to see if CDS is already in the registry */
  if (RegRecPtr != NULL) {
    /* Critical tables are not allowed to be deleted via an ES Command. */
    /* They must be deleted by a Table Services Command */
    if (RegRecPtr->Table != CalledByTblServices) {
      Status = CFE_ES_CDS_WRONG_TYPE_ERR;
    } else {
      /* Check to see if the owning application is still active */
      /* First, extract the owning application name */
      i = 0;
      while ((i < (OS_MAX_API_NAME - 1) && (RegRecPtr->Name[i] != '.'))) {
        OwnerName[i] = RegRecPtr->Name[i];
        i++;
      }
      /* Null terminate the application name */
      OwnerName[i] = '\0';
      /* Check to see if the Application Name is in the Registered Apps list */
      Status = CFE_ES_GetAppIDByName(&AppId, OwnerName);
      /* If we can't find the name, then things are good */
      if (Status != CFE_SUCCESS) {
        /* Free the registry entry and the CDS memory block associated with it */
        Status = CFE_ES_GenPoolPutBlock(&CDS->Pool, &OldBlockSize, RegRecPtr->BlockOffset);
        /* Report any errors incurred while freeing the CDS Memory Block */
        if (Status != CFE_SUCCESS) {
          StrPrintN(LogMessage, CFE_ES_MAX_SYSLOG_MSG_SIZE,
                    "Failed to free CDS Mem Block (Handle=0x%08lX)(Stat=0x%08X)\n",
                    RegRecPtr->BlockOffset, Status);
        } else {
          /* Remove entry from the CDS Registry */
          CFE_ES_CDSBlockRecordSetFree(RegRecPtr);
          Status = CFE_ES_UpdateCDSRegistry();
          if (Status != CFE_SUCCESS) {
            StrPrintN(LogMessage, CFE_ES_MAX_SYSLOG_MSG_SIZE,
                      "Failed to update CDS Registry (Stat=0x%08X)\n", Status);
          }
        }
      } else {
        Status = CFE_ES_CDS_OWNER_ACTIVE_ERR;
      }
    }
  } else /* Error - CDS not in registry */
  {
    Status = CFE_ES_ERR_NAME_NOT_FOUND;
  }
  /* Unlock Registry for future updates */
  CFE_ES_UnlockCDS();
  /* Output the message to syslog once the CDS registry resource is unlocked */
  if (LogMessage[0] != 0) {
    CFE_ES_WriteToSysLog("%s: %s", "CFE_ES_DeleteCDS", LogMessage);
  }
  return Status;
}
#endif
