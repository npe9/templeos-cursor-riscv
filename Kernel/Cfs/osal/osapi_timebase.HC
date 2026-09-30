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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-timebase.c.
//
// OS_TimeBase_CallbackThread is the interesting part: a `while (1)` that calls the time base's
// sync function, then walks the circular ring of timers built by osapi-time.c and fires the
// ones whose wait_time has run out. It exits only when the time base is deleted underneath it,
// which it notices by comparing its own id against the global record's active_id.
#ifndef OSAPI_TIMEBASE_HC
#define OSAPI_TIMEBASE_HC
#include "os_shared_time.HC"
#include "../CfsStr.HC"

#define LOCAL_OBJID_TYPE_TIMEBASE OS_OBJECT_TYPE_OS_TIMEBASE

// How many consecutive zero-tick returns from a sync function are tolerated before the thread
// starts yielding. Defined in NASA's .c, not a header, so it lives here.
#define OS_TIMEBASE_SPIN_LIMIT 4

// The backend seam. Declared before use because HolyC is single-pass.
I32 OS_TimeBaseCreate_Impl(OS_object_token_t *token);
I32 OS_TimeBaseSet_Impl(OS_object_token_t *token, U32 start_time, U32 interval_time);
I32 OS_TimeBaseDelete_Impl(OS_object_token_t *token);
I32 OS_TimeBaseGetInfo_Impl(OS_object_token_t *token, OS_timebase_prop_t *timer_prop);
U0 OS_TimeBaseLock_Impl(OS_object_token_t *token);
U0 OS_TimeBaseUnlock_Impl(OS_object_token_t *token);

// The table is defined in os_shared_time.HC -- see the note there on why.

I32 OS_TimeBaseAPI_Init()
{
  MemSet(OS_timebase_table, 0, sizeof(OS_timebase_table));
  return OS_SUCCESS;
}

I32 OS_TimeBaseCreate(U32 *timebase_id, U8 *timebase_name, U32 (*external_sync)(U32))
{
  I32 return_code;
  U32 objtype;
  OS_object_token_t token;
  OS_timebase_internal_record_t *timebase;
  OS_common_record_t *grec;
  // A NULL sync function means the time base is NOT externally synchronized: an OS timer is
  // used to generate the simulated tick instead.
  if (timebase_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (timebase_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(timebase_name, 0, OS_MAX_API_NAME) == NULL)
    return OS_ERR_NAME_TOO_LONG;
  objtype = OS_ObjectIdToType_Impl(OS_TaskGetId_Impl);
  if (objtype == OS_OBJECT_TYPE_OS_TIMEBASE)
    return OS_ERR_INCORRECT_OBJ_STATE;
  return_code = OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_TIMEBASE, timebase_name, &token);
  if (return_code == OS_SUCCESS) {
    timebase = &OS_timebase_table[OS_ObjectIndexFromToken(&token)];
    // OS_OBJECT_INIT(token, timebase, timebase_name, timebase_name)
    MemSet(timebase, 0, sizeof(OS_timebase_internal_record_t));
    StrNCpy(timebase->timebase_name, timebase_name, OS_MAX_API_NAME - 1);
    grec = OS_ObjectIdGlobalFromToken(&token);
    grec->name_entry = timebase->timebase_name;
    timebase->external_sync = external_sync;
    // An OS-timed base reports the system tick as its accuracy; an externally synchronized one
    // reports 0, because only the application knows what its sync period means.
    if (external_sync == NULL)
      timebase->accuracy_usec = OS_SharedGlobalVars.MicroSecPerTick;
    else
      timebase->accuracy_usec = 0;
    return_code = OS_TimeBaseCreate_Impl(&token);
    return_code = OS_ObjectIdFinalizeNew(return_code, &token, timebase_id);
  }
  return return_code;
}

I32 OS_TimeBaseSet(U32 timebase_id, U32 start_time, U32 interval_time)
{
  I32 return_code;
  U32 objtype;
  OS_object_token_t token;
  OS_timebase_internal_record_t *timebase;
  // The implementation holds the interval as a SIGNED 32-bit value but the parameter is
  // unsigned, because a negative interval is meaningless. The UNITS are intentionally
  // unspecified -- an external sync period could be microseconds or hours.
  if (!(start_time < 1000000000))
    return OS_TIMER_ERR_INVALID_ARGS;
  if (!(interval_time < 1000000000))
    return OS_TIMER_ERR_INVALID_ARGS;
  objtype = OS_ObjectIdToType_Impl(OS_TaskGetId_Impl);
  if (objtype == OS_OBJECT_TYPE_OS_TIMEBASE)
    return OS_ERR_INCORRECT_OBJ_STATE;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TIMEBASE, timebase_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    timebase = &OS_timebase_table[OS_ObjectIndexFromToken(&token)];
    // The time base lock ensures no tick is being processed while this changes.
    OS_TimeBaseLock_Impl(&token);
    return_code = OS_TimeBaseSet_Impl(&token, start_time, interval_time);
    // The nominal values are saved ONLY on success, so a failed set leaves the previously
    // reported interval in place rather than a value that was never applied.
    if (return_code == OS_SUCCESS) {
      timebase->nominal_start_time = start_time;
      timebase->nominal_interval_time = interval_time;
    }
    OS_TimeBaseUnlock_Impl(&token);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_TimeBaseDelete(U32 timebase_id)
{
  I32 return_code;
  U32 objtype;
  OS_object_token_t token;
  objtype = OS_ObjectIdToType_Impl(OS_TaskGetId_Impl);
  if (objtype == OS_OBJECT_TYPE_OS_TIMEBASE)
    return OS_ERR_INCORRECT_OBJ_STATE;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, OS_OBJECT_TYPE_OS_TIMEBASE,
                                   timebase_id, &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_TimeBaseDelete_Impl(&token);
    return_code = OS_ObjectIdFinalizeDelete(return_code, &token);
  }
  return return_code;
}

I32 OS_TimeBaseGetIdByName(U32 *timebase_id, U8 *timebase_name)
{
  I32 return_code;
  U32 objtype;
  if (timebase_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (timebase_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(timebase_name, 0, OS_MAX_API_NAME) == NULL)
    return OS_ERR_NAME_TOO_LONG;
  objtype = OS_ObjectIdToType_Impl(OS_TaskGetId_Impl);
  if (objtype == OS_OBJECT_TYPE_OS_TIMEBASE)
    return OS_ERR_INCORRECT_OBJ_STATE;
  return_code = OS_ObjectIdFindByName(OS_OBJECT_TYPE_OS_TIMEBASE, timebase_name, timebase_id);
  return return_code;
}

I32 OS_TimeBaseGetInfo(U32 timebase_id, OS_timebase_prop_t *timebase_prop)
{
  OS_common_record_t *record;
  OS_common_record_t *base;
  I32 return_code;
  U32 objtype;
  OS_object_token_t token;
  OS_timebase_internal_record_t *timebase;
  if (timebase_prop == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // As in OS_TimerGetInfo, the context check comes BEFORE the memset, so a rejected call
  // leaves the caller's buffer untouched.
  objtype = OS_ObjectIdToType_Impl(OS_TaskGetId_Impl);
  if (objtype == OS_OBJECT_TYPE_OS_TIMEBASE)
    return OS_ERR_INCORRECT_OBJ_STATE;
  MemSet(timebase_prop, 0, sizeof(OS_timebase_prop_t));
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_TIMEBASE, timebase_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    base = &OS_common_table[OS_TIMEBASE_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
    timebase = &OS_timebase_table[OS_ObjectIndexFromToken(&token)];
    StrNCpy(timebase_prop->name, record->name_entry, OS_MAX_API_NAME - 1);
    timebase_prop->creator = record->creator;
    timebase_prop->nominal_interval_time = timebase->nominal_interval_time;
    timebase_prop->freerun_time = timebase->freerun_time;
    timebase_prop->accuracy = timebase->accuracy_usec;
    return_code = OS_TimeBaseGetInfo_Impl(&token, timebase_prop);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_TimeBaseGetFreeRun(U32 timebase_id, U32 *freerun_val)
{
  I32 return_code;
  OS_object_token_t token;
  OS_timebase_internal_record_t *timebase;
  if (freerun_val == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // NOTE: LOCK_MODE_NONE, and no context check either -- this one IS callable from a timer
  // callback, unlike every other function in this module.
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_NONE, LOCAL_OBJID_TYPE_TIMEBASE, timebase_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    timebase = &OS_timebase_table[OS_ObjectIndexFromToken(&token)];
    *freerun_val = timebase->freerun_time;
  }
  return return_code;
}

// The time base helper thread. Runs in a dedicated, typically elevated-priority context and
// does two things: call the BSP sync routine to wait for the tick, then run the application
// callbacks whose time has come. Callbacks run under THIS thread rather than an ISR or signal
// handler, where the available C library is very limited.
U0 OS_TimeBase_CallbackThread(U32 timebase_id)
{
  U32 (*syncfunc)(U32);
  OS_timebase_internal_record_t *timebase;
  OS_timecb_internal_record_t *timecb;
  OS_common_record_t *record;
  OS_common_record_t *base;
  OS_object_token_t token;
  OS_object_token_t cb_token;
  U32 tick_time;
  U32 spin_cycles;
  I32 saved_wait_time;
  // Register this task as a time base handler. Application code MUST NOT configure timers from
  // a callback -- that is what the OS_ObjectIdToType_Impl checks throughout osapi-time.c are
  // for, and deadlock is the alternative.
  OS_TaskRegister_Impl(timebase_id);
  if (OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TIMEBASE, timebase_id,
                         &token) != 0) {
    // Something went wrong -- abort this thread.
    return;
  }
  base = &OS_common_table[OS_TIMEBASE_BASE];
  record = &base[OS_ObjectIndexFromToken(&token)];
  timebase = &OS_timebase_table[OS_ObjectIndexFromToken(&token)];
  syncfunc = timebase->external_sync;
  spin_cycles = 0;
  OS_ObjectIdRelease(&token);
  while (1) {
    // The sync function pends and returns how many timebase ticks elapsed.
    tick_time = (*syncfunc)(timebase_id);
    // A zero return means the wait was interrupted and the elapsed count is unknown -- valid,
    // e.g. EINTR on a POSIX-like OS. Retrying is often right, but this thread usually runs at
    // high priority, so the spinning is bounded.
    if (tick_time != 0) {
      spin_cycles = 0;
    } else if (spin_cycles < OS_TIMEBASE_SPIN_LIMIT) {
      ++spin_cycles;
    } else {
      // Spin loop detected: yield the CPU, and warn only the FIRST time so the operator learns
      // about it without the log filling up. OS_DEBUG is a no-op in this configuration.
      OS_TaskDelay_Impl(10);
      if (spin_cycles == OS_TIMEBASE_SPIN_LIMIT)
        ++spin_cycles;
    }
    OS_TimeBaseLock_Impl(&token);
    // After waiting, check the id still matches. If not, this time base was deleted and the
    // thread must stop -- this is the ONLY exit from the loop.
    if (!OS_ObjectIdEqual(timebase_id, record->active_id)) {
      OS_TimeBaseUnlock_Impl(&token);
      break;
    }
    timebase->freerun_time += tick_time;
    if (OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_TIMECB, timebase->first_cb,
                           &cb_token) == 0) {
      do {
        timecb = &OS_timecb_table[OS_ObjectIndexFromToken(&cb_token)];
        saved_wait_time = timecb->wait_time;
        timecb->wait_time -= tick_time;
        while (timecb->wait_time <= 0) {
          timecb->wait_time += timecb->interval_time;
          // Let the underflow go only one interval negative. Without this a callback interval
          // SHORTER than the timebase interval would accumulate debt forever.
          if (timecb->wait_time < -timecb->interval_time) {
            ++timecb->backlog_resets;
            timecb->wait_time = -timecb->interval_time;
          }
          // Fire only when wait_time actually crossed from positive to negative. That is what
          // makes ONE-SHOT work: the API sets wait_time positive and leaves interval_time
          // zero, so it never goes positive again and never fires twice.
          if (saved_wait_time > 0 && timecb->callback_ptr != NULL)
            (*timecb->callback_ptr)(OS_ObjectIdFromToken(&cb_token), timecb->callback_arg);
          // Do not repeat unless an interval is configured.
          if (timecb->interval_time <= 0)
            break;
        }
      } while (OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_TIMECB, timecb->next_cb,
                                  &cb_token) == OS_SUCCESS &&
               !OS_ObjectIdEqual(OS_ObjectIdFromToken(&cb_token), timebase->first_cb));
    }
    OS_TimeBaseUnlock_Impl(&token);
  }
}

// Internal helper: milliseconds to ticks, rounding UP, and failing on overflow.
I32 OS_Milli2Ticks(U32 milli_seconds, I32 *ticks)
{
  U64 num_of_ticks;
  I32 return_code = OS_SUCCESS;
  num_of_ticks = (milli_seconds * OS_SharedGlobalVars.TicksPerSecond + 999) / 1000;
  // Check against maximum int32; some OSes cannot take more.
  if (num_of_ticks <= 0x7FFFFFFF) {
    *ticks = num_of_ticks;
  } else {
    return_code = OS_ERROR;
    *ticks = 0;
  }
  return return_code;
}
#endif
