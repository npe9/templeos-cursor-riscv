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
// STORED COMMAND'S GLOBAL STATE AND ITS SEVEN ACCESSORS -- the 1:1 translation of NASA's
// fsw/src/sc_app.h.
//
// ### SC HAS **TWO** GLOBALS, AND THE SPLIT IS NINE TABLES AGAINST TWO INDEXES
//
// `SC_OperData` (4,256 bytes) holds everything cFE owns: the command pipe, NINE table handles
// with their nine addresses, and the housekeeping packet. `SC_AppData` (8,032 bytes) holds
// everything SC owns: two 1,000-entry index buffers, the time reference, and the running counters.
// No other app in this port has two.
//
// ### SEVEN PADDING HOLES IN SC_OperData_t, ALL FROM ONE HABIT
//
// NASA writes a **2-byte `CFE_TBL_Handle_t` immediately before an 8-byte pointer**, seven times:
//
//     CFE_TBL_Handle_t   AppendTblHandle;   /* 2 bytes at offset 24 */
//     uint32 *           AppendTblAddr;     /* 8 bytes at offset 32 -- SIX BYTES OF HOLE */
//
// Six bytes lost per pair, seven pairs, plus 4 bytes after AtsCmdStatusHandle, 2 after
// NumCmdsWakeup and 4 of trailing padding: **46 of the 4,256 bytes are holes the compiler
// inserted and NASA declared none of them.** Grouping the handles together would have cost
// nothing and the structure would be 46 bytes smaller. Kept exactly, because a translation that
// reordered fields would be a different structure -- and every one of those holes is written out
// below as a `_padN` member, measured with offsetof, because check_padding compares byte layout
// and sizeof and a missing hole shifts everything after it.
//
// ### THE SEVEN ACCESSORS ARE WHERE SC'S VARIABLE-LENGTH ENTRIES LIVE -- AND HOLYC LIMIT
//
// Four of them index a flat `uint32 *` buffer and cast the result to an entry pointer:
//
//     return (SC_AtsEntry_t *)&SC_OperData.AtsTblAddr[AtsIndex][EntryOffset];
//
// **THE `uint32 *` IS LOAD-BEARING.** `&buf[EntryOffset]` scales the offset by FOUR, so the
// offset is in 32-bit words -- see sc_cfg.HC for the three units involved. A translation that
// typed the buffer `U8 *` would scale by one and land every entry at a quarter of its offset,
// with no diagnostic from anything.
//
// **AND EVERY CALL SITE THAT WRITES `SC_GetAtsEntryAtOffset(...)->Header` IS THE OPEN HolyC
// DEFECT.** docs/HOLYC_STRUCT_LIMITS.md: a call followed by `->` resolves the arrow against the
// FIRST ARGUMENT's class, and these accessors take SCALARS, so the arrow resolves against nothing
// and the access SILENTLY LOADS THROUGH ZERO. There are **twelve such sites** in SC's sources,
// measured before translation began -- sc_loads.c 6, sc_atsrq.c 4, sc_rtsrq.c 2 -- and every one
// becomes a hoist to a typed local. docs/CFS_PLAN.md records the count so the twelve are a
// checklist rather than twelve mysterious divergences.
//
// ### AND THE TIME REFERENCE IS A FUNCTION POINTER, SELECTED ONCE AT INIT
//
// `SC_TimeAccessor_t` is one member: `CFE_TIME_SysTime_t (*GetTime)(void)`. SC_AppInit picks
// CFE_TIME_GetTime, GetTAI or GetUTC according to SC_TIME_TO_USE and stores it here, so every
// later time read is an indirect call. That is the only function pointer in SC, and it returns a
// STRUCT BY VALUE -- which works here because CFE_TIME_SysTime is 8 bytes and the translation's
// cfe_time_api.HC already returns it that way.
#ifndef SC_GLOBAL_HC
#define SC_GLOBAL_HC

#include "sc_cfg.HC"
#include "sc_tbl.HC"
#include "sc_msg.HC"

// --- sc_app.h's own constants ------------------------------------------------------------------
//
// ALL FOURTEEN, whole, for the reason check_defines usually enforces -- **except that right now it
// does not, and the first version of this file proved it by shipping ELEVEN.**
//
// THE GAP BIT IMMEDIATELY AND EXACTLY AS PREDICTED. The note below was written saying sc_app.h is
// unpaired and the gate cannot demand its constants; the same commit claimed "ALL ELEVEN" were
// present. Translating sc_loads.c two commits later needed `SC_INVALID_CMD_NUMBER`, which was not
// here -- and enumerating sc_app.h properly then showed **three** missing, not one:
// SC_SB_TIMEOUT, SC_INVALID_CMD_NUMBER and SC_ROUND_UP_BYTES. A hand count of "eleven" against a
// header with fifteen object-like defines, with no gate able to contradict it.
//
// So the list below is now produced by
//     grep -E "^#define SC_[A-Za-z0-9_]+( |\t)" vendor/SC/fsw/src/sc_app.h
// minus the include guard, and checked back against that grep -- not counted by eye.
//
// check_defines builds its required list by pairing a TRANSLATED file with a NASA header OF THE
// SAME BASENAME, then checks presence anywhere in the translation. This file is `sc_global.HC`
// and there is no `sc_global.h`, so it pairs with nothing; `sc_app.h` will not be paired until
// `sc_app.HC` exists, which is the translation of sc_app.c and has not been written yet. Deleting
// SC_BYTES_IN_WORD from this file and re-running the gate produced no complaint at all.
//
// The same shape is GATED for HS, and the contrast is what proves the mechanism: deleting
// HS_CDSNAME from hs_global.HC fails immediately with
// `Kernel/Cfs/hs/hs_app.HC (vs vendor/HS/fsw/src/hs_app.h) is missing 1`, because HS's hs_app.HC
// exists to carry the pairing. So this is a TEMPORARY, SELF-CLOSING gap that shuts the moment
// sc_app.HC lands -- not a gate defect -- and it means "the gate is green" is not evidence about
// these eleven constants today. They were taken from a probe over NASA's own header instead.
// THE SOFTWARE BUS RECEIVE TIMEOUT, in milliseconds. SC's main loop blocks on its command pipe
// for one second at a time; see sc_app.c. **This was one of the three missing** -- see above.
#define SC_SB_TIMEOUT 1000
#define SC_BYTES_IN_WORD 4
// THE 32-BIT WORD COUNTS, DERIVED BY HALVING THE CONFIGURED 16-BIT COUNTS. See sc_cfg.HC: these
// are what every comparison in sc_loads.c and sc_atsrq.c uses, and the `/ 2` is kept unfolded
// because an odd configured size would silently lose its last 16-bit word.
#define SC_ATS_BUFF_SIZE32    (SC_ATS_BUFF_SIZE / 2)
#define SC_RTS_BUFF_SIZE32    (SC_RTS_BUFF_SIZE / 2)
#define SC_APPEND_BUFF_SIZE32 (SC_APPEND_BUFF_SIZE / 2)
#define SC_ERROR -1
#define SC_CMD_PIPE_NAME "SC_CMD_PIPE"
// THE HEADER SIZES IN WORDS, and note each comes in TWO flavours: with the minimum packet and
// without it. `SC_ATS_HDR_WORDS` = (8 + 8)/4 = 4 is the smallest an ATS entry can be;
// `SC_ATS_HDR_NOPKT_WORDS` = 8/4 = 2 is the header alone. sc_loads.c uses the first to bound a
// load and the second to step past a header, and confusing them is a two-word error in a
// variable-length stream.
#define SC_ATS_HDR_WORDS       ((SC_ATS_HEADER_SIZE + SC_PACKET_MIN_SIZE) / SC_BYTES_IN_WORD)
#define SC_ATS_HDR_NOPKT_WORDS (SC_ATS_HEADER_SIZE / SC_BYTES_IN_WORD)
#define SC_RTS_HDR_WORDS       ((SC_RTS_HEADER_SIZE + SC_PACKET_MIN_SIZE) / SC_BYTES_IN_WORD)
#define SC_RTS_HDR_NOPKT_WORDS (SC_RTS_HEADER_SIZE / SC_BYTES_IN_WORD)
// -1, AND IT IS A MARKER IN AN int32 ARRAY whose other values are command indexes. SC's duplicate
// test fills AtsDupTestArray with this and then writes a sequence index into each slot a command
// claims; a second claim on the same slot is a duplicate command number in the uploaded ATS.
#define SC_DUP_TEST_UNUSED -1
// TWO, because an ATS append entry is counted in 16-bit words where everything else in SC is
// counted in 32-bit ones. The one constant in SC that names the OTHER word size.
#define SC_BYTES_IN_ATS_APPEND_ENTRY 2
// ZERO, and NASA spells it `((SC_CommandNum_t){0})` -- a COMPOUND LITERAL ON A SCALAR TYPEDEF,
// the same unusual form SC_EntryOffsetAdvance's return uses. It is just 0 with a type attached,
// and HolyC has no spelling for it, so it is the number. **This was one of the three missing**,
// and it is the one sc_loads.c needs on every line that clears a time-index slot -- so the gap
// surfaced as a compile failure rather than as a wrong value, which is the lucky direction.
#define SC_INVALID_CMD_NUMBER 0
// THREE, which is `sizeof(uint32) - 1` written as a literal. It is the round-up addend in the
// byte-to-word conversions sc_loads.c does inline, where SC_EntryOffsetAdvance spells the same
// idea as `(Bytes + sizeof(uint32) - 1) / sizeof(uint32)`. **Also one of the three missing**, and
// having both spellings of one constant in the app is NASA's, not this translation's.
#define SC_ROUND_UP_BYTES 3

/*******************************************************************************/
// THE TIME REFERENCE. One function pointer, chosen once at init -- see the file header.
class SC_TimeAccessor_t
{
  CFE_TIME_SysTime (*GetTime)();
};

/*******************************************************************************/
// ONE BYTE. NASA wraps the status in a struct so that an array of them is an array of named
// things rather than an array of uint8 -- the same reason SC_AtsCmdNumRecord_t and
// SC_AtsCmdEntryOffsetRecord_t exist below.
class SC_AtsCmdStatusEntry_t
{
  U8 Status; // SC_Status_Enum_t
};

// TWO BYTES EACH, and these two are why SC's index buffers are arrays of structs: an
// `SC_AtsCmdNumRecord_t[2][1000]` and an `SC_AtsCmdEntryOffsetRecord_t[2][1000]` make the
// accessors return a typed pointer, which is what lets a caller write `->CmdNum` and `->Offset`
// rather than index a bare uint16 array.
class SC_AtsCmdEntryOffsetRecord_t
{
  U16 Offset; // SC_EntryOffset_t -- a 32-bit-word offset into the ATS buffer
};

class SC_AtsCmdNumRecord_t
{
  U16 CmdNum; // SC_CommandNum_t -- 1-based
};

/*******************************************************************************/
// EVERYTHING cFE OWNS. 4,256 bytes, 46 of them holes -- see the file header. Offsets in the right
// margin were read out of the C with offsetof.
class SC_OperData_t
{
  U32 CmdPipe; // CFE_SB_PipeId_t                                              offset 0

  I16 AtsTblHandle[SC_NUMBER_OF_ATS]; // CFE_TBL_Handle_t per ATS              offset 4
  U32 *AtsTblAddr[SC_NUMBER_OF_ATS];  // and its buffer -- A **U32** POINTER   offset 8

  I16 AppendTblHandle; //                                                      offset 24
  U8 _pad0[6];         // the handle/pointer habit: six bytes lost
  U32 *AppendTblAddr;  //                                                      offset 32

  I16 RtsTblHandle[SC_NUMBER_OF_RTS]; //                                       offset 40
  U32 *RtsTblAddr[SC_NUMBER_OF_RTS];  //                                       offset 48

  I16 AtsInfoHandle; //                                                        offset 80
  U8 _pad1[6];       //
  SC_AtsInfoTable_t *AtsInfoTblAddr; //                                        offset 88

  I16 RtsInfoHandle; //                                                        offset 96
  U8 _pad2[6];       //
  SC_RtsInfoEntry_t *RtsInfoTblAddr; //                                        offset 104

  I16 RtsCtrlBlckHandle; //                                                    offset 112
  U8 _pad3[6];           //
  SC_RtpControlBlock_t *RtsCtrlBlckAddr; //                                    offset 120

  I16 AtsCtrlBlckHandle; //                                                    offset 128
  U8 _pad4[6];           //
  SC_AtpControlBlock_t *AtsCtrlBlckAddr; //                                    offset 136

  I16 AtsCmdStatusHandle[SC_NUMBER_OF_ATS]; //                                 offset 144
  U8 _pad5[4];                              //
  SC_AtsCmdStatusEntry_t *AtsCmdStatusTblAddr[SC_NUMBER_OF_ATS]; //            offset 152

  // 4,000 BYTES, AN int32 PER POSSIBLE ATS COMMAND. See SC_DUP_TEST_UNUSED above: this is how SC
  // notices that an uploaded ATS claims the same command number twice.
  I32 AtsDupTestArray[SC_MAX_ATS_CMDS]; //                                     offset 168

  // THE RATE LIMITER. SC sends at most SC_MAX_CMDS_PER_WAKEUP (8) commands per wakeup, so a
  // thousand-command ATS whose times have all passed drains over 125 wakeups rather than
  // flooding the software bus in one.
  U16 NumCmdsWakeup; //                                                        offset 4168
  U8 _pad6[2];       //

  SC_HkTlm_t HkPacket; //                                                      offset 4172
  U8 _pad7[4];         // trailing padding to the structure's 8-byte alignment
};

/*******************************************************************************/
// EVERYTHING SC OWNS. 8,032 bytes, and 8,000 of them are the two index buffers.
class SC_AppData_t
{
  // **THE TIME-SORTED ORDER.** Entry 0 holds the command number that runs FIRST, entry 1 the
  // second, and so on -- so this buffer is a sort of the ATS by time tag, built once at load.
  // That is why an ATS can be uploaded in any order and still run chronologically, and why
  // SC_GetAtsCommandNumAtSeq takes a SEQUENCE index where everything else takes a command index.
  SC_AtsCmdNumRecord_t AtsTimeIndexBuffer[SC_NUMBER_OF_ATS][SC_MAX_ATS_CMDS]; // offset 0

  // AND THE OFFSET PER COMMAND INDEX. Given command index N, this says where in the flat word
  // buffer its entry begins -- the other half of the variable-length scheme.
  SC_AtsCmdEntryOffsetRecord_t AtsCmdIndexBuffer[SC_NUMBER_OF_ATS][SC_MAX_ATS_CMDS]; // offset 4000

  SC_TimeAccessor_t TimeRef; // the configured clock                           offset 8000

  Bool EnableHeaderUpdate; // whether to update outgoing message headers       offset 8008
  U8 _pad0[3];             //

  // TWO ENTRIES AND THEY ARE DIFFERENT UNITS: [0] is the ATP's next command TIME in seconds and
  // [1] is the RTP's next command WAKEUP COUNT. NASA's own comment says so. One array, two
  // clocks -- the same split SC_AtsEntryHeader_t and SC_RtsEntryHeader_t have.
  U32 NextCmdTime[2]; //                                                       offset 8012

  U32 CurrentTime;        // SC_AbsTimeTag_t -- SC's current time              offset 8020
  U32 CurrentWakeupCount; // and its current wakeup count                      offset 8024
  U16 AutoStartRTS;       // SC_RtsNum_t -- the RTS to start after init         offset 8028
  U16 AppendWordCount;    // size of the current Append table's entries        offset 8030
};

// --- the globals -------------------------------------------------------------------------------
//
// NASA declares both `extern` in sc_app.h and defines them in sc_app.c. The translation defines
// them HERE for the reason every app in this port shares: a HolyC `extern` outside the module
// loader's window is a module-local dummy, so a global gets exactly one definition and it lives
// with its type. tools/cfs/check_oracle_globals.py enforces that the C oracle does not also
// define them once sc_app.c is gated.
SC_AppData_t SC_AppData;
SC_OperData_t SC_OperData;

/*******************************************************************************/
// --- sc_app.h's seven `static inline` accessors ------------------------------------------------
//
// check_header_inlines owns these: a header inline is part of every caller, so each must exist by
// name. **AND EVERY CALL SITE THAT PUTS `->` ON ONE OF THESE RESULTS MUST HOIST TO A LOCAL** --
// see the file header for the open HolyC defect and the twelve measured sites.

SC_RtsInfoEntry_t *SC_GetRtsInfoObject(U16 RtsIndex)
{
  return &SC_OperData.RtsInfoTblAddr[SC_IDX_AS_UINT(RtsIndex)];
}

SC_AtsInfoTable_t *SC_GetAtsInfoObject(U16 AtsIndex)
{
  return &SC_OperData.AtsInfoTblAddr[SC_IDX_AS_UINT(AtsIndex)];
}

// THE U32 INDEXING IS THE POINT -- see the file header. `RtsTblAddr[i]` is a `U32 *`, so
// `[EntryOffset]` steps four bytes per unit, and the cast relabels the result as an entry.
SC_RtsEntry_t *SC_GetRtsEntryAtOffset(U16 RtsIndex, U16 EntryOffset)
{
  return &SC_OperData.RtsTblAddr[SC_IDX_AS_UINT(RtsIndex)][SC_IDX_AS_UINT(EntryOffset)](SC_RtsEntry_t *);
}

SC_AtsEntry_t *SC_GetAtsEntryAtOffset(U16 AtsIndex, U16 EntryOffset)
{
  return &SC_OperData.AtsTblAddr[SC_IDX_AS_UINT(AtsIndex)][SC_IDX_AS_UINT(EntryOffset)](SC_AtsEntry_t *);
}

SC_AtsCmdEntryOffsetRecord_t *SC_GetAtsEntryOffsetForCmd(U16 AtsIndex, U16 CommandIndex)
{
  return &SC_AppData.AtsCmdIndexBuffer[SC_IDX_AS_UINT(AtsIndex)][SC_IDX_AS_UINT(CommandIndex)];
}

// A **SEQUENCE** INDEX, NOT A COMMAND INDEX -- see AtsTimeIndexBuffer above. The two are
// interchangeable to the compiler and mean different things.
SC_AtsCmdNumRecord_t *SC_GetAtsCommandNumAtSeq(U16 AtsIndex, U16 SeqIndex)
{
  return &SC_AppData.AtsTimeIndexBuffer[SC_IDX_AS_UINT(AtsIndex)][SC_IDX_AS_UINT(SeqIndex)];
}

SC_AtsCmdStatusEntry_t *SC_GetAtsStatusEntryForCommand(U16 AtsIndex, U16 CommandIndex)
{
  return &SC_OperData.AtsCmdStatusTblAddr[SC_IDX_AS_UINT(AtsIndex)][SC_IDX_AS_UINT(CommandIndex)];
}

#endif
