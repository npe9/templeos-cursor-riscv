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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-common.c.
//
// This file was PARTIAL for most of the port and deliberately out of the gate, because
// check_coverage.py is all-or-nothing per NASA source. It was completed LAST on purpose --
// OS_API_Init calls every other module's initialiser, so each module translated before it
// removed a stub from it.
//
// INCLUDE POSITION MATTERS AND IS NOT FREE. osapi_idmap.HC includes this file, because idmap
// needs OS_SharedGlobalVars and OS_NotifyEvent, which puts it very early -- long before the
// modules OS_API_Init drives. That works because the compiler patches a forward reference
// through the blob's import slots, filling each from the definition's own address once the
// unit is complete. Moving it later does NOT work: the AOT entry chunk is emitted FIRST and
// performs those patch-ups, so a definition that appears after it is never wired, and the
// program returns without reaching main. Splitting the file in two was tried and reverted for
// the same reason -- every placement of the second half traded one set of unresolved imports
// for another.
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
  U8 _pad0[3]; // C pads here; HolyC packs. See tools/cfs/check_padding.py
  U32 MicroSecPerTick;
  U32 TicksPerSecond;
  U8 _pad1[4]; // C pads here; HolyC packs. See tools/cfs/check_padding.py
  OS_EventHandlerSlot EventHandler[OS_MAX_EVENT_HANDLER];
  // uint8 DebugLevel sits here in the C, under #ifdef OSAL_CONFIG_DEBUG_PRINTF, which this
  // configuration does not set -- the same switch that keeps osapi-debug.c out of OSAL_SRCLIST.
  // Omitted rather than translated, because including it would change the layout.
  U32 CoresConfigured;
  U8 _pad2[4]; // C rounds the struct up to its alignment; HolyC does not
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

// EVERYTHING OS_API_Init AND OS_CleanUpObject REACCH FOR, declared ahead of use.
//
// In C these come from a dozen os-shared-*.h headers and the linker resolves them. Here the
// include order does a linker's job, and this file sits EARLY -- osapi_idmap.HC includes it,
// because idmap needs OS_SharedGlobalVars and OS_NotifyEvent -- while the modules it drives are
// included long afterwards. So the declarations go here rather than reordering the whole file
// set around one function.
I32 OS_ObjectIdInit();
U32 OS_IdentifyObject(U32 object_id);
U0 OS_ForEachObject(U32 creator_id, U0 (*callback_ptr)(U32, U8 *), U8 *callback_arg);
U0 OS_ForEachObjectOfType(U32 objtype, U32 creator_id, U0 (*callback_ptr)(U32, U8 *),
                          U8 *callback_arg);
// The per-object-type initialisers, in the order OS_API_Init calls them.
I32 OS_TaskAPI_Init();
I32 OS_QueueAPI_Init();
I32 OS_BinSemAPI_Init();
I32 OS_CountSemAPI_Init();
I32 OS_MutexAPI_Init();
I32 OS_ModuleAPI_Init();
I32 OS_TimeBaseAPI_Init();
I32 OS_TimerCbAPI_Init();
I32 OS_FileAPI_Init();
I32 OS_DirAPI_Init();
I32 OS_FileSysAPI_Init();
I32 OS_ConsoleAPI_Init();
I32 OS_CondVarAPI_Init();
I32 OS_NetworkAPI_Init();
I32 OS_SocketAPI_Init();
// The deletes OS_CleanUpObject dispatches to.
I32 OS_TaskDelete(U32 task_id);
I32 OS_QueueDelete(U32 queue_id);
I32 OS_BinSemDelete(U32 sem_id);
I32 OS_CountSemDelete(U32 sem_id);
I32 OS_MutSemDelete(U32 sem_id);
I32 OS_ModuleUnload(U32 module_id);
I32 OS_TimeBaseDelete(U32 timebase_id);
I32 OS_TimerDelete(U32 timer_id);
I32 OS_close(U32 filedes);
I32 OS_DirectoryClose(U32 dir_id);
I32 OS_CondVarDelete(U32 var_id);
I32 OS_TaskDelay(U32 millisecond);

// The backend seam. Declared before use because HolyC is single-pass.
I32 OS_API_Impl_Init(U32 idtype);
U0 OS_IdleLoop_Impl();
U0 OS_ApplicationShutdown_Impl();

// Forward declarations for the two mutual references below: OS_API_Teardown calls
// OS_DeleteAllObjects and OS_ApplicationShutdown, both defined after it in NASA's file order.
U0 OS_DeleteAllObjects();
U0 OS_ApplicationShutdown(U8 flag);

I32 OS_API_Init()
{
  I32 return_code = OS_SUCCESS;
  U32 idtype;
  U32 microSecPerSec;
  // Already initialized is not really a problem -- it happens validly when tests run on a
  // platform without a reset between invocations -- so this just returns. NASA logs it through
  // OS_DEBUG, which is a no-op in this configuration.
  if (OS_SharedGlobalVars.GlobalState == OS_INIT_MAGIC_NUMBER)
    return OS_SUCCESS;
  // Wipe the global state to be sure everything is clean.
  MemSet(&OS_SharedGlobalVars, 0, sizeof(OS_shared_global_vars));
  // OS_SharedGlobalVars.DebugLevel = 1 goes here under #ifdef OSAL_CONFIG_DEBUG_PRINTF, which
  // this configuration does not set -- the same switch that omits the field entirely.
  OS_SharedGlobalVars.GlobalState = OS_INIT_MAGIC_NUMBER;
  // The common table everything else shares.
  return_code = OS_ObjectIdInit;
  if (return_code != OS_SUCCESS)
    return return_code;
  idtype = 0;
  while (idtype < OS_OBJECT_TYPE_USER) {
    // The IMPLEMENTATION first, because the shared layer depends on it.
    return_code = OS_API_Impl_Init(idtype);
    if (return_code != OS_SUCCESS)
      break;
    // One shared-layer initialiser per object type. Every one of these is a module translated
    // before this file, which is why it came last.
    if (idtype == OS_OBJECT_TYPE_OS_TASK)
      return_code = OS_TaskAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_QUEUE)
      return_code = OS_QueueAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_BINSEM)
      return_code = OS_BinSemAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_COUNTSEM)
      return_code = OS_CountSemAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_MUTEX)
      return_code = OS_MutexAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_MODULE)
      return_code = OS_ModuleAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_TIMEBASE)
      return_code = OS_TimeBaseAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_TIMECB)
      return_code = OS_TimerCbAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_STREAM)
      return_code = OS_FileAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_DIR)
      return_code = OS_DirAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_FILESYS)
      return_code = OS_FileSysAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_CONSOLE)
      return_code = OS_ConsoleAPI_Init;
    else if (idtype == OS_OBJECT_TYPE_OS_CONDVAR)
      return_code = OS_CondVarAPI_Init;
    // NOTE there is no case for OS_OBJECT_TYPE_OS_RWLOCK: rwlocks have no per-type
    // initialiser in this switch, and OS_RwLockAPI_Init is never called from here. Translated
    // as written.
    if (return_code != OS_SUCCESS)
      break;
    ++idtype;
  }
  // Network and sockets are initialised OUTSIDE the per-type loop, because they are not keyed
  // to an object type.
  if (return_code == OS_SUCCESS)
    return_code = OS_NetworkAPI_Init;
  if (return_code == OS_SUCCESS)
    return_code = OS_SocketAPI_Init;
  // Confirm that somewhere during initialization the time variables got set to something
  // valid. A backend that forgets is the failure this catches.
  if (return_code == OS_SUCCESS &&
      (OS_SharedGlobalVars.MicroSecPerTick == 0 || OS_SharedGlobalVars.TicksPerSecond == 0))
    return_code = OS_ERROR;
  microSecPerSec = OS_SharedGlobalVars.MicroSecPerTick * OS_SharedGlobalVars.TicksPerSecond;
  if (microSecPerSec != 1000000) {
    // NASA warns through OS_DEBUG here and CONTINUES -- a tick rate that does not multiply out
    // to a second is suspicious but not fatal. The warning is a no-op in this configuration,
    // so the only translated effect is that return_code is left alone.
  }
  if (return_code != OS_SUCCESS) {
    // Part of init failed, so mark OSAL as shutting down. In particular this makes any
    // internal resources already created (the console utility task, say) self-exit, returning
    // the system to the state it started in.
    OS_SharedGlobalVars.GlobalState = OS_SHUTDOWN_MAGIC_NUMBER;
  }
  return return_code;
}

U0 OS_API_Teardown()
{
  // Delete any remaining user-created objects and tasks.
  OS_DeleteAllObjects;
  // Then make the "internal" objects exit and prevent any new ones being created.
  OS_ApplicationShutdown(TRUE);
}

I32 OS_RegisterEventHandler(I32 (*handler)(I64, U32, U8 *))
{
  I64 i;
  I32 Status = OS_ERROR;
  if (handler == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // First free slot wins; a full table returns the initial OS_ERROR.
  i = 0;
  while (i < OS_MAX_EVENT_HANDLER) {
    if (OS_SharedGlobalVars.EventHandler[i].fn == NULL) {
      OS_SharedGlobalVars.EventHandler[i].fn = handler;
      Status = OS_SUCCESS;
      break;
    }
    ++i;
  }
  return Status;
}

// NASA calls exit(EXIT_SUCCESS) or exit(EXIT_FAILURE). There is no exit() on a bare-metal
// target and no process to leave, so this is the one function in the module whose BODY cannot
// be translated -- the behaviour belongs to the platform. It is left as a halt so that a
// caller does not simply fall through, and the oracle never calls it.
U0 OS_ApplicationExit(I32 Status)
{
  while (1) {
  }
}

// Local helper, not part of the OSAL API: deletes ANY object, whatever its type.
U0 OS_CleanUpObject(U32 object_id, U8 *arg)
{
  U32 *ObjectCount;
  U32 objtype;
  ObjectCount = arg;
  ++(*ObjectCount);
  objtype = OS_IdentifyObject(object_id);
  if (objtype == OS_OBJECT_TYPE_OS_TASK)
    OS_TaskDelete(object_id);
  else if (objtype == OS_OBJECT_TYPE_OS_QUEUE)
    OS_QueueDelete(object_id);
  else if (objtype == OS_OBJECT_TYPE_OS_BINSEM)
    OS_BinSemDelete(object_id);
  else if (objtype == OS_OBJECT_TYPE_OS_COUNTSEM)
    OS_CountSemDelete(object_id);
  else if (objtype == OS_OBJECT_TYPE_OS_MUTEX)
    OS_MutSemDelete(object_id);
  else if (objtype == OS_OBJECT_TYPE_OS_MODULE)
    OS_ModuleUnload(object_id);
  else if (objtype == OS_OBJECT_TYPE_OS_TIMEBASE)
    OS_TimeBaseDelete(object_id);
  else if (objtype == OS_OBJECT_TYPE_OS_TIMECB)
    OS_TimerDelete(object_id);
  else if (objtype == OS_OBJECT_TYPE_OS_STREAM)
    OS_close(object_id);
  else if (objtype == OS_OBJECT_TYPE_OS_DIR)
    OS_DirectoryClose(object_id);
  else if (objtype == OS_OBJECT_TYPE_OS_CONDVAR)
    OS_CondVarDelete(object_id);
  // NOTE no case for OS_OBJECT_TYPE_OS_RWLOCK or OS_FILESYS: a leftover rwlock or mounted
  // filesystem is NOT cleaned up here. Translated as written.
}

U0 OS_DeleteAllObjects()
{
  U32 ObjectCount;
  U32 TryCount;
  // A LOOP, because some objects hold references to others and cannot be deleted until the
  // refcount drops -- so a first pass may delete the holder and a second the held.
  TryCount = 0;
  while (1) {
    ObjectCount = 0;
    ++TryCount;
    // Timers and tasks FIRST, since they could be actively using the other types.
    OS_ForEachObjectOfType(OS_OBJECT_TYPE_OS_TIMECB, OS_OBJECT_CREATOR_ANY, &OS_CleanUpObject,
                           &ObjectCount);
    OS_ForEachObjectOfType(OS_OBJECT_TYPE_OS_TIMEBASE, OS_OBJECT_CREATOR_ANY, &OS_CleanUpObject,
                           &ObjectCount);
    OS_ForEachObjectOfType(OS_OBJECT_TYPE_OS_TASK, OS_OBJECT_CREATOR_ANY, &OS_CleanUpObject,
                           &ObjectCount);
    // Then everything else of any type.
    OS_ForEachObject(OS_OBJECT_CREATOR_ANY, &OS_CleanUpObject, &ObjectCount);
    // Stop when a pass found nothing left, or after five passes -- the bound is what keeps a
    // stuck reference from making this loop forever.
    if (ObjectCount == 0 || TryCount > 4)
      break;
    OS_TaskDelay(5);
  }
}

U0 OS_IdleLoop()
{
  // Wait until the shutdown value is set. On most real embedded systems this never happens;
  // in debugging situations (CTRL+C and the like) it does.
  while (OS_SharedGlobalVars.GlobalState != OS_SHUTDOWN_MAGIC_NUMBER)
    OS_IdleLoop_Impl;
}

U0 OS_ApplicationShutdown(U8 flag)
{
  if (flag == TRUE)
    OS_SharedGlobalVars.GlobalState = OS_SHUTDOWN_MAGIC_NUMBER;
  // A hook so the implementation can do something -- assuming the main task is sitting in
  // OS_IdleLoop, this should wake it.
  OS_ApplicationShutdown_Impl;
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
