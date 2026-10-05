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
// TABLE SERVICES' TRANSACTION STATE -- the DECLARATIONS of NASA's cfe_tbl_transaction.h: two
// types and the eight `static inline` accessors over them. cfe_tbl_transaction.c itself is NOT
// gated; it sits inside tbl's eight-source call cycle (tools/cfs/module_deps.py --cuts).
//
// THE DECL-SPLIT PATTERN, the same one osapi_heap_decl.HC, osapi_module_decl.HC and
// osapi_filesys_decl.HC use: a gated source needs a TYPE from a source that is not gated yet.
// Carrying the type alone is honest and costs nothing -- check_padding measures it against
// NASA's struct like any other -- where carrying the implementation would be a translation
// nobody asked for.
//
// WHAT A TRANSACTION IS. Every public CFE_TBL_* call that touches the registry runs inside
// one: it records WHO is calling (AppId, and the name buffer so an event can say it), WHICH
// table (Handle, RegId, and resolved pointers to the access descriptor and registry record),
// how many times this call has taken the registry lock, and a list of EVENTS to send once the
// lock is released. That last part is the design: a table operation decides what to report
// while holding the lock, and the reporting happens after, so EVS is never called under it.
//
// EIGHT EVENTS MAXIMUM, and NumPendingEvents counts PAST the limit deliberately -- NASA
// increments it even when the array is full, so a caller can tell "eight events" from "eight
// events and some dropped". CFE_TBL_TxnAddEvent is where that happens.
#ifndef CFE_TBL_TRANSACTION_DECL_HC
#define CFE_TBL_TRANSACTION_DECL_HC
#ifndef CFE_TBL_MAX_EVENTS_PER_TXN
#define CFE_TBL_MAX_EVENTS_PER_TXN 8
#endif

// The ID that should be broadcast via EVS, plus two general-purpose integers that further
// identify the cause. NASA's rule of thumb, kept because it is the only thing that says which
// is which: "if the event was triggered from a comparison between two values, then register
// the actual observed value (or status code) as event data 1, and the expected value as event
// data 2".
class CFE_TBL_TxnEvent_t
{
  U16 EventId;
  U8 _pad0[2]; // C aligns the two 4-byte values that follow
  I32 EventData1; // Actual value observed
  I32 EventData2; // Expected value, if applicable, or other relevant value
};

class CFE_TBL_TxnState_t
{
  U32 AppId;  // CFE_ES_AppId_t
  U32 Handle; // CFE_TBL_HandleId_t
  U32 RegId;  // CFE_TBL_RegId_t
  U32 RegLockCount;
  U32 CallContext;
  U8 AppNameBuffer[CFE_MISSION_MAX_API_LEN];
  CFE_TBL_AccessDescriptor_t *AccDescPtr;
  CFE_TBL_RegistryRec_t *RegRecPtr;
  U32 NumPendingEvents;
  CFE_TBL_TxnEvent_t PendingEvents[CFE_TBL_MAX_EVENTS_PER_TXN];
  // A TRAILING PAD, and the second time this exact thing has been missed. PendingEvents ends
  // at 156 and the class carries pointers, so C rounds the whole thing to 160. Every member
  // offset matched without it -- a trailing pad is invisible to all of them and shows up only
  // in sizeof, which is what a memset of the transaction clears. CFE_TBL_Global_t's own
  // comment predicted this recurring; it did, four classes later.
  U8 _pad1[4];
};

// --- cfe_tbl_transaction.h's eight accessors ------------------------------------------------
// All eight are one field read. They exist in C so that the transaction struct can stay opaque
// to its callers; they are translated rather than inlined away for the reason
// cfe_es_resource.HC records, and tools/cfs/check_header_inlines.py requires the ones a gated
// source reaches.
U32 CFE_TBL_TxnHandle(CFE_TBL_TxnState_t *Txn)
{
  return Txn->Handle;
}

U64 CFE_TBL_TxnHandleAsULong(CFE_TBL_TxnState_t *Txn)
{
  return CFE_ResourceId_ToInteger(CFE_TBL_TxnHandle(Txn));
}

CFE_TBL_AccessDescriptor_t *CFE_TBL_TxnAccDesc(CFE_TBL_TxnState_t *Txn)
{
  return Txn->AccDescPtr;
}

U32 CFE_TBL_TxnRegId(CFE_TBL_TxnState_t *Txn)
{
  return Txn->RegId;
}

U64 CFE_TBL_TxnRegIdAsULong(CFE_TBL_TxnState_t *Txn)
{
  return CFE_ResourceId_ToInteger(CFE_TBL_TxnRegId(Txn));
}

CFE_TBL_RegistryRec_t *CFE_TBL_TxnRegRec(CFE_TBL_TxnState_t *Txn)
{
  return Txn->RegRecPtr;
}

U32 CFE_TBL_TxnAppId(CFE_TBL_TxnState_t *Txn)
{
  return Txn->AppId;
}

U64 CFE_TBL_TxnAppIdAsULong(CFE_TBL_TxnState_t *Txn)
{
  return CFE_ResourceId_ToInteger(CFE_TBL_TxnAppId(Txn));
}
#endif
