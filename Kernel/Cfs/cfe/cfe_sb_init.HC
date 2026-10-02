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
// 1:1 HolyC translation of cFE modules/sb/fsw/src/cfe_sb_init.c -- SB's EarlyInit.
//
// THREE FUNCTIONS, AND THE ORDER INSIDE THE FIRST ONE IS THE WHOLE FILE. CFE_SB_EarlyInit clears
// the global, then takes the shared-data mutex, then the buffer pool, then the pipe table, then
// the routing module, and only then initialises the statistics packet. Nothing after the mutex
// can be done without it, and the memset has to come first because every step below records its
// result in the structure it just cleared.
//
// NOTE WHAT IT DOES NOT DO: CFE_SB_EarlyInit does not create the command pipe or subscribe to
// anything. That is CFE_SB_TaskInit's job, and the split is the same one TIME has -- EarlyInit
// runs before the task exists, so it may only touch memory and OSAL primitives.
#ifndef CFE_SB_INIT_HC
#define CFE_SB_INIT_HC
#include "cfe_sb_global.HC" // the types, the constants and CFE_SB_Global
#include "cfe_sb_buf.HC"    // CFE_SB_TrackingListReset, for the two buffer lists
// --- default_cfe_sb_msgids.h ------------------------------------------------------------------
// The statistics telemetry message id. NASA spells it CFE_PLATFORM_SB_TLM_MIDVAL(STATS_TLM) and
// its comment says Default=0x080A; check_constants.py compares the number against that header.
#define CFE_SB_STATS_TLM_MID 0x080A
// --- cfe_es_api_typedefs.h --------------------------------------------------------------------
// CFE_ES_NO_MUTEX is `false`: SB's pool is used only from SB's own task and the buffers it hands
// out are reference-counted rather than shared mutably, so the pool does not take a semaphore on
// every allocation. NASA's own value, not a port decision.
#define CFE_ES_NO_MUTEX FALSE
// --- what this file needs from elsewhere ------------------------------------------------------
// ES's memory pool and OSAL's mutex. None of ES is translated; the differential oracle supplies
// both sides with the same recording stubs.
I32 CFE_ES_PoolCreateEx(U32 *PoolID, U8 *MemPtr, I64 Size, U32 NumBlockSizes, U8 *BlockSizes, Bool UseMutex);
I32 CFE_ES_WriteToSysLog(U8 *Spec,...);
I32 OS_MutSemCreate(U32 *sem_id, U8 *sem_name, U32 options);
U8 *MemSet(U8 *dst, I64 dat, I64 size);
// Defined below and called from above it.
I32 CFE_SB_InitBuffers();
U0 CFE_SB_InitPipeTbl();
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_EarlyInit()
{
  I32 OsStatus;
  I32 Stat;
  /* Clear task global */
  MemSet(&CFE_SB_Global, 0, sizeof(CFE_SB_Global));
  OsStatus = OS_MutSemCreate(&CFE_SB_Global.SharedDataMutexId, "CFE_SB_DataMutex", 0);
  if (OsStatus != OS_SUCCESS) {
    // NASA passes __func__. HolyC has no __func__, so the name is spelled out -- the deviation
    // cfe_evs_task.HC and cfe_time_task.HC both record, and the syslog text is the same either
    // way.
    CFE_ES_WriteToSysLog("CFE_SB_EarlyInit: Shared data mutex creation failed! RC=%d\n", OsStatus);
    return CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
  }
  /* Initialize the state of subscription reporting */
  CFE_SB_Global.SubscriptionReporting = CFE_SB_DISABLE;
  /* Initialize memory partition. */
  Stat = CFE_SB_InitBuffers();
  if (Stat != CFE_SUCCESS) {
    /* error reported in CFE_SB_InitBuffers */
    return Stat;
  }
  /* Initialize the pipe table. */
  CFE_SB_InitPipeTbl();
  /* Initialize the routing module */
  CFE_SBR_Init();
  /* Initialize the SB Statistics Pkt */
  CFE_MSG_Init(&CFE_SB_Global.StatTlmMsg.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CFE_SB_STATS_TLM_MID), sizeof(CFE_SB_Global.StatTlmMsg));
  return Stat;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_SB_InitBuffers()
{
  I32 Stat = 0;
  CFE_Config_ArrayValue MemPoolDefSize;
  // THE BLOCK SIZES COME FROM THE CONFIG SERVICE, not from a constant: the same array
  // cfe_platformcfg_tables.HC publishes, which is why that table's seventeen entries are chosen
  // around CFE_SB_BUFFERD_CONTENT_OFFSET. NASA's comment on the buffer descriptor says so.
  // NASA writes `MemPoolDefSize = CFE_Config_GetArrayValue(...)`. This port's version takes an
  // OUT-PARAMETER, which is the one deviation cfe_config.HC records in full: the C returns a
  // 16-byte class by value and this compiler has no struct-return ABI, so it REFUSES the return
  // rather than truncating it. When that ABI lands, both sites revert to the C's shape.
  CFE_Config_GetArrayValue(CFE_CONFIGID_PLATFORM_SB_MEM_BLOCK_SIZE, &MemPoolDefSize);
  Stat = CFE_ES_PoolCreateEx(&CFE_SB_Global.Mem.PoolHdl, CFE_SB_Global.Mem.Partition.Data, CFE_PLATFORM_SB_BUF_MEMORY_BYTES, MemPoolDefSize.NumElements, MemPoolDefSize.ElementPtr, CFE_ES_NO_MUTEX);
  if (Stat != CFE_SUCCESS) {
    CFE_ES_WriteToSysLog("CFE_SB_InitBuffers: PoolCreate failed for SB Buffers, gave adr 0x%X,size %d,stat=0x%X\n", CFE_SB_Global.Mem.Partition.Data, CFE_PLATFORM_SB_BUF_MEMORY_BYTES, Stat);
    return Stat;
  }
  /*
   * Initialize the buffer tracking lists to be empty
   */
  // An empty list is a node pointing at ITSELF, which is what removes every null check from the
  // three list operations in cfe_sb_buf.HC. These two calls are what establish that.
  CFE_SB_TrackingListReset(&CFE_SB_Global.InTransitList);
  CFE_SB_TrackingListReset(&CFE_SB_Global.ZeroCopyList);
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
U0 CFE_SB_InitPipeTbl()
{
  // The whole body. Pipe ids are handed out from a resource-id space rather than being table
  // indices, so the only state the empty table needs is where the next id starts.
  CFE_SB_Global.LastPipeId = CFE_ResourceId_FromInteger(CFE_SB_PIPEID_BASE);
}
#endif
