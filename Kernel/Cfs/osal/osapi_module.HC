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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-module.c.
//
// THE STATIC SYMBOL TABLE IS EMPTY IN THIS CONFIGURATION, and that decides what two functions
// return. NASA writes:
//
//     #if !defined(OS_STATIC_SYMTABLE_SOURCE) && defined(OSAL_CONFIG_INCLUDE_STATIC_LOADER)
//     #define OS_STATIC_SYMTABLE_SOURCE OS_STATIC_SYMBOL_TABLE
//     #endif
//     #ifdef OS_STATIC_SYMTABLE_SOURCE
//     extern OS_static_symbol_record_t OS_STATIC_SYMTABLE_SOURCE[];
//     #else
//     #define OS_STATIC_SYMTABLE_SOURCE NULL
//     #endif
//
// OSAL_CONFIG_INCLUDE_STATIC_LOADER is #undef here, so the table pointer is NULL, both
// `while (StaticSym != NULL)` loops never execute, and the functions return their INITIAL
// values -- OS_ERR_NOT_IMPLEMENTED for a symbol lookup and OS_ERR_NAME_NOT_FOUND for a module
// load. Those two initialisers are the entire observable behaviour here, so they are what the
// transcript pins.
#ifndef OSAPI_MODULE_HC
#define OSAPI_MODULE_HC
#include "os_shared_module.HC"
#include "os_shared_filesys.HC"
#include "../CfsStr.HC"

#define LOCAL_NUM_OBJECTS_MODULE OS_MAX_MODULES
#define LOCAL_OBJID_TYPE_MODULE  OS_OBJECT_TYPE_OS_MODULE

#define OS_STATIC_SYMTABLE_SOURCE NULL

// The backend seam. Declared before use because HolyC is single-pass.
I32 OS_ModuleLoad_Impl(OS_object_token_t *token, U8 *translated_path);
I32 OS_ModuleUnload_Impl(OS_object_token_t *token);
I32 OS_ModuleGetInfo_Impl(OS_object_token_t *token, OS_module_prop_t *module_prop);
I32 OS_SymbolLookup_Impl(U64 *SymbolAddress, U8 *SymbolName);
I32 OS_ModuleSymbolLookup_Impl(OS_object_token_t *token, U64 *SymbolAddress, U8 *SymbolName);
I32 OS_SymbolTableDump_Impl(U8 *filename, I64 size_limit);

OS_module_internal_record_t OS_module_table[OS_MAX_MODULES];

// Local helper, not part of the OSAL API. Checks for a symbol name in the static symbol table.
I32 OS_SymbolLookup_Static(U64 *SymbolAddress, U8 *SymbolName, U8 *ModuleName)
{
  I32 return_code = OS_ERR_NOT_IMPLEMENTED;
  OS_static_symbol_record_t *StaticSym = OS_STATIC_SYMTABLE_SOURCE;
  while (StaticSym != NULL) {
    if (StaticSym->Name == NULL) {
      // End of list. OS_ERROR rather than the initial value, to say an actual search was done
      // with a not-found result as against not searching at all.
      //
      // NASA clears the pointer and continues instead of breaking, and says why: it is to get
      // full MC/DC coverage, the two forms being behaviourally equivalent. Translated as
      // written rather than simplified to a break.
      return_code = OS_ERROR;
      StaticSym = NULL;
      continue;
    }
    if (StrCmp(StaticSym->Name, SymbolName) == 0 &&
        (ModuleName == NULL || StrCmp(StaticSym->Module, ModuleName) == 0)) {
      // found matching symbol
      *SymbolAddress = StaticSym->Address;
      return_code = OS_SUCCESS;
      break;
    }
    ++StaticSym;
  }
  return return_code;
}

// Local helper, not part of the OSAL API. Checks for a module name in the static symbol table.
I32 OS_ModuleLoad_Static(U8 *ModuleName)
{
  I32 return_code = OS_ERR_NAME_NOT_FOUND;
  OS_static_symbol_record_t *StaticSym = OS_STATIC_SYMTABLE_SOURCE;
  while (StaticSym != NULL) {
    if (StaticSym->Name == NULL) {
      StaticSym = NULL;
      continue;
    }
    if (StaticSym->Module != NULL && StrCmp(StaticSym->Module, ModuleName) == 0) {
      return_code = OS_SUCCESS;
      break;
    }
    ++StaticSym;
  }
  return return_code;
}

I32 OS_ModuleAPI_Init()
{
  MemSet(OS_module_table, 0, sizeof(OS_module_table));
  return OS_SUCCESS;
}

I32 OS_ModuleLoad(U32 *module_id, U8 *module_name, U8 *filename, U32 flags)
{
  U8 translated_path[OS_MAX_LOCAL_PATH_LEN];
  I32 return_code;
  I32 filename_status;
  OS_object_token_t token;
  OS_module_internal_record_t *module;
  OS_common_record_t *grec;
  // "filename" is deliberately NOT checked: in certain configurations it can validly be null,
  // and OS_TranslatePath checks it below.
  if (module_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (module_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(module_name, 0, OS_MAX_API_NAME) == NULL)
    return OS_ERR_NAME_TOO_LONG;
  // Translate the filename FIRST and keep the status aside. This must happen before allocating
  // an object id, because both lock the global table and doing it after would double-lock. The
  // status may or may not matter, depending on whether the module turns out to be static.
  filename_status = OS_TranslatePath(filename, translated_path);
  return_code = OS_ObjectIdAllocateNew(LOCAL_OBJID_TYPE_MODULE, module_name, &token);
  if (return_code == OS_SUCCESS) {
    module = &OS_module_table[OS_ObjectIndexFromToken(&token)];
    // OS_OBJECT_INIT(token, module, module_name, module_name)
    MemSet(module, 0, sizeof(OS_module_internal_record_t));
    StrNCpy(module->module_name, module_name, OS_MAX_API_NAME - 1);
    grec = OS_ObjectIdGlobalFromToken(&token);
    grec->name_entry = module->module_name;
    module->flags = flags; // save user-supplied flags
    // A statically linked module is already effectively loaded, so a match here means success
    // with no further action. With the static loader disabled the list is empty and this
    // always returns OS_ERR_NAME_NOT_FOUND.
    return_code = OS_ModuleLoad_Static(module_name);
    if (return_code == OS_SUCCESS) {
      module->module_type = OS_MODULE_TYPE_STATIC;
    } else {
      // Not static, so the file must be loaded by the dynamic loader -- which means the
      // filename must be valid, and THIS is where filename_status is finally enforced.
      if (filename_status != OS_SUCCESS) {
        return_code = filename_status;
      } else {
        StrNCpy(module->file_name, filename, OS_MAX_PATH_LEN - 1);
        module->module_type = OS_MODULE_TYPE_DYNAMIC;
        return_code = OS_ModuleLoad_Impl(&token, translated_path);
      }
    }
    return_code = OS_ObjectIdFinalizeNew(return_code, &token, module_id);
  }
  return return_code;
}

I32 OS_ModuleUnload(U32 module_id)
{
  OS_module_internal_record_t *module;
  I32 return_code;
  OS_object_token_t token;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, LOCAL_OBJID_TYPE_MODULE, module_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    module = &OS_module_table[OS_ObjectIndexFromToken(&token)];
    // Only call the implementation if a file was actually loaded. A STATIC module is just a
    // placeholder -- there is no file to unload.
    if (module->module_type == OS_MODULE_TYPE_DYNAMIC)
      return_code = OS_ModuleUnload_Impl(&token);
    return_code = OS_ObjectIdFinalizeDelete(return_code, &token);
  }
  return return_code;
}

I32 OS_ModuleInfo(U32 module_id, OS_module_prop_t *module_info)
{
  OS_common_record_t *record;
  OS_common_record_t *base;
  OS_module_internal_record_t *module;
  I32 return_code;
  OS_object_token_t token;
  if (module_info == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  MemSet(module_info, 0, sizeof(OS_module_prop_t));
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_MODULE, module_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    // Base into a local first: indexing the parenthesised OS_global_*_table macro directly is
    // off by one in this compiler (docs/HOLYC_STRUCT_LIMITS.md).
    base = &OS_common_table[OS_MODULE_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
    module = &OS_module_table[OS_ObjectIndexFromToken(&token)];
    // NOTE no NULL guard on name_entry here, unlike OS_TaskGetInfo which has one.
    StrNCpy(module_info->name, record->name_entry, OS_MAX_API_NAME - 1);
    StrNCpy(module_info->filename, module->file_name, OS_MAX_PATH_LEN - 1);
    return_code = OS_ModuleGetInfo_Impl(&token, module_info);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_SymbolLookup(U64 *symbol_address, U8 *SymbolName)
{
  I32 return_code;
  I32 staticsym_status;
  if (symbol_address == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (SymbolName == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_SymbolLookup_Impl(symbol_address, SymbolName);
  // If the OS did not find it, or the loader is disabled, try the static table.
  if (return_code != OS_SUCCESS) {
    staticsym_status = OS_SymbolLookup_Static(symbol_address, SymbolName, NULL);
    // Only overwrite on SUCCESS; otherwise the low-level error survives, which is why a failed
    // lookup reports the backend's code and not OS_ERR_NOT_IMPLEMENTED.
    if (staticsym_status == OS_SUCCESS)
      return_code = staticsym_status;
  }
  return return_code;
}

I32 OS_ModuleSymbolLookup(U32 module_id, U64 *symbol_address, U8 *symbol_name)
{
  I32 return_code;
  I32 staticsym_status;
  OS_common_record_t *record;
  OS_common_record_t *base;
  OS_object_token_t token;
  if (symbol_address == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (symbol_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_MODULE, module_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    base = &OS_common_table[OS_MODULE_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
    return_code = OS_ModuleSymbolLookup_Impl(&token, symbol_address, symbol_name);
    if (return_code != OS_SUCCESS) {
      // look for a static symbol that also matches this module name
      staticsym_status = OS_SymbolLookup_Static(symbol_address, symbol_name, record->name_entry);
      if (staticsym_status == OS_SUCCESS)
        return_code = staticsym_status;
    }
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_SymbolTableDump(U8 *filename, I64 size_limit)
{
  I32 return_code;
  U8 translated_path[OS_MAX_LOCAL_PATH_LEN];
  OS_object_token_t token;
  if (filename == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_TranslatePath(filename, translated_path);
  if (return_code != OS_SUCCESS)
    return return_code;
  // Locking the global ensures only ONE symbol table dump can run at a time, and prevents
  // module load/unload during it. Because the calls are serialized this way, the underlying
  // implementation may safely keep state in globals. Note this uses TransactionInit/Cancel
  // directly rather than GetById -- there is no object being addressed, only the type lock.
  return_code = OS_ObjectIdTransactionInit(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_MODULE, &token);
  if (return_code != OS_SUCCESS)
    return return_code;
  return_code = OS_SymbolTableDump_Impl(translated_path, size_limit);
  OS_ObjectIdTransactionCancel(&token);
  return return_code;
}
#endif
