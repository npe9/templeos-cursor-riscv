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
// HOUSEKEEPING'S CONFIGURATION AND PERFORMANCE IDS -- the 1:1 translation of NASA's
// fsw/inc/hk_internal_cfg.h, fsw/inc/hk_interface_cfg.h, fsw/inc/hk_perfids.h and
// fsw/src/hk_version.h, with every two-level token-pasted name resolved to its value.
//
// NASA reaches each of these through a macro that pastes a prefix onto a name --
// `HK_PIPE_DEPTH` is `HK_INTERNAL_CFGVAL(PIPE_DEPTH)` which is
// `DEFAULT_HK_INTERNAL_##PIPE_DEPTH` -- and HolyC has no `##`. The resolved values are written
// out, as LC's were, and they were READ OUT OF THE PREPROCESSOR rather than counted by hand.
//
// ### HK_DISCARD_INCOMPLETE_COMBO IS **ZERO**, AND THAT DECIDES A DIRECTIVE
//
// hk_utils.c's HK_SendCombinedHkPacket contains
//
//     #if HK_DISCARD_INCOMPLETE_COMBO == 1
//                 else /* This clause is only exclusive if discarding incomplete packets */
//     #endif
//                 { ... send the packet ... }
//
// which is a `#if` around a BARE `else` -- the directive does not wrap a statement, it decides
// whether the send is the alternative to the missing-data branch or follows it unconditionally.
// With the flag at 0 the `else` is excluded, so **a combined packet with missing data is sent
// ANYWAY**, after its DEBUG event. The translation has no `#if` there and the send is
// unconditional; see hk_utils.HC at the site.
//
// That is the shape docs/HOLYC_STRUCT_LIMITS.md #19 makes dangerous to leave in: `#if <expr>` is
// unconditionally true in this compiler, so writing NASA's directive out verbatim would have
// INCLUDED the `else` and silently inverted the behaviour of HK's main output path. Resolving it
// at translation time is not a convenience here, it is the only correct option.
//
// ### AND THE MEMORY POOL IS 6 KiB FOR A 1500-BYTE PACKET LIMIT
//
// HK_NUM_BYTES_IN_MEM_POOL is 6,144 and HK_MAX_COMBINED_PACKET_SIZE is 1,500, so at most four
// full-size combined packets fit -- and HK_COPY_TABLE_ENTRIES is 128, so a copy table may name
// far more output packets than the pool can hold. HK_ProcessNewCopyTable's
// HK_MEM_POOL_MALLOC_FAILED_EID is the arm that reports it, per packet, and it CONTINUES rather
// than failing the load.
#ifndef HK_CFG_HC
#define HK_CFG_HC

// --- hk_interface_cfg.h: the one value a mission's ground system has to agree with -----------
#define DEFAULT_HK_INTERFACE_COPY_TABLE_ENTRIES 128
#define HK_COPY_TABLE_ENTRIES                   DEFAULT_HK_INTERFACE_COPY_TABLE_ENTRIES

// --- hk_internal_cfg.h -----------------------------------------------------------------------
#define DEFAULT_HK_INTERNAL_PIPE_DEPTH                40
#define HK_PIPE_DEPTH                                 DEFAULT_HK_INTERNAL_PIPE_DEPTH
#define DEFAULT_HK_INTERNAL_DISCARD_INCOMPLETE_COMBO  0
#define HK_DISCARD_INCOMPLETE_COMBO                   DEFAULT_HK_INTERNAL_DISCARD_INCOMPLETE_COMBO
#define DEFAULT_HK_INTERNAL_NUM_BYTES_IN_MEM_POOL     (6 * 1024)
#define HK_NUM_BYTES_IN_MEM_POOL                      DEFAULT_HK_INTERNAL_NUM_BYTES_IN_MEM_POOL
#define DEFAULT_HK_INTERNAL_COPY_TABLE_NAME           "CopyTable"
#define HK_COPY_TABLE_NAME                            DEFAULT_HK_INTERNAL_COPY_TABLE_NAME
#define DEFAULT_HK_INTERNAL_RUNTIME_TABLE_NAME        "RuntimeTable"
#define HK_RUNTIME_TABLE_NAME                         DEFAULT_HK_INTERNAL_RUNTIME_TABLE_NAME
#define DEFAULT_HK_INTERNAL_COPY_TABLE_FILENAME       "/cf/hk_cpy_tbl.tbl"
#define HK_COPY_TABLE_FILENAME                        DEFAULT_HK_INTERNAL_COPY_TABLE_FILENAME
#define DEFAULT_HK_INTERNAL_MISSION_REV               0
#define HK_MISSION_REV                                DEFAULT_HK_INTERNAL_MISSION_REV
#define DEFAULT_HK_INTERNAL_MAX_COMBINED_PACKET_SIZE  1500
#define HK_MAX_COMBINED_PACKET_SIZE                   DEFAULT_HK_INTERNAL_MAX_COMBINED_PACKET_SIZE

// --- hk_version.h. HK_MISSION_REV is NOT here: it is internal configuration, above, which is
// where NASA puts it too -- the same split LC has.
#define HK_MAJOR_VERSION 7
#define HK_MINOR_VERSION 0
#define HK_REVISION      1

// --- hk_perfids.h ----------------------------------------------------------------------------
// ONE performance id, bracketing the main loop. LC has two; HK has only this.
#define HK_APPMAIN_PERF_ID 25

#endif
