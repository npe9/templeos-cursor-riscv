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
// LIMIT CHECKER'S EVENT IDS -- the translation of NASA's fsw/inc/lc_eventids.h, whole, in NASA's
// order. 71 of them, which is fewer than CS's 155 and more than MM's 54, and the shape is
// different from all three: LC's ids are mostly about ITS OWN tables rather than about the thing
// it watches. Watchpoint and actionpoint failures do not get an id each.
//
// THE LAST ONE IS NOT AN EVENT, IT IS A BASE. LC_BASE_AP_EID is 1000, and an actionpoint that
// fails reports `LC_BASE_AP_EID + <table index>` -- so with 176 actionpoints, ids 1000..1175 are
// reserved by arithmetic rather than by #define. That is why the defined range stops at 69 and
// then jumps: there is nothing between, and nothing may be added there.
#ifndef LC_EVENTIDS_HC
#define LC_EVENTIDS_HC

#define LC_RESERVED_EID              0
#define LC_TASK_EXIT_EID             1
#define LC_INIT_INF_EID              2
#define LC_CR_PIPE_ERR_EID           3
#define LC_SUB_HK_REQ_ERR_EID        4
#define LC_SUB_GND_CMD_ERR_EID       5
#define LC_SUB_SAMPLE_CMD_ERR_EID    6
#define LC_WDT_REGISTER_ERR_EID      7
#define LC_WDT_REREGISTER_ERR_EID    8
#define LC_ADT_REGISTER_ERR_EID      9
#define LC_WRT_REGISTER_ERR_EID      10
#define LC_ART_REGISTER_ERR_EID      11
#define LC_WRT_CDS_REGISTER_ERR_EID  12
#define LC_ART_CDS_REGISTER_ERR_EID  13
#define LC_APP_CDS_REGISTER_ERR_EID  14
#define LC_WDT_LOAD_ERR_EID          15
#define LC_ADT_LOAD_ERR_EID          16
#define LC_WRT_GETADDR_ERR_EID       17
#define LC_ART_GETADDR_ERR_EID       18
#define LC_WDT_GETADDR_ERR_EID       19
#define LC_ADT_GETADDR_ERR_EID       20
#define LC_CDS_RESTORED_INF_EID      21
#define LC_CDS_UPDATED_INF_EID       22
#define LC_CDS_DISABLED_INF_EID      23
#define LC_CC_ERR_EID                24
#define LC_APSAMPLE_APNUM_ERR_EID    25
#define LC_NOOP_INF_EID              26
#define LC_RESET_INF_EID             27
#define LC_LCSTATE_INF_EID           28
#define LC_LCSTATE_ERR_EID           29
#define LC_APSTATE_NEW_ERR_EID       30
#define LC_APSTATE_CURR_ERR_EID      31
#define LC_APSTATE_APNUM_ERR_EID     32
#define LC_APSTATE_INF_EID           33
#define LC_APOFF_APNUM_ERR_EID       34
#define LC_APOFF_CURR_ERR_EID        35
#define LC_APOFF_INF_EID             36
#define LC_APSTATS_APNUM_ERR_EID     37
#define LC_APSTATS_INF_EID           38
#define LC_WPSTATS_WPNUM_ERR_EID     39
#define LC_WPSTATS_INF_EID           40
#define LC_HKREQ_LEN_ERR_EID         41
#define LC_APSAMPLE_LEN_ERR_EID      42
#define LC_CMD_LEN_ERR_EID           43
#define LC_UNSUB_WP_ERR_EID          44
#define LC_SUB_WP_ERR_EID            45
#define LC_WRT_NO_SAVE_ERR_EID       46
#define LC_ART_NO_SAVE_ERR_EID       47
#define LC_APP_NO_SAVE_START_ERR_EID 48
#define LC_MID_INF_EID               49
#define LC_WP_DATATYPE_ERR_EID       50
#define LC_WP_OPERID_ERR_EID         51
#define LC_WP_NAN_ERR_EID            52
#define LC_WP_OFFSET_ERR_EID         53
#define LC_WDTVAL_FPERR_EID          54
#define LC_WDTVAL_ERR_EID            55
#define LC_WDTVAL_INF_EID            56
#define LC_APSAMPLE_CURR_ERR_EID     57
#define LC_AP_PASSTOFAIL_INF_EID     58
#define LC_PASSIVE_FAIL_DBG_EID      59
#define LC_AP_PASSIVE_FAIL_INF_EID   60
#define LC_AP_FAILTOPASS_INF_EID     61
#define LC_ACTION_ERROR_ERR_EID      62
#define LC_INVALID_RPN_ERR_EID       63
#define LC_ADTVAL_RPNERR_EID         64
#define LC_ADTVAL_ERR_EID            65
#define LC_ADTVAL_INF_EID            66
#define LC_CFCALL_ERR_EID            67
#define LC_WDT_REGISTER_CRIT_ERR_EID 68
#define LC_ADT_REGISTER_CRIT_ERR_EID 69
#define LC_BASE_AP_EID               1000

#endif
