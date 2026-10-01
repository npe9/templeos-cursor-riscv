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

// 1:1 HolyC translation of cFE modules/config/fsw/src/cfe_config_objtab.c.
//
// CONFIG is a library-only module with no task, and its EarlyInit runs FIRST, before every
// other module's -- the registry has to exist before anything else in the startup sequence can
// read a configuration value. Target_ObjectTable comes from cfe_msg_objtab.HC and
// CFE_Config_Init from cfe_config_init.HC; include both first.
//
// The same single deviation as every other objtab here, and it is syntax only: the C uses a
// designated initializer, `{ .Name = "CFE_CONFIG", .EarlyInit = CFE_Config_Init }`, which
// zero-fills the rest. HolyC has no designated initializers, so the values are positional.
#ifndef CFE_CONFIG_OBJTAB_HC
#define CFE_CONFIG_OBJTAB_HC
// this is a core library module with no task, but it does have global data to initialize
Target_ObjectTable CFE_CONFIG_ModuleEntry = {"CFE_CONFIG", &CFE_Config_Init, NULL, NULL, 0, 0};
#endif
