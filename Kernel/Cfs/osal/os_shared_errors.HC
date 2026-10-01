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

// 1:1 HolyC translation of OSAL src/os/shared/inc/os-shared-errors.h.
//
// A separate file for the same reason the C has a separate header: the error-name TABLE is
// supplied by the backend, not by the portable layer, so the type has to be visible before the
// backend can define its table and before the portable layer can walk it.
//
// ORDERING IS LOAD-BEARING HERE, in a way it is not in C. There the linker resolves
// OS_IMPL_ERROR_NAME_TABLE whichever order the objects appear; HolyC is single-pass and an
// `extern` array is a MODULE-LOCAL DUMMY rather than a reference to someone else's definition
// -- that is a recorded property of this compiler, and using `extern` here read address 4 and
// faulted. So a consumer must, in order:
//     #include "os_shared_errors.HC"     // this file: the type
//     OS_ErrorTable_Entry OS_IMPL_ERROR_NAME_TABLE[] = {...};   // the backend's table
//     #include "osapi_errors.HC"          // the portable layer that walks it
// which is the include order standing in for what the linker would have done.
#ifndef OS_SHARED_ERRORS_HC
#define OS_SHARED_ERRORS_HC
class OS_ErrorTable_Entry
{
  I32 Number;
  // C pads here; HolyC packs. See tools/cfs/check_padding.py. A SCALAR rather than the usual
  // `U8 _pad0[4]` because this is the one padded struct with positional INITIALIZERS -- and an
  // array member in an aggregate initializer does not parse (HOLYC_STRUCT_LIMITS.md #8). The
  // tables below therefore carry an explicit 0 where NASA's C, with designated initializers,
  // skips the padding silently.
  U32 _pad0;
  U8 *Name;
};
#endif
