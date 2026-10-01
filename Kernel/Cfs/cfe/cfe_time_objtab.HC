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
// 1:1 HolyC translation of cFE modules/time/fsw/src/cfe_time_objtab.c -- TIME's entry in the core
// module object table. Thirty-eight lines, and all of them one initialiser.
//
// NASA's own comment says what the table says: "TIME is a task module with both EarlyInit and
// Cleanup functions." All three function pointers are filled in, which is what separates TIME
// from the library modules (msg, sbr) whose entries leave TaskMain NULL, and matches evs and ta,
// the other two task modules here.
//
// INCLUDE cfe_msg_objtab.HC (for Target_ObjectTable), cfe_time_task.HC (EarlyInit and TaskMain)
// and cfe_time_utils.HC (CleanUpApp) FIRST -- the three function pointers are defined there, and
// TIME is the first module whose objtab entry draws from TWO of its own translation units.
//
// The same single deviation the other five objtabs record, and it is syntax only: the C uses
// designated initializers and HolyC has none, so the values are positional.
#ifndef CFE_TIME_OBJTAB_HC
#define CFE_TIME_OBJTAB_HC
// --- cfe_time_internal_cfg.h / cfe_es_internal_cfg.h ------------------------------------------
#define CFE_PLATFORM_TIME_START_TASK_PRIORITY 60
// NASA's default is CFE_PLATFORM_ES_DEFAULT_STACK_SIZE, which is 8192 and lives in ES's
// internal_cfg -- ES is not translated yet, so the number is spelled out and check_constants.py
// compares it against NASA's own header. evs's objtab reaches its 8192 the same way.
#define CFE_PLATFORM_TIME_START_TASK_STACK_SIZE 8192
Target_ObjectTable CFE_TIME_ModuleEntry = {"CFE_TIME", &CFE_TIME_EarlyInit, &CFE_TIME_TaskMain, &CFE_TIME_CleanUpApp, CFE_PLATFORM_TIME_START_TASK_PRIORITY, CFE_PLATFORM_TIME_START_TASK_STACK_SIZE};
#endif
