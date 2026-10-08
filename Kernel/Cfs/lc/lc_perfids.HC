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
// LIMIT CHECKER'S PERFORMANCE IDS -- NASA's fsw/inc/lc_perfids.h.
//
// TWO, WHERE EVERY APP BEFORE THIS ONE HAD ONE. LC_APPMAIN_PERF_ID brackets the main loop like
// MD's, MM's and CS's; LC_WDT_SEARCH_PERF_ID brackets the HASH LOOKUP that finds which
// watchpoints a received message feeds. That second marker is the measurement that justifies the
// 256-entry hash table in lc_global.HC: LC is on the critical path of every subscribed packet, so
// the cost of finding the watchpoints is worth its own number on the ground.
#ifndef LC_PERFIDS_HC
#define LC_PERFIDS_HC

#define LC_APPMAIN_PERF_ID    28
#define LC_WDT_SEARCH_PERF_ID 43

#endif
