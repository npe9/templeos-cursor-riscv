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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-network.c.
#ifndef OSAPI_NETWORK_HC
#define OSAPI_NETWORK_HC

// The backend seam. Declared before use because HolyC is single-pass.
I32 OS_NetworkGetHostName_Impl(U8 *host_name, I64 name_len);
I32 OS_NetworkGetID_Impl(I32 *IdBuf);

I32 OS_NetworkAPI_Init()
{
  return OS_SUCCESS;
}

I32 OS_NetworkGetHostName(U8 *host_name, I64 name_len)
{
  I32 return_code;
  // OS_CHECK_POINTER is a BUGCHECK and LOGS; OS_CHECK_SIZE is a silent ARGCHECK.
  if (host_name == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  if (!(name_len > 0 && name_len < 0x7FFFFFFF))
    return OS_ERR_INVALID_SIZE;
  // delegate to low-level API
  return_code = OS_NetworkGetHostName_Impl(host_name, name_len);
  if (return_code != OS_SUCCESS) {
    // return an empty string on failure, just in case
    host_name[0] = 0;
  }
  return return_code;
}

I32 OS_NetworkGetID()
{
  I32 IdBuf;
  // always delegate to low-level API
  if (OS_NetworkGetID_Impl(&IdBuf) != OS_SUCCESS) {
    // return a hardcoded value on failure
    return -1;
  }
  return IdBuf;
}
#endif
