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
// HOUSEKEEPING'S EVENT IDS -- the 1:1 translation of NASA's fsw/inc/hk_events.h.
//
// THIRTY-SIX IDS AND **TWO GAPS**: 13 and anything above 37 are unused. NASA's header has no 13
// at all -- it goes from HK_OUTPKT_MISSING_DATA_EID (12) straight to HK_CR_PIPE_ERR_EID (14) --
// and the numbers are the wire format a ground decoder keys on, so the gap is kept rather than
// closed. Renumbering to make the list dense would silently retarget every filter a mission has
// written.
//
// AND SEVENTEEN OF THE THIRTY-SIX ARE "UNEXPECTED cFE RETURN" EVENTS. HK talks to table services
// more than any app translated so far -- a double-buffered load table and a dump-only runtime
// table, managed every housekeeping cycle -- and it reports every unexpected status from
// CFE_TBL_GetStatus, Validate, Update, ReleaseAddress, GetAddress and DumpToBuffer separately.
// Six of those are CFE_EVS_EventType_CRITICAL, which is a stronger claim than any other app in
// this port makes about a table call: HK treats a table manager that answers something it did not
// expect as a reason to stop running.
#ifndef HK_EVENTIDS_HC
#define HK_EVENTIDS_HC

#define HK_INIT_INF_EID                    1
#define HK_CC_ERR_EID                      2
#define HK_CMD_LEN_ERR_EID                 3
#define HK_NOOP_INF_EID                    4
#define HK_RESET_INF_EID                   5
#define HK_ACCESSING_PAST_PACKET_END_EID   6
#define HK_MEM_POOL_MALLOC_FAILED_EID      7
#define HK_CANT_SUBSCRIBE_TO_SB_PKT_EID    8
#define HK_MEM_POOL_FREE_FAILED_EID        9
#define HK_UNEXPECTED_GETSTAT_RET_EID      10
#define HK_UNKNOWN_COMBINED_PACKET_EID     11
#define HK_OUTPKT_MISSING_DATA_EID         12
// 13 IS NOT DEFINED BY NASA. The gap is upstream's and is preserved.
#define HK_CR_PIPE_ERR_EID                 14
#define HK_SUB_CMB_ERR_EID                 15
#define HK_SUB_REQ_ERR_EID                 16
#define HK_SUB_CMD_ERR_EID                 17
#define HK_CR_POOL_ERR_EID                 18
#define HK_CPTBL_REG_ERR_EID               19
#define HK_RTTBL_REG_ERR_EID               20
#define HK_CPTBL_LD_ERR_EID                21
#define HK_CPTBL_MNG_ERR_EID               22
#define HK_RTTBL_MNG_ERR_EID               23
#define HK_CPTBL_GADR_ERR_EID              24
#define HK_RTTBL_GADR_ERR_EID              25
#define HK_RCV_MSG_ERR_EID                 26
#define HK_UNEXPECTED_GETSTAT2_RET_EID     27
#define HK_MSG_LEN_ERR_EID                 28
#define HK_UNEXPECTED_GETADDR_RET_EID      29
#define HK_UNEXPECTED_TBLUPD_RET_EID       30
#define HK_UNEXPECTED_RELADDR_RET_EID      31
#define HK_UNEXPECTED_TBLVLD_RET_EID       32
#define HK_UNEXPECTED_DUMPTOBUFFER_RET_EID 33
#define HK_NULL_POINTER_NEWCPY_ERR_EID     34
#define HK_NULL_POINTER_TEARCPY_ERR_EID    35
#define HK_NEWCPYTBL_HK_FAILED_EID         36
#define HK_NEWCPYTBL_INIT_FAILED_EID       37

#endif
