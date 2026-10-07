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
// CHECKSUM'S PERFORMANCE ID -- the translation of NASA's fsw/inc/cs_perfids.h, whole.
//
// ONE, and the contrast with MM is the point. MM has five because its slow operations are
// EEPROM writes, and it wants each kind timed separately. CS's slow operation is the same one
// every cycle -- CRC a bounded number of bytes -- and it is already bounded by
// CS_DEFAULT_BYTES_PER_CYCLE, so the only thing worth timing is the main loop.
#ifndef CS_PERFIDS_HC
#define CS_PERFIDS_HC

#define CS_APPMAIN_PERF_ID 29
#endif
