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

// Stand-ins for the two <string.h> routines the translated cFE sources call.
//
// NOT a translation of anything -- cFE calls the C library, and this is what the C library owes
// it. The kernel has MemSet in Kernel/KUtilsRV.HC, but the translated units are deliberately
// standalone so that the differential oracle tests the translation and nothing else. The names
// are the C ones so the call sites can stay character-for-character what NASA wrote.
#ifndef CFE_XLAT_LIBC_HC
#define CFE_XLAT_LIBC_HC
U0 memset(U8 *dst, I64 c, I64 n)
{
  while (n > 0) {
    *dst++ = c;
    n--;
  }
}

U0 memcpy(U8 *dst, U8 *src, I64 n)
{
  while (n > 0) {
    *dst++ = *src++;
    n--;
  }
}
#endif
