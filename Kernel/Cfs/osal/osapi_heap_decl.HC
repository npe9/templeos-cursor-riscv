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
// OSAL src/os/inc/osapi-heap.h -- THE TYPE ONLY, with no implementation behind it.
//
// WHY IT IS ITS OWN FILE, which is the same answer cfe_sb_decl.HC gives. cfe_es_task.c fills an
// OS_heap_prop_t from OS_HeapGetInfo, so the cFE translation needs the TYPE -- but osapi_heap.HC
// merges NASA's header and its .c, so including it would drag OSAL's implementation into the
// cFE translation unit. That is the one thing check_seam exists to prevent: cFE sees OSAL only
// through its API. It also collided outright, because both differential drivers supply their
// own OS_HeapGetInfo stub.
//
// Declaring the class a second time inside cfe_es_task.HC would have worked -- the compiler
// accepts a duplicate class SILENTLY, which is the problem -- and left one layout rule in two
// places for check_padding to measure separately. One definition, in the layer that owns it.
#ifndef OSAPI_HEAP_DECL_HC
#define OSAPI_HEAP_DECL_HC
// --- osapi-heap.h ----------------------------------------------------------------------------
class OS_heap_prop_t
{
  I64 free_bytes;         // size_t
  I64 free_blocks;        // osal_blockcount_t, itself a size_t
  I64 largest_free_block; // size_t
};
#endif
