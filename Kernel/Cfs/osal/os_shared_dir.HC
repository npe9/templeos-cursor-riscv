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

// 1:1 HolyC translation of the directory types, from OSAL src/os/shared/inc/os-shared-dir.h and
// the public type in src/os/inc/osapi-dir.h. Separate from the implementation so a backend can
// declare its _Impl functions first; see os_shared_errors.HC for why include order does that.
#ifndef OS_SHARED_DIR_HC
#define OS_SHARED_DIR_HC
#include "osconfig.HC"

class OS_dir_internal_record_t
{
  U8 dir_name[OS_MAX_PATH_LEN];
};

class os_dirent_t
{
  U8 FileName[OS_MAX_FILE_NAME];
};
#endif
