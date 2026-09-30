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

// 1:1 HolyC translation of cFE modules/sbr/fsw/src/cfe_sbr_objtab.c. One registration entry; see
// cfe_msg_objtab.HC for why these are translated and what the one syntax deviation is.
#ifndef CFE_SBR_OBJTAB_HC
#define CFE_SBR_OBJTAB_HC
#include "cfe_msg_objtab.HC"
Target_ObjectTable CFE_SBR_ModuleEntry = {"CFE_SBR", NULL, NULL, NULL, 0, 0};
#endif
