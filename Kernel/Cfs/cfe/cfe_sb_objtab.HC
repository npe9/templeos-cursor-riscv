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
// 1:1 HolyC translation of cFE modules/sb/fsw/src/cfe_sb_objtab.c -- SB'S ENTRY IN THE OBJECT
// TABLE. Thirty-eight lines, and it is how ES finds the module at startup: a name, an
// early-init, a task entry point, a cleanup callback, a priority and a stack size.
//
// SB is a TASK module with BOTH an EarlyInit and a Cleanup, which makes this the fullest entry
// of the five translated so far -- config and fs have no TaskMain, and ta has no EarlyInit of
// its own worth speaking of.
#ifndef CFE_SB_OBJTAB_HC
#define CFE_SB_OBJTAB_HC
#include "cfe_sb_dispatch.HC" // CFE_SB_TaskMain, by way of the whole module
// --- cfe_sb_platform_cfg.h / cfe_es_internal_cfg.h -------------------------------------------
#define CFE_PLATFORM_SB_START_TASK_PRIORITY   64
// NASA's default is CFE_PLATFORM_ES_DEFAULT_STACK_SIZE, which is 8192 and lives in ES's
// internal_cfg -- ES is not translated yet, so the number is spelled out and check_constants.py
// compares it against NASA's own header, the same way time's and evs's objtabs reach theirs.
#define CFE_PLATFORM_SB_START_TASK_STACK_SIZE 8192
// The same single deviation as the other four, and it is syntax only: the C uses designated
// initializers and HolyC has none, so the values are positional.
Target_ObjectTable CFE_SB_ModuleEntry = {"CFE_SB",           &CFE_SB_EarlyInit,
                                         &CFE_SB_TaskMain,   &CFE_SB_CleanUpApp,
                                         CFE_PLATFORM_SB_START_TASK_PRIORITY,
                                         CFE_PLATFORM_SB_START_TASK_STACK_SIZE};
#endif
