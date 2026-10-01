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

// 1:1 HolyC translation of cFE modules/fs/fsw/src/cfe_fs_objtab.c.
//
// One table entry, and the first one in this translation with a NON-NULL hook: FS is a
// library-only module with no task, but it does have global data, so ES calls its EarlyInit
// during the early initialization phase. Target_ObjectTable comes from cfe_msg_objtab.HC --
// include that first.
//
// The same single deviation as every other objtab here, and it is syntax only: the C uses a
// designated initializer, `{ .Name = "CFE_FS", .EarlyInit = CFE_FS_EarlyInit }`, which
// zero-fills the rest. HolyC has no designated initializers, so the values are positional.
// HolyC also has no `const`, so this entry is writable where the C's is not.
#ifndef CFE_FS_OBJTAB_HC
#define CFE_FS_OBJTAB_HC
// this is a core library module with no task, but it does have a global data struct
Target_ObjectTable CFE_FS_ModuleEntry = {"CFE_FS", &CFE_FS_EarlyInit, NULL, NULL, 0, 0};
#endif
