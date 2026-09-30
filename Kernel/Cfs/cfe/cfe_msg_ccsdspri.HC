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

// 1:1 HolyC translation of cFE modules/msg/fsw/src/cfe_msg_ccsdspri.c (and the two header-field
// helpers it uses from cfe_msg_priv.h). Derivative work; the notice above is retained as the
// Apache licence requires.
//
// TRANSLATION RULES APPLIED, so the next file can be done the same way:
//   uint8/uint16 -> U8/U16;  int32 / CFE_Status_t -> I32;  bool -> Bool
//   typedef struct X {...} X_t  ->  class X {...}          (HolyC has no typedef)
//   enum         -> #define                                 (HolyC has no enum)
//   static inline helper -> plain function
//   const on parameters -> dropped (HolyC has no const); the functions still do not write them
//   NULL checks, masks, shifts and the order of operations are preserved EXACTLY, because the
//   whole point is that the transcript matches byte for byte.
//
// Verified against the unmodified C by tests/scripts/run_cfs_xlat_smoke.sh, which runs both and
// diffs the output.
#ifndef CFE_MSG_CCSDSPRI_HC
#define CFE_MSG_CCSDSPRI_HC
#include "cfe_msg_defaults.HC"
// --- from cfe_error.h / cfe_msg_api_typedefs.h --------------------------------------------
#define CFE_SUCCESS               0
#define CFE_MSG_BAD_ARGUMENT      0xCA000003
#define CFE_MSG_Type_Invalid      0
#define CFE_MSG_Type_Cmd          1
#define CFE_MSG_Type_Tlm          2
#define CFE_MSG_SegFlag_Invalid     0
#define CFE_MSG_SegFlag_Continue    1
#define CFE_MSG_SegFlag_First       2
#define CFE_MSG_SegFlag_Last        3
#define CFE_MSG_SegFlag_Unsegmented 4
// --- CCSDS Primary Standard definitions (verbatim from the C) ------------------------------
#define CFE_MSG_SIZE_OFFSET    7
#define CFE_MSG_CCSDSVER_MASK  0xE000
#define CFE_MSG_CCSDSVER_SHIFT 13
#define CFE_MSG_TYPE_MASK      0x1000
#define CFE_MSG_SHDR_MASK      0x0800
#define CFE_MSG_APID_MASK      0x07FF
#define CFE_MSG_SEGFLG_MASK    0xC000
#define CFE_MSG_SEGFLG_CNT     0x0000
#define CFE_MSG_SEGFLG_FIRST   0x4000
#define CFE_MSG_SEGFLG_LAST    0x8000
#define CFE_MSG_SEGFLG_UNSEG   0xC000
#define CFE_MSG_SEQCNT_MASK    0x3FFF
// --- from ccsds_hdr.h and the pri-only cfe_msg_hdr.h ---------------------------------------
class CCSDS_PrimaryHeader
{
  U8 StreamId[2];
  U8 Sequence[2];
  U8 Length[2];
};

class CCSDS_SpacePacket
{
  CCSDS_PrimaryHeader Pri;
};

class CFE_MSG_Message
{
  CCSDS_SpacePacket CCSDS;
};
// --- from cfe_msg_priv.h -------------------------------------------------------------------
U0 CFE_MSG_GetHeaderField(U8 *Word, U16 *Val, U16 Mask)
{
  *Val = (Word[0] << 8 | Word[1]) & Mask;
}

U0 CFE_MSG_SetHeaderField(U8 *Word, U16 Val, U16 Mask)
{
  Word[0] = (Word[0] & ~(Mask >> 8)) | ((Val & Mask) >> 8);
  Word[1] = ((Word[1] & ~Mask) | (Val & Mask)) & 0xFF;
}
// --- cfe_msg_ccsdspri.c ---------------------------------------------------------------------
I32 CFE_MSG_GetHeaderVersion(CFE_MSG_Message *MsgPtr, U16 *Version)
{
  if (MsgPtr == NULL || Version == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  CFE_MSG_GetHeaderField(MsgPtr->CCSDS.Pri.StreamId, Version, CFE_MSG_CCSDSVER_MASK);
  *Version = *Version >> CFE_MSG_CCSDSVER_SHIFT;
  return CFE_SUCCESS;
}

I32 CFE_MSG_SetHeaderVersion(CFE_MSG_Message *MsgPtr, U16 Version)
{
  if (MsgPtr == NULL || Version > (CFE_MSG_CCSDSVER_MASK >> CFE_MSG_CCSDSVER_SHIFT))
    return CFE_MSG_BAD_ARGUMENT;
  CFE_MSG_SetHeaderField(MsgPtr->CCSDS.Pri.StreamId, Version << CFE_MSG_CCSDSVER_SHIFT,
                         CFE_MSG_CCSDSVER_MASK);
  return CFE_SUCCESS;
}

I32 CFE_MSG_GetType(CFE_MSG_Message *MsgPtr, I64 *Type)
{
  if (MsgPtr == NULL || Type == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  if ((MsgPtr->CCSDS.Pri.StreamId[0] & (CFE_MSG_TYPE_MASK >> 8)) != 0)
    *Type = CFE_MSG_Type_Cmd;
  else
    *Type = CFE_MSG_Type_Tlm;
  return CFE_SUCCESS;
}

I32 CFE_MSG_SetType(CFE_MSG_Message *MsgPtr, I64 Type)
{
  I32 status = CFE_SUCCESS;
  if (MsgPtr == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  if (Type == CFE_MSG_Type_Cmd)
    MsgPtr->CCSDS.Pri.StreamId[0] = MsgPtr->CCSDS.Pri.StreamId[0] | (CFE_MSG_TYPE_MASK >> 8);
  else if (Type == CFE_MSG_Type_Tlm)
    MsgPtr->CCSDS.Pri.StreamId[0] = MsgPtr->CCSDS.Pri.StreamId[0] & ~(CFE_MSG_TYPE_MASK >> 8);
  else
    status = CFE_MSG_BAD_ARGUMENT;
  return status;
}

I32 CFE_MSG_GetHasSecondaryHeader(CFE_MSG_Message *MsgPtr, Bool *HasSecondary)
{
  if (MsgPtr == NULL || HasSecondary == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  *HasSecondary = (MsgPtr->CCSDS.Pri.StreamId[0] & (CFE_MSG_SHDR_MASK >> 8)) != 0;
  return CFE_SUCCESS;
}

I32 CFE_MSG_SetHasSecondaryHeader(CFE_MSG_Message *MsgPtr, Bool HasSecondary)
{
  if (MsgPtr == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  if (HasSecondary)
    MsgPtr->CCSDS.Pri.StreamId[0] = MsgPtr->CCSDS.Pri.StreamId[0] | (CFE_MSG_SHDR_MASK >> 8);
  else
    MsgPtr->CCSDS.Pri.StreamId[0] = MsgPtr->CCSDS.Pri.StreamId[0] & ~(CFE_MSG_SHDR_MASK >> 8);
  return CFE_SUCCESS;
}

I32 CFE_MSG_GetApId(CFE_MSG_Message *MsgPtr, U16 *ApId)
{
  if (MsgPtr == NULL || ApId == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  CFE_MSG_GetHeaderField(MsgPtr->CCSDS.Pri.StreamId, ApId, CFE_MSG_APID_MASK);
  return CFE_SUCCESS;
}

I32 CFE_MSG_SetApId(CFE_MSG_Message *MsgPtr, U16 ApId)
{
  if (MsgPtr == NULL || ApId > CFE_MSG_APID_MASK)
    return CFE_MSG_BAD_ARGUMENT;
  CFE_MSG_SetHeaderField(MsgPtr->CCSDS.Pri.StreamId, ApId, CFE_MSG_APID_MASK);
  return CFE_SUCCESS;
}

I32 CFE_MSG_GetSegmentationFlag(CFE_MSG_Message *MsgPtr, I64 *SegFlag)
{
  U16 rawval;
  I32 status = CFE_SUCCESS;
  if (MsgPtr == NULL || SegFlag == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  CFE_MSG_GetHeaderField(MsgPtr->CCSDS.Pri.Sequence, &rawval, CFE_MSG_SEGFLG_MASK);
  // The original is a switch whose UNSEG case falls together with default; this chain is
  // equivalent, and HolyC switch does fall through like C so the shape could have been kept.
  if (rawval == CFE_MSG_SEGFLG_CNT)
    *SegFlag = CFE_MSG_SegFlag_Continue;
  else if (rawval == CFE_MSG_SEGFLG_FIRST)
    *SegFlag = CFE_MSG_SegFlag_First;
  else if (rawval == CFE_MSG_SEGFLG_LAST)
    *SegFlag = CFE_MSG_SegFlag_Last;
  else
    *SegFlag = CFE_MSG_SegFlag_Unsegmented;
  return status;
}

I32 CFE_MSG_SetSegmentationFlag(CFE_MSG_Message *MsgPtr, I64 SegFlag)
{
  I32 status = CFE_SUCCESS;
  if (MsgPtr == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  if (SegFlag == CFE_MSG_SegFlag_Continue)
    CFE_MSG_SetHeaderField(MsgPtr->CCSDS.Pri.Sequence, CFE_MSG_SEGFLG_CNT, CFE_MSG_SEGFLG_MASK);
  else if (SegFlag == CFE_MSG_SegFlag_First)
    CFE_MSG_SetHeaderField(MsgPtr->CCSDS.Pri.Sequence, CFE_MSG_SEGFLG_FIRST, CFE_MSG_SEGFLG_MASK);
  else if (SegFlag == CFE_MSG_SegFlag_Last)
    CFE_MSG_SetHeaderField(MsgPtr->CCSDS.Pri.Sequence, CFE_MSG_SEGFLG_LAST, CFE_MSG_SEGFLG_MASK);
  else if (SegFlag == CFE_MSG_SegFlag_Unsegmented)
    CFE_MSG_SetHeaderField(MsgPtr->CCSDS.Pri.Sequence, CFE_MSG_SEGFLG_UNSEG, CFE_MSG_SEGFLG_MASK);
  else
    status = CFE_MSG_BAD_ARGUMENT;
  return status;
}

I32 CFE_MSG_GetSequenceCount(CFE_MSG_Message *MsgPtr, U16 *SeqCnt)
{
  if (MsgPtr == NULL || SeqCnt == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  CFE_MSG_GetHeaderField(MsgPtr->CCSDS.Pri.Sequence, SeqCnt, CFE_MSG_SEQCNT_MASK);
  return CFE_SUCCESS;
}

I32 CFE_MSG_SetSequenceCount(CFE_MSG_Message *MsgPtr, U16 SeqCnt)
{
  if (MsgPtr == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  CFE_MSG_SetHeaderField(MsgPtr->CCSDS.Pri.Sequence, SeqCnt, CFE_MSG_SEQCNT_MASK);
  return CFE_SUCCESS;
}

// NOTE: these two do NOT use the header-field helpers in the original -- they index Length[]
// directly. The first draft of this translation wrote them from the surrounding pattern instead
// of from the source and got both the arithmetic and the bounds wrong. Translate what is there.
I32 CFE_MSG_GetSize(CFE_MSG_Message *MsgPtr, I64 *Size)
{
  if (MsgPtr == NULL || Size == NULL)
    return CFE_MSG_BAD_ARGUMENT;
  *Size = (MsgPtr->CCSDS.Pri.Length[0] << 8) + MsgPtr->CCSDS.Pri.Length[1] + CFE_MSG_SIZE_OFFSET;
  return CFE_SUCCESS;
}

I32 CFE_MSG_SetSize(CFE_MSG_Message *MsgPtr, I64 Size)
{
  if (MsgPtr == NULL || Size < CFE_MSG_SIZE_OFFSET || Size > (0xFFFF + CFE_MSG_SIZE_OFFSET))
    return CFE_MSG_BAD_ARGUMENT;
  Size -= CFE_MSG_SIZE_OFFSET;
  MsgPtr->CCSDS.Pri.Length[0] = (Size >> 8) & 0xFF;
  MsgPtr->CCSDS.Pri.Length[1] = Size & 0xFF;
  return CFE_SUCCESS;
}

// The last function in the same C file. It is declared in cfe_msg_defaults.h rather than in the
// public API because it is module-internal.
U0 CFE_MSG_SetDefaultCCSDSPri(CFE_MSG_Message *MsgPtr)
{
  // cFS standard for CCSDS Version
  CFE_MSG_SetHeaderVersion(MsgPtr, CFE_MISSION_CCSDSVER);
  // Default bits of the APID, for whatever isn't set by MsgId
  CFE_MSG_SetApId(MsgPtr, CFE_PLATFORM_DEFAULT_APID);
  // Default to complete packets
  CFE_MSG_SetSegmentationFlag(MsgPtr, CFE_MSG_SegFlag_Unsegmented);
}
#endif
