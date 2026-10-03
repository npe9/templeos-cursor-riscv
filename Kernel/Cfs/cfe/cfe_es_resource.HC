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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_resource.c AND the twenty-four
// `static inline` accessors of cfe_es_resource.h -- HOW ES FINDS A RECORD.
//
// Four tables in CFE_ES_Global -- apps, libraries, tasks, counters -- and three ways to reach a
// record in each: by ID, by NAME, and BY CALLING CONTEXT. The third is the interesting one:
// CFE_ES_GetAppRecordByContext asks OSAL which task is running, maps that to an ES task record,
// and reads the app id out of it. That is how every cFS call that says "the calling
// application" knows who is calling, and it is why CFE_ES_GetAppID needs no argument.
//
// THE TASK TABLE IS INDEXED DIFFERENTLY FROM THE OTHER THREE, and this is the one thing in the
// file that will mislead a reader who skims. Apps, libraries and counters are indexed by
// subtracting a cFE resource-id base. A TASK is indexed by handing the id to OSAL --
// CFE_ES_TaskID_ToIndex converts to an osal_id_t and calls OS_ObjectIdToArrayIndex -- because
// an ES task record must line up with the OSAL task it wraps. The conversion is an XOR with
// CFE_RESOURCEID_MARK in both directions, which is a bijection, so it is reversible and
// CFE_ES_TaskId_FromOSAL is the same operation again.
#ifndef CFE_ES_RESOURCE_HC
#define CFE_ES_RESOURCE_HC
#include "cfe_es_mempool.HC" // the ES chain: global state, the pool, the syslog
// --- cfe_core_resourceid_basevalues.h: the three bases this file subtracts -------------------
// ES_APPID_BASE_OFFSET is already in cfe_sb_api.HC (SB needs an app id to compare pipe
// ownership); the other three are here. Written from NASA's enumerator list rather than from
// the ordering in the file, after check_constants caught the pool-id base being off by one.
#define CFE_RESOURCEID_ES_LIBID_BASE_OFFSET   (OS_OBJECT_TYPE_USER + 2)
#define CFE_RESOURCEID_ES_COUNTID_BASE_OFFSET (OS_OBJECT_TYPE_USER + 3)
#define CFE_ES_LIBID_BASE   CFE_RESOURCEID_MAKE_BASE(CFE_RESOURCEID_ES_LIBID_BASE_OFFSET)
#define CFE_ES_COUNTID_BASE CFE_RESOURCEID_MAKE_BASE(CFE_RESOURCEID_ES_COUNTID_BASE_OFFSET)
// A TASK ID IS NOT MADE WITH MAKE_BASE. NASA's CFE_ES_TASKID_BASE is
// CFE_RESOURCEID_MAKE_BASE(OS_OBJECT_TYPE_OS_TASK) -- the OSAL object type, not a cFE offset --
// which is what makes the XOR below line an ES task id up with its OSAL one.
#define CFE_ES_TASKID_BASE CFE_RESOURCEID_MAKE_BASE(OS_OBJECT_TYPE_OS_TASK)
// --- what this file needs from elsewhere ------------------------------------------------------
// OSAL's id arithmetic and the running task's id.
U32 OS_TaskGetId();
U32 OS_ObjectIdFromInteger(U64 Value);
U64 OS_ObjectIdToInteger(U32 object_id);
I32 OS_ObjectIdToArrayIndex(U32 idtype, U32 object_id, U32 *ArrayIndex);
// cfe_es_api.c, translated after this file: the three index conversions it owns.
I32 CFE_ES_AppID_ToIndex(U32 AppID, U32 *Idx);
I32 CFE_ES_LibID_ToIndex(U32 LibId, U32 *Idx);
I32 CFE_ES_TaskID_ToIndex(U32 TaskID, U32 *Idx);
I32 CFE_ES_CounterID_ToIndex(U32 CounterId, U32 *Idx);
// Declared here, defined below -- CFE_ES_GetAppRecordByContext calls the task one.
CFE_ES_TaskRecord_t *CFE_ES_GetTaskRecordByContext();
CFE_ES_AppRecord_t *CFE_ES_LocateAppRecordByID(U32 AppID);
// --- cfe_es_resource.h: the twenty-four accessors, `static inline` in the C ------------------
// HolyC has no `static` on a function and no inline, so these are ordinary functions -- the
// same spelling every other translated inline in this port uses. They are mechanical by design:
// four tables times {IsUsed, GetID, SetUsed, SetFree, IsMatch, GetName}, and the value of
// having them as functions rather than open-coded field reads is that the ID field is the ONE
// place "is this slot in use" is decided.
Bool CFE_ES_AppRecordIsUsed(CFE_ES_AppRecord_t *AppRecPtr)
{
  return CFE_ResourceId_IsDefined(AppRecPtr->AppId);
}

U32 CFE_ES_AppRecordGetID(CFE_ES_AppRecord_t *AppRecPtr)
{
  return AppRecPtr->AppId;
}

U0 CFE_ES_AppRecordSetUsed(CFE_ES_AppRecord_t *AppRecPtr, U32 PendingId)
{
  AppRecPtr->AppId = PendingId;
}

U0 CFE_ES_AppRecordSetFree(CFE_ES_AppRecord_t *AppRecPtr)
{
  AppRecPtr->AppId = CFE_RESOURCEID_UNDEFINED;
}

Bool CFE_ES_AppRecordIsMatch(CFE_ES_AppRecord_t *AppRecPtr, U32 AppID)
{
  return AppRecPtr != NULL && AppRecPtr->AppId == AppID;
}

U8 *CFE_ES_AppRecordGetName(CFE_ES_AppRecord_t *AppRecPtr)
{
  return AppRecPtr->AppName;
}

Bool CFE_ES_LibRecordIsUsed(CFE_ES_LibRecord_t *LibRecPtr)
{
  return CFE_ResourceId_IsDefined(LibRecPtr->LibId);
}

U32 CFE_ES_LibRecordGetID(CFE_ES_LibRecord_t *LibRecPtr)
{
  return LibRecPtr->LibId;
}

U0 CFE_ES_LibRecordSetUsed(CFE_ES_LibRecord_t *LibRecPtr, U32 PendingId)
{
  LibRecPtr->LibId = PendingId;
}

U0 CFE_ES_LibRecordSetFree(CFE_ES_LibRecord_t *LibRecPtr)
{
  LibRecPtr->LibId = CFE_RESOURCEID_UNDEFINED;
}

Bool CFE_ES_LibRecordIsMatch(CFE_ES_LibRecord_t *LibRecPtr, U32 LibID)
{
  return LibRecPtr != NULL && LibRecPtr->LibId == LibID;
}

U8 *CFE_ES_LibRecordGetName(CFE_ES_LibRecord_t *LibRecPtr)
{
  return LibRecPtr->LibName;
}

U32 CFE_ES_TaskRecordGetID(CFE_ES_TaskRecord_t *TaskRecPtr)
{
  return TaskRecPtr->TaskId;
}

Bool CFE_ES_TaskRecordIsUsed(CFE_ES_TaskRecord_t *TaskRecPtr)
{
  return CFE_ResourceId_IsDefined(TaskRecPtr->TaskId);
}

U0 CFE_ES_TaskRecordSetUsed(CFE_ES_TaskRecord_t *TaskRecPtr, U32 PendingId)
{
  TaskRecPtr->TaskId = PendingId;
}

U0 CFE_ES_TaskRecordSetFree(CFE_ES_TaskRecord_t *TaskRecPtr)
{
  TaskRecPtr->TaskId = CFE_RESOURCEID_UNDEFINED;
}

Bool CFE_ES_TaskRecordIsMatch(CFE_ES_TaskRecord_t *TaskRecPtr, U32 TaskID)
{
  return TaskRecPtr != NULL && TaskRecPtr->TaskId == TaskID;
}

U8 *CFE_ES_TaskRecordGetName(CFE_ES_TaskRecord_t *TaskRecPtr)
{
  return TaskRecPtr->TaskName;
}

Bool CFE_ES_CounterRecordIsUsed(CFE_ES_GenCounterRecord_t *CounterRecPtr)
{
  return CFE_ResourceId_IsDefined(CounterRecPtr->CounterId);
}

U32 CFE_ES_CounterRecordGetID(CFE_ES_GenCounterRecord_t *CounterRecPtr)
{
  return CounterRecPtr->CounterId;
}

U0 CFE_ES_CounterRecordSetUsed(CFE_ES_GenCounterRecord_t *CounterRecPtr, U32 PendingId)
{
  CounterRecPtr->CounterId = PendingId;
}

U0 CFE_ES_CounterRecordSetFree(CFE_ES_GenCounterRecord_t *CounterRecPtr)
{
  CounterRecPtr->CounterId = CFE_RESOURCEID_UNDEFINED;
}

Bool CFE_ES_CounterRecordIsMatch(CFE_ES_GenCounterRecord_t *CounterRecPtr, U32 CounterID)
{
  return CounterRecPtr != NULL && CounterRecPtr->CounterId == CounterID;
}

U8 *CFE_ES_CounterRecordGetName(CFE_ES_GenCounterRecord_t *CounterRecPtr)
{
  return CounterRecPtr->CounterName;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE XOR IS A BIJECTION AND THAT IS THE WHOLE TRICK. An ES task id and the OSAL task id it
// wraps differ by CFE_RESOURCEID_MARK, so the same XOR converts either way and
// CFE_ES_TaskId_FromOSAL below is this function again with the two names swapped. It is why an
// ES task record can be indexed by asking OSAL for its array slot instead of by subtracting a
// cFE base, which is what the other three tables do.
U32 CFE_ES_TaskId_ToOSAL(U32 id)
{
  U32 Result;
  U64 Val;
  Val = CFE_ResourceId_ToInteger(id);
  Result = OS_ObjectIdFromInteger(Val ^ CFE_RESOURCEID_MARK);
  return Result;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U32 CFE_ES_TaskId_FromOSAL(U32 id)
{
  U32 Result;
  U64 Val;
  Val = OS_ObjectIdToInteger(id);
  Result = CFE_ResourceId_FromInteger(Val ^ CFE_RESOURCEID_MARK);
  return Result;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE THREE BY-NAME SEARCHES ARE A LINEAR SCAN AND THE LOOP SHAPE IS NASA'S. `while (TRUE)`
// with the count test first, so an empty table exits before touching a record, and the pointer
// is set to NULL on the exhausted path rather than after the loop -- which means the return
// value carries both the result and the not-found answer in one variable.
CFE_ES_AppRecord_t *CFE_ES_LocateAppRecordByName(U8 *Name)
{
  CFE_ES_AppRecord_t *AppRecPtr;
  U32 Count;
  /*
  ** Search the Application table for an app with a matching name.
  */
  AppRecPtr = CFE_ES_Global.AppTable;
  Count = CFE_PLATFORM_ES_MAX_APPLICATIONS;
  while (TRUE) {
    if (Count == 0) {
      AppRecPtr = NULL;
      break;
    }
    if (CFE_ES_AppRecordIsUsed(AppRecPtr) && !StrCmp(Name, CFE_ES_AppRecordGetName(AppRecPtr))) {
      break;
    }
    ++AppRecPtr;
    --Count;
  }
  return AppRecPtr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_ES_LibRecord_t *CFE_ES_LocateLibRecordByName(U8 *Name)
{
  CFE_ES_LibRecord_t *LibRecPtr;
  U32 Count;
  /*
  ** Search the Library table for a library with a matching name.
  */
  LibRecPtr = CFE_ES_Global.LibTable;
  Count = CFE_PLATFORM_ES_MAX_LIBRARIES;
  while (TRUE) {
    if (Count == 0) {
      LibRecPtr = NULL;
      break;
    }
    if (CFE_ES_LibRecordIsUsed(LibRecPtr) && !StrCmp(Name, CFE_ES_LibRecordGetName(LibRecPtr))) {
      break;
    }
    ++LibRecPtr;
    --Count;
  }
  return LibRecPtr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_ES_GenCounterRecord_t *CFE_ES_LocateCounterRecordByName(U8 *Name)
{
  CFE_ES_GenCounterRecord_t *CounterRecPtr;
  U32 Count;
  /*
  ** Search the Counter table for a counter with a matching name.
  */
  CounterRecPtr = CFE_ES_Global.CounterTable;
  Count = CFE_PLATFORM_ES_MAX_GEN_COUNTERS;
  while (TRUE) {
    if (Count == 0) {
      CounterRecPtr = NULL;
      break;
    }
    if (CFE_ES_CounterRecordIsUsed(CounterRecPtr) && !StrCmp(Name, CFE_ES_CounterRecordGetName(CounterRecPtr))) {
      break;
    }
    ++CounterRecPtr;
    --Count;
  }
  return CounterRecPtr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_ES_AppRecord_t *CFE_ES_LocateAppRecordByID(U32 AppID)
{
  CFE_ES_AppRecord_t *AppRecPtr;
  U32 Idx;
  if (CFE_ES_AppID_ToIndex(AppID, &Idx) == CFE_SUCCESS) {
    AppRecPtr = &CFE_ES_Global.AppTable[Idx];
  } else {
    AppRecPtr = NULL;
  }
  return AppRecPtr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_ES_LibRecord_t *CFE_ES_LocateLibRecordByID(U32 LibID)
{
  CFE_ES_LibRecord_t *LibRecPtr;
  U32 Idx;
  if (CFE_ES_LibID_ToIndex(LibID, &Idx) == CFE_SUCCESS) {
    LibRecPtr = &CFE_ES_Global.LibTable[Idx];
  } else {
    LibRecPtr = NULL;
  }
  return LibRecPtr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_ES_TaskRecord_t *CFE_ES_LocateTaskRecordByID(U32 TaskID)
{
  CFE_ES_TaskRecord_t *TaskRecPtr;
  U32 Idx;
  if (CFE_ES_TaskID_ToIndex(TaskID, &Idx) == CFE_SUCCESS) {
    TaskRecPtr = &CFE_ES_Global.TaskTable[Idx];
  } else {
    TaskRecPtr = NULL;
  }
  return TaskRecPtr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
CFE_ES_GenCounterRecord_t *CFE_ES_LocateCounterRecordByID(U32 CounterID)
{
  CFE_ES_GenCounterRecord_t *CounterRecPtr;
  U32 Idx;
  if (CFE_ES_CounterID_ToIndex(CounterID, &Idx) == CFE_SUCCESS) {
    CounterRecPtr = &CFE_ES_Global.CounterTable[Idx];
  } else {
    CounterRecPtr = NULL;
  }
  return CounterRecPtr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// "THIS REQUIRES/ASSUMES THE GLOBAL DATA IS LOCKED" IS NASA'S OWN COMMENT ON THE MATCH TEST,
// and it is the reason this function is not simply a lookup: between locating the record and
// confirming it, another task could delete the one being looked at. The confirm is what makes
// the answer a record that WAS valid at a known moment rather than a pointer into the table.
CFE_ES_TaskRecord_t *CFE_ES_GetTaskRecordByContext()
{
  CFE_ES_TaskRecord_t *TaskRecPtr;
  U32 TaskID;
  /*
  ** Use the OS task ID to get the ES task record
  */
  TaskID = CFE_ES_TaskId_FromOSAL(OS_TaskGetId);
  TaskRecPtr = CFE_ES_LocateTaskRecordByID(TaskID);
  /*
   * Confirm that the entry is actually a match (this requires/assumes
   * the global data is locked).
   *
   * If not a match, return NULL.
   */
  if (!CFE_ES_TaskRecordIsMatch(TaskRecPtr, TaskID)) {
    TaskRecPtr = NULL;
  }
  return TaskRecPtr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// TWO HOPS, AND BOTH ARE CONFIRMED. OSAL's running task -> an ES task record -> the app id in
// it -> an ES app record, with a match test after each lookup. This is what every cFS call that
// says "the calling application" is built on; CFE_ES_GetAppID is a four-line wrapper over it.
CFE_ES_AppRecord_t *CFE_ES_GetAppRecordByContext()
{
  CFE_ES_AppRecord_t *AppRecPtr;
  CFE_ES_TaskRecord_t *TaskRecPtr;
  /*
  ** Step 1: Get the task record
  */
  TaskRecPtr = CFE_ES_GetTaskRecordByContext();
  if (TaskRecPtr != NULL) {
    /*
    ** Step 2: get the Application ID for the current task
    */
    AppRecPtr = CFE_ES_LocateAppRecordByID(TaskRecPtr->AppId);
    /*
     * Confirm that the entry is actually a match (this requires/assumes
     * the global data is locked).
     *
     * If not a match, return NULL.
     */
    if (!CFE_ES_AppRecordIsMatch(AppRecPtr, TaskRecPtr->AppId)) {
      AppRecPtr = NULL;
    }
  } else {
    AppRecPtr = NULL;
  }
  return AppRecPtr;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE THREE SLOT-USED PREDICATES FAIL SAFE BY SAYING "TAKEN", and NASA's comment -- repeated
// verbatim on all three -- explains why: a NULL record means the id was out of range, and
// claiming the slot is in use makes CFE_ResourceId_FindNext move on rather than hand it out.
// cfe_es_mempool.HC's CFE_ES_CheckMemPoolSlotUsed is the fourth of the same shape.
Bool CFE_ES_CheckCounterIdSlotUsed(U32 CheckId)
{
  CFE_ES_GenCounterRecord_t *GenCounterRecPtr;
  /*
   * Note - The pointer here should never be NULL because the ID should always be
   * within the expected range, but if it ever is NULL, this should return true
   * such that the caller will _not_ attempt to use the record.
   */
  GenCounterRecPtr = CFE_ES_LocateCounterRecordByID(CheckId);
  return GenCounterRecPtr == NULL || CFE_ES_CounterRecordIsUsed(GenCounterRecPtr);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_ES_CheckAppIdSlotUsed(U32 CheckId)
{
  CFE_ES_AppRecord_t *AppRecPtr;
  /*
   * Note - The pointer here should never be NULL because the ID should always be
   * within the expected range, but if it ever is NULL, this should return true
   * such that the caller will _not_ attempt to use the record.
   */
  AppRecPtr = CFE_ES_LocateAppRecordByID(CheckId);
  return AppRecPtr == NULL || CFE_ES_AppRecordIsUsed(AppRecPtr);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
Bool CFE_ES_CheckLibIdSlotUsed(U32 CheckId)
{
  CFE_ES_LibRecord_t *LibRecPtr;
  /*
   * Note - The pointer here should never be NULL because the ID should always be
   * within the expected range, but if it ever is NULL, this should return true
   * such that the caller will _not_ attempt to use the record.
   */
  LibRecPtr = CFE_ES_LocateLibRecordByID(CheckId);
  return LibRecPtr == NULL || CFE_ES_LibRecordIsUsed(LibRecPtr);
}
#endif
