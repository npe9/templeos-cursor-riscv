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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-time.c.
//
// The timers attached to one time base form a CIRCULAR DOUBLY LINKED LIST through prev_cb and
// next_cb, with timebase->first_cb as the entry point. A freshly created timer points at
// itself in both directions; adding splices it in ahead of first_cb and then becomes the new
// first_cb; deleting unlinks it and resets its own links to itself. The callback thread in
// osapi-timebase.c walks that ring, which is why getting the splice wrong shows up as a walk
// that never terminates or that visits the wrong number of timers.
#ifndef OSAPI_TIME_HC
#define OSAPI_TIME_HC
#include "os_shared_time.HC"
#include "../CfsStr.HC"

// Declared before use because HolyC is single-pass; both live in osapi_timebase.HC.
I32 OS_TimeBaseCreate(U32 *timebase_id, U8 *timebase_name, U32 (*external_sync)(U32));
I32 OS_TimeBaseSet(U32 timebase_id, U32 start_time, U32 interval_time);
I32 OS_TimeBaseDelete(U32 timebase_id);
U0 OS_TimeBaseLock_Impl(OS_object_token_t *token);
U0 OS_TimeBaseUnlock_Impl(OS_object_token_t *token);
U32 OS_ObjectIdToType_Impl(U32 id);

// The table is defined in os_shared_time.HC -- see the note there on why.

// NASA's union, punning a function pointer through the void * callback argument. It is legal
// here for the reason NASA gives -- a CompileTimeAssert checks
// sizeof(OS_TimerCallback_t) <= sizeof(void *) -- and this compiler agrees: a probe shows
// sizeof of this union is 8 and the pointer survives the round trip.
union OS_Timer_ArgWrapper_t
{
  U0 (*timer_callback_func)(U32); // OS_TimerCallback_t
  U8 *opaque_arg;
};

I32 OS_TimerCbAPI_Init()
{
  MemSet(OS_timecb_table, 0, sizeof(OS_timecb_table));
  return OS_SUCCESS;
}

// The shim that lets a no-argument OS_TimerCallback_t be driven by the two-argument
// OS_ArgCallback_t the ring walks. NASA's comment: not written as *((OS_SimpleCallback_t)arg)
// because you technically cannot cast a void * to a function pointer.
U0 OS_Timer_NoArgCallback(U32 objid, U8 *arg)
{
  OS_Timer_ArgWrapper_t Conv;
  Conv.opaque_arg = arg;
  (*Conv.timer_callback_func)(objid);
}

// Local helper, not part of the OSAL API. Shared by OS_TimerAdd and OS_TimerCreate.
I32 OS_DoTimerAdd(U32 *timer_id, U8 *timer_name, U32 timebase_ref_id,
                  U0 (*callback_ptr)(U32, U8 *), U8 *callback_arg, U32 flags)
{
  I32 return_code;
  U32 objtype;
  OS_object_token_t timebase_token;
  OS_object_token_t timecb_token;
  OS_object_token_t listcb_token;
  OS_timecb_internal_record_t *timecb;
  OS_timecb_internal_record_t *list_timecb;
  OS_timebase_internal_record_t *timebase;
  OS_common_record_t *grec;
  // "callback_arg" is deliberately NOT checked: in certain configurations it can validly be
  // null, and NASA says so here.
  if (timer_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (timer_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(timer_name, 0, OS_MAX_API_NAME) == NULL)
    return OS_ERR_NAME_TOO_LONG;
  if (callback_ptr == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // Check our context: the timer API may NOT be used from inside a timer callback, because the
  // callback thread already holds the timebase lock and would deadlock. Only the object TYPE of
  // the running task is needed to tell.
  objtype = OS_ObjectIdToType_Impl(OS_TaskGetId_Impl);
  if (objtype == OS_OBJECT_TYPE_OS_TIMEBASE)
    return OS_ERR_INCORRECT_OBJ_STATE;
  // Check the timebase reference is valid. AFTER this succeeds we MUST decrement the refcount
  // on every error path out of this routine.
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_REFCOUNT, OS_OBJECT_TYPE_OS_TIMEBASE,
                                   timebase_ref_id, &timebase_token);
  if (return_code != OS_SUCCESS)
    return return_code;
  return_code = OS_ObjectIdAllocateNew(OS_OBJECT_TYPE_OS_TIMECB, timer_name, &timecb_token);
  if (return_code == OS_SUCCESS) {
    timecb = &OS_timecb_table[OS_ObjectIndexFromToken(&timecb_token)];
    timebase = &OS_timebase_table[OS_ObjectIndexFromToken(&timebase_token)];
    // OS_OBJECT_INIT(timecb_token, timecb, timer_name, timer_name)
    MemSet(timecb, 0, sizeof(OS_timecb_internal_record_t));
    StrNCpy(timecb->timer_name, timer_name, OS_MAX_API_NAME - 1);
    grec = OS_ObjectIdGlobalFromToken(&timecb_token);
    grec->name_entry = timecb->timer_name;
    // Transfer ownership: the refcount taken above now belongs to the timecb object and is
    // held until that object is deleted.
    OS_ObjectIdTransferToken(&timebase_token, &timecb->timebase_token);
    timecb->callback_ptr = callback_ptr;
    timecb->callback_arg = callback_arg;
    timecb->flags = flags;
    // A ring of one: it points at itself both ways until spliced in below.
    timecb->prev_cb = OS_ObjectIdFromToken(&timecb_token);
    timecb->next_cb = OS_ObjectIdFromToken(&timecb_token);
    // Take the timebase-specific lock so a tick cannot be processed mid-splice.
    OS_TimeBaseLock_Impl(&timebase_token);
    if (OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_TIMECB, timebase->first_cb,
                           &listcb_token) == OS_SUCCESS) {
      list_timecb = &OS_timecb_table[OS_ObjectIndexFromToken(&listcb_token)];
      timecb->next_cb = OS_ObjectIdFromToken(&listcb_token);
      timecb->prev_cb = list_timecb->prev_cb;
      if (OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_TIMECB, timecb->prev_cb,
                             &listcb_token) == OS_SUCCESS) {
        // NOTE the ORDER here, which is easy to get wrong: list_timecb still points at the OLD
        // first_cb when its prev_cb is set, and is only then re-pointed at the tail whose
        // next_cb is set. Two different records are updated through one variable.
        list_timecb->prev_cb = OS_ObjectIdFromToken(&timecb_token);
        list_timecb = &OS_timecb_table[OS_ObjectIndexFromToken(&listcb_token)];
        list_timecb->next_cb = OS_ObjectIdFromToken(&timecb_token);
      }
    }
    timebase->first_cb = OS_ObjectIdFromToken(&timecb_token);
    OS_TimeBaseUnlock_Impl(&timebase_token);
    return_code = OS_ObjectIdFinalizeNew(return_code, &timecb_token, timer_id);
  } else {
    OS_ObjectIdRelease(&timebase_token);
  }
  return return_code;
}

I32 OS_TimerAdd(U32 *timer_id, U8 *timer_name, U32 timebase_ref_id,
                U0 (*callback_ptr)(U32, U8 *), U8 *callback_arg)
{
  return OS_DoTimerAdd(timer_id, timer_name, timebase_ref_id, callback_ptr, callback_arg, 0);
}

I32 OS_TimerCreate(U32 *timer_id, U8 *timer_name, U32 *clock_accuracy,
                   U0 (*callback_ptr)(U32))
{
  I32 return_code;
  U32 timebase_ref_id;
  OS_Timer_ArgWrapper_t Conv;
  // DoTimerAdd checks these too; checking here as well avoids creating and then deleting a
  // timebase object for an argument that was never going to work.
  if (timer_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (timer_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (MemChr(timer_name, 0, OS_MAX_API_NAME) == NULL)
    return OS_ERR_NAME_TOO_LONG;
  if (clock_accuracy == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (callback_ptr == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // Create a dedicated time base object to drive this timer.
  return_code = OS_TimeBaseCreate(&timebase_ref_id, timer_name, NULL);
  if (return_code != OS_SUCCESS)
    return return_code;
  // TIMECB_FLAG_DEDICATED_TIMEBASE marks that the time base was made for this timer.
  Conv.opaque_arg = NULL;
  Conv.timer_callback_func = callback_ptr;
  return_code = OS_DoTimerAdd(timer_id, timer_name, timebase_ref_id, &OS_Timer_NoArgCallback,
                              Conv.opaque_arg, TIMECB_FLAG_DEDICATED_TIMEBASE);
  // On failure the dedicated timebase created above must be cleaned up.
  if (return_code != OS_SUCCESS)
    OS_TimeBaseDelete(timebase_ref_id);
  else
    *clock_accuracy = OS_SharedGlobalVars.MicroSecPerTick;
  return return_code;
}

I32 OS_TimerSet(U32 timer_id, U32 start_time, U32 interval_time)
{
  OS_timecb_internal_record_t *timecb;
  I32 return_code;
  U32 objtype;
  U32 dedicated_timebase_id;
  OS_object_token_t token;
  dedicated_timebase_id = OS_OBJECT_ID_UNDEFINED;
  // Three silent ARGCHECKs. UINT32_MAX / 2 is 0x7FFFFFFF.
  if (!(start_time < 0x7FFFFFFF))
    return OS_TIMER_ERR_INVALID_ARGS;
  if (!(interval_time < 0x7FFFFFFF))
    return OS_TIMER_ERR_INVALID_ARGS;
  if (!(start_time != 0 || interval_time != 0))
    return OS_TIMER_ERR_INVALID_ARGS;
  objtype = OS_ObjectIdToType_Impl(OS_TaskGetId_Impl);
  if (objtype == OS_OBJECT_TYPE_OS_TIMEBASE)
    return OS_ERR_INCORRECT_OBJ_STATE;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TIMECB, timer_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    timecb = &OS_timecb_table[OS_ObjectIndexFromToken(&token)];
    OS_TimeBaseLock_Impl(&timecb->timebase_token);
    if ((timecb->flags & TIMECB_FLAG_DEDICATED_TIMEBASE) != 0)
      dedicated_timebase_id = OS_ObjectIdFromToken(&timecb->timebase_token);
    timecb->wait_time = start_time;
    timecb->interval_time = interval_time;
    OS_TimeBaseUnlock_Impl(&timecb->timebase_token);
    OS_ObjectIdRelease(&token);
  }
  // A dedicated time base is retuned to the same interval. NASA notes this is NOT atomic with
  // the update above -- a tick can land in between, and OS_TimeBaseSet can fail leaving a mixed
  // state -- and that an application must tolerate a spurious callback here regardless, because
  // a tick can occur at any moment anyway.
  if (return_code == OS_SUCCESS && OS_ObjectIdDefined(dedicated_timebase_id))
    return_code = OS_TimeBaseSet(dedicated_timebase_id, start_time, interval_time);
  return return_code;
}

I32 OS_TimerDelete(U32 timer_id)
{
  I32 return_code;
  U32 objtype;
  U32 dedicated_timebase_id;
  OS_object_token_t timecb_token;
  OS_object_token_t timebase_token;
  OS_object_token_t listcb_token;
  OS_timebase_internal_record_t *timebase;
  OS_timecb_internal_record_t *timecb;
  OS_timecb_internal_record_t *list_timecb;
  dedicated_timebase_id = OS_OBJECT_ID_UNDEFINED;
  MemSet(&timebase_token, 0, sizeof(OS_object_token_t));
  objtype = OS_ObjectIdToType_Impl(OS_TaskGetId_Impl);
  if (objtype == OS_OBJECT_TYPE_OS_TIMEBASE)
    return OS_ERR_INCORRECT_OBJ_STATE;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, OS_OBJECT_TYPE_OS_TIMECB, timer_id,
                                   &timecb_token);
  if (return_code == OS_SUCCESS) {
    timecb = &OS_timecb_table[OS_ObjectIndexFromToken(&timecb_token)];
    timebase = &OS_timebase_table[OS_ObjectIndexFromToken(&timecb->timebase_token)];
    OS_ObjectIdTransferToken(&timecb->timebase_token, &timebase_token);
    OS_TimeBaseLock_Impl(&timecb->timebase_token);
    if ((timecb->flags & TIMECB_FLAG_DEDICATED_TIMEBASE) != 0)
      dedicated_timebase_id = OS_ObjectIdFromToken(&timecb->timebase_token);
    // Unlink from the ring. If this was first_cb, first_cb moves to next_cb -- unless this was
    // the ONLY member (next_cb is itself), in which case the ring becomes empty.
    if (OS_ObjectIdEqual(timebase->first_cb, OS_ObjectIdFromToken(&timecb_token))) {
      if (OS_ObjectIdEqual(OS_ObjectIdFromToken(&timecb_token), timecb->next_cb))
        timebase->first_cb = OS_OBJECT_ID_UNDEFINED;
      else
        timebase->first_cb = timecb->next_cb;
    }
    if (OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_TIMECB, timecb->prev_cb,
                           &listcb_token) == OS_SUCCESS) {
      list_timecb = &OS_timecb_table[OS_ObjectIndexFromToken(&listcb_token)];
      list_timecb->next_cb = timecb->next_cb;
    }
    if (OS_ObjectIdGetById(OS_LOCK_MODE_NONE, OS_OBJECT_TYPE_OS_TIMECB, timecb->next_cb,
                           &listcb_token) == OS_SUCCESS) {
      list_timecb = &OS_timecb_table[OS_ObjectIndexFromToken(&listcb_token)];
      list_timecb->prev_cb = timecb->prev_cb;
    }
    // Back to a ring of one, so a stale walk cannot re-enter the live ring.
    timecb->next_cb = OS_ObjectIdFromToken(&timecb_token);
    timecb->prev_cb = OS_ObjectIdFromToken(&timecb_token);
    OS_TimeBaseUnlock_Impl(&timecb->timebase_token);
    return_code = OS_ObjectIdFinalizeDelete(return_code, &timecb_token);
  }
  // Drop the reference this timer held on its time base. UNCONDITIONAL, as in
  // osapi-task-affinity.c: a zeroed token releases nothing.
  OS_ObjectIdRelease(&timebase_token);
  if (return_code == OS_SUCCESS && OS_ObjectIdDefined(dedicated_timebase_id))
    OS_TimeBaseDelete(dedicated_timebase_id);
  return return_code;
}

I32 OS_TimerGetIdByName(U32 *timer_id, U8 *timer_name)
{
  I32 return_code;
  U32 objtype;
  if (timer_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (timer_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  objtype = OS_ObjectIdToType_Impl(OS_TaskGetId_Impl);
  if (objtype == OS_OBJECT_TYPE_OS_TIMEBASE)
    return OS_ERR_INCORRECT_OBJ_STATE;
  return_code = OS_ObjectIdFindByName(OS_OBJECT_TYPE_OS_TIMECB, timer_name, timer_id);
  return return_code;
}

I32 OS_TimerGetInfo(U32 timer_id, OS_timer_prop_t *timer_prop)
{
  OS_common_record_t *record;
  OS_common_record_t *base;
  OS_timecb_internal_record_t *timecb;
  OS_timebase_internal_record_t *timebase;
  I32 return_code;
  U32 objtype;
  OS_object_token_t token;
  if (timer_prop == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // NOTE the ORDER: the context check comes BEFORE the memset, so a call rejected with
  // OS_ERR_INCORRECT_OBJ_STATE leaves the caller's buffer UNTOUCHED. Zeroing first would be a
  // visible difference to a caller that had put something there.
  objtype = OS_ObjectIdToType_Impl(OS_TaskGetId_Impl);
  if (objtype == OS_OBJECT_TYPE_OS_TIMEBASE)
    return OS_ERR_INCORRECT_OBJ_STATE;
  MemSet(timer_prop, 0, sizeof(OS_timer_prop_t));
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TIMECB, timer_id,
                                   &token);
  if (return_code == OS_SUCCESS) {
    // Base into a local first: indexing the parenthesised OS_global_*_table macro directly is
    // off by one in this compiler (docs/HOLYC_STRUCT_LIMITS.md).
    base = &OS_common_table[OS_TIMECB_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
    timecb = &OS_timecb_table[OS_ObjectIndexFromToken(&token)];
    // accuracy comes from the TIME BASE this timer is attached to, not from the global tick
    // rate -- two timers on different time bases report different accuracies.
    timebase = &OS_timebase_table[OS_ObjectIndexFromToken(&timecb->timebase_token)];
    StrNCpy(timer_prop->name, record->name_entry, OS_MAX_API_NAME - 1);
    timer_prop->creator = record->creator;
    timer_prop->interval_time = timecb->interval_time;
    timer_prop->accuracy = timebase->accuracy_usec;
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}
#endif
