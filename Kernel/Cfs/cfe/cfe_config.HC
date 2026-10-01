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

// 1:1 HolyC translation of the cFE CONFIG module's API: cfe_config_lookup.c, cfe_config_get.c,
// cfe_config_set.c, cfe_config_eds_disabled.c and cfe_config_objtab.c, with the types from
// modules/config/fsw/inc/cfe_config_table.h, cfe_config_nametable.h and
// modules/core_api/fsw/inc/cfe_config_api_typedefs.h.
//
// WHAT THIS MODULE IS: a fixed-size key/value registry for build-time configuration -- mission
// name, version numbers, per-module source revisions, a few platform sizes. Each key is a
// resource id, so it is the first consumer of the resourceid module translated beside it.
//
// WHAT IS DELIBERATELY NOT HERE: cfe_config_init.c, 241 lines. It populates the table from
// GLOBAL_CONFIGDATA, a structure the BUILD generates and the linker supplies, describing the
// target's module list and version strings. Translating the code without that artifact would
// produce something that compiles and can never run, so the boundary is drawn where the data
// stops being NASA's. The API below is complete and testable without it: Set* fills the table,
// Get* reads it, which is exactly what Init would have driven. The gate's coverage check only
// looks at sources the gate compiles, so cfe_config_init.c is absent from both sides rather
// than half-present in one.
//
// THE KEY SET IS GENERATED, and that deserves saying plainly. CMake produces the id enum and
// the name table from NASA's config_ids_base.cmake and tool/config_ids_dynamic.cmake.
// tools/cfs/gen_configid_table.py does that same job with the same lists and the same
// templates, emitting the C files a real build would and the HolyC half in
// cfe_configid_offset.HC. The ids are NASA's; only the mechanism is ours. The one
// mission-dependent part is the MOD_SRCVER_ entries, which follow MISSION_CORE_INTERFACES and
// MISSION_CORE_MODULES from cmake/mission_defaults.cmake with no mission apps -- 34 ids.
#ifndef CFE_CONFIG_HC
#define CFE_CONFIG_HC
#include "cfe_resourceid.HC"
#include "../CfsStr.HC"
#include "cfe_configid_offset.HC"
// From cfe_core_resourceid_basevalues.h: CFE_RESOURCEID_MAKE_BASE(OS_OBJECT_TYPE_USER + 7),
// which with OS_OBJECT_TYPE_USER 0x10 and the SIMPLE variant's MARK of 0 is (0x17 << 16).
#define CFE_CONFIGID_BASE (0x17 << CFE_RESOURCEID_SHIFT)
// From cfe_version.h. 0xFF is the development-build marker, which is what an unreleased
// checkout reports -- and it selects the "DEV BUILD, based on ..." branch below.
#define CFE_MISSION_REV 0xFF
// --- cfe_config_table.h ----------------------------------------------------------------------
#define CFE_ConfigType_UNDEFINED 0
#define CFE_ConfigType_VALUE     1 // Value is an unsigned int
#define CFE_ConfigType_STRING    2 // Value is a string pointer
#define CFE_ConfigType_POINTER   3 // Value is a non-string object pointer
#define CFE_ConfigType_ARRAY     4 // Value is a combination of length and pointer

union CFE_Config_ValueBuffer
{
  U32 AsInteger;
  U8 *AsPointer;
};

class CFE_Config_ValueEntry
{
  I32 ActualType; // CFE_ConfigType_t, a C ENUM -- 4 bytes
  U8 _pad0[4]; // C pads here; HolyC packs. See tools/cfs/check_padding.py
  CFE_Config_ValueBuffer Datum;
};
// --- cfe_config_api_typedefs.h ----------------------------------------------------------------
// CFE_ConfigId_t wraps a resource id. With the SIMPLE resourceid variant that is a bare U32, so
// CFE_CONFIGID_C is the identity and leaves no trace, exactly as CFE_RESOURCEID_WRAP does.
class CFE_Config_ArrayValue
{
  I64 NumElements;
  U8 *ElementPtr;
};
// typedef void (*CFE_Config_Callback_t)(void *Arg, CFE_ConfigId_t Id, const char *Name);
// spelled out at the one parameter that takes it.
#define CFE_CONFIGID_UNDEFINED CFE_RESOURCEID_UNDEFINED
// --- cfe_config_priv.h -------------------------------------------------------------------------
class CFE_Config_Global_t
{
  U8 *UnknownString;
  CFE_Config_ValueEntry Table[CFE_ConfigIdOffset_MAX];
};

CFE_Config_Global_t CFE_Config_Global;

U32 CFE_Config_IdToOffset(U32 ConfigId)
{
  U32 OffsetVal;
  OffsetVal = CFE_ResourceId_ToInteger(ConfigId);
  OffsetVal -= CFE_CONFIGID_BASE;
  return OffsetVal;
}

U32 CFE_Config_OffsetToId(U32 OffsetVal)
{
  return CFE_ResourceId_FromInteger(CFE_CONFIGID_BASE + OffsetVal);
}
// --- cfe_config_lookup.c -------------------------------------------------------------------
// The whole of the lookup unit: one bounds check and one index. Note the check is UNSIGNED, so
// an id below the base wraps to a huge offset and is refused by the same comparison -- the same
// trick CFE_ResourceId_ToIndex uses, and it needs the same 32-bit narrowing to work.
CFE_Config_ValueEntry *CFE_Config_LocateConfigRecordByID(U32 ConfigId)
{
  U32 OffsetVal;
  OffsetVal = CFE_Config_IdToOffset(ConfigId);
  if (OffsetVal >= CFE_ConfigIdOffset_MAX)
    return NULL;
  return &CFE_Config_Global.Table[OffsetVal];
}
// From cfe_config_eds.h, defined at the bottom of this file with its own unit.
U8 *CFE_Config_EdsState(U8 *ComponentName);
// --- cfe_config_get.c ------------------------------------------------------------------------
U32 CFE_Config_GetValue(U32 ConfigId)
{
  CFE_Config_ValueEntry *Entry;
  Entry = CFE_Config_LocateConfigRecordByID(ConfigId);
  if (Entry == NULL || Entry->ActualType != CFE_ConfigType_VALUE)
    return 0;
  return Entry->Datum.AsInteger;
}

U8 *CFE_Config_GetObjPointer(U32 ConfigId)
{
  CFE_Config_ValueEntry *Entry;
  Entry = CFE_Config_LocateConfigRecordByID(ConfigId);
  if (Entry == NULL ||
      (Entry->ActualType != CFE_ConfigType_POINTER && Entry->ActualType != CFE_ConfigType_STRING))
    return NULL;
  return Entry->Datum.AsPointer;
}

// THE ONE SIGNATURE IN THIS PORT THAT IS NOT NASA'S, and it is the compiler's fault rather than
// a translation choice. The C returns CFE_Config_ArrayValue_t BY VALUE:
//
//     CFE_Config_ArrayValue_t CFE_Config_GetArrayValue(CFE_ConfigId_t ConfigId)
//
// That class is 16 bytes, and this compiler has no struct-return ABI: a return loads the value
// into a0 with one `ld` and the caller stores it with one `sd`, which is right for 8 bytes and
// silently truncates anything larger. Measured before changing anything -- a 12-byte class loses
// its third field, a 16-byte one hands back a field pair where a pointer belongs, and the first
// use of it faults. The compiler now REFUSES such a return with a diagnostic instead of
// miscompiling it, so this signature could not stay as NASA wrote it.
//
// The deviation is the smallest one available: the returned value becomes an out-parameter, the
// body is otherwise unchanged, and the differential transcript still compares the same numbers
// coming out of both languages. When the struct-return ABI lands, this reverts to the C's shape
// and the transcript will not notice, which is the point of having it.
U0 CFE_Config_GetArrayValue(U32 ConfigId, CFE_Config_ArrayValue *Out)
{
  CFE_Config_ValueEntry *Entry;
  Out->NumElements = 0;
  Out->ElementPtr = NULL;
  Entry = CFE_Config_LocateConfigRecordByID(ConfigId);
  if (Entry == NULL || Entry->ActualType != CFE_ConfigType_ARRAY)
    return;
  // FIELD BY FIELD, not `*Out = *src`. That form is the second compiler limitation this one
  // function ran into: a struct copy through pointers writes only the first eight bytes, so
  // NumElements arrived and ElementPtr stayed NULL. Local-to-local `y = x` is fine -- the
  // block-copy path requires the left side to be a class INSTANCE, and a dereferenced pointer
  // is not one. Reproduction and the reason a first fix was reverted are in
  // docs/CFS_UPSTREAM_NOTES.md; nothing else in this tree copies a struct through pointers,
  // which is why it had never shown up.
  Out->NumElements = Entry->Datum.AsPointer(CFE_Config_ArrayValue *)->NumElements;
  Out->ElementPtr = Entry->Datum.AsPointer(CFE_Config_ArrayValue *)->ElementPtr;
}

U8 *CFE_Config_GetString(U32 ConfigId)
{
  CFE_Config_ValueEntry *Entry;
  Entry = CFE_Config_LocateConfigRecordByID(ConfigId);
  if (Entry == NULL || Entry->ActualType != CFE_ConfigType_STRING)
    return CFE_Config_Global.UnknownString;
  return Entry->Datum.AsPointer;
}

U8 *CFE_Config_GetName(U32 ConfigId)
{
  U32 OffsetVal;
  OffsetVal = CFE_Config_IdToOffset(ConfigId);
  if (OffsetVal >= CFE_ConfigIdOffset_MAX)
    return CFE_Config_Global.UnknownString;
  return CFE_CONFIGID_NAMETABLE[OffsetVal];
}

U32 CFE_Config_GetIdByName(U8 *Name)
{
  U32 OffsetVal;
  if (Name == NULL)
    return CFE_CONFIGID_UNDEFINED;
  for (OffsetVal = 0; OffsetVal < CFE_ConfigIdOffset_MAX; OffsetVal++) {
    if (CFE_CONFIGID_NAMETABLE[OffsetVal] != NULL &&
        StrCmp(CFE_CONFIGID_NAMETABLE[OffsetVal], Name) == 0)
      break;
  }
  if (OffsetVal >= CFE_ConfigIdOffset_MAX)
    return CFE_CONFIGID_UNDEFINED;
  return CFE_Config_OffsetToId(OffsetVal);
}

U0 CFE_Config_IterateAll(U8 *Arg, U0 (*Callback)(U8 *, U32, U8 *))
{
  U32 OffsetVal;
  for (OffsetVal = 0; OffsetVal < CFE_ConfigIdOffset_MAX; OffsetVal++) {
    if (CFE_Config_Global.Table[OffsetVal].ActualType != CFE_ConfigType_UNDEFINED)
      Callback(Arg, CFE_Config_OffsetToId(OffsetVal), CFE_CONFIGID_NAMETABLE[OffsetVal]);
  }
}
// The two version-string helpers -- the widest use of formatting in the translated sources.
// They call StrPrintN (Kernel/Cfs/CfsStr.HC), the size-bounded formatter, so the call sites
// below stay character-for-character what NASA wrote, format strings included, instead of
// hand-built strings that merely produce the same bytes. TempleOS's own StrPrint/StrPrintJoin
// are the right thing in the kernel but neither is size-bounded and StrPrintJoin allocates.
U0 CFE_Config_GetMissionRevString(U8 *Buf, I64 Size, U8 MissionRev, U8 *LastOffcRel)
{
  if (MissionRev == 0) {
    // Mission Revision 0 is reserved only for official releases from the CFS development team
    // that have gone through the full release process
    StrPrintN(Buf, Size, "%s Official Release", LastOffcRel);
  } else if (MissionRev == 0xFF) {
    // Mission Revision 255 (0xFF) is reserved for use by the CFS development team for
    // evaluation builds (refer to git commit ID for more specific information about the build).
    StrPrintN(Buf, Size, "DEV BUILD, based on %s", LastOffcRel);
  } else {
    // Mission Rev values 1-254 are for user customizations. CFS users are free to set this
    // value in any way that is meaningful to them.
    StrPrintN(Buf, Size, "M%u, based on %s", MissionRev, LastOffcRel);
  }
}

U0 CFE_Config_GetVersionString(U8 *Buf, I64 Size, U8 *Component, U8 *SrcVersion, U8 *CodeName,
                               U8 *LastOffcRel)
{
  U8 RevInfo[32];
  CFE_Config_GetMissionRevString(RevInfo, sizeof(RevInfo), CFE_MISSION_REV, LastOffcRel);
  StrPrintN(Buf, Size, "%s %s (%s) %s, EDS %s", Component, SrcVersion, CodeName, RevInfo,
           CFE_Config_EdsState(Component));
}
// --- cfe_config_set.c ------------------------------------------------------------------------
U0 CFE_Config_SetValue(U32 ConfigId, U32 Value)
{
  CFE_Config_ValueEntry *Entry;
  Entry = CFE_Config_LocateConfigRecordByID(ConfigId);
  if (Entry != NULL) {
    Entry->ActualType = CFE_ConfigType_VALUE;
    Entry->Datum.AsInteger = Value;
  }
}

U0 CFE_Config_SetObjPointer(U32 ConfigId, U8 *Ptr)
{
  CFE_Config_ValueEntry *Entry;
  Entry = CFE_Config_LocateConfigRecordByID(ConfigId);
  if (Entry != NULL) {
    Entry->ActualType = CFE_ConfigType_POINTER;
    Entry->Datum.AsPointer = Ptr;
  }
}

U0 CFE_Config_SetArrayValue(U32 ConfigId, CFE_Config_ArrayValue *ArrayPtr)
{
  CFE_Config_ValueEntry *Entry;
  Entry = CFE_Config_LocateConfigRecordByID(ConfigId);
  if (Entry != NULL) {
    Entry->ActualType = CFE_ConfigType_ARRAY;
    Entry->Datum.AsPointer = ArrayPtr(U8 *);
  }
}

U0 CFE_Config_SetString(U32 ConfigId, U8 *Ptr)
{
  CFE_Config_ValueEntry *Entry;
  Entry = CFE_Config_LocateConfigRecordByID(ConfigId);
  if (Entry != NULL) {
    Entry->ActualType = CFE_ConfigType_STRING;
    Entry->Datum.AsPointer = Ptr;
  }
}
// --- cfe_config_eds_disabled.c ----------------------------------------------------------------
// The build picks this or cfe_config_eds_enabled.c on CFE_EDS_ENABLED; this is the default.
U8 *CFE_Config_EdsState(U8 *ComponentName)
{
  return "disabled";
}
// --- cfe_config_objtab.c IS NOT TRANSLATED, and the reason is worth recording ---------------
// Unlike msg's and sbr's registration entries, which carry only a name, config's is
//     { .Name = "CFE_CONFIG", .EarlyInit = CFE_Config_Init }
// so the entry POINTS AT the one file this port has not translated. Translating it would mean
// aiming EarlyInit at nothing, which is worse than leaving it out: ES walks that table at
// startup and calls what it finds. The C link says the same thing -- compiling objtab.c
// without init.c fails with an undefined CFE_Config_Init, which is how this came up.
//
// So the boundary this module can be cut at is narrower than "everything except init": the
// registration entry goes with init, and both wait for GLOBAL_CONFIGDATA.
#endif
