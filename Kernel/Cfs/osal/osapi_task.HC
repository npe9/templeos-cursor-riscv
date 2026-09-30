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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-task.c.
//
// NASA's file-local `enum { LOCAL_NUM_OBJECTS = OS_MAX_TASKS, LOCAL_OBJID_TYPE =
// OS_OBJECT_TYPE_OS_TASK }` becomes two #defines with the module in the name, because HolyC has
// no enum and no file scope -- every translated unit lands in one compilation unit here, so a
// bare LOCAL_OBJID_TYPE would be whichever module was included last.
#ifndef OSAPI_TASK_HC
#define OSAPI_TASK_HC
#include "os_shared_task.HC"

#define LOCAL_NUM_OBJECTS_TASK OS_MAX_TASKS
#define LOCAL_OBJID_TYPE_TASK  OS_OBJECT_TYPE_OS_TASK

// The backend seam. Declared before use because HolyC is single-pass.
I32 OS_TaskCreate_Impl(OS_object_token_t *token, U32 flags);
I32 OS_TaskDelete_Impl(OS_object_token_t *token);
I32 OS_TaskDetach_Impl(OS_object_token_t *token);   // int32, not void
U0 OS_TaskExit_Impl();
I32 OS_TaskDelay_Impl(U32 millisecond);
I32 OS_TaskSetPriority_Impl(OS_object_token_t *token, U8 new_priority);
U32 OS_TaskGetId_Impl();
I32 OS_TaskGetInfo_Impl(OS_object_token_t *token, OS_task_prop_t *task_prop);
I32 OS_TaskMatch_Impl(OS_object_token_t *token);
I32 OS_TaskRegister_Impl(U32 global_task_id);
I32 OS_TaskValidateSystemData_Impl(U8 *sysdata, I64 sysdata_size);
Bool OS_TaskIdMatchSystemData_Impl(U8 *ref, OS_object_token_t *token, OS_common_record_t *obj);

// OS_TaskEntryPoint calls OS_TaskExit, which is defined below it in NASA's file order. In C
// the public header osapi-task.h supplies the declaration; HolyC is single-pass, so it goes
// here rather than reordering the file away from NASA's.
U0 OS_TaskExit();

OS_task_internal_record_t OS_task_table[LOCAL_NUM_OBJECTS_TASK];

// Local helper, not part of the OSAL API. Maps task_id back to its table entry so the caller
// can invoke the real entry point, verifying the id and calling the backend's Register along
// the way so that GetTaskId will work.
I32 OS_TaskPrepare(U32 task_id, U0 (**entrypt)())
{
  I32 return_code;
  OS_object_token_t token;
  OS_task_internal_record_t *task;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, OS_OBJECT_TYPE_OS_TASK, task_id, &token);
  if (return_code == OS_SUCCESS) {
    task = &OS_task_table[OS_ObjectIndexFromToken(&token)];
    return_code = OS_TaskMatch_Impl(&token);
    *entrypt = task->entry_function_pointer;
    OS_ObjectIdRelease(&token);
  }
  if (return_code == OS_SUCCESS)
    return_code = OS_TaskRegister_Impl(task_id);
  if (return_code == OS_SUCCESS)
    return_code = OS_NotifyEvent(OS_EVENT_TASK_STARTUP, task_id, NULL);
  if (return_code != OS_SUCCESS)
    *entrypt = NULL;
  return return_code;
}

// The entry point for all OSAL tasks: the first thing to run in the new task's own context.
U0 OS_TaskEntryPoint(U32 task_id)
{
  U0 (*task_entry)();
  if (OS_TaskPrepare(task_id, &task_entry) == OS_SUCCESS) {
    if (task_entry != NULL)
      (*task_entry)();
  }
  // If the function returns, treat as a normal exit and do the proper cleanup.
  OS_TaskExit;
}

I32 OS_TaskAPI_Init()
{
  memset(OS_task_table, 0, sizeof(OS_task_table));
  return OS_SUCCESS;
}

I32 OS_TaskCreate(U32 *task_id, U8 *task_name, U0 (*function_pointer)(), U8 *stack_pointer,
                  I64 stack_size, U8 priority, U32 flags)
{
  I32 return_code;
  OS_object_token_t token;
  OS_task_internal_record_t *task;
  OS_common_record_t *grec;
  // stack_pointer is deliberately NOT checked -- in certain configurations it can validly be
  // null, and NASA says so in a comment here.
  if (task_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (function_pointer == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (task_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (memchr(task_name, 0, OS_MAX_API_NAME) == NULL)
    return OS_ERR_NAME_TOO_LONG;
  if (!(stack_size > 0 && stack_size < 0x7FFFFFFF))
    return OS_ERR_INVALID_SIZE;
  // ObjectIdAllocateNew locks the object type and LEAVES IT LOCKED; FinalizeNew unlocks.
  return_code = OS_ObjectIdAllocateNew(LOCAL_OBJID_TYPE_TASK, task_name, &token);
  if (return_code == OS_SUCCESS) {
    task = &OS_task_table[OS_ObjectIndexFromToken(&token)];
    // OS_OBJECT_INIT(token, task, task_name, task_name)
    memset(task, 0, sizeof(OS_task_internal_record_t));
    strncpy(task->task_name, task_name, OS_MAX_API_NAME - 1);
    grec = OS_ObjectIdGlobalFromToken(&token);
    grec->name_entry = task->task_name;
    task->stack_size = stack_size;
    task->priority = priority;
    task->entry_function_pointer = function_pointer;
    task->stack_pointer = stack_pointer;
    flags |= OS_ADD_TASK_FLAGS;
    // The backend reads the rest out of the table entry just written.
    return_code = OS_TaskCreate_Impl(&token, flags);
    return_code = OS_ObjectIdFinalizeNew(return_code, &token, task_id);
  }
  return return_code;
}

I32 OS_TaskDelete(U32 task_id)
{
  I32 return_code;
  OS_object_token_t token;
  OS_task_internal_record_t *task;
  U0 (*delete_hook)();
  delete_hook = NULL;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_EXCLUSIVE, LOCAL_OBJID_TYPE_TASK, task_id, &token);
  if (return_code == OS_SUCCESS) {
    task = &OS_task_table[OS_ObjectIndexFromToken(&token)];
    // NASA: "Save the delete hook, as we do not want to call it while locked". What matters
    // is that the CALL happens after FinalizeDelete releases the lock, which it does below.
    // The read order is NOT observable here and a control proved it: moving this line after
    // FinalizeDelete left the transcript identical, because FinalizeDelete clears the GLOBAL
    // record's id and never touches OS_task_table, which is zeroed only on Create.
    delete_hook = task->delete_hook_pointer;
    return_code = OS_TaskDelete_Impl(&token);
    return_code = OS_ObjectIdFinalizeDelete(return_code, &token);
  }
  if (return_code == OS_SUCCESS && delete_hook != NULL)
    delete_hook();
  return return_code;
}

U0 OS_TaskExit()
{
  U32 task_id;
  OS_object_token_t token;
  task_id = OS_TaskGetId_Impl;
  if (OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_TASK, task_id, &token)
      == OS_SUCCESS) {
    OS_TaskDetach_Impl(&token);
    OS_ObjectIdFinalizeDelete(OS_SUCCESS, &token);
  }
  OS_TaskExit_Impl;
  // The _Impl never returns.
}

I32 OS_TaskDelay(U32 millisecond)
{
  return OS_TaskDelay_Impl(millisecond);
}

I32 OS_TaskSetPriority(U32 task_id, U8 new_priority)
{
  I32 return_code;
  OS_object_token_t token;
  OS_task_internal_record_t *task;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_TASK, task_id, &token);
  if (return_code == OS_SUCCESS) {
    task = &OS_task_table[OS_ObjectIndexFromToken(&token)];
    return_code = OS_TaskSetPriority_Impl(&token, new_priority);
    if (return_code == OS_SUCCESS) {
      // The table keeps the ABSTRACTED priority, not whatever the OS made of it.
      task->priority = new_priority;
    }
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

U32 OS_TaskGetId()
{
  U32 task_id;
  task_id = OS_TaskGetId_Impl;
  return task_id;
}

I32 OS_TaskGetIdByName(U32 *task_id, U8 *task_name)
{
  I32 return_code;
  if (task_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (task_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdFindByName(LOCAL_OBJID_TYPE_TASK, task_name, task_id);
  return return_code;
}

I32 OS_TaskGetInfo(U32 task_id, OS_task_prop_t *task_prop)
{
  OS_common_record_t *record;
  OS_common_record_t *base;
  I32 return_code;
  OS_object_token_t token;
  OS_task_internal_record_t *task;
  if (task_prop == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  memset(task_prop, 0, sizeof(OS_task_prop_t));
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_TASK, task_id, &token);
  if (return_code == OS_SUCCESS) {
    // Base into a local first: indexing the parenthesised OS_global_*_table macro directly is
    // off by one in this compiler (docs/HOLYC_STRUCT_LIMITS.md).
    base = &OS_common_table[OS_TASK_BASE];
    record = &base[OS_ObjectIndexFromToken(&token)];
    task = &OS_task_table[OS_ObjectIndexFromToken(&token)];
    // Unlike the semaphore family, this one GUARDS the name copy -- an unnamed record leaves
    // task_prop->name as the memset zeros rather than dereferencing NULL.
    if (record->name_entry != NULL) {
      strncpy(task_prop->name, record->name_entry, OS_MAX_API_NAME - 1);
      task_prop->name[OS_MAX_API_NAME - 1] = 0;
    }
    task_prop->creator = record->creator;
    task_prop->stack_size = task->stack_size;
    task_prop->priority = task->priority;
    return_code = OS_TaskGetInfo_Impl(&token, task_prop);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_TaskInstallDeleteHandler(U0 (*function_pointer)())
{
  I32 return_code;
  OS_object_token_t token;
  OS_task_internal_record_t *task;
  U32 task_id;
  task_id = OS_TaskGetId_Impl;
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_TASK, task_id, &token);
  if (return_code == OS_SUCCESS) {
    task = &OS_task_table[OS_ObjectIndexFromToken(&token)];
    task->delete_hook_pointer = function_pointer;
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_TaskFindIdBySystemData(U32 *task_id, U8 *sysdata, I64 sysdata_size)
{
  I32 return_code;
  OS_object_token_t token;
  if (task_id == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // sysdata and sysdata_size are validated by the BACKEND, not here -- only it knows what a
  // system task handle looks like.
  return_code = OS_TaskValidateSystemData_Impl(sysdata, sysdata_size);
  if (return_code != OS_SUCCESS)
    return return_code;
  return_code = OS_ObjectIdGetBySearch(OS_LOCK_MODE_GLOBAL, LOCAL_OBJID_TYPE_TASK,
                                       &OS_TaskIdMatchSystemData_Impl, sysdata, &token);
  if (return_code == OS_SUCCESS) {
    *task_id = OS_ObjectIdFromToken(&token);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}
#endif
