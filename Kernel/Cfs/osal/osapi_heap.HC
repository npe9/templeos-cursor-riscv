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

// 1:1 HolyC translation of OSAL src/os/shared/src/osapi-heap.c and the type from
// src/os/inc/osapi-heap.h. The whole module is one argument check and a dispatch, which is what
// most of this layer looks like -- the portable side validates, the backend does the work.
#ifndef OSAPI_HEAP_HC
#define OSAPI_HEAP_HC
#include "osapi_errors.HC"
#include "osapi_heap_decl.HC" // OS_heap_prop_t -- the header half, which cFE needs on its own
// --- the backend seam --------------------------------------------------------------------------
I32 OS_HeapGetInfo_Impl(OS_heap_prop_t *heap_prop);
// --- osapi-heap.c ------------------------------------------------------------------------------
I32 OS_HeapGetInfo(OS_heap_prop_t *heap_prop)
{
  // Check parameters
  if (heap_prop == NULL) {
    OS_printf("bugcheck\n");
    return OS_INVALID_POINTER;
  }
  return OS_HeapGetInfo_Impl(heap_prop);
}
#endif
