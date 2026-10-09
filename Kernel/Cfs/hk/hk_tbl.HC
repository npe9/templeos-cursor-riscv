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
// HOUSEKEEPING'S TWO TABLES -- the 1:1 translation of NASA's config/default_hk_tbldefs.h plus the
// flag constants from fsw/src/hk_utils.h that only mean anything against them.
//
// HK's whole job is in these two 16-byte structures. The COPY table is the ground's instruction
// set -- "take NumBytes from offset InputOffset of packet InputMid and put them at OutputOffset
// of packet OutputMid" -- and the RUNTIME table is HK's bookkeeping for it, one entry parallel to
// each copy entry.
//
// ### THE RUNTIME TABLE HOLDS A REAL POINTER AND IS DUMPED TO THE GROUND
//
// `OutputPktAddr` is the address of a buffer HK got from its own memory pool, and
// CFE_ES_MemAddress_t is **uint64** in this configuration (cFE ships a 32-bit variant that masks
// with 0xFFFFFFFF; this build uses the 64-bit one, so nothing is truncated). The runtime table is
// registered CFE_TBL_OPT_DUMP_ONLY and HK_CheckStatusOfDumpTable dumps it on request -- so a
// ground operator reads HK's heap addresses.
//
// THAT MATTERS FOR THE DIFFERENTIAL AND NOT FOR THE TRANSLATION: a host pointer and a QEMU guest
// pointer are never the same number, so the exercise can never PRINT this field. Every assertion
// about it below is either NULL-versus-not-NULL or a comparison against an address the driver
// itself handed over -- the same rule CS's results tables established.
//
// ### THE FLAG VALUES ARE ASYMMETRIC AND NASA'S COMMENTS ON TWO OF THEM ARE SWAPPED
//
//     HK_INPUTMID_SUBSCRIBED     0xFF        HK_DATA_NOT_PRESENT  0
//     HK_INPUTMID_NOT_SUBSCRIBED 0           HK_DATA_PRESENT      1
//
// One pair uses 0xFF for the set state and the other uses 1, in the same structure, in adjacent
// bytes. Both are kept exactly: HK_ProcessNewCopyTable writes 0xFF and HK_ProcessIncomingHkData
// writes 1, and a translation that harmonised them would make HK_CheckForMissingData -- which
// tests `DataPresent == HK_DATA_NOT_PRESENT` -- read a subscribed-but-empty entry as having data.
//
// AND NASA'S TWO DOC COMMENTS ARE THE WRONG WAY ROUND. hk_utils.h reads
//
//     #define HK_DATA_NOT_PRESENT (0) /**< \brief Input MsgId present in output msg */
//     #define HK_DATA_PRESENT     (1) /**< \brief Input MsgId not present */
//
// -- NOT_PRESENT documented as "present" and PRESENT as "not present". The VALUES are right and
// used correctly everywhere; only the two comments are transposed. Upstream, harmless, and
// recorded because a reader who trusts the comment over the name gets the logic backwards.
#ifndef HK_TBL_HC
#define HK_TBL_HC

/*******************************************************************************/
// One copy instruction. 16 bytes.
//
// NASA DECLARES NO PADDING MEMBER AND C INSERTS TWO BYTES. InputMid is a 4-byte CFE_SB_MsgId and
// InputOffset is 2, so OutputMid's 4-byte alignment forces a 2-byte hole after InputOffset. The
// `_pad0[2]` is this translation's and is marked as such; everything else is NASA's.
class HK_CopyTableEntry_t
{
  CFE_SB_MsgId InputMid; // MsgId of the input packet
  U16 InputOffset;       // byte offset into the input packet where the copy begins
  U8 _pad0[2];           // C aligns the 4-byte OutputMid that follows
  CFE_SB_MsgId OutputMid; // MsgId of the output packet
  U16 OutputOffset;      // byte offset into the output packet where the data is placed
  U16 NumBytes;          // number of bytes to copy from input to output
};

/*******************************************************************************/
// HK's bookkeeping for one copy instruction. 16 bytes, and SIX of them are padding.
//
// Three fields and ten bytes of hole: an 8-byte address, two single bytes, and then C pads the
// tail to the address's alignment. NASA declares none of it. That is worth stating because the
// runtime table is DUMPED -- 128 entries of 16 bytes, 768 of those 2,048 bytes being padding a
// ground decoder must skip.
class HK_RuntimeTableEntry_t
{
  U64 OutputPktAddr; // CFE_ES_MemAddress_t -- address of the output packet, from HK's pool
  U8 InputMidSubscribed;           // HK_INPUTMID_SUBSCRIBED or HK_INPUTMID_NOT_SUBSCRIBED
  U8 DataPresent;                  // HK_DATA_PRESENT or HK_DATA_NOT_PRESENT
  U8 _pad0[6];                     // C pads the tail to the address's 8-byte alignment
};

// --- hk_utils.h's flag and status constants -------------------------------------------------
#define HK_INPUTMID_SUBSCRIBED     0xFF
#define HK_INPUTMID_NOT_SUBSCRIBED 0
// The two comments NASA transposed; the names are the truth. See the block comment above.
#define HK_DATA_NOT_PRESENT        0
#define HK_DATA_PRESENT            1
#define HK_NO_MISSING_DATA         0
#define HK_MISSING_DATA_DETECTED   1
#define HK_NULL_POINTER_DETECTED   -1

#endif
