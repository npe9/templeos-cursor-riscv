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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-select.c.
//
// The whole module is bit arithmetic over a fixed-size set, so the thing to get right is the
// index split: local_id >> 3 picks the BYTE and (local_id & 0x7) picks the BIT within it.
// OS_MAX_NUM_OPEN_FILES is 50 here, so object_ids is (50 + 7) / 8 = 7 bytes and ids 0..49 must
// land in bytes 0..6 without ever colliding.
#ifndef OSAPI_SELECT_HC
#define OSAPI_SELECT_HC
#include "os_shared_file.HC"

// OS_StreamState_t, an enum in src/os/inc/osapi-select.h; these are its assigned values.
#define OS_STREAM_STATE_BOUND     0x01
#define OS_STREAM_STATE_CONNECTED 0x02
#define OS_STREAM_STATE_READABLE  0x04
#define OS_STREAM_STATE_WRITABLE  0x08
#define OS_STREAM_STATE_LISTENING 0x10

// OS_FdSet, from src/os/inc/osapi-select.h.
class OS_FdSet
{
  U8 object_ids[(OS_MAX_NUM_OPEN_FILES + 7) / 8];
};

// The backend seam. Declared before use because HolyC is single-pass.
I32 OS_SelectSingle_Impl(OS_object_token_t *token, U32 *StateFlags, OS_time_t abs_timeout);
I32 OS_SelectMultiple_Impl(OS_FdSet *ReadSet, OS_FdSet *WriteSet, OS_time_t abs_timeout);

I32 OS_SelectSingleAbs(U32 objid, U32 *StateFlags, OS_time_t abs_timeout)
{
  I32 return_code;
  OS_object_token_t token;
  if (StateFlags == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_REFCOUNT, OS_OBJECT_TYPE_OS_STREAM, objid,
                                   &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_SelectSingle_Impl(&token, StateFlags, abs_timeout);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}

I32 OS_SelectSingle(U32 objid, U32 *StateFlags, I32 msecs)
{
  return OS_SelectSingleAbs(objid, StateFlags, OS_TimeFromRelativeMilliseconds(msecs));
}

I32 OS_SelectMultipleAbs(OS_FdSet *ReadSet, OS_FdSet *WriteSet, OS_time_t abs_timeout)
{
  I32 return_code;
  // ReadSet and WriteSet are deliberately NOT checked: in certain configurations they can
  // validly be null, and NASA says so here.
  //
  // NASA's other note, reproduced because it is a real property of this layer: this does NOT
  // increment any refcounts, so a file or socket can be closed while another thread is inside
  // an OS_SelectMultiple() call on it.
  return_code = OS_SelectMultiple_Impl(ReadSet, WriteSet, abs_timeout);
  return return_code;
}

I32 OS_SelectMultiple(OS_FdSet *ReadSet, OS_FdSet *WriteSet, I32 msecs)
{
  return OS_SelectMultipleAbs(ReadSet, WriteSet, OS_TimeFromRelativeMilliseconds(msecs));
}

I32 OS_SelectFdZero(OS_FdSet *Set)
{
  if (Set == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  MemSet(Set, 0, sizeof(OS_FdSet));
  return OS_SUCCESS;
}

I32 OS_SelectFdAdd(OS_FdSet *Set, U32 objid)
{
  I32 return_code;
  U32 local_id;
  if (Set == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_STREAM, objid, &local_id);
  if (return_code == OS_SUCCESS) {
    // local_id >> 3 is the array element; (local_id & 0x7) is the bit within it.
    Set->object_ids[local_id >> 3] |= 1 << (local_id & 0x7);
  }
  return return_code;
}

I32 OS_SelectFdClear(OS_FdSet *Set, U32 objid)
{
  I32 return_code;
  U32 local_id;
  if (Set == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return_code = OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_STREAM, objid, &local_id);
  if (return_code == OS_SUCCESS)
    Set->object_ids[local_id >> 3] &= ~(1 << (local_id & 0x7));
  return return_code;
}

Bool OS_SelectFdIsSet(OS_FdSet *Set, U32 objid)
{
  I32 return_code;
  U32 local_id;
  // BUGCHECK(Set != NULL, false) -- note this one returns FALSE rather than an error code,
  // because the function returns bool. It still logs.
  if (Set == NULL) {
    OS_printf("bugcheck\n");
    return FALSE;
  }
  return_code = OS_ObjectIdToArrayIndex(OS_OBJECT_TYPE_OS_STREAM, objid, &local_id);
  if (return_code != OS_SUCCESS)
    return FALSE;
  return (Set->object_ids[local_id >> 3] >> (local_id & 0x7)) & 0x1;
}
#endif
