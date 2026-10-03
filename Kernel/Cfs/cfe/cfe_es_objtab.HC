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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_objtab.c -- ES's entry in the core
// module object table. Forty-one lines, and all of them one initialiser.
//
// NASA's own comment says what the table says, and ES is the odd one out twice over: "ES is a
// task module. It does not have a separate EarlyInit because the ES startup sequence itself
// serves that role. ES also does not have a Cleanup function - it is the last module standing
// during shutdown."
//
// SO THE EarlyInit SLOT HOLDS SOMEONE ELSE'S FUNCTION. It is CFE_ES_CDS_EarlyInit, with NASA's
// comment "ES drives its own startup, this is for CDS" -- the one module-init hook ES has is
// spent on the critical data store, because the CDS has to exist before any app can register
// with it and ES's own startup is already past that point by the time the table is walked.
//
// INCLUDE cfe_msg_objtab.HC (for Target_ObjectTable) and cfe_es_task.HC FIRST -- CFE_ES_TaskMain
// is defined there, and CFE_ES_CDS_EarlyInit is a stub until cfe_es_cds.c is gated.
//
// The same single deviation the other five objtabs record, and it is syntax only: the C uses
// designated initializers and HolyC has none, so the values are positional. ES's AppCleanupCb
// is absent from NASA's initialiser and so is a zero here.
#ifndef CFE_ES_OBJTAB_HC
#define CFE_ES_OBJTAB_HC
// --- cfe_es_internal_cfg.h -------------------------------------------------------------------
#define CFE_PLATFORM_ES_START_TASK_PRIORITY   68
#define CFE_PLATFORM_ES_START_TASK_STACK_SIZE 8192
// cfe_es_cds.c is not gated, so this is a stub on both halves of the differential oracle.
I32 CFE_ES_CDS_EarlyInit();
Target_ObjectTable CFE_ES_ModuleEntry = {"CFE_ES", &CFE_ES_CDS_EarlyInit, &CFE_ES_TaskMain, NULL, CFE_PLATFORM_ES_START_TASK_PRIORITY, CFE_PLATFORM_ES_START_TASK_STACK_SIZE};
#endif
