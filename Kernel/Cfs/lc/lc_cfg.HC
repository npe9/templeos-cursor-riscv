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
// LIMIT CHECKER'S CONFIGURATION -- NASA's fsw/inc/lc_interface_cfg.h and lc_internal_cfg.h.
//
// BOTH LEVELS ARE WRITTEN OUT, AND THAT IS DELIBERATE. NASA defines each constant twice:
//
//     #define LC_MAX_WATCHPOINTS         LC_INTERFACE_CFGVAL(MAX_WATCHPOINTS)
//     #define DEFAULT_LC_MAX_WATCHPOINTS 176
//
// where LC_INTERFACE_CFGVAL(x) is `DEFAULT_LC_##x` -- TOKEN PASTING, which HolyC has no operator
// for. Writing only the resolved value would work and would be worse: check_constants compares a
// translated #define against NASA's, and NASA's LC_MAX_WATCHPOINTS is a MACRO CALL rather than a
// literal, so it lands in the "not a literal, not compared" bucket. The DEFAULT_ name IS a
// literal. So both are here, the literal is gated, and the two-level structure a mission uses to
// override a value survives.
//
// LC_FLOAT_TOLERANCE IS THE SECOND FLOATING-POINT THING IN THIS APP. 1.0e-25 is a double, and it
// is what LC's equal/not-equal comparison allows either side of the comparison value. Worth
// noticing rather than only translating: a watchpoint's value is a 32-bit float, whose smallest
// normal magnitude is about 1.2e-38, so a tolerance of 1e-25 is ENORMOUS next to a small value and
// VANISHING next to a large one -- it is an absolute window, not a relative one, so for anything
// above about 1e-18 it is an exact-equality test and for anything below 1e-25 it matches
// everything. NASA's number, carried as NASA's number.
#ifndef LC_CFG_HC
#define LC_CFG_HC

// --- lc_interface_cfg.h: what the GROUND and the tables see ----------------------------------
#define DEFAULT_LC_RTS_REQ_MID      0x18A9
#define LC_RTS_REQ_MID              DEFAULT_LC_RTS_REQ_MID
#define DEFAULT_LC_RTS_REQ_CC       4
#define LC_RTS_REQ_CC               DEFAULT_LC_RTS_REQ_CC
#define DEFAULT_LC_MAX_WATCHPOINTS  176
#define LC_MAX_WATCHPOINTS          DEFAULT_LC_MAX_WATCHPOINTS
#define DEFAULT_LC_MAX_ACTIONPOINTS 176
#define LC_MAX_ACTIONPOINTS         DEFAULT_LC_MAX_ACTIONPOINTS
#define DEFAULT_LC_MAX_ACTION_TEXT  32
#define LC_MAX_ACTION_TEXT          DEFAULT_LC_MAX_ACTION_TEXT
#define DEFAULT_LC_MAX_RPN_EQU_SIZE 20
#define LC_MAX_RPN_EQU_SIZE         DEFAULT_LC_MAX_RPN_EQU_SIZE

// --- lc_internal_cfg.h: what only LC sees ----------------------------------------------------
//
// THE TWO STATE CONSTANTS ARE NOT NUMBERS, they are the names LC_STATE_DISABLED and
// LC_STATE_FROM_CDS from lc_msgdefs.h -- so this file is included AFTER lc_msg.HC rather than
// before it, and that order is why LC_STATE_POWER_ON_RESET resolves at all.
#define DEFAULT_LC_APP_NAME                "LC"
#define LC_APP_NAME                        DEFAULT_LC_APP_NAME
#define DEFAULT_LC_PIPE_DEPTH              12
#define LC_PIPE_DEPTH                      DEFAULT_LC_PIPE_DEPTH
#define DEFAULT_LC_STATE_POWER_ON_RESET    LC_STATE_DISABLED
#define LC_STATE_POWER_ON_RESET            DEFAULT_LC_STATE_POWER_ON_RESET
#define DEFAULT_LC_STATE_WHEN_CDS_RESTORED LC_STATE_FROM_CDS
#define LC_STATE_WHEN_CDS_RESTORED         DEFAULT_LC_STATE_WHEN_CDS_RESTORED
#define DEFAULT_LC_WDT_FILENAME            "/cf/lc_def_wdt.tbl"
#define LC_WDT_FILENAME                    DEFAULT_LC_WDT_FILENAME
#define DEFAULT_LC_ADT_FILENAME            "/cf/lc_def_adt.tbl"
#define LC_ADT_FILENAME                    DEFAULT_LC_ADT_FILENAME
#define DEFAULT_LC_MAX_VALID_ADT_RTSID     0xFFF0
#define LC_MAX_VALID_ADT_RTSID             DEFAULT_LC_MAX_VALID_ADT_RTSID
#define DEFAULT_LC_FLOAT_TOLERANCE         (1.0e-25)
#define LC_FLOAT_TOLERANCE                 DEFAULT_LC_FLOAT_TOLERANCE
#define DEFAULT_LC_WDT_TABLENAME           "LC_WDT"
#define LC_WDT_TABLENAME                   DEFAULT_LC_WDT_TABLENAME
#define DEFAULT_LC_ADT_TABLENAME           "LC_ADT"
#define LC_ADT_TABLENAME                   DEFAULT_LC_ADT_TABLENAME
#define DEFAULT_LC_WRT_TABLENAME           "LC_WRT"
#define LC_WRT_TABLENAME                   DEFAULT_LC_WRT_TABLENAME
#define DEFAULT_LC_ART_TABLENAME           "LC_ART"
#define LC_ART_TABLENAME                   DEFAULT_LC_ART_TABLENAME
#define DEFAULT_LC_MISSION_REV             0xFF
#define LC_MISSION_REV                     DEFAULT_LC_MISSION_REV

// --- lc_version.h: the three build numbers the no-op command reports ---------------------------
//
// LC_MISSION_REV IS NOT HERE, it is above with the internal configuration -- which is where NASA
// puts it, because a mission sets it and the other three come from the release. The no-op event
// prints all four as one dotted version, which is the only place they appear.
#define LC_MAJOR_VERSION 7
#define LC_MINOR_VERSION 0
#define LC_REVISION      1

#endif
