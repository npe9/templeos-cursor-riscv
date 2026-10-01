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

// 1:1 HolyC translation of cFE modules/ta/fsw/src/cfe_ta_objtab.c.
//
// The FIRST registration entry in this translation with every field filled in: TA is an app,
// not a library, so it has a TaskMain, a cleanup callback, a priority and a stack size. The
// three before it -- msg, fs and config -- are library-only and leave most of the entry zero.
//
// The same single deviation as those three, and it is syntax only: the C uses designated
// initializers and HolyC has none, so the values are positional.
#ifndef CFE_TA_OBJTAB_HC
#define CFE_TA_OBJTAB_HC
Target_ObjectTable CFE_TA_ModuleEntry = {"CFE_TA", &CFE_TA_EarlyInit, &CFE_TA_TaskMain,
                                         &CFE_TA_CleanUpApp, CFE_PLATFORM_TA_START_TASK_PRIORITY,
                                         CFE_PLATFORM_TA_START_TASK_STACK_SIZE};
#endif
