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

// 1:1 HolyC translation of cFE modules/resourceid/fsw/src/cfe_resourceid_api.c, with the
// types and inline helpers it needs from:
//   modules/resourceid/option_inc/cfe_resourceid_simple.h   CFE_ResourceId_t, WRAP/UNWRAP, MARK
//   modules/resourceid/fsw/inc/cfe_resourceid_basevalue.h   SHIFT, MAX, MAKE_BASE
//   modules/core_api/fsw/inc/cfe_resourceid_api_typedefs.h  UNDEFINED, RESERVED
//   modules/core_api/fsw/inc/cfe_resourceid.h               ToInteger/FromInteger/Equal/IsDefined
//   modules/core_api/fsw/inc/cfe_error.h                    the two status codes
//   modules/resourceid/fsw/src/cfe_resourceid_objtab.c      the registration entry
//
// WHY THIS MODULE NEXT. Every handle in cFE -- an app id, a task id, a pipe id, a table id -- is
// a resource id underneath, so this 195-line file is the floor that ES, SB, EVS and TBL all
// stand on. It is also self-contained: no OSAL, no PSP, nothing to stub.
//
// WHICH VARIANT, and this one is worth stating exactly rather than waving at. option_inc holds
// three mutually exclusive definitions of CFE_ResourceId_t, and the selection happens in
// modules/resourceid/mission_build.cmake:11-24: EDS wins if CFE_EDS_ENABLED, else STRICT if
// MISSION_RESOURCEID_MODE is "STRICT", else SIMPLE. In cmake/sample_defs that mode is not set
// by hand -- global_build_options.cmake:19-27 derives it from the OMIT_DEPRECATED environment
// variable, so a stock non-EDS build is SIMPLE unless OMIT_DEPRECATED is set. cFE's own CI runs
// it both ways. The chosen header is not copied; generate_config_includefile writes a one-line
// wrapper that #includes it under the name cfe_resourceid_typedef.h.
//
// This translates SIMPLE, where the id is a bare uint32 and WRAP/UNWRAP are the identity, so
// they leave no trace below. That is what vendor/shim/cfe_resourceid_typedef.h selects, which
// means the C side of the oracle is compiled against the same choice -- both sides describe one
// build. The STRICT variant wraps the uint32 in a struct and sets MARK to 0x02000000; it would
// reuse the opaque-type idiom already proven for CFE_SB_MsgId in cfe_sb_msgid.HC and would
// change the numbers here, not the logic.
#ifndef CFE_RESOURCEID_HC
#define CFE_RESOURCEID_HC
#include "cfe_msg_ccsdspri.HC"
#include "cfe_msg_objtab.HC"
#include "../CfsStr.HC"
// --- cfe_error.h ----------------------------------------------------------------------------
#define CFE_ES_ERR_RESOURCEID_NOT_VALID 0xC4000001(I32)
#define CFE_ES_BAD_ARGUMENT             0xC400000A(I32)
// --- cfe_resourceid_simple.h ----------------------------------------------------------------
// CFE_ResourceId_t is a plain uint32 in this variant, and CFE_RESOURCEID_WRAP/UNWRAP are the
// identity, so they leave no trace in the translation -- every place the C writes WRAP(x) or
// UNWRAP(x), the value is just x.
#define CFE_RESOURCEID_MARK 0
// --- osapi-idmap.h, via cfe_resourceid_basevalue.h -------------------------------------------
#define CFE_RESOURCEID_SHIFT 16     // OS_OBJECT_TYPE_SHIFT
#define CFE_RESOURCEID_MAX   0xFFFF // OS_OBJECT_INDEX_MASK
#define CFE_RESOURCEID_MAKE_BASE(offset) (CFE_RESOURCEID_MARK | ((offset) << CFE_RESOURCEID_SHIFT))
// --- cfe_resourceid_api_typedefs.h -----------------------------------------------------------
#define CFE_RESOURCEID_UNDEFINED 0
#define CFE_RESOURCEID_RESERVED  0xFFFFFFFF
// The C has a CompileTimeAssert here that CFE_RESOURCEID_MAX is one less than a power of two,
// because the same constant is used as a numeric limit AND as a bit mask. HolyC has no static
// assert, so the property is checked at runtime in the oracle instead of vanishing.
// --- cfe_resourceid.h, the inline helpers ----------------------------------------------------
// ToInteger returns `unsigned long`, which is 64-bit here, and that WIDTH IS LOAD-BEARING --
// see CFE_ResourceId_ToIndex below.
U64 CFE_ResourceId_ToInteger(U32 id)
{
  return id;
}

U32 CFE_ResourceId_FromInteger(U64 Value)
{
  return Value;
}

Bool CFE_ResourceId_Equal(U32 id1, U32 id2)
{
  return id1 == id2;
}

Bool CFE_ResourceId_IsDefined(U32 id)
{
  return !CFE_ResourceId_Equal(id, CFE_RESOURCEID_UNDEFINED);
}
// --- cfe_resourceid_api.c ---------------------------------------------------------------------
// State structure for use with CFE_ResourceId_DefaultIncrementSerial
class CFE_ResourceId_DefaultIncrementState
{
  U32 ResourceType;
  U32 TableSize;
  U32 RemainingCount;
};

// The C declares these two as typedef'd function pointers:
//   typedef CFE_ResourceId_t (*CFE_ResourceId_IncrementFunc_t)(CFE_ResourceId_t, void *);
//   typedef bool             (*CFE_ResourceId_CheckFunc_t)(CFE_ResourceId_t);
// HolyC has no typedef, so the pointer types are spelled out at each parameter.

// Forward declarations. The C gets these from cfe_resourceid.h, which every one of these files
// includes; HolyC is single-pass, so the header's job is done here explicitly. The definition
// order below is NASA's, unchanged.
U32 CFE_ResourceId_GetBase(U32 ResourceId);
U32 CFE_ResourceId_GetSerial(U32 ResourceId);
U32 CFE_ResourceId_FindNextEx(U32 StartId, U32 (*IncrFunc)(U32, U8 *), U8 *IncrArg,
                              Bool (*CheckFunc)(U32));

// Local helper routine, not invoked outside of this unit
// Default implementation of serial increment, treats all as equal
U32 CFE_ResourceId_DefaultIncrementSerial(U32 Id, U8 *Arg)
{
  CFE_ResourceId_DefaultIncrementState *State = Arg(CFE_ResourceId_DefaultIncrementState *);
  U32 Result;
  U32 Serial;
  if (State->RemainingCount == 0) {
    Result = CFE_RESOURCEID_UNDEFINED;
  } else {
    Serial = CFE_ResourceId_GetSerial(Id);
    ++Serial;
    if (Serial >= CFE_RESOURCEID_MAX)
      Serial %= State->TableSize;
    Result = CFE_ResourceId_FromInteger(State->ResourceType + Serial);
    --State->RemainingCount;
  }
  return Result;
}

U32 CFE_ResourceId_GetBase(U32 ResourceId)
{
  return CFE_ResourceId_ToInteger(ResourceId) & ~CFE_RESOURCEID_MAX;
}

U32 CFE_ResourceId_GetSerial(U32 ResourceId)
{
  return CFE_ResourceId_ToInteger(ResourceId) & CFE_RESOURCEID_MAX;
}

I32 CFE_ResourceId_ToIndex(U32 Id, U32 BaseValue, U32 TableSize, U32 *Idx)
{
  U32 Serial;
  if (Idx == NULL)
    return CFE_ES_BAD_ARGUMENT;
  // THE WIDTHS MATTER. ToInteger yields 64 bits, so an Id BELOW BaseValue makes this
  // subtraction a huge 64-bit number, and storing it into a uint32 wraps it -- which is what
  // puts it above CFE_RESOURCEID_MAX and gets it rejected on the next line. Do the arithmetic
  // in 64 bits and skip the narrowing and an out-of-range id quietly passes the check.
  Serial = CFE_ResourceId_ToInteger(Id) - BaseValue;
  if (Serial > CFE_RESOURCEID_MAX || TableSize == 0)
    return CFE_ES_ERR_RESOURCEID_NOT_VALID;
  *Idx = Serial % TableSize;
  return CFE_SUCCESS;
}

U32 CFE_ResourceId_FindNextEx(U32 StartId, U32 (*IncrFunc)(U32, U8 *), U8 *IncrArg,
                              Bool (*CheckFunc)(U32))
{
  U32 CheckId;
  if (CheckFunc == NULL || IncrFunc == NULL) {
    CheckId = CFE_RESOURCEID_UNDEFINED;
  } else {
    CheckId = StartId;
    do {
      CheckId = IncrFunc(CheckId, IncrArg);
      if (!CFE_ResourceId_IsDefined(CheckId))
        break;
    } while (CheckFunc(CheckId));
  }
  return CheckId;
}

U32 CFE_ResourceId_FindNext(U32 StartId, U32 TableSize, Bool (*CheckFunc)(U32))
{
  CFE_ResourceId_DefaultIncrementState State;
  MemSet(&State, 0, sizeof(CFE_ResourceId_DefaultIncrementState));
  State.ResourceType = CFE_ResourceId_GetBase(StartId);
  State.TableSize = TableSize;
  State.RemainingCount = TableSize;
  return CFE_ResourceId_FindNextEx(StartId, &CFE_ResourceId_DefaultIncrementSerial, &State,
                                   CheckFunc);
}
// --- cfe_resourceid_objtab.c ------------------------------------------------------------------
// this is a core library module with no task
Target_ObjectTable CFE_RESOURCEID_ModuleEntry = {"CFE_RESOURCEID", NULL, NULL, NULL, 0, 0};
#endif
