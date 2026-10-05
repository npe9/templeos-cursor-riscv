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
// 1:1 HolyC translation of cFE modules/tbl/fsw/src/cfe_tbl_objtab.c -- tbl's entry in the core
// module object table. Thirty-nine lines, all of them one initialiser.
//
// NASA's own comment is the whole description: "TBL is a task module with both EarlyInit and
// Cleanup functions." It is the ordinary shape -- ES is the odd one out, with no Cleanup
// because it is the last module standing at shutdown, and an EarlyInit slot spent on the CDS.
//
// WHAT THE TABLE IS FOR. CFE_ES_CreateObjects walks CFE_CORE_MODULE_OBJTAB twice during
// startup: once calling every EarlyInit, then again spawning every TaskMain as a task. So
// these five fields are the entire contract between a core service and cFE's startup, and the
// AppCleanupCb is what runs for each core service when an application goes away.
//
// ALL THREE FUNCTIONS ARE STUBS ON BOTH HALVES, and will be for a while. They live in
// cfe_tbl_internal.c, cfe_tbl_task.c and cfe_tbl_api.c, which are three of the EIGHT sources
// that tools/cfs/module_deps.py shows have to be gated together -- tbl's core is one
// 3,900-line strongly connected component, unlike ES, which came apart a source at a time.
// Until then this is the same arrangement the other six objtabs have had.
//
// The one deviation the other six also record, syntax only: the C uses designated initializers
// and HolyC has none, so the values are positional.
#ifndef CFE_TBL_OBJTAB_HC
#define CFE_TBL_OBJTAB_HC
// --- cfe_tbl_platform_cfg.h ------------------------------------------------------------------
// Both reach CFE_PLATFORM_TBL_CFGVAL(...) in NASA's header, which resolves through the
// generated config to these. tools/cfs/check_constants.py compares them against the real ones.
#define CFE_PLATFORM_TBL_START_TASK_PRIORITY   70
#define CFE_PLATFORM_TBL_START_TASK_STACK_SIZE 8192
// cfe_tbl_internal.c, cfe_tbl_task.c and cfe_tbl_api.c are not gated, so these three are stubs
// on both halves of the differential oracle.
I32 CFE_TBL_EarlyInit();
U0 CFE_TBL_TaskMain();
I32 CFE_TBL_CleanUpApp(U32 AppId);
Target_ObjectTable CFE_TBL_ModuleEntry = {"CFE_TBL", &CFE_TBL_EarlyInit, &CFE_TBL_TaskMain,
                                          &CFE_TBL_CleanUpApp,
                                          CFE_PLATFORM_TBL_START_TASK_PRIORITY,
                                          CFE_PLATFORM_TBL_START_TASK_STACK_SIZE};
#endif
