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
// LIMIT CHECKER'S TABLE AND CDS MAINTENANCE -- the 1:1 translation of NASA's fsw/src/lc_utils.c,
// 202 lines and three functions. Small, and one half of LC's only call cycle.
//
// THE CYCLE IS TWO EDGES AND BOTH ARE REAL LOGIC: this file calls LC_ResetResultsWP and
// LC_ResetResultsAP in lc_cmds.c, and lc_cmds.c calls LC_PerformMaintenance here. So the two
// sources gate together, which is what module_deps.py reported before either was written.
//
// ### LC_ManageTables IS THE RELOAD PATH, AND THE ORDER IS THE WHOLE FUNCTION
//
// Dump-only tables (the two RESULTS tables) are managed WITHOUT releasing their address -- NASA's
// comment says so explicitly. The two LOADABLE tables (the definition tables) must have their
// addresses RELEASED first, because cFE cannot swap a buffer someone still holds.
//
// Then the addresses are re-acquired, and CFE_TBL_INFO_UPDATED is the signal that the ground
// loaded something: a new WDT clears every watchpoint result AND rebuilds the hash table (which
// re-subscribes), a new ADT clears every actionpoint result. A plain CFE_SUCCESS means nothing
// changed and neither happens.
//
// NOTE WHICH ERROR IS FATAL: a failure to get either address RETURNS, and
// LC_PerformMaintenance passes that up to its caller -- NASA's comment is "an error here is fatal
// - LC must be able to access its tables". A CDS failure, by contrast, only turns the CDS off.
#ifndef LC_UTILS_HC
#define LC_UTILS_HC

#include "lc_global.HC"
#include "lc_eventids.HC"
#include "lc_action.HC"
#include "lc_watch.HC"

// The other half of the cycle: both live in lc_cmds.HC, which is included AFTER this file.
U0 LC_ResetResultsAP(U32 StartIndex, U32 EndIndex, Bool ResetStatsCmd);
U0 LC_ResetResultsWP(U32 StartIndex, U32 EndIndex, Bool ResetStatsCmd);

/*******************************************************************************/
// Manage tables -- give cFE its chance to dump, reload and swap buffers.
I32 LC_ManageTables()
{
  I32 Result;

  /*
  ** It is not necessary to release dump only table pointers before
  **  calling cFE Table Services to manage the table
  */
  CFE_TBL_Manage(LC_OperData.WRTHandle);
  CFE_TBL_Manage(LC_OperData.ARTHandle);

  /*
  ** Must release loadable table pointers before allowing updates
  */
  CFE_TBL_ReleaseAddress(LC_OperData.WDTHandle);
  CFE_TBL_ReleaseAddress(LC_OperData.ADTHandle);

  CFE_TBL_Manage(LC_OperData.WDTHandle);
  CFE_TBL_Manage(LC_OperData.ADTHandle);

  /*
  ** Re-acquire the pointers and check for new table data
  */
  Result = CFE_TBL_GetAddress(&LC_OperData.WDTPtr, LC_OperData.WDTHandle);

  if (Result == CFE_TBL_INFO_UPDATED) {
    /*
    ** Clear watchpoint results for previous table
    */
    LC_ResetResultsWP(0, LC_MAX_WATCHPOINTS - 1, FALSE);

    /*
    ** Create watchpoint hash tables -- also subscribes to watchpoint packets
    */
    LC_CreateHashTable();
  } else if (Result != CFE_SUCCESS) {
    CFE_EVS_SendEvent(LC_WDT_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error getting WDT address, RC=0x%08X", Result);
    return Result;
  }

  Result = CFE_TBL_GetAddress(&LC_OperData.ADTPtr, LC_OperData.ADTHandle);

  if (Result == CFE_TBL_INFO_UPDATED) {
    /*
    ** Clear actionpoint results for previous table
    */
    LC_ResetResultsAP(0, LC_MAX_ACTIONPOINTS - 1, FALSE);
  } else if (Result != CFE_SUCCESS) {
    CFE_EVS_SendEvent(LC_ADT_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error getting ADT address, RC=0x%08X", Result);
    return Result;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Write all three CDS areas.
//
// THE "SAVED" FLAG IS SET **BEFORE** THE COPY THAT CARRIES IT, which is the only order that works:
// LC_AppData.CDSSavedOnExit is part of LC_AppData, so it has to hold LC_CDS_SAVED at the moment
// the structure is copied. The copy is therefore always stamped "this was a deliberate save" --
// and what makes the flag mean anything is lc_app.c writing LC_CDS_NOT_SAVED into the live
// structure after each save, so a CDS found saying SAVED can only have come from here.
//
// AND IT RETURNS ON THE FIRST FAILURE, so a WRT copy that fails leaves the ART and the AppData
// areas holding the PREVIOUS run's bytes while the live tables have moved on. The caller's answer
// to that is to switch the CDS off entirely rather than to retry.
I32 LC_UpdateTaskCDS()
{
  I32 Result;

  /*
  ** Copy the watchpoint results table (WRT) data to CDS
  */
  Result = CFE_ES_CopyToCDS(LC_OperData.WRTDataCDSHandle, LC_OperData.WRTPtr);

  if (Result != CFE_SUCCESS) {
    CFE_EVS_SendEvent(LC_WRT_NO_SAVE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Unable to update watchpoint results in CDS, RC=0x%08X", Result);
    return Result;
  }

  /*
  ** Copy the actionpoint results table (ART) data to CDS
  */
  Result = CFE_ES_CopyToCDS(LC_OperData.ARTDataCDSHandle, LC_OperData.ARTPtr);

  if (Result != CFE_SUCCESS) {
    CFE_EVS_SendEvent(LC_ART_NO_SAVE_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Unable to update actionpoint results in CDS, RC=0x%08X", Result);
    return Result;
  }

  /*
  ** Set the "data has been saved" indicator
  */
  LC_AppData.CDSSavedOnExit = LC_CDS_SAVED;

  /*
  ** Copy the global application data structure to CDS
  */
  Result = CFE_ES_CopyToCDS(LC_OperData.AppDataCDSHandle, &LC_AppData);

  if (Result != CFE_SUCCESS) {
    CFE_EVS_SendEvent(LC_APP_NO_SAVE_START_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Unable to update application data in CDS, RC=0x%08X", Result);
    return Result;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Background maintenance: manage the tables, then save the CDS if there is one.
//
// A TABLE ERROR PROPAGATES AND A CDS ERROR DOES NOT. LC_ManageTables' status is returned to the
// caller -- which is LC_SendHkCmd, whose return reaches the dispatcher -- while a failed
// LC_UpdateTaskCDS only clears HaveActiveCDS. NASA's comments state both: "an error here is fatal
// - LC must be able to access its tables" against "continue, but disable CDS if unable to update
// all 3".
//
// SO A CDS THAT FAILS ONCE IS OFF FOR THE REST OF THE RUN. There is no retry and no event beyond
// the one LC_UpdateTaskCDS already sent, and the housekeeping packet has no bit for it -- the only
// trace is that the three CDS areas stop changing.
I32 LC_PerformMaintenance()
{
  I32 Result;

  /*
  ** Manage tables - allow cFE to perform dump, update, etc.
  **  (an error here is fatal - LC must be able to access its tables)
  */
  Result = LC_ManageTables();

  if (Result == CFE_SUCCESS) {
    if (LC_OperData.HaveActiveCDS) {
      /*
      ** If CDS is enabled - update the 3 CDS areas managed by LC
      **  (continue, but disable CDS if unable to update all 3)
      */
      if (LC_UpdateTaskCDS() != CFE_SUCCESS) {
        LC_OperData.HaveActiveCDS = FALSE;
      }
    }
  }

  return Result;
}

#endif
