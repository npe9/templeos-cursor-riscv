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
// STORED COMMAND'S EVENT IDS -- the 1:1 translation of NASA's fsw/inc/**sc_events.h**.
//
// ### THE FILE NAME MATTERS, BECAUSE SC SHIPS TWO OF THESE AND THEY DISAGREE
//
// `vendor/SC/fsw/inc/` contains both `sc_events.h` (1,358 lines, 117 ids) and `sc_eventids.h`
// (900 lines, 59 ids). **All nine of SC's sources include `sc_events.h`; `sc_eventids.h` is
// included by nothing**, and its doxygen header is DS's -- "The CFS Data Storage (DS) Application
// event id header file", `\defgroup cfsdsevents` -- a copy-paste left in SC's tree.
//
// Five names appear in both and **ALL FIVE DISAGREE**:
//
//     SC_CC_ERR_EID       sc_eventids.h 21    sc_events.h 64
//     SC_INIT_INF_EID                    1                 9
//     SC_MID_ERR_EID                    73                63
//     SC_NOOP_INF_EID                   31                52
//     SC_RESET_INF_EID                  33                51
//
// So this file is named `sc_events.HC` and not `sc_eventids.HC` for a reason that is not
// cosmetic: `check_defines` pairs a translation with a NASA header BY BASENAME, and
// `check_constants` resolves a constant's value through an explicit probe-header list. Putting
// the dead header in that list would move five event ids and leave both gates GREEN while
// asserting numbers the compiled code never uses. Only `sc_events.h` is listed.
//
// SC is the second app in this port to use the `_events.h` spelling -- HK is the first -- and the
// only one carrying both spellings.
//
// ### 117 IDS OVER THE RANGE 1..138, WITH 21 GENUINE GAPS
//
// Missing: 7, 8, 12, 13, 14, 15, 22, 53-58, 89-91, 94-96, 108, 125. **Those are retired events
// and the claim is measured, not assumed** -- no id in this header has a lowercase letter in its
// name, which is checked rather than eyeballed because that is exactly what went wrong in HS:
// a case-sensitive grep there dropped eight of 77 ids whose names contained a lowercase "Val",
// and the file shipped with a comment declaring those eight numbers to be gaps. There are no
// duplicate values either.
//
// The order below is NASA's own, not sorted by value, so the two files diff against each other.
#ifndef SC_EVENTS_HC
#define SC_EVENTS_HC

#define SC_APP_EXIT_ERR_EID                      1
#define SC_CMD_LEN_ERR_EID                       2
#define SC_CR_PIPE_ERR_EID                       3
#define SC_INIT_SB_SUBSCRIBE_HK_ERR_EID          4
#define SC_INIT_SB_SUBSCRIBE_ERR_EID             5
#define SC_INIT_SB_SUBSCRIBE_CMD_ERR_EID         6
#define SC_INIT_INF_EID                          9
#define SC_REGISTER_RTS_TBL_ERR_EID              10
#define SC_REGISTER_ATS_TBL_ERR_EID              11
#define SC_REGISTER_RTS_INFO_TABLE_ERR_EID       16
#define SC_REGISTER_RTS_CTRL_BLK_TABLE_ERR_EID   17
#define SC_REGISTER_ATS_INFO_TABLE_ERR_EID       18
#define SC_REGISTER_ATS_CTRL_BLK_TABLE_ERR_EID   19
#define SC_REGISTER_ATS_CMD_STATUS_TABLE_ERR_EID 20
#define SC_RTS_LOAD_FAIL_COUNT_INFO_EID          21
#define SC_STARTATS_CMD_INF_EID                  23
#define SC_STARTATS_CMD_NOT_LDED_ERR_EID         24
#define SC_STARTATS_CMD_NOT_IDLE_ERR_EID         25
#define SC_STARTATS_CMD_INVLD_ID_ERR_EID         26
#define SC_STOPATS_CMD_INF_EID                   27
#define SC_STOPATS_NO_ATS_INF_EID                28
#define SC_ATS_SKP_ALL_ERR_EID                   29
#define SC_ATS_ERR_SKP_DBG_EID                   30
#define SC_SWITCH_ATS_CMD_INF_EID                31
#define SC_SWITCH_ATS_CMD_NOT_LDED_ERR_EID       32
#define SC_SWITCH_ATS_CMD_IDLE_ERR_EID           33
#define SC_ATS_SERVICE_SWTCH_INF_EID             34
#define SC_SERVICE_SWITCH_ATS_CMD_LDED_ERR_EID   35
#define SC_ATS_SERVICE_SWITCH_IDLE_ERR_EID       36
#define SC_ATS_INLINE_SWTCH_INF_EID              37
#define SC_ATS_INLINE_SWTCH_NOT_LDED_ERR_EID     38
#define SC_JUMPATS_CMD_STOPPED_ERR_EID           39
#define SC_JUMP_ATS_INF_EID                      40
#define SC_JUMPATS_CMD_NOT_ACT_ERR_EID           41
#define SC_CONT_CMD_ERR_EID                      42
#define SC_CONT_CMD_INF_EID                      43
#define SC_ATS_CHKSUM_ERR_EID                    44
#define SC_ATS_ABT_ERR_EID                       45
#define SC_ATS_DIST_ERR_EID                      46
#define SC_ATS_MSMTCH_ERR_EID                    47
#define SC_ATS_SKP_ERR_EID                       48
#define SC_RTS_DIST_ERR_EID                      49
#define SC_RTS_CHKSUM_ERR_EID                    50
#define SC_RESET_INF_EID                         51
#define SC_NOOP_INF_EID                          52
#define SC_RTS_INVLD_MID_ERR_EID                 59
#define SC_RTS_LEN_ERR_EID                       60
#define SC_RTS_LEN_BUFFER_ERR_EID                61
#define SC_RTS_LEN_TOO_LONG_ERR_EID              62
#define SC_MID_ERR_EID                           63
#define SC_CC_ERR_EID                            64
#define SC_GET_ADDRESS_RTS_INFO_ERR_EID          65
#define SC_GET_ADDRESS_RTS_CTRL_BLCK_ERR_EID     66
#define SC_GET_ADDRESS_ATS_INFO_ERR_EID          67
#define SC_GET_ADDRESS_ATS_CTRL_BLCK_ERR_EID     68
#define SC_GET_ADDRESS_ATS_CMD_STAT_ERR_EID      69
#define SC_GET_ADDRESS_RTS_ERR_EID               70
#define SC_GET_ADDRESS_ATS_ERR_EID               71
#define SC_STARTRTS_CMD_DBG_EID                  72
#define SC_RTS_START_INF_EID                     73
#define SC_STARTRTS_CMD_INVLD_LEN_ERR_EID        74
#define SC_STARTRTS_CMD_NOT_LDED_ERR_EID         75
#define SC_STARTRTS_CMD_DISABLED_ERR_EID         76
#define SC_STARTRTS_CMD_INVALID_ERR_EID          77
#define SC_STOPRTS_CMD_INF_EID                   78
#define SC_STOPRTS_CMD_ERR_EID                   79
#define SC_DISABLE_RTS_INF_EID                   80
#define SC_DISRTS_CMD_ERR_EID                    81
#define SC_ENABLE_RTS_INF_EID                    82
#define SC_ENARTS_CMD_ERR_EID                    83
#define SC_RTS_LNGTH_ERR_EID                     84
#define SC_RTS_CMD_LNGTH_ERR_EID                 85
#define SC_RTS_COMPL_INF_EID                     86
#define SC_ATS_COMPL_INF_EID                     87
#define SC_JUMP_ATS_SKIPPED_DBG_EID              88
#define SC_GET_ADDRESS_APPEND_ERR_EID            92
#define SC_REGISTER_APPEND_TBL_ERR_EID           93
#define SC_UPDATE_APPEND_EID                     97
#define SC_APPEND_CMD_INF_EID                    98
#define SC_APPEND_CMD_ARG_ERR_EID                99
#define SC_APPEND_CMD_TGT_ERR_EID                100
#define SC_APPEND_CMD_SRC_ERR_EID                101
#define SC_APPEND_CMD_FIT_ERR_EID                102
#define SC_VERIFY_ATS_EID                        103
#define SC_VERIFY_ATS_NUM_ERR_EID                104
#define SC_VERIFY_ATS_END_ERR_EID                105
#define SC_VERIFY_ATS_PKT_ERR_EID                106
#define SC_VERIFY_ATS_BUF_ERR_EID                107
#define SC_VERIFY_ATS_DUP_ERR_EID                109
#define SC_VERIFY_ATS_MPT_ERR_EID                110
#define SC_TABLE_MANAGE_ID_ERR_EID               111
#define SC_TABLE_MANAGE_RTS_ERR_EID              112
#define SC_TABLE_MANAGE_ATS_ERR_EID              113
#define SC_TABLE_MANAGE_APPEND_ERR_EID           114
#define SC_STARTRTSGRP_CMD_INF_EID               115
#define SC_STARTRTSGRP_CMD_ERR_EID               116
#define SC_STOPRTSGRP_CMD_INF_EID                117
#define SC_STOPRTSGRP_CMD_ERR_EID                118
#define SC_DISRTSGRP_CMD_INF_EID                 119
#define SC_DISRTSGRP_CMD_ERR_EID                 120
#define SC_ENARTSGRP_CMD_INF_EID                 121
#define SC_ENARTSGRP_CMD_ERR_EID                 122
#define SC_JUMPATS_CMD_LIST_INF_EID              123
#define SC_RTS_LOAD_FAIL_DBG_EID                 124
#define SC_STARTRTSGRP_CMD_NOT_LDED_ERR_EID      126
#define SC_STARTRTSGRP_CMD_DISABLED_ERR_EID      127
#define SC_BEGINATS_INVLD_INDEX_ERR_EID          128
#define SC_TABLE_MANAGE_RTS_INV_INDEX_ERR_EID    129
#define SC_TABLE_MANAGE_ATS_INV_INDEX_ERR_EID    130
#define SC_LOADATS_INV_INDEX_ERR_EID             131
#define SC_BUILD_TIME_IDXTBL_ERR_EID             132
#define SC_INSERTATS_INV_INDEX_ERR_EID           133
#define SC_INIT_ATSTBL_INV_INDEX_ERR_EID         134
#define SC_LOADRTS_INV_INDEX_ERR_EID             135
#define SC_PROCESS_APPEND_INV_INDEX_ERR_EID      136
#define SC_KILLRTS_INV_INDEX_ERR_EID             137
#define SC_AUTOSTART_RTS_INV_ID_ERR_EID          138

#endif
