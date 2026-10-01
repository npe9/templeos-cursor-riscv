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

// 1:1 HolyC translation of cFE modules/evs/fsw/src/cfe_evs_utils.c, plus the five `static
// inline` accessors from cfe_evs_utils.h that its code uses.
//
// INCLUDE cfe_evs_global.HC FIRST. This file also needs, already in scope: the MSG accessors
// (cfe_msg_*.HC), the message-id helpers (cfe_sb_msgid.HC), CfsStr.HC for StrPrintNV, and
// OSAL's clock arithmetic from the driver or the kernel.
//
// THE VARIADIC SEAM IS HERE, and it is the one place in this translation where a FORMATTED
// STRING enters the differential comparison rather than being left outside it.
//
// EVS_GenerateEventTelemetry formats the event text with vsnprintf into a 122-byte payload and
// marks truncation with '$'. That text is the packet, so there is nothing to leave out: either
// the translation formats identically to C or the transcript says so. NASA's signature takes a
// `va_list`; HolyC has no such type, but a HolyC variadic function receives an implicit
// (argc, argv) pair -- which is exactly the triple StrPrintNV was written to take, and the
// reason it follows C's conversions rather than TempleOS's. So the parameter becomes the pair:
//
//     C:      ..., const char *MsgSpec, va_list ArgPtr)
//     HolyC:  ..., U8 *MsgSpec, I64 nargs, I64 *args)
//
// One extra parameter, recorded in check_signatures.py's DEVIATIONS with this reason.
#ifndef CFE_EVS_UTILS_HC
#define CFE_EVS_UTILS_HC
#include "../CfsStr.HC"
// OS_time_t and OS_MAX_API_NAME. The declarations only: OSAL's clock implementation reaches
// OS_GetLocalTime_Impl and the error-name tables, and this gate is about EVS.
#include "../osal/os_shared_clock.HC"
#include "../osal/osconfig.HC"
// --- what the layers around EVS provide -------------------------------------------------------
// ES, PSP and TIME. In a built port these are the translated modules; the differential driver
// supplies recording stubs, the same arrangement fs and ta have.
I32 CFE_ES_AppID_ToIndex(U32 AppID, U32 *Idx);
I32 CFE_ES_GetAppID(U32 *AppIdPtr);
I32 CFE_ES_GetAppIDByName(U32 *AppIdPtr, U8 *AppName);
I32 CFE_ES_GetAppName(U8 *AppName, U32 AppId, I64 BufferLength);
U32 CFE_PSP_GetSpacecraftId();
U32 CFE_PSP_GetProcessorId();
U0 CFE_PSP_GetTime(OS_time_t *LocalTime);
I32 CFE_TIME_Print(U8 *PrintBuffer, CFE_TIME_SysTime TimeToPrint);
I32 CFE_SB_TransmitMsg(CFE_MSG_Message *MsgPtr, Bool IsOrigination);
// OSAL. OS_TimeSubtract and OS_TimeGetTotalMilliseconds are translated in osapi_clock.HC; the
// mutex and OS_printf likewise. Declared rather than included, for the reason fs records: this
// gate is about EVS, and OSAL has a gate of its own.
I32 OS_MutSemTake(U32 sem_id);
I32 OS_MutSemGive(U32 sem_id);
U0 OS_printf(U8 *String, ...);
OS_time_t OS_TimeSubtract(OS_time_t time1, OS_time_t time2);
I64 OS_TimeGetTotalMilliseconds(OS_time_t tm);
// Defined in cfe_evs_task.c, which is the last of EVS's sources to be translated. It is the
// only thing this file needs from there, and the driver supplies it until then.
Bool CFE_EVS_GetTypeEnable(U16 EventType);
// Defined in cfe_evs_log.c, included after this file in NASA's build order but before it here,
// so this declaration is what lets EVS_GenerateEventTelemetry name it.
U0 EVS_AddLog(CFE_EVS_LongEventTlm_t *EVS_PktPtr);
// Local Function Prototypes -- NASA's own, in NASA's place.
U0 EVS_SendViaPorts(CFE_EVS_LongEventTlm_t *EVS_PktPtr);
U0 EVS_OutputPort(U8 PortNum, U8 *Message);
// THIS PROTOTYPE IS LOAD-BEARING, and not for the usual reason. EVS_SendEvent is defined at the
// bottom of this file and called from four places above it, and a HolyC call to a function the
// compiler has not seen yet CANNOT KNOW IT IS VARIADIC: the call site packs no (argc, argv), and
// the callee then reads whatever the ABI left in those registers. Measured, with the prototype
// removed, in a four-argument call: argc came out as the last ARGUMENT's value and argv as a
// stale pointer, which here reached StrPrintNV as nargs=1 with args=NULL and faulted on a load
// from address 0. NASA declares it in cfe_evs_utils.h, so this is 1:1 either way -- but it is
// the declaration whose absence is silent. docs/HOLYC_STRUCT_LIMITS.md #10.
I32 EVS_SendEvent(U16 EventID, U16 EventType, U8 *Spec, ...);
// --- cfe_evs_utils.h: the five static inline accessors -----------------------------------------
// A slot is in use when its AppID is not the undefined resource id. CFE_RESOURCEID_* are macros
// over the SIMPLE resourceid variant, where the id is a bare U32 -- see cfe_resourceid.HC.
// CFE_RESOURCEID_TEST_DEFINED(id) is CFE_ResourceId_IsDefined(CFE_RESOURCEID_UNWRAP(id)), and
// UNWRAP is the identity with the SIMPLE resourceid variant this port uses (cfe_resourceid.HC).
Bool EVS_AppDataIsUsed(EVS_AppData_t *AppDataPtr)
{
  return CFE_ResourceId_IsDefined(AppDataPtr->AppID);
}

U32 EVS_AppDataGetID(EVS_AppData_t *AppDataPtr)
{
  return AppDataPtr->AppID;
}

U0 EVS_AppDataSetUsed(EVS_AppData_t *AppDataPtr, U32 AppID)
{
  AppDataPtr->AppID = AppID;
}

U0 EVS_AppDataSetFree(EVS_AppData_t *AppDataPtr)
{
  // CFE_ES_APPID_UNDEFINED is CFE_ES_APPID_C(CFE_RESOURCEID_UNDEFINED); the wrap is the
  // identity here.
  AppDataPtr->AppID = CFE_RESOURCEID_UNDEFINED;
}

// Note the NULL check: every caller may hold a pointer that EVS_GetAppDataByID returned as
// NULL for an out-of-range id.
Bool EVS_AppDataIsMatch(EVS_AppData_t *AppDataPtr, U32 AppID)
{
  return AppDataPtr != NULL && CFE_ResourceId_Equal(AppDataPtr->AppID, AppID);
}
// --- cfe_evs_utils.c ---------------------------------------------------------------------------
EVS_AppData_t *EVS_GetAppDataByID(U32 AppID)
{
  U32 AppIndex;
  EVS_AppData_t *AppDataPtr;

  if (CFE_ES_AppID_ToIndex(AppID, &AppIndex) == CFE_SUCCESS &&
      AppIndex < CFE_PLATFORM_ES_MAX_APPLICATIONS) {
    AppDataPtr = &CFE_EVS_Global.AppData[AppIndex];
  } else {
    AppDataPtr = NULL;
  }

  return AppDataPtr;
}

I32 EVS_GetCurrentContext(EVS_AppData_t **AppDataOut, U32 *AppIDOut)
{
  U32 AppID;
  EVS_AppData_t *AppDataPtr;
  I32 Status;

  // Get the caller's AppID
  Status = CFE_ES_GetAppID(&AppID);
  if (Status == CFE_SUCCESS) {
    AppDataPtr = EVS_GetAppDataByID(AppID);
  } else {
    AppDataPtr = NULL;
  }

  if (AppDataPtr == NULL) {
    // use EVS error/status code
    Status = CFE_EVS_APP_ILLEGAL_APP_ID;
  }

  if (AppIDOut)
    *AppIDOut = AppID;
  if (AppDataOut)
    *AppDataOut = AppDataPtr;

  return Status;
}

I32 EVS_GetApplicationInfo(EVS_AppData_t **AppDataOut, U8 *pAppName)
{
  I32 Status;
  U32 AppID;
  EVS_AppData_t *AppDataPtr;

  Status = CFE_ES_GetAppIDByName(&AppID, pAppName);
  if (Status != CFE_SUCCESS) {
    AppDataPtr = NULL;
  } else {
    AppDataPtr = EVS_GetAppDataByID(AppID);
    if (AppDataPtr == NULL) {
      // should not happen - it means the CFE_ES_GetAppIDByName()
      // returned a success code with an AppID which was in subsequently
      // not accepted by CFE_ES_AppID_ToIndex()
      Status = CFE_EVS_APP_ILLEGAL_APP_ID;
    } else if (!EVS_AppDataIsMatch(AppDataPtr, AppID)) {
      // Avoid outputting a bad pointer
      AppDataPtr = NULL;
      Status = CFE_EVS_APP_NOT_REGISTERED;
    }
  }

  *AppDataOut = AppDataPtr;
  return Status;
}

I32 EVS_NotRegistered(EVS_AppData_t *AppDataPtr, U32 CallerID)
{
  U8 AppName[OS_MAX_API_NAME];

  // Send only one "not registered" event per application
  if (!CFE_ResourceId_Equal(AppDataPtr->UnregAppID, CallerID)) {
    // Increment count of "not registered" applications
    CFE_EVS_Global.EVS_TlmPkt.Payload.UnregisteredAppCounter++;

    // Indicate that "not registered" event has been sent for this app
    AppDataPtr->UnregAppID = CallerID;

    // Get the name of the "not registered" app
    CFE_ES_GetAppName(AppName, CallerID, OS_MAX_API_NAME);

    // Send the "not registered" event
    EVS_SendEvent(CFE_EVS_ERR_UNREGISTERED_EVS_APP, CFE_EVS_EventType_ERROR,
                  "App %s not registered with Event Services. Unable to send event.", AppName);

    // Write the "not registered" info to the system log
    CFE_ES_WriteToSysLog(
        "EVS_NotRegistered: App %s not registered with Event Services. Unable to send event.\n",
        AppName);
  }

  return CFE_EVS_APP_NOT_REGISTERED;
}

Bool EVS_IsFiltered(EVS_AppData_t *AppDataPtr, U16 EventID, U16 EventType)
{
  EVS_BinFilter_t *FilterPtr;
  Bool Filtered = FALSE;
  U8 AppName[OS_MAX_API_NAME];

  if (AppDataPtr->ActiveFlag == FALSE) {
    // All events are disabled for this application
    Filtered = TRUE;
  } else {
    Filtered = !CFE_EVS_GetTypeEnable(EventType);
  }

  // Is this type of event enabled for this application?
  if (Filtered == FALSE) {
    FilterPtr = EVS_FindEventID(EventID, AppDataPtr->BinFilters);

    // Does this event ID have an event filter table entry?
    if (FilterPtr != NULL) {
      if ((FilterPtr->Mask & FilterPtr->Count) != 0) {
        // This iteration of the event ID is filtered
        Filtered = TRUE;
      }

      if (FilterPtr->Count < CFE_EVS_MAX_FILTER_COUNT) {
        // Maintain event iteration count
        FilterPtr->Count++;

        // Is it time to lock this filter?
        if (FilterPtr->Count == CFE_EVS_MAX_FILTER_COUNT) {
          CFE_ES_GetAppName(AppName, EVS_AppDataGetID(AppDataPtr), OS_MAX_API_NAME);

          EVS_SendEvent(CFE_EVS_FILTER_MAX_EID, CFE_EVS_EventType_INFORMATION,
                        "Max filter count reached, AppName = %s, EventID = 0x%08x: Filter locked "
                        "until reset",
                        AppName, EventID);
        }
      }
    }
  }

  return Filtered;
}

Bool EVS_CheckAndIncrementSquelchTokens(EVS_AppData_t *AppDataPtr)
{
  Bool NotSquelched = TRUE;
  Bool SendSquelchEvent = FALSE;
  OS_time_t CurrentTime;
  I64 DeltaTimeMs;
  I64 CreditCount;
  U8 AppName[OS_MAX_API_NAME];
  // NASA declares these three `const int32` at block scope, initialised from the global. HolyC
  // has no `const`, and the values still have to be computed before the first use.
  I32 UPPER_THRESHOLD;
  I32 LOWER_THRESHOLD;
  I32 EVENT_COST;

  CurrentTime.ticks = 0; // `OS_time_t CurrentTime = {0}` in the C

  // Set maximum token credits to burst size
  UPPER_THRESHOLD = CFE_EVS_Global.EVS_EventBurstMax * 1000;
  // Set lower threshold to stop decrementing
  // Make this -CFE_PLATFORM_EVS_MAX_APP_EVENT_BURST to add some hysteresis
  // Events will resume (CFE_PLATFORM_EVS_MAX_APP_EVENT_BURST /
  // CFE_PLATFORM_EVS_APP_EVENTS_PER_SEC + 1 / CFE_PLATFORM_EVS_APP_EVENTS_PER_SEC) seconds
  // after flooding stops if saturated
  LOWER_THRESHOLD = -CFE_EVS_Global.EVS_EventBurstMax * 1000;
  // Set this to 1000 to avoid integer division while computing CreditCount
  EVENT_COST = 1000;

  if (CFE_EVS_Global.EVS_EventBurstMax != 0) {
    // We use a timer here since configurations are not guaranteed to send EVS HK wakeups at 1Hz
    // Use a non-settable timer to prevent this from breaking w/ time changes
    OS_MutSemTake(CFE_EVS_Global.EVS_SharedDataMutexID);
    CFE_PSP_GetTime(&CurrentTime);
    DeltaTimeMs = OS_TimeGetTotalMilliseconds(
        OS_TimeSubtract(CurrentTime, AppDataPtr->LastSquelchCreditableTime));

    // Calculate how many tokens to credit in elapsed time since last creditable event
    CreditCount = DeltaTimeMs * CFE_PLATFORM_EVS_APP_EVENTS_PER_SEC;

    // Don't immediately credit < 1 event worth of credits; defer until
    // enough time that CreditCount > EVENT_COST
    //
    // This prevents condition where credits would creep down slowly
    // through the range which squelch event messages are emitted causing
    // those events to be spammed instead, defeating the suppression.
    if (CreditCount >= EVENT_COST) {
      // Update last squelch returned time if we credited any tokens
      AppDataPtr->LastSquelchCreditableTime = CurrentTime;

      // Add Credits, to a maximum of UPPER_THRESHOLD
      // Shouldn't rollover, as calculations are done in int64 space due to
      // promotion rules then bounded before demotion
      if (AppDataPtr->SquelchTokens + CreditCount > UPPER_THRESHOLD)
        AppDataPtr->SquelchTokens = UPPER_THRESHOLD;
      else
        AppDataPtr->SquelchTokens += CreditCount;
    }

    if (AppDataPtr->SquelchTokens <= 0) {
      if (AppDataPtr->SquelchedCount < CFE_EVS_MAX_SQUELCH_COUNT)
        AppDataPtr->SquelchedCount++;
      NotSquelched = FALSE;

      // Send squelch event message if cross threshold. This has to be a
      // range between -EVENT_COST and 0 due to non-whole event-cost credits being
      // returned allowing 0 to be skipped over. This is solved by
      // checking a range and ensuring EVENT_COST credits are returned at minimum.
      if (AppDataPtr->SquelchTokens > -EVENT_COST && CreditCount < EVENT_COST) {
        // Set flag and send event later, since we still own mutex
        SendSquelchEvent = TRUE;
      }
    }

    // Subtract event cost
    if (AppDataPtr->SquelchTokens - EVENT_COST < LOWER_THRESHOLD)
      AppDataPtr->SquelchTokens = LOWER_THRESHOLD;
    else
      AppDataPtr->SquelchTokens -= EVENT_COST;

    OS_MutSemGive(CFE_EVS_Global.EVS_SharedDataMutexID);

    if (SendSquelchEvent) {
      CFE_ES_GetAppName(AppName, EVS_AppDataGetID(AppDataPtr), OS_MAX_API_NAME);
      EVS_SendEvent(CFE_EVS_SQUELCHED_ERR_EID, CFE_EVS_EventType_ERROR,
                    "Events squelched, AppName = %s", AppName);
    }
  }
  return NotSquelched;
}

EVS_BinFilter_t *EVS_FindEventID(U16 EventID, EVS_BinFilter_t *FilterArray)
{
  U32 i;

  for (i = 0; i < CFE_PLATFORM_EVS_MAX_EVENT_FILTERS; i++) {
    if (FilterArray[i].EventID == EventID)
      return &FilterArray[i];
  }

  return NULL;
}

U0 EVS_SetTypes(EVS_AppData_t *AppDataPtr, U8 BitMask, Bool State)
{
  I64 Index;  // size_t
  U8 EventBit;

  EventBit = 1;
  Index = 0;

  if (AppDataPtr != NULL) {
    // NASA bounds this with sizeof(AppDataPtr->EventTypesActive). `sizeof` of a member reached
    // through a POINTER does not parse in HolyC (HOLYC_STRUCT_LIMITS.md #9), so the count is
    // named -- it is the same #define the member declaration uses, and a `bool` is one byte on
    // both sides, which check_padding is what keeps true.
    while (EventBit <= BitMask && Index < CFE_EVS_NUM_EVENT_TYPES) {
      if ((BitMask & EventBit) != 0)
        AppDataPtr->EventTypesActive[Index] = State;
      EventBit <<= 1;
      ++Index;
    }
  }
}

U8 EVS_EventArrayToBitMask(EVS_AppData_t *AppDataPtr)
{
  U8 BitMask = 0;
  I64 i;

  if (AppDataPtr != NULL) {
    for (i = 0; i < CFE_EVS_NUM_EVENT_TYPES; i++) {
      if (AppDataPtr->EventTypesActive[i]) {
        // Set bit i of BitMask if index i in array is true
        BitMask |= 1 << i;
      }
    }
  }

  return BitMask;
}

// The `va_list ArgPtr` of NASA's signature is the (nargs, args) pair here -- see the note at
// the top of this file.
U0 EVS_GenerateEventTelemetry(EVS_AppData_t *AppDataPtr, U16 EventID, U16 EventType,
                              CFE_TIME_SysTime *TimeStamp, U8 *MsgSpec, I64 nargs, I64 *args)
{
  // The "long" flavor is always generated, as this is what is logged
  CFE_EVS_LongEventTlm_t LongEventTlm;
  // The "short" flavor is only generated if selected
  CFE_EVS_ShortEventTlm_t ShortEventTlm;
  I64 ExpandedLength;
  Bool IsTruncated;

  MemSet(&LongEventTlm, 0, sizeof(CFE_EVS_LongEventTlm_t));
  MemSet(&ShortEventTlm, 0, sizeof(CFE_EVS_ShortEventTlm_t));

  // Initialize EVS event packets
  CFE_MSG_Init(&LongEventTlm.TelemetryHeader.Msg, CFE_SB_ValueToMsgId(CFE_EVS_LONG_EVENT_MSG_MID),
               sizeof(CFE_EVS_LongEventTlm_t));
  LongEventTlm.Payload.PacketID.EventID = EventID;
  LongEventTlm.Payload.PacketID.EventType = EventType;

  // vsnprintf() returns the total expanded length of the formatted string
  // vsnprintf() copies and zero terminates portion that fits in the buffer
  ExpandedLength = StrPrintNV(LongEventTlm.Payload.Message, CFE_MISSION_EVS_MAX_MESSAGE_LENGTH,
                              MsgSpec, nargs, args);

  // If vsnprintf is bigger than message size, mark with truncation character
  // Note negative returns (error from vsnprintf) will just leave the message as-is
  if (ExpandedLength >= CFE_MISSION_EVS_MAX_MESSAGE_LENGTH) {
    // Mark character before zero terminator to indicate truncation
    LongEventTlm.Payload.Message[CFE_MISSION_EVS_MAX_MESSAGE_LENGTH - 2] = CFE_EVS_MSG_TRUNCATED;
    IsTruncated = TRUE;
  } else {
    IsTruncated = FALSE;
  }

  // Obtain task and system information
  CFE_ES_GetAppName(LongEventTlm.Payload.PacketID.AppName, EVS_AppDataGetID(AppDataPtr),
                    CFE_MISSION_MAX_API_LEN);
  LongEventTlm.Payload.PacketID.SpacecraftID = CFE_PSP_GetSpacecraftId();
  LongEventTlm.Payload.PacketID.ProcessorID = CFE_PSP_GetProcessorId();

  // Set the packet timestamp
  CFE_MSG_SetMsgTime(&LongEventTlm.TelemetryHeader.Msg, *TimeStamp);

  // Write event to the event log
  EVS_AddLog(&LongEventTlm);

  // Send event via selected ports
  EVS_SendViaPorts(&LongEventTlm);

  if (CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode == CFE_EVS_MsgFormat_LONG) {
    // Send long event via SoftwareBus
    CFE_SB_TransmitMsg(&LongEventTlm.TelemetryHeader.Msg, TRUE);
  } else if (CFE_EVS_Global.EVS_TlmPkt.Payload.MessageFormatMode == CFE_EVS_MsgFormat_SHORT) {
    // Initialize the short format event message from data that was already
    // gathered in the long format message (short format is a subset)
    //
    // This goes out on a separate message ID.
    CFE_MSG_Init(&ShortEventTlm.TelemetryHeader.Msg,
                 CFE_SB_ValueToMsgId(CFE_EVS_SHORT_EVENT_MSG_MID),
                 sizeof(CFE_EVS_ShortEventTlm_t));
    CFE_MSG_SetMsgTime(&ShortEventTlm.TelemetryHeader.Msg, *TimeStamp);
    ShortEventTlm.Payload.PacketID = LongEventTlm.Payload.PacketID;
    CFE_SB_TransmitMsg(&ShortEventTlm.TelemetryHeader.Msg, TRUE);
  }

  // Serialize access to event log control variables
  OS_MutSemTake(CFE_EVS_Global.EVS_SharedDataMutexID);

  // Increment message send counters (prevent rollover)
  if (CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter < CFE_EVS_MAX_EVENT_SEND_COUNT)
    CFE_EVS_Global.EVS_TlmPkt.Payload.MessageSendCounter++;

  if (AppDataPtr->EventCount < CFE_EVS_MAX_EVENT_SEND_COUNT)
    AppDataPtr->EventCount++;

  if (IsTruncated)
    CFE_EVS_Global.EVS_TlmPkt.Payload.MessageTruncCounter++;

  OS_MutSemGive(CFE_EVS_Global.EVS_SharedDataMutexID);
}

// Internal helper routine only, not part of API.
//
// This routine sends a string event message out all enabled output ports
U0 EVS_SendViaPorts(CFE_EVS_LongEventTlm_t *EVS_PktPtr)
{
  U8 PortMessage[CFE_EVS_MAX_PORT_MSG_LENGTH];
  U8 TimeBuffer[CFE_TIME_PRINTED_STRING_SIZE];
  CFE_TIME_SysTime PktTime;

  PktTime.Seconds = 0; // `CFE_TIME_SysTime_t PktTime = {0}` in the C
  PktTime.Subseconds = 0;

  CFE_MSG_GetMsgTime(&EVS_PktPtr->TelemetryHeader.Msg, &PktTime);
  CFE_TIME_Print(TimeBuffer, PktTime);

  StrPrintN(PortMessage, CFE_EVS_MAX_PORT_MSG_LENGTH, "%s %u/%u/%s %u: %s", TimeBuffer,
            EVS_PktPtr->Payload.PacketID.SpacecraftID, EVS_PktPtr->Payload.PacketID.ProcessorID,
            EVS_PktPtr->Payload.PacketID.AppName, EVS_PktPtr->Payload.PacketID.EventID,
            EVS_PktPtr->Payload.Message);

  if (CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort & CFE_EVS_PORT1_BIT) {
    // Send string event out port #1
    EVS_OutputPort(1, PortMessage);
  }

  if (CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort & CFE_EVS_PORT2_BIT) {
    // Send string event out port #2
    EVS_OutputPort(2, PortMessage);
  }

  if (CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort & CFE_EVS_PORT3_BIT) {
    // Send string event out port #3
    EVS_OutputPort(3, PortMessage);
  }

  if (CFE_EVS_Global.EVS_TlmPkt.Payload.OutputPort & CFE_EVS_PORT4_BIT) {
    // Send string event out port #4
    EVS_OutputPort(4, PortMessage);
  }
}

// Internal helper routine only, not part of API.
U0 EVS_OutputPort(U8 PortNum, U8 *Message)
{
  OS_printf("EVS Port%u %s\n", PortNum, Message);
}

I32 EVS_SendEvent(U16 EventID, U16 EventType, U8 *Spec, ...)
{
  CFE_TIME_SysTime Time;
  EVS_AppData_t *AppDataPtr;

  // Must check that EVS_AppID is valid, which can happen if this is called
  // by some other thread before CFE_EVS_TaskInit() runs
  AppDataPtr = EVS_GetAppDataByID(CFE_EVS_Global.EVS_AppID);

  // Unlikely, but possible that an EVS event filter was added by command
  // Note that we do not squelch events coming from EVS to prevent event recursion,
  // and EVS is assumed to be "well-behaved"
  if (EVS_AppDataIsMatch(AppDataPtr, CFE_EVS_Global.EVS_AppID) &&
      EVS_IsFiltered(AppDataPtr, EventID, EventType) == FALSE) {
    // Get current spacecraft time
    Time = CFE_TIME_GetTime();

    // Send the event packets. `va_start`/`va_end` have no HolyC equivalent and need none: a
    // variadic function receives argc and argv already.
    EVS_GenerateEventTelemetry(AppDataPtr, EventID, EventType, &Time, Spec, argc, argv);
  }

  return CFE_SUCCESS;
}

Bool EVS_IsInvalidBitMask(U32 BitMask, U16 CommandCode)
{
  if (BitMask == 0x0 || BitMask > CFE_EVS_ALL_EVENT_TYPES_MASK) {
    EVS_SendEvent(CFE_EVS_ERR_INVALID_BITMASK_EID, CFE_EVS_EventType_ERROR,
                  "Bit Mask = 0x%08x out of range: CC = %u", BitMask, CommandCode);
    return TRUE;
  }

  return FALSE;
}
#endif
