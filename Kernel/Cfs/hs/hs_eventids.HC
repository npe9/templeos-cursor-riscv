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
// HEALTH & SAFETY'S EVENT IDS -- the 1:1 translation of NASA's fsw/inc/hs_eventids.h.
//
// SEVENTY-SEVEN IDS AND EXACTLY **TWO** GAPS: 62 and 63. The numbers are the wire format a
// ground decoder keys on, so the two holes are kept -- an id is never reused in cFS, and 62 and
// 63 sit between HS_CPUMON_HOGGING_ERR_EID and the CPU-hog enable/disable pair, which is where a
// removed feature would have left them.
//
// ### A FIRST DRAFT OF THIS FILE HAD 69 IDS AND CLAIMED TEN GAPS
//
// It was extracted with `grep -E '^#define HS_[A-Z0-9_]+_EID'`, which is CASE-SENSITIVE -- and
// eight of NASA's ids are the four table validators' pairs:
//
//     HS_AMTVal_INF_EID 50   HS_AMTVal_ERR_EID 51
//     HS_EMTVal_INF_EID 52   HS_EMTVal_ERR_EID 53
//     HS_XCTVal_INF_EID 54   HS_XCTVal_ERR_EID 55
//     HS_MATVal_INF_EID 56   HS_MATVal_ERR_EID 57
//
// -- every one with a lowercase "Val" in the middle, so the pattern matched none of them. The
// file was short by eight and the comment asserted that 50 through 57 were gaps where features
// had been removed. **They are the ids hs_monitors.c uses most.**
//
// It is the same shape docs/ records as a checker passing on what it cannot FIND, turned on my
// own tooling: a pattern that silently matches nothing looks exactly like an absence. What caught
// it was reading hs_monitors.c and finding HS_AMTVal_ERR_EID in a call -- not any gate, because
// no gate compares a translated header against NASA's for COMPLETENESS. The ids that are here are
// checked by check_constants; the ones that were missing were simply not there to check.
//
// AND THE NAMING IS NASA'S: every other id in this file is SHOUTING_CASE and these eight are
// MixedCase, matching the table names (AMT, EMT, XCT, MAT) rather than the convention.
#ifndef HS_EVENTIDS_HC
#define HS_EVENTIDS_HC

#define HS_INIT_INF_EID                      1
#define HS_APP_EXIT_EID                      2
#define HS_CDS_RESTORE_ERR_EID               3
#define HS_CR_PIPE_ERR_EID                   4
#define HS_CR_EVENT_PIPE_ERR_EID             5
#define HS_CR_WAKEUP_PIPE_ERR_EID            6
#define HS_SUB_LONG_EVS_ERR_EID              7
#define HS_SUB_REQ_ERR_EID                   8
#define HS_SUB_CMD_ERR_EID                   9
#define HS_AMT_REG_ERR_EID                   10
#define HS_EMT_REG_ERR_EID                   11
#define HS_XCT_REG_ERR_EID                   12
#define HS_MAT_REG_ERR_EID                   13
#define HS_AMT_LD_ERR_EID                    14
#define HS_EMT_LD_ERR_EID                    15
#define HS_XCT_LD_ERR_EID                    16
#define HS_MAT_LD_ERR_EID                    17
#define HS_CDS_CORRUPT_ERR_EID               18
#define HS_CC_ERR_EID                        19
#define HS_MID_ERR_EID                       20
#define HS_HKREQ_LEN_ERR_EID                 21
#define HS_CMD_LEN_ERR_EID                   22
#define HS_NOOP_INF_EID                      23
#define HS_RESET_INF_EID                     24
#define HS_ENABLE_APPMON_INF_EID             25
#define HS_DISABLE_APPMON_INF_EID            26
#define HS_ENABLE_EVENTMON_INF_EID           27
#define HS_DISABLE_EVENTMON_INF_EID          28
#define HS_ENABLE_ALIVENESS_INF_EID          29
#define HS_DISABLE_ALIVENESS_INF_EID         30
#define HS_RESET_RESETS_INF_EID              31
#define HS_SET_MAX_RESETS_INF_EID            32
#define HS_APPMON_GETADDR_ERR_EID            33
#define HS_EVENTMON_GETADDR_ERR_EID          34
#define HS_EXECOUNT_GETADDR_ERR_EID          35
#define HS_MSGACTS_GETADDR_ERR_EID           36
#define HS_RESET_LIMIT_ERR_EID               37
#define HS_APPMON_APPNAME_ERR_EID            38
#define HS_APPMON_RESTART_ERR_EID            39
#define HS_APPMON_NOT_RESTARTED_ERR_EID      40
#define HS_APPMON_FAIL_ERR_EID               41
#define HS_APPMON_PROC_ERR_EID               42
#define HS_APPMON_MSGACTS_ERR_EID            43
#define HS_EVENTMON_MSGACTS_ERR_EID          44
#define HS_EVENTMON_PROC_ERR_EID             45
#define HS_EVENTMON_RESTART_ERR_EID          46
#define HS_EVENTMON_NOT_RESTARTED_ERR_EID    47
#define HS_EVENTMON_DELETE_ERR_EID           48
#define HS_EVENTMON_NOT_DELETED_ERR_EID      49
#define HS_AMTVal_INF_EID                    50
#define HS_AMTVal_ERR_EID                    51
#define HS_EMTVal_INF_EID                    52
#define HS_EMTVal_ERR_EID                    53
#define HS_XCTVal_INF_EID                    54
#define HS_XCTVal_ERR_EID                    55
#define HS_MATVal_INF_EID                    56
#define HS_MATVal_ERR_EID                    57
#define HS_DISABLE_APPMON_ERR_EID            58
#define HS_DISABLE_EVENTMON_ERR_EID          59
#define HS_SUB_WAKEUP_ERR_EID                60
#define HS_CPUMON_HOGGING_ERR_EID            61
#define HS_ENABLE_CPUHOG_INF_EID             64
#define HS_DISABLE_CPUHOG_INF_EID            65
#define HS_EVENTMON_LONG_SUB_EID             66
#define HS_EVENTMON_SHORT_SUB_EID            67
#define HS_EVENTMON_LONG_UNSUB_EID           68
#define HS_EVENTMON_SHORT_UNSUB_EID          69
#define HS_BADEMT_LONG_UNSUB_EID             70
#define HS_BADEMT_SHORT_UNSUB_EID            71
#define HS_APPMON_APPNAME_DBG_EID            72
#define HS_HKREQ_RESOURCE_DBG_EID            73
#define HS_SYSMON_INIT_ERR_EID               74
#define HS_AM_TBL_NULL_ERR_EID               75
#define HS_EM_TBL_NULL_ERR_EID               76
#define HS_XC_TBL_NULL_ERR_EID               77
#define HS_MA_TBL_NULL_ERR_EID               78
#define HS_SUB_SHORT_EVS_ERR_EID             79

#endif
