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
// LIMIT CHECKER'S FIVE TABLES -- NASA's config/default_lc_tblstruct.h, whole.
//
// LC HAS TWO DEFINITION TABLES AND TWO RESULTS TABLES, the same split CS has, plus a fifth type
// that is neither: LC_MultiType_t, a 4-byte union that is how a watchpoint's value is read out of
// a packet whose layout is not known until the table is loaded.
//
//   LC_WDTEntry_t      28 bytes   what to watch: a MsgId, a byte offset, a mask, an operator and
//                                 a comparison value
//   LC_ADTEntry_t      84 bytes   when to act: a reverse-Polish expression over watch results,
//                                 an RTS to fire, and the event text to send
//   LC_WRTEntry_t      56 bytes   what each watchpoint last evaluated to, with five counters and
//                                 the last transition each way
//   LC_ARTEntry_t      32 bytes   what each actionpoint last evaluated to, with seven counters
//   LC_WRTTransition_t 16 bytes   one transition: the value, its type, and when
//
// ### THE UNION IS THE FIRST FLOATING-POINT COMPARISON IN THIS PORT, AND HolyC HAS NO F32
//
// NASA's LC_MultiType_t has `float Float32;` -- a 32-bit IEEE-754 single. HolyC has F64 and no
// F32 at all, which `0 missing symbols` could never have shown: LC's dependency scan found every
// CFE_ and OS_ name it calls, and the gap is in the LANGUAGE rather than in the library.
//
// SO THE MEMBER IS A U32 HOLDING THE BIT PATTERN, and that is exact rather than a compromise:
//
//   - the layout is unchanged. 4 bytes at offset 0 of a 4-byte union, which is what
//     check_padding measures, so the WDT a ground system uploads is byte-for-byte NASA's.
//   - every float32 VALUE is exactly representable in F64. 24 bits of significand and 8 of
//     exponent fit inside 53 and 11 with room to spare, including subnormals, so decoding the
//     pattern to F64 and comparing there gives the same answer as comparing two float32s --
//     the embedding is exact and monotonic, so the ORDER of any two values is preserved.
//   - NaN and Inf detection gets BETTER, not worse. NASA's WDT validator rejects a comparison
//     value that is NAN (LC_WDTVAL_ERR_FPNAN) or infinite (LC_WDTVAL_ERR_FPINF), and on the bit
//     pattern those are an exponent field of all ones with a zero or non-zero mantissa -- a
//     mask and a compare, with no dependence on how the host's isnan() treats a signalling NaN.
//
// The decode itself lives with the comparison, in lc_watch.HC, not here: this file is layout.
#ifndef LC_TBL_HC
#define LC_TBL_HC

#include "lc_tbldefs.HC"
// LC_MAX_RPN_EQU_SIZE and LC_MAX_ACTION_TEXT are the ADT entry's two array bounds.
#include "lc_cfg.HC"

/*******************************************************************************/
// Actionpoint Definition Table (ADT) entry. 84 bytes, ALIGN 2 -- the only table entry in LC that
// is not 4-aligned, because its widest member is a U16 and its tail is a char array.
//
// NO PADDING IS NEEDED ANYWHERE IN IT, which is worth stating because every other translated
// struct in this app has some: four U8s then two U16s then twenty U16s then two U16s then 32
// chars packs with no holes at all in both languages.
class LC_ADTEntry_t
{
  U8 DefaultState;      // enumerated; the states are in lc_msgdefs.h
  U8 MaxPassiveEvents;  // max events before the filter, RTS not started because AP is passive
  U8 MaxPassFailEvents; // max events before the filter, AP result went pass -> fail
  U8 MaxFailPassEvents; // max events before the filter, AP result went fail -> pass
  U16 RTSId;             // RTS to request if this AP fails
  U16 MaxFailsBeforeRTS; // consecutive failures before an RTS request is issued
  U16 RPNEquation[LC_MAX_RPN_EQU_SIZE]; // reverse-Polish equation: when this AP should fail
  U16 EventType;        // CFE_EVS_EventType_INFORMATION / DEBUG / ERROR / CRITICAL
  U16 EventID;          // event id for the message if this AP fails
  U8 EventText[LC_MAX_ACTION_TEXT]; // text for that event message
};

/*******************************************************************************/
// The alignment union. NASA's comment: "A union type provides a way to have many different data
// types occupy the same memory and legally alias each other. This is used to store the watch data
// points, as they may be 8, 16, or 32 bits and this is defined in the table / not known until
// runtime."
//
// `Float32` IS A U32 HERE AND IT IS STILL FOUR BYTES -- see the note at the top of this file for
// why that is exact. The name keeps NASA's so a reader comparing the two files sees one word
// changed and not a renamed member; tools/cfs/check_structs.py compares them name for name.
union LC_MultiType_t
{
  U32 Unsigned32;
  I32 Signed32;
  U32 Float32; // NASA: `float Float32` -- the BIT PATTERN; HolyC has no F32
  U16 Unsigned16;
  I16 Signed16;
  U8 Unsigned8;
  I8 Signed8;
  U8 RawByte[4];
};

/*******************************************************************************/
// Watchpoint Definition Table (WDT) entry. 28 bytes.
//
// THE TWO-BYTE HOLE AFTER OperatorID IS NASA'S. MessageID is a CFE_SB_MsgId_t, which is 4 bytes
// and 4-aligned in this configuration, so the C compiler pads after the two U8s. HolyC packs, so
// it is written out.
class LC_WDTEntry_t
{
  U8 DataType;    // watchpoint data type, enumerated
  U8 OperatorID;  // comparison type, enumerated
  U8 _pad0[2];    // C aligns the 4-byte MessageID that follows
  CFE_SB_MsgId MessageID; // message id of the packet containing the watchpoint
  U32 WatchpointOffset;   // byte offset from the START of the message, headers included
  U32 BitMask;            // masked with the watchpoint data before the comparison
  LC_MultiType_t ComparisonValue; // what the watchpoint data is compared against
  U32 ResultAgeWhenStale; // sample-actionpoint commands after a comparison before it goes stale
  U32 CustomFuncArgument; // passed to the custom function when OperatorID is LC_OPER_CUSTOM
};

/*******************************************************************************/
// One watchpoint transition. 16 bytes.
//
// THE PADDING IS NASA'S OWN MEMBER, not an invented one: `uint8 Padding[3]` is declared in the C,
// because this struct is written into the CDS and downlinked, so its holes are part of the
// interface and NASA names them. Translated as itself.
class LC_WRTTransition_t
{
  U32 Value;     // watchpoint value at the comparison that caused the transition
  U8 DataType;   // same enumeration as the watchpoint data type
  U8 Padding[3]; // NASA's own structure padding
  CFE_TIME_SysTime Timestamp; // when the transition was detected
};

/*******************************************************************************/
// Watchpoint Results Table (WRT) entry. 56 bytes. `Padding[3]` is again NASA's own member.
class LC_WRTEntry_t
{
  U8 WatchResult; // result of the last evaluation of this watchpoint, enumerated
  U8 Padding[3];  // NASA's own structure padding
  U32 CountdownToStale;     // sample-actionpoint commands still to process before it goes stale
  U32 EvaluationCount;      // how many times this watchpoint has been evaluated
  U32 FalseToTrueCount;     // how many times it has gone FALSE -> TRUE
  U32 ConsecutiveTrueCount; // consecutive times it has evaluated TRUE
  U32 CumulativeTrueCount;  // total times it has evaluated TRUE
  LC_WRTTransition_t LastFalseToTrue; // last transition FALSE -> TRUE
  LC_WRTTransition_t LastTrueToFalse; // last transition TRUE -> FALSE
};

/*******************************************************************************/
// Actionpoint Results Table (ART) entry. 32 bytes. `Padding` is NASA's, and here it is a single
// U16 rather than three U8s -- because two U8s precede it instead of one.
class LC_ARTEntry_t
{
  U8 ActionResult; // result of the last sample of this actionpoint
  U8 CurrentState; // current state of this actionpoint
  U16 Padding;     // NASA's own structure padding
  U32 PassiveAPCount;          // times an RTS was not invoked because this AP was passive
  U32 FailToPassCount;         // times this actionpoint has gone Fail -> Pass
  U32 PassToFailCount;         // times this actionpoint has gone Pass -> Fail
  U32 ConsecutiveFailCount;    // consecutive times it has evaluated Fail
  U32 CumulativeFailCount;     // total times it has evaluated Fail
  U32 CumulativeRTSExecCount;  // total RTS requests sent for this actionpoint
  U32 CumulativeEventMsgsSent; // total event messages sent
};

#endif
