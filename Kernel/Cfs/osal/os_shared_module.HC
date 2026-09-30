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

// 1:1 HolyC translation of the module/symbol types, from OSAL src/os/shared/inc/os-shared-module.h
// and the public types in src/os/inc/osapi-module.h.
#ifndef OS_SHARED_MODULE_HC
#define OS_SHARED_MODULE_HC
#include "osconfig.HC"

// OS_module_type_t, an enum in the C; these are its assigned values.
#define OS_MODULE_TYPE_UNKNOWN 0
#define OS_MODULE_TYPE_DYNAMIC 1
#define OS_MODULE_TYPE_STATIC  2

// cpuaddr is `typedef uintptr_t` -- pointer-sized, so U64 on this target.
class OS_module_internal_record_t
{
  U8 module_name[OS_MAX_API_NAME];
  U8 file_name[OS_MAX_PATH_LEN];
  I64 module_type; // OS_module_type_t, an enum
  U32 flags;
  U64 entry_point; // cpuaddr
};

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
  OS_module_address_t addr;
};

// The static symbol table entry. `Address` is a function pointer in the C.
class OS_static_symbol_record_t
{
  U8 *Name;
  U0 (*Address)();
  U8 *Module;
};
#endif
