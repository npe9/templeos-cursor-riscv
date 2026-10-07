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
// MEMORY MANAGER'S PERFORMANCE IDS -- the translation of NASA's
// default_mm_perfids.h, whole.
//
// A PERFORMANCE ID IS A MARKER IN THE ES PERFORMANCE LOG, not a counter: CFE_ES_PerfLogEntry
// and CFE_ES_PerfLogExit write the id with the exit bit clear and then set, and the ground
// reads the pair as an interval. Five of them, and the interesting thing about the list is
// WHERE the three EEPROM ones are: a poke, a file load and a fill, which are the three slow
// operations in MM -- EEPROM writes take milliseconds, so they are the ones worth timing.
#ifndef MM_PERFIDS_HC
#define MM_PERFIDS_HC

#define MM_APPMAIN_PERF_ID         30
#define MM_SEGBREAK_PERF_ID        31
#define MM_EEPROM_POKE_PERF_ID     32
#define MM_EEPROM_FILELOAD_PERF_ID 33
#define MM_EEPROM_FILL_PERF_ID     34
#endif
