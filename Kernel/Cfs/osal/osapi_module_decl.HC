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
// OSAL src/os/inc/osapi-module.h -- THE TYPES ONLY, with no implementation behind them.
//
// WHY IT IS ITS OWN FILE: the same answer osapi_heap_decl.HC gives, for the same pair of types
// at the same seam. cfe_es_apps.c's CFE_ES_CopyModuleAddressInfo fills an OS_module_prop_t from
// OS_ModuleInfo, so the cFE translation needs the TYPE -- but os_shared_module.HC merges NASA's
// header with the shared layer's own state and private records, and including it would drag
// OSAL's implementation into the cFE translation unit. That is the one thing check_seam exists
// to prevent: cFE sees OSAL only through its API.
//
// Re-declaring the classes inside cfe_es_apps.HC would have worked -- the compiler accepts a
// duplicate class SILENTLY, which is exactly the problem -- and left one layout rule in two
// places for check_padding to measure separately. docs/ records two gates with two copies of one
// join rule drifting apart; a class is no different. One definition, in the layer that owns it,
// included by os_shared_module.HC rather than copied into it.
#ifndef OSAPI_MODULE_DECL_HC
#define OSAPI_MODULE_DECL_HC
// --- osapi-module.h --------------------------------------------------------------------------
class OS_module_address_t
{
  U32 valid;
  U32 flags;
  U64 code_address;
  U64 code_size;
  U64 data_address;
  U64 data_size;
  U64 bss_address;
  U64 bss_size;
};

class OS_module_prop_t
{
  U64 entry_point;    // cpuaddr
  U64 host_module_id; // cpuaddr
  U8 filename[OS_MAX_PATH_LEN];
  U8 name[OS_MAX_API_NAME];
  U8 _pad0[4]; // C pads here; HolyC packs. See tools/cfs/check_padding.py
  OS_module_address_t addr;
};
#endif
