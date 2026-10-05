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
// TABLE SERVICES' LOAD BUFFERS -- the DECLARATIONS of NASA's cfe_tbl_loadbuff.h: two types and
// the thirteen `static inline` accessors over CFE_TBL_LoadBuff_t. cfe_tbl_loadbuff.c itself is
// NOT gated; it is inside tbl's remaining seven-source call cycle, mutually recursive with
// cfe_tbl_regrec.c (tools/cfs/module_deps.py --cuts prices the pair at four stand-ins).
//
// THE NAME SAYS _decl FOR A REASON. This file holds the header's contents and nothing else.
// The twenty .c functions -- the buffer-id serial encoding, the shared/local categories,
// PrepareNewLoadBuff, the activation request -- are not here. A reader gating
// cfe_tbl_loadbuff.c should expect to add those and find these already done.
//
// WHAT A LOAD BUFFER IS. A table's contents live in one, and there are two kinds. The four
// SHARED ones in CFE_TBL_Global.LoadBuffs are borrowed for the duration of a load and handed
// back; a double-buffered table instead owns a DEDICATED pair so it can be updated without
// ever waiting for a shared one. Which kind an id refers to is encoded in the id itself, in a
// category field -- which is exactly the logic that makes `regrec` ungateable without this
// source, because regrec asks "what buffer is this id" and only loadbuff.c knows.
//
// ALLOCATED VERSUS EXTERNAL is the distinction the accessors below turn on.
// CFE_TBL_LoadBuffSetAllocatedBlock records memory Table Services owns and may write;
// CFE_TBL_LoadBuffSetExternalBlock records memory the APPLICATION owns, where cFE may only
// read -- and so CFE_TBL_LoadBuffGetWritePointer returns NULL for it while
// CFE_TBL_LoadBuffGetReadPointer does not. That asymmetry is the whole safety property for a
// user-defined-address table, and it is one `if` in one inline.
#ifndef CFE_TBL_LOADBUFF_DECL_HC
#define CFE_TBL_LOADBUFF_DECL_HC

// Helper for incrementing load buffer serial numbers. NASA's own note: "intended for use with
// CFE_TBL_LoadBuffIncrementSerial(), and should not be used outside of this context. It needs
// to be exposed in this header for unit testing purposes only."
class CFE_TBL_LoadBuffFindNextState_t
{
  U32 BaseCategory;
  U32 RemainingCount;
};

// The context every transaction event is rendered against: what was attempted, on which table,
// by whom. OperationDataPtr is operation-specific and may be NULL.
class CFE_TBL_TxnEventContext_t
{
  U8 *Operation;
  U8 *OperationDataPtr;
  U8 *TableName;
  U8 *CallerName;
  CFE_TBL_RegistryRec_t *RegRecPtr;
};

// --- cfe_tbl_loadbuff.h's thirteen accessors ------------------------------------------------
U32 CFE_TBL_LoadBufferGetID(CFE_TBL_LoadBuff_t *LoadBuffPtr)
{
  return LoadBuffPtr->LoadBufferId;
}

Bool CFE_TBL_LoadBuffIsUsed(CFE_TBL_LoadBuff_t *BuffPtr)
{
  return CFE_ResourceId_IsDefined(BuffPtr->LoadBufferId);
}

U0 CFE_TBL_LoadBuffSetUsed(CFE_TBL_LoadBuff_t *BuffPtr, U32 PendingId, U32 OwnerRegId)
{
  BuffPtr->OwnerRegId = OwnerRegId;
  BuffPtr->LoadBufferId = PendingId;
}

U0 CFE_TBL_LoadBuffSetFree(CFE_TBL_LoadBuff_t *BuffPtr)
{
  BuffPtr->LoadBufferId = CFE_TBL_LOADBUFFID_UNDEFINED;
}

// ALLOCATED: memory Table Services owns. ContentSize starts at 0 because nothing is in it yet,
// and the CRC with it.
U0 CFE_TBL_LoadBuffSetAllocatedBlock(CFE_TBL_LoadBuff_t *BuffPtr, U8 *MemPtr, I64 MemSize)
{
  BuffPtr->BufferPtr = MemPtr;
  BuffPtr->AllocationSize = MemSize;
  BuffPtr->ContentSize = 0;
  BuffPtr->Crc = 0;
}

// EXTERNAL: memory the APPLICATION owns. AllocationSize is 0 -- which is what makes
// CFE_TBL_LoadBuffIsAllocated false and CFE_TBL_LoadBuffGetWritePointer return NULL -- and
// ContentSize is the full size, because an app-owned buffer is full by definition.
U0 CFE_TBL_LoadBuffSetExternalBlock(CFE_TBL_LoadBuff_t *BuffPtr, U8 *MemPtr, I64 MemSize)
{
  BuffPtr->BufferPtr = MemPtr;
  BuffPtr->ContentSize = MemSize;
  BuffPtr->AllocationSize = 0;
  BuffPtr->Crc = 0;
}

Bool CFE_TBL_LoadBuffIsAllocated(CFE_TBL_LoadBuff_t *BuffPtr)
{
  return BuffPtr->AllocationSize != 0;
}

U8 *CFE_TBL_LoadBuffGetReadPointer(CFE_TBL_LoadBuff_t *BuffPtr)
{
  return BuffPtr->BufferPtr;
}

// THE ONE SAFETY PROPERTY IN THIS FILE. A buffer cFE did not allocate is one the application
// owns, and cFE may read it but must never write it.
U8 *CFE_TBL_LoadBuffGetWritePointer(CFE_TBL_LoadBuff_t *BuffPtr)
{
  if (!CFE_TBL_LoadBuffIsAllocated(BuffPtr))
    return NULL;
  return BuffPtr->BufferPtr;
}

I64 CFE_TBL_LoadBuffGetAllocSize(CFE_TBL_LoadBuff_t *BuffPtr)
{
  return BuffPtr->AllocationSize;
}

I64 CFE_TBL_LoadBuffGetContentSize(CFE_TBL_LoadBuff_t *BuffPtr)
{
  return BuffPtr->ContentSize;
}

U0 CFE_TBL_LoadBuffSetContentSize(CFE_TBL_LoadBuff_t *BuffPtr, I64 ContentSize)
{
  BuffPtr->ContentSize = ContentSize;
}

Bool CFE_TBL_LoadBuffIsMatch(CFE_TBL_LoadBuff_t *BuffPtr, U32 BufferId)
{
  return BuffPtr != NULL && CFE_ResourceId_Equal(BuffPtr->LoadBufferId, BufferId);
}
#endif
