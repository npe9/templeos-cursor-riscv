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
// HOUSEKEEPING'S GLOBAL STATE -- the 1:1 translation of NASA's fsw/src/hk_app.h, which is where
// HK_AppData_t lives.
//
// 6,216 bytes, and 6,144 of them -- 98.8% -- are ONE MEMBER: MemPoolBuffer, the backing store HK
// hands to CFE_ES_PoolCreate for the combined output packets it builds. Everything HK actually
// reasons about fits in the first 72 bytes.
//
// ### THE POOL IS INSIDE THE GLOBAL, WHICH IS WHY HK NEEDS NO ALLOCATOR
//
// HK builds output packets at runtime, sized from the copy table, and a copy table load can
// change how many there are and how big each is. So it needs dynamic allocation -- and it gets it
// without ever calling malloc, by handing cFE a fixed array out of its own BSS and letting
// CFE_ES_PoolCreate run a bump-and-bucket allocator inside it. HK_ProcessNewCopyTable takes
// buffers with CFE_ES_GetPoolBuf and HK_TearDownOldCopyTable gives them back with
// CFE_ES_PutPoolBuf, so the pool is the one piece of HK that is genuinely stateful across table
// loads.
//
// AND IT IS THE REASON A COPY TABLE LOAD CAN PARTIALLY FAIL. 6 KiB of pool against a 1,500-byte
// maximum packet size means at most four full-size packets, while the copy table has 128 entries
// -- so a table naming five large output packets gets four and an HK_MEM_POOL_MALLOC_FAILED_EID
// for the fifth, and HK CARRIES ON. The entries whose packet could not be built keep
// OutputPktAddr at zero and are skipped by every later loop, which is exactly how an empty entry
// behaves. See hk_cfg.HC.
//
// ### TWO TABLE HANDLES, AND THEY ARE SIGNED
//
// CFE_TBL_Handle_t is an int16 and CFE_TBL_BAD_TABLE_HANDLE is -1, so these are I16 and not U16
// -- the same two bytes CS's wrapper got wrong and that no layout gate can see, recorded at
// length in cs_table_processing's notes. Holding them unsigned makes the "no handle" value test
// as valid.
#ifndef HK_GLOBAL_HC
#define HK_GLOBAL_HC

#include "hk_cfg.HC"
#include "hk_msg.HC"
#include "hk_tbl.HC"

// --- hk_app.h's OWN constants, which are not configuration and not a type -------------------
//
// These five live in hk_app.h beside HK_AppData_t, which is why they are here rather than in
// hk_cfg.HC: they are not token-pasted configuration values, they are HK's return codes and two
// literals. A first draft of this vocabulary translated the TYPE from hk_app.h and left the
// #defines behind, and the HolyC half failed to compile with four "Undefined variable
// 'HK_SUCCESS'" -- which is the good outcome. A missing CONSTANT is a compile error; a missing
// one that happens to collide with something else is not, and that is why
// docs/CFS_PORT.md asks for a header to be translated whole rather than for the parts a source
// happens to use.
//
// AND THE THREE RETURN CODES ARE NOT cFE STATUS VALUES. HK_SUCCESS is 0 -- the same as
// CFE_SUCCESS -- but HK_ERROR is -1 and HK_BAD_MSG_LENGTH_RC is -2, which are not in cFE's
// 0xCC/0xC4-prefixed space at all. So a function returning HK_ERROR and one returning a cFE
// status cannot have their results compared against each other, and HK never does: the HK_*
// codes stay inside hk_utils.c and hk_dispatch.c.
#define HK_PIPE_NAME "HK_CMD_PIPE"
#define HK_SUCCESS           0
#define HK_ERROR             -1
#define HK_BAD_MSG_LENGTH_RC -2
#define HK_SB_TIMEOUT        1000

/*******************************************************************************/
// HK's entire state. 6,216 bytes.
//
// THE PADDING IS NASA'S LAYOUT, NOT A CHOICE, AND THERE ARE EXACTLY TWO HOLES. HkPacket is 28
// bytes so CmdPipe lands at 28; the two uint8 counters at 32 and 33 need NO padding, because
// MissingDataCtr's 16-bit alignment is already satisfied at 34; the hole is at 38, where
// MemPoolHandle's 4-byte alignment skips two bytes; and the second is at 52, where the two int16
// table handles are followed by 8-byte pointers.
//
// THE OFFSETS IN THE RIGHT MARGIN WERE READ OUT OF THE C WITH offsetof, and they are what caught
// the first draft: it padded after CommandErrorCounter as well, and check_padding reported every
// subsequent offset as two too high and the structure as 6,218 against NASA's 6,216.
class HK_AppData_t
{
  HK_HkPacket_t HkPacket; // HK's own housekeeping packet                      offset 0

  U32 CmdPipe;            // CFE_SB_PipeId_t                                   offset 28
  U8 CommandCounter;      // valid commands received                           offset 32
  U8 CommandErrorCounter; // invalid commands received                         offset 33
  // NO PADDING HERE. Two uint8s at 32 and 33 leave MissingDataCtr's 16-bit alignment already
  // satisfied at 34 -- a first draft inserted two bytes and check_padding named every later
  // offset as two too high, which is the whole reason that gate exists.
  U16 MissingDataCtr;      // times missing data was detected                  offset 34
  U16 CombinedPacketsSent; // combined output messages sent                    offset 36
  U8 _pad0[2];             // C aligns the 4-byte MemPoolHandle that follows

  U32 MemPoolHandle; // CFE_ES_MemHandle_t -- the pool below                   offset 40
  U32 RunStatus;     // CFE_ES_RunStatus_* for the main loop                   offset 44

  // SIGNED, because CFE_TBL_BAD_TABLE_HANDLE is -1. See the block comment above.
  I16 CopyTableHandle;    // CFE_TBL_Handle_t, double-buffered load/dump        offset 48
  I16 RuntimeTableHandle; // CFE_TBL_Handle_t, single-buffered dump-only        offset 50
  U8 _pad1[4];            // C aligns the two pointers that follow

  HK_CopyTableEntry_t *CopyTablePtr;       // the ground's copy instructions    offset 56
  HK_RuntimeTableEntry_t *RuntimeTablePtr; // HK's bookkeeping for them         offset 64

  // 98.8% of the structure. Handed to CFE_ES_PoolCreate; never touched directly by HK.
  U8 MemPoolBuffer[HK_NUM_BYTES_IN_MEM_POOL]; //                                offset 72
};

// --- the global -----------------------------------------------------------------------------
//
// NASA declares this `extern` in hk_app.h and defines it in hk_app.c. The translation defines it
// HERE, in the vocabulary, for the reason every app in this port has: a HolyC `extern` outside
// the module-loader's window is a module-local dummy, so a global has exactly one definition and
// it lives with its type.
HK_AppData_t HK_AppData;

#endif
