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

// 1:1 HolyC translation of cFE modules/evs/fsw/src/cfe_evs.c -- the PUBLIC API every other cFS
// module calls. CFE_EVS_SendEvent is here, and with this file translated it stops being a stub
// in the differential driver and starts being code: the first time an event this port sends
// goes through filtering, squelching, the local log and the real formatter.
//
// INCLUDE cfe_evs_global.HC, cfe_evs_utils.HC and cfe_evs_log.HC FIRST.
//
// THE THREE SendEvent FLAVOURS ARE VARIADIC, and each hands its implicit (argc, argv) straight
// to EVS_GenerateEventTelemetry where NASA hands it a va_list -- see the note at the top of
// cfe_evs_utils.HC for why that is the one extra parameter in the whole module.
#ifndef CFE_EVS_HC
#define CFE_EVS_HC
// cfe_evs_api_typedefs.h: the filter an application registers with. Note this is NOT
// EVS_BinFilter_t -- the internal record adds a Count and a pad, and CFE_EVS_Register copies
// field by field between them for exactly that reason.
class CFE_EVS_BinFilter_t
{
  U16 EventID; // Numerical event identifier
  U16 Mask;    // Binary filter mask
};

I32 CFE_EVS_Register(U8 *Filters, U16 NumEventFilters, U16 FilterScheme)
{
  U16 FilterLimit;
  U16 i;
  I32 Status;
  U32 AppID;
  CFE_EVS_BinFilter_t *AppFilters;
  EVS_AppData_t *AppDataPtr;

  // Query and verify the caller's AppID
  Status = EVS_GetCurrentContext(&AppDataPtr, &AppID);
  if (Status == CFE_SUCCESS) {
    // Clear and configure entry
    MemSet(AppDataPtr, 0, sizeof(EVS_AppData_t));

    // Verify filter arguments
    if (FilterScheme != CFE_EVS_EventFilter_BINARY) {
      Status = CFE_EVS_UNKNOWN_FILTER;
    } else if (NumEventFilters != 0 && Filters == NULL) {
      Status = CFE_ES_BAD_ARGUMENT;
    } else {
      // Initialize application event data
      AppDataPtr->ActiveFlag = TRUE;
      AppDataPtr->SquelchTokens = CFE_PLATFORM_EVS_MAX_APP_EVENT_BURST * 1000;
      EVS_SetTypes(AppDataPtr, CFE_PLATFORM_EVS_DEFAULT_TYPE_FLAG, TRUE);

      // Set limit for number of provided filters
      if (NumEventFilters < CFE_PLATFORM_EVS_MAX_EVENT_FILTERS) {
        FilterLimit = NumEventFilters;
      } else {
        FilterLimit = CFE_PLATFORM_EVS_MAX_EVENT_FILTERS;
        CFE_ES_WriteToSysLog("CFE_EVS_Register: Filter limit truncated\n");
      }

      if (Filters != NULL) {
        AppFilters = Filters;

        // Copy provided filters
        for (i = 0; i < FilterLimit; i++) {
          AppDataPtr->BinFilters[i].EventID = AppFilters[i].EventID;
          AppDataPtr->BinFilters[i].Mask = AppFilters[i].Mask;
          AppDataPtr->BinFilters[i].Count = 0;
        }
      }

      // Initialize remainder of filters as unused
      for (i = FilterLimit; i < CFE_PLATFORM_EVS_MAX_EVENT_FILTERS; i++) {
        AppDataPtr->BinFilters[i].EventID = CFE_EVS_FREE_SLOT;
        AppDataPtr->BinFilters[i].Mask = 0;
        AppDataPtr->BinFilters[i].Count = 0;
      }

      EVS_AppDataSetUsed(AppDataPtr, AppID);
    }
  }

  return Status;
}

I32 CFE_EVS_SendEvent(U16 EventID, U16 EventType, U8 *Spec, ...)
{
  I32 Status;
  U32 AppID;
  CFE_TIME_SysTime Time;
  EVS_AppData_t *AppDataPtr;

  if (Spec == NULL)
    return CFE_EVS_INVALID_PARAMETER;

  // Query and verify the caller's AppID
  Status = EVS_GetCurrentContext(&AppDataPtr, &AppID);
  if (Status == CFE_SUCCESS) {
    if (!EVS_AppDataIsMatch(AppDataPtr, AppID)) {
      // Handler for events from apps not registered with EVS
      Status = EVS_NotRegistered(AppDataPtr, AppID);
    } else if (EVS_IsFiltered(AppDataPtr, EventID, EventType) == FALSE) {
      if (EVS_CheckAndIncrementSquelchTokens(AppDataPtr) == TRUE) {
        // Get current spacecraft time
        Time = CFE_TIME_GetTime();

        // Send the event packets
        EVS_GenerateEventTelemetry(AppDataPtr, EventID, EventType, &Time, Spec, argc, argv);
      } else {
        Status = CFE_EVS_APP_SQUELCHED;
      }
    }
  }

  return Status;
}

I32 CFE_EVS_SendEventWithAppID(U16 EventID, U16 EventType, U32 AppID, U8 *Spec, ...)
{
  I32 Status = CFE_SUCCESS;
  CFE_TIME_SysTime Time;
  EVS_AppData_t *AppDataPtr;

  if (Spec == NULL)
    return CFE_EVS_INVALID_PARAMETER;

  AppDataPtr = EVS_GetAppDataByID(AppID);
  if (AppDataPtr == NULL) {
    Status = CFE_EVS_APP_ILLEGAL_APP_ID;
  } else if (!EVS_AppDataIsMatch(AppDataPtr, AppID)) {
    // Handler for events from apps not registered with EVS
    Status = EVS_NotRegistered(AppDataPtr, AppID);
  } else if (EVS_IsFiltered(AppDataPtr, EventID, EventType) == FALSE) {
    if (EVS_CheckAndIncrementSquelchTokens(AppDataPtr) == TRUE) {
      // Get current spacecraft time
      Time = CFE_TIME_GetTime();

      // Send the event packets
      EVS_GenerateEventTelemetry(AppDataPtr, EventID, EventType, &Time, Spec, argc, argv);
    } else {
      Status = CFE_EVS_APP_SQUELCHED;
    }
  }

  return Status;
}

I32 CFE_EVS_SendTimedEvent(CFE_TIME_SysTime Time, U16 EventID, U16 EventType, U8 *Spec,
                                    ...)
{
  I32 Status;
  U32 AppID;
  EVS_AppData_t *AppDataPtr;

  if (Spec == NULL)
    return CFE_EVS_INVALID_PARAMETER;

  // Query and verify the caller's AppID
  Status = EVS_GetCurrentContext(&AppDataPtr, &AppID);
  if (Status == CFE_SUCCESS) {
    if (!EVS_AppDataIsMatch(AppDataPtr, AppID)) {
      // Handler for events from apps not registered with EVS
      Status = EVS_NotRegistered(AppDataPtr, AppID);
    } else if (EVS_IsFiltered(AppDataPtr, EventID, EventType) == FALSE) {
      if (EVS_CheckAndIncrementSquelchTokens(AppDataPtr) == TRUE) {
        // Send the event packets
        EVS_GenerateEventTelemetry(AppDataPtr, EventID, EventType, &Time, Spec, argc, argv);
      } else {
        Status = CFE_EVS_APP_SQUELCHED;
      }
    }
  }

  return Status;
}

I32 CFE_EVS_ResetFilter(U16 EventID)
{
  I32 Status;
  EVS_BinFilter_t *FilterPtr = NULL;
  U32 AppID;
  EVS_AppData_t *AppDataPtr;

  // Query and verify the caller's AppID
  Status = EVS_GetCurrentContext(&AppDataPtr, &AppID);
  if (Status == CFE_SUCCESS) {
    if (!EVS_AppDataIsMatch(AppDataPtr, AppID)) {
      Status = CFE_EVS_APP_NOT_REGISTERED;
    } else {
      FilterPtr = EVS_FindEventID(EventID, AppDataPtr->BinFilters);

      if (FilterPtr != NULL)
        FilterPtr->Count = 0;
      else
        Status = CFE_EVS_EVT_NOT_REGISTERED;
    }
  }

  return Status;
}

I32 CFE_EVS_ResetAllFilters()
{
  I32 Status;
  U32 AppID;
  U32 i;
  EVS_AppData_t *AppDataPtr;

  // Query and verify the caller's AppID
  Status = EVS_GetCurrentContext(&AppDataPtr, &AppID);
  if (Status == CFE_SUCCESS) {
    if (!EVS_AppDataIsMatch(AppDataPtr, AppID)) {
      Status = CFE_EVS_APP_NOT_REGISTERED;
    } else {
      for (i = 0; i < CFE_PLATFORM_EVS_MAX_EVENT_FILTERS; i++)
        AppDataPtr->BinFilters[i].Count = 0;
    }
  }

  return Status;
}
#endif
