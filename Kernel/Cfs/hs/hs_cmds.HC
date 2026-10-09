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
// HEALTH & SAFETY'S COMMAND HANDLERS -- the 1:1 translation of NASA's fsw/src/hs_cmds.c, 812
// lines and seventeen functions: twelve command handlers, the housekeeping builder, the table
// re-acquisition, two status refreshers and the counter reset.
//
// ### TWO COMMANDS COUNT THEMSELVES DIFFERENTLY FROM THE OTHER TEN, AND STILL RETURN SUCCESS
//
// Eight of the handlers open with `HS_AppData.CmdCount++` before doing anything -- the command is
// counted as accepted on arrival. HS_EnableEventMonCmd and HS_DisableEventMonCmd instead defer,
// subscribe or unsubscribe, and then choose:
//
//     if (Status == CFE_SUCCESS) { HS_AppData.CmdCount++; }
//     else                       { HS_AppData.CmdErrCount++; }
//     return CFE_SUCCESS;                 <-- UNCONDITIONALLY
//
// So **the only two commands that can fail report that failure in telemetry and not in their
// return value.** A dispatcher that counted errors from the return code and the HK packet's
// CmdErrCount disagree by construction, and they disagree in the direction that matters: the
// subscription to the whole system's event stream silently did not happen while the command
// looked accepted. Kept verbatim -- it is an upstream observation, not a translation choice, and
// the exercise drives both counters so the asymmetry is visible in the transcript.
//
// AND HS_ResetCmd DOES NOT COUNT ITSELF AT ALL, which is correct rather than a bug: it calls
// HS_ResetCounters, which zeroes CmdCount, so an increment either side of that call would be
// erased or would make the reset non-idempotent. The remaining handler that does not increment
// is HS_SendHkCmd, because housekeeping is not a ground command.
//
// ### THE HOUSEKEEPING BUILDER DOES A FULL TABLE SCAN AND TWO NAME LOOKUPS PER SLOT
//
// HS_SendHkCmd is not a copy of counters. Every cycle it
//
//   * walks all HS_MAX_MONITORED_EVENTS EMT entries calling CFE_ES_GetAppIDByName on each one
//     that has an action, to recount InvalidEventMonCount from scratch;
//   * walks all HS_MAX_EXEC_CNT_SLOTS XCT entries and, per entry, resolves a task or counter name
//     and reads its execution counter.
//
// With the shipped configuration that is up to 16 + 32 = 48 name lookups per housekeeping cycle,
// each a linear search of cFE's resource tables. The numbers are small enough that it does not
// matter, and the shape is worth naming because the obvious optimisation -- caching the lookup --
// is exactly what would make a restarted application keep reporting a stale counter.
//
// ### AN UNREADABLE EXECUTION COUNTER IS REPORTED AS 0xFFFFFFFF, NOT AS ZERO
//
// ExeCount starts at HS_INVALID_EXECOUNT and is only overwritten on a successful read, so a
// failed lookup, a failed GetTaskInfo, a NOTYPE slot and an unrecognised resource type all land
// in the packet as the same sentinel. That is the right choice -- zero would be
// indistinguishable from a task that has genuinely not run -- and it means the ground decoder
// has to know the sentinel or it reads 4.29 billion executions.
//
// **CFE_ES_GetGenCount's RETURN IS NOT CHECKED**, only CFE_ES_GetGenCounterIDByName's. So for
// a DEVICE or ISR slot whose name resolves but whose count cannot be read, ExeCount holds
// whatever CFE_ES_GetGenCount left -- which for the translated cFE is the sentinel, because it
// does not write through the pointer on failure. Kept, and named here because it is the one path
// in this file whose reported value depends on a callee's failure behaviour rather than on HS's.
//
// ### THE DEFAULT ARM OF THE RESOURCE SWITCH IS A **DEBUG** EVENT, SO IT IS NORMALLY INVISIBLE
//
// An XCT entry with a resource type outside 0..4 produces HS_HKREQ_RESOURCE_DBG_EID at
// CFE_EVS_EventType_DEBUG -- filtered out by default. An operator who uploads a corrupt
// execution-counter table sees 0xFFFFFFFF in the packet and no error anywhere. Note that
// HS_ValidateXCTable would have rejected the table, so this arm is only reachable if the table
// was modified in place after validation; it is still the quietest failure in HS.
//
// ### HS_AcquirePointers IS FOUR COPIES OF THE SAME SEQUENCE AND THEY DIFFER IN THREE WAYS
//
// Release / Manage / GetAddress, four times. The differences are the whole content of the
// function:
//
//   * **AMT and MAT act on CFE_TBL_INFO_UPDATED** (refreshing the enable bitmap and the message
//     cooldowns); EMT and XCT do not, so a newly loaded Event Monitor Table takes effect with
//     whatever counters the previous one left.
//   * **AMT and EMT guard their error report** with `loaded || currently enabled`; MAT and XCT
//     guard it with `currently enabled` alone. So a failure to re-acquire a table that was
//     loaded but is disabled is reported for the two monitors and silent for the other two.
//   * **EMT's failure path unsubscribes from the event stream**, and it is the only one that
//     touches the software bus. It also reports each unsubscribe failure with its own event id
//     (HS_BADEMT_LONG_UNSUB_EID / HS_BADEMT_SHORT_UNSUB_EID) rather than reusing the pair
//     HS_DisableEventMonCmd uses, which is how the ground tells a commanded disable from a
//     table-induced one.
//
// **AND EMT'S UNSUBSCRIBE OVERWRITES `Status`**, which is the variable the enclosing `if` tested.
// It is not read again before the next GetAddress assigns it, so nothing breaks -- but the
// variable that means "why did the EMT fail" becomes "did the unsubscribe fail" halfway through
// the branch. Kept; it is the kind of reuse a reader of the C has to notice and the translation
// must not quietly fix.
//
// ### HS_AppMonStatusRefresh SHIFTS BY 31
//
//     HS_AppData.AppMonEnables[TableIndex / 32] |= (1 << (TableIndex % 32));
//
// with HS_MAX_MONITORED_APPS exactly 32, so TableIndex reaches 31 and `1 << 31` sets the sign bit
// of a signed int. The same shape as the clear in HS_MonitorApplications -- see hs_monitors.HC.
// Kept as NASA writes it.
//
// AND IT ZEROES AppMonLastExeCount FOR EVERY SLOT, INCLUDING DISABLED ONES, while
// AppMonCheckInCountdown is set from the table only for enabled ones. So the first cycle after a
// refresh always sees a counter change for any app whose counter is non-zero, which is what makes
// a table load not immediately trip a monitor.
#ifndef HS_CMDS_HC
#define HS_CMDS_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// hs_cfg.HC, hs_msg.HC, hs_tbl.HC, hs_global.HC, hs_eventids.HC, hs_utils.HC, hs_sysmon.HC,
// hs_monitors.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13.

// --- hs_cmds.c's own macro ---------------------------------------------------------------------
//
// NASA's reason for it, verbatim from the source: "This is done as a macro so it can be applied
// consistently to all message processing functions, based on the way FM defines its messages."
// LC carries a character-for-character identical twin under its own name -- two apps, two
// macros, one body -- and HS uses it at exactly ONE site, because HS has exactly one command
// with a payload.
//
// KEPT AS A MACRO rather than substituted at the call site. HolyC's cast is postfix, so
// `((const type *)(ptr))` becomes `(ptr)(type *)`, and `const` has no HolyC spelling and is
// dropped; the expression is otherwise NASA's. Keeping it is what makes check_members' reverse
// pass see the `->Payload` where NASA writes it instead of in the one function body that
// expands it.
#define HS_GET_CMD_PAYLOAD(ptr, type) (&(ptr)(type *)->Payload)

// --- hs_cmds.h's prototypes -------------------------------------------------------------------
U0 HS_ResetCounters();
U0 HS_AcquirePointers();
I32 HS_SendHkCmd(HS_SendHkCmd_t *BufPtr);
I32 HS_NoopCmd(HS_NoopCmd_t *BufPtr);
I32 HS_ResetCmd(HS_ResetCmd_t *BufPtr);
I32 HS_EnableAppMonCmd(HS_EnableAppMonCmd_t *BufPtr);
I32 HS_DisableAppMonCmd(HS_DisableAppMonCmd_t *BufPtr);
I32 HS_EnableEventMonCmd(HS_EnableEventMonCmd_t *BufPtr);
I32 HS_DisableEventMonCmd(HS_DisableEventMonCmd_t *BufPtr);
I32 HS_EnableAlivenessCmd(HS_EnableAlivenessCmd_t *BufPtr);
I32 HS_DisableAlivenessCmd(HS_DisableAlivenessCmd_t *BufPtr);
I32 HS_EnableCpuHogCmd(HS_EnableCpuHogCmd_t *BufPtr);
I32 HS_DisableCpuHogCmd(HS_DisableCpuHogCmd_t *BufPtr);
I32 HS_ResetResetsPerformedCmd(HS_ResetResetsPerformedCmd_t *BufPtr);
I32 HS_SetMaxResetsCmd(HS_SetMaxResetsCmd_t *BufPtr);
U0 HS_AppMonStatusRefresh();
U0 HS_MsgActsStatusRefresh();

/*******************************************************************************/
// Housekeeping request: rebuild the whole 164-byte payload and transmit it.
I32 HS_SendHkCmd(HS_SendHkCmd_t *BufPtr)
{
  U32 AppId;

  U32 ExeCount;
  U32 TaskId;
  U32 CounterId;
  CFE_ES_TaskInfo_t TaskInfo;
  I32 Status;
  U32 TableIndex;

  HS_HkTlm_Payload_t *PayloadPtr;

  AppId = CFE_ES_APPID_UNDEFINED;

  MemSet(&TaskInfo, 0, sizeof(CFE_ES_TaskInfo_t));

  PayloadPtr = &HS_AppData.HkPacket.Payload;

  /*
  ** Update HK variables
  */
  PayloadPtr->CmdCount = HS_AppData.CmdCount;
  PayloadPtr->CmdErrCount = HS_AppData.CmdErrCount;
  PayloadPtr->CurrentAppMonState = HS_AppData.CurrentAppMonState;
  PayloadPtr->CurrentEventMonState = HS_AppData.CurrentEventMonState;
  PayloadPtr->CurrentAlivenessState = HS_AppData.CurrentAlivenessState;
  PayloadPtr->CurrentCPUHogState = HS_AppData.CurrentCPUHogState;
  PayloadPtr->ResetsPerformed = HS_AppData.CDSData.ResetsPerformed;
  PayloadPtr->MaxResets = HS_AppData.CDSData.MaxResets;
  PayloadPtr->EventsMonitoredCount = HS_AppData.EventsMonitoredCount;
  PayloadPtr->MsgActExec = HS_AppData.MsgActExec;

  /*
  ** Calculate the current number of invalid event monitor entries
  */
  PayloadPtr->InvalidEventMonCount = 0;
  if (HS_AppData.EMTablePtr != NULL) {
    for (TableIndex = 0; TableIndex < HS_MAX_MONITORED_EVENTS; TableIndex++) {
      if (HS_AppData.EMTablePtr[TableIndex].ActionType != HS_EMTActType_NOACT) {
        Status = CFE_ES_GetAppIDByName(&AppId, HS_AppData.EMTablePtr[TableIndex].AppName);

        if (Status != CFE_SUCCESS) {
          PayloadPtr->InvalidEventMonCount++;
        }
      }
    }
  }

  /*
  ** Build the HK status flags byte
  */
  PayloadPtr->StatusFlags = 0;
  if (HS_AppData.ExeCountState == HS_State_ENABLED) {
    PayloadPtr->StatusFlags |= HS_StatusFlag_LOADED_XCT;
  }
  if (HS_AppData.MsgActsState == HS_State_ENABLED) {
    PayloadPtr->StatusFlags |= HS_StatusFlag_LOADED_MAT;
  }
  if (HS_AppData.AppMonLoaded == HS_State_ENABLED) {
    PayloadPtr->StatusFlags |= HS_StatusFlag_LOADED_AMT;
  }
  if (HS_AppData.EventMonLoaded == HS_State_ENABLED) {
    PayloadPtr->StatusFlags |= HS_StatusFlag_LOADED_EMT;
  }
  if (HS_AppData.CDSState == HS_State_ENABLED) {
    PayloadPtr->StatusFlags |= HS_StatusFlag_CDS_IN_USE;
  }

  /*
  ** Update the AppMon Enables
  */
  // `<=` AND A DIVISION: the loop bound is the LAST INDEX, not the count. With 32 apps and 32
  // bits per word this runs once; the expression is NASA's and is kept unfolded -- see hs_msg.HC.
  for (TableIndex = 0; TableIndex <= (HS_MAX_MONITORED_APPS - 1) / HS_BITS_PER_APPMON_ENABLE;
       TableIndex++) {
    PayloadPtr->AppMonEnables[TableIndex] = HS_AppData.AppMonEnables[TableIndex];
  }

  PayloadPtr->UtilCpuAvg = HS_AppData.UtilCpuAvg;
  PayloadPtr->UtilCpuPeak = HS_AppData.UtilCpuPeak;

  /*
  ** Add the execution counters
  */
  for (TableIndex = 0; TableIndex < HS_MAX_EXEC_CNT_SLOTS; TableIndex++) {
    ExeCount = HS_INVALID_EXECOUNT;

    if (HS_AppData.ExeCountState == HS_State_ENABLED && HS_AppData.XCTablePtr != NULL) {
      switch (HS_AppData.XCTablePtr[TableIndex].ResourceType) {
        case HS_XCTResType_APP_MAIN:
        case HS_XCTResType_APP_CHILD:
          Status = CFE_ES_GetTaskIDByName(&TaskId, HS_AppData.XCTablePtr[TableIndex].ResourceName);

          if (Status == CFE_SUCCESS) {
            Status = CFE_ES_GetTaskInfo(&TaskInfo, TaskId);
            if (Status == CFE_SUCCESS) {
              ExeCount = TaskInfo.ExecutionCounter;
            }
          }
          break;
        case HS_XCTResType_DEVICE:
        case HS_XCTResType_ISR:
          Status =
              CFE_ES_GetGenCounterIDByName(&CounterId, HS_AppData.XCTablePtr[TableIndex].ResourceName);

          if (Status == CFE_SUCCESS) {
            // NOT CHECKED, AND NASA DOES NOT CHECK IT -- see the file header on what ExeCount
            // then holds.
            CFE_ES_GetGenCount(CounterId, &ExeCount);
          }
          break;
        case HS_XCTResType_NOTYPE:
          /* no action - ExeCount remains HS_INVALID_EXECOUNT */
          break;
        default:
          /* ExeCount remains HS_INVALID_EXECOUNT */
          // A **DEBUG** EVENT, so by default this is invisible -- see the file header.
          CFE_EVS_SendEvent(HS_HKREQ_RESOURCE_DBG_EID, CFE_EVS_EventType_DEBUG,
                            "Housekeeping req found unknown resource.  Type=0x%08X",
                            HS_AppData.XCTablePtr[TableIndex].ResourceType);
          break;
      } /* end ResourceType switch statement */
    }   /* end ExeCountState if statement */

    PayloadPtr->ExeCounts[TableIndex] = ExeCount;
  }

  /*
  ** Timestamp and send housekeeping packet
  */
  CFE_SB_TimeStampMsg(&HS_AppData.HkPacket.TelemetryHeader.Msg);
  CFE_SB_TransmitMsg(&HS_AppData.HkPacket.TelemetryHeader.Msg, TRUE);

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Noop: count it and report the version.
I32 HS_NoopCmd(HS_NoopCmd_t *BufPtr)
{
  HS_AppData.CmdCount++;

  CFE_EVS_SendEvent(HS_NOOP_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "No-op command: Version %d.%d.%d.%d", HS_MAJOR_VERSION, HS_MINOR_VERSION,
                    HS_REVISION, HS_MISSION_REV);

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Reset counters. DOES NOT INCREMENT CmdCount, and that is deliberate -- see the file header.
I32 HS_ResetCmd(HS_ResetCmd_t *BufPtr)
{
  HS_ResetCounters();

  CFE_EVS_SendEvent(HS_RESET_INF_EID, CFE_EVS_EventType_INFORMATION, "Reset counters command");
  return CFE_SUCCESS;
}

/*******************************************************************************/
// Zero the four housekeeping counters.
U0 HS_ResetCounters()
{
  HS_AppData.CmdCount = 0;
  HS_AppData.CmdErrCount = 0;
  HS_AppData.EventsMonitoredCount = 0;
  HS_AppData.MsgActExec = 0;
}

/*******************************************************************************/
// Enable the application monitor. Refreshing the status BEFORE setting the state is what stops
// the first cycle after an enable from tripping every monitor whose countdown had expired.
I32 HS_EnableAppMonCmd(HS_EnableAppMonCmd_t *BufPtr)
{
  HS_AppData.CmdCount++;

  if (HS_AppData.CurrentAppMonState == HS_State_ENABLED) {
    CFE_EVS_SendEvent(HS_ENABLE_APPMON_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Application Monitoring is *already* Enabled");
  } else {
    HS_AppMonStatusRefresh();
    HS_AppData.CurrentAppMonState = HS_State_ENABLED;
    CFE_EVS_SendEvent(HS_ENABLE_APPMON_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Application Monitoring Enabled");
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable the application monitor. No refresh on the way down, so the countdowns the monitor was
// part way through are still there when it is enabled again -- and HS_EnableAppMonCmd's refresh
// is what discards them.
I32 HS_DisableAppMonCmd(HS_DisableAppMonCmd_t *BufPtr)
{
  HS_AppData.CmdCount++;

  if (HS_AppData.CurrentAppMonState == HS_State_DISABLED) {
    CFE_EVS_SendEvent(HS_DISABLE_APPMON_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Application Monitoring is *already* Disabled");
  } else {
    HS_AppData.CurrentAppMonState = HS_State_DISABLED;
    CFE_EVS_SendEvent(HS_DISABLE_APPMON_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Application Monitoring Disabled");
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable the event monitor: subscribe to BOTH event formats on HS's event pipe.
//
// ONE OF THE TWO COMMANDS THAT COUNT THEMSELVES AT THE END, and it returns CFE_SUCCESS whatever
// happened -- see the file header. Note also that a failure of the SECOND subscribe leaves the
// FIRST in place: HS is subscribed to long-format events, CurrentEventMonState stays DISABLED,
// and the event pipe fills with messages nothing reads.
I32 HS_EnableEventMonCmd(HS_EnableEventMonCmd_t *BufPtr)
{
  I32 Status = CFE_SUCCESS;

  if (HS_AppData.CurrentEventMonState == HS_State_ENABLED) {
    CFE_EVS_SendEvent(HS_ENABLE_EVENTMON_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Event Monitoring is *already* Enabled");
  } else {
    Status = CFE_SB_SubscribeEx(CFE_SB_ValueToMsgId(CFE_EVS_LONG_EVENT_MSG_MID),
                                HS_AppData.EventPipe, CFE_SB_DEFAULT_QOS, HS_EVENT_PIPE_DEPTH);
    if (Status == CFE_SUCCESS) {
      Status = CFE_SB_SubscribeEx(CFE_SB_ValueToMsgId(CFE_EVS_SHORT_EVENT_MSG_MID),
                                  HS_AppData.EventPipe, CFE_SB_DEFAULT_QOS, HS_EVENT_PIPE_DEPTH);

      if (Status == CFE_SUCCESS) {
        HS_AppData.CurrentEventMonState = HS_State_ENABLED;
        CFE_EVS_SendEvent(HS_ENABLE_EVENTMON_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "Event Monitoring Enabled");
      } else {
        CFE_EVS_SendEvent(HS_EVENTMON_SHORT_SUB_EID, CFE_EVS_EventType_ERROR,
                          "Event Monitor Enable: Error Subscribing to short-format Events,RC=0x%08X",
                          Status);
      }
    } else {
      CFE_EVS_SendEvent(HS_EVENTMON_LONG_SUB_EID, CFE_EVS_EventType_ERROR,
                        "Event Monitor Enable: Error Subscribing to long-format Events,RC=0x%08X",
                        Status);
    }
  }

  if (Status == CFE_SUCCESS) {
    HS_AppData.CmdCount++;
  } else {
    HS_AppData.CmdErrCount++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable the event monitor: unsubscribe from both formats. The mirror image, with the same
// deferred counting and the same unconditional CFE_SUCCESS.
I32 HS_DisableEventMonCmd(HS_DisableEventMonCmd_t *BufPtr)
{
  I32 Status = CFE_SUCCESS;

  if (HS_AppData.CurrentEventMonState == HS_State_DISABLED) {
    CFE_EVS_SendEvent(HS_DISABLE_EVENTMON_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Event Monitoring is *already* Disabled");
  } else {
    Status = CFE_SB_Unsubscribe(CFE_SB_ValueToMsgId(CFE_EVS_LONG_EVENT_MSG_MID),
                                HS_AppData.EventPipe);

    if (Status == CFE_SUCCESS) {
      Status = CFE_SB_Unsubscribe(CFE_SB_ValueToMsgId(CFE_EVS_SHORT_EVENT_MSG_MID),
                                  HS_AppData.EventPipe);

      if (Status == CFE_SUCCESS) {
        HS_AppData.CurrentEventMonState = HS_State_DISABLED;
        CFE_EVS_SendEvent(HS_DISABLE_EVENTMON_INF_EID, CFE_EVS_EventType_INFORMATION,
                          "Event Monitoring Disabled");
      } else {
        CFE_EVS_SendEvent(HS_EVENTMON_SHORT_UNSUB_EID, CFE_EVS_EventType_ERROR,
                          "Event Monitor Disable: Error Unsubscribing from short-format Events,RC=0x%08X",
                          Status);
      }
    } else {
      CFE_EVS_SendEvent(HS_EVENTMON_LONG_UNSUB_EID, CFE_EVS_EventType_ERROR,
                        "Event Monitor Disable: Error Unsubscribing from long-format Events,RC=0x%08X",
                        Status);
    }
  }

  if (Status == CFE_SUCCESS) {
    HS_AppData.CmdCount++;
  } else {
    HS_AppData.CmdErrCount++;
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable the aliveness indicator -- the dot HS writes to the console every HS_CPU_ALIVE_PERIOD
// cycles. The plainest of the five toggles.
I32 HS_EnableAlivenessCmd(HS_EnableAlivenessCmd_t *BufPtr)
{
  HS_AppData.CmdCount++;

  if (HS_AppData.CurrentAlivenessState == HS_State_ENABLED) {
    CFE_EVS_SendEvent(HS_ENABLE_ALIVENESS_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Aliveness Indicator is *already* Enabled");
  } else {
    HS_AppData.CurrentAlivenessState = HS_State_ENABLED;
    CFE_EVS_SendEvent(HS_ENABLE_ALIVENESS_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Aliveness Indicator Enabled");
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable the aliveness indicator.
I32 HS_DisableAlivenessCmd(HS_DisableAlivenessCmd_t *BufPtr)
{
  HS_AppData.CmdCount++;

  if (HS_AppData.CurrentAlivenessState == HS_State_DISABLED) {
    CFE_EVS_SendEvent(HS_DISABLE_ALIVENESS_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Aliveness Indicator is *already* Disabled");
  } else {
    HS_AppData.CurrentAlivenessState = HS_State_DISABLED;
    CFE_EVS_SendEvent(HS_DISABLE_ALIVENESS_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "Aliveness Indicator Disabled");
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Enable the CPU hogging indicator. NOTE WHAT IT DOES NOT RESET: CurrentCPUHoggingTime keeps the
// count it had while the indicator was disabled, so an enable during a hogging episode can report
// immediately -- HS_MonitorUtilization fires on `==`, so only if the count has not already passed
// MaxCPUHoggingTime. See hs_monitors.HC.
I32 HS_EnableCpuHogCmd(HS_EnableCpuHogCmd_t *BufPtr)
{
  HS_AppData.CmdCount++;

  if (HS_AppData.CurrentCPUHogState == HS_State_ENABLED) {
    CFE_EVS_SendEvent(HS_ENABLE_CPUHOG_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "CPU Hogging Indicator is *already* Enabled");
  } else {
    HS_AppData.CurrentCPUHogState = HS_State_ENABLED;
    CFE_EVS_SendEvent(HS_ENABLE_CPUHOG_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "CPU Hogging Indicator Enabled");
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Disable the CPU hogging indicator.
I32 HS_DisableCpuHogCmd(HS_DisableCpuHogCmd_t *BufPtr)
{
  HS_AppData.CmdCount++;

  if (HS_AppData.CurrentCPUHogState == HS_State_DISABLED) {
    CFE_EVS_SendEvent(HS_DISABLE_CPUHOG_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "CPU Hogging Indicator is *already* Disabled");
  } else {
    HS_AppData.CurrentCPUHogState = HS_State_DISABLED;
    CFE_EVS_SendEvent(HS_DISABLE_CPUHOG_INF_EID, CFE_EVS_EventType_INFORMATION,
                      "CPU Hogging Indicator Disabled");
  }

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Reset the count of processor resets HS has performed -- and therefore RE-ARM HS's willingness
// to reset the processor, since the monitors compare ResetsPerformed against MaxResets. The
// counter lives in the CDS, so this writes through HS_SetCDSData and survives a reset.
I32 HS_ResetResetsPerformedCmd(HS_ResetResetsPerformedCmd_t *BufPtr)
{
  HS_AppData.CmdCount++;
  HS_SetCDSData(0, HS_AppData.CDSData.MaxResets);
  CFE_EVS_SendEvent(HS_RESET_RESETS_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Processor Resets Performed by HS Counter has been Reset");

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Set the maximum number of processor resets. HS'S ONLY COMMAND WITH A PAYLOAD.
//
// IT IS NOT RANGE CHECKED -- any uint16 is accepted, including 0 (HS will never reset) and 65535.
// And the event reports HS_AppData.CDSData.MaxResets rather than CmdPtr->MaxResets, which is the
// right choice: it reports what was STORED, so a failure inside HS_SetCDSData would show up in
// the event text rather than being masked by echoing the request back.
I32 HS_SetMaxResetsCmd(HS_SetMaxResetsCmd_t *BufPtr)
{
  HS_SetMaxResets_Payload_t *CmdPtr;

  HS_AppData.CmdCount++;
  CmdPtr = HS_GET_CMD_PAYLOAD(BufPtr, HS_SetMaxResetsCmd_t);

  HS_SetCDSData(HS_AppData.CDSData.ResetsPerformed, CmdPtr->MaxResets);

  CFE_EVS_SendEvent(HS_SET_MAX_RESETS_INF_EID, CFE_EVS_EventType_INFORMATION,
                    "Max Resets Performable by HS has been set to %d",
                    HS_AppData.CDSData.MaxResets);

  return CFE_SUCCESS;
}

/*******************************************************************************/
// Re-acquire all four table pointers. Four copies of Release / Manage / GetAddress that differ in
// three ways -- see the file header, which is where the content of this function actually is.
U0 HS_AcquirePointers()
{
  I32 Status;

  /*
  ** Release the table (AppMon)
  */
  CFE_TBL_ReleaseAddress(HS_AppData.AMTableHandle);

  /*
  ** Manage the table (AppMon)
  */
  CFE_TBL_Manage(HS_AppData.AMTableHandle);

  /*
  ** Get a pointer to the table (AppMon)
  */
  Status = CFE_TBL_GetAddress(&HS_AppData.AMTablePtr, HS_AppData.AMTableHandle);

  /*
  ** If there is a new table, refresh status (AppMon)
  */
  if (Status == CFE_TBL_INFO_UPDATED) {
    HS_AppMonStatusRefresh();
  }

  /*
  ** If Address acquisition fails and currently enabled, report and disable (AppMon)
  */
  if (Status < CFE_SUCCESS) {
    /*
    ** Only report and disable if enabled or the table was previously loaded (AppMon)
    */
    if (HS_AppData.AppMonLoaded == HS_State_ENABLED ||
        HS_AppData.CurrentAppMonState == HS_State_ENABLED) {
      CFE_EVS_SendEvent(HS_APPMON_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error getting AppMon Table address, RC=0x%08X, Application Monitoring Disabled",
                        Status);
      HS_AppData.CurrentAppMonState = HS_State_DISABLED;
      HS_AppData.AppMonLoaded = HS_State_DISABLED;
    }
  }
  /*
  ** Otherwise, mark that the table is loaded (AppMon)
  */
  else {
    HS_AppData.AppMonLoaded = HS_State_ENABLED;
  }

  /*
  ** Release the table (EventMon)
  */
  CFE_TBL_ReleaseAddress(HS_AppData.EMTableHandle);

  /*
  ** Manage the table (EventMon)
  */
  CFE_TBL_Manage(HS_AppData.EMTableHandle);

  /*
  ** Get a pointer to the table (EventMon)
  */
  Status = CFE_TBL_GetAddress(&HS_AppData.EMTablePtr, HS_AppData.EMTableHandle);

  // NO CFE_TBL_INFO_UPDATED ARM HERE, and that is the first of the three differences: a newly
  // loaded Event Monitor Table takes effect with the previous one's state.

  /*
  ** If Address acquisition fails and currently enabled, report and disable (EventMon)
  */
  if (Status < CFE_SUCCESS) {
    /*
    ** Only report and disable if enabled or the table was previously loaded (EventMon)
    */
    if (HS_AppData.EventMonLoaded == HS_State_ENABLED ||
        HS_AppData.CurrentEventMonState == HS_State_ENABLED) {
      CFE_EVS_SendEvent(HS_EVENTMON_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error getting EventMon Table address, RC=0x%08X, Event Monitoring Disabled",
                        Status);

      if (HS_AppData.CurrentEventMonState == HS_State_ENABLED) {
        // AND HERE `Status` STOPS MEANING "why did the EMT fail" -- see the file header.
        Status = CFE_SB_Unsubscribe(CFE_SB_ValueToMsgId(CFE_EVS_LONG_EVENT_MSG_MID),
                                    HS_AppData.EventPipe);

        if (Status != CFE_SUCCESS) {
          CFE_EVS_SendEvent(HS_BADEMT_LONG_UNSUB_EID, CFE_EVS_EventType_ERROR,
                            "Error Unsubscribing from long-format Events,RC=0x%08X", Status);
        }

        Status = CFE_SB_Unsubscribe(CFE_SB_ValueToMsgId(CFE_EVS_SHORT_EVENT_MSG_MID),
                                    HS_AppData.EventPipe);

        if (Status != CFE_SUCCESS) {
          CFE_EVS_SendEvent(HS_BADEMT_SHORT_UNSUB_EID, CFE_EVS_EventType_ERROR,
                            "Error Unsubscribing from short-format Events,RC=0x%08X", Status);
        }
      }

      HS_AppData.CurrentEventMonState = HS_State_DISABLED;
      HS_AppData.EventMonLoaded = HS_State_DISABLED;
    }
  }
  /*
  ** Otherwise, mark that the table is loaded (EventMon)
  */
  else {
    HS_AppData.EventMonLoaded = HS_State_ENABLED;
  }

  /*
  ** Release the table (MsgActs)
  */
  CFE_TBL_ReleaseAddress(HS_AppData.MATableHandle);

  /*
  ** Manage the table (MsgActs)
  */
  CFE_TBL_Manage(HS_AppData.MATableHandle);

  /*
  ** Get a pointer to the table (MsgActs)
  */
  Status = CFE_TBL_GetAddress(&HS_AppData.MATablePtr, HS_AppData.MATableHandle);

  /*
  ** If there is a new table, refresh status (MsgActs)
  */
  if (Status == CFE_TBL_INFO_UPDATED) {
    HS_MsgActsStatusRefresh();
  }

  /*
  ** If Address acquisition fails report and disable (MsgActs)
  */
  if (Status < CFE_SUCCESS) {
    /*
    ** To prevent redundant reporting, only report if enabled (MsgActs)
    */
    // THE SECOND DIFFERENCE: no `|| Loaded` here, so a disabled-but-loaded MAT fails silently.
    if (HS_AppData.MsgActsState == HS_State_ENABLED) {
      CFE_EVS_SendEvent(HS_MSGACTS_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error getting MsgActs Table address, RC=0x%08X", Status);
      HS_AppData.MsgActsState = HS_State_DISABLED;
    }
  }
  /*
  ** Otherwise, make sure it is enabled (MsgActs)
  */
  else {
    HS_AppData.MsgActsState = HS_State_ENABLED;
  }

  /*
  ** Release the table (ExeCount)
  */
  CFE_TBL_ReleaseAddress(HS_AppData.XCTableHandle);

  /*
  ** Manage the table (ExeCount)
  */
  CFE_TBL_Manage(HS_AppData.XCTableHandle);

  /*
  ** Get a pointer to the table (ExeCount)
  */
  Status = CFE_TBL_GetAddress(&HS_AppData.XCTablePtr, HS_AppData.XCTableHandle);

  /*
  ** If Address acquisition fails report and disable (ExeCount)
  */
  if (Status < CFE_SUCCESS) {
    /*
    ** To prevent redundant reporting, only report if enabled (ExeCount)
    */
    if (HS_AppData.ExeCountState == HS_State_ENABLED) {
      CFE_EVS_SendEvent(HS_EXECOUNT_GETADDR_ERR_EID, CFE_EVS_EventType_ERROR,
                        "Error getting ExeCount Table address, RC=0x%08X", Status);
      HS_AppData.ExeCountState = HS_State_DISABLED;
    }
  }
  /*
  ** Otherwise, make sure it is enabled (ExeCount)
  */
  else {
    HS_AppData.ExeCountState = HS_State_ENABLED;
  }
}

/*******************************************************************************/
// Refresh the application monitor's derived state from the AMT: clear the enable bitmap, zero
// every last-seen counter, and re-arm the countdowns of the entries that have an action.
//
// NOTE IT DOES NOT CHECK AMTablePtr FOR NULL, unlike HS_MonitorApplications which returns early
// when it is. HS_AcquirePointers calls this only on CFE_TBL_INFO_UPDATED -- a status that implies
// the pointer is good -- and HS_EnableAppMonCmd calls it with whatever the pointer happens to be.
// So an enable command issued while the AMT is unavailable dereferences a null pointer. Kept;
// the exercise drives the enable with a valid table, and the unguarded path is named here.
U0 HS_AppMonStatusRefresh()
{
  U32 TableIndex = 0;
  U32 EnableIndex = 0;

  /*
  ** Clear all AppMon Enable bits
  */
  for (EnableIndex = 0; EnableIndex <= (HS_MAX_MONITORED_APPS - 1) / HS_BITS_PER_APPMON_ENABLE;
       EnableIndex++) {
    HS_AppData.AppMonEnables[EnableIndex] = 0;
  }

  /*
  ** Set AppMon enable bits and reset Countups and Exec Counter comparisons
  */
  for (TableIndex = 0; TableIndex < HS_MAX_MONITORED_APPS; TableIndex++) {
    // EVERY SLOT, enabled or not -- see the file header on why that is what keeps a table load
    // from tripping a monitor on the next cycle.
    HS_AppData.AppMonLastExeCount[TableIndex] = 0;

    if (HS_AppData.AMTablePtr[TableIndex].CycleCount == 0 ||
        HS_AppData.AMTablePtr[TableIndex].ActionType == HS_AMTActType_NOACT) {
      HS_AppData.AppMonCheckInCountdown[TableIndex] = 0;
    } else {
      HS_AppData.AppMonCheckInCountdown[TableIndex] = HS_AppData.AMTablePtr[TableIndex].CycleCount;
      // `1 << 31` IS REACHABLE: HS_MAX_MONITORED_APPS is 32. Kept as NASA writes it.
      HS_AppData.AppMonEnables[TableIndex / HS_BITS_PER_APPMON_ENABLE] |=
          1 << TableIndex % HS_BITS_PER_APPMON_ENABLE;
    }
  }
}

/*******************************************************************************/
// Refresh the message actions' derived state: clear every cooldown, so a newly loaded MAT can
// fire immediately rather than inheriting the previous table's cooldowns.
//
// AND IT IS THE WHOLE REFRESH -- the MAT's EnableState comes straight out of the table and is
// never cached, unlike the AMT whose enables are mirrored into a bitmap.
U0 HS_MsgActsStatusRefresh()
{
  U32 TableIndex = 0;

  /*
  ** Clear all MsgActs Cooldowns
  */
  for (TableIndex = 0; TableIndex < HS_MAX_MSG_ACT_TYPES; TableIndex++) {
    HS_AppData.MsgActCooldown[TableIndex] = 0;
  }
}

#endif
