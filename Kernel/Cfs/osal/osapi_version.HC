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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-version.c, with the constants from
// src/os/inc/osapi-version.h.
//
// ONE DEVIATION, forced by a preprocessor gap and measured rather than assumed. The C builds its
// version string by stringifying a number:
//
//     #define OS_STR_HELPER(x) #x
//     #define OS_STR(x)        OS_STR_HELPER(x)
//     #define OS_VERSION       OS_BUILD_BASELINE "+dev" OS_STR(OS_BUILD_NUMBER)
//
// HolyC concatenates adjacent string literals correctly -- "ab" "cd" really is "abcd", tested --
// but its `#x` stringifies the PARAMETER NAME without expanding the argument first, so the usual
// two-level trick yields "NUM" where C yields "1". So OS_VERSION is written out as the string
// those macros compute. The oracle compares it against what NASA's C actually produces, which is
// what makes writing it out safe rather than a guess.
#ifndef OSAPI_VERSION_HC
#define OSAPI_VERSION_HC
// --- osapi-version.h -------------------------------------------------------------------------
#define OS_MAJOR_VERSION   7
#define OS_MINOR_VERSION   0
#define OS_REVISION        1   // 99 indicates a development version
#define OS_MISSION_REV     0xFF
#define OS_BUILD_NUMBER    1
#define OS_BUILD_CODENAME  "Draco"
#define OS_BUILD_BASELINE  "v7.0.1"
// OS_BUILD_BASELINE "+dev" OS_STR(OS_BUILD_NUMBER) -- see the note above on why this is spelled
// out. If OS_BUILD_NUMBER or the baseline moves, this moves with it and the gate says so.
#define OS_VERSION         "v7.0.1+dev1"
// --- osapi-version.c -------------------------------------------------------------------------
U8 *OS_GetVersionString()
{
  return OS_VERSION;
}

U8 *OS_GetVersionCodeName()
{
  return OS_BUILD_CODENAME;
}

U0 OS_GetVersionNumber(U8 *VersionNumbers)
{
  VersionNumbers[0] = OS_MAJOR_VERSION;
  VersionNumbers[1] = OS_MINOR_VERSION;
  VersionNumbers[2] = OS_REVISION;
  VersionNumbers[3] = OS_MISSION_REV;
}

U32 OS_GetBuildNumber()
{
  return OS_BUILD_NUMBER;
}
#endif
