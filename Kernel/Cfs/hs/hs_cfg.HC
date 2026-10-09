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
// HEALTH & SAFETY'S CONFIGURATION -- the 1:1 translation of NASA's fsw/inc/hs_internal_cfg.h,
// fsw/inc/hs_interface_cfg.h, fsw/inc/hs_perfids.h and fsw/src/hs_version.h, with every
// token-pasted name resolved to its value (HolyC has no `##`; the values were read out of the
// preprocessor, not counted by hand).
//
// ### HS IS THE FIRST APP IN THIS PORT THAT NEEDS SIMULATED **HARDWARE**
//
// MD reads memory, MM writes it, CS checksums it, LC compares it and HK copies it -- all of that
// needs a simulated memory window and nothing else. HS needs two DEVICES:
//
//   a WATCHDOG TIMER        CFE_PSP_WatchdogEnable / WatchdogSet / WatchdogService
//   an I/O DRIVER           CFE_PSP_IODriver_FindByName / IODriver_Command, for CPU utilisation
//
// and the three names below are what aim the second one:
//
//   HS_SYSTEM_MONITOR_DEVICE           "linux_sysmon"
//   HS_SYSTEM_MONITOR_SUBSYSTEM_NAME   "aggregate"
//   HS_SYSTEM_MONITOR_SUBCHANNEL_NAME  "cpu-load"
//
// The simulated driver answers to exactly those, so HS's CONFIGURED path is the one exercised --
// a simulation that answered to any name would pass while a misconfigured mission would not.
//
// ### THE WATCHDOG TIMEOUT IS 10,000 ms AND THE WAKEUP TIMEOUT IS 1,200 ms
//
// So HS expects to be woken roughly eight times per watchdog period, and
// HS_POST_PROCESSING_DELAY is **0** -- there is no sleep between finishing a cycle and petting
// the dog. If the wakeup message stops arriving, HS_WAKEUP_TIMEOUT is what eventually lets the
// main loop run its maintenance anyway; if HS itself stops, the watchdog expires and the board
// resets. That is the whole safety argument of the app, in two numbers.
//
// ### AND HS_MAX_RESTART_ACTIONS IS 3, STORED IN THE CDS AS A PAIR
//
// HS counts how many times it has restarted the processor and refuses past the limit, and it
// keeps the count in the critical data store as a VALUE AND ITS BITWISE COMPLEMENT (HS_CDSData_t
// in hs_global.HC). Three is the shipped maximum, and the complement is how HS notices a
// half-written CDS rather than trusting it.
#ifndef HS_CFG_HC
#define HS_CFG_HC

// --- hs_interface_cfg.h: the sizes a mission's ground system has to agree with ---------------
#define DEFAULT_HS_INTERFACE_MAX_MONITORED_APPS   32
#define HS_MAX_MONITORED_APPS                     DEFAULT_HS_INTERFACE_MAX_MONITORED_APPS
#define DEFAULT_HS_INTERFACE_MAX_MONITORED_EVENTS 16
#define HS_MAX_MONITORED_EVENTS                   DEFAULT_HS_INTERFACE_MAX_MONITORED_EVENTS
#define DEFAULT_HS_INTERFACE_MAX_EXEC_CNT_SLOTS   32
#define HS_MAX_EXEC_CNT_SLOTS                     DEFAULT_HS_INTERFACE_MAX_EXEC_CNT_SLOTS
#define DEFAULT_HS_INTERFACE_MAX_MSG_ACT_TYPES    8
#define HS_MAX_MSG_ACT_TYPES                      DEFAULT_HS_INTERFACE_MAX_MSG_ACT_TYPES
#define DEFAULT_HS_INTERFACE_MAX_MSG_ACT_SIZE     16
#define HS_MAX_MSG_ACT_SIZE                       DEFAULT_HS_INTERFACE_MAX_MSG_ACT_SIZE

// --- hs_internal_cfg.h -----------------------------------------------------------------------
#define DEFAULT_HS_WATCHDOG_TIMEOUT_VALUE               10000
#define HS_WATCHDOG_TIMEOUT_VALUE                       DEFAULT_HS_WATCHDOG_TIMEOUT_VALUE
#define DEFAULT_HS_POST_PROCESSING_DELAY                0
#define HS_POST_PROCESSING_DELAY                        DEFAULT_HS_POST_PROCESSING_DELAY
#define DEFAULT_HS_WAKEUP_TIMEOUT                       1200
#define HS_WAKEUP_TIMEOUT                               DEFAULT_HS_WAKEUP_TIMEOUT
#define DEFAULT_HS_CPU_ALIVE_STRING                     "."
#define HS_CPU_ALIVE_STRING                             DEFAULT_HS_CPU_ALIVE_STRING
#define DEFAULT_HS_CPU_ALIVE_PERIOD                     5
#define HS_CPU_ALIVE_PERIOD                             DEFAULT_HS_CPU_ALIVE_PERIOD
#define DEFAULT_HS_MAX_RESTART_ACTIONS                  3
#define HS_MAX_RESTART_ACTIONS                          DEFAULT_HS_MAX_RESTART_ACTIONS
#define DEFAULT_HS_CMD_PIPE_DEPTH                       12
#define HS_CMD_PIPE_DEPTH                               DEFAULT_HS_CMD_PIPE_DEPTH
#define DEFAULT_HS_EVENT_PIPE_DEPTH                     32
#define HS_EVENT_PIPE_DEPTH                             DEFAULT_HS_EVENT_PIPE_DEPTH
#define DEFAULT_HS_WAKEUP_PIPE_DEPTH                    1
#define HS_WAKEUP_PIPE_DEPTH                            DEFAULT_HS_WAKEUP_PIPE_DEPTH
#define DEFAULT_HS_RESET_TASK_DELAY                     50
#define HS_RESET_TASK_DELAY                             DEFAULT_HS_RESET_TASK_DELAY
#define DEFAULT_HS_STARTUP_SYNC_TIMEOUT                 65000
#define HS_STARTUP_SYNC_TIMEOUT                         DEFAULT_HS_STARTUP_SYNC_TIMEOUT
#define DEFAULT_HS_AMT_FILENAME                         "/cf/hs_amt.tbl"
#define HS_AMT_FILENAME                                 DEFAULT_HS_AMT_FILENAME
#define DEFAULT_HS_EMT_FILENAME                         "/cf/hs_emt.tbl"
#define HS_EMT_FILENAME                                 DEFAULT_HS_EMT_FILENAME
#define DEFAULT_HS_XCT_FILENAME                         "/cf/hs_xct.tbl"
#define HS_XCT_FILENAME                                 DEFAULT_HS_XCT_FILENAME
#define DEFAULT_HS_MAT_FILENAME                         "/cf/hs_mat.tbl"
#define HS_MAT_FILENAME                                 DEFAULT_HS_MAT_FILENAME
#define DEFAULT_HS_SYSTEM_MONITOR_DEVICE                "linux_sysmon"
#define HS_SYSTEM_MONITOR_DEVICE                        DEFAULT_HS_SYSTEM_MONITOR_DEVICE
#define DEFAULT_HS_SYSTEM_MONITOR_SUBSYSTEM_NAME        "aggregate"
#define HS_SYSTEM_MONITOR_SUBSYSTEM_NAME                DEFAULT_HS_SYSTEM_MONITOR_SUBSYSTEM_NAME
#define DEFAULT_HS_SYSTEM_MONITOR_SUBCHANNEL_NAME       "cpu-load"
#define HS_SYSTEM_MONITOR_SUBCHANNEL_NAME               DEFAULT_HS_SYSTEM_MONITOR_SUBCHANNEL_NAME
#define DEFAULT_HS_CPU_UTILIZATION_CYCLES_PER_INTERVAL  30
#define HS_CPU_UTILIZATION_CYCLES_PER_INTERVAL          DEFAULT_HS_CPU_UTILIZATION_CYCLES_PER_INTERVAL
#define DEFAULT_HS_CPU_UTILIZATION_MAX                  10000
#define HS_CPU_UTILIZATION_MAX                          DEFAULT_HS_CPU_UTILIZATION_MAX
#define DEFAULT_HS_UTIL_PER_INTERVAL_HOGGING            7500
#define HS_UTIL_PER_INTERVAL_HOGGING                    DEFAULT_HS_UTIL_PER_INTERVAL_HOGGING
#define DEFAULT_HS_UTIL_HOGGING_TIMEOUT                 5
#define HS_UTIL_HOGGING_TIMEOUT                         DEFAULT_HS_UTIL_HOGGING_TIMEOUT
#define DEFAULT_HS_UTIL_PEAK_NUM_INTERVAL               64
#define HS_UTIL_PEAK_NUM_INTERVAL                       DEFAULT_HS_UTIL_PEAK_NUM_INTERVAL
#define DEFAULT_HS_UTIL_AVERAGE_NUM_INTERVAL            4
#define HS_UTIL_AVERAGE_NUM_INTERVAL                    DEFAULT_HS_UTIL_AVERAGE_NUM_INTERVAL
#define DEFAULT_HS_MISSION_REV                          0
#define HS_MISSION_REV                                  DEFAULT_HS_MISSION_REV

// --- the four default monitor states. These are HS_State_* values, defined in hs_msg.HC.
#define DEFAULT_HS_APPMON_DEFAULT_STATE    HS_State_ENABLED
#define HS_APPMON_DEFAULT_STATE            DEFAULT_HS_APPMON_DEFAULT_STATE
#define DEFAULT_HS_EVENTMON_DEFAULT_STATE  HS_State_DISABLED
#define HS_EVENTMON_DEFAULT_STATE          DEFAULT_HS_EVENTMON_DEFAULT_STATE
#define DEFAULT_HS_ALIVENESS_DEFAULT_STATE HS_State_ENABLED
#define HS_ALIVENESS_DEFAULT_STATE         DEFAULT_HS_ALIVENESS_DEFAULT_STATE
#define DEFAULT_HS_CPUHOG_DEFAULT_STATE    HS_State_ENABLED
#define HS_CPUHOG_DEFAULT_STATE            DEFAULT_HS_CPUHOG_DEFAULT_STATE

// --- hs_version.h. HS_MISSION_REV is above, with the internal configuration, where NASA puts it.
#define HS_MAJOR_VERSION 7
#define HS_MINOR_VERSION 0
#define HS_REVISION      1

// --- hs_perfids.h. ONE performance id, bracketing the main loop.
#define HS_APPMAIN_PERF_ID 40

#endif
