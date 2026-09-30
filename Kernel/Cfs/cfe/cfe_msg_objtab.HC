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

// 1:1 HolyC translation of cFE modules/msg/fsw/src/cfe_msg_objtab.c, with Target_ObjectTable_t
// from cmake/target/inc/target_objtab.h.
//
// Not code: one table entry. Every cFE core module defines exactly one of these, and ES walks
// the collected table at each lifecycle phase -- early init, task start, app cleanup. MSG is a
// utility module with no task, so every field but the name is deliberately absent, and that is
// the whole content of the file. It is translated because a port that skips the registration
// entries has modules that exist but are never started.
//
// ONE DEVIATION, and it is syntax only: the C uses a designated initializer, `{ .Name =
// "CFE_MSG" }`, which zero-fills the rest. HolyC has no designated initializers, so the same
// values are written positionally. The transcript prints all six fields to show they agree.
// HolyC also has no `const`, so the entry is writable here where the C's is not.
#ifndef CFE_MSG_OBJTAB_HC
#define CFE_MSG_OBJTAB_HC
// --- target_objtab.h ------------------------------------------------------------------------
class Target_ObjectTable
{
  U8 *Name;                    // Module name, e.g. "CFE_EVS"
  I32 (*EarlyInit)();          // Early initialization function; must not be NULL
  U0 (*TaskMain)();            // Task entry point; NULL for library-only modules
  I32 (*AppCleanupCb)(U32 Id); // Callback to invoke when external apps are stopped
  U32 Priority;                // Task priority; ignored if TaskMain is NULL
  U32 StackSize;               // Task stack size in bytes; ignored if TaskMain is NULL
};
// --- cfe_msg_objtab.c -----------------------------------------------------------------------
// this is a core library module with no task
Target_ObjectTable CFE_MSG_ModuleEntry = {"CFE_MSG", NULL, NULL, NULL, 0, 0};
#endif
