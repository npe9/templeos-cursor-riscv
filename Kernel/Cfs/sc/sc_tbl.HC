/************************************************************************
 * NASA Docket No. GSC-18,924-1, and identified as "Core Flight
 * System (cFS) Stored Command Application (SC)"
 *
 * Copyright (c) 2021 United States Government as represented by the
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
// STORED COMMAND'S TABLE TYPES AND ITS INDEX ALGEBRA -- the 1:1 translation of NASA's
// config/default_sc_extern_typedefs.h, config/default_sc_tbldefs.h,
// config/default_sc_tblstruct.h and fsw/src/sc_index_types.h.
//
// ### SC DISTINGUISHES A **NUMBER** FROM AN **INDEX**, AND THE WHOLE APP TURNS ON IT
//
// An ATS is "ATS 1" or "ATS 2" to the ground and index 0 or 1 to the code. SC gives the two ideas
// SEPARATE TYPES -- `SC_AtsNum_t` and `SC_AtsIndex_t`, both `uint16` -- and six converter
// functions that are nothing but `-1` and `+1`:
//
//     SC_AtsNumToIndex(n)      n - 1        SC_AtsIndexToNum(i)      i + 1
//     SC_RtsNumToIndex(n)      n - 1        SC_RtsIndexToNum(i)      i + 1
//     SC_CommandNumToIndex(n)  n - 1        SC_CommandIndexToNum(i)  i + 1
//
// **IN C THAT DISCIPLINE IS A COMMENT, NOT A CHECK.** Both are `uint16` typedefs, so passing a
// number where an index belongs compiles silently, and NASA's own `SC_AtsNumIsValid` exists
// precisely because an off-by-one here aims at the wrong sequence. The translation cannot even
// express the distinction -- HolyC has no typedef, so both are `U16` -- which means the TYPE NAMES
// in NASA's signatures are the only surviving record of which is which. They are preserved in the
// parameter comments on every function below and in every translated source, because once they are
// gone nothing distinguishes `SC_GetAtsEntryAtOffset(AtsNum, ...)` from the correct call.
//
// AND THE NULL VALUES ARE **ZERO FOR A NUMBER** AND **0xFFFF FOR AN INDEX**: `SC_ATS_NUM_NULL` is
// 0 (because numbering starts at 1, so 0 cannot be a real ATS) while `SC_ENTRY_OFFSET_INVALID` is
// `(uint16)(-1)`. Two sentinels, opposite ends of the range, in the same arithmetic.
//
// ### `SC_EntryOffsetAdvance` IS WHERE BYTES BECOME WORDS, AND IT ROUNDS UP
//
//     Pos + ((Bytes + sizeof(uint32) - 1) / sizeof(uint32))
//
// One expression, and it is the only place in SC that converts a command's BYTE length into an
// offset step. The `+3)/4` is a deliberate round-up to a whole 32-bit word -- so a 10-byte command
// advances the offset by 3 words, wasting two bytes, and SC's buffers are therefore never exactly
// full. See sc_cfg.HC for the three units involved.
//
// ### EVERY STRUCT LAYOUT BELOW WAS READ OUT OF THE C WITH `offsetof`
//
// Not derived from the field list. `SC_AtpControlBlock_t` is why: it has a 1-byte status at offset
// 0 and a `uint16` at offset 2, so there is a **compiler hole at offset 1** -- and NASA ALSO
// declares its own `Padding` field at offset 4. One structure, two holes, one of them upstream's
// and one the compiler's, and only a measurement tells them apart. check_padding compares the
// result against NASA's byte for byte.
#ifndef SC_TBL_HC
#define SC_TBL_HC

#include "sc_cfg.HC"

// --- config/default_sc_extern_typedefs.h: the execution-state enum --------------------------
//
// NASA writes `enum SC_Status { ... }` with a `typedef uint8 SC_Status_Enum_t`. HolyC has neither,
// so the members become defines and the type becomes U8 at every use.
#define SC_Status_EMPTY           0
#define SC_Status_LOADED          1
#define SC_Status_IDLE            2
#define SC_Status_EXECUTED        3
#define SC_Status_SKIPPED         4
#define SC_Status_EXECUTING       5
#define SC_Status_FAILED_CHECKSUM 6
#define SC_Status_FAILED_DISTRIB  7
#define SC_Status_STARTING        8

// THE NINE DEPRECATED ALIASES, AND THEY ARE LIVE IN THIS CONFIGURATION. NASA guards them with
// `#ifndef SC_OMIT_DEPRECATED`, and **SC_OMIT_DEPRECATED is defined nowhere in SC's tree** --
// checked with a grep over every file, not assumed from the name. So all nine exist, and
// check_defines would report them missing if they were left out. They are not used by SC's own
// sources; they are the old spellings a mission's code may still carry.
#define SC_EMPTY           SC_Status_EMPTY
#define SC_LOADED          SC_Status_LOADED
#define SC_IDLE            SC_Status_IDLE
#define SC_EXECUTED        SC_Status_EXECUTED
#define SC_SKIPPED         SC_Status_SKIPPED
#define SC_EXECUTING       SC_Status_EXECUTING
#define SC_FAILED_CHECKSUM SC_Status_FAILED_CHECKSUM
#define SC_FAILED_DISTRIB  SC_Status_FAILED_DISTRIB
#define SC_STARTING        SC_Status_STARTING

// --- the number and index types ----------------------------------------------------------------
//
// `SC_RtsNum_t`, `SC_AtsNum_t`, `SC_CommandNum_t` and `SC_EntryOffset_t` are all `uint16`;
// `SC_AbsTimeTag_t` and `SC_RelWakeupCount_t` are `uint32`; `SC_SeqIndex_t` is `uint16`. HolyC has
// no typedef, so every one is written as its underlying width at the point of use and the NAME
// survives only in comments -- see the file header on why that matters here more than usual.
//
//   SC_AbsTimeTag_t      U32    an absolute time in seconds
//   SC_RelWakeupCount_t  U32    a count of SC wakeups, not seconds
//   SC_SeqIndex_t        U16    an index into the time-sorted command list
//   SC_RtsNum_t          U16    1 .. SC_NUMBER_OF_RTS
//   SC_AtsNum_t          U16    1 .. SC_NUMBER_OF_ATS
//   SC_CommandNum_t      U16    1 .. SC_MAX_ATS_CMDS
//   SC_EntryOffset_t     U16    a 32-BIT-WORD offset into an ATS or RTS buffer
//   SC_RtsIndex_t        U16    0 .. SC_NUMBER_OF_RTS-1
//   SC_AtsIndex_t        U16    0 .. SC_NUMBER_OF_ATS-1
//   SC_CommandIndex_t    U16    0 .. SC_MAX_ATS_CMDS-1

// Function-like macros, kept as macros. HolyC HAS them -- lc_cmds.HC carries NASA's
// LC_GET_CMD_PAYLOAD unchanged, which is the counter-example to the claim that it does not.
//
// ### **THE TWO WIDENING MACROS CANNOT BE WRITTEN AS CASTS, AND THE FIRST VERSION WAS**
//
// NASA's are `((unsigned int)(arg))` and `((uint16)(arg))`. HolyC's cast is a postfix RELABEL, so
// the obvious translation of the first is `(arg)(U32)` -- and **that widens the LOAD instead of
// converting the value**. For a `U16` lvalue whose neighbouring halfword is non-zero it reads
// FOUR bytes and returns both:
//
//     Offset = 0xFFFF (SC_ENTRY_OFFSET_INVALID), next record's Offset also 0xFFFF
//     (Offset)(U32)   ==>  4294967295       // two records read as one word
//     Offset & 0xFFFF ==>  65535            // C's answer
//
// That shipped in five gated SC sources -- 36 uses of SC_IDX_AS_UINT and 47 of
// SC_IDNUM_AS_UINT -- and every static gate was green, because the two macros are TEXTUALLY
// faithful to NASA's and the defect is in what the compiler does with them. It was found the
// first time SC ran: the exercise printed four consecutive `SC_ENTRY_OFFSET_INVALID` offsets and
// the C half said 65535 where the HolyC half said 4294967295.
//
// **A LOCAL IS WORSE THAN A MEMBER**: a stack slot's neighbour is whatever the frame put there,
// so `(loc)(U32)` of a U16 local is not merely wrong but unpredictable from the source --
// measured at 2155937791 for a 0xFFFF local. tests/exec/cases/e_widening_cast_lvalue.hc pins all
// three forms, the U8 case, the three SAFE spellings, and the narrowing direction.
//
// So the widening macros use `& 0xFFFF`, which forces a load of the declared width and is exactly
// value-equivalent for a uint16 source -- NASA's argument is always one of the index typedefs,
// all of which are uint16 (sc_index_types.h, default_sc_extern_typedefs.h). The FROM_UINT
// direction keeps its cast: relabelling a wider lvalue as U16 reads the LOW halfword, which on
// this little-endian target is the truncation C performs, and the same exec case pins it.
#define SC_IDNUM_AS_UINT(arg)   ((arg) & 0xFFFF)
#define SC_IDNUM_FROM_UINT(arg) ((arg)(U16))
#define SC_IDX_AS_UINT(arg)     ((arg) & 0xFFFF)
#define SC_IDX_FROM_UINT(arg)   ((arg)(U16))
#define SC_IDX_INCREMENT(arg)   (++(arg))
#define SC_IDX_DECREMENT(arg)   (--(arg))
// 'A' + index -- so ATS 1 prints as "A" and ATS 2 as "B". The only place SC turns a number into
// a letter, and it appears in event text.
#define SC_IDX_AS_CHAR(arg)           (('A' + SC_IDX_AS_UINT(arg))(U8))
#define SC_IDNUM_EQUAL(arg1, arg2)    (SC_IDNUM_AS_UINT(arg1) == SC_IDNUM_AS_UINT(arg2))
#define SC_IDNUM_IS_NULL(arg)         (SC_IDNUM_AS_UINT(arg) == 0)
#define SC_IDX_EQUAL(arg1, arg2)      (SC_IDX_AS_UINT(arg1) == SC_IDX_AS_UINT(arg2))
#define SC_IDX_LESS_OR_EQ(arg1, arg2) (SC_IDX_AS_UINT(arg1) <= SC_IDX_AS_UINT(arg2))
#define SC_IDX_WITHIN_LIMIT(arg, lim) (SC_IDX_AS_UINT(arg) < (lim))

#define SC_RTS_NUM_INITIALIZER(i)     SC_IDNUM_FROM_UINT(i)
#define SC_ATS_NUM_INITIALIZER(i)     SC_IDNUM_FROM_UINT(i)
#define SC_COMMAND_NUM_INITIALIZER(i) SC_IDNUM_FROM_UINT(i)

#define SC_RTS_NUM_C(i)     (SC_IDNUM_FROM_UINT(i))
#define SC_ATS_NUM_C(i)     (SC_IDNUM_FROM_UINT(i))
#define SC_COMMAND_NUM_C(i) (SC_IDNUM_FROM_UINT(i))
// ZERO, because numbering starts at 1 -- the opposite sentinel from the index ones below.
#define SC_RTS_NUM_NULL     SC_RTS_NUM_C(0)
#define SC_ATS_NUM_NULL     SC_ATS_NUM_C(0)
#define SC_COMMAND_NUM_NULL SC_COMMAND_NUM_C(0)

#define SC_COMMAND_IDX_C(i)  (SC_IDX_FROM_UINT(i))
#define SC_RTS_IDX_C(i)      (SC_IDX_FROM_UINT(i))
#define SC_ATS_IDX_C(i)      (SC_IDX_FROM_UINT(i))
#define SC_SEQUENCE_IDX_C(i) (SC_IDX_FROM_UINT(i))
#define SC_ENTRY_OFFSET_C(i) (SC_IDX_FROM_UINT(i))
#define SC_SEQUENCE_IDX_FIRST SC_SEQUENCE_IDX_C(0)
// 0xFFFF -- `(uint16)(-1)`. The HolyC (U16) cast MASKS (docs/HOLYC_IMPLEMENTATION_STATUS.md), so
// -1 becomes 65535 here exactly as it does in C.
#define SC_SEQUENCE_IDX_INVALID SC_SEQUENCE_IDX_C(-1)
#define SC_ENTRY_OFFSET_FIRST   SC_ENTRY_OFFSET_C(0)
#define SC_ENTRY_OFFSET_INVALID SC_ENTRY_OFFSET_C(-1)

/*******************************************************************************/
// --- fsw/src/sc_index_types.h's `static inline`s, translated as functions ---------------------
//
// A header `static inline` is part of every caller, so check_header_inlines owns these and
// requires each one to exist by name. Each is NASA's body with the casts respelled.

// ATS number (1-based) -> ATS index (0-based).
U16 SC_AtsNumToIndex(U16 AtsNum)
{
  return SC_IDX_FROM_UINT(SC_IDNUM_AS_UINT(AtsNum) - 1);
}

// ATS index (0-based) -> ATS number (1-based).
U16 SC_AtsIndexToNum(U16 AtsIndex)
{
  return SC_IDNUM_FROM_UINT(SC_IDX_AS_UINT(AtsIndex) + 1);
}

U16 SC_RtsNumToIndex(U16 RtsNum)
{
  return SC_IDX_FROM_UINT(SC_IDNUM_AS_UINT(RtsNum) - 1);
}

U16 SC_RtsIndexToNum(U16 RtsIndex)
{
  return SC_IDNUM_FROM_UINT(SC_IDX_AS_UINT(RtsIndex) + 1);
}

U16 SC_CommandNumToIndex(U16 CommandNum)
{
  return SC_IDX_FROM_UINT(SC_IDNUM_AS_UINT(CommandNum) - 1);
}

U16 SC_CommandIndexToNum(U16 CommandIndex)
{
  return SC_IDNUM_FROM_UINT(SC_IDX_AS_UINT(CommandIndex) + 1);
}

// **NOTE WHICH SENTINEL REACHES THESE.** `SC_AtsNumToIndex(0)` is `(uint16)(0 - 1)` = 65535, and
// 65535 is not within SC_NUMBER_OF_ATS -- so validating the NULL number answers false through the
// index check rather than through a test for zero. That is why SC_AtsNumIsValid is written as a
// call to SC_AtsIndexIsValid and not as its own comparison.
Bool SC_AtsIndexIsValid(U16 AtsIndex)
{
  return SC_IDX_WITHIN_LIMIT(AtsIndex, SC_NUMBER_OF_ATS);
}

Bool SC_AtsNumIsValid(U16 AtsNum)
{
  return SC_AtsIndexIsValid(SC_AtsNumToIndex(AtsNum));
}

Bool SC_RtsIndexIsValid(U16 RtsIndex)
{
  return SC_IDX_WITHIN_LIMIT(RtsIndex, SC_NUMBER_OF_RTS);
}

Bool SC_RtsNumIsValid(U16 RtsNum)
{
  return SC_RtsIndexIsValid(SC_RtsNumToIndex(RtsNum));
}

Bool SC_AtsCommandIndexIsValid(U16 CommandIndex)
{
  return SC_IDX_WITHIN_LIMIT(CommandIndex, SC_MAX_ATS_CMDS);
}

Bool SC_AtsCommandNumIsValid(U16 CommandNum)
{
  return SC_AtsCommandIndexIsValid(SC_CommandNumToIndex(CommandNum));
}

// WHETHER THIS RTS ANNOUNCES ITSELF. RTS index 0..SC_LAST_RTS_WITH_EVENTS-1 report their start and
// stop by event; the rest are silent. With SC_LAST_RTS_WITH_EVENTS = 3 and SC_NUMBER_OF_RTS = 4,
// exactly ONE of the four RTSs is quiet -- see sc_cfg.HC.
Bool SC_RtsIndexHasEvent(U16 RtsIndex)
{
  return SC_IDX_WITHIN_LIMIT(RtsIndex, SC_LAST_RTS_WITH_EVENTS);
}

Bool SC_RtsNumHasEvent(U16 RtsNum)
{
  return SC_RtsIndexHasEvent(SC_RtsNumToIndex(RtsNum));
}

// `<=`, NOT `<` -- a range of RTS numbers is INCLUSIVE at both ends, so "RTS 2 through 2" is one
// RTS and not none.
Bool SC_RtsNumWithinRange(U16 RtsNum, U16 IdLimit)
{
  return SC_IDNUM_AS_UINT(RtsNum) <= SC_IDNUM_AS_UINT(IdLimit);
}

Bool SC_RtsNumValidateRange(U16 FirstRtsNum, U16 LastRtsNum)
{
  return SC_RtsNumIsValid(FirstRtsNum) && SC_RtsNumIsValid(LastRtsNum) &&
         SC_RtsNumWithinRange(FirstRtsNum, LastRtsNum);
}

// BYTES IN, A 32-BIT-WORD OFFSET OUT, ROUNDED UP. The only such conversion in SC -- see the file
// header. NASA writes the result as a compound literal `(SC_EntryOffset_t){...}` on a scalar
// typedef, which is legal C and has no HolyC spelling; the arithmetic is identical without it.
U16 SC_EntryOffsetAdvance(U16 Pos, I64 Bytes)
{
  return SC_IDX_AS_UINT(Pos) + (Bytes + sizeof(U32) - 1) / sizeof(U32);
}

// --- config/default_sc_tbl.h's constants ------------------------------------------------------
//
// ALSO FOUND BY check_defines RATHER THAN BY READING -- default_sc_tbl.h is another thin header
// that includes the others and adds ten constants, and it was missed. See sc_msg.HC's note.
//
// **THE TWO HEADER SIZES ARE `offsetof` IN A MACRO**, which HolyC has no spelling for:
//
//     #define SC_ATS_HEADER_SIZE (offsetof(SC_AtsEntry_t, Msg))
//     #define SC_RTS_HEADER_SIZE (offsetof(SC_RtsEntry_t, Msg))
//
// So they are written out as the numbers the C produces -- 8 and 4, read out of a probe and NOT
// computed from the field list. That makes them the one pair of constants in SC whose correctness
// depends on check_padding: if SC_AtsEntry_t's layout ever moved, NASA's macro would follow it and
// this constant would not. The dependency is stated here because nothing else records it.
#define SC_ATS_HEADER_SIZE 8
#define SC_RTS_HEADER_SIZE 4

// THE EIGHT TABLE IDS, AND THEY ARE A CHAIN. NASA defines each as the previous one plus a count,
// so the whole block shifts if SC_NUMBER_OF_ATS or SC_NUMBER_OF_RTS changes:
//
//     ATS_0     1                              ATS 1 and ATS 2 take ids 1 and 2
//     APPEND    ATS_0 + SC_NUMBER_OF_ATS  = 3
//     RTS_0     APPEND + 1                = 4  RTS 1..4 take ids 4,5,6,7
//     RTS_INFO  RTS_0 + SC_NUMBER_OF_RTS  = 8
//     RTP_CTRL  RTS_INFO + 1              = 9
//     ATS_INFO  RTP_CTRL + 1              = 10
//     ATP_CTRL  ATS_INFO + 1              = 11
//     ATS_CMD_0 ATP_CTRL + 1              = 12
//
// **THE EXPRESSIONS ARE KEPT, NOT FOLDED.** Folding them to 1,3,4,8,9,10,11,12 would be correct
// for this configuration and would hide that `SC_TBL_ID_RTS_INFO` is only 8 because there are
// four RTSs -- which is the kind of configuration-dependent constant docs/ records being wrong
// four times in MM's prefix list. The values in the table above were measured with a probe, as a
// cross-check on the arithmetic.
//
// **AND KEEPING THEM COSTS A GATE: check_constants reports these seven as "not a plain literal,
// so the value is not compared here".** It compares literals, and these are expressions -- so
// seven of SC's constants are verified by the measurement recorded above and by nothing that
// re-runs. The alternative, folding them to literals, would buy the gate and lose the
// configuration dependence, which is the worse trade for a chain whose whole point is that it
// shifts. SC's exercise prints all eight table ids so the differential pins them, and that is
// where the standing check lives.
#define SC_TBL_ID_ATS_0     1
#define SC_TBL_ID_APPEND    (SC_TBL_ID_ATS_0 + SC_NUMBER_OF_ATS)
#define SC_TBL_ID_RTS_0     (SC_TBL_ID_APPEND + 1)
#define SC_TBL_ID_RTS_INFO  (SC_TBL_ID_RTS_0 + SC_NUMBER_OF_RTS)
#define SC_TBL_ID_RTP_CTRL  (SC_TBL_ID_RTS_INFO + 1)
#define SC_TBL_ID_ATS_INFO  (SC_TBL_ID_RTP_CTRL + 1)
#define SC_TBL_ID_ATP_CTRL  (SC_TBL_ID_ATS_INFO + 1)
#define SC_TBL_ID_ATS_CMD_0 (SC_TBL_ID_ATP_CTRL + 1)

/*******************************************************************************/
// --- config/default_sc_tbldefs.h: the on-the-wire entry shapes -------------------------------
//
// Offsets in the right margin were read out of the C with offsetof -- see the file header.

// AN ATS COMMAND'S HEADER. 8 bytes, and the PAD IS FIRST: NASA puts a two-byte `Pad` at offset 0
// so that the command message which follows the header lands on a 4-byte boundary once the
// 8-byte header is accounted for.
//
// AND THE TIME TAG IS SPLIT INTO TWO 16-BIT HALVES rather than stored as a uint32. That is not
// alignment -- the struct is only 2-byte aligned -- it is because an ATS buffer is a stream of
// 16-bit words uploaded from the ground, and a 32-bit field would have imposed an alignment the
// stream cannot promise. sc_utils.c reassembles them.
class SC_AtsEntryHeader_t
{
  U16 Pad;        // NASA's own structure padding                              offset 0
  U16 CmdNumber;  // SC_CommandNum_t -- 1 .. SC_MAX_ATS_CMDS                   offset 2
  U16 TimeTag_MS; // the time tag's most significant 16 bits                   offset 4
  U16 TimeTag_LS; // and its least significant 16 bits                         offset 6
};

// 16 bytes: an 8-byte header and an 8-byte command header. **THE REAL ENTRY IS LONGER THAN THIS
// TYPE** -- the command's payload follows `Msg` in the buffer and is not described by any
// structure, which is what makes SC's entries variable length and why every access goes through
// an offset rather than an array index.
class SC_AtsEntry_t
{
  SC_AtsEntryHeader_t Header; // ATS header                                    offset 0
  CFE_MSG_CommandHeader Msg;  // command message to be sent                    offset 8
};

// AN RTS COMMAND'S HEADER. 4 bytes, ONE FIELD, AND IT IS A WAKEUP COUNT AND NOT A TIME. An RTS
// command fires N SC wakeups after the previous one -- so an RTS is relative to SC's own cycle
// rate and an ATS is relative to the spacecraft clock. That difference is the entire distinction
// between the two sequence types, and it is this one field.
class SC_RtsEntryHeader_t
{
  U32 WakeupCount; // SC_RelWakeupCount_t -- wakeups, not seconds              offset 0
};

// 12 bytes, and note it is SMALLER than an ATS entry: no pad and no command number, because an
// RTS runs in buffer order and does not need one.
class SC_RtsEntry_t
{
  SC_RtsEntryHeader_t Header; // RTS header                                    offset 0
  CFE_MSG_CommandHeader Msg;  // command message to be sent                    offset 4
};

// Per-ATS bookkeeping. 8 bytes.
class SC_AtsInfoTable_t
{
  U16 AtsUseCtr;        // how many times this ATS has been used               offset 0
  U16 NumberOfCommands; // commands in the ATS                                 offset 2
  U32 AtsSize;          // size of the ATS in 32-bit words                     offset 4
};

// Per-RTS bookkeeping. 12 bytes, and the four single-byte fields at the front pack with no holes.
class SC_RtsInfoEntry_t
{
  U8 RtsStatus;            // SC_Status_Enum_t                                 offset 0
  U8 DisabledFlag;         // Bool                                             offset 1
  U8 CmdCtr;               // commands executed in this RTS                    offset 2
  U8 CmdErrCtr;            // errors in this RTS                               offset 3
  U32 NextCommandTgtWakeup; // target wakeup count for the next command        offset 4
  U16 NextCommandPtr;      // SC_EntryOffset_t -- where the next command is    offset 8
  U16 UseCtr;              // how many times this RTS has run                  offset 10
};

/*******************************************************************************/
// --- config/default_sc_tblstruct.h: the two control blocks ------------------------------------

// THE ATS PROCESSOR'S CONTROL BLOCK. 12 bytes, and it has TWO HOLES OF DIFFERENT PARENTAGE:
// the compiler's 1-byte hole at offset 1 (a uint8 followed by a uint16) and NASA's own declared
// `Padding` field at offset 4. Only offsetof distinguishes them -- see the file header.
class SC_AtpControlBlock_t
{
  U8 AtpState;        // SC_Status_Enum_t -- execution state of the ATP         offset 0
  U8 _pad0[1];        // the COMPILER's hole: a uint16 follows
  U16 CurrAtsNum;     // SC_AtsNum_t -- the ATS running, if any                offset 2
  U16 Padding;        // NASA'S OWN, "Structure padding to align to 32-bit boundaries"
  U16 CmdNumber;      // SC_CommandNum_t -- the command to run, if any         offset 6
  U16 TimeIndexPtr;   // SC_SeqIndex_t -- time index for the current command   offset 8
  U16 SwitchPendFlag; // a buffer switch is waiting                            offset 10
};

// THE RTS PROCESSOR'S CONTROL BLOCK. 4 bytes, no holes -- and far smaller than the ATP's, because
// an RTS carries its own state per sequence in SC_RtsInfoEntry_t while the single ATP tracks
// exactly one running ATS.
class SC_RtpControlBlock_t
{
  U16 NumRtsActive; // RTSs currently active                                   offset 0
  U16 CurrRtsNum;   // SC_RtsNum_t -- the next RTS number                      offset 2
};

#endif
