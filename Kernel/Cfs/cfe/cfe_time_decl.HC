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
// The one declaration from cFE modules/core_api/fsw/inc/cfe_time.h that units OUTSIDE the time
// module need: the clock. cfe_sb_util.HC calls it to timestamp a message, and so does the
// simulated spacecraft in Kernel/Cfs/CfsSb.HC.
//
// WHY THIS IS A SEPARATE FILE and not the include of cfe_time_api.HC it used to be. While TIME
// was untranslated, cfe_time_api.HC WAS this file -- thirty-nine lines, a type and a prototype.
// Now it is the module's 546-line translation, and it depends on cfe_time_global.HC and
// cfe_time_utils.HC being included first. A unit that only wants to know the clock exists cannot
// drag all of that in, and must not be the thing that fixes TIME's include order.
//
// The original file's reason for existing still holds and is why this is one file rather than a
// prototype copied into each caller: two units need it, and duplicating a prototype is how the
// two quietly drift apart. tools/cfs/check_variadic.py now enforces part of that for variadics;
// nothing enforces it for a plain signature, so one declaration it is.
#ifndef CFE_TIME_DECL_HC
#define CFE_TIME_DECL_HC
// The type lives in cfe_msg_sechdr_time.HC, translated with the header that stores it.
#include "cfe_msg_sechdr_time.HC"
// --- cfe_time.h ------------------------------------------------------------------------------
CFE_TIME_SysTime CFE_TIME_GetTime();
#endif
