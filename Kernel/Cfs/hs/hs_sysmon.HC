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
// HEALTH & SAFETY'S SYSTEM MONITOR -- the 1:1 translation of NASA's fsw/src/hs_sysmon.c, 176
// lines and three functions. THE ONLY SOURCE IN THIS PORT THAT TALKS TO A DEVICE.
//
// ### WHAT IT DOES: READ CPU UTILISATION THROUGH THE PSP'S I/O DRIVER ABSTRACTION
//
// Five calls in sequence, each through CFE_PSP_IODriver_Command:
//
//   FindByName("linux_sysmon")          -> a module id, or "no device available"
//   SET_RUNNING, 1                      -> start it
//   LOOKUP_SUBSYSTEM, "aggregate"       -> a subsystem id (a POSITIVE RETURN, not an out-param)
//   LOOKUP_SUBCHANNEL, "cpu-load"       -> a subchannel id, same shape
//   ANALOG_IO_READ_CHANNELS, &RdWr      -> fills a 16-bit ADC code
//
// The three names come from hs_cfg.HC and the simulated driver in the differential answers to
// exactly those -- see its block comment on why answering any name would be worse than useless.
//
// ### THE LOOKUPS RETURN THEIR ANSWER AS A **POSITIVE STATUS**, WHICH IS WHY THE TESTS ARE `< 0`
//
// `StatusCode = CFE_PSP_IODriver_Command(..., LOOKUP_SUBSYSTEM, ...)` and then
// `if (StatusCode < 0)`. A subsystem id of 0 is therefore a SUCCESSFUL lookup, not a failure, and
// HS stores whatever came back. That is the opposite convention from every cFE call in this port,
// where a positive non-zero status is informational and the value arrives in an out-parameter --
// so a translation that tested `!= CFE_PSP_SUCCESS` here would reject every real id.
//
// AND A FAILED LOOKUP IS NOT FATAL. Either one failing writes 0 into the id and CARRIES ON, so HS
// starts with a device it cannot read a channel from, and HS_SysMonGetCpuUtilization's own
// `SysMonPspModuleId == 0` guard does not catch it -- the module id is still valid. The read
// simply fails every cycle and reports -1.
//
// ### NO DEVICE AT ALL IS A **SUCCESS**
//
// If FindByName fails, HS writes a syslog line -- "No system monitor device available, CPU usage
// will not be reported" -- and returns CFE_SUCCESS. So a board without a system monitor starts
// HS normally and reports no utilisation, which is the right call for a health app: refusing to
// start because you cannot measure CPU load would be worse than not measuring it.
//
// ### THE CONVERSION TRUNCATES TWICE AND HS DOES NOT ROUND
//
//     Value = ((Sample >> 8) * HS_CPU_UTILIZATION_MAX) / 0xFFFF;
//
// Sample is a 32-bit ADC code whose top 24 bits are used (`>> 8`), scaled to 0..10000. Both the
// shift and the divide truncate, so the round trip through the simulated driver is NOT the
// identity -- the exercise asserts what HS actually computes rather than what the input was,
// which is the only honest way to pin an ADC conversion.
//
// ### AND THE RETURN TYPE DISAGREES WITH THE DECLARATION -- UPSTREAM, AND KEPT
//
// `CFE_Status_t HS_SysMonGetCpuUtilization(void)` ends with `return Value;` where Value is an
// `int32` holding 0..10000 or -1. So the function is DECLARED as returning a cFE status and
// actually returns a utilisation. Its caller (hs_monitors.c) treats the result as a number, which
// is right; nothing treats it as a status. Harmless, and worth naming because a reader who
// trusts the declared type will look for CFE_SUCCESS and find 0 meaning "idle".
#ifndef HS_SYSMON_HC
#define HS_SYSMON_HC

// --- REQUIRED INCLUDE ORDER, PROVIDED BY THE DRIVER -------------------------------------------
//
// hs_cfg.HC, hs_msg.HC, hs_tbl.HC, hs_global.HC, hs_eventids.HC
//
// THIS UNIT DOES NOT INCLUDE ITS SIBLINGS -- docs/HOLYC_STRUCT_LIMITS.md #13.

// --- hs_sysmon.h's prototypes ----------------------------------------------------------------
I32 HS_SysMonInit();
U0 HS_SysMonCleanup();
I32 HS_SysMonGetCpuUtilization();

/*******************************************************************************/
// Initialise the system monitor: find the device, start it, look up the channel.
I32 HS_SysMonInit()
{
  CFE_PSP_IODriver_Location Location;
  I32 StatusCode;

  if (CFE_PSP_IODriver_FindByName(HS_SYSTEM_MONITOR_DEVICE, &HS_AppData.SysMonPspModuleId) !=
      CFE_PSP_SUCCESS) {
    CFE_ES_WriteToSysLog("%s(): No system monitor device available, CPU usage will not be reported\n",
                         "HS_SysMonInit");
    StatusCode = CFE_SUCCESS;
  } else {
    CFE_ES_WriteToSysLog("%s(): System Monitor using PSP device ID %08lx\n", "HS_SysMonInit",
                         HS_AppData.SysMonPspModuleId);

    Location.PspModuleId = HS_AppData.SysMonPspModuleId;
    Location.SubsystemId = 0;
    Location.SubchannelId = 0;

    if (CFE_PSP_IODriver_Command(&Location, CFE_PSP_IODriver_SET_RUNNING,
                                 CFE_PSP_IODriver_U32ARG(1)) != CFE_PSP_SUCCESS) {
      CFE_ES_WriteToSysLog("%s(): Unable to start device %08lx\n", "HS_SysMonInit",
                           HS_AppData.SysMonPspModuleId);
      StatusCode = CFE_STATUS_EXTERNAL_RESOURCE_FAIL;
    } else {
      /* find the subsystem */
      StatusCode = CFE_PSP_IODriver_Command(&Location, CFE_PSP_IODriver_LOOKUP_SUBSYSTEM,
                                            CFE_PSP_IODriver_CONST_STR(HS_SYSTEM_MONITOR_SUBSYSTEM_NAME));

      // `< 0`, NOT `!= CFE_PSP_SUCCESS`: the id IS the return value. See the header.
      if (StatusCode < 0) {
        CFE_ES_WriteToSysLog("%s(): Unable to find subsystem \'%s\'\n", "HS_SysMonInit",
                             HS_SYSTEM_MONITOR_SUBSYSTEM_NAME);
        HS_AppData.SysMonSubsystemId = 0;
      } else {
        HS_AppData.SysMonSubsystemId = StatusCode;
      }

      Location.SubsystemId = HS_AppData.SysMonSubsystemId;
      StatusCode = CFE_PSP_IODriver_Command(&Location, CFE_PSP_IODriver_LOOKUP_SUBCHANNEL,
                                            CFE_PSP_IODriver_CONST_STR(HS_SYSTEM_MONITOR_SUBCHANNEL_NAME));

      if (StatusCode < 0) {
        CFE_ES_WriteToSysLog("%s(): Unable to find channel \'%s\'\n", "HS_SysMonInit",
                             HS_SYSTEM_MONITOR_SUBCHANNEL_NAME);
        HS_AppData.SysMonSubchannelId = 0;
      } else {
        HS_AppData.SysMonSubchannelId = StatusCode;
      }

      /* return success to caller */
      StatusCode = CFE_SUCCESS;
    }
  }

  return StatusCode;
}

/*******************************************************************************/
// Stop the device on the way out. Guarded on the module id being non-zero, which is HS's
// "there is no device" sentinel -- and the only reason the simulated driver must never hand out 0.
U0 HS_SysMonCleanup()
{
  CFE_PSP_IODriver_Location Location;

  if (HS_AppData.SysMonPspModuleId != 0) {
    Location.PspModuleId = HS_AppData.SysMonPspModuleId;
    Location.SubsystemId = 0;
    Location.SubchannelId = 0;

    if (CFE_PSP_IODriver_Command(&Location, CFE_PSP_IODriver_SET_RUNNING,
                                 CFE_PSP_IODriver_U32ARG(0)) != CFE_PSP_SUCCESS) {
      CFE_ES_WriteToSysLog("%s(): Unable to stop device %08lx\n", "HS_SysMonCleanup",
                           HS_AppData.SysMonPspModuleId);
    }
  }
}

/*******************************************************************************/
// Read the CPU utilisation, 0..HS_CPU_UTILIZATION_MAX, or -1 if it cannot be read.
//
// NASA DECLARES THE Location AS A const WITH A DESIGNATED INITIALISER and the three ids come
// straight out of HS_AppData. HolyC has no designated initialisers and no aggregate initialiser
// on a local, so the three fields are assigned -- which is also what keeps this clear of
// docs/HOLYC_STRUCT_LIMITS.md #27, the 8-byte limit on a class local with an initialiser.
I32 HS_SysMonGetCpuUtilization()
{
  CFE_PSP_IODriver_Location Location;
  I32 Sample = 0;
  CFE_PSP_IODriver_AnalogRdWr RdWr;
  I32 StatusCode;
  I32 Value;

  Location.PspModuleId = HS_AppData.SysMonPspModuleId;
  Location.SubsystemId = HS_AppData.SysMonSubsystemId;
  Location.SubchannelId = HS_AppData.SysMonSubchannelId;
  RdWr.NumChannels = 1;
  RdWr.Samples = &Sample;

  if (HS_AppData.SysMonPspModuleId == 0) {
    /* No device to get info from */
    StatusCode = CFE_PSP_ERROR_NOT_IMPLEMENTED;
  } else {
    StatusCode = CFE_PSP_IODriver_Command(&Location, CFE_PSP_IODriver_ANALOG_IO_READ_CHANNELS,
                                          CFE_PSP_IODriver_VPARG(&RdWr));
  }

  if (StatusCode == CFE_PSP_SUCCESS) {
    Value = ((Sample >> 8) * HS_CPU_UTILIZATION_MAX) / 0xFFFF;
  } else {
    /* Unable to read value */
    Value = -1;
  }

  return Value;
}

#endif
