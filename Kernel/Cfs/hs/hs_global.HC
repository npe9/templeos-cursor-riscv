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
// HEALTH & SAFETY'S GLOBAL STATE -- the 1:1 translation of NASA's fsw/src/hs_app.h.
//
// 776 bytes, and unlike HK (98.8% one buffer) almost all of it is live state: three pipe ids,
// nine single-byte monitor states, two counter arrays of 32 entries, a 64-entry utilisation
// history, four table handles with four pointers, a CDS handle and the 180-byte HK packet.
//
// ### THE CDS COPY IS A VALUE **AND ITS INVERSE**, WHICH IS THE ONE PIECE OF REAL FAULT TOLERANCE
//
// HS_CDSData_t is four uint16s: ResetsPerformed, ResetsPerformedNot, MaxResets, MaxResetsNot --
// each count stored alongside its bitwise complement. HS reads the pair back and checks that
// `x == (uint16)~xNot`; if it does not, the CDS is declared corrupt (HS_CDS_CORRUPT_ERR_EID) and
// the counts are reinitialised.
//
// **THAT IS THE ONLY PLACE IN ANY APP IN THIS PORT THAT VALIDATES ITS OWN PERSISTENT STATE.** LC
// uses a magic value (LC_CDS_SAVED) to decide whether a CDS was ever written and trusts the
// contents; HS checks the contents arithmetically. The reason is what the number is for: HS
// refuses to reset the processor more than HS_MAX_RESETS times, so a corrupted count is the
// difference between a board that stops rebooting and one that reboots forever.
//
// ### AND `ResetsPerformedNot` IS NOT A TYPO FOR A BOOLEAN
//
// The `Not` suffix means "the complement of", not "not performed". Reading it the other way makes
// the validation look like redundant storage of a flag; it is a checksum of one word.
//
// ### NINE SINGLE-BYTE STATES, AND NASA DECLARES THE PADDING FOR THREE OF THEM
//
// ServiceWatchdogFlag, five monitor states, two table-loaded flags and CurrentCPUHogState are
// uint8s, and NASA puts an explicit `SpareBytes[3]` after the last one with the comment "Spare
// bytes for 32 bit alignment padding". So three of the holes in this structure are upstream's and
// the rest are the compiler's; both are marked below, and the offsets in the right margin were
// read out of the C with offsetof rather than derived.
#ifndef HS_GLOBAL_HC
#define HS_GLOBAL_HC

#include "hs_cfg.HC"
#include "hs_msg.HC"
#include "hs_tbl.HC"

// --- hs_app.h's own constants ---------------------------------------------------------------
//
// ALL TEN, not just the ones a source happens to use. HK's vocabulary left hs_app.h's siblings
// behind and the HolyC half would not compile; tools/cfs/check_defines.py now refuses a NASA
// #define that is nowhere in the translation, which is what makes "the whole header" the only
// workable rule.
//
// THE FOUR TABLE NAMES ARE WHAT cFE REGISTERS THEM UNDER, and they do NOT match the file names:
// "AppMon_Tbl" loads from "/cf/hs_amt.tbl". So a ground operator aiming a table load names the
// FILE and a ground operator aiming a dump names the TABLE, and the two spellings are different.
#define HS_CMD_PIPE_NAME    "HS_CMD_PIPE"
#define HS_EVENT_PIPE_NAME  "HS_EVENT_PIPE"
#define HS_WAKEUP_PIPE_NAME "HS_WAKEUP_PIPE"
#define HS_CDSNAME          "HS_CDS"
#define HS_TBL_VAL_ERR      -1
// 0xFFFFFFFF, the same sentinel HS_MonitorUtilization reports for an unknown CPU load -- here it
// means "this execution counter could not be read", and it goes straight into the HK packet.
#define HS_INVALID_EXECOUNT 0xFFFFFFFF
#define HS_AMT_TABLENAME    "AppMon_Tbl"
#define HS_EMT_TABLENAME    "EventMon_Tbl"
#define HS_XCT_TABLENAME    "ExeCount_Tbl"
#define HS_MAT_TABLENAME    "MsgActs_Tbl"

/*******************************************************************************/
// The critical data: two counts, each with its complement. 8 bytes. See the header on why.
class HS_CDSData_t
{
  U16 ResetsPerformed;    // processor resets HS has performed
  U16 ResetsPerformedNot; // its bitwise complement, for validation
  U16 MaxResets;          // the maximum HS will perform
  U16 MaxResetsNot;       // its bitwise complement
};

/*******************************************************************************/
// HS's entire state. 776 bytes.
class HS_AppData_t
{
  U32 CmdPipe;    // CFE_SB_PipeId_t -- ground commands                       offset 0
  U32 WakeupPipe; // CFE_SB_PipeId_t -- the scheduler's wakeup                offset 4
  U32 EventPipe;  // CFE_SB_PipeId_t -- the whole system's event stream        offset 8

  U8 ServiceWatchdogFlag; // whether the watchdog is being petted             offset 12

  U8 CurrentAppMonState;    // application monitor                            offset 13
  U8 CurrentEventMonState;  // event monitor                                  offset 14
  U8 CurrentAlivenessState; // aliveness indicator                            offset 15
  U8 ExeCountState;         // execution counter table                        offset 16

  U8 MsgActsState;   // message actions table                                 offset 17
  U8 CDSState;       // critical data storing                                 offset 18
  U8 AppMonLoaded;   // whether the AMT is loaded                             offset 19
  U8 EventMonLoaded; // whether the EMT is loaded                             offset 20

  U8 CurrentCPUHogState; // hogging indicator                                 offset 21
  U8 SpareBytes[3];      // NASA'S OWN, "Spare bytes for 32 bit alignment padding"

  U8 CmdCount;    // valid commands received                                  offset 25
  U8 CmdErrCount; // invalid commands received                                offset 26
  U8 _pad0[1];    // C aligns the U32 that follows

  U32 EventsMonitoredCount; // total event messages inspected                 offset 28

  U16 MsgActCooldown[HS_MAX_MSG_ACT_TYPES];          // per MAT entry         offset 32
  U16 AppMonCheckInCountdown[HS_MAX_MONITORED_APPS]; // per monitored app     offset 48

  // ONE WORD with the shipped configuration; the expression is NASA's -- see hs_msg.HC.
  U32 AppMonEnables[((HS_MAX_MONITORED_APPS - 1) / HS_BITS_PER_APPMON_ENABLE) + 1]; // offset 112

  U32 AppMonLastExeCount[HS_MAX_MONITORED_APPS]; // last count seen per app    offset 116

  U32 AlivenessCounter; // towards the CPU aliveness output period             offset 244
  U32 MsgActExec;       // message actions executed                           offset 248
  U32 RunStatus;        // CFE_ES_RunStatus_* for the main loop                offset 252

  U32 SysMonPspModuleId;  // the PSP I/O driver module, 0 when there is none   offset 256
  U16 SysMonSubsystemId;  // its "aggregate" subsystem                        offset 260
  U16 SysMonSubchannelId; // its "cpu-load" subchannel                        offset 262

  U32 UtilizationCycleCounter; // towards the next utilisation sample          offset 264

  U32 CurrentCPUHoggingTime; // consecutive cycles above the hogging threshold offset 268
  U32 MaxCPUHoggingTime;     // cycles after which hogging is reported         offset 272
  U32 CurrentCPUUtilIndex;   // into the tracker below                        offset 276

  U32 UtilizationTracker[HS_UTIL_PEAK_NUM_INTERVAL]; // 64 intervals          offset 280

  U32 UtilCpuAvg;  // current average                                         offset 536
  U32 UtilCpuPeak; // current peak                                            offset 540

  I16 AMTableHandle; // CFE_TBL_Handle_t -- apps monitor                       offset 544
  I16 EMTableHandle; // CFE_TBL_Handle_t -- events monitor                     offset 546
  I16 MATableHandle; // CFE_TBL_Handle_t -- message actions                    offset 548

  I16 XCTableHandle;        // CFE_TBL_Handle_t -- execution counters          offset 550
  HS_XCTEntry_t *XCTablePtr; //                                                offset 552

  HS_AMTEntry_t *AMTablePtr; //                                                offset 560
  HS_EMTEntry_t *EMTablePtr; //                                                offset 568
  HS_MATEntry_t *MATablePtr; //                                                offset 576

  U32 MyCDSHandle;      // CFE_ES_CDSHandle_t                                 offset 584
  HS_CDSData_t CDSData; // the live copy of the critical data                 offset 588

  HS_HkPacket_t HkPacket; // the housekeeping packet                          offset 596
};

// --- the global -----------------------------------------------------------------------------
//
// NASA declares it `extern` in hs_app.h and defines it in hs_app.c. The translation defines it
// HERE for the reason every app in this port has: a HolyC `extern` outside the module loader's
// window is a module-local dummy, so a global has exactly one definition and it lives with its
// type.
HS_AppData_t HS_AppData;

#endif
