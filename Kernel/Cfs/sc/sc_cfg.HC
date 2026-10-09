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
// STORED COMMAND'S CONFIGURATION -- the 1:1 translation of NASA's fsw/inc/sc_interface_cfg.h,
// fsw/inc/sc_internal_cfg.h, config/default_sc_interface_cfg_values.h,
// config/default_sc_internal_cfg_values.h, fsw/src/sc_version.h and fsw/inc/sc_perfids.h, with
// the token-pasted indirections resolved.
//
// ### THE WHOLE APP IS SIZED BY EIGHT NUMBERS, AND THE BUFFER SIZES ARE **16-BIT WORD** COUNTS
//
// SC holds two Absolute Time Sequences and four Relative Time Sequences. SC's commands are
// VARIABLE LENGTH -- a header plus a command message, laid end to end in a flat array and reached
// by offset -- so the buffers are sized in words rather than entries. **WHICH WORD IS THE POINT,
// and this comment was wrong about it once.** The chain, verified in NASA's sc_app.h and not read
// off the names:
//
//   SC_ATS_BUFF_SIZE        8000     a count of **16-BIT** words -- the configured number
//   SC_ATS_BUFF_SIZE32      4000     `(SC_ATS_BUFF_SIZE / 2)` -- 32-bit words, WHAT THE CODE USES
//   the registered table  16000 B    `SC_ATS_BUFF_SIZE32 * SC_BYTES_IN_WORD`, and BYTES_IN_WORD is 4
//
// So the configured number is in one unit, every comparison in sc_loads.c and sc_atsrq.c is in
// another, and cFE is told a third. A reader who takes `SC_ATS_BUFF_SIZE` for the array bound is
// out by a factor of two, and the `32` suffix is the only thing that says so.
//
// **AND THE `/ 2` IS AN INTEGER DIVISION IN A CONFIGURATION EXPRESSION**, which docs/ records as
// the shape that bit a gate in HS. 8000, 4000 and 150 are all even here, so nothing truncates --
// but a mission that configured an ODD buffer size would silently lose its last 16-bit word, with
// no diagnostic anywhere. The expressions are kept unfolded for that reason.
//
// `SC_ATS_BUFF_SIZE` does not tell you how many commands fit either; `SC_MAX_ATS_CMDS` = 1000
// does, and the two limits bind INDEPENDENTLY -- a sequence of 1000 tiny commands and a sequence
// of 200 big ones can both be full.
//
// **THE WORD UNIT IS THE SINGLE MOST LOAD-BEARING FACT IN SC**, because sc_app.h's accessors index
// those buffers as `uint32 *` and then cast the result to an entry pointer: the offset is scaled
// by four, so a translation that typed the buffer `U8 *` would land every entry at a quarter of
// its offset. docs/CFS_PLAN.md states that with the measurement.
//
// ### `SC_PLATFORM_ENABLE_HEADER_UPDATE` IS A BOOLEAN AND IS **NOT** A `#if`
//
// It is `false`, and SC_AppInit uses it as a RUNTIME assignment --
// `SC_AppData.EnableHeaderUpdate = SC_PLATFORM_ENABLE_HEADER_UPDATE;` -- so nothing in SC has to
// be resolved by hand against docs/HOLYC_STRUCT_LIMITS.md #19. **SC has ZERO `#if` sites in its
// sources**, the first app in this port with none; HS had one, LC two, CS and MM several. Measured
// with a grep over all nine sources, not assumed from a reading.
//
// ### NINE TABLE NAMES, AND THEY DO NOT MATCH THE FILE NAMES
//
// SC registers a table per ATS (2), a table per RTS (4), and seven more for the append buffer and
// the six runtime bookkeeping tables -- and the registered names are eight characters or fewer
// ("ATPCTR_TBL", "ATSCMD_TBL") where the load files are paths ("/cf/sc_ats", "/cf/sc_rts"). So as
// with HS, a ground operator aiming a LOAD names the file and one aiming a DUMP names the table,
// and the two spellings are unrelated. **AND THE ATS/RTS FILE NAMES ARE PREFIXES**: SC appends a
// letter or a number, so "/cf/sc_ats" becomes "/cf/sc_ats1.tbl" -- the only place in this port
// where a configured path is built rather than used.
#ifndef SC_CFG_HC
#define SC_CFG_HC

// --- config/default_sc_interface_cfg_values.h -------------------------------------------------
//
// NASA reaches these through `SC_INTERFACE_CFGVAL(x)`, which token-pastes `DEFAULT_SC_INTERFACE_`
// onto the name. HolyC has no `##`, so the DEFAULT_ names carry the values and the SC_ names below
// are written out resolved -- the arrangement every app in this port uses.
#define DEFAULT_SC_INTERFACE_PACKET_MIN_SIZE 8
#define DEFAULT_SC_INTERFACE_PACKET_MAX_SIZE 256
#define DEFAULT_SC_INTERFACE_NUMBER_OF_ATS   2
#define DEFAULT_SC_INTERFACE_NUMBER_OF_RTS   4
#define DEFAULT_SC_INTERFACE_MAX_ATS_CMDS    1000
// 16-BIT words, not bytes, not entries and NOT the 32-bit count the code uses -- see the header.
#define DEFAULT_SC_INTERFACE_ATS_BUFF_SIZE    8000
#define DEFAULT_SC_INTERFACE_APPEND_BUFF_SIZE 4000
#define DEFAULT_SC_INTERFACE_RTS_BUFF_SIZE    150

#define SC_PACKET_MIN_SIZE   DEFAULT_SC_INTERFACE_PACKET_MIN_SIZE
#define SC_PACKET_MAX_SIZE   DEFAULT_SC_INTERFACE_PACKET_MAX_SIZE
#define SC_NUMBER_OF_ATS     DEFAULT_SC_INTERFACE_NUMBER_OF_ATS
#define SC_NUMBER_OF_RTS     DEFAULT_SC_INTERFACE_NUMBER_OF_RTS
#define SC_MAX_ATS_CMDS      DEFAULT_SC_INTERFACE_MAX_ATS_CMDS
#define SC_ATS_BUFF_SIZE     DEFAULT_SC_INTERFACE_ATS_BUFF_SIZE
#define SC_APPEND_BUFF_SIZE  DEFAULT_SC_INTERFACE_APPEND_BUFF_SIZE
#define SC_RTS_BUFF_SIZE     DEFAULT_SC_INTERFACE_RTS_BUFF_SIZE

// --- config/default_sc_internal_cfg_values.h --------------------------------------------------
//
// `false` HERE AND `FALSE` BELOW. NASA's value is C's `false` from stdbool; the translation's is
// HolyC's FALSE. Both are 0 and the only reason to write it out is that check_constants compares
// the TEXT of a non-literal define against NASA's, so the pair has to be named rather than
// silently harmonised.
#define DEFAULT_SC_INTERNAL_PLATFORM_ENABLE_HEADER_UPDATE FALSE
#define DEFAULT_SC_INTERNAL_MAX_CMDS_PER_WAKEUP           8
// THE LAST RTS THAT REPORTS BY EVENT. RTS 1..3 announce their start and stop; RTS 4 and above are
// silent, because a mission with hundreds of RTSs would otherwise flood the event log. With
// SC_NUMBER_OF_RTS = 4 in this configuration, exactly ONE of the four is quiet -- which is the
// cheapest possible way for the exercise to show the threshold is read and not ignored.
#define DEFAULT_SC_INTERNAL_LAST_RTS_WITH_EVENTS 3
#define DEFAULT_SC_INTERNAL_PIPE_DEPTH           12
// PREFIXES, not paths -- SC appends a number. See the file header.
#define DEFAULT_SC_INTERNAL_ATS_FILE_NAME    "/cf/sc_ats"
#define DEFAULT_SC_INTERNAL_APPEND_FILE_NAME "/cf/sc_append.tbl"
#define DEFAULT_SC_INTERNAL_RTS_FILE_NAME    "/cf/sc_rts"
// The nine registered table names, every one of them ten characters or fewer.
#define DEFAULT_SC_INTERNAL_ATS_TABLE_NAME          "ATS_TBL"
#define DEFAULT_SC_INTERNAL_APPEND_TABLE_NAME       "APPEND_TBL"
#define DEFAULT_SC_INTERNAL_RTS_TABLE_NAME          "RTS_TBL"
#define DEFAULT_SC_INTERNAL_RTSINFO_TABLE_NAME      "RTSINF_TBL"
#define DEFAULT_SC_INTERNAL_RTP_CTRL_TABLE_NAME     "RTPCTR_TBL"
#define DEFAULT_SC_INTERNAL_ATSINFO_TABLE_NAME      "ATSINF_TBL"
#define DEFAULT_SC_INTERNAL_APPENDINFO_TABLE_NAME   "APPINF_TBL"
#define DEFAULT_SC_INTERNAL_ATS_CTRL_TABLE_NAME     "ATPCTR_TBL"
#define DEFAULT_SC_INTERNAL_ATS_CMD_STAT_TABLE_NAME "ATSCMD_TBL"
// Two ENUM MEMBERS used as configuration, not integers -- so these two defines name a symbol that
// sc_tbl.HC defines, and the order of the includes is what makes them resolvable.
#define DEFAULT_SC_INTERNAL_CONT_ON_FAILURE_START SC_AtsCont_TRUE
#define DEFAULT_SC_INTERNAL_TIME_TO_USE           SC_TimeRef_USE_CFE_TIME
#define DEFAULT_SC_INTERNAL_MISSION_REV           0

#define SC_PLATFORM_ENABLE_HEADER_UPDATE DEFAULT_SC_INTERNAL_PLATFORM_ENABLE_HEADER_UPDATE
#define SC_MAX_CMDS_PER_WAKEUP           DEFAULT_SC_INTERNAL_MAX_CMDS_PER_WAKEUP
#define SC_LAST_RTS_WITH_EVENTS          DEFAULT_SC_INTERNAL_LAST_RTS_WITH_EVENTS
#define SC_PIPE_DEPTH                    DEFAULT_SC_INTERNAL_PIPE_DEPTH
#define SC_ATS_FILE_NAME                 DEFAULT_SC_INTERNAL_ATS_FILE_NAME
#define SC_APPEND_FILE_NAME              DEFAULT_SC_INTERNAL_APPEND_FILE_NAME
#define SC_RTS_FILE_NAME                 DEFAULT_SC_INTERNAL_RTS_FILE_NAME
#define SC_ATS_TABLE_NAME                DEFAULT_SC_INTERNAL_ATS_TABLE_NAME
#define SC_APPEND_TABLE_NAME             DEFAULT_SC_INTERNAL_APPEND_TABLE_NAME
#define SC_RTS_TABLE_NAME                DEFAULT_SC_INTERNAL_RTS_TABLE_NAME
#define SC_RTSINFO_TABLE_NAME            DEFAULT_SC_INTERNAL_RTSINFO_TABLE_NAME
#define SC_RTP_CTRL_TABLE_NAME           DEFAULT_SC_INTERNAL_RTP_CTRL_TABLE_NAME
#define SC_ATSINFO_TABLE_NAME            DEFAULT_SC_INTERNAL_ATSINFO_TABLE_NAME
#define SC_APPENDINFO_TABLE_NAME         DEFAULT_SC_INTERNAL_APPENDINFO_TABLE_NAME
#define SC_ATS_CTRL_TABLE_NAME           DEFAULT_SC_INTERNAL_ATS_CTRL_TABLE_NAME
#define SC_ATS_CMD_STAT_TABLE_NAME       DEFAULT_SC_INTERNAL_ATS_CMD_STAT_TABLE_NAME
#define SC_CONT_ON_FAILURE_START         DEFAULT_SC_INTERNAL_CONT_ON_FAILURE_START
#define SC_TIME_TO_USE                   DEFAULT_SC_INTERNAL_TIME_TO_USE
#define SC_MISSION_REV                   DEFAULT_SC_INTERNAL_MISSION_REV

// NOT HERE, AND DELIBERATELY: SC_ATS_BUFF_SIZE32, SC_RTS_BUFF_SIZE32, SC_APPEND_BUFF_SIZE32,
// SC_BYTES_IN_WORD, SC_ATS_HDR_WORDS and the three other derived word counts live in NASA's
// **sc_app.h**, not in either configuration header. check_defines pairs a translated file with a
// NASA header BY BASENAME, so they belong in sc_global.HC -- the counterpart of sc_app.h -- and
// putting them here would leave sc_app.h's half of the pairing short while this file carried
// constants its own NASA counterpart does not define.

// --- fsw/inc/sc_perfids.h ----------------------------------------------------------------------
//
// **38, FROM `fsw/inc/sc_perfids.h`, AND NO GATE PINS IT.**
//
// SC ships two files named sc_perfids.h -- `config/default_sc_perfids.h` says 35 and
// `fsw/inc/sc_perfids.h` says 38 -- and both use the include guard `SC_PERFIDS_H`, so whichever
// is read first silently suppresses the other. Both are on the real build's include path
// (`sc_perfids.h` is in SC's arch_build.cmake platform-config list, and CMakeLists.txt:23
// publishes fsw/inc). docs/CFS_PLAN.md has the history: the duplicate was REINTRODUCED by the
// pinned commit itself, with the value changed.
//
// This port takes 38 -- the value the pinned commit deliberately wrote -- and the choice is
// MEASURED: `vendor/shim/sc_perfids.h` was deleted so it cannot forward to the config copy, and
// the layout probe prints `SC_APPMAIN_PERF_ID the probe SEES = 38`.
//
// **BUT check_constants CANNOT CHECK IT**, and that is stated rather than left to be discovered.
// Its probe resolves a constant's value from an explicit header list, and sc_perfids.h is kept
// OUT of that list on purpose: listing either copy would make the gate assert one side of a
// conflict it has no business deciding. So this constant appears in the gate's "NASA does not
// define" bucket -- one name, deliberately. The value is pinned instead by the differential
// transcript, where SC's exercise prints it and the two halves must agree.
#define SC_APPMAIN_PERF_ID 38

// --- fsw/src/sc_version.h. SC_MISSION_REV is above, with the internal configuration, where NASA
// puts it -- the same split HS has.
#define SC_MAJOR_VERSION 7
#define SC_MINOR_VERSION 0
#define SC_REVISION      0

#endif
