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

// The slice of cFE modules/core_api/fsw/inc/cfe_time.h that the translated units need: the
// system-time type and the one function they call on it.
//
// DECLARATION ONLY, and deliberately so. The TIME module is 4,800 lines and is not translated
// yet, so whoever links these units supplies the clock -- the simulated spacecraft in
// Kernel/Cfs/CfsSb.HC reads its mission-elapsed time, and the differential oracle uses a fixed
// stub so a wall clock cannot make two transcripts disagree. This file exists so that there is
// exactly ONE declaration: two units needed it, and duplicating a prototype is how the two
// quietly drift apart.
//
// An undefined prototype is not a link error here -- it becomes an import that the runtime
// fills, silently if the name is one the C runtime knows. The gates assert an empty import
// trailer for that reason; see tests/scripts/run_cfs_xlat_smoke.sh.
#ifndef CFE_TIME_API_HC
#define CFE_TIME_API_HC
// --- default_cfe_time_extern_typedefs.h -----------------------------------------------------
// The type lives in cfe_msg_sechdr_time.HC, translated with the header that stores it.
#include "cfe_msg_sechdr_time.HC"
// --- cfe_time.h ------------------------------------------------------------------------------
CFE_TIME_SysTime CFE_TIME_GetTime();
#endif
