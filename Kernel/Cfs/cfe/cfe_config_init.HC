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

// 1:1 HolyC translation of cFE modules/config/fsw/src/cfe_config_init.c.
//
// This is the function that fills the configuration registry at startup, and it was the last
// thing blocking the `config` module. Not for translation reasons -- it needs three pieces of
// BUILD OUTPUT, and all three now exist:
//
//   GLOBAL_CONFIGDATA               cfe_target_config.HC, from tools/cfs/gen_target_config.py
//   CFE_CONFIGID_NAMETABLE and      cfe_configid_offset.HC, from tools/cfs/gen_configid_table.py
//     the CFE_CONFIGID_* id macros
//   CFE_Config_SetupPlatformConfigInfo   cfe_platformcfg_tables.HC, from
//                                        tools/cfs/gen_platform_config.py -- which runs NASA's
//                                        OWN generator rather than reimplementing it
//
// INCLUDE ORDER: cfe_resourceid.HC, then cfe_configid_offset.HC and cfe_config.HC, then
// cfe_target_config.HC, then cfe_platformcfg_tables.HC, then this.
//
// WHAT THE TRANSLATION SPELLS DIFFERENTLY, all syntax:
//
//   * `static const char IDNAME_PREFIX[] = "MOD_SRCVER_"` with `sizeof(IDNAME_PREFIX) - 1`.
//     A HolyC `U8 *` has sizeof 8, not the array's 12, so the length is a named constant. Same
//     value, and the string is written once.
//   * `CFE_ConfigName_t *ModuleListSet[2]` as a parameter is `CFE_ConfigName_t **`, which is
//     what C passes anyway.
//   * CFE_SRC_VERSION is `CFE_BUILD_BASELINE "+dev" CFE_STR(CFE_BUILD_NUMBER)` -- adjacent
//     string literals and the # stringification operator, neither of which HolyC has. Written
//     out as the resolved literal, with the pieces named in a comment so a version bump is
//     visible here.
//   * `toupper` is TempleOS's `ToUpper`, which is a compiler intrinsic (IC_TOUPPER) and so is
//     available even in the standalone oracle harness. Verified to agree with C's toupper on
//     the characters a config key can contain.
#ifndef CFE_CONFIG_INIT_HC
#define CFE_CONFIG_INIT_HC
// --- cfe_version.h ----------------------------------------------------------------------------
#define CFE_BUILD_NUMBER    1
#define CFE_BUILD_BASELINE  "v7.0.1"
#define CFE_BUILD_CODENAME  "Draco"
#define CFE_LAST_OFFICIAL   "v7.0.1"
#define CFE_MAJOR_VERSION   7
#define CFE_MINOR_VERSION   0
#define CFE_REVISION        1
#define CFE_MISSION_REV     0xFF
// CFE_BUILD_BASELINE "+dev" CFE_STR(CFE_BUILD_NUMBER)
#define CFE_SRC_VERSION     "v7.0.1+dev1"
#define CFE_CFG_MAX_VERSION_STR_LEN 256

// The define names are uppercase while the module names are likely lowercase
// C99 does not have a standard "strcasecmp" - must do it manually
Bool CFE_Config_StrCaseEq(U8 *c1, U8 *c2)
{
  while (*c1 != 0 && *c2 != 0) {
    if (ToUpper(*c1) != ToUpper(*c2))
      break;
    ++c1;
    ++c2;
  }

  return *c1 == 0 && *c2 == 0;
}

// Internal helper routine only, not part of API.
//
// Find value for given config key
U8 *CFE_Config_FindTargetKeyValue(CFE_ConfigKeyValue_t *ConfigList, U8 *KeyName)
{
  U8 *ValuePtr;

  ValuePtr = NULL;
  if (KeyName != NULL && ConfigList != NULL) {
    while (ConfigList->Key != NULL) {
      if (CFE_Config_StrCaseEq(KeyName, ConfigList->Key)) {
        ValuePtr = ConfigList->Value;
        break;
      }
      ++ConfigList;
    }
  }

  return ValuePtr;
}

U8 *CFE_Config_IsModuleInList(CFE_ConfigName_t *ModuleListPtr, U8 *ModuleName)
{
  U8 *Result;

  Result = NULL;
  while (ModuleListPtr != NULL && ModuleListPtr->Name != NULL) {
    if (CFE_Config_StrCaseEq(ModuleListPtr->Name, ModuleName)) {
      Result = ModuleListPtr->Name;
      break;
    }
    ++ModuleListPtr;
  }

  return Result;
}

U8 *CFE_Config_IsPspModule(CFE_StaticModuleLoadEntry_t *PspModuleList, U8 *ModuleName)
{
  U8 *Result;
  CFE_StaticModuleLoadEntry_t *ModuleListPtr;

  ModuleListPtr = PspModuleList;
  Result = NULL;
  while (ModuleListPtr != NULL && ModuleListPtr->Name != NULL) {
    if (CFE_Config_StrCaseEq(ModuleListPtr->Name, ModuleName)) {
      Result = ModuleListPtr->Name;
      break;
    }
    ++ModuleListPtr;
  }

  return Result;
}

// `CFE_ConfigName_t *ModuleListSet[]` in the C: an array of pointers, which decays to the same
// double pointer either way.
U8 *CFE_Config_FindStaticModName(CFE_ConfigName_t **ModuleListSet, I64 SetLength, U8 *ModuleName)
{
  U8 *Result;
  I64 i; // size_t

  Result = NULL;
  for (i = 0; i < SetLength; ++i) {
    Result = CFE_Config_IsModuleInList(ModuleListSet[i], ModuleName);
    if (Result != NULL)
      break;
  }

  return Result;
}

// `static const char IDNAME_PREFIX[] = "MOD_SRCVER_";` in the C, used as
// `sizeof(IDNAME_PREFIX) - 1`. A HolyC U8 * has sizeof 8, so the length is named.
#define IDNAME_PREFIX     "MOD_SRCVER_"
#define IDNAME_PREFIX_LEN 11

U0 CFE_Config_SetupModuleVersions(CFE_ConfigName_t **ModuleListSet, I64 SetLength,
                                  CFE_ConfigKeyValue_t *ActiveList)
{
  U8 *ModName;
  U8 *KeyVal;
  U32 OffsetVal;
  CFE_Config_IdNameEntry *NamePtr;

  NamePtr = CFE_CONFIGID_NAMETABLE;
  for (OffsetVal = 0; OffsetVal < CFE_ConfigIdOffset_MAX; ++OffsetVal) {
    if (NamePtr->Name != NULL && StrNCmp(NamePtr->Name, IDNAME_PREFIX, IDNAME_PREFIX_LEN) == 0) {
      ModName = NamePtr->Name + IDNAME_PREFIX_LEN;

      // skip modules which are not statically linked (version depends on dynamic load)
      ModName = CFE_Config_FindStaticModName(ModuleListSet, SetLength, ModName);
      if (ModName != NULL) {
        KeyVal = CFE_Config_FindTargetKeyValue(ActiveList, ModName);
        if (KeyVal != NULL)
          CFE_Config_SetString(CFE_Config_OffsetToId(OffsetVal), KeyVal);
      }
    }
    ++NamePtr;
  }
}

U0 CFE_Config_SetupBasicBuildInfo()
{
  U8 *KeyVal;
  U8 VersionString[CFE_CFG_MAX_VERSION_STR_LEN];

  // Global mission name
  CFE_Config_SetString(CFE_CONFIGID_MISSION_NAME, GLOBAL_CONFIGDATA.MissionName);
  KeyVal = CFE_Config_FindTargetKeyValue(GLOBAL_CONFIGDATA.ModuleVersionList, "MISSION");
  CFE_Config_SetString(CFE_CONFIGID_MISSION_SRCVER, KeyVal);

  // Global mission EDS runtime DB
  CFE_Config_SetObjPointer(CFE_CONFIGID_MISSION_EDS_DB, GLOBAL_CONFIGDATA.EdsDb);
  CFE_Config_SetObjPointer(CFE_CONFIGID_MISSION_SBINTF_DB, GLOBAL_CONFIGDATA.SbIntfDb);

  // Pass the TA pointer from the target config into the runtime DB
  CFE_Config_SetObjPointer(CFE_CONFIGID_TA_AFFINITY_TABLE, GLOBAL_CONFIGDATA.TaAffinityTable);

  // propagate the version numbers from version.h
  CFE_Config_SetValue(CFE_CONFIGID_CORE_VERSION_MAJOR, CFE_MAJOR_VERSION);
  CFE_Config_SetValue(CFE_CONFIGID_CORE_VERSION_MINOR, CFE_MINOR_VERSION);
  CFE_Config_SetValue(CFE_CONFIGID_CORE_VERSION_REVISION, CFE_REVISION);
  CFE_Config_SetValue(CFE_CONFIGID_CORE_VERSION_MISSION_REV, CFE_MISSION_REV);
  CFE_Config_SetValue(CFE_CONFIGID_CORE_VERSION_BUILDNUM, CFE_BUILD_NUMBER);

  CFE_Config_SetString(CFE_CONFIGID_CORE_VERSION_BASELINE, CFE_BUILD_BASELINE);
  CFE_Config_GetVersionString(VersionString, CFE_CFG_MAX_VERSION_STR_LEN, "cFE", CFE_SRC_VERSION,
                              CFE_BUILD_CODENAME, CFE_LAST_OFFICIAL);
  CFE_Config_SetString(CFE_CONFIGID_CORE_VERSION_DESCRIPTION, VersionString);

  // Initialize values from the "target_config" CFE internal object
  KeyVal = CFE_Config_FindTargetKeyValue(GLOBAL_CONFIGDATA.BuildEnvironment, "BUILDDATE");
  CFE_Config_SetString(CFE_CONFIGID_CORE_BUILDINFO_DATE, KeyVal);
  KeyVal = CFE_Config_FindTargetKeyValue(GLOBAL_CONFIGDATA.BuildEnvironment, "BUILDUSER");
  CFE_Config_SetString(CFE_CONFIGID_CORE_BUILDINFO_USER, KeyVal);
  KeyVal = CFE_Config_FindTargetKeyValue(GLOBAL_CONFIGDATA.BuildEnvironment, "BUILDHOST");
  CFE_Config_SetString(CFE_CONFIGID_CORE_BUILDINFO_HOST, KeyVal);
}

I32 CFE_Config_Init()
{
  // The C declares this array mid-block, after the memset. Declarations come first in HolyC, so
  // it is declared here and FILLED where the C declares it, which keeps the order of operations.
  CFE_ConfigName_t *ModuleListSet[2];

  // Clear the table, just in case it was not already cleared from initial program loading
  MemSet(&CFE_Config_Global, 0, sizeof(CFE_Config_Global_t));

  ModuleListSet[0] = GLOBAL_CONFIGDATA.CoreModuleList;
  ModuleListSet[1] = GLOBAL_CONFIGDATA.StaticAppList;

  // Create a fixed string that can be returned in place of NULL for string returns,
  // this makes it safer/easier to use with printf-style calls
  CFE_Config_Global.UnknownString = "[unknown]";

  CFE_Config_SetupBasicBuildInfo();
  CFE_Config_SetupModuleVersions(ModuleListSet, 2, GLOBAL_CONFIGDATA.ModuleVersionList);
  CFE_Config_SetupPlatformConfigInfo();

  return CFE_SUCCESS;
}
#endif
