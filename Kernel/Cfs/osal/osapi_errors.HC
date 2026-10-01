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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-errors.c, with the types from
// src/os/shared/inc/os-shared-errors.h and the status codes from src/os/inc/osapi-error.h.
//
// FIRST FILE OF OSAL'S PORTABLE LAYER. That layer is 9,523 lines across 26 files and makes ZERO
// direct OS calls -- no pthread, no sem, no open/read/write, no malloc, verified by grep. Its
// whole job is validation, id mapping and dispatch to 128 OS_*_Impl functions that a backend
// supplies. So it translates like cFE does, and it can be TESTED without a backend, which is why
// it comes before the hand-written TempleOS backend rather than after.
//
// The status codes below are extracted from osapi-error.h by script rather than retyped. There
// are 45 of them and a single wrong digit would be invisible until something compared against it.
#ifndef OSAPI_ERRORS_HC
#define OSAPI_ERRORS_HC
#include "../CfsStr.HC"
#include "os_shared_errors.HC"
// From osapi-printf.h. That module is part of the shared layer and not translated yet; whoever
// links this supplies it, and the gate asserts an empty import trailer so it cannot go missing.
U0 OS_printf(U8 *fmt);
// --- osapi-error.h ---------------------------------------------------------------------------
#define OS_ERROR_NAME_LENGTH    35
#define OS_STATUS_STRING_LENGTH 12
#define OS_SUCCESS                       0
#define OS_ERROR                         -1
#define OS_INVALID_POINTER               -2
#define OS_ERROR_ADDRESS_MISALIGNED      -3
#define OS_ERROR_TIMEOUT                 -4
#define OS_INVALID_INT_NUM               -5
#define OS_SEM_FAILURE                   -6
#define OS_SEM_TIMEOUT                   -7
#define OS_QUEUE_EMPTY                   -8
#define OS_QUEUE_FULL                    -9
#define OS_QUEUE_TIMEOUT                 -10
#define OS_QUEUE_INVALID_SIZE            -11
#define OS_QUEUE_ID_ERROR                -12
#define OS_ERR_NAME_TOO_LONG             -13
#define OS_ERR_NO_FREE_IDS               -14
#define OS_ERR_NAME_TAKEN                -15
#define OS_ERR_INVALID_ID                -16
#define OS_ERR_NAME_NOT_FOUND            -17
#define OS_ERR_SEM_NOT_FULL              -18
#define OS_ERR_INVALID_PRIORITY          -19
#define OS_INVALID_SEM_VALUE             -20
#define OS_ERR_FILE                      -27
#define OS_ERR_NOT_IMPLEMENTED           -28
#define OS_TIMER_ERR_INVALID_ARGS        -29
#define OS_TIMER_ERR_TIMER_ID            -30
#define OS_TIMER_ERR_UNAVAILABLE         -31
#define OS_TIMER_ERR_INTERNAL            -32
#define OS_ERR_OBJECT_IN_USE             -33
#define OS_ERR_BAD_ADDRESS               -34
#define OS_ERR_INCORRECT_OBJ_STATE       -35
#define OS_ERR_INCORRECT_OBJ_TYPE        -36
#define OS_ERR_STREAM_DISCONNECTED       -37
#define OS_ERR_OPERATION_NOT_SUPPORTED   -38
#define OS_ERR_INVALID_SIZE              -40
#define OS_ERR_OUTPUT_TOO_LARGE          -41
#define OS_ERR_INVALID_ARGUMENT          -42
#define OS_ERR_TRY_AGAIN                 -43
#define OS_ERR_EMPTY_SET                 -44
#define OS_FS_ERR_PATH_TOO_LONG          -103
#define OS_FS_ERR_NAME_TOO_LONG          -104
#define OS_FS_ERR_DRIVE_NOT_CREATED      -106
#define OS_FS_ERR_DEVICE_NOT_FREE        -107
#define OS_FS_ERR_PATH_INVALID           -108

// From osapi-error.h, a static inline: the identity, but it is what documents that a status is
// a signed quantity and prints as one.
I64 OS_StatusToInteger(I64 Status)
{
  return Status;
}
// OS_ErrorTable_Entry comes from os_shared_errors.HC, and OS_IMPL_ERROR_NAME_TABLE must ALREADY
// BE DEFINED by the backend before this file is included -- see that file for why the include
// order does a linker's job here. Each OS contributes the error names peculiar to it (POSIX
// errno wrappers, VxWorks status codes); a bare-metal target with none supplies an empty table.
// --- osapi-errors.c ---------------------------------------------------------------------------
// The table is NOT sorted and NOT indexed by value -- the codes have gaps (-20 jumps to -27, -38
// to -40, -44 to -103), so a lookup has to walk it. A NULL Name is the terminator. The rows
// below are generated from NASA's own table in source order rather than retyped.
OS_ErrorTable_Entry OS_GLOBAL_ERROR_NAME_TABLE[] = {
  {OS_SUCCESS, 0, "OS_SUCCESS"},
  {OS_ERROR, 0, "OS_ERROR"},
  {OS_INVALID_POINTER, 0, "OS_INVALID_POINTER"},
  {OS_ERROR_ADDRESS_MISALIGNED, 0, "OS_ERROR_ADDRESS_MISALIGNED"},
  {OS_ERROR_TIMEOUT, 0, "OS_ERROR_TIMEOUT"},
  {OS_INVALID_INT_NUM, 0, "OS_INVALID_INT_NUM"},
  {OS_SEM_FAILURE, 0, "OS_SEM_FAILURE"},
  {OS_SEM_TIMEOUT, 0, "OS_SEM_TIMEOUT"},
  {OS_QUEUE_EMPTY, 0, "OS_QUEUE_EMPTY"},
  {OS_QUEUE_FULL, 0, "OS_QUEUE_FULL"},
  {OS_QUEUE_TIMEOUT, 0, "OS_QUEUE_TIMEOUT"},
  {OS_QUEUE_INVALID_SIZE, 0, "OS_QUEUE_INVALID_SIZE"},
  {OS_QUEUE_ID_ERROR, 0, "OS_QUEUE_ID_ERROR"},
  {OS_ERR_NAME_TOO_LONG, 0, "OS_ERR_NAME_TOO_LONG"},
  {OS_ERR_NO_FREE_IDS, 0, "OS_ERR_NO_FREE_IDS"},
  {OS_ERR_NAME_TAKEN, 0, "OS_ERR_NAME_TAKEN"},
  {OS_ERR_INVALID_ID, 0, "OS_ERR_INVALID_ID"},
  {OS_ERR_NAME_NOT_FOUND, 0, "OS_ERR_NAME_NOT_FOUND"},
  {OS_ERR_SEM_NOT_FULL, 0, "OS_ERR_SEM_NOT_FULL"},
  {OS_ERR_INVALID_PRIORITY, 0, "OS_ERR_INVALID_PRIORITY"},
  {OS_INVALID_SEM_VALUE, 0, "OS_INVALID_SEM_VALUE"},
  {OS_ERR_FILE, 0, "OS_ERR_FILE"},
  {OS_ERR_NOT_IMPLEMENTED, 0, "OS_ERR_NOT_IMPLEMENTED"},
  {OS_TIMER_ERR_INVALID_ARGS, 0, "OS_TIMER_ERR_INVALID_ARGS"},
  {OS_TIMER_ERR_TIMER_ID, 0, "OS_TIMER_ERR_TIMER_ID"},
  {OS_TIMER_ERR_UNAVAILABLE, 0, "OS_TIMER_ERR_UNAVAILABLE"},
  {OS_TIMER_ERR_INTERNAL, 0, "OS_TIMER_ERR_INTERNAL"},
  {OS_ERR_OBJECT_IN_USE, 0, "OS_ERR_OBJECT_IN_USE"},
  {OS_ERR_BAD_ADDRESS, 0, "OS_ERR_BAD_ADDRESS"},
  {OS_ERR_INCORRECT_OBJ_STATE, 0, "OS_ERR_INCORRECT_OBJ_STATE"},
  {OS_ERR_INCORRECT_OBJ_TYPE, 0, "OS_ERR_INCORRECT_OBJ_TYPE"},
  {OS_ERR_STREAM_DISCONNECTED, 0, "OS_ERR_STREAM_DISCONNECTED"},
  {OS_ERR_OPERATION_NOT_SUPPORTED, 0, "OS_ERR_OPERATION_NOT_SUPPORTED"},
  {OS_ERR_INVALID_SIZE, 0, "OS_ERR_INVALID_SIZE"},
  {OS_ERR_OUTPUT_TOO_LARGE, 0, "OS_ERR_OUTPUT_TOO_LARGE"},
  {OS_ERR_INVALID_ARGUMENT, 0, "OS_ERR_INVALID_ARGUMENT"},
  {OS_FS_ERR_PATH_TOO_LONG, 0, "OS_FS_ERR_PATH_TOO_LONG"},
  {OS_FS_ERR_NAME_TOO_LONG, 0, "OS_FS_ERR_NAME_TOO_LONG"},
  {OS_FS_ERR_DRIVE_NOT_CREATED, 0, "OS_FS_ERR_DRIVE_NOT_CREATED"},
  {OS_FS_ERR_DEVICE_NOT_FREE, 0, "OS_FS_ERR_DEVICE_NOT_FREE"},
  {OS_FS_ERR_PATH_INVALID, 0, "OS_FS_ERR_PATH_INVALID"},
  {0, 0, NULL},
};

// os_status_string_t is char[OS_STATUS_STRING_LENGTH] and the C takes a POINTER TO THE ARRAY, so
// its sizeof(*status_string) is the array's size rather than a pointer's. HolyC has no
// pointer-to-array type that preserves that, so the buffer is passed directly and the length is
// the constant the C's sizeof would have yielded. Same bytes written, one fewer indirection.
U8 *OS_StatusToString(I32 status, U8 *status_string)
{
  U8 *string = NULL;
  if (status_string != NULL) {
    // SAD: No need to check snprintf return; OS_STATUS_STRING_LENGTH (12) is ample for all
    // status values
    StrPrintN(status_string, OS_STATUS_STRING_LENGTH, "%ld", OS_StatusToInteger(status));
    string = status_string;
  }
  return string;
}

I32 OS_GetErrorName(I32 error_num, U8 *err_name)
{
  I32 return_code;
  OS_ErrorTable_Entry *Error;
  // OS_CHECK_POINTER(err_name) expands to BUGCHECK((ptr) != NULL, OS_INVALID_POINTER), which
  // LOGS through OS_printf and then returns:
  //     BUGREPORT("\n**BUG** %s():%d:check '%s' FAILED --> %s\n\n", __func__, __LINE__, ...)
  // __func__, __LINE__ and the stringified macro arguments have no HolyC equivalent, so the
  // check and the return are translated and the WORDING is not. Both sides of the oracle print
  // the same fixed marker, so the transcript pins which checks fire rather than their text --
  // the same call made for CFE_ES_WriteToSysLog.
  if (err_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  Error = OS_GLOBAL_ERROR_NAME_TABLE;
  while (Error->Name != NULL && Error->Number != error_num)
    ++Error;
  if (Error->Number != error_num) {
    Error = OS_IMPL_ERROR_NAME_TABLE;
    while (Error->Name != NULL && Error->Number != error_num)
      ++Error;
  }
  if (Error->Number == error_num && Error->Name != NULL) {
    StrNCpy(err_name, Error->Name, OS_ERROR_NAME_LENGTH - 1);
    err_name[OS_ERROR_NAME_LENGTH - 1] = 0;
    return_code = OS_SUCCESS;
  } else {
    StrPrintN(err_name, OS_ERROR_NAME_LENGTH, "OS_UNKNOWN(%d)", error_num);
    return_code = OS_ERROR;
  }
  err_name[OS_ERROR_NAME_LENGTH - 1] = 0;
  return return_code;
}
#endif
