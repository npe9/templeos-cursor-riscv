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
// LIMIT CHECKER'S TABLE CONSTANTS -- NASA's config/default_lc_tbldefs.h, whole.
//
// NASA'S OWN HEADER COMMENT EXPLAINS WHY THIS FILE HAS NO TYPES IN IT: "These Macro definitions
// have been put in this file (instead of lc_tbl.h) so this file can be included directly into
// ASIST build test scripts. ASIST RDL files can accept C language #defines but can't handle type
// definitions. As a result: DO NOT PUT ANY TYPEDEFS OR STRUCTURE DEFINITIONS IN THIS FILE!" The
// split is a ground-tooling constraint, and this translation keeps it: the five table STRUCTS are
// in lc_tbl.HC.
//
// THE TWELVE WATCH DATA TYPES ARE THE WHOLE JOB. LC pulls a value out of a subscribed packet at a
// byte offset, and the type says how to read it: signed or unsigned, 8/16/32 bits, and for the
// multi-byte ones BIG OR LITTLE ENDIAN. Two of the twelve are 32-bit IEEE-754 floats, which is
// the first floating-point comparison anywhere in this port -- see lc_tbl.HC on what HolyC having
// no F32 means for LC_MultiType_t.
//
// AND THE THREE WATCH RESULTS HAVE FIXED VALUES FOR A REASON NASA STATES: LC_WATCH_FALSE "must be
// zero for RPN evaluation" and LC_WATCH_TRUE "must be one". An actionpoint is a reverse-Polish
// expression over watchpoint results, so the results ARE the operands and their numeric values are
// load-bearing. Changing either breaks lc_action.c arithmetically rather than visibly.
#ifndef LC_TBLDEFS_HC
#define LC_TBLDEFS_HC

#define LC_CDS_SAVED            0xF0F0
#define LC_CDS_NOT_SAVED        0x0F0F
#define LC_DATA_WATCH_NOT_USED  0xFF
#define LC_DATA_WATCH_BYTE      1
#define LC_DATA_WATCH_UBYTE     2
#define LC_DATA_WATCH_WORD_BE   3
#define LC_DATA_WATCH_WORD_LE   4
#define LC_DATA_WATCH_UWORD_BE  5
#define LC_DATA_WATCH_UWORD_LE  6
#define LC_DATA_WATCH_DWORD_BE  7
#define LC_DATA_WATCH_DWORD_LE  8
#define LC_DATA_WATCH_UDWORD_BE 9
#define LC_DATA_WATCH_UDWORD_LE 10
#define LC_DATA_WATCH_FLOAT_BE  11
#define LC_DATA_WATCH_FLOAT_LE  12
#define LC_OPER_NONE            0xFF
#define LC_OPER_LT              1
#define LC_OPER_LE              2
#define LC_OPER_NE              3
#define LC_OPER_EQ              4
#define LC_OPER_GE              5
#define LC_OPER_GT              6
#define LC_OPER_CUSTOM          7
#define LC_BITMASK_NONE         0xFFFFFFFF
#define LC_RPN_AND              0xFFF1
#define LC_RPN_OR               0xFFF2
#define LC_RPN_XOR              0xFFF3
#define LC_RPN_NOT              0xFFF4
#define LC_RPN_EQUAL            0xFFF5
#define LC_WATCH_STALE          0xFF
#define LC_WATCH_FALSE          0
#define LC_WATCH_TRUE           1
#define LC_WATCH_ERROR          2
#define LC_ACTION_STALE         0xFF
#define LC_ACTION_PASS          0
#define LC_ACTION_FAIL          1
#define LC_ACTION_ERROR         2
#define LC_WDTVAL_ERR_NONE      0
#define LC_WDTVAL_ERR_DATATYPE  1
#define LC_WDTVAL_ERR_OPER      2
#define LC_WDTVAL_ERR_MID       3
#define LC_WDTVAL_ERR_FPNAN     4
#define LC_WDTVAL_ERR_FPINF     5
#define LC_ADTVAL_ERR_NONE      0
#define LC_ADTVAL_ERR_DEFSTATE  1
#define LC_ADTVAL_ERR_RTSID     2
#define LC_ADTVAL_ERR_FAILCNT   3
#define LC_ADTVAL_ERR_EVTTYPE   4
#define LC_ADTVAL_ERR_RPN       5

// THE DEPRECATED ALIASES, which NASA guards with `#ifndef LC_OMIT_DEPRECATED` and this
// configuration does NOT define -- so they are present, and a ground script or an older table
// definition may still use them. Translated rather than dropped: LC_OMIT_DEPRECATED is a
// configuration choice, and `#if <expr>` is unconditionally true in this compiler (limit #19), so
// writing the guard out would read as a choice that was checked.
#define LC_NO_OPER              LC_OPER_NONE
#define LC_NO_BITMASK           LC_BITMASK_NONE
#define LC_ADTVAL_NO_ERR        LC_ADTVAL_ERR_NONE
#define LC_WDTVAL_NO_ERR        LC_WDTVAL_ERR_NONE
#define LC_DATA_NOT_USED        LC_DATA_WATCH_NOT_USED
#define LC_DATA_BYTE            LC_DATA_WATCH_BYTE
#define LC_DATA_UBYTE           LC_DATA_WATCH_UBYTE
#define LC_DATA_WORD_BE         LC_DATA_WATCH_WORD_BE
#define LC_DATA_WORD_LE         LC_DATA_WATCH_WORD_LE
#define LC_DATA_UWORD_BE        LC_DATA_WATCH_UWORD_BE
#define LC_DATA_UWORD_LE        LC_DATA_WATCH_UWORD_LE
#define LC_DATA_DWORD_BE        LC_DATA_WATCH_DWORD_BE
#define LC_DATA_DWORD_LE        LC_DATA_WATCH_DWORD_LE
#define LC_DATA_UDWORD_BE       LC_DATA_WATCH_UDWORD_BE
#define LC_DATA_UDWORD_LE       LC_DATA_WATCH_UDWORD_LE
#define LC_DATA_FLOAT_BE        LC_DATA_WATCH_FLOAT_BE
#define LC_DATA_FLOAT_LE        LC_DATA_WATCH_FLOAT_LE

#endif
