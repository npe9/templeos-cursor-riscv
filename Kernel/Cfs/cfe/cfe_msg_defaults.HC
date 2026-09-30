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

// 1:1 HolyC translation of the constants in cFE modules/msg/fsw/src/cfe_msg_defaults.h.
//
// In the C these are "backwards compatibility" #ifndef defaults: cfe_mission_cfg.h and
// cfe_platform_cfg.h may define them, and this header supplies a value when they do not. A
// configured mission overrides them. Nothing here overrides anything, so the fallback values ARE
// the values, and they are written out plainly rather than wrapped in a conditional that could
// never fire.
//
// The two function declarations in that header (SetDefaultCCSDSPri, SetDefaultCCSDSExt) are
// translated with their definitions, in cfe_msg_ccsdspri.HC and cfe_msg_ccsdsext.HC.
#ifndef CFE_MSG_DEFAULTS_HC
#define CFE_MSG_DEFAULTS_HC
// Default APID, for bits not in MsgId
#define CFE_PLATFORM_DEFAULT_APID 0
// Default CCSDS Version. Zero, per CCSDS 133.0-B-2 section 4.1.3.2 -- version 1 of the CCSDS
// header is the bit pattern '000', so the "version" this code compares against is 0, not 1.
#define CFE_MISSION_CCSDSVER 0
// Default SubSystem, for bits not in MsgId
#define CFE_PLATFORM_DEFAULT_SUBSYS 0
// Default EDS version, cFS historically = 1
#define CFE_PLATFORM_EDSVER 1
#endif
