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
// OSAL src/os/inc/osapi-filesys.h -- THE TYPE ONLY, with no implementation behind it.
//
// The third of these, after osapi_heap_decl.HC and osapi_module_decl.HC, and the reason is the
// same every time: cfe_es_start.c declares an OS_statvfs_t to ask the RAM disk how full it is,
// so the cFE translation needs the TYPE -- and os_shared_filesys.HC merges NASA's shared-layer
// header with that layer's own state, so including it would drag OSAL's implementation across
// the seam that check_seam exists to protect.
//
// Re-declaring the class in cfe_es_start.HC would have worked, and that is exactly the problem:
// the compiler accepts a duplicate class SILENTLY, so the layout rule would then live in two
// places for check_padding to measure separately and for one of them to drift.
#ifndef OSAPI_FILESYS_DECL_HC
#define OSAPI_FILESYS_DECL_HC
// --- osapi-filesys.h ------------------------------------------------------------------------
// THREE BLOCK COUNTS, AND THE FREE-SPACE CHECK IS INTEGER PERCENT. cfe_es_start.c computes
// `(blocks_free * 100) / total_blocks` and reformats the volatile disk below
// CFE_PLATFORM_ES_RAM_DISK_PERCENT_RESERVED, so the widths here are what keep that arithmetic
// from overflowing on a large volume.
class OS_statvfs_t
{
  I64 block_size;   // size_t
  I64 total_blocks; // osal_blockcount_t
  I64 blocks_free;  // osal_blockcount_t
};
#endif
