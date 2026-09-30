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

// PARTIAL translation of OSAL src/os/shared/src/osapi-common.c -- ONLY the two definitions that
// osapi-idmap.c needs, plus the shared-state type from src/os/shared/inc/os-shared-common.h.
//
// THIS FILE IS DELIBERATELY NOT IN THE GATE, and that is the honest way to carry a partial
// translation here. tools/cfs/check_coverage.py is all-or-nothing per NASA source: the moment
// osapi-common.c joins the gate's source list, every function it defines must exist. So it
// stays out until the remaining ~430 lines (OS_API_Init, the shutdown path, the console and
// task registry) are translated, and until then nothing claims this module is done.
//
// What IS here is what idmap reaches for: the global state record, the event notifier it calls
// when a resource is allocated, created or deleted, and OS_strnlen.
#ifndef OSAPI_COMMON_HC
#define OSAPI_COMMON_HC
#include "os_shared_idmap.HC"
#include "../CfsStr.HC"
// --- os-shared-common.h ------------------------------------------------------------------------
#define OS_INIT_MAGIC_NUMBER     0xBE57C0DE
#define OS_SHUTDOWN_MAGIC_NUMBER 0xABADC0DE
#define OS_MAX_EVENT_HANDLER     4
// OS_Event_t values, from osapi-common.h, in NASA's declaration order -- the numbering is what
// a handler sees, so it is not free to differ.
#define OS_EVENT_RESERVED          0
#define OS_EVENT_RESOURCE_ALLOCATED 1
#define OS_EVENT_RESOURCE_CREATED   2
#define OS_EVENT_RESOURCE_DELETED   3
#define OS_EVENT_TASK_STARTUP       4
#define OS_EVENT_MAX                5

// TWO HOLYC LIMITS SHAPE THIS, both measured rather than worked around blindly:
//
//   1. There is no array-of-function-pointers syntax. `I32 (*h[4])(...)` does not parse at any
//      scope. A single function-pointer MEMBER is fine, so the array becomes an array of a
//      one-member wrapper class -- same storage, same layout, one extra `.fn` at each use.
//   2. A function pointer held in a class member cannot be CALLED in place. Both
//      `g.h[0].fn(...)` and `sp->fn(...)` are parse errors; copying it to a local typed
//      variable first and calling that works. So every indirect call below goes through a
//      local, which is why they look more verbose than the C.
class OS_EventHandlerSlot
{
  I32 (*fn)(I64, U32, U8 *);
};

class OS_shared_global_vars
{
  U32 GlobalState; // volatile in the C; HolyC has no volatile, and nothing here caches it
  U32 PrintfConsoleId;
  Bool PrintfEnabled;
  U32 MicroSecPerTick;
  U32 TicksPerSecond;
  OS_EventHandlerSlot EventHandler[OS_MAX_EVENT_HANDLER];
  // uint8 DebugLevel sits here in the C, under #ifdef OSAL_CONFIG_DEBUG_PRINTF, which this
  // configuration does not set -- the same switch that keeps osapi-debug.c out of OSAL_SRCLIST.
  // Omitted rather than translated, because including it would change the layout.
  U32 CoresConfigured;
};

OS_shared_global_vars OS_SharedGlobalVars;
// --- osapi-common.c ------------------------------------------------------------------------------
I32 OS_NotifyEvent(I64 event, U32 object_id, U8 *data)
{
  I32 Status = OS_SUCCESS;
  I32 ReturnCode;
  I64 i;
  I32 (*handler)(I64, U32, U8 *);
  for (i = 0; i < OS_MAX_EVENT_HANDLER; i++) {
    handler = OS_SharedGlobalVars.EventHandler[i].fn;
    if (handler != NULL) {
      ReturnCode = handler(event, object_id, data);
      if (ReturnCode != OS_SUCCESS)
        Status = OS_ERROR;
    }
  }
  return Status;
}

// A bounded strlen. OSAL has its own because C's strnlen is POSIX rather than C99, and a
// freestanding target may not have it -- which is exactly this port's situation.
I64 OS_strnlen(U8 *s, I64 maxlen)
{
  U8 *end = MemChr(s, 0, maxlen);
  if (end != NULL) {
    // actual length is where the terminator was found
    maxlen = end - s;
  }
  return maxlen;
}
#endif
