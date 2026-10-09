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
// HEALTH & SAFETY'S MONITORS -- the 1:1 translation of NASA's fsw/src/hs_monitors.c, 907 lines
// and eight functions. The three monitors, the four table validators, and the one function that
// writes the critical data store.
//
// ### THE THREE MONITORS ANSWER THREE DIFFERENT QUESTIONS
//
//   HS_MonitorApplications  "is each app still counting?"   -- an execution counter per app
//   HS_MonitorEvent         "did app X emit event N?"       -- the whole system's event stream
//   HS_MonitorUtilization   "is the CPU pegged?"            -- the simulated analog channel
//
// and all three can end in the SAME four actions, selected by an ActionType that is both an
// enumeration and an index -- see hs_tbl.HC. So the interesting code is not the detection, it is
// what happens after.
//
// ### THE ACTION SWITCH IS THE SAME SHAPE THREE TIMES AND DIFFERS IN ONE ARM
//
// PROC_RESET and APP_RESTART are identical in both monitors. The third arm is NOT:
//
//   AMT  HS_AMTActType_EVENT       send an event and stop
//   EMT  HS_EMTActType_APP_DELETE  delete the application
//
// **Same numeric value, 3, and one of them is destructive.** A translation that factored the two
// switches into one function would have to pick, and picking either is a behaviour change. They
// are separate here because they are separate upstream.
//
// ### A PROCESSOR RESET IS REFUSED PAST A LIMIT HELD IN THE CDS
//
// Both monitors' PROC_RESET arm reads
//
//     if (HS_AppData.CDSData.ResetsPerformed < HS_AppData.CDSData.MaxResets)
//
// and on the way to the reset it writes the incremented count THROUGH HS_SetCDSData, which also
// stores the bitwise complement -- so the count survives the reset it is about to cause and
// cannot be half-written without being detected. Then OS_TaskDelay(HS_RESET_TASK_DELAY),
// a syslog line, **ServiceWatchdogFlag = HS_State_DISABLED**, and CFE_ES_ResetCFE.
//
// THE WATCHDOG IS TURNED OFF BEFORE THE RESET ON PURPOSE. HS's main loop pets the dog every
// cycle; a reset that left the flag enabled would race the reset against the watchdog and the
// board could come up from the wrong one. Clearing the flag makes the software reset the only
// one that can happen. That single assignment is the most safety-critical line in the app.
//
// ### AND A FAILED LOOKUP STILL COUNTS DOWN -- NASA'S COMMENT IS NARROWER THAN ITS CODE
//
// HS_MonitorApplications has
//
//     /* Failure to get an execution counter is not considered an automatic failure (or eventworthy) */
//     if ((Status == CFE_SUCCESS) && (LastExeCount != AppInfo.ExecutionCounter)) { ...reset the countdown... }
//     else { HS_AppData.AppMonCheckInCountdown[TableIndex]--; ... }
//
// The comment is about EVENTS and it is true: no event is sent for a failed counter read. But the
// `else` DECREMENTS, so an app whose name cannot be resolved counts down to its action exactly as
// one that stopped running does -- and after CycleCount cycles it is reset, restarted or deleted.
// "Not an automatic failure" means "not immediately"; it does not mean "not eventually". The
// exercise drives both and the countdown is printed, because the two paths are indistinguishable
// from the action they reach.
#ifndef HS_MONITORS_HC
#define HS_MONITORS_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// hs_cfg.HC, hs_msg.HC, hs_tbl.HC, hs_global.HC, hs_eventids.HC, hs_utils.HC, hs_sysmon.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13.

// --- hs_monitors.h's prototypes ---------------------------------------------------------------
U0 HS_MonitorApplications();
U0 HS_MonitorEvent(CFE_EVS_LongEventTlm_t *EventPtr);
U0 HS_MonitorUtilization();
I32 HS_ValidateAMTable(U8 *TableData);
I32 HS_ValidateEMTable(U8 *TableData);
I32 HS_ValidateXCTable(U8 *TableData);
I32 HS_ValidateMATable(U8 *TableData);
U0 HS_SetCDSData(U16 ResetsPerformed, U16 MaxResets);

/*******************************************************************************/
// Monitor the applications: has each one's execution counter moved?
//
// THE ENABLE BIT IS CLEARED WITH `~(1 << (TableIndex % 32))` AND TableIndex CAN BE 31. In C,
// `1` is an `int`, so `1 << 31` sets the sign bit of a signed 32-bit value -- which is
// implementation-defined and in C99 undefined. It works on every compiler cFS targets, and
// HS_MAX_MONITORED_APPS being exactly 32 is what makes 31 reachable. Kept as NASA writes it; the
// exercise drives monitor 31 so the bit that gets cleared is observable rather than assumed.
U0 HS_MonitorApplications()
{
  CFE_ES_AppInfo_t AppInfo;
  U32 AppId;
  I32 Status;
  U32 TableIndex = 0;
  U16 ActionType;
  U32 MsgActsIndex = 0;

  AppId = CFE_ES_APPID_UNDEFINED;

  /* Avoid accessing AMT if table pointer is invalid */
  if (HS_AppData.AMTablePtr == NULL) {
    return;
  }

  MemSet(&AppInfo, 0, sizeof(CFE_ES_AppInfo_t));

  for (TableIndex = 0; TableIndex < HS_MAX_MONITORED_APPS; TableIndex++) {
    ActionType = HS_AppData.AMTablePtr[TableIndex].ActionType;

    /*
    ** Check this App if it has an action, and hasn't already expired
    */
    if (ActionType != HS_AMTActType_NOACT && HS_AppData.AppMonCheckInCountdown[TableIndex] != 0) {
      Status = CFE_ES_GetAppIDByName(&AppId, HS_AppData.AMTablePtr[TableIndex].AppName);

      if (Status == CFE_SUCCESS) {
        Status = CFE_ES_GetAppInfo(&AppInfo, AppId);
      } else if (HS_AppData.AppMonCheckInCountdown[TableIndex] ==
                 HS_AppData.AMTablePtr[TableIndex].CycleCount) {
        /*
        ** Only send an error event the first time the App fails to resolve
        */
        CFE_EVS_SendEvent(HS_APPMON_APPNAME_ERR_EID, CFE_EVS_EventType_ERROR,
                          "App Monitor App Name not found: APP:(%s)",
                          HS_AppData.AMTablePtr[TableIndex].AppName);
      } else {
        /* For repeated errors, send a debug event */
        CFE_EVS_SendEvent(HS_APPMON_APPNAME_DBG_EID, CFE_EVS_EventType_DEBUG,
                          "App Monitor App Name not found: APP:(%s)",
                          HS_AppData.AMTablePtr[TableIndex].AppName);
      }

      /*
      ** Failure to get an execution counter is not considered an automatic failure (or eventworthy)
      */
      // -- BUT THE `else` STILL DECREMENTS. See the file header: an app that cannot be resolved
      // reaches its action just as one that stopped counting does.
      if (Status == CFE_SUCCESS &&
          HS_AppData.AppMonLastExeCount[TableIndex] != AppInfo.ExecutionCounter) {
        /*
        ** Set the current count, and reset the timeout
        */
        HS_AppData.AppMonCheckInCountdown[TableIndex] = HS_AppData.AMTablePtr[TableIndex].CycleCount;
        HS_AppData.AppMonLastExeCount[TableIndex] = AppInfo.ExecutionCounter;
      } else {
        HS_AppData.AppMonCheckInCountdown[TableIndex]--;

        /*
        ** Take Action once the counter reaches zero
        */
        if (HS_AppData.AppMonCheckInCountdown[TableIndex] == 0) {
          /*
          ** Unset the enabled bit flag
          */
          // THE PARENTHESES AROUND THE `%` ARE LOAD-BEARING IN HolyC -- see the long note at
          // the matching line in hs_cmds.HC's HS_AppMonStatusRefresh. `<<` is the tightest
          // binary level here and the loosest-but-one in C, so dropping NASA's parentheses
          // silently turns `1 << (i % 32)` into `(1 << i) % 32`.
          HS_AppData.AppMonEnables[TableIndex / HS_BITS_PER_APPMON_ENABLE] &=
              ~(1 << (TableIndex % HS_BITS_PER_APPMON_ENABLE));
          switch (ActionType) {
            case HS_AMTActType_PROC_RESET:
              CFE_EVS_SendEvent(HS_APPMON_PROC_ERR_EID, CFE_EVS_EventType_ERROR,
                                "App Monitor Failure: APP:(%s): Action: Processor Reset",
                                HS_AppData.AMTablePtr[TableIndex].AppName);

              /*
              ** Perform a reset if we can
              */
              if (HS_AppData.CDSData.ResetsPerformed < HS_AppData.CDSData.MaxResets) {
                HS_SetCDSData(HS_AppData.CDSData.ResetsPerformed + 1, HS_AppData.CDSData.MaxResets);

                OS_TaskDelay(HS_RESET_TASK_DELAY);
                CFE_ES_WriteToSysLog("HS App: App Monitor Failure: APP:(%s): Action: Processor Reset\n",
                                     HS_AppData.AMTablePtr[TableIndex].AppName);
                // THE MOST SAFETY-CRITICAL LINE IN HS -- see the file header.
                HS_AppData.ServiceWatchdogFlag = HS_State_DISABLED;
                CFE_ES_ResetCFE(CFE_PSP_RST_TYPE_PROCESSOR);
              } else {
                CFE_EVS_SendEvent(HS_RESET_LIMIT_ERR_EID, CFE_EVS_EventType_ERROR,
                                  "Processor Reset Action Limit Reached: No Reset Performed");
              }

              break;

            case HS_AMTActType_APP_RESTART:
              CFE_EVS_SendEvent(HS_APPMON_RESTART_ERR_EID, CFE_EVS_EventType_ERROR,
                                "App Monitor Failure: APP:(%s) Action: Restart Application",
                                HS_AppData.AMTablePtr[TableIndex].AppName);
              /*
              ** Attempt to restart the App if we resolved the AppId
              */
              if (Status == CFE_SUCCESS) {
                Status = CFE_ES_RestartApp(AppId);
              }

              /*
              ** Report an error; either no valid AppId, or RestartApp failed
              */
              if (Status != CFE_SUCCESS) {
                CFE_EVS_SendEvent(HS_APPMON_NOT_RESTARTED_ERR_EID, CFE_EVS_EventType_ERROR,
                                  "Call to Restart App Failed: APP:(%s) ERR: 0x%08X",
                                  HS_AppData.AMTablePtr[TableIndex].AppName, Status);
              }

              break;

            case HS_AMTActType_EVENT:
              // THE AMT'S THIRD ACTION. The EMT's action 3 at this numeric value DELETES the
              // application instead -- see the file header.
              CFE_EVS_SendEvent(HS_APPMON_FAIL_ERR_EID, CFE_EVS_EventType_ERROR,
                                "App Monitor Failure: APP:(%s): Action: Event Only",
                                HS_AppData.AMTablePtr[TableIndex].AppName);
              break;

            /*
            ** Message Action types processing (invalid will be skipped)
            */
            default:

              /* Calculate the requested message action index */
              MsgActsIndex = ActionType - HS_AMTActType_LAST_NONMSG - 1;

              /*
              ** Check to see if this is a valid Message Action Type
              */
              if (HS_AppData.MsgActsState == HS_State_ENABLED &&
                  MsgActsIndex < HS_MAX_MSG_ACT_TYPES) {
                /*
                ** Send the message if off cooldown and not disabled
                */
                if (HS_AppData.MsgActCooldown[MsgActsIndex] == 0 &&
                    HS_AppData.MATablePtr[MsgActsIndex].EnableState != HS_MATState_DISABLED) {
                  // TRANSMITTED VERBATIM FROM A 16-BYTE BUFFER WHOSE HEADER THE GROUND WROTE.
                  // docs/CFS_UPSTREAM_NOTES.md #23: HS_ValidateMATable bounds the length against
                  // CFE_MISSION_SB_MAX_SB_MSG_SIZE (32768) rather than HS_MAX_MSG_ACT_SIZE (16),
                  // so an entry claiming more than 16 bytes passes validation and this call reads
                  // past the entry. Kept; the exercise drives the validation and not this read.
                  CFE_SB_TransmitMsg(&HS_AppData.MATablePtr[MsgActsIndex].MsgBuf, TRUE);
                  HS_AppData.MsgActExec++;
                  HS_AppData.MsgActCooldown[MsgActsIndex] =
                      HS_AppData.MATablePtr[MsgActsIndex].Cooldown;
                  if (HS_AppData.MATablePtr[MsgActsIndex].EnableState != HS_MATState_NOEVENT) {
                    CFE_EVS_SendEvent(HS_APPMON_MSGACTS_ERR_EID, CFE_EVS_EventType_ERROR,
                                      "App Monitor Failure: APP:(%s): Action: Message Action Index: %d",
                                      HS_AppData.AMTablePtr[TableIndex].AppName, MsgActsIndex);
                  }
                }
              }

              /* Otherwise, Take No Action */
              break;
          } /* end switch */

        } /* end (HS_AppData.AppMonCheckInCountdown[TableIndex] == 0) if */

      } /* end "failed to update counter" else */

    } /* end (HS_AppData.AppMonCheckInCountdown[TableIndex] != 0) if */

  } /* end for loop */
}

/*******************************************************************************/
// Monitor the event stream: did a monitored application emit a monitored event?
//
// THE APP NAME IS COMPARED WITH strncmp OVER OS_MAX_API_NAME, AND THE EVENT ID FIRST. The outer
// test is on the numeric EventID and only a match gets as far as the string compare -- so the
// common case for every event the system emits is one integer comparison per EMT entry, sixteen
// of them. HS is on the event pipe for the WHOLE SYSTEM, so that ordering is the difference
// between a cheap monitor and one that strncmps sixteen names per event.
//
// AND ITS THIRD ACTION DELETES AN APPLICATION where the app monitor's sends an event. Same
// numeric value. See the file header.
U0 HS_MonitorEvent(CFE_EVS_LongEventTlm_t *EventPtr)
{
  U32 TableIndex = 0;
  I32 Status = CFE_SUCCESS;
  U32 AppId;
  U16 ActionType;
  U32 MsgActsIndex = 0;
  CFE_SB_Buffer *SendPtr = NULL;

  AppId = CFE_ES_APPID_UNDEFINED;

  /* Avoid accessing EMT if table pointer is invalid */
  if (HS_AppData.EMTablePtr == NULL) {
    return;
  }

  for (TableIndex = 0; TableIndex < HS_MAX_MONITORED_EVENTS; TableIndex++) {
    ActionType = HS_AppData.EMTablePtr[TableIndex].ActionType;

    /*
    ** Check this Event Monitor if it has an action, and the event IDs match
    */
    if (ActionType != HS_EMTActType_NOACT &&
        HS_AppData.EMTablePtr[TableIndex].EventID == EventPtr->Payload.PacketID.EventID) {
      if (!StrNCmp(HS_AppData.EMTablePtr[TableIndex].AppName,
                   EventPtr->Payload.PacketID.AppName, OS_MAX_API_NAME)) {
        /*
        ** Perform the action if the strings also match
        */
        switch (ActionType) {
          case HS_EMTActType_PROC_RESET:
            CFE_EVS_SendEvent(HS_EVENTMON_PROC_ERR_EID, CFE_EVS_EventType_ERROR,
                              "Event Monitor: APP:(%s) EID:(%d): Action: Processor Reset",
                              HS_AppData.EMTablePtr[TableIndex].AppName,
                              HS_AppData.EMTablePtr[TableIndex].EventID);

            /*
            ** Perform a reset if we can
            */
            if (HS_AppData.CDSData.ResetsPerformed < HS_AppData.CDSData.MaxResets) {
              HS_SetCDSData(HS_AppData.CDSData.ResetsPerformed + 1, HS_AppData.CDSData.MaxResets);

              OS_TaskDelay(HS_RESET_TASK_DELAY);
              CFE_ES_WriteToSysLog("HS App: Event Monitor: APP:(%s) EID:(%d): Action: Processor Reset\n",
                                   HS_AppData.EMTablePtr[TableIndex].AppName,
                                   HS_AppData.EMTablePtr[TableIndex].EventID);
              HS_AppData.ServiceWatchdogFlag = HS_State_DISABLED;
              CFE_ES_ResetCFE(CFE_PSP_RST_TYPE_PROCESSOR);
            } else {
              CFE_EVS_SendEvent(HS_RESET_LIMIT_ERR_EID, CFE_EVS_EventType_ERROR,
                                "Processor Reset Action Limit Reached: No Reset Performed");
            }

            break;

          case HS_EMTActType_APP_RESTART:
            /*
            ** Check to see if the App is still there, and try to restart if it is
            */
            // NOTE THE ORDER: the event is sent only if the app RESOLVED, unlike the app
            // monitor's restart arm which announces first and resolves after. So an event monitor
            // firing on a vanished app produces ONLY the "Call to Restart App Failed" event,
            // with no preceding "Action: Restart Application" line.
            Status = CFE_ES_GetAppIDByName(&AppId, HS_AppData.EMTablePtr[TableIndex].AppName);
            if (Status == CFE_SUCCESS) {
              CFE_EVS_SendEvent(HS_EVENTMON_RESTART_ERR_EID, CFE_EVS_EventType_ERROR,
                                "Event Monitor: APP:(%s) EID:(%d): Action: Restart Application",
                                HS_AppData.EMTablePtr[TableIndex].AppName,
                                HS_AppData.EMTablePtr[TableIndex].EventID);
              Status = CFE_ES_RestartApp(AppId);
            }

            if (Status != CFE_SUCCESS) {
              CFE_EVS_SendEvent(HS_EVENTMON_NOT_RESTARTED_ERR_EID, CFE_EVS_EventType_ERROR,
                                "Call to Restart App Failed: APP:(%s) ERR: 0x%08X",
                                HS_AppData.EMTablePtr[TableIndex].AppName, Status);
            }

            break;

          case HS_EMTActType_APP_DELETE:
            /*
            ** Check to see if the App is still there, and try to delete if it is
            */
            Status = CFE_ES_GetAppIDByName(&AppId, HS_AppData.EMTablePtr[TableIndex].AppName);
            if (Status == CFE_SUCCESS) {
              CFE_EVS_SendEvent(HS_EVENTMON_DELETE_ERR_EID, CFE_EVS_EventType_ERROR,
                                "Event Monitor: APP:(%s) EID:(%d): Action: Delete Application",
                                HS_AppData.EMTablePtr[TableIndex].AppName,
                                HS_AppData.EMTablePtr[TableIndex].EventID);
              Status = CFE_ES_DeleteApp(AppId);
            }

            if (Status != CFE_SUCCESS) {
              CFE_EVS_SendEvent(HS_EVENTMON_NOT_DELETED_ERR_EID, CFE_EVS_EventType_ERROR,
                                "Call to Delete App Failed: APP:(%s) ERR: 0x%08X",
                                HS_AppData.EMTablePtr[TableIndex].AppName, Status);
            }

            break;

          /*
          ** Message Action types processing (invalid will be skipped)
          */
          default:

            /* Calculate the requested message action index */
            MsgActsIndex = ActionType - HS_EMTActType_LAST_NONMSG - 1;

            /*
            ** Check to see if this is a valid Message Action Type
            */
            if (HS_AppData.MsgActsState == HS_State_ENABLED &&
                MsgActsIndex < HS_MAX_MSG_ACT_TYPES) {
              /*
              ** Send the message if off cooldown and not disabled
              */
              if (HS_AppData.MsgActCooldown[MsgActsIndex] == 0 &&
                  HS_AppData.MATablePtr[MsgActsIndex].EnableState != HS_MATState_DISABLED) {
                // THROUGH A SendPtr HERE, where the app monitor casts inline -- same effect, and
                // both are kept as NASA writes them. See note #23 on what the length can be.
                SendPtr = &HS_AppData.MATablePtr[MsgActsIndex].MsgBuf;
                CFE_SB_TransmitMsg(&SendPtr->Msg, TRUE);

                HS_AppData.MsgActExec++;
                HS_AppData.MsgActCooldown[MsgActsIndex] = HS_AppData.MATablePtr[MsgActsIndex].Cooldown;
                if (HS_AppData.MATablePtr[MsgActsIndex].EnableState != HS_MATState_NOEVENT) {
                  CFE_EVS_SendEvent(HS_EVENTMON_MSGACTS_ERR_EID, CFE_EVS_EventType_ERROR,
                                    "Event Monitor: APP:(%s) EID:(%d): Action: Message Action Index: %d",
                                    HS_AppData.EMTablePtr[TableIndex].AppName,
                                    HS_AppData.EMTablePtr[TableIndex].EventID, MsgActsIndex);
                }
              }
            }

            /* Otherwise, Take No Action */
            break;
        } /* end switch */

      } /* end AppName comparison */

    } /* end EventID comparison */

  } /* end for loop */
}

/*******************************************************************************/
// Monitor CPU utilisation and hogging.
//
// ### THE TRACKER IS A 64-SLOT RING AND THE AVERAGE IS A 4-SLOT WINDOW OVER IT
//
// HS_AppData.UtilizationTracker holds HS_UTIL_PEAK_NUM_INTERVAL (64) samples and the index wraps.
// The PEAK is the maximum over all 64; the AVERAGE is over the last HS_UTIL_AVERAGE_NUM_INTERVAL
// (4), which means a window that can straddle the wrap -- and that is why the loop has two
// branches instead of one subtraction:
//
//     if (ThisUtilIndex >= 4)   the window is (ThisUtilIndex-4, ThisUtilIndex]      -- contiguous
//     else                      it is [0, ThisUtilIndex] PLUS (64-(4-ThisUtilIndex), 64)  -- split
//
// Both are written as conditions on UtilIndex inside a walk of all 64 slots, so the function is
// O(64) either way and the wrap costs nothing. The exercise drives ThisUtilIndex at 0, 1, 3, 4
// and 63 because those are the boundaries: 3 is the last split window, 4 the first contiguous
// one, and 63 the last slot before the wrap.
//
// ### THE INDEX IS INCREMENTED **BEFORE** THE SAMPLE IS STORED, AND THE OLD VALUE IS USED
//
//     ThisUtilIndex = HS_AppData.CurrentCPUUtilIndex;    /* saved first */
//     HS_AppData.CurrentCPUUtilIndex++;
//     if (HS_AppData.CurrentCPUUtilIndex >= 64) { HS_AppData.CurrentCPUUtilIndex = 0; }
//     ...
//     HS_AppData.UtilizationTracker[ThisUtilIndex] = CurrentUtil;
//
// So the slot written is the PRE-increment one and CurrentCPUUtilIndex always points at the slot
// that will be written NEXT. A translation that incremented after would write the wrong slot and
// the average window -- computed from ThisUtilIndex -- would be off by one for every sample.
//
// ### THE AVERAGE ALWAYS DIVIDES BY FOUR, EVEN BEFORE FOUR SAMPLES EXIST
//
// `UtilCpuAvg = CombinedUtil / HS_UTIL_AVERAGE_NUM_INTERVAL` with no count of how many slots were
// actually summed. The tracker starts zeroed, so the first three averages after startup are a
// quarter, a half and three quarters of the true value. NASA's, and it self-corrects after four
// intervals; the exercise prints the first four so the ramp is visible rather than surprising.
//
// ### AND THE HOGGING EVENT FIRES ON `==`, SO EXACTLY ONCE PER EPISODE
//
//     if (HS_AppData.CurrentCPUHoggingTime == HS_AppData.MaxCPUHoggingTime)
//
// Not `>=`. CurrentCPUHoggingTime keeps counting past the threshold, so a CPU pegged for a
// thousand cycles produces ONE event -- and a dip below the threshold resets the counter to zero,
// so the next episode produces another. That is the right behaviour and `==` is what implements
// it; `>=` would emit one per cycle forever.
//
// A -1 from the system monitor -- no device, or a failed read -- reports 0xFFFFFFFF in BOTH
// UtilCpuAvg and UtilCpuPeak, which NASA's comment calls a "unique value that indicates this".
// Note it does NOT touch the tracker or the hogging counter, so a device that fails for a while
// and recovers resumes its average from the samples before the outage.
U0 HS_MonitorUtilization()
{
  I32 CurrentUtil;
  U32 UtilIndex;
  U32 CombinedUtil = 0;
  U32 PeakUtil = 0;
  U32 ThisUtilIndex = HS_AppData.CurrentCPUUtilIndex;

  HS_AppData.CurrentCPUUtilIndex++;

  if (HS_AppData.CurrentCPUUtilIndex >= HS_UTIL_PEAK_NUM_INTERVAL) {
    HS_AppData.CurrentCPUUtilIndex = 0;
  }

  CurrentUtil = HS_SysMonGetCpuUtilization();

  if (CurrentUtil < 0) {
    /* CPU utilization not known, report unique value that indicates this */
    HS_AppData.UtilCpuAvg = 0xFFFFFFFF;
    HS_AppData.UtilCpuPeak = 0xFFFFFFFF;
  } else {
    if (CurrentUtil > HS_CPU_UTILIZATION_MAX) {
      CurrentUtil = HS_CPU_UTILIZATION_MAX;
    }

    if (CurrentUtil >= HS_UTIL_PER_INTERVAL_HOGGING &&
        HS_AppData.CurrentCPUHogState == HS_State_ENABLED) {
      HS_AppData.CurrentCPUHoggingTime++;

      // `==` AND NOT `>=` -- one event per episode. See the file header.
      if (HS_AppData.CurrentCPUHoggingTime == HS_AppData.MaxCPUHoggingTime) {
        CFE_EVS_SendEvent(HS_CPUMON_HOGGING_ERR_EID, CFE_EVS_EventType_ERROR, "CPU Hogging Detected");
        CFE_ES_WriteToSysLog("HS App: CPU Hogging Detected\n");
      }
    } else {
      HS_AppData.CurrentCPUHoggingTime = 0;
    }

    /* SAD: The wrap around logic prior to index access, ensures the index stays within the bounds of the buffer */
    HS_AppData.UtilizationTracker[ThisUtilIndex] = CurrentUtil;

    for (UtilIndex = 0; UtilIndex < HS_UTIL_PEAK_NUM_INTERVAL; UtilIndex++) {
      if (HS_AppData.UtilizationTracker[UtilIndex] > PeakUtil) {
        PeakUtil = HS_AppData.UtilizationTracker[UtilIndex];
      }

      if (ThisUtilIndex >= HS_UTIL_AVERAGE_NUM_INTERVAL) {
        // The contiguous window.
        if (UtilIndex > ThisUtilIndex - HS_UTIL_AVERAGE_NUM_INTERVAL && UtilIndex <= ThisUtilIndex) {
          CombinedUtil += HS_AppData.UtilizationTracker[UtilIndex];
        }
      } else {
        // The split window: the start of the ring plus its tail.
        if (UtilIndex <= ThisUtilIndex ||
            UtilIndex > HS_UTIL_PEAK_NUM_INTERVAL - (HS_UTIL_AVERAGE_NUM_INTERVAL - ThisUtilIndex)) {
          CombinedUtil += HS_AppData.UtilizationTracker[UtilIndex];
        }
      }
    }

    HS_AppData.UtilCpuAvg = CombinedUtil / HS_UTIL_AVERAGE_NUM_INTERVAL;
    HS_AppData.UtilCpuPeak = PeakUtil;
  }
}

/*******************************************************************************/
// THE FOUR TABLE VALIDATORS. One per loadable table, registered as cFE's validation callback, and
// all four are the same five-part shape:
//
//   1. refuse a NULL table with its own event id and HS_TBL_VAL_ERR
//   2. walk every entry, classifying it unused / bad / good
//   3. send a DETAILED event for the FIRST bad entry only, with its index
//   4. send an INFORMATION event with the three totals, ALWAYS
//   5. return the first entry's error code, or CFE_SUCCESS
//
// **THE TOTALS EVENT IS UNCONDITIONAL**, which is the one thing that differs from LC's and HK's
// validators: they send nothing on a clean table. HS reports good/bad/unused on every single
// validation, so a ground operator sees the shape of the table they just uploaded even when it
// was accepted. Four tables, four INFORMATION events per load.
//
// AND "UNUSED" IS A DIFFERENT TEST IN EACH:
//
//   AMT  CycleCount == 0 OR ActionType == NOACT
//   EMT  EventID == 0    OR ActionType == NOACT
//   XCT  ResourceType == NOTYPE
//   MAT  EnableState == DISABLED
//
// So an AMT entry with a cycle count of zero is unused NO MATTER what its action says -- the
// first test is an OR and the action is never examined. An exercise that only set ActionType
// would never reach the bad-entry arms.
I32 HS_ValidateAMTable(U8 *TableData)
{
  HS_AMTEntry_t *TableArray = TableData(HS_AMTEntry_t *);

  I32 TableResult = CFE_SUCCESS;
  U32 TableIndex = 0;
  I32 EntryResult;

  U16 ActionType;
  U16 CycleCount;
  U16 NullTerm;

  U32 GoodCount = 0;
  U32 BadCount = 0;
  U32 UnusedCount = 0;
  U8 BadName[OS_MAX_API_NAME];

  BadName[0] = 0;

  if (TableData == NULL) {
    CFE_EVS_SendEvent(HS_AM_TBL_NULL_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error in AM Table Validation. Table is null.");

    return HS_TBL_VAL_ERR;
  }

  for (TableIndex = 0; TableIndex < HS_MAX_MONITORED_APPS; TableIndex++) {
    ActionType = TableArray[TableIndex].ActionType;
    CycleCount = TableArray[TableIndex].CycleCount;
    NullTerm = TableArray[TableIndex].NullTerm;
    EntryResult = HS_AMTVal_NO_ERR;

    if (CycleCount == 0 || ActionType == HS_AMTActType_NOACT) {
      /*
      ** Unused table entry
      */
      UnusedCount++;
    } else if (NullTerm != 0) {
      /*
      ** Null Terminator Safety Buffer is not Null
      */
      EntryResult = HS_AMTVal_ERR_NUL;
      BadCount++;
    } else if (!HS_AMTActionIsValid(ActionType)) {
      /*
      ** Action Type is not valid
      */
      EntryResult = HS_AMTVal_ERR_ACT;
      BadCount++;
    } else {
      /*
      ** Otherwise, this entry is good
      */
      GoodCount++;
    }
    /*
    ** Generate detailed event for "first" error
    */
    if (EntryResult != HS_AMTVal_NO_ERR && TableResult == CFE_SUCCESS) {
      // StrNCpy ZERO-FILLS to the length, which strncpy does NOT -- so NASA's explicit
      // terminator on the next line is redundant here and is kept anyway: it is NASA's text, and
      // the two behaviours agree for every input because the copy is one byte short of the
      // buffer either way.
      StrNCpy(BadName, TableArray[TableIndex].AppName, OS_MAX_API_NAME - 1);
      BadName[OS_MAX_API_NAME - 1] = '\0';
      CFE_EVS_SendEvent(HS_AMTVal_ERR_EID, CFE_EVS_EventType_ERROR,
                        "AppMon verify err: Entry = %d, Err = %d, Action = %d, App = %s",
                        TableIndex, EntryResult, ActionType, BadName);
      TableResult = EntryResult;
    }
  }

  /*
  ** Generate informational event with error totals
  */
  CFE_EVS_SendEvent(HS_AMTVal_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "AppMon verify results: good = %d, bad = %d, unused = %d", GoodCount, BadCount,
                    UnusedCount);

  return TableResult;
}

/*******************************************************************************/
// Validate the Event Monitor Table. The AMT's shape with EventID where CycleCount was, and one
// more field in its error event.
I32 HS_ValidateEMTable(U8 *TableData)
{
  HS_EMTEntry_t *TableArray = TableData(HS_EMTEntry_t *);

  I32 TableResult = CFE_SUCCESS;
  U32 TableIndex = 0;
  I32 EntryResult;

  U16 ActionType;
  U16 EventID;
  U16 NullTerm;

  U32 GoodCount = 0;
  U32 BadCount = 0;
  U32 UnusedCount = 0;
  U8 BadName[OS_MAX_API_NAME];

  BadName[0] = 0;

  if (TableData == NULL) {
    CFE_EVS_SendEvent(HS_EM_TBL_NULL_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error in EM Table Validation. Table is null.");

    return HS_TBL_VAL_ERR;
  }

  for (TableIndex = 0; TableIndex < HS_MAX_MONITORED_EVENTS; TableIndex++) {
    ActionType = TableArray[TableIndex].ActionType;
    EventID = TableArray[TableIndex].EventID;
    NullTerm = TableArray[TableIndex].NullTerm;
    EntryResult = HS_EMTVal_NO_ERR;

    if (EventID == 0 || ActionType == HS_EMTActType_NOACT) {
      UnusedCount++;
    } else if (NullTerm != 0) {
      EntryResult = HS_EMTVal_ERR_NUL;
      BadCount++;
    } else if (!HS_EMTActionIsValid(ActionType)) {
      EntryResult = HS_EMTVal_ERR_ACT;
      BadCount++;
    } else {
      GoodCount++;
    }
    if (EntryResult != HS_EMTVal_NO_ERR && TableResult == CFE_SUCCESS) {
      StrNCpy(BadName, TableArray[TableIndex].AppName, OS_MAX_API_NAME - 1);
      BadName[OS_MAX_API_NAME - 1] = '\0';
      // NOTE THE MISSING COMMA IN NASA'S TEXT: "ID = %d App = %s". Every other field in all four
      // of these events is comma-separated and this one pair is not. Kept verbatim -- a ground
      // decoder splitting on commas gets "ID = 5 App = FOO" as one field, and changing it would
      // be a change to the interface.
      CFE_EVS_SendEvent(HS_EMTVal_ERR_EID, CFE_EVS_EventType_ERROR,
                        "EventMon verify err: Entry = %d, Err = %d, Action = %d, ID = %d App = %s",
                        TableIndex, EntryResult, ActionType, EventID, BadName);
      TableResult = EntryResult;
    }
  }

  CFE_EVS_SendEvent(HS_EMTVal_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "EventMon verify results: good = %d, bad = %d, unused = %d", GoodCount,
                    BadCount, UnusedCount);

  return TableResult;
}

/*******************************************************************************/
// Validate the Execution Counters Table.
//
// ITS ResourceType IS READ INTO A **U16** AND THE FIELD IS A U32. NASA declares
// `uint16 ResourceType;` in this function and HS_XCTEntry_t.ResourceType is a uint32, so the top
// sixteen bits are discarded before the comparison. A ground upload with a resource type of
// 0x00010001 would therefore validate as APP_MAIN. Upstream, and kept: the four valid types are
// 0..4 so no legitimate table notices, and narrowing it here is what NASA wrote.
I32 HS_ValidateXCTable(U8 *TableData)
{
  HS_XCTEntry_t *TableArray = TableData(HS_XCTEntry_t *);

  I32 TableResult = CFE_SUCCESS;
  U32 TableIndex;
  I32 EntryResult;
  U16 ResourceType;
  U32 NullTerm;

  U32 GoodCount = 0;
  U32 BadCount = 0;
  U32 UnusedCount = 0;
  U8 BadName[OS_MAX_API_NAME];

  BadName[0] = 0;

  if (TableData == NULL) {
    CFE_EVS_SendEvent(HS_XC_TBL_NULL_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error in XC Table Validation. Table is null.");

    return HS_TBL_VAL_ERR;
  }

  for (TableIndex = 0; TableIndex < HS_MAX_EXEC_CNT_SLOTS; TableIndex++) {
    ResourceType = TableArray[TableIndex].ResourceType;
    NullTerm = TableArray[TableIndex].NullTerm;
    EntryResult = HS_XCTVal_NO_ERR;

    if (ResourceType == HS_XCTResType_NOTYPE) {
      UnusedCount++;
    } else if (NullTerm != 0) {
      EntryResult = HS_XCTVal_ERR_NUL;
      BadCount++;
    } else if (ResourceType != HS_XCTResType_APP_MAIN && ResourceType != HS_XCTResType_APP_CHILD &&
               ResourceType != HS_XCTResType_DEVICE && ResourceType != HS_XCTResType_ISR) {
      EntryResult = HS_XCTVal_ERR_TYPE;
      BadCount++;
    } else {
      GoodCount++;
    }

    if (EntryResult != HS_XCTVal_NO_ERR && TableResult == CFE_SUCCESS) {
      StrNCpy(BadName, TableArray[TableIndex].ResourceName, OS_MAX_API_NAME - 1);
      BadName[OS_MAX_API_NAME - 1] = '\0';
      CFE_EVS_SendEvent(HS_XCTVal_ERR_EID, CFE_EVS_EventType_ERROR,
                        "ExeCount verify err: Entry = %d, Err = %d, Type = %d, Name = %s",
                        TableIndex, EntryResult, ResourceType, BadName);
      TableResult = EntryResult;
    }
  }

  CFE_EVS_SendEvent(HS_XCTVal_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "ExeCount verify results: good = %d, bad = %d, unused = %d", GoodCount,
                    BadCount, UnusedCount);

  return TableResult;
}

/*******************************************************************************/
// Validate the Message Actions Table.
//
// ### IT READS THE LENGTH AND MsgId OUT OF **EVERY** ENTRY, INCLUDING UNUSED ONES
//
// CFE_MSG_GetSize and CFE_MSG_GetMsgId are called before the EnableState is even examined, so a
// DISABLED entry's 16 bytes of whatever-the-ground-left-there are parsed as a CCSDS header on
// every validation. Harmless -- the results are discarded for an unused entry -- and worth
// noting because it means the two calls are not guarded by anything.
//
// ### AND THE LENGTH IS BOUNDED BY THE SOFTWARE BUS, NOT BY THE BUFFER -- see note #23
//
//     else if (Length > CFE_MISSION_SB_MAX_SB_MSG_SIZE)     /* 32768 */
//
// against an HS_MATMsgBuf_t of HS_MAX_MSG_ACT_SIZE = **16** bytes. A factor of 2,048. An entry
// whose uploaded header claims more than 16 bytes validates cleanly, and both monitors then
// transmit it verbatim -- reading past the entry, through the seven after it, and past the table.
// Kept exactly: the bound and the constant are NASA's, and docs/CFS_UPSTREAM_NOTES.md #23 records
// why the right fix is not obviously a one-liner.
I32 HS_ValidateMATable(U8 *TableData)
{
  HS_MATEntry_t *TableArray = TableData(HS_MATEntry_t *);

  I32 TableResult = CFE_SUCCESS;
  U32 TableIndex = 0;
  I64 Length = 0;
  U16 EnableState;
  I32 EntryResult;

  CFE_SB_MsgId MessageID;
  CFE_SB_Buffer *BufPtr = NULL;

  U32 GoodCount = 0;
  U32 BadCount = 0;
  U32 UnusedCount = 0;

  MessageID = CFE_SB_InvalidMsgId();

  if (TableData == NULL) {
    CFE_EVS_SendEvent(HS_MA_TBL_NULL_ERR_EID, CFE_EVS_EventType_ERROR,
                      "Error in MA Table Validation. Table is null.");

    return HS_TBL_VAL_ERR;
  }

  for (TableIndex = 0; TableIndex < HS_MAX_MSG_ACT_TYPES; TableIndex++) {
    EntryResult = HS_MATVal_NO_ERR;
    BufPtr = &TableArray[TableIndex].MsgBuf;
    CFE_MSG_GetSize(&BufPtr->Msg, &Length);
    CFE_MSG_GetMsgId(&BufPtr->Msg, &MessageID);
    EnableState = TableArray[TableIndex].EnableState;

    if (EnableState == HS_MATState_DISABLED) {
      UnusedCount++;
    } else if (EnableState != HS_MATState_ENABLED && EnableState != HS_MATState_NOEVENT) {
      EntryResult = HS_MATVal_ERR_ENA;
      BadCount++;
    } else if (!CFE_SB_IsValidMsgId(MessageID)) {
      EntryResult = HS_MATVal_ERR_ID;
      BadCount++;
    } else if (Length > CFE_MISSION_SB_MAX_SB_MSG_SIZE) {
      EntryResult = HS_MATVal_ERR_LEN;
      BadCount++;
    } else {
      GoodCount++;
    }
    if (EntryResult != HS_MATVal_NO_ERR && TableResult == CFE_SUCCESS) {
      CFE_EVS_SendEvent(HS_MATVal_ERR_EID, CFE_EVS_EventType_ERROR,
                        "MsgActs verify err: Entry = %d, Err = %d, Length = %d, ID = 0x%08lX",
                        TableIndex, EntryResult, Length, CFE_SB_MsgIdToValue(MessageID));
      TableResult = EntryResult;
    }
  }

  CFE_EVS_SendEvent(HS_MATVal_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "MsgActs verify results: good = %d, bad = %d, unused = %d", GoodCount,
                    BadCount, UnusedCount);

  return TableResult;
}

/*******************************************************************************/
// Set the values stored in the critical data store: each count, and its bitwise complement.
//
// THE COMPLEMENT IS COMPUTED FROM THE FIELD, NOT FROM THE ARGUMENT:
//
//     HS_AppData.CDSData.ResetsPerformed    = ResetsPerformed;
//     HS_AppData.CDSData.ResetsPerformedNot = ~HS_AppData.CDSData.ResetsPerformed;
//
// -- so the pair is guaranteed consistent with what was actually stored even if the assignment
// narrowed. Both fields are uint16 and the argument is uint16, so it cannot narrow today; writing
// it this way means it still could not if one of them widened.
//
// AND THE COPY TO THE CDS IS CONDITIONAL ON CDSState. If the critical data store was never
// created, the live copy is still updated and the write is skipped -- so HS enforces its reset
// limit within a single boot even with no CDS at all, and only loses the count across a reset.
U0 HS_SetCDSData(U16 ResetsPerformed, U16 MaxResets)
{
  /*
  ** Set CDS data and verification inverses
  */
  HS_AppData.CDSData.ResetsPerformed = ResetsPerformed;
  HS_AppData.CDSData.ResetsPerformedNot = ~HS_AppData.CDSData.ResetsPerformed;
  HS_AppData.CDSData.MaxResets = MaxResets;
  HS_AppData.CDSData.MaxResetsNot = ~HS_AppData.CDSData.MaxResets;
  /*
  ** Copy the data to the CDS if CDS Creation was successful
  */
  if (HS_AppData.CDSState == HS_State_ENABLED) {
    CFE_ES_CopyToCDS(HS_AppData.MyCDSHandle, &HS_AppData.CDSData);
  }
}

#endif
