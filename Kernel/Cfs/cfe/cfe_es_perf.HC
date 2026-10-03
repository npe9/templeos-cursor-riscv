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
// 1:1 HolyC translation of cFE modules/es/fsw/src/cfe_es_perf.c -- THE PERFORMANCE LOG.
//
// Eleven functions, three of them NASA's own file-local helpers. The performance log is a
// 10,000-entry ring in the reset area that every cFE task writes into through
// CFE_ES_PerfLogAdd -- a pair of entry/exit markers around anything worth timing -- and reads
// out of through a BACKGROUND STATE MACHINE, because dumping 10,000 entries cannot be done in
// one pass without starving the rest of the system.
//
// WHY THE DUMP IS A STATE MACHINE, in NASA's words: "Writing performance log data is now
// handled by a state machine that runs as a background job in Executive services. When a
// performance log dump is pending, each iteration of the state machine performs a limited
// amount of work. Each iteration resumes work where the last iteration left off."
//
// AND IT PAYS FOR ITS WORK WITH CREDIT. CFE_ES_RunPerfLogDump earns WorkCredit in proportion to
// the time elapsed since it last ran and spends one per work item, capped so that "after a long
// idle time this would defeat the purpose". That is the cooperative-multitasking contract
// cfe_es_backgroundtask.c describes, implemented.
//
// THE MUTEX IS HELD ACROSS MOST OF THE DUMP, which NASA flags at CFE_ES_PerfLogAdd: "this lock
// is held for long periods while a background dump is taking place, but the dump should never
// be active at the same time that a capture/record is taking place." LOCK_DATA and UNLOCK_DATA
// are two of the eleven states, several states apart.
//
// THIS FILE INCLUDES NOTHING. docs/HOLYC_STRUCT_LIMITS.md #13.
//
// REQUIRED INCLUDE ORDER, which the driver provides:
//     cfe_es_global.HC   CFE_ES_Global, the perf dump state and the PerfDataMutex
//     cfe_es_resetdata.HC CFE_ES_PerfData_t, its metadata and its entries
//     cfe_es_msg.HC      the four perf command formats
//     cfe_es_api.HC      WriteToSysLog
//     cfe_es_erlog.HC    before cfe_es_task.HC, for the address-of reason recorded there
//     cfe_es_task.HC     CFE_ES_FileWriteByteCntErr and CFE_ES_TEST_U8_MASK
#ifndef CFE_ES_PERF_HC
#define CFE_ES_PERF_HC
// --- cfe_es_perf.h: the eleven dump states --------------------------------------------------
// NASA's comment on each is kept because the NAMES do not say what the state DOES: four of the
// eleven are placeholders that perform no action and exist so the numeric transition in
// CFE_ES_PerfLogDump_CompleteState has somewhere to land.
#define CFE_ES_PerfDumpState_IDLE                0 // Placeholder for idle, no action
#define CFE_ES_PerfDumpState_INIT                1 // Placeholder for entry/init, no action
#define CFE_ES_PerfDumpState_OPEN_FILE           2 // Opening of the output file
#define CFE_ES_PerfDumpState_DELAY               3 // Wait-state: let in-progress writes finish
#define CFE_ES_PerfDumpState_LOCK_DATA           4 // Locking of the global data structure
#define CFE_ES_PerfDumpState_WRITE_FS_HDR        5 // Write the CFE FS file header
#define CFE_ES_PerfDumpState_WRITE_PERF_METADATA 6 // Write the Perf global metadata
#define CFE_ES_PerfDumpState_WRITE_PERF_ENTRIES  7 // Write the Perf Log entries (throttled)
#define CFE_ES_PerfDumpState_CLEANUP             8 // Placeholder for cleanup, no action
#define CFE_ES_PerfDumpState_UNLOCK_DATA         9 // Unlocking of the global data structure
#define CFE_ES_PerfDumpState_CLOSE_FILE          10 // Closing of the output file
#define CFE_ES_PerfDumpState_MAX                 11 // Placeholder for last state, always last
// --- cfe_es_internal_cfg.h ------------------------------------------------------------------
#ifndef CFE_PLATFORM_ES_PERF_DATA_BUFFER_SIZE
#define CFE_PLATFORM_ES_PERF_DATA_BUFFER_SIZE 10000
#endif
#define CFE_PLATFORM_ES_PERF_FILTMASK_INIT      0xFFFFFFFF
#define CFE_PLATFORM_ES_PERF_TRIGMASK_INIT      0x0
#define CFE_PLATFORM_ES_PERF_ENTRIES_BTWN_DLYS  50
#define CFE_PLATFORM_ES_DEFAULT_PERF_DUMP_FILENAME "/ram/cfe_es_perf.dat"
#ifndef CFE_PLATFORM_ES_PERF_CHILD_MS_DELAY
#define CFE_PLATFORM_ES_PERF_CHILD_MS_DELAY 20
#endif
// --- cfe_es_perf.h / cfe_fs_extern_typedefs.h -----------------------------------------------
#define CFE_ES_PERF_LOG_DESC "ES Performance data file"
#ifndef CFE_FS_SubType_ES_PERFDATA
#define CFE_FS_SubType_ES_PERFDATA 4
#endif
// --- cfe_es_interface_cfg.h -----------------------------------------------------------------
// THE EXIT BIT IS THE TOP BIT of the 32-bit entry word: a marker is OR'd with EntryExit shifted
// up by 31, so one word carries both which point it was and which side of it.
#define CFE_MISSION_ES_PERF_EXIT_BIT 31
// --- default_cfe_es_extern_typedefs.h -------------------------------------------------------
#ifndef CFE_ES_PerfTrigger_START
#define CFE_ES_PerfTrigger_START  0
#define CFE_ES_PerfTrigger_CENTER 1
#define CFE_ES_PerfTrigger_END    2
#endif
// The capture STATE, which is not the dump state above: three values in the metadata that say
// whether the log is collecting, armed, or stopped. NASA spells them as an enum in
// cfe_es_perf.h; the names have no CFE_ES_PerfState_ prefix, which is why they read oddly
// beside the eleven CFE_ES_PerfDumpState_ ones.
#define CFE_ES_PERF_IDLE                0
#define CFE_ES_PERF_WAITING_FOR_TRIGGER 1
#define CFE_ES_PERF_TRIGGERED           2
// --- cfe_es_eventids.h: the eleven this file raises -----------------------------------------
#ifndef CFE_ES_PERF_STARTCMD_EID
#define CFE_ES_PERF_STARTCMD_EID          57
#define CFE_ES_PERF_STARTCMD_ERR_EID      58
#define CFE_ES_PERF_STARTCMD_TRIG_ERR_EID 59
#define CFE_ES_PERF_STOPCMD_EID           60
#define CFE_ES_PERF_STOPCMD_ERR2_EID      62
#define CFE_ES_PERF_FILTMSKCMD_EID        63
#define CFE_ES_PERF_FILTMSKERR_EID        64
#define CFE_ES_PERF_TRIGMSKCMD_EID        65
#define CFE_ES_PERF_TRIGMSKERR_EID        66
#define CFE_ES_PERF_LOG_ERR_EID           67
#define CFE_ES_PERF_DATAWRITTEN_EID       68
#endif
// --- what this file needs from elsewhere ----------------------------------------------------
// The PSP's timebase. These are the BOARD and will still be stubs when every line of cFE is
// translated: the whole point of the performance log is that the timestamps come from hardware.
U32 CFE_PSP_GetTimerTicksPerSecond();
U32 CFE_PSP_GetTimerLow32Rollover();
U0 CFE_PSP_Get_Timebase(U32 *Tbu, U32 *Tbl);
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// A PROCESSOR RESET LEAVES THE DATA ALONE, and that is the point of this function: the log is
// in the reset area, so after a processor reset the capture that led to the reset is still
// there. NASA's comment -- "On a processor reset, just IDLE the data collection so the ground
// can dump the data" -- is the whole design in one line. Only a POWER-ON reset reinitialises.
//
// THE ENDIAN FIELD IS DETECTED, NOT CONFIGURED. NASA writes a constant union of a uint16 0x0100
// and a uint8, and reads the byte: 1 on a big-endian machine, 0 on a little-endian one. HolyC
// has no file-scope union initialiser that would survive #19's company, and RISC-V here is
// little-endian, so the detection is written out as the same union in a LOCAL -- which is where
// NASA puts it too.
U0 CFE_ES_SetupPerfVariables(U32 ResetType)
{
  /* Create a constant union -
   * The "Endian" field will have "0x01" on a big endian processor
   * and will have value "0x00" on a little endian processor.
   */
  U16 EndianWord = 0x0100;
  U8 *EndianBytes = &EndianWord;
  U32 i;
  CFE_ES_PerfData_t *Perf;
  /*
  ** Set the pointer to the data area
  */
  Perf = &CFE_ES_Global.ResetDataPtr->Perf;
  if (ResetType == CFE_PSP_RST_TYPE_PROCESSOR) {
    /*
    ** On a processor reset, just IDLE the data
    ** collection so the ground can dump the data
    */
    Perf->MetaData.State = CFE_ES_PERF_IDLE;
  } else {
    Perf->MetaData.Version = 1;
    Perf->MetaData.Endian = EndianBytes[0];
    Perf->MetaData.TimerTicksPerSecond = CFE_PSP_GetTimerTicksPerSecond();
    Perf->MetaData.TimerLow32Rollover = CFE_PSP_GetTimerLow32Rollover();
    /* set data collection state to waiting for command state */
    Perf->MetaData.State = CFE_ES_PERF_IDLE;
    Perf->MetaData.Mode = CFE_ES_PerfTrigger_START;
    Perf->MetaData.TriggerCount = 0;
    Perf->MetaData.DataStart = 0;
    Perf->MetaData.DataEnd = 0;
    Perf->MetaData.DataCount = 0;
    Perf->MetaData.InvalidMarkerReported = FALSE;
    Perf->MetaData.FilterTriggerMaskSize = CFE_ES_PERF_8BIT_WORDS_IN_MASK;
    for (i = 0; i < CFE_ES_PERF_8BIT_WORDS_IN_MASK; i++) {
      Perf->MetaData.FilterMask[i] = CFE_PLATFORM_ES_PERF_FILTMASK_INIT;
      Perf->MetaData.TriggerMask[i] = CFE_PLATFORM_ES_PERF_TRIGMASK_INIT;
    }
  }
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// IT READS WITHOUT THE LOCK ON PURPOSE, and NASA justifies it: "note this reads the data 'live'
// without exclusion and as such it may change even between checking the state and checking the
// value. This shouldn't be a big deal, as the result should still be meaningful for a progress
// report, and the actual 32-bit counters should be atomic."
//
// AND THE ANSWER DEPENDS ON THE STATE, which is why it is a function at all rather than a field
// read: before the entry-writing state it reports the whole log, during it the blocks
// remaining, and after it zero. NASA's own note: "Foreground tasks/telemetry code shouldn't
// directly 'peek' into data structures which it does not own."
U32 CFE_ES_GetPerfLogDumpRemaining()
{
  CFE_ES_PerfDumpGlobal_t *PerfDumpState = &CFE_ES_Global.BackgroundPerfDumpState;
  U32 CurrentState = PerfDumpState->CurrentState;
  U32 Result;
  CFE_ES_PerfData_t *Perf;
  /*
  ** Set the pointer to the data area
  */
  Perf = &CFE_ES_Global.ResetDataPtr->Perf;
  /* note this reads the data "live" without exclusion and as such it
   * may change even between checking the state and checking the value.
   * This shouldn't be a big deal, as the result should still be meaningful
   * for a progress report, and the actual 32-bit counters should be atomic */
  if (CurrentState > CFE_ES_PerfDumpState_IDLE && CurrentState < CFE_ES_PerfDumpState_WRITE_PERF_ENTRIES) {
    /* dump is requested but not yet to entry writing state,
     * report the entire data count from perf log */
    Result = Perf->MetaData.DataCount;
  } else if (CurrentState == CFE_ES_PerfDumpState_WRITE_PERF_ENTRIES) {
    /* dump is in active writing state,
     * report the block counter (number remaining) */
    Result = PerfDumpState->StateCounter;
  } else {
    /* no dump active or dump is complete, report 0 */
    Result = 0;
  }
  return Result;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// BOTH STATE FIELDS ARE CHECKED, not just the current one, and NASA says why at the Stop
// command below: "also need to check the PendingState here, in case this command was sent twice
// in succession and the background task has not awakened yet". The pending state is the only
// record that a dump has been ASKED for but not yet begun.
//
// THE STATE IS SET LAST, and NASA marks the line: "this must be done last". Every other field
// is a counter the capture path reads only once State is non-IDLE, so writing State first
// would let a capture start against half-reset counters -- which is also why the whole block
// is inside the perf mutex, with its own reason given ("this might be changing states from one
// active mode to another").
I32 CFE_ES_StartPerfDataCmd(CFE_ES_StartPerfDataCmd_t *data)
{
  CFE_ES_StartPerfCmd_Payload_t *CmdPtr = &data->Payload;
  CFE_ES_PerfDumpGlobal_t *PerfDumpState = &CFE_ES_Global.BackgroundPerfDumpState;
  CFE_ES_PerfData_t *Perf;
  /*
  ** Set the pointer to the data area
  */
  Perf = &CFE_ES_Global.ResetDataPtr->Perf;
  /* Ensure there is no file write in progress before proceeding */
  if (PerfDumpState->CurrentState == CFE_ES_PerfDumpState_IDLE && PerfDumpState->PendingState == CFE_ES_PerfDumpState_IDLE) {
    /* Make sure Trigger Mode is valid */
    if (CmdPtr->TriggerMode <= CFE_ES_PerfTrigger_END) {
      CFE_ES_Global.TaskData.CommandCounter++;
      /* Taking lock here as this might be changing states from one active mode to another.
       * In that case, need to make sure that the log is not written to while resetting the
       *counters. */
      OS_MutSemTake(CFE_ES_Global.PerfDataMutex);
      Perf->MetaData.Mode = CmdPtr->TriggerMode;
      Perf->MetaData.TriggerCount = 0;
      Perf->MetaData.DataStart = 0;
      Perf->MetaData.DataEnd = 0;
      Perf->MetaData.DataCount = 0;
      Perf->MetaData.InvalidMarkerReported = FALSE;
      Perf->MetaData.State = CFE_ES_PERF_WAITING_FOR_TRIGGER;
      /* this must be done last */
      OS_MutSemGive(CFE_ES_Global.PerfDataMutex);
      CFE_EVS_SendEvent(CFE_ES_PERF_STARTCMD_EID, CFE_EVS_EventType_DEBUG, "Start collecting performance data cmd received, trigger mode = %d", CmdPtr->TriggerMode);
    } else {
      CFE_ES_Global.TaskData.CommandErrorCounter++;
      CFE_EVS_SendEvent(CFE_ES_PERF_STARTCMD_TRIG_ERR_EID, CFE_EVS_EventType_ERROR, "Cannot start collecting performance data, trigger mode (%d) out of range (%d to %d)", CmdPtr->TriggerMode, CFE_ES_PerfTrigger_START, CFE_ES_PerfTrigger_END);
    }
  } else {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_PERF_STARTCMD_ERR_EID, CFE_EVS_EventType_ERROR, "Cannot start collecting performance data,perf data write in progress");
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// STOPPING AND DUMPING ARE ONE COMMAND. It idles the capture, parses the filename, sets the
// PENDING state and wakes the background task -- and then returns. Everything that actually
// writes the file happens later, in CFE_ES_RunPerfLogDump.
//
// NOTE WHAT THE EVENT PROMISES: "will write %d entries.%dmS dly every %d entries". The ground
// is told the throttle up front, because the dump can take a long time and nothing else will
// report progress except the housekeeping packet's PerfDataToWrite.
I32 CFE_ES_StopPerfDataCmd(CFE_ES_StopPerfDataCmd_t *data)
{
  CFE_ES_StopPerfCmd_Payload_t *CmdPtr = &data->Payload;
  CFE_ES_PerfDumpGlobal_t *PerfDumpState = &CFE_ES_Global.BackgroundPerfDumpState;
  CFE_ES_PerfData_t *Perf;
  I32 Status;
  /*
  ** Set the pointer to the data area
  */
  Perf = &CFE_ES_Global.ResetDataPtr->Perf;
  /* Ensure there is no file write in progress before proceeding */
  /* note - also need to check the PendingState here, in case this command
   * was sent twice in succession and the background task has not awakened yet */
  if (PerfDumpState->CurrentState == CFE_ES_PerfDumpState_IDLE && PerfDumpState->PendingState == CFE_ES_PerfDumpState_IDLE) {
    Perf->MetaData.State = CFE_ES_PERF_IDLE;
    /* Copy out the string, using default if unspecified */
    Status = CFE_FS_ParseInputFileNameEx(PerfDumpState->DataFileName, CmdPtr->DataFileName, OS_MAX_PATH_LEN, CFE_MISSION_MAX_PATH_LEN, CFE_PLATFORM_ES_DEFAULT_PERF_DUMP_FILENAME, CFE_FS_GetDefaultMountPoint(CFE_FS_FileCategory_BINARY_DATA_DUMP), CFE_FS_GetDefaultExtension(CFE_FS_FileCategory_BINARY_DATA_DUMP));
    if (Status == CFE_SUCCESS) {
      PerfDumpState->PendingState = CFE_ES_PerfDumpState_INIT;
      CFE_ES_BackgroundWakeup();
      CFE_ES_Global.TaskData.CommandCounter++;
      CFE_EVS_SendEvent(CFE_ES_PERF_STOPCMD_EID, CFE_EVS_EventType_DEBUG, "Perf Stop Cmd Rcvd, will write %d entries.%dmS dly every %d entries", Perf->MetaData.DataCount, CFE_PLATFORM_ES_PERF_CHILD_MS_DELAY, CFE_PLATFORM_ES_PERF_ENTRIES_BTWN_DLYS);
    } else {
      CFE_ES_Global.TaskData.CommandErrorCounter++;
      CFE_EVS_SendEvent(CFE_ES_PERF_LOG_ERR_EID, CFE_EVS_EventType_ERROR, "Error parsing filename, RC = %d", Status);
    }
  }
  /* if data to write == 0 */
  else
  {
    CFE_ES_Global.TaskData.CommandErrorCounter++;
    CFE_EVS_SendEvent(CFE_ES_PERF_STOPCMD_ERR2_EID, CFE_EVS_EventType_ERROR, "Stop performance data cmd ignored,perf data write in progress");
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Local helper function
 * Handles transition to the pending performance log dump state
 *
 *-----------------------------------------------------------------*/
// THE STATE ENTRY ACTIONS, and three of them are not writes at all: LOCK_DATA takes the perf
// mutex, UNLOCK_DATA gives it, and DELAY zeroes the work credit -- which is how a state YIELDS.
// NASA's comment on DELAY is the one to keep: "Add a state entry delay before locking the
// 'Perf' structure to ensure that any foreground task that may have been writing to this
// structure has completed its access... This can be done by simply zeroing out the current
// credit, which will cause this loop to exit for now and resume after some time delay (does not
// really matter how much time)."
//
// A FILE THAT WOULD NOT OPEN IS NOT AN ERROR RETURN. FileDesc is set to UNDEFINED and the event
// goes out; CompleteState below is what notices and sends the machine back to IDLE.
U0 CFE_ES_PerfLogDump_EnterPendingState(CFE_ES_PerfDumpGlobal_t *State, CFE_ES_PerfData_t *Perf)
{
  I32 OsStatus;
  if (State->PendingState != State->CurrentState) {
    /*
     * Handle state change/entry logic.
     * Zero the block counter register (may be changed later).
     */
    State->StateCounter = 0;
    switch (State->PendingState) {
      case CFE_ES_PerfDumpState_OPEN_FILE :
      /* Create the file to dump to */
      OsStatus = OS_OpenCreate(&State->FileDesc, State->DataFileName, OS_FILE_FLAG_CREATE | OS_FILE_FLAG_TRUNCATE, OS_WRITE_ONLY);
      if (OsStatus != OS_SUCCESS) {
        State->FileDesc = OS_OBJECT_ID_UNDEFINED;
        CFE_EVS_SendEvent(CFE_ES_PERF_LOG_ERR_EID, CFE_EVS_EventType_ERROR, "Error creating file %s, RC = %ld", State->DataFileName, OsStatus);
      }
      State->FileSize = 0;
      break;
      case CFE_ES_PerfDumpState_DELAY :
      /*
         * Add a state entry delay before locking the "Perf" structure to
         * ensure that any foreground task that may have been writing to this
         * structure has completed its access.
         *
         * Note that the state should already have been set to IDLE, so
         * no new writes will start, this is just to yield the CPU such that
         * any already-started writes may finish.
         *
         * This can be done by simply zeroing out the current credit,
         * which will cause this loop to exit for now and resume after
         * some time delay (does not really matter how much time).
         */
      State->WorkCredit = 0;
      break;
      case CFE_ES_PerfDumpState_LOCK_DATA :
      OS_MutSemTake(CFE_ES_Global.PerfDataMutex);
      break;
      case CFE_ES_PerfDumpState_WRITE_FS_HDR :
      case CFE_ES_PerfDumpState_WRITE_PERF_METADATA :
      State->StateCounter = 1;
      break;
      case CFE_ES_PerfDumpState_WRITE_PERF_ENTRIES :
      State->DataPos = Perf->MetaData.DataStart;
      State->StateCounter = Perf->MetaData.DataCount;
      break;
      case CFE_ES_PerfDumpState_UNLOCK_DATA :
      OS_MutSemGive(CFE_ES_Global.PerfDataMutex);
      break;
      case CFE_ES_PerfDumpState_CLOSE_FILE :
      /* close the fd */
      if (OS_ObjectIdDefined(State->FileDesc)) {
        OS_close(State->FileDesc);
        State->FileDesc = OS_OBJECT_ID_UNDEFINED;
      }
      break;
      default:
      break;
    }
    State->CurrentState = State->PendingState;
  }
}
/*----------------------------------------------------------------
 *
 * Local helper function
 * Completes the current performance log dump state
 * This must be called when the current state's StateCounter is zero
 *
 *-----------------------------------------------------------------*/
// THE DEFAULT TRANSITION IS +1 AND THAT IS LOAD-BEARING, which is why the eleven states are
// numbered rather than named in a table: NASA's comment is "Default transition is to the next
// state by numeric value. This prevents endless looping in the same state. The switch statement
// can override this transition, however, based on any relevant error checks." So the four
// placeholder states are not dead -- they are the arithmetic.
U0 CFE_ES_PerfLogDump_CompleteState(CFE_ES_PerfDumpGlobal_t *State, CFE_ES_PerfData_t *Perf)
{
  /*
   * State is finished, do any final error checking and logging
   *
   * Default transition is to the next state by numeric value.
   * This prevents endless looping in the same state.
   *
   * The switch statement can override this transition, however,
   * based on any relevant error checks.
   */
  State->PendingState = 1 + State->CurrentState;
  if (State->PendingState >= CFE_ES_PerfDumpState_MAX) {
    State->PendingState = CFE_ES_PerfDumpState_IDLE;
  }
  switch (State->CurrentState) {
    case CFE_ES_PerfDumpState_OPEN_FILE :
    if (!OS_ObjectIdDefined(State->FileDesc)) {
      State->PendingState = CFE_ES_PerfDumpState_IDLE;
    }
    break;
    case CFE_ES_PerfDumpState_WRITE_PERF_ENTRIES :
    CFE_EVS_SendEvent(CFE_ES_PERF_DATAWRITTEN_EID, CFE_EVS_EventType_DEBUG, "%s written:Size=%lu,EntryCount=%lu", State->DataFileName, State->FileSize, Perf->MetaData.DataCount);
    break;
    default:
    break;
  }
}
/*----------------------------------------------------------------
 *
 * Local helper function
 * Writes one work item for the current performance log dump state
 * This must be called when the current state's StateCounter is nonzero
 *
 *-----------------------------------------------------------------*/
// ONE WORK ITEM IS ONE WRITE, which is what makes the throttle meaningful: the entry-writing
// state has StateCounter == DataCount, so ten thousand entries are ten thousand passes through
// here, fifty per wake-up.
//
// THE HEADER'S Length IS A PREDICTION, not a measurement: it is computed before anything is
// written, from the entry count at that moment -- which is safe only because the perf mutex is
// held from LOCK_DATA to UNLOCK_DATA and the capture path cannot run in between.
//
// A SHORT WRITE JUMPS TO CLEANUP, not to IDLE: the remaining states still have to run, because
// UNLOCK_DATA and CLOSE_FILE are among them. Going straight to IDLE would leave the perf mutex
// held forever and the file open.
U0 CFE_ES_PerfLogDump_WriteWorkItem(CFE_ES_PerfDumpGlobal_t *State, CFE_ES_PerfData_t *Perf)
{
  I32 OsStatus;
  I32 Status;
  CFE_FS_Header_t FileHdr;
  I64 BlockSize;
  Status = 0;
  BlockSize = 0;
  switch (State->CurrentState) {
    case CFE_ES_PerfDumpState_WRITE_FS_HDR :
    /* Zero cFE header, then fill in fields */
    CFE_FS_InitHeader(&FileHdr, CFE_ES_PERF_LOG_DESC, CFE_FS_SubType_ES_PERFDATA);
    /* predicted total length of final output */
    FileHdr.Length = sizeof(CFE_ES_PerfMetaData_t) + (Perf->MetaData.DataCount *sizeof(CFE_ES_PerfDataEntry_t));
    /* write the cFE header to the file */
    Status = CFE_FS_WriteHeader(State->FileDesc, &FileHdr);
    BlockSize = sizeof(CFE_FS_Header_t);
    break;
    case CFE_ES_PerfDumpState_WRITE_PERF_METADATA :
    /* write the performance metadata to the file */
    BlockSize = sizeof(CFE_ES_PerfMetaData_t);
    OsStatus = OS_write(State->FileDesc, &Perf->MetaData, BlockSize);
    Status = OsStatus;
    /* status type conversion (size) */
    break;
    case CFE_ES_PerfDumpState_WRITE_PERF_ENTRIES :
    BlockSize = sizeof(CFE_ES_PerfDataEntry_t);
    OsStatus = OS_write(State->FileDesc, &Perf->DataBuffer[State->DataPos], BlockSize);
    Status = OsStatus;
    /* status type conversion (size) */
    ++State->DataPos;
    if (State->DataPos >= CFE_PLATFORM_ES_PERF_DATA_BUFFER_SIZE) {
      State->DataPos = 0;
    }
    break;
    default:
    break;
  }
  if (BlockSize != 0) {
    if (Status != BlockSize) {
      CFE_ES_FileWriteByteCntErr(State->DataFileName, BlockSize, Status);
      State->PendingState = CFE_ES_PerfDumpState_CLEANUP;
    } else {
      State->FileSize += BlockSize;
    }
  }
  --State->StateCounter;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THE CREDIT IS WHAT MAKES THIS A BACKGROUND JOB. It is earned from the ELAPSED TIME the
// background task measured, converted into work items at the configured rate, and capped --
// NASA: "do not allow credit to accumulate indefinitely - after a long idle time this would
// defeat the purpose." Without the cap, a dump requested after an idle hour would run to
// completion in one pass and starve everything else.
//
// AND THE LOOP SPENDS CREDIT BEFORE DOING THE WORK, so an entry to the DELAY state -- which
// zeroes the credit -- ends the pass immediately however much was banked.
Bool CFE_ES_RunPerfLogDump(U32 ElapsedTime, U8 *Arg)
{
  CFE_ES_PerfDumpGlobal_t *State = Arg;
  CFE_ES_PerfData_t *Perf;
  /*
  ** Set the pointer to the data area
  */
  Perf = &CFE_ES_Global.ResetDataPtr->Perf;
  /*
   * each time this background job is re-entered after a time delay,
   * accumulate a work credit amount based on the elapsed time.
   *
   * This implements work-throttling as a form of cooperative
   * CPU sharing with other low priority background jobs.
   */
  State->WorkCredit += (ElapsedTime *CFE_PLATFORM_ES_PERF_ENTRIES_BTWN_DLYS) / CFE_PLATFORM_ES_PERF_CHILD_MS_DELAY;
  /*
   * do not allow credit to accumulate indefinitely -
   * after a long idle time this would defeat the purpose.
   */
  if (State->WorkCredit > CFE_PLATFORM_ES_PERF_ENTRIES_BTWN_DLYS) {
    State->WorkCredit = CFE_PLATFORM_ES_PERF_ENTRIES_BTWN_DLYS;
  }
  while (State->WorkCredit > 0) {
    --State->WorkCredit;
    CFE_ES_PerfLogDump_EnterPendingState(State, Perf);
    if (State->CurrentState == CFE_ES_PerfDumpState_IDLE) {
      break;
    }
    if (State->StateCounter == 0) {
      CFE_ES_PerfLogDump_CompleteState(State, Perf);
    } else {
      CFE_ES_PerfLogDump_WriteWorkItem(State, Perf);
    }
  }
  /*
   * Return "true" if activity is ongoing, or "false" if not active
   */
  return (State->CurrentState != CFE_ES_PerfDumpState_IDLE);
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// NO LOCK, AND NO DUMP-IN-PROGRESS CHECK. Either mask command will write into the metadata
// while a capture is running, which is the asymmetry the capture path relies on -- see the note
// on the filter test in CFE_ES_PerfLogAdd, which reads these masks outside the lock on the
// grounds that they "should NOT be changed while perf log is active".
I32 CFE_ES_SetPerfFilterMaskCmd(CFE_ES_SetPerfFilterMaskCmd_t *data)
{
  CFE_ES_SetPerfFilterMaskCmd_Payload_t *cmd = &data->Payload;
  CFE_ES_PerfData_t *Perf;
  /*
  ** Set the pointer to the data area
  */
  Perf = &CFE_ES_Global.ResetDataPtr->Perf;
  if (cmd->FilterMaskNum < CFE_ES_PERF_8BIT_WORDS_IN_MASK) {
    Perf->MetaData.FilterMask[cmd->FilterMaskNum] = cmd->FilterMask;
    CFE_EVS_SendEvent(CFE_ES_PERF_FILTMSKCMD_EID, CFE_EVS_EventType_DEBUG, "Set Performance Filter Mask Cmd rcvd, num %u, val 0x%02X", cmd->FilterMaskNum, cmd->FilterMask);
    CFE_ES_Global.TaskData.CommandCounter++;
  } else {
    CFE_EVS_SendEvent(CFE_ES_PERF_FILTMSKERR_EID, CFE_EVS_EventType_ERROR, "Performance Filter Mask Cmd Error, Index(%u) out of range, valid range is 0 to %u", cmd->FilterMaskNum, (CFE_ES_PERF_8BIT_WORDS_IN_MASK - 1));
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Application-scope internal function
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
I32 CFE_ES_SetPerfTriggerMaskCmd(CFE_ES_SetPerfTriggerMaskCmd_t *data)
{
  CFE_ES_SetPerfTrigMaskCmd_Payload_t *cmd = &data->Payload;
  CFE_ES_PerfData_t *Perf;
  /*
  ** Set the pointer to the data area
  */
  Perf = &CFE_ES_Global.ResetDataPtr->Perf;
  if (cmd->TriggerMaskNum < CFE_ES_PERF_8BIT_WORDS_IN_MASK) {
    Perf->MetaData.TriggerMask[cmd->TriggerMaskNum] = cmd->TriggerMask;
    CFE_EVS_SendEvent(CFE_ES_PERF_TRIGMSKCMD_EID, CFE_EVS_EventType_DEBUG, "Set Performance Trigger Mask Cmd rcvd, num %u, val 0x%02X", cmd->TriggerMaskNum, cmd->TriggerMask);
    CFE_ES_Global.TaskData.CommandCounter++;
  } else {
    CFE_EVS_SendEvent(CFE_ES_PERF_TRIGMSKERR_EID, CFE_EVS_EventType_ERROR, "Performance Trigger Mask Cmd Error, Index(%u) out of range, valid range is 0 to %u", cmd->TriggerMaskNum, (CFE_ES_PERF_8BIT_WORDS_IN_MASK - 1));
    CFE_ES_Global.TaskData.CommandErrorCounter++;
  }
  return CFE_SUCCESS;
}
/*----------------------------------------------------------------
 *
 * Local helper function
 * Updates the performance log trigger state after an entry is recorded
 * This must be called with the PerfDataMutex _held_, as it reads and
 * modifies the shared trigger state in the reset data area
 *
 *-----------------------------------------------------------------*/
// THE THREE TRIGGER MODES DECIDE WHERE THE BUFFER SITS RELATIVE TO THE TRIGGER. START stops
// after a full buffer, so the capture BEGINS at the trigger; END stops immediately, so the
// buffer holds what came BEFORE it; CENTER stops after half, so the trigger is in the middle.
// All three do it by the same means -- counting triggers and setting State to IDLE.
U0 CFE_ES_PerfUpdateTriggerState(CFE_ES_PerfData_t *Perf, U32 Marker)
{
  /* waiting for trigger */
  if (Perf->MetaData.State == CFE_ES_PERF_WAITING_FOR_TRIGGER) {
    if (CFE_ES_TEST_U8_MASK(Perf->MetaData.TriggerMask, Marker)) {
      Perf->MetaData.State = CFE_ES_PERF_TRIGGERED;
    }
  }
  /* triggered */
  if (Perf->MetaData.State == CFE_ES_PERF_TRIGGERED) {
    Perf->MetaData.TriggerCount++;
    if (Perf->MetaData.Mode == CFE_ES_PerfTrigger_START) {
      if (Perf->MetaData.TriggerCount >= CFE_PLATFORM_ES_PERF_DATA_BUFFER_SIZE) {
        Perf->MetaData.State = CFE_ES_PERF_IDLE;
      }
    } else if (Perf->MetaData.Mode == CFE_ES_PerfTrigger_CENTER) {
      if (Perf->MetaData.TriggerCount >= CFE_PLATFORM_ES_PERF_DATA_BUFFER_SIZE / 2) {
        Perf->MetaData.State = CFE_ES_PERF_IDLE;
      }
    } else if (Perf->MetaData.Mode == CFE_ES_PerfTrigger_END) {
      Perf->MetaData.State = CFE_ES_PERF_IDLE;
    }
  }
}
/*----------------------------------------------------------------
 *
 * Implemented per public API
 * See description in header file for argument/return detail
 *
 *-----------------------------------------------------------------*/
// THIS IS CALLED FROM EVERY TASK IN cFE, twice per instrumented region, so FOUR CHECKS HAPPEN
// BEFORE THE LOCK and each is there to avoid paying for it:
//   1. State == IDLE           -- "exit immediately without locking or doing anything"
//   2. Marker out of range     -- and the complaint is made ONCE, not per call
//   3. the filter mask         -- read outside the lock on the grounds that masks "should NOT
//                                 be changed while perf log is active", so this is effectively
//                                 constant and "avoids locking (and potential task switch) if
//                                 the data is ultimately not going to be written"
//   4. the TIMESTAMP is taken  -- "before locking, just in case the locking operation incurs a
//                                 delay", so the entry records when the event happened and not
//                                 when the lock was won
// and then State is checked AGAIN inside the lock, because it "could become idle while getting
// lock".
//
// THE INVALID-MARKER LATCH IS THE INTERESTING ONE. A bad marker in a hot loop would otherwise
// fill the syslog with the same line; InvalidMarkerReported makes it a single entry for the
// life of the capture -- at the cost of hiding a SECOND, different bad marker.
U0 CFE_ES_PerfLogAdd(U32 Marker, U32 EntryExit)
{
  CFE_ES_PerfDataEntry_t EntryData;
  U32 DataEnd;
  CFE_ES_PerfData_t *Perf;
  /*
  ** Set the pointer to the data area
  */
  Perf = &CFE_ES_Global.ResetDataPtr->Perf;
  /*
   * If the global state is idle, exit immediately without locking or doing anything
   */
  if (Perf->MetaData.State == CFE_ES_PERF_IDLE) {
    return;
  }
  /* if marker is out of range... */
  if (Marker >= CFE_MISSION_ES_PERF_MAX_IDS) {
    /* if marker has not been reported previously ... */
    if (Perf->MetaData.InvalidMarkerReported == FALSE) {
      CFE_ES_WriteToSysLog("%s: Invalid performance marker %d,max is %d\n", "CFE_ES_PerfLogAdd", Marker, (CFE_MISSION_ES_PERF_MAX_IDS - 1));
      Perf->MetaData.InvalidMarkerReported = TRUE;
    }
    return;
  }
  /*
   * check if this ID is filtered.
   * This is also done outside the lock -
   * normally masks should NOT be changed while perf log is active / non-idle,
   * so although this is reading a global it should be constant, and this avoids
   * locking (and potential task switch) if the data is ultimately not going to
   * be written to the log.
   */
  if (!CFE_ES_TEST_U8_MASK(Perf->MetaData.FilterMask, Marker)) {
    return;
  }
  /*
   * prepare the entry data (timestamp) before locking,
   * just in case the locking operation incurs a delay
   */
  EntryData.Data = (Marker | (EntryExit << CFE_MISSION_ES_PERF_EXIT_BIT));
  CFE_PSP_Get_Timebase(&EntryData.TimerUpper32, &EntryData.TimerLower32);
  /*
   * Acquire the perflog mutex before writing into the shared area.
   * Note this lock is held for long periods while a background dump
   * is taking place, but the dump should never be active at the
   * same time that a capture/record is taking place.
   */
  OS_MutSemTake(CFE_ES_Global.PerfDataMutex);
  /*
   * Confirm that the global is still non-idle after lock
   * (state could become idle while getting lock)
   */
  if (Perf->MetaData.State != CFE_ES_PERF_IDLE) {
    /* copy data to next perflog slot */
    DataEnd = Perf->MetaData.DataEnd;
    Perf->DataBuffer[DataEnd] = EntryData;
    ++DataEnd;
    if (DataEnd >= CFE_PLATFORM_ES_PERF_DATA_BUFFER_SIZE) {
      DataEnd = 0;
    }
    Perf->MetaData.DataEnd = DataEnd;
    /* we have filled up the buffer */
    if (Perf->MetaData.DataCount < CFE_PLATFORM_ES_PERF_DATA_BUFFER_SIZE) {
      Perf->MetaData.DataCount++;
    } else {
      /* after the buffer fills up start and end point to the same entry since we
         are now overwriting old data */
      Perf->MetaData.DataStart = Perf->MetaData.DataEnd;
    }
    /* update the trigger state */
    CFE_ES_PerfUpdateTriggerState(Perf, Marker);
  }
  OS_MutSemGive(CFE_ES_Global.PerfDataMutex);
}
#endif
