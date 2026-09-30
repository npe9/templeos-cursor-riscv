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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-shell.c.
#ifndef OSAPI_SHELL_HC
#define OSAPI_SHELL_HC

I32 OS_ShellOutputToFile_Impl(OS_object_token_t *token, U8 *Cmd);

I32 OS_ShellOutputToFile(U8 *Cmd, U32 filedes)
{
  OS_object_token_t token;
  I32 return_code;
  if (Cmd == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  // REFCOUNT, not GLOBAL: the stream stays usable by others while the shell writes to it.
  return_code = OS_ObjectIdGetById(OS_LOCK_MODE_REFCOUNT, OS_OBJECT_TYPE_OS_STREAM, filedes,
                                   &token);
  if (return_code == OS_SUCCESS) {
    return_code = OS_ShellOutputToFile_Impl(&token, Cmd);
    OS_ObjectIdRelease(&token);
  }
  return return_code;
}
#endif
