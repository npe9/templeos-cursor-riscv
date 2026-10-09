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
// SIXTY-NINE IDS AND **TEN GAPS**: 50 through 57, plus 62 and 63, are not defined. NASA's header simply
// skips them, and the numbers are the wire format a ground decoder keys on, so every gap is kept.
// Renumbering to close them would silently retarget every event filter a mission has written.
//
// AND THE GAPS ARE WHERE FEATURES WERE REMOVED, which is worth knowing rather than guessing: 50
// through 57 sit exactly between the event-monitor errors and HS_DISABLE_APPMON_ERR_EID, and 62
// and 63 between the CPU-hogging error and the CPU-hog enable/disable pair. An id is never reused
// in cFS -- a removed feature leaves a hole forever -- so the holes are a record of what HS used
// to do.
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
